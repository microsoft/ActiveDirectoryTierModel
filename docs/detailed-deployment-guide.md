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

## Post-Deployment Verification

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
