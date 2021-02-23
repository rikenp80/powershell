param 
( 
    [string]$Subject,
    [string]$Body
)

    $smtpserver = "tjgmail.app.tjgprod.ds"
    $from = "powershell@totaljobsgroup.com"
    $to = "TJGDLTotalJobsOps-DBAs@totaljobsgroup.com"

    Send-MailMessage -smtpserver $smtpServer -from $from -to $to -subject $subject -body $body -bodyashtml

    Write-Output "Sending Email"