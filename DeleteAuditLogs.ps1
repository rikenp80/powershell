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
$dbname = "DBA_Logs"

#get windows login credentials
$windows_username = "PTGSTAGING\SQLMonitor"
$windows_password =  get-content "E:\Powershell\WindowsPassword.txt" | ConvertTo-SecureString
$windows_credentials = New-Object System.Management.Automation.PSCredential ($windows_username,$windows_password)
$windows_password = $windows_credentials.GetNetworkCredential().Password


# loop through all SQL Servers
$servers = Get-Content "E:\Powershell\Servers.txt" 

$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection

foreach($server in $servers)
{	
	# get server name and IP
	$srv_split = $server.split(",")
	
	$srv_ip = $srv_split[0]
	$srv_name = $srv_split[1]
	
	$srv = New-Object Microsoft.SqlServer.Management.Smo.Server ($srv_ip)
	$srv.ConnectionContext.NonPooledConnection = "True"
	
	
	#check if server is up
	$PingStatus = Gwmi Win32_PingStatus -Filter "Address = '$srv_ip'"|Select-Object StatusCode

	
	if($PingStatus.StatusCode -eq 0)
	{

		# login using SQL authentication, supplying the username and password
		$srv.ConnectionContext.LoginSecure=$false;
		$srv.ConnectionContext.set_Login($userName)
		$srv.ConnectionContext.Password = $password
		
		#output server ip
		Write-Host $srv
	
	
		# connect to DB
		$sqlConnection.ConnectionString = "Server=$srv_ip;Database=$dbname;User ID=$userName;Password=$password;"
		$sqlConnection.Open()
		$sqlCommand.Connection = $sqlConnection
		$sqlCommand.CommandTimeout = 600

					
		# Get Audit File Path
		$sqlCommand.CommandText = "IF EXISTS (SELECT * FROM sys.tables WHERE name = 'AuditFile') SELECT TOP 1 LEFT([file_name], LEN([file_name]) - PATINDEX('%\%', REVERSE([file_name]))) FROM AuditFile WITH(NOLOCK)"
		$AuditFilePath = $sqlCommand.ExecuteScalar()
		
		#go to next server if no audit file path exists
		if ($AuditFilePath -eq $null)
			{
			$sqlConnection.Close()
			continue
			}
		
		$AuditFilePath = $AuditFilePath + "\*.sqlaudit"
		
		
		
		# populate dataset with audit files used in AuditFile table
		$ds_AuditFiles = new-object "System.Data.DataSet" "AuditFiles"
		$qry_DistinctAuditFiles = "IF EXISTS (SELECT * FROM sys.tables WHERE name = 'AuditFile') SELECT DISTINCT [file_name] FROM AuditFile WITH(NOLOCK)"

		$da_AuditFiles = new-object "System.Data.SqlClient.SqlDataAdapter" ($qry_DistinctAuditFiles, $sqlConnection)
		
		$da_AuditFiles.Fill($ds_AuditFiles) | out-null
		
		
		# create data table from data set
		$dt_AuditFiles = new-object System.Data.DataTable "AuditFiles"
		$dt_AuditFiles = $ds_AuditFiles.Tables[0]

		$ar_AuditFiles = @()
		
		
		# create data table from data set
		foreach ($Row in $dt_AuditFiles.Rows)
		{
			$ar_AuditFiles = $ar_AuditFiles + $Row.file_name.trimend()
		}
		
		$sqlConnection.Close()

		
		
		# Get list of files from the Audit File Path location
		$newsession = New-PSSession -computername $srv_name -credential $windows_credentials
			
		$FolderFileName = Invoke-Command -Session $newsession -ScriptBlock {param($AuditFilePath=$AuditFilePath) Get-ChildItem $AuditFilePath | Select-Object FullName} -ArgumentList $AuditFilePath | select FullName
		
		
		# put files from directory into array
		$FilesDirectory = @()
		
		foreach ($i in $FolderFileName)
		{			
			$x = [string]$i		
			$x = $x.Replace("@{FullName=", "")
			$x = $x.Replace("}", "")
			
			$FilesDirectory = $FilesDirectory + $x
		}

		
		# compare the two arrays to determine which files can be deleted
		$compare = compare-object ($ar_AuditFiles) ($FilesDirectory)

		
		# loop through records from comparison 
		foreach ($c in $compare)
		{	
			# if records exists in database but not in directory then do nothing	
			if ($c -like "*<=*")
			{
				continue
			}
			
			# remove extra characters from file string
			$File = [string]$c			
			$File = $File.Replace("@{InputObject=", "")
			$File = $File.Replace("; SideIndicator==>}", "")
			
			# delete file
			Write-Host $File
			Invoke-Command -Session $newsession -ScriptBlock {param($File=$File) Remove-Item -path $File} -ArgumentList $File
		}
		
		Remove-PSSession $newsession
	}
	
	$srv.ConnectionContext.Disconnect()
}
