# Decision: Cyclops — `-EnableVerbose` / `-EnableDebug` Plan Calls

**Date:** 2026-09-05
**Author:** Cyclops (Architect & Reviewer)
**Status:** RECOMMENDED — D6 and D8 await Joel; the rest are architectural calls made within the plan
**Requested by:** Joel Platek
**Artefact:** `.research\verbose-debug-implementation-plan.md` (git-ignored)

## Team-relevant calls made

### 1. The hard prohibition gets CI enforcement, not just documentation

**NEVER forward `-Debug` to an AD or GroupPolicy cmdlet** — lab-proven NRE on every AD cmdlet in a non-interactive host. `$global:DebugPreference = 'Continue'` is safe; the explicit parameter is not. Also prohibited: splatting `@PSBoundParameters` into any AD/GPO call, because it can carry `-Debug` in silently.

A prohibition defended only by memory will be broken. **WI-19 item 8 adds an AST-based CI check** that fails the build on any literal `-Debug` at an AD/GPO call site or any `@PSBoundParameters` splat into one. **It must be merged and green BEFORE WI-17** (the `-Verbose` forwarding sweep) begins — that sweep edits the exact lines where `-Debug` would be typed by reflex.

### 2. `Audit-TierModel.ps1` has no `-Logging` switch — RESOLVED by Joel's parked patch

Audit has **no `-Logging` switch, zero `Write-TierModelLog` call sites, and never calls `Initialize-TierModelLogging`**. Its `-LogPath` is a report output directory (L1620-1626).

**Joel supplied a parked patch** (`…\session-state\…\files\logging-branch-patches\audit-logging-switch.patch`) written in an earlier session and held back for this branch. It adds a real `-Logging` switch to Audit with Deploy's semantics. **This resolves what I had raised as OPEN-A1** — Audit gets `-Logging`.

**Why it must land first:** Joel's task 3 is *"confirm the `-Logging` path/output are working with our two new `-EnableVerbose` and `-EnableDebug`."* On Audit today **there is no `-Logging` to confirm.** So Audit needs **a third work item Deploy does not need**, sequenced ahead of the diagnostics wiring. Plan restructured 20 → 21 items: **WI-12** re-applies the patch, **WI-13** hangs the diagnostics switches off it.

**⛔ Do NOT `git apply` the patch — its line numbers are stale** (Audit +37 lines from yesterday's BUG-022 wire-in). Measured drift: `@@ -88` → **L90/91**; `@@ -154` → **L156**; `@@ -225` → **L227**; `@@ -1637` → **L1676**. Reference design only; re-apply by hand.

**Review finding on the patch:** its end-of-run hunk resolves `$auditSummary` via a defensive double `Get-Variable` lookup. Unnecessary — `$auditSummary` is a hashtable initialised unconditionally at L261-263 with `TotalChecked`/`DriftCount` present. Simplify to direct access. (`Set-StrictMode -Version Latest` at L161 means a *missing* key throws, so confirm the keys rather than hunt scopes.)

### 2a. ✅ Deploy does NOT have the same module-scope logging gap — verified

The patch's key idea is calling `Initialize-TierModelLogging` **inside module scope** (`-PassThru` + `& $module { … }`); without it `$script:LoggingEnabled` stays `$false` and every `Write-TierModelLog` raised *inside* the module — **including every `-Level Error`** — is console-only, producing an effectively empty log (design-doc §1.4).

| | Deploy | Audit (today) |
|---|---|---|
| Import captured with `-PassThru` | ✅ **L403** | ❌ L229 |
| Module-scope `Initialize-TierModelLogging` | ✅ **L411-416** | ❌ absent |
| Entry-script `Write-TierModelLog` sites | ✅ **30** | ❌ **0** |
| `-Logging` switch | ✅ L196 | ❌ absent |

**Our existing `-Logging` is NOT partly hollow — Deploy's is fully wired. No remediation needed on Deploy.** The gap is Audit-only. (The initialiser was W3, implemented 2026-09-03; Deploy was wired then, Audit was not, because Audit had no `-Logging` to hang it off.)

### 2b. `-Verbose:$false` must be preserved on both entry-script imports

Both already carry it (Deploy L403, Audit L229) and it is load-bearing for Flaw 1 / D5. **WI-12 rewrites the Audit import line to add `-PassThru` — dropping `-Verbose:$false` in that edit would re-open the ~60-line module-load noise problem** the design doc calls "the highest-value polish item in the feature." WI-20 item 13 tests that line specifically, on top of the general import invariant (item 9).

### 3. WI-17 (D9 `-Verbose` forwarding, ~31 sites / 17 files) is GATED on re-verification

The measurement justifying D9 — "AD cmdlets emit exactly 1 verbose record, the ShouldProcess target DN, even on failure" — comes from a POC round whose platform assumptions were **overturned by the 2026-09-04 WS2025/PS7.5.1 correction**. POC-5 re-confirms it on the supported platform first. If the record is not there, WI-17 is worthless and must not be built. Do not spend 3-4 h across 17 files on an unre-verified premise.

Same treatment for Beast's Mode B/C debug comparison (POC-4): it ran in simulate mode against a `New-Module` dynamic module, and its own README flags that dynamic modules inherit script scope while the real `.psd1` does not. Re-run live before citing.

**Re-derive all call sites with AST parsing, never regex** (`.squad\decisions.md` 2026-09-04 §8 — regex produced a wildly inflated count on this exact codebase).

### 4. Sequencing: wait for Rogue, do not merge around him

`git status` during this session showed **13 modified files under `modules/TierModel/public/`** — Rogue's BUG-019 work in flight, including `New-TierModelGpo.ps1` and `Get-TierModelGpo.ps1`, which are precisely WI-17's targets. Rogue is adding `-ErrorAction Stop` to AD/GPO invocations; WI-17 adds `-Verbose:$flag` to the same lines of the same files.

**Stage B of the plan (12 items, both entry scripts) touches zero `modules\` files and runs today at full speed. Stage C (WI-16, WI-17) waits for Rogue's commit, then rebases.** Not "coordinate" — wait. A three-way merge on Tier 0 AD call sites is how an `-ErrorAction Stop` gets silently dropped.

### 5. Flaw 1 / D5: ordering IS load-bearing — measured, not assumed (POC-8)

A proposal was raised to downgrade Flaw 1 / D5 to a constraint-to-preserve, on the reasoning that `-Verbose:$false` overrides `$global:VerbosePreference` for that call and so ordering is redundant. **POC'd rather than accepted; refuted for our own module.**

`.research\verbose-vs-debug-poc\guest\Test-ImportVerboseOverride.ps1` → `results\import-verbose-override.json` (2026-09-05, local, no AD):

| Module | Pref set | `-Verbose:$false` | Verbose records |
|---|---|---|---|
| `TierModel.psd1` | before | no | 343 |
| `TierModel.psd1` | before | **yes** | **163 — still noisy** |
| `TierModel.psd1` | **after** | no | **0** |
| `Microsoft.PowerShell.Archive` | before | no | 46 |
| `Microsoft.PowerShell.Archive` | before | **yes** | **0** |

**Mechanism:** `-Verbose:$false` suppresses the *engine's* import narration, so it fully silences a binary-manifest module. It does **not** suppress `Write-Verbose` running **inside the module body during import** — `TierModel.psm1` emits `"Loading: <file>"` once per public file (84 of them) plus its scan messages, giving the 163 residual records. Only ordering reaches those.

**Team-relevant conclusions:**
- **WI-06 / WI-14 stay mandatory work items.** Setting preferences before the TierModel import costs **163** noise lines per diagnostics run.
- **The design doc's "~60 lines" understated it by ~2.7×.**
- **Keep both mechanisms — they are complementary, not alternatives.** Ordering covers our script module; `-Verbose:$false` covers downstream binary modules imported *after* preferences go live, which ordering cannot protect (the four bare AD imports in WI-17).
- **Do not remove `-Verbose:$false` from either entry-script import** (Deploy L403, Audit L229). WI-12 rewrites the Audit line to add `-PassThru` — that is where it would be lost.

### 5a. ⚠️ Correction: `TierModel.psm1:45` is documentation, not a reusable helper

`Initialize-TierModelLogging` is declared at **L14**; **L45 sits inside that function's own comment-based-help `.DESCRIPTION`** — the `& $module { param($p) … } $path` line is a usage *example*. Grep returns exactly two hits in the whole `.psm1`: the declaration and that example. **There is nothing higher-level to reuse — the `& $module { … }` idiom IS the API**, and `Deploy-TierModel.ps1` L411-416 is the reference implementation to copy into Audit verbatim. Do not build a wrapper: making one callable from an entry script means exporting it, which adds a public function and trips three assertions in `tests\Unit.ModuleManifest.Tests.ps1` — the exact constraint the psm1's own comment block (L28-45) documents.

### 5b. ⚠️ Correction: Audit DOES have a version string; both are stale

Reported as "0 hits" — false negative. Audit has `Version: 2.0` at **L123** (a `Version:` search returns 2 hits: L123 and L213's `"Current version: PowerShell …"` fail-fast text).

| Location | Reads | Should be |
|---|---|---|
| `Deploy-TierModel.ps1` L167 | `Version: 1.3.0` | 2.1.0 |
| `Deploy-TierModel.ps1` L168 | `Requires: … (v1.3.0+)` | (v2.1.0+) |
| `Audit-TierModel.ps1` L123 | `Version: 2.0` | 2.1.0 |
| `TierModel.psd1` | `ModuleVersion = '2.1.0'` | ✅ authoritative |

**Staleness in both, not absence in one.** Flagged for Joel; **not renumbered unilaterally** — version bumps travel with a CHANGELOG entry, which is Scribe's/Joel's call. Also noted: Audit's `.NOTES` omits the PowerShell 7.0+ requirement despite the hard gate at L210, where Deploy L168-169 states it. Parity recommended in WI-16.

**Help-block asymmetry:** Audit needs **three** new `.PARAMETER` entries (`Logging`, `EnableVerbose`, `EnableDebug`); Deploy needs **two** — Deploy already documents `-Logging` at L128-132. Same asymmetry as the code.

### 6. D6 — transcript is unredacted: ACCEPT, warn, and retire the "redacted log" framing

**Do not attempt to redact the transcript.** No supported interception point exists; post-processing is racy (the file is open during the run, and a crash leaves the raw file — the exact run you most want to share); the only alternative is the v1 unified sink Joel withdrew. **A half-working redactor is more dangerous than none** — it converts an understood risk into an assumed safety.

**Team-wide correction that must propagate:** verified at `Write-TierModelLog.ps1` L63-70 — redaction replaces **exact top-level keys** only (`Password`/`Secret`/`Token`/`Key`/`Credential`), does not recurse, does not match `AdminPassword`/`SafeModePwd`/`GmsaBlob`, and **never inspects `$Message`**, which L79-88 interpolate straight into the console string. **No document, help text, or argument may describe our JSON log as "redacted."** The transcript is worse in degree, not in kind.

Safeguard: 4 warnings — console at transcript start, **first line inside the transcript file itself** (so it travels with the file when forwarded), both scripts' `-EnableDebug` help, and `docs\tiermodel-logging.md`. No bespoke ACL on `Debug\` — a wrong ACL on a customer DC is its own incident; document the requirement instead.

**Follow-up raised, not scoped:** making `Write-TierModelLog` redaction recursive and message-aware. The function's name and its `# Redaction placeholder (FR-024: ensure no secrets logged)` comment both over-promise relative to what it does. Should become a tracked defect.

### 7. D8 — auto-enable `-Logging`: YES, with two hard conditions

The surprise objection is to *silence*, not to the behaviour; an announcement line neutralises it. The alternative — an operator mid-incident on a customer DC watching output scroll past the buffer with no file — is a failed diagnostics run that must be repeated on a broken production system.

1. **Never `Read-Host`.** Deploy L233-238 prompts for `-OutputFileBase` when `-Logging` is set without one. The auto-enable path must bypass it and default the base name. The D3 hint prints a command containing both switches — a prompt on that path ships a **hang** into an unattended re-run. Asserted by WI-19 item 10.
2. **One-directional.** `-EnableVerbose` implies `-Logging`; `-Logging` must never imply either diagnostics switch. No existing user's `-Logging` run changes behaviour.

### 8. Transcript failure must never abort a deployment

`Start-Transcript` wrapped in try/catch; the catch warns and continues — **no rethrow, no exit, no blocked state**. A `$script:TranscriptStarted` flag prevents an unpaired `Stop-Transcript` (which throws). Same rule for `Debug\` creation failure: warn and continue. This deliberately differs from `optional\Update-TierModelMembership.ps1` L300, which fail-fasts — that script makes unattended AD writes; ours is an operator-initiated diagnostics aid, and refusing to deploy because a log folder is unwritable is the wrong trade for a Tier 0 tool. **WI-19 item 6 is the test that protects a customer deployment.**

### 9. Scope: W2 is walled off, not folded in

W2 (enrich ~40 GPO catch blocks with FQID/CategoryInfo/ScriptStackTrace) is valuable and genuinely related — without it, the switches faithfully surface catch blocks that already discarded the useful part of the exception. It is **not in today's scope**. Plan §8 carries it with a re-derived **12-20 h** estimate (the design doc's own 6-8 h was withdrawn by its author) and an explicit "nothing here is agreed." Same status: W4, W7, W8, and the redaction hardening.

### 10. Line numbers in `.research\verbose-vs-debug-design.md` are ALL stale

Deploy `"GPO planning failed - check logs for details."` is **L1387**, not L1284. Audit's PS-version gate is **L210**, not L212. Deploy is 3,235 lines; Audit is 1,678. Every anchor in the plan was re-derived from disk. Third session running where trusting a prior document's line numbers would have produced a wrong edit — **re-verify before every edit; Rogue is changing `modules\` right now.**

## Requested from Joel

- **D6** and **D8** confirmations (recommendations above).
- ~~**OPEN-A1**~~ — ✅ **RESOLVED 2026-09-05** by the parked `audit-logging-switch.patch`. Audit gets `-Logging`.
- **OPEN-A2** — with `-Logging` added, Audit's `-LogPath` now serves **three** jobs: the `-OutputFormat` report, the `-Logging` log file, and the `Debug\` folder. Acceptable overload, or does diagnostics need its own path parameter?
- **OPEN-A3** — if POC-1 shows reliable preference restoration needs a whole-body `try/finally` (a ~3,000-line reindent of a Tier 0 script), accept that diff or fall back to per-exit-point restoration?
- **§8 / W2** — approve as a follow-on branch, or leave parked?
