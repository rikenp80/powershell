#C:\Powershell\ManualForcedFailover.ps1 -new_primary TJGSQLT250 -availability_group_name AG | Out-File C:\Powershell\ManualForcedFailover_Log.txt

param
(
  [string]$new_primary,
  [string]$availability_group_name
)

# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")



$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection


#define old and new primary SQL servers
$old_primary_name = (C:\Powershell\GetAlwaysOnServers.ps1 -ServerType Primary -AvailabilityGroupName AG -ServersList C:\Powershell\Servers.txt)
$old_primary_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($old_primary_name)
$new_primary_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($new_primary)



#force failover to specified server
Switch-SqlAvailabilityGroup -Path "SQL\$new_primary\DEFAULT\AvailabilityGroups\$availability_group_name" -AllowDataLoss -Force



#disable jobs on the old primary that were enabled and enable those same jobs on the new primary
ForEach ($old_primary_job in ($old_primary_SQL.JobServer.Jobs | Where-Object {$_.IsEnabled -eq $TRUE}))
{
    if ($old_primary_job.name -notin ("Archive suspect_pages","Create New Errorlog","syspolicy_purge_history"))
    {
        $old_primary_job_name = $old_primary_job.name
        $old_primary_job_runstatus = $old_primary_job.CurrentRunStatus
        $old_primary_job_runstep = $old_primary_job.CurrentRunStep

        write-output "$old_primary_job_name $old_primary_job_runstatus $old_primary_job_runstep"


        $old_primary_job.IsEnabled = $FALSE
        $old_primary_job.Alter()

		$new_primary_job = $new_primary_SQL.JobServer.Jobs | Where-Object {$_.Name -eq $old_primary_job.name}
        $new_primary_job.IsEnabled = $TRUE
        $new_primary_job.Alter()
    }
}


#map orphaned users in the new primary
ForEach($db in $new_primary_SQL.Databases)
{
    # remove square brackets from db name
    [string]$dbname = $db
    $dbname = $dbname.Replace("[", "")
    $dbname = $dbname.Replace("]", "")


    #users with no login that are not system users to be fixed
    ForEach($db_user in ($db.users | Where-Object {$_.UserType -eq "NoLogin" -and $_.IsSystemObject -eq $false}))
    {
        # remove square brackets from db user
        [string]$dbuser = $db_user
        $dbuser = $dbuser.Replace("[", "")
        $dbuser = $dbuser.Replace("]", "")

        $Query = "EXEC sp_change_users_login 'Auto_Fix', '$dbuser'"
        write-output $dbname $Query
        Invoke-Sqlcmd -ServerInstance $new_primary_SQL -database $dbname -Query $Query -ErrorAction SilentlyContinue
    }
}


#get secondary servers after failover
$SecondarySrv = @($new_primary_SQL.AvailabilityGroups[$availability_group_name].AvailabilityReplicas | Where-Object {$_.Role -eq "Secondary"} | Select-Object Name -ExpandProperty Name)


#loop through each secondary server and resume data movement if it is paused
foreach ($Server in $SecondarySrv)
{
      
	$SecondarySQLSrv = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)
	$SecondarySQLSrv.ConnectionContext.NonPooledConnection = "True"
		
	foreach($db in $SecondarySQLSrv.Databases)
	{
        #determine if database is used in Always On and synchronized
        $SynchronizationState = $db.AvailabilityDatabaseSynchronizationState
        $AvailabilityGroupName = $db.AvailabilityGroupName
		    
            
        if ($AvailabilityGroupName -ne "" -and $SynchronizationState -ne "Synchronizing")
        {
            # remove square brackets from db name
            [string]$dbname = $db
		    $dbname = $dbname.Replace("[", "")
		    $dbname = $dbname.Replace("]", "")
            
            #set db path to resume data movement and execute task
			$path = "SQL\$Server\DEFAULT\AvailabilityGroups\$AvailabilityGroupName\AvailabilityDatabases\$dbname"
		        
            write-output $path
			Resume-SqlAvailabilityDatabase -Path $path
        }
	}
}