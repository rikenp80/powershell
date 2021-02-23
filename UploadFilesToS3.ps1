<#
Archive files from local server to S3 bucket

example execution
C:\Powershell\UploadFilesToS3.ps1 -ServerName "metering2" -ProfileName "cloudops-dba" -BucketName "cloudops-dba-aspect" -Region "us-east-1" -LookbackDays 2 -Local_BackupPath "H:\Backup" -S3_BackupPath "Backups/LAS/metering2"
#>

param
(
    $ServerName,
    $ProfileName,
    $BucketName,
	$Region,
    $LookbackDays = 2,
    $Local_BackupPath,
    $S3_BackupPath
)

Import-Module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"

try
{    

    $FileDate = (get-date).AddDays(-$LookbackDays)

    $DB_BackupFolders = Get-ChildItem -Path $Local_BackupPath | Where-Object {$_.PSIsContainer} | Select-Object Name -ExpandProperty Name 

    ForEach ($DB_BackupFolder in $DB_BackupFolders)
    {

		$Full_Local_Path = $Local_BackupPath + "\" + $DB_BackupFolder
   
		$Local_Files = Get-ChildItem -Path $Full_Local_Path -include *.BAK,*.TRN -Recurse | Where-Object {$_.LastWriteTime -gt $FileDate }
		if ($Local_Files -eq $null) {continue}
		
		$Full_S3_Path = $S3_BackupPath + "/" + $DB_BackupFolder
   
   
        # get all files in the current directory from S3
		$S3Files = Get-S3Object -BucketName $BucketName -Region $Region -Key $Full_S3_Path -ProfileName $ProfileName | Select Key -ExpandProperty Key
		
		if ($S3Files -ne $null)
		{
			#extract only the file name part of the Get-S3Object output
			$S3_FileName = $S3Files | foreach-object {
							$_.Split("/")[($_.Split("/").count)-1] }
		}
		
		
        # set the Bucket Name for Write-S3Object command
        $BucketNameForWrites = $BucketName + "/" + $Full_S3_Path


        # loop thourgh each backup file on the local server in the current directory
        ForEach ($Local_File in $Local_Files)
        {
            
            $Local_File_Name = $Local_File.Name
            $Local_File_FullName = $Local_File.FullName


            # if file does not exist in S3 then upload
            if ($S3_FileName -contains $Local_File_Name -eq $false)
            {
                #log start time of archiving
                $StartTime = get-date -format G

                Write-Output "$StartTime - Writing to $BucketNameForWrites `r`n File = $Local_File_FullName"
                Write-S3Object -BucketName $BucketNameForWrites -Region $Region -File $Local_File_FullName -ProfileName $ProfileName

                #log end time of archiving and output duration
                $EndTime = get-date -format G
                $Duration = [math]::round((new-timespan $StartTime $EndTime).TotalMinutes)
                write-output ("Archive Duration (Minutes): $Duration `r`n")

            }
        }
    }
}



catch
{
    Write-Error $_

    [System.Environment]::Exit(1)
}