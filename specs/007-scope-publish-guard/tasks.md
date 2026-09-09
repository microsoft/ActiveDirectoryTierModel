# Tasks: Scope Publish Guard — **DEFERRED / NOT STARTED (v2.2.0)**

**Spec**: `specs/007-scope-publish-guard/spec.md`
**Plan**: `specs/007-scope-publish-guard/plan.md` *(stub — deliberately not written)*
**Generated**: 2026-09-05
**Status**: **DEFERRED TO v2.2.0 by Joel, 2026-09-05. No task below has been started.**

---

## ⛔ Nothing here is in v2.1.0

All six known defect instances affecting scope publishing
**are individually fixed**, so no v2.1.0 user is exposed. This guard is regression insurance against a future
seventh instance — its value is entirely prospective, which is why deferring costs a v2.1.0 user nothing.

---

## Phase 0: Decisions Required Before Any Work

- [ ] T001 Resolve **OQ-002** — on cross-check failure, `throw` or log loudly plus a console banner?
      A throwing guard can kill a healthy run (spec §5); a logging guard weakens the guarantee. Joel chooses.
  - **Files**: record the resolution under OQ-002 in the "Open Questions for Joel" section of `specs/007-scope-publish-guard/spec.md`
  - **Satisfies**: spec §5, OQ-002

- [ ] T002 Resolve **OQ-003** — bring branch 5 (`-OuAclOnly`) into the normaliser with an extended `Type`
      derivation, or keep a `-PreNormalised` escape hatch? Every escape hatch is a place instance seven can
      hide. This piece can ship independently of the guard.
  - **Files**: record the resolution under OQ-003 in the "Open Questions for Joel" section of `specs/007-scope-publish-guard/spec.md`
  - **Satisfies**: spec §4, OQ-003

---

## Phase 1: Prerequisites Outside This Feature

- [ ] T003 The drifted fixture runs against a real DC, producing known-real producer shapes for every one of
      the eleven publishing branches. The guard must not be built against assumed shapes — shipping an
      unexercised non-vacuity mechanism is the exact mistake the guard exists to prevent.
  - **Satisfies**: spec §6 deferral argument 4

- [ ] T004 The canonical-ACL phase is observed **succeeding** against a healthy DC. It has never been
      observed doing so; until it has, its published shape is unknown and a throwing guard against it is a
      live risk on a good domain.
  - **Satisfies**: spec §5 hazard

---

## ⛔ STOP GATE — v2.2.0 scoping session with Joel

Do not begin Phase 2 without T001–T004 and an explicit v2.2.0 go.

---

## Phase 2: Implementation (Not Scoped)

- [ ] T005 Write `plan.md` properly, replacing the stub — helper contract, call-site sequencing, test plan.
  - **Files**: `specs/007-scope-publish-guard/plan.md`

- [ ] T006 Implement `Publish-TierModelScopeResult`: assignment, normalisation via
      `ConvertTo-TierModelDriftFinding`, publication recording, the arithmetic cross-check, the
      double-publish detector, and the `-NoFindings -Reason` declaration for branches with nothing to say.
  - **Satisfies**: spec §3.1, §3.2, §3.3

- [ ] T007 Route all eleven publishing branches through the helper, including the seven currently correct.
  - **Satisfies**: spec §4

- [ ] T008 Tests: each cross-check rule fires on its own defect pattern; none fires on a clean domain; the
      double-publish detector catches the re-initialization pattern; a legitimate `-NoFindings` branch passes.
  - **Files**: `tests/`

---

## Task Count

| State | Count |
|-------|-------|
| ⬜ Not started (deferred to v2.2.0) | 8 |
| **Total** | **8** |
