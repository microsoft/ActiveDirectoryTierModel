# Decision / risk — WI-04 + WI-10 leave BOTH entry scripts with inert diagnostics switches

**Author:** Rogue (Core Dev)
**Date:** 2026-09-05
**Branch:** `feature/enable-verbose-debug`
**Scope:** `Deploy-TierModel.ps1` (WI-04, WI-10, auto-enable seam), `Audit-TierModel.ps1` (`.NOTES` only)
**Status:** ⚠️ **Raising a risk, not proposing a change.** Nothing committed.

---

## 1. ⛔ The risk — declared-but-inert diagnostics switches, now in both scripts

Cyclops raised this as **B-3** in the implementation plan (§1a) about `Audit-TierModel.ps1`.
**WI-04 has now created the identical condition in `Deploy-TierModel.ps1`, by design and on
instruction.** I am recording it because the plan says it must not be committed in this
state, and the work is deliberately being landed in stages.

As the working tree stands:

```
.\Deploy-TierModel.ps1 -PreferredDc DC01 -OuOnly -EnableVerbose -EnableDebug
.\Audit-TierModel.ps1  -PreferredDc DC01 -OuOnly -EnableVerbose -EnableDebug
```

Both are **accepted without error and do nothing.** No verbose output, no debug output, no
transcript, no `Debug\` folder, no warning. In both files the two parameters are referenced
only at their own declarations.

Cyclops's framing is right and worth repeating: this is the worst failure mode this feature
can have, because the switch silently no-ops **at the exact moment something is already
broken and the operator is reaching for diagnostics**. It manufactures false confidence —
the operator concludes *"diagnostics showed nothing"* rather than *"diagnostics never ran"*.

**WI-10 makes this sharper, not milder.** Deploy's help now *documents* behaviour that does
not exist yet: that the switches auto-enable `-Logging` (WI-05) and that both together start
a transcript in `Debug\` (WI-07). I wrote it that way because WI-10 specifies that wording
and it is the correct shipping text — but until WI-05…WI-09 land, **`Get-Help` describes
behaviour the script does not have.**

**This is a sequencing risk, not a defect in the work.** It is bounded: nothing is
committed, Joel is holding WI-05…WI-09 pending POC-8, and he owns the commit boundary. Two
ways to close it, both his call:

- **(a) Land WI-05…WI-09 before any commit** — preferred, and the plan's own instruction.
- **(b) If any part of this must be committed sooner,** either remove the four declarations
  and the two Deploy `.PARAMETER` blocks until they are wired, or add a temporary guard that
  warns loudly when a diagnostics switch is supplied but not yet implemented.

**I did not choose between these.** Joel scoped me to declaration-only and said explicitly
that WI-05…WI-09 arrive once POC-8 resolves. Flagging, not acting.

---

## 2. The auto-enable seam is now symmetric across both scripts

Deploy has the twin of Audit's seam: a `$script:LoggingAutoEnabled` flag (init `$false`)
selecting the branch, and a `# WI-05 HOOK` comment marking the insertion point. WI-05's
implementer sets `$Logging = $true` and the flag, then falls through.

**Deploy's existing `Read-Host` prompt is preserved unchanged** — it is shipped behaviour.
The seam only adds the bypass that the future implicit path will use. Defaults differ by
script and match each plan item: `'Deploy-TierModel'` (WI-05) and `'Audit-TierModel'`
(WI-13).

**Verified at runtime, all three branches, on Deploy** (mirroring what I did for Audit):

| Case | Result |
|---|---|
| `-Logging`, no `-OutputFileBase`, empty response | throws `OutputFileBase cannot be empty when Logging is enabled` |
| `-Logging`, no `-OutputFileBase`, response `MyDeploy` | `MyDeploy-090526-0941.log` |
| Auto-enable simulated (flag flipped in a `$env:TEMP` scratch copy) | no prompt, `Deploy-TierModel-090526-0941.log` |

`(Get-Command …).Parameters` confirms the diagnostics parameter *sets* are equal across the
two scripts — the WI-20 parity assertion passes today.

---

## 3. Version strings corrected — with Joel's explicit authorisation

WI-10 says *"flag the staleness; do not unilaterally renumber"*. **Joel authorised the
renumber directly in the task brief**, so it is done rather than merely flagged:

| Location | Was | Now |
|---|---|---|
| `Deploy-TierModel.ps1` L198 | `Version: 1.3.0` | `Version: 2.1.0` |
| `Deploy-TierModel.ps1` L199 | `(v1.3.0+)` | `(v2.1.0+)` |
| `Audit-TierModel.ps1` L132 | `Version: 2.0` | `Version: 2.1.0` |
| `Audit-TierModel.ps1` L133 | no PowerShell requirement | `(v2.1.0+), PowerShell 7.0+` + SeSecurityPrivilege note |

Authoritative source is `TierModel.psd1:3` (`ModuleVersion = '2.1.0'`). No `1.3.0` or
`Version: 2.0` string remains in either script.

**On the Audit `.NOTES` privilege line:** I verified before writing it that Audit's
`-EnableAuditing` genuinely *reads* the domain-root SACL (`Get-TierModelAuditRule` analyses
the existing SACL), so SeSecurityPrivilege is a real requirement for that path and not
copied boilerplate from Deploy.

**Note for Scribe:** a version bump normally travels with a CHANGELOG entry. `CHANGELOG.md`
is deliberately untouched — per Joel the entry lands in one place once the feature is whole.
This correction should be included in it.

---

## UPDATE 2026-09-05 — B-3 IS CLOSED

Deploy WI-05..WI-09 and Audit WI-13..WI-16 landed. Both scripts now wire `-EnableVerbose` and
`-EnableDebug` end-to-end: preference variables set at script *and* module scope after the
module import, `-Logging` auto-enabled without prompting, a `Debug\` folder beside the resolved
log file, and a transcript when both switches are supplied.

The inert-switch window is gone. The help in both scripts now documents behaviour that exists.

Verified at runtime, not inferred:
- auto-enable prints the announcement line and does not prompt
- a relative `-LogPath` puts the log file and `Debug\` in the same directory
- `-EnableVerbose` alone creates `Debug\` but **no** transcript
- the transcript is created, contains 0 `Loading:` / 0 `Exporting function` records, and is
  properly closed by the guarded stop
- the re-run hint is copy-pasteable and is suppressed when both switches are already on

Unit 1573/0, Integration 318/0.
