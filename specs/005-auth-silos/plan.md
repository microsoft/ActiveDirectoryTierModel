# Implementation Plan: Authentication Policy Silos (`-IncludeAuthSilos`)

**Feature Branch**: `feature/auth-silos`
**Spec**: `specs/005-auth-silos/spec.md`
**Created**: 2026-08-24
**Status**: Draft (scoping) — Architecture and file list are planning-level only. Cmdlet contracts, configuration schema, and detailed implementation specifics are deferred to the design phase after the ops-guide walkthrough.

---

## Technical Context

- **Stack**: PowerShell 7.0+, Active Directory module (`ActiveDirectory` PSDrive), Pester
- **Module**: `modules/TierModel/` with public functions in `modules/TierModel/public/`
- **Deployment Script**: `Deploy-TierModel.ps1` — orchestrates Get-*/New-* cmdlet pattern
- **Config**: Segmented JSON under `config/` — new `config/tiermodel-authsilos.json` (exact shape deferred to design phase, OQ-007)
- **Existing Pattern**: `Get-TierModelX` (plan) → `New-TierModelX` (apply); `Get-TierModelXFd` for FullDeployment pre-compute; `Test-TierModelX` for audit
- **Switch Naming**: `-IncludeAuthSilos` — consistent with `-IncludeWinLaps`, `-IncludeGmsa`, `-IncludeDmsa` (additive optional-feature pattern)
- **Full Deployment Phase Order**: Standard phases 1–6 (OUs → Groups → Users → OU ACLs → GPOs → ADMX) + optional phases (MSA → gMSA → dMSA → WinLaps → AuditSacl → **AuthSilos new**)
- **Lab**: Hyper-V DC `TierLab-DC01` at `192.168.100.10`, domain `tierlab.internal`

### Research and Design References

| Document | Purpose |
|---|---|
| `.research/auth-silos/research/A1-mechanics-and-configuration.md` | Canonical glossary; capability and applicability matrix; object model mechanics |
| `.research/auth-silos/research/A8-security-and-failure-modes.md` | Security invariants; pre-enforcement gates G1–G12; failure-mode register; lockout and recovery |
| `.research/auth-silos/research/A3-limitations-and-complementary-controls.md` | Coverage gaps; what silos cannot do; complementary controls |
| `.research/auth-silos/research/A4-current-script-review.md` | Script defects (4 Critical, 19 Major); what to keep, what to fix, what to not replicate |
| `.research/auth-silos/research/B-options-synthesis.md` | Options synthesis; §5 consolidated security invariants; §6 validation backlog; §7 ADR plan |
| `.research/auth-silos/handoff/E1-deployment-code-constraints.md` | Build-time structural constraints: resolver/differ/writer separation, delta contract, thresholds, fail-safe |
| `.research/auth-silos/scoping.md` | Governing constraints AS-C-01 through AS-C-06; done bar |

---

## AD Object Model (Planning Level)

### Four Silo Objects (`msDS-AuthNPolicySilo`)

| Silo | Name (convention: OQ-007) | Member accounts | Member computers | `Enforce` |
|---|---|---|---|---|
| Tier 0 Admin | `TierModel-Tier0Admin-AuthSilo` *(illustrative)* | Tier 0 Accounts + Tier 0 Service Accounts | DCs, Tier 0 Servers, Tier 0 PAWs | `false` (audit) |
| Tier 1 Admin | `TierModel-Tier1Admin-AuthSilo` *(illustrative)* | Tier 1 Accounts + Tier 1 Service Accounts | Tier 1 Servers, Tier 1 PAWs | `false` (audit) |
| Tier 2 Admin | `TierModel-Tier2Admin-AuthSilo` *(illustrative)* | Tier 2 Accounts + Tier 2 Service Accounts | Tier 2 PAWs | `false` (audit) |
| Tier 2 EUD | `TierModel-Tier2EUD-AuthSilo` *(illustrative)* | Local Device Admins group | Tier 2 EUD devices | `false` (audit) |

### Authentication Policy Objects per Silo (`msDS-AuthNPolicies`)

Three policies per silo — one per account class. Exact TGT lifetime values and SDDL template are pending OQ-007/OQ-008. The `AllowedToAuthenticateFrom` OR logic applies to all silos.

| Policy class | Account class | Key settings |
|---|---|---|
| User policy | User accounts | TGT lifetime (config-driven), `AllowedToAuthenticateFrom` (approved device group SIDs, OR logic), `Enforce = false` |
| Computer policy | Computer accounts | `AllowedToAuthenticateTo` (who may obtain service tickets to this computer's SPN), `Enforce = false` |
| Service/MSA policy | sMSA / gMSA (scope: OQ-004) | TGT lifetime, `AllowedToAuthenticateFrom` (approved host SIDs, OR logic), `Enforce = false` |

### Structural Exemptions (must be enforced by code)

| Account | Exempt from | Exclusion method |
|---|---|---|
| `svc-pawdomainjoin` | Tier 0 Admin silo (and all silos) | SID-based skip; structural |
| `svc-t1srvdomainjoin` | Tier 1 Admin silo (and all silos) | SID-based skip; structural |
| `svc-t2euddomainjoin` | Tier 2 EUD silo (and all silos) | SID-based skip; structural |
| RID-500 (built-in Administrator) | All silos | SID suffix `-500$`; platform-exempt; structural |

### Account Assignment Sequence

For each in-scope account:
1. `Grant-ADAuthenticationPolicySiloAccess` — grants permission to join the silo (silo permitted-accounts list)
2. `Set-ADAccountAuthenticationPolicySilo` — assigns the account to the silo

Both steps are required. The delta must be computed for each step separately: grant-delta (who needs permission granted/revoked) and assignment-delta (who needs to be assigned/unassigned).

---

## Integration Shape

### `Deploy-TierModel.ps1` Parameter Wiring

```
-IncludeAuthSilos                                   # standalone: silo deployment plan only
-IncludeAuthSilos -ConfirmApply                     # standalone: apply
-FullDeployment -IncludeAuthSilos                   # full deploy: plan only
-FullDeployment -IncludeAuthSilos -ConfirmApply     # full deploy + auth silos
```

**Blocked combinations**: `-IncludeAuthSilos` + any `-*Only` parameter → parameter validation error (consistent with other optional features).

**Standalone flow**: validate prerequisites → `Get-TierModelAuthSilo` (plan) → display plan → if `-ConfirmApply`: confirmation → `New-TierModelAuthSilo` (apply).

**FullDeployment flow**: `Get-TierModelAuthSiloFd` added to pre-compute phase before summary display; `New-TierModelAuthSilo` runs after all standard and other optional phases; AuthSilos phase is skipped if any earlier standard phase has errors (consistent with optional phase gating).

### `Audit-TierModel.ps1` Parameter Wiring

```
-IncludeAuthSilos    # check silo state only when switch is passed
```

Calls `Test-TierModelAuthSilo`. Without the switch, silo state is not reported. Mirrors `-IncludeGmsa` gating pattern.

---

## Deployment Lifecycle

| Stage | Operator action | Code path | AD state after | Protection? |
|---|---|---|---|---|
| 1. Deploy (audit) | `-IncludeAuthSilos -ConfirmApply` | `Get-TierModelAuthSilo` → `New-TierModelAuthSilo` | Silo + policy objects exist; accounts assigned; `Enforce = false` | ❌ No |
| 2. Observe and validate | Normal operations; `Audit-TierModel.ps1 -IncludeAuthSilos` | `Test-TierModelAuthSilo` | No change | ❌ No |
| 3. Enforcement flip | Separate operator action (deferred: OQ-002/OQ-006) | Separate cmdlet (TBD) | `Enforce = true` on policies/silos | ✅ Yes |

The enforcement flip code path is a separate deliverable, not part of this spec's implementation scope.

---

## Constitution Check (Scoping Level)

| Principle | Assessment | Notes |
|-----------|-----------|-------|
| I. Code Quality | ✅ | New cmdlets follow existing module patterns; comment-based help required |
| II. Test-First with Pester | ✅ | Tests authored before production implementation (deferred to design phase) |
| III. Idempotent Deployments | ✅ | FR-007: no write when state matches desired; zero-write proof required |
| IV. Zero-Unintended-Impact | ✅ | All prereqs validated before any write; FAST GPOs validated not modified; RID-500 excluded |
| V. Drift Detection | ✅ | `Test-TierModelAuthSilo` + `Audit-TierModel.ps1 -IncludeAuthSilos` cover all drift conditions |
| VI. Structured Observability | ✅ | `Write-TierModelLog` with CorrelationId; delta counts (adds/removes/unchanged/errors) required |
| VII. Simplicity & Explicitness | ✅ | Audit mode labeled non-protective; enforcement is a separate, explicitly-invoked step |
| VIII. Modular Decomposition | ✅ | Get / Get-Fd / New / Test cmdlet pattern; silo object management isolated |
| IX. Dependency Governance | ✅ | `schemaVersion` in config JSON; SHA-256 provenance hash includes optional segment |

---

## New Files to Create (Planning Level)

> Cmdlet names are illustrative and may be revised in the design phase. Signatures, return types, and parameter shapes are deferred.

### Cmdlet Files

| File (illustrative) | Cmdlet | Responsibility |
|---|---|---|
| `modules/TierModel/public/Get-TierModelAuthSilo.ps1` | `Get-TierModelAuthSilo` | Standalone planner — prereq validation, FAST GPO check, four-silo plan generation |
| `modules/TierModel/public/Get-TierModelAuthSiloFd.ps1` | `Get-TierModelAuthSiloFd` | FullDeployment planner — lighter prereq check; plan pre-compute for FD summary |
| `modules/TierModel/public/New-TierModelAuthSilo.ps1` | `New-TierModelAuthSilo` | Executor — create silo objects, policies, grants, assignments; `SupportsShouldProcess`; delta-only; structural exemption enforcement |
| `modules/TierModel/public/Test-TierModelAuthSilo.ps1` | `Test-TierModelAuthSilo` | Audit checker — read-only; drift detection for silo/policy/assignment/device-group state across all four silos |

### Configuration File

| File | Purpose |
|---|---|
| `config/tiermodel-authsilos.json` | Silo configuration: four silo definitions, policy settings, device group names, exempt account SIDs, `schemaVersion` — exact shape pending OQ-007 |

### Test Files

| File | Scope |
|---|---|
| `tests/Unit.AuthSiloOperations.Tests.ps1` | Four-silo creation, idempotency, SDDL OR logic, delta-only assignment, structural exemptions (domain-join accounts + RID-500), prereq checks, error codes |
| `tests/Integration.AuthSiloDeployment.Tests.ps1` | Live-DC: create all four silos → verify state → idempotency → drift detection; negative scenarios (cross-tier deny); domain-join exempt account pass-through |

### Tier 2 EUD Config Additions (base Tier Model config, not auth-silos-only)

These items must be added to the base Tier Model configuration before the Tier 2 EUD silo can be deployed. They affect multiple existing config files:

| Item | Target config area | Notes |
|---|---|---|
| `svc-t2euddomainjoin` service account | `config/tiermodel-users.json` (or equivalent) | Disabled by default; mirrors `svc-pawdomainjoin` / `svc-t1srvdomainjoin` pattern |
| `Tier2EUDDomainJoin` security group | `config/tiermodel-groups.json` (or equivalent) | Single-member group; scopes delegation rights |
| `Tier 2 EUD Staging` OU | `config/tiermodel-ous.json` (or equivalent) | Staging OU for EUD computer objects before GPO assignment |
| Delegated create-computer rights on `Tier 2 EUD Staging` OU | `config/tiermodel-acls.json` (or equivalent) | `Tier2EUDDomainJoin` → create/delete computer; mirrors Tier 1 Server Staging ACL |
| Tier 2 EUD Account Restriction GPO | GPO config (or equivalent) | Kerberos armoring; deny interactive/RDP for `svc-t2euddomainjoin`; disabled-by-default |

---

## Existing Files to Modify

| File | Change | Authorization |
|---|---|---|
| `Deploy-TierModel.ps1` | Add `-IncludeAuthSilos` switch; blocked combos with `-*Only`; standalone and FullDeployment flows; confirmation UX | ✅ FR-001, FR-010, FR-011 |
| `Audit-TierModel.ps1` | Add `-IncludeAuthSilos` switch; wire to `Test-TierModelAuthSilo` conditional on switch | ✅ FR-002, FR-013 |
| `modules/TierModel/TierModel.psd1` | Add new cmdlets to `FunctionsToExport`; version bump (TBD — OQ-010) | ✅ Feature requirement |
| `modules/TierModel/public/Get-TierModelConfig.ps1` | Register `tiermodel-authsilos.json` as optional segment; expose `authSilos` property; include in SHA-256 hash | ✅ FR (config integration) |
| `modules/TierModel/public/Test-TierModelPrerequisites.ps1` | Add `-IncludeAuthSilos` switch; conditional checks: DFL, FAST GPO validation, AD module presence | ✅ FR-006 |
| `config/tiermodel.schema.json` | Add `authSilos` segment definition (additive; no existing properties modified) | ✅ FR (config integration) |

**No other existing cmdlet is modified.**

---

## Architecture Decisions Pending

The following decisions must be resolved in the design phase. Inputs from the ops-guide walkthrough (T001) are required before deciding.

| # | Decision title | Question | Options |
|---|---|---|---|
| D-001 | SDDL generation strategy | Runtime SID resolution vs. config-authored SDDL? | Runtime: more resilient to group rename; config: more auditable and reviewable |
| D-002 | Enforcement flip form | Separate script, separate cmdlet on Deploy-TierModel.ps1, or standalone tool? | Drives UX and code placement |
| D-003 | Service account (gMSA) in wave 1 | Are service/gMSA accounts siloed in the first wave? | Adds service-policy complexity; gMSA lab validation required |
| D-004 | Exemption model | AD attribute, config file with integrity check, or external register? | Drives exemption data structure |
| D-005 | Reconciliation automation boundary | Deploy-time only (alert on drift) vs. scheduled automation? Default is deploy-only unless JML rate demands automation. | Drives whether a writer/scheduler is needed |
| D-006 | Configuration schema shape | Per-tier JSON structure; naming conventions; placeholder patterns | Drives `tiermodel-authsilos.json` design |
| D-007 | Wave structure | Deployment + audit in the same wave vs. deployment first? | Drives version bump timing and task phasing |

---

## Pre-Enforcement Safety Design (Planning)

The enforcement flip operation (User Story 3, deferred) must satisfy the following structural requirements regardless of its final form:

- **Gate verification**: Device groups non-empty and replicated; replication health confirmed; recovery path tested (not documented — tested).
- **Explicit acknowledgement**: An operator acknowledgement parameter is required. Absence of `-WhatIf` is not sufficient.
- **Audit record**: Actor identity (SID), host, timestamp, and justification must be logged before any `Enforce` write.
- **Scope control**: Enforcement may be scoped per tier; all-tier enforcement must be a conscious decision.
- **Never automated**: No scheduled task, no automatic trigger. Enforcement flip is always a human decision with a human-readable audit trail.

---

## Risk Register

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | AND SDDL logic locks out intended admin devices at enforcement | **Critical** | CON-002: OR logic required; G1 pre-enforcement gate; SDDL must be tested positive/negative in lab (UAT-05/06/07) |
| R2 | Empty approved-device group → enforcement denies all siloed accounts | **Critical** | FR-006: non-empty check with halt; `AUTHSILO_DEVICE_GROUP_EMPTY` stable error code |
| R3 | Non-delta membership writes generate constant Tier 0 group-change alerts | High | FR-008: delta-only required; E1 §2 idempotency and convergence-proof contract |
| R4 | Enforcement triggered without passing pre-enforcement gates | High | CON-003/004: enforcement not in deployment flow; G1–G12 gate checklist required before flip |
| R5 | RID-500 or domain-join account included in silo membership | Medium | CON-005/010: structural SID-based exclusions; non-configurable; unit tests in T011 |
| R6 | FAST/DAC prerequisite unvalidated → device conditions silently fail at enforcement | Medium | FR-006: FAST GPO validation check; `AUTHSILO_FAST_PREREQ_MISSING` halt |
| R7 | Distributed maintenance automation recreates Tier 0 control-plane supply-chain threat | High | CON-006: single-writer required; no GPO-delivered scheduled task pattern |
| R8 | Audit parking — silo deployed in audit mode, never enforced | Medium | FR-012: audit-only labeling required; operational documentation time-box guidance |
| R9 | Replication inconsistency after object creation | Medium | Post-write verification must cover multiple DCs; no single-DC read-after-write assumption |
| R10 | Tier 2 EUD silo deployed without prerequisite config additions | Medium | Edge case documented; `AUTHSILO_T2EUD_PREREQ_MISSING` halt if `svc-t2euddomainjoin` / `Tier2EUDDomainJoin` / `Tier 2 EUD Staging` OU absent |
