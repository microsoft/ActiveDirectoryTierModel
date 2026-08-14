# Feature Specification: Domain-Root Audit SACL (`-EnableAuditing`)

**Feature Branch**: `feature/domain-auditing`
**Created**: 2026-08-14
**Status**: Draft
**Input**: Locked design from `.squad/decisions.md` and `.squad/decisions/inbox/coordinator-audit-union-ruling.md`. This spec documents a finalized design — no new design decisions are introduced here.

> **SACL vs DACL distinction**: This feature writes a **Security Audit Control List (SACL)** entry (an audit rule) on the domain root object. This is distinct from a DACL delegation and grants no access rights to any principal. "Delegation" language MUST NOT be used to describe this feature.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Apply Domain-Root Audit SACL (Priority: P1)
Administrator runs `Deploy-TierModel.ps1 -PreferredDc DC01 -EnableAuditing -ConfirmApply` to write a canonical `Everyone/Success/All` audit rule covering 9 rights on the domain root object, enabling Microsoft Sentinel Tier Model monitoring to receive the correct audit events.

**Clarifications Applied**:
- The audit rule is a SACL ACE, not a DACL ACE. It records security events; it grants zero access.
- The canonical rule targets the domain root DN (`DC=domain,DC=tld`), not any child OU.
- The advanced-audit policy GPO is a separate prerequisite — already deployed and linked by default in the Tier Model. This feature does NOT configure or check the GPO in code.
- `SeSecurityPrivilege` is required to read and write SACLs. Domain Admins hold this privilege in the deployment context.
- Both the SACL (set by this feature) AND the DC advanced-audit GPO (link enabled by default) must be present for Sentinel monitoring to function.

**Acceptance Scenarios**:
1. **Given** a deployed Tier Model and no existing managed audit ACE, **When** running `-EnableAuditing` without `-ConfirmApply`, **Then** a plan lists 1 `CreateAuditAce` action on the domain root; zero SACL writes occur.
2. **Given** the same invocation with `-ConfirmApply`, after the audit-specific confirmation prompt and deployment confirmation prompt are both answered Y, **Then** the canonical audit ACE is written. A second dry run reports 0 actions and `Converged = True`.
3. **Given** the canonical audit ACE is already present (all 9 rights, single ACE), **When** running `-EnableAuditing` in any mode, **Then** the plan reports 0 actions (`Converged = True`); no SACL write occurs.
4. **Given** a partial audit ACE exists (e.g., Everyone/Success/All/WriteProperty only), **When** running `-EnableAuditing -ConfirmApply`, **Then** the converge recipe removes the existing managed ACE(s) and writes a single canonical ACE that is the union of the existing rights and the 9 required rights.
5. **Given** a customer-added `Everyone/Failure/All/ReadProperty` ACE exists alongside managed ACEs, **When** running `-EnableAuditing -ConfirmApply`, **Then** the customer ACE is untouched (no-clobber); only managed ACEs are replaced.

---

### User Story 2 — Audit SACL as Part of Full Deployment (Priority: P1)
Administrator runs `Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -EnableAuditing -ConfirmApply` to deploy the full Tier Model and enable audit SACL configuration in a single operation.

**Acceptance Scenarios**:
1. **Given** full deployment prerequisites met and `-EnableAuditing` included, **When** running with `-ConfirmApply`, **Then** the deployment proceeds through all standard phases, plus an audit SACL phase; TotalActions includes 1 audit ACE action; the audit-specific Y gate and deployment Y gate are both presented before any writes.
2. **Given** all standard phases complete without error, **When** the audit SACL phase runs, **Then** the audit ACE is written and reported in consolidated totals.
3. **Given** `-EnableAuditing` is NOT passed with `-FullDeployment`, **When** deployed, **Then** no SACL is written and no audit phase appears in the plan.

---

### User Story 3 — Audit Script Checks Auditing (Priority: P2)
Security engineer runs `Audit-TierModel.ps1 -PreferredDc DC01 -EnableAuditing` to verify the domain-root audit SACL is correctly configured. Without `-EnableAuditing`, audit SACL state is not checked.

**Acceptance Scenarios**:
1. **Given** the audit SACL is correctly configured, **When** running `Audit-TierModel.ps1 -EnableAuditing`, **Then** the report shows the audit SACL as converged (no drift).
2. **Given** the audit SACL has drifted (e.g., a right was removed), **When** running `Audit-TierModel.ps1 -EnableAuditing`, **Then** the report flags the drift.
3. **Given** `Audit-TierModel.ps1` is run WITHOUT `-EnableAuditing`, **Then** audit SACL state is not checked and does not appear in the report.

---

### Edge Cases
- `SeSecurityPrivilege` not held by caller → hard stop with `AUDITACL_PRIVILEGE_MISSING`; zero writes.
- `-EnableAuditing` combined with any `-*Only` parameter → parameter validation error; blocked at parameter binding.
- Multiple managed ACEs exist (e.g., two default `Everyone/Success/All/WriteProperty` duplicates) → converge replaces all managed ACEs with one canonical union ACE (beneficial cleanup of pre-existing duplicate default ACEs).
- Customer has a `Everyone/Success/All` ACE with rights superset of our 9 → detected as already satisfying all required rights; no write (idempotent).
- Customer has a `Everyone/Failure/All` ACE → no-clobber; untouched (AuditFlags = Failure is outside managed scope).
- Customer has a `S-1-5-32-544/Success/All` ACE (different SID) → no-clobber; untouched.
- Customer has a `Everyone/Success/None` (Inherit=None) ACE → no-clobber; untouched (InheritanceType != All is outside managed scope).
- Customer has inherited ACEs (IsInherited=true) → no-clobber; untouched.
- SACL replication: written to one preferred DC; replicates to all DCs via normal AD replication. No multi-DC simultaneous write.
- `-EnableAuditing` without `-ConfirmApply` → plan-only (0 prompts, 0 writes).

---

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: System MUST support `-EnableAuditing` as a switch parameter on `Deploy-TierModel.ps1`.
- **FR-002**: System MUST support `-EnableAuditing` as a switch parameter on `Audit-TierModel.ps1`. When not passed, audit SACL state MUST NOT be checked or reported.
- **FR-003**: When `-EnableAuditing` is specified on deployment, the system MUST apply the canonical audit rule to the domain root object: `SID = S-1-1-0 (Everyone)`, `AuditFlags = Success`, `InheritanceType = All`, covering the following 9 rights: `CreateChild`, `DeleteChild`, `WriteProperty`, `Self`, `Delete`, `DeleteTree`, `WriteDacl`, `WriteOwner`, `ExtendedRight`.
- **FR-004**: System MUST implement UNION converge: the target rights applied = union of (existing managed-ACE rights) and (the canonical 9 rights). Customer-added rights within the managed-ACE scope are preserved. A managed ACE is defined as: `SID = S-1-1-0`, `AuditFlags = Success`, `InheritanceType = All`, `IsInherited = false`.
- **FR-005**: System MUST NOT modify any ACE outside the managed scope. The following are no-clobber:
  - ACEs with `AuditFlags = Failure`
  - ACEs with any SID other than `S-1-1-0 (Everyone)`
  - ACEs with `InheritanceType = None` (Inherit=None)
  - ACEs where `IsInherited = true`
- **FR-006**: System MUST be idempotent — when a single managed ACE already satisfies the union target (all required rights present, exactly 1 ACE in managed scope), no SACL write occurs; plan reports 0 actions and `Converged = True`.
- **FR-007**: System MUST use the converge recipe: (1) read SACL via `Get-Acl -Path "AD:<dn>" -Audit`; (2) enumerate managed ACEs via `foreach` over `GetAuditRules()` (NOT `@()` — see implementation note); (3) compute union target; (4) if already satisfied → no write; (5) else `RemoveAuditRuleSpecific` each managed ACE on the same `$acl` object, then `AddAuditRule` one canonical union ACE; (6) `Set-Acl -Path "AD:<dn>" -AclObject $acl`.
- **FR-008**: System MUST require `SeSecurityPrivilege`. If not held by the caller, the system MUST halt with error code `AUDITACL_PRIVILEGE_MISSING` and make zero changes.
- **FR-009**: System MUST bind SACL read and write to one preferred DC (via `-PreferredDc`). Multi-DC simultaneous SACL writes MUST NOT occur. SACL replication to other DCs occurs via standard AD replication.
- **FR-010**: System MUST NOT allow `-EnableAuditing` combined with any `-*Only` parameter (e.g., `-OuOnly`, `-GroupOnly`, `-UserOnly`, `-GposOnly`, `-OuAclsOnly`, `-AdmxOnly`). Valid combinations: standalone OR with `-FullDeployment`.
- **FR-011**: System MUST present a **two-prompt confirmation sequence** when `-EnableAuditing -ConfirmApply` is specified: (1) audit-specific warning + Y gate (BEFORE the deployment confirmation); (2) existing deployment confirmation Y gate. See Confirmation UX (Requirement 12) for the exact warning text and behavior matrix.
- **FR-012**: **Confirmation UX** — The audit-specific warning prompt MUST display the following EXACT text before the standard deployment confirmation prompt, only when (`-EnableAuditing` AND `-ConfirmApply`):

  ```
  ⚠️  AUDIT SACL WARNING ⚠️
  -EnableAuditing will write a SACL audit rule to the domain root object.
  This records security events (CreateChild, DeleteChild, WriteProperty, Self,
  Delete, DeleteTree, WriteDacl, WriteOwner, ExtendedRight) for Everyone on
  the domain root. This is required for Microsoft Sentinel Tier Model
  monitoring. It does NOT grant access — this is an audit rule, not a
  permission. Existing non-managed audit ACEs will not be modified.
  Continue with audit SACL configuration? [Y/N]:
  ```

  **Behavior matrix:**

  | Invocation | Prompts | Order |
  |---|---|---|
  | `-EnableAuditing -ConfirmApply` | **2** | Audit warning → Deploy confirm |
  | `-FullDeployment -EnableAuditing -ConfirmApply` | **2** | Audit warning → Deploy confirm |
  | `-FullDeployment -ConfirmApply` (no `-EnableAuditing`) | **1** | Deploy confirm only |
  | Any invocation without `-ConfirmApply` | **0** | Plan-only, no prompts |

- **FR-013**: System MUST support `-WhatIf` / planning mode (no `-ConfirmApply`) — zero SACL writes; plan shows what would be applied.
- **FR-014**: System MUST produce plan output with the following structure (matching existing cmdlet contracts):
  - `Summary.TotalActions` — total planned SACL operations (0 or 1)
  - `Summary.CreateAuditAceCount` — count of new ACEs to be written (0 or 1)
  - `Summary.ExistingCount` — count of ACEs already converged
  - `Summary.Status` — `ABSENT` / `PARTIAL` / `COMPLETE` / `MULTI-ACE`
  - `Summary.ExistingRights` — which of the 9 target rights are currently present (N/9)
  - `Summary.MissingRights` — which of the 9 target rights are absent (N/9)
  - `Actions` — array of action objects (`Action = 'CreateAuditAce'`, `Data = { ... }`)
  - `Errors` — array of pre-req/planning errors
  - `Converged` — boolean (`True` when `TotalActions = 0`)
- **FR-015**: System MUST produce apply result with the following structure:
  - `Applied` — count of SACL writes performed (0 or 1)
  - `Errors` — array of errors encountered
  - `DurationMs` — execution duration in milliseconds
  - `Converged` — boolean (True when no write was required or write succeeded)
- **FR-016**: System MUST log all operations with `Write-TierModelLog` including CorrelationId, Level, Message, and Data. No credential or sensitive data logged.
- **FR-017**: Config MUST be driven by `config/tiermodel-audit.json` loaded as an optional segment via `Get-TierModelConfig`. A new `auditSacl` segment MUST be added to the central `config/tiermodel.schema.json`. No per-feature schema file.
- **FR-018**: When `-EnableAuditing` is specified at deployment, the `auditSacl` config segment MUST be present. Missing config is a hard stop.
- **FR-019**: `Audit-TierModel.ps1` MUST accept `-EnableAuditing` and check audit SACL state ONLY when that switch is passed (mirrors `-IncludeGmsa` gating pattern). This is a future-phase implementation requirement; the interface is specified here.

### Key Entities
- **AuditRule (Canonical)**: `SID = S-1-1-0 (Everyone)`, `AuditFlags = Success`, `InheritanceType = All`, `Rights = CreateChild | DeleteChild | WriteProperty | Self | Delete | DeleteTree | WriteDacl | WriteOwner | ExtendedRight`.
- **ManagedAce**: An `Everyone/Success/All/non-inherited` ACE on the domain root — the only kind of ACE the converge recipe touches.
- **UnionTarget**: `managed-ACE rights ∪ canonical 9 rights` — what the converge recipe writes if a write is needed.
- **ConvergeStatus**: `ABSENT` (no managed ACEs), `PARTIAL` (managed ACEs exist but union target not satisfied), `COMPLETE` (single managed ACE satisfies union target), `MULTI-ACE` (multiple managed ACEs — converge needed regardless of total rights coverage).

---

## Cmdlet Contracts

### `Get-TierModelAuditRule` (Standalone planner)
**Purpose**: Reads the current domain-root SACL and produces a plan showing what converge would do. Used in standalone `-EnableAuditing` mode. Performs full pre-req validation.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Config` | PSCustomObject | Yes | Loaded config from `Get-TierModelConfig` |
| `-DomainController` | string | Yes | FQDN of preferred DC to bind to |
| `-IncludeDetails` | switch | No | Include per-right detail in plan output |

**Returns**: Plan object — `Summary`, `Actions`, `Errors`, `Converged` (see FR-014 for full shape).

---

### `New-TierModelAuditRule` (Executor)
**Purpose**: Applies the converge recipe — removes managed ACEs, writes canonical union ACE. Supports `-WhatIf`.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Plan` | PSCustomObject | Yes | Plan object from `Get-TierModelAuditRule` or `Get-TierModelAuditRuleFd` |
| `-DomainController` | string | Yes | FQDN of preferred DC |
| `-Config` | PSCustomObject | Yes | Loaded config |
| `-WhatIf` | switch | No | Simulate; zero SACL writes |

**Returns**: Result object — `Applied`, `Errors`, `DurationMs`, `Converged` (see FR-015).

---

### `Test-TierModelAuditRule` (Audit checker)
**Purpose**: Checks current SACL state against desired state for the audit script. Callable from `Audit-TierModel.ps1` when `-EnableAuditing` is passed.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Config` | PSCustomObject | Yes | Loaded config |
| `-DomainController` | string | Yes | FQDN of preferred DC |

**Returns**: Object with `Converged`, `Status`, `ExistingRights`, `MissingRights`, `Errors`.

---

### `Get-TierModelAuditRuleFd` (FullDeployment planner)
**Purpose**: Lighter-weight planner for use inside FullDeployment orchestration. OUs and standard prerequisites assumed present from earlier phases; privilege check still mandatory.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Config` | PSCustomObject | Yes | Loaded config |
| `-DomainController` | string | Yes | FQDN of preferred DC |
| `-Silent` | switch | No | Suppress informational output (for FD pre-compute) |

**Returns**: Plan object matching `Get-TierModelAuditRule` shape.

---

## Configuration & Schema

### `config/tiermodel-audit.json` (new file)

```json
{
  "schemaVersion": "1.0.0",
  "auditSacl": {
    "enabled": true,
    "targetSid": "S-1-1-0",
    "auditFlags": "Success",
    "inheritanceType": "All",
    "rights": [
      "CreateChild", "DeleteChild", "WriteProperty", "Self",
      "Delete", "DeleteTree", "WriteDacl", "WriteOwner", "ExtendedRight"
    ]
  }
}
```

### `config/tiermodel.schema.json` — new segment (additive)

A new `auditSacl` property block MUST be added to the central schema. No separate per-feature schema file. The segment validates `enabled` (boolean), `targetSid` (string), `auditFlags` (enum: `Success`/`Failure`/`All`), `inheritanceType` (string), and `rights` (array of strings).

---

## Deployment Integration

### Parameter Wiring (`Deploy-TierModel.ps1`)

- Add `-EnableAuditing` switch parameter.
- **Blocked combinations**: any `-*Only` flag combined with `-EnableAuditing` → parameter validation error.
- **Standalone mode**: load config → check privilege → `Get-TierModelAuditRule` → present plan → if `-ConfirmApply`: show audit warning prompt → if Y: `New-TierModelAuditRule`.
- **FullDeployment mode**: add audit SACL as a new phase; pre-compute via `Get-TierModelAuditRuleFd` before the summary display; phase order is not critical within optional phases; if standard phases had errors the audit phase is skipped.

### Full Deployment Phase Order

Standard phases (1–6: OUs → Groups → Users → OU ACLs → GPOs → ADMX) run first. Optional phases (MSA, gMSA, dMSA, WinLaps, **AuditSacl**) run after. The `-EnableAuditing` audit SACL phase has no ordering dependency on other optional phases.

### Confirmation UX Integration

The audit warning prompt (FR-012) fires **before** the standard deployment confirm Y gate, only when `-EnableAuditing -ConfirmApply` is both present. If the user answers N to the audit prompt, the entire deployment is aborted; no writes occur.

### Prerequisites

- `SeSecurityPrivilege` check added to `Test-TierModelPrerequisites.ps1`, conditional on `-EnableAuditing`.
- `Import-Module ActiveDirectory` must be verified present (required for `AD:` PSDrive).
- No Windows LAPS schema check, no DFL check required for this feature.

### Config Integration

- `tiermodel-audit.json` registered in `$optionalFiles` in `Get-TierModelConfig.ps1` (same pattern as msa/gmsa/dmsa/winlaps). `auditSacl` property exposed on the unified config object.
- When absent and `-EnableAuditing` is not passed: no effect.
- When absent and `-EnableAuditing` IS passed: hard stop ("audit config not found").

---

## Idempotency, UNION Converge, and No-Clobber Acceptance Criteria

These criteria are the basis for Wolverine's Pester test cases.

### Idempotency
- **AC-IDEM-01**: Given canonical ACE already present (1 managed ACE, all 9 rights), `Get-TierModelAuditRule` returns `Converged = True`, `TotalActions = 0`.
- **AC-IDEM-02**: Given canonical ACE already present, `New-TierModelAuditRule` returns `Applied = 0`, `Converged = True`, and performs zero SACL writes.

### UNION Converge
- **AC-UNION-01**: Given one managed ACE with rights = {WriteProperty} (subset of 9), converge writes one ACE with rights = {WriteProperty ∪ canonical 9} (union).
- **AC-UNION-02**: Given one managed ACE with rights = {WriteProperty, ReadProperty} where ReadProperty is not in the canonical 9, converge writes one ACE with rights = {WriteProperty ∪ ReadProperty ∪ canonical 9} (customer-added right preserved).
- **AC-UNION-03**: Given two managed ACEs (multi-ACE), converge replaces both with one canonical union ACE; `Applied = 1`.
- **AC-UNION-04**: Given no managed ACEs (ABSENT), converge writes one ACE with exactly the canonical 9 rights.

### No-Clobber
- **AC-NOCLOBBER-01**: `Everyone/Failure/All` ACE present alongside managed ACEs → survives converge untouched.
- **AC-NOCLOBBER-02**: `S-1-5-32-544/Success/All` (Administrators SID) ACE present → survives converge untouched.
- **AC-NOCLOBBER-03**: `Everyone/Success/None` (Inherit=None) ACE present → survives converge untouched (default domain SACL entry; not managed).
- **AC-NOCLOBBER-04**: Inherited ACE (`IsInherited = true`) present → survives converge untouched.

### Plan Status Mapping
- **AC-STATUS-01**: Zero managed ACEs → `Status = ABSENT`, `ExistingRights = 0/9`.
- **AC-STATUS-02**: One managed ACE, some rights present, not all 9 → `Status = PARTIAL`.
- **AC-STATUS-03**: One managed ACE, all 9 rights present → `Status = COMPLETE`, `Converged = True`.
- **AC-STATUS-04**: Multiple managed ACEs → `Status = MULTI-ACE`, regardless of total rights coverage.

### `GetAuditRules()` Enumeration
- **AC-ENUM-01**: Managed ACE enumeration uses `foreach ($r in $acl.GetAuditRules(...))` — NOT `@($acl.GetAuditRules(...))`. The latter wraps the collection in a 1-element array, not a per-rule array.

---

## Out of Scope

The following are explicitly excluded from this feature:

| Item | Reason |
|---|---|
| Rollback / disable cmdlet (`Remove-TierModelAuditRule`) | Environment-specific; operators own rollback. Covered by confirmation Y gate and plan display of rights added. |
| Advanced-audit-policy / GPO code check | GPO already deployed and linked by default. This is a documentation requirement only — no in-code detection. |
| Windows Event Log or SIEM configuration | Out of product scope. |
| Multi-forest or cross-domain audit scope | Single domain root only. |
| Per-OU SACL entries | Domain root only per locked design. |
| Failure-flag audit rules | Success-only per locked design. |
| Legacy `optional/Enable-TierModelAuditing.ps1` | Superseded by `-EnableAuditing`. See Open Items. |

---

## Open Items

| ID | Item | Owner |
|---|---|---|
| OI-001 | **`optional/Enable-TierModelAuditing.ps1` fate**: this script is superseded by `-EnableAuditing`. Retire (delete) or leave as reference archive? | Joel (@VAsHachiRoku) |
| OI-002 | **Exact config values** for `tiermodel-audit.json` (domain DN placeholder convention confirmed as `{{DOMAIN_DN}}`; confirm if any other placeholders needed) | Joel |

---

## Docs to Update

The following documentation files require updates. **Storm authors these; Cyclops flags them here.**

| File | Required Change |
|---|---|
| `docs/sentinel-monitoring.md` | (1) Remove the manual `optional/Enable-TierModelAuditing.ps1` "future release" content. (2) State that `-EnableAuditing` is **required** for Sentinel monitoring. (3) State that **both** the audit SACL (via `-EnableAuditing`) AND the DC advanced-audit GPO (configured + link enabled — link is on by default) are required for monitoring to function. (4) Note SACL replication delay (AD replication; not instant on all DCs after write). |
| `README.md` | Add `-EnableAuditing` to parameter summary and feature list; update version reference to 1.3.0. |
| `CHANGELOG.md` | Add 1.3.0 entry for `-EnableAuditing` feature. |
| `docs/faq.md` | Add Q&A entries for: "Do I need to run `-EnableAuditing`?", "What does `-EnableAuditing` write?", "Why two confirmation prompts?", "Does `-EnableAuditing` affect access rights?" |

---

## Version

| Item | Change |
|---|---|
| Module manifest (`TierModel.psd1`) | `1.2.3` → `1.3.0` (additive minor — new switch, new cmdlets, new config segment) |

---

## Assumptions

- Deployment context runs as Domain Admin, which holds `SeSecurityPrivilege`.
- The domain root DN is resolved at runtime from `Get-ADDomain` against the preferred DC.
- The advanced-audit GPO is already deployed and linked. This feature does not check GPO state in code.
- `Import-Module ActiveDirectory` (for `AD:` PSDrive) is available on the management host.
- Lab is single-DC; multi-DC binding is addressed by preferred-DC constraint and SACL replication documentation.
- The two default `Everyone/Success/All/WriteProperty` duplicate ACEs on a clean domain root will be absorbed into the canonical ACE (WriteProperty is within the 9). This is a net improvement (removes duplicate default ACEs); it is not a destructive operation.

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Caller misidentifies SACL write as permission grant | High | Explicit `⚠️ AUDIT SACL WARNING` prompt; spec forbids "delegation" language throughout |
| `GetAuditRules()` wrapped in `@()` → silent wrong behavior | High | AC-ENUM-01 Pester test; explicit code guidance in FR-007 |
| SACL write on wrong DC → replication race | Medium | Bind read+write to one preferred DC (FR-009) |
| Customer ACE accidentally clobbered | Medium | No-clobber scope defined in FR-005; AC-NOCLOBBER-01 through -04 tests |
| `SeSecurityPrivilege` absent → cryptic error | Medium | Explicit privilege check and `AUDITACL_PRIVILEGE_MISSING` error code (FR-008) |
| `optional/Enable-TierModelAuditing.ps1` left active and conflicts | Low | OI-001 flagged for Joel; doc update removes reference |

---

## Dependencies

- Spec 001 (Tier Model AD Deployment & Audit Module) — base infrastructure required.
- `Import-Module ActiveDirectory` on the management host.
- DC advanced-audit GPO deployed and linked (pre-existing; not a code dependency).
- `SeSecurityPrivilege` available to the deployment account.

---

## Test Strategy (Supplemental)

- Pester suite covers: idempotency (AC-IDEM-01/02), UNION converge scenarios (AC-UNION-01 through -04), no-clobber scenarios (AC-NOCLOBBER-01 through -04), plan status mapping (AC-STATUS-01 through -04), enumeration correctness (AC-ENUM-01), parameter guard (`-EnableAuditing` + `-*Only` = error), confirmation prompt matrix, privilege missing → error.
- Offline (ByBytes) tests use SACL fixture objects — no live AD required for unit tests.
- Live-AD integration tests: restore domain checkpoint → apply → verify SACL → re-apply → verify idempotency.
- `Audit-TierModel.ps1 -EnableAuditing` drift test: remove ACE, run audit, assert drift detected.
