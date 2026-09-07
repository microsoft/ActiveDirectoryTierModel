# BUG-035 — `Redirect-DefaultContainers.ps1` reads the domain without `-ErrorAction`

**Author:** Rogue (Core Developer)
**Date:** 2026-09-05
**Files:** `optional\Redirect-DefaultContainers.ps1` only
**Status:** Implemented, verified, uncommitted

## Problem

`optional\Redirect-DefaultContainers.ps1` read the domain with no `-ErrorAction`:

```powershell
$Domain = Get-ADDomain
$DomainCN = $Domain.DistinguishedName
```

On a failed read the error is non-terminating, `$Domain` is `$null`, `$DomainCN` is empty, and
the script continues. The redirection targets are built by string interpolation, so the failure
does not surface — it produces the malformed DN `OU=Tier 2 End-User Accounts,` and hands it to
`redirusr`/`redircmp`. The operator then sees a container-redirection failure that points
nowhere near the domain read that actually broke.

This is the same class as the BUG-019 sweep: an unguarded AD read whose `$null` result is
silently absorbed into a downstream string.

## Sweep result

AST sweep of `optional\` for AD/GroupPolicy cmdlet invocations lacking `-ErrorAction`:

- `Redirect-DefaultContainers.ps1` — **1** site (L46, the one above)
- `Update-TierModelMembership.ps1` — **0** sites; all **29** AD calls already carry
  `-ErrorAction Stop`

This confirms the reviewer's independent figure of exactly one remaining site repo-wide.
That directory has never been linted or tested, so the sweep was run rather than assumed.

## Fix

`-ErrorAction Stop` inside try/catch, matching the BUG-019 house pattern, **plus** an explicit
empty-DN guard.

## Why `-ErrorAction Stop` alone is not sufficient — measured, not assumed

The control exercises two independent failure modes:

| Scenario | BEFORE | AFTER |
|---|---|---|
| `Get-ADDomain` emits a non-terminating error | `redirusr -> 'OU=Tier 2 End-User Accounts,'` | throws: *Failed to read the current Active Directory domain: …* |
| `Get-ADDomain` succeeds with a blank `DistinguishedName` | `redirusr -> 'OU=Tier 2 End-User Accounts,'` | throws: *Get-ADDomain returned no DistinguishedName…* |

**Scenario 2 is not closed by `-ErrorAction Stop`.** A successful read that yields no
`DistinguishedName` produces the identical malformed DN, and no error-action setting can catch
it. The explicit guard is what closes it. Had I applied the BUG-019 pattern mechanically I
would have fixed one of the two paths and reported the bug as closed.

## Control design note

Wolverine proved `tests\ADStubs.ps1` makes CI **structurally incapable** of testing this class:
an empty-bodied stub returns `$null` rather than throwing, so `Get-ADDomain -ErrorAction Stop`
never throws and the fixed and broken code are indistinguishable.

The control therefore stubs the **failure mode**, not the return value — `Write-Error` emits a
non-terminating error, exactly as a real AD read failure does when the caller supplies no
`-ErrorAction`. The BEFORE text is taken from `git show HEAD:` rather than retyped, and both
versions are asserted to parse before their behaviour is believed.

## Verification

- Parse errors: 0 on PS 7 **and** on real PS 5.1 (5.1.26100.9278)
- Non-ASCII byte count still **0**, so the file continues to need no UTF-8 BOM (BUG-033)
- Unit **1573/1573/0**, Integration **318/318/0**, both by path
