cls
$source_path =  "C:\Users\riken\Downloads\"

$files = dir $source_path -recurse | where {$_.extension -in ".jpg",".png",".jpeg" -and $_.PsIsContainer -eq $false } | Select Fullname -ExpandProperty Fullname

#$files = gci -Recurse $source_path -Filter *.jpg, *.png | Select Fullname -ExpandProperty Fullname
#$files

New-Item -Path $source_path -Name "new" -ItemType "directory"

$target_path =  $source_path + "\new\"

foreach($file in $files)
{    
   write-output $file
   Copy-Item -Path $file -Destination $target_path
}
