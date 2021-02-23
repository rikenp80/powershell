<#
Copy new alerts and Delete removed alerts from Primary Availability Group server to all Secondary servers

example execution:
H:\SSIS\PAT\Root\BatchFiles\CopyAlerts.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -AvailabilityGroupName "AG"
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

    
    #change directory to where the powershell script reside
    cd $PSFilesPath


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


    #drop alert on secondary if it does not exist on primary
    $PrimaryAlerts = @()
    $PrimaryAlerts = $PrimaryServer_SQL.Jobserver.Alerts


    foreach ($Server in $SecondaryServer)
    {
        $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

        #loop through each alert on secondary server, if it does not exist on primary, then drop it
        foreach ($SecondaryAlerts in $SecondaryServer_SQL.jobserver.Alerts.Name)
        {
        
            if ($SecondaryAlerts -notin $PrimaryAlerts.Name)
            {
                Write-Output "Drop Alert: $SecondaryServer_SQL $SecondaryAlerts"
                $SecondaryServer_SQL.jobserver.Alerts[$SecondaryAlerts].Drop()
            }
        }
    }



    #create alert on secondary if it does not exist on secondary
    foreach ($Alert in $PrimaryServer_SQL.jobserver.Alerts)
    {
        
        foreach ($Server in $SecondaryServer)
        {

            $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

            #check if alert on primary server exists on the seconday, if not, create it
            if ($Alert.Name -notin $SecondaryServer_SQL.jobserver.Alerts.Name)
            {
                $AlertName = $Alert.name

                $new_Alert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert $SecondaryServer_SQL.JobServer,$AlertName

                $new_Alert.DatabaseName = $Alert.DatabaseName
                $new_Alert.DelayBetweenResponses = $Alert.DelayBetweenResponses
                $new_Alert.EventDescriptionKeyword = $Alert.EventDescriptionKeyword
                $new_Alert.JobID = $Alert.JobID
                $new_Alert.LastOccurrenceDate = $Alert.LastOccurrenceDate
                $new_Alert.LastResponseDate = $Alert.LastResponseDate
                $new_Alert.MessageID = $Alert.MessageID
                $new_Alert.PerformanceCondition = $Alert.PerformanceCondition
                $new_Alert.Severity = $Alert.Severity
                $new_Alert.IsEnabled = $Alert.IsEnabled
                
                $new_Alert.Create()


                Write-Output "Create Alert: $Server $AlertName"
            }
        }
    }
}

catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Copy Alerts failed on $Server $AlertName"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}