# cyclops — History



## Session -04 — Config Validation Wire-In Finalization & Scribe

**Status:** COMPLETE — BUG-022/023 CHANGELOG entries finalized, known-bugs.md trimmed, orchestration documented.

This session completed the config-validation wire-in work (BUG-020..023):
- **BUG-022 CHANGELOG correction:** Stale entry re-reviewed; GPO link enforcement classification confirmed
- **BUG-023 CHANGELOG entry:** Added; documents FromConfig schema validation fix
- **.research/known-bugs.md trimmed:** BUG-019 only (others superseded or fixed)
- **Line number verification:** Deploy secondary-config-load L2914, Audit L1474 independently confirmed before any edits
- **Orchestration logs:** Cyclops, Beast, Wolverine, Rogue work documented and verified

**Commit:** c973611 "Wire config validation into Deploy/Audit and fix silent-pass defects (BUG-020..023)" — 9 files, Unit 1,573/0, Integration 318/0, lab validation passed.

---



## Learnings

### Session -05 — `-EnableVerbose` / `-EnableDebug` Implementation Plan (2026-09-05)

**Deliverable:** `.research\verbose-debug-implementation-plan.md` — 20 ordered work items, 7 POC-first uncertainties, D6/D8 recommendations. Plan only; no production code touched.

**Structural finding that reshaped half the plan.** `Audit-TierModel.ps1` has **no `-Logging` switch, zero `Write-TierModelLog` call sites, and never calls `Initialize-TierModelLogging`.** Its `-LogPath` is a *report output directory* (L1620-1626), not a log directory. So "auto-enable `-Logging`" (D8) is undefined for Audit, and Audit parity is net-new work (WI-12: add `-PassThru` to the L229 import, then wire module-scope logging with Deploy's `& $module { Initialize-TierModelLogging }` idiom from L411-416) — not a copy-paste of Deploy. The design doc did not surface this; only reading the file did.

**The design doc's Flaw 1 is already 9/13 closed.** Both entry-script imports (Deploy L403, Audit L229) and 4 sites in `Test-TierModelPrerequisites.ps1` (L234/291/355/748) plus 2 WinLaps files already carry `-Verbose:$false`. Only 4 `Import-Module ActiveDirectory` sites remain bare: `Get-TierModelAuditRule.ps1` L105, `New-TierModelAuditRule.ps1` L93, `Resolve-TierModelPrincipalSid.ps1` L423, `Test-TierModelAuditRule.ps1` L106. **The "highest-value polish item in the feature" was mostly already done** — the doc's framing was stale. Verifying against disk turned a 60-line-noise crisis into a four-token fix.

**`Test-TierModelPrerequisites.ps1` L212 is a decoy.** It matches `Import-Module` but is a string inside a Pester advisory message, not a call site. Anyone sweeping imports by grep will edit it. Wrote it into the plan explicitly.

**Line numbers: 100% of the design doc's were stale.** Deploy `"GPO planning failed"` is L1387, not the doc's L1284. Audit's PS-version gate is L210, not L212. Deploy is 3,235 lines, Audit 1,678. Re-derived every anchor from disk before writing a single one. This is the third session running where trusting a prior document's line numbers would have produced a wrong edit.

**Reused rather than re-derived:** Beast's `.research\debug-switch-poc\README.md` already proved the WhatIf landmine (`Add-Content` suppressed without `-WhatIf:$false`) and `finally{}` restoration hygiene. Deploy is `[CmdletBinding(SupportsShouldProcess)]` at L171 — so the landmine applies to it and **not** to Audit (`[CmdletBinding()]` at L126). That asymmetry is deliberate and is commented in the plan so nobody "fixes" it later.

**Beast's Mode B/C comparison is scaffold evidence, not production evidence.** It ran in simulate mode against a `New-Module` dynamic module; its own README flags that dynamic modules inherit script scope while the real `.psd1` does not. Made it POC-4 (re-run live) rather than cite it. Same treatment for the `-Verbose` target-DN capture that justifies D9's 31-site sweep: gated the entire sweep (WI-17) on POC-5 re-confirming it on WS2025/PS7.5.1, because that capture predates the 2026-09-04 platform correction. **Do not spend 3-4 h across 17 files on an unre-verified premise.**

**D6 (unredacted transcript) — recommended ACCEPT, do not attempt redaction.** Verified `Write-TierModelLog.ps1` L63-70 myself: exact top-level keys only, no nesting, `$Message` never inspected, and L79-88 interpolate `$Message` straight into the console string. The "redacted JSON vs raw transcript" framing is false and must be retired from docs. Redacting a transcript is unachievable without reviving the withdrawn v1 sink, and a half-working redactor is **more** dangerous than none because it converts an understood risk into an assumed safety. Safeguard is 4 warnings, one of which lives *inside* the transcript file so it travels with the file.

**D8 (auto-enable `-Logging`) — recommended YES, with two hard conditions.** The surprise objection is to *silence*, not to the behaviour; one announcement line neutralises it. Condition 1: **never `Read-Host`** — Deploy L233-238 prompts for `-OutputFileBase`, and the D3 hint prints a command containing both switches, so a prompt on that path ships a hang into an unattended re-run. Condition 2: one-directional; `-Logging` must never imply diagnostics.

**Collision confirmed live.** `git status` during this session showed 13 modified files under `modules/TierModel/public/` — Rogue's BUG-019 work in flight, including `New-TierModelGpo.ps1` and `Get-TierModelGpo.ps1`, which are exactly WI-17's targets. Staged the plan so Stage B (both entry scripts, 12 items) touches zero `modules\` files and can run today at full speed, with a hard gate before Stage C. Declared "wait", not "coordinate" — a three-way merge on Tier 0 AD call sites is how an `-ErrorAction Stop` gets silently dropped.

**Scope discipline.** W2 (~40 GPO catch blocks) is valuable and related, and the temptation to fold it in was real — the switches without W2 faithfully surface catch blocks that already threw the useful part away. Put it in a walled-off §8 with a re-derived 12-20 h estimate (the doc's own 6-8 h was withdrawn by its author) and an explicit "nothing here is agreed."

**Methodology.** Applied Joel's POC-first rule as a register with 7 numbered entries, each with a named deliverable file and a pass condition, plus a standing instruction: *if you hit an uncertainty not in this table, add a row and POC it — do not resolve it inside `Deploy-TierModel.ps1`.* The rule only holds if it is cheaper to follow than to bypass.

---
### Session -05 addendum — Audit `-Logging` gap and the parked patch (2026-09-05)

**Joel supplied a parked patch mid-session:** `…\session-state\…\files\logging-branch-patches\audit-logging-switch.patch`, written earlier and deliberately held back for this branch. It adds a real `-Logging` switch to Audit with Deploy's semantics. This **resolved OPEN-A1**, which I had raised in the first draft as a deliberately-deferred product decision. My call there ("give Audit a diagnostics-only log channel, do not bolt on `-Logging`") was the wrong shape — not because the reasoning was bad, but because I did not know a decision already existed. **Check for parked artefacts before deferring a decision as "separate work."**

**Plan restructured 20 → 21 items.** Split the old WI-12 into WI-12 (add `-Logging` per the parked patch) and WI-13 (hang diagnostics off it), then renumbered 13-20 → 14-21. Did the renumber with a descending regex pass over the whole file so every cross-reference (blocked-by table, §3 diagram, D6 safeguard table, definition of done) moved with it — cheaper and safer than hand-editing each reference.

**Answer to "does Deploy have the same gap?" — NO, verified.** Deploy L403 captures the module with `-PassThru`; L411-416 performs the module-scope `Initialize-TierModelLogging` call gated on `$Logging -and $script:LogFilePath`; Deploy has 30 entry-script `Write-TierModelLog` sites. **Deploy's `-Logging` is fully wired and is not hollow.** The gap is Audit-only. Historical reason: the module-scope initialiser was W3, implemented 2026-09-03 — Deploy was wired then, Audit was not, because Audit had no `-Logging` switch to hang it off. This was worth stating explicitly and loudly in the plan, because "our existing `-Logging` might be partly hollow" is exactly the kind of doubt that spawns unnecessary remediation work.

**Patch line-number drift, measured rather than assumed.** Hunk `@@ -88` → real anchor L90/91; `@@ -154` → L156; `@@ -225` → L227; `@@ -1637` → L1676. Recorded all four in the plan so the implementer re-applies by hand against verified anchors instead of fighting a failed `git apply`. Consistent with Audit's +37 lines from yesterday's BUG-022 wire-in.

**Review finding on the parked patch itself.** Its end-of-run hunk resolves `$auditSummary` via a defensive double `Get-Variable` lookup (`-Scope Script`, then unscoped). Unnecessary: `$auditSummary` is a plain hashtable initialised unconditionally at Audit L261-263 with `TotalChecked`/`DriftCount` already present. Told the implementer to confirm and simplify. Note the real hazard nearby — `Set-StrictMode -Version Latest` is live at L161, so a *missing* hashtable key throws; the right defence is confirming the keys exist, not hunting scopes.

**The `-Verbose:$false` preservation trap.** Both entry-script imports already carry it (Deploy L403, Audit L229). WI-12 rewrites the Audit import line to add `-PassThru` — and dropping `-Verbose:$false` in that single edit would reintroduce the full ~60-line module-load noise on every diagnostics run, i.e. re-open Flaw 1 / D5, "the highest-value polish item in the feature." Added a targeted test (WI-20 item 13) on top of the general import invariant (item 9). **The most likely way to break a thing is to edit the line it lives on for an unrelated reason.**

**Lab matrix grew 12 → 16 rows** using the full verified switch inventory (7 scope, 6 include/enable, `ConfirmApply` Deploy-only, `OutputFormat` Audit-only). Deliberately did **not** attempt the cross-product. Picked representatives and instead wrote down the invariant that must hold universally: **diagnostics switches change only what is *recorded*, never what is *decided* or *written to AD*.** Row 14 tests that invariant directly by diffing applied/skipped/error counts against a switch-free run.

---
### Session -05 addendum 2 — POC-8 refutes the `-Verbose:$false` shortcut (2026-09-05)

**Joel proposed downgrading Flaw 1 / D5** from a work item to a constraint-to-preserve, reasoning that an explicit `-Verbose:$false` overrides `$global:VerbosePreference` for that call, so ordering wouldn't matter. He explicitly asked me to verify in the lab rather than take it on trust. **I POC'd it and it is refuted for our own module.**

`.research\verbose-vs-debug-poc\guest\Test-ImportVerboseOverride.ps1` (local, no AD), results in `results\import-verbose-override.json`:

| Module | Pref set | `-Verbose:$false` | Verbose records |
|---|---|---|---|
| TierModel.psd1 | before | no | 343 |
| TierModel.psd1 | before | **yes** | **163 — still noisy** |
| TierModel.psd1 | **after** | no | **0** |
| Microsoft.PowerShell.Archive | before | no | 46 |
| Microsoft.PowerShell.Archive | before | **yes** | **0** |

**Mechanism:** `-Verbose:$false` suppresses the *engine's* import narration (`Loading module from path…`, `Exporting function 'Get-GPO'.`) — hence 46 → 0 on a binary-manifest module. It does **not** suppress `Write-Verbose` executed **inside the module body during import**, which runs in module scope and inherits `$global:VerbosePreference`. `TierModel.psm1` emits `"Looking for public files in: …"`, `"Found N public files"`, and **`"Loading: <file>"` once per public file** — 84 files → the 163 residual records. Only ordering reaches those.

**So the two mechanisms are complementary, not alternatives.** Ordering covers our own script module; `-Verbose:$false` covers downstream binary modules imported after preferences are live (which ordering cannot protect — the four bare AD imports WI-17 fixes). Kept both; said so explicitly in the plan.

**The design doc understated this.** It said "~60 lines". Measured: **163**. The "highest-value polish item in the feature" was, if anything, undersold — and I would have shipped a plan that quietly dropped it had I accepted the reasoning without measuring. **This is the single best return on the POC-first rule so far: a plausible, well-argued, senior-sourced simplification that was wrong for our specific module, and only a five-minute experiment could tell.** Generic PowerShell reasoning does not survive contact with a script module that narrates its own load.

**Correction to Finding 1 — `TierModel.psm1:45` is NOT a reusable helper.** Verified: `Initialize-TierModelLogging` is declared at L14, and **L45 sits inside that function's own comment-based-help `.DESCRIPTION`** — the `& $module { param($p) … } $path` line is a usage *example*, not code. Grep returns exactly two hits in the whole psm1: the declaration and that example. There is nothing higher-level to call; the `& $module { … }` idiom **is** the API, and `Deploy-TierModel.ps1` L411-416 is the reference implementation to copy. Building a wrapper would require exporting it, which adds a public function and trips three assertions in `Unit.ModuleManifest.Tests.ps1` — exactly what the psm1's own comment block warns about. **A line number inside a comment block reads identically to a line number in code when you only have the grep hit.**

**Correction to the version-string claim.** Audit **does** have a version string: `Version: 2.0` at **L123**. The reported "0 hits" was a false negative — `Version:` returns 2 hits in Audit (L123, and L213's `"Current version: PowerShell …"` fail-fast text). So it is a **staleness** problem in both files, not an **absence** in one: Deploy L167 `1.3.0` / L168 `(v1.3.0+)`, Audit L123 `2.0`, against `ModuleVersion = '2.1.0'`. Flagged for Joel; did **not** renumber unilaterally, since version bumps travel with a CHANGELOG entry and that is Scribe's/Joel's call.

**Also noted:** Audit's `.NOTES` (L122-124) omits the PowerShell 7.0+ requirement despite the hard gate at L210, where Deploy's L168-169 states it. Recommended parity in WI-16.

**Net effect on the plan:** Audit needs **three** new `.PARAMETER` entries (`Logging`, `EnableVerbose`, `EnableDebug`), Deploy only two — because Deploy already documents `-Logging` at L128-132. Same asymmetry as the code: Audit needs both halves (switch + module-scope init), Deploy needs neither.

---

### Addendum 3 — 2026-09-05 (POC round: WI-01/02/03 executed)

Ran the three gating POCs locally before any implementer touched a production script.
Three of the four results contradicted assumptions in my own plan; all three were corrected in place.

- **POC-1 (`Test-PrefRestore.ps1`, 6 exit shapes x 5 strategies).** `try/finally` is the ONLY
  strategy restoring globals on all six shapes. `finally` DOES run on `exit` and on a genuine
  Ctrl-C (raised via `[powershell]::Stop()`, i.e. a real PipelineStoppedException, not a proxy).
  `Register-EngineEvent PowerShell.Exiting` fired **0/6** — it is a session-exit event, not a
  script-exit event; never propose it for this. Script-scope `trap` covers `throw` only.
  Restore-at-each-exit covers 5 shapes and fails exactly on Ctrl-C.
  LESSON: I measured the cheap no-reindent option (`trap`) *specifically* because the expensive
  option costs a ~3,000-line reindent of a Tier 0 script. Proving the cheap option fails is what
  justifies the expensive one. Never impose a large diff without first killing the small one.

- **POC-2 (`Test-TranscriptWhatIf.ps1`).** All five filesystem cmdlets are suppressed under
  `-WhatIf` (`New-Item`, `Start-Transcript`, `Add-Content`, `Set-Content`, `Out-File`), and the
  rescue is PER CALL — I left `Out-File` undefended and it stayed broken, which turned out to be
  the most useful row in the table.
  BIGGEST FIND: `Start-Transcript` under `-WhatIf` throws NOTHING and creates no file. The
  obvious `try { Start-Transcript } catch { warn }` reports success and prints a path to a file
  that does not exist. Success must be confirmed with `Test-Path`, never inferred from the
  absence of an exception. Generalise: for any ShouldProcess-aware cmdlet, "no exception" is not
  evidence of an effect.

- **POC-3/POC-6 (`Test-NestedTranscript.ps1`).** I had the transcript hazard backwards. The
  nested `Start` is SAFE (transcripts stack; the operator's keeps receiving output). The hazard is
  the unpaired `Stop`: if our `Start` failed while the operator has their own transcript running,
  an unconditional `Stop-Transcript` SUCCEEDS and stops THEIRS. A `catch {}` does not protect
  against this because nothing throws — it just hides that we destroyed their change record.
  Guard on a boolean, not on an exception.
  Path resolution: `Resolve-Path`/`Convert-Path` throw on not-yet-existing paths, and
  `[System.IO.Path]::GetFullPath()` resolves against the .NET current directory, which does NOT
  track PowerShell's location (measured: PS in TEMP, .NET still in the repo root). Mandated idiom
  is `$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath()` + `Join-Path`.

- **Process finding, more important than any of the above.** The brief stated BUG-019 had landed
  and `modules\` was free. Verified: `git log` head is `04ab664` (a .squad commit) and
  `git diff --cached` is EMPTY. BUG-019 is 27 UNCOMMITTED working-tree files. Additionally
  `Audit-TierModel.ps1` had already been modified (+105/-5, now 1,778 lines) — WI-11 and WI-12
  were implemented ahead of the POC gate the brief itself set.
  Worst of it: `EnableVerbose`/`EnableDebug` are declared at L174/L177 and referenced NOWHERE
  ELSE. Passing them today is a silent no-op. A diagnostics switch that does nothing is worse
  than an absent one — it manufactures false confidence precisely when something is already
  broken. Recorded as a blocking gate in the plan's Definition of Done.
  LESSON: verify the tree state myself even when the state is asserted in the brief, and
  especially when the assertion is what unblocks my work. `git status` and `git log` are two
  commands and they changed four sections of the plan.

---

## Addendum 4 — 2026-09-05, POC-9/POC-10 and three corrections from review

**POC-9 removed a ~2,000-line reindent from the plan.** Joel asked whether `$global:` was needed at all, given we already have the `& $module { ... }` idiom. Measured with `Test-ScopedPreference.ps1` (4 modes, fresh runspace each, real production functions as probes):

| Mode | Verbose | Debug | Global leaked | Ctrl-C leak |
|---|---|---|---|---|
| `$global:` | 4 | 1 | YES | YES |
| `$script:` only | 0 | 0 | no | no |
| `$script:` + module scope | 4 | 1 | **no** | **no** |

Script+module scope reproduces `$global:` exactly and cannot leak, because scope teardown does the work `finally` was going to do. `$script:` alone reaching 0 is the control that proves module scope is genuinely required — which also explains why `$global:` was chosen originally. WI-06/WI-14 rewritten; WI-08/WI-15 lost their preference half entirely; OPEN-A3 resolved then reversed.

**POC-10 stopped me over-claiming.** Having just deleted the `try/finally`, I checked whether the transcript got the same free ride. It does not: after a genuine interrupt the transcript is **still open and still capturing** — post-interrupt output landed in the file. Because the transcript is unredacted and D6 anticipates customers emailing it to us, that is a security finding, not untidiness. Raised as OPEN-A6 with both options costed, plus a new safeguard S5. **Did not decide it** — POC-9 removed the engineering justification for the reindent, so what remains is a security/review-cost trade that belongs to Joel.

**Learning — the pattern that keeps paying.** Three times now a measurement has reversed a design I had already written down and justified at length (POC-3 inverted the transcript hazard, POC-8 refuted the reviewer's `-Verbose:$false` reasoning, POC-9 refuted my own `try/finally` decision). The discipline that produces this is cheap: **when a design implies an expensive change, spend an hour trying to kill it before imposing it.** Note that POC-9 was Joel's idea, not mine — I had accepted my own conclusion and stopped looking. Worth remembering: *my* measured conclusions deserve the same adversarial pass I give other people's.

**Three corrections I got wrong, recorded so I do not repeat them:**

1. **"BUG-019 is not committed" was a false alarm.** Uncommitted is *by design* on this branch — Joel reviews everything manually before any commit. I inferred a process failure from a state I had not confirmed was abnormal. **Rule: before flagging tree state as a problem, check whether it is the team's deliberate convention.** The consequence that did survive: Stage C can never "rebase onto Rogue's commit", so it was rewritten for a single uncommitted working tree.
2. **"Audit's dead switches are a defect" was mis-framed.** They were scoped as declaration-only pending my own POCs. My *framing* was kept verbatim as a pre-merge gate — a diagnostics switch that silently no-ops is worse than an absent one — but I asserted a defect where I should have asked about intent.
3. **OPEN-A4: I defended an accident.** I recommended keeping Audit's non-prompting `-Logging`, not knowing it existed only because of a mis-scoped instruction given 30 minutes earlier. The fact that settles it was on disk and I had not weighted it: **`Audit-TierModel.ps1:241` already prompts for that same variable.** So prompting matches both existing behaviours and silence invents a third. **Rule: when recommending that as-built behaviour be kept, first establish whether it is established behaviour or a fresh accident — and search the file for prior art on the same variable.**

---

### Addendum 4 — 2026-09-05 — Lab validation harness built and self-reviewed

Deliverable: `.research\lab-validation\Invoke-LabValidationMatrix.ps1` (44 rows) + `README.md`.
Written while Rogue held `Deploy-TierModel.ps1`, `Audit-TierModel.ps1` and `modules\`; I read
those files and wrote only into `.research\`. Not run against the lab — that is Joel's step 3.

**The single most important design decision: the harness must be able to fail, and I proved it
rather than asserting it.** After the happy-path self-test went 10/10 green against stub
scripts, I injected two regressions into the stub — `[System.IO.Path]::GetFullPath()` for the
log directory, and a transcript that is announced but never started — and re-ran. Both were
caught with the correct diagnosis in the `reason` field. Crucially, **the absolute-path row did
not notice the path bug at all**, which is the empirical confirmation of POC-6's claim and the
justification for the relative-path rows existing. A green harness that has never been shown to
go red is a decoration.

**Two real defects surfaced only by executing it, both fatal to the whole exercise.**
1. **PowerShell ARRAY splatting mis-binds switch parameters.** `@('-EnableVerbose','-EnableDebug')`
   splatted into a script fails with *"A positional parameter cannot be found that accepts
   argument '-EnableDebug'"*. Array splatting is positional; only **hashtable** splatting binds
   named switches. Every diagnostics row would have died at parameter binding.
2. **`exit` inside a script invoked with `&` does not set the caller's process exit code.** The
   child runner returned 0 for every failure row until it began propagating `$LASTEXITCODE`.
   And reading `$LASTEXITCODE` directly *throws* under `Set-StrictMode -Version Latest` when it
   has never been set — `Get-Variable -ErrorAction SilentlyContinue` is required.
   LESSON: both bugs are invisible to a parse check. `ParseFile` returning 0 errors told me
   nothing about either. Static validation of a harness is close to worthless; it has to run.

**A check I wrote was wrong on the merits, and only reading the source caught it.** I initially
asserted that the transcript must contain `Diagnostics enabled: … -EnableDebug`. It cannot:
Deploy prints that line at L662, and `Start-Transcript` runs at L676. A *correct*
implementation can never satisfy that check. Split into two honest assertions — the
announcement is asserted against the captured console (proves the branch ran), and transcript
content is asserted against the `UNREDACTED` banner, which the scripts emit at L682-687,
*after* the transcript starts. **When designing an assertion about ordering, derive it from the
source line numbers, not from the feature description.**

**Refused to write a check that cannot fail, and said so in the README instead.** The repo has
**4** `Write-Debug` sites total (`New-TierModelOu` ×2, `Repair-TierModelCanonicalAcl`,
`Write-TierModelLog`) and **0** `-Level 'Debug'` log calls — and none are on a plan-only path;
two live inside OU creation, which needs `-ConfirmApply`. So **a plan-only run emits zero debug
records by construction.** `> 0` could only fail spuriously; `>= 0` could never fail. Recorded
the count with an INFO verdict and stated plainly in README §6: *this matrix proves the debug
plumbing, not the debug content.* Making debug content assertable is a code change (add
instrumentation on plan-only paths), not a harness change. Related: **`-ConfirmApply` cannot be
automated at all** — both gates are `Read-Host` — so the entire matrix is non-mutating and
apply-path diagnostics stay manual.

**Measurement architecture.** One child `pwsh` per row: gives a real exit code, survives the
`exit` calls on failure paths, and allows records to be classified by **PowerShell record type**
(`VerboseRecord` / `DebugRecord` / …) rather than by parsing `VERBOSE:` prefixes. The runner
streams each record to disk *as it arrives* — a collect-then-write design loses the entire
capture for exactly the failure rows that matter most. The child's .NET CWD is pinned to
`_procwd` while it `Set-Location`s to its own row folder, so PS location ≠ .NET CWD for the
whole run. That divergence is the POC-6 trap, deliberately armed.

**Merging streams defeats transcription — an unavoidable trade.** `*>&1 |` means the host never
renders the records, and transcription only records what the host renders, so transcripts came
out header-only. Fixed by having the runner echo each record back to the host, and documented
the residual limit honestly rather than claiming fidelity I have not measured.

**Corrected two assumptions by reading the source instead of guessing.** (a) Both scripts write
two `Info` entries immediately after the module import and *before* prerequisite validation
(Deploy L790-801, Audit L503-509) — so a failure row must still leave a real log file behind. I
had initially excused those checks as INFO; they are now strict, which is exactly the BUG-019
catch-path evidence Joel wants. (b) The dMSA DFL gate `return`s at Deploy ~L735 *before* the
first log write, so `-IncludeDmsa` rows below DFL 2025 genuinely cannot produce a log — those
checks SKIP with a stated reason, and the harness pre-flights the DFL and reports it up front.

**`PASS*`** was introduced so a row with a skipped check can never be mistaken for a clean row.

---

## Addendum 5 - 2026-09-05 - POC-10: cmdlet debug emission micro-POC

**Built:** `.research\verbose-debug-poc\Test-CmdletDebugEmission.ps1`. Parse-clean (0 errors),
executed locally against its control target, negative-tested twice.

**Why it exists.** The product has exactly 4 `Write-Debug` sites - `New-TierModelOu.ps1:93`
and `:100`, `Repair-TierModelCanonicalAcl.ps1:151`, `Write-TierModelLog.ps1:92` - and **zero
of them are in GPO code**. The customer incident that motivated `-EnableDebug` was a GPO
creation failing silently. So the feature delivers on the incident path if and only if the
GroupPolicy module's own cmdlets emit debug records when the preference variable is set. That
was never measured. Now it is measurable.

**Design.** 8 targets (1 control + 3 AD + 4 GroupPolicy) x 6 preference cells (Off, DebugOnly,
VerboseOnly, Both in script scope; DebugOnly and Both in global scope). Read-only cmdlets only.
Records captured via `4>&1 5>&1` and classified by record type, so results are counts, not
console-text impressions. Both total and DISTINCT counts are reported - 500 records that are 3
distinct messages is not 500 units of diagnostic value. Sample content is dumped so a human can
judge whether the output would help diagnose a GPO that will not create; the script explicitly
refuses to make that judgement itself.

**Lessons - both found by EXECUTING, invisible to parse-checking:**

1. **A "global scope" cell that pins script scope to SilentlyContinue can never fire.** My first
   version set the cell's value at global scope and pinned script scope off "for hygiene".
   Preference lookup is function -> script -> global, so script scope shadowed the value under
   test and the global cells returned 0 unconditionally. The control target reported 0 for
   `DebugOnly-Global`, which is impossible - that is what exposed it. Fix: `Remove-Variable
   -Scope Script` for global cells so lookup falls through. **A cell that cannot go non-zero is
   the same defect class as a check that cannot fail.**

2. **A verdict string branched on `MaxCount -gt 0` with a two-way if/else declares NEGATIVE when
   the category was never measured at all.** My self-test skipped GroupPolicy and the script
   confidently printed the full "-EnableDebug is hollow, W2 becomes the real work" conclusion
   from zero measurements. Any verdict function needs three outcomes - positive, negative, and
   NOT MEASURED - and the not-measured branch must be as loud as the negative one.

3. **Mechanical enforcement of the `-Debug` ban.** The prohibition on passing `-Debug` explicitly
   to AD/GroupPolicy cmdlets is lab-proven (NullReferenceException in a non-interactive host).
   Rather than trust a comment, the script regex-scans its own target scriptblocks at startup and
   throws if any contains an explicit `-Debug`. Comments get skimmed; a throw does not.

4. **The control target is the load-bearing part.** A zero from GroupPolicy means nothing unless a
   target that definitely emits shows non-zero in the same run. The script reports RIG VALID /
   RIG INVALID first and marks every other verdict UNDETERMINED when the control is silent.
   Verified by injecting a silent control and a throwing control - both correctly turned the run
   red rather than producing a confident wrong answer.

**Not run against the lab.** Handed to Joel with the exact command line.

**Stray file finding:** `.venv\Scripts\Activate.ps1` is a Python 3.14.3 virtualenv artifact, not
ours. Zero files under `.venv` are git-tracked, `.venv\.gitignore` line 2 is `*`, and `pyvenv.cfg`
records creation at `C:\ADO\TierModelv2\.venv` - a different path, so the folder was copied in.
No `requirements.txt`, `pyproject.toml`, `setup.py` or any `.py` file in the repo root. Nothing in
the PowerShell product references it. Safe to delete the whole `.venv` folder. Note this also means
the "39 Write-Verbose sites" figure is inflated: 17 are in that file, so real product coverage is ~22.

**Naming note:** `.research\` now contains both `verbose-vs-debug-poc\` (earlier) and
`verbose-debug-poc\` (this one), plus `debug-switch-poc\`. Three similarly-named folders is a trap
for whoever reads this next; worth consolidating.

---

## Addendum 6 - 2026-09-05T11:57:30.0322399+08:00 - Apply-path phase for the lab validation matrix

Requested by Joel. Closed a real gap: my README claimed `-ConfirmApply` could not be automated
because both confirmation gates use `Read-Host`. **That claim was wrong.** It has been
withdrawn and replaced.

### Learnings

1. **I missed an existing in-repo helper because it lived in a different `.research\` subfolder.**
   `.research\copilot-cli-hyperv-ad-lab\scripts\Invoke-AutoConfirmDeploy.ps1` already solved
   gate auto-confirmation with a `function global:Read-Host` returning `'Y'`. Lesson: before
   declaring something impossible in a README, grep the WHOLE `.research\` tree, not just my
   own subfolder. A false "cannot" in a README is worse than no README - it stops other people
   looking.

2. **A `global:` function cannot cross a process boundary, and my harness crosses one every row.**
   `Invoke-AutoConfirmDeploy.ps1` puts the override in the parent, which is correct FOR IT
   because it dot-runs Deploy in its own process. My harness uses `Start-Process -File` per row.
   Copying the pattern verbatim would have been silently useless and hung every apply row on a
   prompt. The override had to go INSIDE the generated child runner. Same class of defect as the
   `exit`-inside-`&` bug I caught earlier: the pattern is right, the SCOPE is what kills you.
   Proven, not assumed: `proof\Prove-ReadHostOverride.ps1`, 7/7 with a negative control.

3. **CORRECTION TO MY OWN HARNESS: an unexpected `Read-Host` does NOT surface as a TIMEOUT.**
   I had documented "a timeout is the signature of an unexpected Read-Host". Measured and false
   in this invocation model. Under `-NonInteractive` `Read-Host` THROWS
   `"PowerShell is in NonInteractive mode. Read and Prompt functionality is not available."`
   and, because the scripts' gates sit at script scope and the runner propagates the script's own
   exit code, the child can still **exit 0**. The timeout would never have fired. Added a
   per-row check `No unanswered Read-Host prompt` that asserts that string is absent on EVERY
   row. This is the second time an assumption about exit codes in this harness was wrong; exit
   code is a weak signal in PowerShell and must always be paired with a content assertion.

4. **Exit code cannot distinguish "applied" from "declined" from "never reached the gate".**
   Deploy's gates compare against the literal `'Y'` and `exit 0` on anything else. So a
   successful apply, a declined apply, and a broken override all produce exit 0 AND a log file.
   The only discriminator is the auto-confirm echo in the capture plus `Mode = EXECUTION` in
   the log. Negative control in `proof\Test-ApplyPathRows.ps1` proves a declined run is caught
   as FAIL; without those two checks it read as a clean pass.

5. **Prompt count is a source-derived constant, so assert it exactly.**
   `-ConfirmApply` = 1 gate; `-ConfirmApply -EnableAuditing` = 2 (Deploy L744-L790). Asserting
   `exactly N` catches both a gate that was never reached (too few) and an unexpected new gate
   (too many). `>= 1` would have caught neither.

6. **Apply rows are stateful, so ordering is a correctness requirement, not array order.**
   Explicit `ApplyOrder` + an `Assert-ApplyOrdering` guard that refuses to start a run where
   apply rows are not contiguous-and-last, where `-GroupOnly` precedes `-OuOnly`, or where the
   post-apply Audit is not final. Proven by feeding `-RowId` in reverse and getting dependency
   order back.

7. **Row 4 (`-FullDeployment` + all `-Include*`) applies NOTHING below DFL 2025.**
   The dMSA pre-flight gate `return`s BEFORE the confirmation gates. So the post-apply Audit row
   audits the `-FullDeployment` scope, not the all-`-Include*` scope - row 3's scope is the only
   one guaranteed to have been applied, and therefore the only one whose compliance can be
   asserted honestly on any lab.

8. **Drift after an apply is not automatically a defect.** Audit's headline verdict is
   three-valued (`TRUE-FINAL-2`, Audit L1599-L1606). I assert only that compliance was
   DETERMINABLE, and report COMPLIANT/DRIFT as INFO. Asserting zero drift would fail spuriously
   on anything the deployment does not own.

9. **`Restage-Lab.ps1` default `-ConfigPath` is wrong and must always be passed explicitly.**
   Default is `(Join-Path (Split-Path $PSScriptRoot -Parent) 'lab-config.json')` - the PARENT of
   `scripts\`. Both that file and `scripts\lab-config.json` exist on disk, so the wrong one is
   picked up silently rather than erroring. Documented in README section 9.6.

10. **`pwsh -File` cannot pass a multi-value `[string[]]` parameter.** Every token arrives as a
    separate positional string. Use `-Command` when driving the harness from another process.
    Cost me a self-test cycle.

### Scope discipline

Wrote only under `.research\lab-validation\`. Did NOT touch `Deploy-TierModel.ps1`,
`Audit-TierModel.ps1`, `modules\` or `tests\` - Joel holds those. Did NOT run anything against
the lab VM; both proof scripts run entirely under `C:\Users\vasha\AppData\Local\Temp`. Did NOT commit.

### Still unproven - needs a lab run

The override is proven against a STUB that mirrors Deploy's gates, not against the real
`Deploy-TierModel.ps1`. What remains unverified is whether the real script reaches its gates by
some path a stub does not model. Everything about the override MECHANISM is proven.

---

## Addendum 7 - 2026-09-05T12:21:42.3774332+08:00 - Three defects in my own harness, found by Joel's live lab run

Joel ran the frozen harness on the lab. All 41 rows failed. **The cause was my defect, not the
product's.** Folded the fixes into the same edit pass as the apply-path work.

### Learnings

1. **I hardcoded a lab topology value that a config file already owned - and got it wrong.**
   `[string]$PreferredDc = 'TierLab-DC01'` was the **Hyper-V VM name**. The DC's OS hostname is
   `DC01`; the VM name does not exist in DNS at all. `lab-config.json` states both explicitly
   (`"vm": { "hyperv_name": "TierLab-DC01", "hostname": "DC01" }`) and I duplicated the wrong
   field into a default. **The lesson is not "pick a better string" - it is that duplicating a
   value the config already owns is what allows drift.** The harness now READS `vm.hostname`,
   and passing `hyperv_name` is rejected up front with the correct value in the message.
   Handled the git-ignored-config case too: the file is absent when the harness is copied to the
   DC alone, so it falls back and says the value is a guess.

2. **A precondition that invalidates every row is not a row.** My harness dutifully ran 41 child
   processes to discover one environmental fact 41 times, costing ~10 minutes of Joel's lab
   time. Every verdict was CORRECT - that is what made it insidious. Correct-but-useless output
   at scale is its own defect class. Added a row-zero DNS + TCP 389 probe that aborts the whole
   run in ~2 seconds. Deliberately a raw socket probe, not `Get-ADDomain`: it must work before
   and independently of the ActiveDirectory module and must not need AD Web Services. The
   diagnosis distinguishes "does not resolve" (the VM-name mistake) from "resolves but 389
   closed" (DC down/firewalled) because those have different fixes.
   Asserted in proof by **absence of any row folder**, not by exit code - exit code would not
   have proven nothing ran.

3. **Mojibake means the READ is wrong, not the write. Diagnose before fixing.** The em-dash
   rendering as `â€”` looked like an encoding bug in my capture writer. I inspected the bytes
   before changing anything: they were `E2 80 94` - correct UTF-8. The file simply had **no
   BOM**, so ANSI-defaulting readers mis-decoded it. Fix = write a BOM, not re-encode. Had I
   "fixed" the writer I would have corrupted a correct file. Also resisted the tempting wrong
   fix of changing the em-dash in `Deploy-TierModel.ps1`: that file is fine, is not mine, and
   was never the problem.
   Kept `matrix-results.json` BOM-less on purpose (BOMs trip strict JSON parsers); BOM'd only
   the human-readable artifacts, which are the ones that were being mis-read.

4. **Generalised rule I keep relearning in this harness: verify the INPUT, not just the output.**
   Three of my four defects so far (array-splat binding, `exit` inside `&`, and now the DC
   default) were places where the harness measured correctly but was fed something wrong. My
   checks have been reliable; my preconditions have not. Pre-flight guards are now a standing
   part of the design, not an afterthought.

5. **Positive, worth recording:** Joel confirmed the product behaved WELL on this accidental
   failure path - Deploy's prerequisite gate caught the unreachable DC, wrote the log file,
   printed remediation, and emitted the new re-run hint with `-EnableVerbose -EnableDebug` and
   the resolved `-OutputFileBase`. That is real evidence for the new BUG-019/diagnostics code
   on a genuine failure, obtained by accident. Worth keeping in the record.

### Evidence

New proof script `proof\Prove-DcPreflight.ps1` - **14/14**. All three suites green:
Prove-ReadHostOverride 7/7, Test-ApplyPathRows 12/12, Prove-DcPreflight 14/14. Only network
activity is a DNS lookup of a `.invalid` name (RFC 2606, can never resolve). No VM contact.
Scope still `.research\lab-validation\` only. Nothing committed.

---

## Addendum 8 - 2026-09-05T12:59:45.0411572+08:00 - The transcript blind spot: my own instrumentation destroyed the evidence

Joel measured on the lab DC that row `D-ou-vd`'s `capture.tsv` held 55 verbose and 52 debug
records while the SAME run's transcript held **zero** `VERBOSE:` and zero `DEBUG:` lines. The
identical Deploy call in a plain child pwsh with no capture produced a transcript with exactly
55 and 52. Not a product defect, not a harness defect - a consequence of my capture design.

### Learnings

1. **Instrumentation can consume the very evidence it is meant to record.** My runner merges
   all streams (`*>&1 | ForEach-Object`) to classify records by .NET type. That interception
   means the HOST never renders the records, and PowerShell transcription only records what the
   host renders. I was measuring the streams by destroying the artifact I also wanted to
   measure. **Any observer that intercepts a channel must be assumed blind to anything derived
   downstream of that channel until proven otherwise.**

2. **My mitigating comment was itself a false claim - the second one Joel has caught.** The
   runner said the `Write-Host` echo kept transcripts "representative". It does put the
   message TEXT back, which is why the transcript had 286 lines rather than almost none - but
   `Write-Host` carries no stream prefix, so `VERBOSE:`/`DEBUG:` markers never return. The
   comment was plausible, untested, and wrong. Same failure mode as the README's
   `-ConfirmApply` claim. **A comment asserting a behaviour is a claim, and claims need
   evidence.**

3. **An assertion that cannot fail is worse than an absent one.** Had I asserted transcript
   `VERBOSE:` content on capture rows, it would have failed instantly and I would have
   "fixed" it - most likely by re-prefixing my own echo, which would have made the harness
   assert against evidence it manufactured itself. A perfect green tautology. I chose the two
   honest options instead: declare the gap as an explicit SKIP that reports the observed zeros,
   and add ONE row that can genuinely see the content.

4. **Buy the missing observation with a dedicated instrument, not by weakening the main one.**
   `T-native-vd` uses a second runner with NO capture at all. It gives up `capture.tsv` -
   all the record-type checks are unavailable to it - to gain the one thing nothing else can
   see. I deliberately did NOT reuse `Test-MatrixRow` for it: running the capture-based
   battery against an empty record set would have produced a wall of vacuous passes, which is
   the exact problem the row exists to remove.

5. **Prove a blind spot exists before claiming to have closed it.** `Prove-NativeTranscript.ps1`
   reproduces BOTH halves off-lab against a stub emitting exactly 7 verbose and 5 debug records:
   capture runner -> tsv 7/5, transcript 0/0 (Joel's symptom, reproduced); native runner ->
   transcript exactly 7/5. Then a negative control with a silent stub proves the new checks FAIL
   rather than decorate. 17/17.

6. **Report expected values, assert only invariants.** The 55/52 lab baseline is recorded as an
   INFO comparison, never asserted. Two of the four `Write-Debug` sites are per-OU in
   `New-TierModelOu.ps1`, so the counts legitimately move with the OU inventory. Asserting
   equality would build a check that fails on correct changes. Assert `> 0`; report the rest.

7. **Guard the gap itself.** A matrix-level check reports SKIP when the no-capture row is absent
   from a run, so a narrow `-RowId` filter cannot silently return the matrix to the state
   where transcript-content claims passed without being able to fail.

8. **Mechanical note:** inside `pwsh -Command`, `-RowId a b` binds only `a` and treats
   `b` as a positional argument. Multi-value array parameters need `-RowId a,b`. Related to
   but distinct from the earlier `pwsh -File` finding, and it cost me one debugging cycle.

### Side effect Joel should expect

Every capture row with both diagnostics switches now reports `PASS*` rather than `PASS`,
because the declared blind spot is a SKIP. Intended: the gap is stated on every affected row
instead of being invisible. `T-native-vd` reports a clean PASS.

### Evidence

Default matrix 41 -> 42 rows. All four suites green: 7/7, 12/12, 14/14, 17/17. No VM contact,
nothing committed, scope confined to `.research\lab-validation\`.

---

## Addendum 9 - 2026-09-05T13:20:35.4638834+08:00 - My harness held the evidence of a product bug and passed the row anyway

Joel validated the previous batch against the real scripts on a restaged `WinLapsSchema` lab:
`T-native-vd` PASS in 15.9s with an independently opened transcript showing 55 VERBOSE and 52
DEBUG lines - the identical counts the capture harness reported. The transcript blind spot is
genuinely closed and the `> 0` assertion was right; Joel confirmed some VERBOSE lines are Pester
module-load noise, so an equality assertion would have been brittle.

Then he read the `ENTRIES` column in my own summary table. Every failure row wrote exactly 7 log
entries. The row ran 13:08:16 -> 13:11:26 and the log's last entry was 13:08:18.

### Learnings

1. **A number I measure, print, and do not assert on is not evidence - it is decoration.**
   `ENTRIES 7` appeared in my summary table on three rows across two lab runs. I designed the
   column, chose the value, rendered it, and never once asked what 7 meant. The only assertion
   touching it was `> 0`, which 7 satisfies. This is a *new* failure mode for me: my previous
   defects were checks that could not fail. This was a measurement with no check attached at
   all. **Every column in a summary table is a claim awaiting an assertion; if it does not have
   one, say so explicitly or delete the column.**

2. **The strength of an assertion has to match the failure it is supposed to catch.** "Log is
   non-empty" cannot distinguish "the run logged its failure" from "the run logged that it
   started". Seven entries is non-empty and completely useless. I have been writing careful
   checks about log *plumbing* - path resolution, co-location, existence, `Debug\` placement -
   for two sessions, and never once checked the log's *content* against the failure the
   operator would be sending it to us to explain.

3. **Rejecting the loophole is most of the design work.** Joel's brief said "Error/Warning
   level". Taking that literally would have created a check with a free pass:
   `Test-TierModelPrerequisites` L264 logs a `Warning` while merely probing modules, so a run
   whose actual failure was never recorded could still satisfy "a Warning exists". So bare
   `Warning` is not evidence; a `Warning` that *correlates with the console failure* is. I
   built a stub for exactly that case and it fails, as it must.

4. **Seen to fail before believed.** The new checks were run against a stub reproducing today's
   product behaviour and observed FAILING (`7 entries; Error=0, console-correlated=0`, last
   entry `[Debug] Module check details`), then against a stub with the fix modelled and observed
   PASSING. Both halves are recorded in the proof output. I did not assert the checks were
   correct on the strength of having written them carefully.

5. **Fix direction matters more than the fix - `0/0` FAIL is noise, `0/0` PASS is a lie.** The
   obvious repair for `[FAIL] POC-6 ... 0/0 passed` is to pass it. That would be a false green
   over an empty population, which is the exact defect class I have spent this whole session
   removing. The right answer is a visible third state. And Joel was right that it would not be
   the only instance: auditing every aggregate found the same pattern in `Verbose stream
   reachable` and `Read-Host override reached every gate`. **When a defect is a pattern, grep
   for the pattern before fixing the instance.**

6. **A red assertion that does not affect the exit code is a red assertion nobody has to
   answer.** Found while fixing the above: matrix-level FAILs printed in red and the harness
   still exited 0. Both now feed the exit code. `NOT COVERED` deliberately does not.

7. **Messages that assert more than the code has done keep recurring in my work.** The README's
   `-ConfirmApply` claim, the runner's "representative transcript" comment, and now
   `-ListOnly`'s "Nothing was executed" while it wrote two runner scripts. Three instances, one
   habit. Each time the correct repair was to make the claim true, not to soften the wording.

8. **Where I disagreed with the brief, and said so:** Joel asked whether a `-Verbose`-only
   transcript negative check belonged. It already existed - `Transcript NOT created` fires on
   every row lacking both switches. Adding a second one would have been duplicate coverage
   dressed as new rigour. The real gap was the same one POC-6 had: nothing reported whether the
   privacy assertion had been *exercised*. That got an aggregate, not a new row.

### Evidence

New proof `proof\Prove-FailureLogAssertion.ps1` - **26/26**, including the two negative controls
that matter (current-behaviour stub FAILS, stray-Warning stub FAILS). All five suites green:
7/7, 12/12, 14/14, 17/17, 26/26. Default matrix still 42 rows. No VM contact, nothing committed,
scope confined to `.research\lab-validation\`. Deleted the two stray `results\run-*` folders the
`-ListOnly` defect left behind.

### What Joel should expect on the next lab run

The three failure rows will go **FAIL**, and the matrix will report
`Failed runs recorded their failure (BUG-029)  0/3 rows passed` in red with a non-zero exit
code. That is the harness working. It should go green when the BUG-029 product fix lands and
not before.

---

## Addendum 10 - 2026-09-05 - A clean domain cannot fail: the drifted lab fixture

### The gap, stated plainly

Sixteen defects found, fifteen fixed. Six of them share one shape: **the console shows the
operator correct information while the log / report / XML - the artifacts sent to Microsoft -
are silently wrong or empty.** Nothing throws. Nothing is red. Exit codes are unaffected.

My 42-row matrix runs against a clean, compliant domain. It **would have passed while every one
of those bugs was live.** Not because the assertions were weak, but because a clean domain
cannot produce the input that distinguishes right from wrong. A stale `DriftCount = 0` is
indistinguishable from a correct `0`. `No drift detected - configuration matches AD state` is
the CORRECT output on a clean domain and the SYMPTOM on a drifted one.

That is not a testing gap I can close by asserting harder. It needs a different domain.

### Two defects in the brief I was given, found by reading the product

Rogue's fixture design said row 1 should drift **group membership**. Reading
`modules\TierModel\public\Test-TierModelGroup.ps1` shows the group audit compares existence, OU
location, GroupScope and GroupCategory - and **not membership**. Two drifted members would have
produced **zero** group findings, and row 1 - the row whose whole purpose is to span more than
one entity type - would have had exactly one. It would have been incapable of failing, in
exactly the way the row exists to prevent. Substituted a **GroupScope flip (Global to
Universal)** on two tier groups.

Second: the brief wanted ADMX **clean** on row 1 and **missing** on row 3. Both are right; they
just cannot be the same domain state. Resolved with three fixture profiles (`Clean`, `Drifted`,
`DriftedAdmx`) and by ordering rows so the fixture converges three times, not six.

Lesson, and it is the same one as the `Test-TierModelPrerequisites` L264 Warning loophole:
**derive the fixture from what the product actually audits, not from what the feature is
called.** I have now been handed two briefs whose stated drift the product does not measure.

### The ordering trap is the whole design

`$activeScopeCount -gt 1` is rejected, so one row per scope is a product constraint. The
consolidated audit walks OU(1) - Canonical ACL(2) - Group(3) - User(4) - OU ACL(5) - GPO(6) -
ADMX(7) - ... - AuthPolicy(14) - AuthSilo(15), and broken code keeps only the **last** entity's
findings.

So the drift must be **early** and the **last consolidated type must be clean**. Drift ADMX and
a broken build still publishes something: the row passes while broken. That is exactly why a
`-FullDeployment` DENY-URA removal test passed against BUG-028, and why a single-entity fixture
is worse than no fixture - it produces a green tick that means nothing.

I did not want to trust that reasoning, so I made it an assertion: `-Action Plan` refuses the
profile offline (exit 2) if fewer than two consolidated types are drifted or if ADMX is dirty,
and `Last consolidated type (ADMX) is clean` re-checks it from the console during the run.

### Watched every assertion fail first - and one of them nearly lied to me

`proof\Prove-DriftRowAssertions.ps1`, 54/54. Every X-row runs against a stub reproducing the
BROKEN behaviour and must FAIL, then a stub reproducing the FIX and must PASS.

The first run reported all 42 as failures. Every single one read
`CHECK NOT EMITTED: '<name>' absent from row X1-full-multi`. If I had written that assertion as
a plain boolean, all 42 would have read "FAIL" and I would have believed I had watched them fail
correctly. **They had not run at all** - `Add-DriftReportChecks` was throwing on parameter
binding, because a `[string[]]` marked `Mandatory` rejects empty-string elements and console
output is full of blank lines.

Two things saved it. The parse-before-trust gate (borrowed from Rogue's near-miss this morning)
proved the stubs were fine, so the fault had to be mine. And `Assert-Check` distinguishes
**absent** from **failed**, which is now a rule I will not write a proof script without: an
assertion that did not run is the most dangerous outcome there is, because it looks exactly like
an assertion that failed for the right reason.

Three further StrictMode faults surfaced the same way, all the same species: `.Count` and `.Sum`
read from a pipeline result that unrolled to a scalar, or from an empty `Measure-Object`. One of
them (`$driftedObjects`) was on the **Clean** path, which the fixture converges to on every
single revert - it would have thrown at the end of every drift-enabled run.

### The vacuity controls are the part I would keep if I could keep only one thing

Five controls, each describing a way this fixture could quietly stop being able to fail:

- fixture staged nothing (product code FIXED, domain clean) - checks must still FAIL
- only ONE entity type drifted - the BUG-028 detector must FAIL, and must blame the **fixture**
- the LAST type is dirty - the ordering precondition must FAIL
- no drift rows in scope - matrix aggregates must read `NOT COVERED`, never green
- fixture script missing - the run must abort rather than run the rows against a clean domain

The third one is the one I would have skipped a week ago, and it is the one that catches the
DENY-URA-shaped mistake.

### Row 5 exists because nobody has watched that phase succeed

BUG-031 now folds canonical-ACL phase throws into the verdict. Every observation of that phase
so far had an **unreachable** DC. If it throws for a benign reason against a healthy reachable
DC, every clean domain now reports `COMPLIANCE COULD NOT BE FULLY DETERMINED`. That is a false
alarm on the happy path, and it is the change most likely to make an operator stop reading the
output.

Row 5 asserts the phase was **reached** (vacuity guard), did **not** throw, and produced no
undetermined verdict. The overall verdict line is INFO, not asserted: an unapplied lab
legitimately holds drift, and asserting zero would fail a correct product for an environmental
reason.

### What is still not capable of failing, and I am saying so

The `OuAce` component. A non-canonical DACL cannot be forced through the managed API - .NET
re-orders Deny before Allow on write - so whether two extra explicit ACEs surface as **OU ACL**
findings, as **Canonical ACL** findings, or as neither is unobserved. It is upside, not
load-bearing: X1's multi-entity guarantee rests on `OuRename` (order 1) and `GroupScope`
(order 3), which are two distinct early types without it.

### Rows 6a and 6b: watched failing, then BUG-034 landed and they went green

**I did observe 6a/6b failing against pre-fix code.** That happened while BUG-034 was still
open, earlier the same day, and the failures are quoted below. Joel later confirmed the fix had
landed. **No product code was reverted to manufacture the control** - the pre-fix rendering is
retained as a *stub* inside the proof script, so the failure stays reproducible forever.

Observed pre-fix failures, both for the intended reason:

- `X6a-authsilos-named` - `Report names the drifted objects` -> `0/2 named; NOT named: Tier 2
  Authentication Policy, Tier 2 Authentication Silo`, while `Report FINDINGS non-empty` PASSED
  (`2 finding line(s)`) - the report was written, it just said nothing useful.
- `X6b-winlaps-named` - `Report names the drifted objects` -> `0/1 named; NOT named: Tier 2
  PAWs Windows LAPS - Computer`.

Post-fix, both pass: `2/2 named in the report` with verdict token `Missing`, and `1/1 named in
the report` with verdict token `Mismatched`.

BUG-034's scope was **wider than the brief first stated**: **three** producers, and they are
**not reachable from the same switch**.

| Producer | Shape emitted | Switch |
|---|---|---|
| `Test-TierModelAuthPolicy` | `PolicyName, Status, Issues, EnforceState` | `-IncludeAuthSilos` |
| `Test-TierModelAuthSilo` | `SiloName, Status, Issues, EnforceState` | `-IncludeAuthSilos` |
| `Test-TierModelWinLapsDecryptor` | `GpoName, Expected, Actual, Status` | `-IncludeWinLaps` |

**A single `-IncludeAuthSilos` row would have caught two of the three and looked complete.**
Keep this: "one row per defect" is wrong when the defect is a *shape* mismatch, because
shape-producers are distributed across switches. Row count must follow the producer inventory.

### Asserting on a fix that is still moving - the rule I settled on

Rogue had a ResourceType follow-up in flight while I was writing these assertions. The temptation
was to assert the whole rendered line, which is easy and reads well. It is also **wrong**: it
would have gone red on a cosmetic improvement, and someone would then have "fixed" the test.

The rule: **assert the part of the shape that carries the information loss, and observe the rest.**

- Identifier -> asserted (the loss lived here).
- Verdict token -> asserted (the loss lived here too - `Status` was being dropped).
- ResourceType -> **INFO, never asserted**, because its owner is still changing it.
- Whole rendered line -> never matched.
- The token `Unknown` -> appears in **no expected value anywhere**.

Two further details worth keeping:

1. **The naming check reads the PARSED Identifier field, not the report text.** Searching the
   text would let a name that appears only in a summary or a file header satisfy the assertion.
   That is a vacuity hole in slow motion.
2. **The hard-coding guard.** In the fixed-product stub the `-IncludeAuthSilos` findings still
   carry the *old* resource type while the `-IncludeWinLaps` finding carries the *new* one, and
   both rows must pass. Anyone who reintroduces a resource-type assertion turns one of them red
   immediately. A comment saying "don't assert on this" would not have survived; a failing test
   will.
3. **A new assertion must fail on its OWN reason.** Against the pre-fix stub the verdict-token
   check fails, but so does the naming check - so the verdict failure could be a passenger. I
   added a `typeregress` stub that names the object correctly and *only* collapses the verdict.
   The verdict check fails there and the naming check passes, which isolates them. Same species
   of error as trusting a control that failed on a parse error.

`Test-TierModelAuditRule` (one of five construction sites substitutes `Status` for `Details`)
was deliberately given **no row**: it degrades gracefully via the `Property/Expected/Actual`
triple, so it is lossy rather than broken.

### The two vacuity holes the controls found in my own harness

Neither was found by reading code. Both were found by running a control that was *supposed* to
fail and watching it pass.

1. **An empty array bound to a `[string[]]` parameter arrives as `$null`.**
   `-ExpectedNames $(if (...) { $d.Names } else { @() })` yields nothing when the list is empty,
   so `$null` was bound; `@($null)` has `Count = 1`; and `$line -like "*$null*"` is
   `$line -like "**"`, which matches every line. The naming check reported **`1/1 named in the
   report` while asserting nothing at all.** Exactly the defect family I was hired to catch,
   living in the detector. Fixed at both ends: bind through a local, and strip null/blank
   needles before counting.
2. **`tiermodel-winlaps.json` is heterogeneous.** Only the Domain Controllers entry carries
   `isDomainControllerOu`, so `-not $_.isDomainControllerOu` threw under `Set-StrictMode` on
   every other entry. This one failed *loudly* ("no expected names were resolved from config")
   because hole 1 had just been closed - the guard added an hour earlier caught the next bug.

**Do not filter JSON config on property truthiness.** These config files are heterogeneous by
design. Test `PSObject.Properties[$name]` for presence, and select on a property whose absence
is itself meaningful (here: `decryptorGpoName`, which the DC entry lacks on purpose).

### `*- ` means two different things, and I had to read the product to learn which

- `Test-TierModelAuthPolicy` L103 passes the config name **verbatim** to
  `Get-ADAuthenticationPolicy -Identity` - the `*` is a **literal character**.
- `Test-TierModelWinLapsDecryptor` feeds `decryptorGpoName` to
  `Get-GPO -All | Where-Object DisplayName -like` - the `*` is a genuine **wildcard**.

Asserting on the distinctive **tail** of the name is the only form correct under both readings.

### Group membership is NOT audited - the brief was wrong twice about this

The brief asked for "Groups: 2 members" drift, in the original and again in the correction.
`Test-TierModelGroup.ps1` compares **existence, OU location, GroupScope and GroupCategory**. It
does not compare membership. Had I taken the brief literally, row 1 would have had exactly one
drifted entity type and would have been **incapable of failing** - the precise failure mode the
row exists to prevent. The fixture uses a **GroupScope flip (Global -> Universal)** on two tier
groups instead.

### What Joel should expect on the next lab run

`-IncludeDriftRows` is opt-in and MUTATING. **All seven drift rows are now expected to pass** -
BUG-034 landed, so a failure on X6a or X6b is a regression in the Status-as-Type fallback or in
the identifier keys, and should be reported as a finding rather than softened. If X5 fails, that
is a real BUG-031 false alarm on a healthy DC. Full inventory is 49 rows with drift rows, 57
with failure and apply paths added.

---

## 2026-09-05 — The lab run. 61 rows executed. Three new product defects, one fixture defect of my own.

### BUG-029 flipped. That is the headline.

`[PASS] Failed runs recorded their failure (BUG-029) 3/3 rows passed`

Pre-fix this aggregate read 0/3. RUN 1 put 50 rows through the lab with
`-IncludeFailurePaths` and `-IncludeApplyPaths` and returned **0 FAIL**. The three
unreachable-DC rows exited 1, logged their failure, and did not stop at start-up.
The whole bug-squash effort has its signal.

### The checkpoint premise in the brief was false, and checking took two minutes

`AuthSilo-Lab` exists on the three MEMBER VMs. It does **not** exist on `TierLab-DC01`.
The DC had `DC-Promoted-Clean` and `WinLapsSchema` only. I was told to leave the lab on
a DC checkpoint that had never been taken.

I probed the live DC before touching anything and found it already clean — 0 Tier OUs,
0 groups, 0 policies, 0 silos, only DC01 joined. So the AuthSilo-Lab state had to be
BUILT, not restored: RUN 1's apply rows produce exactly that state. Two invocations
were needed because the harness sorts Drift rows BEFORE Apply rows, and the
`-IncludeAuthSilos` drift rows need the silo to exist first.

**Verify the fixtures named in a brief exist before planning around them.** Restoring
`WinLapsSchema` would have been irreversible: there was no checkpoint to come back to.

### I was wrong three times about the -Verbose measurement and the controls caught all three

Round 1 looked like a clean finding: explicit `-Verbose` on an AD write = 1 record
naming the DN, preference-only = 0. I nearly reported it.

Round 2's positive control emitted **zero**, so I declared round 1 void. That was also
wrong — I had assumed the arm was broken without testing whether `New-Item` simply
emits nothing.

Round 3 moved to child processes and matched `'^VERBOSE: '`. It read 0 for an arm
already proven to be 1. pwsh renders verbose records through `$PSStyle`, so the line
does not begin with `VERBOSE:` at all. Void again.

Round 4 stopped guessing and built a **graded ladder**: direct `Write-Verbose` (1),
inside an advanced function (1), hand-written `$PSCmdlet.ShouldProcess` (0),
`New-Item` (0). That located the boundary exactly, and the AD arms then meant
something. Answer: the preference variable governs `Write-Verbose` and does **not**
turn on ShouldProcess descriptions — for AD cmdlets or anything else.

**A single positive control is not enough when it can fail for two different reasons.
Grade the ladder until a zero can only mean one thing.**

Second falsification, and it contradicts the brief directly: explicit `-Verbose` names
the DN when the write is refused **after** the object resolves, but emits **nothing**
when the object does not exist. The brief asserted the record appears "even when the
operation fails". It depends entirely on the failure shape, and the not-found shape —
the commonest one in audit — gets nothing.

### The fixture defect: an offline proof cannot validate a mutation

All six drift rows failed with `fixture exited 2`. Cause:

    AuthPolicyRename -- Apply failed: A system flag has been set on the object and
    does not allow the object to be moved or renamed.

The fixture's design rule — "nothing is created, nothing is deleted; every drift is a
rename or an attribute flip" — is the reason 6a/6b were built on rename. AD refuses to
rename `msDS-AuthNPolicy` / `msDS-AuthNPolicySilo`. `Prove-DriftRowAssertions.ps1` was
54/54 green against stubs and could never have caught it.

**54/54 offline validated my assertions. It validated nothing about whether the
directory would accept the writes those assertions depend on.** Any fixture component
that mutates AD needs one cheap in-lab staging smoke test before the matrix depends on
it.

Second lesson from the same failure: the fixture's exit 2 is all-or-nothing. Six of
eight components staged, `ConsolidatedTypeCount` was 4 and ADMX was clean — every
precondition met — yet all seven rows were recorded unstaged and failed. The exit code
conflates "a component failed" with "this profile is unusable".

### Row 6a: covered in the end, and it passes

Rename refused, delete refused, delete-after-clearing-`ProtectedFromAccidentalDeletion`
**worked**. Rendered lines:

    [Missing] AuthPolicy/*- Tier 2 Authentication Policy: Not found in Active Directory
    [Missing] AuthSilo/*- Tier 2 Authentication Silo: Not found in Active Directory

2/2 named, verdict token `Missing`. BUG-034 confirmed fixed in the lab for the
`-IncludeAuthSilos` producers; X6b confirmed it for `-IncludeWinLaps`
(`[PASS] Standalone producers are named in the report 1/1`). All three producers now
have lab evidence.

### The X1 failure was mine AND theirs — and the product half is worse

X1 failed `FINDINGS span more than one entity type` with
`console itself showed drift in only 0 entity type(s)` while simultaneously passing
`all 11 console finding identifier(s) present`. A contradiction that obvious is a
detector bug, so I read the raw report instead of trusting either check.

The FINDINGS segment: **2267 characters, 2 newlines, 11 finding tokens.** The product
writes every finding onto ONE physical line. My per-line detector counted 1 line and 0
entity types. The content was correct all along — multi-entity drift DOES survive into
the report — but the rendering makes it unreadable, and it reproduced independently in
the 6a report.

Same read turned up **8 unexpanded `{{DOMAIN_DN}}` tokens** in the identifiers, and a
summary block claiming `Drift Findings: 8 / Missing: 8 / Mismatch: 0` above a body
holding 1 Missing, 2 Mismatch and 8 Drift.

**Three product defects found by reading one file that two automated checks disagreed
about.** When two assertions contradict each other, neither is evidence — go to the
artifact.

### Also worth keeping

- `Deploy -IncludeAuthSilos -ConfirmApply` DOES recreate a deleted policy and silo. I
  briefly recorded it as non-idempotent; it was my auto-confirm stub answering `YES` to
  a gate that demands exactly `Y`, and the run cancelled with **exit 0**. A cancelled
  deploy that exits 0 is worth remembering the next time a wrapper "succeeds".
- `Restage-Lab.ps1` still does not stage `.research\`. Re-copied by hand, as warned.
- The 21 `PASS*` rows on RUN 1 all carry the same single skip; the run is genuinely
  clean.
