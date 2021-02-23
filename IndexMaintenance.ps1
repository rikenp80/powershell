<#
Rebuild or Reorgnize indexes

example execution
C:\powershell\IndexMaintenance.ps1 -ServersList "889792-CHTRWFDB" -MaxDuration 120  -Index_Include "AK1APEMPSTAT" -DefragDB "eWFM_P_WFMCC"
#>


param
(
  $ServersList = (hostname),
  $DefragDB, #specific database to defragment, if left blank then all databases on the server will be processed
  $MaxDuration = 600, #duration for which the script will run in Minutes before exiting
  $Index_Include = "", #Specify the only indexes to be defragmented
  $Index_Exclude = "" #Specify which indexes should not be defragmented
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


    #replace spaces between Index names and split out from variables into a list
    $Index_Include = $Index_Include -replace ", ","," -replace " ,",","
    $Index_Exclude = $Index_Exclude -replace ", ","," -replace " ,",","

    $Index_Include_Split = $Index_Include.split(",")
    $Index_Exclude_Split = $Index_Exclude.split(",")

    
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
            if	($db.IsSystemObject -eq $false -and $db.Status -like "Normal*" -and $db.IsUpdateable -eq $true -and ($dbName -eq $DefragDB -or $DefragDB -eq $null))
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
                            
                            $IndexID = $index.id
							$IndexName = $index.name
                            $FillFactor = $index.fillfactor


                            if (
                                ($Index_Include_Split -ne "" -and $Index_Include_Split -contains $IndexName -eq $false) -or
                                ($Index_Exclude_Split -contains $IndexName -eq $true)
                               )                 
                            {continue}

                          

                            # calculate how long the script has been running for, if it exceeds the $MaxDuration parameter then end the script
                            $ScriptDuration = [math]::round((new-timespan $StartTime $index_start_time).TotalMinutes)
							
							if ($ScriptDuration -gt $MaxDuration) {return}


							
							# get fragmentation and page count for current index
							$query = "select avg_fragmentation_in_percent 'frag_pc', page_count 'pagecount', partition_number 'partition' from sys.dm_db_index_physical_stats(DB_ID('$dbName'), OBJECT_ID('$tbName'), $IndexID, NULL, 'LIMITED') where page_count > 0"
							
							$IndexStats = (Invoke-Sqlcmd -ServerInstance $server_instance -database $dbName -Query $query -QueryTimeout 65535)
                            
                            $PartitionCount = $IndexStats.frag_pc.count


                            #loop through each index/index partition
						    foreach($IndexParition in $IndexStats)
						    {
							
                                $Frag_Before = [math]::round($IndexParition.frag_pc,2)
							    $Pages = $IndexParition.pagecount
                                $Partition = $IndexParition.partition
							
							
							    Write-Output "$index_start_time - $dbName / Table= $tbName / Index= $IndexName / Partition= $Partition / Frag%= $Frag_Before / Pages= $Pages / FillFactor= $FillFactor"
							    Write-Output "ScriptDuration= $ScriptDuration"

							
							    # if fragmentation is above 15% and page count is greater than 1000 proceed to defragment
							    if ($Frag_Before -gt 15 -and $Pages -gt 1000)
							    {

								    # log start time of the defragmentation process
								    $DefragStartTime = get-date -format G
								    

								    # reorganize index that are fragmented between 15 and 30 percent, unless SQL Edition is Enterprise, in which case always rebuild online
								    if ($Frag_Before -le 30 -and $SQLEdition -notlike "Enterprise*")
								    {
                                        if($PartitionCount -gt 1)
                                            {$query = "ALTER INDEX $IndexName on $tbName REORGANIZE PARTITION=$Partition"}
                                        else
                                            {$query = "ALTER INDEX $IndexName on $tbName REORGANIZE"}

								    }


								    # rebuild index that are fragmented more than 30 percent
								    else
								    {
                                        $query = "ALTER INDEX $IndexName on $tbName REBUILD"
                                        
                                        
                                        #if index is partitioned and fillfactor is not 100% then add code to defrag specific partition
                                        if($PartitionCount -gt 1 -and $FillFactor -notin (0,100))
                                            {
                                                $query = $query + " PARTITION=$Partition"
                                            
                                                if($SQLEdition -like "Enterprise*") {$query = $query + " WITH (ONLINE=ON)"}
                                            }
                                        
                                        #otherwise defrag the whole index and if fillfactor=100 then change it to 90
                                        else
                                            {
                                                if($FillFactor -in (0,100)) {$FillFactor = 90}

                                                $query = $query + " WITH (FILLFACTOR = $FillFactor)"

                                                if($SQLEdition -like "Enterprise*") {$query = $query + ", (ONLINE=ON)"}
                                            }
                                    }


                                    #run the defrag query
                                    $query								
								    Invoke-Sqlcmd -ServerInstance $server_instance -database $dbName -Query $query -QueryTimeout 65535
								
                                    #output defrag duration
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
}


catch
{
    Write-Error $_

    [System.Environment]::Exit(1)
}