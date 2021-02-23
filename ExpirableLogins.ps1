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
$dbname = "master"


# loop through all SQL Servers
$servers = Get-Content "E:\Powershell\Servers.txt"

$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection


#set email body string to empty so it can be appended to
$body = ""


#loop through each server and get expired certificates
foreach($server in $servers)
{	
	$srv_split = $server.split(",")
	
	$srv_ip = $srv_split[0]
	
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
			

		# connect to DB
		$sqlConnection.ConnectionString = "Server=$srv_ip;Database=$dbname;User ID=$userName;Password=$password;"
		$sqlConnection.Open()
		$sqlCommand.Connection = $sqlConnection
		$sqlCommand.CommandTimeout = 600

		# populate dataset with expired certificate data
		$ds = new-object "System.Data.DataSet" "ExpirableLogins"
		$query = "SELECT name 'LoginName', @@servername 'ServerName' FROM sys.sql_logins WHERE is_expiration_checked = 1 AND modify_date > CAST(GETDATE()-1 AS DATE) ORDER BY name"

		$da = new-object "System.Data.SqlClient.SqlDataAdapter" ($query, $sqlConnection)
		$da.Fill($ds) | out-null

		# create data table from data set
		$dt = new-object System.Data.DataTable "ExpirableLogins"
		$dt = $ds.Tables[0]
		
		# create data table from data set
		foreach ($Row in $dt.Rows)
		{
			#set value of variable from table
			$ServerName = $Row.ServerName
			$LoginName = $Row.LoginName
			
			#add row data to $body for emailing
			$body = $body + $ServerName + " - " + $LoginName +  "`n`r"
		}

		$sqlConnection.Close()
	}

	$srv.ConnectionContext.Disconnect()
}

#send email of the contects of $body
if($body -ne "")
{
	$command = “E:\Powershell\Release\SendEmail.ps1 –Subject ""Expirable Logins"" -Body ""$body"""
	Invoke-Expression $command
}
