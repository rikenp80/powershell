cls

$snapshot_dir = "F:\Repldata\unc\1006690EBAYDBC2_WFMDATA_WFMDATA_2\20190515101716"
$i = 15
$SumFileSize = 0
$array = New-Object System.Collections.ArrayList


Add-Type -assembly "system.io.compression.filesystem"


#get all Archive folders older than $CurrentDay that need to be zipped
$FilesToZip = Get-ChildItem -Path $snapshot_dir | select-object FullName,Name,Length | Sort -Property Length


foreach($File in $FilesToZip)
{           

    $FileSize = ((Get-ChildItem -Path $File.FullName | Measure-Object -Property Length -Sum).Sum)
    $SumFileSize = $SumFileSize + $FileSize
           
    $array.Add($File.FullName) | out-null
    
    

    #when the group of files gets to 1GB, zip them up
    if ($SumFileSize -gt 1073741824)
    {
        $zip_filecount = $array.count
        $i = $i + 1

        $zip_file = $snapshot_dir + "_" + $i + ".zip"

        write-output "$zip_file - Files=$zip_filecount"
        Compress-Archive -LiteralPath $array -CompressionLevel Optimal -DestinationPath $zip_file

        $SumFileSize = 0
        $array.Clear()
    }
}