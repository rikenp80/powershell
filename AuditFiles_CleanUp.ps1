<#
compress archive folders older than the current day
delete the source files and folder
delete old zip files

example execution
C:\Powershell\AuditFiles_CleanUp.ps1 -AuditRootDir 'D:\AuditLogs' -RetentionMonths 1
#>


param
(
    $AuditRootDir,
    $RetentionMonths
)

Add-Type -assembly "system.io.compression.filesystem"


$CurrentDay = (get-date).ToString("yyyyMMdd")


#get all Archive folders older than $CurrentDay that need to be zipped
$FoldersToZip = Get-ChildItem -Path ($AuditRootDir + "\Archive_*") | Where-Object {$_.PSIsContainer -and $_.Name -notlike ("*_" + $CurrentDay)} | Select -ExpandProperty FullName


foreach($SourceFolder in $FoldersToZip)
{    
    $DestinationZip = $SourceFolder + ".zip"

    write-output "$SourceFolder -> $DestinationZip"
    
    [io.compression.zipfile]::CreateFromDirectory($SourceFolder, $DestinationZip)

    Remove-Item -Path $SourceFolder -Force -Recurse
}



#clean up old zip files
$RetentionDate = (get-date).AddMonths(-$RetentionMonths).ToString("yyyyMMdd")
$RetentionDate

$ZipFiles = Get-ChildItem -Path $AuditRootDir | Where-Object {$_.Extension -eq ".zip"} | Select -ExpandProperty FullName

foreach($File in $ZipFiles)
{
    $FileDate = $File.Substring($File.IndexOf("_")+1, 8)
    $FileDate

    if ($FileDate -lt $RetentionDate)
    {
        $File   

        Remove-Item $File -Force
    }
}