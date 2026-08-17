# Implementation Plan: Domain-Root Audit SACL (`-EnableAuditing`)

**Feature Branch**: `feature/domain-auditing`
**Spec**: `specs/004-domain-auditing/spec.md`
**Created**: 2026-08-14
**Status**: Draft

---

## Technical Context

- **Stack**: PowerShell 7.0+, Active Directory module (`AD:` PSDrive), Pester
- **Module**: `modules/TierModel/` with public functions in `modules/TierModel/public/`
- **Deployment Script**: `Deploy-TierModel.ps1` — orchestrates Get-*/New-* cmdlet pattern
- **Config**: Segmented JSON under `config/` — new `config/tiermodel-audit.json`
- **Existing Pattern**: `Get-TierModelX` (plan) → `New-TierModelX` (apply) for deployment; `Get-TierModelXFd` for FullDeployment pre-compute
- **Full Deployment Phase Order**: OUs → Groups → Users → OU ACLs → GPOs → ADMX → MSA → gMSA → dMSA → WinLaps → **AuditSacl (new)**
- **Lab**: Hyper-V DC `TierLab-DC01` at `192.168.100.10`, domain `tierlab.internal`
- **Spike**: `.research/copilot-cli-hyperv-ad-lab/scripts/audit-spike/Invoke-AuditSpikeRepro.ps1` — lab-validated converge recipe

### Research References

- **Locked design**: `.squad/decisions.md` (Decision: SACL Audit — Read API, Merge Behaviour, Converge Recipe)
- **UNION ruling**: `.squad/decisions/inbox/coordinator-audit-union-ruling.md`
- **Prior spike results**: See decisions.md Decision 1 through Decision 7

---

## Constitution Check

| Principle | Compliant | Notes |
|-----------|-----------|-------|
| I. Code Quality | ✅ | New cmdlets follow existing module patterns; comment-based help required |
| II. Test-First with Pester | ✅ | Pester suite authored BEFORE production implementation |
| III. Idempotent Deployments | ✅ | Converge recipe: no-write when single managed ACE satisfies union target |
| IV. Zero-Unintended-Impact | ✅ | No-clobber for non-managed ACEs; privilege check; planning mode default |
| V. Drift Detection | ✅ | `Test-TierModelAuditRule` + `Audit-TierModel.ps1 -EnableAuditing` |
| VI. Structured Observability | ✅ | `Write-TierModelLog` with CorrelationId |
| VII. Simplicity & Explicitness | ✅ | SACL vs DACL distinction explicit in prompts and docs; no hidden converge behavior |
| VIII. Modular Decomposition | ✅ | 4 cmdlets; single-responsibility; converge recipe isolated |
| IX. Dependency Governance | ✅ | `schemaVersion` in JSON; SHA-256 provenance hash includes optional segment |

---

## SACL Read/Write API (Lab-Validated)

```powershell
# Read SACL (requires SeSecurityPrivilege + AD: PSDrive)
Import-Module ActiveDirectory
$acl = Get-Acl -Path "AD:$domainDN" -Audit

# Enumerate managed ACEs — MUST use foreach, NOT @()
# @() wraps the AuthorizationRuleCollection as a 1-element array
foreach ($r in $acl.GetAuditRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
    # filter: SID=S-1-1-0, AuditFlags=Success, InheritanceType=All, IsInherited=false
}

# Converge: remove managed ACEs then add canonical union ACE (same $acl object)
foreach ($a in $managedAces) { $acl.RemoveAuditRuleSpecific($a) }
$acl.AddAuditRule(<canonical-union-rule>)
Set-Acl -Path "AD:$domainDN" -AclObject $acl
```

**Key gotcha**: `RemoveAuditRuleSpecific` silently no-ops if called on a different `$acl` object than the one the ACE was enumerated from. Read, modify, and write MUST use the same `$acl` object.

**Why not `PurgeAuditRules(SID)`**: Removes ALL `S-1-1-0` ACEs including `Everyone/Success/None` (Inherit=None) default domain SACL entries which are outside managed scope.

---

## Converge Recipe Decision Tree

```
Read $acl = Get-Acl -Path "AD:$domainDN" -Audit
│
Enumerate managed ACEs (SID=S-1-1-0, Success, All, non-inherited)
│
├─ 0 managed ACEs → Status = ABSENT
│   Plan: CreateAuditAce (rights = canonical 9)
│
├─ 1 managed ACE
│   Compute union = existingRights ∪ canonical9
│   ├─ union == existingRights (canonical 9 ⊆ existing) → Status = COMPLETE
│   │   No write. Converged = True.
│   └─ union != existingRights → Status = PARTIAL
│       Plan: RemoveAuditRuleSpecific + AddAuditRule(union)
│
└─ 2+ managed ACEs → Status = MULTI-ACE
    Compute union = (all managed rights) ∪ canonical9
    Plan: RemoveAuditRuleSpecific × N + AddAuditRule(union)
```

---

## New Files to Create

### Cmdlet Files

| File | Cmdlet | Responsibility |
|------|--------|----------------|
| `modules/TierModel/public/Get-TierModelAuditRule.ps1` | `Get-TierModelAuditRule` | Standalone planner — privilege check, SACL read, plan generation |
| `modules/TierModel/public/Get-TierModelAuditRuleFd.ps1` | `Get-TierModelAuditRuleFd` | FullDeployment planner — lighter, pre-compute friendly |
| `modules/TierModel/public/New-TierModelAuditRule.ps1` | `New-TierModelAuditRule` | Executor — converge recipe; `SupportsShouldProcess` |
| `modules/TierModel/public/Test-TierModelAuditRule.ps1` | `Test-TierModelAuditRule` | Audit checker — read-only, called by `Audit-TierModel.ps1` |

### Configuration File

| File | Purpose |
|------|---------|
| `config/tiermodel-audit.json` | Audit SACL configuration: target SID, flags, inheritance, rights list |

### Test Files

| File | Tags | Scope |
|------|------|-------|
| `tests/Unit.AuditRuleOperations.Tests.ps1` | Unit, AuditSacl | Converge recipe, no-clobber, union, idempotency, enumeration correctness |
| `tests/Unit.Prerequisites.Tests.ps1` | Unit, AuditSacl | Add context: privilege check conditional on `-EnableAuditing` |
| `tests/Integration.AuditDeployment.Tests.ps1` | Integration, AuditSacl | Live-DC: apply → verify → re-apply → idempotency; drift detection |

---

## Files to Modify (Existing)

| File | Change | Authorization |
|------|--------|---------------|
| `Deploy-TierModel.ps1` | Add `-EnableAuditing` switch parameter; audit SACL phase orchestration (standalone + FD modes); two-prompt confirmation UX | ✅ Feature requirement |
| `Audit-TierModel.ps1` | Add `-EnableAuditing` switch parameter; wire to `Test-TierModelAuditRule` conditional on switch | ✅ FR-002, FR-019 |
| `modules/TierModel/TierModel.psd1` | Add 4 new cmdlets to `FunctionsToExport`; bump version to `1.3.0` | ✅ Feature requirement |
| `modules/TierModel/public/Get-TierModelConfig.ps1` | Register `tiermodel-audit.json` in `$optionalFiles`; expose `auditSacl` property; include in SHA-256 hash | ✅ FR-017 |
| `modules/TierModel/public/Test-TierModelPrerequisites.ps1` | Add `-EnableAuditing` switch; conditional `SeSecurityPrivilege` check; `AUDITACL_PRIVILEGE_MISSING` error code | ✅ FR-008 |
| `config/tiermodel.schema.json` | Add `auditSacl` segment definition (additive; no existing properties modified) | ✅ FR-017 |

**No other existing module cmdlet is modified.**

---

## Parameter Validation Design

```powershell
# Valid:
-EnableAuditing                                    # standalone audit SACL
-EnableAuditing -ConfirmApply                      # standalone with apply (2 prompts)
-FullDeployment -EnableAuditing -ConfirmApply      # full deploy + audit SACL (2 prompts)
-FullDeployment -EnableAuditing                    # full deploy plan-only

# Invalid (parameter validation error):
-EnableAuditing -OuOnly
-EnableAuditing -GroupOnly
-EnableAuditing -UserOnly
-EnableAuditing -GposOnly
-EnableAuditing -OuAclsOnly
-EnableAuditing -AdmxOnly
```

---

## Privilege Check Design (`SeSecurityPrivilege`)

```powershell
# Check in Test-TierModelPrerequisites.ps1, conditional on -EnableAuditing
$privs = [System.Security.Principal.WindowsPrincipal]::new(
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
)
# Verify SE_SECURITY_NAME via token privilege enumeration
# If absent:
$result.Errors.Add("AUDITACL_PRIVILEGE_MISSING: ...")
$result.Valid = $false
```

---

## Confirmation UX Design

```
Invocation: Deploy-TierModel.ps1 -EnableAuditing -ConfirmApply

Step 1 — Audit Warning Prompt (new):
  ⚠️  AUDIT SACL WARNING ⚠️
  -EnableAuditing will write a SACL audit rule to the domain root object.
  ...
  Continue with audit SACL configuration? [Y/N]:
  → N: abort, zero writes
  → Y: continue to Step 2

Step 2 — Standard Deployment Confirm (existing):
  Are you sure you want to apply these changes? [Y/N]:
  → N: abort, zero writes
  → Y: apply
```

---

## Risk Register

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | Caller confuses SACL write with permission grant | High | Mandatory audit warning prompt; no "delegation" language |
| R2 | `@()` wrapping of `GetAuditRules()` collection | High | Explicit foreach; AC-ENUM-01 Pester test |
| R3 | `RemoveAuditRuleSpecific` on wrong `$acl` object silently no-ops | High | Read/modify/write must use same `$acl` object (FR-007) |
| R4 | PurgeAuditRules clobbers default Inherit=None ACEs | High | Use `RemoveAuditRuleSpecific` per managed ACE (not Purge) |
| R5 | SACL written to multiple DCs → conflict | Medium | Preferred DC binding (FR-009) |
| R6 | `SeSecurityPrivilege` absent → cryptic OS error | Medium | Explicit pre-check, stable error code (FR-008) |
| R7 | `optional/Enable-TierModelAuditing.ps1` not retired → confusion | Low | OI-001 flagged for Joel; doc update |
