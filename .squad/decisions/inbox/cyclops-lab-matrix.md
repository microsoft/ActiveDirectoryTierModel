# Decision: Cyclops — Lab validation matrix scope, and what it deliberately does not assert

**Date:** 2026-09-05 · **Author:** Cyclops · **Status:** proposed, awaiting Joel
**Artefacts:** `.research\lab-validation\Invoke-LabValidationMatrix.ps1`, `.research\lab-validation\README.md`

## Context

Joel's step 3 requires lab validation of `-EnableVerbose` / `-EnableDebug` on `TierLab-DC01`
(rollback checkpoint `WinLapsSchema`). The harness is built, self-reviewed, parse-clean and
negative-tested. It has **not** been run against the lab.

## Decisions

### 1. The matrix is entirely non-mutating, and apply-path diagnostics stay manual

No row passes `-ConfirmApply`. Both of Deploy's confirmation gates use `Read-Host`, so an
apply row would hang a non-interactive run — this is not a preference, it is a hard blocker.
Consequence: **diagnostics behaviour on the apply path is not covered by any automated harness
and must be checked by an operator by hand.** If the team wants that automated, the gates need
a non-interactive acknowledgement mechanism, which is a product change with its own risk.

### 2. `-EnableDebug` record emission is NOT asserted, because it cannot honestly be

The repository has **4** `Write-Debug` call sites (`New-TierModelOu` ×2,
`Repair-TierModelCanonicalAcl`, `Write-TierModelLog`) and **0** `-Level 'Debug'` log calls.
None are on a plan-only path. A plan-only run emits **zero** debug records by construction.

`> 0` would fail spuriously; `>= 0` would never fail. The harness measures the count and
reports it as INFO, and asserts the debug *plumbing* strictly instead (announcement,
`-Logging` auto-enable, `Debug\` folder, transcript).

**Team-relevant consequence:** a fully green matrix does **not** mean `-EnableDebug` produces
useful output. Making that assertable requires adding debug instrumentation on plan-only paths
— a code change, not a harness change. Flagged for Rogue / a follow-up work item; not agreed
here.

### 3. Relative `-LogPath` rows are mandatory and the co-location check alone is insufficient

A `[System.IO.Path]::GetFullPath()` regression relocates the log file **and** the `Debug\`
folder together, so they remain co-located while both land in the wrong directory. Any future
test that checks only co-location will pass through that bug. Both halves are required:
co-location, **and** that the shared parent is the PowerShell-location-relative one with no
stray directory under the process CWD. Verified by injection: the absolute-path row did not
detect the regression; the relative row did.

### 4. Failure-path rows are opt-in and narrow

`tests\helpers\ADStubs.ps1` L88-L104 accept `-ErrorAction` but never throw, so the green
1573/318 suite exercises none of the ~33 BUG-019 catch blocks. The harness's unreachable-DC
rows abort inside prerequisite validation and exercise the failure *reporting* apparatus
(exit code, hint emission, hint suppression, log-file-on-failure). They do **not** exercise the
33 catch blocks individually; that needs per-call-site fault injection and is separate work.
Recording this so a green run is not read as "BUG-019 is validated."

## Reusable engineering findings (worth propagating beyond this harness)

- **PowerShell array splatting mis-binds switch parameters.** Use hashtable splatting whenever
  switches are involved. Array splatting is positional.
- **`exit` inside a script invoked with `&` does not set the caller's process exit code.**
  Propagate `$LASTEXITCODE` explicitly — and read it via `Get-Variable -ErrorAction
  SilentlyContinue`, because under `Set-StrictMode -Version Latest` an unset `$LASTEXITCODE`
  throws.
- **Neither of the above is visible to `Parser::ParseFile`.** A harness must be executed, and
  executed against a deliberately broken subject, before it is trusted.
- **Assertions about ordering must be derived from source line numbers.** An early check
  required the transcript to contain `Diagnostics enabled:` — impossible, because Deploy prints
  it at L662 and starts the transcript at L676.
