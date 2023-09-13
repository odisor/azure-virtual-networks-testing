###############################################################################################################################################################################################
#                                                                                                                                                                                             #
#  This script automates New Vnet/additional Vnet Address space connectity test                                                                                                               #
#  Input Parameters                                                                                                                                                                           #
#   Vnet ID (mandatory): ie.  /subscriptions/d38aeb3d-c9f6-48b1-8223-fee8f298edd3/resourceGroups/ASP-GXUS-S-RGBA-S001/providers/Microsoft.Network/virtualNetworks/ASP-GXUS-G-VNT-S046     #                                                                                                                  #
#   CIDR to test (mandatory): ie  10.205.0.0/20                                                                                                                                               #
#   virtualMachineSize (optional, by default smallest VM available at each location): i.e Standard_D3_v2 for East US                                                                         #
#                                                                                                                                                                                             #
#  The script looks for the template and parameter files in the current path, make sure the three files are in the same path                                                                  #
#                                                                                                                                                                                             #
###############################################################################################################################################################################################

#Script params passed as arguments: CloudOpsEng_VnetConnTestQA.ps1 -vnetIdParam "VnetID"  -CIDRParam "CIDR"
param($vnetIdParam, $CIDRParam)

Function Check-VnetId {
    param (
        $vnetIdfParam
    )
    
    if ($vnetIdfParam.ToLower() -eq 'cancel' ){
        Write-Host "   Execution Canceled   " -ForegroundColor yellow -BackgroundColor Red
        break
     }
    else{
        $vnetIdFields = $vnetIdfParam.split('/')
    }

    if ($vnetIdFields.count -eq 9 -and $vnetIdFields[5] -eq 'providers' -and $vnetIdFields[6] -eq 'Microsoft.Network' -and $vnetIdFields[7] -eq 'virtualNetworks') {
        try{
            $getVnetId = Get-AzVirtualNetwork -Name $vnetIdFields[8] -ResourceGroupName $vnetIdFields[4] -ErrorAction Stop
        }
        catch{
            Write-Host "   AN ERROR OCURRED TRYING TO FETCH VNET FROM AZURE   `n`n   PLEASE VERIFY VNET ID!!!   `n`n   CANNOT CONTINUE EXECUTION   `n" -ForegroundColor yellow -BackgroundColor Red
            Write-Host $Error[0]
            break
        }
    }
     
    if ($getVnetId.Id -eq $vnetIdfParam){
        Write-Host "`nVnet Id $vnetIdfParam VALIDATED`n`n" -ForegroundColor Green
    }
    else{
        Write-Host "   INVALID VNET ID   `n`n   PLEASE VERIFY!!!   `n`n   CANNOT CONTINUE EXECUTION   `n" -ForegroundColor yellow -BackgroundColor Red
        break
    }
}


Function Check-SNT_CIDR {
    param (
        $CIDRfParam
    )

    if ($CIDRfParam.ToLower() -eq 'cancel' ){
        Write-Host "   Execution Canceled   " -ForegroundColor yellow -BackgroundColor Red
        break
     }

    if($CIDRfParam.split('/').count -eq 2){
        $addressRange = $CIDRfParam.split('/')[0]
        $netMask = [int] $CIDRfParam.split('/')[1]
    }
    else
     {
        Write-Host "   AN ERROR OCURRED   `n`n   PLEASE VERIFY CIDR: IP ADDRESS OR NETMASK MISSING!!!   `n`n   CANNOT CONTINUE EXECUTION   `n" -ForegroundColor yellow -BackgroundColor Red
        break
    }

    try{
        $addressRangeValidation = [IPAddress] $addressRange -as [boolean] -and ([int] $AddressRange.split('.')[0] -eq 10 -or ([int] $AddressRange.split('.')[0] -eq 172 -and [int] $AddressRange.split('.')[1] -ge 16 -and [int] $AddressRange.split('.')[1] -le 31))
    }
    catch{
        $addressRangeValidation = $false
    }

    $netMaskValidation = $netMask -ge 8 -and $netMask -le 31

    if(!$addressRangeValidation){
        Write-Host "   INVALID PRIVATE IP ADDRESS RANGE   `n`n   NOT FROM 10.0.0.0/8 NOR 172.16.0.0./12 PLEASE VERIFY!!!   `n`n   CANNOT CONTINUE EXECUTION   `n" -ForegroundColor yellow -BackgroundColor Red
        break
     }

     if(!$netMaskValidation){
        Write-Host "   INVALID NET MASK   `n`n   PLEASE VERIFY!!!   `n`n   CANNOT CONTINUE EXECUTION   `n" -ForegroundColor yellow -BackgroundColor Red
        break
     }

    Write-Host "`nCIDR $CIDRParam VALIDATED`n`n" -ForegroundColor Green
}

Function Get-ElapsedTime {

    #$StartTime = $(get-date)  --> put this code at the beggining of your script

    $elapsedTime = $(get-date) - $StartTime
    $totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
    Write-Host "`n`nElapsed Time:  $totalTime" -ForegroundColor cyan

}

# Main

$StartTime = $(get-date)
$Error.Clear()
$templateFilePath = ".\vm-template.json"
$parameterFilePath = ".\vm-parameters.json"


#Azure context change and  validation
Try{
    $subsParam = $vnetIdParam.Split('/')[2]
    Set-AzContext -Subscription $subsParam -ErrorAction Stop
}
catch{
    Write-Host "   AN ERROR OCURRED   `n`n   CANNOT CHANGE AZURE CONTEXT, PLEASE VERIFY SUBSCRIPTION!!!   `n`n   CANNOT CONTINUE EXECUTION   `n" -ForegroundColor yellow -BackgroundColor Red
    break
}


#Parameter validation and calculation
$context = Get-AzContext
Write-Host "Azure context changed, new working context is: `n`n   $($context.Name | fl | Out-String)`n" -ForegroundColor green
Check-VnetId -vnetIdfParam $vnetIdParam
Check-SNT_CIDR -CIDRfParam $CIDRParam

$vnetParam = $vnetIdParam.Split('/')[8]
$rgpParam = $vnetIdParam.Split('/')[4]
$locationParam = (Get-AzResourceGroup -Name $rgpParam).location
$vmNameParam = ("VM-QA-"+$($vnetIdParam.Split('/')[8]).Split('-')[4].ToString())
$NSGNameParam = ("NSG-QA-"+$($vnetIdParam.Split('/')[8]).Split('-')[4].ToString())
$SNTNameParam = ("SNT-QA-"+$($vnetIdParam.Split('/')[8]).Split('-')[4].ToString())


#Deploy Subnet Test-SNT-QA, Service Endopoints,RouteTableID, NSG for SNT creation
$sntEndPoints = (Get-AzVirtualNetworkAvailableEndpointService -Location $locationParam).Name | Where-Object {$_ -notmatch 'Microsoft.Storage.Global'}
$networkSecurityGroup = New-AzNetworkSecurityGroup -name $NSGNameParam -ResourceGroupName $rgpParam -Location $locationParam
$routeTable = (Get-AzRouteTable -ResourceGroupName $rgpParam).Id | Select-String -Pattern "-T2LB-"
$virtualNetwork = Get-AzVirtualNetwork -Name $vnetParam -ResourceGroupName $rgpParam

Write-Host "Deploying new Subnet '$SNTNameParam' at Vnet '$vnetParam' at Resource Group '$rgpParam'`n`n" -ForegroundColor green
Add-AzVirtualNetworkSubnetConfig -Name $SNTNameParam `
    -VirtualNetwork $virtualNetwork `
    -AddressPrefix $CIDRParam `
    -NetworkSecurityGroupId $networkSecurityGroup.Id `
    -RouteTableId $routeTable `
    -ServiceEndpoint $sntEndPoints
$virtualNetwork | Set-AzVirtualNetwork


#Deploy VM
Write-Host "Deploying VM '$vmNameParam' attached to Vnet '$vnetParam' at Resource Group '$rgpParam' , Please wait ..." -ForegroundColor green
$deploymentName = ($vnetParam+"_ConnTest_"+(Get-Date -Format  MMddyy.HHmm)+"hs").ToString()

try{
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $rgpParam `
      -TemplateFile $templateFilePath `
      -TemplateParameterFile $parameterFilePath `
      -location $locationParam -virtualNetworkId $vnetIdParam -subnetName $SNTNameParam -virtualMachineName $vmNameParam -virtualMachineRG $rgpParam -ErrorAction Stop
}
catch{
    Write-Host "`nAN ERROR OCURRED WHEN TRYING TO DEPLOY VM, PLEASE CHECK DEPLOYMENT. CANNOT CONTINUE    " -ForegroundColor Yellow -BackgroundColor Red
    Write-Host $Error[0]
    break
}

#Waiting VM to spin up
$tick = 0
$vmStatuses = Get-AzVM -ResourceGroupName $rgpParam -Status
$vmStatus = ($vmStatuses | ?{$_.Name -eq $vmNameParam}).PowerState
Write-Host "`nWaiting VM '$vmNameParam' to spin up ...`n" -ForegroundColor green

while ($vmStatus -ne 'VM running' -and $tick -le 30){
    Start-Sleep -Seconds 10
    $vmStatuses = Get-AzVM -ResourceGroupName $rgpParam -Status
    $vmStatus = ($vmStatuses | ?{$_.Name -eq $vmNameParam}).PowerState
    $tick += 1
}

if ($tick -gt 30){
    Write-Host "`nVM     '$vmNameParam' NOT READY, PLEASE CHECK STATUS. CANNOT CONTINUE    " -ForegroundColor Yellow -BackgroundColor Red
    break
}


#Execute connectivity test script inside VM shell
$commands = @(`
'Test-NetConnection -computer pzigxpneupstasi0001.blob.core.windows.net -port 443', `
'Test-NetConnection -computer google.com -port 443', `
'Test-NetConnection -computer www.azure.com -port 80', `
'Test-NetConnection -computer test.rebex.net -port 22', `
'Test-NetConnection -computer smtp.gmail.com -port 587', `
'Resolve-DnsName -Name login.microsoftonline.com | %{Test-NetConnection -ComputerName $_.IPAddress -Port 389 -warningaction silentlycontinue} | ft ComputerName,TcpTestSucceeded')

Write-Host "`nExecuting connectivity test script`n" -ForegroundColor green
$vmTesting = Get-AzVM -ResourceGroupName $rgpParam -Name $vmNameParam

if ($?){
    $logFile = ($vnetParam+"_ConnTest_"+(Get-Date -Format  MMddyy.HHmm)+"hs"+".log").ToString()
    $n = 1
    ForEach ($command in $commands){
        $fileName = "RunScript_$n.ps1"
        Out-File -FilePath $fileName -InputObject $command -NoNewline
        $result = Invoke-AzVMRunCommand -VM $vmTesting `
                    -CommandId 'RunPowerShellScript' `
                    -ScriptPath $fileName
        Remove-Item -Path $fileName -Force -ErrorAction SilentlyContinue
        $n+=1
        Write-Host ($command | Out-String)
        Write-Host ($result.Value[0].Message | Out-String)
        $command | Out-file -append -filepath $logFile
        $result.Value[0].Message | Out-file -append -filepath $logFile
    }
    
    Write-Host "`n`nConnectivity Test log file:  $(Get-ChildItem $logFile)`n" -ForegroundColor Green
}


#Removing resources created
$vnicToDelete = ($vmTesting | Select-Object -ExpandProperty NetworkProfile).NetworkInterfaces.Id.split('/')[8]
Write-Host "`nRemoving resources...`n" -ForegroundColor green
Write-Host "`nRemoving VM '$vmNameParam' at Resource Group '$rgpParam' , Please wait ...`n" -ForegroundColor green
Remove-AzVM -ResourceGroupName $rgpParam -Name $vmNameParam -Force
Remove-AzNetworkInterface  -Name $vnicToDelete -ResourceGroupName $rgpParam -Force
Write-Host "`nRemoving Subnet '$SNTNameParam' at Vnet '$vnetParam' at Resource Group '$rgpParam'  Please wait ...`n" -ForegroundColor green
Remove-AzVirtualNetworkSubnetConfig -Name $SNTNameParam -VirtualNetwork $virtualNetwork 
$virtualNetwork | Set-AzVirtualNetwork
Remove-AzNetworkSecurityGroup -Name $NSGNameParam -ResourceGroupName $rgpParam -Force


Get-ElapsedTime
Write-Host "##vso[task.setvariable variable=VnetLogFile]$logFile"
