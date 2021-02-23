$file_path = "C:\Users\Riken.Patel\Downloads\new_test.csv"
$table = new-object System.Data.DataTable "Data"

#Define Columns
$col1 = New-Object system.Data.DataColumn MultiMailerBatchInstanceId,([string])
$col2 = New-Object system.Data.DataColumn StartDate,([string])
$col3 = New-Object system.Data.DataColumn EndDate,([string])
$col4 = New-Object system.Data.DataColumn BatchSize,([string])
$col5 = New-Object system.Data.DataColumn SentCount,([string])
$col6 = New-Object system.Data.DataColumn ExceptionCount,([string])


#Add the Columns
$table.columns.add($col1)
$table.columns.add($col2)
$table.columns.add($col3)
$table.columns.add($col4)
$table.columns.add($col5)
$table.columns.add($col6)

		
$BatchInstanceId = Get-ChildItem $file_path | Select-String -pattern "Batch Instance ID="
$EndDate = Get-ChildItem $file_path | Select-String -pattern "completed at "
$StartDate = Get-ChildItem $file_path | Select-String -pattern "Started at:"
$BatchSize = Get-ChildItem $file_path | Select-String -pattern "Members processed:"
$SentCount = Get-ChildItem $file_path | Select-String -pattern "Emails sent:"
$ExceptionCount = Get-ChildItem $file_path | Select-String -pattern "Exceptions:"



foreach ($row in $BatchInstanceId)
{
	$new_table_row = $table.NewRow()	
	
	$row_sub = [string]$row
	
	$batch_index = $row_sub.IndexOf("Batch Instance ID=")
	$start_date_index = $row_sub.IndexOf("1000,")
	
	$row_sub_batch = $row_sub.Substring($batch_index + 19, 36)
	$row_sub_startdate = $row_sub.Substring($start_date_index + 5)
	
		
	$new_table_row.StartDate = $row_sub_startdate
	$new_table_row.MultiMailerBatchInstanceId = $row_sub_batch
	
	$table.Rows.Add($new_table_row)
}

	
$i = 0
foreach ($row in $EndDate)
{	
	$row_sub = [string]$row
	
	$start_trim = $row_sub.IndexOf("completed at")

	$row_sub = $row_sub.Substring($row_sub.length - ($row_sub.length - $start_trim - 13))
	$row_sub = $row_sub.replace(".","")
	$table.Rows[$i]["EndDate"] = $row_sub
	
	$i = $i + 1
}


$i = 0
foreach ($row in $BatchSize)
{	
	$row_sub = [string]$row

	$start_trim = $row_sub.IndexOf("processed")

	$row_sub = $row_sub.Substring($row_sub.length - ($row_sub.length - $start_trim - 11))
	$row_sub = $row_sub.replace(".","")
	$table.Rows[$i]["BatchSize"] = $row_sub
	
	$i = $i + 1
}


$i = 0
foreach ($row in $SentCount)
{	
	$row_sub = [string]$row

	$start_trim = $row_sub.IndexOf("sent")

	$row_sub = $row_sub.Substring($row_sub.length - ($row_sub.length - $start_trim - 6))
	$row_sub = $row_sub.replace(".","")
	$table.Rows[$i]["SentCount"] = $row_sub
	
	$i = $i + 1
}


$i = 0
foreach ($row in $ExceptionCount)
{	
	$row_sub = [string]$row

	$start_trim = $row_sub.IndexOf("Exceptions")

	$row_sub = $row_sub.Substring($row_sub.length - ($row_sub.length - $start_trim - 12))
	$row_sub = $row_sub.replace(".","")
	$table.Rows[$i]["ExceptionCount"] = $row_sub
	
	$i = $i + 1
}


$table | export-csv –path C:\Users\Riken.Patel\Downloads\formatted.csv

			
#$table | format-table -AutoSize
