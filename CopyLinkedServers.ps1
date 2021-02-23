<#
Copy new linked servers from Primary Availability Group server to all Secondary servers

example execution:
H:\SSIS\PAT\Root\BatchFiles\CopyLinkedServers.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -AvailabilityGroupName "AG"
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


    #get linked servers from the primary server
    $PrimaryLinkedServers = @()
    $PrimaryLinkedServers = $PrimaryServer_SQL.LinkedServers


    #create linked server on the secondary if it does not exist on secondary
    foreach ($LinkedServer in $PrimaryServer_SQL.LinkedServers)
    {        
        foreach ($Server in $SecondaryServer)
        {
            $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

            #check if linked server on primary server, exists on the seconday, if not, create it
            if ($LinkedServer.Name -notin $SecondaryServer_SQL.LinkedServers.Name)
            {
                $LinkedServerName = $LinkedServer.name

                $new_LinkedServer = New-Object Microsoft.SqlServer.Management.Smo.LinkedServer $SecondaryServer_SQL, $LinkedServerName
                
                
                $new_LinkedServer.Catalog = $LinkedServer.Catalog
                $new_LinkedServer.CollationCompatible = $LinkedServer.CollationCompatible
                $new_LinkedServer.CollationName = $LinkedServer.CollationName
                $new_LinkedServer.ConnectTimeout = $LinkedServer.ConnectTimeout
                $new_LinkedServer.DataAccess = $LinkedServer.DataAccess
                $new_LinkedServer.DataSource = $LinkedServer.DataSource
                $new_LinkedServer.DistPublisher = $LinkedServer.DistPublisher
                $new_LinkedServer.Distributor = $LinkedServer.Distributor
                $new_LinkedServer.LazySchemaValidation = $LinkedServer.LazySchemaValidation
                $new_LinkedServer.Location = $LinkedServer.Location
                $new_LinkedServer.ProductName = $LinkedServer.ProductName
                $new_LinkedServer.ProviderName = $LinkedServer.ProviderName
                $new_LinkedServer.ProviderString = $LinkedServer.ProviderString
                $new_LinkedServer.Publisher = $LinkedServer.Publisher
                $new_LinkedServer.QueryTimeout = $LinkedServer.QueryTimeout
                $new_LinkedServer.Rpc = $LinkedServer.Rpc
                $new_LinkedServer.RpcOut = $LinkedServer.RpcOut
                $new_LinkedServer.Subscriber = $LinkedServer.Subscriber
                $new_LinkedServer.UserData = $LinkedServer.UserData
                $new_LinkedServer.UseRemoteCollation = $LinkedServer.UseRemoteCollation

                $new_LinkedServer.Create()


                #query to get linked server login data
                $Query_GetSecurity =
                    "
                    SELECT  CASE WHEN l.uses_self_credential = 0 THEN 'False' ELSE 'True' END 'useself',
		                    ISNULL(sp.name,'') 'locallogin',
                            l.remote_name 'rmtuser'
                    FROM sys.servers s
	                    INNER JOIN sys.linked_logins l ON s.server_id = l.server_id
	                    LEFT JOIN sys.server_principals sp ON l.local_principal_id = sp.principal_id
                    WHERE s.name = '$LinkedServerName'
                    ORDER BY locallogin DESC
                    "
                
                $Results_GetSecurity = @(Invoke-Sqlcmd -ServerInstance $PrimaryServer_SQL -database "master" -Query $Query_GetSecurity)
            

                #create security for linked server. the password is not set as it is not possible to retrieve it from the primary
                foreach ($row in $Results_GetSecurity)
                {
                    $useself = $row.useself
                    $locallogin = $row.locallogin
                    $rmtuser = $row.rmtuser
                

                    if ($locallogin -eq $null -or $locallogin -eq "")
                    {
                        $Query_AddLinkedSrvLogin = "EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname='$LinkedServerName', @useself='$useself', @locallogin=null, @rmtuser='$rmtuser', @rmtpassword=null"                   
                    }
                    else
                    {
                        $Query_AddLinkedSrvLogin = "EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname='$LinkedServerName', @useself='$useself', @locallogin='$locallogin', @rmtuser='$rmtuser', @rmtpassword=null"                    
                    }

                    Invoke-Sqlcmd -ServerInstance $SecondaryServer_SQL -database "master" -Query $Query_AddLinkedSrvLogin

                }

                Write-Output "Create Linked Server: $Server $LinkedServerName"
            }
        }
    }
}


catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Copy Linked Servers failed on $Server $LinkedServerName"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}
