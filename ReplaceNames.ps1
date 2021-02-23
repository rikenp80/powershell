get-childitem *.* | foreach { rename-item $_ $_.Name.Replace("02. ", "") }


$files = Get-ChildItem *.* -Path C:\Users\Riken\Music\Hindi\ -Recurse | Where-Object {$_ -isnot [IO.DirectoryInfo]}

foreach ($file in $files)
 	{
	$file = Get-Item $file.name
	
	$FileName = $file.Name
	write-host $FileName
	
	$DotPos	= $FileName.indexof(".")
	$FileNameNew = $FileName.substring(0,$DotPos)
	write-host $FileNameNew
	
	$MediaPlayer = New-Object -Com WMPlayer.OCX
	$SetItemInfo = $MediaPlayer.mediaCollection.add($file)
	$SetItemInfo.setItemInfo('Title', $FileNameNew)
	$SetItemInfo.setItemInfo('Composer', "")
	$SetItemInfo.setItemInfo('Conductor', "")
	$SetItemInfo.setItemInfo('Genre', "")
	$SetItemInfo.setItemInfo('Track_number', "")
	}
	
	
	
$files = Get-ChildItem *.* -Path C:\Users\Riken\Music\Hindi\ -Recurse | Where-Object {$_ -isnot [IO.DirectoryInfo]}

foreach ($file in $files)
 	{
	$file = Get-Item $file.name
	
	$FileName = $file.Name
	
	$MediaPlayer = New-Object -Com WMPlayer.OCX
	$SetItemInfo = $MediaPlayer.mediaCollection.add($file)
	$SetItemInfo.setItemInfo('Track number', "")
	}	
