# Tasks: Windows LAPS Deployment (`-IncludeWinLaps`)

**Feature Branch**: `feature/windows-laps`  
**Spec**: `specs/003-win-laps/spec.md`  
**Plan**: `specs/003-win-laps/plan.md`  
**Generated**: 2026-07-13

---

## ⚠️ Testing Scope Constraints (Joel's Direction — 2026-07-13)

**Squad WILL test:**
- `-IncludeWinLaps` fails when OUs and Groups are NOT present
- `-IncludeWinLaps` CANNOT combine with `-OuOnly` or any `*-Only` parameters
- `-IncludeWinLaps` runs together with `-FullDeployment` without issues
- All four `-Include*` parameters (`-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`, `-IncludeWinLaps`) run together with `-FullDeployment` without issues
- Track deployment/audit counts to verify they increase with WinLaps additions
- Windows-LAPS-only invariant: no `ms-Mcs-AdmPwd*` or `AdmPwd.PS` references anywhere
- Idempotency: second run produces 0 changes, `Converged = True`
- `-WhatIf` / planning mode produces zero AD writes

**Squad will NOT test (Joel tests manually):**
- Pre-requisite failures (schema not present, LAPS module missing, DFL < 2016)
- Actual Set-LapsAD*Permission calls against live AD DACLs
- DC/DSRM scope rejection scenarios (DC objects in target OUs)

**Workflow:**
1. Deploy tier model first → capture counts → roll back checkpoint
2. Make code changes
3. Test new code against the constraints above
4. **STOP before Phase 10 (Pester tests)** — wait for Joel's manual testing to complete

**Rules:**
- Do NOT modify other cmdlets beyond what is required (see authorized modifications in Phase 2 and Phase 8)
- If any issue arises → STOP and ask Joel. Do NOT brute force or work around limitations.
- Update this file (tasks.md) as each task is completed

---

## Phase 1: Setup & Configuration

> Foundation configuration file and JSON schema that all subsequent tasks depend on.

- [x] T001 [P] Create `config/tiermodel-winlaps.json` with `schemaVersion: "1.0.0"` and a `winLapsDelegations` array. Each entry has fields: `ouDn` (OU distinguished name using `{{DOMAIN_DN}}` placeholder), `computerSelfPermission` (boolean — enables computer SELF-store), `readGroup` (principal allowed to read/retrieve the LAPS password), `resetGroup` (principal allowed to force reset/expire), and optional `isDomainControllerOu` (boolean, default `false` — when `true`, the DC-object hard-stop is bypassed for that entry, enabling explicit opt-in for the Domain Controllers OU). `readGroup` and `resetGroup` are separate fields by design (reset/expire is a distinct right from read/decrypt); operators MAY set them to the same value. Beast confirmed 7 LAPS-linked computer OUs: Domain Controllers; Tier 0/1 Member Servers; Tier 0/1/2 PAW Devices; Tier 2 End-User Devices. Only the Domain Controllers entry sets `isDomainControllerOu: true`. Values marked `[NEEDS INPUT: Joel]` — Joel is sourcing the OU list now.
  - ✅ Completed 2026-07-14: 7 delegation entries with Joel-approved values, all groups verified against config.
  - **Files**: `config/tiermodel-winlaps.json`
  - **Satisfies**: FR-013, Constitution IX

- [x] T002 ~~[P] Create `config/tiermodel-winlaps-schema.json`~~ — DROPPED per Joel 2026-07-14 — no per-feature schema files; central tiermodel.schema.json is the single schema, aligned in this change.
  - **Files**: ~~`config/tiermodel-winlaps-schema.json`~~ (deleted)
  - **Satisfies**: Constitution IX

---

## Phase 2: Existing Cmdlet Changes — Shared Config & Prerequisites

> Modify shared config and prerequisite helpers before introducing new WinLaps deployment cmdlets. **These are existing file modifications — review separately.**

- [x] T003 Update `modules/TierModel/public/Get-TierModelConfig.ps1` — load `tiermodel-winlaps.json` as an optional config segment (add to `$optionalFiles` array, same pattern as `tiermodel-msa.json`, `tiermodel-gmsa.json`, `tiermodel-dmsa.json`). Merge `winLapsDelegations` into the unified config object only when the file is present. Preserve current behavior when absent. Include optional segment content in the composite SHA-256 provenance hash only when loaded. Ensure downstream cmdlets receive the merged config object from `Get-TierModelConfig` rather than reading raw JSON directly.
  - ✅ Completed 2026-07-14: Added to $optionalFiles and merged as config.winLapsDelegations.
  - **Files**: `modules/TierModel/public/Get-TierModelConfig.ps1`
  - **Satisfies**: FR-014, Constitution IX
  - **Authorization**: ✅ APPROVED (OQ-WL-06)

- [x] T004 Update `modules/TierModel/public/Test-TierModelPrerequisites.ps1` — add `-IncludeWinLaps` switch parameter. When `-IncludeWinLaps` is specified, run the following gates (ALL must pass; fail-fast on Gate 1–3, accumulate on Gates 4–5):
  - ✅ Completed 2026-07-14: All 5 gates implemented with correct error codes and remediation messages.
  - **Gate 1 (HARD STOP)**: Windows LAPS schema present — query `msLAPS-*` attributeSchema objects in schema NC, verify computer class `mayContain` linkage. FAIL → emit stable error code `WINLAPS_SCHEMA_MISSING` using the KDS-key pattern (`$result.Errors.Add(...)` + `$result.Remediation.Add(...)`). Approved message: *"The Windows LAPS schema is not present in this directory. The -IncludeWinLaps parameter requires the Windows LAPS schema to be extended first. Extend the schema using your organization's controlled schema-change process before running with -IncludeWinLaps. Alternatively, deploy the Tier Model now without -IncludeWinLaps and add Windows LAPS later (post-deployment) once the schema is extended. The Tier Model will NEVER extend the schema automatically."*
  - **Gate 2**: LAPS PowerShell module available — `Import-Module LAPS -ErrorAction Stop`, verify `ExportedCommands` contains `Set-LapsADComputerSelfPermission`, `Set-LapsADReadPasswordPermission`, `Set-LapsADResetPasswordPermission`. FAIL → `WINLAPS_MODULE_MISSING`.
  - **Gate 3**: Domain Functional Level ≥ 2016 (encryption mandatory). FAIL → `WINLAPS_DFL_INSUFFICIENT`.
  - **Gate 4**: Target OUs exist + DC exclusion — for each `ouDn` in config, resolve via `Get-ADOrganizationalUnit`, query for DC objects (primaryGroupID=516 or UAC SERVER_TRUST_ACCOUNT). If entry has `isDomainControllerOu: true`, DC objects are ALLOWED for that entry (explicit opt-in). Otherwise, DC objects → FAIL → `WINLAPS_OU_MISSING` or `WINLAPS_DC_SCOPE_REJECTED`.
  - **Gate 5**: Required groups exist — for each `readGroup` + `resetGroup`, resolve via `Get-ADGroup`. FAIL → `WINLAPS_GROUP_MISSING`.
  - Add results to `EnvironmentSnapshot` under `winLapsPrereqs` key. **No-impact constraint**: checks must NOT run and must NOT affect output when `-IncludeWinLaps` is not passed (parallel to existing `-IncludeGmsa`/`-IncludeDmsa` conditional blocks).
  - **Files**: `modules/TierModel/public/Test-TierModelPrerequisites.ps1`
  - **Satisfies**: FR-003, FR-004, SC-004
  - **Authorization**: ✅ APPROVED (OQ-WL-05)

---

## Phase 3: WinLaps Standalone Deployment [US1] [US2]

> New cmdlets for Windows LAPS DACL delegation — standalone mode.

- [x] T005 [P] [US1] Create `modules/TierModel/public/Get-TierModelWinLapsAcl.ps1` — plan Windows LAPS DACL delegations for standalone deployment using the merged config object from `Get-TierModelConfig`. Accept `-Config` parameter (loaded by caller). Resolve `{{DOMAIN_DN}}` placeholders via `Resolve-TierModelPlaceholder`. Validate target OUs exist in live AD (fail-fast if missing with "Run -FullDeployment first or -OuOnly"), validate read/reset groups exist (fail-fast if missing). Perform defensive re-checks of Gates 1–3 (schema, module, DFL). For Gate 4 DC exclusion: honor `isDomainControllerOu` flag — if `true`, DC objects allowed for that entry; otherwise hard-stop (`WINLAPS_DC_SCOPE_REJECTED`). For each `winLapsDelegations` entry: determine required DACL state from `ouDn`, `computerSelfPermission`, `readGroup`, `resetGroup`; compare live state to required; produce 3 `CreateAcl` actions per entry (Self + Read + Reset) when not already present. Return plan object with `Actions`, `Summary` (`TotalActions`, `CreateActions`, `ExistingCount`, `RiskAssessment`), `Warnings`, `Errors`, and `Converged` matching `Get-TierModelOuAcl` output structure. Parameters: `-Config`, `-DomainController`, `-IncludeDetails`. Use `Write-TierModelLog` for structured logging with CorrelationId. Invoke ONLY `ms-LAPS-*` / `LAPS` module references (ADR-0001).
  - ✅ Completed 2026-07-14: 3 actions per delegation, Find-LapsADExtendedRights detection, idempotent, NeedsLabValidation.
  - **Files**: `modules/TierModel/public/Get-TierModelWinLapsAcl.ps1`
  - **Satisfies**: FR-002, FR-003, FR-004, FR-007, FR-008, FR-009, FR-010, SC-004

- [x] T006 [P] [US1] Create `modules/TierModel/public/New-TierModelWinLapsAcl.ps1` — apply Windows LAPS DACL delegations from plan. Accept plan object from `Get-TierModelWinLapsAcl` or `Get-TierModelWinLapsAclFd`. Support `-WhatIf` (zero writes when set). When applying, for each action in `Plan.Actions`:
  - ✅ Completed 2026-07-14: Calls Set-LapsAD*Permission cmdlets, SupportsShouldProcess, structured logging.
  - Invoke `Set-LapsADComputerSelfPermission -Identity <OU>` (if `computerSelfPermission = true`)
  - Invoke `Set-LapsADReadPasswordPermission -Identity <OU> -AllowedPrincipals <readGroup>`
  - Invoke `Set-LapsADResetPasswordPermission -Identity <OU> -AllowedPrincipals <resetGroup>`
  - Log each operation via `Write-TierModelLog` with CorrelationId. NEVER log passwords.
  - Return result object with `Applied`, `Skipped`, `Errors`, `DurationMs`, `Converged` matching `New-TierModelOuAcl` output structure.
  - **Files**: `modules/TierModel/public/New-TierModelWinLapsAcl.ps1`
  - **Satisfies**: FR-002, FR-005, FR-006, FR-009

---

## Phase 4: WinLaps Deployment Verification [US1]

> Verification cmdlet to confirm DACL delegations were applied correctly. Mirrors the Test-TierModel*Acl pattern from MSA/gMSA/dMSA.

- [x] T007 [US1] Create `modules/TierModel/public/Test-TierModelWinLapsAcl.ps1` — verify Windows LAPS DACL delegations are applied correctly using the merged config object from `Get-TierModelConfig`. For each `winLapsDelegations` entry: verify Self-permission, Read-permission, and Reset-permission DACLs exist on the target OU with correct principals. Report findings as `Compliant`, `MissingAcl`, and `UnexpectedAcl`. Return result object compatible with audit reporting structure and follow `Test-TierModelOuAcl.ps1` pattern. Support `-Silent`/`-SuppressSummary` for consolidated reporting. Use `Write-TierModelLog` for structured logging.
  - ✅ Completed 2026-07-14: Find-LapsADExtendedRights-based audit, Compliant/MissingAcl findings, Silent support.
  - **Files**: `modules/TierModel/public/Test-TierModelWinLapsAcl.ps1`
  - **Satisfies**: FR-005, SC-001

---

## Phase 5: Module Manifest Update

> Update module manifest to export standalone public functions. **This is an existing file modification — review separately.**

- [x] T008 Update `modules/TierModel/TierModel.psd1` — add `Get-TierModelWinLapsAcl`, `New-TierModelWinLapsAcl`, `Test-TierModelWinLapsAcl` to `FunctionsToExport`. (FD variant will be added in Phase 8 when created.) Increment module version to 2.2.0.
  - ✅ Completed 2026-07-14: Version bumped to 2.2.0, all standalone exports added.
  - **Files**: `modules/TierModel/TierModel.psd1`
  - **Satisfies**: FR-002, Constitution VIII

---

## Phase 6: Existing Script Changes — Deploy Standalone Mode [US1] [US2]

> Update Deploy-TierModel.ps1 for standalone `-IncludeWinLaps` deployment. **This is an existing file modification — review separately.**

- [x] T009 [US1] [US2] Update `Deploy-TierModel.ps1` — add `-IncludeWinLaps` switch parameter to the param block. Update parameter validation: `-IncludeWinLaps` can be used standalone (without any scope parameter) or combined with `-FullDeployment` only — never with `-OuOnly`, `-GroupOnly`, `-UserOnly`, `-GposOnly`, `-OuAclsOnly`, or `-AdmxOnly`. When `-IncludeWinLaps` is used standalone: call `Get-TierModelConfig` so cmdlets receive the merged config object, pass `-IncludeWinLaps` to `Test-TierModelPrerequisites` for fail-fast validation, call `Get-TierModelWinLapsAcl` for planning and `New-TierModelWinLapsAcl` for apply when `-ConfirmApply`. Report deployment counts accurately — track so totals verifiably INCREASE when `-IncludeWinLaps` is added (3 × number of configured delegations). Support planning mode (no `-ConfirmApply`) and execution mode.
  - ✅ Completed 2026-07-14: Standalone -IncludeWinLaps wired with prereqs, planning, and apply paths.
  - **Files**: `Deploy-TierModel.ps1`
  - **Satisfies**: FR-011, FR-012, SC-002, SC-003

---

## Phase 7: WinLaps Full Deployment Integration [US1] [US3]

> Create FD variant for full deployment integration.

- [x] T010 [P] [US1] [US3] Create `modules/TierModel/public/Get-TierModelWinLapsAclFd.ps1` — plan Windows LAPS DACL delegations for full deployment mode using the merged config object from `Get-TierModelConfig`. Same logic as `Get-TierModelWinLapsAcl.ps1` but with lighter validation: assume OUs and groups will exist from earlier deployment phases, validate against configured state during planning, validate against live AD during apply. Schema + module + DFL + DC-exclusion checks still mandatory (defensive). Follow the same action model (3 actions per delegation entry). Use `-Silent` for consolidated reporting. Return plan object matching `Get-TierModelOuAclFd.ps1` output structure.
  - ✅ Completed 2026-07-14: Lighter OU/group validation, DC-exclusion still enforced, Silent support.
  - **Files**: `modules/TierModel/public/Get-TierModelWinLapsAclFd.ps1`
  - **Satisfies**: FR-012, FR-008

---

## Phase 8: Existing File Changes — FD Exports & Deploy Full Deployment Mode [US1] [US3]

> Update module exports and Deploy-TierModel.ps1 for FullDeployment + `-IncludeWinLaps` integration. **These are existing file modifications — review separately.**

- [x] T011 [US1] Update `modules/TierModel/TierModel.psd1` — add `Get-TierModelWinLapsAclFd` to `FunctionsToExport`
  - ✅ Completed 2026-07-14: FD variant exported.
  - **Files**: `modules/TierModel/TierModel.psd1`
  - **Satisfies**: FR-012

- [x] T012 [US1] [US3] Update `Deploy-TierModel.ps1` — add Phase 10 (Windows LAPS ACL Delegations) to the FullDeployment flow. This executes AFTER Phase 9 (dMSA) and is gated by `$standardDeployHadErrors`. Pre-compute `$winLapsFdPlan = Get-TierModelWinLapsAclFd` BEFORE the aggregate summary display (same pattern as MSA/gMSA/dMSA). Include WinLaps action counts in `Add-IncludeAclPhaseToDeploymentPlan` call (`PhaseNumber=10`, `PhaseName='Windows LAPS ACL Delegations'`). Execute via `New-TierModelWinLapsAcl -Plan $winLapsFdPlan` when `-ConfirmApply`. Add `$winLapsExecResult` to `$allResults` for consolidated totals. Order: MSA → gMSA → dMSA → WinLaps. Can run after any/all of msa/gmsa/dmsa without conflict.
  - ✅ Completed 2026-07-14: Phase 10 precompute, execute, and consolidated results all wired.
  - **Files**: `Deploy-TierModel.ps1`
  - **Satisfies**: FR-012, SC-002, SC-007

---

## 🛑 STOP — MANUAL TEST GATE (Joel)

**Windows LAPS deployment is complete and independently testable in the lab.**

Verification procedure:
1. Restore `WinLapsSchema` checkpoint on VM `TierLab-DC01`
2. Run `Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -ConfirmApply` (baseline — no WinLaps) → record `Applied: N`
3. Restore `WinLapsSchema` checkpoint again
4. Run `Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -IncludeWinLaps -ConfirmApply` → record `Applied: M`
5. Verify `M > N` (delta = 3 × number of configured delegations)
6. Rerun WITHOUT restoring → verify `Applied: 0`, `Converged: True` (idempotency)
7. Run standalone `-IncludeWinLaps` on fresh restore → verify same behavior
8. Run `Test-TierModelWinLapsAcl` → verify `Compliant` for all delegations

**Do NOT proceed past this line until Joel confirms manual testing passed.**

---

## Phase 9: WinLaps Audit Integration

> Integrate Test-TierModelWinLapsAcl into the Audit orchestration script.

- [ ] T013 Update `Audit-TierModel.ps1` — add `-IncludeWinLaps` switch parameter to the param block. Update parameter validation to match `Deploy-TierModel.ps1` rules (standalone or with `-FullDeployment` only). Load merged optional config via `Get-TierModelConfig`, pass `-IncludeWinLaps` to `Test-TierModelPrerequisites`, and when `-IncludeWinLaps` is active call `Test-TierModelWinLapsAcl` for drift detection. Include WinLaps drift results in consolidated audit report. When running `-FullDeployment` with `-IncludeWinLaps`, audit WinLaps after standard audit scope. Only audit what was requested.
  - **Files**: `Audit-TierModel.ps1`
  - **Satisfies**: Constitution V (Drift Detection)

---

## Phase 10: Pester Tests

> Pester unit and integration tests — authored AFTER Joel's manual UAT confirms deployment works.

- [ ] T014 [P] Write Pester unit tests for `Test-TierModelPrerequisites` WinLaps checks — add Context block for `-IncludeWinLaps` switch in `tests/Unit.Prerequisites.Tests.ps1`: schema hard-stop (`WINLAPS_SCHEMA_MISSING`), LAPS module missing, DFL insufficient; per Joel's scope constraints: actual pre-req failures against live AD are NOT tested in the automated suite (Joel tests manually)
  - **Files**: `tests/Unit.Prerequisites.Tests.ps1`
  - **Satisfies**: FR-003, FR-004, SC-004

- [ ] T015 [P] Write Pester unit tests for `Get-TierModelWinLapsAcl` — in `tests/Unit.WinLapsAclOperations.Tests.ps1`: plan generation (3 actions per delegation), fail-fast on missing OUs/groups, idempotency when all DACLs present (`Converged = True`, `TotalActions = 0`), parameter guard (`-IncludeWinLaps -OuOnly` throws)
  - **Files**: `tests/Unit.WinLapsAclOperations.Tests.ps1`
  - **Satisfies**: FR-002, FR-003, FR-005, FR-011

- [ ] T016 [P] Write Pester unit tests for `New-TierModelWinLapsAcl` — in `tests/Unit.WinLapsAclOperations.Tests.ps1`: WhatIf zero-writes (`Applied = 0`), apply from plan (`Applied = N`), apply idempotency (`Applied = 0` on converged), `Converged`/`Skipped`/`Errors` result structure
  - **Files**: `tests/Unit.WinLapsAclOperations.Tests.ps1`
  - **Satisfies**: FR-005, FR-006

- [ ] T017 [P] Write Pester unit tests for `Get-TierModelWinLapsAclFd` — in `tests/Unit.WinLapsAclOperations.Tests.ps1`: lighter validation, `-Silent` support, plan output matches Fd structure, `ExistingCount` metadata
  - **Files**: `tests/Unit.WinLapsAclOperations.Tests.ps1`
  - **Satisfies**: FR-012, FR-008

- [ ] T018 [P] Write Pester unit tests for `Test-TierModelWinLapsAcl` — in `tests/Unit.WinLapsAclOperations.Tests.ps1`: `Compliant`/`MissingAcl`/`UnexpectedAcl` classifications, `-Silent`/`-SuppressSummary` support, drift detection accuracy
  - **Files**: `tests/Unit.WinLapsAclOperations.Tests.ps1`
  - **Satisfies**: FR-005, SC-001

- [ ] T019 [P] Write Pester integration tests — in `tests/Integration.WinLapsDeployment.Tests.ps1`: totals increase with `-IncludeWinLaps` (plan + apply), idempotency convergence (second apply = 0), all four `-Include*` phase labels in stdout with WinLaps after dMSA
  - **Files**: `tests/Integration.WinLapsDeployment.Tests.ps1`
  - **Satisfies**: FR-008, SC-002, SC-007

- [ ] T020 [P] Write Pester regression tests for Windows-LAPS-only invariant — in `tests/Unit.WinLapsAclOperations.Tests.ps1`: every action `objectType` is `ms-LAPS-*`, NONE references `ms-Mcs-*` or `*AdmPwd*`, no `AdmPwd.PS` module calls. Guard against legacy LAPS leakage.
  - **Files**: `tests/Unit.WinLapsAclOperations.Tests.ps1`
  - **Satisfies**: FR-010, SC-005

- [ ] T021 [Storm] Update documentation in `docs/` and `README.md` — document `-IncludeWinLaps` switch for Deploy and Audit scripts, new cmdlets (`Get-TierModelWinLapsAcl`, `New-TierModelWinLapsAcl`, `Test-TierModelWinLapsAcl`, `Get-TierModelWinLapsAclFd`), Windows LAPS schema prerequisite, deployment examples (standalone and full deployment), audit examples, deployment-scope boundary, and the Windows-LAPS-only invariant. Update `docs/detailed-deployment-guide.md`, `docs/deployment-methodology.md`, `docs/cmdlet-architecture.md`, `docs/test-coverage.md`, and `README.md` with consistent "Optional Feature" messaging matching the MSA/gMSA/dMSA documentation pattern.
  - **Files**: `docs/detailed-deployment-guide.md`, `docs/deployment-methodology.md`, `docs/cmdlet-architecture.md`, `docs/test-coverage.md`, `README.md`
  - **Owner**: Storm (DevRel & Documentation)

---

## Dependencies

```
T001, T002 → T003 (optional config file and schema defined before registering in Get-TierModelConfig)
T003 → T004 (config loading before prerequisite checks that read config)
T003, T004 → T005, T006 (shared config + prereqs before standalone cmdlets)
T005, T006 → T007 (standalone deployment working before verification cmdlet)
T005, T006, T007 → T008 (standalone cmdlets before manifest export)
T008 → T009 (manifest before standalone deploy script)
T009 → T010 (standalone deployment working before FD variant)
T010 → T011 (FD cmdlet before manifest export)
T011 → T012 (FD export before deploy script full deployment integration)
T012 → STOP GATE (all deployment complete before manual test)
STOP GATE → T013 (audit integration after Joel confirms deployment)
T013 → T014–T021 (all code working before deferred tests and docs)
```

## Parallel Execution Opportunities

| Tasks | Why Parallel |
|-------|-------------|
| T001, T002 | Independent config file and schema file |
| T005, T006 | Planner and executor are independent cmdlet files |
| T014–T020 | Independent Pester test contexts/files |

## Approval Gates

| After Task | Gate |
|------------|------|
| T009 | ⏸️ **Joel UAT**: Lab test standalone `-IncludeWinLaps` |
| T012 | 🛑 **STOP — MANUAL TEST GATE**: Joel lab-tests deployment end-to-end (see above) |
| T013 | ⏸️ **Joel UAT**: Lab test audit after deployment, audit after manual ACL removal |
| T021 | ⏸️ **Joel final review** |

---

## Summary

| Metric | Count |
|--------|-------|
| **Total phases** | 10 |
| **Total tasks** | 21 |
| **Config/setup tasks** | 2 (T001–T002) |
| **Shared foundation tasks** | 2 (T003–T004) |
| **Existing file modifications** | 7 (T003, T004, T008, T009, T011, T012, T013) |
| **New cmdlet tasks** | 4 (T005, T006, T007, T010) |
| **Pester test tasks** | 7 (T014–T020) |
| **Documentation tasks** | 1 (T021) |
| **Approval gates** | 4 |
| **Parallelizable tasks** | 12 |

### Implementation Strategy
- **MVP**: Phases 1–6 (T001–T009) — config + shared foundations + standalone deployment
- **Increment 2**: Phases 7–8 (T010–T012) — full deployment integration
- **🛑 Manual Test Gate**: Joel verifies in lab before proceeding
- **Increment 3**: Phase 9 (T013) — audit integration
- **Increment 4**: Phase 10 (T014–T021) — Pester tests + documentation (AFTER manual UAT)
