# Feature Specification: Scope Publish Guard for `Audit-TierModel.ps1`

**Feature Branch**: *(none — not scheduled)*
**Created**: 2026-09-05
**Status**: DESIGN ONLY — **DEFERRED TO v2.2.0 by Joel, 2026-09-05**
**Original author**: Rogue (Core Developer)
**Input**: Relocated from `docs/design-scope-publish-guard.md` (deleted — `docs/` publishes to GitHub Pages
and design scope belongs under `specs/`). Content preserved and reformatted to house spec style; no
argument was softened or dropped in the move.

---

## Deferral Ruling and Its Rationale

Joel asked: *"everything is still working in the v2.1.0 release and its rare someone would see this during
deployment? If so lets push to v2.2.0."* The answer is **defer to v2.2.0** — but the reason is **not** that
the problem is rare.

**The accurate statement:**

- Six defects in the v2.1.0 release shared **one** root cause: *every scope branch populates the shared
  reporting variables by hand, and nothing verifies that it did.* The console was right while the saved
  artifact was silently wrong.
- **All six are individually fixed.** No v2.1.0 user is exposed to any of them.
- The proposed guard is **regression insurance against a future seventh instance**. Its value is entirely
  prospective.

That is why deferring costs a v2.1.0 user nothing — not because the failure is unlikely to be encountered.

> **Note on scope**: the source design document identified **six** defect instances affecting different scope
> combinations and argued about preventing a potential *seventh* instance. These defects have all been
> individually fixed in v2.1.0. Their details are recorded in `.research/known-bugs.md`, which is
> authoritative. This section describes them by scope/symptom pattern rather than by identifier.

---

## 1. The Problem This Would Solve

| Defect | Scope affected | Symptom |
|--------|----------------|---------|
| 1 | `-FullDeployment` (consolidated) | Audit totals never published — report/XML/log all zeros |
| 2 | consolidated per-entity loop | Findings re-initialised inside loop — only the last entity survived |
| 3 | `-AdmxOnly`, standalone `-Include*` | Findings never assigned — "No drift detected" on a drifted domain |
| 4 | `-GposOnly` | Findings published without ResourceType — report interpolation threw, **no report at all** |
| 5 | standalone (3 producers) | Findings published in incorrect shape — normaliser mis-typed them |
| 6 | standalone (8 producers) | Findings published with `ResourceType = Unknown` |

The common structure, stated precisely:

> **Every scope branch populates the shared reporting variables by hand, and nothing verifies that it did —
> or that what it published is well-formed.**

`Audit-TierModel.ps1` has **one** reporting contract (`$auditSummary.TotalChecked`, `.DriftCount`,
`.ErrorCount`, and `$driftFindings`) and **eleven** independent producers of it. Eleven hand-written
implementations of one contract is not eleven accidents; it is one missing invariant. The report, the XML,
the JSON and the log are all downstream of those four variables, so a branch that forgets one of them
produces a *confident, wrong artifact* rather than an error. That is the worst possible failure mode for an
audit tool and it is precisely what v2.1.0 exists to prevent.

**Why it stayed invisible**: on a clean domain a stale `0` and a correct `0` are identical. Every one of the
six was found by reading code or by a drifted fixture — never by a passing run.

---

## 2. What Is NOT Proposed, and Why That Matters Most

The first instinct was a **post-branch assertion**: after the scope dispatch, assert that the reporting
variables were published. **The author argues against his own idea, because it would have become instance
seven.**

A post-branch assertion of the form "were these variables assigned?" **passes vacuously**:

- **It would have missed Defect 2** (re-initialization in a loop). The `$driftFindings` variable *was* assigned — repeatedly. The bug was that each
  assignment destroyed the previous one. The variable is non-empty at the assertion point and the assertion
  goes green.
- **It would have missed Defects 4, 5, 6** (malformed findings). All three published a populated, non-empty findings
  collection. The *contents* were wrong (missing `ResourceType`, wrong `Type`, `ResourceType = Unknown`).
  An existence check cannot see inside.
- **It would have missed Defect 1's** (consolidated totals) **worst consequence.** The total-checked count was `0` — a legitimate
  value on a clean domain. "Is it set?" is satisfied by `0`.

So a naive guard would have caught **1 of 6** (Defect 3, unassigned findings) while creating a new, highly visible artifact that
*appears* to verify the contract. Reviewers would reasonably stop looking. **A guard that can pass vacuously
is worse than no guard**, for the same reason a control that fails for the wrong reason is worse than no
control, and for the same reason `Should -Match 'COMPLIANT'` passed against the text "not compliant".

Any design that survives must be **non-vacuous by construction**.

---

## 3. Proposed Design — Publish Helper + Arithmetic Cross-Check + Double-Publish Detector

Three parts. The helper supplies uniformity; the cross-check supplies non-vacuity; the detector catches the
defect pattern from Defect 2 (re-initialization). **None of the three is sufficient alone.**

### 3.1 A single publish helper every branch must route through

```
Publish-TierModelScopeResult
    -Scope        <string>    # 'OuOnly', 'FullDeployment', 'Standalone', ...
    -TotalChecked <int>
    -DriftCount   <int>
    -ErrorCount   <int>
    -Findings     <object[]>  # already normalised
    -ResourceType <string>    # default for findings that carry none
```

It performs the assignment to `$auditSummary` / `$driftFindings`, runs every finding through
`ConvertTo-TierModelDriftFinding`, and records that scope `X` has published.

This alone removes the *class* of findings-related defects (Defects 3, 4, 5, 6): a branch cannot publish an un-normalised finding,
because publishing and normalising become the same action.

### 3.2 The arithmetic cross-check — the non-vacuity mechanism

The helper rejects a publication that is internally inconsistent:

- `DriftCount -gt 0` but `Findings.Count -eq 0` → **throw**. This catches Defects 3 and 1 (unassigned findings / uninitialized totals), and unlike
  an existence check it is *not* satisfied by a clean domain: on a clean domain `DriftCount` is `0` and the
  rule is not engaged.
- `Findings.Count -gt DriftCount` → **throw**. The `AuditRight`/`Pass` inverse case: compliant rows leaking
  into the drift collection.
- `TotalChecked -lt (DriftCount + ErrorCount)` → **throw**. Catches a stale `TotalChecked` published beside
  live counts, which matches Defect 1's pattern (uninitialized consolidated totals).
- Every finding must render: `Type`, `ResourceType`, `Identifier`, `Details` all present and non-empty, and
  `ResourceType -ne 'Unknown'` → **throw**. This catches Defects 4, 5, 6 (malformed findings).

**Why this is not vacuous**: it does not ask *"did you publish?"* — it asks *"does what you published agree
with itself?"* The counts and the findings are produced by different code paths in every branch, so they
constitute genuinely independent evidence. A branch that forgets to publish findings still has a live
`DriftCount`, and the two disagree.

**It is still not universal**, and the design does not claim otherwise: if a branch computed *both* the count
and the findings wrongly and consistently, the cross-check agrees and passes. That residual gap is real. It
is much smaller than the existence check's gap, but it exists.

### 3.3 The double-publish detector — the Defect 2 case

The helper records each `-Scope` that publishes. A second publication for the same scope, or any publication
after the reporting variables have been read, throws. This is the only one of the three that would have
caught Defect 2 (re-initialized findings), whose signature was *legitimate assignment repeated destructively*.

Note this required knowing Defect 2's pattern to design. **The author explicitly declines to claim the guard
would have caught it prospectively** — reverse-engineering a detector from a known defect is weaker evidence
than it looks.

---

## 4. Blast Radius

**Publishing branches: 11.**

| # | Branch | Publishes today | Notes |
|---|--------|-----------------|-------|
| 1 | `-FullDeployment` / consolidated | counts + findings | consolidated publishing site (totals + re-initialization) |
| 2 | `-OuOnly` | counts + findings | |
| 3 | `-GroupOnly` | counts + findings | |
| 4 | `-UserOnly` | counts + findings | |
| 5 | `-OuAclOnly` | counts + findings | hand-built projection, deliberately not routed through the normaliser (carries a `Type` derivation the normaliser cannot express) |
| 6 | `-GposOnly` | counts + findings | Defect 4 site |
| 7 | `-AdmxOnly` | counts + findings | Defect 3 site |
| 8 | standalone `-Include*` aggregate | counts + findings | multiple findings-related defects; 8 producers behind one branch |
| 9 | canonical-ACL phase | error count only | **publishes no findings by design** |
| 10 | prerequisite / fail-fast exits | nothing | terminates before reporting |
| 11 | `-ReportOnly`-style no-op paths | nothing | |

**What breaks if a branch legitimately has nothing to publish** — branches 9, 10 and 11. This is the design's
sharpest edge. "Nothing to publish" must become an *explicit, named* state rather than an absence:

```
Publish-TierModelScopeResult -Scope X -NoFindings -Reason 'phase reports errors only'
```

A branch must still call the helper; it simply declares that it has nothing. That preserves non-vacuity
(silence is no longer valid) at the cost of touching branches that have no bug.

**Branch 5 (`-OuAclOnly`) is a genuine casualty**: routing its hand-built projection through the helper would
relabel every OU-ACL finding, a regression already declined once. It would need a `-PreNormalised` escape
hatch — and every escape hatch is a place instance seven can hide.

**Realistic size**: ~11 call-site edits, one new helper (~60 lines), plus the escape hatch for branch 5. Not
enormous, but it touches **every** reporting path in the file simultaneously, including the seven that are
currently correct.

---

## 5. Hazard — Can It Fail Loudly at the Right Moment?

Yes, with one caveat that must stay on the record.

**Right moment**: the helper throws at the publish call, inside the scope branch, while the scope name and
the offending values are in hand. The message can name the branch and the inconsistency. That is far better
than the current failure mode, where the artifact is written successfully and is simply wrong.

**⚠️ The caveat — a guard that throws is a guard that can kill a healthy run.** If the cross-check is wrong
about a legitimate shape, a *healthy* audit dies at the publish step and produces no report at all. That is
similar to Defect 4's failure mode (missing ResourceType) — a guard that could itself become a new failure
mode. The canonical-ACL phase shows the risk is not theoretical: **it has still never been observed succeeding against a good DC** — every observation to date
had an unreachable DC. If it emits a shape the guard rejects, a clean domain produces no report.

A mitigation would be to have the guard **record a loud, correlated log entry and a console banner** rather
than throw, on the argument that a wrong artifact plus a loud complaint is strictly better than no artifact.
The author leans this way, but it weakens the guarantee, and wants Joel to choose deliberately.

---

## 6. Recommendation and Ruling

**Author's recommendation: defer to v2.2.0. Joel's ruling, 2026-09-05: DEFERRED to v2.2.0.**

**Arguments to ship in v2.1.0**
- The family is proven and expensive: six instances, and the last three were found only because someone went
  looking. There is no evidence the search is exhausted.
- The release exists to make failures visible. This is the structural version of that goal.
- Joel's standard is explicit that time is not the constraint.

**Arguments to defer**
1. **It touches all eleven reporting paths, seven of which are correct.** Every fix in this release so far
   has been surgical, with a measured guarantee that untouched sites render byte-identically. This guard
   cannot offer that: it rewrites the publish step everywhere at once. Adding a change with this blast radius
   at the end of the release inverts the risk profile of the whole release.
2. **It can take down a healthy run.** See §5. Against an unvalidated canonical-ACL success path, that is a
   live risk on a *good* domain — the failure mode that damages operator trust most.
3. **The six known instances are already fixed.** The guard prevents instance seven; it repairs nothing
   currently broken. Its value is entirely prospective.
4. **The fixture to prove it does not exist yet.** A guard shipped before the drifted fixture runs has never
   been exercised against real producer output — and this guard's whole purpose is to be non-vacuous.
   Shipping an unexercised non-vacuity mechanism is the exact mistake it is designed to prevent.
5. **The right sequence is available and cheap.** Land the fixture in v2.1.0, let it exercise the fixes on a
   real DC, then build the guard in v2.2.0 against known-real shapes.

**What was done instead for v2.1.0** — already complete, at effectively zero blast radius: findings are
routed through `ConvertTo-TierModelDriftFinding` at every publish site (true for all scopes except branch 5,
which is documented in-code with the reason). That captures most of §3.1's benefit without the helper, the
escape hatch, or the throw.

---

## Open Questions for Joel

- **OQ-001** — **v2.1.0 or v2.2.0?** *Answered 2026-09-05: **v2.2.0**.* Retained here because the reasoning
  above is what the v2.2.0 work must start from.
- **OQ-002** — On cross-check failure, **throw or log loudly?** The author's lean is a loud log entry plus a
  console banner, given §5. **Unresolved.**
- **OQ-003** — Should branch 5 (`-OuAclOnly`) be brought into the normaliser with a deliberately extended
  `Type` derivation, so the last non-uniform publish site is removed? This is a small, self-contained piece
  that could ship independently of the guard. **Unresolved.**
