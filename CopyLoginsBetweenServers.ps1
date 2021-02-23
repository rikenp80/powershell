   cls
   
    [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    

    $sqlCommand = New-Object System.Data.SqlClient.SqlCommand
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection

    $PrimaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ("infostore1")
    $SecondaryServer_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ("infostore2")
    
    $PrimaryServer_SQL.ConnectionContext.NonPooledConnection = "True"
    $PrimaryServer_SQL.ConnectionContext.LoginSecure=$false;
    $PrimaryServer_SQL.ConnectionContext.set_Login("replman")
    $PrimaryServer_SQL.ConnectionContext.Password = ""

   


    #create login on secondary if it does not exist on secondary
    foreach ($login in $PrimaryServer_SQL.Logins)
    {
    
        if ($login.Name -ne "sa" -and $login.Name -notlike "##*" -and $login.IsDisabled -eq $false -and $login.LoginType -eq "SqlLogin")
        {
        $login.Name
                #check if login on primary server exists on the seconday, if not, create it
                if ($login.Name -notin $SecondaryServer_SQL.Logins.Name)
                {
                    $LoginName = $login.name
                    $LoginType = $login.LoginType      
            $LoginName
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
    
