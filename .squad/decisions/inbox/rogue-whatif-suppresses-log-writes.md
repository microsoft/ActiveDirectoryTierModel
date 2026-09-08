# Decision / disclosure: `-WhatIf` still produces an empty log file (BUG-024's sibling)

**Author:** Rogue (Core Dev)
**Date:** 2026-09-05
**Status:** Disclosure — needs an owner for `modules\**`
**Related:** BUG-024, WI-05

## What was fixed

BUG-024 as scoped: `Deploy-TierModel.ps1` is `[CmdletBinding(SupportsShouldProcess)]`, so under
`-WhatIf` the `New-Item` that created the log directory was suppressed while the following
`Write-Host "Created log directory: ..."` printed unconditionally, and a log file path was then
composed underneath a directory that did not exist.

The rule applied, in Deploy, at both the log directory and the new `Debug\` folder:

- **Diagnostics infrastructure carries `-WhatIf:$false`.** It is not part of the change being
  previewed — it is the apparatus that *records* the preview. An operator doing a dry run must
  still get their log.
- **Success is confirmed with `Test-Path`, never announced.** No message claims a directory,
  folder or transcript exists until it has been observed to exist.

Verified at runtime: with `-WhatIf` the log directory really exists, the announcement is
truthful, and the `Debug\` folder and transcript are genuinely created.

## What is still broken, and why I did not fix it

Under `-WhatIf` the **log file itself comes out empty.** Observed verbatim:

```
What if: Performing the operation "Add Content" on target "Path: ...\Deploy-TierModel-090526-0958.log".
```

`Write-TierModelLog` lives in `modules\TierModel\public\`. Its `Add-Content` inherits
`$WhatIfPreference` from the caller's scope chain and is suppressed, so a `-WhatIf` run
produces a log directory, a `Debug\` folder and a transcript — but a zero-content log.

This is the same defect class as BUG-024 one layer down: the *apparatus* is being treated as
part of the previewed change.

**I did not work around it.** The only fix available from the entry script would be to force
`$WhatIfPreference = $false` into module scope via `& $module { ... }`. That would disable
`-WhatIf` for **every** module operation, meaning a dry run would perform real writes to Active
Directory. That is catastrophically worse than an empty log. It must not be done.

## Recommendation

The correct fix is in `modules\TierModel\public\Write-TierModelLog.ps1`: the `Add-Content` (and
any `Set-Content`/`Out-File`) that writes the log file should carry `-WhatIf:$false`, for exactly
the same reason Deploy's directory creation now does. That file is outside my boundary for this
work item, so I am raising it rather than editing it.

Impact if left: a `-WhatIf` diagnostics run tells the operator where their log is, creates the
file, and leaves it empty. The transcript still captures the session, so the run is not
undiagnosable — but the log file is exactly the hollow-log failure class this feature exists to
prevent.

---

## RESOLVED 2026-09-05 — BUG-025 fixed in `Write-TierModelLog.ps1`

Joel released the `modules\**` boundary and located the write site. Fixed as specified, plus one
flagged extension.

**Confirmed before fixing:** no test in either suite asserts that `-WhatIf` suppresses logging.
The opposite precedent already exists — `Unit.MembershipReconciliation.Tests.ps1:581` and `:942`
assert **"WhatIf immunity"**: the sibling `Write-Log` in `optional\Update-TierModelMembership.ps1`
*must* write its file when `$WhatIfPreference = $true`. So this fix brings `Write-TierModelLog`
into line with an already-tested contract elsewhere in the product rather than inventing one.

**Two calls changed, both inside the `try` in the file-logging block:**
1. `Add-Content ... -WhatIf:$false` (the site Joel identified) — the only write in the function.
2. `New-Item ... -WhatIf:$false` on the log-directory creation immediately above it — **a
   deviation from "scope it to that call only", flagged deliberately.**

**Why (2), with evidence.** After fixing only the `Add-Content`, I ran a direct
`Write-TierModelLog -LogPath <new dir>\x.log` with `$WhatIfPreference = $true`:
```
What if: Performing the operation "Create Directory" ...
WARN: Failed to write to log file '...\freshdir\x.log': Could not find a part of the path ...
exists: False
```
The suppressed `New-Item` made the fixed `Add-Content` throw. Deploy and Audit are unaffected
because they now create their own log directory up front, but any other caller passing `-LogPath`
into a not-yet-existing directory still got no log. Same apparatus, same justification, one word.
It creates a **log directory** — it is not, and must not become, a write to Active Directory.

**On Joel's point 1 (companion `Test-Path` check): declined, deliberately.** The
"absence of an exception is not success" hazard existed *because* `-WhatIf` suppression is
silent. With `-WhatIf:$false` on the write, suppression can no longer happen, so every remaining
failure mode is a genuine exception that the existing `catch` reports honestly — proven above,
where the directory case produced a real, accurate warning. A `Test-Path` per log line would add
a filesystem stat to a hot path called thousands of times per run, to detect a condition that can
no longer occur. Not worth it.

**Verified at runtime, both directions:**
- `Deploy -WhatIf -Logging` → **0** suppressed `Add Content` messages, log file present with
  **7 entries**. Previously: no log file at all.
- Direct call into a non-existent directory under `$WhatIfPreference = $true` → directory
  created, file written, `exists: True`.
- Normal non-`-WhatIf` run → log file with 7 entries, unchanged.

Unit 1573/0, Integration 318/0.
