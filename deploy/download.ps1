Param (
    [Parameter(HelpMessage = "Resource group of API MAnagement")] 
    [string] $ResourceGroupName = "apim-rg",

    [Parameter(HelpMessage = "API Management Name")] 
    [string] $APIMName = "demo9001"
)

$ErrorActionPreference = "Stop"

$apimContext = New-AzApiManagementContext -ResourceGroupName $ResourceGroupName -ServiceName $APIMName
$tenantAccess = Get-AzApiManagementTenantAccess -Context $apimContext

$portalEndpoint = "https://$APIMName.developer.azure-api.net"
$managementEndpoint = "https://$APIMName.management.azure-api.net"
$contentTypesUri = "${managementEndpoint}/contentTypes?api-version=2019-12-01"
$contentTypesUri

$userId = $tenantAccess.Id
$userId
$resourceName = $APIMName + "/" + $userId
$resourceName

$parameters = @{
    "keyType" = "primary"
    "expiry"  = ('{0:yyyy-MM-ddTHH:mm:ss.000Z}' -f (Get-Date).ToUniversalTime().AddDays(1))
}
$parameters

$token = Invoke-AzResourceAction  -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.ApiManagement/service/users" -Action "token" -ResourceName $resourceName -ApiVersion "2019-12-01" -Parameters $parameters -Force
$token

$headers = @{Authorization = ("SharedAccessSignature {0}" -f $token.value) }
$headers

$ctx = Get-AzContext
$ctx.Subscription.Id
$baseUri = "$managementEndpoint/subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$APIMName"
$baseUri

$products = Invoke-RestMethod -headers $headers -Uri "$baseUri/products?api-version=2019-12-01" -Method GET -ContentType "application/json"
$products

$contentTypes = Invoke-RestMethod -headers $headers -Uri "$baseUri/contentTypes?api-version=2019-12-01" -Method GET -ContentType "application/json"
$contentTypes
