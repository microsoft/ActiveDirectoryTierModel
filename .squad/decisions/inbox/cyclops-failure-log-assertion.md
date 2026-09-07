# Decision — A failed run must prove its failure reached the log

- **Author:** Cyclops (lab validation)
- **Date:** 2026-09-05T13:20:35.4638834+08:00
- **Requested by:** Joel Platek
- **Scope of change:** `.research\lab-validation\` only. No product script, module or test was
  modified. Nothing committed. Nothing run against the lab VM.

---

## 1. Context

Joel restaged the lab to a clean `WinLapsSchema` baseline and ran the harness against the real
`Deploy-TierModel.ps1` / `Audit-TierModel.ps1` for the first time. The transcript work held up:
`T-native-vd` passed in 15.9 s, and an independently opened transcript showed 55 `VERBOSE:` and
52 `DEBUG:` lines — the identical counts the capture harness reported.

He then read the `ENTRIES` column of the harness's own summary table. Every failure row wrote
exactly **7** log entries. One row ran `13:08:16 → 13:11:26`; its log's final entry is at
`13:08:18`. Three minutes and the entire failure are absent from the log, while the console
carried the full unreachable-DC message and its remediation block.

**Cause (confirmed in source, read-only):** `Write-TierModelFailFast` exists in both scripts
(`Deploy-TierModel.ps1` L393, `Audit-TierModel.ps1` L241) and calls **only `Write-Host`**. Seven
call sites cover the PowerShell-version gate, the dMSA DFL gate and the general prerequisite
gate. No fail-fast gate is logged. Tracked as **BUG-029**; the product fix is dispatched
separately and is explicitly **not** part of this change.

The harness had the evidence — it measured, printed and displayed `7` — and passed the row.

## 2. Decisions

### D1 — A row that fails must prove the failure reached the log

Two checks are added to any row that is **expected to fail or actually exited non-zero**:

| Check | Passes when |
|---|---|
| `Failure recorded in log` | the log holds an `Error`-level entry, **or** an entry whose message corresponds to the failure the console reported |
| `Log continues past start-up records` | the log's final entry is not a routine start-of-run record |

Both must hold.

- **`log is non-empty` is explicitly rejected** as the check. Seven entries is non-empty and
  useless.
- **Bare `Warning` level is not accepted as evidence.**
  `Test-TierModelPrerequisites.ps1` L264 logs a `Warning` while merely probing modules, so
  "a Warning exists somewhere" would be a free pass on a run whose real failure was never
  recorded. A `Warning` that *correlates with the console failure* does count.
- **The console failure text is derived structurally** from the fail-fast layout
  (`Remediation steps:` and the message lines above it), not from a hardcoded error string, so
  the correlation covers every gate rather than only the unreachable-DC rows.
- The routine start-of-run list is taken from source (Deploy L793/L800, Audit L516/L521,
  `Test-TierModelPrerequisites` L87/L218/L253/L293), not invented.
- A third check reports how much of the run's wall clock falls after the last log entry. It is
  **`INFO`, never asserted**: the product stamps *local* time with a `Z` suffix, so any
  threshold would be built on a known-wrong timezone label.

**Seen to fail before being believed.** Against a stub reproducing today's product behaviour
both checks FAIL (`7 entries; Error=0, console-correlated=0`; last entry
`[Debug] Module check details`). Against a stub with the fix modelled — one `Error` entry
carrying the failure — both PASS. Recorded in the proof output, not asserted from confidence.

### D2 — The trigger is the observed exit code, not the row category

The question "did this failed run record its failure?" is as valid for a run that dies mid-apply
as for one stopped at a fail-fast gate, so the trigger is **expected-to-fail OR observed
non-zero exit**.

This is not a vacuous extension: the mid-run paths *do* log at `Error` level today (12
`Error`/`Warning` log call sites across the two scripts), so the check can pass there and can
catch a regression that removed one. Proven with a stub that fails mid-run and logs an `Error`
entry — it PASSES.

**Deliberately excluded:** runs that fail while exiting `0`. Deploy's declined-confirmation path
and the dMSA DFL gate both return `0` and both already have dedicated checks. Asserting failure
evidence for runs the product does not treat as failures would be asserting the wrong thing.

### D3 — `0/0` becomes `NOT COVERED`, never `PASS`

Reporting `FAIL` for an aggregate with no rows in scope is noise; reporting `PASS` would be a
**false green** over an empty population — the exact vacuous-assertion failure mode this harness
exists to remove. `0/0` is therefore a distinct third state: printed as `N/C` in yellow with the
reason, counted separately, never a pass, and never affecting the exit code.

Every aggregate over a row population now routes through one helper (`New-CoverageCheck`).
Auditing them all — rather than fixing the reported instance — found the same pattern in
`Verbose stream reachable` and `Read-Host override reached every gate`.

**Related:** matrix-level `FAIL`s previously printed in red and still exited `0`. Row failures
and matrix-check failures now both set a non-zero exit code.

### D4 — The `-EnableVerbose`-only privacy assertion already existed; its *coverage* did not

`Transcript NOT created` already fires on every row lacking both switches and asserts the
absence of both the announced transcript and any `*transcript*.log` beside the log file. Adding
a second such check would be duplicate coverage dressed as new rigour.

The real gap was the POC-6 gap again: nothing reported whether that assertion had been
*exercised*. A `-RowId` filter selecting only both-switch rows would leave the privacy decision
unguarded and the report would look identical. Closed with a coverage aggregate, not a new row.

### D5 — `-ListOnly` writes nothing

`-ListOnly` claimed `Nothing was executed` while creating `results\run-<stamp>\` with both
generated runner scripts. Fixed in the preferred direction — by making the claim true. Workspace
creation and runner emission moved into `Initialize-RunWorkspace`, called **after** the
`-ListOnly` gate returns.

## 3. What Joel should expect on the next lab run

The three failure rows will report **FAIL**, and the matrix will print
`Failed runs recorded their failure (BUG-029)  0/3 rows passed` in red with a non-zero process
exit code. **That is the harness working correctly against a known product defect.** It should
go green when the BUG-029 fix lands, and not before.

## 4. Evidence

- New: `.research\lab-validation\proof\Prove-FailureLogAssertion.ps1` — **26/26 proven**,
  including the current-behaviour negative control and the stray-`Warning` loophole guard.
- Regression: `Prove-ReadHostOverride` 7/7, `Test-ApplyPathRows` 12/12, `Prove-DcPreflight`
  14/14, `Prove-NativeTranscript` 17/17.
- Default matrix unchanged at 42 rows and still non-mutating; apply rows remain behind
  `-IncludeApplyPaths`.
- All proofs run under `$env:TEMP` against stubs. The only network activity anywhere is a DNS
  lookup of a `.invalid` name (RFC 2606, can never resolve).
