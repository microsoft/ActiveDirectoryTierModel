# ADMX Management (Deployment Phase 6)

ADMX/ADML template handling is the final deployment phase. Templates are declared in JSON (`tiermodel-admx.json` + `tiermodel-adml-<lang>.json`) and imported only when missing (future hash comparison planned).

## Core Behaviors
- Enumerate declared templates
- Detect presence in `%SystemRoot%/PolicyDefinitions`
- Plan Import vs Skip actions
- Support `-WhatIf` across deployment scopes

## Common Scenarios
```powershell
# Include ADMX in full deployment
./Deploy-TierModel.ps1 -FullDeployment -PreferredDc DC01.contoso.com -ConfirmApply

# ADMX only
./Deploy-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com -ConfirmApply

# Audit ADMX state
./Audit-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com
```

## ADMX JSON Declaration Structure

### tiermodel-admx.json Format
```json
{
  "version": "2.0.0",
  "lastUpdated": "2026-02-23",
  "comment": "ADMX administrative template configuration with MD5 hash verification",
  "admx": {
    "destinationPath": "\\\\{{DOMAIN_FQDN}}\\SYSVOL\\{{DOMAIN_FQDN}}\\Policies\\PolicyDefinitions",
    "sourcePath": "config\\admx",
    "files": {
      "CustomSecurity.admx": {
        "comment": "Organization-specific security policy templates",
        "hashDate": "2026-02-23",
        "downloadLink": "https://contoso.com/templates/security",
        "hash": "9353B83B2DDB5FEB60C10A3A8DDC7818"
      },
      "LAPS.admx": {
        "comment": "Administrative Templates (.admx) for Windows 11 2025 Update (25H2) - V2.0",
        "hashDate": "2025-10-27",
        "downloadLink": "https://www.microsoft.com/en-my/download/details.aspx?id=108428",
        "hash": "9BFFE86494F2C156EB3DDF7EB1E57560"
      },
      "DeviceGuard.admx": {
        "comment": "Administrative Templates (.admx) for Windows 11 2025 Update (25H2) - V2.0",
        "hashDate": "2025-10-27",
        "downloadLink": "https://www.microsoft.com/en-my/download/details.aspx?id=108428",
        "hash": "B4ABDC91D9F8DD0A2EFA4ED9638098EB"
      }
    }
  }
}
```

### tiermodel-adml-en-US.json Format
```json
{
  "version": "2.0.0",
  "lastUpdated": "2026-02-23",
  "comment": "ADML English (United States) language files with MD5 hash verification",
  "adml": {
    "destinationPath": "\\\\{{DOMAIN_FQDN}}\\SYSVOL\\{{DOMAIN_FQDN}}\\Policies\\PolicyDefinitions\\en-US",
    "sourcePath": "config\\admx\\en-US",
    "files": {
      "CustomSecurity.adml": {
        "comment": "Organization-specific security policy templates",
        "hashDate": "2026-02-23",
        "downloadLink": "https://contoso.com/templates/security",
        "hash": "898BA4BCA8162C318C16E3E81F4095DD"
      },
      "LAPS.adml": {
        "comment": "Administrative Templates (.admx) for Windows 11 2025 Update (25H2) - V2.0",
        "hashDate": "2025-10-27",
        "downloadLink": "https://www.microsoft.com/en-my/download/details.aspx?id=108428",
        "hash": "7FE7D0560EAA804F7670BDBABCB1EA95"
      },
      "DeviceGuard.adml": {
        "comment": "Administrative Templates (.admx) for Windows 11 2025 Update (25H2) - V2.0",
        "hashDate": "2025-10-27",
        "downloadLink": "https://www.microsoft.com/en-my/download/details.aspx?id=108428",
        "hash": "30377C9FAE7E5ABC2E55077E2AAD5417"
      }
    }
  }
}
```

### Key Properties
- **version**: Schema version for the JSON structure (currently 2.0.0)
- **lastUpdated**: Date of last modification to the configuration
- **destinationPath**: SYSVOL PolicyDefinitions path (supports `{{DOMAIN_FQDN}}` placeholder)
- **sourcePath**: Relative path to source ADMX/ADML files
- **files**: Object containing file metadata keyed by filename
  - **comment**: Description of the template source or purpose
  - **hashDate**: Date when the MD5 hash was generated
  - **downloadLink**: URL to download or reference the template
  - **hash**: MD5 hash for file integrity verification

## Troubleshooting
| Issue | Cause | Resolution |
|-------|-------|-----------|
| Missing locale ADML | Locale folder absent | Add `en-US` (or target locale) with matching `.adml` files |
| Import access denied | Permissions / elevation | Run as Domain Admin / elevated and verify SYSVOL write access |
| No `.admx` files found | Incorrect source path | Validate PolicyDefinitions folder contains templates |
| Locale mismatch | ADML folder not aligned to system locale | Use `Get-WinSystemLocale` to confirm and create matching folder |

## ADMX Operations Workflow

The TierModel module provides three cmdlets for ADMX management:

- **Get-TierModelAdmx**: Analyzes and plans deployment needs using hash verification
- **Copy-TierModelAdmx**: Deploys ADMX/ADML files to SYSVOL Central Store
- **Test-TierModelAdmx**: Audits compliance and detects drift

### Example Workflow
```powershell
# Load TierModel configuration
$config = Get-TierModelConfig

# Step 1: Plan deployment (analyze what needs updating)
$analysis = Get-TierModelAdmx -Config $config -DomainController "DC01" -AdmlLanguage "en-US"

# Review analysis
Write-Host "Files to update: $($analysis.Summary.FilesToUpdate)"
Write-Host "Files up to date: $($analysis.Summary.FilesUpToDate)"

# Step 2: Deploy templates (if needed)
if ($analysis.Summary.FilesToUpdate -gt 0) {
    $deployment = Copy-TierModelAdmx -Config $config -DomainController "DC01" -AdmlLanguage "en-US"
    Write-Host "Deployed: $($deployment.Summary.Successful)  Failed: $($deployment.Summary.Failed)"
}

# Step 3: Audit compliance
$audit = Test-TierModelAdmx -Config $config -DomainController "DC01" -AdmlLanguage "en-US"
Write-Host "Compliant files: $($audit.Summary.Compliant)"
Write-Host "Issues found: $($audit.Summary.IssuesFound)"
```

### Automated Deployment
The deployment and audit scripts handle these operations automatically:

```powershell
# Planning mode (no changes)
.\Deploy-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com

# Execute deployment
.\Deploy-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com -ConfirmApply

# Audit compliance
.\Audit-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com
```

## Best Practices
1. Store ADMX source in version control
2. Validate syntax before import (Microsoft tools / vendor documentation)
3. Stage imports in non-production domain first
4. Document custom template purpose & change history
5. Monitor post-import GPO processing performance
6. Restrict import capability to least-privilege admin groups

## Future Enhancements
- Template hash comparison for update detection
- Multi-locale synchronization strategy
- Automatic rollback on partial failures

For additional documentation, see:
- [GPO Management Strategy](gpo-management-strategy.md)
- [Drift Detection Details](drift-detection-details.md)
