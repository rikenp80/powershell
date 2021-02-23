$Query = "select * from ServerList where Active = 1"
$ActiveIntSQLServer = ""

$ServerList = @(Invoke-Sqlcmd -ServerInstance $ActiveIntSQLServer -database "SQLMaint" -Query $Query)

write-output $ServerList