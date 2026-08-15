#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs all TierModel tests with comprehensive reporting
    
.DESCRIPTION
    This script runs all Pester tests for the TierModel project including:
    - Unit tests (Unit.*.Tests.ps1) - Test individual components in isolation
    - Integration tests (Integration.*.Tests.ps1) - Test component interactions
    - Main test suite (TierModel\tests\)
    - Module-specific tests (Modules\TierModel\tests\) if present
    
    Test files follow the naming convention:
    - Unit.<Component>.Tests.ps1 (e.g., Unit.Prerequisites.Tests.ps1)
    - Integration.<Feature>.Tests.ps1 (e.g., Integration.Convergence.Tests.ps1)
    
.PARAMETER TestType
    Filter tests by type: 'All' (default), 'Unit', or 'Integration'
    
.PARAMETER Detailed
    Show detailed test output including individual test results
    
.PARAMETER FailedOnly
    Show only failed tests (suppresses all passed/skipped test output)
    
.PARAMETER PassThru
    Return test result objects for further processing
    
.EXAMPLE
    .\Invoke-AllTests.ps1
    Run all tests (unit + integration) with summary output
    
.EXAMPLE
    .\Invoke-AllTests.ps1 -TestType Unit
    Run only unit tests with summary output
    
.EXAMPLE
    .\Invoke-AllTests.ps1 -TestType Integration
    Run only integration tests with summary output
    
.EXAMPLE
    .\Invoke-AllTests.ps1 -Detailed
    Run all tests with detailed output showing individual test results
    
.EXAMPLE
    .\Invoke-AllTests.ps1 -TestType Unit -Detailed
    Run unit tests with detailed output
    
.EXAMPLE
    .\Invoke-AllTests.ps1 -TestType Integration -Detailed
    Run integration tests with detailed output
    
.EXAMPLE
    .\Invoke-AllTests.ps1 -FailedOnly
    Run all tests but only display failed tests (useful for large test suites)
    
.EXAMPLE
    $results = .\Invoke-AllTests.ps1 -PassThru
    Run all tests and capture results in a variable for further processing
    
.EXAMPLE
    $results = .\Invoke-AllTests.ps1 -TestType Unit -PassThru
    if ($results.Success) { Write-Host "All unit tests passed!" }
    Run unit tests and check results programmatically
    
.EXAMPLE
    .\Invoke-AllTests.ps1 -TestType Unit -Detailed -PassThru | Out-File TestResults.txt
    Run unit tests with detailed output and save results to file
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('All', 'Unit', 'Integration')]
    [string]$TestType = 'All',
    
    [switch]$Detailed,
    
    [switch]$FailedOnly,
    
    [switch]$PassThru
)

# Ensure we're in the correct directory (TierModelv2 subdirectory)
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

Push-Location $scriptRoot

try {
    Write-Host "🧪 TierModel Test Runner" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host ""

    # ===================================================================
    # PESTER 6.x CLR ASSEMBLY EVICTION — MUST HAPPEN BEFORE ANYTHING ELSE
    # ===================================================================
    # Problem (pwsh 7.6.5 + side-by-side Pester 6.0.0): Once a .NET assembly
    # is loaded into the process AppDomain, Import-Module -Force cannot evict
    # it. If the caller's terminal session ever imported Pester 6.x (explicitly
    # or via auto-load), the CLR has 6.x locked in. Attempting to then load
    # Pester 5.x throws "Assembly with same name is already loaded."
    #
    # Solution: Detect the v6 CLR assembly and re-spawn this script in a
    # clean child process where no Pester assembly is pre-loaded. The child
    # runs with -NoProfile to prevent profile scripts from re-loading v6.
    # ===================================================================
    $v6Assembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Pester' -and $_.GetName().Version.Major -ge 6 } |
        Select-Object -First 1

    if ($v6Assembly) {
        Write-Warning "Pester $($v6Assembly.GetName().Version) CLR assembly is already loaded in this process — it cannot be evicted. Re-spawning Invoke-AllTests.ps1 in a clean child process to guarantee Pester 5.x binds."
        $myScript = $MyInvocation.MyCommand.Path
        $respawnArgs = @('-NoProfile', '-NonInteractive', '-File', $myScript)
        if ($TestType -ne 'All')  { $respawnArgs += '-TestType', $TestType }
        if ($Detailed)            { $respawnArgs += '-Detailed' }
        if ($FailedOnly)          { $respawnArgs += '-FailedOnly' }
        if ($PassThru)            { $respawnArgs += '-PassThru' }
        & pwsh @respawnArgs
        exit $LASTEXITCODE
    }

    # Clean up any temp directories from previous test runs
    $tempDir = Join-Path (Split-Path $scriptRoot -Parent) "Temp"
    if (Test-Path $tempDir) {
        Write-Host "🧹 Cleaning up temp directory from previous test run..." -ForegroundColor Yellow
        try {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "   Temp directory cleaned" -ForegroundColor Green
        } catch {
            Write-Warning "Could not clean temp directory: $_"
        }
    }
    Write-Host ""

    # ===================================================================
    # PESTER VERSION POLICY — DO NOT CHANGE WITHOUT TESTING THE FULL SUITE
    # ===================================================================
    # Joel Platek directive (2026-08-15): Invoke-AllTests.ps1 MUST execute
    # under a Pester 5.x.x release and MUST NEVER bind to Pester 6.x, even
    # when v6 is installed side-by-side and even when PowerShell 7.6.5+
    # auto-loading would otherwise pull in the highest installed version.
    #
    # Why: Pester 6.x has breaking changes — overhauled mock engine, removed
    # Assert-MockCalled, redesigned Should-* assertion syntax. Our 1,500+
    # test cases are authored for the Pester 5.x API and WILL NOT be updated
    # to chase 6.x breaking changes at this time. Pester 5.9.0 is fully
    # supported and produces 0 failures on the current suite.
    #
    # KNOWN-GOOD: 5.9.0 — validated 2026-08-15, 1533/1533 pass, 0 failures.
    #
    # STRATEGY (defence in depth against pwsh 7.6.5 autoloading v6):
    #   1. Disable module auto-loading before ANY Pester discovery.
    #   2. Remove ALL currently-loaded Pester modules (any version, inc. v6).
    #   3. Hard-import exactly the known-good version.
    #   4. Hard-assert Major -eq 5 after import; abort if wrong version bound.
    #   5. Restore auto-loading preference after import (tests themselves may
    #      need auto-loading for other modules, e.g. ActiveDirectory).
    # ===================================================================
    $KnownGoodPesterVersion = '5.9.0'

    # Step 1 — disable auto-loading so Get-Module -ListAvailable and
    # Import-Module cannot be short-circuited by pwsh picking the highest.
    $savedAutoLoad = $PSModuleAutoLoadingPreference
    $PSModuleAutoLoadingPreference = 'None'

    try {
        # Step 2 — purge any already-loaded Pester (any version, inc. v6).
        Get-Module Pester | Remove-Module -Force -ErrorAction SilentlyContinue

        # Step 3 — discover what is installed.
        # PSModuleAutoLoadingPreference = None means we must pass -ListAvailable explicitly.
        $allPester = @(Get-Module Pester -ListAvailable | Where-Object { $null -ne $_ })
        if (-not $allPester) {
            Write-Error "Pester not found. Install: Install-Module -Name Pester -RequiredVersion $KnownGoodPesterVersion -Force"
            return
        }

        $highestPester = ($allPester | Sort-Object Version -Descending | Select-Object -First 1).Version

        # Warn if Pester 6.x (or any non-5.x) is present — it CANNOT run this suite.
        if ($highestPester.Major -ne 5) {
            Write-Warning "Pester $highestPester is installed side-by-side. Pester $($highestPester.Major).x has breaking changes incompatible with this test suite and WILL NOT be used. Pinning to $KnownGoodPesterVersion."
        }

        # Find the pinned known-good version.
        $pinnedPester = $allPester | Where-Object { $_.Version.ToString() -eq $KnownGoodPesterVersion } | Select-Object -First 1

        if ($pinnedPester) {
            $selectedPester = $pinnedPester
        } else {
            # Fallback: highest available 5.x. Warn loudly — suite may not be fully green.
            $selectedPester = $allPester | Where-Object { $_.Version.Major -eq 5 } | Sort-Object Version -Descending | Select-Object -First 1
            if (-not $selectedPester) {
                Write-Error "No Pester 5.x installed. Install the known-good version: Install-Module -Name Pester -RequiredVersion $KnownGoodPesterVersion -Force"
                return
            }
            Write-Warning "Pester $KnownGoodPesterVersion (known-good) is NOT installed. Falling back to $($selectedPester.Version) — suite may not be fully green. To restore 100% pass rate: Install-Module -Name Pester -RequiredVersion $KnownGoodPesterVersion -Force"
        }

        # Step 3b — import the selected 5.x explicitly.
        # $PSModuleAutoLoadingPreference = 'None' suppresses IMPLICIT loading (command-triggered);
        # explicit Import-Module calls are unaffected by the preference, so -RequiredVersion
        # is safe here and is the most reliable way to pin the exact version.
        Import-Module Pester -RequiredVersion $selectedPester.Version -Force -ErrorAction Stop

        # Step 4 — HARD ASSERT: verify the version that actually loaded.
        $loadedPester = Get-Module Pester
        if ($null -eq $loadedPester -or $loadedPester.Version.Major -ne 5) {
            $actual = if ($loadedPester) { $loadedPester.Version } else { '(none)' }
            throw "FATAL: Pester 5.x failed to bind. Loaded version: $actual. Aborting — v6.x CANNOT run this suite."
        }
        $pesterModule = $loadedPester
    } finally {
        # Step 5 — restore auto-loading so test files can import other modules normally.
        $PSModuleAutoLoadingPreference = $savedAutoLoad
    }

    Write-Host "📋 Pester Version: $($pesterModule.Version)" -ForegroundColor Green
    Write-Host "   Module path:     $($pesterModule.ModuleBase)" -ForegroundColor Gray
    # Emit the runtime-confirmed major as an extra safety signal.
    Write-Host "   Major confirmed: $($pesterModule.Version.Major) (must be 5)" -ForegroundColor $(if ($pesterModule.Version.Major -eq 5) { 'Green' } else { 'Red' })
    
    Write-Host ""
    
    # Configure test filtering based on TestType
    $testFilter = @{}
    switch ($TestType) {
        'Unit' {
            Write-Host "🔍 Test Filter: Unit tests only" -ForegroundColor Cyan
            $testFilter['Path'] = @(Get-ChildItem -Path $scriptRoot -Filter "Unit.*.Tests.ps1")
        }
        'Integration' {
            Write-Host "🔍 Test Filter: Integration tests only" -ForegroundColor Cyan
            $testFilter['Path'] = @(Get-ChildItem -Path $scriptRoot -Filter "Integration.*.Tests.ps1")
        }
        'All' {
            Write-Host "🔍 Test Filter: All tests (Unit + Integration)" -ForegroundColor Cyan
            $testFilter['Path'] = @(Get-ChildItem -Path $scriptRoot -Filter "*.Tests.ps1")
        }
    }
    
    Write-Host ""
    
    # Run tests
    Write-Host "🔬 Running TierModel Test Suite..." -ForegroundColor Yellow
    Write-Host "   Path: $scriptRoot" -ForegroundColor Gray
    Write-Host "   Files: $($testFilter['Path'].Count) test file(s)" -ForegroundColor Gray
    
    if ($testFilter['Path'].Count -eq 0) {
        Write-Warning "No test files found matching filter: $TestType"
        return
    }
    
    # Configure Pester settings
    $pesterConfig = @{
        Path = $testFilter['Path']
        PassThru = $true
    }
    
    if ($FailedOnly) {
        $pesterConfig['Output'] = 'None'
        Write-Host "   Output Mode: Failed tests only" -ForegroundColor Gray
    } elseif (-not $Detailed) {
        $pesterConfig['Output'] = 'Minimal'
    }
    
    Write-Host ""
    
    # Execute tests
    $results = Invoke-Pester @pesterConfig
    
    # Display failed tests if FailedOnly mode
    if ($FailedOnly -and $results.FailedCount -gt 0) {
        Write-Host ""
        Write-Host "❌ FAILED TESTS ($($results.FailedCount))" -ForegroundColor Red
        Write-Host "================================" -ForegroundColor Red
        
        foreach ($test in $results.Failed) {
            Write-Host ""
            Write-Host "[-] $($test.ExpandedPath)" -ForegroundColor Red
            Write-Host "    at $($test.ScriptBlockFile):$($test.ScriptBlockStartLine)" -ForegroundColor Gray
            Write-Host "    $($test.ErrorRecord.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    
    # Display results
    Write-Host "📊 TEST RESULTS SUMMARY" -ForegroundColor Green
    Write-Host "========================" -ForegroundColor Green
    Write-Host "Test Type:      $TestType" -ForegroundColor Cyan
    Write-Host "Files Tested:   $($testFilter['Path'].Count)" -ForegroundColor Cyan
    Write-Host "---" -ForegroundColor Gray
    Write-Host "Total Tests:    $($results.TotalCount)" -ForegroundColor Cyan
    Write-Host "Passed:         $($results.PassedCount)" -ForegroundColor Green
    Write-Host "Failed:         $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -eq 0) { "Green" } else { "Red" })
    Write-Host "Skipped:        $($results.SkippedCount)" -ForegroundColor Yellow
    Write-Host "---" -ForegroundColor Gray
    
    if ($results.FailedCount -eq 0) {
        Write-Host "🎉 ALL TESTS PASSED!" -ForegroundColor Green
    } else {
        Write-Host "❌ $($results.FailedCount) TEST(S) FAILED" -ForegroundColor Red
    }
    
    Write-Host ""
    
    # Return results if requested
    if ($PassThru) {
        return @{
            TestType = $TestType
            Results = $results
            TotalTests = $results.TotalCount
            TotalPassed = $results.PassedCount
            TotalFailed = $results.FailedCount
            TotalSkipped = $results.SkippedCount
            Success = ($results.FailedCount -eq 0)
        }
    }
    
    # Exit with appropriate code
    if ($results.FailedCount -gt 0) {
        exit 1
    }
}
finally {
    # Clean up temp directory after test completion
    $tempDir = Join-Path (Split-Path $scriptRoot -Parent) "Temp"
    if (Test-Path $tempDir) {
        Write-Host ""
        Write-Host "🧹 Cleaning up temp files..." -ForegroundColor Yellow
        try {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "   Temp directory cleaned successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Could not clean temp directory: $_"
        }
    }
    
    Pop-Location
}