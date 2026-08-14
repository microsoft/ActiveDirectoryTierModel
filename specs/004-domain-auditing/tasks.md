# Tasks: Domain-Root Audit SACL (`-EnableAuditing`)

**Feature Branch**: `feature/domain-auditing`
**Spec**: `specs/004-domain-auditing/spec.md`
**Plan**: `specs/004-domain-auditing/plan.md`
**Generated**: 2026-08-14

---

## ⚠️ Testing Scope Constraints (Joel's Direction — 2026-08-14)

**Sequence:** Write Pester tests BEFORE production implementation. Lab validation follows implementation.

**Squad WILL test:**
- `-EnableAuditing` blocked with any `-*Only` parameter
- `-EnableAuditing` runs standalone and with `-FullDeployment`
- Idempotency: second run returns `Applied = 0`, `Converged = True`
- UNION converge: partial managed ACE → correct union written
- No-clobber: Failure/other-SID/Inherit=None/inherited ACEs survive converge
- Plan status mapping: ABSENT / PARTIAL / COMPLETE / MULTI-ACE
- `GetAuditRules()` enumeration correctness (foreach vs @())
- Privilege missing → `AUDITACL_PRIVILEGE_MISSING` error

**Squad will NOT test (Joel manual):**
- Live SACL write against production domain
- GPO presence/configuration

**Rules:**
- Do NOT modify existing cmdlets beyond the authorized list in plan.md.
- If any issue arises → STOP and ask Joel. Do not brute force.
- Update this file as each task is completed.

---

## Phase 1: Configuration & Schema

- [ ] T001 Create `config/tiermodel-audit.json` with `schemaVersion: "1.0.0"` and `auditSacl` block (targetSid, auditFlags, inheritanceType, rights array — 9 rights).
  - **Files**: `config/tiermodel-audit.json`
  - **Satisfies**: FR-017

- [ ] T002 Add `auditSacl` segment to `config/tiermodel.schema.json` (additive only — no existing properties modified).
  - **Files**: `config/tiermodel.schema.json`
  - **Satisfies**: FR-017

---

## Phase 2: Shared Infrastructure Changes

- [ ] T003 Update `modules/TierModel/public/Get-TierModelConfig.ps1` — register `tiermodel-audit.json` as optional segment; expose `auditSacl` property; include in SHA-256 hash.
  - **Files**: `modules/TierModel/public/Get-TierModelConfig.ps1`
  - **Satisfies**: FR-017, FR-018, Constitution IX

- [ ] T004 Update `modules/TierModel/public/Test-TierModelPrerequisites.ps1` — add `-EnableAuditing` switch; conditional `SeSecurityPrivilege` check; emit `AUDITACL_PRIVILEGE_MISSING` on failure. Must NOT affect deployments that do not pass `-EnableAuditing`.
  - **Files**: `modules/TierModel/public/Test-TierModelPrerequisites.ps1`
  - **Satisfies**: FR-008

---

## Phase 3: Pester Tests (BEFORE Implementation)

> Per Constitution II — tests authored before production code.

- [ ] T005 Author `tests/Unit.AuditRuleOperations.Tests.ps1` — covers all AC-* criteria:
  - AC-IDEM-01/02 (idempotency)
  - AC-UNION-01 through AC-UNION-04 (UNION converge)
  - AC-NOCLOBBER-01 through AC-NOCLOBBER-04 (no-clobber)
  - AC-STATUS-01 through AC-STATUS-04 (plan status)
  - AC-ENUM-01 (GetAuditRules enumeration)
  - Parameter guard (`-EnableAuditing` + `-*Only` = error)
  - Privilege missing → AUDITACL_PRIVILEGE_MISSING
  - **Files**: `tests/Unit.AuditRuleOperations.Tests.ps1`
  - **Satisfies**: FR-003 through FR-010, all AC-* criteria

- [ ] T006 Add `Context "AuditSacl prerequisites"` to `tests/Unit.Prerequisites.Tests.ps1` — privilege check gate (conditional on `-EnableAuditing`).
  - **Files**: `tests/Unit.Prerequisites.Tests.ps1`
  - **Satisfies**: FR-008

---

## 🛑 STOP GATE — Await Joel's Go/No-Go Before Continuing

Review test output with Joel before writing production implementation. Confirm lab spike results are accepted.

---

## Phase 4: Cmdlet Implementation

- [ ] T007 Create `modules/TierModel/public/Get-TierModelAuditRule.ps1` — standalone planner with full privilege + config prereq check; SACL read; converge decision tree; returns plan object (FR-014).
  - **Files**: `modules/TierModel/public/Get-TierModelAuditRule.ps1`
  - **Satisfies**: FR-003, FR-004, FR-005, FR-006, FR-007, FR-013, FR-014

- [ ] T008 Create `modules/TierModel/public/Get-TierModelAuditRuleFd.ps1` — FullDeployment planner; lighter validation; privilege check still mandatory; returns plan object matching Get-TierModelAuditRule shape.
  - **Files**: `modules/TierModel/public/Get-TierModelAuditRuleFd.ps1`
  - **Satisfies**: FR-013, FR-014

- [ ] T009 Create `modules/TierModel/public/New-TierModelAuditRule.ps1` — executor; converge recipe; `SupportsShouldProcess`; `Write-TierModelLog`; returns result object (FR-015).
  - **Files**: `modules/TierModel/public/New-TierModelAuditRule.ps1`
  - **Satisfies**: FR-003, FR-007, FR-009, FR-015, FR-016

- [ ] T010 Create `modules/TierModel/public/Test-TierModelAuditRule.ps1` — read-only audit checker; returns Converged/Status/ExistingRights/MissingRights/Errors.
  - **Files**: `modules/TierModel/public/Test-TierModelAuditRule.ps1`
  - **Satisfies**: FR-019

---

## Phase 5: Deployment Script Integration

- [ ] T011 Update `Deploy-TierModel.ps1` — add `-EnableAuditing` switch; parameter validation guards; standalone mode flow (plan → audit prompt → deploy prompt → apply); FullDeployment mode (pre-compute `Get-TierModelAuditRuleFd` before summary; AuditSacl phase after standard phases); confirmation UX per FR-012.
  - **Files**: `Deploy-TierModel.ps1`
  - **Satisfies**: FR-001, FR-010, FR-011, FR-012

- [ ] T012 Update `Audit-TierModel.ps1` — add `-EnableAuditing` switch; wire to `Test-TierModelAuditRule` conditional on switch.
  - **Files**: `Audit-TierModel.ps1`
  - **Satisfies**: FR-002, FR-019

- [ ] T013 Update `modules/TierModel/TierModel.psd1` — add 4 new cmdlets to `FunctionsToExport`; bump `ModuleVersion` from `1.2.3` to `1.3.0`.
  - **Files**: `modules/TierModel/TierModel.psd1`
  - **Satisfies**: Version requirement

---

## Phase 6: Integration Tests & Lab Validation

- [ ] T014 Author `tests/Integration.AuditDeployment.Tests.ps1` — live-DC tests: apply → verify SACL → re-apply (idempotency) → drift test.
  - **Files**: `tests/Integration.AuditDeployment.Tests.ps1`
  - **Satisfies**: AC-IDEM-01/02, FR-006

- [ ] T015 Lab validation: restore checkpoint → run `-EnableAuditing -ConfirmApply` → verify SACL via `Get-Acl -Audit` → re-run → confirm `Applied = 0` / `Converged = True`.
  - **Satisfies**: AC-IDEM-01/02, FR-006

---

## Phase 7: Docs (Storm)

- [ ] T016 Storm updates documentation per spec.md "Docs to Update" section: `docs/sentinel-monitoring.md`, `README.md`, `CHANGELOG.md`, `docs/faq.md`.
  - **Satisfies**: Docs to Update list in spec.md
