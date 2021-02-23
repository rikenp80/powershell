<#
Check drive space on all server. if free space is less than $FreeThreshold and percentage free space is less than $PercentFreeThreshold then send an email

example execution:
H:\SSIS\PAT\Root\BatchFiles\LowDriveSpace.ps1 -PSFilesPath "H:\SSIS\PAT\Root\BatchFiles" -FreeThreshold 100 -PercentFreeThreshold 30
#>


param
(
  $PSFilesPath,
  $FreeThreshold = 100,
  $PercentFreeThreshold = 30  
)


cd $PSFilesPath


#Define Table and Columns for storing data
$table = New-Object system.Data.DataTable "DriveSpace"
$col1 = New-Object system.Data.DataColumn Server,([string])
$col2 = New-Object system.Data.DataColumn Name,([string])
$col3 = New-Object system.Data.DataColumn VolumeName,([string])
$col4 = New-Object system.Data.DataColumn DiskSize_GB,([decimal])
$col5 = New-Object system.Data.DataColumn FreeSpace_GB,([decimal])
$col6 = New-Object system.Data.DataColumn pc_Free,([decimal])

$table.columns.add($col1)
$table.columns.add($col2)
$table.columns.add($col3)
$table.columns.add($col4)
$table.columns.add($col5)
$table.columns.add($col6)


    
# Gets the list of active servers in the environment
$ServersList = (.\GetServerList.ps1 | select-object -ExpandProperty ServerName)


foreach($server in $ServersList)
{	
	# get server name without instance name
	$srv_split = $server.split("\")	
	$srv_name = $srv_split[0]
        

    #if server already exists in the table then ignore
    if ($table.Server -contains $srv_name -eq $true) {continue}


    #check if server is up
	$PingStatus = Gwmi Win32_PingStatus -Filter "Address = '$srv_name'"|Select-Object StatusCode


	if($PingStatus.StatusCode -eq 0)
    {
        $data = Get-WmiObject -ComputerName $srv_name -Class Win32_LogicalDisk |
	        Where-Object {$_.DriveType -notin (5,2) -and ($_.FreeSpace/1GB) -lt $FreeThreshold -and ($_.FreeSpace/$_.Size*100) -lt $PercentFreeThreshold}|
            Sort-Object -Property Name |             
            Select-Object Name, VolumeName,
		        `
                @{"Label"="DiskSize(GB)";"Expression"={"{0:N}" -f ($_.Size/1GB) -as [float]}}, `
                @{"Label"="FreeSpace(GB)";"Expression"={"{0:N}" -f ($_.FreeSpace/1GB) -as [float]}}, `
                @{"Label"="%Free";"Expression"={"{0:N}" -f ($_.FreeSpace/$_.Size*100) -as [float]}}


            foreach ($objitem in $data)
            {
            $table.rows.add($srv_name, $objitem."Name", $objitem."VolumeName", $objitem."DiskSize(GB)", $objitem."FreeSpace(GB)", $objitem."%Free")             
            }
    }
}



#sort data based on percentage free space ascending
$dv = New-Object System.Data.DataView($table)
$dv.Sort="pc_Free ASC"


#do not send an email if there is no data
if ($dv.Count -eq 0) {exit}


#put data into html output for emailing results   
$html = "<table table border=1>
        <tr>
            <td><font face=arial size=2>Server</font></td>
            <td><font face=arial size=2>Name</font></td>
            <td><font face=arial size=2>VolumeName</font></td>
            <td><font face=arial size=2>DiskSize(GB)</font></td>
            <td><font face=arial size=2>FreeSpace(GB)</font></td>
            <td><font face=arial size=2>%Free</font></td>
        </tr>"

foreach ($row in $dv)
{
    $html += "<tr>
            <td><font face=arial size=2>" + $row.Server + "</font></td>
            <td><font face=arial size=2>" + $row.Name + "</font></td>
            <td><font face=arial size=2>" + $row.VolumeName + "</font></td>
            <td><font face=arial size=2>" + $row.DiskSize_GB + "</font></td>
            <td><font face=arial size=2>" + $row.FreeSpace_GB + "</font></td>
            <td><font face=arial size=2>" + $row.pc_Free + "</font></td>
            </tr>"
}
    
$html += "</table>"



#send email
$command = ".\SendEmail.ps1 –Subject ""Low Drive Space"" -Body ""$html"" -bodyashtml"
Invoke-Expression $command