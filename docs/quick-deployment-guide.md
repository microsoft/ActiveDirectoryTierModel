# Quick Deployment Guide

This guide provides a streamlined workflow for deploying and auditing the Tier Model in production environments.

## Prerequisites

Before deploying the Tier Model, ensure the following requirements are met:

### Environment Requirements
- **PowerShell 7.0 or later** (PowerShell 5.1 is not supported)
- **Domain Admin membership** for deployment operations
- **Network access** to your preferred Domain Controller

### Required PowerShell Modules
- `ActiveDirectory` (version 1.0.1.0 or later)
- `GroupPolicy` (version 1.0 or later)
- `Pester` (version 5.7.1 or later) - Must be obtained from public sources (PowerShell Gallery)

### Installation
Install Pester from the PowerShell Gallery:
```powershell
Install-Module -Name Pester -MinimumVersion 5.7.1 -Force -SkipPublisherCheck
```

### Obtain TierModel
Download the latest TierModel release from GitHub

# Unblock the downloaded zip file
Unblock-File -Path "$env:USERPROFILE\Downloads\TierModel.zip"

# Extract to C:\
Expand-Archive -Path "$env:USERPROFILE\Downloads\TierModel.zip" -DestinationPath "C:\" -Force

# Navigate to the TierModel directory
cd C:\TierModel
```

**Note:** The deployment and audit scripts automatically import the TierModel module and validate prerequisites.

## Deployment Workflow

### Step 1: Plan the Deployment (Dry-Run)
Run the deploy script in **planning mode** (default behavior) to preview all changes without applying them:

```powershell
.\Deploy-TierModel.ps1 -FullDeployment -PreferredDc DC01.contoso.com
```

This will:
- Validate prerequisites
- Generate a deployment plan showing all proposed changes
- Display adds, updates, and potential issues
- **NOT apply any changes** to Active Directory

Review the output carefully to ensure the planned changes are correct.

### Step 2: Execute the Deployment
After reviewing the plan, apply the changes using the `-ConfirmApply` parameter:

```powershell
.\Deploy-TierModel.ps1 -FullDeployment -PreferredDc DC01.contoso.com -ConfirmApply
```

This will deploy all Tier Model components in the correct dependency order:
1. Organizational Units (OUs)
2. Security Groups
3. User Accounts
4. OU ACL Delegations
5. Group Policy Objects (GPOs)
6. ADMX Administrative Templates

> **Optional features** (MSA/gMSA/dMSA ACL delegations, Windows LAPS ACL delegations + GPO decryptor) are **not** included in a standard `-FullDeployment` — add the appropriate switches to enable them:
> ```powershell
> .\Deploy-TierModel.ps1 -FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa -IncludeWinLaps -PreferredDc DC01.contoso.com -ConfirmApply
> ```

### Step 3: Audit the Deployment
After deployment completes, run a full audit to verify compliance and detect any drift:

```powershell
.\Audit-TierModel.ps1 -FullDeployment -PreferredDc DC01.contoso.com
```

This will:
- Check all deployed components against the configuration
- Identify any drift from the desired state
- Generate a compliance report
- Highlight any manual intervention required

## Expected Results

### Successful Deployment
- All components created or updated as specified
- Zero errors in the deployment log
- Audit shows full compliance with no drift detected

### First Audit After Deployment
The audit should report:
- **All components compliant** with the Tier Model configuration
- **No drift findings** (or minimal informational findings)
- **Zero high-severity issues**

If the audit identifies drift immediately after deployment, review the deployment logs and investigate the discrepancies.

## Optional: Enable Logging

For troubleshooting or audit trails, enable detailed logging:

```powershell
# Deployment with logging
.\Deploy-TierModel.ps1 -FullDeployment -PreferredDc DC01.contoso.com -ConfirmApply -Logging

# Audit with logging
.\Audit-TierModel.ps1 -FullDeployment -PreferredDc DC01.contoso.com -Logging
```

Logs are saved to the current directory or the path specified by `-LogPath`.

## Troubleshooting

### Prerequisites Failed
If `Test-TierModelPrerequisites` reports errors:
- Install PowerShell 7+ from https://github.com/PowerShell/PowerShell/releases
- Verify Domain Admin group membership
- Ensure required AD and GP modules are installed (use RSAT on Windows)

### Deployment Errors
- Review error messages in deployment output
- Check logs if `-Logging` was enabled
- Verify JSON configuration syntax and schema compliance
- Ensure the preferred DC is reachable and responsive

### Audit Drift Detected
- Compare audit findings against recent changes
- Review manual interventions that may have occurred outside automation
- Re-run deployment to converge environment back to desired state

## Next Steps

After successful deployment:
- Schedule regular audits to detect configuration drift
- Document any manual changes made outside the automation
- Update the configuration JSON for future deployments
- Review audit reports periodically for compliance monitoring

For detailed documentation, see:
- [Detailed Deployment Guide](detailed-deployment-guide.md)
- [Deployment Methodology](deployment-methodology.md)
- [Drift Detection Details](drift-detection-details.md)
- [GPO Management Strategy](gpo-management-strategy.md)
