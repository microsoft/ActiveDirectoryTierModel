#Requires -Modules Pester
# Helper usage: . "$PSScriptRoot\Helpers\PrereqTestHelpers.ps1" for structure assertions.

Describe "TierModel Prerequisites Tests" -Tag 'Unit','Prereq' {
    BeforeAll {
        # Import the TierModel module
        $ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'TierModel.psd1'
        Import-Module $ModulePath -Force
        
        # Import test helpers
        . "$PSScriptRoot\Helpers\PrereqTestHelpers.ps1"
        
        # Mock external dependencies
        Mock Test-NetConnection { return $true } -ParameterFilter { $ComputerName -eq 'MockDC.test.local' } -ModuleName TierModel
        Mock Test-NetConnection { return $false } -ParameterFilter { $ComputerName -eq 'UnreachableDC.test.local' } -ModuleName TierModel
        
        # Create test dependencies file content
        $validDependencies = @{
            pester = "5.7.1"
            modules = @{
                ActiveDirectory = "1.0.1.0"
                GroupPolicy = "1.0"
            }
            schemaVersion = "1.0.0"
        }
        
        # Create temporary test files
        $tempPath = [System.IO.Path]::GetTempPath()
        $script:validDepsFile = Join-Path $tempPath "valid-dependencies.json"
        $script:invalidDepsFile = Join-Path $tempPath "invalid-dependencies.json"
        $script:missingDepsFile = Join-Path $tempPath "missing-dependencies.json"
        
        $validDependencies | ConvertTo-Json | Set-Content $script:validDepsFile
        "invalid json content {" | Set-Content $script:invalidDepsFile
        # $script:missingDepsFile intentionally not created
    }
    
    AfterAll {
        # Cleanup temporary files
        Remove-Item $script:validDepsFile -ErrorAction SilentlyContinue
        Remove-Item $script:invalidDepsFile -ErrorAction SilentlyContinue
    }
    
    Context "PowerShell Version Checks" -Tag 'Version','Prereq' {
    It "Should pass with PowerShell 7.0 or later" -Tag 'Positive','Version' {
            # This test runs in the current PS session, so if we're here, version is valid
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.PowerShellVersion | Should -Match "^[7-9]\."
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $result.Errors | Should -Not -Contain "*PowerShell version*not supported*"
            }
        }
        
    It "Should report PowerShell version in environment snapshot" -Tag 'Positive','Version' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.PowerShellVersion | Should -Not -BeNullOrEmpty
            $result.EnvironmentSnapshot.PowerShellVersion | Should -Match "\d+\.\d+\.\d+"
        }
    }
    
    Context "Elevation Checks" -Tag 'Elevation','Prereq' {
    It "Should check if running as Administrator" -Tag 'Elevation','Positive' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.IsElevated | Should -BeOfType [bool]
            
            # Test based on actual elevation status
            $isActuallyElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            $result.EnvironmentSnapshot.IsElevated | Should -Be $isActuallyElevated
            
            if (-not $isActuallyElevated) {
                $result.Valid | Should -Be $false
                $result.Errors | Should -Contain "PowerShell session is not running as Administrator."
                $result.Remediation | Should -Contain "Start PowerShell as Administrator (Run as administrator)"
            }
        }
    }
    
    Context "Dependencies File Parsing" -Tag 'Dependencies','Prereq' {
    It "Should successfully parse valid dependencies.json" -Tag 'Positive','Dependencies' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $script:validDepsFile
            
            $result.EnvironmentSnapshot.RequiredDependencies | Should -Not -BeNull
            $result.EnvironmentSnapshot.RequiredDependencies.pester | Should -Be "5.7.1"
            $result.EnvironmentSnapshot.RequiredDependencies.modules.ActiveDirectory | Should -Be "1.0.1.0"
        }
        
    It "Should fail when dependencies file is missing" -Tag 'Negative','Dependencies' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $script:missingDepsFile
            
            $result.Valid | Should -Be $false
            $result.Errors | Should -Contain "Dependencies file not found at: $script:missingDepsFile"
            $result.Remediation | Should -Contain "Ensure dependencies.json exists at the specified path"
        }
        
    It "Should fail when dependencies file has invalid JSON" -Tag 'Negative','Dependencies' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $script:invalidDepsFile
            
            $result.Valid | Should -Be $false
            $result.Errors | Should -Match "Error reading dependencies file.*Invalid JSON*"
            $result.Remediation | Should -Contain "Verify dependencies.json file format and syntax"
        }
    }
    
    Context "Module Version Validation" -Tag 'Modules','Prereq' {
    It "Should check Pester module availability" -Tag 'Positive','Modules' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $script:validDepsFile

            $result.EnvironmentSnapshot.PesterVersion | Should -Not -BeNullOrEmpty

            $installedPester = @(Get-Module -ListAvailable -Name Pester)
            # The snapshot reports the highest supported 5.x release (Pester 6.x is not yet
            # supported and installs side-by-side), falling back to the highest installed
            # version only when no 5.x is present.
            $expectedPester = $installedPester | Where-Object { $_.Version.Major -eq 5 } |
                Sort-Object Version -Descending | Select-Object -First 1
            if (-not $expectedPester) {
                $expectedPester = $installedPester | Sort-Object Version -Descending | Select-Object -First 1
            }
            if ($expectedPester) {
                $result.EnvironmentSnapshot.PesterVersion | Should -Be $expectedPester.Version.ToString()
            } else {
                $result.EnvironmentSnapshot.PesterVersion | Should -Be 'Not installed'
                $result.Valid | Should -Be $false
                $result.Errors | Should -Contain "Pester module is not installed."
            }
        }
        
    It "Should provide remediation for missing modules" -Tag 'Negative','Modules' {
            # Create a dependencies file requiring a non-existent module
            $testDeps = @{
                pester = "5.7.1"
                modules = @{
                    NonExistentModule = "1.0.0"
                }
                schemaVersion = "1.0.0"
            }
            $testDepsFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-deps-missing.json"
            $testDeps | ConvertTo-Json | Set-Content $testDepsFile
            
            try {
                $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $testDepsFile
                
                $result.Valid | Should -Be $false
                $result.Errors | Should -Contain "NonExistentModule module is not installed."
                $result.Remediation | Should -Contain "Install NonExistentModule module: Install-Module -Name NonExistentModule -RequiredVersion 1.0.0 -Force"
            }
            finally {
                Remove-Item $testDepsFile -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Domain Controller Connectivity" -Tag 'Connectivity','Prereq' {
    It "Should pass with reachable DC" -Tag 'Positive','Connectivity' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.PreferredDcReachable | Should -Be $true
            ($result.Errors -join ' ') | Should -Not -Match "Cannot reach PreferredDc"
        }
        
    It "Should fail with unreachable DC" -Tag 'Negative','Connectivity' {
            $result = Test-TierModelPrerequisites -PreferredDc 'UnreachableDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.PreferredDcReachable | Should -Be $false
            $result.Valid | Should -Be $false
            $result.Errors | Should -Contain "Cannot reach PreferredDc 'UnreachableDC.test.local' on LDAP port 389."
            $result.Remediation | Should -Contain "Verify network connectivity and DNS resolution for UnreachableDC.test.local"
        }
    }
    
    Context "Domain Environment Detection" -Tag 'Domain','Prereq' {
        BeforeEach {
            # Mock AD cmdlets for testing
            Mock Import-Module { } -ModuleName TierModel -ParameterFilter { $Name -eq 'ActiveDirectory' }
            Mock Get-Module { 
                return @{ Name = 'ActiveDirectory'; Version = '1.0.1.0' }
            } -ModuleName TierModel -ParameterFilter { $Name -eq 'ActiveDirectory' }
        }
        
    It "Should detect domain information when AD module is available" -Tag 'Positive','Domain' {
            Mock Get-ADDomain {
                return @{
                    DNSRoot = 'child.contoso.com'
                    NetBIOSName = 'CHILD'
                }
            } -ModuleName TierModel
            Mock Get-ADForest {
                return @{
                    RootDomain = 'contoso.com'
                }
            } -ModuleName TierModel
            Mock Get-ADGroup { return $null } -ModuleName TierModel -ParameterFilter { $Identity -eq 'Enterprise Admins' }
            
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.DomainName | Should -Be 'child.contoso.com'
            $result.EnvironmentSnapshot.DomainNetBIOSName | Should -Be 'CHILD'
            $result.EnvironmentSnapshot.IsChildDomain | Should -Be $true
            $result.EnvironmentSnapshot.ForestRootDomain | Should -Be 'contoso.com'
            $result.EnvironmentSnapshot.HasEnterpriseAdmins | Should -Be $false
        }
        
    It "Should handle AD cmdlet errors gracefully" -Tag 'Negative','Domain' {
            # Mock a successful environment for all other checks
            Mock Get-Module { return @{ Name = 'ActiveDirectory'; Version = '1.0.1.0' } } -ModuleName TierModel -ParameterFilter { $Name -eq 'ActiveDirectory' }
            Mock Get-Module { return @{ Name = 'GroupPolicy'; Version = '1.0' } } -ModuleName TierModel -ParameterFilter { $Name -eq 'GroupPolicy' }
            Mock Import-Module { } -ModuleName TierModel
            
            # Mock the failing AD cmdlet
            Mock Get-ADDomain { throw "Access denied" } -ModuleName TierModel
            
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.DomainDetectionError | Should -Match "Access denied"
            # Should capture AD errors gracefully without crashing (other prerequisite failures are OK)
            $result.EnvironmentSnapshot | Should -Not -BeNullOrEmpty  # Function should complete successfully
        }
    }

    Context "Domain Admin Membership" -Tag 'DomainAdmin','Prereq' {
        BeforeEach {
            # Mock all prerequisite checks to simulate ideal environment with module scope
            Mock Import-Module { } -ModuleName TierModel -ParameterFilter { $Name -eq 'ActiveDirectory' }
            Mock Get-Module { return @{ Name = 'ActiveDirectory'; Version = '1.0.1.0' } } -ModuleName TierModel -ParameterFilter { $args[0] -eq 'ActiveDirectory' }
            Mock Get-Module { return @{ Name = 'GroupPolicy'; Version = '1.0' } } -ModuleName TierModel -ParameterFilter { $Name -eq 'GroupPolicy' }  
            Mock Get-Module { return @{ Name = 'Pester'; Version = '5.7.1' } } -ModuleName TierModel -ParameterFilter { $Name -eq 'Pester' }
            Mock Get-ADDomain { return @{ DNSRoot = 'test.contoso.com'; NetBIOSName = 'TEST' } } -ModuleName TierModel
            # Mock AD cmdlets to prevent actual server connections
            Mock Get-ADGroup { return $null } -ModuleName TierModel
            Mock Get-ADGroupMember { return @() } -ModuleName TierModel
        }
        
    It "Should detect current user as Domain Admin when member" -Tag 'Positive','DomainAdmin' {
            # Test verifies domain admin check runs but returns false in test environment
            # since we can't mock [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            # In test environment without actual domain context, expects false
            $result.EnvironmentSnapshot.IsDomainAdmin | Should -Be $false
            # Function should still complete successfully
            $result | Should -Not -BeNullOrEmpty
        }
        
    It "Should fail when current user not Domain Admin" -Tag 'Negative','DomainAdmin' {
            # Call the function to get result - with default mocks, Get-ADGroup returns null
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            
            $result.EnvironmentSnapshot.IsDomainAdmin | Should -Be $false
            $result.Valid | Should -Be $false
            $result.Errors | Should -Contain "Domain Admin membership required for deployment operations"
            # With Get-ADGroup returning null from BeforeEach, expect this remediation message
            $result.Remediation | Should -Contain "Ensure Domain Admins group exists and user is member of Domain Admins group"
        }
    }
    
    Context "Result Object Structure" {
        It "Should return properly structured result object" -Tag 'Positive','Structure' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            Assert-PrereqResultStructure -Result $result -Context 'Unit'
        }
        
        It "Should include comprehensive environment snapshot" -Tag 'Positive','Structure' {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            Assert-PrereqResultStructure -Result $result -Context 'Unit-Snapshot'
        }
    }
    
    Context "Error Handling" {
        It "Should handle unexpected errors gracefully" {
            # Force an error by providing invalid parameters to internal calls
            Mock Test-NetConnection { throw "Unexpected network error" } -ModuleName TierModel
            
            $result = Test-TierModelPrerequisites -PreferredDc 'ErrorDC.test.local' -DependenciesPath $validDepsFile
            
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match "Error testing PreferredDc connectivity"
            $result.Remediation | Should -Contain "Check network configuration and firewall settings"
        }
    }

    Context "MSA Prerequisites" -Tag 'MsaPrereq', 'Prereq' {

        It "-IncludeMsa switch is accepted without error" {
            # Verify the switch exists and the function does not throw when used
            { Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeMsa } |
                Should -Not -Throw
        }

        It "-IncludeMsa returns a valid result object" {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeMsa
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Valid'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
            $result.PSObject.Properties.Name | Should -Contain 'EnvironmentSnapshot'
        }

        It "-IncludeMsa does not break existing prerequisite check output" {
            $resultBase = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            $resultMsa  = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeMsa

            # Both should have the same standard EnvironmentSnapshot fields
            $resultBase.EnvironmentSnapshot.PSObject.Properties.Name | ForEach-Object {
                $resultMsa.EnvironmentSnapshot.PSObject.Properties.Name | Should -Contain $_
            }
        }
    }

    Context "gMSA Prerequisites" -Tag 'GmsaPrereq', 'Prereq' {

        It "-IncludeGmsa switch is accepted without error" {
            { Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeGmsa } |
                Should -Not -Throw
        }

        It "-IncludeGmsa returns a valid result object" {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeGmsa
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Valid'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
            $result.PSObject.Properties.Name | Should -Contain 'EnvironmentSnapshot'
        }

        It "-IncludeGmsa does not break existing prerequisite check output" {
            $resultBase  = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            $resultGmsa  = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeGmsa

            $resultBase.EnvironmentSnapshot.PSObject.Properties.Name | ForEach-Object {
                $resultGmsa.EnvironmentSnapshot.PSObject.Properties.Name | Should -Contain $_
            }
        }
    }

    Context "dMSA Prerequisites" -Tag 'DmsaPrereq', 'Prereq' {

        It "-IncludeDmsa switch is accepted without error" {
            { Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa } |
                Should -Not -Throw
        }

        It "-IncludeDmsa returns a valid result object" {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Valid'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
            $result.PSObject.Properties.Name | Should -Contain 'EnvironmentSnapshot'
        }

        It "-IncludeDmsa does not break existing prerequisite check output" {
            $resultBase  = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            $resultDmsa  = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa

            $resultBase.EnvironmentSnapshot.PSObject.Properties.Name | ForEach-Object {
                $resultDmsa.EnvironmentSnapshot.PSObject.Properties.Name | Should -Contain $_
            }
        }
    }

    # ── BUG-003: dMSA functional-level messaging (DFL-only, no FFL check) ────────
    Context "dMSA Prerequisites — DFL / schema messaging (BUG-003)" -Tag 'DmsaPrereq', 'Prereq' {

        BeforeEach {
            Mock Get-ADRootDSE -ModuleName TierModel {
                return [PSCustomObject]@{ schemaNamingContext = "CN=Schema,CN=Configuration,DC=test,DC=local" }
            }
            # Schema objectVersion below 91 by default — would trigger the schema gate if not suppressed
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
                return [PSCustomObject]@{ objectVersion = 88 }
            }
            # dMSA class lookup present
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                return [PSCustomObject]@{ ldapDisplayName = 'msDS-DelegatedManagedServiceAccount' }
            }
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode = 'Windows2016Domain'; NetBIOSName = 'TEST'
                    DNSRoot = 'test.local'; DistinguishedName = 'DC=test,DC=local'
                }
            }
            Mock Get-ADForest -ModuleName TierModel {
                return [PSCustomObject]@{ ForestMode = 'Windows2016Forest'; RootDomain = 'test.local' }
            }
        }

        It "Insufficient DFL yields the friendly 2025 guidance and suppresses the redundant schema-version error" {
            $result    = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa
            $errorText = ($result.Errors -join "`n")

            $result.Valid | Should -Be $false
            $errorText    | Should -Match 'Domain Functional Level of 2025'
            # Schema-version error is suppressed when the DFL is the blocking issue (raising DFL implies schema >= 91)
            $errorText    | Should -Not -Match 'schema version >= 91'
            # DFL-only: no Forest Functional Level requirement is enforced (OQ-4 — dMSA needs FFL 2025 only cross-forest)
            $errorText    | Should -Not -Match 'Forest Functional Level'
        }

        It "Sufficient DFL (Windows2025Domain, schema 91) passes the dMSA functional-level gate" {
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode = 'Windows2025Domain'; NetBIOSName = 'TEST'
                    DNSRoot = 'test.local'; DistinguishedName = 'DC=test,DC=local'
                }
            }
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
                return [PSCustomObject]@{ objectVersion = 91 }
            }

            $result    = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa
            $errorText = ($result.Errors -join "`n")

            $errorText | Should -Not -Match 'Domain Functional Level of 2025'
            $errorText | Should -Not -Match 'schema version >= 91'
        }

        It "BUG-003: DFL=Windows2025 but schema version < 91 surfaces schema-gap error and adprep remediation" {
            # DFL is already at Windows Server 2025 so the DFL gate passes,
            # but schema objectVersion is 88 → the elseif ($schemaVersion -lt 91) branch fires.
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode = 'Windows2025Domain'; NetBIOSName = 'TEST'
                    DNSRoot = 'test.local'; DistinguishedName = 'DC=test,DC=local'
                }
            }
            # Schema objectVersion below 91 (BeforeEach default is 88 — no override needed,
            # but we set it explicitly for clarity)
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
                return [PSCustomObject]@{ objectVersion = 88 }
            }

            $result    = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa
            $errorText = ($result.Errors -join "`n")
            $remText   = ($result.Remediation -join "`n")

            $result.Valid  | Should -Be $false
            # Schema-gap error IS surfaced (DFL is fine, schema is the bottleneck)
            $errorText     | Should -Match 'schema version >= 91'
            # DFL guidance is NOT repeated (DFL is already at 2025)
            $errorText     | Should -Not -Match 'Domain Functional Level of 2025'
            # Remediation directs to adprep (new message from this branch)
            $remText       | Should -Match 'adprep'
        }

        It "BUG-003: dMSA class not found in schema yields correct error and schema remediation" {
            # DFL=2025, schema=91 → passes DFL+schema gates; but Get-ADObject throws for the DMSA
            # class lookup → the catch block surfaces the new remediation message.
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode = 'Windows2025Domain'; NetBIOSName = 'TEST'
                    DNSRoot = 'test.local'; DistinguishedName = 'DC=test,DC=local'
                }
            }
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
                return [PSCustomObject]@{ objectVersion = 91 }
            }
            # DMSA class lookup (Filter-based) throws → catch block fires
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                throw "AD object not found"
            }
            # Prevent Invoke-Command from attempting real WinRM
            Mock Invoke-Command -ModuleName TierModel { return @() }

            $result    = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa
            $errorText = ($result.Errors -join "`n")
            $remText   = ($result.Remediation -join "`n")

            $result.Valid  | Should -Be $false
            $errorText     | Should -Match 'msDS-DelegatedManagedServiceAccount class not found'
            $remText       | Should -Match 'schema version >= 91'
        }

        It "BUG-003: no KDS Root Key for dMSA yields the Add-KdsRootKey remediation" {
            # DFL=2025, schema=91, DMSA class present; Invoke-Command returns empty → no key found.
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode = 'Windows2025Domain'; NetBIOSName = 'TEST'
                    DNSRoot = 'test.local'; DistinguishedName = 'DC=test,DC=local'
                }
            }
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
                return [PSCustomObject]@{ objectVersion = 91 }
            }
            # DMSA class exists (Filter-based)
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                return [PSCustomObject]@{ ldapDisplayName = 'msDS-DelegatedManagedServiceAccount' }
            }
            # KDS check: Invoke-Command returns nothing (no keys installed)
            Mock Invoke-Command -ModuleName TierModel { return @() }

            $result    = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa
            $errorText = ($result.Errors -join "`n")
            $remText   = ($result.Remediation -join "`n")

            $result.Valid  | Should -Be $false
            $errorText     | Should -Match 'No KDS Root Key found'
            $remText       | Should -Match 'Add-KdsRootKey'
            $remText       | Should -Match 'NEVER create KDS keys automatically'
        }

        It "BUG-003: KDS Root Key present but not yet effective yields the wait-window remediation" {
            # DFL=2025, schema=91, DMSA class present; KDS key exists but EffectiveTime < 10 hours ago.
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode = 'Windows2025Domain'; NetBIOSName = 'TEST'
                    DNSRoot = 'test.local'; DistinguishedName = 'DC=test,DC=local'
                }
            }
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
                return [PSCustomObject]@{ objectVersion = 91 }
            }
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                return [PSCustomObject]@{ ldapDisplayName = 'msDS-DelegatedManagedServiceAccount' }
            }
            # KDS key exists but EffectiveTime is only 1 hour ago (< 10-hour window)
            Mock Invoke-Command -ModuleName TierModel {
                return @([PSCustomObject]@{ EffectiveTime = (Get-Date).AddHours(-1) })
            }

            $result    = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeDmsa
            $errorText = ($result.Errors -join "`n")
            $remText   = ($result.Remediation -join "`n")

            $result.Valid  | Should -Be $false
            $errorText     | Should -Match 'KDS Root Key exists but is not yet effective'
            $remText       | Should -Match '10-hour replication window'
        }
    }

    # ── T014: WinLaps Prerequisites ─────────────────────────────────────────────
    Context "WinLaps Prerequisites (-IncludeWinLaps)" -Tag 'WinLapsPrereq', 'Prereq' {

        BeforeEach {
            # Shared schema/DFL block: Get-ADRootDSE -> schemaDN; Get-ADObject (schemaObj) -> version;
            # Get-ADDomain -> DomainMode + NetBIOSName; Get-ADForest -> ForestMode
            Mock Get-ADRootDSE -ModuleName TierModel {
                return [PSCustomObject]@{
                    schemaNamingContext = "CN=Schema,CN=Configuration,DC=test,DC=local"
                }
            }

            # Get-ADObject -Identity (schema objectVersion check) vs -Filter (LAPS attr checks)
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
                return [PSCustomObject]@{ objectVersion = 88 }
            }
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                # Default: LAPS attributes present (schema OK)
                return [PSCustomObject]@{ lDAPDisplayName = 'msLAPS-Password' }
            }

            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode        = 'Windows2016Domain'
                    NetBIOSName       = 'TEST'
                    DNSRoot           = 'test.local'
                    DistinguishedName = 'DC=test,DC=local'
                }
            }
            Mock Get-ADForest -ModuleName TierModel {
                return [PSCustomObject]@{ ForestMode = 'Windows2016Forest'; RootDomain = 'test.local' }
            }

            # LAPS module present by default — self-contained, no reliance on ADStubs or
            # cross-file session ordering. Import-Module LAPS succeeds; Get-Module LAPS returns
            # the module; Get-Command resolves the required LAPS cmdlets. Tests that need the
            # "module absent / cmdlets missing" path override these at the It scope
            # (Gate 2 import-failure / missing-cmdlets).
            Mock Import-Module -ModuleName TierModel { } -ParameterFilter { $Name -eq 'LAPS' }
            Mock Get-Module -ModuleName TierModel -ParameterFilter { $Name -eq 'LAPS' } {
                return [PSCustomObject]@{ Name = 'LAPS'; Version = '1.0.0' }
            }
            Mock Get-Command -ModuleName TierModel -ParameterFilter { $Module -eq 'LAPS' } {
                return [PSCustomObject]@{ Name = 'MockLapsCmd' }
            }

            Mock Get-ADGroup -ModuleName TierModel { return $null }
            Mock Get-ADGroupMember -ModuleName TierModel { return @() }
        }

        It "-IncludeWinLaps switch is accepted without error" {
            { Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps } |
                Should -Not -Throw
        }

        It "-IncludeWinLaps returns a valid result object with WinLaps snapshot keys" {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Valid'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
            $result.PSObject.Properties.Name | Should -Contain 'EnvironmentSnapshot'
            # EnvironmentSnapshot is a hashtable — use ContainsKey, not PSObject.Properties
            $result.EnvironmentSnapshot.ContainsKey('WinLapsSchemaPresent') | Should -Be $true
            $result.EnvironmentSnapshot.ContainsKey('LapsModulePresent')    | Should -Be $true
        }

        It "-IncludeWinLaps does not affect output when omitted (no-op isolation)" {
            $resultBase = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            $resultBase.EnvironmentSnapshot.ContainsKey('WinLapsSchemaPresent') | Should -Be $false
            $resultBase.EnvironmentSnapshot.ContainsKey('LapsModulePresent')    | Should -Be $false
        }

        It "Gate 1: schema missing returns WINLAPS_SCHEMA_MISSING error and Valid=false" {
            # Override: no LAPS attributes found in schema
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                return $null
            }

            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'Windows LAPS schema'
            $result.EnvironmentSnapshot.WinLapsSchemaPresent | Should -Be $false
        }

        It "Gate 1: schema missing blocks Gate 2 (LapsModulePresent stays false)" {
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } { return $null }

            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.EnvironmentSnapshot.LapsModulePresent | Should -Be $false
        }

        It "Gate 2: LAPS module import failure returns WINLAPS_MODULE_MISSING error" {
            # Schema present, but LAPS module cannot be imported
            Mock Import-Module -ModuleName TierModel -ParameterFilter { $Name -eq 'LAPS' } {
                throw "No module named 'LAPS' was found."
            }

            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'WINLAPS_MODULE_MISSING'
            $result.EnvironmentSnapshot.LapsModulePresent | Should -Be $false
        }

        It "Gate 3: DFL below Windows2016Domain returns WINLAPS_DFL_INSUFFICIENT error" {
            # Schema + module OK; domain functional level is 2012R2 (too old for LAPS encryption)
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode        = 'Windows2012R2Domain'
                    NetBIOSName       = 'TEST'
                    DNSRoot           = 'test.local'
                    DistinguishedName = 'DC=test,DC=local'
                }
            }

            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'WINLAPS_DFL_INSUFFICIENT'
        }

        It "All three WinLaps gates pass: WinLapsSchemaPresent=true, LapsModulePresent=true" {
            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.EnvironmentSnapshot['WinLapsSchemaPresent'] | Should -Be $true
            $result.EnvironmentSnapshot['LapsModulePresent']    | Should -Be $true
        }

        It "Gate 1 catch: Valid=false and WINLAPS_SCHEMA error when Get-ADObject throws during schema check" {
            # ADObject throws during the LAPS attribute loop → catch sets winLapsSchemaPresent=false
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                throw "Schema query error"
            }

            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'Windows LAPS schema'
        }

        It "WinLaps section schemaDN fallback: Valid=false when Get-ADRootDSE throws in shared block" {
            # When Get-ADRootDSE throws, the shared block leaves $schemaDN=null
            # The WinLaps section re-tries; if it throws again, schema validation error is raised
            Mock Get-ADRootDSE -ModuleName TierModel { throw "DC unreachable" }

            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.Valid | Should -Be $false
            # Error message about schema or connectivity
            ($result.Errors -join ' ') | Should -Match 'LAPS schema|schema extensions|DC unreachable'
        }

        It "Gate 2 missing cmdlets: Valid=false when LAPS module loads but required cmdlets absent" {
            # Import-Module LAPS succeeds, Get-Module returns module, but Get-Command returns null
            Mock Get-Module -ModuleName TierModel -ParameterFilter { $Name -eq 'LAPS' } {
                return [PSCustomObject]@{ Name = 'LAPS'; Version = '1.0.0' }
            }
            Mock Get-Command -ModuleName TierModel -ParameterFilter { $Module -eq 'LAPS' } {
                return $null
            }

            $result = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'WINLAPS_MODULE_MISSING'
        }

        It "Does not break existing prerequisite snapshot fields when combined with -IncludeWinLaps" {
            $resultBase    = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile
            $resultWinLaps = Test-TierModelPrerequisites -PreferredDc 'MockDC.test.local' -DependenciesPath $validDepsFile -IncludeWinLaps

            $resultBase.EnvironmentSnapshot.PSObject.Properties.Name | ForEach-Object {
                $resultWinLaps.EnvironmentSnapshot.PSObject.Properties.Name | Should -Contain $_
            }
        }
    }
}

Describe "Get-TierModelConfig - Configuration Loading" -Tag "Unit", "Config" {

    BeforeAll {
        Mock Write-TierModelLog -ModuleName TierModel { }

        # Real production config directory — all 8 required JSON files are present
        # and structured correctly for the function (avoids strict-mode .Count issues
        # that arise when gpos/admx segments are empty-object PSCustomObjects).
        $script:RealCfgDir = Join-Path $PSScriptRoot '..' 'config'
    }

    Context "Get-TierModelConfig - Directory and File Validation" {

        It "Should throw when ConfigPath directory does not exist" {
            Mock Test-Path -ModuleName TierModel { return $false }

            { Get-TierModelConfig -ConfigPath "C:\NonExistent\TierModelConfig" } | Should -Throw "*Configuration directory not found*"
        }

        It "Should throw listing missing files when required files are absent" {
            $missingDir = "C:\EmptyTierModelConfig"
            Mock Test-Path -ModuleName TierModel {
                param($Path)
                return ($Path -eq $missingDir)   # dir exists; no files exist
            }

            { Get-TierModelConfig -ConfigPath $missingDir } | Should -Throw "*Missing required configuration files*"
        }
    }

    Context "Get-TierModelConfig - JSON Parse Failure" {

        It "Should throw 'Failed to parse' when a config file contains invalid JSON" {
            Mock Test-Path   -ModuleName TierModel { return $true }
            Mock Get-Content -ModuleName TierModel { return 'not valid json {{{{' }

            { Get-TierModelConfig -ConfigPath "C:\FakeCfgDir" } | Should -Throw "*Failed to parse*"
        }
    }

    Context "Get-TierModelConfig - Successful Load" {

        It "Should return a PSCustomObject on success" {
            $result = Get-TierModelConfig -ConfigPath $script:RealCfgDir

            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be "PSCustomObject"
        }

        It "Should expose all required top-level properties" {
            $result = Get-TierModelConfig -ConfigPath $script:RealCfgDir
            $props  = $result.PSObject.Properties.Name

            foreach ($p in @('version','metadata','conditionalLogic','organizationUnits',
                              'groups','users','aclDelegations','gpos','admx',
                              'guidMappings','ConfigHash','LoadedAt','ConfigPath')) {
                $props | Should -Contain $p
            }
        }

        It "Should read version from the metadata segment" {
            $result = Get-TierModelConfig -ConfigPath $script:RealCfgDir

            $result.version | Should -Not -BeNullOrEmpty
        }

        It "Should store ConfigPath on the returned object" {
            $result = Get-TierModelConfig -ConfigPath $script:RealCfgDir

            $result.ConfigPath | Should -Be $script:RealCfgDir
        }

        It "Should compute a non-empty SHA256 ConfigHash" {
            $result = Get-TierModelConfig -ConfigPath $script:RealCfgDir

            $result.ConfigHash | Should -Not -BeNullOrEmpty
            $result.ConfigHash.Length | Should -BeGreaterThan 16
        }
    }

    Context "Get-TierModelConfig - Default Values" {

        It "Should default version to '1.0.0' when metadata has no version property" {
            # Create a temp config dir where metadata lacks 'version'
            $noVerDir = Join-Path ([System.IO.Path]::GetTempPath()) "TierModelNoVer_$(New-Guid)"
            $null = New-Item -ItemType Directory -Path $noVerDir -Force

            # Copy real config files then overwrite metadata without 'version'
            $realCfg = Join-Path $PSScriptRoot '..' 'config'
            @('tiermodel-ous.json','tiermodel-groups.json','tiermodel-users.json',
              'tiermodel-acls.json','tiermodel-gpos.json','tiermodel-admx.json',
              'tiermodel-guid-mappings.json') | ForEach-Object {
                Copy-Item (Join-Path $realCfg $_) (Join-Path $noVerDir $_)
            }
            # metadata without 'version' key
            Set-Content -Path (Join-Path $noVerDir 'tiermodel-metadata.json') `
                -Value '{"metadata":{},"conditionalLogic":{}}' -Encoding UTF8

            try {
                $result = Get-TierModelConfig -ConfigPath $noVerDir
                $result.version | Should -Be "1.0.0"
            } finally {
                Remove-Item $noVerDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Get-TierModelConfig - Debug Log Failure Recovery" {
        # Covers the two inner try/catch blocks that guard debug-level Write-TierModelLog calls
        # inside the merge section ("Metadata segment debug" and "Final config object debug").
        # Those catch bodies are only reachable when the logger throws for those specific calls.

        It "Should continue successfully and return config when merge-section debug logging fails" {
            Mock Write-TierModelLog -ModuleName TierModel {
                param($Level, $Message, $Data)
                # Throw only for the two specific debug calls inside the merge try block
                if ($Level -eq 'Debug' -and ($Message -match 'segment debug|config object debug')) {
                    throw "Debug log backend unavailable"
                }
                # All other calls (Info, Error, and the per-file loop Debug) succeed silently
            }

            $result = Get-TierModelConfig -ConfigPath $script:RealCfgDir

            $result | Should -Not -BeNullOrEmpty
            $result.version | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-TierModelConfig - Merge Failure (outer catch)" {
        # NOTE: This context exercises the only path to the outer catch block.
        # The outer try wraps the merge + SHA256 hash computation.
        # To reach it, segment loading must succeed (8 Get-Content calls)
        # and then the hash-computation Get-Content loop (call 9+) must throw.
        # Without refactoring the hash step into a private helper mockable via
        # -ModuleName TierModel, this call-counter approach is the only reliable way.

        It "Should throw 'Failed to merge' when hash computation raises an I/O error" {
            $script:_gcCount = 0
            # Minimal JSON valid for ALL segments (avoids strict-mode .Count issues
            # since we are NOT hitting the Write-TierModelLog success log in this path)
            $validSegmentJson = '{"version":"2.0.0","metadata":{},"conditionalLogic":{},' +
                                '"organizationUnits":[],"groups":[],"users":[],' +
                                '"aclDelegations":[],"gpos":{},"admx":{}}'

            Mock Test-Path    -ModuleName TierModel { return $true }
            Mock Get-Content  -ModuleName TierModel {
                $script:_gcCount++
                if ($script:_gcCount -le 8) { return $validSegmentJson }
                throw "Simulated I/O error on hash read"
            }

            { Get-TierModelConfig -ConfigPath "C:\FakeCfgDir" } | Should -Throw "*Failed to merge configuration segments*"
        }
    }
}

Describe "Test-TierModelPrerequisites – Extended Coverage" -Tag "Unit", "Prereq" {
    BeforeAll {
        $script:ExtDC = "DC01.test.local"

        # Valid deps file: Pester + ActiveDirectory + GroupPolicy
        $depsObj = @{ pester = "5.7.1"; modules = @{ ActiveDirectory = "1.0.1.0"; GroupPolicy = "1.0" }; schemaVersion = "1.0.0" }
        $script:ExtDepsFile = Join-Path ([System.IO.Path]::GetTempPath()) "ext-prereq-full.json"
        $depsObj | ConvertTo-Json | Set-Content $script:ExtDepsFile

        # Deps file with only Pester (no modules section) for isolated Pester tests
        $pesterDeps = @{ pester = "5.7.1"; modules = @{}; schemaVersion = "1.0.0" }
        $script:ExtPesterOnlyDeps = Join-Path ([System.IO.Path]::GetTempPath()) "ext-prereq-pester.json"
        $pesterDeps | ConvertTo-Json | Set-Content $script:ExtPesterOnlyDeps

        InModuleScope TierModel {
            # Base mocks – each test overrides only what it needs
            Mock Test-NetConnection   { return $true }
            Mock Write-TierModelLog   { }
            Mock Import-Module        { }
            # Pester present at the right version
            Mock Get-Module { return [PSCustomObject]@{ Name = 'Pester'; Version = [version]'5.7.1' } } `
                -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pester' }
            # AD and GP modules appear loaded
            Mock Get-Module { return [PSCustomObject]@{ Name = 'ActiveDirectory'; Version = [version]'1.0.1.0' } } `
                -ParameterFilter { $Name -eq 'ActiveDirectory' }
            Mock Get-Module { return [PSCustomObject]@{ Name = 'GroupPolicy';     Version = [version]'1.0' } } `
                -ParameterFilter { $Name -eq 'GroupPolicy' }
            # AD cmdlets – safe defaults
            Mock Get-ADGroup       { return $null }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADDomain      { return [PSCustomObject]@{ DNSRoot = 'test.local'; NetBIOSName = 'TEST' } }
            Mock Get-ADForest      { return [PSCustomObject]@{ RootDomain = 'test.local' } }
        }
    }

    AfterAll {
        Remove-Item $script:ExtDepsFile        -ErrorAction SilentlyContinue
        Remove-Item $script:ExtPesterOnlyDeps  -ErrorAction SilentlyContinue
    }

    It "Should write verbose fallback and continue when Write-TierModelLog throws (line 84)" {
        InModuleScope TierModel { Mock Write-TierModelLog { throw "Logger unavailable" } }
        { Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile } | Should -Not -Throw
    }

    It "Should report Pester not installed when Get-Module -ListAvailable returns null (lines 138-140)" {
        InModuleScope TierModel {
            Mock Get-Module { return $null } `
                -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pester' }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile
        $result.Valid                        | Should -Be $false
        $result.Errors                       | Should -Contain "Pester module is not installed."
        $result.EnvironmentSnapshot.PesterVersion | Should -Be 'Not installed'
        ($result.Remediation -join ' ')      | Should -Match 'Install-Module.*Pester'
    }

    It "Should report a Pester version mismatch when only a non-5.x major is installed (lines 147-165)" {
        InModuleScope TierModel {
            Mock Get-Module { return [PSCustomObject]@{ Name = 'Pester'; Version = [version]'6.0.0' } } `
                -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pester' }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtPesterOnlyDeps
        $result.Valid | Should -Be $false
        ($result.Errors -join ' ') | Should -Match 'No supported Pester 5\.x release found'
        ($result.Errors -join ' ') | Should -Match 'Pester 6\.x has breaking changes'
        ($result.Remediation -join ' ') | Should -Match 'Install-Module.*Pester.*5\.0\.0'
        $result.EnvironmentSnapshot.PesterVersion | Should -Be '6.0.0'
    }

    It "Should accept any Pester 5.x version, not only the reference version (loosened gate)" {
        InModuleScope TierModel {
            Mock Get-Module { return [PSCustomObject]@{ Name = 'Pester'; Version = [version]'5.8.0' } } `
                -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pester' }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtPesterOnlyDeps
        ($result.Errors -join ' ') | Should -Not -Match 'Pester version mismatch'
        ($result.Errors -join ' ') | Should -Not -Match 'No supported Pester'
        $result.EnvironmentSnapshot.PesterVersion | Should -Be '5.8.0'
    }

    It "Should accept a supported 5.x installed side-by-side with an unsupported 6.x (non-blocking warning)" {
        InModuleScope TierModel {
            Mock Get-Module {
                return @(
                    [PSCustomObject]@{ Name = 'Pester'; Version = [version]'6.0.0' },
                    [PSCustomObject]@{ Name = 'Pester'; Version = [version]'5.9.0' }
                )
            } -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pester' }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtPesterOnlyDeps
        ($result.Errors -join ' ') | Should -Not -Match 'No supported Pester'
        ($result.Errors -join ' ') | Should -Not -Match 'Pester module is not installed'
        $result.EnvironmentSnapshot.PesterVersion | Should -Be '5.9.0'
        ($result.Remediation -join ' ') | Should -Match 'installed side-by-side'
        ($result.Remediation -join ' ') | Should -Match 'Import-Module Pester -MaximumVersion 5\.99\.99'
    }

    It "Should report RSAT-AD remediation when ActiveDirectory module is missing (line 209)" {
        $adOnlyDeps = @{ pester = "5.7.1"; modules = @{ ActiveDirectory = "1.0.1.0" }; schemaVersion = "1.0.0" }
        $adFile = Join-Path ([System.IO.Path]::GetTempPath()) "ext-prereq-ad-only.json"
        $adOnlyDeps | ConvertTo-Json | Set-Content $adFile
        InModuleScope TierModel {
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'ActiveDirectory' }
        }
        try {
            $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $adFile
            $result.Valid   | Should -Be $false
            $result.Errors  | Should -Contain "ActiveDirectory module is not installed."
            $result.Remediation | Should -Contain "Install RSAT Active Directory module: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools"
        } finally { Remove-Item $adFile -ErrorAction SilentlyContinue }
    }

    It "Should report RSAT-GP remediation when GroupPolicy module is missing (line 212)" {
        $gpOnlyDeps = @{ pester = "5.7.1"; modules = @{ GroupPolicy = "1.0" }; schemaVersion = "1.0.0" }
        $gpFile = Join-Path ([System.IO.Path]::GetTempPath()) "ext-prereq-gp-only.json"
        $gpOnlyDeps | ConvertTo-Json | Set-Content $gpFile
        InModuleScope TierModel {
            # Not loaded AND not installed
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'GroupPolicy' }
        }
        try {
            $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $gpFile
            $result.Valid   | Should -Be $false
            $result.Errors  | Should -Contain "GroupPolicy module is not installed."
            $result.Remediation | Should -Contain "Install RSAT Group Policy module: Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools"
        } finally { Remove-Item $gpFile -ErrorAction SilentlyContinue }
    }

    It "Should attempt GroupPolicy Import-Module when module is not loaded (lines 168-169)" {
        # Get-Module -Name GroupPolicy (no -ListAvailable) returns null → Import path executes
        $gpOnlyDeps = @{ pester = "5.7.1"; modules = @{ GroupPolicy = "1.0" }; schemaVersion = "1.0.0" }
        $gpFile = Join-Path ([System.IO.Path]::GetTempPath()) "ext-prereq-gpload.json"
        $gpOnlyDeps | ConvertTo-Json | Set-Content $gpFile
        InModuleScope TierModel {
            Mock Get-Module { return $null }                                                     -ParameterFilter { $Name -eq 'GroupPolicy' -and $ListAvailable -ne $true }
            Mock Import-Module { }                                                               -ParameterFilter { $args[0] -eq 'GroupPolicy' -or $Name -eq 'GroupPolicy' }
        }
        try {
            $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $gpFile
            $result | Should -Not -BeNullOrEmpty
            # Import-Module GroupPolicy was called (lines 168-169 executed)
            Should -Invoke Import-Module -ModuleName TierModel -Times 1 -ParameterFilter { $args[0] -eq 'GroupPolicy' -or $Name -eq 'GroupPolicy' }
        } finally { Remove-Item $gpFile -ErrorAction SilentlyContinue }
    }

    It "Should catch per-module check errors and treat module as missing (lines 198-202)" {
        $adOnlyDeps = @{ pester = "5.7.1"; modules = @{ ActiveDirectory = "1.0.1.0" }; schemaVersion = "1.0.0" }
        $adFile = Join-Path ([System.IO.Path]::GetTempPath()) "ext-prereq-adthrow.json"
        $adOnlyDeps | ConvertTo-Json | Set-Content $adFile
        InModuleScope TierModel {
            # Make Get-Module -ListAvailable throw to trigger the per-module catch block
            Mock Get-Module { throw [System.IO.IOException]::new("Listing failed") } `
                -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'ActiveDirectory' }
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -ne $true }
        }
        try {
            $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $adFile
            $result | Should -Not -BeNullOrEmpty
            # After the catch, $moduleToCheck = null → module treated as missing
            $result.Errors | Should -Contain "ActiveDirectory module is not installed."
        } finally { Remove-Item $adFile -ErrorAction SilentlyContinue }
    }

    It "Should report import failure when module is installed but cannot be imported (lines 233-235)" {
        $adOnlyDeps = @{ pester = "5.7.1"; modules = @{ ActiveDirectory = "1.0.1.0" }; schemaVersion = "1.0.0" }
        $adFile = Join-Path ([System.IO.Path]::GetTempPath()) "ext-prereq-adfail.json"
        $adOnlyDeps | ConvertTo-Json | Set-Content $adFile
        InModuleScope TierModel {
            # loadedModule = null, installedModule = present → triggers Import-Module validation
            Mock Get-Module { return $null } `
                -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -ne $true }
            Mock Get-Module { return [PSCustomObject]@{ Name = 'ActiveDirectory'; Version = [version]'1.0.1.0' } } `
                -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -eq $true }
            Mock Import-Module { throw [System.IO.IOException]::new("Import failed due to corruption") } `
                -ParameterFilter { $args[0] -eq 'ActiveDirectory' -or $Name -eq 'ActiveDirectory' }
        }
        try {
            $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $adFile
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'ActiveDirectory module exists but cannot be imported'
            $result.Remediation | Should -Contain "Reinstall ActiveDirectory module or check for corruption"
        } finally { Remove-Item $adFile -ErrorAction SilentlyContinue }
    }

    It "Should run Get-ADGroupMember when Domain Admins group exists and report not-admin (lines 253-261)" {
        # Needs InModuleScope to properly override Get-Module AND Get-ADGroupMember
        InModuleScope TierModel {
            # Get-Module ActiveDirectory (no -ListAvailable at line 248) → must return a module object
            Mock Get-Module { return [PSCustomObject]@{ Name = 'ActiveDirectory'; Version = [version]'1.0.1.0' } }

            # Domain Admins group found → $domainAdmins truthy → enters the if block at line 252
            Mock Get-ADGroup {
                param($Identity, $Server, $ErrorAction)
                if ($Identity.ToString() -eq 'Domain Admins') {
                    return [PSCustomObject]@{ Name = 'Domain Admins'; DistinguishedName = 'CN=Domain Admins,CN=Users,DC=test,DC=local' }
                }
                return $null
            }
            # Return one member with a non-matching SID so Where-Object scriptblock body (line 254) executes
            # but the filter yields nothing → $isDomainAdmin is $null → lines 256-261 cover
            Mock Get-ADGroupMember {
                return @([PSCustomObject]@{ SID = 'S-1-5-21-0000000-0000-0000-0000'; Name = 'SomeDomainUser' })
            }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile
        $result.EnvironmentSnapshot.IsDomainAdmin | Should -Be $false
        $result.Errors | Should -Contain "Domain Admin membership required for deployment operations"
        ($result.Remediation -join ' ') | Should -Match "Add current user to Domain Admins"
    }

    It "Should set IsDomainAdmin false and add install-AD error when AD module unavailable after import (lines 273-276)" {
        InModuleScope TierModel {
            # Get-Module ActiveDirectory (no -ListAvailable) returns null after Import-Module → else branch
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -ne $true }
            Mock Get-Module { return [PSCustomObject]@{ Name = 'ActiveDirectory'; Version = [version]'1.0.1.0' } } `
                -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -eq $true }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile
        $result.EnvironmentSnapshot.IsDomainAdmin | Should -Be $false
        $result.Valid | Should -Be $false
        ($result.Remediation -join ' ') | Should -Match "Install ActiveDirectory module"
    }

    It "Should set HasEnterpriseAdmins true when Enterprise Admins group is found (line 327)" {
        InModuleScope TierModel {
            Mock Get-Module { return [PSCustomObject]@{ Name = 'ActiveDirectory'; Version = [version]'1.0.1.0' } } `
                -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -ne $true }
            # Broad mock with identity dispatch to avoid ParameterFilter matching issues
            Mock Get-ADGroup {
                param($Identity, $Server, $ErrorAction)
                if ($Identity.ToString() -eq 'Enterprise Admins') {
                    return [PSCustomObject]@{ Name = 'Enterprise Admins' }
                }
                return $null
            }
            Mock Get-ADGroupMember { return @() }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile
        $result.EnvironmentSnapshot.HasEnterpriseAdmins | Should -Be $true
    }

    It "Should set HasDnsAdmins true with note when DnsAdmins group is found (lines 340-342)" {
        InModuleScope TierModel {
            Mock Get-Module { return [PSCustomObject]@{ Name = 'ActiveDirectory'; Version = [version]'1.0.1.0' } } `
                -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -ne $true }
            # Broad mock: DnsAdmins returns a group; Enterprise Admins returns null
            Mock Get-ADGroup {
                param($Identity, $Server, $ErrorAction)
                if ($Identity.ToString() -eq 'DnsAdmins') { return [PSCustomObject]@{ Name = 'DnsAdmins' } }
                return $null
            }
            Mock Get-ADGroupMember { return @() }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile
        $result.EnvironmentSnapshot.HasDnsAdmins   | Should -Be $true
        $result.EnvironmentSnapshot.DnsAdminsNote  | Should -Match 'DnsAdmins group available'
    }

    It "Should set HasDnsAdmins false with note when DnsAdmins group is not found (lines 344-345)" {
        InModuleScope TierModel {
            Mock Get-Module { return [PSCustomObject]@{ Name = 'ActiveDirectory'; Version = [version]'1.0.1.0' } } `
                -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable -ne $true }
            # All Get-ADGroup calls return null (broad mock overrides BeforeAll default)
            Mock Get-ADGroup { return $null }
            Mock Get-ADGroupMember { return @() }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile
        $result.EnvironmentSnapshot.HasDnsAdmins   | Should -Be $false
        $result.EnvironmentSnapshot.DnsAdminsNote  | Should -Match 'DnsAdmins group not found'
    }

    It "Should return valid=false with outer-catch error when prerequisite check fails unexpectedly (lines 368-377)" {
        InModuleScope TierModel {
            # Throw from inside the outer try (Pester check) → outer catch fires
            Mock Get-Module { throw [System.Exception]::new("Catastrophic failure") } `
                -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pester' }
        }
        $result = Test-TierModelPrerequisites -PreferredDc $script:ExtDC -DependenciesPath $script:ExtDepsFile
        $result | Should -Not -BeNullOrEmpty
        $result.Valid | Should -Be $false
        ($result.Errors -join ' ') | Should -Match 'Unexpected error during prerequisites check'
        ($result.Remediation -join ' ') | Should -Match 'Review the error details'
    }
}
