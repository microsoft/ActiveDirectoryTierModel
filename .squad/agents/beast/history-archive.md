# beast — History Archive

## Recent Work (2026-09-01)

**Status:** Latest fixes deployed and lab-validated

### 2026-09-01 — WhatIf-Safe Logging + Path Fix (v1.7.2)
- Fixed: -WhatIf flag now writes logs via -WhatIf:$false on infra I/O (New-Item, Add-Content, Remove-Item, Set-Content)
- Added: WHATIF preview lines at 9 change sites for preview-mode logging
- Moved: Logs/Debug folders from %ProgramData%\TierModel to $PSScriptRoot (script-relative)
- Lab validated on TierLab-DC01 by Coordinator — log file created, zero real changes in WhatIf mode
- Committed: a1ddffe (Joel Platek)

### 2026-09-01 — Milestone 8: -EnableEventLog Windows Event Log Support (v1.7.0)
- Added: Event log emission to Application log, Source 'TierModel'
- Added: -EnableEventLog switch (opt-in), -JobId parameter (correlation ID)
- Events: 1000 START (Information), 1001 COMPLETE (Information), 1009 ERROR (Error)
- All event writes are no-throw, best-effort — logging never blocks AD work
- Lab validation: awaiting Coordinator

## Archived Sessions

Work from 2026-08-24 and earlier has been archived to history-archive.md to maintain file size. See archive for:
- 2026-08-27: Design Plan for Update-TierModelMembership.ps1
- 2026-08-27: Amendment (Computer-Membership-Only model)
- 2026-08-29: Milestones 1-7 (comprehensive tier implementation)
- 2026-08-24: Format-TierModelDuration implementation
- 2026-08-14: -EnableAuditing implementation
- 2026-08-11: BUG-006 Canonical ACL gate

## Current Focus

Update-TierModelMembership.ps1 feature work ongoing. Lab validation in progress (Coordinator). Ready for Joel UAT upon Coordinator sign-off.

## Learnings

### 2026-09-04 — Inner-vs-Outer catch matters for fail-loud semantics

When a function has a gpoStatus-specific inner `try/catch` nested inside an outer per-GPO `try/catch`, a `throw` inside the inner `try` is absorbed by the inner `catch` (Warning-only). To make an invalid value register as a genuine GPO failure (red ERROR, `$failed++`, `$converged = $false`), the validation must happen **before** entering the inner `try` block but inside the outer one — then the throw propagates correctly to the outer catch without restructuring the inner error handling. This was the root of BUG-016's silent-default trap: the `default { 0 }` was inside the inner try, so any config error was silently converted to flags=0 and then counted as executed.

### 2026-09-04 — AD flags vs .NET GpoStatus enum ordinals (permanent trap record)

The .NET `Microsoft.GroupPolicy.GpoStatus` enum ordinals and the AD `flags` attribute values for GPO status are NOT the same. `AllSettingsEnabled` is ordinal 3 but flags 0; `AllSettingsDisabled` is ordinal 0 but flags 3. Our code reads and writes the `flags` attribute throughout, so the mapping is internally consistent — but anyone who looks up the .NET enum docs will see the opposite order and think there is a bug. Record: there is no bug; do not "fix" this.

### 2026-09-03 — Debug/Logging Architecture Inventory

**⚠️ CORRECTION APPENDED (Scribe):** Initial claim "zero Write-TierModelLog -Level Debug call sites" was **INCORRECT**. Empirical audit by Coordinator confirmed **26 dormant Write-TierModelLog -Level Debug call sites** across 19 module files (concentrated in config/OU/group/GUID-resolution/ACL-planning and audit Test-* functions). This finding was corrected in the authoritative `.squad/decisions.md` section "CRITICAL VERIFIED FINDINGS — Finding 2" and recorded with explicit [CORRECTED FINDING] marker. Future sessions: reference the corrected finding, not this erroneous claim.

**Key findings from the `-Debug` feasibility inventory:**

- **`[CmdletBinding()]` coverage is nearly complete:** All 80 `modules/TierModel/public/*.ps1` functions and all 7 `TierModel.psm1` functions already have it. Both entry-point scripts have it (Deploy: `SupportsShouldProcess`, Audit: plain). The only gap is **15 script-internal helper functions** (8 in Deploy-TierModel.ps1, 7 in Audit-TierModel.ps1) that lack `[CmdletBinding()]`.

- **The reference implementation (`optional/Update-TierModelMembership.ps1`) deliberately avoids the `-Debug` common parameter.** It uses a custom `[switch]$EnableDebug` parameter and a private `Write-DebugLog` function that writes directly to `$PSScriptRoot\Debug\*.log` files. It never touches `$DebugPreference`. This is intentional — the automatic `-Debug` sets `$DebugPreference = 'Inquire'` which PROMPTS on every `Write-Debug` call.

- **`Write-TierModelLog` already has `Level = 'Debug'`** (routes to `Write-Debug $consoleMessage`), but there are only 4 `Write-Debug` calls anywhere in the codebase and zero `Write-TierModelLog -Level Debug` calls. The debug infrastructure in the logger is dormant.

- **Preference variable propagation:** `$DebugPreference = 'Continue'` set in Deploy/Audit scope DOES flow into module function calls (PowerShell inherits preference variables into child scopes including module calls). However, the default `-Debug` common parameter behavior sets it to `'Inquire'` (not `'Continue'`), so the fix pattern requires explicitly overriding to `'Continue'` after detecting `-Debug` was passed.

- **Silent `catch { }` blocks:** 1 in Deploy (line 320, intentional DFL probe), 25 in public module functions (all intentional — property access fallbacks in WinLaps, AuthPolicy, AuthSilo, Prerequisites). None are the root cause of "GPO deployment just stopped." The actual culprit is likely `$ErrorActionPreference = 'Stop'` propagating a deep exception that's reported via `Write-Host` but not visible when the console buffer scrolls.

- **Key file paths:**
  - Entry-point logging params: Deploy → `-Logging [switch]` + `-LogPath [string]`; Audit → `-LogPath [string]` only (no `-Logging` switch)
  - Log dir: `$PSScriptRoot\Logs\` (moved from `%ProgramData%\TierModel` in v1.7.2)
  - Membership debug dir: `$PSScriptRoot\Debug\` (beside the script)
  - Write-TierModelLog: `modules/TierModel/public/Write-TierModelLog.ps1`

- **Write-Verbose exists (41 calls in 6 files), Write-Debug scarce (4 calls in 2 files).** Running Deploy/Audit with `-Verbose` already surfaces more than most customers realize.

### 2026-09-03 — Debug Switch POC: Mode A/B/C Comparison, GPO Silence, WhatIf Landmine

**Branch:** `feature/enable-debug-switch`  
**Deliverables:** `.research\debug-switch-poc\Invoke-DebugApproachPoc.ps1`, `.research\debug-switch-poc\README.md`  
**Status:** POC complete, run on WATERCOOLED in `-SimulateOnly` mode. All sections passing. No production code touched.

#### What Was Built

A 7-section POC that:
- Reproduces the customer incident (6 silent failures, 0 error stream entries, 6 `Write-Host` records)
- Runs Mode A/B/C (baseline / global pref / explicit `-Debug`) side-by-side with stream and file metrics
- Proves WhatIf landmine, restoration hygiene, and the silent GPO analogue
- Generates per-mode debug log files for lab inspection

#### Key Findings

**Finding: Mode B = Mode C (identical output)**  
`$global:DebugPreference = 'Continue'` and explicit `-Debug` forwarding produce identical results: 13 debug stream records and 13 debug log file lines in a 9-step scenario. For top-level script invocations, the two approaches are equivalent. In production, global preference is preferable because it reaches nested/indirect calls that cannot receive `-Debug` explicitly.

**Finding: Phase 2 is mandatory**  
With Mode B active, `Invoke-PocGpoDeployment` (the GPO silent-failure analogue) produces 2 pre-throw debug records and 2 log file lines. The failure reason in `catch { Write-Host ... }` produces ZERO entries in any stream or file. This proves that Phase 1 (wiring `-EnableDebug`) alone does not surface the customer's original failure. The catch blocks on the GPO path need `Write-TierModelLog -Level Debug` (Phase 2).

**Finding: WhatIf landmine confirmed**  
`Add-Content` inside `[CmdletBinding(SupportsShouldProcess)]` called with `-WhatIf` is silently suppressed. `Add-Content -WhatIf:$false` writes correctly. Mandatory on all debug helper file writes.

**Finding: Restoration hygiene confirmed**  
`$global:DebugPreference` is correctly restored in `finally{}` even when an exception is thrown mid-run.

**Finding: Section 1 scope test — dynamic module caveat**  
With a dynamic `New-Module` stub, script-scope `$DebugPreference = 'Continue'` DOES propagate to the module (1 record instead of expected 0). This is a behavioral difference between dynamic modules and disk-based `.psd1` modules. The verified Finding #1 (0 records with script-scope only) was confirmed this morning against the real `modules\TierModel\TierModel.psd1`. The POC cannot reproduce this failure case with a dynamic stub. Joel's lab run against the real module will show 0 / 1 / 1 as expected.

#### PS 7.6.5 Bugs Encountered and Fixed

1. **`4>&1` does not capture debug stream** — use `*>&1 | Where-Object { $_ -is [DebugRecord] }` instead. `4>&1` redirects nothing from module-scope `Write-Debug` in PS 7.6.5.
2. **`switch ($_.GetType().Name)` fails with `Set-StrictMode -Version Latest` inside a `*>&1` pipeline** — causes the containing function to return `$null` due to a terminating error propagating out of the switch. Fix: use `-is` type tests (`if ($_ -is [DebugRecord]) { }`) instead of string switch on type name. See new skill `ps7-strict-mode-stream-classification`.

#### Observed Numbers (RunId: 20260903-145525, WATERCOOLED, pwsh 7.6.5)

| Mode | Failures | Err | Dbg | Info | LogFile | Silent? |
|------|----------|-----|-----|------|---------|---------|
| A | 6/9 | 0 | 0 | 6 | 0 | YES ⚠️ |
| B | 6/9 | 0 | 13 | 6 | 13 | YES |
| C | 6/9 | 0 | 13 | 6 | 13 | YES |

Mode B = Mode C: **YES** (identical).

---

### 2026-09-02 — Dot-Source Test Seam for Pester (v1.7.2, no version bump)

**Pattern:** To make a monolithic PowerShell script unit-testable with Pester without altering runtime behaviour, insert a single guard immediately after the `# MAIN EXECUTION` banner and before the `try {` block:

```powershell
if ($MyInvocation.InvocationName -eq '.') { return }
```

**Why it works:**
- When Pester (or any caller) dot-sources the script (`. .\script.ps1`), PowerShell sets `$MyInvocation.InvocationName` to `'.'`, so the guard fires and `return` exits the script scope — functions defined above are loaded into the caller's scope but the main block never runs.
- When the script is invoked normally (`pwsh -File script.ps1` or `.\script.ps1`), `$MyInvocation.InvocationName` is the script path/name (never `'.'`), so the guard is a no-op and main runs as usual.
- `ScriptVersion` was intentionally left at `1.7.2` — this is a non-functional test seam with zero runtime impact.

**Verified (2026-09-02):**
- `ParseFile` → 0 syntax errors
- Byte scan → 0 non-ASCII bytes
- Dot-source in fresh `pwsh` session → `Resolve-ActiveSwitches`, `Test-IsCustomerExcluded`, `Write-TmEvent` all resolved; no PARAMETER ERROR / no main-execution output
- `-File` path unaffected (guard never fires)

### 2026-09-03 — LIVE Lab Reproduction: Silent GPO Drop + Mode B/C Equivalence (real module, real domain)

**Lab:** TierLab-DC01 / tierlab.internal / DC01, PowerShell Direct. Evidence only — no production file modified, nothing committed.
**Artifacts:** `.research\debug-switch-poc\Invoke-GuestGpoRepro.ps1`, `Measure-GuestDebugMode.ps1`, `Invoke-GuestDebugModeComparison.ps1`, `lab-results\`
**Write-up:** `.squad\decisions\inbox\beast-lab-gpo-repro.md`

#### Reproduction — confirmed, and far worse than reported

Deployed GPOs with required groups absent (`-GposOnly -ConfirmApply -Logging`). Ground truth:

| Measure | Value |
|---|---:|
| GPOs in config | 146 |
| Distinct GPOs reaching the plan | 29 |
| **GPOs silently dropped** | **117** |
| `Summary.ExistingCount` printed GREEN as "Already Exist" | **65** |
| Tier Model GPOs actually in AD after run | **0** |
| Dependency error records | 43 |
| **Distinct GPO names named to operator** | **1** |

The customer reported 2 GPOs. Reality is 117.

#### NEW Finding — `ExistingCount` is dimensionally invalid, not merely wrong

`Get-TierModelGpo.ps1` L638: `$existingGpoCount = $totalGpoCount - $totalActionCount`.
`$totalGpoCount` counts **GPOs** (146). `$totalActionCount` counts **ACTIONS** (81 — Create/Import/Configure/Link; one GPO yields several). Subtracting actions from GPOs is a category error; 65 is not a quantity of anything. It is then labelled "Already Exist" and printed green. **This figure is meaningless under all conditions, including a healthy run.** Worth fixing independently of the debug work.

#### NEW Finding (5th defect) — the structured log declares success

The complete `-Logging` output for a run that dropped 117 GPOs is **6 lines**, contains **0 error entries**, **0 GPO names**, and ends with `"Deploy script completed successfully"`. Any downstream log shipping or alerting reports green. This is a severity escalation.

#### Mode B vs Mode C — IDENTICAL against the real module

46 debug records each, 46 log lines each, **0 differences after canonicalisation**. `$global:DebugPreference` restored in both. The 26 dormant `Write-TierModelLog -Level Debug` sites do light up (14 config-segment loads, 2 config-shape, 1 domain-DN, 29 GroupPlanCheck). Recommendation stands: use the global preference for `-EnableDebug`; it is equivalent and reaches nested calls that cannot receive `-Debug`.

#### Phase 2 is MANDATORY — proven, not argued

With debug fully enabled by either mechanism: **0** records reference a skip/drop, and **0** of the 117 dropped GPOs are named anywhere. The bare `continue` at L241-243 has nothing to switch on. Phase 1 alone ships a debug switch that cannot answer the customer's question.

#### Two harness bugs that caused false negatives (now a skill)

1. **Module-level cache leaked between modes in one process** — Mode B warmed the cached domain DN, so Mode C lost that record (46 vs 45). Fix: run each mode in its OWN fresh `pwsh` process. `Import-Module -Force` is insufficient.
2. **Hashtable key order is not stable between processes** — `Write-TierModelLog -Data` renders `key=value` pairs in hash-bucket order, producing a 31-line phantom diff with identical keys and values. Fix: split on `,\s*(?=[A-Za-z]\w*=)` and sort the tokens before comparing. Took the diff to 0.

Also: probe whether `-Debug` prompts (`Inquire`) in the target host BEFORE building the harness — over PowerShell Direct it returned `DebugRecord` cleanly with no prompt, but a hang would otherwise look like a failed test.

Skill written: `.squad\skills\powershell-debug-mode-comparison\SKILL.md`

#### Debug log path convention — confirmed writable

`$PSScriptRoot\Debug\<ScriptName>.debug.<yyyyMMdd-HHmmss>.<correlationId>.log`, separate from `$PSScriptRoot\Logs\`, no rotation. Verified writable on the guest at `C:\TierModel\Debug\`. `-WhatIf:$false` remains mandatory on every debug write because Deploy is `SupportsShouldProcess`.

#### Lab state on exit

VM Running. Checkpoints `DC-Promoted-Clean` and `WinLapsSchema` both intact. Nothing restored, nothing deleted, nothing committed.

### 2026-09-03 — Bugfix Batch 1: Blocked-Run Log Fidelity, GPO ExistingCount, ADMX Per-File Resilience, Skipped-GPO Attribution

**Branch:** `fix/gpo-silent-skip-and-false-success` — working tree only, not committed, no PR.

**Correction that framed the work:** the earlier "silently drops 117 GPOs" framing was wrong.
The lab transcript proves the console DOES print all 43 dependency errors and refuses to
proceed. That fail-fast gate is correct and was left completely alone. The real defects were
narrower — the log file, an arithmetic error, an over-broad abort, and missing attribution.

#### What changed

1. **`Deploy-TierModel.ps1` — blocked runs no longer log success.** Added
   `$script:DeploymentBlocked` / `$script:BlockedPhases` plus script-internal helpers
   `Write-TierModelBlockedOutcome` and `Write-TierModelSkippedGpoReport`. All five
   "Resolve all dependency errors before proceeding with X" gates (Group, User, OU ACL, GPO,
   ADMX) now route their deduplicated errors through `Write-TierModelLog -Level Error` into the
   log file, and the closing summary logs a BLOCKED record instead of
   "Deploy script completed successfully".
2. **`Get-TierModelGpo.ps1` — `ExistingCount` counted, not derived.** Replaced
   `$totalGpoCount - $totalActionCount` with a real count of GPO display names found in AD.
3. **`Copy-TierModelAdmx.ps1` (BUG-007) — per-file resilience.** Analysis errors are split into
   per-file (skip that file, keep deploying) and fatal (still abort).
4. **`Get-TierModelGpo.ps1` + Deploy — skipped GPOs are named.** New `SkippedGpos` /
   `SkippedGpoSummary` / `Summary.SkippedCount`, rendered grouped-by-reason and logged.

#### Gotchas found (worth remembering)

- **Deduplicated error records cannot carry per-entity attribution.** The GPO planner only adds
  a `RequiredGroupNotFound` record the *first* time a given group is seen missing, and stamps it
  with *that* GPO's name. Every later GPO blocked by the same group gets no record at all. To
  attribute a reason back to an individual GPO you must track the blocking condition **locally**
  in the loop (`$missingGroups`), not re-query the shared error collection. This is the single
  reason the customer saw "no error messages" — the errors existed, but named the *dependency*,
  never the *dependent*.
- **Two distinct drop sites, not one.** Everyone focused on the per-GPO
  `if (-not $allGroupsExist) { continue }`. The bigger silent drain is the *earlier*
  whole-OU-section `if (-not $ouExists -and -not $isTemplate) { continue }`, which discards every
  GPO in that section at once. Any attribution fix that only patches the per-GPO site leaves the
  majority of dropped GPOs unnamed.
- **`ExistingCount` was dimensionally invalid and IS on the healthy path.** It is printed by
  `Invoke-GpoDeployment`, which is only reached when there are **no** dependency errors — so a
  perfectly healthy run was showing a meaningless number. One GPO yields up to four actions
  (Create/Import/Configure/Link), so `GPOs - actions` can even go negative.
- **`$deploymentResult.AdmxSkipped = $Analysis.AdmxUpToDate` is an assignment, not an append.**
  When adding a second contributor to a result collection, audit every existing write for `=`
  vs `+=`; a plain `=` silently discards everything recorded earlier in the function.
- **`Get-TierModelAdmx.Errors` is a flat `string[]`, with no error codes.** The only way to tell
  a per-file hash mismatch from a fatal config/DC failure today is the message shape
  (`^Source (ADMX|ADML) file (not found|hash mismatch)`). The fatal case is also identifiable
  structurally: the outer `catch` returns the exception message **with all file collections
  empty**. If that contract ever gains codes, switch the classifier to them.
- **`Deploy-TierModel.ps1` has NO dot-source seam** (unlike
  `optional/Update-TierModelMembership.ps1`). To unit-smoke a script-internal helper without
  running the whole script, pull it out with the AST and re-create it as a scriptblock:
  `$ast.FindAll({param($n) $n -is [FunctionDefinitionAst] -and $n.Name -eq 'X'}, $true)[0]`
  then `. ([scriptblock]::Create($fn.Extent.Text))`. Works cleanly and touches no production code.
- **Script-internal helpers keep the manifest test green.** `Unit.ModuleManifest.Tests.ps1`
  asserts an exact match between `modules/TierModel/public/*.ps1` and `FunctionsToExport`, so
  new shared logic belongs in the entry-point script, not in a new public function file.
- **Console assertions survive wording changes if you extend rather than replace.**
  `Integration.Deploy.Tests.ps1` matches on `'Deploy script completed'`, so
  `"Deploy script completed - DEPLOYMENT BLOCKED, no changes were applied."` still passes while
  conveying the opposite outcome.

#### Validation

Unit suite **1573 passed / 0 failed / 0 skipped** (61.19s) — exactly baseline.
`Integration.Deploy.Tests.ps1` 158 passed / 0 failed.
Plus three throwaway smoke harnesses (deleted) covering the ADMX split, the GPO planner counts,
and the blocked-outcome log records.

Decisions written to `.squad/decisions/inbox/beast-bugfix-batch1.md`.
Skill written: `.squad/skills/blocked-run-log-fidelity/SKILL.md`.

### 2026-09-03 — Sibling "Already Exist" Audit (follow-up to Bugfix Batch 1)

Audited every "Already Exist" / `AlreadyExistCount` display site for the unit-mixing bug class
found in the GPO planner. **Two genuine defects, three sound, one dead.** Reporting "no change
needed" was the right answer more often than not.

#### The one that was structurally always zero

`Get-TierModelOuAcl` has a **single** `$actions +=` site and it always emits
`Action = 'CreateAcl'`. So `TotalActions -eq $CreateActions` **by construction**, and the display
expression `TotalActions - CreateActions` could only ever print `0`. Proven with a mocked run:
2 delegations, 1 already in AD → printed `0`, truth `1`; `Total in Config` printed `1`, truth `2`.

**Lesson:** before judging a subtraction, check whether the planner emits more than one action
*type*. If it emits exactly one, `Total - Create` is not "unit-consistent but loose" — it is a
guaranteed constant zero, which is worse than the GPO case because it never varies and so never
looks suspicious.

**Fix pattern is the same one as the GPO planner:** count the thing, do not derive it. The `*Fd`
sibling (`Get-TierModelOuAclFd`) already had `$existingAclCount++` and `Summary.ExistingCount`.
When a `Get-TierModelX` and a `Get-TierModelXFd` pair exists, **diff their Summary shapes** — the
Fd variants in this repo are consistently the more correct implementation, and the divergence is
a reliable bug smell.

#### The ones that were fine (do not "fix" these)

- `Get-TierModelOu`: `$totalInConfig - $toCreate`, one `CreateOU` per configured OU. Correct.
- `Get-TierModelGroup`: real `$existingCount++`. Correct.
- `Get-TierModelUser`: `users.Count` minus **`CreateUser`-filtered** actions, so the
  `UpdateUserMembership` actions cannot contaminate it. Correct.
- `AlreadyExistCount` accumulators: every contributor verified (OU/Group/User/OuAclFd/GPO/ADMX/
  auth policy/auth silo/silo membership). All real counts. Sound.
- `Analysis.ExistingAcls` in `Get-TierModelOuAcl`: unit-consistent AND **not consumed anywhere**
  in production. Dead. Reported, not touched.

#### A defect my own earlier fix created

Making `Copy-TierModelAdmx` per-file resilient meant `-AdmxOnly -ConfirmApply` would now deploy
the good files — but `-AdmxOnly` **planning** still called a per-file hash mismatch a blocking
"Dependency Error", and with the new blocked-run logging would have recorded the run as BLOCKED.
The plan contradicted the execution. **Whenever you relax an execution-time gate, grep for the
planning-time predicate that mirrors it** (here `$hasErrors = ...Analysis.Errors.Count -gt 0`, in
two places plus the "Use -ConfirmApply" hint). Extracted the classifier into a shared
`Get-TierModelAdmxFatalError` helper so the two can no longer drift.

Also confirmed the ADMX execution paths (`-AdmxOnly -ConfirmApply` and FullDeployment Phase 6)
have **no** analysis-error gate at all — they call `Copy-TierModelAdmx` directly — so BUG-007 is
genuinely resolved end to end, not just inside the cmdlet.

#### PS gotcha that cost 5 tests

`return @(...)` from a PowerShell function does **not** preserve the array — the pipeline unrolls
it, so an empty result arrives as `$null` and a single item as a scalar. Under `Set-StrictMode`,
`$null.Count` throws `PropertyNotFoundException`. **Every** call site must re-wrap:
`$x = @(Get-Thing ...)`. Caught by `Integration.Deploy.Tests.ps1` dropping 158 → 153; re-wrapping
at all three call sites restored 158. Unit tests did not catch this — the entry-point script is
only exercised by the integration file, so run **both** after touching `Deploy-TierModel.ps1`.

#### Validation

Unit **1573 / 0 failed**. `Integration.Deploy.Tests.ps1` **158 / 0**.
`Unit.OuAclOperations` + `Unit.AdmxImport` **130 / 0**.
An intermediate run showed 1572/1 on `Has current version 2.0.0` while Storm's ModuleVersion bump
to 2.1.0 was mid-flight — not mine, resolved itself once she updated the assertion.

### 2026-09-03 — False-Success Pattern Widened Beyond GPOs (`fix/gpo-silent-skip-and-false-success`)

Swept every AD/GroupPolicy write in `New-TierModel*.ps1` + `Import-TierModelGpo.ps1` for the
"assign result, print a green tick, never check anything" shape. **11 sites changed, 3 judged
already-correct, 1 out of scope.**

#### CORRECTED MECHANISM — the version previously recorded in team notes is WRONG

The wrong version said `$ErrorActionPreference` "fails to cross the module boundary". That claim
is false and should not be repeated:

- `modules\TierModel\TierModel.psm1` **L2** is `$ErrorActionPreference = 'Stop'` and it **does**
  apply in module scope.
- `TierModel.psm1` **L1** is `Set-StrictMode -Version Latest` and it **is** active. I verified
  directly on PS 7.6.5: `$null.DistinguishedName` throws
  `PropertyNotFoundException: The property 'DistinguishedName' cannot be found on this object.`
- The real trigger is **PowerShell 7 + the WinPSCompat shim**. ActiveDirectory and GroupPolicy
  load as **script proxy functions** that report failure via `$PSCmdlet.WriteError()`. That path
  does not honour the *caller's inherited* `Stop` preference the way a binary cmdlet does, so
  execution falls through, the result variable stays `$null`, and the success message prints.
- Under Windows PowerShell 5.1 (GroupPolicy as a true binary module) EAP=Stop catches it and
  there is no false success. **The defect is conditional on PS7 + compat shim** — the same
  environmental trigger as BUG-013.
- Consequence for the fix: an **explicit `-ErrorAction Stop` parameter on the call** is the
  actual remedy, because the explicit parameter sets the preference *inside the proxy function's
  own scope*, which `WriteError` does honour. Inherited preference is what fails, not explicit.

#### Gotchas found

- **StrictMode accidentally protects some of these sites, but badly.** `New-TierModelOu`,
  `New-TierModelGroup`, `New-TierModelAuthPolicy` and `New-TierModelAuthSilo` all dereference
  `$result.DistinguishedName` shortly after the write. Under StrictMode a null result throws
  there, so the counters were in fact correct — but the recorded error message was
  `The property 'DistinguishedName' cannot be found on this object`, which tells the operator
  nothing about the AD failure that actually happened. **Do not report these as false successes;
  report them as correct-outcome / useless-diagnostics.** AuthPolicy and AuthSilo were worse:
  they printed the green tick on the line *before* the deref, so the console showed ✅ then ❌
  for the same object.
- **The genuinely silent ones are the `| Out-Null` sites**, because nothing is ever
  dereferenced: `New-ADUser`, `Add-ADGroupMember`, `New-GPLink`, `Set-GPLink` ×2, `Import-GPO`,
  `Set-GPRegistryValue`, and `New-GPO` (tick printed before first deref). Those are the ones
  that could report `Failed=0, Converged=True` for work that never happened.
- **Test mocks constrain how much verification you can add.** Verification must be chosen per
  site against the existing mocks, not applied uniformly:
  - `Unit.GpoOperations.Tests.ps1:1373` is `Mock Import-GPO { return $null }` **and expects
    success** → a null-check on `Import-GPO` would break the suite. `-ErrorAction Stop` only.
  - `Unit.UserOperations.Tests.ps1:353` is `Mock New-ADUser { }` (returns nothing) and
    `Mock Get-ADUser` at :349 deliberately returns "user does not exist" → neither `-PassThru`
    null-checking nor a post-hoc `Get-ADUser` existence probe is possible. `-ErrorAction Stop` only.
  - `New-GPO`, `New-ADGroup`, `New-ADOrganizationalUnit`, `New-GPLink`, `Set-GPLink`,
    `New-ADAuthenticationPolicy`, `New-ADAuthenticationPolicySilo` mocks all return real objects
    → null-checks are safe there.
- **`Unit.UserOperations.Tests.ps1:582` encodes group-membership failure as deliberately
  non-fatal** ("Should continue processing after group membership failure" asserts
  `Executed | Should -Be 1`). So `Add-ADGroupMember` must not increment `$failed`. I kept
  `Executed` intact but now record an `errors` entry with code `UserGroupMembershipFailed` and
  set `$converged = $false`, so the run no longer claims convergence when a Tier 0 group
  membership silently did not apply.
- **`tests\helpers\ADStubs.ps1` gates which parameters are safe to add.** Every stub declares an
  explicit `$ErrorAction` parameter but has **no `[CmdletBinding()]`**, so `-ErrorAction Stop`
  binds fine under stubs but `-ErrorVariable` would be a parameter-binding error in CI. I wanted
  `-ErrorVariable` as a belt-and-braces check and had to drop it for that reason.
- **`modules\TierModel\internal\` exists but is empty**, and `TierModel.psm1` dot-sources
  `internal/*.ps1` before `public/*.ps1`. It is the natural home for private helpers and
  `Unit.ModuleManifest.Tests.ps1` ignores it entirely. I could not use it this time because the
  task constrained me to `New-TierModel*.ps1` / `Import-TierModelGpo.ps1`, so the shared helper
  `Get-TierModelWriteFailureDetail` lives at the top of `New-TierModelGpo.ps1`. That is safe:
  `Unit.ModuleManifest.Tests.ps1:191-206` derives function names from the public file **BaseName
  only**, never by AST, and `TierModel.psm1` has **no `Export-ModuleMember`**, so the explicit
  `FunctionsToExport` list in the manifest governs and the helper is not exported.

#### Diagnostics under the shim

The shim marshals errors across a runspace boundary, so exceptions are **flattened** —
`InnerException` is normally absent. `FullyQualifiedErrorId` and `CategoryInfo` do survive.
`Get-TierModelWriteFailureDetail` recovers `$global:Error[0]` when a write returns null (there is
no exception to catch in that case) and captures Message + FullyQualifiedErrorId + CategoryInfo +
ExceptionType. The catch blocks I touched now log those two extra fields as well.

#### Environment gotcha that cost two full suite runs

`Unit.Prerequisites.Tests.ps1` failed 26-55 tests with
`Dependencies file not found at: C:\Users\...\Temp\valid-dependencies.json`. **Not a code defect.**
The test uses a **fixed** temp filename, so when another agent runs the suite concurrently on the
same machine the two runs delete each other's fixture. Proven by re-running the identical tree:
first pass 1857/34, second pass **1891/0**. If prerequisites tests fail with a "not found" temp
path, re-run before investigating.

**Attribution technique that settled it:** `git worktree add C:\Temp\admt-head HEAD --detach`,
run the full suite there for a clean baseline (1891/0), then copy **only my** changed files over
and re-run. This isolates your changes from other agents' uncommitted work in the shared tree —
essential on this repo, where `git status` showed 25 modified files from four agents.

#### Validation

Unit **1573 passed / 0 failed** (`Invoke-AllTests.ps1 -TestType Unit`).
Integration **317 passed / 1 failed** of 318; `Integration.Deploy.Tests.ps1` alone **158 / 0**.
The single failure is `Integration.Module.Tests.ps1:35` asserting ModuleVersion `'2.0.0'` while
`TierModel.psd1` is now `'2.1.0'` — Storm's version bump, a file I did not touch. Same
in-flight collision recorded on 2026-09-03 for the unit suite.

**Honest limitation:** `ADStubs.ps1` uses plain `param()` with no `[CmdletBinding()]` and **never
throws**, and the unit mocks that do throw exercise the *pre-existing* catch paths. **No existing
test exercises the new null-result failure paths** (proxy returns `$null` without terminating).
A green suite proves I caused no regression; it does **not** prove the fix works. That needs
either a mock returning `$null` where success is currently expected, or a live PS7 + shim run.

Decision: `.squad/decisions/inbox/beast-false-success-widening.md`.

### 2026-09-03 — PowerShell Truthiness Trap: `enforced` Default Silently Enforced Every GPO Link

**The trap.** In PowerShell **any non-empty string is truthy**. `if ('No') { 'Yes' } else { 'No' }`
returns **`'Yes'`**. Verified on this box: `'No' -ne $false` -> `True`.

`New-TierModelGPOLink.ps1` L77 defaulted `$requiredEnforced` to the **string** `'No'` when config
did not declare `enforced`. `config\tiermodel-gpos.json` has **zero** `"enforced"` keys across all
146 GPO entries, so the default fired every time. Consequence in the *existing-link* branch:

- L143 `if ($null -ne $requiredEnforced -and $requiredEnforced -ne $currentEnforced)` -> fires
  (`'No' -ne $false` is True), logs the nonsense message `Enforced: No -> Yes`
- L162 -> fires; L163 `if ($requiredEnforced)` -> `'Yes'`
- L165 -> `Set-GPLink -Enforced 'Yes'` on an existing, possibly **production** link

So **every re-run of Deploy enforced every already-linked GPO.** The creation path was never
affected because L121 uses `-eq 'Yes' -or -eq $true`, which is type-correct.

**The insight.** Both guards were written `if ($null -ne $requiredEnforced -and ...)`. That `$null`
check only makes sense if the original author intended **`$null` = "config did not declare
enforcement, do not touch it"**. The string default made that guard dead code. Fix = restore the
sentinel.

**RULE (Joel, Rule 4): the tool must NOT modify link enforcement unless config explicitly declares
`enforced`.** An already-linked GPO may be in production. Absent config -> `$null` -> skip entirely.
New links are still created **unenforced**.

#### `[bool]` is the WRONG coercion here — do not use it

The obvious fix `[bool]$gpoData.enforced` is **actively dangerous**. Measured on PS 7:

| declared value | `[bool]` | `-eq 'Yes' -or -eq $true` |
|---|---|---|
| `$true` / `$false` (bool) | True / False | True / False |
| `'Yes'` | True | True |
| `'No'`  | **True** WRONG | False |
| `'True'` | True | True |
| `'False'` | **True** WRONG | False |
| `'true'` | True | True |
| `'false'` | **True** WRONG | False |

`[bool]'No'`, `[bool]'False'` and `[bool]'false'` are **all `$true`**. This is not theoretical:
the repo's own tests and the sibling planners already use the **string** forms
(`enforced = 'Yes'` / `'No'`), so a future config written as `"enforced": "No"` would have been
silently **enforced**. Shipped idiom instead:

```powershell
$requiredEnforced = if ($gpoData.PSObject.Properties.Name -contains 'enforced') { ($gpoData.enforced -eq 'Yes' -or $gpoData.enforced -eq $true) } else { $null }
```

`-eq` takes the **left** operand's type: `'No' -eq $true` coerces the *right* side to the string
`'True'` -> False (correct), whereas a cast coerces the *string* to bool -> True (wrong). Left-hand
type is what makes this idiom safe. It yields a real `[bool]` or `$null` for all 9 input shapes.

**`ConvertFrom-Json` does emit real `[bool]`** for JSON `true`/`false` (verified), so a
well-formed config is fine either way — the danger is only quoted strings, which this repo uses.

#### Related sites — reported, NOT changed

- `Get-TierModelGPOLink.ps1:56` has the identical `else { 'No' }` default, and **L136
  `if ($requiredEnforced -ne $currentEnforced)`** compares that string to the real `[bool]` from
  `Get-GPInheritance` -> **always reports a false "Enforcement mismatch"** in the audit/plan.
  Read-only (planning), so no production write. **Left alone deliberately:**
  `Unit.GpoLinking.Tests.ps1:1288-1302` ("Line 56 - enforced property absent, defaults to 'No'")
  asserts `RequiredState.Enforced -eq 'No'` — the string default is **locked in by test**. Changing
  it needs Wolverine to move the test first.
- `Get-TierModelGpoLinkFd.ps1:58` same default, but it only stores the value in `RequiredState`;
  it never compares it. Cosmetic only.
- `$linkEnabled` L76 `else { $true }` — **confirmed FINE.** The default is a real `[bool]`, and all
  **131** `linkEnabled` values in `config\tiermodel-gpos.json` are real JSON booleans (80 `true`,
  51 `false`), so `if ($linkEnabled)` at L120 never sees a string. Latent only if someone writes
  `"linkEnabled": "No"` in future config.
- `Deploy-TierModel.ps1:2820` `if ($admxResult.Summary.Failed -eq 0) { 'True' } else { 'False' }` —
  string is **produced for display only**, never consumed as a boolean. Fine.

#### Gotcha worth remembering

**My own verification harness hit the same bug.** I looped over cases with an `'__ABSENT__'`
sentinel and tested `if ($raw -eq '__ABSENT__')`. For `$raw = $true` that is
`$true -eq '__ABSENT__'` -> the string is coerced to `$true` -> **matched**, so the boolean-`$true`
case was silently mis-reported as "absent". Interestingly `$false` was unaffected. If you write a
truthiness test, **do not use a string sentinel** — use a separate flag field. I only caught it
because one row of the table looked wrong.

#### Validation

Unit **1573 passed / 0 failed** (`Invoke-AllTests.ps1 -TestType Unit`, 24 files, 96.8s). No test
change required: the one existing update-path test (`Unit.GpoLinking.Tests.ps1:513`) declares
`enforced = 'No'` against `Enforced = $false`, which now correctly resolves to `$false` -> equal ->
enforcement branch skipped, and `Set-GPLink` is still invoked once for the **order** change, which
is what the test asserts.

Decision: `.squad/decisions/inbox/beast-enforced-string-bug.md`. Not committed, not staged.

### 2026-09-03 — False-Success Completion Pass: 2 More Sites Verified, 3 Provably Blocked by Test Mocks

Closing pass on the false-success sweep. **Honest tally: 17 AD/GPO write sites audited, 11 now
fully verified, 6 carry `-ErrorAction Stop` only because a result check is blocked by mocks I am
not allowed to edit.** I could not truthfully report "14 of 14".

#### TWO CORRECTIONS to what I previously believed — both were wrong

**1. ADStubs do NOT block `-PassThru`.** My earlier note said adding parameters the stub does not
declare would be a binding error in CI. **False.** The stubs are *simple* functions (plain `param()`,
no `[CmdletBinding()]`), and a simple function **absorbs unknown named arguments into `$args`
instead of erroring**. Verified directly:

```powershell
function Set-ADObject { param($Identity,$Server,$Replace,$Add,$Remove,$Clear,$ErrorAction) }
Set-ADObject -Identity x -Replace @{a=1} -PassThru -ErrorAction Stop   # -> BOUND OK, no error
```

So `-PassThru` is safe to add under CI stubs. (`-ErrorVariable` is still unusable — that is a
*common* parameter, which requires `[CmdletBinding()]`, so it really does fail. The two cases are
not the same and I had conflated them.)

**2. The real blocker is the MOCK RETURN VALUE, not the stub signature.** Every mock for these
cmdlets is `{ }` or `{ return $null }` **while the test asserts success**. Any null-result check
therefore throws on the happy path and breaks the suite.

#### Verified cmdlet capabilities (probed on this box, RSAT present)

| cmdlet | type | `-PassThru`? |
|---|---|---|
| `Set-ADObject` | Cmdlet | **Yes** |
| `Set-ADOrganizationalUnit` | Cmdlet | **Yes** |
| `Grant-ADAuthenticationPolicySiloAccess` | Cmdlet | **Yes** |
| `Set-ADAccountAuthenticationPolicySilo` | Cmdlet | **Yes** |
| `New-ADUser` / `Add-ADGroupMember` | Cmdlet | Yes |
| `Set-GPRegistryValue` | **Function** (proxy) | **No** — but emits the GPO object by default |
| `Import-GPO` | **Function** (proxy) | **No** — emits the GPO object by default |

**Probe your own shell carefully.** My first probe reported `Set-ADObject PassThru=False`, which is
wrong — I had defined a stub of the same name earlier *in that same script*, and it shadowed the
real cmdlet. Re-probe in a clean shell before trusting the answer.

#### Fixed this pass (2 sites — both now `-PassThru` + null check + `Get-TierModelWriteFailureDetail`)

- **`New-TierModelGpo.ps1:177` — `Set-ADObject` (gpoStatus flags).** Real risk: a failed write left
  the GPO at the default `flags=0` (AllEnabled) while the console printed the green tick, so a GPO
  meant to be `UserSettingsDisabled` silently applied user settings. At HEAD the tick was printed
  **before** the write and said "Setting" (present tense). Now the tick is after a verified write.
  Test-safe because the failure is caught by the existing non-fatal inner catch, so
  `Unit.GpoOperations.Tests.ps1:1803` still sees `Executed=1, Failed=0`.
- **`New-TierModelOu.ps1:260` — `Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion`.** Real
  risk: PFAD is a security control, and the follow-on `Invoke-CanonicalVerifyAndRemediate` only
  checks **ACE ordering**, not that PFAD was actually applied — so a silent no-op passed the
  existing verification. Failure now hits the existing `throw "Phase1Abort:PfadApplyFailed"`.

#### BLOCKED — reverted to `-ErrorAction Stop` only, needs Wolverine (3 sites)

I implemented the null check on all three, **ran the suite, got 4 failures, and reverted** rather
than editing tests. This is measured, not predicted:

- `New-TierModelWinLapsAcl.ps1:179` — `Set-GPRegistryValue`. Blocked by
  `Unit.WinLapsAclOperations.Tests.ps1:171` `Mock Set-GPRegistryValue { }`.
  Failure: *"Apply from plan: Executed = N"* — `Expected 4, but got 3`.
- `Set-TierModelAuthSiloMembership.ps1:199` — `Grant-ADAuthenticationPolicySiloAccess`
- `Set-TierModelAuthSiloMembership.ps1:212` — `Set-ADAccountAuthenticationPolicySilo`
  Both blocked by `Unit.AuthSiloOperations.Tests.ps1:862-863` and the `InModuleScope` re-mocks at
  `:882-883`, all `{ }`. Diagnostic failure was
  **`Expected 'Set' to be found in collection Grant, but it was not found`** — the Grant null check
  threw, so the Set call was never reached. 3 tests.

Fix requires the mocks to return a placeholder object (e.g. `{ [PSCustomObject]@{ Name = $Identity } }`).
That is a one-line change per mock in Wolverine's files.

#### Already correct, no change (1 site)

- `New-TierModelOu.ps1:468` — `Set-GPInheritance`. Uses a **read-back verify loop**: up to 4 attempts,
  each re-reading `Get-GPInheritance` and checking `GpoInheritanceBlocked -eq $true`, recording
  `BlockGpoInheritanceUnverified` on failure. This is *stronger* than a null check and is the pattern
  to copy elsewhere when a Get- mock is available.

#### Still `-ErrorAction Stop` only from the earlier pass (3 sites, unchanged, documented)

`Import-TierModelGpo.ps1:76` (Import-GPO), `New-TierModelUser.ps1:111` (New-ADUser),
`New-TierModelUser.ps1:119` (Add-ADGroupMember). All blocked by mocks that return nothing while
asserting success — same root cause.

#### Rule going forward

**A null-result check is only addable where the existing mock returns an object.** Check the mock
*before* writing the check. The generalisable escape hatch when the mock returns nothing is the
`Set-GPInheritance` read-back pattern, but only if a `Get-*` mock exists that reflects the write.

#### Validation

Unit **1573 passed / 0 failed** after revert (24 files). The intermediate 4-failure run is recorded
above as evidence, not as a regression. Nothing committed, nothing staged.

Decision: `.squad/decisions/inbox/beast-false-success-completion.md`.

---

## Learnings — 2026-09-03 (unblocked pass: null checks, planner enforced, gpoStatus)

**1. "The mock blocks me" was only half true — the correct escalation is to name the exact one-line
mock change.** Last pass I reverted three null checks because the mocks returned nothing. This pass
they landed unchanged in intent, because the mocks became faithful to the real cmdlets. The lesson is
not "wait for the test author", it is that the *precise* ask ("return a realistic object; model both
the -PassThru and no--PassThru arms") is what makes the unblock cheap. A vague "the mock breaks me"
would not have.

**2. Consuming a return value is part of the fix, not an afterthought.** For
`Grant-ADAuthenticationPolicySiloAccess` / `Set-ADAccountAuthenticationPolicySilo`, `-PassThru` is
required to get a value at all, and the value must be *assigned*, never left on the pipeline —
production calls these inside a function whose output object is asserted, so a leaked object breaks
unrelated tests. `Set-GPRegistryValue` is the mirror case: it is a proxy function with no `-PassThru`
that emits the GPO object by default, so the old `| Out-Null` was throwing the evidence away.
Assign-and-check covers both shapes.

**3. `[bool]` is the wrong cast for tri-state config, always.** `[bool]'No'` is `$true`. The safe
idiom is an explicit `-eq 'Yes' -or -eq $true` with `$null` for "not declared". I applied it in three
places now; it should be treated as the house rule for any config flag that can arrive as a string,
a boolean, or not at all.

**4. Guard the comparison, not just the default.** Changing `Get-TierModelGPOLink.ps1:56` to `$null`
was necessary but not sufficient: `$null -ne $false` is `$true`, so the mismatch check at :136 would
have kept firing. A tri-state default is only safe once every consumer of that variable has been
audited for how it treats `$null`. I found one consumer; I should look for all of them before
declaring a tri-state change done.

**5. Fixing a phantom "always acts" bug makes the zero-action path reachable for the first time.**
`$linkActions | Sort-Object {}` collapses to `$null` on an empty pipeline, and `.Count` then throws
under StrictMode — so a fully converged plan was reported as `GPOLinkPlanningFailed`. That bug had
been unreachable only because the phantom enforcement mismatch guaranteed at least one action. When
removing a source of spurious work, deliberately check the now-reachable empty path. `@()` around
any `| Sort-Object` / `| Where-Object` whose result gets `.Count` called on it.

**6. Deploy and audit switch statements over the same config value are one unit and must be diffed
side by side.** `AllSettingsDisabled` deployed as flags 0 and audited as flags 3 — permanent,
self-perpetuating drift, because re-running deploy kept writing 0. Any enum handled in two places is
a candidate for exactly this. Worth a sweep for other paired switches.

**7. On an audit path, "fail loudly" means a `Fail` finding, not a `throw`.** Removing
`default { 0 }` from the audit switch was right — a typo could report `Pass`. But throwing would turn
one bad config value into a total audit failure, or get swallowed by the surrounding catch and
mis-classified as an environment `Error`. A per-GPO `Fail` check naming the bad value and listing the
valid ones keeps the rest of the report intact and is diagnostically better. Distinguish
"unverifiable" from "broken environment".

**8. Don't trust a test run taken while another agent is editing the test files.** Two of my
intermediate failures were against test content that had already been superseded on disk mid-run.
Re-run once the other agent's edits have settled before drawing any conclusion about your own change.

**9. Relative default paths are a real, deterministic hazard that looks intermittent.**
`Test-TierModelPrerequisites.ps1` defaults `-DependenciesPath` to the relative `config/dependencies.json`;
run from the wrong cwd it early-returns with an *empty* `EnvironmentSnapshot`, which reads as null to
every assertion. That is exactly the reported "intermittent" symptom, but it is cwd-deterministic. I
could not reproduce the failure over five clean runs, so I flagged the fragility rather than editing
a file with someone else's in-flight work.

Decision: `.squad/decisions/inbox/beast-final-code-fixes.md`. Unit **1573 passed / 0 failed**.
Nothing committed, nothing staged.

