$roots = get-psdrive -PSProvider FileSystem | select-object -ExpandProperty Root | sort-object -Descending
$retention_date = (get-date).AddDays(-50)

foreach ($root in $roots)
{
    write-output $root
   
    $FullName = get-childitem $root -recurse -include *.txt | select-object -ExpandProperty FullName | Where-Object {$_.LastWriteTime -le $retention_date}

    if ($FullName -eq $null) {continue}
    

    $MatchFiles = select-string -path $FullName -SimpleMatch "Server Maintenance Utility" | select -ExpandProperty path

    if ($MatchFiles -eq $null) {continue}

    
    foreach ($file in $MatchFiles)
    {
        write-output $file
        remove-item $file
    }

    if ($MatchFiles -ne $null) {break}
    
}