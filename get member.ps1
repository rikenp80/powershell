cls
# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null

$PrimaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ("")
$PrimaryServer_SQL.linkedservers





#Get a server object which corresponds to the default instance
$svr = New-Object -TypeName Microsoft.SqlServer.Management.SMO.Server

#Create a linked server object which corresponds to an OLEDB type of SQL server product
$lsvr = New-Object -TypeName Microsoft.SqlServer.Management.SMO.LinkedServer -argumentlist $svr,"OLEDBSRV"

#When the product name is SQL Server the remaining properties are not required to be set. 
$lsvr.ProductName = "SQL Server"

#Create the Database Object
$lsvr.Create()  