<#
Archive files from local server to S3 bucket

example execution
C:\Powershell\MoveFilesToBucket.ps1 -ServerName "infostore2" -Bucket_EndpointURL "http://s3-us.ash.aspect-cloud.net" -ProfileName "cloudian" -BucketName "db-backup1" -Local_BackupPath "F:\Backups" -Cloud_BackupPath "ash/infostore2"
#>

param
(
    $ServerName,
    $Bucket_EndpointURL,
    $ProfileName,
    $BucketName,
    $Local_BackupPath,
    $Cloud_BackupPath,
    $MaxDuration = 120 #duration for which the script will run in Minutes before exiting
)


try
{    
    #output date
	$ScriptStartTime = get-date -format "yyyy-MM-dd HH:mm:ss"
    Write-Output ("=======" + $ScriptStartTime + "=======")
    
    $DB_BackupFolders = Get-ChildItem -Path $Local_BackupPath | Where-Object {$_.PSIsContainer} | Select-Object Name -ExpandProperty Name
    

    ForEach ($DB_BackupFolder in $DB_BackupFolders)
    {

		$Full_Local_Path = $Local_BackupPath + "\" + $DB_BackupFolder
   
		$Local_Files = Get-ChildItem -Path $Full_Local_Path -include *.BAK,*.TRN -exclude *DIFF.BAK -Recurse | Where-Object {$_.LastWriteTime -gt $FileDate }
		if ($Local_Files -eq $null) {continue}
		
		$FullCloudPath = $Cloud_BackupPath + "/" + $DB_BackupFolder

		
        # set the Bucket Name for Write-S3Object command
        $BucketNameForWrites = "s3://" + $BucketName + "/" + $FullCloudPath + "/"
        

        # loop thourgh each backup file on the local server in the current directory
        ForEach ($Local_File in $Local_Files)
        {
           
            $Local_File_FullName = $Local_File.FullName
           
            
            #log start time of archiving
            $StartTime = get-date -format G
            Write-Output "$StartTime - $Local_File_FullName"

            aws --profile=$ProfileName --endpoint-url=$Bucket_EndpointURL s3 mv $Local_File_FullName $BucketNameForWrites --no-progress

            #log end time of archiving and output duration
            $EndTime = get-date -format G
            $Duration = [math]::round((new-timespan $StartTime $EndTime).TotalMinutes)
            write-output ("Duration (Minutes): $Duration `r`n")


            # calculate how long the script has been running for, if it exceeds the $MaxDuration parameter then end the script
            $ScriptDuration = [math]::round((new-timespan $ScriptStartTime $EndTime).TotalMinutes)

            if ($ScriptDuration -gt $MaxDuration) {return}

        }
    }
}



catch
{
    Write-Error $_

    [System.Environment]::Exit(1)
}