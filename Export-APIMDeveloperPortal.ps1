Param (
    [Parameter(Mandatory = $true, HelpMessage = "Resource group of API MAnagement")] 
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "API Management Name")] 
    [string] $APIMName,

    [Parameter(HelpMessage = "Export folder")] 
    [string] $ExportFolder = "$PSScriptRoot\Export"
)

$ErrorActionPreference = "Stop"
$apiVersion = "2024-05-01"

"Exporting Azure API Management Developer portal content to: $ExportFolder"
$mediaFolder = Join-Path -Path $ExportFolder -ChildPath "Media"

New-Item -ItemType "Directory" -Path $ExportFolder -Force
New-Item -ItemType "Directory" -Path $mediaFolder -Force

$ctx = Get-AzContext
$ctx.Subscription.Id
$baseUri = "subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$APIMName"
$baseUri

$contentItems = @{ }
$contentTypes = (Invoke-AzRestMethod -Path "$baseUri/contentTypes?api-version=$apiVersion" -Method GET).Content | ConvertFrom-Json

foreach ($contentTypeItem in $contentTypes.value) {
    $contentTypeItem.id
    $contentType = (Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)/contentItems?api-version=$apiVersion" -Method GET).Content | ConvertFrom-Json

    foreach ($contentItem in $contentType.value) {
        $contentItem.id
        $contentItems.Add($contentItem.id, $contentItem)    
    }
}

$contentItems
$contentItems | ConvertTo-Json -Depth 100 | Out-File -FilePath "$ExportFolder\data.json"

$storage = (Invoke-AzRestMethod -Path "$baseUri/portalSettings/mediaContent/listSecrets?api-version=$apiVersion" -Method POST).Content | ConvertFrom-Json
$containerSasUrl = [System.Uri] $storage.containerSasUrl
$storageAccountName = $containerSasUrl.Host.Split('.')[0]
$sasToken = $containerSasUrl.Query
$contentContainer = $containerSasUrl.GetComponents([UriComponents]::Path, [UriFormat]::SafeUnescaped)

$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken
Set-AzCurrentStorageAccount -Context $storageContext

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
        $targetFile = Join-Path -Path $mediaFolder -ChildPath $blob.Name
        $targetFolder = Split-Path -Path $targetFile -Parent
        if (-not (Test-Path -Path $targetFolder)) {
            New-Item -ItemType "Directory" -Path $targetFolder -Force
        }
        Get-AzStorageBlobContent -Blob $blob.Name -Container $contentContainer -Destination $targetFile
    }
    
    $continuationToken = $blobs[$blobs.Count - 1].ContinuationToken;
}
while ($null -ne $continuationToken)

"Downloaded $totalFiles files from container $contentContainer"
"Export completed"
