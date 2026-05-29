# Implementation Plan: Managed Service Account Support (MSA, gMSA, dMSA)

**Feature Branch**: `002-gmsa-support`  
**Spec**: `specs/002-gmsa-support/spec.md`  
**Created**: 2026-05-29  
**Status**: Draft

---

## Technical Context

- **Stack**: PowerShell 5.1+, Active Directory, Pester
- **Module**: `modules/TierModel/` with public functions in `modules/TierModel/public/`
- **Deployment Script**: `Deploy-TierModel.ps1` — orchestrates Get-*/New-* cmdlet pattern
- **Audit Script**: `Audit-TierModel.ps1` — mirrors deployment for drift detection
- **Config**: Segmented JSON under `config/` — OUs, groups, ACLs, GPOs, etc.
- **GUID Mappings**: `config/tiermodel-guid-mappings.json` — static + dynamic schema GUIDs
- **Existing Pattern**: `Get-TierModelX` (plan) → `New-TierModelX` (apply) for deployment; `Test-TierModelX` for audit/drift
- **Full Deployment Order**: OUs → Groups → Users → OU ACL Delegations → GPOs → ADMX → **Optional Features**
- **Lab**: Hyper-V DC `TierLab-DC01` at `192.168.100.10`, domain `tierlab.internal`, checkpoint `DC-Promoted-Clean`

### Research References

- **Technical Deep-Dive**: `.research/ad-msa-delegation/research/technical-deep-dive.md`
- **Market Landscape**: `.research/ad-msa-delegation/research/market-landscape.md`
- **Lab Configuration**: `.research/copilot-cli-hyperv-ad-lab/specs/lab-configuration.md`

---

## Constitution Check

| Principle | Compliant | Notes |
|-----------|-----------|-------|
| I. Code Quality | ✅ | New cmdlets follow existing module patterns |
| II. Test-First with Pester | ⚠️ Deferred | Per Joel: Pester tests written AFTER code works via manual UAT |
| III. Idempotent Deployments | ✅ | ACL delegation checks for existing ACEs before applying |
| IV. Zero-Unintended-Impact | ✅ | -WhatIf / planning mode; -ConfirmApply required |
| V. Drift Detection | ✅ | Audit cmdlets reuse Get-* + Test-* pattern |
| VI. Structured Observability | ✅ | Write-TierModelLog with CorrelationId |
| VII. Simplicity & Explicitness | ✅ | Switch parameters, no hidden behavior |
| VIII. Modular Decomposition | ✅ | New cmdlets per entity, no monolith |
| IX. Dependency Governance | ✅ | Schema GUIDs in mapping file, versions pinned |

**Constitution deviation**: Pester tests are intentionally deferred until after manual UAT confirms code is working. This is Joel's explicit workflow choice for this feature.

---

## Prerequisites Analysis (from Research)

### MSA (Managed Service Account)
- **Schema version**: ≥ 47 (Windows Server 2008 R2)
- **Domain functional level**: None specified beyond OS
- **KDS Root Key**: NOT required
- **Object class**: `msDS-ManagedServiceAccount`
- **Schema-Id-Guid**: `ce206244-5827-4a86-ba1c-1c0c386c1b64`

### gMSA (Group Managed Service Account)
- **Schema version**: ≥ 56 (Windows Server 2012)
- **Domain functional level**: Windows2012Domain
- **KDS Root Key**: REQUIRED (effective, not just created)
- **Object class**: `msDS-GroupManagedServiceAccount`
- **Schema-Id-Guid**: `7b8b558a-93a5-4af7-adca-c017e67f1057`

### dMSA (Delegated Managed Service Account)
- **Schema version**: ≥ 91 (Windows Server 2025)
- **Domain/Forest functional level**: Windows2025Domain AND Windows2025Forest
- **KDS Root Key**: REQUIRED
- **Object class**: `msDS-DelegatedManagedServiceAccount`
- **Schema-Id-Guid**: Must be queried from live schema (not in public docs yet)
- **Additional**: Client machines need `DelegatedMSAEnabled = 1` registry key

### Fail-Fast Decision Tree

```
For each -Include* switch:
  1. Check schema version >= required → FAIL with remediation if not
  2. Check domain/forest functional level → FAIL with remediation if not
  3. For gMSA/dMSA, run Invoke-Command -ComputerName $PreferredDomainController { Get-KdsRootKey }:
     - FAIL if no KDS root key exists
     - FAIL if the effective key is not older than 10 hours
     - Tier Model NEVER runs Add-KdsRootKey; provide remediation only
  4. Check schema class exists in schema partition → FAIL with remediation if not
  5. Check target OUs exist (Tier X Service Accounts) → FAIL: "Run -FullDeployment first" or deploy OUs
  6. Check delegation groups exist (Tier X Admins) → FAIL: "Run -FullDeployment first" or deploy groups
  ALL PASS → proceed with ACL delegation
```

---

## Deployment Flow Design

### Standalone Mode (`-IncludeGmsa` only, no `-FullDeployment`)

```
1. Load merged config via Get-TierModelConfig + validate prerequisites
2. Run MSA-specific prerequisites (schema, FL, KDS via remoting, class existence)
3. Verify OUs exist (Tier 0/1/2 Service Accounts) → fail-fast if missing
4. Verify Groups exist (Tier0Admins, Tier1Admins, Tier2Admins) → fail-fast if missing
5. Select account-type ACL definitions from the merged config object
6. Get-TierModelMsaAcl → generate ACL plan (what to add/skip)
7. Display plan using Summary.TotalActions, Summary.CreateActions, and Summary.RiskAssessment
8. If -ConfirmApply: New-TierModelMsaAcl → apply ACL delegations
9. Report results
```

### Full Deployment Mode (`-FullDeployment -IncludeGmsa`)

```
1. Load merged config via Get-TierModelConfig + validate standard prerequisites
2. Deploy: OUs → Groups → Users → OU ACL Delegations → GPOs → ADMX (standard)
3. === OPTIONAL FEATURES SECTION ===
   (Not numbered — optional features run after ADMX, the last standard step)
4. For each -Include* switch present:
   a. Run MSA-specific prerequisites (schema, FL, KDS via remoting, class existence)
   b. Planning mode: validate OUs/groups against CONFIGURED state (they will exist after standard deploy)
      Apply mode: validate OUs/groups exist in LIVE AD (standard deploy already ran)
      If standard deploy failed: SKIP optional features entirely
   c. Select account-type ACL definitions from the merged config object
   d. Get-TierModelMsaAcl → plan
   e. If -ConfirmApply: New-TierModelMsaAcl → apply
5. Report consolidated results (standard + optional)
```

### Plan Output Contract

All new planning/output paths must align with the existing cmdlet schema:
- `Summary.TotalActions`
- `Summary.CreateActions`
- `Summary.RiskAssessment`

No new `TotalInConfig` / `ToCreate` / `ExistingCount` summary contract is introduced for this feature.

### Parameter Validation Design

The `-Include*` switches are **not** scope parameters. They are optional feature add-ons:

```powershell
# Valid combinations:
-FullDeployment                           # standard only (existing behavior, unchanged)
-FullDeployment -IncludeMsa               # standard + MSA delegation
-FullDeployment -IncludeMsa -IncludeGmsa  # standard + MSA + gMSA delegation
-IncludeGmsa                              # standalone gMSA delegation only
-IncludeMsa -IncludeGmsa                  # standalone MSA + gMSA delegation

# Invalid combinations:
-OuOnly -IncludeGmsa                      # ERROR: -Include* only with -FullDeployment or standalone
-GroupOnly -IncludeMsa                     # ERROR: same
(no switches at all)                      # ERROR: must specify scope or -Include*
```

Recommended validation:
```powershell
$scopeCount = @($scopeParameters | Where-Object { $_ }).Count
$includeCount = @($includeParameters | Where-Object { $_ }).Count

if ($scopeCount -eq 0 -and $includeCount -eq 0) {
    Write-Error "Specify exactly one deployment scope or one or more -Include* switches."
}
elseif ($scopeCount -gt 1) {
    Write-Error "Only one deployment scope can be specified."
}
elseif ($includeCount -gt 0 -and $scopeCount -eq 1 -and -not $FullDeployment) {
    Write-Error "-Include* switches can be used standalone or with -FullDeployment only."
}
```

---

## New Files to Create

### JSON Configuration Files

| File | Purpose | Based On |
|------|---------|----------|
| `config/tiermodel-msa-acls.json` | MSA ACL delegation definitions | `tiermodel-acls.json` structure |
| `config/tiermodel-gmsa-acls.json` | gMSA ACL delegation definitions | `tiermodel-acls.json` structure |
| `config/tiermodel-dmsa-acls.json` | dMSA ACL delegation definitions | `tiermodel-acls.json` structure |

Each follows the `tiermodel-acls.json` schema pattern with an added type marker for validation:
```json
{
  "version": "1.0.0",
  "managedServiceAccountType": "gMSA",
  "comment": "gMSA ACL delegations for Tier Model...",
  "aclDelegations": [
    {
      "targetOUPath": "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{DOMAIN_DN}}",
      "identityreference": "Tier1Admins",
      "activedirectoryrights": ["CreateChild", "DeleteChild"],
      "accesscontroltype": "Allow",
      "objecttype": "msDS-GroupManagedServiceAccount",
      "activeDirectorysecurityinheritance": "All",
      "resolveguid": true,
      "comment": "Grant Tier1Admins create/delete for gMSA objects in Tier 1 Service Accounts"
    },
    {
      "targetOUPath": "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{DOMAIN_DN}}",
      "identityreference": "Tier1Admins",
      "activedirectoryrights": ["GenericAll"],
      "accesscontroltype": "Allow",
      "objecttype": "AllObjectClasses",
      "inheritedObjectType": "msDS-GroupManagedServiceAccount",
      "activeDirectorysecurityinheritance": "Descendents",
      "resolveguid": true,
      "comment": "Grant Tier1Admins full control over descendant gMSA objects in Tier 1 Service Accounts"
    }
  ]
}
```

**Config loading decision**:
- `Get-TierModelConfig.ps1` adds the three new ACL JSON files to its file list via a new `$optionalFiles` array.
- These files are loaded when present and merged into the returned config object; they are **not** added to `$requiredFiles`.
- MSA/gMSA/dMSA cmdlets consume the merged config object passed through deployment/audit flows. They do **not** load JSON directly.

**Rights model (decided)**:
- Match the existing delegation pattern already used for Tier 1/2 Accounts, PAW Devices, and Groups OUs.
- Per tier and account type, define exactly two ACEs on the relevant Service Accounts OU:
  1. `CreateChild`/`DeleteChild` scoped to the object class GUID on the OU
  2. `GenericAll` on descendant objects of that class
- Tier 1/2 ACEs are restricted to their respective `Tier X Service Accounts` OUs only.
- Tier 0 first verifies whether inherited parent-OU full control already covers MSA/gMSA/dMSA; add explicit Tier 0 ACEs only where that verification shows coverage is missing.

### PowerShell Module Cmdlets

Each account type gets its own cmdlet set following the established `Get-` (plan) / `New-` (apply) / `Test-` (audit) pattern, plus FD (Full Deployment) variants:

**MSA Cmdlets:**

| Cmdlet | Purpose | Pattern |
|--------|---------|---------|
| `Get-TierModelMsaAcl.ps1` | Plan MSA ACL delegations — standalone mode (validates OUs/groups exist in live AD) | Like `Get-TierModelOuAcl.ps1` |
| `Get-TierModelMsaAclFd.ps1` | Plan MSA ACL delegations — full deployment mode (lighter validation, assumes OUs/groups from earlier phases) | Like `Get-TierModelOuAclFd.ps1` |
| `New-TierModelMsaAcl.ps1` | Apply MSA ACL delegations from plan | Like `New-TierModelOuAcl.ps1` |
| `Test-TierModelMsaAcl.ps1` | Audit/drift check for MSA ACL delegations | Like `Test-TierModelOuAcl.ps1` |

**gMSA Cmdlets:**

| Cmdlet | Purpose | Pattern |
|--------|---------|---------|
| `Get-TierModelGmsaAcl.ps1` | Plan gMSA ACL delegations — standalone mode | Like `Get-TierModelOuAcl.ps1` |
| `Get-TierModelGmsaAclFd.ps1` | Plan gMSA ACL delegations — full deployment mode | Like `Get-TierModelOuAclFd.ps1` |
| `New-TierModelGmsaAcl.ps1` | Apply gMSA ACL delegations from plan | Like `New-TierModelOuAcl.ps1` |
| `Test-TierModelGmsaAcl.ps1` | Audit/drift check for gMSA ACL delegations | Like `Test-TierModelOuAcl.ps1` |

**dMSA Cmdlets:**

| Cmdlet | Purpose | Pattern |
|--------|---------|---------|
| `Get-TierModelDmsaAcl.ps1` | Plan dMSA ACL delegations — standalone mode | Like `Get-TierModelOuAcl.ps1` |
| `Get-TierModelDmsaAclFd.ps1` | Plan dMSA ACL delegations — full deployment mode | Like `Get-TierModelOuAclFd.ps1` |
| `New-TierModelDmsaAcl.ps1` | Apply dMSA ACL delegations from plan | Like `New-TierModelOuAcl.ps1` |
| `Test-TierModelDmsaAcl.ps1` | Audit/drift check for dMSA ACL delegations | Like `Test-TierModelOuAcl.ps1` |

**Total: 12 new cmdlets** (4 per account type × 3 account types)

> **Naming rationale**: The `MsaAcl`/`GmsaAcl`/`DmsaAcl` suffixes make it explicit these cmdlets manage ACL delegations, not MSA objects themselves. This follows the existing `OuAcl`/`OuAclFd` naming pattern and avoids confusion with `New-ADServiceAccount`. Separate cmdlets per type allow independent deployment (`-IncludeMsa` only, `-IncludeGmsa` only, etc.) without loading or validating unneeded types.

### Implementation Guardrails

- Keep each new cmdlet self-contained, matching the existing codebase pattern. Do **not** introduce shared private orchestration helpers such as `Invoke-TierModelAclPlan` or `Invoke-TierModelAclApply`.
- Every `New-TierModel*Acl` cmdlet must guard resolved GUID values before creating an ACE. If a GUID is `$null`, `''`, or `[Guid]::Empty`, throw a terminating error. This is security-critical to prevent over-scoped ACEs.
- All new cmdlets must use DC-qualified LDAP binding: `"LDAP://$DomainController/$targetOUPath"`.
- Parameter names remain PascalCase only: `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`.

### Prerequisites — Integrated into Existing Cmdlet

MSA/gMSA/dMSA prerequisites will be added to the **existing** `Test-TierModelPrerequisites.ps1` rather than creating a new standalone cmdlet. This keeps all prerequisite validation in one place and follows the established pattern where `Deploy-TierModel.ps1` calls `Test-TierModelPrerequisites` early in the flow.

**Changes to `Test-TierModelPrerequisites.ps1`:**

| New Parameter | Checks Added |
|---------------|-------------|
| `-IncludeMsa` | Schema version ≥ 47; `msDS-ManagedServiceAccount` class exists in schema |
| `-IncludeGmsa` | Schema version ≥ 56; DFL ≥ Windows2012Domain; KDS root key exists and effective (> 10 hours old) via `Invoke-Command -ComputerName $PreferredDomainController`; `msDS-GroupManagedServiceAccount` class exists in schema |
| `-IncludeDmsa` | Schema version ≥ 91; DFL = Windows2025Domain; FFL = Windows2025Forest; KDS root key exists and effective (> 10 hours old) via `Invoke-Command -ComputerName $PreferredDomainController`; `msDS-DelegatedManagedServiceAccount` class exists in schema (resolved from `classSchema`) |

**Prerequisite results** will be added to the existing `EnvironmentSnapshot` object and reported in the existing `Errors`/`Remediation` arrays. Example:

```powershell
# When -IncludeGmsa is specified:
$result.EnvironmentSnapshot.SchemaVersion = 91
$result.EnvironmentSnapshot.DomainFunctionalLevel = 'Windows2025Domain'
$result.EnvironmentSnapshot.KdsCheckedOn = $PreferredDomainController
$result.EnvironmentSnapshot.KdsRootKeyExists = $true
$result.EnvironmentSnapshot.KdsRootKeyEffective = $true
$result.EnvironmentSnapshot.GmsaSchemaClassExists = $true

# If KDS root key is missing or not yet effective:
$result.Errors.Add("KDS Root Key is required for gMSA. No effective key older than 10 hours was found on $PreferredDomainController.")
$result.Remediation.Add("Create a KDS root key outside Tier Model operations, wait until the effective time is more than 10 hours old, then rerun deployment.")
```

> **Design rationale**: `Test-TierModelPrerequisites` already checks PS version, modules, elevation, domain connectivity, and domain admin membership. MSA/gMSA/dMSA prerequisites are domain-level checks that naturally belong here. The `-Include*` switch parameters pass through from `Deploy-TierModel.ps1` so the prereq check only validates what's actually being deployed.
>
> **KDS constraint**: The Tier Model prereq check is read-only. It checks for an existing KDS root key on the preferred domain controller and verifies the key is older than 10 hours, but it never runs `Add-KdsRootKey`. If remote `Get-KdsRootKey` requires an explicit dependency declaration, update `config/dependencies.json` accordingly.

### GUID Mappings Update

Add to `config/tiermodel-guid-mappings.json` `staticMappings.objectClasses`:
```json
"msDS-ManagedServiceAccount": "ce206244-5827-4a86-ba1c-1c0c386c1b64",
"msDS-GroupManagedServiceAccount": "7b8b558a-93a5-4af7-adca-c017e67f1057"
```

Add to `config/tiermodel-guid-mappings.json` `dynamicMappings` (new `objectClasses` section):
```json
"objectClasses": {
  "msDS-DelegatedManagedServiceAccount": "{{resolve_guid:msDS-DelegatedManagedServiceAccount}}"
}
```

Note: dMSA GUID must be resolved dynamically from live schema (not in public docs). `Resolve-DomainSpecificGuid.ps1` will be extended with a `-SchemaObjectClass` parameter whose default remains `attributeSchema`; dMSA callers pass `-SchemaObjectClass classSchema`. No inline schema resolution alternative is planned.

---

## Files to Modify (Existing)

| File | Change | Scope |
|------|--------|-------|
| `Deploy-TierModel.ps1` | Add `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switch params; add optional features section after ADMX in full deployment; add standalone `-Include*` support; pass `-Include*` switches to `Test-TierModelPrerequisites` | Moderate |
| `Audit-TierModel.ps1` | Add `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switch params; integrate `Test-TierModelMsaAcl`/`Test-TierModelGmsaAcl`/`Test-TierModelDmsaAcl` | Moderate (AFTER deployment works) |
| `Test-TierModelPrerequisites.ps1` | Add `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switch params; add schema version, functional level, KDS remoting, and schema class existence checks per type | Moderate |
| `modules/TierModel/public/Get-TierModelConfig.ps1` | Add new `$optionalFiles` handling so `tiermodel-msa-acls.json`, `tiermodel-gmsa-acls.json`, and `tiermodel-dmsa-acls.json` load when present and merge into the returned config object | Moderate |
| `modules/TierModel/public/Resolve-DomainSpecificGuid.ps1` | Add `-SchemaObjectClass` parameter (default `attributeSchema`) so dMSA can resolve against `classSchema` | Minor |
| `config/tiermodel-guid-mappings.json` | Add MSA/gMSA/dMSA GUIDs | Minor |
| `config/dependencies.json` | Add KDS module dependency only if required for remote `Get-KdsRootKey` prerequisite checks | Minor |
| `modules/TierModel/TierModel.psd1` | Export new public functions | Minor |

**Existing-code changes remain tightly scoped**: deployment/audit/prereq/config/GUID-resolution orchestration plus the new cmdlets. No `Remove-TierModel*Acl` rollback cmdlet is planned; idempotent rerun is the convergence model.

---

## Rights Model Application by Tier

- **Tier 0**: Verify whether existing inherited full control from the parent OU already covers MSA/gMSA/dMSA create/delete and descendant-object control in `Tier 0 Service Accounts`. Add explicit type-specific ACEs only if that verification shows a gap.
- **Tier 1**: Apply the standard two-ACE pattern only to `Tier 1 Service Accounts`.
- **Tier 2**: Apply the standard two-ACE pattern only to `Tier 2 Service Accounts`.

This keeps the feature aligned with the established delegation boundary: Service Account delegations stay scoped to their own per-tier Service Accounts OUs and do not broaden into adjacent OUs.

---

## Phased Implementation & Approval Gates

### Phase 1: Foundation — New Cmdlets + Standalone Deployment
**Scope**: Create all new cmdlets and standalone `-Include*` deployment (no full deployment integration yet)

| Step | Task | Approval |
|------|------|----------|
| 1.1 | Create optional JSON config files (`tiermodel-msa-acls.json`, `tiermodel-gmsa-acls.json`, `tiermodel-dmsa-acls.json`) | — |
| 1.2 | Update `Get-TierModelConfig.ps1` with `$optionalFiles` loading/merge behavior for the new ACL segments | — |
| 1.3 | Update `tiermodel-guid-mappings.json` with MSA/gMSA static GUIDs + dMSA dynamic mapping; extend `Resolve-DomainSpecificGuid.ps1` with `-SchemaObjectClass` | — |
| 1.4 | Update `Test-TierModelPrerequisites.ps1` — add `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switch params with schema, FL, KDS remoting, and class checks | — |
| 1.5 | Create MSA cmdlets: `Get-TierModelMsaAcl.ps1`, `New-TierModelMsaAcl.ps1` | — |
| 1.6 | Create gMSA cmdlets: `Get-TierModelGmsaAcl.ps1`, `New-TierModelGmsaAcl.ps1` | — |
| 1.7 | Create dMSA cmdlets: `Get-TierModelDmsaAcl.ps1`, `New-TierModelDmsaAcl.ps1` | — |
| 1.8 | Update `Deploy-TierModel.ps1` — add `-Include*` switches for standalone mode; pass to `Test-TierModelPrerequisites` | — |
| 1.9 | Update module manifest to export new functions | — |
| 1.10 | **Lab test: standalone `-IncludeMsa` only (simplest — no KDS needed)** | ⏸️ **Joel UAT** |
| 1.11 | **Lab test: standalone `-IncludeGmsa` only (KDS required)** | ⏸️ **Joel UAT** |
| 1.12 | **Lab test: standalone `-IncludeDmsa` only (WS2025 FL required)** | ⏸️ **Joel UAT** |
| 1.13 | **Lab test: standalone `-IncludeMsa -IncludeGmsa` combined** | ⏸️ **Joel UAT** |

### Phase 2: Full Deployment Integration
**Scope**: Integrate `-Include*` into `-FullDeployment` as optional features after ADMX; create FD variants

| Step | Task | Approval |
|------|------|----------|
| 2.1 | Create FD variants: `Get-TierModelMsaAclFd.ps1`, `Get-TierModelGmsaAclFd.ps1`, `Get-TierModelDmsaAclFd.ps1` | — |
| 2.2 | Update `Deploy-TierModel.ps1` — add optional features section after ADMX using FD variants | — |
| 2.3 | Ensure plan reporting includes optional features in consolidated summary | — |
| 2.4 | **Lab test: `-FullDeployment -IncludeGmsa` on lab DC** | ⏸️ **Joel UAT** |
| 2.5 | **Lab test: `-FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa` on lab DC** | ⏸️ **Joel UAT** |

### Phase 3: Audit Integration
**Scope**: Add MSA/gMSA/dMSA drift detection to `Audit-TierModel.ps1`

| Step | Task | Approval |
|------|------|----------|
| 3.1 | Create audit cmdlets: `Test-TierModelMsaAcl.ps1`, `Test-TierModelGmsaAcl.ps1`, `Test-TierModelDmsaAcl.ps1` | — |
| 3.2 | Update `Audit-TierModel.ps1` with `-Include*` switches + per-type `Test-TierModel*Acl` integration | — |
| 3.3 | **Lab test: audit after deployment, audit after manual ACL removal** | ⏸️ **Joel UAT** |

### Phase 4: Pester Tests & Documentation
**Scope**: Unit tests and documentation (AFTER code confirmed working)

| Step | Task | Approval |
|------|------|----------|
| 4.1 | Write Pester unit tests for `Test-TierModelPrerequisites` (MSA/gMSA/dMSA checks only) | — |
| 4.2 | Write Pester unit tests for `Get-TierModelMsaAcl`, `Get-TierModelGmsaAcl`, `Get-TierModelDmsaAcl` | — |
| 4.3 | Write Pester unit tests for `New-TierModelMsaAcl`, `New-TierModelGmsaAcl`, `New-TierModelDmsaAcl` | — |
| 4.4 | Write Pester unit tests for `Test-TierModelMsaAcl`, `Test-TierModelGmsaAcl`, `Test-TierModelDmsaAcl` (audit) | — |
| 4.5 | Write Pester unit tests for FD variants | — |
| 4.6 | Update documentation (README, docs/) | — |
| 4.7 | **Final review** | ⏸️ **Joel approval** |

---

## Lab Testing Workflow

Each phase uses the Hyper-V AD lab for validation:

```
1. Restore checkpoint: Restore-VMCheckpoint -VMName "TierLab-DC01" -Name "DC-Promoted-Clean" -Confirm:$false
2. Copy module files to DC via PowerShell Direct
3. Run deployment in planning mode (verify plan output)
4. Run deployment with -ConfirmApply (verify ACLs applied)
5. Run deployment again (verify idempotency — 0 changes)
6. Verify ACLs on OU via Get-OuDelegationForObjectType (from research)
7. If issues: fix code, restore checkpoint, retry from step 2
```

**Lab credentials**: `TIERLAB\Administrator` / `LabPass123!`  
**Transport**: PowerShell Direct (no WinRM/SMB needed)  
**Rollback**: Production checkpoint `DC-Promoted-Clean`

---

## Risks & Mitigations (Implementation-Specific)

| Risk | Mitigation |
|------|------------|
| dMSA schema GUID not in public docs | Query from live WS2025 schema through `Resolve-DomainSpecificGuid -SchemaObjectClass classSchema`; store in dynamic mapping |
| Lab domain may not have WS2025 FL for dMSA testing | Test MSA + gMSA first; dMSA testing requires FL raise in lab |
| Existing Tier 0 GenericAll may cause idempotency check to skip ACLs | Verify Tier 0 inherited coverage explicitly, and only add explicit ACEs if coverage is missing |
| A null/empty resolved GUID could create an over-scoped ACE | Terminating guard in every `New-TierModel*Acl` cmdlet before ACE creation |
| `-Include*` switches change Deploy-TierModel.ps1 parameter validation | Current validation requires exactly 1 scope param; `-Include*` must be allowed alongside `-FullDeployment` or standalone |

---

## Rubber-Duck Review Decisions Incorporated

- Rights model is fixed: match the existing per-tier delegation pattern with two ACEs per tier per account type.
- dMSA GUID resolution is fixed: extend `Resolve-DomainSpecificGuid.ps1` with `-SchemaObjectClass`; use `classSchema` for dMSA.
- Security guard is mandatory: every `New-TierModel*Acl` cmdlet throws if a resolved GUID is null, empty, or `[Guid]::Empty`.
- Cmdlets remain self-contained; no shared private ACL orchestration helpers are introduced.
- Config loading is centralized in `Get-TierModelConfig.ps1` using optional config segments, not direct JSON loading in cmdlets.
- LDAP binding is DC-qualified in all new cmdlets: `LDAP://$DomainController/$targetOUPath`.
- KDS validation is read-only and remote: `Invoke-Command -ComputerName $PreferredDomainController { Get-KdsRootKey }`.
- No rollback cmdlet is planned; idempotent rerun remains the convergence strategy.
- Parameter names stay PascalCase: `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`.
- Output/reporting references the existing summary fields: `TotalActions`, `CreateActions`, `RiskAssessment`.

---

## Summary

- **12 new cmdlets** (4 per account type: `Get-*Acl`, `Get-*AclFd`, `New-*Acl`, `Test-*Acl`) + **3 new optional JSON config files** + **6 focused script/config updates** (`Deploy-TierModel.ps1`, `Audit-TierModel.ps1`, `Test-TierModelPrerequisites.ps1`, `Get-TierModelConfig.ps1`, `Resolve-DomainSpecificGuid.ps1`, `tiermodel-guid-mappings.json`) + optional `dependencies.json` update if needed for KDS prereq declaration
- **No rollback cmdlet** — only new code and tightly scoped orchestration/config updates
- **4 phases** with approval gates between each
- **Lab-tested** at each phase before proceeding
- **Pester tests last** — after manual UAT confirms working code