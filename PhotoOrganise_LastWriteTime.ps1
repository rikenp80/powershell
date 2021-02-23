cls

[reflection.assembly]::loadfile( "C:\Windows\Microsoft.NET\Framework\v4.0.30319\System.Drawing.dll") 

$i = 0

        New-PSDrive -Name P -PSProvider FileSystem -Root \\DISKSTATION\photo\Family
        
        $source_path = "C:\Users\rik_e\Pictures\Transfer\Photo"

		$files=Get-ChildItem $source_path

        $processed_out_file = "C:\Users\rik_e\Pictures\Transfer\logs\photo\processed_" + (Get-Date -Format yyyy_MM_dd_HHmmss) + ".txt"
        $duplicates_delete_out_file = "C:\Users\rik_e\Pictures\Transfer\logs\photo\duplicates_delete_" + (Get-Date -Format yyyy_MM_dd_HHmmss) + ".txt"
        $duplicates_by_name_out_file = "C:\Users\rik_e\Pictures\Transfer\logs\photo\duplicates_delete_" + (Get-Date -Format yyyy_MM_dd_HHmmss) + ".txt"
        $errors_out_file = "C:\Users\rik_e\Pictures\Transfer\logs\photo\errors_" + (Get-Date -Format yyyy_MM_dd_HHmmss) + ".txt"

        $duplicate_count = 0
        $errors_count = 0
        $processed_count = 0
        

        
		ForEach ($file in $files)
		{   
            try
            {
	            $error.clear()
     
                write-output "-------------------------------------------------------------"
                $source_writetime = $file.LastWriteTime.ticks
                $source_size = $file.Length
                $source_fullname = $file.fullname
                $source_name = $file.name

				[string]$strMonth = $file.LastWriteTime.Month
                [string]$strYear = $file.LastWriteTime.Year


				$destination_directory = "P:\"
                $destination_folder = $strYear + "\" + $strMonth
                $destination_path = $destination_directory + $destination_folder

                write-output $source_fullname
                write-output $destination_path


                $file=""

                #all files in the destination to compare to source
                $Destination_Names = (Get-ChildItem -Path $destination_path | select name).name
                

                #check if source file exists in destination directory
                if ($Destination_Names -contains $source_name -eq $false)
                {

                    New-Item -ItemType Directory -Force -Path $destination_path | Out-Null              
                    Copy-Item $source_fullname $destination_path 
                    $processed_count = $processed_count + 1

                    $source_fullname | out-file -FilePath $processed_out_file -Append
                }
                else
                {
                    $duplicate_count = $duplicate_count + 1
                    Write-Output ("Duplicate: " + $source_name)

                   

                    $destination_fullname = $destination_path + "\" + $source_name
                    write-output $destination_fullname
                    
                    $detination_properties = Get-ItemProperty -path $destination_fullname
                    $destination_writetime = $detination_properties.LastWriteTime.Ticks
                    $destination_size = $detination_properties.Length


                    if ($source_writetime -eq $destination_writetime -and $source_size -eq $destination_size)
                    {
                        $source_fullname | out-file -FilePath $duplicates_delete_out_file -Append
                    }
                    else
                    {
                        $source_fullname | out-file -FilePath $duplicates_by_name_out_file -Append
                    }
                }

            }
            catch
            {
                Write-Output $error
               
                $errors_count = $errors_count + 1
                $source_fullname | out-file -FilePath $errors_out_file -Append
                $error.clear()
            }    
           

            write-output ("Processed: " + $processed_count)
            write-output ("Duplicate: " + $duplicate_count)
            write-output ("Error: " + $errors_count)
           
        }

write-output ("Total: " + ($processed_count + $duplicate_count + $errors_count))

Remove-PSDrive -Name P
