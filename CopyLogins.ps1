<#
Copy new logins and Delete removed logins from Primary Availability Group server to all Secondary servers

example execution:
H:\SSIS\PAT\Root\BatchFiles\CopyLogins.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -AvailabilityGroupName "AG"
#>


param
(
  $PSFilesPath,
  $AvailabilityGroupName
)


try
{
	$error.clear()


    #write run time to log file
	$date = get-date
	Write-Output $date.ToShortDateString() $date.ToShortTimeString()

    
    #change directory to where the powershell script reside
    cd $PSFilesPath
    

    $sqlCommand = New-Object System.Data.SqlClient.SqlCommand
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection


    # Gets the list of active servers in the environment
    $ServersList = (.\GetServerList.ps1 | select-object -ExpandProperty ServerName)


    #determine primary and secondary AG servers
    $PrimaryServer = (.\GetAlwaysOnServers.ps1 -ServerType Primary -AvailabilityGroupName $AvailabilityGroupName -ServersList $ServersList)
    $PrimaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($PrimaryServer)

    $SecondaryServer = @(.\GetAlwaysOnServers.ps1 -ServerType Secondary -AvailabilityGroupName $AvailabilityGroupName -ServersList $ServersList)


    write-output "Primary Server: $PrimaryServer"
    write-output "Secondary Servers: $SecondaryServer"


    #drop login on secondary if it does not exist on primary
    $PrimaryLogins = @()
    $PrimaryLogins = $PrimaryServer_SQL.Logins

    foreach ($Server in $SecondaryServer)
    {
        $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)

        #loop through each login on secondary server, if it does not exist on primary, then drop it
        foreach ($SecondaryLogin in $SecondaryServer_SQL.Logins.Name)
        {                
        
            if ($SecondaryLogin -notin $PrimaryLogins.Name)
            {
                Write-Output "Drop Login: $SecondaryServer_SQL $SecondaryLogin"
                $SecondaryServer_SQL.Logins[$SecondaryLogin].Drop()
            }
        }
    }



    #create login on secondary if it does not exist on secondary
    foreach ($login in $PrimaryServer_SQL.Logins)
    {
        if ($login.Name -ne "sa" -and $login.Name -notlike "##*")
        {
        
            foreach ($Server in $SecondaryServer)
            {           

                $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)
                write-output $SecondaryServer_SQL
                #check if login on primary server exists on the seconday, if not, create it
                if ($login.Name -notin $SecondaryServer_SQL.Logins.Name)
                {
                    $LoginName = $login.name
                    $LoginType = $login.LoginType      
            
                    $new_login = New-Object Microsoft.SqlServer.Management.Smo.Login $SecondaryServer_SQL, $LoginName
                    $new_login.LoginType = $LoginType
                                
				    Write-Output "Create Login: $Server $LoginName $LoginType"
				    

                    #copy SID to the new login
                    $new_login.set_Sid($login.get_Sid())

				
				    #create sql login
                    if ($LoginType -eq "SqlLogin")
                    {
                        if ($login.PasswordPolicyEnforced) {$new_login.PasswordPolicyEnforced = $true}
	    	            if ($login.PasswordExpirationEnabled) {$new_login.PasswordExpirationEnabled = $true}
                        #if ($login.MustChangePassword) {$new_login.MustChangePassword = $true}

    
			            $Query ="	SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') 
				                    AS varbinary (256)), 1) AS nvarchar(max)) as hashedpass
                                    FROM sys.server_principals
				                    WHERE name = '$LoginName'
							    "
			
			            $PasswordHash = ($PrimaryServer_SQL.databases['master'].ExecuteWithResults($Query)).Tables.hashedpass

                        $new_login.Create($PasswordHash, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
                    }

				    #create windows login
                    elseif ($LoginType -in ("WindowsUser", "WindowsGroup"))
                    {
                        $new_login.Create()
                    }

                    
                
                    #if login is disabled on primary then set it on secondaries
                    if ($login.IsDisabled) {$new_login.Disable()}
                    if ($login.IsLocked) {$new_login.IsLocked = $true}
                    $new_login.alter()


                    #copy roles for the newly copied logins
                    foreach ($role in $PrimaryServer_SQL.roles)
                    {
                        if ($role.EnumMemberNames() -contains $login.name)
					    {
						    if ($SecondaryServer_SQL.roles[$role.name] -ne $null)
						    {
							    $new_login.AddToRole($role.name)
						    }
					    }
                    }
                }
            }
        }
    }
}

catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Copy Logins failed on $Server $LoginName $LoginType"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}