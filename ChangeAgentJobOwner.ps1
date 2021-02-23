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
		
		#output server IP
		Write-Host $srv
		
		#get all jobs on the server
		$jobs = $srv.JobServer.Jobs

		
		#change job owner to sa for each job that is not already sa
		$sa = $srv.Logins["sa"]
		
		foreach($job in $jobs)
			{								
				if($job.OwnerLoginName -ne "sa" -and $job.Name -ne $null)
				{
					#store old job owner
					$jobOwner_old = $job.OwnerLoginName
					
					#change owner of job
					$job.set_OwnerLoginName($sa.Name)
					$job.Alter()
					
					#output details of change
					$output_text = $job.Name + "; old owner.." + $jobOwner_old + "; new owner.." + $job.OwnerLoginName
					Write-Host $output_text
				}
			}		
	}
	
	$srv.ConnectionContext.Disconnect()
}
