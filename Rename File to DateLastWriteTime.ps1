cls
$directory = ""

cd $directory
$files = Get-ChildItem *.* -Path $directory -Recurse | Where-Object {$_ -isnot [IO.DirectoryInfo]}


foreach ($file in $files)
 	{

    $full_file_path = Get-Item $file.name
	$file_name = $file.name
    $file_date = $file.LastWriteTime                      
    $extension = $file.Extension
	  
    $year=$file_date.year.tostring("0000")
    $month=$file_date.month.tostring("00")
    $day=$file_date.day.tostring("00")
    $hour=$file_date.hour.tostring("00")
    $minute=$file_date.minute.tostring("00")
    $second=$file_date.second.tostring("00")


    $new_file_name = $year + "_" + $month + "_" + $day + "_" + $hour + $minute + $second + $extension

    write-host $full_file_path
    #write-host $file_name
    #write-host $file_date
    write-host $new_file_name

	rename-item -path $full_file_path -newname $new_file_name

	}