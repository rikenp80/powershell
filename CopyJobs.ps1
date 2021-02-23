cls
# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null


$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection


$PrimaryServer = (C:\Powershell\GetAlwaysOnServers.ps1 -ServerType Primary -AvailabilityGroupName AG -ServersList C:\Powershell\Servers.txt)
$PrimaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($PrimaryServer)

$SecondaryServer = @(C:\Powershell\GetAlwaysOnServers.ps1 -ServerType Secondary -AvailabilityGroupName AG -ServersList C:\Powershell\Servers.txt)


write-output "Primary Server: $PrimaryServer"
write-output "Secondary Servers: $SecondaryServer"

#drop login on secondary if it does not exist on primary
$PrimaryJobs = @()
$PrimaryJobs = $PrimaryServer_SQL.Jobserver.Jobs



foreach ($Server in $SecondaryServer)
{
    $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

    #loop through each login on secondary server, if it does not exist on primary, then drop it
    foreach ($SecondaryJob in $SecondaryServer_SQL.Jobserver.Jobs.Name)
    {                
        
        if ($SecondaryJob -notin $PrimaryJobs.Name)
        {
            Write-Output "Drop Job: $SecondaryServer_SQL $SecondaryJob"
            $SecondaryServer_SQL.Jobserver.Jobs[$SecondaryJob].Drop()
        }
    }
}



#create job on secondary if it does not exist on secondary
foreach ($Job in $PrimaryServer_SQL.Jobserver.Jobs)
{
        
        foreach ($Server in $SecondaryServer)
        {

            $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

            #check if job on primary server exists on the seconday, if not, create it
            if ($Job.Name -notin $SecondaryServer_SQL.Jobserver.Jobs.Name)
            {

                $JobName = $Job.name

                $new_Job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job $SecondaryServer_SQL.JobServer,$JobName
                
                $new_Job.Category = $Job.Category
                $new_Job.CategoryType = $Job.CategoryType
                $new_Job.DeleteLevel = $Job.DeleteLevel
                $new_Job.Description = $Job.Description
                $new_Job.EmailLevel = $Job.EmailLevel
                $new_Job.EventLogLevel = $Job.EventLogLevel
                $new_Job.IsEnabled = $Job.IsEnabled
                $new_Job.OperatorToEmail = $Job.OperatorToEmail
                $new_Job.OperatorToNetSend = $Job.OperatorToNetSend
                $new_Job.OperatorToPage = $Job.OperatorToPage
                $new_Job.OwnerLoginName = $Job.OwnerLoginName
                $new_Job.PageLevel = $Job.PageLevel
                $new_Job.UserData = $Job.UserData
                $new_Job.StartStepID = $Job.StartStepID

                
                $new_Job.Create()

                $PrimaryServer_SQL.Jobserver.Jobs[$JobName].JobSteps
                                
                Write-Output "Create Job: $Server $JobName"

                }
        }
}