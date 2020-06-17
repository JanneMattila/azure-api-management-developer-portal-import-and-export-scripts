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

### Example implementation in Azure DevOps

You can implement this process in few different ways but here's one
example implementation:

- CI for exporting the content from developer portal
  - Store export as artifact
- CD for importing the content to developer portal

Idea is that you manually trigger the CI when you want to export
the content out from the developer portal.

#### Export using CI

![Azure DevOps CI for developer portal export](https://user-images.githubusercontent.com/2357647/84689642-f1a7c980-af49-11ea-9528-d0dd2b501002.png)

![CI PowerShell configuration](https://user-images.githubusercontent.com/2357647/84690137-aa6e0880-af4a-11ea-8a20-a22893086f76.png)

Relevant `yaml` portions of the configuration:

```yaml
- task: AzurePowerShell@5
  displayName: 'Azure PowerShell script: FilePath'
  inputs:
    azureSubscription: 'AzureDev'
    ScriptPath: 'Export-APIMDeveloperPortal.ps1'
    ScriptArguments: '-ResourceGroupName apim-rg -APIMName demo -ExportFolder $(Build.ArtifactStagingDirectory)\Export'
    azurePowerShellVersion: LatestVersion
    pwsh: true

- task: PublishBuildArtifacts@1
  displayName: 'Publish Artifact: Export'
  inputs:
    PathtoPublish: '$(Build.ArtifactStagingDirectory)\Export'
    ArtifactName: Export
```

That build should now have artifact correctly stored in it:

![CI artifact](https://user-images.githubusercontent.com/2357647/84690871-da69db80-af4b-11ea-85e8-d0fc5a581df8.png)

#### Import using CD

![Importing the developer portal](https://user-images.githubusercontent.com/2357647/84690353-0a64af00-af4b-11ea-97ee-4f07a2f81fd1.png)

![Release Definition](https://user-images.githubusercontent.com/2357647/84690474-36803000-af4b-11ea-8107-8735da4a6549.png)

Relevant `yaml` portions of the configuration:

```yaml
- task: AzurePowerShell@5
  displayName: 'Azure PowerShell script: FilePath'
  inputs:
    azureSubscription: 'AzureDev'
    ScriptPath: '$(System.DefaultWorkingDirectory)/source/Import-APIMDeveloperPortal.ps1'
    ScriptArguments: '-ResourceGroupName apim-qa-rg -APIMName demo-qa -ImportFolder $(System.DefaultWorkingDirectory)/CI/Export'
    azurePowerShellVersion: LatestVersion
    pwsh: true
    workingDirectory: '$(System.DefaultWorkingDirectory)/CI/Export'
```

### Credits

Special thanks to [@MiikaAntila](https://github.com/MiikaAntila) for helping out finalizing and testing these scripts.
