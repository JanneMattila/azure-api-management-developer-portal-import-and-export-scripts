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
$ImportFolder = (Resolve-Path $ImportFolder).Path
$mediaFolder = Join-Path -Path $ImportFolder -ChildPath "Media"
$dataFile = Join-Path -Path $ImportFolder -ChildPath "data.json"

if ($false -eq (Test-Path $ImportFolder)) {
    throw "Import folder path was not found: $ImportFolder"
}

if ($false -eq (Test-Path $dataFile)) {
    throw "Data file was not found: $dataFile"
}

if (-not (Test-Path -Path $mediaFolder)) {
    New-Item -ItemType "Directory" -Path $mediaFolder -Force
    Write-Warning "Media folder $mediaFolder was not found but it was created."
}

"Reading $dataFile"
$contentItems = Get-Content -Encoding utf8  -Raw -Path $dataFile | ConvertFrom-Json -AsHashtable
$contentItems | Format-Table -AutoSize

$apiManagement = Get-AzApiManagement -ResourceGroupName $ResourceGroupName -Name $APIMName
$developerPortalEndpoint = "https://$APIMName.developer.azure-api.net"

if ($null -ne $apiManagement.DeveloperPortalHostnameConfiguration) {
    # Custom domain name defined
    $developerPortalEndpoint = "https://" + $apiManagement.DeveloperPortalHostnameConfiguration.Hostname
    $developerPortalEndpoint
}

$ctx = Get-AzContext
$ctx.Subscription.Id

$baseUri = "subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$APIMName"
$baseUri

"Processing clean up of the target content"
$contentTypes = (Invoke-AzRestMethod -Path "$baseUri/contentTypes?api-version=2019-12-01" -Method GET).Content | ConvertFrom-Json
foreach ($contentTypeItem in $contentTypes.value) {
    $contentTypeItem.id
    $contentType = (Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)/contentItems?api-version=2019-12-01" -Method GET).Content | ConvertFrom-Json

    foreach ($contentItem in $contentType.value) {
        $contentItem.id
        Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)?api-version=2019-12-01" -Method DELETE
    }
    Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)/contentItems?api-version=2019-12-01" -Method DELETE
}

"Processing clean up of the target storage"
$storage = (Invoke-AzRestMethod -Path "$baseUri/portalSettings/mediaContent/listSecrets?api-version=2019-12-01" -Method POST).Content | ConvertFrom-Json
$containerSasUrl = [System.Uri] $storage.containerSasUrl
$storageAccountName = $containerSasUrl.Host.Split('.')[0]
$sasToken = $containerSasUrl.Query
$contentContainer = $containerSasUrl.GetComponents([UriComponents]::Path, [UriFormat]::SafeUnescaped)

$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken
Set-AzCurrentStorageAccount -Context $storageContext

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

    Invoke-AzRestMethod -Path "$baseUri/$key`?api-version=2019-12-01" -Method PUT -Payload $body
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
$revision = [DateTime]::UtcNow.ToString("yyyyMMddHHmm")
$data = @{
    properties = @{
        description = "Migration $revision"
        isCurrent   = $true
    }
}
$body = ConvertTo-Json $data
$publishResponse = Invoke-AzRestMethod -Path "$baseUri/portalRevisions/$($revision)?api-version=2019-12-01" -Method PUT -Payload $body
$publishResponse

if (202 -eq $publishResponse.StatusCode) {
    "Import completed"
    return
}

throw "Could not publish developer portal"
