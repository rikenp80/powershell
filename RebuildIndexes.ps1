param
(
  [string]$include_list,
  [string]$exclude_list
)

# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended")


try
{	
	$error.clear()
	
	#write run time to log file
	$date = get-date
	Write-Output $date.ToShortDateString() $date.ToShortTimeString()
	
	
	#set sql connection objects
	$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
	$sqlConnection = New-Object System.Data.SqlClient.SqlConnection

	
	#split $include_list and $exclude_list into array
	if ($include_list -ne "") {$include_array = @($include_list -split ",")}
	if ($exclude_list -ne "") {$exclude_array = @($exclude_list -split ",")}


	#get login credentials
	$userName = "powershell"
	$password =  get-content "E:\Powershell\Password.txt" | ConvertTo-SecureString
	$Credentials = New-Object System.Management.Automation.PSCredential ($userName,$password)
	$password = $Credentials.GetNetworkCredential().Password


	# loop through all SQL Servers
	$servers = Get-Content "E:\Powershell\Servers.txt"

	foreach($server in $servers)
	{
		$srv_split = $server.split(",")	
		
		# get server name and IP
		$srv_name = $srv_split[0]
		
		$srv_ip = New-Object Microsoft.SqlServer.Management.Smo.Server ($srv_name)
		$srv_ip.ConnectionContext.NonPooledConnection = "True"

		#check if server is up
		$PingStatus = Gwmi Win32_PingStatus -Filter "Address = '$srv_name'"|Select-Object StatusCode	
		if($PingStatus.StatusCode -eq 0)
		{	
			# login using SQL authentication, supplying the username and password
			$srv_ip.ConnectionContext.LoginSecure=$false;
			$srv_ip.ConnectionContext.set_Login($userName)
			$srv_ip.ConnectionContext.Password = $password

			#output server IP
			Write-Output "----------------------" $srv_name "----------------------"
			
			
			# determine if instance supports online index rebuild
			$sqlConnection.ConnectionString = "Server=$srv_name;Database=master;User ID=$userName;Password=$password;"
			$sqlConnection.Open()
			$sqlCommand.Connection = $sqlConnection
			$sqlCommand.CommandTimeout = 0

			$sqlCommand.CommandText =
				"
				DECLARE @ProductVersion DECIMAL(9,3)
				DECLARE @Edition VARCHAR(200)
				DECLARE @OnlineFlag BIT = 0


				SELECT @ProductVersion = LEFT(CAST(SERVERPROPERTY('productversion') AS VARCHAR(200)), CHARINDEX('.',CAST(SERVERPROPERTY('productversion') AS VARCHAR(200)), 4)-1)
				SELECT @Edition = CAST(SERVERPROPERTY('edition') AS VARCHAR(200))

				IF	(@Edition LIKE 'Enterprise%' AND @ProductVersion >= 9) OR
					(@Edition LIKE 'Developer%' AND @ProductVersion >= 9)
				SET @OnlineFlag = 1

				SELECT @OnlineFlag
				"
			
			$online_flag = $sqlCommand.ExecuteScalar()
			$sqlConnection.Close()
						

			# loop through all DBs on server
			foreach($db in $srv_ip.Databases)
			{
				$dbName = $db.Name
				$dbid = [string]$db.ID
				Write-Output $dbName 

				
				#go through $include_array and $exclude_array to determine if the database should be processed
				$include_db = $null
				$exclude_db = $null			
				
				#determine if current DB matches an entry in $include_array. if array is empty (null) allow DB to be processed, this means all DBs will be processed
				if ($include_array -eq $null)
					{
					#set to true so DB is included
					$include_db = $True
					}
				else
					{
						foreach ($db_like in $include_array)
						{
						if($dbName -like $db_like)
							{
							#set to true so DB is included
							$include_db = $True
							break
							}
						else
							{
							#set to false so DB is not included
							$include_db = $False
							}
						}
					}
					
				
				#determine if current DB matches an entry in $exclude_array. if array is empty (null) allow DB to be processed, this means all DBs will be processed
				if ($exclude_array -eq $null)
					{
					#set to false so DB is included
					$exclude_db = $False
					}
				else
					{
					foreach ($db_like in $exclude_array)
					{
						if($dbName -like $db_like)
							{
							#set to true so DB is not included
							$exclude_db = $True
							break
							}
						else
							{
							#set to false so DB is included
							$exclude_db = $False
							}
						}
					}										


				
				if	($db.Status -like "Normal*" -and $db.IsSystemObject -ne $True -and $include_db -eq $True -and $exclude_db -eq $False)
					
				{						
					$sqlConnection.ConnectionString = "Server=$srv_name;Database=$dbName;User ID=$userName;Password=$password;"
					$sqlConnection.Open()
					$sqlCommand.Connection = $sqlConnection
					$sqlCommand.CommandTimeout = 0
			
			
					#get all tables in the DB
					$tbs = $db.Tables
					
					foreach($tb in $tbs)
					{
						$tbName = $tb.Name
						$tbid = $tb.ID		
						

						# populate dataset with Fragmentation and page count information for each index in the currrent table
						$ds = new-object "System.Data.DataSet" "IndexData"
						$query =
								"
								SELECT d.avg_fragmentation_in_percent, d.page_count, si.rowmodctr AS rows_changed, si.name
								FROM sys.dm_db_index_physical_stats($dbid, $tbid, NULL, NULL, 'LIMITED') d
									INNER JOIN sys.sysindexes si ON d.[object_id] = si.ID AND d.INDEX_ID = si.INDID
									INNER JOIN sys.tables t ON t.[object_id] = d.[object_id] AND t.[schema_id] = 1
								"

						$da = new-object "System.Data.SqlClient.SqlDataAdapter" ($query, $sqlConnection)
						$da.Fill($ds) | out-null
						
						
						# create data table from data set
						$dt = new-object System.Data.DataTable "Fragmentation"
						$dt = $ds.Tables[0]
						
						
						# loop through each index in the table
						foreach ($index in $dt.Rows)
						{
							#set value of variables from table
							$avg_frag = $index.avg_fragmentation_in_percent
							$page_count = $index.page_count
							$rows_changed = $index.rows_changed
							$ixname = $srv_ip.databases[$dbName].Tables[$tbName].Indexes[$index.name]							

							#Write-Output "$($srv_ip); $($dbName); $($tbname); $($index.name)"						


							# determine if index should be rebuilt, reorganized or neither
							if ($avg_frag -gt 30 -and $page_count -gt 1000 -and $rows_changed -gt 0 -and $ixname -ne $null)
							{
								# Rebuild the index if fragmentation over 30 percent
								Write-Output "REBUILD: $($dbname); $($tbname); $($index.name)"
								$ixname.Rebuild()											
							}
								elseif ($avg_frag -gt 5 -and $page_count -gt 1000 -and $rows_changed -gt 0 -and $ixname -ne $null)
							{
								# Reorg the index if fragmentation over 10 percent
								Write-Output "REORGANIZE: $($dbname); $($tbname); $($index.name)"
								$ixname.Reorganize()
								
								# A reorg doesn't update statistics, so do it manually
								$ixname.UpdateStatistics()
							}
						}
					}
					$sqlConnection.Close()					
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
		$command = "E:\Powershell\Release\SendEmail.ps1 –Subject ""Rebuild Index Failed on $srv_name, $dbName, $tbName, $ixName"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}
