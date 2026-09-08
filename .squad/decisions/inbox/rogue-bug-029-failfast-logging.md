# BUG-029 — fail-fast failures never reached the log

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05T13:42:57+08:00
- **Requested by:** Joel Platek
- **Branch:** `feature/enable-verbose-debug` — HEAD `04ab664`, nothing committed, nothing staged
- **Files changed:** `Deploy-TierModel.ps1`, `Audit-TierModel.ps1`
- **Status:** Implemented and verified. One structural gap escalated.

---

## 1. The defect

`Write-TierModelFailFast` — the single helper every up-front gate uses to report a terminal
failure — called **only** `Write-Host`. No logger call of any kind. Confirmed by AST in both
scripts, and confirmed pre-existing at `04ab664`.

Joel's lab measurement: a Deploy run against an unreachable DC wrote **7 routine start-up
records**, last at `13:08:18`, and died at `13:11:26`. Three minutes and the entire failure absent
from the log while the console printed the complete story. The operator's log — the artifact they
send us — simply stopped mid-sentence.

**7 call sites:** 5 in Deploy, 2 in Audit, covering the PowerShell version gate, the dMSA DFL
gate, the general prerequisite check, and both configuration-validation gates.

---

## 2. The fix

The logging is placed **inside the helper**, not at the call sites. One change covers all seven
gates, cannot be forgotten by a future gate, and keeps the two helpers equivalent as the code
deliberately intends.

Design points, each of which is load-bearing:

- **Level `Error`, never `Warning`.** Cyclops's loophole is real: `Test-TierModelPrerequisites`
  logs a routine `Warning` while probing modules, so a Warning-only fix would let a log *look* as
  though it recorded a failure while saying nothing about the actual one.
- **`FailFast = $true` and `Terminal = $true` data keys**, so the terminal record is
  machine-identifiable and cannot be confused with any other Error in the file.
- **`ConsoleMessage` and `Remediation` carry the exact arrays the console rendered**, so the log
  and the console correlate line for line. Remediation matters as much as the error — it is half
  of what the operator needs.
- **Emitted AFTER the console output, inside `try/catch`.** A failure while *reporting* a failure
  must never become the operator's error, and must never suppress the report they are reading.

---

## 3. Per-call-site logger availability (task 2)

Joel expected these to differ. They do. Derived from the AST against the current file.

| # | Site | Gate | `$script:LogFilePath` set? | `Write-TierModelLog` loaded? | Handling |
|---|---|---|---|---|---|
| 1 | Deploy L669 | PowerShell version | ✅ (L356) | ❌ (import is L679) | **direct JSON append** |
| 2 | Deploy L785 | dMSA DFL | ✅ | ✅ | `Write-TierModelLog` |
| 3 | Deploy L887 | prerequisites | ✅ | ✅ | `Write-TierModelLog` |
| 4 | Deploy L957 | config validation threw | ✅ | ✅ | `Write-TierModelLog` |
| 5 | Deploy L971 | config validation failed | ✅ | ✅ | `Write-TierModelLog` |
| 6 | **Audit L472** | **PowerShell version** | ❌ (set at L528/L570) | ❌ (import is L608) | **cannot log — see §5** |
| 7 | Audit L720 | prerequisites | ✅ | ✅ | `Write-TierModelLog` |

Two distinct not-ready cases, handled explicitly rather than assumed:

**Case A — path ready, logger not (site 1).** The Deploy PowerShell-version gate fires before
`Import-Module`. The helper detects the missing command with `Get-Command` and writes the
**identical JSON record** directly with `Add-Content`, creating the directory if needed, so the
log file stays a valid stream of one-JSON-object-per-line. Proven in isolation (§6).

**Case B — nothing ready (site 6).** Escalated below.

**StrictMode trap, handled.** At Audit site 6 `$script:LogFilePath` is not merely null, it is
**not yet declared**, and under `Set-StrictMode -Version Latest` reading it throws. The helper
therefore probes with `Get-Variable -Scope Script -ErrorAction SilentlyContinue` rather than
reading the variable. Verified empirically — undeclared returns nothing, declared-null returns an
empty value, assigned returns the path — so a fail-fast path can never throw while reporting.

---

## 4. ⚠️ A mistake I made, and how it was caught

I initially inserted the block by anchoring on the helper's closing line,
`Write-Host "Deploy script completed." -ForegroundColor Green` followed by `}`. **That string
occurs twice in Deploy** — the second time in the script's normal *success epilogue*. The block
was therefore duplicated into the success path, where `$Message` and `$Remediation` do not exist,
which under StrictMode would have thrown inside the `try` on **every successful `-Logging` run**
and emitted a spurious warning.

The harness did **not** catch it: Deploy exits at the prerequisite gate and never reaches the
epilogue. It was caught only because I went looking for the block boundaries to build the control
copy and found two. Removed, and the epilogue verified **byte-identical to `04ab664`**.

Recorded deliberately: an anchored text replacement is a search, and a search needs its match
count checked. This is the third variant of the same lesson this session.

---

## 5. ESCALATION — Audit site 6 cannot log, and the reason is ordering

The two scripts order their startup differently:

- **Deploy:** logging block (L356) → PowerShell-version gate (L669) → import (L679)
- **Audit:** PowerShell-version gate (L472) → logging block (L528/L570) → import (L608)

So Audit's version gate runs when **no log file path exists yet**. There is nothing to write to;
this is not a bug in the fix but a consequence of gate ordering.

**Mitigating factors:** this gate fires only on PowerShell < 7, which is an explicitly unsupported
configuration, and the console output is unaffected. It is the lowest-value of the seven sites.

**The fix would be to move Audit's version gate to after its logging block, matching Deploy's
proven ordering.** I have not done it: relocating a fail-fast gate means more code executes on an
unsupported PowerShell version before the guard fires, and that is a structural change beyond
"make fail-fast write to the log". Small and well-defined, but Joel's call.

---

## 6. Verification

### Control experiment

The fix was stripped from **repo-root** copies of both scripts (they must sit in the repo root or
`$PSScriptRoot` fails to resolve `Modules\` and the control fails for the wrong reason). Both
control copies were confirmed to **parse cleanly** first — an earlier control attempt failed with
a parse error, which proves nothing, and was rebuilt.

| Assertion | Pre-fix control | Post-fix |
|---|---|---|
| Audit: Error-level records exist | **FAIL — 0 errors** | pass |
| Audit: exactly one `FailFast`/`Terminal` record | **FAIL** | pass |
| Audit: log message matches console text | **FAIL** | pass |
| Audit: `Remediation` preserved | **FAIL** | pass |
| Audit: terminal record is the LAST entry | **FAIL** | pass |
| Audit: Warning-only does not satisfy (Cyclops loophole) | **FAIL** | pass |
| Deploy: one `FailFast` record, `Script` correct | **FAIL — got 0** | pass |

The control reproduces Cyclops's independently-measured signature exactly: **`Error=0`,
console-correlated `=0`**. Control copies deleted immediately after the run.

### Pre-import fallback (site 1)

No test can reach this on PowerShell 7, so it was proven in isolation: the helper was extracted by
AST into a script with a script-scope log path and **no module imported**, so
`Write-TierModelLog` genuinely did not exist. Result — directory created, and a valid record
written:

```
Level=Error
FailFast=True Terminal=True Script=Deploy-TierModel.ps1
Message=FAIL-FAST (terminal): PowerShell 7.x or later is required. Current version: PowerShell 5.1.19041.1
Remediation=Run from a PowerShell 7 (pwsh) console.
```

### Suites — by path, never by tag

| Suite | Result | Baseline | Delta |
|---|---|---|---|
| Unit | **1573 passed / 0 failed** | 1573 / 0 | none |
| Integration | **318 passed / 0 failed** | 318 / 0 | none |

Parse errors 0 in both scripts. HEAD `04ab664`, nothing staged, no stray files.

---

## 7. Scope compliance

Only `Deploy-TierModel.ps1` and `Audit-TierModel.ps1` changed. `tests\`,
`.research\lab-validation\`, `Test-TierModelPrerequisites.ps1` and `TierModel.psm1` untouched. No
commits. No PowerShell 5.1 accommodation. No `[System.IO.Path]::GetFullPath()`. No `-Debug`
forwarded to any AD or GroupPolicy cmdlet.

## 8. Open decision

**Audit site 6** — move the PowerShell-version gate after the logging block to match Deploy, or
accept that the one unsupported-PowerShell gate stays console-only.
