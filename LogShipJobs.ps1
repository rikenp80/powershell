<#
Enable Log Shipping jobs on the Log Shipping secondary server for jobs that reference the Availability Group Primary Server.
Disable jobs that reference the Availability Group Secondary.

example execution:
C:\Powershell\LogShipJobs.ps1 -ListenerName "UIPHAGROUP_LIST" -LS_Target "810093-DEV-UDBC\UIP_CONFIG" -Backup_SourcePath "\\809215-dev-dat1\epro" -Backup_TargetPath "\\810093-dev-udbc\log_shipping"
#>

param
(
    $ListenerName,
    $LS_Target,
    $Backup_TargetPath
)

[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null


#write run time to log file
$date = get-date
Write-Output $date.ToShortDateString() $date.ToShortTimeString()


$sqlListener = New-Object Microsoft.SqlServer.Management.Smo.Server($ListenerName);

$PrimaryReplicaName = $sqlListener.AvailabilityGroups.PrimaryReplicaServerName
$SecondaryReplicaName = $sqlListener.AvailabilityGroups.AvailabilityReplicas | Where-Object {$_.Role -eq "Secondary"} | Select-Object Name -ExpandProperty Name


$sql_LS_Target = New-Object Microsoft.SqlServer.Management.Smo.Server ($LS_Target)
$sql_PrimaryReplica = New-Object Microsoft.SqlServer.Management.Smo.Server ($PrimaryReplicaName)
$sql_SecondaryReplica = New-Object Microsoft.SqlServer.Management.Smo.Server ($SecondaryReplicaName)


write-output "AG Primary: $PrimaryReplicaName"
write-output "AG Secondary: $SecondaryReplicaName"
write-output "LS Target: $LS_Target"



#enable log shipping jobs that have the name of the primary AG in it
#disable log shipping jobs that have the name of the secondary AG in it
foreach($job in $sql_LS_Target.JobServer.Jobs)
{ 
    if  (
            ($job.Name -like "LSCopy*" -or $job.Name -like "LSRestore*") -and
            $job.Name -like "*" + $PrimaryReplicaName + "*" -and
            $job.IsEnabled -ne $true
        )

        {
            $job.IsEnabled = $true
            $job.Alter()

            write-output $job.Name $job.IsEnabled
        }


    if  (
            ($job.Name -like "LSCopy*" -or $job.Name -like "LSRestore*") -and
            $job.Name -notlike "*" + $PrimaryReplicaName + "*" -and
            $job.IsEnabled -ne $false
        )

        {
            $job.IsEnabled = $false
            $job.Alter()

            write-output $job.Name $job.IsEnabled
        }
}



#enable log shipping backup jobs on the primary AG and disable the secondary AG
#after an AG failover the jobs do not enable/disable themselves
foreach($job in $sql_PrimaryReplica.JobServer.Jobs)
{ 
    if  (
            $job.Name -like "LSBackup*" -and
            $job.IsEnabled -ne $true
        )

        {
            $job.IsEnabled = $true
            $job.Alter()

            write-output $job.Name $job.IsEnabled
        }
}


foreach($job in $sql_SecondaryReplica.JobServer.Jobs)
{ 
    if  (
            $job.Name -like "LSBackup*" -and
            $job.IsEnabled -ne $false
        )

        {
            $job.IsEnabled = $false
            $job.Alter()

            write-output $job.Name $job.IsEnabled
        }
}



#move missing .trn backup files from primary AG to log shipping target server
#after an AG failover, the last backup file will not get copied over
$LS_DBs = (invoke-sqlcmd -ServerInstance $sql_LS_Target -Database "msdb" -Query "select secondary_database from msdb.dbo.log_shipping_secondary_databases").secondary_database


foreach($db in $LS_DBs)
{ 
    cd c:

    $SourcePath = "\\" + $sql_PrimaryReplica.NetName + "\epro\" + $db + "\*.trn"
    $TargetPath = $Backup_TargetPath + "\" + $db + "*.trn"

    Write-Output "------------------------"
    Write-Output $SourcePath
    Write-Output $TargetPath
    
    $SourceFiles = Get-ChildItem -Path $SourcePath | Where-Object LastWriteTime -ge ((Get-Date).AddMinutes(-30)) | Select-Object Name, FullName
    $TargetFiles = Get-ChildItem -Path $TargetPath | Where-Object LastWriteTime -ge ((Get-Date).AddMinutes(-30)) | Select-Object Name, FullName

    $SourceFiles.Count
    $TargetFiles.Count



    foreach($SourceFile in $SourceFiles)
    {

        $SourceFileName = $SourceFile.Name
        $SourceFileFullName = $SourceFile.FullName
        
        if  ($TargetFiles.Name -contains $SourceFileName -eq $false)
            {
            Copy-Item $SourceFileFullName ($Backup_TargetPath + "\" + $SourceFileName) -Verbose
            }
    }
    
}



<#
update log shipping tables with the log shipping secondary id of the primary 
#>

$SQLQuery =  "
            declare @log_shipping_secondary_AGPrimary table (AGPrimary_secondary_id uniqueidentifier, primary_database sysname, AGPrimary_server sysname)
            declare @log_shipping_secondary_AGSecondary table (AGSecondary_secondary_id uniqueidentifier, primary_database sysname, AGSecondary_server sysname)

            insert into @log_shipping_secondary_AGPrimary
            select s.secondary_id, s.primary_database, s.primary_server
            from log_shipping_secondary s
            where s.primary_server = '" + $PrimaryReplicaName + "'

            insert into @log_shipping_secondary_AGSecondary
            select s.secondary_id, s.primary_database, s.primary_server
            from log_shipping_secondary s
            where s.primary_server = '" + $SecondaryReplicaName + "'

            update sd
            set secondary_id = a.AGPrimary_secondary_id
            from @log_shipping_secondary_AGPrimary a
		            inner join @log_shipping_secondary_AGSecondary b on a.primary_database = b.primary_database
		            inner join log_shipping_secondary_databases sd on sd.secondary_id = b.AGSecondary_secondary_id

            update ms
            set secondary_id = a.AGPrimary_secondary_id, primary_server = a.AGPrimary_server
            from @log_shipping_secondary_AGPrimary a
		            inner join @log_shipping_secondary_AGSecondary b on a.primary_database = b.primary_database
		            inner join log_shipping_monitor_secondary ms on ms.secondary_id = b.AGSecondary_secondary_id
            "
write-output $Query

invoke-sqlcmd -ServerInstance $LS_Target -Database "msdb" -Query $SQLQuery