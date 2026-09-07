# Decision note - instrumentation blind spots and how this project should handle them

**From:** Cyclops (Test/Validation)
**Date:** 2026-09-05
**Trigger:** Joel measured that a harness row's `capture.tsv` held 55 verbose and 52 debug
records while the same run's transcript held zero `VERBOSE:` and zero `DEBUG:` lines.
**Scope of change:** `.research\lab-validation\` only. Nothing committed.

---

## 1. The finding

The validation harness merges every stream into a pipeline so it can classify records by .NET
type. That interception means the **host never renders** the records, and PowerShell
transcription records only what the host renders. Measured on the lab DC, row `D-ou-vd`:

| | `capture.tsv` | transcript |
|---|---|---|
| via the standard runner | 55 verbose / 52 debug | 286 lines, `VERBOSE:` **0**, `DEBUG:` **0** |
| same call, no capture | n/a | 224 lines, `VERBOSE:` **55**, `DEBUG:` **52** |

**Neither the product nor the harness is defective.** `Start-Transcript` works correctly. The
harness's own instrumentation consumed the evidence.

## 2. Decision: a check that cannot fail must never be written

The tempting fix was to re-prefix the harness's `Write-Host` echo with `VERBOSE: ` so the
transcript "looked right". That would have made the harness assert against evidence it
manufactured itself - a permanently green tautology. Rejected.

Two honest options were taken together:

- **Declare the gap.** Capture rows emit an explicit `SKIP` named `Transcript stream content`
  that reports the observed zeros and states they are expected under stream capture. Those rows
  still assert what they genuinely see: existence, `Debug\` location, non-zero size, and the
  post-start `UNREDACTED` banner.
- **Buy the observation with a dedicated instrument.** One new row, `T-native-vd`, runs Deploy
  through a second runner with no stream capture at all and asserts `VERBOSE:`/`DEBUG:` line
  counts are non-zero. It forgoes `capture.tsv` entirely; that is the accepted trade.

**Proposed as a general rule for this project:** when instrumentation cannot observe something,
say so in the output. Do not let the absence of a check read as a pass.

## 3. Decision: report expected values, assert only invariants

The lab baseline for `-OuOnly -EnableVerbose -EnableDebug` on a freshly restaged
`WinLapsSchema` domain is **55 verbose / 52 debug** lines. It reconciles with the four
`Write-Debug` sites in the product, two of them per-OU in `New-TierModelOu.ps1` (~25 OUs x 2).

That baseline is recorded as an `INFO` comparison and **never asserted**. The counts track the
OU and group inventory and will legitimately drift when the model definition changes; asserting
equality would build a check that fails on correct work. The harness asserts `> 0` only. If the
counts move and the model did not change, that is worth investigating.

## 4. Consequence to expect on the lab

Every capture row supplying both diagnostics switches now reports `PASS*` (no failures, one
recorded skip) rather than `PASS`. This is intended - the gap is stated on each affected row
rather than hidden. `T-native-vd` reports a clean `PASS`. Default matrix: 41 -> 42 rows, still
non-mutating.

## 5. Correction recorded against my own work

The runner comment claiming the `Write-Host` echo kept transcripts "representative" was false
and has been replaced with the measurement. This is the second false claim of mine Joel has
caught, both of them plausible-sounding statements written without evidence. A comment
asserting a behaviour is a claim, and claims need proof.

## 6. Evidence

`proof\Prove-NativeTranscript.ps1` reproduces the blind spot off-lab against a stub emitting
exactly 7 verbose and 5 debug records (capture runner: tsv 7/5, transcript 0/0), proves the
no-capture runner's transcript contains exactly 7 and 5, and includes a negative control in
which a silent stub **fails** the new checks. **17/17 assertions.** Full suite: 7/7, 12/12,
14/14, 17/17. No lab VM contact.
