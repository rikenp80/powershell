cls

$month = "06"
$year = "2020"

$source_file_purchase = "C:\Users\riken\Downloads\"+$month+"Purchases.csv"
$source_file_refund = "C:\Users\riken\Downloads\"+$month+"Refunds.csv"

$target_file_purchase = "\\192.168.1.6\Documents\Receipts\Amazon\Amazon_"+$year+"_"+$month+"_Purchase.csv"
$target_file_refund = "\\192.168.1.6\Documents\Receipts\Amazon\Amazon_"+$year+"_"+$month+"_Refund.csv"

$source_file_purchase
$source_file_refund

$target_file_purchase
$target_file_refund


Import-Csv $source_file_purchase -Delimiter "," | Select "Order Date","Shipment Date","Title","Quantity","Item Total" | Export-Csv $target_file_purchase -Delimiter "," -Encoding UTF8 -notypeinfo

Import-Csv $source_file_refund -Delimiter "," | Select "Order Date","Refund Date","Title","Refund Condition","Refund Amount","Refund Tax Amount" | Export-Csv $target_file_refund -Delimiter "," -Encoding UTF8 -notypeinfo