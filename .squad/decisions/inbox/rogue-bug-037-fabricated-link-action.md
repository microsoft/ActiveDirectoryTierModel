# BUG-037 — `Get-TierModelGpoFd` fabricates a `Risk = High` action from a failed read

**Author:** Rogue (Core Developer)
**Date:** 2026-09-05
**File:** `modules\TierModel\public\Get-TierModelGpoFd.ps1`
**Status:** Implemented, verified, uncommitted — **1 Unit test now fails and must be updated**

## Problem

```powershell
} catch {
    # If we can't check built-in container links, assume linking is needed
    $actions += [PSCustomObject]@{ Action = 'LinkGPO'; ...; Risk = 'High' }
}
```

A failed link check became a fabricated `Risk = High` planned change against a built-in /
Tier 0 container. Every other silent catch in this codebase *loses* information; this one
*invents* it, and the operator saw a legitimate-looking plan entry with nothing to indicate it
rested on a read that failed.

## Decision: an unreadable link state is an error, not an assumed action

I agree with the reviewer's instinct, and the "assume linking" behaviour is **not** load-bearing:

- The `Get-GPInheritance` read above is deliberately `-ErrorAction SilentlyContinue` (documented
  BUG-019 note). The normal *"GPO is not linked"* case therefore arrives as an **empty result**,
  never as an exception, and is handled by the `if (-not $isLinked)` branch immediately above —
  **which is untouched and still plans the link.**
- So every exception reaching this catch is a genuine read failure, and nothing depends on the
  catch to plan legitimate links.

Asymmetry of consequences decides the rest: an unplanned link is recoverable on the next run;
an **unrequested** link applied to a built-in container is a live GPO change nobody asked for.
Plan nothing, say so loudly.

## Implementation note — a near-miss worth recording

My first version appended to `$planErrors`, matching the sibling catch at L326. **That would
have been a silent no-op.** The AST shows this catch lives inside the *nested* helper
`Get-GpoActionsForConfig` (L52–249), while `$planErrors = @()` is initialised in the **outer**
function afterwards. In PowerShell, `+=` against a parent-scope variable reads the parent and
writes a **new local**, so the error would have been discarded — a fix that silently does
nothing, in a release about silent failures.

The file already documents the correct pattern for this exact constraint, at L106: *"This helper
is a nested function and cannot append to the caller's `$planErrors`, so the failure is logged
as a real error and surfaced as a console warning."* The fix now follows it —
`Write-TierModelLog -Level Error` plus `Write-Warning` — matching the rename-search catch
directly above.

## ⚠️ One Unit test fails, and it encodes the defect

```
Unit.GpoOperations.Tests.ps1:2139
Get-TierModelGpoFd – extended coverage
  → "Adds LinkGPO fallback when Get-GPInheritance throws for domain root"

    Mock Get-GPInheritance -ModuleName TierModel { throw "Access denied" }
    @($result.Actions | Where-Object { $_.Action -eq 'LinkGPO' }).Count | Should -BeGreaterOrEqual 1
```

The test mocks the read as throwing and asserts a `LinkGPO` action **is** produced. It asserts
the fabricated action — the bug itself — and its name calls it a "fallback".

**I have not touched it**, per the standing constraint. Reporting rather than absorbing, and I
have not weakened the fix to keep the baseline green.

**Suggested replacement for Wolverine (Group 15):** same mocks; assert
`@($result.Actions | Where-Object { $_.Action -eq 'LinkGPO' }).Count | Should -Be 0`, and assert
the warning is emitted, so the test discriminates "planned nothing and said so" from "planned
nothing silently" — otherwise it passes against a plain `catch {}` and proves nothing.

## Verification

Parse 0. Unit **1573 total, 1572 passed, 1 failed** — the single named test above.
Integration **318/318/0**, unaffected.
