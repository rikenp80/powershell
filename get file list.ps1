$output = Get-ChildItem "\\tjgsqlp703\sqllivebackups\Daily Backups\Hub\TJGSQLP703\Log\TotalCV" -force | Where-Object {$_.LastWriteTime -ge "06/11/2015 16:38:00"} | Select FullName
$output | Out-File D:\temp\restorelog.txt -width 500

Get-ChildItem -recurse -Path 'D:\' -Include *df | Where-Object {$_.FullName -match $FileName } | select-object FullName