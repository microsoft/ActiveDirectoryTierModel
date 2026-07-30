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
    
    # Check Pester version. Require a supported 5.x release; Pester 6.x has breaking
    # changes (new mock engine / Should-* assertions) that are not yet supported. Pester
    # versions install side-by-side, so select and explicitly import the highest 5.x even
    # when a newer major is also installed (PowerShell would otherwise auto-load the highest).
    $allPester = @(Get-Module Pester -ListAvailable | Where-Object { $null -ne $_ })
    if (-not $allPester) {
        Write-Error "Pester module not found. Install with: Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force. For help, see: https://github.com/pester/Pester"
        return
    }
    $supportedPester = $allPester | Where-Object { $_.Version.Major -eq 5 } | Sort-Object Version -Descending | Select-Object -First 1
    $highestPester = ($allPester | Sort-Object Version -Descending | Select-Object -First 1).Version
    if (-not $supportedPester) {
        Write-Error "No supported Pester 5.x release found (highest installed: $highestPester). Pester $($highestPester.Major).x has breaking changes that are not yet supported. Install 5.x side-by-side: Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force"
        return
    }

    # Explicitly load the supported 5.x line so Invoke-Pester does not auto-load a newer major.
    Remove-Module Pester -Force -ErrorAction SilentlyContinue
    Import-Module Pester -RequiredVersion $supportedPester.Version -Force
    $pesterModule = $supportedPester

    Write-Host "📋 Pester Version: $($pesterModule.Version)" -ForegroundColor Green

    if ($highestPester.Major -ne 5) {
        Write-Warning "Pester $highestPester is installed side-by-side; $($highestPester.Major).x has untested breaking changes. Using supported $($pesterModule.Version)."
    }
    
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