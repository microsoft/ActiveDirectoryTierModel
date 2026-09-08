# Decision — Audit `-Logging`: prompt rule, and a hard-stop at the domain-DN read

**Author:** Rogue (Core Dev)
**Date:** 2026-09-05 (section 1 revised same day)
**Branch:** `feature/enable-verbose-debug`
**Scope:** `Audit-TierModel.ps1` (WI-11, WI-12, BUG-019 L620)
**Status:** Proposed — for Joel's review. Nothing committed.

---

## 1. `-OutputFileBase` prompt rule for `-Logging`

**Decision — the rule depends on *how* `-Logging` became active:**

| How `-Logging` turned on | Missing `-OutputFileBase` behaviour |
|---|---|
| **Explicit** — operator passed `-Logging` | **Prompt** via `Read-Host`; empty response throws `"OutputFileBase cannot be empty when Logging is enabled"` |
| **Implicit** — a diagnostics switch auto-enabled it (WI-13, not yet built) | **Never prompt.** Default to `'Audit-TierModel'` silently |

**Revision note.** My first implementation defaulted silently in *both* cases, following an
instruction to never prompt. Joel corrected this: D8's non-interactive constraint applies
only to the auto-enable path, not to an explicitly-passed `-Logging`, and the plan (L126)
specified WI-12 to include the prompt.

**The decisive argument was internal consistency, not Deploy parity.**
`Audit-TierModel.ps1` **already prompts** for `-OutputFileBase` when `-OutputFormat` is
supplied without one. A silent default for `-Logging` meant *the same variable had two
different behaviours in the same script* — prompt on one path, silent default on the other,
with no principle separating them. That is worse than the Deploy/Audit asymmetry I
originally flagged. The rule as now implemented is coherent: **`-OutputFileBase` is prompted
for wherever it is required and missing; the sole exception is a switch the operator did not
ask for turning logging on implicitly, because a diagnostics re-run must stay copy-pasteable
and runnable in a non-interactive host.**

**Implementation — the WI-13 hook.** A `$script:LoggingAutoEnabled` flag (initialised
`$false`) selects the branch. WI-13's auto-enable block has a marked insertion point
immediately above the validation block and needs only to set `$Logging = $true` and
`$script:LoggingAutoEnabled = $true`, then fall through. **WI-13 itself is not built here** —
it remains gated on the outstanding POCs.

**Verified at runtime, not just by inspection** (all three cases executed):

| Case | Result |
|---|---|
| `-Logging`, no `-OutputFileBase`, empty response | throws the expected message |
| `-Logging`, no `-OutputFileBase`, response `MyAudit` | `MyAudit-090526-0928.log` |
| Auto-enable simulated (flag flipped in a `$env:TEMP` scratch copy) | no prompt, `Audit-TierModel-090526-0928.log` |

The third case proves WI-13's hook is reachable and correct before WI-13 exists.

**For Wolverine (WI-20 item 12):** the planned assertion *"`-Logging` without
`-OutputFileBase` prompts and throws on empty"* is **valid again** and matches Audit as
built. The additional Audit-specific assertion worth adding is the auto-enable counterpart
once WI-13 lands: auto-enabled logging must **not** prompt and must default to
`'Audit-TierModel'`.

**Deploy is untouched.** Joel is handling the Deploy side of the prompt rule separately.

---

## 2. The domain-DN read at (old) L620 hard-stops

**Decision.** `$domainDn = (Get-ADDomain -Server $DomainController).DistinguishedName` in
`Invoke-CanonicalAclAudit` now uses `-ErrorAction Stop`, is wrapped in `try/catch`, and
**throws** on failure — plus an explicit guard that throws on a null/whitespace DN. This is
the opposite of the log-then-continue pattern I applied to the other 33 BUG-019 sites.

**Why throw here.**

1. **The callers already contain it — this is the load-bearing reason.** Both call sites,
   Phase 1b (`Audit-TierModel.ps1` ~L838) and the `-OuOnly` Canonical ACL Check (~L1404),
   already wrap `Invoke-CanonicalAclAudit` in `try/catch` that surfaces
   `$_.Exception.Message` as a warning and proceeds to the next phase. So the effect is
   **this phase fails loudly and honestly; the rest of the audit still runs.** That satisfies
   "fail loudly" *and* decisions.md section 3 (Audit warns and continues) simultaneously, and
   it means a transient DC blip cannot kill a whole audit. **Check the caller's catch before
   choosing throw vs continue — the same keyword means opposite things depending on who
   catches it.**
2. **No legitimate not-found case.** The domain always exists, so every exception from this
   call is a genuine read failure. There is no not-found branch to preserve.
3. **No graceful fallback exists.** `$domainDn` feeds placeholder substitution for every
   configured OU. A `$null` does not degrade the audit — it makes every OU DN garbage, so
   every OU resolves as absent and the phase reports a **confident, wrong verdict**. For an
   audit tool a false clean is the worst possible failure mode.
4. **Contrast with the rename-search sites.** There, `Unit.GpoOperations.Tests.ps1:2262`
   encodes an explicit graceful-fallback contract. Nothing equivalent exists here, and there
   is nothing sensible to fall back *to*.

**Verified, not assumed:** `Write-TierModelLog -Level 'Error'` emits via `Write-Host`, not
`Write-Error`, so the log call in the catch cannot pre-empt the `throw` under Audit's
`$ErrorActionPreference = 'Stop'`.

---

## 3. Standing caveat — the suites still do not test the new behaviour

Unit 1573/0 and Integration 318/0 match baseline, but **no test in either suite constructs
Audit's `-Logging` path or drives the domain-DN failure branch.** Green means "nothing
regressed", not "the new code works". Two gaps are now closed by evidence rather than
assertion:

- **Module-scope logging** — proven by
  `.research\verbose-vs-debug-poc\guest\Test-ModuleScopeLogging.ps1`, result recorded in
  `.research\verbose-vs-debug-poc\results\module-scope-logging.md`.
  Headline: **without module-scope init, no log file is created at all.**
- **Prompt rule** — proven by the three runtime cases in section 1.

**Still unexercised:** the L695 throw path. It needs WI-19 lab validation against a real DC.
