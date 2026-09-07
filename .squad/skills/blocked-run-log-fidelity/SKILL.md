# Skill: Blocked-Run Log Fidelity

**Domain:** PowerShell operational scripts with structured logging
**Author:** Beast
**Established:** 2026-09-03 (`fix/gpo-silent-skip-and-false-success`)

## Problem

A script correctly refuses to proceed — it prints every error in red, applies nothing, and
stops. The console is honest. The **log file** is not: it contains only the `Info` breadcrumbs
that were emitted before the gate, records zero errors, and ends with
`"<script> completed successfully"`. Any log shipper, SIEM rule, or scheduled-task monitor
reports green on a deployment that did nothing.

This is a *worse* class of bug than a noisy failure, because it is invisible to exactly the
people watching for failures.

**Tell-tale signature:** the blocking errors are surfaced with `Write-Host` only. `Write-Host`
does not touch the error stream, the exit code, or the log file.

## Detection

For any script with both a fail-fast gate and a log file:

1. Find every path that ends the run *without applying changes because of errors*.
2. For each, ask: does the log file distinguish this from a clean no-op run?
3. Grep the error-display path for `Write-Host` with no adjacent logging call.

```powershell
# Anything matching this and NOT near a logging call is suspect
grep -n 'Write-Host.*(❌|ERROR|error|Resolve all)' script.ps1
```

## Pattern

Do **not** try to log at every display site — they are scattered and each has a different
result-object shape. Instead, find the **gate**: the single place per phase where the script
decides "errors exist, stop here". Route through one helper.

```powershell
# Script scope, declared once near the top
$script:DeploymentBlocked = $false
$script:BlockedPhases = @()

function Write-<Tool>BlockedOutcome {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [AllowEmptyCollection()][object[]]$Errors = @(),
        [AllowEmptyCollection()][object[]]$SkippedItems = @()
    )

    $script:DeploymentBlocked = $true
    if ($script:BlockedPhases -notcontains $Phase) { $script:BlockedPhases += $Phase }

    if (-not $Logging -or -not $script:LogFilePath) { return }

    # Error collections are rarely homogeneous - handle hashtable, PSCustomObject and string
    $messages = @(
        @($Errors) | ForEach-Object {
            if ($_ -is [hashtable]) { $_['Message'] }
            elseif ($_ -and $_.PSObject.Properties.Name -contains 'Message') { $_.Message }
            else { "$_" }
        } | Where-Object { $_ } | Select-Object -Unique | Sort-Object
    )

    foreach ($m in $messages) {
        Write-<Tool>Log -LogPath $script:LogFilePath -Level 'Error' -Message "$Phase dependency error: $m"
    }
    Write-<Tool>Log -LogPath $script:LogFilePath -Level 'Error' `
        -Message "$Phase deployment BLOCKED by dependency errors - no changes were applied"
}
```

And branch the closing summary:

```powershell
if ($script:DeploymentBlocked) {
    Write-Host "<Tool> script completed - DEPLOYMENT BLOCKED, no changes were applied." -ForegroundColor Red
} else {
    Write-Host "<Tool> script completed." -ForegroundColor Green
}
if ($Logging) {
    if ($script:DeploymentBlocked) {
        Write-<Tool>Log -LogPath $script:LogFilePath -Level 'Error' `
            -Message "<Tool> script completed with BLOCKED deployment" `
            -Data @{ BlockedPhases = ($script:BlockedPhases -join ', '); Outcome = 'Blocked' }
    } else {
        Write-<Tool>Log -LogPath $script:LogFilePath -Level 'Info' -Message "<Tool> script completed successfully"
    }
}
```

## Rules

0. **Before judging a subtraction, check how many action TYPES the planner emits.** If it emits
   exactly one (every `$actions +=` sets the same `Action` value), then `TotalActions -
   CreateActions` is not merely "loose" — it is a guaranteed constant zero. That is worse than a
   mixed-unit bug, because it never varies and therefore never looks suspicious in output.
   Conversely, if `Total` counts objects and the subtrahend counts *actions*, and one object can
   yield several actions, the figure is dimensionally meaningless. Only when one object yields at
   most one action of the filtered type is the subtraction actually sound — in that case say so
   and change nothing.
1. **Fix the log, not the gate.** Refusing to proceed on unmet dependencies is correct
   behaviour. Never "fix" a silent-failure report by removing the `continue` or the gate.
   Verify what the script actually does before assuming it is broken.
2. **Deduplicate, then log.** The console already deduplicates for readability; the log should
   match so the two can be reconciled. `Select-Object -Unique | Sort-Object`.
3. **Name the dependents, not just the dependency.** "Required group X does not exist" tells
   the operator nothing about which objects were dropped. See the companion rule below.
4. **Extend the closing line, do not replace it.** Existing tests commonly assert on a substring
   like `'script completed'`. `"... completed - DEPLOYMENT BLOCKED ..."` keeps them green while
   inverting the meaning for a human.
5. **Guard the helper.** `if (-not $Logging -or -not $script:LogFilePath) { return }` — the
   helper must be a no-op (except for the state flag) when logging is off.

## Companion rule: deduplicated errors destroy attribution

If a validation loop records an error only the *first* time a given dependency is seen missing,
every subsequent entity blocked by that same dependency produces **no record at all**. You
cannot recover attribution by re-querying the shared error collection afterwards.

Track the blocking condition **locally, per entity**, at the moment of the skip:

```powershell
$missingDeps = @()          # reset per entity, alongside $allDepsExist = $true
# ... in the catch: if ($missingDeps -notcontains $d) { $missingDeps += $d }

if (-not $allDepsExist) {
    $skipped += [PSCustomObject]@{
        Name   = $entityName
        Reason = "Required dependency(s) do not exist: $($missingDeps -join ', ')"
    }
    continue
}
```

Then return the `$skipped` collection from the planner and render it grouped by reason.

**Also:** look for *more than one* skip site. A per-entity `continue` is easy to spot; an
earlier *whole-section* `continue` (e.g. "target container missing, skip this entire group")
usually accounts for far more dropped objects and is easy to miss.

**Do not** push per-entity skip records into the shared error collection. With a large config
that can mean hundreds of new error entries, inflating validation-error counts and flooding the
console. Attribution should be additive and reported separately; the gate is already tripped by
the original dependency errors.

## Testing a script-internal helper with no dot-source seam

If the entry-point script has no `if ($MyInvocation.InvocationName -eq '.') { return }` guard,
extract the function with the AST rather than adding a seam just for validation:

```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
$fn  = $ast.FindAll({
    param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-ToolBlockedOutcome'
}, $true)[0]
. ([scriptblock]::Create($fn.Extent.Text))
```

The helper is then callable in isolation; set `$Logging` and `$script:LogFilePath` yourself and
assert on the resulting JSON log lines.

## Applied in

- `Deploy-TierModel.ps1` — `Write-TierModelBlockedOutcome`, `Write-TierModelSkippedGpoReport`,
  `Get-TierModelAdmxFatalError`
- `modules/TierModel/public/Get-TierModelGpo.ps1` — `SkippedGpos` / `SkippedGpoSummary`
- `modules/TierModel/public/Get-TierModelOuAcl.ps1` — real `Summary.ExistingCount`

## Two more traps

**When you relax an execution-time gate, grep for the planning-time predicate that mirrors it.**
Making a phase per-file resilient at execution while leaving the planner's
`$hasErrors = ...Errors.Count -gt 0` untouched produces a plan that contradicts the execution —
the preview says BLOCKED, the apply deploys happily. Extract the classifier into one shared
helper so the two can never drift.

**`return @(...)` from a PowerShell function does not preserve the array.** The pipeline unrolls
it: an empty result arrives as `$null`, a single item as a scalar. Under `Set-StrictMode`,
`$null.Count` throws `PropertyNotFoundException`. Re-wrap at every call site:
`$x = @(Get-Thing ...)`. Entry-point scripts are often exercised only by integration tests, so
a unit-suite pass does not prove this is safe — run both.

**Sibling `Get-X` / `Get-XFd` pairs: diff their Summary shapes.** Where a repo has "full
deployment" variants of a planner, a property present on one and missing on the other is a
reliable bug smell — and the more complete variant is usually the correct reference
implementation to copy.
