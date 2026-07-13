# Implementation Plan: Windows LAPS Deployment (`-IncludeWinLaps`)

**Feature Branch**: `feature/windows-laps`  
**Spec**: `specs/003-win-laps/spec.md`  
**Created**: 2026-07-13  
**Status**: Draft

---

## Technical Context

- **Stack**: PowerShell 7.0+, Active Directory, Pester, Windows LAPS module
- **Module**: `modules/TierModel/` with public functions in `modules/TierModel/public/`
- **Deployment Script**: `Deploy-TierModel.ps1` — orchestrates Get-*/New-* cmdlet pattern
- **Config**: Segmented JSON under `config/` — new `config/tiermodel-winlaps.json`
- **GUID Mappings**: `config/tiermodel-guid-mappings.json` — not required for WinLaps (Microsoft cmdlets handle GUID internally)
- **Existing Pattern**: `Get-TierModelX` (plan) → `New-TierModelX` (apply) for deployment
- **Full Deployment Order**: OUs → Groups → Users → OU ACLs → GPOs → ADMX → MSA → gMSA → dMSA → **WinLaps (Phase 10)**
- **Lab**: Hyper-V DC `TierLab-DC01` at `192.168.100.10`, domain `tierlab.internal`, checkpoint `WinLapsSchema`

### Research References

- **DACL Design**: `.research/windowslaps/architecture/dacl-design.md`
- **Dependencies & Preflight**: `.research/windowslaps/research/dependencies-and-preflight.md`
- **Red-Team Findings**: `.research/windowslaps/research/red-team-findings.md`
- **ADR-0001**: `.research/windowslaps/decisions/0001-windows-laps-only.md`
- **Architecture Decision**: `.squad/decisions/inbox/cyclops-winlaps-architecture.md`

---

## Constitution Check

| Principle | Compliant | Notes |
|-----------|-----------|-------|
| I. Code Quality | ✅ | New cmdlets follow existing module patterns; comment-based help required |
| II. Test-First with Pester | ✅ | 19-test suite authored BEFORE implementation (see tasks.md Phase 1) |
| III. Idempotent Deployments | ✅ | Microsoft `Set-LapsAD*Permission` cmdlets are convergent; plan detects existing ACEs; second run = 0 changes |
| IV. Zero-Unintended-Impact | ✅ | Planning mode default; -ConfirmApply required; -WhatIf; fail-fast gating; DC exclusion |
| V. Drift Detection | ⚠️ Deferred | Audit cmdlet (`Test-TierModelWinLapsAcl`) deferred to future wave |
| VI. Structured Observability | ✅ | Write-TierModelLog with CorrelationId; passwords never logged |
| VII. Simplicity & Explicitness | ✅ | Switch parameters; no hidden behavior; DC exclusion visible in plan output |
| VIII. Modular Decomposition | ✅ | 3 cmdlets (Get-standalone, Get-Fd, New-apply); single-responsibility; < 300 lines each |
| IX. Dependency Governance | ✅ | Schema-versioned JSON config; SHA-256 hash logged; version bump on schema change |

**Constitution deviation**: Auditing is intentionally deferred to a future wave. This wave delivers deployment; together they constitute the complete feature.

---

## Prerequisites Architecture — All Green Before Any Change

### Gating Sequence (ordered, fail-fast)

```
GATE 1: Windows LAPS Schema Present (HARD STOP)
  ├─ Query msLAPS-* attributeSchema objects in schema NC
  ├─ Verify computer class mayContain linkage
  └─ FAIL → WINLAPS_SCHEMA_MISSING (non-prescriptive; reference MS docs only)

GATE 2: LAPS PowerShell Module Available
  ├─ Import-Module LAPS -ErrorAction Stop
  ├─ Verify ExportedCommands contains:
  │   Set-LapsADComputerSelfPermission
  │   Set-LapsADReadPasswordPermission
  │   Set-LapsADResetPasswordPermission
  └─ FAIL → WINLAPS_MODULE_MISSING

GATE 3: Domain Functional Level ≥ 2016 (encryption mandatory)
  ├─ Query DFL via Get-ADDomain on PreferredDc
  └─ FAIL → WINLAPS_DFL_INSUFFICIENT

GATE 4: Required OUs Present + DC Exclusion
  ├─ For each ouDn in winLapsDelegations config:
  │   Resolve DN, confirm exists via Get-ADOrganizationalUnit
  │   Query objects in OU for DC attributes (primaryGroupID=516, UAC 0x2000)
  │   IF isDomainControllerOu = true for this entry:
  │     DC objects ALLOWED (explicit opt-in — Domain Controllers OU is a known LAPS target)
  │   ELSE (default):
  │     DC objects → FAIL (hard-stop protection retained)
  ├─ FAIL on missing OU → WINLAPS_OU_MISSING (list all missing)
  └─ FAIL on DC objects (entries without isDomainControllerOu) → WINLAPS_DC_SCOPE_REJECTED

GATE 5: Required Groups Present
  ├─ For each readGroup + resetGroup in winLapsDelegations:
  │   Resolve via Get-ADGroup
  └─ FAIL → WINLAPS_GROUP_MISSING (list all missing)

ALL GATES PASS → Proceed
```

### Fail-Fast Contract

- Gates 1–3: sequential hard-stops (each aborts immediately).
- Gates 4–5: accumulate all errors, emit combined report.
- ANY gate failure = ZERO changes written (standalone or FullDeployment).
- FullDeployment: WinLaps gate failure blocks ENTIRE deploy (plan as a unit).

### Schema Hard-Stop Contract (OQ-WL-03 — Resolved)

- Tool NEVER mutates schema. No `Update-LapsADSchema`. No offer. No step-by-step.
- Emit stable error code `WINLAPS_SCHEMA_MISSING`.
- Check lives in `Test-TierModelPrerequisites.ps1`, conditional on `-IncludeWinLaps` (modeled on the existing KDS-root-key-missing check pattern using `$result.Errors.Add(...)` + `$result.Remediation.Add(...)`).
- Approved message wording (pending Joel final sign-off on exact text):

> "The Windows LAPS schema is not present in this directory. The -IncludeWinLaps parameter requires the Windows LAPS schema to be extended first. Extend the schema using your organization's controlled schema-change process before running with -IncludeWinLaps. Alternatively, deploy the Tier Model now without -IncludeWinLaps and add Windows LAPS later (post-deployment) once the schema is extended. The Tier Model will NEVER extend the schema automatically."

---

## Deployment Flow Design

### Standalone Mode (`-IncludeWinLaps` only, no `-FullDeployment`)

```
1. Load config via Get-TierModelConfig (tiermodel-winlaps.json registered as optional segment)
2. Run Gates 1–5 via Test-TierModelPrerequisites -IncludeWinLaps (schema, module, DFL, OUs, groups)
3. Get-TierModelWinLapsAcl → generate DACL plan (3 actions per delegation entry)
4. Display plan: summary counts, per-OU actions
5. If -ConfirmApply: New-TierModelWinLapsAcl → apply via Set-LapsAD*Permission cmdlets
6. Report results (Applied/Skipped/Errors/DurationMs/Converged)
```

### Full Deployment Mode (`-FullDeployment -IncludeWinLaps`)

```
1. Standard prerequisites (Test-TierModelPrerequisites -IncludeWinLaps — runs WinLaps gates conditionally)
2. Load config via Get-TierModelConfig (includes winLapsDelegations from optional segment)
3. Pre-compute: $winLapsFdPlan = Get-TierModelWinLapsAclFd (BEFORE summary display)
4. Phases 1–6 standard (OUs → Groups → Users → OU ACLs → GPOs → ADMX)
5. Display aggregate Deployment Plan summary (includes WinLaps action counts)
6. Phases 7–9 optional (MSA → gMSA → dMSA) if requested
7. Phase 10: WinLaps ACL Delegation (if -IncludeWinLaps)
   ├─ Planning: reuse pre-computed $winLapsFdPlan
   ├─ If -ConfirmApply: New-TierModelWinLapsAcl -Plan $winLapsFdPlan
   └─ $winLapsExecResult added to $allResults for consolidated totals
8. Report consolidated results
```

### Plan Output Contract

Matches existing structure:
- `Summary.TotalActions` — count of all DACL operations planned
- `Summary.CreateActions` — count of new ACEs to apply
- `Summary.ExistingCount` — count of ACEs already present (converged)
- `Summary.RiskAssessment` — Low/Medium/High counts
- `Actions` — array of action objects (`Action = 'CreateAcl'`, `Data = {...}`)
- `Errors` — array of pre-req/planning errors
- `Warnings` — array of warnings
- `Converged` — boolean (True when TotalActions = 0)

### Totals Integration

Each `winLapsDelegations` entry produces exactly 3 `CreateAcl` actions:
1. `Set-LapsADComputerSelfPermission` (Self-store)
2. `Set-LapsADReadPasswordPermission` (Read)
3. `Set-LapsADResetPasswordPermission` (Reset)

For N configured delegations: `TotalActions += 3N`, `CreateCount += 3N`.  
Verification: `$lapsActionCount > $baseActionCount` (delta = 3 × number of winLapsDelegations entries).

---

## New Files to Create

### Cmdlet Files

| File | Cmdlet | Responsibility |
|------|--------|----------------|
| `modules/TierModel/public/Get-TierModelWinLapsAcl.ps1` | `Get-TierModelWinLapsAcl` | Standalone planner — full pre-req validation, plan generation |
| `modules/TierModel/public/Get-TierModelWinLapsAclFd.ps1` | `Get-TierModelWinLapsAclFd` | FullDeployment planner — lighter validation (OUs/groups assumed from earlier phases) |
| `modules/TierModel/public/New-TierModelWinLapsAcl.ps1` | `New-TierModelWinLapsAcl` | Executor — invokes Microsoft `Set-LapsAD*Permission` cmdlets; supports -WhatIf |

### Configuration File

| File | Purpose |
|------|---------|
| `config/tiermodel-winlaps.json` | Windows LAPS DACL delegation definitions |

### Configuration Schema (Shape — values are [NEEDS INPUT: Joel])

```json
{
  "$schema": "./tiermodel-winlaps-schema.json",
  "schemaVersion": "1.0.0",
  "winLapsDelegations": [
    {
      "ouDn": "OU=Domain Controllers,{{DOMAIN_DN}}",
      "computerSelfPermission": true,
      "readGroup": "[NEEDS INPUT: Joel]",
      "resetGroup": "[NEEDS INPUT: Joel]",
      "isDomainControllerOu": true
    },
    {
      "ouDn": "[NEEDS INPUT: Joel — e.g. OU=Tier 0 Member Servers,OU=Tier 0,OU=Tier Model Administration,{{DOMAIN_DN}}]",
      "computerSelfPermission": true,
      "readGroup": "[NEEDS INPUT: Joel]",
      "resetGroup": "[NEEDS INPUT: Joel]"
    }
  ]
}
```

> **Design note (OQ-WL-02 resolved):** `readGroup` and `resetGroup` are separate fields by design — in Windows LAPS, reset/expire is a distinct right from read/decrypt. A remediation principal can force password rotation WITHOUT being able to read the current password. Operators MAY set both fields to the same group (Joel's confirmation environment will), but separation is enforced at the schema level so that least-privilege is always available without config-schema migration.

> **Design note (isDomainControllerOu):** Optional boolean, default `false`. Only the Domain Controllers OU entry sets it `true`. This refines locked decision OQ-RT-01: default DC-object hard-stop protection is retained for ALL entries; explicit per-entry opt-in is required to target an OU containing Domain Controllers. DC targeting is deliberate and visible in config.

> **Deployment note (7 OUs, 2 GPO templates):** Beast confirmed exactly 7 LAPS-linked computer OUs: Domain Controllers; Tier 0 Member Servers; Tier 1 Member Servers; Tier 0 PAW Devices; Tier 1 PAW Devices; Tier 2 PAW Devices; Tier 2 End-User Devices. Two GPO templates are used (DC template for DCs + PAWs; Common template for member servers + EUDs). Read/reset groups MAY differ across those groupings — Joel decides actual values.

### Test Files

| File | Tags | Count |
|------|------|-------|
| `tests/Unit.Prerequisites.Tests.ps1` | Unit, WinLaps (add Context) | 3 |
| `tests/Unit.WinLapsAclOperations.Tests.ps1` | Unit, WinLaps | 12+ |
| `tests/Integration.WinLapsDeployment.Tests.ps1` | Integration, WinLaps | 3 |

### Files to Modify (Existing)

| File | Change | Authorization |
|------|--------|---------------|
| `Deploy-TierModel.ps1` | Add `-IncludeWinLaps` switch parameter + Phase 10 orchestration wiring (standalone + FullDeployment modes) | ✅ Authorized by the feature request |
| `modules/TierModel/TierModel.psd1` | Add 4 new cmdlets to `FunctionsToExport`; bump version to 2.2.0 | ✅ Authorized by the feature request |
| `modules/TierModel/public/Get-TierModelConfig.ps1` | Register `tiermodel-winlaps.json` in `$optionalFiles` array (parallel to tiermodel-msa/gmsa/dmsa.json); expose merged `winLapsDelegations` property; include in composite SHA-256 provenance hash | ✅ **APPROVED** (OQ-WL-06) |
| `modules/TierModel/public/Test-TierModelPrerequisites.ps1` | Add `-IncludeWinLaps` switch with Gates 1–5 logic, conditional on `-IncludeWinLaps` — must NOT run and must NOT affect deployments that do not use `-IncludeWinLaps` (parallel to existing gMSA/dMSA conditional blocks) | ✅ **APPROVED** (OQ-WL-05) |

**No other existing module cmdlet is modified.**

---

## Parameter Validation Design

```powershell
# Valid combinations:
-FullDeployment -IncludeWinLaps              # Phase 10 in full sequence
-IncludeWinLaps                              # standalone WinLaps DACL deploy
-IncludeWinLaps -IncludeMsa -IncludeGmsa     # multiple standalone optional features
-FullDeployment -IncludeWinLaps -IncludeGmsa # full deploy + multiple optionals

# Invalid combinations:
-IncludeWinLaps -OuOnly                      # ERROR: cannot combine with *Only
-IncludeWinLaps -GroupOnly                   # ERROR
-IncludeWinLaps -OuAclsOnly                  # ERROR
```

---

## Windows-LAPS-Only Invariant (ADR-0001)

Enforcement at three layers:
1. **Schema detection**: Only query `msLAPS-*` attributes. Never query `ms-Mcs-AdmPwd*`.
2. **Cmdlet invocation**: Only `Set-LapsAD*Permission` from `LAPS` module. Never `AdmPwd.PS`.
3. **Config schema**: Only `winLaps*` / `msLAPS-*` keys. No `legacyLaps` / `admPwd` keys.

---

## Cmdlet Implementation Contracts

### Get-TierModelWinLapsAcl (Standalone)

```
Parameters: -Config, -DomainController, -IncludeDetails
Responsibilities:
  1. Receive config from caller (loaded via Get-TierModelConfig)
  2. Schema check (Gate 1 — HARD STOP) — defensive re-check in standalone mode
  3. Module check (Gate 2)
  4. DFL check (Gate 3)
  5. OU validation + DC exclusion (Gate 4)
  6. Group validation (Gate 5)
  7. For each delegation entry: compare live DACLs to required state
  8. Return plan object (Actions/Summary/Errors/Warnings/Converged)
```

### Get-TierModelWinLapsAclFd (FullDeployment)

```
Parameters: -Config, -DomainController, -IncludeDetails, -Silent
Responsibilities:
  1. Receive config from caller (loaded via Get-TierModelConfig)
  2. Lighter validation (OUs/groups assumed present from earlier phases)
  3. Schema + module + DFL checks still mandatory
  4. DC exclusion check still mandatory (defensive)
  5. Generate plan
  6. Return plan object matching Fd output structure
```

### New-TierModelWinLapsAcl (Executor)

```
Parameters: -Plan, -DomainController, -Config, -WhatIf
Responsibilities:
  1. If -WhatIf: return plan structure, zero writes
  2. For each action in Plan.Actions:
     - Invoke Set-LapsADComputerSelfPermission -Identity <OU> (if computerSelfPermission = true)
     - Invoke Set-LapsADReadPasswordPermission -Identity <OU> -AllowedPrincipals <readGroup>
     - Invoke Set-LapsADResetPasswordPermission -Identity <OU> -AllowedPrincipals <resetGroup>
  3. Log each operation via Write-TierModelLog
  4. Return result (Applied/Skipped/Errors/DurationMs/Converged)
```

---

## Integrated Design (Chosen Baseline — OQ-WL-05/06 Approved)

The Windows LAPS feature integrates with existing module infrastructure, consistent with MSA/gMSA/dMSA:

### Config Integration (Get-TierModelConfig.ps1)

- `tiermodel-winlaps.json` registered in `$optionalFiles` array (same pattern as `tiermodel-msa.json`, `tiermodel-gmsa.json`, `tiermodel-dmsa.json`)
- Exposes merged `winLapsDelegations` property on the config object
- Included in composite SHA-256 provenance hash (Constitution IX)
- When file is absent: property not set; `-IncludeWinLaps` will fail at prereq stage ("config not found")

### Prerequisite Integration (Test-TierModelPrerequisites.ps1)

- `-IncludeWinLaps` switch added (parallel to `-IncludeMsa`/`-IncludeGmsa`/`-IncludeDmsa`)
- **No-impact constraint**: WinLaps gates ONLY execute when `-IncludeWinLaps` is passed. A deployment without `-IncludeWinLaps` is byte-for-byte identical in behavior to pre-feature code.
- Gates 1–5 implemented inside the conditional block
- Results added to `EnvironmentSnapshot` under `winLapsPrereqs` key
- Schema-missing uses the KDS-key pattern: `$result.Errors.Add(...)` + `$result.Remediation.Add(...)`

### Cmdlet Config Loading

The three new cmdlets receive their config from the caller (passed via `-Config` parameter from Deploy-TierModel.ps1, which loads via Get-TierModelConfig). This keeps cmdlets testable (inject mock config) while using the unified loading mechanism in production.

### Why Integrated (not self-contained)

- **Consistency**: MSA/gMSA/dMSA all use this pattern — WinLaps diverging would create maintenance burden
- **Single prereq report**: Operators see ALL failures (schema + OUs + groups + gMSA + dMSA) in one report
- **SHA-256 provenance**: Config hash covers all segments; self-contained loading would bypass this
- **Reduced duplication**: No embedded config-loading code in each cmdlet

---

## Risk Register

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | Over-broad read delegation exposes passwords across OU subtrees | Critical | Per-Tier groups; narrowest OU scoping; `Find-LapsADExtendedRights` validation |
| R2 | DC/DSRM accidental scope creates Tier 0 credential-custody path | Critical | Hard-stop by default (`WINLAPS_DC_SCOPE_REJECTED`); DC targeting requires explicit per-entry `isDomainControllerOu: true` opt-in in config — deliberate and visible |
| R3 | Collapsed read+reset defeats separation of duties | High | `readGroup` and `resetGroup` kept as separate schema fields; equalizing is an explicit operator choice, not a default |
| R4 | Clear-text storage (DFL < 2016) exposes passwords | High | DFL 2016+ gate mandatory (Gate 3) |
| R5 | Partial schema extension passes naive check | High | Hardened check: mayContain on computer class, not just attribute names |
| R6 | Reset-group abuse forces rotation DoS | Medium | Separate principals; structured logging; alerting recommendation |
| R7 | Orphaned DACLs if OUs/groups later deleted | Medium | Audit wave drift detection (future) |
| R8 | Multiple LAPS module copies produce inconsistency | Low | `Import-Module LAPS` + validate loaded ExportedCommands |

---

## Idempotency Gap: ACE Fixture Requirement (H-1)

Microsoft does not publish the exact ACE/SDDL emitted by `Set-LapsAD*Permission` cmdlets. For v1, the implementation uses Microsoft cmdlets directly (convergent behavior). For future manual ACL comparison/removal/drift-detection, lab-captured before/after DACL fixtures are REQUIRED:

- Lab procedure: restore `WinLapsSchema` checkpoint → run `Set-LapsAD*Permission` per cmdlet → export before/after DACLs → record exact ACE entries.
- This is a lab-validation task (see tasks.md), not an implementation blocker for v1 deployment.

---

## Open Architecture Questions

| ID | Question | Status |
|---|---|---|
| AQ-1 | Does `New-TierModelWinLapsAcl` need additional idempotency wrapping beyond what `Set-LapsAD*Permission` provides natively? | Deferred to lab validation (T030) |
| AQ-2 | Does auditing (`Set-LapsADAuditing`) belong in `-IncludeWinLaps` or separate switch? | Deferred — scope decision for auditing wave |
| AQ-3 | Config: separate JSON file or integrated segment? | ✅ RESOLVED — integrated via Get-TierModelConfig (OQ-WL-06 approved) |
