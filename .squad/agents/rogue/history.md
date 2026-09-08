# Rogue — Core Developer History

## 2026-09-04 | BUG-023 — Test-TierModelConfig -Config silently skips schema validation

**Branch:** `fix/gpo-silent-skip-and-false-success`  
**Requested by:** Joel Platek (@VAsHachiRoku)

### Problem
`Test-TierModelConfig` in `modules\TierModel\TierModel.psm1` had its entire schema validation block gated by:
```powershell
if ($PSCmdlet.ParameterSetName -eq 'FromPath' -and $schema) {
```
This meant `FromConfig` calls (used by both `Deploy-TierModel.ps1` and `Audit-TierModel.ps1`) skipped ALL schema validation — missing required properties, invalid array items, bad version strings — returning `Valid=True` when the config was broken.

### Fix (surgical — 2 changes to TierModel.psm1)

**Change 1:** In the `else` branch (i.e., when `FromConfig`), explicitly resolve and load the schema before reaching the validation gate. The schema path is computed using the same `$PSScriptRoot`-anchored expression used by `FromPath`'s default. If the schema file is missing or unparseable, the function returns `Valid=False` with a clear error — never silently skips.

**Change 2:** Changed the gate from `if ($PSCmdlet.ParameterSetName -eq 'FromPath' -and $schema)` to `if ($schema)`. Both parameter sets now reach schema validation identically.

### Key design decisions
- `$SchemaPath` param is `FromPath`-only, so the `FromConfig` branch uses an explicitly computed local variable `$schemaPathForConfig`.
- Missing/unparseable schema in `FromConfig` → hard `Valid=False` return, not silent skip. This is intentional and matches the defect class this branch targets.
- `Get-TierModelConfig` adds runtime properties (`ConfigHash`, `LoadedAt`, `ConfigPath`) — no false positives because the validator only checks `required` fields, not extra properties.

### Verification results

| Check | Result |
|-------|--------|
| Negative test (`-Config` with broken OU missing `name`) | ✅ `Valid=False, Errors=1` — matches `-Path` |
| Customer safety gate: 7 scopes via `-Config` | ✅ All `Valid=True, Errors=0` |
| `FromPath` unchanged | ✅ Same errors as pre-change |
| Module imports cleanly | ✅ No parse errors |
| Unit test suite | **1572 passed / 1 failed** (baseline: 1573/0) |

### Test damage (Wolverine to fix)
1 test broken: `Test-TierModelConfig.GPO mode validation.accepts createAndImport and createImportAndConfigure modes`  
This test used `Test-TierModelConfig -Config` with a fixture that now correctly triggers schema validation where it previously skipped it. The fixture needs updating to match the real schema shape.

### Lessons learned
- PowerShell does NOT populate default values for parameters that are not in the active parameter set. Always resolve such paths explicitly in the other set's branch.
- When fixing a "silent skip" bug class, the repair must surface schema-load failures as hard errors — the original defect was silent, the fix must be loud.
- `$c.Output.Verbosity = 'None'` suppresses Pester output but WhatIf messages from module code (stream 1) still emit and flood the shell; use NUnit XML export to read summary counts reliably.

---

## 2026-09-05 | BUG-019 — read-path `-ErrorAction` gap

**Branch:** `feature/enable-verbose-debug`
**Requested by:** Joel Platek

### What I changed
33 AD/GroupPolicy **read** call sites hardened with explicit `-ErrorAction Stop` plus per-site
`try/catch` that distinguishes "object does not exist" from "the read failed". 26 deliberate
`SilentlyContinue` sites annotated (behaviour untouched). Write path (22/22 already `Stop`) not
touched. `Deploy-TierModel.ps1`, `Audit-TierModel.ps1`, `tests\**` and `CHANGELOG.md` not touched.

### AST audit (85 files, 0 parse errors, `System.Management.Automation.Language.Parser`)

| Path  | Total | Stop (before → after) | SilentlyContinue | None (before → after) |
|-------|------:|----------------------:|-----------------:|----------------------:|
| Write | 22    | 22 → 22               | 0                | 0 → 0                 |
| Read  | 191   | 128 → 161             | 26               | 37 → 4                |

Test results: **Unit 1573 passed / 0 failed**, **Integration 318 passed / 0 failed** (baseline matched).

## Learnings

- **The audit''s "37" contains 2 false positives.** `Get-GpoActionsForConfig` (a *local nested
  function* inside `Get-TierModelGpoFd.ps1`) matches a `Get-GP*` noun pattern and was counted as a
  GroupPolicy cmdlet. It is not one, and it has **no `[CmdletBinding()]`**. The real BUG-019
  population is **35**, of which 33 are in Rogue-owned files. Anyone re-running the audit should
  expect a floor of 4 "None", not 0.

- **Write-path count is 21 or 22 depending on verb list.** `New|Set|Remove|Add` alone gives 20;
  adding `Import-GPO` and `Grant-ADAuthenticationPolicySiloAccess` gives 22. The documented 21
  included exactly one of those two. Irrelevant to the fix — write "None" is 0 under every
  variant — but it will keep re-surfacing unless the verb list is written down.

- **Simple functions DO accept `-ErrorAction` and silently ignore it.** I expected
  "A parameter cannot be found" from the stubs in `tests\helpers\ADStubs.ps1` — `Get-ADDomain`,
  `Get-ADRootDSE` and `Get-GPInheritance` have **no** `$ErrorAction` in their `param()` and no
  `[CmdletBinding()]`. Verified empirically, including under a real Pester `Mock`: it binds fine.
  So adding `-ErrorAction Stop` is stub-safe — but it is also **inert** in unit tests, so a green
  suite proves nothing about the catch blocks. Lab validation is still required.

- **A failing test was right and my fix was wrong.** `Unit.GpoOperations.Tests.ps1:2262`
  ("Falls back gracefully when Get-GPO -All throws during rename search") mocks a *generic*
  `throw "AD connection error"` and asserts a `CreateGPO` action is still planned. My first
  attempt escalated that read failure to a `throw`. The suite caught it. I changed the code, not
  the test. The contract is **log-then-continue**, exactly as Joel warned.

- **`-ErrorAction Stop` alone is a no-op if the catch is the only consumer.** Several sites already
  had a perfectly good `try/catch` (`Resolve-TierModelDomainDN`, `Test-TierModelOu`'s inheritance
  check) that simply never fired, because the error was non-terminating. Adding the parameter was
  the whole fix; no restructuring needed. Conversely, several sites had *no* catch and a `$null`
  return silently produced a **false audit verdict** — `Test-TierModelOu` reported
  "Not Protected" / "Not Blocked" for OUs whose state was never actually read.

- **Not-found does not always arrive as an exception.** `Get-GPO -All` and `Get-ADObject -Filter`
  return an *empty result set* when nothing matches. Their catch blocks are therefore reached
  ONLY on genuine read failure — which makes them safe to harden without touching not-found flow.
  `Get-GPO -Name` / `Get-ADObject -Identity` are the opposite. Classifying each site by this
  distinction is what made the "individual judgement" tractable.

- **Type literals are a load-order trap.** `[Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]`
  as a type literal fails to resolve when the ActiveDirectory module is not loaded (i.e. in the
  stubbed test environment). I matched on `$_.Exception.GetType().FullName -like '*ADIdentityNotFoundException'`
  instead. Use the string form in this codebase.

- **`"$iif ("` interpolates as `$iif`.** Cost me one bad patch and a restore-from-backup. Use
  `"${i}if ("` when a variable is immediately followed by identifier characters.

---

## 2026-09-05 | Audit-TierModel.ps1 — WI-11, WI-12, BUG-019 L620

Requested by Joel Platek. Branch `feature/enable-verbose-debug`. Not committed.

**WI-11** — added `[switch]$EnableVerbose` / `[switch]$EnableDebug` to the `param()` block under a
`# --- Diagnostics ---` banner, last, after `-LogPath`. Declaration only; no transcript or
preference wiring (WI-13..WI-16 are gated on Cyclops's POCs).

**WI-12** — added the `-Logging` switch and closed the hollow-log gap. Five edits, mirroring
`Deploy-TierModel.ps1` verbatim: `.PARAMETER Logging` help; `[switch]$Logging` immediately before
`-LogPath`; the log-path init block (`"$OutputFileBase-MMddyy-HHmm.log"`, same convention as
Deploy); `-PassThru` on the import plus the module-scope `Initialize-TierModelLogging` call and two
start-of-run entries; and the end-of-run "TierModel audit completed" entry carrying
`TotalChecked`/`DriftCount`.

**BUG-019 L620** (now L695) — `$domainDn = (Get-ADDomain -Server $DomainController).DistinguishedName`
gained `-ErrorAction Stop`, a try/catch, and an empty-string guard. Chose **hard-stop (throw)**, not
log-then-continue. See the decision record.

AST audit after: Write 22 total / 22 Stop / 0 None. Read 196 total / 162 Stop / 26 SilentlyContinue
/ **8 None** — all 8 are local nested functions (`Invoke-GpoAudit`, `Invoke-GpoDeployment`,
`Get-GpoActionsForConfig`, `Resolve-ADPrincipalSid`) that a `GP*`/`AD*` noun pattern false-positives
on, plus `optional\Redirect-DefaultContainers.ps1:46` which is outside my ownership. The Audit
`Get-ADDomain` site is gone from the None column.

0 parse errors. **Unit 1573 passed / 0 failed**, **Integration 318 passed / 0 failed**.

## Learnings

- **Neither suite touches the `-Logging` wiring, so I proved it out of band.** No Unit or
  Integration test constructs Audit's `-Logging` path, so a green run says nothing about WI-12. I
  ran a standalone harness in `$env:TEMP`: import with `-PassThru`, `& $module { param($p)
  Initialize-TierModelLogging -LogFilePath $p } $path`, then raise a `Write-TierModelLog -Level
  Error` **inside module scope with no `-LogPath`**. With the init the entry lands on disk; a
  control run without it creates **no file at all**. That control is the whole justification for
  WI-12 — reproduce it rather than trusting the diff.

- **`Write-TierModelLog -Level 'Error'` uses `Write-Host`, not `Write-Error`** (deliberate, per the
  comment at `Write-TierModelLog.ps1` L~93: "avoid ErrorRecord objects in pipeline"). This matters
  because Audit sets `$ErrorActionPreference = 'Stop'`: a log-then-throw block is safe, the log call
  will never pre-empt the `throw` with a different error. Do not "fix" it to `Write-Error`.

- **A `throw` from inside an Audit phase function is contained, not fatal.** Both callers of
  `Invoke-CanonicalAclAudit` (Phase 1b, and the `-OuOnly` Canonical ACL Check) wrap it in
  `try/catch` that warns with `$_.Exception.Message` and continues to the next phase. So throwing
  gives Joel exactly what he asked for — fail loudly — while still honouring decisions.md §3 (Audit
  warns and keeps going). **Check the caller's catch before choosing throw vs continue**; the same
  keyword means opposite things depending on who catches it.

- **`.research\` is git-ignored, and so `glob` will not find files in it.** My first two attempts to
  locate `verbose-debug-implementation-plan.md` returned "No files matched" and briefly looked like
  the file did not exist. It did. Use `Get-ChildItem` / `view` directly for anything under
  `.research\`.

- **Joel's brief can override the written plan — read both, and prefer the brief.** WI-12 edit 3
  specifies mirroring Deploy's `Read-Host` prompt for `-OutputFileBase`. Joel's instruction was the
  opposite: never prompt, default to `'Audit-TierModel'`, because a diagnostics re-run must be
  copy-pasteable and non-interactive. I followed the brief and noted the divergence in the decision
  record rather than silently picking one.

- **`"...$PSScriptRoot..."` inside a double-quoted `-Pattern` interpolates to empty** and produced
  `Illegal \ at end of pattern`. Same class as the `"$iif ("` trap from BUG-019. Single-quote regex
  patterns by default.

### Correction, same day — the prompt rule

My first WI-12 implementation defaulted `-OutputFileBase` to `'Audit-TierModel'` silently and
never prompted. Joel corrected it: D8's non-interactive rule covers only the **auto-enable**
path, not an explicitly-passed `-Logging`. Now implemented as: explicit `-Logging` **prompts**
(and throws on empty, mirroring the `-OutputFormat` prompt already in the file); the future
auto-enabled path defaults silently. A `$script:LoggingAutoEnabled` flag selects the branch and
gives WI-13 a marked hook point.

- **The strongest argument against my version came from inside the same file, not from Deploy.**
  I flagged the Deploy/Audit asymmetry but missed that `Audit-TierModel.ps1` **already prompts**
  for `-OutputFileBase` when `-OutputFormat` is given without one. My change made the *same
  variable* behave two different ways in the *same script* with no principle separating them —
  strictly worse than the cross-script asymmetry I did report. **When checking a new behaviour
  for consistency, search the file for other uses of the same variable before looking at the
  sibling script.** One `Select-String -Pattern 'OutputFileBase'` would have caught it.

- **A blanket rule from a brief can be an over-application of a narrower written rule.** "Never
  `Read-Host`" came to me as unconditional; the plan's D8 scoped it to the auto-enable path only.
  I followed the brief and flagged the divergence, which was right — but I could also have read
  D8's own wording (plan section 6, condition 1) and asked whether the scope was intended.
  Flagging is good; checking the cited source of the rule is better.

- **You can prove a hook works before the feature that uses it exists.** WI-13 does not exist yet,
  but copying the script to `$env:TEMP`, flipping `$script:LoggingAutoEnabled` to `$true` and
  running it confirmed the auto-enable branch is reachable and defaults correctly without
  prompting. Cheap, non-invasive, and it means WI-13's implementer inherits a tested seam rather
  than an untested comment.

- **Runtime-test a `Read-Host` path by piping stdin.** `'' | pwsh -NoProfile -File .\script.ps1 …`
  drives an empty response and `'MyAudit' | …` drives a real one, so both prompt branches are
  verifiable non-interactively. Note this **creates real artifacts** — case 2 wrote
  `MyAudit-090526-0928.log` into the repo root, the same root-pollution class as the `TestLog-*`
  files. Run these from a `$env:TEMP` working directory, or sweep the root afterwards.

---

## 2026-09-05 | Deploy-TierModel.ps1 — WI-04, WI-10, auto-enable seam

Requested by Joel Platek. Branch `feature/enable-verbose-debug`. Not committed.

**WI-04** — `[switch]$EnableVerbose` / `[switch]$EnableDebug` added after `[string]$OutputFileBase`
under a `# --- Diagnostics ---` banner, matching the banner style used in Audit. Declaration only.

**Auto-enable seam** — Deploy twin of Audit's `$script:LoggingAutoEnabled` flag plus a
`# WI-05 HOOK` comment. Deploy's pre-existing `Read-Host` prompt is preserved unchanged; the seam
only adds the bypass the future implicit path will take. Default `'Deploy-TierModel'` per WI-05.

**WI-10** — `.PARAMETER EnableVerbose` / `.PARAMETER EnableDebug` plus two `.EXAMPLE` entries,
including the unredacted-transcript warning (D6). Version strings corrected in both scripts to
2.1.0 against `TierModel.psd1:3`, and Audit's `.NOTES` brought to parity with the PowerShell 7.0+
requirement it was missing.

Runtime-verified all three prompt branches on Deploy (empty -> throw; `MyDeploy` -> honoured;
auto-enable simulated -> no prompt, defaults). Diagnostics parameter sets are equal across both
scripts. 0 parse errors. **Unit 1573 passed / 0 failed**, **Integration 318 passed / 0 failed**.

Raised `.squad/decisions/inbox/rogue-inert-diagnostics-switches-risk.md`.

## Learnings

- **Re-read a plan you have already read if you are told it changed — mine had grown 656 -> 940
  lines in under an hour.** Cyclops had reversed several of his own instructions after re-running
  the POCs (nested-transcript pre-check deleted as wrong; `Start-Transcript` under `-WhatIf`
  silently creates nothing; `[System.IO.Path]::GetFullPath()` banned because it resolves against
  the .NET current directory, which does not track PowerShell's location). None of it was in my
  scope, but working from the version in my head would have been working from fiction. **Check
  `LastWriteTime` and line count on a plan document before trusting a prior reading of it.**

- **A plan can forbid exactly what the brief authorises — and the brief wins, but say so.** WI-10
  reads *"flag the staleness; do not unilaterally renumber"*. Joel's brief authorised the renumber
  outright. I made the change and recorded the authorisation in the decision note, so the next
  reader does not find a change that appears to violate the written plan with no explanation.

- **Documenting behaviour before implementing it is a real hazard, not a formality.** WI-10's
  specified help text describes auto-enabled logging (WI-05) and the transcript (WI-07), neither of
  which exists yet. Written as specified, `Get-Help` now describes a script that does not behave
  that way. That is the documentation twin of Cyclops's B-3 inert-switch defect, and it made the
  sequencing risk worth escalating rather than just noting.

- **The scratch-copy hook simulation generalises.** Second use in a day: copy the script to
  `$env:TEMP`, flip one flag, run, confirm the not-yet-built branch behaves. Cheap, invisible to
  the repo, and it hands the next implementer a tested seam. Worth making a habit for any
  "structure it so X can hook in later" instruction.

- **Verify privilege claims before copying them between scripts.** Before putting Deploy's
  SeSecurityPrivilege line into Audit's `.NOTES` I checked that Audit's `-EnableAuditing` actually
  reads the domain-root SACL (it does — `Get-TierModelAuditRule` analyses the existing SACL). Help
  text asserting a privilege requirement that is not real is a support cost, not a nicety.

- **Every `Read-Host` runtime test leaves an artifact.** Between them these prompt tests produced
  `MyDeploy-*.log`, `Deploy-TierModel-*.log` and `MyAudit-*.log`, and the Integration suite added
  another `TestLog-*.log` to the repo root. Run from a `$env:TEMP` working directory **and** sweep
  the root afterwards; one alone is not enough.

- **`Get-ChildItem -Filter` takes a single string, not an array.** `-Filter '*.a','*.b'` throws
  `Cannot convert 'System.Object[]'`. Use `Where-Object` with a regex for multi-pattern sweeps.

### 2026-09-05 — Deploy WI-05..WI-09 and Audit WI-13..WI-16 (diagnostics wired end-to-end)

- **B-3 is closed.** `-EnableVerbose`/`-EnableDebug` now do something in both scripts. The
  window where the help documented behaviour that did not exist is gone.
- **BUG-024 confirmed and fixed.** Reproduced it exactly as Joel described: under `-WhatIf`
  `New-Item` was suppressed but `Write-Host "Created log directory"` printed anyway. The rule I
  applied everywhere: *diagnostics infrastructure carries `-WhatIf:$false` because it is the
  apparatus recording the preview, not part of the previewed change — and success is confirmed
  with `Test-Path`, never announced.*
- **`-WhatIf` still swallows the log file, and that is NOT mine to fix.** Verified at runtime:
  with `-WhatIf` the log directory, `Debug\` folder and transcript are all created correctly,
  but the log file is empty because `Write-TierModelLog`'s `Add-Content` (in `modules\**`)
  inherits `$WhatIfPreference` and is suppressed. Same defect class as BUG-024, one layer down.
  I did **not** work around it by forcing `$WhatIfPreference = $false` into module scope — that
  would make `-WhatIf` perform real writes, which is catastrophically worse. Reported instead.
- **Transcript noise came from module auto-loading, not the bare imports.** The four bare
  imports in `Test-TierModelPrerequisites.ps1` already carry `-Verbose:$false`. The
  `Exporting function 'Get-Net*'` records I saw on the console are PowerShell *auto-loading*
  NetTCPIP, which no `-Verbose:$false` can cover. The transcript itself measured **0**
  `Loading:` and **0** `Exporting function` — the plan's criterion — so ordering did its job.
  Four module files (`Get-/New-/Test-TierModelAuditRule.ps1`, `Resolve-TierModelPrincipalSid.ps1`)
  do import ActiveDirectory without `-Verbose:$false`; out of my boundary, logged for whoever
  owns `modules\**`.
- **Order matters at the exit paths: hint BEFORE stop.** My first pass inserted
  `Write-TierModelDiagnosticsHint` after `Stop-TierModelDiagnosticsTranscript`, which would have
  dropped the re-run line out of the transcript. Caught it by reading the inserted lines back
  rather than trusting the insertion. Reordered all six Deploy sites.
- **I widened WI-09 beyond the two sites specified.** Joel named the GPO-planning failure and
  the end block. But Deploy's *most common* failures — prerequisites and config validation —
  exit at six other `exit 1` sites which would have shown no hint at all, while Audit showed one
  at every failure exit. Symmetry was the stated priority, so I put the hint at all six. Flagged
  in the summary as a deliberate deviation.
- **`$PSBoundParameters` is per-scope.** The re-run hint could not read the script's bound
  parameters from inside a function; it had to be stashed into `$script:` while still at script
  scope. Obvious in hindsight, would have silently produced a truncated re-run line.
- **Method that keeps paying:** run it, do not reason about it. Every claim in the summary —
  relative `-LogPath` keeping log and `Debug\` together, `-EnableVerbose` alone producing no
  transcript, the transcript actually being closed, `-WhatIf` no longer lying — came from
  executing the script and reading the filesystem, not from reading the diff.

### 2026-09-05 (later) — BUG-025: `-WhatIf` suppressed the log write itself

- **Check the tests before changing behaviour, not after.** Grepped `tests\**` for any assertion
  that `-WhatIf` produces no log. There was none — but I found the *opposite* contract already
  asserted for the sibling logger in `optional\`: "WhatIf immunity: file is created and line is
  written when WhatIfPreference=true". That turned the fix from a judgement call into aligning
  with an existing, tested product contract. Two minutes of grep, much stronger justification.
- **Fixing the obvious call was not enough.** After adding `-WhatIf:$false` to the `Add-Content`
  Joel identified, I tested the adjacent case — a log directory that does not exist yet — and the
  suppressed `New-Item` above made the now-unsuppressed `Add-Content` throw. Deploy/Audit are
  immune because they create their own directory, but other callers were not. Extended the fix by
  one word and flagged it as a deviation rather than doing it quietly.
- **Not every "confirm it worked" check is worth adding.** Declined the suggested `Test-Path`
  companion: once the write cannot be silently suppressed, every remaining failure is a real
  exception the existing `catch` already reports accurately. A per-line filesystem stat on a hot
  path to detect an impossible condition is cost without benefit. Said so explicitly rather than
  adding it to look thorough.
- **The residual failure is now loud.** That is the actual win here, beyond the missing file:
  before, `-WhatIf` wrote nothing and reported nothing. Now anything that goes wrong produces a
  warning with the real message.

## 2026-09-05 — Six-finding review pass (BLOCKING-1/2 + NON-BLOCKING-3/4/5/6)

- **A green suite proved nothing here, and that was the point.** All six findings came from a
  rubber-duck read of the diff. Unit 1573/0 and Integration 318/0 were green *before* the fixes and
  green *after* — including for BLOCKING-2, where the audit was reporting "all OUs compliant" for
  an OU it could not read. No assertion existed on either side of that behaviour. Test-suite green
  means "nothing regressed", never "the new code is right".

- **I re-created the exact defect I had been hired to remove.** BUG-019 was about not letting a
  read failure masquerade as not-found. My own `$isNotFound` heuristic then classified
  `[System.ArgumentException]` as not-found at three `Get-GPO -All` sites — and `Get-GPO` throws
  exactly that for an unreachable `-Server`. So an enumeration failure was swallowed, `$existingGPO`
  stayed `$null`, and planning would plan a create for a GPO that already exists. My own comment two
  lines above said "the not-found path is an empty result set, not an exception" — I wrote the
  correct reasoning and then coded past it. **Pattern-matching a fix across sites without re-asking
  "can this call even produce this condition?" is how a fix becomes the bug.**

- **The discriminator is the parameter, not the cmdlet.** `Get-GPO -Name` genuinely throws for
  not-found, so the heuristic is right there. `Get-GPO -All` and `-Filter` searches return empty
  sets, so their catch is only ever reached on genuine failure and any not-found branch in it is
  dead code that eats real errors. Same cmdlet, opposite correct handling.

- **A false "compliant" is worse than a false "not protected".** BLOCKING-2: the read-failure catch
  added an `Type='Error'` finding but incremented neither counter feeding `$driftCount`, so
  `DriftCount = 0` and Audit printed a clean bill of health. The earlier bug at least made the
  operator look. **"Could not verify" must never render as "compliant"** — I added an explicit
  `$unverifiedCount` that feeds the drift total at both computation sites and shows as its own line
  in the summary, rather than folding it into "mismatch" where it would read as a known state.

- **Fixed the sibling defect I was not asked about.** The per-OU *outer* catch had the identical
  counter gap; Joel's brief named only the inner one. Fixed both — a half-fixed false-clean is
  still a false-clean.

- **Errors must reach the verdict, not just the console.** NON-BLOCKING-5 was the same class one
  layer up: the canonical-ACL hard-stop I added was caught by both callers, which printed a yellow
  warning and moved on without touching `$auditSummary.ErrorCount`. The throw was right; the
  callers silently downgraded it to cosmetics. **A `Write-Warning` is not a verdict.**

- **"Copy-pasteable" has to be tested by pasting it.** The re-run hint replayed
  `$script:InvocationBoundParameters` verbatim — but a value that came from `Read-Host` is not in
  `$PSBoundParameters`, so the emitted line carried `-Logging` with no `-OutputFileBase`, and on
  re-run took the prompt branch again and died in a non-interactive host. Fixed by emitting the
  *resolved* value. Verified by literally running the emitted line with empty stdin: no prompt, log
  and transcript both written.

- **Symmetry is a feature and it decays silently.** Deploy emitted the hint when blocked; Audit's
  tail emitted none, so an audit finishing with drift never offered the re-run line. Nothing was
  broken — the two scripts had just drifted apart, which is precisely the thing an operator pays
  for at 2am.

## 2026-09-05 — FINAL-1/2/3: the green all-clear that outlived the data

- **The same false-clean bug had three more mouths.** BLOCKING-2 fixed the *counter*; the caller
  still printed "Compliance: 100%" in green and "✅ All OUs match configuration expectations"
  underneath a red Errors block. Fixing a number is not fixing a verdict — I had to follow the
  value all the way to the pixel the operator actually reads.

- **`else { 100 }` is the tell.** `if ($total -gt 0) { math } else { 100 }` reads as a safe
  divide-by-zero guard, which is why it survives review. But the guard silently asserts that zero
  checks means perfect compliance. Zero checks means *unknown*. The dangerous branch is the one
  that looks like arithmetic hygiene.

- **A percentage over a partial run overstates what we know.** I gated on `Errors.Count -gt 0` as
  well as `TotalChecked -le 0` — if half the OUs failed to read, the 100% over the surviving half
  is true and useless.

- **My defensive display line was itself undefended.** Adding `$audit.Summary.UnverifiedCount`
  broke three Integration tests — not because they encoded the old behaviour, but because the mock
  builds `Summary` as a `[PSCustomObject]` while the real function returns a hashtable, and
  `Set-StrictMode -Version Latest` throws on a missing property. **I captured the actual exception
  before concluding anything** rather than assuming the tests were stale: `The property
  'UnverifiedCount' cannot be found on this object.` The tests were right and my code was wrong.
  Fixed my code, dictionary-and-object safe. Almost the exact inverse of the earlier lesson —
  sometimes the test is not encoding the bug, it is catching one.

- **A failing test handed me proof I could not otherwise get.** The failure output showed
  NON-BLOCKING-4's tail hint and NON-BLOCKING-5's "compliance is UNKNOWN, not compliant" both
  firing on a real unreachable-DC run — two findings I had reported as code-inspected-only because
  they need a DC. The broken run reached further into the script than any harness I had built.

- **Reported rather than bulk-fixed.** The `else { 100 }` pattern repeats in Invoke-GroupAudit,
  Invoke-UserAudit and the consolidated Overall Summary, and five more unguarded ✅ lines exist.
  Fixed only the OU one as instructed and listed the rest, on the last round before code lock.

## 2026-09-05 — TRUE-FINAL: the fix that was half-dead at the level people read

- **A correct fix can be silently undone one layer up.** BLOCKING-2 made `Test-TierModelOu`
  count unverified OUs into `DriftCount`. The consolidated summary then did
  `if ($totalMissing -gt 0 -or $totalMismatched -gt 0) { $totalDrift = $totalMissing + $totalMismatched }`
  — an **overwrite**, not an accumulation — discarding the unverified component. 1 missing +
  1 unreadable OU reported as 1 drift item. My fix survived only in the case where the `if`
  happened not to fire. **Fixing the producer is not fixing the number; follow the value to the
  line the operator actually reads.**

- **An accumulator you never consult is decoration.** `$totalErrors` was summed across sixteen
  lines and then never referenced by the headline verdict, so the product's single most-read line
  could print ✅ COMPLIANT directly above a non-zero error count. "Could not determine" is a third
  state and now renders as one.

- **My own catalogue was wrong in both directions and I only found out by reading each site.**
  I had reported the canonical-ACL ✅ at L1125 as unguarded — it was **already correct**
  (`$mismatched -eq 0 -and $errors -eq 0`). And I had **missed** an `else { 100 }` in the same
  function because the variable is `$compliancePct`, not `$compliancePercentage`, so my grep never
  saw it. **A grep-derived inventory is a hypothesis, not a finding.** Verify each entry before
  reporting a count, and never let the search term define the population.

- **The StrictMode lesson generalised.** Every new read this round went in dictionary-and-object
  safe. That immediately paid: `Test-TierModelGPOAudit`'s wholesale-failure shape has **no
  `Findings` property at all**, so the existing `$audit.Findings.Count` would have thrown before
  my gate ever ran.

- **Reported rather than forced.** That same GPO block reads `Summary.TotalGpos`, `.Drift`,
  `.Errors`, `.CompliancePercentage` — none of which exist on the failure shape. Gating the ✅ is
  correct but cannot rescue a block that throws four lines earlier. Fixed what was authorised,
  said plainly that it is not sufficient, and left the shape mismatch for a decision instead of
  quietly widening scope on the last round before code lock.

## 2026-09-05 — Code lock: one contract beats many defences

- **I measured the reviewer's premise instead of accepting it.** The brief stated that under
  `Set-StrictMode -Version Latest` a missing *hashtable* key returns `$null` rather than throwing,
  so the GPO failure path would print a green "Total Drift: 0". **That is not true on pwsh 7.6.5** —
  I tested StrictMode 2.0, 3.0 and Latest and a hashtable dot-miss throws in all three. Driving the
  real failure object through the real display function showed it throwing on
  `Summary.TotalGpos`, the *first* Summary read, earlier even than the `Findings` access I had
  originally identified. The conclusion (fix the shape) was unchanged, but the symptom is a crash,
  not a false-clean, and an operator debugging one will look in a completely different place.
  **Accepting a plausible mechanism from a trusted reviewer is the same error as accepting my own
  grep output — verify, then agree.**

- **Fix the contract, not the consumers.** Two return shapes from one function forced every caller
  to defend itself twice over. Mirroring the failure shape onto the success key set - adding, never
  replacing, the four original keys - deleted the whole class in one place.

- **Adding a key to a shape changes every accumulator that reads it.** Giving the failure shape a
  `Summary.Errors` immediately double-counted: the consolidated block summed `Summary.Errors` *and*
  the top-level `Errors` collection, which are two representations of the same set. Measured it
  first (got 2, expected 1), then switched to `[Math]::Max(...)`. That also silently fixed a
  **pre-existing** double-count on the success path, which had been inflating error totals for
  every entity type that emits both.

- **The empty `Findings = @()` is doing real work.** A property that exists and is empty is a
  contract; a property that is absent is a landmine for every consumer under StrictMode.

- **Why this mattered more than it looked:** lab measurement showed GroupPolicy cmdlets emit zero
  verbose and zero debug records because they load through the WinPSCompat proxy and their streams
  do not cross the remoting boundary. On the GPO path our own logging is the *only* diagnostic
  channel, so a GPO audit that crashes or reports clean leaves nothing at all behind.


---

## 2026-09-05 | BUG-026 — Audit-TierModel.ps1 could not start from any foreign working directory

Requested by Joel Platek. Branch `feature/enable-verbose-debug`. Not committed. Option (a) only.

Cyclops's 41-row lab matrix split perfectly: 22/22 Deploy PASS, 19/19 Audit FAIL, each Audit row
in ~1s. Cause: `Test-TierModelPrerequisites` defaults `-DependenciesPath` to the CWD-relative
`config/dependencies.json` (L50). Deploy overrides it with `$PSScriptRoot` at both call sites;
Audit overrode it at neither. Fixed both Audit sites (now L601 and the `$prereqSplat` at
L1971-L1974) to `(Join-Path $PSScriptRoot 'config\dependencies.json')`. `Deploy-TierModel.ps1`,
`Test-TierModelPrerequisites.ps1`, `tests\` and `.research\lab-validation\` untouched.

0 parse errors. **Unit 1573 passed / 0 failed**, **Integration 318 passed / 0 failed** — both
baselines matched exactly.

## Learnings

- **A green suite was guaranteed here and therefore worthless.** Every Integration Audit test
  `Mock`s `Test-TierModelPrerequisites` wholesale, so real parameter binding is never reached,
  and Pester runs from the repo root where the CWD-relative default happens to resolve. Two
  independent reasons the suite is blind to this entire bug class. The evidence that mattered was
  a control run: invoke the function with its default from a scratch `$env:TEMP` directory and
  watch `Dependencies file not found at: config/dependencies.json` appear, then run the patched
  script from the same kind of directory and watch it proceed to genuine DC-connectivity errors.
  **When the defect is about ambient process state (CWD, env, locale), reproduce it by changing
  that state — a test suite pinned to one working directory cannot see it.**

- **This is the second occurrence of the same defect, and grep hides the third and fourth.**
  CHANGELOG line 176 records BUG-008: the identical omission in Deploy's `-Include*` splats.
  While inventorying callers I found `New-TierModel` (TierModel.psm1 L674-772, call at L694) and
  `Set-TierModel` (L774-891, call at L794) both *pass* `-DependenciesPath` — so they read as
  compliant in any grep — while their **own** parameter defaults (L678, L778) are the same
  CWD-relative literal. They just launder the bad default one layer up, and both are publicly
  exported. **When auditing for a bad default, do not stop at "does the caller pass the
  parameter"; follow the value the caller passes back to where it originates.**

- **The blast radius of a "breaking" signature change was 2 lines, not a ripple.** I assumed
  making `DependenciesPath` mandatory would ripple through the Pester suite. Of 87 real test
  invocations, **86** already pass an explicit path; exactly one (`Integration.TierModel.Tests.ps1:28`)
  relies on the default, plus one comment-based-help example. Counting before arguing turned a
  vague "too risky" into a concrete two-item cost. **Do the inventory before forming the opinion.**

- **`Audit-TierModel.ps1` requires a scope switch before it will do anything.** My first
  reproduction attempt (`-PreferredDc x` alone) died at "You must specify exactly one audit scope
  parameter", never reaching the prerequisite gate — which briefly looked like the fix had
  changed the failure mode. Add `-OuOnly` (or any scope) to any smoke invocation of this script.

- **The `[System.IO.Path]::GetFullPath()` ban is this exact bug wearing a different hat.** Both
  resolve a relative path against a process-level notion of "current directory" that does not
  track PowerShell's location. `$PSScriptRoot` + `Join-Path` is the only correct answer in this
  repo, and it is worth saying so in a comment at the call site so the next reader does not
  "simplify" it back out.

### Correction, same day — I claimed two functions were exported, and they are not

Joel caught it. I wrote that `New-TierModel` and `Set-TierModel` are "publicly exported, so
customers hit this too", and that claim was the entire load-bearing argument for recommending
option (b). It was false. `TierModel.psd1` contains `New-TierModelGpo`, `New-TierModelOu` and
fourteen other prefixed names that *contain* the string `New-TierModel`; I read those as hits for
the bare name. Runtime settles it: importing the manifest in a clean session gives **83 exported**,
with `New-TierModel` and `Set-TierModel` both **False**, and there is no `Export-ModuleMember`
anywhere in the psm1, so the manifest list is authoritative. Joel picked **(a)** as final for
v2.1.0 — `Test-TierModelPrerequisites` *is* exported, so a mandatory parameter is a breaking
signature change in a minor release, and there is no customer to defend.

- **Same trap, twice in one session, and that is the real lesson.** Earlier today I corrected my
  own `else { 100 }` inventory with the words *"my inventory was a grep hypothesis, not a verified
  finding — the search term defined the population."* Then I did it again, in the same session, on
  a claim I put in a decision record as fact. Recognising a failure mode is not the same as having
  a habit that prevents it. **The habit: for any claim of the form "X is exported / X is public /
  X is reachable", the evidence must be runtime enumeration or an exact-match search — never a
  substring grep.** In a codebase where every name shares a `TierModel` prefix, substring matching
  has no discriminating power at all, and that is precisely where it feels most convincing.
- **Word-boundary regex for PowerShell command names needs the hyphen in the class.**
  `(?<![-\w])(New|Set)-TierModel(?![-\w])` — plain `\b` fails here, because `\b` sits happily
  between `New-TierModel` and the `Ou` of `New-TierModelOu`... no, worse: `\b` does not fire there
  at all, but it *does* treat the internal hyphen as a boundary, so `\bTierModel` matches inside
  every prefixed name. Put `-` in the lookaround classes.
- **Prefer the AST over regex for "who calls X".** `CommandAst.GetCommandName()` counts command
  position only, so prose, comments, wildcards like `New-TierModel*.ps1` and substring cousins
  cannot register. The regex sweep returned ~60 lines of which most were prose; the AST sweep
  returned exactly 22, all real. Regex first to find candidate files, AST to count.

### Follow-up finding — both wrappers are dead code

Swept the repo for exact-name invocations of `New-TierModel` / `Set-TierModel`: **22 total, every
one in `tests\Unit.TierModelModule.Tests.ps1` via `InModuleScope`** (10 New at L886-L1021, 12 Set
at L1049-L1196). Zero callers in `Deploy-TierModel.ps1`, `Audit-TierModel.ps1`, `modules\`,
`optional\`, `docs\` or `specs\`. Zero indirect reachability — no `Invoke-Expression`, no
`& 'New-TierModel'`, no `Get-Command` lookup. The one promising-looking hit,
`Integration.Convergence.Tests.ps1:106`, is a stale comment above a test that actually calls
`Get-TierModelPlan`.

- **`Set-TierModel` cannot complete even if called.** `TierModel.psm1:868` calls
  `Invoke-TierModelPlan -Plan $plan`, and that function is defined **nowhere** — the AST sweep
  finds exactly one occurrence of the name in the whole repo, and it is that call site.
  `docs\test-coverage.md:254` independently records it as coverage hard-limit (6). **When deciding
  whether code is dead, check whether its own callees exist**; a function that would throw
  `CommandNotFoundException` on its apply path has clearly never been executed in anger.
- **A test file can be the only thing keeping a function alive, and that is worth naming.** These
  two exist solely so that `Unit.TierModelModule.Tests.ps1` can cover them. Coverage of dead code
  reads as coverage, which is exactly how it survives.
- **Check the coupling someone warns you about before agreeing it is a risk.** Joel flagged that
  `Unit.ModuleManifest.Tests.ps1` derives expectations from the `public\` folder listing. True —
  but both functions live in `TierModel.psm1`, not `public\`, so that test is structurally immune
  to their deletion. The real blast radius is Wolverine's Describe blocks and Scribe's coverage
  doc, plus a Unit re-baseline.


---

## 2026-09-05 | BUG-027 — consolidated audit totals never reached `$auditSummary`

Requested by Joel Platek. Branch `feature/enable-verbose-debug`. Not committed.

A lab run printed `✅ COMPLIANT` with per-phase counts totalling 406, then logged
`TotalChecked=0, DriftCount=0`. The `-FullDeployment` path accumulated into locals, rendered them
to the console, and never published them into `$auditSummary` — which every persisted artifact
reads. Fixed by publishing the totals at the end of the consolidated block, plus two further
stale paths I found (`-AdmxOnly` and standalone `-Include*`). Added `UnverifiedCount` and
`ErrorCount` to the log payload.

0 parse errors. **Unit 1573 passed / 0 failed**, **Integration 318 passed / 0 failed** — baselines
matched. Drifted stub harness 5/5 post-fix, **0/5 pre-fix**.

## Learnings

- **The brief said three consumers; there were five.** Joel named the report, the XML and the log.
  An AST sweep for `$auditSummary` also turned up the **Json report, which serializes the entire
  hashtable**, and — worse — the tail gate `if ($auditSummary.DriftCount -gt 0 -or
  $auditSummary.ErrorCount -gt 0)` that decides whether to offer the diagnostics re-run. So on
  `-FullDeployment`, the operator with real drift was never offered the very `-EnableVerbose
  -EnableDebug` hint this branch exists to provide. **Enumerate every read of a variable before
  believing a list of its consumers, including the ones in boolean conditions rather than string
  interpolations** — those are the easy ones to miss because they do not look like output.

- **The brief said one stale path; there were three.** Joel asked me to confirm the consolidated
  block was the only one. It was not: `-AdmxOnly` is the single one of six single-entity branches
  that never writes `$auditSummary`, and the standalone `-Include*` path has its own
  `$standaloneTotal*` accumulators that were equally unpublished. **When a bug is "the totals were
  never assigned", the right question is not "where is the bug" but "enumerate every terminal path
  and check each one" — the AST gives you the branch list for free.**

- **Under `Set-StrictMode -Version Latest`, reading a missing HASHTABLE key throws.** I assumed
  hashtables were exempt and that only PSObject property access was guarded. They are not:
  `$h=@{A=1}; $h.ZZZ` → *"The property 'ZZZ' cannot be found on this object."* This turned
  "initialize the new key for tidiness" into "initialize it or report generation dies on every
  scope that never sets it". **Verify StrictMode semantics empirically rather than from memory;
  it took one line to check and it changed the design.**

- **`+=` versus `=` was a real decision, not a style choice, and the harness proved it.** The
  canonical-ACL `catch` in the consolidated block increments `$auditSummary.ErrorCount` for a phase
  that *threw* — and a phase that throws never lands in `$auditResults`, so `$totalErrors` cannot
  see it. A plain `=` would have erased a known error. The harness against a fake DC logged
  `"ErrorCount":1, "TotalChecked":56` with `$totalErrors` at 0, demonstrating it live. **Before
  overwriting an accumulator, find every other writer to it and ask whether their contribution is
  contained in the value you are about to write.**

- **The same fix revealed an earlier fix had been inert.** NON-BLOCKING-5 added that `ErrorCount++`
  so a failed canonical phase would not vanish from the verdict — but nothing on the consolidated
  path ever *read* `$auditSummary.ErrorCount`, and the console prints `$totalErrors` instead. The
  counter had no reader for the whole life of that fix. **A fix that writes to a field nobody reads
  is indistinguishable from no fix; when adding a signal, verify the consumer exists on the path
  you care about.**

- **A green run cannot prove a counter fix, and a pre-fix control is what makes the evidence
  two-sided.** A stale `DriftCount = 0` is identical to a correct 0; only `TotalChecked` being 0
  against an obvious 406 exposed this. I built the drifted harness, then stripped my own 13
  assignment lines from a copy and re-ran: **0/5, with the XML literally reading
  `total="0" failures="0"` on a five-drift run**, while the console assertion still passed. That
  console-passes/artifact-fails split is the bug reproduced on demand. **Do the control run — the
  post-fix green is half an argument on its own.**

- **Put the control copy where `$PSScriptRoot` still resolves.** My first control lived in
  `$env:TEMP` and failed all five cases at module import, which looks like a control that "worked"
  if you only read the pass count. It proved nothing. Same class as BUG-026 an hour earlier — the
  script's own directory is load-bearing.

- **Check test coupling before claiming an output change is additive.** Adding lines to the report
  and keys to the log payload is only safe if nothing asserts on their shape. Every report-format
  test runs `-OuOnly` and asserts structural strings only; the one consolidated test asserting
  `'Total Checked: 56'` reads **console** output, not the report. Confirmed by reading them, then
  by the unmoved 1573/318 — not by assuming.

- **Six sequential `if`s that look like they could co-fire, but cannot.** Joel suspected the
  `=`/`+=` mix in `-OuOnly` could clobber. It cannot: `$activeScopeCount -gt 1` is rejected during
  validation, so exactly one branch runs, and within `-OuOnly` the `=` seeds before the `+=`
  accumulates. **Resolve "can these both run?" from the guard, not from the shape of the code** —
  and report the readability trap rather than silently converting to `elseif`.

### BUG-028 — `$driftFindings` clobbered in the per-entity loop (2026-09-05)

- **A loop-local and a script-scope variable sharing a name is a silent data-loss bug, not a style
  problem.** `$driftFindings = @()` sat inside the per-entity `foreach`, resetting the list the
  Text/Json/Html reports read. Joel predicted the report would hold the *last* entity type's
  findings. Measured, it held **zero** — because the last entity type on the consolidated path is
  ADMX, which usually has no drift. The report printed "No drift detected" for a run whose console
  listed five findings. Always measure the blast radius; the predicted severity was too kind.
- **Third confirmed instance of console-right/artifact-wrong in this one file, and I found a
  fourth while proving it.** `$driftFindings` is never assigned on `-AdmxOnly` or standalone
  `-Include*` either, so those scopes always report "No drift detected". Escalated, not folded in.
  When a defect class appears three times in a file, sweep the whole file for it before reporting.
- **Test the hypothesis, do not evaluate it in your head.** Joel believed
  `Get-SafePropertyValue ... 'DriftFindings'` returned a collection and that `-gt 0` was a
  filtering comparison. It actually returns `.Count` — so his mechanism was wrong. But building
  all three input shapes surfaced a *different* real defect: a **bare, non-array finding object**
  falls to `try { [int]$current } catch { return 0 }`, scores 0, and is silently dropped after
  passing the outer truthiness guard. I would have missed that by reasoning. Third time this
  session that an empirical check beat an analytical one.
- **`@()`-wrap before `+=` when the source may be a scalar.** It costs nothing and makes `.Count`
  meaningful. Shipped module code always returns arrays today, so this was latent — but
  `Test-TierModelUser.ps1:275` puts an *integer* under a `DriftFindings` key (log payload only,
  confirmed harmless) which shows how close the live case is.
- **The obvious fix is not always the authorised fix.** Folding `$auditSummary.ErrorCount` into
  `$totalErrors` before the verdict is more correct — a phase that threw has not established
  compliance, which is what NON-BLOCKING-5 says in so many words. But it flipped the headline
  verdict and broke **three** Integration tests (318→315) that mock the six entity functions and
  *not* `Invoke-CanonicalAclAudit`. I cannot touch `tests\`, and the task was scoped to the console
  line. Correct move: narrow to a separate `$displayErrors` for the console, restore 318/0, and
  escalate the verdict question **with the exact cost named**. A decision is cheap when you hand
  over the price tag.
- **Prove "dead code" before deleting it.** L646 `$driftFindings = @()` looked redundant after the
  fix. Stripping it from a repo-root copy and running `-AdmxOnly` gave
  `The variable '$driftFindings' cannot be retrieved because it has not been set.` Load-bearing —
  and the *reason* it is load-bearing is itself the fourth bug.
- **Mock shapes lie about product bugs.** A probe threw `The property 'CompliancePercentage'
  cannot be found` and looked like a live `-AdmxOnly` defect. It was my mock missing a property the
  real `Test-TierModelAdmx` returns. Confirm a suspected product bug against the real contract
  before writing it up.
- **A control experiment needs the right negative fixture.** Two entity types with drift *and* a
  clean final entity type. A single-entity fixture passes while the code is broken; two entity
  types with the last one drifted would also have passed.

### BUG-029 / BUG-030 — fail-fast logging, and the scopes that never reported drift (2026-09-05)

- **An anchored text replacement is a search, and a search needs its match count checked.** I
  inserted the BUG-029 block by anchoring on `Write-Host "Deploy script completed."` + `}`. That
  string occurs **twice** in Deploy — the second in the normal success epilogue — so the block was
  duplicated into the success path where `$Message` does not exist, which under StrictMode would
  have thrown on every successful `-Logging` run. **The harness could not catch it** because Deploy
  exits at the prerequisite gate and never reaches the epilogue. I found it only by going to build
  the control copy. Always count matches before replacing, and diff the result against HEAD.
  Third variant of the same lesson this session: the search term defines the population.
- **A control copy that does not parse proves nothing.** My first BUG-029 control failed 4/4 — but
  with a parse error, not the defect. The strip had eaten a merged `}}`. Always assert
  `parse errors = 0` on the control *before* believing its failures. A red control is only evidence
  if it is red for the reason under test.
- **Put the fix in the shared helper, not at the call sites.** One change covered all 7 fail-fast
  gates, cannot be forgotten by a future gate, and preserved the deliberate Deploy/Audit symmetry.
- **Enumerate readiness per call site instead of assuming a single answer.** Deploy sets its log
  path BEFORE the PowerShell-version gate; Audit sets it AFTER. So of 7 sites: 5 have a live logger,
  1 has a path but no logger (direct JSON append), and 1 has neither and structurally cannot log.
  Two different not-ready cases where I would have guessed one.
- **StrictMode: probe, do not read.** `$script:LogFilePath` is *undeclared* at Audit's version gate,
  so reading it throws. `Get-Variable -Scope Script -ErrorAction SilentlyContinue` is the safe
  probe — verified across undeclared / declared-null / assigned. A path that throws while reporting
  a failure is worse than the bug it was meant to fix.
- **`Warning` is not a substitute for `Error`, and neither alone is enough.** Cyclops's loophole was
  real: a routine module-probe Warning can make a log *look* as though it recorded a failure.
  Machine-identifiable data keys (`FailFast`, `Terminal`) plus the verbatim console text are what
  make a terminal record unambiguous and correlatable.
- **When a branch is "missing" an assignment, ask why before adding it.** `-AdmxOnly` and standalone
  `-Include*` were unwired because the audit functions disagree on finding shape — ADMX uses
  FileName/Message, the standalone ACL audits carry no `Details` at all. A naive assignment would
  have replaced a silently-wrong report with a StrictMode crash. The normaliser was the fix; the
  omission was a symptom.
- **Always keep one assertion that must pass in BOTH control and post-fix.** "A clean ADMX run still
  reports no drift" is the guard against over-fixing — without it, a change that force-populates
  findings would look like a success.
- **Fifth instance found: `-GposOnly` builds findings with no `ResourceType`**, which the report
  interpolates, so it throws under StrictMode. Loud rather than silent, but still a lost artifact.
  The real root across all five is architectural: every scope branch populates the shared reporting
  variables by hand and nothing verifies that it did.
- **My mock shapes twice produced fake "product bugs"** (`CompliancePercentage` missing). Before
  writing up a suspected defect found through a mock, confirm it against the real function's
  contract — or, better, test the precise expression in isolation, which is what finally settled
  the `-GposOnly` question in one step.

### BUG-031 / BUG-032 / version-gate reorder (2026-09-05T14:14:51.5615929+08:00)

**BUG-031 — the '+=' to '=' hinge.** Folding `\.ErrorCount` into `\`
before the verdict means the BUG-027 publish line MUST become `=`. Leaving it `+=` double-counts
every phase-level throw. When you widen an accumulator upstream, always re-check every downstream
publish that already summed the same source.

**Integration 315/3 was the CORRECT outcome.** Joel reversed the "keep the baseline" constraint.
The three failures encode pre-BUG-019 swallow-the-error behaviour. Lesson: a baseline is evidence,
not a goal. When a correct fix breaks tests, name the tests and the cause precisely and let the
owner decide — do not narrow the fix to keep a number green. I narrowed it once (BUG-028) and it
was the wrong instinct, though escalating with the exact cost named was right.

**BUG-032 — StrictMode makes a missing key a THROW, not a blank.** `\.ResourceType` on an object
lacking it throws. So the guard must be `\.PSObject.Properties.Name -contains 'ResourceType'`
FIRST, short-circuiting before the property read — otherwise the guard commits the defect it fixes.

**Test the exact expression in isolation.** Both the defect and the fix were proved in ~15 lines
against the report's literal interpolation string. Far faster and more trustworthy than a harness,
and it produced the over-fixing GUARD case for free.

**MAJOR FINDING — neither script parses on PowerShell 5.1.** Measured with the real 5.1 engine:
Audit 2 parse errors, Deploy 16. Cause is NOT PS7 syntax — both files are UTF-8 **without a BOM**
and carry 76/180 non-ASCII chars (em-dashes, status glyphs). 5.1 decodes them as ANSI and the
parser derails on characters inside COMMENTS. So the version fail-fast gate is unreachable on 5.1
in BOTH scripts, including Deploy's, which was cited as the proof the pattern works.
Method lesson: **when asked "does this run on version X", run it on version X.** I nearly settled
for grepping for ternaries, which would have given the wrong answer with high confidence. Reported
to Joel; did not change encoding unilaterally.

**Control-experiment refinement.** My anchored strip of the gate block silently matched nothing
(line-ending mismatch), leaving TWO gates in the pre-fix control. Rather than assume, I verified by
line number that the earlier gate preceded log-path resolution and therefore reproduced the original
ordering exactly. Restates the standing rule: **an anchored replacement is a search — assert the
match count, and if it is zero, verify what you actually built before trusting it.** Both controls
were parse-asserted before being run.

### BUG-033 (UTF-8 BOM) + normaliser routing (2026-09-05T14:31:51.2170590+08:00)

**The BOM was the whole defect; the characters were fine.** Both entry scripts were UTF-8
**without** a BOM with 76/180 non-ASCII chars. 5.1 decodes BOM-less as ANSI and the parser dies
on em-dashes **inside comments**, reporting `Missing closing '}'` against VALID code. Prepending
3 bytes took Deploy 16->0 and Audit 2->0 errors on real 5.1. Resist the urge to "clean up" the
glyphs - that would be treating the symptom and would churn console output.

**Prove byte-preservation by hashing the STRIPPED file.** SHA-256 of (file minus 3 leading bytes)
== original SHA-256. That is a real proof; "diff looks fine" is not.

**Re-verify the BOM AFTER any later edit.** I edited both files again after adding the BOM and
deliberately re-checked - an editor that rewrites a file can silently drop it. Both survived, but
this is now a standing post-edit check for these two files.

**MEASUREMENT ARTIFACT that looked exactly like a product bug.** My first 5.1 run reported
`log files: 0` and I very nearly reported "the fallback doesn't work on 5.1". The cause was my
own harness: `| Select-Object -First 10` **stops the pipeline**, killing the child powershell.exe
before it flushed the log. Rule: **never pipe a child-process run through `Select-Object -First N`
when the thing being measured is a side effect near the end of the process.** Investigate your own
instrument before blaming the product - that is twice now that a harness artifact masqueraded as a
defect.

**Declined half of an approved task, with evidence.** Joel approved routing BOTH hand-built
projections through the normaliser. Only `-GposOnly` was equivalent (producer emits exactly
Type/GpoName/Message). The OU-ACL one carries a custom Type DERIVATION (Drift -> Missing/Mismatch,
else Error) the normaliser cannot express, AND its stated justification did not hold: all 8
construction sites in Test-TierModelOuAcl emit all six fields, so there was no StrictMode hazard to
close. Doing it would have been pure regression risk for zero benefit. **An approved instruction
whose premise fails on inspection should be reported, not executed** - same principle as the
version-gate deferral, except this time the evidence pointed the other way.

**Extract the SHIPPING function by AST for equivalence controls.** I pulled
ConvertTo-TierModelDriftFinding out of the file via FunctionDefinitionAst and dot-sourced it,
rather than retyping it into the test. A control that tests a retyped copy proves nothing about
the code that ships.

### BUG-034 - two reporting conventions, and why AST literals mattered (2026-09-05T15:05:12.8250861+08:00)

**The codebase has TWO finding conventions, not one.** Type/Identifier/Details (5 producers) and
Status/PolicyName|SiloName|GpoName/Issues (4 shapes across 3 producers + 1 AuditRule variant).
`Status` was the common thread - all four broken shapes carried it, none carried a usable Type.
One rule keyed on Status beat four separate key-list patches.

**Extracting real LITERALS by AST killed my own design.** I planned to prefer Status over Type
when Type was not a "recognised drift class". Pulling the hard-coded literals out of the producers
showed the healthy ones use `MissingAcl`/`UnexpectedAcl`/`MissingAuditRule`/`AuditRight` - a
whitelist would have mis-classified values it had never heard of and changed 79 correct rows.
Final rule is far narrower: **Type always wins when present; Status is consulted only when Type is
absent.** Lesson: extract key sets AND literal values; a key-set-only sweep hides the values that
decide the algorithm.

**A key-set-only grep missed a whole shape.** My first pass reported Test-TierModelAuditRule as
uniform. AST showed 2 distinct shapes - one substitutes `Status` for `Details`. Grep matched
literal keys at line start and could not see a second construction site.

**Found the INVERSE of the family.** AuditRule L177 appends a finding unconditionally per right,
so `Status='Pass'` entries rendered as `[AuditRight] ...` drift. Artifact claims drift where
console says compliant - the mirror image of BUG-027/028/030/032. Fixed by the compliant-drop.
Exact matching is load-bearing there: `NonCompliant` must not match `*Compliant*`.

**The acceptance bar is what you are NOT fixing.** 110 AST-derived rows: 79 byte-identical,
31 changed and all 31 were the broken shapes. That measurement - not the 3 repairs - is what
proves a shared-code-path change is safe. Ordering (`elseif` for Expected/Actual AFTER
ExpectedValue/ActualValue; Issues AFTER Details/Message/Reason) is what kept the 79 identical.

**Re-verified the UTF-8 BOM after editing**, per the BUG-033 standing rule. Still present.

### BUG-035 / BUG-036 - population definition, and a pattern applied mechanically (2026-09-05T15:22:46.5429701+08:00)

**"Which objects are real findings?" is a research question, not a grep.** The reviewer's
independent audit of my BUG-034 numbers disagreed with mine because his extraction counted
**result-object initialisers** as findings. It is only a finding if its enclosing assignment is
a `+=` onto the findings collection. Everything else - the TotalChecked/Compliant result
objects, per-item `` objects, parameter-log hashtables, ACE shapes - is a different
population. **Getting the population wrong manufactures false "changed" rows and makes a safe
change look dangerous.** Classify by enclosing statement, and state the exclusions out loud.

**BUG-036 was structural, so the fix had to move, not extend.** The standalone path aggregated
8 producers and normalised ONCE, so one `-DefaultResourceType` could never serve 8 resource
classes. Moving normalisation to the 8 append sites was the only shape that worked. Lesson: when
a parameter cannot express the problem, the call site is in the wrong place - do not widen the
parameter.

**Take defaults from the producers' own literals.** `ACL`/`LapsPermission`/`DomainAuditRule`
came out by AST, so the three new values match house style instead of my taste. 33/43 rows
byte-identical because the normaliser prefers a finding's own ResourceType - the 5 correct
producers were immune by construction, not by luck.

**Applying a known pattern mechanically fixes only the path the pattern knows about.** BUG-035
looked like a textbook BUG-019 site: add `-ErrorAction Stop`. But my control ran TWO failure
modes, and the second - a SUCCESSFUL read returning a blank DistinguishedName - still produced
the malformed DN `OU=Tier 2 End-User Accounts,`. No error-action setting can catch that. If I
had applied the pattern without building both scenarios I would have closed the bug half-fixed.
**Always ask what the remediation pattern does NOT cover.**

**Stub the failure MODE, not the return value.** Wolverine proved an empty-bodied stub returning
`` cannot represent a read failure at all, so `-ErrorAction Stop` never throws and
broken and fixed code are indistinguishable. The control used `Write-Error` (non-terminating),
which is what the unguarded call actually swallows. BEFORE text from `git show HEAD:`, never
retyped, and both versions asserted to parse before believing their behaviour.

**Argue against your own design in a design doc.** For the publish guard the most valuable
section was the one explaining why MY first idea - a post-branch assertion - would have caught
1 of 6 instances and become instance seven by passing vacuously. A guard that can pass vacuously
is worse than no guard, exactly as a control that fails for the wrong reason is worse than none.

### BUG-037 / BUG-038 - verify the framework claim, and check who already solved it (2026-09-05T15:42:01.2105351+08:00)

**Verify a platform semantic against the platform, not against memory.** The whole BUG-038
argument rested on "`inheritedObjectType = Guid.Empty` means all classes". I constructed two
real `ActiveDirectoryAccessRule` objects: the restricted one reports
`ObjectFlags = InheritedObjectAceTypePresent`, the Empty one reports `ObjectFlags = None`.
.NET reports the widening itself. One command, and the security claim stops being an inference.

**Before designing a fix, search for the same defect already fixed elsewhere.** MSA/gMSA/dMSA
already throw `"Aborting ACL application to prevent an over-scoped ACE."` with tests named
"Fails safely when inheritedObjectType resolves to Guid.Empty". The OU family was the ONLY
inconsistent one. That turned "should this fail outright?" from my opinion into the project's
existing decision - and gave me the exact wording. **Grep the tests for the behaviour you are
about to invent; someone may have already ruled on it.**

**The self-blinding shape, worth recognising again: expectation and reality corrupted by the
SAME fallback.** The audit derived its expectation through the identical failing resolver it
used to read the ACE, so both widened together and agreed. Any check where the expected value
is computed by the same code as the actual value can only ever confirm itself. This is the
assertion-that-cannot-fail family in a security control.

**A parent-scope `+=` inside a nested function is a silent no-op.** My first BUG-037 fix
appended to `` copying the sibling catch - but that catch is in the OUTER function.
`+=` reads the parent and writes a NEW LOCAL, so the error would have vanished: a fix that
does nothing, in a release about silent failures. AST function boundaries caught it. The file
already documented the correct pattern at L106 for exactly this constraint. **When copying a
nearby pattern, confirm it is in the same scope.**

**"Assume X" in a catch is not automatically load-bearing - check what the SUCCESS path does.**
The fabricated LinkGPO looked risky to remove until I confirmed the read is deliberately
SilentlyContinue, so genuine "not linked" arrives as an EMPTY RESULT and is handled by the
branch above. The catch only ever fired on real failures. Nothing depended on it.

**Report the test that encodes the bug; never edit around it.** One Unit test asserts the
fabricated action ("Adds LinkGPO fallback when Get-GPInheritance throws"). 1572/1 reported
straight, with a suggested replacement that also asserts the warning - otherwise the new test
would pass against a bare `catch {}` and prove nothing.

### BUG-039 / BUG-040 / BUG-041 - the report rendering path, and a fix I had to overrule (2026-09-05T18:40:00+08:00)

**A failing test told me my fix was wrong, and it was right.** My first BUG-041 fix made the
Missing/Mismatch accumulators read both Summary key spellings, mirroring what $totalDrift
already did. It was symmetric, minimal, and made the reported lab arithmetic reconcile - and it
took Integration from 318/318 to 316/318. The two failures asserted `Total Drift: 5` and
`Total Drift: 10`; I produced 3 and 8. Fixing the key names only changed WHICH producer family
the global override discarded. **When a fix makes previously-green tests fail on numbers, the
tests are the measurement and the fix is the hypothesis.** I threw the fix away, not the tests.

**A global formula cannot express a per-producer choice.** The override
`$totalDrift = $totalMissing + $totalMismatched + $totalUnverified` is unconditionally lossy,
because the producers are two DISJOINT families: `Test-TierModelOuAcl` publishes
Missing/Mismatched and NO drift total (which is why the override was added), while
`Test-TierModelGPOAudit`/`Test-TierModelAdmx` publish a drift total and NO breakdown (so the
override drops them). Either way one family dies. Same shape as BUG-036: when the construct
cannot express the problem, MOVE it, do not widen it. Accumulate per result; delete the override.

**Presence is not value.** `Get-SafePropertyValue` returns 0 for "absent" and 0 for "zero".
The whole fix turns on telling those apart - "publishes no drift total" and "publishes a drift
total of 0" need opposite handling. Any helper that collapses absent to a default is unusable
for a decision about whether to derive a value. That needed two new readers.

**A finding object that contradicts ITSELF proves where the bug is not.** BUG-040 looked like
it might be an upstream `$domainDN` resolution failure with prior history. It was not, and the
proof took one look: `ExpectedValue` and `Details` carried the RESOLVED DN while only
`Identifier` carried `{{DOMAIN_DN}}`, in the same object. A resolution failure corrupts all
three together. Five sites re-read the raw `$acl.targetOUPath` instead of the resolved local.
**Before believing a shared upstream helper failed, check whether its other consumers in the
same object are fine.**

**Two raw-path reads I left alone, on purpose.** The MSA/gMSA/dMSA sites sit in the
RESOLUTION-FAILURE catch, where reporting the unresolvable config value is correct. The
`Test-TierModelOuAcl` outer catch keeps the raw path too: if the resolve is what threw,
`$targetOUPath` still holds the PREVIOUS iteration's value, and a silently wrong identifier is
worse than a visible placeholder. **A stale-but-plausible value is a worse bug than the one you
are fixing** - same instinct as declining half the normaliser routing under BUG-033.

**$OFS is a rendering hazard nobody thinks about.** BUG-039 was not a loop bug. An array in a
subexpression inside an expandable string is flattened with `$OFS`, default a single SPACE - 11
findings, 2,267 chars, 2 newlines. The pipeline was perfect. `-join [Environment]::NewLine`.
Reproduced in isolation BEFORE editing, which is what made the cause obvious rather than guessed.

**The family test I was asked to run came back "partly", and the differences mattered more than
the similarity.** BUG-041 shares the BUG-026 family's root cause (hand-maintained reporting
numbers nothing verifies) but breaks its two diagnostic signatures: it is NOT "console right,
artifact wrong" - the consolidated console prints the SAME variables, so both were wrong and
AGREED - and it is not in a scope-branch publish step, so the specs/007 publish guard would not
catch it. **Saying "instance eight" would have been tidier and would have pointed the guard work
at the wrong place.**

**Contradicted the reviewer's severity call on one of three.** Cyclops's "rendering, not loss"
holds for BUG-039/040 - 11 findings in, 11 out. It does NOT hold for BUG-041: the headline drift
count read 8 when the truth was 11, and that number also feeds the NUnit `failures=` attribute a
CI gate keys on. Guarded that a compliant estate still reports 0, so it under-reports rather than
manufacturing a false green - but under-reporting drift is not a cosmetic defect.

**All three bugs converged on ONE producer.** The 8 leaked identifiers, the 8 miscounted
"Missing", and 8 of the 11 concatenated findings are the same 8 `Test-TierModelOuAcl` objects.
When three defects surface from one run, check whether they share a producer before treating
them as independent - it changes what a regression test has to cover.

**Guards over counts.** Proved the compliant estate still reports 0 and an unverified-only OU
still reports 1, using the SHIPPING helpers extracted by AST rather than retyped. The 0-stays-0
guard is the one that matters: it is the difference between under-reporting and a false green.

**BOM re-verified after every write** per the standing BUG-033 rule, including the last one.
Left BUG-042 (Type='Drift' vs re-classified Missing/Mismatch across scopes) unfixed and named.

### BUG-042 / BUG-043 - a recommendation that was necessary but not sufficient (2026-09-05T19:35:00+08:00)

**"Fix it in the producer, not the consolidator" was a false choice, and saying so mattered.**
Beast's instinct was right - `Test-TierModelOuAcl` knew the drift class at every site (it
increments `$missingCount` or `$mismatchCount` right there) and threw it away behind a generic
`Type='Drift'`, which the consumer then reconstructed by substring-matching its own English
prose. But the consolidated body selects on `Type -eq 'Drift'`. Change the producer ALONE and
OU ACL drift vanishes from the `-FullDeployment` report entirely - strictly worse than the bug.
Producer and consumer had to move together. **The producer was not independently wrong; it had
been BENT TO FIT a broken consumer.** When a producer emits a value that only one consumer's
filter understands, ask which one is the defect before "fixing" the other.

**The rendering the bug report treats as CORRECT was itself wrong.** BUG-042 was framed as
"`-OuAclsOnly` re-classifies Drift to Missing/Mismatch; `-FullDeployment` does not", implying
`-OuAclsOnly` was the good one. I ran the verbatim derivation against the producer's four real
Drift shapes: two of them - target OU does not exist, identity does not exist - increment
`$missingCount` but rendered as `[Mismatch]`, because their Details say "does not exist" and
the test looked for "missing". So `-OuAclsOnly` already contradicted its own "Missing: n"
header. **"Make A match B" is only safe once you have verified B.** Had I inherited the
severity call I would have propagated a wrong label into a second scope.

**One projection, two consumers - the shape that makes disagreement impossible.** Rather than
widen the shared filter, I published `DriftFindings` from `Invoke-OuAclAudit`, which is exactly
what `Invoke-OuAudit`/`GroupAudit`/`UserAudit` already do and what the consolidated loop takes
WHOLESALE. Both scopes now read the same array object. Not "both compute the same answer" -
the same objects. Cross-scope consistency by construction beats two projections kept in sync by
discipline, which is what BUG-042 was.

**Measuring the filter found a bug an order of magnitude bigger than the one I was fixing.**
`Type -eq 'Drift'` is a whitelist of ONE producer: an AST sweep showed the other eleven emit
`MissingAcl`/`UnexpectedAcl`/`Mismatch`/`Missing`/`ADMX`/`AuditRight` or are Status-shaped, so
every GPO, ADMX, MSA, gMSA, dMSA, WinLaps, AuditRule, AuthPolicy, AuthSilo and Canonical
finding is dropped from the `-FullDeployment` body. Filed as BUG-044 and deliberately NOT
fixed - it changes every consolidated report and needs Joel's approval. **Before changing a
shared filter, enumerate what currently passes it. Twelve producers, one survivor, is not a
number I would have guessed.**

**I broke it myself and the suite caught me - with the exact defect the surrounding comments
warn about.** My first `-GposOnly` cut read `Summary.MissingGpos` unguarded; Integration went
318 -> 316 with a StrictMode "property cannot be found". That is BUG-032, documented a few
lines away in the same file: a StrictMode throw at report time means a DRIFTED run produces NO
report. I had reintroduced it while fixing a reporting bug. Not a fixture problem, not tuned
around - guarded, and back to 318/318/0. **A breakdown is a nice-to-have; it must never be able
to take the report down.** Third time this month the moved count was the truth.

**Declined to close a residual rather than invent a number.** `Test-TierModelGPOAudit` defines
Drift as missing + mismatch + ERRORED audits, and WinLapsDecryptor as Missing + Mismatched +
Errors, so after publishing the honest breakdown `Missing + Mismatch` can still be less than
`Drift Findings` by that error count. Routing the remainder into `UnverifiedCount` was tempting
and would have made the arithmetic close - but `UnverifiedCount` means "read failures", and
bending a real published counter to make a header reconcile is the BUG-026 family defect
(a figure nothing verifies) wearing the costume of a fix. Recorded the gap with numbers and
sent it up for a ruling. **An artifact that admits a gap is better evidence than one that
hides it behind a derived number.**

**BUG-043 was a pure publish, and proving that was most of the work.** All nine `DriftCount`
assignments diffed byte-identical; exit gate, NUnit `failures=`, compliance %, Html count and
the log record all verified untouched. Only the Text `- Missing:`/`- Mismatch:` lines and the
Json `auditSummary` fields move. **"Does this change a verdict?" is answered by enumerating
every consumer of the number, not by reasoning about the edit.**

**Guards over counts, again.** Compliant estate stays `0 / 0 / 0` with an empty body on both
the OU ACL and standalone paths, using the SHIPPING `Invoke-OuAclAudit` and
`Get-StandaloneBreakdownCount` extracted by AST rather than retyped. Under-reporting, never a
false green.

**BOM re-verified `EF BB BF` after every write** per the standing BUG-033 rule. Also confirmed
`Test-TierModelOuAcl.ps1` never had one (BUG-033 was entry scripts only) rather than assuming.
Reported the one Unit failure straight - `Unit.OuAclOperations.Tests.ps1:981` asserts
`Type='Drift'`, i.e. it encodes the bug - with a replacement that asserts the label AGREES WITH
THE COUNTER, so it cannot pass against a fixed string.

### BUG-044 - a filter is a whitelist, and "blank" is not a verdict (2026-09-05T19:42:00+08:00)

**"Blank" in a sweep means the sweep did not look, not that the code is fine.** Ten producers came
back with no literal `Type`. Six of them turned out not to be in the population AT ALL -
GPOContent and GPOLink are called INSIDE Test-TierModelGPOAudit and collapsed into `$result.Issues`
before any finding object exists; GPO/AuthSiloPrerequisite are never referenced by
Audit-TierModel.ps1; OuExists is an existence probe; Prerequisites is a start-up gate. The other
four were genuinely affected and Status-shaped. Had I treated blank as "unaffected" I would have
shipped a half-fix; had I treated it as "broken" I would have chased four files that cannot reach
the report. **Determine the POPULATION before classifying the members** - the question was never
"what does every Test-* emit", it was "what lands in `$auditResults`". Fifteen entity types, and
the entry script enumerates them in one place.

**The sweep I was handed conflated ResourceType with Type.** Admx was reported as emitting
ADML/ADMX/Error; it emits Missing/Mismatch, and ADMX/ADML are its ResourceType values. Same
lesson as BUG-034: extract key sets AND values, and say which key you matched.

**A filter is a whitelist - enumerate what currently passes it.** `Findings | Where Type -eq 'Drift'`
looked like a category test. It was a single string literal that, after BUG-042 removed the last
emitter that morning, NOTHING satisfied. My own fix hours earlier had quietly reduced the filter's
yield to zero. **A change that makes a downstream filter match nothing is invisible at the point of
change** - the consumer does not error, it just goes quiet.

**The fix was already in the file.** Before designing a projection I checked what -GposOnly,
-AdmxOnly and all eight -Include* branches do: they already call ConvertTo-TierModelDriftFinding.
Choosing the consumer-side shape was not "the cheaper option" - it was the one that makes the
consolidated body and the standalone bodies render the SAME objects through the SAME code. Eleven
new producer projections would have been eleven new things to keep in sync. Same instinct as
BUG-042, second time it paid.

**The compliant trap was real and the shipping helper had already solved it.** Five producers emit
`Type='Compliant'`, three emit `Status='Compliant'`/`'Pass'`. A naive "keep everything non-Drift"
widening trades a false green for a false red - a clean estate reporting findings. The normaliser
drops those by EXACT match, so `NonCompliant` survives. **Proved it rather than asserted it:
compliant estate 0 rows before AND after, with the compliant shapes pulled out of the producers by
AST rather than imagined.**

**The second reason to normalise, which I nearly missed.** The console block interpolates
`$_.Identifier` and `$_.Details`. Raw AuditRule, AuthPolicy, AuthSilo and WinLapsDecryptor findings
carry NEITHER. Widening the filter without normalising would have thrown under StrictMode at report
time on a DRIFTED run - BUG-032 all over again, in the fix for a reporting bug. **Check what the
consumer READS off the objects you are about to let through, not just whether letting them through
is semantically right.**

**`elseif`, not a second `+=`.** Invoke-OuAclAudit publishes BOTH DriftFindings and the raw Findings
it projected from, so normalising Findings unconditionally would itemise every OU ACL finding twice.
And the branch must test the property being PRESENT, not non-empty: a compliant OU/Group/User
result publishes an EMPTY DriftFindings and must stay empty rather than falling through. Presence
is not value - the BUG-041 lesson, in a boolean this time.

**When git cannot give you a BEFORE, measure the BEFORE instead of retyping it.** The whole block
was an ADDITION relative to HEAD (BUG-028 rewrote it the same morning, uncommitted), so there was
no committed prior text. Running a retyped copy would have proved nothing about what shipped. What
the old code produced turns on ONE question - does anything carry the literal `Type='Drift'`? - so
I measured that count against the scenario data: zero. **A derived-and-measured BEFORE beats a
retyped-and-executed one.**

**5 -> 46, and 0 -> 0.** Eleven entity types moved off zero; the compliant estate did not move at
all. Reported the Html `Findings: N` count as a behaviour change even though it is the fix working,
because it is a NUMBER IN AN ARTIFACT and Joel gets to see those named, not discover them. Verdict,
exit code, compliance % and NUnit `failures=` all verified untouched by enumerating every consumer
of the number rather than reasoning about the edit.

**Named a console-only side effect I chose to accept.** Invoke-CanonicalAclAudit prints its own
findings (it takes no -Silent), so canonical drift now appears in Phase 1b AND the consolidated
summary. I judged restating it correct - a summary that omits an entity type is the bug - but a
change I decided is fine is still a change the reviewer should be told about, not one he should
find.

**Recorded a ruling in-code, not just in a decision file.** Joel ruled the GPO/WinLapsDecryptor
arithmetic residual documented rather than fixed. Both KNOWN RESIDUAL comments previously read
"recorded for Joel's decision" - left as-is, the next reader sees an open question and closes it by
inventing a number. Rewrote both to carry the ruling, the date, and the specific instruction NOT to
route the remainder into UnverifiedCount. **A decision that lives only in a decision file will be
re-litigated by whoever is in the code at 2am.**

**Baseline held exactly: Unit 1573/1572/1, Integration 318/318/0.** No new failures; the one
failure is the known `Unit.OuAclOperations.Tests.ps1:981`. Third bug running where the moved count
would have been the truth - this time it did not move, which is its own evidence.

**BOM re-verified `EF BB BF` after every write**, per the standing BUG-033 rule, plus a parse check
(0 errors) after editing. Scratch controls written to the session folder, never the repo; root
ended clean. Nothing staged, nothing committed.

### Stripping BUG-nnn comments from product code - three populations, not two (2026-09-06T10:15:00+08:00)

**The brief framed it as a binary and the code said otherwise.** Pure history to delete, live
constraint to rewrite, "about six" of the latter. The actual population had a large THIRD class:
comments that were already entirely present-tense guidance whose only offence was a `BUG-019: `
prefix - 26 of the form "SilentlyContinue is INTENTIONAL here ... Do not change to Stop." Deleting
those satisfies the letter of the directive and destroys live engineering guidance Joel never asked
to lose; stripping the number satisfies it exactly, because what survives says only what the code is
doing. **Sorting by "is there a bug number in it" gets the wrong answer; sort by what the comment
would cost if it were gone.**

**The test that actually decided each case: would deleting this plausibly make a future maintainer
write a defect?** That sent ~25 `-ErrorAction Stop` justification blocks to the bin - nobody
"improves" an explicit `-ErrorAction Stop` back to nothing, so those comments protected nothing and
were pure narration of the fix - while keeping every `SilentlyContinue` note, which names a
deliberate choice that looks exactly like an oversight. Same shape of comment, opposite verdict,
because the RISK is opposite. 139 ops: 38 deleted outright, 60 number-strips, 41 rewrites.
Reported 41 rather than trimming the list to the six I was told to expect.

**The AST pre-check earned its keep on the first run.** One of my 139 ranges
(`Resolve-TierModelPrincipalSid.ps1` L473..L489) spanned three lines of EXECUTABLE code including a
`Get-ADObject` call, because I had merged two comment runs that had code between them. Validating
every range against Comment tokens BEFORE editing caught it; a line-based strip, or trusting my own
transcription, would have deleted a directory query. **Build the checker that can fail your own plan
before you run the plan.**

**The requested verification was impossible and saying so was the job.** "git diff restricted to
product code must contain only comment removals" assumed HEAD == pre-pass state. All 36 product
files already carried uncommitted BUG-039..044 work, so git diff showed 1822 added / 231 removed
lines, almost none of them mine. Rather than report the contaminated number or quietly substitute a
weaker check, I RECONSTRUCTED the pre-pass baseline from the AST context dump (0 unrecovered lines)
and proved it faithful by re-applying all 139 ops and getting the working tree back BYTE-FOR-BYTE in
all 36 files. Only then is "635 removed / 227 added, 0 non-comment either way" a real measurement.
**When the baseline is wrong, fix the baseline - do not reinterpret the result against it.**

**Two proofs disagreed and the favourable one was wrong to accept.** The line-based diff said PASS;
the AST token-stream cross-check said 26 of 36 files had changed. Chasing it rather than shipping
the green one: the difference was entirely `NewLine` tokens, because removing comment LINES removes
newlines. Excluding NewLine: 0 differences in all 36. **A second check that contradicts the first is
information, not noise - and the one to distrust is the one you wanted.**

**Corrected three factual claims in the brief with evidence.** The named sibling raw-path sites
(`Test-TierModelMsaAcl/Gmsa/Dmsa`) contain NO `BUG-` comments at all - those catch blocks are
entirely uncommented, so there was nothing to strip and I did not add any, since the directive runs
toward less commentary. `tests\` holds 54 mentions across 8 files, not 30. And
`.squad/agents/rogue/charter.md` does not exist - no agent has a charter, only history.md.

**Baseline held exactly: Unit 1573/1572/1, Integration 318/318/0**, single known failure
`Unit.OuAclOperations.Tests.ps1:981`, which is Wolverine's. BOM re-verified `EF BB BF` on both entry
scripts after the final write, per the standing BUG-033 rule, plus a parse check across 84 files
(0 errors). Scratch and the reconstructed baseline live in the session folder, never the repo; repo
root ended clean. Nothing staged, nothing committed.

---

## 2026-09-07 — BUG-045: Enter at the -OutputFileBase prompt must not kill the run

Joel hit it in the lab: `-Logging` with no `-OutputFileBase`, press Enter at the prompt, and the
script threw `OutputFileBase cannot be empty when Logging is enabled`. Three sites, all re-derived
with the AST rather than trusted from the brief (`ThrowStatementAst` + `Read-Host` CommandAst over
both entry scripts): Deploy 306/308, Audit 525/527 (`-Logging`), Audit 488/490 (`-OutputFormat`).
The AST pass confirmed the brief's line numbers exactly and also confirmed the only other
`Read-Host` calls in Deploy are the two Y/N gates at 795/817, which I did not touch.

**The fix is the same shape at all three: prompt shows the default in brackets, empty or
whitespace-only input falls back to it, and the resolved value is echoed once.** The default is
discoverable at the prompt (`... [Deploy-TierModel]`) rather than silently applied, so an operator
who presses Enter can see what they got, and the echo puts it in the transcript. `IsNullOrWhiteSpace`
was already there and stays — whitespace-only is still treated as empty, it just no longer throws.

**Did NOT collapse the auto-enable branch into the prompt branch.** Both now end in the same literal
default, so they look redundant. They are not: D8 requires the auto-enabled path to never even
DISPLAY a prompt, because a diagnostics run must be runnable in a non-interactive host. Merging them
would have been a silent regression that no test in the repo would have caught.

**Proved the auto-enable guarantee instead of asserting it.** Harness outside the repo, six
scenarios in child `pwsh` processes: dot-source `tests/helpers/ADStubs.ps1`, replace `Read-Host`
with a global function that RECORDS every prompt string and answers empty, run the real script.
Deploy `-EnableVerbose`, Deploy `-EnableDebug`, Audit `-EnableVerbose` all recorded **zero prompts**
and still produced `Deploy-TierModel-*.log` / `Audit-TierModel-*.log`. The three explicit paths
recorded exactly one prompt each, carrying the bracketed default, and completed without throwing.
**A recorder beats a mock assertion here — it proves the prompt was never even reached, not merely
that a canned answer was consumed.**

**The diagnostics-hint replay was verified, not assumed.** All six scenarios emitted a re-run line
containing the RESOLVED `-OutputFileBase '<default>'`, including the `-OutputFormat`-only case where
no log file exists at all. NON-BLOCKING-3 still holds: a defaulted value flows into the replay, so
the copy-pasted line does not hit `Read-Host` on the re-run.

**Two tests break, and I did not touch them.** `tests\Integration.Deploy.Tests.ps1:1822` and `:1832`
("Should throw when OutputFileBase is empty string / is whitespace-only while Logging enabled")
assert `*OutputFileBase cannot be empty*`. **They encode the old throw-on-empty behaviour, which is
exactly the behaviour Joel asked to remove — they did not catch a regression.** Reported to
Wolverine rather than edited or worked around. The totals confirm no collateral: Integration went
316 passed / 2 failed out of the same 318, CI-shaped 1924/2 out of the same 1926. **A moved test
count would have been evidence against the diagnosis; the count did not move.**

**Corrected two claims in the brief.** (1) Product code is NOT at 0 `BUG-` references: there are 3,
all pre-existing at HEAD — `modules\TierModel\TierModel.psm1:180` and `:210`, and a `BUG-001..011`
mention inside the `ReleaseNotes` string in `TierModel.psd1:102`. The two ENTRY SCRIPTS are at 0 and
stayed at 0; I added none. (2) The repo has no test coverage for the diagnostics switches at all —
`EnableVerbose` and `LoggingAutoEnabled` appear nowhere under `tests\`. **The D8 guarantee is
lab-confirmed and comment-documented but completely untested**, which is precisely why collapsing
the branches would have gone unnoticed. Worth raising with Wolverine.

**Also updated three comment-based help blocks**, because they stated the behaviour I removed:
Deploy `.PARAMETER OutputFileBase` ("Required when -Logging is specified"), Audit `.PARAMETER
OutputFileBase` ("Required when OutputFormat is specified"), and Audit `.PARAMETER Logging`
("an empty response is an error"). Leaving those would have made the help actively wrong.

**Baselines: Unit 1608/1608/0. Integration 316/318 (the 2 above). CI-shaped 1924/1926 across all 32
test files in one session.** BOM re-verified `EF BB BF` on both entry scripts after the final write,
0 parse errors. Scratch harness lives in the session folder; repo root ended with no new untracked
files. Nothing staged, nothing committed.

---

## 2026-09-07T12:20:00+08:00 — D13 follow-up: the two survivors, and WHY they survived

Two `BUG-023` comments in `modules\TierModel\TierModel.psm1` survived my 155→0 strip pass on
2026-09-06 and were verified as "0 in product code" at the time. Stripped now under the D13 nuance
"keep the rule, drop the history" — number and was-a-bug framing out, engineering constraint kept:

- `:180` `# BUG-023: Load schema for FromConfig so validation is not silently skipped.`
  → `# Load schema for FromConfig so validation is not silently skipped.`
- `:210` `# Schema validation — runs for both FromPath and FromConfig (BUG-023 fix)`
  → `# Schema validation — runs for both FromPath and FromConfig`

Neither needed an authored rewrite. Both were already the third population from the strip pass —
present-tense guidance whose only offence was the number. `:180` still names the live constraint
(FromConfig would otherwise skip validation silently) and its second line, untouched, explains why
the path is resolved locally. `:210` still states what the block does for both parameter sets. No
stubs left behind.

**I found the exact boundary of the too-narrow verification, and it is arithmetically clean.**
`TierModel.psm1` was UNMODIFIED in the working tree before this turn (`git status` empty for it),
so the pass never wrote to it — it was not in the searched set, rather than searched and missed.
The repo has 80 `modules\TierModel\public\*.ps1`, 2 root entry scripts and 2 `optional\` scripts =
**84**, which is exactly the "parse check across 84 files" recorded in my own strip-pass notes. The
36 files the pass edited are 32 of those public cmdlets + 2 entry scripts + 2 optional. **The root
module `.psm1` and the manifest `.psd1` were outside the enumeration entirely, so both the strip and
its verification were blind to them by construction.** Today's correct scope is 86 files.

**Lesson: the file-set enumeration IS part of the measurement, and mine excluded the two files that
are not shaped like the others.** I enumerated cmdlet-shaped files — `public\*.ps1` plus scripts —
and a root module and a manifest are neither. A sweep that defines its population by file shape will
silently exclude the structurally unusual members, which are exactly the ones nobody else is
checking. **Record the file COUNT and the enumeration rule alongside a "0", not just the 0** — "84
files, 0 hits" would have been falsifiable on sight against the repo's real 86.

Anything else measured through the same lens: the parse check, same 84. Nothing else in that pass
depended on the enumeration; the 139 ops were AST-validated per range against Comment tokens.

**Left `TierModel.psd1:102` alone**, per the brief. It is the manifest's `ReleaseNotes` string —
shipped metadata surfaced by `Find-Module`/`Get-Module`, i.e. changelog-shaped release
documentation, not a code comment. D13 governs comments. Joel's ruling pending; I did not pre-empt
it in either direction.

**Verification:** AST tokens at both edited lines are `Comment` (+`NewLine`) only, so no executable
code was in range — same pre-check that caught the `Resolve-TierModelPrincipalSid` near-miss last
time. `git diff` on the file is exactly 2 insertions / 2 deletions, both comment lines. File size
fell 43168 → 43145 = 23 bytes, matching `"BUG-023: "` (9) + `" (BUG-023 fix)"` (14) exactly.
**`TierModel.psm1` has NO BOM** — unlike the two entry scripts — and it still has none
(`53 65 74`); the em dash on `:210` is still `E2 80 94`. 0 parse errors.

**Wider-scope sweep (root `*-TierModel.ps1` + `modules\` + `optional\`, all `.ps1`/`.psm1`/`.psd1`,
86 files): 1 `BUG-` reference — `modules\TierModel\TierModel.psd1:102`.** As expected.

**CI-shaped suite re-run: 1924 passed / 2 failed of 1926**, the same two Integration.Deploy tests my
BUG-045 fix correctly invalidated, which Wolverine is repairing. No movement, as a comment-only
change to the root module should produce. Entry scripts untouched this turn, both still `EF BB BF`.
Nothing staged, nothing committed, no scratch in the repo.


---

## 2026-09-07 — Audit drift reporting: colour, labels, and the "Drift: 0" lie (Joel, lab)

Joel reported "just a simple color bug". It was not. Two defects, both latent since **`f8270cd`, the
initial v1.0.0 codebase** — `git log -S` proved it, and neither came from the v2.1.0 diagnostics
commit. His instinct that the `-Include*` parameters were involved was **right about the trigger and
wrong about the location**: the renderer and the reader were written when the only producers were
OU/Group/User, and the later `-Include*` producers walked into them.

Baseline confirmed with my own eyes before touching anything: CI-shaped **1938/1938/0** across 32
containers, Unit **1608/1608/0**, Integration **330/330/0**.

**The most important thing I learned this turn: I was handed a diagnosis and it was wrong, and I
nearly built on it.** The brief said `Drift: 0` was caused by four hard-coded key names missing the
producers' spellings — "the same defect shape as BUG-039/040/041, exact-name matching across
producers that were never given a shared vocabulary". That model is seductive because it matches the
last six bugs I fixed in this seam. It was not this bug. Every producer publishes `Drift`, `Missing`
and `Mismatched` correctly — I AST-verified all eight before writing a line.

The real cause is a **type**-blindness, not a **name**-blindness: `Get-SafePropertyValue` walks a
dotted path with `$current.PSObject.Properties.Name -contains $part`, and a hashtable's
`PSObject.Properties` are `IsReadOnly, IsFixedSize, IsSynchronized, Keys, Values, SyncRoot, Count`
— **never its keys**. Every standalone section publishes `Summary = @{ ... }`. So the walk fell out
at segment one and returned 0, for every one of them.

**Rule: when a bug looks exactly like the last one you fixed, that is the moment to demand evidence,
not the moment to skip it.** Pattern-matching on my own recent fixes would have had me "unifying the
vocabulary" across eight producers that were already saying the right thing — a large, behavioural,
test-breaking change that would have fixed nothing. Six lines of `pwsh` under StrictMode falsified
the handed-down diagnosis in one shot. **Reproduce the mechanism before you accept the mechanism,
even when it comes from someone who has been right all day.**

**Corollary, and it is the reusable one: `Get-SafePropertyValue`-style "safe" accessors fail SILENTLY
by design, and silence plus the wrong container type is indistinguishable from a clean estate.**
`Checked:` on the very same line was correct, because it used an explicit
`if ($result.Summary -is [hashtable])` branch. One line, two readers, one of them type-aware and one
not. **Any helper that collapses "absent", "unreachable" and "zero" into one value is a false-clean
generator.** I had already written `Test-SummaryKey`/`Get-SummaryCount` for exactly this reason
during BUG-041 — and had used them ONLY in the grand-total loop, leaving the section counter on the
old accessor. **I fixed half a seam and did not check the other half.**

That is the finding I want to remember: **the section counter and the grand total had disagreed ever
since my own BUG-041 change, and the grand total was right.** My intra-artifact reconciliation rule
found this — but only because I applied it. Both numbers now come from two shared functions,
`Get-EntityDriftTotals` and `Get-EntityErrorTotal`, called from both loops. **Prefer one shared
computation over two agreeing ones; two agreeing computations are a future divergence.**

**Trap B was real and I am glad I checked.** `Test-TierModelAuditRule.ps1:177` emits `Type='AuditRight'`
for BOTH outcomes from a single hashtable — `Status = 'Pass'/'Fail'`, `ActualValue = 'Present'/'Missing'`.
A blanket relabel to `MissingAuditRule` would have marked a **passing** audit right as missing,
re-introducing the exact bug the comment at `:345-346` records fixing. Derived the label from the
finding's own state instead. **A type name that encodes the CHECK rather than the RESULT is always
state-agnostic until proven otherwise — grep the producer, never assume.**

**I overruled the brief on Step 3 and I would again.** The instruction was `Error`→`Missing` for
WinLaps Decryptor. That producer has six `Status='Error'` sites; five are genuine could-not-determine
states (ambiguous GPO match, `Get-GPO` throwing, group resolution failing, domain resolution failing,
outer catch). A blanket relabel would report **an unreachable DC as a clean-but-missing estate** —
strictly worse than the `Drift: 0` bug the whole exercise exists to kill, and it would suppress
`COMPLIANCE COULD NOT BE FULLY DETERMINED`. Only `L154` changed, where `Get-GPO -All` **succeeded**
and matched nothing: the GPO is genuinely absent. **"Absent" and "could not determine" are different
states and collapsing them is the single most dangerous edit available in an audit tool.**

**Trap A generalises, and it bit me in a place the brief did not predict.** Fixing the hashtable
blindness made a latent double-count *visible*: `Errors: 2` above one error line, because
`Summary.Errors`, top-level `Errors` and Error-typed findings are three views of one failure and the
code did `Max(a,b) + c`. Shipping the drift fix alone would have regressed the error count from a
correct 1 to a wrong 2. **A fix that makes a previously-unread value readable inherits every defect
that value had while nobody was looking.** Now `Max` of all three — verified it cannot under-count
(`Test-TierModelAdmx` publishes `Errors = 0` beside real Error findings; OU/Group/User publish
`DriftFindings`, not `Findings`, so the third source is absent for them).

**Colour is now derived by severity CLASS, and unknown types escalate to Red.** There were **four**
copies of `$color = if ($_.Type -eq 'Missing')`, not the one the brief named — I only found the other
three by grepping for the pattern instead of going to the quoted line number. **Never trust a
reported line number to be the only instance.** `[Error]` findings had been rendering **yellow**.

**A tooling scar worth keeping: PowerShell's `-replace` mangled the file and I did not notice for one
whole step.** I replaced four identical lines with `-replace [regex]::Escape($old), "...$_.Type"`.
The replacement string went through .NET substitution semantics and the file went from 2,523 lines to
**11,733**, with my helper function duplicated five times. `git checkout --` restored it. **For
literal-to-literal edits use ordinal `String.Replace`, which has no substitution semantics at all —
and ALWAYS assert the match count before AND the residual count after, then re-parse.** My eventual
guard (`before=4 after=0 newCalls=4` and abort otherwise) is the shape to keep. Also: my helper's
docstring quoted the very literal I was replacing, which would have made it a fifth match — **when
you document the string you are removing, you make the document a target.**

**Outcome.** Steps 1 and 2 green in all three shapes. Step 3 breaks exactly one test —
`tests\Unit.WinLapsAclOperations.Tests.ps1:1210`, "GPO not found: Error status in findings, Errors > 0",
asserting `$result.Errors | Should -BeGreaterThan 0` at `:1217`. **It encodes the old behaviour; it
did not catch a regression.** Did not touch it, did not bend the fix. Proved attribution by reverting
only Step 3 and re-running: **1608/1608/0**, so the single failure is Step 3 and nothing else moved.
**Reverting one hunk to attribute a failure is cheap and it converts "a test broke" into
"exactly this decision broke exactly this test" — do it every time.**

Surfaced but did NOT fix: `Invoke-OuAclAudit` maps any Type that is not literally `Missing`/`Mismatch`
to `'Error'`, so `Test-TierModelOuAcl`'s `Type='Warning'` finding renders as a red `[Error]`. Same
defect shape, not in Joel's six, no lab evidence. **A found-and-reported defect outside the brief is
worth more than a silently-fixed one, because it stays Joel's decision.**

**Discrepancy in the brief, recorded because a wrong baseline is a real finding:** HEAD was `6725ab3`,
not `04ab664`, and the tree was not "nothing committed" — `23b5100` and `6725ab3` landed today.
Provenance was checked against the real HEAD. Separately, `.squad/agents/beast/history.md` became
modified mid-session; the tree was clean when I started, so Beast is working concurrently. Left alone.

Hygiene: root **13 files, zero strays**. Both entry scripts still `EF BB BF`; `TierModel.psm1` and
`Test-TierModelWinLapsDecryptor.ps1` still BOM-free. 0 parse errors. Nothing staged, nothing
committed. **`BUG-nnn` count: 1 — `modules\TierModel\TierModel.psd1:102`, unchanged.** *Enumeration
rule: 2 root `*-TierModel.ps1` + all files under `modules\` + all files under `optional\` = 86 files.*
## 2026-09-07 — Audit rule producer alignment (Jobs 1 & 2)

**What landed.** Removed the per-right `AuditRight` findings append from
`Test-TierModelAuditRule.ps1`; routed `Invoke-OuAclAudit`'s findings projection through the
shared `ConvertTo-TierModelDriftFinding` normaliser; reworded four comment blocks that
carried bug history into behaviour-only descriptions.

**Numbers.** Printed findings 410 → 402. Drift counter unmoved at 402. Headline
`402 DRIFT ITEMS` and 0.25% compliance both held exactly as predicted. Domain Audit Rule went
from `Drift: 1` over 9 lines to `Drift: 1` over 1 line. All fourteen sections now reconcile.

**Learnings worth keeping.**

1. *An arithmetic check can dissolve a false choice.* I was asked to pick between "the counter
   reports objects" and "the counter reports findings", both presented as defensible. They were
   not. Drift is divided by TotalChecked to produce a compliance percentage, so counting findings
   yields −1.74% compliance. One line of arithmetic on the downstream consumer eliminated an
   option that had been recommended as the default. When asked to choose between two abstractions,
   look for the formula that already consumes them — it usually has already decided.

2. *Assess the vocabulary before relabelling anything.* Job 2 looked like a one-line remap of
   `Warning` → `Error`. Before touching it I enumerated the producer's complete finding vocabulary
   by AST: eight types, of which only `Warning` was being remapped and genuine `Error` types
   already mapped to `Error`. That is what made the fix provably safe — it cannot suppress a real
   error state. Had `Error` also been in the remapped set, the same one-line change would have
   been a suppression bug. The size of a diff says nothing about the size of its blast radius.

3. *Prove attribution by subtraction, not by assertion.* The suite had one failure. Rather than
   reason about which change caused it, I reverted exactly one hunk and re-ran: 1640/1640/0.
   Restored it: 1640/1639/1. That is a proof, not an argument, and it cost one suite run. Do this
   every time a change lands alongside other agents' work — the totals were moving under me
   (1938 → 1967 → 1970) as Wolverine added tests, and without subtraction I could not have made
   any honest claim about what was mine.

4. *A failing test is evidence, and whose evidence matters.*
   `Unit.AuditRuleOperations.Tests.ps1:464` asserts nine `AuditRight` findings and now gets zero.
   It encodes precisely the behaviour Joel ruled to remove. I did not edit it, did not bend the
   fix to satisfy it, and did not treat it as noise. I reported it with file, line, test name and
   a verdict on which of the two it was. That distinction — encodes-old-behaviour vs
   caught-a-regression — is the only thing that makes a moved test count useful.

5. *Removing a guard because today's producer stopped emitting the shape is how the bug recurs.*
   Job 1 left the `AuditRight` branch in the normaliser unexercised. The tempting cleanup is to
   delete it. I kept it and flagged it instead. A defensive normaliser exists for the producer
   that has not been written yet.

6. *Bug-history comments are a rule I have to enforce on my own output.* I wrote four comment
   blocks explaining what the code *used to* do wrong. That is exactly what Joel prohibits. I
   caught them on a targeted diff scan for history phrasing (`previously|used to|regression|bug`)
   and rewrote them to describe present behaviour. Worth running that scan on my own diff before
   every report, not just on other people's code.

7. *Ordinal `String.Replace` with before/after count assertions, always.* Used it again for the
   comment rewrites: assert exactly 1 match, replace, assert 0 residual, re-parse, re-check BOM.
   Four edits, zero surprises. PowerShell's `-replace` is still banned in my hands on this repo.
## 2026-09-07 — BUG-054, the hardcoded Missing bucket

**What landed.** Four literal `0`s replaced with real counts across `Test-TierModelAdmx.ps1`
(two producer sites) and `Audit-TierModel.ps1` (GPO and ADMX summary blocks), plus the ADMX
producer now publishes `Missing`/`Mismatched` additively on both Summary shapes. Restored the
UTF-8 BOM on `Audit-TierModel.ps1`, which something else had stripped. Suite unmoved at
1980/1980/0.

**Learnings worth keeping.**

1. *Check the mocks before you read a new key.* My first instinct was to read
   `Summary.MissingGpos` directly. The integration suite mocks both producers through
   `New-MockAuditResult`, which publishes neither breakdown — an unguarded read would have
   thrown under StrictMode across roughly twenty tests. Reading the test scaffolding before
   writing the product code turned a predicted twenty failures into zero. When adding a
   producer key, the question is never just "does the producer publish it" but "does every
   shape that reaches this line publish it", and mocks are shapes.

2. *Choose the fallback that preserves behaviour, not the one that looks tidy.* Falling back to
   `0` when the breakdown is absent would have been the obvious default and would have
   re-created the exact "prints 0 over real drift" bug I was removing, inside the mocked paths.
   Falling back to the drift total keeps today's numbers exactly and only improves where real
   data exists. A fallback is a behaviour, so pick it deliberately.

3. *An invariant beats an assertion.* `missingCount + mismatchCount == driftCount` is not
   checked at runtime; it is true because every `$totalFailed++` sits in a branch that sets
   Status to exactly one of the two values. Building the breakdown so it cannot disagree with
   the total is worth more than any test that notices when it does. Same principle as the
   counter work earlier today.

4. *Prove "nothing moved" by running both versions, not by reasoning about the diff.* I staged
   the HEAD producer and the changed producer into identical mirrored directory trees and ran
   both across four scenarios. That caught my first harness being wrong: `$PSScriptRoot` from a
   temp folder made the producer fail its config lookup and return the catch shape, so every
   BEFORE number was a plausible-looking zero. A comparison where one side is silently broken
   reads exactly like a comparison where nothing changed. Always sanity-check that the BEFORE
   side actually did the work.

5. *Both buckets were lying, not just the one reported.* Joel reported `Missing: 0`. Execution
   showed that in the all-missing scenario the report also said `Configuration Mismatches: 60`
   — every missing file was being counted as a mismatch. The reported symptom was half the
   defect. Running the scenario surfaced the other half; reading the line would not have.

6. *Check the BOM every time, not once per session.* I verified `Audit-TierModel.ps1` carried
   `EF BB BF` after my own writes and considered it settled. Two hours later it was gone —
   stripped at 15:46:55 by something that was not me. I only caught it because I re-ran the
   check as a matter of routine before writing. Environment invariants are not monotonic when
   several agents share a tree; re-verify them at the point of use.

7. *Fix the numbers, leave the colours.* The instruction offered the shared classifier for any
   colour work. I declined it here: only the counts were wrong, and recolouring GPO and ADMX
   would have desynchronised them from the five sibling sections that print the same two lines
   in the same colours. Taking an offered tool you do not need is still scope creep.
## 2026-09-07 — BUG-054, and being handed prior art after I had already shipped a design

The lesson worth keeping is not about counters. It is that I built a defensible solution to a
problem this codebase had already solved, and nobody caught it until Beast swept the CHANGELOG
for an unrelated reason. My design reconciled, computed every figure, and hardcoded nothing - it
passed every test I set it. It was still the wrong shape, because `Test-TierModelGPOAudit.ps1`
already had an approved answer and I never looked for one. **Before designing, search for whether
this codebase has already ruled on the question.** The CHANGELOG is a decision record, not a
release artifact.

When the precedent arrived I was asked to say plainly if I had built something different rather
than retrofit a rationalisation. I had, and I said so. The failure mode being guarded against is
real and tempting: my two-bucket version could be described after the fact as "a reasonable
reading of mutually exclusive buckets", which would have buried a genuine design disagreement
under agreeable language. Two designs compared honestly are worth more than one defended.

The deviation I *did* keep - ADMX stays at two buckets - is only legitimate because I stated it
as a deviation with its reasoning, rather than letting it pass as compliance. ADMX's printed
total excludes errors, so a third line there would not participate in the total above it. Same
principle, different arithmetic. Blind mirroring would have reintroduced the exact defect class
the precedent exists to prevent.

**Sweeps need a self-test.** Beast asked me to look for further survivors. The sweep returned
zero, which is precisely the result that most deserves suspicion, since a broken detector and a
clean file are indistinguishable from the output. I ran the same detector against both files at
HEAD and it flagged five - four known, plus one nobody had listed. Only then was the zero worth
reporting. A negative result is evidence only when the instrument has been shown to produce a
positive one.

**A suite failure that was not mine, and how I established that.** The run came back 1979/1/1980
against a 1980/1980/0 baseline. The instinct is to assume my change caused it. Instead:
file mtimes showed `Test-TierModelGroup.ps1` and `Test-TierModelUser.ps1` written at 17:00:46 and
17:01:40, after my last edit at 16:59:59; the diff showed another agent adding a fifth
`$driftFindings +=` for unverifiable groups; the failing assertion is `DriftFindings | Should
-BeNullOrEmpty`. Their in-flight producer change, their test to update. I reported it and left it
alone. Working in a tree with four other agents means "the suite moved" is a question about
authorship first, and mtime plus diff answers it without touching anything.

## 2026-09-07 — a prediction I got wrong, and what it was worth

I predicted zero test movement for the compliance work and got 23 failures. The brief said an
unpredicted change is evidence against the fix, and it was: `Unit.CanonicalAclAudit.Tests.ps1`
extracts `Invoke-CanonicalAclAudit` from the script by brace-matching and executes it alone, so
the shared renderer I had just introduced did not exist in its scope. My prediction was reasoned
entirely from the mock data - every mock has objects checked and no errors, so no mock could
reach a changed branch. That reasoning was correct and still insufficient, because it only
considered what the tests *assert* and never how they *load the code*. A test harness is part of
the interface a function has to honour.

The valuable part is what the failure was evidence *of*. It was not a fixture problem to tune
around; it was the suite telling me that one of those seven functions is contractually
standalone. So I removed the dependency instead of asking for the harness to be changed - the
more so because that site was already correct and its empty-scope state is unreachable, the
domain root always being checked. The uniformity I would have bought was cosmetic; the isolation
I would have spent was real. Six sites share the renderer and one is inline, and that asymmetry
is worth stating out loud rather than quietly buying back with a test edit.

**Matching an existing rule means matching all of it.** The two broken sites were told to "match
the five". The five consult the error count as well as the check count. Honouring only the
empty-scope half would have left GPO and ADMX printing a percentage over an errored audit, and
passing a literal zero error count to dodge that would have been the same hardcoded-literal
defect I had just spent a day removing. Partial conformance to a precedent is how the second
shape gets born.

**Guard the distinction the tool already gets right.** The instruction that mattered most was
that a configured scope resolving to zero live objects already reports drift correctly, and a
fix collapsing that into "nothing configured" would destroy it. I tested it explicitly
(`TotalChecked=3, Drift=3` → `0%` red) rather than reasoning that it was fine. When a brief names
something that currently works, that is the thing most likely to be broken by the repair.

## 2026-09-07 — sweeping for render sites, and stubbing a boundary well enough to be believed

Beast's instruction was that a fix repairing a producer is not finished until every render site
of that producer has been checked. Applying it to someone else's change found a real defect in
my file within minutes: `UnverifiedCount` was rendered in the OU section only, so once Cyclops
extended it to Group and User those sections printed `Missing: 0 / Mismatched: 0 / Total Drift: 2`
— a breakdown that does not sum to the total directly beneath it. Exactly the class of defect
this whole release exists to remove, arriving through the seam between two people's work rather
than inside either one.

The sweep that found it was mechanical: for every producer touched this release, list its
consumers across the product surface, then list every render site of the specific key that
changed. Two greps. The reason it works is that it asks about the *key*, not the file — the
question "who renders UnverifiedCount" has an answer, where "did I miss anything" does not.

**Stub the boundary properly or you will test the wrong branch.** My first attempt to reproduce
the read-failure path produced zero Error findings and I nearly reported that the branch was
unreachable. Two separate defects in my harness: a `Get-ADGroup` stub with no parameter block, so
the call failed on binding rather than inside the try; and, more subtly, the producer's inner
catch is typed on `ADIdentityNotFoundException`, which cannot resolve without the AD assembly
loaded, so the error escaped to the outer catch and produced a plausible, entirely wrong result.
I had to `Add-Type` the exception before the branch under test would run. A harness that reaches
the wrong catch reports confident nonsense, and both wrong answers looked exactly like real ones.

**Report what the evidence shows, including the part nobody asked about.** The same "could not
verify" condition lands in Drift alone through one catch and in both Drift and Errors through
another, so two unreadable groups can present as four problems. It is in Cyclops's file, it is
not green-over-errors, and it was not what I was asked to check — so I wrote it up for a ruling
and did not touch it. Owning a seam means reporting across it, not editing across it.

**On the working tree going quiet.** `git status` came back empty at the end of the session and my
first assumption was that something had gone wrong. It had not: Joel had taken a WIP checkpoint
commit capturing the whole tree, mine and everyone else's in-flight work together. Worth checking
rather than assuming in either direction — the same empty output would also be the signature of
having lost the changes.

### Handover, 2026-09-07 end of day — state and carry-forward

All three fixes are applied and verified; nothing is mid-edit. Both owned files parse with 0
errors, `Audit-TierModel.ps1` at 2670 lines with its UTF-8 BOM intact, `Test-TierModelAdmx.ps1`
at 314 lines BOM-less as it should be. Suite last ran 1982/1982/0. Nothing staged, nothing
committed by me.

Where the two non-obvious ones live, for whoever picks this up:

- **Standalone headline** — the ladder is at L2518-2524, mirroring the consolidated one at
  L1926-1932. Order is errors -> nothing-checked -> drift, and the order is load-bearing: an
  unreachable directory yields TotalChecked=0 *and* an error, so if the empty-scope branch were
  tested first it would report "nothing configured" for a domain that could not be read.
- **Empty scope** — one renderer, `Write-TierModelComplianceLine` at L471, called from six sites
  (L998, L1064, L1129, L1240, L1944, L2263). The seventh, canonical ACL near L1398, is
  **deliberately inline** — `Unit.CanonicalAclAudit.Tests.ps1` extracts that function by
  brace-matching and runs it alone, so a sibling-helper call breaks 23 tests. That site was
  already correct and its empty state is unreachable. Do not "tidy" it into the shared helper
  without changing the harness first.

**A precedent that does not say what it looks like it says.** It was suggested that
`Test-TierModelAuthSiloPrerequisite.ps1:81-88` is the in-codebase model for Joel's Option 1,
because it refuses to pass an empty scope. It returns `Passed = $false` with the message
"Ensure tiermodel-authsilos.json is present and loaded" — that is a *prerequisite* check where an
empty set means the config never loaded, i.e. a real misconfiguration. Option 1 is the opposite
disposition: a legitimately unconfigured scope is **not** a failure, renders grey, and leaves the
denominator. Copying that site's shape into the audit renderer would render legitimate partial
deployments as failures — the exact outcome Cyclops rejected and Joel agreed to reject, and the
same shape as the mistake that produced -1.74% compliance. Good precedent for "empty is never
silently green"; wrong precedent for how to render it.

Still open, none of it blocking: the 15:46:55 BOM stripper on `Audit-TierModel.ps1` (cause
unknown, content was undamaged); the now-stale ADMX exemption in the `DriftCount` ratchet in
`Unit.AuditReporting.Tests.ps1`, which is Wolverine's to retire; the `AuditRight` normaliser's
third-state branch, which is correct but unexercised by any test; and the ruling owed on whether
an object that could not be verified belongs in the drift bucket, the error bucket, or both —
today it depends on which catch fires in `Test-TierModelGroup.ps1`.

## Learnings

### 2026-09-08 09:32 +08:00 - Rule 23 instance seven: the renderer did not listen

Cyclops closed the producer sweep with "the producers are honest; the question is whether the
reporting layer listens." It was not. `Get-TierModelFindingColor` (Audit-TierModel.ps1:407)
classifies by severity CLASS and carries a comment block that IS the specification. Six render
sites print `[$($_.Type)]` coloured by `$color`. Four called the classifier. Two - the GPO Audit
Findings block and the ADMX Audit Findings block - carried their own inline `switch ($_.Type)`
with a `default { 'Gray' }` arm. Both now call the classifier. Each site keeps its own
Write-Host format string verbatim; only the colour computation changed.

**I was asked to confirm the framing and it was half wrong, so here is the measured version.**
I enumerated every Type both producers can emit before editing, and the honest answer is that
neither can reach the grey arm today:

- `Test-TierModelAdmx.ps1` emits exactly `Missing` (L122, L189), `Mismatch` (L147, L214) and
  `Error` (L302, the wholesale-failure shape). `Findings` is built only at those five sites.
  Provably closed at three values.
- `Test-TierModelGPOAudit.ps1` L420-426 computes `Missing` / `Error` / `Mismatch` and has a
  fourth arm, `default { 'Unknown' }`. That arm is **currently unreachable**, because
  `OverallStatus` is set by an exhaustive if/elseif/else at L354-368 to Pass, Error or Fail, and
  the only object initialised with `OverallStatus = 'Unknown'` (L312) is appended to
  `$auditResults` at L371, i.e. after the assignment. A throw in between skips the append.

So `MissingAcl`, `MissingAuditRule`, `Unverified` and `Failed` do **not** reach these two lists
today - those come from the MSA/gMSA/dMSA/WinLAPS/AuthSilo producers, which render elsewhere.
The "tool currently lies in grey" framing is not supported by the code. What IS supported: a
developer wrote a `default { 'Unknown' }` arm in the producer expecting it to mean something,
and the renderer would have painted it grey - the colour we have just assigned to "nothing
configured / not checked". The fix is correct as defence-in-depth and for consistency, and it
converts a latent lie into an impossible one, but it is not a live customer-visible defect. I
am recording that plainly rather than inflating it to match the dispatch.

**D13: five `FINAL-2` identifiers, all five stripped, explanations kept.** Verified count
independently rather than trusting the dispatch - it was right, five. Lines 1019, 1085, 1150,
1267, 2279 before the edit. Four were the form `(see FINAL-2).`; one, L1019, was the different
form `# FINAL-2: no drift findings...` and needed its own replacement - a single blanket
replace would have left it. Zero `FINAL-n`, `BUG-nnn` or `T-nnn` remain in the file.

**Three tests now fail, and they are information, not damage.** In
`Unit.AuditReporting.Tests.ps1`: "Hands the classifier result... to every converted render site"
(L1012, expects 4 delegating sites, now 6), "Colours [Error] red at the two render sites that do
NOT use the classifier" (L1036, expects 2 inline switches, now 0), and "Routes every
drift-finding render through the classifier" (L1062, expects 4 call sites, now 6). Every one of
those literals pins the pre-fix SPLIT as the specification. The behavioural assertions in the
same tests still pass: six coloured render sites, zero exact-literal `-eq 'Missing'` rules.
The second test is now moot by name - there are no sites that do not use the classifier. I did
not touch them; `tests\` is not mine. Raised to the inbox for Wolverine.

This is rule 22 territory as much as rule 23: `Should -Be 4` and `Should -Be 2` were derived
numbers - consequences of how many sites happened to have been converted - written as literals.
The invariant that survives the fix is "delegating + inline == 6 and inline == 0", not "4 and 2".

**Method note, cheap and it paid.** `[string]::Replace` on the full CRLF text after asserting
the block occurs exactly 2 times, then re-measuring bytes, BOM, bare-LF count, line count and
parse errors. Line delta was exactly -10 (two 6-line blocks to one line each), which is the
number I predicted before writing. Call sites counted with the AST, never grep. The classifier
was lifted out of the shipping file via its FunctionDefinitionAst and executed against
'Unknown' to confirm Gray became Red - executed, not read, because reading is how I got
yesterday wrong.

### 2026-09-08 10:43 +08:00 - the entry scripts are now linted, and the "one line" was not one line

`Deploy-TierModel.ps1` and `Audit-TierModel.ps1` (6,276 lines of shipped orchestration, where
most of this session's fixes landed) appeared in `ci.yml` only as `Copy-Item` lines. They are
now analysed by the lint job. Measured against CI's real 13-entry exclude list, **read out of
`ci.yml` by regex rather than retyped**: 0 issues, entry scripts and modules alike.

**Anti-vacuity first, because a zero from a path that matched nothing is not evidence.** With no
exclude list the same two files report 1,082 issues (691 `PSAvoidUsingWriteHost`, 384
`PSAvoidTrailingWhitespace`, 3 `PSAvoidUsingEmptyCatchBlock`, 2
`PSUseShouldProcessForStateChangingFunctions`, 2 `PSUseSingularNouns`) - all five rule names are
in CI's exclude list, which is exactly why the honest total is 0. I also ran the finished step
against an injected known-bad file and confirmed it exits 1. **The gate is green because the
code is clean, and it is provably still able to go red.**

**The dispatch said one line. It could not be one line, and finding out why was the whole job.**
`Invoke-ScriptAnalyzer -Path` is `[string]`, not `[string[]]` - passing an array throws
"Cannot convert System.Object[]". The obvious fix is to pipe the paths in, which *does* bind.
**Do not do that.** Piping multiple paths with `-ExcludeRule` intermittently throws
`Collection was modified; enumeration operation may not execute.` - it fired on 1 of 3
identical consecutive runs. The run still reported 0 issues and **still exited 0**. That is a
race that silently drops files from analysis and reports a pass while doing it: the same shape
as BUG-044's confidently-empty report, in the tool we were adding to *catch* that class of bug.
Had I written the tidy one-liner and checked it once, it would have passed and I would have
shipped a flaky false-green.

So the step now loops over three targets accumulating `$results`. That forced dropping
`-EnableExit`, and the reason is worth keeping: **`-EnableExit` sets the exit code via
`SetShouldExit` and does NOT halt the script** - I proved this, the statement after it ran and
the code (466) still landed. With several invocations the LAST one wins, so a clean entry-script
pass would have overwritten a dirty module pass with exit 0. `-EnableExit` is only safe when
there is exactly one invocation. Replaced with an explicit `exit $results.Count`, placed after
the `Export-Csv` so the artifact survives a failing job.

**Security pass: measured, not widened, and deliberately so.** The second invocation's six
`-IncludeRule` security rules report 2 issues on the entry scripts - both
`PSUseShouldProcessForStateChangingFunctions` on `Stop-TierModelDiagnosticsTranscript`. Both are
Warnings, and that job only fails on `Severity -eq 'Error'`, of which there are 0; the current
green baseline already carries 3 hits of the identical rule. So widening it is safe by that
job's own gate. I still did not do it: my brief said stop at any non-zero measurement, and
release day is not when I override a safety rule on my own authority. Recommendation recorded
for Joel. Worth noting the oddity while it is in view - that rule is *excluded* by name from the
main lint pass and *included* by name in the security pass, so the repo currently both ignores
and enforces it.

`CodeCoverage.Path` untouched, confirmed by diff. Neither entry script was reformatted.
