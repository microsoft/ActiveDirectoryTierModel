# SKILL: Debug Capability Regression Surface Checklist

**Category:** Pester / PowerShell testing  
**When to use:** Any time a proposal adds `-Debug`, `[CmdletBinding()]`, or a new debug/logging channel to scripts or module functions.

---

## Checklist

### 1. CmdletBinding already present?
Before any work, check:
```powershell
Select-String -Path "your-script.ps1" -Pattern "CmdletBinding"
Get-ChildItem modules\YourModule\public\*.ps1 | ForEach-Object {
    [PSCustomObject]@{ File = $_.Name; HasCmdletBinding = (Get-Content $_ -Raw) -match '\[CmdletBinding' }
} | Group-Object HasCmdletBinding
```
If already present, the `-Debug` common parameter is already exposed. Proposal may be a no-op.

### 2. ModuleManifest count assertion
Check for exact-count assertions on exported functions:
```powershell
Select-String -Path "tests\Unit.ModuleManifest.Tests.ps1" -Pattern "Should -Be.*ActualFunctions|DeclaredFunctions.*Should -Be"
```
**Rule:** Any new `.ps1` in `public/` must be added to `FunctionsToExport` in the manifest, or this assertion breaks.

### 3. Code coverage threshold
Check CI for a coverage percentage gate:
```powershell
Select-String -Path ".github\workflows\ci.yml" -Pattern "coverageThreshold|coverage.*80|80.*coverage"
```
New untested public functions grow the denominator without growing the numerator. Calculate the delta before merging.

### 4. ADStubs CmdletBinding gap
```powershell
Select-String -Path "tests\helpers\ADStubs.ps1" -Pattern "CmdletBinding"
```
If stubs lack `[CmdletBinding()]`, they cannot accept `-Debug`, `-Verbose`, or other common parameters. Implementation must NOT forward `-Debug` to AD/GPO cmdlets via `$PSBoundParameters` splat or explicit forwarding.

### 5. $DebugPreference = 'Inquire' hazard
- **PowerShell 5.1:** `-Debug` switch → `$DebugPreference = 'Inquire'` → every `Write-Debug` prompts interactively.
- **PowerShell 7.x:** `-Debug` switch → `$DebugPreference = 'Continue'` → outputs to console, no prompt.
- Check what PS version CI uses. GitHub Actions `shell: pwsh` = PS7 → safe in CI.
- Reference pattern to avoid the hazard entirely: use a custom `-EnableDebug` switch + dedicated file log (no `Write-Debug`), as in `optional/Update-TierModelMembership.ps1`.

### 6. Logging test format assertions
Check for exact regex assertions on log message format:
```powershell
Select-String -Path "tests\Unit.Logging.Tests.ps1" -Pattern "Should.*-Match|match.*\^"
```
Adding a debug file channel doesn't affect these if they use explicit `-LogPath`. Only at risk if the new code changes the console message format or file-write path.

### 7. ParameterFilter with PSBoundParameters
```powershell
Select-String -Path "tests\*.Tests.ps1" -Pattern "PSBoundParameters" | Select-Object Filename, LineNumber, Line
```
Verify none of the filters check for common parameter presence (`Debug`, `Verbose`, `WhatIf`). Only domain-specific parameter checks are safe.

---

## Pre/Post Validation Template
```powershell
# BEFORE: capture baseline
cd tests; .\Invoke-AllTests.ps1 -TestType Unit
# Record TotalCount, PassedCount

# AFTER: compare
cd tests; .\Invoke-AllTests.ps1 -TestType Unit
Invoke-Pester -Path tests\Unit.ModuleManifest.Tests.ps1 -Output Detailed
```
