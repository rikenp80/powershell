<#
delete log files older than the specified number of months

example execution:
H:\SSIS\Prod\Root\BatchFiles\DeleteLogFiles.ps1 -LogFileDirectory "H:\SSIS\DEV\Root\BatchFiles\logs" -FileRetentionMonths 3
#>


param
(
  $LogFileDirectory,
  $FileRetentionMonths
)


try
{
	$error.clear()

    $RetentionDate = (Get-Date).AddMonths(-$FileRetentionMonths) 

    Get-ChildItem -Path $LogFileDirectory -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $RetentionDate } | Remove-Item -Force
}



catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Deleting Log Files Failed in $LogFileDirectory"""
		Invoke-Expression $command
	}
}
