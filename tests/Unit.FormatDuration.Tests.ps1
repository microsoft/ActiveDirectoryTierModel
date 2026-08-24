#Requires -Modules Pester
# Unit tests for Format-TierModelDuration — pure string function, no AD stubs needed.
# Covers all four output tiers, floor semantics, and banker's-rounding regression guards.

Describe 'Format-TierModelDuration' -Tag 'Unit', 'FormatDuration' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'TierModel.psd1'
        Import-Module $ModulePath -Force
    }

    Context 'Sub-millisecond tier — returns <1ms for input below 1' {

        It 'zero returns <1ms' {
            Format-TierModelDuration -Milliseconds 0 | Should -Be '<1ms'
        }

        It '0.4 returns <1ms' {
            Format-TierModelDuration -Milliseconds 0.4 | Should -Be '<1ms'
        }

        It '0.999 (boundary below 1ms) returns <1ms' {
            Format-TierModelDuration -Milliseconds 0.999 | Should -Be '<1ms'
        }

        It 'negative input returns <1ms' {
            Format-TierModelDuration -Milliseconds -1 | Should -Be '<1ms'
        }

        It 'null coerces to 0.0 and returns <1ms' {
            # [Parameter(Mandatory)][double]: $null coerces to 0.0; Mandatory is satisfied by explicit pass.
            Format-TierModelDuration -Milliseconds $null | Should -Be '<1ms'
        }
    }

    Context 'Millisecond tier — returns Xms for 1ms through 999ms' {

        It '1ms returns 1ms' {
            Format-TierModelDuration -Milliseconds 1 | Should -Be '1ms'
        }

        It '1.7ms floors to 1ms (not rounded to 2ms)' {
            Format-TierModelDuration -Milliseconds 1.7 | Should -Be '1ms'
        }

        It '500ms returns 500ms' {
            Format-TierModelDuration -Milliseconds 500 | Should -Be '500ms'
        }

        It '999ms returns 999ms' {
            Format-TierModelDuration -Milliseconds 999 | Should -Be '999ms'
        }

        It '999.7ms floors to 999ms (not promoted to 1000ms)' {
            Format-TierModelDuration -Milliseconds 999.7 | Should -Be '999ms'
        }
    }

    Context 'Second tier — returns Xs for 1000ms through 59999ms' {

        It '1000ms returns 1s' {
            Format-TierModelDuration -Milliseconds 1000 | Should -Be '1s'
        }

        It '2254ms returns 2s' {
            Format-TierModelDuration -Milliseconds 2254 | Should -Be '2s'
        }

        It '2254.1343ms floors to 2s' {
            Format-TierModelDuration -Milliseconds 2254.1343 | Should -Be '2s'
        }

        It '59000ms returns 59s' {
            Format-TierModelDuration -Milliseconds 59000 | Should -Be '59s'
        }

        It '59999ms returns 59s (boundary below 60s tier)' {
            Format-TierModelDuration -Milliseconds 59999 | Should -Be '59s'
        }
    }

    Context 'Minute tier — returns Xm Ys for 60000ms and above' {

        It '60000ms returns 1m 0s' {
            Format-TierModelDuration -Milliseconds 60000 | Should -Be '1m 0s'
        }

        It '89999ms returns 1m 29s' {
            Format-TierModelDuration -Milliseconds 89999 | Should -Be '1m 29s'
        }

        It '90000ms returns 1m 30s — banker''s-rounding regression guard' {
            # [int][TimeSpan]::TotalMinutes: 90000ms = 1.5 min; [int]1.5 banker''s-rounds to 2 (even)
            # → wrong "2m 30s". Floor-based arithmetic gives the correct "1m 30s".
            Format-TierModelDuration -Milliseconds 90000 | Should -Be '1m 30s'
        }

        It '119999ms returns 1m 59s — banker''s-rounding regression guard' {
            # [int][TimeSpan]::TotalMinutes: [int]1.9999 rounds to 2, yielding wrong "2m 59s".
            Format-TierModelDuration -Milliseconds 119999 | Should -Be '1m 59s'
        }

        It '120000ms returns 2m 0s — minute boundary regression guard' {
            Format-TierModelDuration -Milliseconds 120000 | Should -Be '2m 0s'
        }

        It '140000ms returns 2m 20s' {
            Format-TierModelDuration -Milliseconds 140000 | Should -Be '2m 20s'
        }

        It '7500000ms returns 125m 0s (large value, no hour tier)' {
            Format-TierModelDuration -Milliseconds 7500000 | Should -Be '125m 0s'
        }
    }

    Context 'Output type' {

        It 'return value is a string' {
            $result = Format-TierModelDuration -Milliseconds 500
            $result | Should -BeOfType [string]
        }
    }
}
