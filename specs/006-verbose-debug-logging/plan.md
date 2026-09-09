# Implementation Plan: Diagnostic Logging Switches (`-EnableVerbose` / `-EnableDebug`)

**Feature Branch**: `feature/enable-verbose-debug` (cut from `fix/gpo-silent-skip-and-false-success`)
**Spec**: `specs/006-verbose-debug-logging/spec.md`
**Created**: 2026-09-05 (retroactive — records an implementation that is already on disk)
**Status**: Implemented; awaiting lab validation

---

## ⛔ HARD PRODUCTION PROHIBITION — READ BEFORE EDITING ANY CALL SITE

> **Never forward `-Debug` as an explicit parameter to an `ActiveDirectory` or `GroupPolicy` cmdlet.**

| Mechanism | Verdict |
|---|---|
| `$DebugPreference = 'Continue'` at script/module scope | ✅ **SAFE.** The only sanctioned way to raise debug output. |
| `-Debug` as an explicit parameter on `New-ADGroup`, `Get-ADUser`, `New-GPO`, … | ⛔ **PROHIBITED.** Throws `Object reference not set to an instance of an object` in a non-interactive host. |
| `@PSBoundParameters` splatted into any AD/GPO call | ⛔ **PROHIBITED.** It can carry `-Debug` in silently. |
| `-Verbose` as an explicit parameter on AD/GPO cmdlets | ✅ **NOT banned**, but narrower than once believed. Measured 2026-09-05: **1** record naming the target DN on an AD write that succeeds or is refused *after* the object resolves; **0** when the target does not exist; **0** from `GroupPolicy` in every case. See spec **D11**. |

A `-Debug` NRE fires precisely when the operator has turned diagnostics on because something is already
broken. This prohibition must eventually be defended by CI (see **T018**), not by memory.

---

## Technical Context

- **Stack**: PowerShell 7.0+ (5.1 is blocked and unsupported — do not write 5.1 accommodation code), the
  `ActiveDirectory` and `GroupPolicy` modules, Pester.
- **Entry scripts**: `Deploy-TierModel.ps1` (`[CmdletBinding(SupportsShouldProcess)]` — `-WhatIf` is live)
  and `Audit-TierModel.ps1` (plain `[CmdletBinding()]` — no `-WhatIf` surface). This asymmetry is the single
  biggest structural difference between the two halves of the feature.
- **Module**: `modules/TierModel/`, imported `-Force -Verbose:$false -PassThru` by both scripts; the
  `-PassThru` handle is what makes the module-scope preference assignment possible.
- **Both entry scripts carry a UTF-8 BOM** that must survive every edit.
- **Lab**: Hyper-V DC `TierLab-DC01`, `tierlab.internal`, `192.168.100.10`, guest pwsh 7.5.1 via
  PowerShell Direct.

### Research References

- `.research/verbose-debug-implementation-plan.md` — the 21 work items (WI-01…WI-21), POC results §1b/§1c,
  and the WI-19 lab matrix.
- `.research/verbose-vs-debug-design.md` — the original design study, including the AD/GPO module-shape
  measurements.
- `.research/test-plan-verbose-debug.md`, `.research/test-plan-verbose-debug-v2.md` — the test plan.
- `.research/known-bugs.md` — the authoritative register for reliability improvements currently in flight.

---

## Constitution Check

| Principle | Compliant | Notes |
|-----------|-----------|-------|
| I. Code Quality | ✅ | Comment-based help updated on both scripts; every non-obvious mechanism carries its POC citation in-line |
| II. Test-First with Pester | ⚠️ | **Deliberately inverted.** Tests are written *after* lab validation (WI-20), because the diagnostics behaviour that must be asserted is the behaviour the lab measures. Recorded here as a known, Joel-accepted deviation, not an oversight |
| III. Idempotent Deployments | ✅ | Diagnostics change what is *recorded*, never what is *decided or written to AD* |
| IV. Zero-Unintended-Impact | ✅ | FR-019: a run with neither switch is indistinguishable from the pre-feature script. This is the regression gate |
| V. Drift Detection | n/a | No drift surface |
| VI. Structured Observability | ✅ | This feature *is* the observability work; auto-enabled `-Logging` guarantees an artefact |
| VII. Simplicity & Explicitness | ✅ | Two switches, one folder, no retention, no output sink. `LoggingAutoEnabled` makes the prompt rule explicit rather than inferred |
| VIII. Modular Decomposition | ✅ | Diagnostics live entirely in the entry scripts; no module cmdlet gains diagnostics-specific code |
| IX. Dependency Governance | ✅ | No new dependency; no config schema change |

---

## Locked Design Decisions

| # | Decision | Consequence in code |
|---|----------|---------------------|
| **D1** | Switch names are `-EnableVerbose` / `-EnableDebug` | The PowerShell common parameters `-Verbose` / `-Debug` stay free and unshadowed |
| **D2** | Diagnostic output goes to a `Debug\` subfolder | Kept separate from normal logs; derived from the same absolutised base as the log file |
| **D3** | **No retention / rotation** | Deploy and Audit run once to confirm things. `optional/Update-TierModelMembership.ps1` is a scheduled task that keeps 7 days — different lifecycle, untouched |
| **D5** | Preferences set at script + module scope, after import, never global | POC-8 / POC-9 |
| **D6** | The transcript is unredacted, warned about bluntly, and started **only when BOTH switches are supplied** | Requiring both makes the capture a deliberate act |
| **D8** | The switches auto-enable `-Logging` and **announce** it; they never prompt | Explicit `-Logging` without `-OutputFileBase` still prompts; auto-enabled never does |
| — | Both entry scripts get both switches | Audit is in scope, not optional |
| — | Console noise under `-EnableDebug` is accepted | No console-cleanliness machinery; the v1 "unified sink" is withdrawn and must not be revived |
| **D11** | **WI-18 / D9 — `-Verbose` on AD/GPO call sites is MEASURED and DEFERRED.** No v2.1.0 impact | Additive annotation only; nothing depends on it. Full write-up, measured arms and before/after examples in `spec.md` D11 |
| **D12** | **Release taxonomy: bug fixes → PATCH (`v2.1.1`, `v2.1.2`); features → MINOR (`v2.2.0`)** | Joel, 2026-09-05. Durable project convention; recorded in the spec because agent memory is unavailable. WI-18's recommended target is `v2.2.0` |
| **D13** | **No bug numbers or bug history in code comments — ALL of Joel's repositories** | Joel, 2026-09-06. Comments state what the code does and what live constraint it respects, never what broke. "Keep the rule, drop the history": a live non-obvious constraint survives as one present-tense line with no `BUG-nnn`; pure history is deleted. Being applied to product code (155 mentions / 36 files) as task T024 |
| **D14** | **`tests/` is EXEMPT from D13** | Joel, 2026-09-06. Bug-number references under `tests\` stay — in a test the bug number is often the only record of why a specific assertion exists, and stripping it invites the assertion's deletion and the defect's return |
| **D15** | **Bug detail goes in the PULL REQUEST, not `CHANGELOG.md`. The 22-bug migration is CANCELLED** | Joel, 2026-09-06. `CHANGELOG.md` still needs a `[2.1.0]` **feature** section for `-EnableVerbose`/`-EnableDebug`; the 22 pending reliability improvements are not migrated at all. Pre-existing entries from earlier releases stay as shipped history. Re-scopes task T021 |

**Not a decision, and never to be written as one:** the cause of the original customer incident. The
investigation is closed and the cause is unknown.

---

## Mechanism Design

### Preference assignment (the load-bearing ordering)

```powershell
# AFTER Import-Module … -Force -Verbose:$false -PassThru
if ($script:DiagnosticsEnabled) {
    if ($EnableVerbose) { $script:VerbosePreference = 'Continue' }
    if ($EnableDebug)   { $script:DebugPreference   = 'Continue' }

    & $script:TierModelModule {
        param($WantVerbose, $WantDebug)
        if ($WantVerbose) { $script:VerbosePreference = 'Continue' }
        if ($WantDebug)   { $script:DebugPreference   = 'Continue' }
    } $EnableVerbose.IsPresent $EnableDebug.IsPresent
}
```

**Why every part is required:**
- **After the import**, because `TierModel.psm1` emits a `Write-Verbose "Loading: <file>"` per public file
  from inside the module body, and `-Verbose:$false` on the import does **not** suppress those (POC-8
  measured 163 surviving records). Only importing while `VerbosePreference` is still `SilentlyContinue`
  reaches zero.
- **`-Verbose:$false` stays on the import anyway**, because it is what covers the bare
  `ActiveDirectory`/`GroupPolicy` imports that run *after* preferences go live — ordering alone cannot
  protect those.
- **Module scope as well as script scope**, because module functions resolve preference variables
  function-local → module scope → global, and never see the caller's script scope. Script scope alone
  measured **0** records from inside module functions (POC-9).
- **Never global**, so Ctrl-C cannot leak state into the operator's session. Because nothing global is
  written, there is deliberately **no** `try/finally` restore and **no** `$Original*Preference` capture.
  The module-scope value persists for the session, but both scripts `Import-Module -Force` at startup, so it
  self-heals between runs.

### Transcript handling

- Started only when **both** switches are present **and** the `Debug\` folder exists.
- `Start-Transcript … -Force -WhatIf:$false -ErrorAction Stop` inside a `try`/`catch`, **followed by a
  `Test-Path` confirmation**. Under `-WhatIf`, `Start-Transcript` throws nothing and creates nothing
  (POC-2), so a bare try/catch would report success and print a path to a file that does not exist.
- `$script:TranscriptStarted` is set **only** on confirmed success and is the sole guard on
  `Stop-Transcript`. POC-3: a *nested* start is harmless, but an **unpaired stop** succeeds silently against
  the operator's own transcript. There is deliberately no "is a transcript already running" pre-check — an
  earlier version of the plan had one and it was wrong.
- Failure is never fatal: warn and carry on.

### Path resolution

`$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath()` on `-LogPath` (or the current
location) produces one absolutised base; the log file and `Debug\` are both derived from it, so a relative
`-LogPath` cannot split them. `Resolve-Path` / `Convert-Path` throw on a path that does not exist yet;
`[System.IO.Path]::GetFullPath()` is **banned** — it resolves against the .NET process current directory,
which does not track PowerShell's location, and absolute paths hide the bug so tests miss it.

### The prompt rule

`$script:LoggingAutoEnabled` is the explicit discriminator:

| Path | `-OutputFileBase` missing |
|---|---|
| Operator passed `-Logging` | **Prompt** (`Read-Host`); empty input defaults to `Deploy-TierModel` (Deploy) or `Audit-TierModel` (Audit). On Deploy this prompt is pre-existing shipped behaviour, preserved; on Audit, new in this release. |
| A diagnostics switch forced `-Logging` on | **Never prompt** — silent default, so the re-run stays copy-pasteable and non-interactive-safe |

---

## Files Modified

| File | Change | Authorization |
|------|--------|---------------|
| `Deploy-TierModel.ps1` | Both switches; diagnostics resolution + `Debug\` folder; preference assignment; transcript start/stop; re-run hint; comment-based help | ✅ FR-001 … FR-020 |
| `Audit-TierModel.ps1` | Same, plus the `-Logging` switch itself (Audit did not previously have one) | ✅ FR-001 … FR-020 |

**No module cmdlet gains diagnostics-specific code.** No config file and no schema change.

---

## Risk Register

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | `-Debug` forwarded explicitly to an AD/GPO cmdlet → NRE in the exact scenario diagnostics exist for | **Critical** | Hard prohibition above; preference-variable mechanism only; CI AST scan (**T018**) |
| R2 | `-WhatIf` silently suppresses the diagnostics apparatus | High | Per-call `-WhatIf:$false` on every filesystem call; `Test-Path` confirmation; never infer success from a missing exception |
| R3 | Unpaired `Stop-Transcript` kills the operator's own transcript | High | `$script:TranscriptStarted` guard; never call `Stop-Transcript` unguarded |
| R4 | A relative `-LogPath` splits the log file from `Debug\` | Medium | Single absolutised base via `GetUnresolvedProviderPathFromPSPath`; `GetFullPath()` banned |
| R5 | Auto-enabled `-Logging` prompts and hangs a non-interactive re-run | High | `LoggingAutoEnabled` discriminator; silent default on the auto path |
| R6 | An inert diagnostics switch ships (looks present, does nothing) | High | FR-020 pre-merge gate: assert observable effects on both scripts |
| R7 | Someone "simplifies away" the module-scope half of the preference assignment | Medium | POC-9 cited in-line at the call site; targeted test in T012 |
| R8 | Global preference leakage into the operator's session | Medium | Nothing global is ever written; test asserts **non-modification**, not restoration |
| R9 | A diagnostics failure aborts a customer deployment | High | All diagnostics paths warn and continue |
| R10 | The transcript is emailed to Microsoft with host/account names in it | Medium | D6 blunt on-screen warning; the same warning must appear in the docs |
| R11 | A document or comment asserts a cause for the customer incident | High | Closed-and-unknown rule stated in spec, plan and the docs hand-off |
