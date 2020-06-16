Param (
    [Parameter(Mandatory = $true, HelpMessage = "Resource group of API MAnagement")] 
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "API Management Name")] 
    [string] $APIMName,

    [Parameter(HelpMessage = "Import folder")] 
    [string] $ImportFolder = "$PSScriptRoot\Import"
)

$ErrorActionPreference = "Stop"

"Importing Azure API Management Developer portal content from: $ImportFolder"
$mediaFolder = (Resolve-Path (Join-Path -Path $ImportFolder -ChildPath "Media")).Path
$dataFile = Join-Path -Path $ImportFolder -ChildPath "data.json"

if ($false -eq (Test-Path $ImportFolder)) {
    throw "Import folder path was not found: $ImportFolder"
}

if ($false -eq (Test-Path $mediaFolder)) {
    throw "Media folder path was not found: $mediaFolder"
}

if ($false -eq (Test-Path $dataFile)) {
    throw "Data file was not found: $dataFile"
}

"Reading $dataFile"
$contentItems = Get-Content -Encoding utf8  -Raw -Path $dataFile | ConvertFrom-Json -AsHashtable
$contentItems | Format-Table -AutoSize

$apimContext = New-AzApiManagementContext -ResourceGroupName $ResourceGroupName -ServiceName $APIMName
$tenantAccess = Get-AzApiManagementTenantAccess -Context $apimContext
if (!$tenantAccess.Enabled) {
    Write-Warning "Management API is not enabled. Enabling..."
    Set-AzApiManagementTenantAccess -Context $apimContext -Enabled $true
}

$managementEndpoint = "https://$APIMName.management.azure-api.net"
$developerPortalEndpoint = "https://$APIMName.developer.azure-api.net"

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

"Processing clean up of the target content"
$contentTypes = Invoke-RestMethod -Headers $headers -Uri "$baseUri/contentTypes?api-version=2019-12-01" -Method GET -ContentType "application/json"
foreach ($contentTypeItem in $contentTypes.value) {
    $contentTypeItem.id
    $contentType = Invoke-RestMethod -Headers $headers -Uri "$baseUri/$($contentTypeItem.id)/contentItems?api-version=2019-12-01" -Method GET -ContentType "application/json"

    foreach ($contentItem in $contentType.value) {
        $contentItem.id
        Invoke-RestMethod -Headers $headers -Uri "$baseUri/$($contentTypeItem.id)?api-version=2019-12-01" -Method DELETE -SkipHttpErrorCheck
    }
    $contentType = Invoke-RestMethod -Headers $headers -Uri "$baseUri/$($contentTypeItem.id)?api-version=2019-12-01" -Method DELETE -SkipHttpErrorCheck
}

"Processing clean up of the target storage"
$storage = Invoke-RestMethod -Headers $headers -Uri "$baseUri/tenant/settings?api-version=2019-12-01" -Method GET -ContentType "application/json"
$connectionString = $storage.settings.PortalStorageConnectionString

$storageContext = New-AzStorageContext -ConnectionString $connectionString
Set-AzCurrentStorageAccount -Context $storageContext

$contentContainer = "content"

$totalFiles = 0
$continuationToken = $null

$allBlobs = New-Object Collections.Generic.List[string]
do {
    $blobs = Get-AzStorageBlob -Container $contentContainer -MaxCount 1000 -ContinuationToken $continuationToken
    "Found $($blobs.Count) files in current batch."
    $blobs
    $totalFiles += $blobs.Count
    if (0 -eq $blobs.Length) {
        break
    }

    foreach ($blob in $blobs) {
        $allBlobs.Add($blob.Name)
    }
    
    $continuationToken = $blobs[$blobs.Count - 1].ContinuationToken;
}
while ($null -ne $continuationToken)

foreach ($blobName in $allBlobs) {
    "Removing $blobName"
    Remove-AzStorageBlob -Blob $blobName -Container $contentContainer -Force
}

"Removed $totalFiles files from container $contentContainer"
"Clean up completed"

"Uploading content"
foreach ($key in $contentItems.Keys) {
    $key
    $contentItem = $contentItems[$key]
    $body = $contentItem | ConvertTo-Json -Depth 100

    Invoke-RestMethod -Body $body -Headers $headers -Uri "$baseUri/$key`?api-version=2019-12-01" -Method PUT -ContentType "application/json; charset=utf-8"
}

"Uploading files"
$stringIndex = ($mediaFolder + "\").Length
Get-ChildItem -File -Recurse $mediaFolder `
| ForEach-Object { 
    $name = $_.FullName.Substring($stringIndex)
    Write-Host "Uploading file: $name"
    Set-AzStorageBlobContent -File $_.FullName -Blob $name -Container $contentContainer
}

"Publishing developer portal"
$publishResponse = Invoke-RestMethod -Headers $headers -Uri "$developerPortalEndpoint/publish?api-version=2019-12-01" -Method POST
$publishResponse

if ("OK" -eq $publishResponse) {
    "Import completed"
    return
}

throw "Could not publish developer portal"
