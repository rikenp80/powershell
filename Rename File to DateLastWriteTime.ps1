cls
$directory = "\\DISKSTATION\Other\TempPhotoTransfer\Video"

cd $directory
$files = Get-ChildItem *.* -Path $directory -Recurse | Where-Object {$_ -isnot [IO.DirectoryInfo]}


foreach ($file in $files)
 	{
 
        $last_write = $file.LastWriteTime

        $full_file_path = Get-Item $file.name
        
        $extension = $file.Extension

        $Day = $last_write.Day.ToString("00")
        $Month = $last_write.Month.ToString("00")
        $Year = $last_write.Year.ToString("00")
        $Hour = $last_write.Hour.ToString("00")
        $Minute = $last_write.Minute.ToString("00")
        $Second = $last_write.Second.ToString("00")
        #[string]$Ticks = $last_write.Ticks


      
        if($file_name -match '[0-9]')
        {
            
            $new_file_name = $year + $month + $day + "_" + $hour + $minute + $second + $extension
    

            write-host $full_file_path
            write-host $new_file_name

	        #rename-item -path $full_file_path -newname $new_file_name
        }

	}