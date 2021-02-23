$Credential = Get-Credential
$credential.Password | ConvertFrom-SecureString | Set-Content E:\Powershell\Password.txt





#with key
$KeyFile = "C:\Powershell\PS_PWD.key"
$Key = New-Object Byte[] 32
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
$Key | out-file $KeyFile

$PasswordFile = "C:\Powershell\PWD.txt"
$KeyFile = "C:\Powershell\PS_PWD.key"
$Key = Get-Content $KeyFile
$Password = "" | ConvertTo-SecureString -AsPlainText -Force
$Password | ConvertFrom-SecureString -key $Key | Out-File $PasswordFile

#get login credentials
$username = "powershell"
$key = Get-Content ".\PS_PWD.key"

$password =  get-content ".\PWD.txt" | ConvertTo-SecureString -Key $key
$Credentials = New-Object System.Management.Automation.PSCredential ($userName,$password)
$password = $Credentials.GetNetworkCredential().Password
