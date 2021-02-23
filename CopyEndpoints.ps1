<#
Copy new endpoint from Primary Availability Group server to all Secondary servers

example execution:
H:\SSIS\PAT\Root\BatchFiles\CopyEndpoints.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -AvailabilityGroupName "AG"
#>


param
(
  $PSFilesPath,
  $AvailabilityGroupName
)


try
{
	$error.clear()
	cd $PSFilesPath
	
	#write run time to log file
	$date = get-date
	Write-Output $date.ToShortDateString() $date.ToShortTimeString()


    $sqlCommand = New-Object System.Data.SqlClient.SqlCommand
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection

	
	# Gets the list of active servers in the environment
    $ServersList = (.\GetServerList.ps1 | select-object -ExpandProperty ServerName)


    #determine primary and secondary AG servers
    $PrimaryServer = (.\GetAlwaysOnServers.ps1 -ServerType Primary -AvailabilityGroupName $AvailabilityGroupName -ServersList $ServersList)
    $PrimaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($PrimaryServer)

    $SecondaryServer = @(.\GetAlwaysOnServers.ps1 -ServerType Secondary -AvailabilityGroupName $AvailabilityGroupName -ServersList $ServersList)


    write-output "Primary Server: $PrimaryServer"
    write-output "Secondary Servers: $SecondaryServer"

	
	#get endpoints servers from the primary server
    $PrimaryEndpoints = @()
    $PrimaryEndpoints = $PrimaryServer_SQL.Endpoints | where IsSystemObject -eq $False


    #create endpoint on secondary if it does not exist on secondary
    foreach ($Endpoint in $PrimaryServer_SQL.Endpoints)
    {        
            foreach ($Server in $SecondaryServer)
            {

                $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

                #check if endpoint on primary server exists on the secondary, if not, create it
                if ($Endpoint.Name -notin $SecondaryServer_SQL.Endpoints.Name)
                {
                    $EndpointName = $Endpoint.name

                    $new_Endpoint = New-Object Microsoft.SqlServer.Management.Smo.Endpoint $SecondaryServer_SQL, $EndpointName
                
                
                    $new_Endpoint.Catalog = $Endpoint.Catalog
                    $new_Endpoint.CollationCompatible = $Endpoint.CollationCompatible
                    $new_Endpoint.CollationName = $Endpoint.CollationName
                    $new_Endpoint.ConnectTimeout = $Endpoint.ConnectTimeout
                    $new_Endpoint.DataAccess = $Endpoint.DataAccess
                    $new_Endpoint.DataSource = $Endpoint.DataSource
                    $new_Endpoint.DistPublisher = $Endpoint.DistPublisher
                    $new_Endpoint.Distributor = $Endpoint.Distributor
                    $new_Endpoint.LazySchemaValidation = $Endpoint.LazySchemaValidation
                    $new_Endpoint.Location = $Endpoint.Location
                    $new_Endpoint.ProductName = $Endpoint.ProductName
                    $new_Endpoint.ProviderName = $Endpoint.ProviderName
                    $new_Endpoint.ProviderString = $Endpoint.ProviderString
                    $new_Endpoint.Publisher = $Endpoint.Publisher
                    $new_Endpoint.QueryTimeout = $Endpoint.QueryTimeout
                    $new_Endpoint.Rpc = $Endpoint.Rpc
                    $new_Endpoint.RpcOut = $Endpoint.RpcOut
                    $new_Endpoint.Subscriber = $Endpoint.Subscriber
                    $new_Endpoint.UserData = $Endpoint.UserData
                    $new_Endpoint.UseRemoteCollation = $Endpoint.UseRemoteCollation
                
                    $new_Endpoint.Create()

                                
                    Write-Output "Create Endpoint: $Server $EndpointName"

                    }
            }
    }
}

catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Copy Endpoints failed on $Server $EndpointName"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}
