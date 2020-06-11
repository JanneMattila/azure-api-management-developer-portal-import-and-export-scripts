# Azure API Management Developer Portal Import and Export scripts

## Introduction

[Developer portal](https://github.com/Azure/api-management-developer-portal) has examples
how to [migrate portal between services](https://github.com/Azure/api-management-developer-portal/wiki/Migrate-portal-between-services) **however** it might be process that does not work for everybody.
[Example](https://github.com/Azure/api-management-developer-portal/blob/master/scripts/migrate.js) was
built in mind that you migrate the content from source to target in same flow. This
means that if done in e.g. Azure DevOps Pipelines then you would have to have access to
both systems at the same time. To separate
these two process steps these PowerShell helper scripts has been developed:

- Export-APIMDeveloperPortal
- Import-APIMDeveloperPortal

Names should pretty well describe the actual intent of the scripts.

`Export-APIMDeveloperPortal` exports the developer content to filesystem. 
This requires only access rights to the **source** environment 
(e.g. Service Principal executing the export in Azure Pipelines).

`Import-APIMDeveloperPortal` imports content from filesystem.
This requires only access rights to the **target** environment.

You can use these scripts for this kind of process:

- Export developer portal in pipeline
- Store exported developer portal to Azure Artifacts or Pipeline Artifacts
- Import developer portal in your pipeline using above artifacts

## Usage

### Export

```powershell
.\Export-APIMDeveloperPortal.ps1 -ResourceGroupName rg-apim -APIMName contosoapi -ExportFolder Export
```

This creates `Export` folder and exports developer portal content and media
files from `contosoapi` APIM Developer portal.

### Import

```powershell
.\Import-APIMDeveloperPortal.ps1 -ResourceGroupName rg-apim -APIMName contosoapi -ImportFolder Import
```

This load content and media files from `Import` folder and imports them to `contosoapi`
APIM Developer portal.