cls

$file = Get-Content -Path "C:\Users\riken\Pictures\Transfer\logs\video\processed_2018_10_28_221528.txt"
$count = 0

foreach ($row in $file)
{
    $row

    Remove-Item $row

    $count = $count + 1
}

write-output $count