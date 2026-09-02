# Tasks: Authentication Policy Silos (`-IncludeAuthSilos`)

**Feature Branch**: `feature/auth-silos`
**Spec**: `specs/005-auth-silos/spec.md`
**Plan**: `specs/005-auth-silos/plan.md`
**Generated**: 2026-08-24

---

## ⚠️ Phase Gating Notes

This is a scoping-phase spec. Implementation tasks are **deferred** and will be defined after:
1. The manual ops-guide walkthrough session with Joel resolves OQ-001 through OQ-010 (Phase 1)
2. Design decisions are finalized and detailed FRs are written (Phase 2)

Do not begin Phase 3 or later without Joel's explicit go/no-go after the walkthrough.

---

## Phase 1: Spec Finalization via Ops-Guide Walkthrough

- [ ] T001 **Ops-guide walkthrough session with Joel**: step through the auth-silo mechanics, the current script limitations, the proposed silo/policy object model, and open questions OQ-001 through OQ-010.
  - **Input**: `specs/005-auth-silos/spec.md`, `.research/auth-silos/` research pack (esp. A1, A8, B, E1)
  - **Output**: Resolved decisions for OQ-001 through OQ-010 (or the subset Joel prioritizes); decision records to be written in T002
  - **Notes**: Review the pre-enforcement gates G1–G12 (spec User Story 3) and confirm the intended enforcement flip UX. Confirm Tier device group ownership and pre-population process.

- [ ] T002 **Record walkthrough decisions as ADRs**: for each open question resolved in T001, write a decision record in `.squad/decisions/inbox/`.
  - **Files**: `.squad/decisions/inbox/` — one file per material decision
  - **Satisfies**: Audit trail required before design phase begins

---

## ⛔ STOP GATE — Await Joel's Go/No-Go Before Phase 2

Review T001 walkthrough outcomes with Joel and confirm scope before proceeding to design.

---

## Phase 2: Design Decisions and Detailed FRs (Post-Walkthrough)

- [ ] T003 **Finalize detailed FRs and acceptance criteria** (AC-* table) in `specs/005-auth-silos/spec.md`:
  - SDDL OR logic correctness test matrix (approved device: pass; non-approved device: fail)
  - Idempotency criteria: no-op run executes zero AD write cmdlets
  - Delta-only assignment criteria: SID normalization, threshold logic (separate add/remove), empty-query halt
  - Enforcement flip UX and gate verification steps
  - Exemption data structure and lifecycle
  - Update spec status from Draft (scoping) to Draft (design)
  - **Files**: `specs/005-auth-silos/spec.md`

- [ ] T004 **Design cmdlet contracts**: parameter shapes, return object structures, plan/result object shapes for Get / Get-Fd / New / Test cmdlets.
  - **Files**: `specs/005-auth-silos/plan.md` (update New Files section with full contracts)

- [ ] T005 **Design configuration schema**: `tiermodel-authsilos.json` field structure; `authSilos` segment definition in `config/tiermodel.schema.json`.
  - **Files**: `specs/005-auth-silos/plan.md`; later `config/tiermodel-authsilos.json` and `config/tiermodel.schema.json`

- [ ] T006 **Design SDDL generation strategy**: runtime SID resolution vs. config-authored SDDL; validation approach for OR vs. AND boolean logic correctness; test harness for positive/negative device checks.
  - **Files**: Decision record in `.squad/decisions/inbox/`; update `specs/005-auth-silos/plan.md`

- [ ] T007 **Design exemption data structure**: representation format, grant authorization model, expiry enforcement, scope-widening protection, and how the deployment code handles expired or over-scope exemptions.
  - **Files**: Decision record; update `specs/005-auth-silos/spec.md` (OQ-003 resolution)

---

## ⛔ STOP GATE — Await Joel's Review of Design Phase Deliverables

Review T003–T007 outputs with Joel before writing production code.

---

## Phase 3: Implementation (Deferred — To Be Defined After Design Phase)

> Task details will be filled in after design decisions are finalized (T003–T007). The buckets below establish sequencing; details are placeholders.

- [ ] T008 **Configuration and schema**: Create `config/tiermodel-authsilos.json` with `schemaVersion` and four silo definitions; add `authSilos` segment to `config/tiermodel.schema.json` (additive only). Include structural exemption SIDs in config.
  - **Files**: `config/tiermodel-authsilos.json`, `config/tiermodel.schema.json`
  - **Satisfies**: FR (config integration)

- [ ] T009 **Tier 2 EUD base-config additions**: Add `svc-t2euddomainjoin`, `Tier2EUDDomainJoin`, `Tier 2 EUD Staging` OU, delegated create-computer ACL, and Tier 2 EUD Account Restriction GPO config to the appropriate Tier Model base config files. This is a prerequisite for the Tier 2 EUD silo deployment.
  - **Files**: `config/tiermodel-users.json`, `config/tiermodel-groups.json`, `config/tiermodel-ous.json`, `config/tiermodel-acls.json`, relevant GPO config
  - **Satisfies**: "Required New Config Addition" section; Tier 2 EUD silo prerequisite

- [ ] T009 **Prerequisite infrastructure**: Update `modules/TierModel/public/Test-TierModelPrerequisites.ps1` — add `-IncludeAuthSilos` switch; conditional checks for DFL, FAST GPO validation, AD module presence; emit stable error codes.
  - **Files**: `modules/TierModel/public/Test-TierModelPrerequisites.ps1`
  - **Satisfies**: FR-006

- [ ] T010 **Config integration**: Update `modules/TierModel/public/Get-TierModelConfig.ps1` — register `tiermodel-authsilos.json` as optional segment; expose `authSilos` property; include in SHA-256 hash.
  - **Files**: `modules/TierModel/public/Get-TierModelConfig.ps1`
  - **Satisfies**: FR (config integration), Constitution IX

- [ ] T011 **Pester tests — BEFORE production implementation** (Constitution II):
  - `tests/Unit.AuthSiloOperations.Tests.ps1`: idempotency (no-op = zero writes), delta-only assignment (SID normalization), SDDL OR logic validation, RID-500 exclusion, prereq gate checks, plan status mapping, error codes
  - Extend `tests/Unit.Prerequisites.Tests.ps1` with auth-silo prereq context
  - **Files**: `tests/Unit.AuthSiloOperations.Tests.ps1`, `tests/Unit.Prerequisites.Tests.ps1`
  - **Satisfies**: All AC-* criteria; Constitution II

- [ ] T012 **Cmdlet implementation — Get-TierModelAuthSilo**: standalone planner; full prereq validation; FAST GPO check; silo/policy/assignment plan generation; plan object per spec FR-010.
  - **Files**: `modules/TierModel/public/Get-TierModelAuthSilo.ps1`
  - **Satisfies**: FR-001, FR-003, FR-006, FR-007, FR-010

- [ ] T013 **Cmdlet implementation — Get-TierModelAuthSiloFd**: FullDeployment planner; lighter prereq check; plan pre-compute for FD summary; prereq check still required.
  - **Files**: `modules/TierModel/public/Get-TierModelAuthSiloFd.ps1`
  - **Satisfies**: FR-001, FR-010

- [ ] T014 **Cmdlet implementation — New-TierModelAuthSilo**: executor; create silo objects, policies, grants, and assignments; delta-only; RID-500 exclusion enforced; `SupportsShouldProcess`; `Write-TierModelLog`; result object per spec.
  - **Files**: `modules/TierModel/public/New-TierModelAuthSilo.ps1`
  - **Satisfies**: FR-003, FR-004, FR-005, FR-007, FR-008, FR-009, FR-015

- [ ] T015 **Cmdlet implementation — Test-TierModelAuthSilo**: read-only audit checker; drift detection for silo/policy/assignment/device-group state; returns structured result with `Converged`, drift findings, and errors.
  - **Files**: `modules/TierModel/public/Test-TierModelAuthSilo.ps1`
  - **Satisfies**: FR-002, FR-013

- [ ] T016 **Deploy-TierModel.ps1 integration**: add `-IncludeAuthSilos` switch; blocked combos with `-*Only`; standalone flow (plan → confirmation → apply); FullDeployment flow (FD pre-compute before summary; phase after other optional phases); confirmation UX.
  - **Files**: `Deploy-TierModel.ps1`
  - **Satisfies**: FR-001, FR-010, FR-011

- [ ] T017 **Audit-TierModel.ps1 integration**: add `-IncludeAuthSilos` switch; wire to `Test-TierModelAuthSilo` conditional on switch; silo state not reported without switch.
  - **Files**: `Audit-TierModel.ps1`
  - **Satisfies**: FR-002, FR-013

- [ ] T018 **Module manifest**: add new cmdlets to `FunctionsToExport`; bump `ModuleVersion` per OQ-010 resolution.
  - **Files**: `modules/TierModel/TierModel.psd1`
  - **Satisfies**: Version requirement

---

## Phase 4: Integration Tests and Lab Validation

- [ ] T019 **Author integration tests**: `tests/Integration.AuthSiloDeployment.Tests.ps1` — live-DC tests: create silo/policy objects → verify state → second-run idempotency → drift detection via `Test-TierModelAuthSilo` → partial-state cleanup.
  - **Files**: `tests/Integration.AuthSiloDeployment.Tests.ps1`
  - **Satisfies**: FR-007, AC-* idempotency criteria

- [ ] T020 **Lab validation — audit mode (UAT-01–04, UAT-15)**: restore checkpoint → run `-IncludeAuthSilos -ConfirmApply` for all four silos → verify silo/policy state and account assignments → second run = 0 actions (UAT-15) → `Audit-TierModel.ps1 -IncludeAuthSilos` confirms converged.
  - **Lab**: `TierLab-DC01`, `tierlab.internal`
  - **Satisfies**: FR-007; US-1 acceptance scenarios; UAT-01 through UAT-04

- [ ] T021 **Lab validation — negative tests / cross-tier deny (UAT-05–07)**: verify that a standard non-Tier-Model server (UAT-05) and cross-tier devices (Tier 1 PAW vs Tier 0 account: UAT-06; EUD vs Tier 1 account: UAT-07) produce 305 events in audit mode and 105 denials in enforced mode. Confirms SDDL OR logic is correct and tier isolation is real.
  - **Satisfies**: UAT-05, UAT-06, UAT-07; G1 pre-enforcement gate evidence

- [ ] T022 **Lab validation — new-device onboarding sequence (UAT-08–09)**: verify that a device not yet in the approved group is denied (UAT-08); after adding to group and replication, verify TGT issuance succeeds (UAT-09). Documents onboarding sequencing and replication timing.
  - **Satisfies**: UAT-08, UAT-09; G3 pre-enforcement gate evidence

- [ ] T023 **Lab validation — domain-join exempt accounts (UAT-10–11, UAT-13)**: enable `svc-t1srvdomainjoin` during provisioning window; domain-join a Tier 1 server; verify account is not blocked by silo (UAT-10). Repeat for `svc-t2euddomainjoin` once Tier 2 EUD config additions are deployed (UAT-11). With Tier 0 Admin silo enforced, verify `svc-pawdomainjoin` still operates (UAT-13).
  - **Satisfies**: UAT-10, UAT-11, UAT-13; CON-010 validation

- [ ] T024 **Lab validation — pre-enforcement gates and RID-500 recovery (UAT-12, UAT-14)**: attempt enforcement without passing gate checklist (UAT-12 — should be blocked or operator-flagged). In separate lab-only destructive test: misconfigure SDDL to exclude all approved devices, enforce, verify RID-500 can authenticate from DC console and revert enforcement (UAT-14).
  - **Lab-only** — destructive test; requires VM snapshot before execution
  - **Satisfies**: UAT-12, UAT-14; G4 recovery path validation; SI-01 invariant

---

## Phase 5: Review and Release

- [ ] T025 **Lab validation — pre-enforcement gates G1–G12**: work through the full gate checklist using the lab environment; document evidence for each gate; confirm all UAT pass/fail criteria per ops guide; establish the lab-validation runbook.
  - **Input**: Pre-enforcement gates table in spec User Story 3; UAT-01 through UAT-15 scenarios
  - **Satisfies**: US-3 pre-conditions; G1–G12 gate evidence requirements

- [ ] T026 **Architecture review**: verify implementation satisfies CON-001 through CON-010 and FR-001 through FR-015. Specific checks: four silo objects created (not just policies), OR logic in all SDDL, `Enforce = false` in all objects, RID-500 and domain-join accounts excluded, no enforcement in deployment flow, Tier 2 EUD config additions present.

- [ ] T027 **Joel's manual lab UAT**: run UAT-01 through UAT-15 per ops guide; verify all positive/negative/exemption/recovery scenarios; confirm no-op second run and drift detection.

- [ ] T028 **Documentation**: update `README.md`, `CHANGELOG.md`, and `docs/` files for the new feature; include audit-only labeling guidance; four-silo model; domain-join exemptions; pre-enforcement gate checklist location.
  - **Files**: `README.md`, `CHANGELOG.md`, relevant `docs/` files
  - **Satisfies**: Documentation standards
