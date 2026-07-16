# Cmdlet Architecture

## Overview
This document outlines the modular cmdlet architecture that separates Full Deployment (`-FullDeployment`) cmdlets from phase-specific cmdlets. This separation improves testability, maintainability, and allows different validation strategies for different deployment modes.

## Problem Statement
The current implementation has validation conflicts between two different deployment modes:

### Phase-Specific Modes (`-GroupOnly`, `-UserOnly`, etc.)
- **Philosophy**: Fail fast and hard with strict checks
- **Assumption**: Prerequisites have already been created by previous phases
- **Validation**: Must verify that dependencies exist (e.g., OUs exist before creating groups)
- **Use Case**: Incremental deployment where each phase is run manually one-by-one

### Full Deployment Mode (`-FullDeployment`)
- **Philosophy**: Plan ahead and assume dependencies will be created in correct order
- **Assumption**: All phases will be executed in sequence automatically
- **Validation**: Lighter checks - only verify if target objects exist, not their dependencies
- **Use Case**: Automated deployment of entire tier model in one execution

## Current Issues
- Get-TierModel cmdlets are designed for phase-specific mode with strict validation
- `-FullDeployment` attempts to use these same cmdlets but needs different validation logic
- Results in failures because cmdlets expect prerequisites to already exist
- Constant risk of breaking existing functionality when modifying validation logic

## Proposed Solution

### Create Separate Cmdlet Variants for Full Deployment
Duplicate existing Get-TierModel cmdlets and create "Fd" (Full Deployment) variants:

#### Phase 1 (OU Creation)
- No changes needed - has no dependencies

#### Phase 2 (Group Creation)
- **Current**: `Get-TierModelGroup`
- **New**: `Get-TierModelGroupFd`
- **Validation Change**: Only check if group exists in AD, don't validate OU existence

#### Phase 3 (User Creation)
- **Current**: `Get-TierModelUser`
- **New**: `Get-TierModelUserFd`
- **Validation Change**: Only check if user exists in AD, assume OU and Groups will be created

#### Phase 4 (OU ACL Configuration)
- **Current**: `Get-TierModelOUAcl`
- **New**: `Get-TierModelOUAclFd`
- **Validation Change**: Check if ACL exists, assume OU and Groups will be created if missing

#### Phase 5 (GPO Management)
- **Current**: `Get-TierModelGPO`
- **New**: `Get-TierModelGPOFd`
- **Validation Change**: Check if GPO exists and is linked, assume OU and Groups will be created

#### Phase 6 (File Copy)
- No changes needed - has no dependencies on AD objects

### Implementation Strategy

#### Phase 1: Preparation
1. Create new feature branch
2. Remove existing `-FullDeployment` logic from Deploy-TierModel.ps1
3. Document current validation logic in existing cmdlets

#### Phase 2: Create Fd Variants
For each phase (2-5):
1. Copy existing `Get-TierModel*` cmdlet
2. Rename to `Get-TierModel*Fd`
3. Modify validation logic to remove dependency checks
4. Implement "plan-ahead" validation approach
5. Test independently

#### Phase 3: Integration
1. Update Deploy-TierModel.ps1 to use Fd variants when `-FullDeployment` is specified
2. Create `New-TierModel*Fd` cmdlets as needed
3. Test full deployment flow
4. Validate that existing phase-specific modes still work

## Validation Logic Changes

### Current Approach (Phase-Specific)
```
Phase 2 (Groups): 
- Check if OU exists → FAIL if missing
- Check if Group exists → Skip if exists, Create if missing

Phase 3 (Users):
- Check if OU exists → FAIL if missing  
- Check if Group exists → FAIL if missing
- Check if User exists → Skip if exists, Create if missing
```

### New Approach (Full Deployment)
```
Phase 2 (GroupsFd):
- Check if Group exists → Skip if exists, PLAN to create if missing
- Note: OU existence will be handled by Phase 1

Phase 3 (UsersFd):
- Check if User exists → Skip if exists, PLAN to create if missing
- Note: OU and Group existence will be handled by Phases 1 & 2
```

## Benefits
- **Stability**: Existing phase-specific cmdlets remain unchanged and stable
- **Clarity**: Clear separation between deployment modes
- **Maintainability**: Independent testing and development of each mode
- **Flexibility**: Can optimize each mode for its specific use case
- **Risk Reduction**: No more breaking existing functionality when adding new features

## Implementation Timeline
- **Week 1**: Create branch, remove existing FullDeployment logic
- **Week 2**: Implement Phase 2 (GroupsFd) and test
- **Week 3**: Implement Phase 3 (UsersFd) and test
- **Week 4**: Implement Phases 4-5 (ACL and GPO Fd variants)
- **Week 5**: Integration testing and documentation updates

## Success Criteria
- [ ] All existing phase-specific modes continue to work without changes
- [ ] `-FullDeployment` mode works without strict dependency validation
- [ ] Clear separation between cmdlet variants
- [ ] Comprehensive test coverage for both modes
- [ ] Documentation updated to reflect new architecture

## Phase 7: Managed Service Account (MSA) ACL Configuration (Optional)

MSA ACL delegation is an optional feature enabled with `-IncludeMsa` switch.

### Cmdlets
- **Get-TierModelMsaAcl** - Plan MSA ACL delegations (phase-specific)
  - Configuration + DomainController → validates MSA OUs/groups exist, checks ACL state → plan
  - Parameters: `-Config`, `-DomainController`, `-Silent`

- **Get-TierModelMsaAclFd** - Full deployment variant (lighter validation)
  - Assumes MSA objects created by prior steps
  - Parameters: `-Config`, `-DomainController`, `-Silent`

- **New-TierModelMsaAcl** - Apply MSA ACL delegations
  - Plan + DomainController + Config → applies ACLs via ADSI
  - Supports `-WhatIf`
  - Parameters: `-Plan`, `-DomainController`, `-Config`, `-WhatIf`

- **Test-TierModelMsaAcl** - Audit MSA ACL delegations
  - Configuration + DomainController → checks ACEs exist on msDS-ManagedServiceAccount objects
  - Returns: TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings
  - Parameters: `-Config`, `-DomainController`, `-Silent`, `-SuppressSummary`

### ACL Model
Two ACEs per MSA delegation:
1. CreateChild/DeleteChild scoped to msDS-ManagedServiceAccount class on the OU
2. GenericAll on descendant objects of msDS-ManagedServiceAccount class

## Phase 8: Group Managed Service Account (gMSA) ACL Configuration (Optional)

gMSA ACL delegation is an optional feature enabled with `-IncludeGmsa` switch.

### Cmdlets
- **Get-TierModelGmsaAcl** - Plan gMSA ACL delegations (phase-specific)
  - Configuration + DomainController → validates gMSA OUs/groups exist, checks ACL state → plan
  - Parameters: `-Config`, `-DomainController`, `-Silent`

- **Get-TierModelGmsaAclFd** - Full deployment variant (lighter validation)
  - Assumes gMSA objects created by prior steps
  - Parameters: `-Config`, `-DomainController`, `-Silent`

- **New-TierModelGmsaAcl** - Apply gMSA ACL delegations
  - Plan + DomainController + Config → applies ACLs via ADSI
  - Supports `-WhatIf`
  - Parameters: `-Plan`, `-DomainController`, `-Config`, `-WhatIf`

- **Test-TierModelGmsaAcl** - Audit gMSA ACL delegations
  - Configuration + DomainController → checks ACEs exist on msDS-GroupManagedServiceAccount objects
  - Returns: TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings
  - Parameters: `-Config`, `-DomainController`, `-Silent`, `-SuppressSummary`

### ACL Model
Two ACEs per gMSA delegation:
1. CreateChild/DeleteChild scoped to msDS-GroupManagedServiceAccount class on the OU
2. GenericAll on descendant objects of msDS-GroupManagedServiceAccount class

## Phase 9: Delegated Managed Service Account (dMSA) ACL Configuration (Optional)

dMSA ACL delegation is an optional feature enabled with `-IncludeDmsa` switch.

### Cmdlets
- **Get-TierModelDmsaAcl** - Plan dMSA ACL delegations (phase-specific)
  - Configuration + DomainController → validates dMSA OUs/groups exist, checks ACL state → plan
  - Parameters: `-Config`, `-DomainController`, `-Silent`

- **Get-TierModelDmsaAclFd** - Full deployment variant (lighter validation)
  - Assumes dMSA objects created by prior steps
  - Parameters: `-Config`, `-DomainController`, `-Silent`

- **New-TierModelDmsaAcl** - Apply dMSA ACL delegations
  - Plan + DomainController + Config → applies ACLs via ADSI
  - Supports `-WhatIf`
  - Parameters: `-Plan`, `-DomainController`, `-Config`, `-WhatIf`

- **Test-TierModelDmsaAcl** - Audit dMSA ACL delegations
  - Configuration + DomainController → checks ACEs exist on msDS-DelegatedManagedServiceAccount objects
  - Returns: TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings
  - Parameters: `-Config`, `-DomainController`, `-Silent`, `-SuppressSummary`

### ACL Model
Two ACEs per dMSA delegation:
1. CreateChild/DeleteChild scoped to msDS-DelegatedManagedServiceAccount class on the OU
2. GenericAll on descendant objects of msDS-DelegatedManagedServiceAccount class

## Phase 10: Windows LAPS ACL Delegation (Optional)

Windows LAPS delegation is an optional feature enabled with `-IncludeWinLaps` switch. It deploys 7 ACL delegations (Self-permission, Read-permission, Reset-permission per OU) **and** configures the `ADPasswordEncryptionPrincipal` GPO registry value on the 6 non-DC Windows LAPS GPOs.

> **Windows LAPS only** — this phase exclusively uses `ms-LAPS-*` schema attributes and the `LAPS` PowerShell module APIs. Legacy Microsoft LAPS (`ms-Mcs-AdmPwd*`, `AdmPwd.PS`) is never referenced.

### Cmdlets

- **Get-TierModelWinLapsAcl** — Plan Windows LAPS ACL delegations (phase-specific)
  - Configuration + DomainController → validates schema, LAPS module, DFL, OUs, groups, GPO existence → plan
  - Produces 3 `CreateAcl` actions per delegation (Self, Read, Reset) + `ConfigureLapsDecryptor` actions for non-DC entries
  - **Hard stop on missing schema:** if `ms-LAPS-Password` is absent, returns a plan error and never extends the schema
  - Parameters: `-Config`, `-DomainController`, `-IncludeDetails`

- **Get-TierModelWinLapsAclFd** — Full deployment variant (lighter validation)
  - Assumes OUs and groups will exist from earlier phases; schema/module/DFL checks still mandatory
  - Parameters: `-Config`, `-DomainController`, `-IncludeDetails`, `-Silent`

- **New-TierModelWinLapsAcl** — Apply Windows LAPS ACL delegations and decryptor configuration
  - Plan + DomainController + Config → calls `Set-LapsADComputerSelfPermission`, `Set-LapsADReadPasswordPermission`, `Set-LapsADResetPasswordPermission` for ACL actions
  - Calls `Set-GPRegistryValue ADPasswordEncryptionPrincipal` for `ConfigureLapsDecryptor` actions
  - Supports `-WhatIf`
  - Parameters: `-Plan`, `-DomainController`, `-Config`, `-WhatIf`

- **Test-TierModelWinLapsAcl** — Audit Windows LAPS DACL delegations
  - Configuration + DomainController → checks Self-permission (via `Get-Acl AD:` with LAPS schema GUID filter), Read-permission, Reset-permission (via `Find-LapsADExtendedRights`) on each target OU
  - Returns: TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings
  - Parameters: `-Config`, `-DomainController`, `-Silent`, `-SuppressSummary`

- **Test-TierModelWinLapsDecryptor** — Audit Windows LAPS GPO decryptor configuration
  - Configuration + DomainController → resolves each non-DC entry's `decryptorGpoName` pattern to an exact GPO, reads current `ADPasswordEncryptionPrincipal` value, compares case-insensitively against expected `NETBIOS\sAMAccountName`
  - Reports Compliant / Missing / Mismatched / Error per GPO
  - Domain Controllers OU (`isDomainControllerOu: true`) is skipped — DSRM always uses Domain Admins
  - Read-only — never modifies GPO settings
  - Returns: TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings (array of `{GpoName, Expected, Actual, Status}`)
  - Parameters: `-Config`, `-DomainController`, `-Silent`, `-SuppressSummary`

### Delegation Model

Per-OU delegation (7 OUs from `config/tiermodel-winlaps.json`):

| OU | Self | Read | Reset | Decryptor GPO |
|----|------|------|-------|---------------|
| Domain Controllers | ✅ Domain Admins | ✅ Domain Admins | ✅ Domain Admins | ❌ None (DSRM uses Domain Admins) |
| Tier 0 Member Servers | ✅ SELF | ✅ Tier 0 Server Operators | ✅ Tier 0 Server Operators | Tier 0 Servers LAPS GPO |
| Tier Model Administration (root) | ✅ SELF | ✅ Tier 0 Admins | ✅ Tier 0 Admins | Tier 0 PAWs LAPS GPO |
| Tier 1 Member Servers | ✅ SELF | ✅ Tier 1 Server Operators | ✅ Tier 1 Server Operators | Tier 1 Servers LAPS GPO |
| Tier 1 PAW Devices | ✅ SELF | ✅ Tier 1 Admins | ✅ Tier 1 Admins | Tier 1 PAWs LAPS GPO |
| Tier 2 PAW Devices | ✅ SELF | ✅ Tier 2 Admins | ✅ Tier 2 Admins | Tier 2 PAWs LAPS GPO |
| Tier 2 End-User Devices | ✅ SELF | ✅ Tier 2 Device Operators | ✅ Tier 2 Device Operators | Tier 2 EUD LAPS GPO |

### Tier Isolation Note

`ADPasswordEncryptionPrincipal` accepts a single principal per GPO. The configuration assigns each tier's GPO to that tier's admin/operator group. A Tier 0 admin holds `GenericAll` on lower-tier PAW OUs for management purposes but **cannot** use that to decrypt Tier 1 or Tier 2 PAW passwords — CNG-DPAPI decryption requires the exact encryption principal. This is the design intent.

## Related Documentation

For additional documentation, see:
- [Deployment Methodology](deployment-methodology.md)
- [Test Tag Matrix](test-tag-matrix.md)
- [CI/CD](ci-cd.md)

---
*Document created: November 21, 2025*  
*Status: Planning Phase*  
*Next Action: Create feature branch and begin implementation*