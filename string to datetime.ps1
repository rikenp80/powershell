cls

$lastboot = (Get-WmiObject -class Win32_OperatingSystem -ComputerName 'mtr116').LastBootUpTime 
$lastboot = $lastboot.Substring(0,14)
write-output $lastboot


$d = "{0:G}" -f [datetime]::ParseExact($lastboot, "yyyyMMddHHmmss", $null)
write-output $d