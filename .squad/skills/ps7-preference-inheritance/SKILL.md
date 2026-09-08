# SKILL: PowerShell 7 Preference Variable Inheritance

**Created:** 2026-09-03  
**Author:** Cyclops  
**Verified:** Empirically on pwsh 7.6.5

## Summary

PowerShell 7 preference variable inheritance across module boundaries works automatically. No explicit propagation code needed.

## Key Facts (Verified Empirically)

### 1. `-Debug` Sets `Continue`, NOT `Inquire`

In PowerShell 7, passing `-Debug` to a `[CmdletBinding()]` function or script sets `$DebugPreference = 'Continue'` in that scope. This is a **breaking change from Windows PowerShell 5.1**, which set `$DebugPreference = 'Inquire'` (interactive prompt at every `Write-Debug`).

**Implication:** No need to neutralize the Inquire behavior in PS7-only code. The repo's `#requires -Version 7.0` makes this safe.

### 2. Preference Variables Inherit Across Module Boundaries

When a script sets `$DebugPreference = 'Continue'` and calls a function exported from a module, the module function **sees the caller's preference**. Tested scenarios:

- ✅ Script → module function (direct)
- ✅ Script → script function → module function (nested)
- ✅ Functions with and without `[CmdletBinding()]`
- ✅ Same behavior for `$VerbosePreference` and `$WarningPreference`

**Why:** PowerShell's dynamic scoping walks the call stack. If the module function has no local `$DebugPreference`, it inherits from the nearest scope that does.

### 3. `[CmdletBinding()]` Is Required for `-Debug` Acceptance

A function without `[CmdletBinding()]` does not accept `-Debug` as a parameter (it's a common parameter). However, it still inherits `$DebugPreference` from the caller's scope via dynamic scoping.

## Pattern: Enable Debug Logging Across a Module

```powershell
# In the orchestrator script:
[CmdletBinding()]
param(
    [switch]$EnableDebug
)

if ($EnableDebug) {
    $DebugPreference = 'Continue'  # All Write-Debug in this scope + callees will emit
}

# Call module functions normally — no -Debug splatting needed
Get-SomeModuleFunction -Param1 $value
```

## Anti-Patterns

- ❌ Splatting `-Debug:$true` at every call site (unnecessary, brittle, ~N edits for N calls)
- ❌ Creating a "preference propagation helper" (PS7 does this natively)
- ❌ Worrying about `Inquire` prompts in PS7 (only a PS 5.1 issue)
- ❌ Using `$PSCmdlet.WriteDebug()` instead of `Write-Debug` for preference inheritance (both work, but `Write-Debug` is simpler)

## Caveat

This applies to **PowerShell 7.0+** only. Windows PowerShell 5.1 has different behavior:
- `-Debug` sets `$DebugPreference = 'Inquire'` (prompts user)
- Module boundary inheritance is less reliable in some edge cases

Always check `#requires -Version 7.0` before relying on this pattern.
