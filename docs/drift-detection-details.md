# Drift Detection Details

This document provides detailed guidance for using the `Audit-TierModel.ps1` script to detect configuration drift between the TierModel configuration and the actual Active Directory state.

## Overview
`Audit-TierModel.ps1` analyzes current Active Directory state against the declarative Tier Model configuration using modular Test-TierModel* cmdlets. It identifies missing objects, mismatched configurations, and provides structured drift findings for remediation.

## Basic Drift Detection

### Full Deployment Audit
```powershell
# Run comprehensive audit of all components
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -FullDeployment
```

### Scoped Audits
```powershell
# Audit only organizational units
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -OuOnly

# Audit only groups
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -GroupOnly

# Audit only Users
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -UserOnly

# Audit only OU ACLs
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -OuAclsOnly

# Audit only GPOs
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -GposOnly

# Audit only ADMX templates
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -AdmxOnly
```

## Audit Output Structure

The audit script displays real-time progress and returns structured results:

### Console Output
Each component audit displays:
- **Summary**: TotalChecked, Missing, Mismatched, Total Drift, Compliance %
- **Warnings**: Non-critical issues requiring attention
- **Errors**: Critical issues preventing full audit
- **Drift Findings**: Detailed list of configuration mismatches

### Drift Finding Structure
| Field | Description |
|-------|-------------|
| Type | Missing, Mismatch, ExtraProtection, HashMismatch |
| ResourceType | OrganizationalUnit, Group, User, GPO, ACL, ADMXTemplate |
| Identifier | Object name or distinguished name |
| ExpectedValue | Configuration from JSON |
| ActualValue | Current AD state (null if missing) |
| Details | Human-readable description |
| Severity | High (if applicable) |

## Generating Reports

### JSON Output for Automation
```powershell
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -FullDeployment `
    -OutputFormat Json `
    -OutputFileBase "TierModel-Audit" `
    -LogPath "C:\Reports"
```

**JSON Structure:**
```json
{
  "auditSummary": {
    "totalChecked": 150,
    "driftCount": 3,
    "compliancePercentage": 98.0
  },
  "driftFindings": [
    {
      "Type": "Missing",
      "ResourceType": "OrganizationalUnit",
      "Identifier": "Tier0-PAW-Staging",
      "ExpectedValue": "OU=PAW Staging,OU=Tier Model Administration,DC=contoso,DC=com",
      "ActualValue": null,
      "Details": "OU does not exist in Active Directory"
    }
  ],
  "metadata": {
    "scope": "FullDeployment",
    "preferredDc": "DC01.contoso.com",
    "timestamp": "2026-02-27T10:30:00Z",
    "version": "v0.2"
  }
}
```

### HTML Report
```powershell
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -GposOnly `
    -OutputFormat Html `
    -OutputFileBase "GPO-Compliance"
```

### NUnit XML for CI/CD Integration
```powershell
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -FullDeployment `
    -OutputFormat NUnitXml `
    -OutputFileBase "TierModel-Tests" `
    -LogPath "C:\TestResults"
```

## Interpreting Common Drift Issues

| Type | ResourceType | Cause | Recommended Action |
|------|--------------|-------|---------------------|
| Missing | OrganizationalUnit | OU deleted manually | Re-run Deploy-TierModel.ps1 with -OuOnly or -FullDeployment |
| Missing | Group | Group deleted or not created | Re-run Deploy-TierModel.ps1 with -GroupOnly |
| Missing | User | User account deleted or not created | Re-run Deploy-TierModel.ps1 with -UserOnly |
| Missing | ADMXTemplate | Template removed from PolicyDefinitions | Re-run Deploy-TierModel.ps1 with -AdmxOnly |
| Missing | ACL | OU ACL delegation not applied | Re-run Deploy-TierModel.ps1 with -OuAclsOnly |
| Mismatch | Group | Membership differs from config | Manual remediation or update configuration |
| Mismatch | User | User properties differ from config | Manual remediation or update configuration |
| Mismatch | GPO | Link order incorrect | Manual GPO link order adjustment required |
| HashMismatch | ADMXTemplate | Template file content differs | Re-run Deploy-TierModel.ps1 with -AdmxOnly to update |
| ExtraProtection | OrganizationalUnit | Additional OU protection enabled | Manual review; may be intentional hardening |

## Integrating with CI/CD

### Scheduled Drift Detection
```powershell
# Daily audit with JSON output for trending
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -FullDeployment `
    -OutputFormat Json `
    -OutputFileBase "TierModel-Audit-$timestamp" `
    -LogPath "\\FileServer\ComplianceReports"
```

### CI Pipeline Integration
See [CI/CD Documentation](ci-cd.md) for examples of integrating audit scripts into GitHub Actions and Azure DevOps pipelines.

## Remediation Workflow

1. **Run Audit**: Identify drift using `Audit-TierModel.ps1`
2. **Review Findings**: Analyze DriftFindings for Missing/Mismatch issues
3. **Plan Remediation**: Decide whether to update config or redeploy
4. **Deploy Changes**: Use `Deploy-TierModel.ps1` with appropriate scope
5. **Verify**: Re-run audit to confirm drift resolution

## Component-Specific Details

### OUs (Organizational Units)
- **Checks**: Existence, protection from deletion, GPO inheritance blocking
- **Cmdlet**: `Test-TierModelOu`
- **Common Issues**: Missing OUs, mismatched protection settings

### Groups
- **Checks**: Existence, group scope, group category, description
- **Cmdlet**: `Test-TierModelGroup`
- **Common Issues**: Missing groups, membership drift (future)

### Users
- **Checks**: Existence, enabled status, OU placement
- **Cmdlet**: `Test-TierModelUser`
- **Common Issues**: Missing users, incorrect OU assignment

### GPOs
- **Checks**: Existence, link presence, link order, settings (partial)
- **Cmdlets**: `Test-TierModelGpo`, `Test-TierModelGPOAudit`, `Test-TierModelGPOLink`
- **Common Issues**: Missing GPOs, incorrect link order, missing links

### OU ACLs
- **Checks**: Presence of delegation ACEs for specified groups
- **Cmdlet**: `Test-TierModelOuAcl`
- **Common Issues**: Missing delegations, extra permissions

### ADMX Templates
- **Checks**: File existence, MD5 hash verification
- **Cmdlet**: `Test-TierModelAdmx`
- **Common Issues**: Missing templates, outdated files (hash mismatch)

## Notes
- Drift detection is **read-only**; no changes are made to AD
- Remediation is performed using `Deploy-TierModel.ps1` script
- MD5 hash-based ADMX drift detection is fully implemented
- Individual cmdlets can be called directly for programmatic use

## Related Documentation

For additional documentation, see:
- [Deployment Methodology](deployment-methodology.md)
- [Quick Deployment Guide](quick-deployment-guide.md)
- [Detailed Deployment Guide](detailed-deployment-guide.md)
- [CI/CD](ci-cd.md)
