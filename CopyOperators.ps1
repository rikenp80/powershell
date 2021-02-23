<#
Copy new operators from Primary Availability Group server to all Secondary servers

example execution:
H:\SSIS\PAT\Root\BatchFiles\Copyoperators.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -AvailabilityGroupName "AG"
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

    #get operators from the primary server
    $PrimaryOperators = @()
    $PrimaryOperators = $PrimaryServer_SQL.jobserver.operators



    foreach ($Server in $SecondaryServer)
    {
        $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

        #loop through each operators on secondary server, if it does not exist on primary, then drop it
        foreach ($SecondaryOperators in $SecondaryServer_SQL.jobserver.operators.Name)
        {                        
            if ($SecondaryOperators -notin $PrimaryOperators.Name)
            {
                Write-Output "Drop Operator: $SecondaryServer_SQL $SecondaryOperators"
                $SecondaryServer_SQL.jobserver.operators[$SecondaryOperators].Drop()
            }
        }
    }



    #create operators on secondary if it does not exist on secondary
    foreach ($operator in $PrimaryServer_SQL.jobserver.operators)
    {
        
            foreach ($Server in $SecondaryServer)
            {

                $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

                #check if operators on primary server exists on the seconday, if not, create it
                if ($operator.Name -notin $SecondaryServer_SQL.jobserver.operators.Name)
                {
                    $operatorName = $operator.name

                    $new_operator = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator $SecondaryServer_SQL.JobServer,$operatorName
                
                    $new_operator.EmailAddress = $operator.EmailAddress
                    $new_operator.Enabled = $operator.Enabled
                
                    $new_operator.Create()
                                
                    Write-Output "Create Operator: $Server $operatorName"

                    }
            }
    }
}


catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Copy Operator failed on $Server $operatorName"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}