# Decision: truthful Missing/Mismatched breakdown in the GPO and ADMX summaries (BUG-054)

Author: Rogue
Date: 2026-09-07
Branch: feature/enable-verbose-debug (uncommitted)
Ruled by: Joel Platek - "the log must be accurate too"

## What was wrong

Four sites printed a hardcoded literal `0` for the Missing bucket, directly above findings that
proved otherwise:

- `Audit-TierModel.ps1:1168` - `"  Missing: 0"` (GPO summary)
- `Audit-TierModel.ps1:2195` - `"  Missing: 0"` (ADMX summary)
- `Test-TierModelAdmx.ps1:233` - `"Missing ADMX Files: 0 [check]"` in green
- `Test-TierModelAdmx.ps1:235` - `"Missing ADMX Files: 0 [cross]"` in red, on the DRIFT branch

Executed evidence: with all files absent the producer returns 60 `Missing` findings while the
summary printed `Missing ADMX Files: 0` and `Configuration Mismatches: 60`. BOTH buckets were
wrong - missing files were being reported as mismatches.

## Decision

Populate the existing buckets with real counts. Do NOT introduce a new display bucket.

The Missing line already existed at every one of the four sites; it simply lied. Filling it in
is therefore not a bucket split and carries no risk to any total. A genuinely new bucket would
have risked moving the drift total, which was explicitly protected.

**Producer (`Test-TierModelAdmx.ps1`)** counts the breakdown from its own per-file results:

    $missingCount  = @($auditResults | Where-Object { $_.Status -eq 'Missing' }).Count
    $mismatchCount = @($auditResults | Where-Object { $_.Status -eq 'Mismatch' }).Count

Every result that increments `$totalFailed` sets Status to exactly one of `Missing` or
`Mismatch`, so `missingCount + mismatchCount == driftCount` by construction, not by coincidence.
`Missing` and `Mismatched` are published additively on both Summary shapes. `TotalFiles`,
`Compliant`, `Drift`, `Errors` and `CompliancePercentage` are untouched.

**Consumer (`Audit-TierModel.ps1`)** reads the breakdown defensively and falls back to exactly
today's numbers when a shape does not publish it:

- GPO: `Missing = MissingGpos`, `Mismatched = ConfigurationMismatches + AuditErrors`.
  Those sum to the printed `Total Drift` (`Drift + Errors`) identically. Audit errors stay
  folded into Mismatched rather than gaining a new line, which keeps the breakdown reconciling
  without changing the shape of the output.
- ADMX: `Missing = Summary.Missing`, `Mismatched = Summary.Mismatched`, falling back to
  `Mismatched = Drift` when the keys are absent.

The fallback matters: the integration suite mocks both producers through `New-MockAuditResult`,
which publishes neither breakdown. An unguarded read would have thrown under StrictMode across
roughly twenty tests, and a bare fallback to 0 would have re-created the very "prints 0 over
real drift" shape being removed. Falling back to the drift total preserves current behaviour
exactly wherever the breakdown is unavailable.

## Colour

Deliberately NOT routed through `Get-TierModelFindingColor` in `Audit-TierModel.ps1`. The two
lines there keep their existing Red/Yellow constants, matching the OU, Group and User blocks
immediately above them. Only the numbers were wrong; changing colour as well would have made
the GPO and ADMX sections inconsistent with the five sibling sections for no stated benefit, and
would have brought the classifier's escalate-unknown-to-Red behaviour into a code path that
never sees a finding type. The producer's own block keeps its existing count-driven green/red
convention, which becomes correct once the count is truthful.

## Proof the protected numbers did not move

Before and after producers were staged into identical mirrored trees - the only difference
being the file content - and executed across four scenarios:

| Scenario | TotalFiles | Drift | Compliance | Errors | Findings | Protected unmoved |
|---|---|---|---|---|---|---|
| Missing | 60 -> 60 | 60 -> 60 | 0 -> 0 | 0 -> 0 | 60 -> 60 | yes |
| Mismatch | 60 -> 60 | 60 -> 60 | 0 -> 0 | 0 -> 0 | 60 -> 60 | yes |
| Pass | 60 -> 60 | 0 -> 0 | 100 -> 100 | 0 -> 0 | 0 -> 0 | yes |
| AdFailure | 0 -> 0 | 0 -> 0 | 0 -> 0 | 1 -> 1 | 1 -> 1 | yes |

`Missing + Mismatched == Drift` holds in all four. Console before/after, Missing scenario:

    BEFORE: Missing ADMX Files: 0  | Configuration Mismatches: 60 | Overall Status: 60 issues found
    AFTER : Missing ADMX Files: 60 | Configuration Mismatches: 0  | Overall Status: 60 issues found

## Tests

1980/1980/0 CI-shaped, 1650/1650/0 Unit by-path, 330/330/0 Integration by-path. Zero movement
against the pre-change baseline, as predicted before the run.

The ADMX exemption in the BUG-043 ratchet (`Unit.AuditReporting.Tests.ps1`, `$script:MissingCountExempt`)
is now stale. It reads "the console reports ADMX drift as Mismatched with Missing pinned at 0,
so the published figure is correct by construction" - that is no longer how the branch behaves.
The test still passes, because exempt sites are skipped rather than asserted against. Wolverine
should retire the ADMX entry so the ratchet starts enforcing the breakdown at that site too.

## Separate finding raised during this work

`Audit-TierModel.ps1` had LOST its UTF-8 BOM in the working tree. HEAD carries `EF BB BF`; the
working copy began `3C 23`. Not written by this task - file timestamp 15:46:55. No content
damage: parse clean, single helper definitions, git showed it as an isolated line-1 change.
The BOM was restored on write. Whatever tool stripped it should be identified before it touches
another file.
## Correction: consumer design realigned to the established precedent

Recorded after `CHANGELOG.md:25` was surfaced. My first consumer-side implementation
**differed from the approved pattern and I changed it.** Stating that plainly rather than
presenting the final shape as if it had been the intent.

**What I did first.** In the GPO console breakdown I printed two lines, folding
`Summary.AuditErrors` into the Mismatched figure so the two printed numbers would sum to the
`Total Drift` line below them. It reconciled, and every number shown was computed rather than
hardcoded, so it satisfied the brief as I had it.

**Why that was wrong.** `Test-TierModelGPOAudit.ps1:445-453` establishes Missing, Error and
Mismatch as *mutually exclusive* buckets, and the CHANGELOG entry describing it is explicit that
nothing is derived by subtraction and nothing is double counted. Folding errors into mismatches
merges two buckets the producer deliberately keeps apart: a GPO that threw during audit is not a
GPO whose configuration differs. My version reported it as one. A second, different shape for the
same problem in the same codebase is worse than either shape on its own.

**What it does now.** Three separate lines - Missing, Mismatched, Errors - read straight from the
producer keys the precedent built, mirroring the producer's own display order.

**Deliberate deviation on ADMX, stated rather than done silently.** ADMX keeps *two* buckets. Its
printed `Total Drift` is `Summary.Drift`, which excludes errors - they are counted separately in
`$auditSummary.ErrorCount`. `Missing + Mismatched == Drift` exactly. Adding a third line there
would print a figure that does not participate in the total above it, creating the reconciliation
puzzle this whole work item exists to remove. ADMX also has no per-file Error state: errors arise
only from the wholesale catch. Two buckets is the faithful application of the precedent here, not
a departure from it.

**Verification.** The lifted GPO render block was executed against five Summary shapes - real
mixed (2 missing / 3 mismatch / 1 GPO error / 1 threw), real clean, real wholesale-failure, and
both integration-mock shapes. `Missing + Mismatched + Errors == Total Drift` held in all five.
The `Total Drift` line itself was not touched, and compliance percentage and grand total are
read from untouched expressions, so no stop-and-report condition was triggered.

**Survivor sweep.** All 244 `Write-Host` call sites across the two owned files were enumerated by
AST and their first argument tested for a label followed by a literal digit. Post-change: 0. The
detector was self-tested against the same two files at HEAD, where it flagged 5 - the four sites
in the brief plus `Test-TierModelAdmx.ps1:238 "Configuration Mismatches: 0 ✅"`, a fifth literal
that was correct only while drift was zero. A sweep that finds nothing proves nothing unless the
instrument is shown to find something.
