# Decision: Rogue — BUG-019 read failures are log-then-continue, not throw

**Date:** 2026-09-05
**Author:** Rogue (Core Dev)
**Status:** DECIDED in code — needs Joel's review before commit
**Branch:** `feature/enable-verbose-debug`
**Requested by:** Joel Platek

## Context

BUG-019 required every AD/GroupPolicy **read** call site to distinguish "the object does not
exist" from "the read failed". The open question at each of the 33 sites was what to do once a
genuine read failure is detected: fail loudly, or record it and continue.

## Decision

**Genuine read failures are surfaced but never terminate deployment planning.**

The pattern applied to every plan-generation site is:

1. `-ErrorAction Stop` on the read, so the failure is catchable at all.
2. In the catch, classify: `*ADIdentityNotFoundException` / `System.ArgumentException` /
   `CategoryInfo.Category -eq 'ObjectNotFound'` → legitimate not-found, **existing control flow
   preserved byte-for-byte**.
3. Anything else → `Write-TierModelLog -Level Error` + an operator-facing `Write-Warning` naming
   the real underlying message, **then continue**.

## Why not throw

My first implementation escalated a failed `Get-GPO -All` rename search to a `throw`, reasoning
that planning a `CreateGPO` from an unreadable domain risks creating a **duplicate GPO** next to
an existing one.

`tests\Unit.GpoOperations.Tests.ps1:2262` — *"Falls back gracefully when Get-GPO -All throws
during rename search"* — mocks a generic `throw "AD connection error"` and asserts a `CreateGPO`
action is still produced. It failed. The graceful-fallback contract is deliberate and
pre-existing, and it matches Joel's instruction that these empty catches are load-bearing
control flow. **I changed the code, not the test.**

The duplicate-GPO risk is real but is now *visible* rather than silent, which was the actual
point of BUG-019.

## Open question for Joel

For the two `Get-TierModelGpo.ps1` rename-search sites, `$planErrors` **is** in scope, so a
failed enumeration could instead be recorded as a plan error with
`Code = 'GpoEnumerationFailed'`. Because Deploy blocks on validation errors (decisions.md #3),
that would make Deploy refuse to run after a transient read blip rather than plan a possible
duplicate.

I implemented the **consistent log-then-continue** behaviour instead, so all four rename-search
sites behave identically and Deploy's go/no-go is unchanged. Say the word if you want the
Deploy-blocking variant — it is a three-line change in one place.

## Notes that affect everyone

- **The "37" figure includes 2 false positives.** `Get-GpoActionsForConfig` is a *local nested
  function* in `Get-TierModelGpoFd.ps1`, not a GroupPolicy cmdlet; the `Get-GP*` noun pattern
  matched it. It has **no `[CmdletBinding()]`**, so passing `-ErrorAction` to it would throw.
  The true BUG-019 population is **35** (33 Rogue-owned). A re-run audit floors at 4 "None",
  not 0. The other two are `Audit-TierModel.ps1:620` and `optional\Redirect-DefaultContainers.ps1:46`,
  both outside my boundary this session.

- **`tests\helpers\ADStubs.ps1` stubs for `Get-ADDomain`, `Get-ADRootDSE` and `Get-GPInheritance`
  have no `$ErrorAction` parameter.** This turned out to be harmless — a simple function accepts
  and ignores `-ErrorAction`, verified empirically including under a real Pester `Mock`. But it
  also means **the stubs never throw, so the whole suite exercises none of the new catch blocks.**
  A green run is not evidence the error paths work. Lab validation on `TierLab-DC01` is still
  outstanding for BUG-019.

- Use the string form `$_.Exception.GetType().FullName -like '*ADIdentityNotFoundException'`.
  The type literal `[Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]` fails to
  resolve whenever the ActiveDirectory module is not loaded, which is exactly the stubbed test
  environment.
