@{
    RootModule = 'TierModel.psm1'
    ModuleVersion = '1.3.2'
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
        'Format-TierModelDuration',
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
        'Get-TierModelMsaAcl',
        'Get-TierModelMsaAclFd',
        'New-TierModelMsaAcl',
        'Get-TierModelGmsaAcl',
        'Get-TierModelGmsaAclFd',
        'New-TierModelGmsaAcl',
        'Get-TierModelDmsaAcl',
        'Get-TierModelDmsaAclFd',
        'New-TierModelDmsaAcl',
        'Repair-TierModelCanonicalAcl',
        'Resolve-DomainSpecificGuid',
        'Resolve-TierModelDomainDN',
        'Resolve-TierModelGuid',
        'Resolve-TierModelOuPath',
        'Resolve-TierModelPlaceholder',
        'Resolve-TierModelPrincipalSid',
        'Set-TierModelGpoTemplate',
        'Test-TierModelAdmx',
        'Test-TierModelCanonicalAcl',
        'Test-TierModelConfig',
        'Test-TierModelGPO',
        'Test-TierModelGPOAudit',
        'Test-TierModelGPOContent',
        'Test-TierModelGPOLink',
        'Test-TierModelGroup',
        'Test-TierModelOu',
        'Test-TierModelOuAcl',
        'Test-TierModelMsaAcl',
        'Test-TierModelGmsaAcl',
        'Test-TierModelDmsaAcl',
        'Get-TierModelWinLapsAcl',
        'New-TierModelWinLapsAcl',
        'Test-TierModelWinLapsAcl',
        'Test-TierModelWinLapsDecryptor',
        'Get-TierModelWinLapsAclFd',
        'Get-TierModelAuditRule',
        'New-TierModelAuditRule',
        'Test-TierModelAuditRule',
        'Get-TierModelAuditRuleFd',
        'Test-TierModelOuExists',
        'Test-TierModelPrerequisites',
        'Test-TierModelUser',
        'Update-TierModelGPOConfig',
        'Write-TierModelLog'
    )
    PrivateData = @{ 
        PSData = @{
            Tags = @('ActiveDirectory', 'TierModel', 'Security', 'GPO', 'ADMX', 'Deployment', 'Audit')
            ReleaseNotes = '1.3.0: Add -EnableAuditing domain audit rule support (SACL/Sentinel monitoring via domain-root Everyone/Success/All canonical ACE, UNION converge). 1.2.3: Non-canonical root ACL pre-flight check (Test-TierModelCanonicalAcl) - Deploy and Audit hard-stop when the domain root DACL is not in canonical form (detect-only; never rewrites ACLs), with a friendly message and new docs/canonical-acl.md remediation guide. 1.2.2: English-language enforcement (#23) — fail-fast host-OS and Active Directory (en-US only) language checks in Test-TierModelPrerequisites, plus docs/language-support.md. 1.2.1: UI and reliability bug fixes (BUG-001..011) — preferred-DC ACL binds, aligned fail-fast prerequisite messages, WinLaps UnexpectedAcl + GenericAll exclusion, verified/retried OU inheritance, phantom-skip count fix. See CHANGELOG. 1.2.0: Added Windows LAPS deployment and audit cmdlets (-IncludeWinLaps). 1.1.0: Added Managed Service Account (MSA/gMSA/dMSA) ACL deployment and audit cmdlets. 1.0.0: Segmented JSON config, fail-fast validation, correlation ID logging, ADMX import'
        }
    }
}
