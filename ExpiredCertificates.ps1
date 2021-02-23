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


#loop through each server and get expired certificates
foreach($server in $servers)
{	
	# get server name and IP
	$srv_split = $server.split(",")
	
	$srv_name = $srv_split[1]

	
	$srv = New-Object Microsoft.SqlServer.Management.Smo.Server ($srv_name)
	$srv.ConnectionContext.NonPooledConnection = "True"

	#check if server is up
	$PingStatus = Gwmi Win32_PingStatus -Filter "Address = '$srv_name'"|Select-Object StatusCode

	if($PingStatus.StatusCode -eq 0)
	{
		#login using SQL authentication, supplying the username and password
		$srv.ConnectionContext.LoginSecure=$false;
		$srv.ConnectionContext.set_Login($userName)
		$srv.ConnectionContext.Password = $password
			

		#loop through each DB on each server
		foreach($db in $srv.Databases)
		{
			if($db.Status -like "Normal*")
			{
				[string]$dbname = $db
				
				# remove square brackets from db name
				$dbname = $dbname.Replace("[", "")
				$dbname = $dbname.Replace("]", "")

				# connect to current DB
				$sqlConnection.ConnectionString = "Server=$srv_name;Database=$dbname;User ID=$userName;Password=$password;"
				$sqlConnection.Open()
				$sqlCommand.Connection = $sqlConnection
				$sqlCommand.CommandTimeout = 0

				# populate dataset with expired certificate data
				$ds = new-object "System.Data.DataSet" "ExpiredCert"
				$query = "SELECT name 'CertName', @@servername 'ServerName', '" + $dbname + "' AS 'DBName' FROM sys.certificates WHERE [expiry_date] < GETDATE() AND name NOT LIKE '##%'"

				$da = new-object "System.Data.SqlClient.SqlDataAdapter" ($query, $sqlConnection)
				$da.Fill($ds) | out-null

				# create data table from data set
				$dt = new-object System.Data.DataTable "ExpiredCert"
				$dt = $ds.Tables[0]

				# create data table from data set
				foreach ($Row in $dt.Rows)
				{
					#set value of variable from table
					$ServerName = $Row.ServerName
					$CertName = $Row.CertName
					$DBName = $Row.DBName
					
					#add row data to $body for emailing
					$body = $body + $ServerName + " - " + $DBName + " - " + $CertName +  "`n`r"
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
	$command = “E:\Powershell\Release\SendEmail.ps1 –Subject ""Expired Certificates"" -Body ""$body"""
	Invoke-Expression $command
}
