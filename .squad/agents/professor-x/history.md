# professor-x — History

## FEATURE COMPLETE: Windows LAPS T001–T021 (2026-07-16)

**Status:** ✅ SHIPPED — All tasks complete, committed, ready for Joel's UAT + release.

The Windows LAPS feature (T001–T021) is now complete and committed to feature/windows-laps branch:
- Beast (T001–T013): Implementation + audit cmdlet ✅
- Wolverine (T014–T020): Test suite (113 tests, 90.92% coverage, 1401/1401 green) ✅
- Storm (T021): Documentation (8 files, README metrics) ✅

Spec review (Professor-X T008): APPROVED — feature spec meets all Constitution requirements and security invariants.

Orchestration logs: 2026-07-16T09-34-10Z-wolverine.md and 2026-07-16T09-34-10Z-storm.md  
Session log: 2026-07-16T09-34-10Z-winlaps-feature-complete.md

Next gate: Joel's manual UAT, then PR merge, v1.2.0 release.

---

## 2026-08-24: Spec 005 Updated — All-Tier Four-Silo Model

**Update**: Applied Joel's approved all-tier model to `specs/005-auth-silos/`.

### Changes Made

**spec.md**: Header updated with revision date. Overview updated to all four tiers. Four new sections added:
- **The Four-Silo Model** — scope table with Tier 0 Admin / Tier 1 Admin / Tier 2 Admin / Tier 2 EUD silos, approved-origin-device column, no-fifth-silo constraint, privileged-accounts-only scope
- **Silo Enforcement Boundary** — explicit distinction: silos gate TGT source-device (AS exchange) only; URA logon rights (existing GPOs) and TGS service-ticket control are independent planes; do not conflate
- **Domain-Join Service Account Exemptions** — svc-pawdomainjoin + svc-t1srvdomainjoin (existing) + svc-t2euddomainjoin (new/required); structural exemptions with compensating controls
- **Required New Config Addition — Tier 2 EUD Provisioning** — svc-t2euddomainjoin + Tier2EUDDomainJoin group + Tier 2 EUD Staging OU + delegated create-computer rights + Account Restriction GPO

User Story 1 updated to all four silos, domain-join exemption clarification added (scenario 7). New section **Test Acceptance Matrix (UAT-01–UAT-15)** added. Edge Cases expanded (+2: domain-join exemption, Tier 2 EUD prereq). Constraints extended to CON-009 (no fifth silo; privileged-only) and CON-010 (domain-join structural exemptions). Out of Scope: "Tier 2 silo deployment" removed; "General Domain Users/Computers siloing" added as out of scope by design. Open Questions: OQ-005 marked RESOLVED; OQ-003 partially resolved; OQ-011/OQ-012 added.

**plan.md**: AD Object Model shows all four silos + structural exemptions table. New Files section expanded with Tier 2 EUD config additions table. Risk Register extended to R10.

**tasks.md**: T009 added for Tier 2 EUD base-config additions. Lab validation tasks expanded: T021 (negative/cross-tier), T022 (new-device onboarding), T023 (domain-join exempt accounts), T024 (gate check + RID-500 recovery), T025 (G1–G12 full gate checklist). Review/release tasks renumbered T026–T028.

**checklists/requirements.md**: All sections updated to reflect four-silo model; OQ-005 checked as RESOLVED; CON-009/010 added to Security & Safety; UAT matrix referenced in Tasks.md Completeness.

### Decisions Made in This Update

1. **Four-silo model is final**: Tier 0 Admin / Tier 1 Admin / Tier 2 Admin / Tier 2 EUD. No fifth silo. (CON-009)
2. **Privileged-accounts-only**: General Domain Users/Computers intentionally not siloed. (CON-009)
3. **Silo enforcement boundary clarified**: TGT source-device (AS exchange) only; URA and TGS are separate, independent control planes.
4. **Domain-join exemptions are structural**: svc-pawdomainjoin, svc-t1srvdomainjoin, svc-t2euddomainjoin are permanently exempt (not time-bounded). (CON-010)
5. **Tier 2 EUD provisioning is a required config addition**: svc-t2euddomainjoin + Tier2EUDDomainJoin + Tier 2 EUD Staging OU must be added to base Tier Model config before Tier 2 EUD silo can deploy.

---

## 2026-08-24: Spec 005 Authored — Authentication Policy Silos (`-IncludeAuthSilos`)

**Deliverables**: `specs/005-auth-silos/spec.md`, `plan.md`, `tasks.md`, `checklists/requirements.md`
**Status**: Draft (scoping) — ops-guide walkthrough with Joel is next step (T001)

### Scoping Decisions Made

1. **Full silo model required (CON-001)**: Real `msDS-AuthNPolicySilo` objects + per-class `msDS-AuthNPolicies` policies. Direct policy assignment without silo objects is not the target model. Customer scripts are frozen evidence only.
2. **OR logic required in AllowedToAuthenticateFrom SDDL (CON-002)**: `&&` (AND) between device groups is prohibited. The customer scripts' AND logic is the documented lockout failure mode.
3. **Audit-first as three-stage lifecycle (CON-003/004)**: All objects created with `Enforce = false`. Enforcement flip is a separate, manually-invoked operation — never triggered by `-IncludeAuthSilos`.
4. **RID-500 structural exclusion (CON-005)**: Non-configurable; by SID suffix match (`-500$`), not by `sAMAccountName`.
5. **FAST/DAC GPO validation only (CON-008)**: Pre-existing in Tier Model. Code validates; does not create or modify GPOs.
6. **Switch naming**: `-IncludeAuthSilos` — consistent with `-IncludeWinLaps`, `-IncludeGmsa` optional-feature pattern.
7. **Tier scope**: Tier 0 + Tier 1 in scope; Tier 2 is explicit out-of-scope for initial implementation.

### Deferred / Open

OQ-001 through OQ-010 (converge recipe, enforcement flip UX, exemption model, gMSA scope, Tier 2, gate verification, config shape, SDDL generation, lab validation requirements, wave structure) — all deferred to ops-guide walkthrough session (T001).

### Learnings

- The audit→enforce lifecycle is first-class, not a flag. Spec 005 establishes it as three distinct stages with twelve pre-enforcement gates. Future specs that involve Tier boundary controls should reference this structure.
- The customer script review (A4: 4 Critical, 19 Major) is a direct design input. The two most important defects to prohibit in code are: (1) no silo objects created, (2) AND logic in SDDL between device groups. Both are now structural constraints in CON-001 and CON-002.
- Pre-enforcement gates (G1–G12) are a reusable checklist pattern for any AD control that deploys in audit-then-enforce lifecycle. Consider referencing this pattern in future control-plane features.

---

## 2026-07-13: Spec Review — 003-win-laps

**Verdict:** APPROVED (with 2 minor non-blocking items)

Reviewed `specs/003-win-laps/` (spec.md, plan.md, tasks.md, checklists/requirements.md) against:
- Constitution v1.3.0 (all 9 principles)
- 002-gmsa-support baseline (structure parity)
- Source findings (Beast, Cyclops, Wolverine inbox documents)
- Joel's 10 explicit requirements

## Learnings

- 003 correctly implements Constitution II (test-first) unlike 002 which deviated. This is the RIGHT approach going forward — test-first is non-negotiable per constitution.
- Self-contained design pattern (baseline works without modifying existing cmdlets, with OQ-flagged optional integration) is a strong architecture choice for new features. Reduces blast radius and gives Joel explicit control over scope creep.
- The 002→003 size ratio (~60%) is proportional to cmdlet count (3 vs 12) — do NOT flag feature specs as "too thin" when scope is genuinely narrower.
- Documentation tasks (README/docs updates) should be explicitly tasked in every spec's tasks.md. 002 had T037; 003 missed this. Flag in future reviews.
- "Files to Modify (Existing)" summary table is valuable for Joel's review — recommend it as standard structure for all plan.md files.
- ADR-0001 (Windows LAPS only invariant) with 3-layer enforcement is a strong security architecture pattern worth replicating for future exclusion invariants.

## 2026-07-13: Wave-2 Orchestration Complete

**Orchestration session log created**: `.squad/orchestration-log/2026-07-13T11-34-25-UTC-professor-x.md`

Review final verdict: APPROVED. All agent findings consolidated into decisions.md. Spec-Kit ready for implementation wave handoff. 6 open decisions routed to Joel; 2 already resolved (OQ-WL-05, OQ-WL-06). Team transition from Wave-2 specification to implementation waves now underway.

Recommendation: This level of structured wave coordination (research → architecture → specification → approval → implementation) should be documented as a process pattern for future multi-agent features. Cyclops + Professor X review cycle is effective.

