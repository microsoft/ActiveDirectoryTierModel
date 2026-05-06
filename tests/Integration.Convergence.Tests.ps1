BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules' 'TierModel' 'TierModel.psm1'
    Import-Module $ModulePath -Force

    # Test configuration paths
    $script:TestDataDir = Join-Path $PSScriptRoot 'TestData'
    $script:EmptyConfigPath = Join-Path $script:TestDataDir 'convergence-empty-config.json'
    $script:SimpleConfigPath = Join-Path $script:TestDataDir 'convergence-simple-config.json'
    
    # Create test data directory if it doesn't exist
    if (-not (Test-Path $script:TestDataDir)) {
        New-Item -Path $script:TestDataDir -ItemType Directory -Force | Out-Null
    }
    
    # Empty configuration (should always be converged)
    $emptyConfig = @{
        version = '1.0.0'
        organizationUnits = @()
        groups = @()
        users = @()
        gpos = @()
        aclDelegations = @()
        admx = @()
    }
    
    # Simple configuration with minimal resources
    $simpleConfig = @{
        version = '1.0.0'
        organizationUnits = @(
            @{ name = 'TestOU'; path = 'OU=TestOU,DC=test,DC=local'; description = 'Test OU' }
        )
        groups = @(
            @{ 
                name = 'TestGroup'
                path = 'OU=TestOU,DC=test,DC=local'
                samaccountname = 'TestGroup'
                description = 'Test group for convergence tests'
                scope = 'Global'
                type = 'Security'
                members = @('user1')
            }
        )
        users = @()
        gpos = @()
        aclDelegations = @()
        admx = @()
    }
    
    # Write test configurations
    $emptyConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:EmptyConfigPath -Force
    $simpleConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:SimpleConfigPath -Force
}

AfterAll {
    # Clean up test files
    if (Test-Path $script:EmptyConfigPath) { Remove-Item $script:EmptyConfigPath -Force }
    if (Test-Path $script:SimpleConfigPath) { Remove-Item $script:SimpleConfigPath -Force }
}

Describe 'TierModel Convergence & Idempotency' -Tag 'Convergence' {
    
    Context 'Plan Hash Computation (T0050)' {
        
        It 'Should generate deterministic plan hash for same configuration' {
            $plan1 = Get-TierModelPlan -Path $script:SimpleConfigPath
            $plan2 = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Both plans should have identical hashes
            $plan1.PlanHash | Should -Not -BeNullOrEmpty
            $plan2.PlanHash | Should -Not -BeNullOrEmpty
            $plan1.PlanHash | Should -Be $plan2.PlanHash
        }
        
        It 'Should generate different plan hashes for different configurations' {
            $plan1 = Get-TierModelPlan -Path $script:EmptyConfigPath
            $plan2 = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Plans should have different hashes
            $plan1.PlanHash | Should -Not -BeNullOrEmpty
            $plan2.PlanHash | Should -Not -BeNullOrEmpty
            $plan1.PlanHash | Should -Not -Be $plan2.PlanHash
        }
        
        It 'Should use special empty hash for configurations with no actions' {
            $plan = Get-TierModelPlan -Path $script:EmptyConfigPath
            
            # Empty plan should have special hash format
            $plan.PlanHash | Should -Not -BeNullOrEmpty
            $plan.PlanHash | Should -Match ':empty$'
        }
        
        It 'Should include ConfigHash in plan when requested' {
            $plan = Get-TierModelPlan -Path $script:SimpleConfigPath -IncludeHashes
            
            # Should include both config and plan hashes
            $plan.ConfigHash | Should -Not -BeNullOrEmpty
            $plan.PlanHash | Should -Not -BeNullOrEmpty
            $plan.ConfigHash | Should -Not -Be $plan.PlanHash
        }
    }
    
    Context 'Convergence Detection (T0051)' {
        
        It 'Should detect already converged state for empty configuration' {
            # Mock Set-TierModel to avoid actual execution but test convergence logic
            # For now, test the plan generation that feeds into convergence
            $plan = Get-TierModelPlan -Path $script:EmptyConfigPath
            
            # Empty config should produce no actions (converged state)
            $plan.AllActions | Should -HaveCount 0
            $plan.ActionSummary.TotalActions | Should -Be 0
        }
        
        It 'Should include convergence indicators in plan structure' {
            $plan = Get-TierModelPlan -Path $script:EmptyConfigPath
            
            # Plan should include necessary properties for convergence detection
            # Don't use pipeline for array type checking - it unrolls the array
            Should -ActualValue $plan.AllActions -BeOfType [array]
            $plan.ActionSummary | Should -Not -BeNull
            $plan.ActionSummary.TotalActions | Should -BeOfType [int]
        }
        
        It 'Should maintain plan structure consistency for convergence logic' {
            $plan = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Plan should have consistent structure regardless of content
            $plan | Should -Not -BeNull
            # AllActions may be empty array or null - both are valid
            Should -ActualValue $plan.AllActions -BeOfType [array]
            $plan.ActionSummary | Should -Not -BeNull
            $plan.PlanHash | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Plan Structure Validation' {
        
        It 'Should maintain backward compatibility in plan object structure' {
            $plan = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Verify all expected properties exist
            $plan.Timestamp | Should -Not -BeNullOrEmpty
            $plan.ModelVersion | Should -Not -BeNullOrEmpty
            $plan.PlanHash | Should -Not -BeNullOrEmpty
            # Don't use pipeline for array type checking - it unrolls the array
            Should -ActualValue $plan.AllActions -BeOfType [array]
            $plan.ActionSummary | Should -Not -BeNull
            $plan.CurrentState | Should -BeNull # CurrentState not yet implemented (see line 267)
            Should -ActualValue $plan.DriftFindings -BeOfType [array]
            $plan.CorrelationId | Should -Not -BeNullOrEmpty
        }
        
        It 'Should include resource counts in plan' {
            $plan = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Verify resource counts are present and correct types
            $plan.OrganizationUnitsCount | Should -BeOfType [int]
            $plan.GroupsCount | Should -BeOfType [int]
            $plan.UsersCount | Should -BeOfType [int]
            $plan.GposCount | Should -BeOfType [int]
            $plan.AdmxCount | Should -BeOfType [int]
        }
        
        It 'Should compute resource counts correctly' {
            $plan = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Verify counts match the test configuration
            $plan.OrganizationUnitsCount | Should -Be 1  # One OU in simple config
            $plan.GroupsCount | Should -Be 1             # One group in simple config
            $plan.UsersCount | Should -Be 0              # No users in simple config
            $plan.GposCount | Should -Be 0               # No GPOs in simple config
            $plan.AdmxCount | Should -Be 0               # No ADMX in simple config
        }
    }
    
    Context 'Idempotency Foundation' {
        
        It 'Should support multiple plan generations without side effects' {
            # Generate multiple plans and verify they're identical
            $plan1 = Get-TierModelPlan -Path $script:SimpleConfigPath
            $plan2 = Get-TierModelPlan -Path $script:SimpleConfigPath
            $plan3 = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # All plans should be functionally equivalent
            $plan1.PlanHash | Should -Be $plan2.PlanHash
            $plan2.PlanHash | Should -Be $plan3.PlanHash
            $plan1.ActionSummary.TotalActions | Should -Be $plan2.ActionSummary.TotalActions
            $plan1.OrganizationUnitsCount | Should -Be $plan2.OrganizationUnitsCount
        }
        
        It 'Should handle configuration changes predictably' {
            $plan1 = Get-TierModelPlan -Path $script:EmptyConfigPath
            $plan2 = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Different configs should produce predictably different plans
            $plan1.PlanHash | Should -Not -Be $plan2.PlanHash
            # Both may have 0 actions without actual AD comparison, verify resource counts differ
            $plan1.OrganizationUnitsCount | Should -BeLessThan $plan2.OrganizationUnitsCount
        }
    }
    
    Context 'Error Handling & Resilience' {
        
        It 'Should handle malformed configuration gracefully' {
            # Test with non-existent config file
            { Get-TierModelPlan -Path 'C:\NonExistent\config.json' } | Should -Throw
        }
        
        It 'Should validate plan hash computation with various inputs' {
            $emptyPlan = Get-TierModelPlan -Path $script:EmptyConfigPath
            $simplePlan = Get-TierModelPlan -Path $script:SimpleConfigPath
            
            # Both should have valid hashes despite different content
            # Empty plans have :empty suffix, non-empty may also have it if no action plan generated
            $emptyPlan.PlanHash | Should -Match '^[a-f0-9]+(:empty)?$'
            $simplePlan.PlanHash | Should -Match '^[a-f0-9]+(:empty)?$'
        }
    }
}

# T0052a: ADMX Idempotency Tests
Describe 'ADMX Import Idempotency' -Tag 'ADMX', 'Idempotency' {
    
    BeforeAll {
        # ADMX-specific test configuration
        $script:AdmxConfigPath = Join-Path $script:TestDataDir 'admx-idempotency-config.json'
        
        $admxConfig = @{
            version = '1.0.0'
            organizationUnits = @()
            groups = @()
            users = @()
            gpos = @()
            aclDelegations = @()
            admx = @(
                @{ path = 'C:\TestADMX'; language = 'en-US' }
                @{ path = 'C:\TestADMX2'; language = 'fr-FR' }
            )
        }
        
        $admxConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:AdmxConfigPath -Force
    }
    
    AfterAll {
        if (Test-Path $script:AdmxConfigPath) { Remove-Item $script:AdmxConfigPath -Force }
    }
    
    Context 'ADMX Import Plan Generation' {
        
        It 'Should generate consistent plans for ADMX imports' {
            $plan1 = Get-TierModelPlan -Path $script:AdmxConfigPath
            $plan2 = Get-TierModelPlan -Path $script:AdmxConfigPath
            
            # Plans should be identical for same ADMX configuration
            $plan1.PlanHash | Should -Be $plan2.PlanHash
            $plan1.AdmxCount | Should -Be 2
            $plan2.AdmxCount | Should -Be 2
        }
        
        It 'Should include ADMX resources in plan structure' {
            $plan = Get-TierModelPlan -Path $script:AdmxConfigPath
            
            # Verify ADMX count is captured in plan
            $plan.AdmxCount | Should -Be 2
            
            # Note: CurrentState is not yet implemented, so skip detailed state validation
            # When state capture is implemented, this test should validate:
            # - $plan.CurrentState.Admx array
            # - Path and Language properties for each ADMX entry
        }
        
        It 'Should detect no ADMX drift in mirrored state' {
            $plan = Get-TierModelPlan -Path $script:AdmxConfigPath
            
            # Current implementation mirrors config, so no ADMX drift should be detected
            $admxDriftFindings = $plan.DriftFindings | Where-Object { $_.Category -like 'Admx*' }
            $admxDriftFindings | Should -HaveCount 0
        }
        
        It 'Should support ADMX-only plan generation' {
            $emptyPlanWithAdmx = Get-TierModelPlan -Path $script:AdmxConfigPath
            $emptyPlanWithoutAdmx = Get-TierModelPlan -Path $script:EmptyConfigPath
            
            # Plans should differ only in ADMX content
            $emptyPlanWithAdmx.AdmxCount | Should -Be 2
            $emptyPlanWithoutAdmx.AdmxCount | Should -Be 0
            $emptyPlanWithAdmx.PlanHash | Should -Not -Be $emptyPlanWithoutAdmx.PlanHash
        }
    }
    
    Context 'Simulated ADMX Idempotency' {
        
        It 'Should maintain ADMX state consistency across multiple plan generations' {
            # Simulate the idempotency behavior that would occur after actual ADMX import
            $initialPlan = Get-TierModelPlan -Path $script:AdmxConfigPath
            $followupPlan = Get-TierModelPlan -Path $script:AdmxConfigPath
            
            # Since current state mirrors config, both plans should be identical (simulating idempotency)
            $initialPlan.PlanHash | Should -Be $followupPlan.PlanHash
            $initialPlan.AdmxCount | Should -Be $followupPlan.AdmxCount
            
            # Both should show no ADMX drift (simulating successful import achieving convergence)
            $initialAdmxDrift = $initialPlan.DriftFindings | Where-Object { $_.Category -like 'Admx*' }
            $followupAdmxDrift = $followupPlan.DriftFindings | Where-Object { $_.Category -like 'Admx*' }
            
            $initialAdmxDrift | Should -HaveCount 0
            $followupAdmxDrift | Should -HaveCount 0
        }
        
        It 'Should produce stable plan signatures for ADMX configurations' {
            # Test that plan hash is deterministic for ADMX content
            $plans = 1..5 | ForEach-Object { Get-TierModelPlan -Path $script:AdmxConfigPath }
            
            # All plans should have identical hashes
            $uniqueHashes = $plans | ForEach-Object { $_.PlanHash } | Select-Object -Unique
            $uniqueHashes | Should -HaveCount 1
        }
    }
}
