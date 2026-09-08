# Skill: Comparing PowerShell Debug/Stream Output Across Invocation Modes

**Domain:** PowerShell diagnostics, module instrumentation, evidence harnesses
**Discovered:** 2026-09-03 (Beast, TierModel `-EnableDebug` lab validation)

## Problem

You need to prove that two ways of enabling diagnostic output produce the *same* result —
for example `$global:DebugPreference = 'Continue'` versus forwarding the native `-Debug`
common parameter to module cmdlets. A naive harness will report differences that are
artifacts of the harness, not of the modes, and you will chase ghosts.

Three distinct traps, each of which produced a false negative in practice.

## Trap 1 — Module-level caches leak between modes in one process

Modules routinely memoise expensive lookups in script scope:

```powershell
if (-not $script:CachedDomainDn) {
    $script:CachedDomainDn = (Get-ADDomain -Server $Dc).DistinguishedName
    Write-TierModelLog -Level Debug -Message "Domain DN resolved and cached" ...
}
```

Run Mode B then Mode C in the same process and Mode B warms the cache. Mode C never takes the
branch, never emits the record, and you get 46 vs 45 records and a bogus "the modes differ"
conclusion.

**Fix: run every mode in its own fresh process.** Emit results as JSON and compare externally.

```powershell
foreach ($m in 'B','C') {
    & $pwsh -NoProfile -File .\Measure-DebugMode.ps1 -Mode $m -OutJson "out-$m.json"
}
```

`Import-Module -Force` is **not** sufficient — assembly and runspace state can persist.

## Trap 2 — Volatile content inside the message text

Structured log messages embed timestamps, correlation IDs and durations. Normalise before
comparing:

```powershell
function Get-NormalizedText {
    param([string]$Text)
    $t = $Text -replace '\[\d{4}-\d{2}-\d{2}T[\d:.]+Z\]', '[TS]'
    $t = $t -replace '\[CID: [0-9a-fA-F]+\]', '[CID]'
    $t = $t -replace '\b\d+(\.\d+)?\s?ms\b', 'Nms'
    return $t.Trim()
}
```

## Trap 3 — Hashtable key order is not stable between processes

This is the subtle one. A logger that renders a `-Data` hashtable into `key=value, key=value`
emits keys in **hash-bucket order**, which varies between processes. The same record appears as:

```
... | ConfigProperties=aclDelegations, ..., HasVersionProperty=True, VersionValue=1.0.0 [CID]
... | HasVersionProperty=True, ConfigProperties=aclDelegations, ..., VersionValue=1.0.0 [CID]
```

Identical keys, identical values, different sequence. String comparison says "different".

**Fix: canonicalise by sorting the `key=value` tokens within the data section.** Split only on
commas that precede an identifier followed by `=`, so values containing commas survive intact:

```powershell
function Canon([string]$t) {
    if ($t -match '^(?<h>.*?\|\s*)(?<d>.*?)(?<tail>\s*\[CID\])$') {
        $pairs = ($Matches.d -split ',\s*(?=[A-Za-z]\w*=)') | Sort-Object
        return $Matches.h + ($pairs -join ', ') + $Matches.tail
    }
    return $t
}
```

Applying normalisation plus canonicalisation took a 31-line diff to **0 differences across 46
records**, converting a false negative into a clean, defensible proof.

## Capturing the debug stream reliably (PowerShell 7.x)

`4>&1` does **not** capture debug records emitted from module scope. Use a merged redirect and
type-test:

```powershell
$mixed = Invoke-Thing *>&1
$debugTexts = foreach ($item in $mixed) {
    if ($item -is [System.Management.Automation.DebugRecord]) { [string]$item.Message }
}
```

Use `-is` type tests, **not** `switch ($_.GetType().Name)` — under
`Set-StrictMode -Version Latest` the latter throws inside a `*>&1` pipeline and silently returns
`$null` from the containing function.

To return a real object alongside the captured streams, tag it and pick it out:

```powershell
[PSCustomObject]@{ IsPlanCarrier = $true; Plan = $p }   # emitted last
# caller:
elseif ($item -is [PSCustomObject] -and $item.PSObject.Properties['IsPlanCarrier']) { ... }
```

## Does `-Debug` prompt? Probe, do not assume

`-Debug` sets `$DebugPreference = 'Inquire'`, which can block a non-interactive run forever.
Before building the harness, spend one cheap call proving the behaviour in *your* host:

```powershell
function Probe { [CmdletBinding()] param() Write-Debug "probe"; "done" }
$r = Probe -Debug *>&1
($r | ForEach-Object { $_.GetType().Name }) -join ','
```

Over PowerShell Direct / remoting this returned `DebugRecord,String` with no prompt. Establish
that fact first; otherwise a hang looks like a failed test.

## Two rules that are never optional

**Always restore preference variables in `finally`**, including on exception:

```powershell
$saved = $global:DebugPreference
try   { $global:DebugPreference = 'Continue'; ... }
finally { $global:DebugPreference = $saved }
```

**Always pass `-WhatIf:$false` on debug file writes.** If the containing script is
`[CmdletBinding(SupportsShouldProcess)]`, a `-WhatIf` run silently suppresses `Add-Content`,
`New-Item` and `Set-Content`, and your diagnostic file is empty exactly when someone is trying
to diagnose something.

```powershell
Add-Content -Path $DebugLogFile -Value $lines -Encoding UTF8 -WhatIf:$false
```

## Checklist

- [ ] Probe whether `-Debug` prompts in the target host before building anything
- [ ] Each mode in its own fresh process
- [ ] Timestamps, correlation IDs, durations normalised
- [ ] Hashtable `key=value` tokens sorted before comparison
- [ ] `*>&1` plus `-is [DebugRecord]`, never `4>&1`
- [ ] `-is` type tests, never `switch` on `GetType().Name` under StrictMode
- [ ] Preference variables restored in `finally`
- [ ] `-WhatIf:$false` on every diagnostic file write
- [ ] Compare counts **and** canonical text; report both

## Corollary: absence of output is itself a finding

Once the harness is trustworthy, "0 debug records mention the failure" becomes hard evidence
rather than a suspected harness bug. That is precisely how it was established that instrumenting
a debug switch alone was insufficient, and that the silent code path itself had to be
instrumented. Always measure the negative case explicitly and report the zero.
