Param (
    [Parameter(Mandatory = $true, HelpMessage = "Resource group of API MAnagement")] 
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "API Management Name")] 
    [string] $APIMName,

    [Parameter(HelpMessage = "Export folder")] 
    [string] $ExportFolder = "$PSScriptRoot\Export"
)

$ErrorActionPreference = "Stop"

"Exporting Azure API Management Developer portal content to: $ExportFolder"
$mediaFolder = Join-Path -Path $ExportFolder -ChildPath "Media"
mkdir $ExportFolder -Force
mkdir $mediaFolder -Force

$apimContext = New-AzApiManagementContext -ResourceGroupName $ResourceGroupName -ServiceName $APIMName
$tenantAccess = Get-AzApiManagementTenantAccess -Context $apimContext
if (!$tenantAccess.Enabled) {
    Write-Warning "Management API is not enabled. Enabling..."
    Set-AzApiManagementTenantAccess -Context $apimContext -Enabled $true
}

$managementEndpoint = "https://$APIMName.management.azure-api.net"

$userId = $tenantAccess.Id
$resourceName = $APIMName + "/" + $userId

$parameters = @{
    "keyType" = "primary"
    "expiry"  = ('{0:yyyy-MM-ddTHH:mm:ss.000Z}' -f (Get-Date).ToUniversalTime().AddDays(1))
}

$token = Invoke-AzResourceAction  -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.ApiManagement/service/users" -Action "token" -ResourceName $resourceName -ApiVersion "2019-12-01" -Parameters $parameters -Force
$headers = @{Authorization = ("SharedAccessSignature {0}" -f $token.value) }

$ctx = Get-AzContext
$ctx.Subscription.Id
$baseUri = "$managementEndpoint/subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$APIMName"
$baseUri

$contentItems = @{ }
$contentTypes = Invoke-RestMethod -Headers $headers -Uri "$baseUri/contentTypes?api-version=2019-12-01" -Method GET -ContentType "application/json"

foreach ($contentTypeItem in $contentTypes.value) {
    $contentTypeItem.id
    $contentType = Invoke-RestMethod -Headers $headers -Uri "$baseUri/$($contentTypeItem.id)/contentItems?api-version=2019-12-01" -Method GET -ContentType "application/json"

    foreach ($contentItem in $contentType.value) {
        $contentItem.id
        $contentItems.Add($contentItem.id, $contentItem)    
    }
}

$contentItems
$contentItems | ConvertTo-Json -Depth 100 | Out-File -FilePath "$ExportFolder\data.json"

$storage = Invoke-RestMethod -Headers $headers -Uri "$baseUri/tenant/settings?api-version=2019-12-01" -Method GET -ContentType "application/json"
$connectionString = $storage.settings.PortalStorageConnectionString

$storageContext = New-AzStorageContext -ConnectionString $connectionString
Set-AzCurrentStorageAccount -Context $storageContext

$contentContainer = "content"

$totalFiles = 0
$continuationToken = $null
do {
    $blobs = Get-AzStorageBlob -Container $contentContainer -MaxCount 1000 -ContinuationToken $continuationToken
    "Found $($blobs.Count) files in current batch."
    $blobs
    $totalFiles += $blobs.Count
    if (0 -eq $blobs.Length) {
        break
    }

    foreach ($blob in $blobs) {
        Get-AzStorageBlobContent -Blob $blob.Name -Container $contentContainer -Destination (Join-Path -Path $mediaFolder -ChildPath $blob.Name)
    }
    
    $continuationToken = $blobs[$blobs.Count - 1].ContinuationToken;
}
while ($null -ne $continuationToken)

"Downloaded $totalFiles files from container $contentContainer"
"Export completed"
