# BUG-031 — `Total Errors`: adopt the WIDE behaviour

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05
- **Status:** Implemented, awaiting review
- **Scope:** `Audit-TierModel.ps1` only
- **Branch state:** uncommitted; HEAD `04ab664`

## Decision

Fold the canonical-ACL phase-throw counter into `$totalErrors` **itself**, before the
headline verdict, rather than into a display-only variable. This is the behaviour
`NON-BLOCKING-5` already describes in the code, and it is what I argued for during
BUG-028. Joel approved it.

## Problem

`$auditSummary.ErrorCount++` (Audit L1342) counts the canonical-ACL phase when that phase
**threw**. A phase that throws never lands in `$auditResults`, so the consolidated
accumulator `$totalErrors` (L1622, fed at L1697/L1706 from `$auditResults`) is structurally
incapable of seeing it.

Consequence before this change: a `-FullDeployment` audit in which the canonical-ACL phase
threw would still print `Overall Audit Status: COMPLIANT` and a compliance percentage,
because the verdict at L1737 and the percentage guard at L1751 both consult `$totalErrors`,
which was zero. The error was real, was counted, and had **no reader at all** on the
consolidated path.

## Change

1. **L1732** — `$totalErrors += $auditSummary.ErrorCount`, placed after the `$auditResults`
   accumulation and **before** the TRUE-FINAL-2 verdict (L1737), the console `Total Errors`
   line (L1748) and the compliance-percentage guard (L1751). All three now agree.

2. **L1930** — the BUG-027 publish line changed from `+=` to `=`:
   ```powershell
   $auditSummary.ErrorCount      = $totalErrors
   ```
   **This is load-bearing.** `$totalErrors` now already contains `$auditSummary.ErrorCount`,
   so leaving `+=` would double-count every phase-level throw. This is the single most
   likely place for a future regression to be reintroduced.

3. Removed the now-dead narrow `$displayErrors` variable and its explanatory comment.
   Verified: **0** residual references to `$displayErrors` in the file.

## Verification

- Parse errors: `Audit-TierModel.ps1` **0**, `Deploy-TierModel.ps1` **0**.
- Unit suite by path: **1573 total / 1573 passed / 0 failed** — baseline held.
- Integration suite by path: **318 total / 315 passed / 3 failed**.

The three failures are **exactly** the three Joel named in advance, and are the correct
outcome, not a regression:

- `Full Deployment Audit.Full Audit Orchestration.Should calculate compliance percentage correctly`
- `Compliance Reporting.Compliance Status Display.Should show COMPLIANT status when no drift detected`
- `Compliance Reporting.Compliance Status Display.Should show drift count when drift detected`

**Cause:** all three mock the six entity audit functions but do **not** mock
`Invoke-CanonicalAclAudit`. It therefore runs against the test's unreachable DC, throws, and
increments the counter. With the wide fix that error is now visible to the verdict, so the
status becomes `COMPLIANCE COULD NOT BE FULLY DETERMINED` and the compliance percentage
becomes `N/A`. The tests encode the pre-BUG-019 swallow-the-error behaviour.

Per Joel's instruction the fix was **not** weakened to preserve the 318/0 baseline. Wolverine
owns updating those three tests to expect the error, in a file I must not touch.

## Notes for review

- The `=` at L1930 is the correctness hinge. If someone later re-adds an independent
  `ErrorCount` source they must decide deliberately whether it belongs in `$totalErrors` or
  in the publish, not both.
- The single-entity branches (L2010, L2041, L2079) and the standalone path (L2319) are
  untouched and continue to assign `ErrorCount` from their own sources.
