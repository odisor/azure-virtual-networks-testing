[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $subscriptionName        
)
    
<#------------------------------------------------------------------------------------------------------------------------------------------------------------------#>

# Install the Azure Resource Graph module if not already installed
if (-not (Get-Module -ListAvailable -Name Az.ResourceGraph)) {
    Install-Module -Name Az.ResourceGraph -Scope CurrentUser -Force
}

# Get Subscription ID from Name
$subscription = Get-AzSubscription -SubscriptionName $subscriptionName
$subscriptionId = $subscription.Id

# Set the query
$query = "
    resources
    | where type == 'microsoft.network/virtualnetworks'
    | where subscriptionId == '$subscriptionId'
    | extend 
        resourceType = split(type,'/')[1],
        vntName = split(id, '/')[8],
        addressSpace = properties.addressSpace.addressPrefixes[0]
    | project resourceType, vntName, addressSpace, id
    "

# Execute the query
$results = Search-AzGraph -Query $query

#Convert Results to hastable
$resources = @{}
ForEach ($row in $results){
    $resources[$row.resourceType] += @{ $row.vntName = @{ "resourceId" = $row.id; "adressSpace" = $row.addressSpace; "resourceGroup" = $row.id.Substring(0,88)}}
}

# Output the results
Write-Host "##vso[task.setvariable variable=resources]$($resources | ConvertTo-Json -Compress)"