$sqlCommand = New-Object System.Data.SqlClient.SqlCommand
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection


#connect to sql server
$Server_SQL = "mtr116"
$Database = "dbmanagement"

$sqlConnection.ConnectionString = "Server=$Server; Database=$Database; Integrated Security = True;"
        

# populate dataset with sql data
$ds = new-object "System.Data.DataSet"

$query = "select ServerName from ServersList where Active = 1"

$da = new-object "System.Data.SqlClient.SqlDataAdapter" ($query, $sqlConnection)
$da.Fill($ds) | out-null


# create data table from data set
$dt = new-object System.Data.DataTable
$dt = $ds.Tables[0] | select-object -ExpandProperty ServerName

write-output $dt 