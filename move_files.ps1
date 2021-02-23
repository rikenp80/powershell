cls

[reflection.assembly]::loadfile( "C:\Windows\Microsoft.NET\Framework\v2.0.50727\System.Drawing.dll") 

$i = 0

New-PSDrive -Name P -PSProvider FileSystem -Root \\DISKSTATION\photo\Ashni
$source_path = "\\DISKSTATION\Other\TempPhotoTransfer\Photo"

		$files=Get-ChildItem $source_path -filter *.jpg -recurse
          
		ForEach ($file in $files)
		{              
                $source = $file.fullname
                
				$foo=New-Object -TypeName system.drawing.bitmap -ArgumentList $file.fullname				
				$date = $foo.GetPropertyItem(36867).value[0..9]
				$arYear = [Char]$date[0],[Char]$date[1],[Char]$date[2],[Char]$date[3]
				$arMonth = [Char]$date[5],[Char]$date[6]
				$arDay = [Char]$date[8],[Char]$date[9]
				$strYear = [String]::Join("",$arYear)
				$strMonth = [String]::Join("",$arMonth) 
				$strDay = [String]::Join("",$arDay)
			    
				$destination_directory = "P:\"
                $destination_folder = $strYear + "_" + $strMonth
                $destination_path = $destination_directory + $destination_folder + "\" + $strDay
                
                write-output $source
                write-output $destination_path
                
                New-Item -ItemType Directory -Force -Path $destination_path | Out-Null                
                Copy-Item $source $destination_path
                
                $i = $i + 1
                write-output $i
		}

Remove-PSDrive -Name P