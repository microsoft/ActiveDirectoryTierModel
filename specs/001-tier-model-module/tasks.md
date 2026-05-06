# Tasks: Tier Model AD Deployment & Audit Module

**Input**: Design documents `./spec.md`, `./plan.md`  
**Prerequisites**: `spec.md` (user stories), `plan.md` (phases), schema & module scaffolding already present.

## Format: `[ID] [P?] [Story] Description`
P = Can run in parallel (different files/no dependency conflict)  
Story labels: US1 Initial Deployment, US2 Convergent Update, US3 Drift Audit, US4 Prerequisite Gating, US5 GPO Rights Editing, US6 ADMX Import

---
## Phase 0: Foundational Infrastructure (Blocking)

- [x] T0001 [P] [US4] Establish module structure (evolved to `Modules/TierModel/public/` with one advanced function per file; original `internal/` folder design deprecated). **COMPLETED / UPDATED**
- [x] T0002 [P] [US4] Add `Test-TierModelPrerequisites.ps1` advanced function (direct public export; no separate `Prerequisites.ps1`). **COMPLETED / UPDATED** 
- [x] T0003 [US4] Implement PS version + elevation checks inside `Test-TierModelPrerequisites.ps1` (legacy reference to `Prerequisites.ps1` removed). **COMPLETED / UPDATED**
- [x] T0004 [P] [US4] Implement module version matching (parse `config/dependencies.json`) **COMPLETED** 
- [x] T0005 [US4] Domain Admin membership + PreferredDc reachability checks **COMPLETED**
- [x] T0006 [P] [US4] DNS groups presence & domain type detection (includes DnsAdmins group check) **COMPLETED**
- [x] T0007 [US4] Remediation mapping & unified result object (Valid/Errors/Remediation) **COMPLETED**
- [x] T0008 [P] [US4] Pester tests: failure scenarios (non-admin, wrong PS version, missing module) **COMPLETED**
- [x] T0009 [US4] Integrate prerequisite gate into `New/Set-TierModel` (abort if invalid) **COMPLETED**
 - [x] T0009a [P] [US4] Scaffold `Deploy-TierModel.ps1` & `Audit-TierModel.ps1` scripts with parameter sets (initially included `-ImportAdmxOnly` & conditional `-AdmxFolderPath`; superseded by `-AdmxOnly` and config-driven ADMX). **COMPLETED / UPDATED**
 - [x] T0009b [US4] Implement mutually exclusive scope switch validation (throws on multiple scopes). **COMPLETED**
 - [x] T0009c [US4] (Deprecated) Early validation for mandatory `-AdmxFolderPath` removed after transition to JSON-declared ADMX (no external path parameter). **RETIRED**

**Checkpoint**: Prerequisite gate fully functional; proceed to resource ordering. **COMPLETED**

---
## Phase 1: Schema & Validation Enhancements

- [x] T0010 [P] [US1] Add deep validation warnings (enum modes, denyApplyGroups existence) in `Test-TierModelConfig` **COMPLETED**
- [x] T0011 [US1] Pester tests: invalid GPO mode, missing group reference in denyApplyGroups **COMPLETED**
 - [x] T0011a [P] [US6] Add ADMX source path validation (exists, contains ≥1 .admx, has default locale folder `en-US`). **COMPLETED**
 - [x] T0011b [US6] Pester tests: ADMX source missing locale folder; zero .admx files scenario. **COMPLETED**

**Checkpoint**: Config validation robust; prevents invalid plan actions. **COMPLETED**

---
## Phase 2: Ordering & Plan Generation (Deployment Skeleton)

- [x] T0012 [US1] Implement ordering logic within `Get-TierModelPlan.ps1` (no standalone `Ordering.ps1`; action plan construction centralized). **COMPLETED / UPDATED**
- [x] T0013 [P] [US1] Implement OU parent-first ordering logic **COMPLETED**
- [x] T0014 [P] [US1] Implement group creation ordering & membership defer list **COMPLETED**
- [x] T0015 [P] [US1] Implement user creation ordering (validate target OU exists) **COMPLETED**
- [x] T0016 [US1] Inject action objects into `Get-TierModelPlan` output with `Adds/Updates/Links` **COMPLETED**
- [x] T0017 [US1] Pester tests: ordering (OU before child OU; group before user membership) **COMPLETED**
- [x] T0018 [US2] Plan membership delta for existing groups (add only missing members) **COMPLETED**
 - [x] T0018a [P] [US6] Integrate ADMX template enumeration into action plan when scope includes ADMX (produce Import/Skip actions). **COMPLETED**

**Checkpoint**: Action plan deterministic; initial deployment plan testable. **COMPLETED**

---
## Phase 3: ACL Delegations

- [x] T0019 [US1] Implement OU ACL delegation via public functions `New-TierModelOuAcl.ps1`, `Test-TierModelOuAcl.ps1`, `Get-TierModelOuAcl.ps1` (supersedes internal helper). **COMPLETED / UPDATED**
- [x] T0020 [P] [US1] Implement delegation action planning (validate principals & targets) **COMPLETED**
- [x] T0021 [US1] Implement apply logic using ADSI/Set-ACL (stub if environment absent) **COMPLETED**
- [x] T0022 [US1] Pester tests: ACL plan generation with missing principal error case **COMPLETED**

**Checkpoint**: ACL delegation integrated into plan/apply. **COMPLETED**

---
## Phase 4: GPO Import/Create & Linking

- [x] T0023 [US1] Implement GPO import/create using `Import-TierModelGpo.ps1`, `New-TierModelGpo.ps1`, `New-TierModelGPOLink.ps1` (replacing `GpoImport.ps1` stub). **COMPLETED / UPDATED**
- [x] T0024 [P] [US1] Implement GPO creation + capturing GUID **COMPLETED**
- [x] T0025 [P] [US1] Implement import path handling & link actions (linkEnabled flag) **COMPLETED**
- [x] T0026 [US1] Add denyApplyGroups permission operations **COMPLETED**
- [x] T0027 [US1] Pester tests: import vs create branch; link enabled state **COMPLETED**
- [x] T0028 [US2] Update plan to treat changed GPO link as Update action **COMPLETED**

**Checkpoint**: GPO import/create/link pipeline functional. **COMPLETED**

---
## Phase 5: SID Resolution & Rights Editing

- [x] T0029 [US5] Add SID resolution in `Resolve-TierModelPrincipalSid.ps1` (no separate `SidResolution.ps1`; public advanced function). **COMPLETED / UPDATED**
- [x] T0030 [P] [US5] Cache resolved SIDs; add unit tests for well-known principals **COMPLETED**
- [x] T0031 [US5] Implement GPO rights editing using `Set-TierModelGpoTemplate.ps1`, `New-TierModelGptTmplContent.ps1`, `Update-TierModelGPOConfig.ps1` (replaces `GpoEditing.ps1`). **COMPLETED / UPDATED**
- [x] T0032 [US5] Implement URA line generation (resolve vs raw) **COMPLETED**
- [x] T0033 [P] [US5] Implement restricted group line generation **COMPLETED**
- [x] T0034 [US5] Atomic write & backup pre-edit **COMPLETED**
- [x] T0035 [US5] Pester tests: SID resolution success/failure; INF diff minimality **COMPLETED**

**Checkpoint**: GPO rights editing produces deterministic INF output. **COMPLETED**

---
## Phase 6: ADMX Import

- [x] T0036 [US6] Implement ADMX template handling via `Get-TierModelAdmx.ps1`, `Test-TierModelAdmx.ps1`, `Copy-TierModelAdmx.ps1` (supersedes planned `AdmxImport.ps1`). **COMPLETED / UPDATED**
- [x] T0037 [P] [US6] Implement import action planning (overwrite all existing files) **COMPLETED**
- [x] T0038 [US6] Pester tests: missing vs present ADMX scenario **COMPLETED**
 - [x] T0039 [US6] Add validation of locale ADML pairing (warn if ADML absent for a source ADMX). **COMPLETED**
 - [x] T0040 [US6] Implement `Get-TierModelAdmxState` (public) returning template manifest (SourceName, DestinationExists, HasDefaultLocale, Action). **COMPLETED**
 - [x] T0041 [P] [US6] Implement `Import-TierModelAdmx` with WhatIf support and structured action output. **COMPLETED**
 - [x] T0042 [US6] Pester tests: Import-TierModelAdmx WhatIf output, missing locale warning classification. **COMPLETED**
- [x] T0043 [US6] Ensure `-AdmxOnly` scope runs ADMX phase exclusively (legacy `ImportAdmxOnly` naming retired). **COMPLETED / UPDATED**

**Checkpoint**: ADMX actions integrated; plan shows only required imports. **COMPLETED**

---
## Phase 7: Drift Detection Expansion

- [x] T0044 [US3] Implement drift snapshot/comparison inside `Test-TierModelDrift` (no separate `Drift.ps1`). **COMPLETED / UPDATED**
- [x] T0045 [P] [US3] Implement OU/Group/User drift comparison **COMPLETED**
- [x] T0046 [P] [US3] Implement GPO link & rights drift comparison **COMPLETED**
- [x] T0047 [US3] Implement ACL delegation drift classification **COMPLETED**
- [x] T0048 [US3] Integrate drift findings into `Test-TierModelDrift` **COMPLETED**
- [x] T0049 [US3] Pester tests: injected discrepancies classification **COMPLETED**
 - [x] T0049a [P] [US3] Drift: ADMX state comparison (missing template vs unexpected extra) classification. **COMPLETED**

**Checkpoint**: Drift report comprehensive with classification. **COMPLETED**

---
## Phase 8: Idempotency & Convergence

- [x] T0050 [US2] Add PlanHash computation based on sorted action list + config hash **COMPLETED**
- [x] T0051 [US2] Implement second-run convergence detection (empty actions → Converged=true) **COMPLETED**
- [x] T0052 [US2] Pester tests: convergence after apply **COMPLETED**
 - [x] T0052a [US6] Idempotency test: second run after ADMX import produces zero ADMX Import actions. **COMPLETED**

**Checkpoint**: Idempotent behavior verifiable. **COMPLETED**

---
## Phase 9: Logging & CI Integration

- [x] T0053 [P] [US1] Implement `Write-TierModelLog` structured logging helper **COMPLETED**
- [x] T0054 [P] [US1] Add logging calls to major action execution points **COMPLETED**
- [x] T0055 [US1] Add GitHub Actions (or Azure DevOps) pipeline YAML: ScriptAnalyzer + Invoke-Pester **COMPLETED**
- [x] T0056 [US3] Publish drift report artifact in CI **COMPLETED**
- [x] T0057 [US5] Security: ensure no sensitive data logged (test for redaction) **COMPLETED**
 - [x] T0057a [P] [US6] Logging: verify ADMX import actions recorded with Action=Import or Skip and DurationMs >0. **COMPLETED**

**Checkpoint**: CI green baseline with logs; artifacts produced. **COMPLETED**

---
## Phase 10: Backward Compatibility & Governance

- [x] T0058 [US2] Add previous version sample config `config/tiermodel.v1.sample.json` **COMPLETED**
- [x] T0059 [US2] Test loading previous config version; ensure non-breaking **COMPLETED**
- [x] T0060 [US1] Update constitution version if new governance rules added **COMPLETED**

**Checkpoint**: Version governance enforced; backward compatibility validated. **COMPLETED**

---
## Phase 11: Documentation & Polish

- [x] T0061 [P] [US1] Update README with prerequisite cmdlet & ordering explanation **COMPLETED**
- [x] T0062 [P] [US3] Add drift usage and interpretation section **COMPLETED**
- [x] T0063 [P] [US5] Document GPO rights editing process + examples **COMPLETED**
- [x] T0064 [US1] Add Quickstart snippet referencing spec + plan **COMPLETED**
- [x] T0065 [US1] Add CHANGELOG entry for major features **COMPLETED**
 - [x] T0066 [US6] README section: ADMX import usage examples (FullDeployment vs ImportAdmxOnly) + troubleshooting (missing locale). **COMPLETED**
 - [x] T0067 [US6] Original documentation for conditional `-AdmxFolderPath`; superseded by ADMX JSON declaration and `-AdmxOnly` scope (docs updated). **RETIRED**

**Checkpoint**: Documentation complete; ready for wider adoption. **COMPLETED**

---
## Parallel Opportunities Summary
- Tasks marked [P] can be split among contributors without conflict.
- Each user story phase independently testable after its checkpoint.

## Acceptance Gate Alignment
- Every phase produces artifacts to satisfy spec success criteria (SC-001..SC-007).
- Idempotency, drift accuracy, and rights editing validated before CI integration completion.

## Remaining Open Questions (Traceability)
- Deletion semantics not yet scheduled (future tasks TBD)
- Cross-domain references intentionally excluded (scope control)

---
Generated from spec and plan documents.
