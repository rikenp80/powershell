<#
Backup all database in the current environment

example execution
C:\Powershell\BackupDBs.ps1 -ServersList "mtrdata1" -Retention_Days 7 -Min_Full_Diff_Time_Gap 12 -BackupType "Full" -DB_Include "subaccount" -BackupDirectory "I:\Backups"
#>


param
(
  $ServersList,              #Specify which servers should be backed up
  $BackupType,              #Full, Diff or Log
  $DB_Include = "",         #Specify which databases should be backed up
  $DB_Exclude = "",         #Specify which databases should not be backed up, all other databases will get backed up
  $Retention_Days = 60,      #retention period for backups in days
# $Retention_Days_Diff = 7,     #retention period for Differential and log backups in days
  $Min_Full_Diff_Time_Gap = 0,   #minimum number of hours between full and diff backup
  $BackupDirectory = ""        #Location where backups should go to. A folder will be created for each database in the $BackupDirectory.
)


# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") | Out-Null


if ($PSVersionTable.PSVersion.Major -le 2)
{
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
    
    
    if ( (Get-PSSnapin -Name SqlServerCmdletSnapin100 -ErrorAction SilentlyContinue) -eq $null )
    {
        Add-PsSnapin SqlServerCmdletSnapin100
    }
    
    if ( (Get-PSSnapin -Name SqlServerProviderSnapin100 -ErrorAction SilentlyContinue) -eq $null )
    {
        Add-PsSnapin SqlServerProviderSnapin100
    }
}
else
{
    # Import the SQLPS module so that the Invoke-SQLCMD command works
    Import-Module “sqlps” -DisableNameChecking
}


try
{    

	#output date
	Write-Output ("=======" + (get-date -format "yyyy-MM-dd HH:mm:ss") + "=======")


    #replace spaces between DB names and split out DBs from variables into a list
    $DB_Include = $DB_Include -replace ", ","," -replace " ,",","
    $DB_Exclude = $DB_Exclude -replace ", ","," -replace " ,",","
    
    $DB_Include_Split = $DB_Include.split(",")
	$DB_Exclude_Split = $DB_Exclude.split(",")



    # Gets the list of servers from DB table if the parameter is not specified
    if ($ServersList -eq "")
    {
        $ServersList = (&(Join-Path $PSScriptRoot 'GetServerList.ps1') | select-object -ExpandProperty ServerName)
    }
    
    
	# loop through all SQL Servers
	foreach($server_instance in $ServersList)
    {	
  
        Write-Output "`r`n#### $server_instance ####"

        #remove sql instance name from server name
        $Server = $server_instance.split("\")[0]

        #connect to sql server
        $Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($ServersList)
        $Server_SQL.ConnectionContext.StatementTimeout = 0

        #get SQL instance name
        $Instance = (Invoke-Sqlcmd -ServerInstance $server_instance -database "master" -Query "SELECT CASE WHEN @@SERVICENAME = 'MSSQLSERVER' THEN '' ELSE @@SERVICENAME END").Column1

   	      	

		# loop through all DBs on server and backup
		foreach($db in $Server_SQL.Databases)
        {
            $dbName = $db.Name
            $LastFullBackupDate = $db.LastBackupDate                            
                          
                
            #do not backup the current DB if:
            #1. DB is tempdb
            #2. DB is master and backup type is differential
            #3. DB status is not normal
            #4. the DB include list has values, and the current DB is not in the list
            #5. the DB exclude has the current DB in the list


			if  (
                    $dbName -eq "tempdb" -or
                    ($dbName -eq "master" -and $BackupType -eq "Diff") -or
                    $db.Status -notlike "Normal*" -or
                    ($DB_Include_Split -ne "" -and $DB_Include_Split -contains $dbName -eq $false) -or
                    $DB_Exclude_Split -contains $dbName -eq $true
                )                   
				{continue}
       

            # if db recovery model is simple and backup type is not full then loop to next DB                  
            if ($BackupType -eq "Log" -and $db.RecoveryModel -like "*Simple*")
                {continue}


            # determine if a backup has previously occured, if not, and the BackupType is not Full then ignore this DB
            if ($LastFullBackupDate -eq "Monday, January 01, 0001 12:00:00 AM" -and $BackupType -ne "Full")
                {continue}
            

            # skip the diff backup if a full backup has been taken more recently than allowed by $Min_Full_Diff_Time_Gap parameter
            if ($BackupType -eq "Diff" -and $LastFullBackupDate -gt (get-date).addhours(-$Min_Full_Diff_Time_Gap))
                {continue}
            
            # skip backup if a Full or Diff backup is already running
            $DB_BackupRunning = $Server_SQL.EnumProcesses() | where-object {$_.Command -eq "BACKUP DATABASE"} | Select Database -ExpandProperty Database
            
            if ($DB_BackupRunning -contains $dbName -eq $true -and $BackupType -ne "Log")
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


            # if $BackupDirectory has not been definied in the parameters then get the backup location from the dbmanagement database
            if ($BackupDirectory -eq "")
            {
                $BackupDirectory = (&(Join-Path $PSScriptRoot 'GetServerList.ps1') | Where {$_.ServerName -eq $server_instance}).BackupPath
            }

            $BackupDrive = $BackupDirectory.substring(0,2)



            #check if the backup drive exists, if not then loop to next DB
            $script={param($BackupDrive); If (-not(Test-Path $BackupDrive)) {Write-Output "0"}}
            
            $BackupDriveExists = invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDrive
                            
            if ($BackupDriveExists -eq 0) {continue}

       

            #add instance name to backup path if it is a named sql instance
            if ($Instance -ne "") {$BackupDirectory += "\" + $Instance}
         

            
            #set backup file path based on the type of backup
            $BackupDirectory_DB = $BackupDirectory + "\" + $dbName
            
            $timestamp = Get-Date -format yyyy_MM_dd_HHmmss
            

            if ($BackupType -eq "Log")
            {
                $targetPath = $BackupDirectory_DB  + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".TRN"
            }
            else
            {
                $targetPath = $BackupDirectory_DB  + "\" + $dbName + "_" + $BackupType + "_" + $timestamp + ".BAK"
            }
            
            

            #create backup directory
            $script={param($BackupDirectory_DB); New-Item -ItemType Directory -Force -Path $BackupDirectory_DB}
            invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDirectory_DB | out-null


            # set backup options and execute backup command
            $smoBackup.Database = $dbName
            $smoBackup.Devices.AddDevice($targetPath, "File")
            $smoBackup.CompressionOption = "1"


            write-output "`r`nBacking Up DB: $dbName"
            write-output "Path: $targetPath"
            write-output ("Recovery: " + $db.RecoveryModel)
            
            
            #log start time for backup
            $BackupStartTime = get-date -format G
            
            #perform backup
            $smoBackup.SqlBackup($Server_SQL)
            
            #log end time for backup and output backup duration
            $BackupEndTime = get-date -format G
            $BackupDuration = [math]::round((new-timespan $BackupStartTime $BackupEndTime).TotalMinutes)
            write-output ("Backup Duration (Minutes): $BackupDuration `r`n")

            

            # delete old backup files
            [datetime]$Retention_Date = Get-Date -format "dd-MMM-yyyy"
            
            $Retention_Date = $Retention_Date.AddDays(-$Retention_Days)
      
            $script={param($BackupDirectory_DB,$Retention_Date); Get-ChildItem -Path $BackupDirectory_DB -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Retention_Date } | Remove-Item -Force}
        
            #Delete backup files older than $Retention_Date
            invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDirectory_DB,$Retention_Date

<#          
             # delete old backup files (Diff, Log)
            [datetime]$Retention_Date = Get-Date -format d
            $Retention_Date = $Retention_Date.AddDays(-$Retention_Days_Diff)

            $script={param($BackupDirectory_DB,$Retention_Date); Get-ChildItem -Path $BackupDirectory_DB -include *_Diff_*.BAK,*_Log_*.trn -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Retention_Date } | Remove-Item -Force}

            #Delete backup files older than $Retention_Date
            invoke-command -computername $Server -scriptblock $script -ArgumentList $BackupDirectory_DB,$Retention_Date | out-null   
#>
      
        }
	}
}



catch
{
    Write-Error $_

    [System.Environment]::Exit(1)
}

