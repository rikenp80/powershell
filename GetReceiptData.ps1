cls
$table = New-Object System.Data.DataTable

$date_col = New-Object System.Data.DataColumn("date_col")
$store_col = New-Object System.Data.DataColumn("store_col")
$amount_col = New-Object System.Data.DataColumn("amount_col")

$table.columns.Add($date_col)
$table.columns.Add($store_col)
$table.columns.Add($amount_col)



$destination_path = "\\192.168.1.6\Documents\Receipts\2020-06"
$files = Get-ChildItem -Path $destination_path | where { -not $_.PsIsContainer } | select name, Extension | Sort name 
#$files

ForEach ($file in $files)
{
    $filename = $file.name
    $file_ext = $file.extension
    #$filename
    $filename = $filename.replace($file_ext, "")

    $date = ($filename.split("_")[0]).trim()
    $store = ($filename.split("_")[1]).trim()
    $amount = ($filename.split("_")[2]).trim()

    
    #Add a row to DataTable

    $row = $table.NewRow()
    $row["date_col"] = $date
    $row["store_col"] = $store
    $row["amount_col"] = $amount
    $table.rows.Add($row)




}

$table | Export-Csv \\192.168.1.6\Documents\Receipts\table.csv -NoType