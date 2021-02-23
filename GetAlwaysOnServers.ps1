param
(
  $ServerType,
  $AvailabilityGroupName,
  $ServersList
)


# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null


#get list of servers
$servers = $ServersList

#loop through each server from list
foreach($server in $servers)
{	
   # Write-Output $server
    $srv = New-Object Microsoft.SqlServer.Management.Smo.Server ($server)
        
        
    #if current server is the primary in always on then $PrimarySrv will be set
	$PrimarySrv = $srv.AvailabilityGroups[$AvailabilityGroupName].AvailabilityReplicas | Where-Object {$_.Role -eq "Primary"} | Select-Object Name -ExpandProperty Name
        
    
        
    #if $PrimarySrv is not null then get the secondary servers in always on and exit from loop
    if ($PrimarySrv -ne $null)
        {
        $SecondarySrv = @($srv.AvailabilityGroups[$AvailabilityGroupName].AvailabilityReplicas | Where-Object {$_.Role -eq "Secondary"} | Select-Object Name -ExpandProperty Name)
        break
        } 
}


#output server name
if ($ServerType -eq "Primary")
{
    write-output $PrimarySrv
    
}
elseif ($ServerType -eq "Secondary")
{
    write-output $SecondarySrv
}
else
{
    Throw "ServerType not set correctly. Should be 'Primary' or 'Secondary'"
}
