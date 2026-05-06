@{
    RootModule = 'TierModel.psm1'
    ModuleVersion = '2.0.0'
    GUID = 'b6a7c9f8-5e5d-4c7a-9b9e-2e2e9a4f6d10'
    Author = 'TierModel Team'
    CompanyName = 'Enterprise AD'
    Copyright = '(c) 2025 Enterprise AD. All rights reserved.'
    Description = 'PowerShell module for deploying and auditing Active Directory Tier Models from segmented JSON configuration. Supports idempotent deployment, drift detection, GPO rights editing, and ADMX import.'
    PowerShellVersion = '7.0'
    RequiredModules = @(
        # Note: ActiveDirectory and GroupPolicy modules are loaded dynamically when needed
        # This allows the module to work in development/testing environments where RSAT may not be available
    )
    FunctionsToExport = @(
        'Copy-TierModelAdmx',
        'Get-TierModel',
        'Get-TierModelAdmx',
        'Get-TierModelConfig',
        'Get-TierModelGpo',
        'Get-TierModelGpoFd',
        'Get-TierModelGPOLink',
        'Get-TierModelGpoLinkFd',
        'Get-TierModelGpoTemplate',
        'Get-TierModelGroup',
        'Get-TierModelGroupFd',
        'Get-TierModelOu',
        'Get-TierModelOuAcl',
        'Get-TierModelOuAclFd',
        'Get-TierModelPlan',
        'Get-TierModelUser',
        'Get-TierModelUserFd',
        'Import-TierModelGpo',
        'New-TierModelGpo',
        'New-TierModelGPOLink',
        'New-TierModelGptTmplContent',
        'New-TierModelGroup',
        'New-TierModelOu',
        'New-TierModelOuAcl',
        'New-TierModelUser',
        'Resolve-DomainSpecificGuid',
        'Resolve-TierModelDomainDN',
        'Resolve-TierModelGuid',
        'Resolve-TierModelOuPath',
        'Resolve-TierModelPlaceholder',
        'Resolve-TierModelPrincipalSid',
        'Set-TierModelGpoTemplate',
        'Test-TierModelAdmx',
        'Test-TierModelConfig',
        'Test-TierModelGPO',
        'Test-TierModelGPOAudit',
        'Test-TierModelGPOContent',
        'Test-TierModelGPOLink',
        'Test-TierModelGroup',
        'Test-TierModelOu',
        'Test-TierModelOuAcl',
        'Test-TierModelOuExists',
        'Test-TierModelPrerequisites',
        'Test-TierModelUser',
        'Update-TierModelGPOConfig',
        'Write-TierModelLog'
    )
    PrivateData = @{ 
        PSData = @{
            Tags = @('ActiveDirectory', 'TierModel', 'Security', 'GPO', 'ADMX', 'Deployment', 'Audit')
            ReleaseNotes = '2.0.0: Segmented JSON config, fail-fast validation, correlation ID logging, ADMX import'
        }
    }
}
