# SKILL: PowerShell Debug Switch Pattern for Long-Running Scripts

## Problem

The automatic `-Debug` common parameter (from `[CmdletBinding()]`) sets `$DebugPreference = 'Inquire'`, which causes PowerShell to **interactively prompt the user** on every `Write-Debug` call. For long-running scripts (deployment, audit, migration), this is completely unusable.

## Solution Pattern

Use a **custom `-EnableDebug` switch** instead of the common `-Debug`. Write debug output directly to a file via a private `Write-DebugLog` helper. Never touch `$DebugPreference`.

### Template

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    # ... other params ...
    [switch]$EnableDebug
)

$script:DebugFilePath = $null

function Write-DebugLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [hashtable]$Data
    )
    if (-not $script:DebugFilePath) { return }

    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "$ts $Message"
    if ($Data -and $Data.Count -gt 0) {
        $pairs = foreach ($k in ($Data.Keys | Sort-Object)) { "$k=$($Data[$k])" }
        $line += " | $($pairs -join '; ')"
    }
    Add-Content -Path $script:DebugFilePath -Value $line -Encoding UTF8 -WhatIf:$false
}

function Initialize-Debug {
    if (-not $EnableDebug) { return }

    $debugDir = Join-Path $PSScriptRoot 'Debug'
    if (-not (Test-Path $debugDir)) {
        New-Item -Path $debugDir -ItemType Directory -Force -WhatIf:$false | Out-Null
    }

    $ts       = Get-Date -Format 'yyyyMMdd-HHmmss'
    $fileName = "ScriptName.debug.$ts.log"
    $script:DebugFilePath = Join-Path $debugDir $fileName

    Set-Content -Path $script:DebugFilePath `
        -Value "# Debug log Created=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
        -Encoding UTF8 -WhatIf:$false

    Write-Host "Debug logging: $script:DebugFilePath" -ForegroundColor DarkGray
}
```

### Usage in script body

```powershell
Initialize-Debug

Write-DebugLog -Message "Starting OU phase" -Data @{ OuCount = $ous.Count; DC = $PreferredDc }

# ... do work ...

Write-DebugLog -Message "OU created" -Data @{ DN = $dn; Elapsed = $sw.ElapsedMilliseconds }
```

## Key Rules

1. **Never use `-Debug` common parameter** for long-running interactive scripts — it sets `Inquire` mode.
2. **`-WhatIf:$false`** is mandatory on all file I/O in the debug helper (otherwise `-WhatIf` prevents the debug log from being written).
3. **Log file lives beside the script** (`$PSScriptRoot\Debug\`) — not in `%ProgramData%` or CWD.
4. **Fail-fast** if the log file cannot be created (fail before any AD changes).
5. **Retention** is only needed for scheduled (non-interactive) scripts. One-shot interactive scripts (Deploy, Audit) can skip retention logic.
6. **No `$DebugPreference` manipulation** — the file is written unconditionally when `$script:DebugFilePath` is set.

## Preference Variable Note

`$DebugPreference = 'Continue'` set in a script scope DOES flow into module function calls in PowerShell 7 (preference variables are inherited by child scopes including module calls). However, the default `-Debug` common parameter sets `'Inquire'` not `'Continue'`, which is why this custom pattern is preferable.

## Reference Implementation

`optional/Update-TierModelMembership.ps1` — full production implementation with 7-day retention, count and size caps. See `Write-DebugLog` (line 237), `Initialize-Debug` (line 286), and `Initialize-Logging` (line 263).
