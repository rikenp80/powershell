cls
# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")

#get login credentials
$userName = "powershell"
$password =  get-content "E:\Powershell\Password.txt" | ConvertTo-SecureString
$Credentials = New-Object System.Management.Automation.PSCredential ($userName,$password)
$password = $Credentials.GetNetworkCredential().Password

# loop through all SQL Servers
$servers = Get-Content "E:\Powershell\Servers.txt" 

$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection

#set email body string to empty so it can be appended to
$body = ""


foreach($server in $servers)
{	
	# get server name and IP
	$srv_split = $server.split(",")
	
	$srv_name = $srv_split[1]
	Write-Host $srv_name
	
	$srv = New-Object Microsoft.SqlServer.Management.Smo.Server ($srv_name)
	$srv.ConnectionContext.NonPooledConnection = "True"

	#check if server is up
	$PingStatus = Gwmi Win32_PingStatus -Filter "Address = '$srv_name'"|Select-Object StatusCode

	if($PingStatus.StatusCode -eq 0)
	{
		# login using SQL authentication, supplying the username and password
		$srv.ConnectionContext.LoginSecure=$false;
		$srv.ConnectionContext.set_Login($userName)
		$srv.ConnectionContext.Password = $password
				
				
		foreach($db in $srv.Databases)
		{
			if($db.Status -like "Normal*")
			{
				[string]$dbname = $db
				
				# remove square brackets from db name
				$dbname = $dbname.Replace("[", "")
				$dbname = $dbname.Replace("]", "")
				Write-Host $dbname
				
				# connect to sql server
				$sqlConnection.ConnectionString = "Server=$srv_name;Database=$dbname;User ID=$userName;Password=$password;"
				$sqlConnection.Open()
				$sqlCommand.Connection = $sqlConnection
				$sqlCommand.CommandTimeout = 0
				
				
				# create execution script
				$sqlCommand.CommandText =
					"				
					IF NOT EXISTS (SELECT * FROM DBA_Logs.sys.tables WHERE name = 'DBCC_Output')
					BEGIN					
							CREATE TABLE DBA_Logs.dbo.DBCC_Output
								(
								Error int NULL,
								[Level] int NULL,
								[State] int NULL,
								MessageText varchar(1000) NULL,
								RepairLevel varchar(1000) NULL,
								[status] int NULL,
								[DbId] int NULL,
								DbFragId int NULL,
								ObjectId int NULL,
								IndexId int NULL,
								PartitionId bigint NULL,
								AllocUnitId bigint NULL,
								RidDbId int NULL,
								RidPruId int NULL,
								[File] int NULL,
								[Page] int NULL,
								Slot int NULL,
								RefDbId int NULL,
								RefPruId int NULL,
								RefFile int NULL,
								RefPage int NULL,
								RefSlot int NULL,
								Allocation int NULL,
								DateCreated DATETIME2(0) NULL
								)
											
						ALTER TABLE DBA_Logs.dbo.DBCC_Output ADD CONSTRAINT DF_DateCreated DEFAULT (GETDATE()) FOR DateCreated
					END



					DECLARE @SQL VARCHAR(8000)
					DECLARE @ProductVersion VARCHAR(50)
					SELECT @ProductVersion = CAST(SERVERPROPERTY('productversion') AS VARCHAR(50))
					SELECT @ProductVersion = LEFT(@ProductVersion, CHARINDEX('.',@ProductVersion)-1)
					
					SET @SQL = 'DBCC CHECKDB ([" + $dbname + "]) WITH TABLERESULTS, ALL_ERRORMSGS, NO_INFOMSGS, PHYSICAL_ONLY'


					IF @ProductVersion = 10
					BEGIN
						INSERT INTO DBA_Logs.dbo.DBCC_Output
							(
							Error,
							[Level],
							[State],
							MessageText,
							RepairLevel,
							[Status],
							[DbId],
							ObjectId,
							IndexId,
							PartitionId,
							AllocUnitId,
							[File],
							[Page],
							Slot,
							RefFile,
							RefPage,
							RefSlot,
							Allocation
							)
											
						EXEC(@SQL)
						SELECT @@ROWCOUNT
					END

					IF @ProductVersion = 11
					BEGIN
						INSERT INTO DBA_Logs.dbo.DBCC_Output
							(
							Error,
							[Level],
							[State],
							MessageText,
							RepairLevel,
							[status],
							[DbId],
							DbFragId,
							ObjectId,
							IndexId,
							PartitionId,
							AllocUnitId,
							RidDbId,
							RidPruId,
							[File],
							[Page],
							Slot,
							RefDbId,
							RefPruId,
							RefFile,
							RefPage,
							RefSlot,
							Allocation
							)
											
						EXEC(@SQL)
						SELECT @@ROWCOUNT
					END
					"
				
				# execute sql command
				$rowcount = $sqlCommand.ExecuteScalar()
				write-host $rowcount
				
				if($rowcount -ne 0)
				{
				$body = $body + $srv_name + " - " + $dbname + "`n`r"
				}
				
				$sqlConnection.Close()
			}
		}
	}
	
	$srv.ConnectionContext.Disconnect()
}



#send email of the contects of $body
if($body -ne "")
{
$body = $body + "`n`r" + "Check details in DBA_Logs.dbo.DBCC_Output"

$command = “E:\Powershell\Release\SendEmail.ps1 –Subject ""Database Integrity Error"" -Body ""$body"""
Invoke-Expression $command
}