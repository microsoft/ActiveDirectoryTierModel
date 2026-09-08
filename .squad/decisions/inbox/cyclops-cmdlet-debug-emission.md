# Decision note - `-EnableDebug` scope hinges on an unmeasured question

**Author:** Cyclops
**Date:** 2026-09-05
**Status:** Proposed - blocked on one measurement

## The finding

The product contains exactly **four** `Write-Debug` call sites:

| File | Line |
|---|---|
| `modules\TierModel\public\New-TierModelOu.ps1` | 93 |
| `modules\TierModel\public\New-TierModelOu.ps1` | 100 |
| `modules\TierModel\public\Repair-TierModelCanonicalAcl.ps1` | 151 |
| `modules\TierModel\public\Write-TierModelLog.ps1` | 92 |

**None of them are in GPO code.** There are also zero `-Level 'Debug'` log calls.

The customer incident that motivated the whole `-EnableVerbose` / `-EnableDebug` feature was a
**GPO creation that failed silently**. As built, `-EnableDebug` emits nothing of our own on the
exact path it exists to illuminate.

## The question that decides scope

Joel's stated requirement was that debug output would come from "every single cmdlet that is
being executed". That holds only if the **ActiveDirectory and GroupPolicy cmdlets themselves**
emit debug records when `$DebugPreference` is set. Nobody has measured that.

- **If they do** - the four-site count is largely irrelevant, `-EnableDebug` delivers on the
  incident path, and W2 stays optional. Proceed to the lab matrix and ship.
- **If they do not** - `-EnableDebug` is close to hollow, and **W2 (adding `Write-Debug` to the
  GPO code paths) becomes the real work, not an optional extra**. The switch must not be
  described to customers as a GPO diagnostic until W2 lands.

## Decision

**Do not guess.** `.research\verbose-debug-poc\Test-CmdletDebugEmission.ps1` measures it
directly: 8 targets x 6 preference cells, read-only, records classified by record type via
`4>&1 5>&1`, with sample content dumped for human judgement. It reports RIG VALID/INVALID from
a control target first, so a zero from GroupPolicy cannot be mistaken for an answer when the
apparatus is simply broken.

Run it on `TierLab-DC01` before finalising the feature's scope or its customer-facing description.

## Constraints reaffirmed

- **Never pass `-Debug` as an explicit parameter to an AD or GroupPolicy cmdlet.** Lab-proven
  `Object reference not set to an instance of an object` in a non-interactive host. Setting the
  preference variable is the safe mechanism. The POC enforces this by scanning its own target
  scriptblocks and throwing, rather than relying on a comment.
- `-SkipEditionCheck` on the GroupPolicy import remains mandatory (decisions.md #6).

## Reusable engineering findings

1. **A test cell that cannot produce a non-zero result is the same defect class as a check that
   cannot fail.** Preference lookup is function -> script -> global; pinning script scope off
   while setting global scope makes the global cell structurally blind. Remove the shadowing
   variable instead of pinning it.
2. **Verdict logic needs three outcomes, not two.** Branching only on `count > 0` reports a
   confident NEGATIVE for a category that was never measured. NOT MEASURED must be as loud as
   NEGATIVE.
3. **Report distinct record counts alongside totals.** Repetition inflates a count without adding
   diagnostic value, and a large number creates false confidence precisely when something is
   already broken.

## Housekeeping

`.venv\Scripts\Activate.ps1` is a stray Python 3.14.3 virtualenv artifact - untracked,
self-ignored, created for a different path (`C:\ADO\TierModelv2\.venv`), with no Python project
files anywhere in the repo. The whole `.venv` folder is safe to delete. It also inflates the
`Write-Verbose` site count by 17; real product coverage is ~22, not 39.

`.research\` now holds `debug-switch-poc\`, `verbose-vs-debug-poc\` and `verbose-debug-poc\`.
Worth consolidating before anyone else has to guess which is current.
