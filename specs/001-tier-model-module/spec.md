# Feature Specification: Tier Model AD Deployment & Audit Module

**Feature Branch**: `[001-tier-model-module]`  
**Created**: 2025-10-28  
**Status**: Draft  
**Input**: User description: "PowerShell module deploying Tier Model (OUs, Groups, Users, ACL Delegations, GPO import/create/edit/linking, ADMX import) from version-controlled JSON; idempotent reruns; drift audit; Get/New/Set cmdlets; prerequisite gating."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declarative Initial Deployment (Priority: P1)
Administrator supplies a validated segmented JSON configuration (fixed path under `config`) and runs `Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -ConfirmApply [-Confirm]` to deploy the entire Tier Model (OUs, Groups, Users, ACLs, GPOs, ADMX) to a fresh or partially prepared domain. Without `-ConfirmApply` the script performs a plan-only dry run regardless of `-WhatIf`.

**Why this priority**: Foundational capability enabling the framework; without initial declarative deployment subsequent convergence and auditing are impossible.

**Independent Test**: With prerequisite mocks (passing), executing without `-ConfirmApply` produces an ordered plan listing all creates; executing with `-ConfirmApply` yields reported success and a converged follow-up plan (no remaining Adds).

**Acceptance Scenarios**:
1. **Given** a valid config and reachable DC, **When** running with `-WhatIf`, **Then** a plan object lists ordered actions (OUs before Groups, Groups before Users, etc.).
2. **Given** the same config and `-ConfirmApply`, **When** executed, **Then** resources are created and a second dry run (without `-ConfirmApply`) reports 0 adds.

---

### User Story 2 - Convergent Update (Priority: P2)
Administrator updates segmented configuration (e.g., adds a user, modifies a GPO link) and runs `Deploy-TierModel.ps1 -PreferredDc DC01 -UserOnly` (or other scope) to converge the environment.

**Why this priority**: Enables safe incremental evolution without manual scripting.

**Independent Test**: Modify config (add group member); plan lists update action; applying yields updated membership and subsequent plan shows no changes.

**Acceptance Scenarios**:
1. **Given** existing deployed Tier Model, **When** adding a new group member in JSON, **Then** plan shows membership update only.
2. **Given** an added GPO link in JSON, **When** applying, **Then** link exists and is enabled as specified.

---

### User Story 3 - Drift Audit (Priority: P3)
Security engineer runs `Audit-TierModel.ps1 -PreferredDc DC01 -FullDeployment -OutputFormat Json` to detect deviations (unexpected groups, missing ACL delegation, altered GPO rights).

**Why this priority**: Provides ongoing assurance and supports compliance.

**Independent Test**: Manually change a group membership outside JSON; drift report flags discrepancy with classification.

**Acceptance Scenarios**:
1. **Given** a user removed from a group in AD, **When** drift test runs, **Then** report lists MissingMembership finding.
2. **Given** an extra OU exists not declared, **When** drift test runs, **Then** report lists UnexpectedOU.

---

### User Story 4 - Prerequisite Gating (Priority: P4)
Operator runs `Test-TierModelPrerequisites -PreferredDc DC01 -DependenciesPath config/dependencies.json` before deployment; function fails fast with remediation if conditions unmet.

**Why this priority**: Prevents partial deployments and unclear failure modes.

**Independent Test**: Simulate non-admin session; test returns failure with remediation instruction.

**Acceptance Scenarios**:
1. **Given** PowerShell 5.1 host, **When** prerequisites run, **Then** result invalid with recommendation to use PS 7+.
2. **Given** missing ActiveDirectory module, **When** prerequisites run, **Then** result lists module missing with install instructions.
 3. **Given** a malformed JSON segment (e.g., missing required `groups` file), **When** deployment pre-flight runs, **Then** execution aborts fail-fast before any changes with non-zero exit code and remediation message.

---

### User Story 5 - GPO Security Rights Editing (Priority: P5)
Engineer declares user rights assignments (URAs) and restricted groups in JSON; system resolves SIDs and updates GptTmpl.inf atomically.

**Why this priority**: Critical for enforcing least privilege and consistent security baseline.

**Independent Test**: Create test GPO; JSON defines URA; edit function rewrites lines; subsequent run detects no diff.

**Acceptance Scenarios**:
1. **Given** a URA with resolvable principal, **When** applying, **Then** GptTmpl.inf includes correct SID line.
2. **Given** restricted group with members, **When** applying, **Then** group membership lines reflect resolved SIDs.

---

### User Story 6 - ADMX Import (Priority: P6)
Administrator specifies ADMX files; module imports them if absent on PreferredDc.

**Why this priority**: Ensures required policy definitions present before GPO editing.

**Independent Test**: Remove ADMX, run WhatIf; plan shows import actions.

**Acceptance Scenarios**:
1. **Given** missing ADMX file, **When** plan executed, **Then** import action listed.
2. **Given** ADMX exists, **When** plan executed, **Then** overwrite file.

---

### Edge Cases
- Missing parent OU for nested child → plan shows error and blocks execution before applying.
- Attempt to link GPO to non-existent OU → flagged as invalid action.
- SID resolution fails for principal name → drift or apply reports unresolved principal with remediation.
- PreferredDc unreachable mid-run → execution aborts; partial changes logged; re-run yields idempotent recovery.
- JSON includes denyApplyGroups referencing non-existent group → validation error prior to apply.
 - Missing denyApplyGroups target group acceptance scenario: **Given** a GPO definition with `denyApplyGroups` containing a non-existent group, **When** pre-flight validation runs, **Then** deployment aborts fail-fast with an error listing the unresolved group name.
- Child domain lacking Enterprise Admin group in URA → auto-skip with warning (if declared) or error if required.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: System MUST deploy resources (OUs, Groups, Users, ACL Delegations, GPOs, ADMX) from a segmented configuration (multiple JSON files under a fixed module-relative `config` directory) treated as one logical TierModelConfig (no runtime path override).
- **FR-002**: System MUST validate prerequisites before any mutating operation.
- **FR-003**: System MUST support `-WhatIf` for plan-only output on New/Set operations.
- **FR-004**: System MUST ensure idempotency—second immediate Set run yields zero changes.
- **FR-005**: System MUST compute and log configuration SHA256 hash for provenance.
- **FR-006**: System MUST resolve AD object SIDs for URA and Restricted Group declarations when `resolveSid=true`.
- **FR-007**: System MUST update GptTmpl.inf atomically only if content diff detected.
- **FR-008**: System MUST classify drift findings (Missing, Unexpected, Mismatch) across all resource types.
- **FR-009**: System MUST pin dependency versions and fail if mismatched.
- **FR-010**: System MUST provide remediation guidance for each failed prerequisite.
- **FR-011**: System MUST run all AD operations against a single `-PreferredDc`.
- **FR-012**: System MUST support both GPO import (existing backup folder) and raw create + edit modes.
- **FR-013**: System MUST allow deny apply ACL entries on GPOs (`denyApplyGroups`).
- **FR-014**: System MUST support OU flags: disable inheritance, block GPO inheritance.
- **FR-015**: System MUST allow optional comment on every JSON entity without affecting logic.
- **FR-016**: System SHOULD provide dry-run risk summary (counts adds/updates/high-risk operations).
- **FR-017**: System SHOULD support backward compatibility tests for prior config versions.
- **FR-018**: System SHOULD redact sensitive values from logs (no credentials, no user PII beyond names).
- **FR-019**: System MUST fail if domain admin membership not present.
- **FR-020**: System MUST detect child vs parent domain and adapt security object expectations.
 - **FR-021**: System MUST load configuration only from the fixed module-relative `config` directory (no caller override parameter).
 - **FR-022**: System MUST generate a run-level CorrelationId (GUID) and include it in every log entry.
 - **FR-023**: System MUST produce a dry-run (WhatIf/audit) risk summary aggregating counts by Action (Create|Update|Link|Import|Edit) and Risk (Low|Medium|High).
 - **FR-024**: System MUST ensure logging redacts or excludes any secret material (no passwords; only non-sensitive identifiers logged).
 - **FR-025**: System SHOULD extend drift classification with OrphanedGpoLink and SecurityDelta categories in addition to Missing|Unexpected|Mismatch.
 - **FR-026**: Deployment script MUST require explicit `-ConfirmApply` switch for any mutating actions; absence forces dry-run plan-only behavior even if `-WhatIf` not specified. Audit script MUST NOT require this switch.

### Key Entities
- **TierModelConfig**: Root object; version, preferredDc, arrays for OUs, Groups, Users, ACL Delegations, GPOs, ADMX.
- **OU**: name, path, protectFromAccidentalDeletion, disableInheritance, blockGpoInheritance, comment.
- **Group**: name, scope, members[], comment.
- **User**: samAccountName, displayName, ouPath, email, enabled, comment.
- **ACL Delegation**: targetPath, principal, rights[], comment.
- **GPO**: name, mode, guid?, importPath?, links[], linkEnabled, scope[], denyApplyGroups[], userRightsAssignments[], restrictedGroups[], enabled, comment.
- **UserRightsAssignment**: right, principals[], resolveSid, comment.
- **RestrictedGroup**: groupName, members[], resolveSid, comment.
- **ADMX**: path, language, comment.
- **PlanAction**: orderIndex, resourceType, name, action, rationale, dependsOn[], risk.
- **DriftFinding**: type (Missing|Unexpected|Mismatch), resourceType, identifier, details.
- **PrereqResult**: Valid (bool), Errors[], Remediation[], EnvironmentSnapshot.

### Command Surface Mapping (Revised)
-Legacy monolithic orchestration removed; current surface:
- Deployment script: `Deploy-TierModel.ps1` with explicit scope switches (`-FullDeployment`, `-OuOnly`, `-GroupOnly`, `-UserOnly`, `-OuAclsOnly`, `-GposOnly`, `-AdmxOnly`).
- Audit script: `Audit-TierModel.ps1` mirrors scope for drift/compliance.
- Planning: `Get-TierModelPlan` (public advanced function) builds action list without performing changes.
- Drift: `Test-TierModelDrift` returns categorized findings; script wrapper produces optional formatted/exported report.
- Resource CRUD: Discrete `New-/Get-/Test-` functions per resource (e.g., `New-TierModelOu`, `New-TierModelGroup`, `New-TierModelUser`, `New-TierModelGpo`, `New-TierModelGPOLink`).
- ADMX Handling: `Get-TierModelAdmx`, `Test-TierModelAdmx`, `Copy-TierModelAdmx` (import/copy operations) executed when `-AdmxOnly` or as final phase of full deployment.
- Prerequisites: `Test-TierModelPrerequisites` public function invoked early by scripts.

Configuration is always loaded from the fixed module-relative `config` directory (no `-TierModelJsonPath`, no external ADMX source path parameter).

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-001**: Initial deployment completes with zero fatal errors and passes idempotency retest (second Set WhatIf shows 0 actions).
- **SC-002**: Drift audit detects >95% of manually induced discrepancies in test suite.
- **SC-003**: Prerequisite function identifies and provides remediation for 100% of simulated failure scenarios.
- **SC-004**: GPO rights editing rewrites only expected lines (file diff limited to `[Privilege Rights]` & `[Group Membership]` blocks) in all test cases.
- **SC-005**: Average plan generation executes in <5 seconds for config with 50 OUs, 100 groups, 200 users (performance baseline).
- **SC-006**: 100% functions covered by at least one Pester test (initial goal: ≥70% then iterate to 100%).
- **SC-007**: No unpinned module versions in deployment environment (audit script returns 0 violations).
 - **SC-008**: 100% log entries include the same run-level CorrelationId.
 - **SC-009**: Dry-run (WhatIf/audit) output includes a risk summary object with counts per Action and per Risk level.
 - **SC-010**: Any deployment invocation lacking `-ConfirmApply` performs zero mutations and exits with plan-only output; invocation with `-ConfirmApply` applies actions and a subsequent run without `-ConfirmApply` shows 0 planned actions.

### Non-Functional (Implicit)
- Logging structured (JSON lines optional future) with correlation id.
- Safe failure: partial apply stops with clear summary; re-run resolves automatically without manual cleanup.

## Test Strategy (Supplemental)
- Pester suites: Prereq, Schema Validation, Plan Ordering, Idempotency, Drift Simulation, GPO Editing, SID Resolution.
- Use mocks for AD cmdlets where live domain not available; integration tests optional.

## Risks & Mitigations
- Risk: SID resolution failures → Mitigation: fallback to principal name with warning; classification in drift.
- Risk: Race conditions with replication → Mitigation: single DC targeting.
- Risk: Large config performance → Mitigation: caching lookups, lazy SID resolution.
- Risk: Incorrect file editing of GptTmpl.inf → Mitigation: compute hash pre/post, backup original.

## Roadmap (High-Level)
1. Prereqs & Schema Validation
2. OU/Group/User foundation
3. ACL Delegations
4. GPO Import/Create
5. URA / Restricted Groups editing
6. Drift classification
7. ADMX import
8. Performance tuning + advanced logging
9. Backward compatibility tests

## Open Questions
- Should we support cross-domain references? (Currently out of scope.)
- How to handle removal operations (explicit vs no-op)?
- Policy for orphaned objects not in JSON (delete vs flag)?
 
### Clarifications / Non-Requirements
* Automatic deletion of unmanaged (orphaned) AD objects is explicitly out of scope for this iteration; such objects are surfaced via drift only.
* Additional ADMX locales beyond the default (e.g., `en-US`) are treated as unmanaged; missing default locale produces a warning, not an error.

## Appendices
- Constitution alignment: Principles I–IX satisfied (quality, test-first, idempotency, modularization, dependency governance).
- Dependencies pinned in `config/dependencies.json`.

---
Generated using spec template and existing TierModel design context.
