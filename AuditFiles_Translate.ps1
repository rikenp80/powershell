<#
Translate SQL Audit files to csv files using bcp and move the files into an archive folder based on the day of the file

example execution
C:\Powershell\AuditFiles_Translate.ps1 -SourceDir 'D:\AuditLogs' -TargetDir 'D:\AuditLogs\TranslatedFiles' -ArchiveDir 'D:\AuditLogs\Archive' -RetentionMonths 2
#>


param
(
    $SourceDir,
    $TargetDir,
    $ArchiveDir,
    $RetentionMonths = 3
)



#clean up old translated files
$RetentionDate = (get-date).AddMonths(-$RetentionMonths).ToString("yyyyMMdd")
$RetentionDate

$TranslatedFiles = Get-ChildItem -Path $TargetDir


foreach($File in $TranslatedFiles)
{
    $FileDate = ($File.Name).Replace(".csv","")
    $FullName = $File.FullName
  

    if ($FileDate -lt $RetentionDate)
    {
        Remove-Item $FullName -Force

        $FullName
    }
}



#source files to be translated
$SourceFiles = Get-ChildItem *.sqlaudit* -Path $SourceDir | Select-Object -ExpandProperty Name



foreach($SourceFile in $SourceFiles)
{    

    $SourceFileFullPath = $SourceDir + "\" + $SourceFile
    $FileTimeStamp = ((Get-Item $SourceFileFullPath).LastWriteTime).ToString("yyyyMMdd_HHmmss")
    $FileDay = ((Get-Item $SourceFileFullPath).LastWriteTime).ToString("yyyyMMdd")


    try
    {
        try
        {
            #check if the current file is in use, if it is then an error will be thrown so move to next file in thh CATCH block
            [IO.File]::OpenWrite($SourceFileFullPath).close()
        }
        catch
        {continue}
    

        #set the query that will be used to extract data from the audit files
        $Query = "SELECT af.event_time,aa.name 'audit_action',af.session_id,af.server_principal_name,af.server_instance_name,af.database_name,ct.class_type_desc,af.object_name, LEFT(REPLACE(REPLACE(REPLACE(af.[statement], CHAR(13), ''), CHAR(9), ''), CHAR(10), ''),2000) 'statement' FROM sys.fn_get_audit_file('" + $SourceFileFullPath + "', NULL, NULL) af LEFT JOIN sys.dm_audit_class_type_map ct ON af.class_type = ct.class_type LEFT JOIN sys.dm_audit_actions aa ON af.action_id = aa.action_id AND aa.class_desc = ct.securable_class_desc LEFT JOIN sys.server_principals sp ON af.server_principal_id = sp.principal_id LEFT JOIN sys.database_principals dp ON af.[database_principal_id] = dp.principal_id"


        #set the target locaton of the translated files
        $TargetFile = $FileTimeStamp + ".csv"
        
        $TargetFileFullPath = $TargetDir + "\" + $TargetFile

        $SourceFile
        $TargetFileFullPath

        #set the bcp command and execute
        $bcp = "bcp """ + $Query + """ queryout "+ $TargetFileFullPath +" -c -t"","" -T -S " + $env:computername
        Invoke-Expression -command $bcp


        #move processed audit file to the Archive folder
        $ArchiveDir_Day = $ArchiveDir + "_" + $FileDay

        If (-not(Test-Path $ArchiveDir_Day)) {New-Item -ItemType "directory" -Path $ArchiveDir_Day}
        
        Move-Item $SourceFileFullPath $ArchiveDir_Day

        $ArchiveDir_Day = ""
    }


    catch
    {
        Write-Error $_

        [System.Environment]::Exit(1)
    }
}
