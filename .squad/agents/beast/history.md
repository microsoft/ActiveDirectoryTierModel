# beast -- History

## Session 2026-09-04 — Config Validation Wire-In & Scribe Orchestration

**Status:** Scribe logs recorded; prior session work (BUG-020/021/022/023) completed by team

This session's focus: Scribe orchestration and decision archival for the config-validation wire-in session. Beast's prior work (CHANGELOG entries for BUG-020, BUG-021, early BUG-023 tracking) was verified shipped in commit c973611. BUG-022 CHANGELOG correction was flagged as incomplete by Beast but later recovered and completed by Cyclops.

**Key lesson:** Agent self-reports of completion are not sufficient evidence. Cyclops independently verified line numbers and corrected the CHANGELOG entry that Beast reported as done but which never persisted to disk.

---

## Recent Work (2026-09-04)

**Status:** BUG-016 complete — gpoStatus reduced to 4 real values, deploy fails loudly on bad value

### 2026-09-04 — BUG-016: Remove Invented gpoStatus Values, Deploy Fail-Loud

**Branch:** `fix/gpo-silent-skip-and-false-success`  
**Files changed:** `modules/TierModel/public/New-TierModelGpo.ps1`, `modules/TierModel/public/Test-TierModelGPO.ps1`

**What was done:**
- **Deploy side (New-TierModelGpo.ps1 ~L167-205):** Removed `AllEnabled` and `BothSettingsDisabled` from the `switch` lookup. Removed the silent `default { 0 }`. Added an explicit pre-validation block (before the inner `try`) that throws for any unrecognized value — the throw propagates to the **outer** catch (per-GPO failure accounting: red ERROR console line, `$failed++`, `$converged = $false`) not the inner catch (which is warning-only and counts the GPO as executed). Error message names the GPO, the bad value, and lists all 4 valid values.
- **Audit side (Test-TierModelGPO.ps1 ~L166-189):** Reduced `$validGpoStatus` ordered hashtable from 6 entries to 4. Updated the comment to document the AD-flags-vs-enum-ordinal trap. Removed dead `BothSettingsDisabled` reference from the `GPO Enabled State` advisory string comparison.
- **Both sides:** Comments updated to state these are AD `flags` attribute values (not .NET GpoStatus enum ordinals), to record the empirically verified mapping from Joel's 2026-09-04 lab run, and to explain why the BUG-016 removals were made.
- **Flags values:** Unchanged. AllSettingsEnabled=0, UserSettingsDisabled=1, ComputerSettingsDisabled=2, AllSettingsDisabled=3 (AD flags attribute, not enum ordinals).
- **PSScriptAnalyzer:** 0 errors, 0 new warnings. Pre-existing Write-Host and BOM warnings unchanged.
- **Unit tests:** 1567 passed / 6 failed. All 6 failures are expected (tests encode old wrong behaviour). Wolverine report produced (see below).

**Wolverine test report (6 expected failures to fix):**

| File | Line | Test name | Why it fails | Required new expectation |
|---|---|---|---|---|
| Unit.GpoOperations.Tests.ps1 | 494 | "Should validate GPO status configuration" | Uses `gpoStatus = "AllEnabled"` (invented value; now unrecognized → Fail, not Pass) | Change `gpoStatus` to `"AllSettingsEnabled"` and keep `Status = 'Pass'` |
| Unit.GpoOperations.Tests.ps1 | 1736 | "Should call Set-ADObject when mode is 'create' and gpoStatus is AllEnabled" | `"AllEnabled"` is now invalid → pre-validation throws → Set-ADObject never called | Change `gpoStatus` to `"AllSettingsEnabled"`; test should pass with `Executed = 1` and `Set-ADObject` called once with `flags = 0` |
| Unit.GpoOperations.Tests.ps1 | 1767 | "Should pass flag=3 for BothSettingsDisabled" | `"BothSettingsDisabled"` is now invalid → pre-validation throws → Set-ADObject never called | Change `gpoStatus` to `"AllSettingsDisabled"` and expect `flags = 3` |
| Unit.GpoOperations.Tests.ps1 | 1777 | "Should default to flag=0 for unrecognized gpoStatus value" | The silent default is gone; unrecognized value now throws → GPO counted as `Failed = 1`, not `Executed = 1` | Rewrite: assert `result.Failed -eq 1`, `result.Executed -eq 0`, `result.Converged -eq $false`, and that error message matches the GPO name + bad value |
| Unit.GpoOperations.Tests.ps1 | 1803 | "Should log a warning and still mark GPO as executed when Set-ADObject throws" | Uses `gpoStatus = "AllEnabled"` (now invalid) → pre-validation throws before Set-ADObject is even mocked → GPO is Failed, not Executed | Change `gpoStatus` to `"AllSettingsEnabled"` (or any valid value) so the mock is reached; the original non-fatal-ADObject-throw behaviour still applies |
| Unit.GpoOperations.Tests.ps1 | 2533 | "Passes status check for BothSettingsDisabled (flags=3)" | `"BothSettingsDisabled"` removed from `$validGpoStatus` → `$expectedFlags` is `$null` → status check Fails, not Passes | Change `gpoStatus` to `"AllSettingsDisabled"` (flags=3, same value) |

## Recent Work (2026-09-02)

**Status:** Dot-source seam delivery complete; module v2.0.0 ready for release

### 2026-09-02 — Session Orchestration: Decisions Archived, v2.0.0 Prepared
- Dot-source guard committed in optional/Update-TierModelMembership.ps1 (no version bump — v1.7.2 unchanged)
- Wolverine's 107-test suite integrated; Membership script coverage 60.18%
- Module version bumped: 1.7.2 → 2.0.0 (Authentication Policy Silos release)
- PR #50 open (Closes #20) on feature/auth-silos; awaits merge to main
- Decisions archive: 12 old entries (pre-2026-08-26) archived; 1 inbox decision merged
- v2.0.0-rc1 tag pushed; v2.0.0 release tag to follow post-merge
- .squad files committed (no deliverable changes)

