# Deployment Methodology

## Overview
This document outlines the deployment methodology for Tier Model, including deployment order, testing strategy, validation framework, auditing requirements, and idempotency principles. It serves as the technical foundation for the quick and detailed deployment guides.

## Alignment with Constitutional Principles

This testing framework embodies several constitutional governance principles:

### **Due Process**
- **Systematic validation** before making changes (test existence → evaluate → act)
- **Documented procedures** for all deployment actions
- **Appeal mechanism** through manual intervention warnings rather than forced changes

### **Checks and Balances**
- **Separation of concerns**: Different testing approaches for different object types
- **No single point of failure**: Multiple validation layers (pre-deployment, during deployment, post-deployment)
- **Manual oversight required** for complex issues (GPO link order corrections)

### **Transparency and Accountability**
- **Complete audit trail** of all actions and decisions
- **Clear documentation** of what was changed, skipped, or requires attention
- **Public record** through comprehensive logging

### **Federalism (Distributed Authority)**
- **Respects existing configurations** rather than centralizing all control
- **Preserves local customizations** by skipping existing objects
- **Delegates authority** to administrators for manual intervention decisions

### **Rule of Law**
- **Consistent application** of testing logic across all deployments
- **Predictable outcomes** through idempotent operations
- **Equal treatment** of all objects within their respective categories

### **Limited Government** 
- **Minimal intervention principle**: Only change what needs to be changed
- **Preserve existing rights**: Don't overwrite functional configurations
- **Constrained scope**: Testing focused on structural integrity, not detailed policy content

## Deployment Order of Precedence
Ordering mirrors authoritative design (plan.md) to satisfy dependencies and enable convergence:

1. **OUs (Organizational Units)** – Establish hierarchy
2. **Groups** – Provide principals for ACLs and GPO filtering (denyApply)
3. **Users** – Create accounts referencing existing OUs & groups
4. **ACL Delegations** – Apply OU permissions (requires OUs & groups)
5. **GPO Import/Create/Linking** – Materialize and link baselines & configurable policies (requires OUs)
6. **ADMX Import** – Administrative templates (performed only in `-FullDeployment` or standalone `-ImportAdmxOnly` scope)
7. **MSA ACL Delegations** (Optional) – Apply permissions on Managed Service Accounts (requires MSAs & groups; enable with `-IncludeMsa`)
8. **gMSA ACL Delegations** (Optional) – Apply permissions on Group Managed Service Accounts (requires gMSAs & groups; enable with `-IncludeGmsa`)
9. **dMSA ACL Delegations** (Optional) – Apply permissions on Delegated Managed Service Accounts (requires dMSAs & groups; enable with `-IncludeDmsa`)
10. **Windows LAPS Delegations** (Optional) – Apply Windows LAPS ACL delegations (Self/Read/Reset) and configure `ADPasswordEncryptionPrincipal` on LAPS GPOs (requires OUs, Groups, and all 7 Windows LAPS GPOs; Windows LAPS schema required; enable with `-IncludeWinLaps`)

## Testing Strategy by Component

### 1. Organizational Units (OUs)
**Testing Approach**: Simple AD object existence check
- **Test**: `Get-ADOrganizationalUnit -Filter "Name -eq 'OUName'"`
- **If Exists**: Skip with INFO message "OU already exists: [OU DN]"
- **If Missing**: Create OU with specified properties
- **Validation**: Verify OU creation success and log DN

### 2. Groups
**Testing Approach**: Simple AD object existence check
- **Test**: `Get-ADGroup -Filter "Name -eq 'GroupName'"`  
- **If Exists**: Skip with INFO message "Group already exists: [Group Name]"
- **If Missing**: Create group with specified properties
- **Validation**: Verify group creation and membership assignment

### 3. Users  
**Testing Approach**: Simple AD object existence check
- **Test**: `Get-ADUser -Filter "SamAccountName -eq 'Username'"`
- **If Exists**: Skip with INFO message "User already exists: [Username]"
- **If Missing**: Create user with specified properties
- **Validation**: Verify user creation and group membership

### 4. OU ACLs
**Testing Approach (Delegation Simplified)**: Presence-based delegation check (no deep ACE diff)
- **Test**: Enumerate OU security descriptor; search for any ACE whose IdentityReference matches target delegation group (e.g., `CORP\\Tier1ServerOperators`).
- **If Group Present**: Assume ACLs previously applied correctly; skip with INFO message "Delegation already present for group: [GroupName] on [OU DN]".
- **If Group Missing**: Apply full predefined ACL block from JSON (all intended rights for that group) and log SUCCESS.
- **No Deep Validation**: Individual rights are not re-compared; remediation is manual if misconfigured.
- **Rationale**: Minimizes complexity, keeps idempotency, avoids performance overhead of ACE-by-ACE diff.

#### OU ACL Delegation Algorithm (Pseudocode)
```
ForEach ($delegation in $model.ouDelegations) {
    $ouDn = $delegation.ouDistinguishedName
    $group = $delegation.groupSamAccountName
    $sd = Get-Acl -Path "AD:$ouDn"
    if ($sd.Access.IdentityReference -contains $groupIdentity) {
        Write-Information "Delegation already present for group: $group on $ouDn"
        $result = 'Present'
    } else {
        # Build ACEs from JSON rights list
        $aces = New-Object System.Collections.Generic.List[System.Security.AccessControl.ActiveDirectoryAccessRule]
        foreach ($perm in $delegation.permissions) {
             $ace = New-ADDelegationAce -Identity $groupIdentity -Permission $perm
             $aces.Add($ace)
        }
        Set-ADDelegation -DistinguishedName $ouDn -AccessRules $aces
        Write-Success "Applied delegation for group: $group on $ouDn"
        $result = 'Applied'
    }
}
```

#### Function Contract Update
`Test-TierModelOuAcl -DistinguishedName <string> -Group <string> [-Apply]`
- Returns `Status = 'Present'` if any ACE matches group.
- Returns `Status = 'Missing'` if no ACE found; with `-Apply` will add full ACL set.
- Does not return Warn for mismatched rights; such drift is out-of-scope.

### 5. Group Policy Objects (GPOs)
**Testing Approach**: Existence and link order validation

#### GPO Existence Testing
- **Test**: `Get-GPO -Name 'GPOName'`
- **If Exists**: 
  - Skip creation with INFO message "GPO already exists: [GPO Name]"
  - Proceed to link order testing
- **If Missing**: 
  - Create GPO based on mode (create, createAndImport, createImportAndConfigure)
  - Apply configurations (URA, Restricted Groups, etc.)
  - Link to specified OUs

#### GPO Link Order Testing  
- **Test**: `Get-GPInheritance -Target 'OU DN'` and verify LinkOrder values
- **If Correct Order**: Skip with INFO message "GPO link order correct: [OU DN]"
- **If Wrong Order**: WARN message "GPO link order incorrect: Expected [X], Found [Y] for GPO [Name] on [OU DN]"
- **Action**: Do NOT automatically fix link order - manual intervention required

#### GPO Configuration Scope
**NOT TESTED**: The following GPO settings are not validated during deployment:
- Individual User Rights Assignment values
- Restricted Group membership details  
- Registry policy settings
- Security settings beyond URA/RG
- GPO enabled/disabled status (changes post-deployment)

**Rationale**: These settings are complex and may change post-deployment. Focus is on structural integrity, not detailed policy content.

### 6. ADMX Administrative Templates
**Testing Approach**: Enumerate declared templates (from JSON) vs destination with MD5 hash verification.
- **Declaration Source**: `tiermodel-admx.json` + `tiermodel-adml-<lang>.json` (default `en-US`).
- **Pair Validation**: Each declared `.admx` must have corresponding locale `.adml`; missing locale triggers WARN & Skip.
- **Import Decision**: If template pair absent in `%SystemRoot%\PolicyDefinitions`, action = Import; existing pair with matching hash = Skip.
- **Hash Verification**: MD5 hash comparison detects file differences and triggers updates when needed.
- **WhatIf**: Lists planned Import/Skip actions without copying.
- **Drift**: MissingTemplate / ExtraTemplate / HashMismatch classifications during audit.

## Auditing and Logging Requirements

### Information Messages (INFO)
- Object already exists (OU, Group, User, GPO, MSA, gMSA, dMSA)
- Correct configuration found (ACL, GPO link order, MSA/gMSA/dMSA/WinLaps delegations)
- Successful creation/configuration
- File count validation success
- MSA/gMSA/dMSA/WinLaps optional feature enabled

### Warning Messages (WARN)  
- GPO link order incorrect (manual fix required)
- ADMX locale `.adml` missing for source template
- ADMX import failure (permission/lock issues)
- Missing declared ADML locale file
- MSA/gMSA/dMSA optional feature switch not enabled but configuration present
- MSA/gMSA/dMSA ACL application failure (permissions/lock issues)
- WinLaps optional feature switch not enabled but configuration present
- WinLaps schema not present (Windows LAPS not installed in forest)

### Error Messages (ERROR)
- Object creation failure
- ACL application failure  
- GPO creation/import failure
- Critical path dependencies missing

### Success Messages (SUCCESS)
- Component deployment completed
- Overall deployment phase completed
- Validation checks passed

## Re-deployment Safety

### Idempotent Operations
All operations must be safe to re-run:
- **Skip existing objects, except ADMX which is always overwrite exiting** rather than fail
- **Validate configuration** before applying changes
- **Log all actions** for audit trail
- **Preserve existing customizations** where possible

### Change Detection
- Compare current state with desired configuration
- Only apply changes where differences exist
- Log what would change before applying (dry-run capability)

### Rollback Considerations
- OUs: Safe to leave (contain other objects)
- Groups: Safe to leave (may have manual members)
- Users: Safe to leave (may have manual configurations)  
- GPOs: Safe to leave (may have manual settings)
- ADMX: Always overwrite (cumulative templates)

## Testing Workflow Example

```powershell
# Phase 1: OU Testing and Creation
ForEach ($ou in $tierModel.organizationalUnits) {
    if (Test-ADOrganizationalUnit $ou.distinguishedName) {
        Write-Information "OU already exists: $($ou.distinguishedName)"
    } else {
        New-ADOrganizationalUnit $ou
        Write-Success "Created OU: $($ou.distinguishedName)"
    }
}

# Phase 2: GPO Testing and Creation
ForEach ($gpo in $tierModel.gpos) {
    if (Test-GPO $gpo.name) {
        Write-Information "GPO already exists: $($gpo.name)"
        if (-not (Test-GPOLinkOrder $gpo)) {
            Write-Warning "GPO link order incorrect for: $($gpo.name)"
        }
    } else {
        New-TierModelGPO $gpo
        Write-Success "Created and configured GPO: $($gpo.name)"
    }
}
```

## Validation Framework

### Pre-deployment Validation
- JSON schema validation
- Domain connectivity test  
- Required permissions check
- PowerShell module dependencies

### Post-deployment Validation  
- Object creation verification
- ACL application verification
- GPO link verification (order only)
- ADMX file count verification

### Continuous Auditing
- Generate deployment report
- Log all skipped objects with reasons
- Document manual intervention requirements
- Provide rollback guidance where applicable

## Success Criteria

### Deployment Success
- All required objects created or verified existing
- No ERROR messages in deployment log
- All file counts match expected values
- GPO link orders correct (or documented deviations)

### Audit Success  
- Complete audit trail of all actions
- Clear documentation of skipped operations
- Warning resolution guidance provided
- Validation report confirms configuration integrity

This approach ensures safe, repeatable deployments while maintaining flexibility for ongoing administration and customization.

## Formal Check Specification ("/specify check")

The following table and function contract list define the canonical validation logic. Each check returns a structured result object with properties: `Name`, `Type`, `Status` (Present|Missing|Warn|Error), `ActionTaken`, `Message`, `Details`.

### Object Type Validation Matrix

| Type | Precondition | Check Command (Conceptual) | Pass Criteria | Warn Criteria | Error Criteria | Action on Missing |
|------|--------------|----------------------------|---------------|---------------|----------------|------------------|
| OU | AD reachable | Get-ADOrganizationalUnit | OU DN found | N/A | Lookup failure | Create OU |
| Group | AD reachable | Get-ADGroup | Group found | N/A | Lookup failure | Create group |
| User | AD reachable | Get-ADUser | User found | N/A | Lookup failure | Create user |
| OU ACL | OU + Group exist | Get-Acl / any ACE for group | Delegation group present | N/A | Cannot read ACL | Apply delegation ACE set |
| GPO | OU exists (if linking) | Get-GPO -Name | GPO found | N/A | Lookup failure | Create/import/configure |
| GPO Link Order | GPO + target OU exist | Get-GPInheritance | LinkOrder matches expected | LinkOrder mismatch | Cannot enumerate | Log warning only (no auto-fix) |
| ADMX Template | Source path valid | Enumerate source/destination | Template pair present both sides | Locale ADML missing | Copy failure | Import template pair |
| MSA ACL | OU + Group exist | Get-Acl / two-ACE model (CreateChild/DeleteChild + GenericAll on msDS-ManagedServiceAccount) | Both ACEs present for identity | N/A | Cannot read ACL | Apply two-ACE delegation |
| gMSA ACL | OU + Group exist | Get-Acl / two-ACE model (CreateChild/DeleteChild + GenericAll on msDS-GroupManagedServiceAccount) | Both ACEs present for identity | N/A | Cannot read ACL | Apply two-ACE delegation |
| dMSA ACL | OU + Group exist + Schema GUID resolved | Get-Acl / two-ACE model (CreateChild/DeleteChild + GenericAll on msDS-DelegatedManagedServiceAccount) | Both ACEs present for identity | N/A | Cannot read ACL / GUID resolution failure | Apply two-ACE delegation |
| WinLaps ACL | OU + Group exist + LAPS schema present + LAPS GPOs exist | Get-Acl + Find-LapsADExtendedRights (SELF ACE via AD: provider; Read/Reset via extended rights) | Self-permission, Read-permission, Reset-permission all present | N/A | Schema absent / LAPS module unavailable | Apply Set-LapsADComputerSelfPermission, Set-LapsADReadPasswordPermission, Set-LapsADResetPasswordPermission |
| WinLaps Decryptor | GPO exists + Group exists + LAPS schema present | Get-GPRegistryValue ADPasswordEncryptionPrincipal | Value present and matches NETBIOS\sAMAccountName of config group | N/A | GPO not found / group not found | Set-GPRegistryValue ADPasswordEncryptionPrincipal |

### Function Contracts

All test functions are pure (no side-effects) except when `-Apply` or Import cmdlets are invoked.

1. `Test-TierModelOu -DistinguishedName <string> [-Apply]`
2. `Test-TierModelGroup -Name <string> [-Apply]`
3. `Test-TierModelUser -SamAccountName <string> [-Apply]`
4. `Test-TierModelAcl -OuDistinguishedName <string> -Principal <string> -ExpectedRights <string[]> [-Apply]`
5. `Test-TierModelGpo -Name <string> -Mode <createAndImport|createImportAndConfigure> [-Apply]`
6. `Test-TierModelGpoLinkOrder -Ou <string> -ExpectedOrderMap <hashtable>`
7. `Get-TierModelAdmxState -SourcePath <string> -DefaultLocale <string>`
8. `Import-TierModelAdmx -SourcePath <string> -DefaultLocale <string> [-WhatIf]`
9. `Test-TierModelMsaAcl -Config <object> -DomainController <string> [-Silent] [-SuppressSummary]`
10. `Test-TierModelGmsaAcl -Config <object> -DomainController <string> [-Silent] [-SuppressSummary]`
11. `Test-TierModelDmsaAcl -Config <object> -DomainController <string> [-Silent] [-SuppressSummary]`
12. `Get-TierModelWinLapsAcl -Config <object> -DomainController <string> [-IncludeDetails]`
13. `Get-TierModelWinLapsAclFd -Config <object> -DomainController <string> [-IncludeDetails] [-Silent]`
14. `New-TierModelWinLapsAcl -Plan <object> -DomainController <string> -Config <object> [-WhatIf]`
15. `Test-TierModelWinLapsAcl -Config <object> -DomainController <string> [-Silent] [-SuppressSummary]`
16. `Test-TierModelWinLapsDecryptor -Config <object> -DomainController <string> [-Silent] [-SuppressSummary]`

### Result Object Shape (PowerShell PSCustomObject)
```
@{
    Name = 'Tier 1 PAWs Account Restrictions'
    Type = 'GPO'
    Status = 'Present'
    ActionTaken = 'None'
    Message = 'GPO already exists.'
    Details = @{ LinkOrderExpected = 1; LinkOrderActual = 1 }
}
```

### Automated Testing Coverage

The TierModel includes comprehensive Pester test suites covering all deployment components:

**Unit Tests:**
- `Unit.OuOperations.Tests.ps1` - OU creation and validation
- `Unit.GroupOperations.Tests.ps1` - Group creation and membership
- `Unit.UserOperations.Tests.ps1` - User account operations
- `Unit.OuAclOperations.Tests.ps1` - ACL delegation logic
- `Unit.MsaAclOperations.Tests.ps1` - MSA ACL delegation planning, execution, and audit
- `Unit.GmsaAclOperations.Tests.ps1` - gMSA ACL delegation planning, execution, and audit
- `Unit.DmsaAclOperations.Tests.ps1` - dMSA ACL delegation planning, execution, and audit
- `Unit.WinLapsAclOperations.Tests.ps1` - Windows LAPS ACL delegation planning, execution, audit, and decryptor validation
- `Unit.GpoOperations.Tests.ps1` - GPO creation and import
- `Unit.GpoLinking.Tests.ps1` - GPO linking logic
- `Unit.GpoTemplates.Tests.ps1` - GPO template generation (URA, Restricted Groups)
- `Unit.AdmxImport.Tests.ps1` - ADMX template operations

**Integration Tests:**
- `Integration.Deploy.Tests.ps1` - End-to-end deployment validation
- `Integration.Audit.Tests.ps1` - Audit functionality
- `Integration.DriftDetection.Tests.ps1` - Drift detection
- `Integration.Convergence.Tests.ps1` - Re-deployment idempotency
- `Integration.WinLapsDeployment.Tests.ps1` - Windows LAPS end-to-end deployment and idempotency

See `tests/TestCoverageRoadmap.md` in the repository for detailed test coverage analysis.

### Logging Conventions
| Level | Prefix | Example |
|-------|--------|---------|
| INFO | `[INFO]` | `[INFO] OU already exists: OU=Tier 1,DC=corp,DC=example,DC=com` |
| WARN | `[WARN]` | `[WARN] Link order mismatch for GPO *- Tier 1 PAWs SOE - Computer (Expected 2, Actual 3)` |
| ERROR | `[ERROR]` | `[ERROR] Failed to create group Tier1Operators: Access denied` |
| SUCCESS | `[SUCCESS]` | `[SUCCESS] Created GPO: *- Tier 2 PAWs BitLocker` |

### Idempotency Rules
- Creation only attempted when Status = Missing.
- No automatic remediation for WARN link order.
- ADMX import performed when files are missing or hash mismatches detected.
- Functions return Status = Missing; do not throw for absent objects.
- WhatIf/ShouldProcess support throughout for safe testing.

### Implemented Features
- ✅ MD5 hash verification for ADMX templates with update detection
- ✅ JSON schema validation (`tiermodel.schema.json`)
- ✅ WhatIf/ShouldProcess support across all cmdlets
- ✅ Comprehensive unit and integration test coverage
- ✅ Deployment convergence and idempotency validation

### Future Enhancements
- Deep GPO policy drift detection (individual setting comparison)
- Multi-locale ADMX import support (currently en-US only)
- Extended dry-run risk summary (counts by resource & risk level)

## Related Documentation

For additional documentation, see:
- [Quick Deployment Guide](quick-deployment-guide.md)
- [Detailed Deployment Guide](detailed-deployment-guide.md)
- [Drift Detection Details](drift-detection-details.md)
- Test Coverage Roadmap: `tests/TestCoverageRoadmap.md` (in repository)
- [CI/CD](ci-cd.md)
