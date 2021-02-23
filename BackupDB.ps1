cls
# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended")


$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection

$error.clear()

#get login credentials
$userName = "powershell"
$password =  get-content "E:\Powershell\Password.txt" | ConvertTo-SecureString
$Credentials = New-Object System.Management.Automation.PSCredential ($userName,$password)
$password = $Credentials.GetNetworkCredential().Password


#get threshold times
$MinTime = (get-date).AddMinutes(-15)
$MaxTime = (get-date).AddMinutes(15) 

$MinTime = get-date $MinTime -format T
$MaxTime = get-date $MaxTime -format T


# loop through all SQL Servers
$servers = Get-Content "E:\Powershell\Servers.txt"

foreach($server in $servers)
{	

	$srv_split = $server.split(",")	
	
	# get server name and IP
	$srv_name = $srv_split[0]
	
	$srv_ip = New-Object Microsoft.SqlServer.Management.Smo.Server ($srv_name)
	$srv_ip.ConnectionContext.NonPooledConnection = "True"
	$srv_ip.ConnectionContext.StatementTimeout = 0

	#check if server is up
	$PingStatus = Gwmi Win32_PingStatus -Filter "Address = '$srv_name'"|Select-Object StatusCode	
	if($PingStatus.StatusCode -eq 0)
	{	
		# login using SQL authentication, supplying the username and password
		$srv_ip.ConnectionContext.LoginSecure=$false;
		$srv_ip.ConnectionContext.set_Login($userName)
		$srv_ip.ConnectionContext.Password = $password

		#output server IP
		Write-Output "------- " $srv_name " -------"
	
	
		# get backup info
		$BackupDirectory = $srv_split[2]
		$FullBackupTime = $srv_split[3]
		$DiffBackupOffset = $srv_split[4]
		
		if ($BackupDirectory -eq $null -or $FullBackupTime -eq $null -or $DiffBackupOffset -eq $null)
		{
			continue
		}
				
				
		#determine what type of backup should take place based on current time		
		#default to log backup
		$BackupType = "Log"

		if ($FullBackupTime -gt $MinTime -and $FullBackupTime -lt $MaxTime)
		{
			$BackupType = "Full"
		}
		else
		{
			$CurrentDate = get-date -format d
			$DiffBackupDate = $CurrentDate
			$DiffBackupTime = $FullBackupTime

			while ($CurrentDate -eq $DiffBackupDate)
			{
				$DiffBackupTime = (get-date $DiffBackupTime).AddHours($DiffBackupOffset)
				$DiffBackupDate = get-date $DiffBackupTime -format d
				
				if ($DiffBackupTime -gt $MinTime -and $DiffBackupTime -lt $MaxTime)
				{
					$BackupType = "Diff"
				}
			}
		}
		
		
		# determine if instance supports compression
		$sqlConnection.ConnectionString = "Server=$srv_name;Database=master;User ID=$userName;Password=$password;"
		$sqlConnection.Open()
		$sqlCommand.Connection = $sqlConnection
		$sqlCommand.CommandTimeout = 0
						
						
		$sqlCommand.CommandText =
			"
            	DECLARE @ProductVersion DECIMAL(9,3)
			DECLARE @Edition VARCHAR(200)
			DECLARE @CompressionFlag BIT = 0


			SELECT @ProductVersion = LEFT(CAST(SERVERPROPERTY('productversion') AS VARCHAR(200)), CHARINDEX('.',CAST(SERVERPROPERTY('productversion') AS VARCHAR(200)), 4)-1)
			SELECT @Edition = CAST(SERVERPROPERTY('edition') AS VARCHAR(200))

			IF	(@Edition LIKE 'Enterprise%' AND @ProductVersion >= 10) OR
				(@Edition LIKE 'Developer%' AND @ProductVersion >= 10) OR
				(@Edition LIKE 'Standard%' AND @ProductVersion >= 10.5)
			SET @CompressionFlag = 1

			SELECT @CompressionFlag
			"
		
		$compression = $sqlCommand.ExecuteScalar()
		$sqlConnection.Close()
		
		
				
		# loop through all DBs on server and backup
		foreach($db in $srv_ip.Databases)
		{
			if($db.Status -like "Normal*" -and $db.Name -ne "tempdb")
			{
				$smoBackup = New-Object ('Microsoft.SqlServer.Management.Smo.Backup')
				$dbName = $db.Name
                $dbName_NoSpace = $dbName.Replace(" ","") 
                #remove spaces from DB name so future CMD tasks dont fail
				Write-Output $dbName
			
			
				# determine if a last_log_backup_lsn exists, if not, a full backup will occur
				$sqlConnection.ConnectionString = "Server=$srv_name;Database=$dbname;User ID=$userName;Password=$password;"
				$sqlConnection.Open()
				$sqlCommand.Connection = $sqlConnection
				$sqlCommand.CommandText = "SELECT ISNULL(a.last_log_backup_lsn, -1) FROM sys.database_recovery_status a INNER JOIN sys.databases b on a.database_id = b.database_id WHERE b.name = '" + $dbname + "'"
				
				$last_log_backup_lsn = $sqlCommand.ExecuteScalar()
				
											
				# set CompressionOption for the backups on the server				
				if ($compression -eq "1")
					{$smoBackup.CompressionOption = "1"}
				else
					{$smoBackup.CompressionOption = "0"}
					
				
				if ($BackupType -ne "Full" -and $db.RecoveryModel -eq "Simple")
				{
					$sqlConnection.Close()
					continue
				}
				
				
				# set backup type that will occur based on the time. if last_log_backup_lsn does not exist then run a full backup
				if ($BackupType -eq "Full" -or $last_log_backup_lsn -eq "-1")
				{
					$smoBackup.Action = "Database"
					$BackupType_ForFileName = "Full"
				}
				elseif ($BackupType -eq "Log")
				{
					$smoBackup.Action = "Log"
					$BackupType_ForFileName = "Log"
				}
				elseif ($BackupType -eq "Diff")
				{
					$smoBackup.Incremental = 1
					$BackupType_ForFileName = "Diff"
				}

				
				#set backup file name and path, database to backup and backup device type
				$timestamp = Get-Date -format yyyyMMddHHmmss
				$targetPath = $BackupDirectory + "\" + $dbName.Replace(" ", "") + "\" + $dbName_NoSpace + "_" + $BackupType_ForFileName + "_" + $timestamp + ".BAK"
								
				$smoBackup.Database = $dbName
				$smoBackup.Devices.AddDevice($targetPath, "File")
				
								
				# create a directory for the backup if it does not exist
				$sqlCommand.CommandText =
							"
							EXEC master.dbo.sp_configure 'show advanced options', 1
                            RECONFIGURE
                            EXEC master.dbo.sp_configure 'xp_cmdshell', 1
                            RECONFIGURE
					
                            DECLARE @cmd SYSNAME
                            SET @cmd = 'dir " + $targetPath + "'
							
                            DECLARE @Result INT


                     BEGIN TRY
	                        EXEC @result = master.dbo.xp_cmdshell @cmd, NO_OUTPUT;
							
                            IF @result <> 0
	                           BEGIN
	                           SELECT @cmd = 'mkdir " + $BackupDirectory + "\" + $dbName_NoSpace + "';

	                           EXEC master.dbo.xp_cmdshell @cmd, NO_OUTPUT;
                            END
							
	                           EXEC master.dbo.sp_Admin_Delete_Files_By_Date '" + $BackupDirectory + "\" + $dbName_NoSpace + "\','" + $dbName_NoSpace  + "*',1;
	                           GOTO ZeroFeatures   
                     END TRY

                BEGIN CATCH
                    GOTO ZeroFeatures
                END CATCH; 

                ZeroFeatures:
	               EXEC master.dbo.sp_configure 'xp_cmdshell', 0
	               RECONFIGURE
	               EXEC master.dbo.sp_configure 'show advanced options', 0
	               RECONFIGURE
							"
				$sqlCommand.ExecuteScalar()
				$sqlConnection.Close()

				
				# output backup details
				Write-Output $BackupType $db.RecoveryModel $compression $targetPath
				Write-Output $_`r
				
				
				# execute backup command
				$smoBackup.SqlBackup($srv_ip)
				
				#send error email
				Write-Output $error 
				if ($error -ne $null)
				{
					$command = "E:\Powershell\Release\SendEmail.ps1 –Subject ""$BackupType Backup Failed on $srv_name for $dbName"" -Body ""Backup path= $targetPath"""
					Invoke-Expression $command
				}
				
				$error.clear()			

			}
		}
	}
	$srv_ip.ConnectionContext.Disconnect()
}
