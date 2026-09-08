# Decision: Rogue — BUG-027, consolidated audit totals never reached `$auditSummary`

**Date:** 2026-09-05
**Author:** Rogue (Core Dev)
**Status:** FIXED in code — needs Joel's review before commit. Three follow-up findings below are
**report-only** and await his call.
**Branch:** `feature/enable-verbose-debug`
**Requested by:** Joel Platek

## Context

A lab apply run went 46/46 green; the post-apply audit console printed per-phase counts of
31/32/29/3/105/146/60 and an overall `✅ COMPLIANT`. The final log record said:

```
[Info] TierModel audit completed | DriftCount=0, TotalChecked=0
```

The console was right and the persisted artifact was wrong.

## The defect, as verified

The consolidated `-FullDeployment` path accumulates into **locals** — `$totalChecked`,
`$totalDrift`, `$totalMissing`, `$totalMismatched`, `$totalUnverified`, `$totalErrors` — renders
them to the console, and never publishes them. `$auditSummary` is written **only** by the
single-entity branches, so on the consolidated path it retained its initial zeros from the
initializer.

### Correction to the brief: there are **five** consumers, not three

Joel identified the report body, the XML and the log record. The AST sweep found two more:

| Consumer | Line (post-fix) | Impact when stale |
|---|---|---|
| Text report `Total Checked:` / `Drift Findings:` | L2193–L2194 | reports zero on a drifted domain |
| **Json report — serializes the whole hashtable** | **L2209** | *every* key exported as 0 |
| NUnit XML `total=` / `failures=` | L2224 | **CI reads `failures="0"` and goes green on a drifted domain** |
| Log record `TotalChecked` / `DriftCount` | L2235–L2236 | the artifact operators send us under-reports |
| **Diagnostics-hint gate `if ($auditSummary.DriftCount -gt 0 -or .ErrorCount -gt 0)`** | **L2251** | **the operator with real drift is never offered the `-EnableVerbose -EnableDebug` re-run** |

That last one matters for this branch specifically: the NON-BLOCKING-4 tail hint we added is
**dead on `-FullDeployment`**, which is the scope operators actually run.

### Correction to the brief: there are **three** stale paths, not one

Joel asked me to confirm the consolidated block is the only path that leaves these stale. It is
not. The top-level dispatch is `if ($FullDeployment) {...} else {...}` (one `IfStatementAst`,
AST-confirmed), and inside the `else` are **six independent `if` statements** — not an
`elseif` chain — for `-OuOnly`, `-GroupOnly`, `-UserOnly`, `-OuAclsOnly`, `-GposOnly`, `-AdmxOnly`.

1. **`-FullDeployment`** — the reported defect.
2. **`-AdmxOnly`** — prints its own console summary and **never writes `$auditSummary`**. Same
   defect, same five consumers, independently reachable. Four of the six single-entity branches
   write it; `-AdmxOnly` is the one that does not.
3. **Standalone `-Include*`** (`-IncludeMsa` etc. with no scope switch) — accumulates into
   `$standaloneTotalChecked` / `$standaloneTotalDrift` / `$standaloneTotalErrors` and publishes
   none of them. A `-IncludeMsa`-only audit wrote all-zero artifacts too.

I fixed all three. Leaving 2 and 3 would have shipped a partial fix for an identical bug in the
same file.

## The fix

All three sites are in script scope (AST-confirmed; no function boundary between accumulation and
consumers), so plain assignment is sufficient — no `$script:` qualification needed.

**1. Initializer (L641–L644)** — added `UnverifiedCount = 0`.
Not cosmetic: **under `Set-StrictMode -Version Latest` a missing hashtable key throws on read.**
Verified empirically — `$h=@{A=1}; $h.ZZZ` → *"The property 'ZZZ' cannot be found on this object."*
Any key referenced by the report or log must therefore exist for **every** scope, or report
generation dies on the paths that never set it.

**2. End of the consolidated block (L1767–L1782)** — placed after the `$totalDrift` override and
after all console rendering, before every consumer:

```powershell
$auditSummary.TotalChecked    = $totalChecked
$auditSummary.DriftCount      = $totalDrift
$auditSummary.MissingCount    = $totalMissing
$auditSummary.MismatchCount   = $totalMismatched
$auditSummary.UnverifiedCount = $totalUnverified
$auditSummary.ErrorCount     += $totalErrors
```

**3. `-AdmxOnly` (L1915–L1926)** — mirrors the other single-entity branches, guarded for `Summary`
presence, mapping `TotalFiles` → `TotalChecked` and `Drift` → `DriftCount`/`MismatchCount` exactly
as that branch's own console lines do (it pins Missing at 0).

**4. Standalone `-Include*` (L2132–L2137)** — publishes the `$standaloneTotal*` accumulators.

**5. Text report (L2198) and log payload (L2237–L2240)** — see the `UnverifiedCount` decision.

### Why `ErrorCount` uses `+=` and not `=`

The canonical-ACL `catch` earlier in the consolidated block does `$auditSummary.ErrorCount++` for a
phase that **threw**. A phase that throws never lands in `$auditResults`, so `$totalErrors` — which
sums `Summary.Errors` across `$auditResults` — **does not include it**. A plain `=` would have
silently destroyed that signal.

This is not theoretical: the harness run against a fake DC produced exactly this, logging
`"ErrorCount":1, "TotalChecked":56, "DriftCount":5`. The 1 is the canonical phase failing to
resolve the domain DN; `$totalErrors` was 0. Under `=` the log would have said 0 errors.

## Answer to Q3 — yes, `$totalUnverified` should be in `$auditSummary`, and I did it

**Implemented.** `UnverifiedCount` is now initialized, populated on the consolidated path, rendered
in the Text report, and carried in the log payload. I also added `ErrorCount` to the log payload
for the same reason. What it affects:

- **Log payload** — gains `ErrorCount` and `UnverifiedCount`. Purely additive; no key renamed or
  removed. The record is `Write-TierModelLog -Data`, serialized as JSON, so consumers keying on
  `TotalChecked` / `DriftCount` are unaffected.
- **Json report** — `auditSummary` is serialized wholesale, so `UnverifiedCount` appears
  automatically for every scope. Additive.
- **Text report** — one new `- Unverified (read failures):` line plus an `Errors:` line.
- **NUnit XML** — untouched.
- **Tests** — safe, and I checked rather than assumed: every report-format test in
  `Integration.Audit.Tests.ps1` runs `-OuOnly` and asserts only structural strings
  (`'TierModel Drift Audit Report'`, `'Scope: OuOnly'`, `'<test-results'`, `auditSummary` not null).
  **No test asserts a number in a report, and none asserts report content on `-FullDeployment`.**
  The consolidated test at L741 asserts `'Total Checked: 56'` against **console** output, which
  this change does not touch. Confirmed by the suites: 1573 / 318, unmoved.

Rationale: an operator's log that omits unverified reads loses precisely the signal TRUE-FINAL-1
added — an unreadable OU is "could not determine", not "compliant", and the log is what gets sent
to us.

### Fields still structurally zero, by design — flagged, not fixed

- `UnexpectedCount`, `OrphanedGpoLinkCount`, `SecurityDeltaCount` — **no accumulator exists
  anywhere in the script** for these. They print 0 in every report on every scope today. Pre-existing;
  outside BUG-027.
- `UnverifiedCount` on the single-entity and standalone paths — those paths have no unverified
  accumulator, so it stays 0 there. The consolidated path is where the console shows the dedicated
  Unverified line, and that is the path now covered.

## Answer to Q4 — the `=` / `+=` mix in `-OuOnly` is **not** broken

Joel flagged that `-OuOnly` uses `=` for the OU results and `+=` for the canonical-ACL results
against the same fields. Investigated; **no change made**, as instructed.

It is correct as written. `$auditSummary` starts at zeros, the `=` block runs **first** (seeding
from `$ouResult.Summary`), and the canonical `+=` runs **after** (accumulating on top). The `=` is
therefore equivalent to a `+=` from zero, and the ordering is not accidental.

The double-assign/clobber risk Joel intuited would need **two scope switches true at once**, which
the parameter validation forbids: `$activeScopeCount = @($scopeParameters | Where-Object { $_ }).Count`
followed by `elseif ($activeScopeCount -gt 1) { <error> }`. Only one branch can ever run.
The six independent `if`s read as if they could co-fire; they cannot. That is a readability trap,
not a defect — converting them to `elseif` would document the invariant, but it is a no-op change
and I did not make it.

## Follow-up findings — report only, no code changed

**(A) `$driftFindings` is clobbered on the consolidated path — the report's FINDINGS section is
wrong on `-FullDeployment`.** The per-entity display loop reuses the *same* script-scope variable
as a scratch accumulator: inside `foreach ($result in $auditResults)` it does `$driftFindings = @()`
and then appends only that entity's findings. After the loop, `$driftFindings` holds **only the
last entity's** findings, and that is what the Text report's `=== FINDINGS ===` section and the
HTML report's `Findings:` count render. Same "console right, artifact wrong" class as BUG-027, same
file, different variable. **Not fixed** — it is outside the totals Joel scoped, and the correct
repair (rename the loop-local) is a behaviour change to console output I do not want to make
unreviewed. Recommend a BUG-028.

**(B) The console's `Total Errors:` under-reports on the consolidated path.** It prints
`$totalErrors`, which excludes the canonical-phase `catch` increment described above. So
NON-BLOCKING-5's counter had **no reader at all** on `-FullDeployment` before this fix. My change
gives it one (the log/report/XML), which means `$auditSummary.ErrorCount` can now legitimately
exceed the console's `Total Errors` by the canonical count. **The log is the correct one.** If Joel
prefers them identical, the fix belongs on the console line, not on my assignment — say the word.

**(C) `CompliantCount` is written by `-OuAclsOnly` and `-GposOnly` but is absent from the
initializer.** Hashtables permit new keys on write, so this does not throw today, and nothing reads
it. Harmless, but it is the same latent StrictMode shape as (1) above: the day something reads
`CompliantCount` on another scope, it throws. Worth initializing at some point.

## Verification

**A compliant run cannot prove this fix**, so I did not rely on one. Built a drifted harness at
`$env:TEMP\Bug027.Harness.Tests.ps1` (deliberately **not** in `tests\` — Wolverine's) mocking the
six audit cmdlets to return 56 checked / 5 drift, plus an unverified scenario and an `-AdmxOnly`
scenario. **Stub-level, not live DC** — Joel to confirm against a real drifted domain.

**Control (pre-fix).** Copied the script, stripped the 13 assignment lines, ran the same harness:

```
CONTROL (pre-fix) Passed=0 Failed=5
  NUnit XML : <test-results name="TierModelAudit" total="0" failures="0">   <-- on a 5-drift run
  Json      : Expected 56, but got 0
  Text report / log / AdmxOnly report : all zero
  Console   : "Total Checked: 56" MATCHED — the console was right the whole time
```

The first control failure is instructive: the console assertion passed and the *report* assertion
failed, reproducing the exact console-right/artifact-wrong split. (The control copy must live in the
repo root — run from `$env:TEMP` it fails at module import for an unrelated reason and proves
nothing. Deleted immediately after the run.)

**Post-fix.** Same harness, unmodified script: **5 / 5 passed.**

| Artifact | Pre-fix | Post-fix |
|---|---|---|
| Console | 56 checked / 5 drift | 56 / 5 (unchanged) |
| Text report | 0 / 0 | 56 / 5 |
| NUnit XML | `total="0" failures="0"` | `total="56" failures="5"` |
| Json `auditSummary` | 0 / 0 | 56 / 5 |
| Log record | `TotalChecked=0, DriftCount=0` | `"TotalChecked":56, "DriftCount":5, "ErrorCount":1, "UnverifiedCount":0` |
| Unverified scenario log | key absent | `"UnverifiedCount":3` |
| `-AdmxOnly` report | 0 / 0 | 15 checked / 4 drift |

**Suites, by path, never by tag:**

| Suite | Result | Baseline |
|---|---|---|
| `tests\Unit.*.Tests.ps1` | **1573 passed / 0 failed / 0 skipped** | 1573 / 0 — matched |
| `tests\Integration.*.Tests.ps1` | **318 passed / 0 failed / 0 skipped** | 318 / 0 — matched |

Parse errors: **0**. Nothing committed. `tests\`, `.research\lab-validation\`,
`Test-TierModelPrerequisites.ps1`, `TierModel.psm1` and `Deploy-TierModel.ps1` untouched.

## Follow-ups

- Joel to confirm against a genuinely drifted lab domain (mine is stub-level).
- Joel to rule on finding (A) — the `$driftFindings` clobber — as a probable BUG-028.
- Joel to rule on finding (B) — whether the console `Total Errors:` should be brought up to match
  the log, which would make NON-BLOCKING-5 visible on the consolidated path.
- `CHANGELOG.md` entry for BUG-027 — Scribe's.
