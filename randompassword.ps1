cls
$count = 1

while ($count -le 6) #specify number of passwords that need to be generated
{
$password = (("123456789ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz".tochararray() | sort {Get-Random})[0..15] -join '')

$password
$count = $count + 1
}



#$password = (("123456789ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz".tochararray() | sort {Get-Random})[0..15] -join '')
#$password

#$arr = "123456789ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz".tochararray()
#(Get-Random -Count 20 -InputObject $arr) -join ''
