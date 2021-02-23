Install-Module -Name AWSPowerShell
or
Import-Module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"

Set-AWSCredential -AccessKey AKIAJ65TDQCUAGUSBNOQ -SecretKey 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 -StoreAs cloudops-dba
Set-AWSCredential -AccessKey AKIAJYXQNL7UKABBDNJQ -SecretKey 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 -StoreAs cloudops-dba


Set-AWSCredential -ProfileName cloudops-dba
Get-AWSCredential -ListProfileDetail


Write-S3Object -BucketName cloudops-dba-aspect/Backups/LAS/metering2/cassius2011 -File "H:\Backup\cassius2011\cassius2011_Diff_2018_05_03_050003.BAK" -ProfileName cloudops-dba

cls
$test = Get-S3Object -BucketName cloudops-dba-aspect -Key "Backups/LAS/metering2/cassius2011" -ProfileName "cloudops-dba" | Select Key -ExpandProperty Key
$test.Split("/")[($test.Split("/").count)-1]