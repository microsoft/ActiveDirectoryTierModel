---
name: "pester-mandatory-param-testing"
description: "Test mandatory parameters via parameter metadata inspection, not by invoking with missing args"
domain: "testing, Pester"
confidence: "high"
source: "earned"
tools:
  - name: "Pester"
    description: "PowerShell testing framework"
    when: "Writing unit tests that need to verify mandatory parameters"
  - name: "PowerShell Get-Command"
    description: "Reflection of cmdlet metadata"
    when: "Inspecting parameter attributes at test time"
---

## Context

When testing that a cmdlet parameter is mandatory, there is an anti-pattern that works in CI/non-interactive environments but breaks in interactive consoles: invoking the cmdlet with the mandatory parameter missing and expecting `Should -Throw`.

In non-interactive hosts (CI pipelines, `-NonInteractive` mode), PowerShell throws a ParameterBindingException. However, in interactive consoles, PowerShell prompts the user for the missing value ("Supply values for the following parameters: ParameterName:") and blocks indefinitely waiting for input. This hangs test automation.

## Patterns

**ANTI-PATTERN (DO NOT USE):**
```powershell
It "Mandatory parameters enforced: missing -Config throws" {
    { Get-SomeCommand -OtherParam "value" } | Should -Throw
}
```
✗ Works in CI; hangs in interactive console

**RECOMMENDED PATTERN:**
```powershell
It "Config parameter is mandatory" {
    $attr = (Get-Command Get-SomeCommand).Parameters['Config'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    ($attr.Mandatory -contains $true) | Should -BeTrue
}
```
✓ Works in both CI and interactive consoles; no cmdlet invocation risk; tests the declaration directly

**VARIANT (More Explicit):**
```powershell
It "Config parameter has Mandatory attribute" {
    $param = (Get-Command Get-SomeCommand).Parameters['Config']
    $param | Should -Not -BeNullOrEmpty
    $param.Attributes.ParameterAttribute.Mandatory | Should -Contain $true
}
```
✓ Equivalent; slightly more defensive guard

## Examples

### Real-World Example: Windows LAPS Cmdlet Tests

File: `tests/Unit.WinLapsAclOperations.Tests.ps1`

**Before (Problematic):**
```powershell
It "Mandatory parameters enforced: missing -Config throws" {
    { Get-TierModelWinLapsAcl -DomainController $script:TestDC } | Should -Throw
}
It "Mandatory parameters enforced: missing -DomainController throws" {
    { Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 } | Should -Throw
}
```

**After (Fixed):**
```powershell
It "Config parameter is mandatory" {
    $attr = (Get-Command Get-TierModelWinLapsAcl).Parameters['Config'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    ($attr.Mandatory -contains $true) | Should -BeTrue
}
It "DomainController parameter is mandatory" {
    $attr = (Get-Command Get-TierModelWinLapsAcl).Parameters['DomainController'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    ($attr.Mandatory -contains $true) | Should -BeTrue
}
```

**Result:** Tests still verify the parameter is `[Parameter(Mandatory)]`, but now run cleanly in both CI and interactive consoles without hanging.

## Anti-Patterns

1. **Invoking cmdlet with missing mandatory params + Should -Throw** → Use metadata inspection instead
2. **Assuming CI behavior (throw) applies to interactive hosts** → Always test both environments or use host-agnostic patterns
3. **Mocking Get-Command to fake parameter metadata** → Get-Command is stable; test it directly

## Why This Matters

- **Test Automation:** Hanging tests block CI/CD pipelines and interactive development workflows
- **Host Agnosticism:** Tests should pass the same way regardless of PowerShell host (console, ISE, CI runner, etc.)
- **Clarity:** Metadata inspection is explicit — the test directly verifies the intended declaration (`Mandatory=$true`) without ambiguous invocation semantics
- **Defensibility:** No reliance on exception handling behavior, which can change across PowerShell versions or host contexts

## Scope

This pattern applies to **all mandatory parameter tests** in Pester-based test suites. It is particularly important in repos with interactive development workflows (e.g., Hyper-V labs, manual test runs) where tests may run in interactive consoles alongside CI execution.
