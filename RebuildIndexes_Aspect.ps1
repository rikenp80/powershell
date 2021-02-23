<#
Rebuild or Reorgnize indexes

example execution
C:\Powershell\IndexMaintenance.ps1 -ServersList "SWL2K12PMON1VM"
#>


param
(
  $ServersList
)

$Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($ServersList)

try
{    

	#output date
	Write-Output ("=======" + (get-date -format "yyyy-MM-dd HH:mm:ss") + "=======")

    
    # loop through all SQL Servers
	foreach($server_instance in $ServersList)
    {	
  
        Write-Output "`r`n#### $server_instance ####"

        #remove sql instance name from server name
        $Server = $server_instance.split("\")[0]

        #connect to sql server
        $Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($ServersList)
        $Server_SQL.ConnectionContext.StatementTimeout = 0




        foreach($db in $Server_SQL.Databases)
        {
	        $dbName = $db.Name
    
            if	($db.Status -like "Normal*" -and $db.IsSystemObject -eq $False)
					
		        {	
                    Write-Output "DB = $dbName"

			        #get all tables in the DB
			        $tbs = $db.Tables
                    
					
			        foreach($tb in $tbs)
			        {
				        $tbName = $tb.Name
                        
                        foreach($index in $tb.Indexes)
                        {
                            $index.EnumFragmentation() | foreach {
                        
                                $index_type = $_.IndexType
                                $Frag_Before = $_.AverageFragmentation
                                $Pages = $_.Pages

                                        
                                if ($Frag_Before -gt 15 -and $Frag_Before -le 15 -and $Pages -gt 1000)
                                {
                                    Write-Output "Reorg / $tbName / $index / $index_type / $Frag_Before / $Pages"

                                    $index.Reorganize()
                                }

                                elseif ($Frag_Before -gt 30 -and $Pages -gt 1000)
                                {
                                    Write-Output "Rebuild / $tbName / $index / $index_type / $Frag_Before / $Pages"

                                    $index.Rebuild()
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
    Write-Error $_

    [System.Environment]::Exit(1)
}