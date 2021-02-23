<#
Backup all database in the current environment

example execution
C:\Powershell\UpdateStatistics.ps1 -ServersList "SWL2K12PMON1VM"
#>


param
(
  $ServersList = (hostname)
)


# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") | Out-Null


try
{    

	#output date
	Write-Output ("=======" + (get-date -format "yyyy-MM-dd HH:mm:ss") + "=======")

    
	# loop through all SQL Servers
	foreach($server_instance in $ServersList)
    {	
  
        Write-Output "`r`n#### $server_instance ####"

        #remove sql instance name from server name
        $Server = $server_instance.split("\")[0]

        #connect to sql server
        $Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($ServersList)
        $Server_SQL.ConnectionContext.StatementTimeout = 0



		# loop through all DBs on server and backup
		foreach($db in $Server_SQL.Databases)
        {
            if ($db.IsSystemObject -eq $false -and $db.Status -like "Normal*" -and $db.IsUpdateable -eq $true)
            {
            $db.Name
            $db.UpdateIndexStatistics()
            }
        }
	}
}


catch
{
    Write-Error $_

    [System.Environment]::Exit(1)
}
