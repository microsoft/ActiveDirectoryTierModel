# SKILL: PS 7.6.5 Stream Classification in `*>&1` Pipelines with Strict Mode

**Created:** 2026-09-03  
**Author:** Beast (Dr. Hank McCoy)  
**Verified:** Empirically on pwsh 7.6.5 during debug-switch POC

---

## Problem

Two PowerShell 7.6.5 bugs interact catastrophically when classifying objects from a merged `*>&1` pipeline inside a function with `Set-StrictMode -Version Latest`.

### Bug 1: `4>&1` does not capture the debug stream

In PS 7.6.5, `SomeFunction 4>&1` produces no output from module-scope `Write-Debug` calls. The debug stream is simply not redirected. This is specific to PS 7.6.5; the behavior may differ on other PS 7 versions.

```powershell
# BROKEN in PS 7.6.5 — captures nothing from Write-Debug:
$dbgItems = @(SomeModuleFunction 4>&1 | Where-Object { $_ -is [DebugRecord] })
# $dbgItems.Count is always 0 even with $global:DebugPreference = 'Continue'

# WORKING:
$dbgItems = @(SomeModuleFunction *>&1 | Where-Object { $_ -is [System.Management.Automation.DebugRecord] })
```

### Bug 2: `switch ($_.GetType().Name)` fails inside `*>&1` pipeline with `Set-StrictMode`

Inside a `*>&1 | ForEach-Object { }` block, `switch ($_.GetType().Name)` with `Set-StrictMode -Version Latest` throws a terminating "The property 'X' cannot be found on this object" error. This error propagates out of the enclosing function **before** `return`, causing the function to return `$null` silently.

Root cause: The `switch` expression accesses `.GetType().Name` successfully, but the case bodies contain `.Message` or other property accesses that strict mode treats as invalid in this particular execution context. The exact trigger is PS 7.6.5-specific strict-mode interaction with the merged stream pipeline.

---

## Solution

Use `-is` type tests instead of `switch ($_.GetType().Name)`:

```powershell
# BROKEN — strict mode kills this inside *>&1:
SomeFunction *>&1 | ForEach-Object {
    switch ($_.GetType().Name) {
        'DebugRecord'      { $dbg.Add($_.Message) }       # may crash
        'ErrorRecord'      { $err.Add($_.Exception.Message) }
        'InformationRecord'{ $info++ }
    }
}

# WORKING — use -is type tests throughout:
SomeFunction *>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $err.Add($_.Exception.Message)
    } elseif ($_ -is [System.Management.Automation.DebugRecord]) {
        $dbg.Add($_.Message)
    } elseif ($_ -is [System.Management.Automation.VerboseRecord]) {
        $verb.Add($_.Message)
    } elseif ($_ -is [System.Management.Automation.InformationRecord]) {
        $info++
        # HostInformationMessage (from Write-Host) safe to access with -is guard:
        $raw = $_.MessageData
        if ($raw -is [System.Management.Automation.HostInformationMessage]) {
            Write-Host $raw.Message -ForegroundColor $raw.ForegroundColor
        }
    }
    # Discard Write-Output / PSCustomObject (stream 1) — handled separately
}
```

---

## Complete Working Pattern

For capturing all streams from a function call, measuring counts, and re-echoing console output:

```powershell
function Measure-Streams {
    param([scriptblock]$ScriptBlock)
    
    $errMsgs  = [System.Collections.Generic.List[string]]::new()
    $dbgMsgs  = [System.Collections.Generic.List[string]]::new()
    $verbMsgs = [System.Collections.Generic.List[string]]::new()
    $infoCount = 0

    & $ScriptBlock *>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $errMsgs.Add($_.Exception.Message)
        } elseif ($_ -is [System.Management.Automation.DebugRecord]) {
            $dbgMsgs.Add($_.Message)
        } elseif ($_ -is [System.Management.Automation.VerboseRecord]) {
            $verbMsgs.Add($_.Message)
        } elseif ($_ -is [System.Management.Automation.InformationRecord]) {
            $infoCount++
            $raw = $_.MessageData
            if ($raw -is [System.Management.Automation.HostInformationMessage]) {
                $fg = $raw.ForegroundColor
                if ($fg -and $fg -ne [System.ConsoleColor]::Gray) {
                    Write-Host $raw.Message -ForegroundColor $fg
                } else {
                    Write-Host $raw.Message
                }
            }
        }
    }

    return [PSCustomObject]@{
        ErrorCount   = $errMsgs.Count
        ErrorSamples = $errMsgs.ToArray()
        DebugCount   = $dbgMsgs.Count
        DebugSamples = $dbgMsgs.ToArray()
        VerboseCount = $verbMsgs.Count
        InfoCount    = $infoCount
    }
}
```

---

## Rules

1. Always use `*>&1` (never `4>&1`) to capture debug stream output in PS 7.6.5.
2. Always use `-is [TypeName]` to classify pipeline objects, never `switch ($_.GetType().Name)`.
3. Do not wrap the `*>&1 | ForEach-Object { }` pipeline in an outer `try/catch`. Any terminating error from inside `ForEach-Object` that escapes (even with a catch inside) will abort the function. Keep the per-object handlers defensive instead.
4. For `InformationRecord.MessageData`, use `-is [HostInformationMessage]` before accessing `.Message`. This type-checks before property access, safe with strict mode.

---

## Version Scope

Verified on **PowerShell 7.6.5** only. Behavior of `4>&1` and `switch`-in-pipeline may differ on other PS 7.x versions. The `-is` pattern is universally safe.
