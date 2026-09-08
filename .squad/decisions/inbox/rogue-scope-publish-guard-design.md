# Design note — a scope-publish guard to make instance six impossible

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05
- **Status:** **DESIGN ONLY — nothing implemented.** Requested by Joel via review.
- **Scope of the note:** `Audit-TierModel.ps1`

## The invariant that is missing

Five separate defects this session (BUG-027, BUG-028, BUG-030, BUG-032, and the `-AdmxOnly`
half of BUG-030) share one root cause:

> Every scope branch populates the shared reporting variables **by hand**, and nothing
> verifies that it did — or that it published the right *shape*.

The shared reporting surface is exactly two things:

1. `$auditSummary` — a hashtable initialised around L~700 with `TotalChecked`, `DriftCount`,
   `ErrorCount`, `MissingCount`, `MismatchCount`, `UnverifiedCount`.
2. `$driftFindings` — an array initialised at **L762**, read by the three report writers at
   **L2393** (Text), **L2399** (Json) and **L2410** (Html).

Five consumers read `$auditSummary`: the report body (L2390), the NUnit XML, the log record
(L2428), and — the one that matters most — the diagnostics re-run hint gated at **L2440**.

The failure signature is always the same and always silent: **console right, persisted
artifact wrong**. And it is systematically invisible to the test suite, because a *clean*
run publishes zeros, and zeros are indistinguishable from a stale initialiser.

## Branch inventory (measured, not estimated)

| Path | Publishes `$driftFindings` | Notes |
|---|---|---|
| Consolidated `-FullDeployment` | L1913 (`$consolidatedDriftFindings`) | was BUG-027 / BUG-028 |
| `-OuOnly` | L1947 | `=` from result |
| `-OuOnly` + canonical ACL | L2015 | projection, hand-built shape |
| `-GroupOnly` | L1984 | `=` |
| (user sub-branch) | L1999 | `=` |
| `-GposOnly` | L2046 | projection — was BUG-032 (`ResourceType` missing) |
| `-AdmxOnly` | L2088 | was BUG-030 (never published at all) |
| standalone `-Include*` | L2325 | was BUG-030 |

**Eight publish sites, four distinct shapes.** Three of the eight were wrong when this
session started. That is not five accidents; it is one missing invariant.

## Option A — post-branch assertion

After the whole scope `if/elseif` chain and **before** the first consumer, assert that the
reporting surface was published.

```
if (-not $script:ReportingPublished) { throw "internal: scope '<name>' did not publish ..." }
```

Each branch sets a sentinel via its publish.

**Why I do not recommend this alone:** it can pass **vacuously**. A branch that sets the
sentinel and publishes an empty/ill-shaped array satisfies it. BUG-032 (a missing
`ResourceType` key) and BUG-028 (a clobbered accumulator) would both have sailed straight
through. A guard that can pass vacuously **is itself instance six**.

## Option B — a single publish helper every branch must route through (recommended)

```
Publish-TierModelAuditScope -ScopeName <string> -Findings <array> -Summary <hashtable>
```

The helper is the **only** writer of `$driftFindings` and the summary counters. It:

1. Normalises every finding through the existing `ConvertTo-TierModelDriftFinding`, which
   already guarantees `Type` / `ResourceType` / `Identifier` / `Details`. **This alone would
   have prevented BUG-032 and BUG-030.**
2. Rejects a finding that cannot be normalised, loudly, naming the scope.
3. Sets a one-shot published sentinel; a **second** call for the same run throws. That is
   the BUG-028 clobber detector — the per-entity loop calling it repeatedly would fail
   immediately and noisily.
4. Cross-checks arithmetic: if `DriftCount -eq 0` but `Findings.Count -gt 0` (or the
   reverse), throw. **This is the part that fails non-vacuously**, because it compares two
   independently-derived numbers. It is exactly the check that would have caught
   `TotalChecked=0` against an obvious 406.

**Blast radius:** 8 call sites in one file, plus one new helper. No signature changes
outside `Audit-TierModel.ps1`. `Deploy-TierModel.ps1` is untouched.

**A branch that legitimately has nothing to publish** is handled explicitly, not by
omission: it calls the helper with `-Findings @()` and zeroed counters. That is the crux —
"nothing to report" becomes an **affirmative statement** rather than the absence of code,
which is precisely the distinction the current code cannot make.

## Can it fail loudly at the right moment?

Yes, and this is the acceptance test for the design:

- **Right moment** — the helper throws at the publish site, naming the scope, *before* any
  report is written. Not at report-render time (BUG-032's late throw), and not silently.
- **Non-vacuous** — the arithmetic cross-check and the double-publish detector compare
  independent facts. Neither can be satisfied by doing nothing. A branch that forgets to
  call the helper trips the post-chain sentinel (Option A, retained as a backstop).
- The design is therefore **A + B together**: B for shape and arithmetic, A as the
  did-you-call-it backstop.

## Honest recommendation on v2.1.0

**I recommend deferring to v2.2.0, with one exception.**

Reasons:

- v2.1.0 already carries eleven fixes, five of them in this file, and every one is currently
  verified by a targeted control experiment. This guard is a **structural refactor** of the
  publish path — a different risk class entirely from the surgical edits reviewed so far.
- It rewrites all eight publish sites, including the five single-entity `=` branches that
  Joel has repeatedly and correctly insisted must keep behaving identically. Touching them
  now would invalidate that constraint at the worst moment.
- The arithmetic cross-check will almost certainly surface *further* genuine defects. That
  is a good thing, but it means the change cannot be scoped or estimated up front, and
  Joel's new standard ("squash all known bugs before release") would then bind the release
  to an open-ended discovery process.
- Integration is already at 315/3 pending Wolverine's test updates. Adding a structural
  refactor on top of an unsettled baseline makes attribution of any new failure ambiguous.

**The exception I would take now, if anything:** the cheap, additive, non-structural half —
route the two hand-built projections (`-GposOnly` L2046 and `-OuOnly`+ACL L2015) through the
existing `ConvertTo-TierModelDriftFinding` normaliser, as `-AdmxOnly` and the standalone
path already do after BUG-030. That removes the remaining two hand-built shapes without
introducing a helper, a sentinel, or any new control flow, and it closes the specific hole
BUG-032 came through. It is ~2 lines each and I can control-test it the same way.

I have **not** done this. Say the word and it is a ten-minute change.
