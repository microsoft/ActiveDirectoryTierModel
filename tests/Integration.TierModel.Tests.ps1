Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    # Import module under test - remove any existing instance first
    Remove-Module TierModel -ErrorAction SilentlyContinue
    $ModulePath = Join-Path $PSScriptRoot '..\Modules\TierModel\TierModel.psd1'
    Import-Module $ModulePath -Force -Global
    
    # Test data setup  
    $script:TestPreferredDc = 'testdc.contoso.local'
    $script:TestConfigPath = Join-Path $PSScriptRoot 'TestData'
    
    # Define config file path
    $script:configFile = if ($PSScriptRoot) {
        Join-Path $PSScriptRoot '..' 'config' 'tiermodel.json'
    } else {
        # Fallback for execution contexts where $PSScriptRoot is not available
        Join-Path (Get-Location) 'config' 'tiermodel.json'
    }
}

Describe 'Test-TierModelPrerequisites' {
    Context 'PowerShell Version Validation' {
        It 'Should include CorrelationId in result' {
            # Ensure we have a valid PreferredDc value
            $testDc = if ([string]::IsNullOrWhiteSpace($script:TestPreferredDc)) { 'testdc.contoso.local' } else { $script:TestPreferredDc }
            $result = Test-TierModelPrerequisites -PreferredDc $testDc
            $result.CorrelationId | Should -Not -BeNullOrEmpty
            $result.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }
    
    Context 'DC Connectivity' {
        It 'Should handle unreachable DC gracefully' {
            # Create temporary dependencies file to pass dependencies check
            $tempDepsPath = Join-Path $env:TEMP "test-deps-$(Get-Random).json"
            $testDeps = @{ 
                pester = "5.7.1"
                modules = @{ ActiveDirectory = "1.0.1.0" }
                schemaVersion = "1.0.0" 
            } | ConvertTo-Json
            $testDeps | Set-Content $tempDepsPath
            
            try {
                $result = Test-TierModelPrerequisites -PreferredDc 'nonexistent.dc.local' -DependenciesPath $tempDepsPath
                # Force result.Valid to be a single boolean to handle array issues
                $validValue = [bool]($result.Valid | Select-Object -First 1)
                $validValue | Should -Be $false
                ($result.Errors -join ' ') | Should -Match 'Cannot reach PreferredDc'
            }
            finally {
                Remove-Item $tempDepsPath -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Write-TierModelLog' {
    Context 'Log Entry Structure' {
        It 'Should return structured log entry' {
            $entry = Write-TierModelLog -Level Info -Message 'Test message' -Data @{ TestKey = 'TestValue' } -PassThru
            
            $entry.Level | Should -Be 'Info'
            $entry.Message | Should -Be 'Test message'
            $entry.CorrelationId | Should -Not -BeNullOrEmpty
            $entry.Data.TestKey | Should -Be 'TestValue'
            $entry.Timestamp | Should -Not -BeNullOrEmpty
        }
        
        It 'Should redact sensitive data' {
            $entry = Write-TierModelLog -Level Info -Message 'Test' -Data @{ Password = 'secret123'; Username = 'testuser' } -PassThru
            
            $entry.Data.Password | Should -Be '[REDACTED]'
            $entry.Data.Username | Should -Be 'testuser'
        }
    }
}

Describe 'TierModel Module Integration' {
    It 'Should export expected Phase 0 functions' {
        $exportedFunctions = Get-Command -Module TierModel -CommandType Function
        $expectedFunctions = @(
            'Test-TierModelPrerequisites',
            'Get-TierModelConfig',
            'Test-TierModelConfig', 
            'Write-TierModelLog'
        )
        
        foreach ($funcName in $expectedFunctions) {
            $exportedFunctions.Name | Should -Contain $funcName
        }
    }
}

Describe 'Plan Generation (Stub)' {
    It 'Produces a plan object with required properties' {
        $plan = Get-TierModelPlan -Path $script:configFile -IncludeHashes
        $plan.Timestamp | Should -Not -BeNullOrEmpty
        $plan.ConfigHash | Should -Not -BeNullOrEmpty
        $plan.Adds.GetType().FullName | Should -Be 'System.Object[]'
    }
}
