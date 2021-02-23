<#
Rebuild or Reorgnize indexes

example execution
C:\Powershell\IndexMaintenance.ps1 -ServersList "SWL2K12PMON1VM" -DefragDB "Infostore_CXP18_Prod" -MaxDuration 180
#>


param
(
  $ServersList,
  $DefragDB, #specific database to defragment, if left blank then all databases on the server will be processed
  $MaxDuration = 600 #duration for which the script will run in Minutes before exiting
)


# load assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") | Out-Null


if ($PSVersionTable.PSVersion.Major -le 2)
{
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
    
    
    if ( (Get-PSSnapin -Name SqlServerCmdletSnapin100 -ErrorAction SilentlyContinue) -eq $null )
    {
        Add-PsSnapin SqlServerCmdletSnapin100
    }
    
    if ( (Get-PSSnapin -Name SqlServerProviderSnapin100 -ErrorAction SilentlyContinue) -eq $null )
    {
        Add-PsSnapin SqlServerProviderSnapin100
    }
}
else
{
    # Import the SQLPS module so that the Invoke-SQLCMD command works
    Import-Module "sqlps" -DisableNameChecking
}


try
{    
	#output date
	$StartTime = get-date -format "yyyy-MM-dd HH:mm:ss"
	Write-Output ("=======" + $StartTime + "=======")

    
    # loop through all SQL Servers
	foreach($server_instance in $ServersList)
    {	
  
        Write-Output "`r`n#### $server_instance ####"

        #remove sql instance name from server name
        $Server = $server_instance.split("\")[0]

        #connect to sql server
        $Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($ServersList)
        $Server_SQL.ConnectionContext.StatementTimeout = 0

		#get sql edition
		$SQLEdition = $server_SQL.Edition
		$SQLEdition

		
        # loop through all DBs on server
        foreach($db in $Server_SQL.Databases)
        {
	        $dbName = $db.Name
            
            # check database status
            if	($db.Status -like "Normal*" -and $db.IsSystemObject -eq $False -and ($dbName -eq $DefragDB -or $DefragDB -eq $null))
			{	
				# get all tables in the DB
				$tbs = $db.Tables
				
				
				# loop through each table in database
				foreach($tb in $tbs)
				{
					
					#ignore system tables
					if ($tb.IsSystemObject -eq $False)
					{
						$tbName = $tb.Schema + "." + $tb.Name
						

						# loop through each index in table
						foreach($index in $tb.Indexes)
						{

							# log start time for current index
							$index_start_time = get-date -format "yyyy-MM-dd HH:mm:ss"
                            
                            # calculate how long the script has been running for, if it exceeds the $MaxDuration parameter then end the script
                            $ScriptDuration = [math]::round((new-timespan $StartTime $index_start_time).TotalMinutes)
							Write-Output "ScriptDuration= $ScriptDuration"
							if ($ScriptDuration -gt $MaxDuration) {return}


							$IndexID = $index.id
							$IndexName = $index.name
                            $FillFactor = $index.fillfactor
							
							
							# get fragmentation and page count for current index
							$query = "select max(avg_fragmentation_in_percent) 'frag_pc', SUM(page_count) 'pagecount' from sys.dm_db_index_physical_stats(DB_ID('$dbName'), OBJECT_ID('$tbName'), $IndexID, NULL, 'LIMITED')"
							
							$IndexStats = (Invoke-Sqlcmd -ServerInstance $server_instance -database $dbName -Query $query -QueryTimeout 65535)
							
							$Frag_Before = [math]::round($IndexStats.frag_pc,2)
							$Pages = $IndexStats.pagecount
							
							
							Write-Output "$index_start_time - $dbName / Table= $tbName / Index= $IndexName / Frag%= $Frag_Before / Pages= $Pages / FillFactor= $FillFactor"
							
							
							# if fragmentation is above 15% and page count is greater than 1000 proceed to defragment
							if ($Frag_Before -gt 15 -and $Pages -gt 1000)
							{
								# log start time of the defragmentation process
								$DefragStartTime = get-date -format G
								

								# reorganize index that are fragmented between 15 and 30 percent
								if ($Frag_Before -le 30)
								{
									$query = "ALTER INDEX $IndexName on $tbName REORGANIZE"
								}

								# rebuild index that are fragmented more than 30 percent
								else
								{
                                    $query = "ALTER INDEX $IndexName on $tbName REBUILD WITH (PAD_INDEX = OFF"

                                    if($FillFactor -eq 100 -or $FillFactor -eq 0) {$query = $query + ", FILLFACTOR = 90"}

									if($SQLEdition -like "Enterprise*") {$query = $query + ", ONLINE=ON"}

                                    $query = $query + ")"
								}
								
								
								$query
								
								Invoke-Sqlcmd -ServerInstance $server_instance -database $dbName -Query $query -QueryTimeout 65535
								
								$DefragEndTime = get-date -format G
								$DefragDuration = [math]::round((new-timespan $DefragStartTime $DefragEndTime).TotalMinutes)
								write-output ("Defrag Duration (Minutes): $DefragDuration `r`n")
								
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