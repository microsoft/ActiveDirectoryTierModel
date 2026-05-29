# Feature Specification: Managed Service Account Support (MSA, gMSA, dMSA)

**Feature Branch**: `[002-gmsa-support]`  
**Created**: 2026-05-29  
**Status**: Draft  
**Input**: User description: "Add new parameters to Tier Model deployment and audit to configure MSA, gMSA, and dMSA permissions into the Tier Model OU structure. Enable creation, modification, and deletion of these 3 object types at deployment and auditing time. Supports organizational move towards managed service accounts over traditional service accounts."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Managed Service Account Permissions (Priority: P1)
Administrator runs `Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -IncludeGmsa -ConfirmApply` (and/or `-IncludeMsa`, `-IncludeDmsa`) to deploy ACL delegations on the existing `Tier X Service Accounts` OUs that enable creation, modification, and deletion of managed service accounts within the appropriate tiers. No new OUs or groups are created — the deployment adds ACL delegations for the selected managed service account object classes to the existing Tier X Admins groups across all three tiers (Tier 0, 1, 2). Without `-ConfirmApply` the script performs a plan-only dry run.

**Clarifications Applied**:
- **OU Placement**: Existing `Tier 0 Service Accounts`, `Tier 1 Service Accounts`, `Tier 2 Service Accounts` OUs are reused. No new OUs created.
- **Delegation Groups**: Existing `Tier0Admins`, `Tier1Admins`, `Tier2Admins` groups receive new ACL delegations for managed service account object classes. No new groups created.
- **Tier 0 Note**: Tier 0 Admins already have ACL at the root `Tier Model Administration` OU — confirm whether additional explicit ACLs are needed for managed service account object classes on the `Tier 0 Service Accounts` OU specifically, or if the inherited delegation is sufficient.
- **Scope**: When an `-Include*` switch is specified, delegation is applied across all three tiers uniformly.

**Why this priority**: Foundational capability; without the ACL delegations in place, Tier Admins cannot provision managed service accounts within the tiered model.

**Independent Test**: With prerequisite mocks (passing), executing with `-IncludeGMSA` without `-ConfirmApply` produces a plan listing ACL delegation actions for gMSA object class on all three Tier Service Account OUs; executing with `-ConfirmApply` yields reported success and a converged follow-up plan (0 remaining adds).

**Acceptance Scenarios**:
1. **Given** a deployed Tier Model and a reachable DC, **When** running with `-IncludeGmsa` without `-ConfirmApply`, **Then** a plan lists ACL delegations for gMSA create/modify/delete on all three `Tier X Service Accounts` OUs for the existing Tier X Admins groups.
2. **Given** the same invocation with `-ConfirmApply`, **When** executed, **Then** ACL delegations permit Tier X Admins to create/modify/delete gMSA objects in their respective `Tier X Service Accounts` OUs. A second dry run reports 0 adds.
3. **Given** an existing Tier Model deployment, **When** running with `-IncludeMsa -IncludeGmsa -IncludeDmsa -ConfirmApply`, **Then** the system applies ACL delegations for all three object classes across all three tiers.

---

### User Story 2 - Audit Managed Service Account Configuration (Priority: P2)
Security engineer runs `Audit-TierModel.ps1 -PreferredDc DC01 -FullDeployment -IncludeGmsa -OutputFormat Json` and the drift report includes managed service account ACL delegations on the existing `Tier X Service Accounts` OUs alongside existing resource types.

**Why this priority**: Ongoing assurance that managed service account ACL delegations remain correctly configured and have not drifted from declared state.

**Independent Test**: Manually remove a gMSA delegation ACL from `Tier 1 Service Accounts` OU; drift report flags the discrepancy with the appropriate classification.

**Acceptance Scenarios**:
1. **Given** a deployed Tier Model with gMSA ACL delegations, **When** a gMSA create ACL is removed from `Tier 1 Service Accounts`, **Then** drift report lists a MissingAcl finding with the specific right and target path.
2. **Given** an unexpected ACL granting dMSA rights exists when `-IncludeDmsa` was never applied, **When** drift audit runs with `-IncludeDmsa`, **Then** the audit detects and reports the existing delegation correctly.
3. **Given** a Tier Model with `-IncludeGmsa` deployed, **When** drift audit runs without `-IncludeGmsa`, **Then** gMSA ACL delegations are not included in the drift scope (only audits what was requested).

---

### User Story 3 - Convergent Update of Managed Service Account Configuration (Priority: P3)
Administrator modifies managed service account scope (e.g., adds `-IncludeDMSA` to a deployment that previously only had `-IncludeGMSA`, or changes ACL rights in config) and runs deployment to converge the environment.

**Why this priority**: Enables incremental evolution of managed service account permissions without full redeployment.

**Independent Test**: Run deployment adding `-IncludeDMSA` to previously gMSA-only deployment; plan lists only the new dMSA ACL delegations; apply yields the new ACLs and subsequent plan shows 0 changes.

**Acceptance Scenarios**:
1. **Given** existing gMSA ACL delegations deployed across all tiers, **When** running with `-IncludeGmsa -IncludeDmsa -ConfirmApply`, **Then** plan shows only the new dMSA ACL delegations (gMSA already converged).
2. **Given** a change to which AD rights are delegated for MSA objects, **When** applying, **Then** ACL delegation is updated and subsequent plan shows 0 changes.

---

### User Story 4 - Selective Deployment Scope for Managed Service Accounts (Priority: P4)
Administrator runs deployment with `-ManagedServiceAccountsOnly` (or equivalent scope switch) combined with `-IncludeMsa`, `-IncludeGmsa`, or `-IncludeDmsa` to target only managed service account ACL delegations, leaving other Tier Model resources untouched.

**Why this priority**: Enables targeted changes to managed service account ACL delegations without risk of affecting unrelated resources.

**Independent Test**: Run deployment with managed service account scope switch and `-IncludeGmsa`; only gMSA ACL delegations appear in plan; no other resource types affected.

**Acceptance Scenarios**:
1. **Given** a full Tier Model config, **When** running with `-ManagedServiceAccountsOnly -IncludeGmsa`, **Then** plan lists only gMSA ACL delegations on `Tier X Service Accounts` OUs.
2. **Given** changes to both group config and managed service account ACLs, **When** running with managed service account scope only, **Then** only managed service account ACL changes appear in plan.

---

### Edge Cases
- gMSA KDS root key not present in domain → prerequisite check warns but does not block. The Tier Model checks for KDS key presence and effective time; it never creates or modifies KDS keys. Users must create KDS keys manually before deploying gMSA/dMSA ACLs.
- dMSA object type not supported on current domain functional level → prerequisite check reports incompatibility with remediation guidance (Windows Server 2025 required).
- `-IncludeDmsa` specified but domain functional level too low → deployment warns and skips dMSA ACL delegations (or errors, per chosen behavior).
- ACL delegation for managed service account types conflicts with existing deny ACE → drift report flags SecurityDelta finding.
- Tier 0 Admins already have GenericAll at `Tier Model Administration` root — confirm whether inherited rights cover managed service account object classes or explicit ACLs needed on `Tier 0 Service Accounts`.
- Running audit with `-IncludeGmsa` on a domain that never had gMSA deployed → report shows MissingAcl for all tiers (expected when comparing against desired state).
- dMSA accounts cannot be migrated from existing gMSA accounts. The `Start-ADServiceAccountMigration` cmdlet only supports migration from traditional service accounts. dMSA accounts delegated by this feature must be created fresh. This feature provides ACL delegation for dMSA creation, not a migration path from gMSA.
- If a gMSA is added to the Protected Users group (accidentally or by policy), the gMSA will stop authenticating. This is an operational concern outside the scope of ACL delegation but should be documented as a known interaction.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: System MUST support `-IncludeMsa`, `-IncludeGmsa`, and `-IncludeDmsa` as switch parameters on `Deploy-TierModel.ps1` and `Audit-TierModel.ps1`.
- **FR-002**: When an `-Include*` switch is specified, the system MUST apply ACL delegations for that managed service account object class across all three tiers (Tier 0, Tier 1, Tier 2) on the existing `Tier X Service Accounts` OUs.
- **FR-003**: ACL delegations MUST grant the existing Tier X Admins groups (Tier0Admins, Tier1Admins, Tier2Admins) create, modify, and delete permissions for the specified managed service account object class. Rights model: Two ACEs per tier per type — CreateChild/DeleteChild on the OU scoped to object class GUID, plus GenericAll on descendant objects.
- **FR-004**: System MUST support the three AD object classes: `msDS-ManagedServiceAccount` (MSA), `msDS-GroupManagedServiceAccount` (gMSA), and `msDS-DelegatedManagedServiceAccount` (dMSA).
- **FR-005**: System MUST ensure idempotency — second immediate deployment run with the same `-Include*` switches yields zero changes.
- **FR-006**: System MUST include managed service account ACL delegations in drift audit when the corresponding `-Include*` switch is specified.
- **FR-007**: System MUST classify drift findings for managed service account ACL delegations using existing categories (Missing, Unexpected, Mismatch).
- **FR-008**: System MUST support `-WhatIf` for all managed service account deployment operations.
- **FR-009**: System MUST NOT create new OUs or new security groups — only ACL delegations on existing OUs for existing groups.
- **FR-010**: System SHOULD provide a `-ManagedServiceAccountsOnly` scope switch for targeting only managed service account ACL delegations.
- **FR-011**: System SHOULD detect domain functional level and warn when `-IncludeDmsa` is specified but unsupported.
- **FR-012**: System MUST log all managed service account operations with the run-level CorrelationId.
- **FR-013**: System MUST NOT allow managed service account deployment without `-ConfirmApply` (consistent with existing deployment behavior per constitution).
- **FR-014**: Multiple `-Include*` switches MAY be combined in a single invocation (e.g., `-IncludeMsa -IncludeGmsa`).

### Key Entities
- **ManagedServiceAccountType**: Enum — `MSA`, `gMSA`, `dMSA`, mapped to AD object classes.
- **ManagedServiceAccountACL**: ACL delegation entry granting create/modify/delete rights for a specific managed service account object class to an existing Tier X Admins group on the corresponding `Tier X Service Accounts` OU.
- **Include Switches**: `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` — each enables ACL delegation for the corresponding object class across all three tiers.

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-001**: Deployment with managed service account config creates all declared OUs, groups, and ACL delegations; second run shows 0 planned actions.
- **SC-002**: Drift audit detects >95% of manually induced managed service account discrepancies (removed groups, modified ACLs, unexpected OUs) in test suite.
- **SC-003**: Managed service account deployment completes independently via scope switch without affecting other Tier Model resources.
- **SC-004**: All three managed service account types (MSA, gMSA, dMSA) are supported with distinct object class targeting in ACL delegations.
- **SC-005**: Pre-flight validation catches 100% of invalid managed service account configurations (bad tier references, missing groups, unsupported object classes).
- **SC-006**: All managed service account functions covered by Pester tests (unit + idempotency + drift).
- **SC-007**: dMSA incompatibility on lower domain functional levels produces a clear warning with remediation guidance.

### Non-Functional (Implicit)
- Managed service account operations follow existing logging standards (structured, CorrelationId, redaction).
- Performance: Adding managed service account support does not increase plan generation time by more than 10% for existing configurations without managed service account definitions.

## Assumptions
- The existing Tier Model OU structure is deployed (spec 001) — specifically, `Tier 0 Service Accounts`, `Tier 1 Service Accounts`, and `Tier 2 Service Accounts` OUs exist.
- The existing `Tier0Admins`, `Tier1Admins`, and `Tier2Admins` security groups exist and are the delegation targets.
- No new OUs or groups are created by this feature — only ACL delegations are added.
- KDS root key provisioning is outside the scope of this feature (domain-wide operation).
- The feature adds permissions for managed service accounts; it does not create actual MSA/gMSA/dMSA objects — that is left to operational teams using the delegated permissions.
- Tier 0 Admins may already have sufficient inherited permissions from the `Tier Model Administration` root OU — this needs verification during planning; explicit ACLs will be added if inheritance is insufficient.

## Test Strategy (Supplemental)
- Pester suites: Schema Validation (new MSA/gMSA/dMSA config sections), OU Creation, Group Creation, ACL Delegation, Idempotency, Drift Simulation for managed service account resources, Domain Functional Level detection.
- Use mocks for AD cmdlets where live domain not available.
- Integration tests against test domain optional.

## Risks & Mitigations
- Risk: dMSA is a very new object type (Windows Server 2025) with limited tooling → Mitigation: detect domain functional level; degrade gracefully with clear warning; isolate dMSA logic for easy updates.
- Risk: ACL delegation for managed service account object classes requires extended rights GUIDs that vary → Mitigation: resolve GUIDs from schema at runtime; cache in session; test with known-good GUIDs.
- Risk: Existing ACL delegations could conflict with new managed service account delegations → Mitigation: audit existing ACLs before applying; flag conflicts as SecurityDelta findings.
- Risk: Tier 0 Admins inherited GenericAll may already cover managed service account objects → Mitigation: verify during planning; skip redundant ACLs or apply explicitly for auditability.

## Dependencies
- Spec 001 (Tier Model AD Deployment & Audit Module) must be implemented as the base.
- Active Directory schema must include `msDS-GroupManagedServiceAccount` class (Windows Server 2012+).
- For dMSA support: Windows Server 2025 domain functional level required.
