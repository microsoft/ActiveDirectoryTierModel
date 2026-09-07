# Decision: ADStubs.ps1 — Option D applied (`[CmdletBinding()]`, hand-rolled `$ErrorAction` removed)

**Date:** 2026-09-05
**Author:** Wolverine (Tester)
**Status:** Applied to working tree — NOT staged, NOT committed. Joel reviews.
**Requested by:** Joel Platek (Option D approved)
**File:** `tests/helpers/ADStubs.ps1` (note: **not** `tests/ADStubs.ps1`)

## What changed

All **76** stub functions now declare `[CmdletBinding()]`, and the hand-rolled
`$ErrorAction` parameter was deleted from the **66** stubs that had one.
`[CmdletBinding()]` supplies `-ErrorAction` as a genuine common parameter that actually
governs error behaviour. Applied by an AST-driven transform (offsets re-derived at run
time, edits applied back-to-front, output re-parsed before writing).

**Parameters added during triage: 0.** See "The predicted red run did not happen" below.

## Correction 1 — the stubs never load on a developer workstation

`ADStubs.ps1` wraps every stub group in `if (-not (Get-Command <cmdlet> -ErrorAction SilentlyContinue))`.
This machine has RSAT installed: `ActiveDirectory`, `GroupPolicy` and `LAPS` are all present
as real modules. Therefore **74 of the 76 stubs never define locally** — only the two legacy
`AdmPwd.PS` stubs (`Get-AdmPwdPassword`, `Set-AdmPwdPassword`) do, because that module is absent.

Consequences the team must internalise:

- **A green local suite says nothing about stub behaviour.** Locally the tests bind against
  the real AD cmdlets, which have always honoured `-ErrorAction`. The defect was only ever
  reachable in CI.
- My first probe was vacuous for exactly this reason: it reported "BEFORE already throws",
  because `Get-ADGroup` resolved to the real cmdlet. Caught by adding a `PROBE-0` that asserts
  `CommandType -eq 'Function'`.
- To exercise the stubs locally you must **force the guards open**. Do this in a scratch copy,
  never in the repo.

## Correction 2 — the `Get-Acl` / `Set-Acl` stubs are unreachable everywhere

They are guarded by `if (-not (Get-Command Get-Acl ...))`. `Get-Acl` ships in
`Microsoft.PowerShell.Security` and is present in CI as well as locally, so that block can
never execute. Those two stubs are dead code in every environment. They were given
`[CmdletBinding()]` for consistency; no behaviour depends on them. **Flagged, not removed** —
deleting them is a separate call for Joel.

## Correction 3 — the predicted CI-wide red run did not happen

I predicted that turning simple functions into advanced functions would break every call site
passing an undeclared named argument. Measured under a CI-faithful run (full repo copy, guards
forced open, stubs verified to shadow the real cmdlets both globally and inside the `TierModel`
module scope):

- CI-faithful **Integration: 318/318/0**.
- CI-faithful **Unit: 1570/1573**, 3 failed — and the **same 3 failed in both controls**
  (original stubs forced open; and the scratch copy with stubs *not* forced open). They are
  path-dependence artifacts of running `Unit.AdmxImport.Tests.ps1` from a scratch location,
  **not** caused by Option D.
- **Zero** occurrences of `A parameter cannot be found that matches parameter name` or
  `ParameterBindingException` across either CI-faithful run.

Why the forecast was wrong: the stub signatures already matched the call sites. The only
common parameter the product actually passes to these cmdlets is `-ErrorAction`, and that is
precisely the one `[CmdletBinding()]` now supplies for real.

## Standing guidance this creates

1. **`Mock { Write-Error ... }` + `-ErrorAction Stop` is now a valid CI assertion shape.** It
   was not before. The ~27 planned error-handling tests can be written against it.
2. **Never add a hand-rolled `$ErrorAction` (or `$Verbose`, `$Debug`, `$ErrorVariable`) to a
   stub.** It shadows the common parameter and silently discards it. Add `[CmdletBinding()]`
   instead. Worth an AST guard test.
3. **New stubs must declare `[CmdletBinding()]`.** A simple function silently swallows
   undeclared named arguments, which lets a test assert a signature that does not exist.
4. **Do not add `SupportsShouldProcess` to stubs.** Seven stubs declare a plain `$Confirm`
   parameter; that binds correctly on an advanced function without ShouldProcess, and was
   verified at runtime. Adding ShouldProcess would make `-Confirm` a reserved common parameter
   and collide with the declared one.
