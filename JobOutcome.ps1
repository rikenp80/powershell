[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

$table = new-object System.Data.DataTable "Data"

#Define Columns
$col1 = New-Object system.Data.DataColumn JobName,([string])
$col2 = New-Object system.Data.DataColumn JobIsEnabled,([string])
$col3 = New-Object system.Data.DataColumn JobOutcome,([string])


#Add the Columns
$table.columns.add($col1)
$table.columns.add($col2)
$table.columns.add($col3)


$srv = New-Object Microsoft.SqlServer.Management.Smo.Server ("UK-W2K8SQ-TRL01")
			
$jobs = $srv.JobServer.Jobs
	 

ForEach ($job in $jobs)  
{ 
	$new_table_row = $table.NewRow()	
	
	$col1 = $job.name
	$col2 = $job.IsEnabled
	$col3 = $job.LastRunOutcome	

	$new_table_row.JobName = $col1
	$new_table_row.JobIsEnabled = $col2
	$new_table_row.JobOutcome = $col3
	
	$table.Rows.Add($new_table_row)	
}

$dw = New-Object System.Data.DataView($table)

$dw.Sort="JobIsEnabled DESC, JobOutcome ASC, JobName ASC"

$timestamp = Get-Date -format yyyyMMdd

$file_name = "\\uk-w2k8fp-trl01\tjshared$\DBA\UK-W2K8SQ-TRL01_JobResults_" + $timestamp + ".csv"

$dw | export-csv –path $file_name
