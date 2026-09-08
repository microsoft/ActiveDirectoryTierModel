# Cyclops — POC round results for `-EnableVerbose` / `-EnableDebug` (WI-01/02/03)

**Date:** 2026-09-05
**Branch:** `feature/enable-verbose-debug`
**Author:** Cyclops (Architect & Reviewer)
**Requested by:** Joel Platek
**Status:** POCs complete. **Two items need Joel's decision (OPEN-A4, OPEN-A5) and one is a blocking defect.**

---

## ⛔ 1. BLOCKING DEFECT — do not commit the current `Audit-TierModel.ps1`

`-EnableVerbose` and `-EnableDebug` are declared in `Audit-TierModel.ps1` at **L174** and **L177** and are referenced **nowhere else in the file**.

`.\Audit-TierModel.ps1 -OuOnly -EnableVerbose -EnableDebug` is accepted without error and does **nothing** — no verbose, no debug, no transcript, no `Debug\` folder, no warning.

This is the worst failure mode this feature can have. A diagnostics switch that silently no-ops fires at the exact moment an operator is trying to work out why a Tier 0 deployment is broken, and it manufactures false confidence: the operator concludes *"diagnostics showed nothing"* rather than *"diagnostics never ran."*

**Required before commit:** finish WI-13–WI-16, or remove the two declarations until they are wired.
**Cheap standing check:** `grep` for `EnableVerbose` in each script must return more than the declaration lines.

---

## 2. Tree state does not match the briefing

| Claim in brief | Measured |
|---|---|
| "BUG-019 has landed" | ❌ `git log` head is `04ab664` (a `.squad` commit). `git diff --cached` is **empty**. BUG-019 is **27 uncommitted working-tree files**. |
| "before any implementer touches Deploy/Audit" | ❌ `Audit-TierModel.ps1` already modified **+105/−5** → 1,778 lines. WI-11 and WI-12 are **already implemented**. |
| — | ✅ `Deploy-TierModel.ps1` genuinely untouched (3,235 lines). |

**Consequences:** Stage C's *"rebase onto Rogue's commit"* is not executable — there is nothing to rebase onto. All Audit line anchors in the plan were stale and have been re-measured. 28 files of Tier 0 work are unprotected against a stray `git restore`.

---

## 3. POC results — the four measured answers

Harnesses in `.research\verbose-vs-debug-poc\guest\`, results in `…\results\`. All local-only; no AD contact.

### POC-1 — preference restoration (`pref-restore.json`)
Six exit shapes × five strategies. **`try/finally` is the only strategy that restores on all six.**

- `finally` **does** run on `exit` and on a **genuine Ctrl-C** (raised via `[powershell]::Stop()` — a real `PipelineStoppedException`, not an approximation).
- `Register-EngineEvent PowerShell.Exiting` fired **0/6** — it is a *session*-exit event. **Rule it out permanently.**
- Script-scope `trap` covers `throw` **only**.
- Restore-at-each-exit covers five shapes and **fails on Ctrl-C**.

**Decision (resolves OPEN-A3): take the whole-body `try/finally`,** despite the ~3,000-line reindent, delivered as a **separate whitespace-only commit** whose `git diff -w` is empty. The deciding shape is Ctrl-C, which is *likely* here — a diagnostics run deliberately floods the console, so an operator interrupting it is the expected case, not an edge case.

### POC-2 — `-WhatIf` suppression (`transcript-whatif.json`)
**All five** filesystem cmdlets are suppressed under `-WhatIf`: `New-Item`, `Start-Transcript`, `Add-Content`, `Set-Content`, `Out-File`. The `-WhatIf:$false` rescue is **per call** (proved by leaving `Out-File` undefended — it stayed broken).

**⚠️ The finding nobody predicted:** `Start-Transcript` under `-WhatIf` **throws nothing and creates no file**. The obvious implementation reports success and prints a path to a nonexistent file. **Success must be confirmed with `Test-Path`, never inferred from the absence of an exception.**

Audit is genuinely unaffected — a plain `[CmdletBinding()]` control did not even expose `-WhatIf`. So Deploy needs the guards and **Audit must not have them**; the asymmetry is now documented so nobody "fixes" it.

### POC-3 — nested transcripts (`nested-transcript.json`)
**I had the hazard backwards.** The nested `Start` is **safe** — transcripts stack and the operator's keeps receiving output. The real hazard is the **unpaired `Stop`**: if our `Start` failed while the operator has their own transcript running, an unconditional `Stop-Transcript` **succeeds and stops theirs**, silently truncating their change record. `try { Stop-Transcript } catch {}` does **not** protect against this — nothing throws; it just hides the damage.

**Therefore `$script:TranscriptStarted` is load-bearing, not defensive tidiness.** Guard on the boolean, never on the exception. The plan's earlier "add a nested pre-check" instruction was removed as wrong.

### POC-6 — path resolution (`nested-transcript.json` Part B)
- `Resolve-Path` and `Convert-Path` **throw** on a not-yet-existing path — the normal first-run case.
- `[System.IO.Path]::GetFullPath()` resolves against the **.NET current directory, which does not track PowerShell's location** (measured: PS in `…\Temp\x`, .NET still at the repo root). Mixing it with `New-Item` puts the log file and `Debug\` in different directories — **and only when `-LogPath` is relative**, so no absolute-path test catches it.
- **Mandated idiom:** `$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath()` + `Join-Path`. Nothing from `System.IO.Path`.
- Also: `New-Item -Force` creates missing parents; UNC paths work.

---

## 4. Decisions I need from Joel

- **OPEN-A4 — `-Logging` now behaves differently in the two scripts.** Deploy prompts via `Read-Host`; the as-built Audit deliberately does not (defaults to `'Audit-TierModel'`) so a diagnostics re-run stays non-interactive. **The Audit behaviour is right and my WI-12 was wrong to specify mirroring the prompt** — it matches my D8 reasoning. But it is the cross-script inconsistency WI-11 exists to prevent. **Recommend: accept the divergence now, document it in both help blocks, and raise "make Deploy non-interactive too" as a separate change** so a Tier 0 behaviour break gets its own CHANGELOG entry instead of riding along inside a diagnostics feature.
- **OPEN-A5 — commit BUG-019.** 28 files of Tier 0 work exist only as unstaged edits. Not my call to commit, but Stage B will pile more on top and Stage C cannot rebase onto nothing.
- Still open from the previous round: **D6** (unredacted transcript — recommend ACCEPT + warn), **D8** (auto-enable `-Logging` — recommend YES, never prompting), **OPEN-A2** (Audit's `-LogPath` now carries three jobs), and **§8 / W2**.

---

## 5. Plan changes forced by these results

| Section | Change |
|---|---|
| §1a (new) | Working-tree state, the dead-parameter defect, re-measured Audit + `modules\` anchors |
| §1b (new) | The four POC result tables |
| §2 | POC-1/2/3/6 marked done; 5 of 8 closed; only POC-4/5/7 remain (all need the lab) |
| §3 | Collision cleared; "rebase onto Rogue's commit" flagged as not-yet-executable; AST re-derivation still binding |
| WI-01/02/03 | Marked ✅ done with measured outcomes |
| WI-05 | Mandated path idiom; `-WhatIf:$false` now **required**, not conditional; per-call warning |
| WI-07 | `Test-Path` verification added; nested pre-check **removed** as wrong; `$script:TranscriptStarted` rationale rewritten |
| WI-08 | Strategy fixed to `try/finally`; reindent-risk controls added |
| WI-11/12 | Marked already-implemented; converted to a **review checklist**; stale anchors flagged |
| WI-14/15 | Audit gets the same `try/finally`; `-WhatIf` asymmetry documented |
| WI-19 | Lab matrix 16 → **20** rows (`-WhatIf`, operator-transcript survival, relative `-LogPath`, hand-issued Ctrl-C) |
| WI-20 | Three new required test areas; Wolverine told to port `Test-PrefRestore.ps1`'s harness |
| §7 | OPEN-A3 resolved by measurement; **OPEN-A4** and **OPEN-A5** added |
| §9 | Blocking gate added at the top |

**Files written:** `.research\verbose-debug-implementation-plan.md`; `guest\Test-PrefRestore.ps1`, `Test-TranscriptWhatIf.ps1`, `Test-NestedTranscript.ps1`; `results\pref-restore.json`, `transcript-whatif.json`, `nested-transcript.json`.
**Nothing committed. No production script, `modules\**`, `tests\**` or `CHANGELOG.md` modified by me.**

---

## UPDATE 2026-09-05 (later) — POC-9/POC-10 supersede §1 and §4 of this record

### 1. SUPERSEDED — the "blocking defect" in Audit was deliberate scoping, not a defect
Audit's `-EnableVerbose`/`-EnableDebug` being declared-but-unwired is the intended mid-flight state; Rogue was scoped to declaration-only pending these POCs. **Retained as a pre-merge gate**, not a defect: a diagnostics switch that silently no-ops is worse than an absent one, because it fires when something is already broken and reports "diagnostics showed nothing" instead of "diagnostics never ran". Audit must not merge until WI-13-WI-16 land, or the declarations must be removed.

### 2. SUPERSEDED — "BUG-019 is uncommitted" is not a risk
Uncommitted is by design: Joel manually reviews every change on this branch before anything is committed. BUG-019 is complete and verified (0 parse errors/85 files, Unit 1573/0, Integration 318/0). The tree is now backed up as a patch outside the repo. **The one live consequence: Stage C must assume a single uncommitted working tree — there is no commit to rebase onto and there will not be one.**

### 4. SUPERSEDED — OPEN-A4 ruled on by Joel; my recommendation was wrong
I recommended accepting Audit's non-prompting `-Logging`. That state existed only because of a mis-scoped instruction, and **`Audit-TierModel.ps1:241` already prompts for the same `-OutputFileBase` variable** when `-OutputFormat` is supplied. Final rule:
- **explicit `-Logging` without a base name -> prompt via `Read-Host`, throw on empty** (matches Deploy L234 and Audit L241)
- **auto-enabled `-Logging` (from the diagnostics switches) -> never prompt**, default silently so a diagnostics re-run stays copy-pasteable

Full non-interactivity is a reasonable product direction but is a **separate item for both scripts, with its own CHANGELOG entry**.

### NEW — POC-9: do not use `$global:` for preferences
Measured (`Test-ScopedPreference.ps1` -> `results\scoped-preference.json`), fresh runspace per mode, real TierModel functions as probes:

| Mode | Verbose | Debug | Leaks to operator | Leaks on Ctrl-C |
|---|---|---|---|---|
| `$global:` | 4 | 1 | YES | YES |
| `$script:` only | 0 | 0 | no | no |
| **`$script:` + `& $module { $script:... }`** | **4** | **1** | **no** | **no** |

**Team-relevant call: entry scripts must set diagnostic preferences at script scope AND inside the module's scope, never at global scope.** Both halves are required — `$script:` alone reaches nothing inside the module, because module functions resolve preferences function-local -> module -> global and never consult the caller's script scope. Consequences: no `try/finally` is needed for preferences on any exit path including Ctrl-C; the ~2,000-line reindent of `Deploy-TierModel.ps1` is **avoided**; and tests must assert the globals are **never modified**, not merely restored. Residual: the module-scope setting persists for the life of the loaded module in that session, but `Import-Module -Force` resets it and both entry scripts `-Force` at startup, so it is self-healing.

### NEW — POC-10: Ctrl-C leaves the transcript running (OPEN-A6, for Joel)
After a genuine interrupt the transcript is **still open and still capturing** — output written afterwards landed in the file. The transcript is unredacted and D6 anticipates customers emailing it to us, so an interrupted diagnostics run silently records whatever the operator does next. **Options: (A)** guarded `Stop-Transcript` at each exit point, no reindent, hole mitigated by explicit disclosure on screen and in the transcript header; **(B)** whole-body `try/finally`, closes it, ~2,000-line reindent for manual review. **My recommendation: A plus disclosure** — POC-9 removed the bulk of the reindent's justification. **Not deciding it: this is a security/review-cost trade for Joel.** New safeguard **S5** added to the D6 list either way.
