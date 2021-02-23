<#
Copy new notifications from Primary Availability Group server to all Secondary servers

example execution:
H:\SSIS\PAT\Root\BatchFiles\CopyNotifications.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -AvailabilityGroupName "AG"
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



    #query to get the alert notifications
    $Query = "SELECT n.notification_method, a.name 'alert', o.name 'operator'
              FROM msdb.dbo.sysnotifications n
	                INNER JOIN msdb.dbo.sysalerts a on a.id = n.alert_id
	                INNER JOIN msdb.dbo.sysoperators o on o.id = n.operator_id"


    #get alert notifications on primary
    $PrimaryNotifications = @(Invoke-Sqlcmd -ServerInstance $PrimaryServer_SQL -database "msdb" -Query $Query)


    foreach ($Server in $SecondaryServer)
    {
        $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)
    
        #get alert notifications on secondary
        $SecondaryNotifications = @(Invoke-Sqlcmd -ServerInstance $SecondaryServer_SQL -database "msdb" -Query $Query)
    

        #if notification exists on primary and not secondary then create it
        foreach ($primarynotification in $PrimaryNotifications)
        {
            $notification_alert = $primarynotification.alert
            $notification_operator = $primarynotification.operator
            $notification_method = $primarynotification.notification_method

            if ($primarynotification.alert -notin $SecondaryNotifications.alert)
            {
                $InsertQuery =
                    "
                    SET QUOTED_IDENTIFIER OFF

                    DECLARE @alert_id INT,
		                    @operator_id INT

                    SELECT @alert_id = id FROM msdb.dbo.sysalerts where name = ""$notification_alert""
                    SELECT @operator_id = id FROM msdb.dbo.sysoperators where name = ""$notification_operator""

                    INSERT INTO msdb.dbo.sysnotifications (alert_id, operator_id, notification_method)
                    VALUES (@alert_id, @operator_id, $notification_method)
                    "

                Write-Output "$notification_alert, $notification_operator, $notification_method"
                Invoke-Sqlcmd -ServerInstance $SecondaryServer_SQL -database "msdb" -Query $InsertQuery
            }
        }
    }
}


catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Copy Notification failed on $Server $notification_alert $notification_operator $notification_method"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}
