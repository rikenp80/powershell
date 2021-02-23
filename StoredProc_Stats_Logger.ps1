<#
gather stats for lastest cached and executed procedures and update table on database to keep a historical record
also sends alerts if the current CPU is too high compared to historical averages

example execution:
H:\SSIS\PAT\Root\BatchFiles\StoredProc_Stats_Logger.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -NewCacheProcThreshold "15" -HighCPUThreshold "200" | Out-File -append -filepath "H:\SSIS\PAT\Root\BatchFiles\logs\StoredProc_Stats_Logger.txt"
#>


param
(
  $PSFilesPath,
    #procs cached in the last number minutes (as specified in this variable)
    #that will be compared to historical stats of the same proc to determine whether the CPU is too high
    #should be same value as the frequency of the job that runs this script
  $NewCacheProcThreshold,
    #percentage at which alerts will be sent if the new proc cpu is higher than historical average
  $HighCPUThreshold 
)

# Import the SQLPS module so that the Invoke-SQLCMD command works
Import-Module “sqlps” -DisableNameChecking

try
    {
    $error.clear()

    #write run time to log file
	$date = get-date
	Write-Output $date.ToShortDateString() $date.ToShortTimeString()

    
    #set root path for powershell scripts
    cd $PSFilesPath
    
    $sqlCommand = New-Object System.Data.SqlClient.SqlCommand
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection


	
	
    # Gets the list of active servers in the environment
    $ServersList = (.\GetServerList.ps1 | select-object -ExpandProperty ServerName)

    
    $total_data_table_count = 0

    
    #set start of html variable which will be used for emailing results
    $html = "<table table border=1>
                <tr>
                    <td><font face=arial size=2>Server</font></td>
                    <td><font face=arial size=2>DB</font></td>
                    <td><font face=arial size=2>Proc</font></td>
                    <td><font face=arial size=2>Percent_Change</font></td>
                    <td><font face=arial size=2>Executions_Per_Min</font></td>
                    <td><font face=arial size=2>Avg_CPU</font></td>
                </tr>"

    
    #loop through each sql server
    foreach ($Server in $ServersList)
    {
        
        #connect to the current sql server
	    $Server_SQL = New-Object Microsoft.SqlServer.Management.Smo.Server ($Server)
     
        $sqlConnection.ConnectionString = "Server=$Server;Database=master;Integrated Security=True;MultiSubnetFailover=True;ApplicationIntent=ReadOnly;"
        $sqlConnection.Open()
	    $sqlCommand.Connection = $sqlConnection
 
        
        #loop through each database on the SQL server
        foreach($db in $Server_SQL.Databases)
        {
            if((!$db.IsSystemObject) -and ($db.Status -like "Normal*"))
            {       
			    $db_name = $db.name
			

			    #query to get stats for the latest stored procedures being executed.
                #update and insert latest stats into StoredProcExecutionStats table
                #out put data to email where the latest cached plan stats are too high (more than double cpu time)
                $query = 
                
                    "
                    IF OBJECT_ID('tempdb..##new_data') IS NOT NULL DROP TABLE ##new_data

                    CREATE TABLE ##new_data
		                            (
		                            database_name			VARCHAR(100)	NOT NULL,
		                            proc_name				VARCHAR(100)	NOT NULL,
		                            average_cpu_time		INT				NULL,
		                            average_logical_reads	INT				NULL,
		                            average_logical_writes	INT				NULL,
		                            average_physical_reads	INT				NULL,
		                            cached_time				DATETIME2(3)	NULL,
                                    last_execution_time     DATETIME2(3)	NULL,
		                            execution_count			INT				NOT NULL,
                                    executions_per_min      INT             NOT NULL,
		                            query_plan				XML				NULL
		                            )

                    INSERT INTO ##new_data
                    SELECT
                        '$db_name',
                        o.name,
                        qs.total_worker_time/qs.execution_count 'average_cpu_time',
                        qs.total_logical_reads/qs.execution_count 'average_logical_reads',
                        qs.total_logical_writes/qs.execution_count 'average_logical_writes',
                        qs.last_physical_reads/qs.execution_count 'average_physical_reads',
                        qs.cached_time,
                        qs.last_execution_time,
                        qs.execution_count,
                        CAST((ROUND(CAST(qs.execution_count AS DECIMAL(9,0))/CAST((DATEDIFF(ss,qs.cached_time,qs.last_execution_time)) AS DECIMAL(9,0))*60,0)) as INT),
                        qp.query_plan
                    from sys.dm_exec_procedure_stats (nolock) as qs
                        INNER JOIN $db_name.sys.objects (nolock) o ON qs.[object_id] = o.[object_id]
                        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) as st
                        CROSS APPLY sys.dm_exec_query_plan (qs.plan_handle) as qp
                    where qs.last_execution_time > DATEADD(MI,-1,getdate())
                        AND o.name not like 'sp_ms%'
                        AND o.[type] = 'P'
                        AND qs.execution_count > 0
                        AND DATEDIFF(ss,qs.cached_time,qs.last_execution_time) > 0



                    /*--------------------------------------------------------------------------
                    update stats for existing cached procs
                    --------------------------------------------------------------------------*/				
				    UPDATE s
				    SET average_cpu_time = n.average_cpu_time,
					    average_logical_reads = n.average_logical_reads,
					    average_logical_writes = n.average_logical_writes,
					    average_physical_reads = n.average_physical_reads,
					    last_execution_time = n.last_execution_time,
					    execution_count = n.execution_count,
                        executions_per_min = n.executions_per_min
				    FROM SQLMaint.dbo.StoredProcExecutionStats s
					    INNER JOIN ##new_data n ON s.database_name = n.database_name COLLATE SQL_Latin1_General_CP1_CI_AS
												    AND s.proc_name = n.proc_name COLLATE SQL_Latin1_General_CP1_CI_AS
												    AND s.cached_time = n.cached_time



                    /*--------------------------------------------------------------------------
                    insert newly cached procs into table
                    --------------------------------------------------------------------------*/
				    INSERT INTO SQLMaint.dbo.StoredProcExecutionStats
                     (database_name,proc_name,average_cpu_time,average_logical_reads,average_logical_writes,average_physical_reads,cached_time,last_execution_time,execution_count,executions_per_min,query_plan)
                    SELECT *
                    FROM ##new_data n
                        WHERE NOT EXISTS (SELECT * FROM SQLMaint.dbo.StoredProcExecutionStats s WHERE s.database_name = n.database_name COLLATE SQL_Latin1_General_CP1_CI_AS
                                                                                                    AND s.proc_name = n.proc_name COLLATE SQL_Latin1_General_CP1_CI_AS
                                                                                                    AND s.cached_time = n.cached_time)


																								
                    /*--------------------------------------------------------------------------
                    output results to be emailed
                    --------------------------------------------------------------------------*/
                    SELECT database_name,
                            proc_name,
                            cast((CAST(current_average_cpu AS DECIMAL(19,2))/all_time_average_cpu) * 100 as INT) 'percent_change',
                            executions_per_min, current_average_cpu
                    FROM
                    (
	                    SELECT s.database_name,
                                s.proc_name,
                                n.executions_per_min,
                                n.average_cpu_time 'current_average_cpu',
                                avg(cast(s.average_cpu_time as decimal(19,2))) 'all_time_average_cpu'
	                    FROM SQLMaint.dbo.StoredProcExecutionStats s inner join ##new_DATA n ON s.database_name = n.database_name COLLATE SQL_Latin1_General_CP1_CI_AS 
																						    AND s.proc_name = n.proc_name COLLATE SQL_Latin1_General_CP1_CI_AS
                                                                                            AND s.cached_time <> n.cached_time
                        WHERE n.cached_time > DATEADD(MI,-$NewCacheProcThreshold,getdate())
                                AND s.average_cpu_time > 0
                                AND (
									n.average_cpu_time * n.executions_per_min >= 1000000
									OR
									(n.average_cpu_time >= 1000000 AND n.executions_per_min = 0)
									)
	                    GROUP BY s.database_name, s.proc_name, n.executions_per_min, n.average_cpu_time
                        --only return rows that get cached less than 6 times a day
                        HAVING CAST(COUNT(DISTINCT s.cached_time) AS DECIMAL(9,2)) / DATEDIFF(DD, MIN(s.cached_time), GETDATE()) < 6
                    ) a
                    WHERE (CAST(current_average_cpu AS DECIMAL(19,2))/CAST(all_time_average_cpu AS DECIMAL(19,2))) * 100 > $HighCPUThreshold
                    "


                #populate data table
			    $sqlCommand.CommandText = $query
            
                $dataset = New-Object System.Data.DataSet

                $data_adapter = new-object "System.Data.SqlClient.SqlDataAdapter" ($query, $sqlConnection)
		        $data_adapter.Fill($dataset) | out-null
                                
    		    $data_table = new-object System.Data.DataTable "CPUStats"
		        $data_table = $dataset.Tables[0]


                
                #log cumulative total of row count in data table
		        $total_data_table_count += $data_table.Rows.Count

                
                #add new data rows to html variable to prepare for output
                if ($data_table.Rows.Count -gt 0)
                {
                    foreach ($row in $data_table.Rows)
                    { 
                        $html += "<tr>
                                    <td><font face=arial size=2>" + $Server + "</font></td>
                                    <td><font face=arial size=2>" + $row[0] + "</font></td>
                                    <td><font face=arial size=2>" + $row[1] + "</font></td>
                                    <td><font face=arial size=2>" + $row[2] + "</font></td>
                                    <td><font face=arial size=2>" + $row[3] + "</font></td>
                                    <td><font face=arial size=2>" + $row[4] + "</font></td>
                                   </tr>"
                    }                                                
                }
                write-output "$Server $db_name"            
                write-output $data_table
            }        
        }    
        
        #close current sql server connection
	    $sqlConnection.Close()   
    }


    #end the html variable with table tag
    $html += "</table>"



    # if sum of data table rows is more than 0 then send email
    if ($total_data_table_count -ne 0)
    {
        # Send the email
        $command = ".\SendEmail.ps1 –Subject ""Stored Proc CPU too high"" -Body ""$html"" -bodyashtml"
        Invoke-Expression $command	
    }
}


catch
{
	Write-Output $error 
	if ($error -ne $null)
	{
		$command = ".\SendEmail.ps1 –Subject ""Stored Proc Stats Logger Failed $Server $db_name"" -Body ""$error"""
		Invoke-Expression $command
	}
	$error.clear()
}