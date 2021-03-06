<#
Backup all database in the current environment. Does a Full and Diff backup on Primary AG server, Log backup on Seconday AG server.
Any servers that are not in an AG group will have all types of backups executed on them.

example execution:
H:\SSIS\Prod\Root\BatchFiles\BackupDB.ps1 -PSFilesPath "H:\SSIS\Prod\Root\BatchFiles" -AvailabilityGroupName "LiveHubs" -BackupType "Full" -DB_Exclude "UnifiedJobs,TotalCV"
C:\Powershell\BackupDBs.ps1 -PSFilesPath "C:\Powershell" -BackupType "Diff"
#>


param
(
  $PSFilesPath,
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


$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection


$error.clear()



# loop through all SQL Servers
$server_list = Get-Content "C:\Powershell\Servers.txt"

foreach($server in $server_list)
    {	
		$server_split = $server.split(",")
		
		# get server and instance name
		$server_and_instance = $server_split[0]
		$server_name = $server_and_instance.split("\")[0]
        $Instance = $server_and_instance.split("\")[1]
		
		# get backup path
		$BackupDirectory = $server_split[1]
		
        

        #connect to sql server
        $Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($server_and_instance)
		$Server_SQL.ConnectionContext.StatementTimeout = 0    
        
		        
write-output "`r`nserver_and_instance: $server_and_instance, BackupDirectory: $BackupDirectory, server_name: $server_name, Instance: $Instance"
        
        

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
                $db.IsDatabaseSnapshot -eq $True
                #$DB_Include_Split -ne "" -and $DB_Include_Split -contains $dbName -eq $false -or
                #$DB_Exclude_Split -contains $dbName -eq $true
                )                   
				{continue}
                
            
            # if db recovery model is simple and backup type is not full then loop to next DB
            $dbRecoveryModel = $db.RecoveryModel                      
write-output "`r`nDB: $dbName, Recovery: $dbRecoveryModel"
                                       
            if ($BackupType -eq "Log" -and $dbRecoveryModel -eq "Simple")
            {continue}
            
                
                
			# if no previous backup has occure then do not run a Log or Diff backup
		    $last_full_backup_year = $db.LastBackupDate.year
            
            if ($last_full_backup_year -eq "1" -and $BackupType -ne "Full")
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
            

            
  						
			#check if the backup drive exists, if not then loop to next DB
            $BackupDrive = $BackupDirectory.substring(0,2)
            
			$script={param($BackupDrive); If (-not(Test-Path $BackupDrive)) {Write-Output "0"}}

			$BackupDriveExists = invoke-command -computername $server_name -scriptblock $script -ArgumentList $BackupDrive
     
			if ($BackupDriveExists -eq 0) {continue}
            
            

			#add instance name to backup path if it is a names sql instance
			if ($Instance -ne "") {$DB_BackupDirectory = $BackupDirectory + "\" + $Instance + "\"}
			
			$DB_BackupDirectory += $dbName
		 
			#get current date and time    
			$timestamp = Get-Date -format yyyyMMddHHmmss
			   
								

            #set backup file name and path                
            $targetPath = $null
                
			#set backup file path based on the type of backup            
			if ($BackupType -eq "Full")
			{
				$targetPath = $DB_BackupDirectory + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".BAK"
			}

			elseif ($BackupType -eq "Diff")
			{
				$targetPath = $DB_BackupDirectory  + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".BAK"
			}

			elseif ($BackupType -eq "Log")
			{
				$targetPath = $DB_BackupDirectory  + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".TRN"
			}

            
            
write-output $targetPath             


			#create backup directory
			$script={param($DB_BackupDirectory); New-Item -ItemType Directory -Force -Path $DB_BackupDirectory}
			invoke-command -computername $server_name -scriptblock $script -ArgumentList $DB_BackupDirectory | out-null

				

			# set backup options and execute backup command
			$smoBackup.Database = $dbName
			$smoBackup.Devices.AddDevice($targetPath, "File")
			$smoBackup.CompressionOption = "1"

			$smoBackup.SqlBackup($Server_SQL)
							
            
        }
      }
      