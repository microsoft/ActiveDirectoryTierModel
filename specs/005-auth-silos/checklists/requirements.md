# Specification Quality Checklist: Authentication Policy Silos (`-IncludeAuthSilos`)

**Purpose**: Validate scoping specification completeness before proceeding to the design phase
**Created**: 2026-08-24
**Feature**: [specs/005-auth-silos/spec.md](../spec.md)
**Status**: Draft (scoping) — open items in "Deferred to Design Phase" section are expected at this stage

---

## Scoping Coverage

- [x] Feature overview and framing written — explains all four tiers, the lifecycle, and the integration target
- [x] The four-silo model stated with the scope table (Tier 0 Admin / Tier 1 Admin / Tier 2 Admin / Tier 2 EUD)
- [x] Privileged-accounts-only scope stated — general Domain Users/Computers intentionally not siloed
- [x] Silo enforcement boundary documented — TGT source-device restriction is distinct from URA logon rights and from TGS service-ticket control
- [x] The correct AD object model stated explicitly — `msDS-AuthNPolicySilo` + `msDS-AuthNPolicies` per class; not direct policy assignment only
- [x] The wrong model named and prohibited — customer scripts' direct-policy-without-silos pattern documented as a defect (CON-001)
- [x] SDDL boolean logic trap documented — OR vs. AND; AND logic prohibited (CON-002)
- [x] Audit-first lifecycle described as three distinct stages, not a toggle flag
- [x] Enforcement flip separated from deployment — non-negotiable structural separation (CON-003/CON-004)
- [x] Domain-join service account exemptions documented with compensating controls (CON-010)
- [x] Tier 2 EUD config addition requirements documented (new section)
- [x] Status marked as Draft (scoping)

---

## User Scenarios

- [x] US-1 (deploy audit mode) written with acceptance scenarios (6 scenarios)
- [x] US-2 (audit silo state) written with acceptance scenarios (5 scenarios)
- [x] US-3 (enforcement flip — future/gated) written with pre-enforcement gate table (G1–G12) and design-intent shape
- [x] US-3 explicitly marked as deferred with OQ references

---

## Requirement Completeness

- [x] High-level FRs numbered — FR-001 through FR-015
- [x] FR status documented as scoping-level (design-phase detailed FRs deferred)
- [x] Key Entities table defined — all primary AD objects, structural concepts, and lifecycle states
- [x] Edge cases documented (12 cases including domain-join exemptions and Tier 2 EUD prerequisite)
- [x] Prerequisites documented with current state and validation approach
- [x] Constraints numbered — CON-001 through CON-010 with consequences
- [x] Out-of-scope items listed (general population explicitly excluded; Tier 2 now in scope)
- [x] Open Questions numbered — OQ-001 through OQ-012 with status (OQ-005 RESOLVED; OQ-003 partially resolved)
- [x] Dependencies listed (including Tier 2 EUD config additions)
- [x] Assumptions listed
- [x] Version section present (TBD pending OQ-010)

---

## Architecture & Constitution Alignment

- [x] Constitution compliance map completed in plan.md (all 9 principles addressed)
- [x] Modular decomposition: Get / Get-Fd / New / Test cmdlet pattern
- [x] Four-silo model documented in plan.md AD Object Model section with silo scope table
- [x] Structural exemptions table in plan.md (domain-join accounts + RID-500)
- [x] Idempotency contract stated — no write when converged; zero-write proof required
- [x] Delta-only contract stated — FR-008; E1 §2 structural constraints referenced
- [x] Full deployment phase order placement specified (after existing optional phases)
- [x] Integration shape documented for both `Deploy-TierModel.ps1` and `Audit-TierModel.ps1`
- [x] Architecture decisions pending table in plan.md (D-001 through D-007)
- [x] Tier 2 EUD config additions in plan.md New Files section
- [x] Enforcement flip structural requirements described at planning level

---

## Security & Safety

- [x] SDDL AND-logic lockout trap documented and prohibited (CON-002, Edge Cases, R1)
- [x] Empty device group halt documented (FR-006, Edge Cases, R2)
- [x] RID-500 structural exclusion documented — by SID suffix, not samAccountName (FR-009, CON-005, R5)
- [x] Domain-join account structural exemptions documented with compensating controls (CON-010, Edge Cases)
- [x] Audit mode labeled non-protective (FR-012, Audit-First Lifecycle, R8)
- [x] Enforcement flip structurally separated as non-deployable (CON-003/004, R4)
- [x] Delta-only requirement stated (CON-006, FR-008, R3)
- [x] Automation anti-pattern documented (CON-006 — no distributed GPO-delivered scheduled task)
- [x] FAST/DAC prerequisite validation requirement documented (FR-006, Prerequisites, R6)
- [x] Pre-enforcement gates G1–G12 enumerated in US-3 with enforcement stop classification
- [x] Security invariants referenced: SI-01 through SI-12 from research (B §5)
- [x] Privileged-accounts-only scope stated (CON-009); general user/computer siloing prohibited

---

## Hygiene

- [x] No persona names — no codenamed personas or research-author names from the source material
- [x] No agent names, squad references, or squad vocabulary
- [x] No research content copied verbatim — all synthesized from research pack
- [x] Source-material scripts noted as frozen evidence only; not a reference implementation (CON-007)
- [x] All research-internal identifiers (AS-C-nn, A4-Wnn, etc.) are NOT exposed in the spec — content is synthesized without referencing internal IDs

---

## Plan.md Completeness

- [x] Technical context section complete
- [x] AD object model documented — four silos with scope table
- [x] Structural exemptions table in plan.md
- [x] Integration shape documented (parameter wiring, flows)
- [x] Deployment lifecycle table
- [x] Constitution check table (all 9 principles)
- [x] New files to create listed with responsibilities
- [x] Tier 2 EUD config additions in New Files section
- [x] Existing files to modify listed with authorization
- [x] Architecture decisions pending table
- [x] Pre-enforcement safety design section
- [x] Risk register (10 risks including Tier 2 EUD prereq)

---

## Tasks.md Completeness

- [x] Phase gating notes explicit
- [x] Phase 1 (ops-guide walkthrough) tasks defined with inputs/outputs
- [x] Stop gates between phases explicit
- [x] Phase 2 (design) tasks defined with FR traceability
- [x] Phase 3 (implementation — deferred) tasks defined with T009 for Tier 2 EUD config additions
- [x] Phase 4 (integration tests and lab validation) tasks defined, including negative (UAT-05–07), onboarding (UAT-08–09), domain-join exemption (UAT-10–11/13), and recovery (UAT-14) scenarios
- [x] Phase 5 (review and release) tasks defined

---

## Deferred to Design Phase (Expected at Scoping Status)

The following items are intentionally open at this scoping stage. Items marked RESOLVED were settled by Joel's approval of the four-silo model.

- [x] ~~OQ-005: Tier 2 handling~~ — **RESOLVED**: Tier 2 Admin silo + Tier 2 EUD silo both in scope (four-silo model)
- [x] ~~OQ-003 (partial)~~ — **PARTIALLY RESOLVED**: three structural domain-join exemptions documented (CON-010); broader exemption governance model deferred
- [ ] OQ-001: Delta reconciliation converge recipe — deferred
- [ ] OQ-002: Enforcement flip UX — deferred
- [ ] OQ-003 (remainder): Time-bounded exemption governance model — deferred
- [ ] OQ-004: gMSA silo scope in wave 1 — awaiting Joel decision
- [ ] OQ-006: Pre-enforcement gate verification mechanism — deferred
- [ ] OQ-007: Configuration schema shape and placeholder conventions — awaiting Joel decision
- [ ] OQ-008: SDDL generation strategy — deferred
- [ ] OQ-009: Lab validation pass/fail criteria — deferred (UAT-01–15 scenarios named; criteria in ops guide)
- [ ] OQ-010: Wave structure (deployment-only vs. deployment + audit together) — awaiting Joel decision
- [ ] OQ-011: Mixed Policy/Silo Enforce precedence — deferred; requires lab validation
- [ ] OQ-012: gMSA-in-silo behavior — deferred; requires lab validation
- [ ] Detailed FRs (AC-* acceptance criteria table) — deferred to design phase
- [ ] Cmdlet contracts (parameter shapes, return object shapes) — deferred to design phase
- [ ] Version bump target — pending OQ-010
