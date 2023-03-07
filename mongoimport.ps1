cls

$source_path =  "\\diskstation\Documents\CC_Transactions\wells_fargo"
$modified_file_path =  $source_path + "\modified_files\"
$fields_file =  $source_path + "\fields.txt"



$files = gci $source_path -Attributes !Directory | Select Fullname, Name


foreach($file in $files)
{    
    if ($file.Name -contains "fields.txt" -eq $true) {continue}

    

    $file_name = $file.Name
    $file_fullname = $file.FullName

    write-output $file_name


    $modified_file = $modified_file_path + $file_name


    #get leaf folder which should be set to account name
    $parent_dir = Split-Path -Path $file_fullname    
    $account = $parent_dir.split("\")[-1]

    
    #if ($account -eq "wells_fargo") {$file = import-csv $file -Header a,b,c,d,e | export-csv $file}


    $modified_data = Import-Csv $file_fullname -Header a,b,c,d,e | Select-Object *, @{Name='account';Expression={$account}}
    $modified_data | Export-Csv $modified_file -NoTypeInformation

    $modified_data

    $noheader_content = Get-Content $modified_file | select -Skip 1
    $noheader_content = $noheader_content | ForEach-Object {$_ -replace '"',''}

    $noheader_content | Set-Content $modified_file



    mongoimport mongodb+srv://riken:A5hn112215*@cc-transactions.wyhksim.mongodb.net/finances?appName=mongosh+1.6.1 --collection=cctrans --file=$modified_file --type=csv --fieldFile=$fields_file --columnsHaveTypes
    
    $imported_dir = $parent_dir + "\imported"
    Move-Item -Path $modified_file -Destination $imported_dir

}