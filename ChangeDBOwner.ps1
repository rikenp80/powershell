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


foreach($server in $servers)
{	
	# get server name and IP
	$srv_split = $server.split(",")
	
	$srv_name = $srv_split[0]
	
	
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

		#change db owner to sa for each db that is not already sa and is online and is not system db
		$sa = $srv.Logins["sa"]
		foreach($db in $srv.Databases)
		{
			if((!$db.IsSystemObject) -and ($db.Status -like "Normal*") -and ($db.Owner -ne "sa"))
			{
				Write-Host $srv $db.Name $db.Status $db.Owner
				$db.SetOwner($sa.Name)
			}
		}
	}
	
	$srv.ConnectionContext.Disconnect()
}
