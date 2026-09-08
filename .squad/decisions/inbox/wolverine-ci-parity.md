# Wolverine — CI parity for the Pester suite

Date: 2026-09-06
Branch: feature/enable-verbose-debug (HEAD 04ab664, nothing committed)
Owner: Wolverine (tests only)
Requested by: Joel Platek

## Summary

The local suite and the GitHub PR CI suite were not running the same thing. Two
independent mechanisms made a green local run compatible with a red PR. Both are
now closed, and the suite is 100% green in every shape I can produce.

| Run shape | Discovered | Passed | Failed |
|---|---|---|---|
| Local by path — `tests\Unit.*.Tests.ps1` (25 files) | 1608 | 1608 | 0 |
| Local by path — `tests\Integration.*.Tests.ps1` (7 files) | 318 | 318 | 0 |
| CI-shaped, `Run.Path = "tests"` (32 files, this box, RSAT present) | 1926 | 1926 | 0 |
| CI-shaped, `Run.Path = "tests"`, **RSAT removed** (faithful CI) | 1926 | 1926 | 0 |

CI lint job: 0 issues. CI security job: 3 issues, 0 Errors (gate is Errors-only).
CI coverage gate: 87.37% (14579 / 16686) against a threshold of 80 — PASS.

No product code was changed. Changes are confined to `tests\**`.

## Divergence 1 — StrictMode leaks across containers (64 failures)

`Set-StrictMode -Version Latest` is set at **file scope** in 7 test files. Pester 5
runs every container in the **same session state**, so StrictMode set by one file
applies to every file discovered after it.

- CI sets `$config.Run.Path = "tests"`, so all 32 files run in one session and
  `Integration.Audit.Tests.ps1` (alphabetically first, line 15) turns StrictMode on
  for the whole run.
- Locally we run by path in **two separate processes**, and inside the Unit run the
  first StrictMode setter is `Unit.ModuleManifest.Tests.ps1` at position 24 of 25 —
  so almost nothing downstream is affected.

Proven with a 4-file minimal repro in a fresh process: `STRICT=off` → 0 failures,
`STRICT=on` → 64 failures, same files, same order.

The 64 were **all test defects**, not product defects:

1. `Unit.CanonicalAclRepair.Tests.ps1` (44) — helper `New-SdFromAceSpecs` read
   `$s.IsObject`, a key its own comment documents as *optional*. Under StrictMode
   this threw inside `BeforeAll`, taking the whole `Describe` down.
   Fixed with `$s.ContainsKey('IsObject') -and $s.IsObject`.
2. `Unit.GpoOperations.Tests.ps1` (16 of 17) — `Mock Set-ADObject { return $null }`
   and `Mock Write-Host { return $null }`. The real cmdlets emit nothing; `return
   $null` pushes a literal `$null` into the caller's output stream, so `$result` was
   a **2-element array** `@($null, <real result>)`. Without StrictMode, member
   enumeration silently skipped the `$null`; with it, `$result.Executed` threw.
   Fixed by making the mock bodies empty. Verified behaviour-neutral by A/B run:
   153/153 pass and identical product warning counts either way.
3. `Unit.OuAclOperations.Tests.ps1` (2) — `($x | Where-Object {...}).Count` where the
   filter can legitimately match nothing (`$null.Count`), and a deliberate
   "this property should be absent" assertion written as `$result.Converged | Should
   -BeNullOrEmpty`. Fixed with `@(...)` and with
   `$result.PSObject.Properties.Name | Should -Not -Contain 'Converged'`.
4. `Unit.GpoOperations.Tests.ps1` + `Unit.OuOperations.Tests.ps1` (2) — a local
   `$callCount = 0` initialiser paired with `$script:callCount++` inside the mock
   body. Two different variables. Without StrictMode the `$script:` one starts
   undefined and increments from `$null`; with it, it throws, so *every* mocked call
   failed and the counters read 0. Fixed by initialising at `$script:` scope. I
   swept `tests\` for this shape — these were the only two.

## Divergence 2 — no RSAT on the runner, stub signatures too narrow (13 failures)

Every stub in `tests/helpers/ADStubs.ps1` is guarded by
`if (-not (Get-Command <cmdlet>))`. This workstation has RSAT, so the AD block never
defines locally and the suite binds against the **real** `ActiveDirectory` cmdlets.
CI has no RSAT, so it binds against the stubs.

That matters because `Mock` binds parameters against the *mocked command's* metadata.
Where a stub's signature is narrower than the real cmdlet, a product call that is
perfectly valid in production **fails to bind in CI**, the product's `catch` swallows
it, and the test reports "expected 1 call, got 0" — with no hint that the harness,
not the product, was at fault.

Three stubs were missing parameters the product legitimately passes:

| Stub | Missing | Product call site |
|---|---|---|
| `New-ADUser` | `ChangePasswordAtLogon`, `Confirm` | `New-TierModelUser.ps1` L105, L91 |
| `New-ADGroup` | `Confirm` | `New-TierModelGroup.ps1` L128 |
| `Add-ADGroupMember` | `Confirm` | `New-TierModelUser.ps1` L118 |

`Confirm` is available on the real cmdlets via `SupportsShouldProcess`. I added a
plain `$Confirm` parameter rather than declaring `SupportsShouldProcess`, matching the
convention already used by the `New-ADOrganizationalUnit` and
`Set-ADOrganizationalUnit` stubs in the same file. Both copies of each stub (script
scope and the in-memory `ActiveDirectory` module) were updated.

**The product is correct here. The harness was wrong.** No product change was made or
is needed.

### How the no-RSAT run was reproduced

Two earlier attempts were wrong and were discarded:

- Forcing the `Get-Command` guards open while the real `ActiveDirectory` module is
  still importable — the real module and the in-memory stub module coexist, which
  never happens on a runner.
- Removing `C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules` from `PSModulePath`
  entirely — that also removes ~96 inbox modules that windows-latest **does** have,
  and produced 80 bogus `Unit.Prerequisites` failures.

The faithful method: mirror the inbox module directory with directory junctions,
omitting only `ActiveDirectory`, and point `PSModulePath` at the mirror. `ADStubs.ps1`
is left untouched so its own guards decide, exactly as they do on the runner.
Verified environment: `AD=0 LAPS=1 GroupPolicy=1 Pester=present`. Script is
`norsat3.ps1` in the session workspace.

## Answers to the specific questions

**Does CI run the "Manual Integration Tests" file of 378 tests?** No. The file is
`tests\Manual.Integration.Tests.xlsx` — an Excel workbook, not PowerShell. Pester
discovers `*.Tests.ps1` only. CI discovers **32 `.ps1` files**, confirmed by
enumerating `$result.Containers`. README's "32 test files" figure counts the xlsx and
is off by one against the `.ps1` count of 32... which now matches only because I added
`Unit.AuditReporting.Tests.ps1`. Before today CI discovered 31.

**Is `Unit.AdmxImport.Tests.ps1` path-dependence a latent CI failure?** No. I copied
the entire working tree to `%TEMP%\adtm-pathtest`, set the working directory there, and
ran the file: **27/27 pass**. The file references only `$PSScriptRoot`, never a
CWD-relative path. The 3 failures seen previously came from a *partial* scratch copy
that lacked repo fixtures, not from the absolute path. Closing this as not-a-CI-risk.

**Is `Missing + Mismatch < Drift` still permitted?** Yes, unchanged. GPO and
WinLapsDecryptor define Drift to include an error component the Missing/Mismatch
breakdown does not name. The new reconciliation tests assert `Missing + Mismatch <=
Drift`, never equality, and one test documents the exception explicitly.

## Recommendations (not actioned — outside my remit or needing Joel's ruling)

1. **Make the local run CI-shaped by default.** The whole class of bug in Divergence 1
   exists only because we run by path in two processes. A `Run.Path = "tests"` single
   session locally would have caught all 64 the day they were written. Cheapest
   durable fix available.
2. **Set `Set-StrictMode -Version Latest` in every test file**, or in none. Seven of
   32 is the worst configuration: strictness depends on discovery order, so a file
   that passes today fails when someone adds an alphabetically earlier file. I did not
   do this because it changes 25 files I had no failure evidence for; it should be a
   deliberate ruling.
3. **Stub fidelity needs a guard.** Divergence 2 is silent by construction: the stub
   is only exercised where RSAT is absent, and the failure mode is a swallowed binding
   error that looks like a product bug. Consider a test that, for each stubbed cmdlet,
   compares the stub's parameter set against the parameters the product actually
   passes. I did not write it — it needs a ruling on whether `tests/helpers` is in
   scope for that kind of meta-test.
4. **CI floats its Pester version** (`>=5.0.0 <5.99.99`, installed fresh each run).
   Local is 5.9.0, inside the range, so there is no divergence today — but a Pester
   5.10 release could change discovery or mock binding without any change from us.
   Pinning would remove one uncontrolled variable.
