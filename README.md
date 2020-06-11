# 329-azure-api-management-developer-portal

## Export

```powershell
.\Export-APIMDeveloperPortal.ps1 -ResourceGroupName rg-apim -APIMName contosoapi -ExportFolder Export
```

This creates `Export` folder and puts centent and media files there.

## Import

```powershell
.\Import-APIMDeveloperPortal.ps1 -ResourceGroupName rg-apim -APIMName contosoapi -ImportFolder Import
```
