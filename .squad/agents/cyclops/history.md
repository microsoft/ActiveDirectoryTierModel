# cyclops — History

## Sessions

### 2026-07-13 (Windows LAPS Architecture Design)
- Produced full architecture design delivered via `.squad/decisions/inbox/cyclops-winlaps-architecture.md` (per Spec-Kit rules: no non-canonical files in specs/003-win-laps/)
- Established `WinLapsAcl` naming convention for new cmdlets (Get-TierModelWinLapsAcl, Get-TierModelWinLapsAclFd, New-TierModelWinLapsAcl)
- Designed five-gate fail-fast prereq sequence with schema as HARD STOP (tool never mutates schema)
- Confirmed Phase 10 ordering: independent of MSA/gMSA/dMSA, after Phase 9, pre-computed before summary display
- Authored Spec-Kit docs (spec.md, plan.md, tasks.md, checklists/requirements.md) — Professor X approved
- Polish: added T033 (Storm docs task) and "Files to Modify (Existing)" table to plan.md per Professor X review
- OQ-WL-01–06 all RESOLVED by Joel; switched to integrated design baseline (Get-TierModelConfig + Test-TierModelPrerequisites modifications). Config shape: 4 fields (ouDn, computerSelfPermission, readGroup, resetGroup). Schema-missing message approved (KDS-key pattern). "Auditing notice" removed.
- Restructured tasks.md to mirror 002-gmsa-support: implementation-first → deploy → 🛑 STOP gate → audit → Pester LAST. 10 phases, 21 tasks (T001–T021). Test-first ordering superseded per Joel's direction. Added Test-TierModelWinLapsAcl as deployment-verification cmdlet (Phase 4). Audit integration (Phase 9) now in scope after the gate.
- DC OU gating refined (OQ-RT-01): added optional `isDomainControllerOu` (bool, default false) per entry. Default DC hard-stop retained; explicit per-entry opt-in for Domain Controllers OU. 7 LAPS-linked OUs confirmed, 2 GPO template groupings.

### 2026-06-30 (v2.1.0 Release Prep)
- Added PSUseDeclaredVarsMoreThanAssignments to ScriptAnalyzer excludeRules in .github/workflows/ci.yml
- Reviewed and validated v2.1.0 release decision (minor bump for optional gMSA/dMSA/MSA ACL support)
- Confirmed cmdlet files remain untouched (user directive enforced throughout)
- Discovered: Get-TierModel*Acl cmdlets call Resolve-TierModelPlaceholder twice per delegation (line 114 + line 172)
- Validated test pattern compliance: -Scope It without -Exactly Count for per-delegation assertions
- Coordinated with Wolverine on mock scope fixes
- CI fully green, 1292/1292 tests passing

## Learnings
- 2026-07-13T18:21:02+08:00 — Module export mechanics: TierModel.psm1 auto-dot-sources all .ps1 files in `public/` and `internal/`; new cmdlets only need a .ps1 in public/ plus a FunctionsToExport entry in .psd1. No routing table or registration required.
- 2026-07-13T18:21:02+08:00 — Gating design for optional features: `Test-TierModelPrerequisites` already accepts `-IncludeMsa/-IncludeGmsa/-IncludeDmsa` switches; `-IncludeWinLaps` follows the same extension pattern. Gates 1–3 are sequential hard-stops; Gates 4–5 accumulate and report.
- 2026-07-13T18:21:02+08:00 — Windows-LAPS-only invariant: schema detection targets `msLAPS-*` attributeSchema objects ONLY; the tool never references `ms-Mcs-AdmPwd*` (Legacy LAPS). ADR-0001 is the governing decision.
- 2026-07-13T18:21:02+08:00 — Key risks for WinLaps: (1) DC/DSRM accidental scope is Critical — fail-closed default approved by Joel; (2) over-broad read delegation is Critical — per-Tier groups required; (3) collapsed read+reset+decrypt defeats SoD — config schema enforces separate arrays.
- 2026-07-13T18:37:30+08:00 — Spec-Kit house style (from 002-gmsa-support): spec.md has User Scenarios with Acceptance Scenarios + Requirements (FR-nnn) + Success Criteria (SC-nnn) + Assumptions + Risks; plan.md has Technical Context + Constitution Check + Prerequisites + Deployment Flow + New Files + Parameter Validation + Risk Register; tasks.md has phased tasks with [Requirement] tags and file/satisfies traceability; checklists/requirements.md gates completion.
- 2026-07-13T18:37:30+08:00 — Self-contained cmdlet design pattern: when point-7 "no existing cmdlet modifications" is in effect, new cmdlets embed their own config-loading and prereq checks rather than relying on shared Get-TierModelConfig/Test-TierModelPrerequisites; integration into those shared cmdlets becomes an optional additive enhancement pending owner approval.
- 2026-07-13T18:37:30+08:00 — WinLaps totals formula: each winLapsDelegations entry = 3 CreateAcl actions (Self + Read + Reset). N delegations = 3N added to TotalActions/CreateCount. Verification: capture stdout `Action count: N` / `Applied: N` and assert delta > 0.
- 2026-06-30T12:17:50+08:00 — Test shadow variables (existence-check vars for scope assertions) require ScriptAnalyzer rule exclusion; they are intentionally not dereferenced in the script body
- 2026-06-30T12:17:50+08:00 — Double invocation patterns require "at least N" assertions (-Scope It without -Exactly Count) rather than exact counts
- 2026-05-29T18:03:29.139+08:00 — The gMSA/dMSA feature plan is now locked to existing OU delegation patterns, self-contained cmdlets, optional ACL config segments loaded through `Get-TierModelConfig`, and read-only KDS validation via remoting to the preferred domain controller.
- 2026-07-13T11:34:25Z — Windows LAPS Wave-2 specification phase COMPLETE and APPROVED. All wave-1 research consolidated; 4-document spec-kit authored (spec.md, plan.md, tasks.md, checklists/requirements.md); Professor X review approved (9/9 constitution, 10/10 requirements). Orchestration log created: .squad/orchestration-log/2026-07-13T11-34-25-UTC-cyclops.md. 6 open questions routed to Joel (OQ-WL-01 through OQ-WL-06); 2 resolved (OQ-WL-05, OQ-WL-06 APPROVED for integration). Spec-Kit handed off ready for implementation waves.
- 2026-05-29T10:10:00Z — Architectural decisions documented in Scribe merge. Plan review complete with 11 decisions captured.
- 2026-07-14T11:05:00+08:00 — Windows LAPS code review (T001–T012): APPROVED with 1 blocking fix (unauthorized deletion of optional/Enable-TierModelAuditing.ps1). All 10 review criteria assessed. Implementation faithfully translates reference script into idempotent config-driven deployment. Key structural finding: Find-LapsADExtendedRights cannot distinguish Read vs Reset holders — acceptable given readGroup==resetGroup in all current entries but documented as known gap for future divergent configs.
- 2026-07-14T11:05:00+08:00 — Pattern confirmation: WinLaps cmdlets correctly follow gMSA baseline (no function-level StrictMode, SupportsShouldProcess on executor, CorrelationId structured logging, comment-based help). Phase 10 ordering after Phase 9 validated. EUD multi-principal correctly passes array in single Set-LapsAD*Permission call.

