
Get-ChildItem -Path 'F:\log_shipping' | Where-Object {$_.LastWriteTime -le ((Get-Date).AddDays(-2)) } | Remove-Item -Force