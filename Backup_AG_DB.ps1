<#
Backup all database in the current environment. Does a Full and Diff backup on Primary AG server, Log backup on Seconday AG server.
Any servers that are not in an AG group will have all types of backups executed on them.

example execution:
H:\SSIS\Prod\Root\BatchFiles\BackupDB.ps1 -PSFilesPath "H:\SSIS\Prod\Root\BatchFiles" -AvailabilityGroupName "AG" -BackupType "Full" -DB_Exclude "SampleDB"
#>


param
(
  $PSFilesPath,
  $AvailabilityGroupName,
  $BackupType,      #Full, Diff or Log
  $DB_Include = "", #Specify which databases should be backed up
  $DB_Exclude = "",  #Specify which databases should not be backed up, all other databases will get backed up
  $Log_Diff_Retention_Days = 31, #retention period in days for log and diff backups
  $Full_Retention_Days = 365 #retention period for full backups in days
)


# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") | Out-Null


# Import the SQLPS module so that the Invoke-SQLCMD command works
Import-Module “sqlps” -DisableNameChecking

try
{
	$error.clear()
    cd $PSFilesPath
	
	#write run time to log file
	$date = get-date
	Write-Output $date.ToShortDateString() $date.ToShortTimeString()



    #split out DBs from variables into a list
    $DB_Include_Split = $DB_Include.split(",")
	$DB_Exclude_Split = $DB_Exclude.split(",")


    Write-Output "Backup Type = $BackupType"
    Write-Output "DB to Include = $DB_Include"
    Write-Output "DB to Exclude = $DB_Exclude"
   

    # Gets the list of active AG servers in the environment
    $ServersList = (.\GetServerList.ps1 | select-object -ExpandProperty ServerName)


    #determine primary AG server
    $PrimaryServer = (.\GetAlwaysOnServers.ps1 -ServerType Primary -AvailabilityGroupName $AvailabilityGroupName -ServersList $ServersList)
    $PrimaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($PrimaryServer)

	$SecondaryServer = @(.\GetAlwaysOnServers.ps1 -ServerType Secondary -AvailabilityGroupName $AvailabilityGroupName -ServersList $ServersList)



    #get servers that are not in AG group
    $ExclusionList = @($SecondaryServer) + @($PrimaryServer)
    $NonAGServers = $ServersList | where { $ExclusionList -notcontains $_ }

    
    

    #get the highest backup priority secondary server
	$secondary_backup_srv = (invoke-sqlcmd -ServerInstance $PrimaryServer_SQL -Database "master" -Query "
                            SELECT replica_server_name
                            FROM sys.availability_replicas a
	                            INNER JOIN sys.dm_hadr_availability_replica_states h ON a.replica_id = h.replica_id
                            WHERE h.[role] = 2
                            ORDER BY a.[backup_priority] DESC").replica_server_name

    
    #loop through the list 
    foreach($secondary_srv in $secondary_backup_srv)
    {
        $PingStatus = Gwmi Win32_PingStatus -Filter "Address = '$secondary_srv'"|Select-Object StatusCode	

        if($PingStatus.StatusCode -eq 0)
        {
           break
        }
    }


    Write-Output "Primary Server: $PrimaryServer"
    Write-Output "Secondary Server for Backups: $secondary_srv"
    Write-Output "Non AG Servers = $NonAGServers"




	# loop through all SQL Servers
	foreach($server_instance in $ServersList)
    {	
        Write-Output "`r`n####### $server_instance #######"


        #connect to sql server
        $Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($server_instance)
		$Server_SQL.ConnectionContext.StatementTimeout = 0       

        $Instance = (Invoke-Sqlcmd -ServerInstance $Server_SQL -database "master" -Query "SELECT CASE WHEN @@SERVICENAME = 'MSSQLSERVER' THEN '' ELSE @@SERVICENAME END").Column1


        #remove sql instance name from server name
        $Server = $server_instance.split("\")[0]


								
		# loop through all DBs on server and backup
		foreach($db in $Server_SQL.Databases)
        {
            $dbName = $db.Name                               
                                
                
            #do not backup the current DB if:
            #1. DB is tempdb
            #2. DB status is not normal
            #3. DB is a snapshot
            #4. the DB include list has values, and the current DB is not in the list
            #5. the DB exclude has the current DB in the list

			if  (
                $dbName -eq "tempdb" -or
                $db.Status -notlike "Normal*" -or
                $db.SnapshotIsolationState -eq "Enabled" -or
                $DB_Include_Split -ne "" -and $DB_Include_Split -contains $dbName -eq $false -or
                $DB_Exclude_Split -contains $dbName -eq $true
                )                   
				{continue}


            #check if the current DB is in an AG, if so, apply rules to determine if backup
            #should take place on a primary or secondary server
                
            $AvailabilityGroupName = $db.AvailabilityGroupName

            if  ($AvailabilityGroupName -eq "" -or #if not in AG then backup on all servers
                ($AvailabilityGroupName -ne "" -and
                ($BackupType -eq "Log" -and $secondary_srv -eq $server_instance) -or
                ($BackupType -ne "Log" -and $PrimaryServer -eq $server_instance))
                )
            {
       

                # if db recovery model is simple and backup type is not full then loop to next DB
                $dbRecoveryModel = $db.RecoveryModel                    

                write-output "`r`nDB: $dbName, Recovery: $dbRecoveryModel, AG_Name: $AvailabilityGroupName"
                                       
                if ($BackupType -eq "Log" -and $dbRecoveryModel -eq "Simple")
				{continue}

		    

			    # determine if a last_log_backup_lsn exists, if not, and the BackupType is not Full then ignore this DB
			    $last_log_backup_lsn = (invoke-sqlcmd -ServerInstance $Server_SQL -Database "master" -Query "
				    SELECT ISNULL(a.last_log_backup_lsn, -1) as LSN
				    FROM sys.database_recovery_status a 
					    INNER JOIN sys.databases b on a.database_id = b.database_id 
				    WHERE b.name = '$dbName'").LSN
				
                if ($last_log_backup_lsn -eq "-1" -and $BackupType -ne "Full")
				{continue}
									


                # set backup object
                $smoBackup = New-Object ('Microsoft.SqlServer.Management.Smo.Backup')

                
                # set backup type
				if ($BackupType -eq "Full")
				{
					$smoBackup.Action = "Database"
				}
				elseif ($BackupType -eq "Log")
				{
					$smoBackup.Action = "Log"
				}
				elseif ($BackupType -eq "Diff")
				{
					$smoBackup.Incremental = 1
				}



			    #set backup file name and path                
                $targetPath = $null

                $BackupDirectory = (.\GetServerList.ps1 | Where ServerName -eq $server_instance | select-object -ExpandProperty BackupPath)                                          

                $BackupDrive = $BackupDirectory.substring(0,2)

                                
                
                #check if the backup drive exists, if not then loop to next DB
                $script={param($BackupDrive); If (-not(Test-Path $BackupDrive)) {Write-Output "0"}}
                
                $BackupDriveExists = invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDrive
                                
                if ($BackupDriveExists -eq 0) {continue}
                


                #add instance name to backup path if it is a names sql instance
                if ($Instance -ne "") {$BackupDirectory += "\" + $Instance}
                


                #get current date and time    
                $timestamp = Get-Date -format yyyyMMddHHmmss
                   
                                    

                #set backup file path based on the type of backup
                if ($BackupType -eq "Full")
                {
                    $BackupDirectory += "\Data\" + $dbName
				    $targetPath = $BackupDirectory + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".BAK"
			    }

			    elseif ($BackupType -eq "Diff")
                {
                    $BackupDirectory += "\Diff\" + $dbName
				    $targetPath = $BackupDirectory  + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".BAK"
			    }

			    elseif ($BackupType -eq "Log")
                {
                    $BackupDirectory += "\Log\" + $dbName
				    $targetPath = $BackupDirectory  + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".TRN"
			    }


                write-output $targetPath
				


			    #create backup directory
                $script={param($BackupDirectory); New-Item -ItemType Directory -Force -Path $BackupDirectory}
                invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDirectory | out-null

                    

                # set backup options and execute backup command
                $smoBackup.Database = $dbName
				$smoBackup.Devices.AddDevice($targetPath, "File")
                $smoBackup.CompressionOption = "1"

			    $smoBackup.SqlBackup($Server_SQL)



                # Set at what age backups are deleted and delete if they have passed the retention period
	            $month_retention_date = (Get-Date).AddDays(-$Log_Diff_Retention_Days)                        

                if ($BackupType -ne "Full")
                {   
                    # for log and diff backups                                                        
                    $script={param($BackupDirectory,$month_retention_date); Get-ChildItem -Path $BackupDirectory -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $month_retention_date } | Remove-Item -Force}

                    #Delete backup files older than the $limit set above for log and diff backups
                    invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDirectory,$month_retention_date | out-null
                        
                }
                else
                {   
                    # for full backups
                    $year_retention_date = (Get-Date).AddDays(-$Full_Retention_Days)

                    $script={param($BackupDirectory,$year_retention_date); Get-ChildItem -Path $BackupDirectory -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $year_retention_date } | Remove-Item -Force}

                    #Delete backup files older than the $limit set above.
                    invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDirectory,$year_retention_date | out-null


                    #set values for the first month on which only 1 full backup should be kept
                    $date_month = $year_retention_date.Month
                    $date_year = $year_retention_date.Year
                        
                       
                    #loop through each month to delete all but the last full backup of that month
                    while ($year_retention_date -lt $month_retention_date)                            
                    {

                        #when the month being processed in the current loop matches the month of the monthly retention date, stop processing
                        #this ensures that previous months full backups are kept
                        if ($month_retention_date.Year -eq $date_year -and $month_retention_date.Month -eq $date_month)
                        {
                            write-output "Latest Month of Full Backups deleted: $date_month $date_year"
                            break
                        }                            
                                                   

                        $script={param($BackupDirectory,$date_month,$date_year);
                                $KeepBackupName = (Get-ChildItem -Path $BackupDirectory | Where-Object {$_.LastWriteTime.month -eq $date_month -and $_.LastWriteTime.year -eq $date_year} | sort LastWriteTime | select -last 1 name).name
                                Get-ChildItem -Path $BackupDirectory -Recurse -Force | Where-Object {!$_.PSIsContainer -and $_.Name -ne $KeepBackupName -and $_.LastWriteTime.month -eq $date_month -and $_.LastWriteTime.year -eq $date_year} | Remove-Item -Force
                                }

                        invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDirectory,$date_month,$date_year | out-null

                            
                        $year_retention_date = $year_retention_date.AddMonths(1)
                        $date_month = $year_retention_date.Month
                        $date_year = $year_retention_date.Year

                    }
                }
            }
    	}
	}
}



catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""$BackupType Backup Failed on $server_instance for $dbName"" -Body ""Backup path= $targetPath"""
		Invoke-Expression $command
	}
	$error.clear()
}