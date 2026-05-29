# Tasks: Managed Service Account Support (MSA, gMSA, dMSA)

**Feature Branch**: `002-gmsa-support`  
**Spec**: `specs/002-gmsa-support/spec.md`  
**Plan**: `specs/002-gmsa-support/plan.md`  
**Generated**: 2026-05-29T18:03:29.139+08:00

---

## Phase 1: Setup & Configuration

> Foundation configuration files and GUID mappings that all subsequent tasks depend on.

- [ ] T001 [P] Create MSA ACL delegation config in `config/tiermodel-msa.json` with `managedServiceAccountType: "MSA"`, optional add-on ACL entries for Tier 0/1/2 Service Accounts OUs, and the decided rights model matching the existing Computer delegation pattern: two ACEs per applicable tier/type combination — (1) `CreateChild`/`DeleteChild` scoped to `msDS-ManagedServiceAccount` on the OU, (2) `GenericAll` on descendant objects of that class; verify Tier 0 parent OU full-control coverage before adding any explicit Tier 0 ACE
- [ ] T002 [P] Create gMSA ACL delegation config in `config/tiermodel-gmsa.json` with `managedServiceAccountType: "gMSA"`, optional add-on ACL entries for Tier 0/1/2 Service Accounts OUs, and the same two-ACE rights model: (1) `CreateChild`/`DeleteChild` scoped to `msDS-GroupManagedServiceAccount` on the OU, (2) `GenericAll` on descendant objects of that class, matching the existing Computer delegation pattern
- [ ] T003 [P] Create dMSA ACL delegation config in `config/tiermodel-dmsa.json` with `managedServiceAccountType: "dMSA"`, optional add-on ACL entries for Tier 0/1/2 Service Accounts OUs, and the same two-ACE rights model: (1) `CreateChild`/`DeleteChild` scoped to `msDS-DelegatedManagedServiceAccount` on the OU, (2) `GenericAll` on descendant objects of that class, matching the existing Computer delegation pattern
- [ ] T004 Update `config/tiermodel-guid-mappings.json` — add `msDS-ManagedServiceAccount` (`ce206244-5827-4a86-ba1c-1c0c386c1b64`) and `msDS-GroupManagedServiceAccount` (`7b8b558a-93a5-4af7-adca-c017e67f1057`) to `staticMappings.objectClasses`; add `msDS-DelegatedManagedServiceAccount` to new `dynamicMappings.objectClasses` section with `{{resolve_guid:msDS-DelegatedManagedServiceAccount}}` syntax

---

## Phase 2: Existing Cmdlet Changes — Shared Config & Prerequisites

> Modify shared config and prerequisite helpers before introducing any new MSA/gMSA/dMSA deployment cmdlets. **These are existing file modifications — review separately.**

- [ ] T005 Update `modules/TierModel/public/Get-TierModelConfig.ps1` — load `tiermodel-msa.json`, `tiermodel-gmsa.json`, and `tiermodel-dmsa.json` as optional config segments (do NOT add them to `$requiredFiles`), merge their `aclDelegations` into the unified config object only when files are present, preserve current behavior when absent, include optional segment content in the composite hash only when loaded, and ensure downstream cmdlets receive the merged config object from `Get-TierModelConfig` rather than reading raw JSON directly
- [ ] T006 Update `modules/TierModel/tools/Resolve-DomainSpecificGuid.ps1` — add `-SchemaObjectClass` parameter with default value `attributeSchema`, preserve existing behavior for current callers, and allow dMSA callers to pass `classSchema` when resolving `msDS-DelegatedManagedServiceAccount`
- [ ] T007 Update `modules/TierModel/public/Test-TierModelPrerequisites.ps1` — add `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switch parameters. When `-IncludeMsa` is specified: validate schema version ≥ 47 and verify `msDS-ManagedServiceAccount` class exists in the schema partition. When `-IncludeGmsa` is specified: validate schema version ≥ 56, DFL ≥ Windows2012Domain, verify `msDS-GroupManagedServiceAccount` class exists, and run `Get-KdsRootKey` on the target DC by using `Invoke-Command -ComputerName $PreferredDomainController`. When `-IncludeDmsa` is specified: validate schema version ≥ 91, DFL = Windows2025Domain, FFL = Windows2025Forest, verify `msDS-DelegatedManagedServiceAccount` class exists via `classSchema`, and run the same remote KDS check. KDS validation is read-only only: confirm a KDS root key exists AND its effective time is more than 10 hours old; the Tier Model MUST NEVER execute `Add-KdsRootKey`. Add remediation messages: if no KDS key exists, instruct the user to create it manually; if the key exists but is younger than 10 hours, instruct the user to wait until the replication window elapses. Add results to `EnvironmentSnapshot` (for example `SchemaVersion`, `DomainFunctionalLevel`, `ForestFunctionalLevel`, `KdsRootKeyExists`, `KdsRootKeyEffective`, `MsaSchemaClassExists`, `GmsaSchemaClassExists`, `DmsaSchemaClassExists`). Update `config/dependencies.json` as part of this task if the required KDS module dependency is not already listed. Do not change existing prerequisite checks — only add new checks when `-Include*` switches are present.

---

## Phase 3: MSA Standalone Deployment [US1] [US4]

> New cmdlets for MSA (Managed Service Account) ACL delegation — standalone mode.

- [ ] T008 [P] [US1] Create `modules/TierModel/public/Get-TierModelMsaAcl.ps1` — plan MSA ACL delegations for standalone deployment using the merged config object from `Get-TierModelConfig`. Resolve domain DN via `Resolve-TierModelDomainDN`, validate target OUs exist in live AD (Tier 0/1/2 Service Accounts — fail-fast if missing with "Run -FullDeployment first or -OuOnly"), validate delegation groups exist (Tier0Admins/Tier1Admins/Tier2Admins — fail-fast if missing), resolve GUIDs via `Resolve-TierModelGuid`, and compare live ACLs to the decided two-ACE model per applicable tier/type combination: (1) `CreateChild`/`DeleteChild` scoped to `msDS-ManagedServiceAccount` on the OU, (2) `GenericAll` on descendant objects of that class. Return plan object with `Actions`, `Summary` (`TotalActions`, `CreateActions`, `RiskAssessment`), `Warnings`, and `Errors` matching `Get-TierModelOuAcl` output structure. Parameters: `-Config`, `-DomainController`, `-IncludeDetails`. Use `Write-TierModelLog` for structured logging with CorrelationId.
- [ ] T009 [P] [US1] Create `modules/TierModel/public/New-TierModelMsaAcl.ps1` — apply MSA ACL delegations from plan. Accept plan object from `Get-TierModelMsaAcl`, apply the decided two-ACE model using `System.DirectoryServices.ActiveDirectoryAccessRule`, and return result object with `Applied`, `Skipped`, `Errors`, `DurationMs`, `Converged` matching `New-TierModelOuAcl` output structure. Use DC-qualified LDAP binding: `LDAP://$DomainController/$targetOUPath`. Resolve group SIDs properly (not just NTAccount translation). MUST include GUID null/empty guard — if resolved GUID is null, empty string, or `[Guid]::Empty`, throw terminating error to prevent over-scoped ACE.

---

## Phase 4: gMSA Standalone Deployment [US1] [US4]

> New cmdlets for gMSA (Group Managed Service Account) ACL delegation — standalone mode.

- [ ] T010 [P] [US1] Create `modules/TierModel/public/Get-TierModelGmsaAcl.ps1` — plan gMSA ACL delegations for standalone deployment using the merged config object from `Get-TierModelConfig`. Follow the same validation and planning pattern as `Get-TierModelMsaAcl.ps1`, but target `msDS-GroupManagedServiceAccount` and compare live ACLs to the decided two-ACE model: (1) `CreateChild`/`DeleteChild` scoped to the gMSA object class on the OU, (2) `GenericAll` on descendant objects of that class. Return plan object with `Actions`, `Summary` (`TotalActions`, `CreateActions`, `RiskAssessment`), `Warnings`, and `Errors` matching `Get-TierModelOuAcl` output structure.
- [ ] T011 [P] [US1] Create `modules/TierModel/public/New-TierModelGmsaAcl.ps1` — apply gMSA ACL delegations from plan. Follow the same implementation pattern as `New-TierModelMsaAcl.ps1`, apply the two-ACE model for `msDS-GroupManagedServiceAccount`, use DC-qualified LDAP binding `LDAP://$DomainController/$targetOUPath`, and return result object matching `New-TierModelOuAcl` output structure. MUST include GUID null/empty guard — if resolved GUID is null, empty string, or `[Guid]::Empty`, throw terminating error to prevent over-scoped ACE.

---

## Phase 5: dMSA Standalone Deployment [US1] [US4]

> New cmdlets for dMSA (Delegated Managed Service Account) ACL delegation — standalone mode.

- [ ] T012 [P] [US1] Create `modules/TierModel/public/Get-TierModelDmsaAcl.ps1` — plan dMSA ACL delegations for standalone deployment using the merged config object from `Get-TierModelConfig`. Follow the same validation and planning pattern as `Get-TierModelMsaAcl.ps1`, but target `msDS-DelegatedManagedServiceAccount` and resolve its schema GUID dynamically by extending `Resolve-DomainSpecificGuid -SchemaObjectClass classSchema` (not hardcoding the GUID). Compare live ACLs to the decided two-ACE model: (1) `CreateChild`/`DeleteChild` scoped to the dMSA object class on the OU, (2) `GenericAll` on descendant objects of that class. Return plan object with `Actions`, `Summary` (`TotalActions`, `CreateActions`, `RiskAssessment`), `Warnings`, and `Errors` matching `Get-TierModelOuAcl` output structure.
- [ ] T013 [P] [US1] Create `modules/TierModel/public/New-TierModelDmsaAcl.ps1` — apply dMSA ACL delegations from plan. Follow the same implementation pattern as `New-TierModelMsaAcl.ps1`, apply the two-ACE model for `msDS-DelegatedManagedServiceAccount` using the dynamically resolved GUID, use DC-qualified LDAP binding `LDAP://$DomainController/$targetOUPath`, and return result object matching `New-TierModelOuAcl` output structure. MUST include GUID null/empty guard — if resolved GUID is null, empty string, or `[Guid]::Empty`, throw terminating error to prevent over-scoped ACE.

---

## Phase 6: Existing Module Manifest Update

> Update module manifest to export all new standalone public functions. **This is an existing file modification — review separately.**

- [ ] T014 Update `modules/TierModel/TierModel.psd1` — add all new standalone public functions to `FunctionsToExport`: `Get-TierModelMsaAcl`, `New-TierModelMsaAcl`, `Get-TierModelGmsaAcl`, `New-TierModelGmsaAcl`, `Get-TierModelDmsaAcl`, `New-TierModelDmsaAcl`. (FD variants and Test cmdlets will be added in later phases when created.) Increment module version if appropriate.

---

## Phase 7: Existing Script Changes — Deploy Standalone Mode [US1] [US4]

> Update Deploy-TierModel.ps1 for standalone `-Include*` deployment. **This is an existing file modification — review separately.**

- [ ] T015 [US1] Update `Deploy-TierModel.ps1` — add `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switch parameters to the param block. Update parameter validation: `-Include*` switches can be used standalone (without any scope parameter) or combined with `-FullDeployment` only — never with `-OuOnly`, `-GroupOnly`, etc. When `-Include*` is used standalone: call `Get-TierModelConfig` once so the cmdlets receive the merged optional MSA/gMSA/dMSA config object, pass switches to `Test-TierModelPrerequisites` for fail-fast validation, then for each active switch call the corresponding `Invoke-*Deployment` function (create these inline functions following the existing `Invoke-OuDeployment` pattern). Each `Invoke-*Deployment` calls `Get-TierModel*Acl` for planning and `New-TierModel*Acl` for apply when `-ConfirmApply`. Report deployment counts accurately. Support planning mode (no `-ConfirmApply`) and execution mode.

---

## Phase 8: MSA Full Deployment Integration [US1] [US3]

> Create FD variant and integrate MSA into FullDeployment optional features section.

- [ ] T016 [US1] Create `modules/TierModel/public/Get-TierModelMsaAclFd.ps1` — plan MSA ACL delegations for full deployment mode using the merged config object from `Get-TierModelConfig`. Same logic as `Get-TierModelMsaAcl.ps1` but with lighter validation: assume OUs and groups will exist from earlier deployment phases, validate against configured state during planning, validate against live AD during apply, follow the same two-ACE rights model, and use `-Silent` for consolidated reporting. Return plan object matching `Get-TierModelOuAclFd.ps1` output structure.

---

## Phase 9: gMSA Full Deployment Integration [US1] [US3]

> Create FD variant and integrate gMSA into FullDeployment optional features section.

- [ ] T017 [US1] Create `modules/TierModel/public/Get-TierModelGmsaAclFd.ps1` — plan gMSA ACL delegations for full deployment mode using the merged config object from `Get-TierModelConfig`. Same lighter validation pattern as `Get-TierModelMsaAclFd.ps1`, same two-ACE rights model, and output structure matching `Get-TierModelOuAclFd.ps1`.

---

## Phase 10: dMSA Full Deployment Integration [US1] [US3]

> Create FD variant and integrate dMSA into FullDeployment optional features section.

- [ ] T018 [US1] Create `modules/TierModel/public/Get-TierModelDmsaAclFd.ps1` — plan dMSA ACL delegations for full deployment mode using the merged config object from `Get-TierModelConfig`. Same lighter validation pattern as `Get-TierModelMsaAclFd.ps1`, but resolve the dMSA GUID dynamically via `Resolve-DomainSpecificGuid -SchemaObjectClass classSchema`, follow the same two-ACE rights model, and return output matching `Get-TierModelOuAclFd.ps1`.

---

## Phase 11: Existing File Changes — FD Exports & Deploy Full Deployment Mode [US1] [US3]

> Update module exports and Deploy-TierModel.ps1 for FullDeployment + `-Include*` integration. **These are existing file modifications — review separately.**

- [ ] T019 [US1] Update `modules/TierModel/TierModel.psd1` — add `Get-TierModelMsaAclFd`, `Get-TierModelGmsaAclFd`, and `Get-TierModelDmsaAclFd` to `FunctionsToExport`
- [ ] T020 [US1] Update `Deploy-TierModel.ps1` — add optional features section after ADMX (last standard step) in the FullDeployment flow. This section is NOT numbered (optional features are unnumbered). For each active `-Include*` switch: reuse the merged config object from `Get-TierModelConfig`, call the corresponding FD variant (`Get-TierModelMsaAclFd`, `Get-TierModelGmsaAclFd`, `Get-TierModelDmsaAclFd`) for planning, and call `New-TierModel*Acl` for apply when `-ConfirmApply`. Skip optional features section entirely if standard deployment had errors. Include optional feature results in consolidated deployment summary reporting. Order: MSA → gMSA → dMSA (simplest prerequisites first). Planning mode should validate against configured state (OUs/groups from config, not live AD since they may not exist yet in a fresh domain).

---

## Phase 12: MSA Audit Integration [US2]

> Create Test cmdlet and integrate MSA drift detection into Audit script.

- [ ] T021 [US2] Create `modules/TierModel/public/Test-TierModelMsaAcl.ps1` — audit/drift check for MSA ACL delegations using the merged config object from `Get-TierModelConfig`. Verify both expected ACEs for each configured delegation: scoped `CreateChild`/`DeleteChild` on the target OU and `GenericAll` on descendant `msDS-ManagedServiceAccount` objects. Report findings as `Compliant`, `MissingAcl`, and `UnexpectedAcl`. Return result object compatible with audit reporting structure and follow `Test-TierModelOuAcl.ps1` pattern.
- [ ] T022 [US2] Update `modules/TierModel/TierModel.psd1` — add `Test-TierModelMsaAcl` to `FunctionsToExport`

---

## Phase 13: gMSA Audit Integration [US2]

> Create Test cmdlet and integrate gMSA drift detection into Audit script.

- [ ] T023 [US2] Create `modules/TierModel/public/Test-TierModelGmsaAcl.ps1` — audit/drift check for gMSA ACL delegations using the merged config object from `Get-TierModelConfig`. Verify both expected ACEs for each configured delegation: scoped `CreateChild`/`DeleteChild` on the target OU and `GenericAll` on descendant `msDS-GroupManagedServiceAccount` objects. Return result compatible with audit reporting and follow `Test-TierModelOuAcl.ps1` pattern.
- [ ] T024 [US2] Update `modules/TierModel/TierModel.psd1` — add `Test-TierModelGmsaAcl` to `FunctionsToExport`

---

## Phase 14: dMSA Audit Integration [US2]

> Create Test cmdlet and integrate dMSA drift detection into Audit script.

- [ ] T025 [US2] Create `modules/TierModel/public/Test-TierModelDmsaAcl.ps1` — audit/drift check for dMSA ACL delegations using the merged config object from `Get-TierModelConfig`. Resolve the dMSA GUID dynamically via `Resolve-DomainSpecificGuid -SchemaObjectClass classSchema`, verify both expected ACEs for each configured delegation (scoped `CreateChild`/`DeleteChild` on the target OU plus `GenericAll` on descendant `msDS-DelegatedManagedServiceAccount` objects), and return result compatible with audit reporting.
- [ ] T026 [US2] Update `modules/TierModel/TierModel.psd1` — add `Test-TierModelDmsaAcl` to `FunctionsToExport`

---

## Phase 15: Existing Script Changes — Audit Script [US2]

> Update Audit-TierModel.ps1 for `-Include*` drift detection. **This is an existing file modification — review separately.**

- [ ] T027 [US2] Update `Audit-TierModel.ps1` — add `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switch parameters to the param block. Update parameter validation to match `Deploy-TierModel.ps1` rules (standalone or with `-FullDeployment` only). Load merged optional config via `Get-TierModelConfig`, pass `-Include*` switches to `Test-TierModelPrerequisites`, and for each active switch call the corresponding `Test-TierModel*Acl` cmdlet. Include MSA/gMSA/dMSA drift results in consolidated audit report. When running `-FullDeployment` with `-Include*`, audit optional features after standard audit scope. Only audit what was requested.

---

## Phase 16: Pester Tests [Deferred]

> Pester unit tests — ONLY after Joel's manual UAT confirms all code is working.

- [ ] T028 [P] Write Pester unit tests for `Test-TierModelPrerequisites` MSA/gMSA/dMSA checks in `tests/Test-TierModelPrerequisites.Tests.ps1` — mock AD queries, test each `-Include*` switch independently, test remote KDS validation via `Invoke-Command`, verify missing-key and not-yet-effective remediation messages, verify Tier Model never calls `Add-KdsRootKey`, and test that existing prerequisite checks are unaffected
- [ ] T029 [P] Write Pester unit tests for `Get-TierModelMsaAcl` in `tests/Get-TierModelMsaAcl.Tests.ps1` — mock AD queries, test plan generation against the two-ACE rights model, test fail-fast when OUs or groups are missing, and test idempotency when existing ACEs are already present
- [ ] T030 [P] Write Pester unit tests for `New-TierModelMsaAcl` in `tests/New-TierModelMsaAcl.Tests.ps1` — mock AD operations, test both ACE applications, test DC-qualified LDAP binding, test GUID guard behavior, and test result object structure
- [ ] T031 [P] Write Pester unit tests for `Get-TierModelGmsaAcl` in `tests/Get-TierModelGmsaAcl.Tests.ps1` — same coverage as MSA planning tests but for gMSA object class and summary schema
- [ ] T032 [P] Write Pester unit tests for `New-TierModelGmsaAcl` in `tests/New-TierModelGmsaAcl.Tests.ps1` — same coverage as MSA apply tests but for gMSA
- [ ] T033 [P] Write Pester unit tests for `Get-TierModelDmsaAcl` in `tests/Get-TierModelDmsaAcl.Tests.ps1` — include dynamic GUID resolution through `Resolve-DomainSpecificGuid -SchemaObjectClass classSchema`
- [ ] T034 [P] Write Pester unit tests for `New-TierModelDmsaAcl` in `tests/New-TierModelDmsaAcl.Tests.ps1` — include dynamic GUID handling, GUID guard behavior, and DC-qualified LDAP binding
- [ ] T035 [P] Write Pester unit tests for FD variants (`Get-TierModelMsaAclFd`, `Get-TierModelGmsaAclFd`, `Get-TierModelDmsaAclFd`) — test lighter validation (configured state vs. live AD), optional merged config loading, and `-Silent` behavior
- [ ] T036 [P] Write Pester unit tests for audit cmdlets (`Test-TierModelMsaAcl`, `Test-TierModelGmsaAcl`, `Test-TierModelDmsaAcl`) — test the two-ACE audit model and `Compliant`/`MissingAcl`/`UnexpectedAcl` classifications
- [ ] T037 Update documentation in `docs/` and `README.md` — document `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switches for Deploy and Audit scripts, merged optional config loading via `Get-TierModelConfig`, prerequisites per account type, deployment examples (standalone and full deployment), and audit examples

---

## Dependencies

```
T001, T002, T003, T004 → T005 (optional config loading after add-on files and GUID mappings are defined)
T004 → T006 (GUID mapping design aligned before extending domain-specific resolver)
T005, T006 → T007 (shared config loading and resolver updates before prerequisite checks)
T005, T006, T007 → T008, T009, T010, T011, T012, T013 (shared foundation before standalone cmdlets)
T008, T009, T010, T011, T012, T013 → T014 (standalone cmdlets before manifest export)
T014 → T015 (manifest before standalone deploy script)
T015 → T016, T017, T018 (standalone deployment working before FD variants)
T016, T017, T018 → T019 (FD cmdlets before manifest export)
T019 → T020 (FD exports before deploy script full deployment integration)
T020 → T021, T023, T025 (deployment flow working before audit cmdlets)
T021 → T022; T023 → T024; T025 → T026 (audit cmdlets before manifest export)
T022, T024, T026 → T027 (audit cmdlets exported before audit script)
T027 → T028-T037 (all code working before deferred tests and docs)
```

## Parallel Execution Opportunities

| Tasks | Why Parallel |
|-------|-------------|
| T001, T002, T003, T004 | Independent config file and GUID mapping changes |
| T008+T009, T010+T011, T012+T013 | Separate standalone cmdlet files per account type |
| T016, T017, T018 | Independent FD planner variants per account type |
| T021, T023, T025 | Independent audit cmdlets per account type |
| T028–T036 | Independent Pester test files |

## Approval Gates

| After Task | Gate |
|------------|------|
| T015 | ⏸️ **Joel UAT**: Lab test standalone `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` individually and combined |
| T020 | ⏸️ **Joel UAT**: Lab test `-FullDeployment -IncludeGmsa`, `-FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa` |
| T027 | ⏸️ **Joel UAT**: Lab test audit after deployment, audit after manual ACL removal |
| T037 | ⏸️ **Joel final review** |

---

## Summary

| Metric | Count |
|--------|-------|
| **Total phases** | 16 |
| **Total tasks** | 37 |
| **Config/setup tasks** | 4 (T001–T004) |
| **Shared foundation tasks** | 3 (T005–T007) |
| **Existing file modifications** | 12 (T004, T005, T006, T007, T014, T015, T019, T020, T022, T024, T026, T027) |
| **New cmdlet tasks** | 12 (T008–T013, T016–T018, T021, T023, T025) |
| **Pester test tasks** | 9 (T028–T036) |
| **Documentation tasks** | 1 (T037) |
| **Approval gates** | 4 |
| **Parallelizable tasks** | 25 |

### Implementation Strategy
- **MVP**: Phases 1–7 (T001–T015) — config + shared foundations + standalone deployment for all 3 account types
- **Increment 2**: Phases 8–11 (T016–T020) — full deployment integration
- **Increment 3**: Phases 12–15 (T021–T027) — audit integration
- **Increment 4**: Phase 16 (T028–T037) — Pester tests + documentation (AFTER manual UAT)

