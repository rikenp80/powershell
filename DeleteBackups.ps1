<#
Delete Old S3 backups based on retention values specified in parameters

example execution
C:\Powershell\DeleteBackups.ps1 -ServerName "infostore1" -ProfileName "cloudops-dba" -BucketName "cloudops-dba-aspect" -Log_Diff_Retention_Days 14 -Full_Retention_Days 2555 -NoOfWeeklyFullRetentions 18 -S3_BackupPath "Backups/LAS/infostore1"
#>

param
(
    $ProfileName,
    $BucketName,
    $Log_Diff_Retention_Days = 14,
    $Full_Retention_Days = 2555,
    $NoOfWeeklyFullRetentions = 18,
    $S3_BackupPath
)

Import-Module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"

try
{

    # Set at what age LOG and DIFF backups are deleted and delete if they have passed the retention period
    $Log_Diff_Retention_Date = [Datetime](Get-Date).ToShortDateString()
    $Log_Diff_Retention_Date = $Log_Diff_Retention_Date.AddDays(-$Log_Diff_Retention_Days)
    $Log_Diff_Retention_Date



    $S3Files = Get-S3Object -BucketName $BucketName -KeyPrefix $S3_BackupPath -ProfileName $ProfileName | Where-Object {$_.LastModified -le $Log_Diff_Retention_Date -and ($_.Key -like "*_Diff*" -or $_.Key -like "*_Log*")} | Select -ExpandProperty Key


	if ($S3Files -ne $null)
	{
		ForEach ($S3File in $S3Files)
		{
		   $S3File

		   Remove-S3Object -BucketName $BucketName -Key $S3File -ProfileName $ProfileName -Force
		}
	}




    $objects = Get-S3Object -BucketName $BucketName -KeyPrefix $S3_BackupPath -ProfileName $ProfileName

    $paths=@()

    foreach($object in $objects) 
    {
        $path = split-path $object.Key -Parent 

        $paths += $path
    }

    $paths = $paths | select -Unique




    $WeekEnd_DayOfWeek = $Log_Diff_Retention_Date.dayofweek.value__
    if ($WeekEnd_DayOfWeek -eq 0) {$WeekEnd_DayOfWeek = 7}

    $Week_End = $Log_Diff_Retention_Date.AddDays(-($WeekEnd_DayOfWeek)+1)
    $Week_Start = $Week_End.AddDays(-7)



    for ($i=1; $i -le $NoOfWeeklyFullRetentions; $i++) 
    {

        $Week_Start
        $Week_End


        foreach($path in $paths)
        { 
            $path = $path + "\"

            if ($path -notlike $S3_BackupPath.replace("/","\") + "*") {continue}

            $S3Files = Get-S3Object -BucketName $BucketName -KeyPrefix $path -ProfileName $ProfileName | Where-Object {$_.LastModified -ge $Week_Start -and $_.LastModified -lt $Week_End -and $_.Key -like "*_Full*"} | sort LastModified -Desc | Select -Skip 1 -ExpandProperty Key
			
			if ($S3Files -eq $null) {continue}
			
            foreach($S3File in $S3Files) 
            {
                $S3File

                Remove-S3Object -BucketName $BucketName -Key $S3File -ProfileName $ProfileName -Force
            }
        }

        $Week_End = $Week_Start
        $Week_Start = $Week_Start.AddDays(-7)

    }





    # Set at what age FULL backups are deleted and delete if they have passed the retention period
    $Full_Retention_Date = [Datetime](Get-Date).ToShortDateString()
    $Full_Retention_Date = $Full_Retention_Date.AddDays(-$Full_Retention_Days)                        
    $Full_Retention_Date


    $S3Files = Get-S3Object -BucketName $BucketName -KeyPrefix $S3_BackupPath -ProfileName $ProfileName | Where-Object {$_.LastModified -le $Full_Retention_Date -and $_.Key -like "*_Full*"} | Select -ExpandProperty Key
	
	if ($S3Files -ne $null)
	{
		ForEach ($S3File in $S3Files)
		{
			$S3File

			Remove-S3Object -BucketName $BucketName -Key $S3File -ProfileName $ProfileName -Force -
		}
	}
}



catch
{
    Write-Error $_

    [System.Environment]::Exit(1)
}