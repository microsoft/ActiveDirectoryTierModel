# Detailed Deployment Guide

This guide provides a step-by-step deployment workflow using scoped deployment parameters. Use this approach when you need granular control over the deployment process or want to deploy components incrementally.

For a streamlined full deployment workflow, see the [Quick Deployment Guide](quick-deployment-guide.md).

## Overview

This detailed approach deploys Tier Model components one type at a time, following the proper dependency order:

1. **Organizational Units (OUs)** - Foundation hierarchy
2. **Security Groups** - Required for ACL delegations and GPO filtering
3. **User Accounts** - Service accounts and administrative users
4. **OU ACL Delegations** - Permissions and rights delegation
5. **Group Policy Objects (GPOs)** - Policy configuration and linking
6. **ADMX Templates** - Administrative template imports

Each component follows a three-step pattern:
1. **Plan** - Preview changes without applying them
2. **Deploy** - Execute the deployment with `-ConfirmApply`
3. **Audit** - Verify compliance and detect drift

## Step 1: Deploy Organizational Units

### 1.1 Plan OU Deployment
Review what OUs will be created:

```powershell
.\Deploy-TierModel.ps1 -OuOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of OUs to be created
- OU paths and protection settings
- No changes applied to Active Directory

### 1.2 Deploy OUs
Execute the OU deployment:

```powershell
.\Deploy-TierModel.ps1 -OuOnly -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- OUs created successfully
- Protection from accidental deletion applied
- Deployment summary

### 1.3 Audit OUs
Verify OU compliance:

```powershell
.\Audit-TierModel.ps1 -OuOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All OUs compliant
- No drift detected
- Zero high-severity findings

---

## Step 2: Deploy Security Groups

### 2.1 Plan Group Deployment
Review what groups will be created:

```powershell
.\Deploy-TierModel.ps1 -GroupOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of groups to be created
- Group scope and type
- Planned membership assignments
- No changes applied to Active Directory

### 2.2 Deploy Groups
Execute the group deployment:

```powershell
.\Deploy-TierModel.ps1 -GroupOnly -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- Groups created successfully
- Group memberships configured
- Deployment summary

### 2.3 Audit Groups
Verify group compliance:

```powershell
.\Audit-TierModel.ps1 -GroupOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All groups compliant
- Membership matches configuration
- No drift detected

---

## Step 3: Deploy User Accounts

### 3.1 Plan User Deployment
Review what users will be created:

```powershell
.\Deploy-TierModel.ps1 -UserOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of users to be created
- User properties and group memberships
- OU placement
- No changes applied to Active Directory

### 3.2 Deploy Users
Execute the user deployment:

```powershell
.\Deploy-TierModel.ps1 -UserOnly -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- Users created successfully
- Group memberships assigned
- Users placed in correct OUs
- Deployment summary

### 3.3 Audit Users
Verify user compliance:

```powershell
.\Audit-TierModel.ps1 -UserOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All users compliant
- Placement and membership correct
- No drift detected

---

## Step 4: Deploy OU ACL Delegations

### 4.1 Plan OU ACL Deployment
Review what ACL delegations will be applied:

```powershell
.\Deploy-TierModel.ps1 -OuAclsOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of OUs receiving ACL delegations
- Groups being delegated permissions
- Rights and access control entries to be applied
- No changes applied to Active Directory

### 4.2 Deploy OU ACLs
Execute the ACL delegation deployment:

```powershell
.\Deploy-TierModel.ps1 -OuAclsOnly -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- ACL delegations applied successfully
- Groups granted appropriate permissions
- Deployment summary

### 4.3 Audit OU ACLs
Verify ACL delegation compliance:

```powershell
.\Audit-TierModel.ps1 -OuAclsOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All delegations compliant
- Security principals have correct permissions
- No drift detected

---

## Step 5: Deploy Group Policy Objects

### 5.1 Plan GPO Deployment
Review what GPOs will be created and linked:

```powershell
.\Deploy-TierModel.ps1 -GposOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of GPOs to be created or updated
- GPO link targets and link order
- Security filtering and WMI filters
- No changes applied to Active Directory

### 5.2 Deploy GPOs
Execute the GPO deployment:

```powershell
.\Deploy-TierModel.ps1 -GposOnly -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- GPOs created or updated successfully
- GPOs linked to target OUs
- Link order and enforcement configured
- Deployment summary

### 5.3 Audit GPOs
Verify GPO compliance:

```powershell
.\Audit-TierModel.ps1 -GposOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All GPOs compliant
- Links and settings match configuration
- No drift detected

---

## Step 6: Deploy ADMX Templates

### 6.1 Plan ADMX Deployment
Review what ADMX templates will be imported:

```powershell
.\Deploy-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of ADMX files to be imported to Central Store
- ADML language files to be imported
- Target path in SYSVOL
- No changes applied to the domain

### 6.2 Deploy ADMX Templates
Execute the ADMX deployment:

```powershell
.\Deploy-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- ADMX templates copied to Central Store
- ADML language files deployed
- Templates available for GPO configuration
- Deployment summary

### 6.3 Audit ADMX Templates
Verify ADMX template compliance:

```powershell
.\Audit-TierModel.ps1 -AdmxOnly -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All ADMX templates present in Central Store
- File hashes match configuration
- No drift detected

---

## Step 7: Deploy MSA ACL Delegations (Optional)

This step is optional and only required if you need to manage Managed Service Account (MSA) permissions using the Tier Model. Enable with `-IncludeMsa` switch.

### 7.1 Plan MSA ACL Deployment
Review what MSA ACL delegations will be applied:

```powershell
.\Deploy-TierModel.ps1 -IncludeMsa -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of MSAs receiving ACL delegations
- Groups being delegated permissions (msDS-ManagedServiceAccount object class)
- Rights and access control entries to be applied
- No changes applied to Active Directory

### 7.2 Deploy MSA ACLs
Execute the MSA ACL delegation deployment:

```powershell
.\Deploy-TierModel.ps1 -IncludeMsa -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- MSA ACL delegations applied successfully
- Groups granted appropriate permissions on MSA objects
- Deployment summary

### 7.3 Audit MSA ACLs
Verify MSA ACL delegation compliance:

```powershell
.\Audit-TierModel.ps1 -IncludeMsa -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All MSA delegations compliant
- Security principals have correct permissions on msDS-ManagedServiceAccount objects
- No drift detected

---

## Step 8: Deploy gMSA ACL Delegations (Optional)

This step is optional and only required if you need to manage Group Managed Service Account (gMSA) permissions using the Tier Model. Enable with `-IncludeGmsa` switch.

### 8.1 Plan gMSA ACL Deployment
Review what gMSA ACL delegations will be applied:

```powershell
.\Deploy-TierModel.ps1 -IncludeGmsa -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of gMSAs receiving ACL delegations
- Groups being delegated permissions (msDS-GroupManagedServiceAccount object class)
- Rights and access control entries to be applied
- No changes applied to Active Directory

### 8.2 Deploy gMSA ACLs
Execute the gMSA ACL delegation deployment:

```powershell
.\Deploy-TierModel.ps1 -IncludeGmsa -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- gMSA ACL delegations applied successfully
- Groups granted appropriate permissions on gMSA objects
- Deployment summary

### 8.3 Audit gMSA ACLs
Verify gMSA ACL delegation compliance:

```powershell
.\Audit-TierModel.ps1 -IncludeGmsa -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All gMSA delegations compliant
- Security principals have correct permissions on msDS-GroupManagedServiceAccount objects
- No drift detected

---

## Step 9: Deploy dMSA ACL Delegations (Optional)

This step is optional and only required if you need to manage Delegated Managed Service Account (dMSA) permissions using the Tier Model. Enable with `-IncludeDmsa` switch.

### 9.1 Plan dMSA ACL Deployment
Review what dMSA ACL delegations will be applied:

```powershell
.\Deploy-TierModel.ps1 -IncludeDmsa -PreferredDc DC01.contoso.com
```

**Expected Output:**
- List of dMSAs receiving ACL delegations
- Groups being delegated permissions (msDS-DelegatedManagedServiceAccount object class)
- Rights and access control entries to be applied
- No changes applied to Active Directory

### 9.2 Deploy dMSA ACLs
Execute the dMSA ACL delegation deployment:

```powershell
.\Deploy-TierModel.ps1 -IncludeDmsa -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- dMSA ACL delegations applied successfully
- Groups granted appropriate permissions on dMSA objects
- Deployment summary

### 9.3 Audit dMSA ACLs
Verify dMSA ACL delegation compliance:

```powershell
.\Audit-TierModel.ps1 -IncludeDmsa -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All dMSA delegations compliant
- Security principals have correct permissions on msDS-DelegatedManagedServiceAccount objects
- No drift detected

---

## Step 10: Deploy Windows LAPS ACL Delegations (Optional)

This step is optional and only required if you use Windows LAPS encrypted-password storage. It deploys 7 ACL delegations (Self, Read, and Reset permissions per target OU) **and** sets the `ADPasswordEncryptionPrincipal` registry value on the 6 non-DC LAPS GPOs so the correct tier group can decrypt managed passwords. Enable with `-IncludeWinLaps` switch.

> ⚠️ **Windows LAPS only** — this feature exclusively uses the Windows LAPS APIs (`ms-LAPS-*` attributes). Legacy Microsoft LAPS (`ms-Mcs-AdmPwd*`, `AdmPwd.PS`) is never referenced or modified.

### Prerequisites

Before running this step, the following must already exist in Active Directory:

| Dependency | Required by |
|-----------|-------------|
| All Tier Model OUs | ACL delegation targets |
| All Tier Model Groups | Read/Reset permission principals |
| All 7 Windows LAPS GPOs | Decryptor configuration (GPO existence only, not links) |
| Windows LAPS schema extension (`ms-LAPS-Password` attribute class) | Schema gate — **tool stops with a friendly error if absent; it never extends the schema itself** |

Missing OUs or groups produce a **Dependency Errors** listing and halt the plan. Missing GPOs are flagged per entry.

### 10.1 Plan Windows LAPS ACL Deployment
Review what delegations will be applied:

```powershell
.\Deploy-TierModel.ps1 -IncludeWinLaps -PreferredDc DC01.contoso.com
```

**Expected Output:**
- 7 target OUs listed with their read/reset group assignments
- 6 `ConfigureLapsDecryptor` actions showing GPO name → decryptor principal
- Domain Controllers OU shows Self + Read/Reset for Domain Admins (no decryptor — DSRM always uses Domain Admins)
- No changes applied to Active Directory

### 10.2 Deploy Windows LAPS ACLs
Execute the Windows LAPS ACL deployment:

```powershell
.\Deploy-TierModel.ps1 -IncludeWinLaps -PreferredDc DC01.contoso.com -ConfirmApply
```

**Expected Output:**
- 7 × Self-permission, Read-permission, Reset-permission delegations applied
- 6 GPOs configured with `ADPasswordEncryptionPrincipal` (NETBIOS\sAMAccountName format)
- Deployment is idempotent — re-runs skip already-configured delegations and decryptor entries
- Deployment summary

### 10.3 Audit Windows LAPS ACLs
Verify Windows LAPS ACL and decryptor compliance:

```powershell
.\Audit-TierModel.ps1 -IncludeWinLaps -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All 7 LAPS ACL delegations compliant (Self, Read, Reset present on each OU)
- All 6 GPO decryptor values compliant (correct `ADPasswordEncryptionPrincipal` set)
- No drift detected
- Findings show `Compliant` for each delegation entry

> **Note on tier isolation:** `ADPasswordEncryptionPrincipal` is a single principal per GPO. This means Tier 0 Admins can decrypt Tier 0 PAW passwords, but **cannot** decrypt Tier 1 or Tier 2 PAW passwords — each tier's admins decrypt only their own tier. This is intentional per-tier isolation enforced by CNG-DPAPI; GenericAll on a lower-tier PAW OU does not grant decryption.

---

## Deploying Windows LAPS as Part of Full Deployment

`-IncludeWinLaps` composes cleanly with `-FullDeployment`. The Windows LAPS phase runs **after** MSA → gMSA → dMSA (Phase 10):

```powershell
# Plan full deployment including Windows LAPS
.\Deploy-TierModel.ps1 -FullDeployment -IncludeWinLaps -PreferredDc DC01.contoso.com

# Apply full deployment including Windows LAPS
.\Deploy-TierModel.ps1 -FullDeployment -IncludeWinLaps -PreferredDc DC01.contoso.com -ConfirmApply

# Audit everything including Windows LAPS
.\Audit-TierModel.ps1 -FullDeployment -IncludeWinLaps -PreferredDc DC01.contoso.com
```

> **Opt-in:** A plain `-FullDeployment` (without `-IncludeWinLaps`) does **not** deploy or audit Windows LAPS. You must explicitly add `-IncludeWinLaps` to include it.

---



After completing all deployment steps, run a comprehensive audit to ensure the entire Tier Model is compliant:

```powershell
.\Audit-TierModel.ps1 -FullDeployment -PreferredDc DC01.contoso.com
```

**Expected Output:**
- All components compliant across all categories
- Zero high-severity findings
- Complete audit report

## Troubleshooting

### Component Dependencies

If a deployment step fails, verify dependencies are in place:
- **Groups** require OUs to exist
- **Users** require OUs and Groups to exist
- **OU ACLs** require OUs and Groups to exist
- **MSA ACLs** (Optional) require MSA objects and Groups to exist
- **gMSA ACLs** (Optional) require gMSA objects and Groups to exist
- **dMSA ACLs** (Optional) require dMSA objects and Groups to exist
- **Windows LAPS ACLs** (Optional) require OUs, Groups, and all 7 Windows LAPS GPOs to exist; Windows LAPS schema extension (`ms-LAPS-Password`) must be present
- **GPOs** require OUs to exist for linking

### Redeployment

If issues occur, you can safely re-run any deployment step. The deployment scripts are idempotent and will skip existing objects:

```powershell
# Re-run a specific component deployment
.\Deploy-TierModel.ps1 -GroupOnly -PreferredDc DC01.contoso.com -ConfirmApply
```

### Audit Failures

If an audit step reports drift or non-compliance:
1. Review the audit findings
2. Identify the specific discrepancies
3. Re-run the deployment for that component to remediate
4. Re-audit to verify compliance

## When to Use This Approach

Use this detailed step-by-step approach when:
- Deploying to production for the first time
- Validating each component before proceeding
- Troubleshooting specific component issues
- Learning the deployment process
- Meeting change control requirements for incremental changes

For routine deployments or updates, consider using the [Quick Deployment Guide](quick-deployment-guide.md) with `-FullDeployment`.

## Next Steps

After successful deployment:
- Schedule regular audits to detect configuration drift
- Document any manual changes made outside automation
- Review audit reports periodically for compliance monitoring

For additional documentation, see:
- [Quick Deployment Guide](quick-deployment-guide.md)
- [Deployment Methodology](deployment-methodology.md)
- [Drift Detection Details](drift-detection-details.md)
- [GPO Management Strategy](gpo-management-strategy.md)
