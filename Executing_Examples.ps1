#run in powershell
#generate log file path and name
$LogFileName = "C:\Powershell\logs\LogShipJobs_" + (Get-Date -format yyyy_MM_dd_HHmmss) + ".txt"

#run backup command
C:\Powershell\LogShipJobs.ps1 -ListenerName "UIPHA_List" -LS_Target "790524-GLS-EDW\UIP_CONFIG" -Backup_TargetPath "\\790524-GLS-EDW\log_shipping" | out-file $LogFileName -append

#delete old log files
Get-ChildItem -Path "C:\Powershell\logs" | Where-Object {$_.LastWriteTime -le (Get-Date).AddMonths(-1)} | Remove-Item -Force



#run in cmd
powershell.exe -file C:\Powershell\LogShipJobs.ps1 -ListenerName "UIPHA_List" -LS_Target "790524-GLS-EDW\UIP_CONFIG" -Backup_TargetPath "\\790524-GLS-EDW\log_shipping"


#run in cmd
powershell -ExecutionPolicy bypass -command "$LogFileName = (\"C:\Powershell\logs\LogShipJobs_\" + (Get-Date -format yyyy_MM_dd_HHmmss) + \".txt\"); C:\Powershell\LogShipJobs.ps1 -ListenerName \"UIPHA_List\" -LS_Target \"790524-GLS-EDW\UIP_CONFIG\" -Backup_TargetPath \"\\790524-GLS-EDW\log_shipping\" | out-file $LogFileName -append"


#log file clean up
Get-ChildItem -Path "C:\Powershell\logs" | Where-Object {$_.LastWriteTime -le (Get-Date).AddDays(-7)} | Remove-Item -Force
