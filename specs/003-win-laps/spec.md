# Feature Specification: Windows LAPS Deployment (`-IncludeWinLaps`)

**Feature Branch**: `feature/windows-laps`  
**Created**: 2026-07-13  
**Status**: Draft  
**Input**: User description: "Add `-IncludeWinLaps` option plus new standalone and FullDeployment cmdlets to deploy Windows LAPS (modern in-box, ms-LAPS-* only) DACL delegation into the Tier Model OU structure. Deployment first; auditing deferred to a future wave."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Deploy Windows LAPS DACL Delegation (Priority: P1)
Administrator runs `Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -IncludeWinLaps -ConfirmApply` to deploy Windows LAPS OU-level DACL delegation across the tiered computer OUs. This configures: (a) computer SELF-store permission so machines can update their LAPS password, (b) read-password permission for designated retrieval groups, and (c) reset-password-expiration permission for designated reset groups. Without `-ConfirmApply`, the script performs a plan-only dry run showing what changes would be made.

**Clarifications Applied**:
- **OU Placement**: Existing `Tier X Computers` (or equivalent) OUs are targeted. No new OUs created by this feature.
- **Delegation Groups**: Separate read-password and reset-password groups per tier, configured in JSON. No new groups created by this feature — groups must pre-exist.
- **Schema Requirement**: Windows LAPS schema (`ms-LAPS-*` attributes) must already be extended in the forest. The tool never mutates schema.
- **Scope**: Delegation is applied to all OUs listed in `config/tiermodel-winlaps.json`; each entry specifies a tier and target OU.

**Why this priority**: Windows LAPS DACL delegation is the foundational capability. Without it, computers cannot store passwords and operators cannot retrieve/reset them within the tiered model.

**Independent Test**: With prerequisite mocks (passing), executing with `-IncludeWinLaps` without `-ConfirmApply` produces a plan listing 3 × N DACL actions (Self + Read + Reset per configured OU); executing with `-ConfirmApply` yields reported success and a converged follow-up plan (0 remaining actions).

**Acceptance Scenarios**:
1. **Given** a deployed Tier Model with Windows LAPS schema extended, **When** running with `-IncludeWinLaps` without `-ConfirmApply`, **Then** a plan lists Self-permission, read-password, and reset-password DACL actions for all configured tier OUs.
2. **Given** the same invocation with `-ConfirmApply`, **When** executed, **Then** DACL delegations are applied via Microsoft `Set-LapsAD*Permission` cmdlets. A second dry run reports 0 actions and Converged = True.
3. **Given** an existing Tier Model deployment, **When** running with `-FullDeployment -IncludeWinLaps -ConfirmApply`, **Then** Windows LAPS DACL delegation executes as Phase 10 after all standard and optional MSA/gMSA/dMSA phases.
4. **Given** Windows LAPS schema NOT extended, **When** running with `-IncludeWinLaps`, **Then** the tool halts with `WINLAPS_SCHEMA_MISSING` and makes zero changes.

---

### User Story 2 — Standalone Windows LAPS Deployment (Priority: P1)
Administrator runs `Deploy-TierModel.ps1 -PreferredDc DC01 -IncludeWinLaps -ConfirmApply` (standalone, without `-FullDeployment`) to apply ONLY Windows LAPS DACL delegation, assuming OUs and groups already exist from a prior full deployment.

**Why this priority**: Enables targeted LAPS delegation without re-running the entire tier model deployment.

**Independent Test**: If OUs or groups are missing, the tool fails fast with a clear error listing what is absent.

**Acceptance Scenarios**:
1. **Given** OUs and groups exist, schema extended, **When** running `-IncludeWinLaps` standalone, **Then** plan lists only WinLaps DACL actions (no OU/group/GPO actions).
2. **Given** required OUs do NOT exist, **When** running `-IncludeWinLaps` standalone, **Then** fail with error identifying missing OUs. Zero changes applied.
3. **Given** required groups do NOT exist, **When** running `-IncludeWinLaps` standalone, **Then** fail with error identifying missing groups. Zero changes applied.

---

### User Story 3 — Combined Deployment with MSA/gMSA/dMSA (Priority: P2)
Administrator runs `-FullDeployment -IncludeWinLaps -IncludeGmsa -IncludeDmsa -ConfirmApply` and all optional features deploy in order (MSA→gMSA→dMSA→WinLaps) without conflict.

**Why this priority**: Validates composition/ordering guarantee.

**Acceptance Scenarios**:
1. **Given** all prerequisites met, **When** all four `-Include*` switches combined, **Then** deployment succeeds with TotalActions = sum of all phases; WinLaps executes after dMSA.
2. **Given** standard phases 1–6 fail, **When** optional phases gate is reached, **Then** WinLaps is skipped (same gate as MSA/gMSA/dMSA).

---

### Edge Cases
- Windows LAPS schema NOT extended → HARD STOP (`WINLAPS_SCHEMA_MISSING`). Non-prescriptive message pointing to Microsoft documentation. No step-by-step, no cmdlet names exposed.
- Target OU contains Domain Controller objects AND entry does NOT have `isDomainControllerOu: true` → `WINLAPS_DC_SCOPE_REJECTED`. Fail-closed by default; DC targeting requires explicit per-entry opt-in.
- Target OU contains Domain Controller objects AND entry has `isDomainControllerOu: true` → allowed (explicit opt-in; Domain Controllers OU is a known LAPS target).
- DFL < 2016 → `WINLAPS_DFL_INSUFFICIENT`. Encryption cannot be enabled.
- LAPS PowerShell module not present on management host → `WINLAPS_MODULE_MISSING`.
- Legacy LAPS (`ms-Mcs-AdmPwd*`) attributes exist on target OU → informational log only. Never modified, never assumed.
- `-IncludeWinLaps` combined with `-OuOnly`/`-GroupOnly`/etc. → parameter validation error.
- Second immediate run → Applied = 0, Converged = True (idempotency).
- Feature completeness: this wave delivers DEPLOYMENT only; auditing is the next wave (deployment + auditing together = complete feature).

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: System MUST support `-IncludeWinLaps` as a switch parameter on `Deploy-TierModel.ps1`.
- **FR-002**: When `-IncludeWinLaps` is specified, the system MUST apply Windows LAPS DACL delegation for each entry in `config/tiermodel-winlaps.json`, consisting of three operations per OU: (a) `Set-LapsADComputerSelfPermission`, (b) `Set-LapsADReadPasswordPermission`, (c) `Set-LapsADResetPasswordPermission`.
- **FR-003**: System MUST validate ALL prerequisites UP FRONT before ANY AD change: (1) Windows LAPS schema present, (2) LAPS module + cmdlets, (3) DFL ≥ 2016, (4) target OUs exist and contain no DC objects unless the entry has `isDomainControllerOu: true`, (5) required groups exist.
- **FR-004**: System MUST halt with stable error code `WINLAPS_SCHEMA_MISSING` if Windows LAPS schema is not extended. Message must be non-prescriptive: reference Microsoft documentation only, no step-by-step, no cmdlet name, no auto-schema-update path.
- **FR-005**: System MUST ensure idempotency — second immediate run yields zero changes and Converged = True.
- **FR-006**: System MUST support `-WhatIf` / planning mode (no `-ConfirmApply`) with zero AD writes.
- **FR-007**: System MUST default-exclude OUs containing Domain Controller objects (fail-closed, `WINLAPS_DC_SCOPE_REJECTED`). Detection by object attributes (primaryGroupID=516 or SERVER_TRUST_ACCOUNT bit), not OU name. When a delegation entry has `isDomainControllerOu: true`, the DC-object check is intentionally bypassed for that entry only — this is an explicit per-entry opt-in for targeting the Domain Controllers OU.
- **FR-008**: System MUST produce 3 × N `CreateAcl` actions (N = number of configured tier delegations), ensuring deployment totals strictly increase when `-IncludeWinLaps` is added.
- **FR-009**: System MUST log all operations with `Write-TierModelLog` including CorrelationId, Level, Message, and Data. Passwords NEVER logged.
- **FR-010**: System MUST only reference Windows LAPS (`ms-LAPS-*` attributes, `LAPS` module cmdlets). Legacy Microsoft LAPS (`ms-Mcs-AdmPwd*`, `AdmPwd.PS` module) MUST NEVER be deployed, assumed, or referenced (ADR-0001 invariant).
- **FR-011**: System MUST NOT allow `-IncludeWinLaps` combined with `-OuOnly`, `-GroupOnly`, `-UserOnly`, `-GposOnly`, `-OuAclsOnly`, or `-AdmxOnly`. Valid only standalone or with `-FullDeployment`.
- **FR-012**: System MUST compose as Phase 10 in FullDeployment, executing AFTER Phase 9 (dMSA) and gated by `$standardDeployHadErrors`.
- **FR-013**: System MUST use the following schema per delegation entry in `config/tiermodel-winlaps.json`: `ouDn` (OU distinguished name), `computerSelfPermission` (boolean), `readGroup` (principal allowed to read/retrieve), `resetGroup` (principal allowed to force reset/expire), and optional `isDomainControllerOu` (boolean, default `false`). Fields `readGroup` and `resetGroup` are separate (secure-by-design: reset/expire is a distinct right from read/decrypt); operators MAY set them to the same value. When `isDomainControllerOu` is `true`, the DC-object hard-stop is bypassed for that entry (explicit opt-in for Domain Controllers OU).
- **FR-014**: System MUST integrate with existing module infrastructure: config loaded via `Get-TierModelConfig.ps1` (optional segment pattern), prerequisite checks via `Test-TierModelPrerequisites.ps1` (conditional on `-IncludeWinLaps` — must NOT run or affect deployments that do not use `-IncludeWinLaps`).
- **FR-015**: Multiple `-Include*` switches MAY be combined in a single invocation (e.g., `-IncludeWinLaps -IncludeGmsa`).

### Key Entities
- **WinLapsDelegation**: Configuration entry with fields: `ouDn` (target OU distinguished name), `computerSelfPermission` (boolean), `readGroup` (read/retrieve principal), `resetGroup` (reset/expire principal), and optional `isDomainControllerOu` (boolean, default `false` — explicit opt-in for DC OU targeting).
- **Windows LAPS Schema Attributes**: `msLAPS-PasswordExpirationTime`, `msLAPS-Password`, `msLAPS-EncryptedPassword`, `msLAPS-EncryptedPasswordHistory`, `msLAPS-EncryptedDSRMPassword`, `msLAPS-EncryptedDSRMPasswordHistory`.
- **Microsoft LAPS Permission Cmdlets**: `Set-LapsADComputerSelfPermission`, `Set-LapsADReadPasswordPermission`, `Set-LapsADResetPasswordPermission`.

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-001**: Deployment with `-IncludeWinLaps` applies all configured DACL delegations; second run shows 0 planned actions and Converged = True.
- **SC-002**: Deployment totals (Action count / Applied) strictly increase when `-IncludeWinLaps` is added vs baseline (3 × number of configured delegations).
- **SC-003**: Windows LAPS deployment completes independently via standalone `-IncludeWinLaps` without affecting other Tier Model resources.
- **SC-004**: Pre-flight validation catches 100% of: missing schema, missing OUs, missing groups, DC-scope violations, missing LAPS module.
- **SC-005**: No `ms-Mcs-AdmPwd*` (legacy LAPS) reference appears in any plan action, config key, or cmdlet invocation.
- **SC-006**: All three new cmdlets covered by Pester tests (unit + idempotency + integration).
- **SC-007**: Phase 10 executes AFTER phases 7–9 (MSA/gMSA/dMSA) and is skipped if standard phases had errors.

### Non-Functional (Implicit)
- Operations follow existing logging standards (structured, CorrelationId, Write-TierModelLog, redaction).
- Performance: Adding WinLaps support does not increase plan generation time by more than 10% for existing configurations without WinLaps definitions.

## Assumptions
- The existing Tier Model OU structure is deployed (spec 001) — specifically, computer OUs per tier exist.
- Required read-password and reset-password AD groups exist (created by operator or prior `-GroupOnly` run).
- Windows LAPS schema has been extended in the forest by the domain's Schema Admin via their controlled change process.
- The feature deploys DACL delegation only — it does not create actual LAPS policies, configure GPO/CSP settings, or provision passwords.
- Auditing (`Set-LapsADAuditing`) is explicitly OUT OF SCOPE for this wave.
- Domain Functional Level ≥ 2016 (encryption mandatory per Joel decision OQ-RT-03).
- Concrete OU paths, group names, and tier assignments are supplied by Joel after architecture approval.

## Open Questions

| ID | Question | Owner | Status |
|---|---|---|---|
| OQ-WL-01 | Config shape: 4 fields per entry (`ouDn`, `computerSelfPermission`, `readGroup`, `resetGroup`) | Joel | ✅ RESOLVED — 4-field schema adopted |
| OQ-WL-02 | Read/reset separation model | Joel | ✅ RESOLVED — separate fields; operators MAY equalize; no decrypt-principal group needed |
| OQ-WL-03 | Exact wording for `WINLAPS_SCHEMA_MISSING` message | Joel | ✅ RESOLVED — approved wording (pending final sign-off on exact text) |
| OQ-WL-04 | "Auditing not yet configured" runtime notice | Joel | ✅ RESOLVED — removed; completeness tracked by STOP gate + Future Wave boundary |
| OQ-WL-05 | Permission to modify `Test-TierModelPrerequisites.ps1` | Joel | ✅ APPROVED — conditional on `-IncludeWinLaps`; must not affect non-WinLaps deployments |
| OQ-WL-06 | Permission to modify `Get-TierModelConfig.ps1` | Joel | ✅ APPROVED — optional segment pattern (parallel to msa/gmsa/dmsa) |

### Remaining Inputs (pending Joel)

| ID | Input Needed | Status |
|---|---|---|
| INPUT-01 | Concrete OU paths and group names for `config/tiermodel-winlaps.json` values | NEEDS INPUT |
| INPUT-02 | Final sign-off on exact WINLAPS_SCHEMA_MISSING message wording | NEEDS INPUT |

## Test Strategy (Supplemental)
- 19-test Pester suite (15 unit, 4 integration) authored BEFORE implementation per Constitution II.
- Unit tests cover: schema hard-stop, OU/group gating, ms-Mcs-AdmPwd* exclusion, idempotency (plan + apply), WhatIf no-writes, parameter guards, standalone scope, FD integration, call ordering, error gating.
- Integration tests cover: totals increase (plan + apply), idempotency convergence, all-four-Include-phases ordering.
- Lab validation: restore `WinLapsSchema` checkpoint → deploy → assert totals increased → capture before/after DACLs.
- Use mocks for AD cmdlets where live domain not available.

## Risks & Mitigations
- Risk: Over-broad read delegation exposes passwords across OU subtrees → Mitigation: per-Tier groups, narrowest OU scoping.
- Risk: Accidental DC/DSRM scope creates Tier 0 credential-custody path → Mitigation: hard-stop by default (`WINLAPS_DC_SCOPE_REJECTED`); DC targeting requires explicit per-entry `isDomainControllerOu: true` opt-in in config — deliberate and visible.
- Risk: Collapsed read+reset defeats separation of duties → Mitigation: `readGroup` and `resetGroup` kept as separate schema fields (secure-by-design); equalizing is an explicit operator choice, not a default.
- Risk: Exact ACEs from `Set-LapsAD*Permission` are unpublished → Mitigation: lab-captured before/after DACL fixtures required before manual ACL/idempotency code.
- Risk: Partial schema extension passes naive check → Mitigation: hardened schema check (mayContain on computer class, not just attribute names).

## Dependencies
- Spec 001 (Tier Model AD Deployment & Audit Module) must be implemented as the base.
- Spec 002 (gMSA/dMSA/MSA ACL support) should be merged for FullDeployment integration patterns, but is not a hard prerequisite.
- Windows LAPS schema extension must be performed by forest Schema Admin before deployment.
- `LAPS` PowerShell module must be available on the management host.

## Invariant: Windows LAPS Only (ADR-0001)

This feature targets **Windows LAPS** exclusively — the modern in-box Windows Local Administrator Password Solution. Legacy Microsoft LAPS (`ms-Mcs-AdmPwd*`, `AdmPwd.PS` module) is architecturally excluded at every layer:
1. **Schema detection** — only queries `msLAPS-*` attributes.
2. **Cmdlet invocation** — only calls `Set-LapsAD*Permission` from the `LAPS` module.
3. **Configuration** — only `winLaps*` / `ms-LAPS-*` keys in JSON.

Legacy LAPS state in the environment is treated as "foreign" — logged informational, never modified, never relied upon.
