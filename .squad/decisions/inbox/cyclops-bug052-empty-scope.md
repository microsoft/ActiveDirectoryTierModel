# Decision record — BUG-052: what an empty scope should report

**Author:** Cyclops (lab execution)
**Date:** 2026-09-07
**Status:** RECOMMENDATION — awaiting Joel's ruling
**Build measured:** `git archive HEAD` = `6725ab3` (does NOT include Rogue's uncommitted drift fix)
**Evidence:** `C:\CyclopsStage\bug052\FINDINGS-bug052-empty-scope.md`, raw logs `C:\CyclopsStage\bug052\lab9\`

---

## D1. BUG-052 is REAL and is reproduced by execution
Standalone `-IncludeMsa` / `-IncludeWinLaps` with an empty config section print
`Overall Status: ✅ COMPLIANT` in **green** over `Total Checked: 0`. Real product, real DC,
colour captured. Not inferred.

## D2. The registered scope claim "every producer" is WRONG — 3 of 13 fail closed instead
Emptying `organizationUnits`, `groups` or `users` hard-fails `Get-TierModelConfig`
("The property 'Count' cannot be found on this object") and aborts the audit. Bisected in the lab
across 12 sections. Population: 21 `Test-TierModel*` functions, **13** config-driven scope producers,
**13 of 13 executed** for the empty case. Register entry should be corrected to
"10 of 13 config-driven producers report false-clean; 3 of 13 abort the run".

## D3. NEW DEFECT, needs no ruling — the standalone headline ignores errors
`Audit-TierModel.ps1:2381` branches on `$standaloneTotalDrift` alone. Lab output shows
`✅ COMPLIANT` GREEN directly above `Total Errors: 2` RED. The consolidated path already has the
guard at L1774 ("TRUE-FINAL-2"). **Recommend applying the same guard to the standalone path
regardless of how Joel rules on BUG-052.** This is independent of empty scopes.

## D4. NEW DEFECT, needs no ruling — unreachable directory reports as compliant
`Test-TierModelGroup` and `Test-TierModelUser` print "All Groups/Users are compliant ✅" in green
when every directory read fails. Executed. `Test-TierModelOu` already carries the remedy
(`UnverifiedCount`). **Recommend porting it to Group and User.** This is the exact failure mode
Rogue refused to create when he declined the blanket WinLaps relabel — it is already shipping.

## D5. Zero-case arithmetic — ANSWERED BY EXECUTION
Not a divide-by-zero. 5 of 7 compliance sites already guard and print
`Compliance: N/A (could not be determined)` in red. **2 of 7 do not** (L1116 GPO, L2120 ADMX);
they read producer `CompliancePercentage`, and three producers return `else { 100 }`. Result:
**silent 100% rendered GREEN**, lab-confirmed over `Total Checked: 0`. The defect is inconsistency,
not absence.

## D6. Case (b) is already correct and must be protected
"Configured but resolving to zero live objects" reports drift correctly today. A BUG-052 fix that
collapses (a) "nothing configured" with (b) would destroy a distinction the tool currently gets
right. The three cases must stay separate; (c) "failed to enumerate" must never read as clean.

## D7. RECOMMENDED OPTION — "Not checked / nothing configured", neutral, excluded from compliance
Neutral gray status, never green, no ✅; excluded from the compliance denominator; headline becomes
`NOT CHECKED` when every scope is empty. **Chosen because it is the rule this codebase already
adopted** in 5 of 7 compliance sites and in `Test-TierModelOu` — it makes the tool self-consistent
rather than introducing a fourth opinion. A yellow "configuration may be incomplete" warning is a
reasonable *addition* but a poor substitute (a warning that fires on every partial deployment gets
ignored). **Rejected:** treating empty as drift — it punishes legitimate partial deployments and is
the shape of the earlier −1.74% compliance mistake.

## D8. Cost of the fix
Changes `Compliance: 100%` → `N/A` and `✅ COMPLIANT` → `NOT CHECKED` on empty scopes. Any test
asserting `100` or green on an empty fixture will fail, and should. Joel has already accepted in
advance that audit numbers will change.
