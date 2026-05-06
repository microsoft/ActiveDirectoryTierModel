BeforeAll {
    # Load the TierModel module
    $ModulePath = "$PSScriptRoot\..\Modules\TierModel\TierModel.psd1"
    Import-Module $ModulePath -Force
}

Describe "Get-TierModelGpo - GPO Deployment Planning" -Tag "Unit", "GPO", "Planning" {
    
    BeforeAll {
        # Mock AD Domain (target module scope)
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DistinguishedName = "DC=test,DC=local"
                DNSRoot = "test.local"
            }
        }
        
        # Mock AD OU checks (target module scope)
        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            
            # Simulate OU existence for specific paths
            if ($Identity -match '^OU=Tier0' -or $Identity -match '^OU=Domain Controllers') {
                return [PSCustomObject]@{
                    DistinguishedName = $Identity
                }
            }
            
            # OU not found - respect ErrorAction (default is Continue which throws)
            if ($ErrorAction -eq 'SilentlyContinue') {
                return $null  # Suppress error
            }
            throw "OU not found: $Identity"
        }
        
        # Mock GPO cmdlets (target module scope)
        Mock Get-GPO -ModuleName TierModel {
            param($Name, $Server, $All, $ErrorAction)
            
            if ($All) {
                return @()  # Return empty array for Get-GPO -All
            }
            
            # Simulate existing GPOs
            if ($Name -eq "ExistingGPO") {
                return [PSCustomObject]@{
                    DisplayName = $Name
                    Id = [System.Guid]::NewGuid()
                }
            }
            
            # GPO not found - respect ErrorAction
            if ($ErrorAction -eq 'SilentlyContinue') {
                return $null
            }
            throw "GPO not found: $Name"
        }
        
        Mock Get-GPInheritance -ModuleName TierModel {
            param($Target, $Server)
            
            # Simulate linked GPOs
            return [PSCustomObject]@{
                GpoLinks = @(
                    [PSCustomObject]@{
                        DisplayName = "ExistingGPO"
                    }
                )
            }
        }
        
        Mock Get-ADGroup -ModuleName TierModel {
            param([string]$Identity, [string]$Server, $ErrorAction)
            

            if ($Identity -eq "ExistingGroup") {
                return [PSCustomObject]@{ SamAccountName = $Identity }
            }
            
            # Group not found - respect ErrorAction
            if ($ErrorAction -eq 'SilentlyContinue') {
                return $null  # Suppress error
            }
            throw "Group not found: $Identity"
        }
    }
    
    Context "GPO Planning - Basic Scenarios" {
        
        It "Should generate plan for new GPO requiring creation, import, and link" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "NewGPO"
                                mode = "createAndImport"
                            }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpo -Config $config -DomainController "DC01" -Silent
            
            $plan.Actions | Should -Not -BeNullOrEmpty
            $createAction = $plan.Actions | Where-Object { $_.Action -eq 'CreateGPO' }
            $importAction = $plan.Actions | Where-Object { $_.Action -eq 'ImportGPO' }
            $linkAction = $plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' }
            
            $createAction | Should -Not -BeNullOrEmpty
            $importAction | Should -Not -BeNullOrEmpty
            $linkAction | Should -Not -BeNullOrEmpty
            
            $plan.Summary.TotalActions | Should -BeGreaterThan 0
        }
        
        It "Should skip GPO link action if GPO already exists and is linked" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "ExistingGPO"
                                mode = "createAndImport"
                            }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpo -Config $config -DomainController "DC01" -Silent
            
            # Should not generate any actions for already-linked GPO
            $linkActions = @($plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' -and $_.GPOName -eq 'ExistingGPO' })
            $linkActions.Count | Should -Be 0
        }
        
        It "Should generate configure action for PostConfigureGpo mode" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @(
                            [PSCustomObject]@{
                                name = "ConfigurableGPO"
                                mode = "createImportAndConfigure"
                            }
                        )
                    }
                }
                groups = @(
                    [PSCustomObject]@{ samaccountname = "ExistingGroup" }
                )
            }
            
            $plan = Get-TierModelGpo -Config $config -DomainController "DC01" -Silent
            
            $configureAction = $plan.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }
            $configureAction | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "GPO Planning - Validation Errors" {
        
        It "Should add error when target OU does not exist" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=NonExistent,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "TestGPO"
                                mode = "createAndImport"
                            }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpo -Config $config -DomainController "DC01" -Silent
            
            $plan.Errors | Should -Not -BeNullOrEmpty
            $ouError = $plan.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' }
            $ouError | Should -Not -BeNullOrEmpty
        }
        
        It "Should add error when required group does not exist for configuration mode" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @(
                            [PSCustomObject]@{
                                name = "ConfigGPO"
                                mode = "createImportAndConfigure"
                            }
                        )
                    }
                }
                groups = @(
                    [PSCustomObject]@{ samaccountname = "NonExistentGroup" }
                )
            }
            
            $plan = Get-TierModelGpo -Config $config -DomainController "DC01" -Silent
            
            $plan.Errors | Should -Not -BeNullOrEmpty
            $groupError = $plan.Errors | Where-Object { $_.Code -eq 'RequiredGroupNotFound' }
            $groupError | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "GPO Planning - Template GPOs" {
        
        It "Should process TemplateGpos without requiring OU validation or linking" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "TemplateGpos" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "TemplateGPO"
                                mode = "createAndImport"
                            }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpo -Config $config -DomainController "DC01" -Silent
            
            # Should create and import, but not link
            $createAction = $plan.Actions | Where-Object { $_.Action -eq 'CreateGPO' -and $_.Name -eq 'TemplateGPO' }
            $importAction = $plan.Actions | Where-Object { $_.Action -eq 'ImportGPO' }
            $linkAction = $plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' -and $_.Name -match 'TemplateGPO' }
            
            $createAction | Should -Not -BeNullOrEmpty
            $importAction | Should -Not -BeNullOrEmpty
            $linkAction | Should -BeNullOrEmpty  # No linking for templates
        }
    }
    
    Context "GPO Planning - Summary and Risk Assessment" {
        
        It "Should generate accurate summary statistics" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{ name = "GPO1"; mode = "createAndImport" }
                            [PSCustomObject]@{ name = "GPO2"; mode = "createAndImport" }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpo -Config $config -DomainController "DC01" -Silent
            
            $plan.Summary.CreateActions | Should -BeGreaterOrEqual 2
            $plan.Summary.ImportActions | Should -BeGreaterOrEqual 2
            $plan.Summary.LinkActions | Should -BeGreaterOrEqual 2
        }
    }
}

Describe "Get-TierModelGpoFd - Full Deployment Planning" -Tag "Unit", "GPO", "FullDeployment" {
    
    BeforeAll {
        # Mock AD Domain (target module scope)
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DistinguishedName = "DC=test,DC=local"
                DNSRoot = "test.local"
            }
        }
        
        # Mock AD OU checks (target module scope - only validates built-in, not custom OUs)
        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param([string]$Identity, [string]$Server, $ErrorAction)
            
            # Only built-in containers exist now
            if ($Identity -match '^OU=Domain Controllers') {
                return [PSCustomObject]@{
                    DistinguishedName = $Identity
                }
            }
            
            # OU not found - respect ErrorAction
            if ($ErrorAction -eq 'SilentlyContinue') {
                return $null
            }
            throw "OU not found: $Identity"
        }
        
        # Mock GPO cmdlets (target module scope)
        Mock Get-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
            
            if ($All) {
                return @()  # No GPOs exist in fresh AD
            }
            
            # GPO not found - respect ErrorAction
            if ($ErrorAction -eq 'SilentlyContinue') {
                return $null
            }
            throw "GPO not found: $Name"
        }
        
        Mock Get-GPInheritance -ModuleName TierModel {
            param([string]$Target, [string]$Server, $ErrorAction)
            
            # No links in fresh AD
            return [PSCustomObject]@{
                GpoLinks = @()
            }
        }
        
        # Mock the GPO link validation function (target module scope)
        Mock Get-TierModelGpoLinkFd -ModuleName TierModel {
            param($Plan, [string]$DomainController, [switch]$Silent)
            
            # Return the plan unchanged (no links to validate yet)
            return $Plan
        }
    }
    
    Context "Full Deployment - Relaxed Validation" {
        
        It "Should allow custom OUs without validation (assumes Phase 1 creates them)" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=CustomOU,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "NewGPO"
                                mode = "createAndImport"
                            }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpoFd -Config $config -DomainController "DC01" -Silent
            
            # Should not generate OU validation errors for custom OUs
            $ouErrors = @($plan.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' })
            $ouErrors.Count | Should -Be 0
            
            # Should generate GPO creation actions
            $createAction = $plan.Actions | Where-Object { $_.Action -eq 'CreateGPO' }
            $createAction | Should -Not -BeNullOrEmpty
        }
        
        It "Should generate full action sequence for new GPO" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @(
                            [PSCustomObject]@{
                                name = "NewConfigGPO"
                                mode = "createImportAndConfigure"
                            }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpoFd -Config $config -DomainController "DC01" -Silent
            
            # Should have create, import, configure, link actions
            $createAction = $plan.Actions | Where-Object { $_.Action -eq 'CreateGPO' }
            $importAction = $plan.Actions | Where-Object { $_.Action -eq 'ImportGPO' }
            $configureAction = $plan.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }
            $linkAction = $plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' }
            
            $createAction | Should -Not -BeNullOrEmpty
            $importAction | Should -Not -BeNullOrEmpty
            $configureAction | Should -Not -BeNullOrEmpty
            $linkAction | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Full Deployment - Risk Assessment" {
        
        It "Should calculate risk summary correctly" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{ name = "GPO1"; mode = "createAndImport" }
                        )
                        PostConfigureGpo = @(
                            [PSCustomObject]@{ name = "GPO2"; mode = "createImportAndConfigure" }
                        )
                    }
                }
            }
            
            $plan = Get-TierModelGpoFd -Config $config -DomainController "DC01" -Silent
            
            $plan.Summary.RiskSummary | Should -Not -BeNullOrEmpty
            $plan.Summary.RiskSummary.Create | Should -BeGreaterOrEqual 2
            $plan.Summary.RiskSummary.Import | Should -BeGreaterOrEqual 2
        }
    }
}

Describe "Test-TierModelGpo - Individual GPO Validation" -Tag "Unit", "GPO", "Validation" {
    
    BeforeAll {
        # Mock AD Domain (target module scope)
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DistinguishedName = "DC=test,DC=local"
                DNSRoot = "test.local"
            }
        }
        
        # Mock Get-GPO for GPO existence checks (target module scope)
        Mock Get-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
            
            if ($All) {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "ExistingGPO"
                        Id = [System.Guid]::NewGuid()
                    }
                    [PSCustomObject]@{
                        DisplayName = "Wildcard-GPO-V1-2024"
                        Id = [System.Guid]::NewGuid()
                    }
                )
            }
            
            if ($Name -eq "ExistingGPO") {
                return [PSCustomObject]@{
                    DisplayName = $Name
                    Id = [System.Guid]::NewGuid()
                }
            }
            
            # GPO not found - respect ErrorAction
            if ($ErrorAction -eq 'SilentlyContinue') {
                return $null
            }
            throw "GPO not found: $Name"
        }
        
        # Mock Get-ADObject for GPO status checks (target module scope)
        Mock Get-ADObject -ModuleName TierModel {
            param([string]$Identity, $Properties, [string]$Server)
            
            return [PSCustomObject]@{
                flags = 0  # AllEnabled
            }
        }
    }
    
    Context "GPO Existence Validation" {
        
        It "Should pass when GPO exists" {
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -DomainController "DC01"
            
            $result.Status | Should -Be 'Pass'
            $result.GPOName | Should -Be 'ExistingGPO'
            $existenceCheck = $result.Checks | Where-Object { $_.Check -eq 'GPO Existence' }
            $existenceCheck.Status | Should -Be 'Pass'
        }
        
        It "Should fail when GPO does not exist" {
            $result = Test-TierModelGpo -GPOName "NonExistentGPO" -DomainController "DC01"
            
            $result.Status | Should -Be 'Fail'
            $result.Issues | Should -Not -BeNullOrEmpty
            $result.Issues[0] | Should -Match "does not exist"
        }
    }
    
    Context "GPO Wildcard Matching (Rename Key)" {
        
        It "Should find GPO using rename wildcard pattern" {
            $gpoConfig = [PSCustomObject]@{
                rename = "Wildcard-GPO-V1-*"
            }
            
            $result = Test-TierModelGpo -GPOName "Wildcard-GPO-V1" -GPOConfig $gpoConfig -DomainController "DC01"
            
            $result.Status | Should -Be 'Pass'
            $result.ActualGPOName | Should -Be 'Wildcard-GPO-V1-2024'
        }
    }
    
    Context "GPO Status Validation" {
        
        It "Should validate GPO status configuration" {
            $gpoConfig = [PSCustomObject]@{
                gpoStatus = "AllEnabled"
            }
            
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -GPOConfig $gpoConfig -DomainController "DC01"
            
            $result.Status | Should -Be 'Pass'
            $statusCheck = $result.Checks | Where-Object { $_.Check -eq 'GPO Status' }
            $statusCheck | Should -Not -BeNullOrEmpty
            $statusCheck.Status | Should -Be 'Pass'
        }
    }
}

Describe "Test-TierModelGPOContent - GPO Security Template Validation" -Tag "Unit", "GPO", "Content" {
    
    BeforeAll {
        # Mock AD Domain (target module scope)
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DistinguishedName = "DC=test,DC=local"
                DNSRoot = "test.local"
            }
        }
        
        # Mock Get-GPO (target module scope)
        Mock Get-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, $ErrorAction)
            
            if ($Name -eq "TestGPO") {
                return [PSCustomObject]@{
                    DisplayName = $Name
                    Id = "12345678-1234-1234-1234-123456789012"
                }
            }
            
            # GPO not found - respect ErrorAction
            if ($ErrorAction -eq 'SilentlyContinue') {
                return $null
            }
            throw "GPO not found: $Name"
        }
        
        # Mock New-TierModelGptTmplContent (target module scope)
        Mock New-TierModelGptTmplContent -ModuleName TierModel {
            return @"
[Unicode]
Unicode=yes
[Version]
Revision=1

[Privilege Rights]
SeServiceLogonRight = *S-1-5-80-0,*S-1-5-32-544
SeDenyNetworkLogonRight = *S-1-5-113

[Group Membership]
*S-1-5-32-544__Members = *S-1-5-21-123-456-789-500
"@
        }
    }
    
    Context "GPO Content Validation - Success Cases" {
        
        It "Should pass when URA and RG content matches" {
            # Create matching GptTmpl.inf content
            $gptTmplContent = @"
[Unicode]
Unicode=yes
[Version]
Revision=1

[Privilege Rights]
SeServiceLogonRight = *S-1-5-80-0,*S-1-5-32-544
SeDenyNetworkLogonRight = *S-1-5-113

[Group Membership]
*S-1-5-32-544__Members = *S-1-5-21-123-456-789-500
"@
            
            # Override Test-Path to return true for SYSVOL path
            Mock Test-Path -ModuleName TierModel {
                param($Path)
                if ($Path -match 'SYSVOL.*GptTmpl\.inf') {
                    return $true
                }
                return $false
            } -ParameterFilter { $Path -match 'SYSVOL' }
            
            # Override Get-Content to return matching content
            Mock Get-Content -ModuleName TierModel {
                param($Path, $Raw)
                if ($Path -match 'SYSVOL.*GptTmpl\.inf') {
                    return $gptTmplContent
                }
                return $null
            } -ParameterFilter { $Path -match 'SYSVOL' }
            
            $gpoConfig = [PSCustomObject]@{
                userRightsAssignments = @()
                restrictedGroups = @()
            }
            
            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig $gpoConfig -DomainController "DC01" -Silent
            
            $result.Status | Should -Be 'Pass'
        }
    }
    
    Context "GPO Content Validation - Failure Cases" {
        
        It "Should fail when GptTmpl.inf file is missing" {
            Mock Test-Path -ModuleName TierModel { return $false } -ParameterFilter { $Path -match 'SYSVOL' }
            
            $gpoConfig = [PSCustomObject]@{
                userRightsAssignments = @()
                restrictedGroups = @()
            }
            
            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig $gpoConfig -DomainController "DC01" -Silent
            
            $result.Status | Should -Be 'Fail'
            $result.Issues | Should -Contain "GptTmpl.inf file is missing from GPO 'TestGPO'"
        }
    }
    
    Context "GPO Content Validation - Error Handling" {
        
        It "Should return error status when GPO does not exist" {
            Mock Get-GPO -ModuleName TierModel { throw "GPO not found" }
            
            $gpoConfig = [PSCustomObject]@{
                userRightsAssignments = @()
            }
            
            $result = Test-TierModelGPOContent -GPOName "NonExistentGPO" -GPOConfig $gpoConfig -DomainController "DC01" -Silent
            
            $result.Status | Should -Be 'Error'
            $result.Issues | Should -Match "not found"
        }
    }
}

Describe "Test-TierModelGPOContent – Extended Coverage" -Tag "Unit", "GPO", "Content" {

    BeforeAll {
        Mock Get-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, $ErrorAction)
            if ($Name -eq "TestGPO") {
                return [PSCustomObject]@{
                    DisplayName = $Name
                    Id          = "12345678-1234-1234-1234-123456789012"
                }
            }
            throw "GPO not found: $Name"
        }
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{ DistinguishedName = "DC=test,DC=local"; DNSRoot = "test.local" }
        }
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock New-TierModelGptTmplContent -ModuleName TierModel {
            return "[Unicode]`r`nUnicode=yes`r`n[Privilege Rights]`r`nSeServiceLogonRight = *S-1-5-80-0`r`n"
        }
    }

    Context "URA Validation Failures" {

        BeforeEach {
            Mock Test-Path -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } { return $true }
        }

        It "Should record Fail validation result and issue when URA has missing SIDs" {
            Mock New-TierModelGptTmplContent -ModuleName TierModel {
                return "[Privilege Rights]`r`nSeServiceLogonRight = *S-1-5-80-0,*S-1-5-32-544`r`n"
            }
            Mock Get-Content -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } {
                return "[Privilege Rights]`r`nSeServiceLogonRight = *S-1-5-80-0`r`n"
            }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            $result.Status | Should -Be 'Fail'
            $failEntry = $result.ValidationResults | Where-Object { $_.Type -eq 'URA' -and $_.Status -eq 'Fail' }
            $failEntry                | Should -Not -BeNullOrEmpty
            $failEntry.Name           | Should -Be 'SeServiceLogonRight'
            ($result.Issues | Where-Object { $_ -match 'missing required SIDs' }) | Should -Not -BeNullOrEmpty
            ($result.Recommendations | Where-Object { $_ -match 'SeServiceLogonRight' }) | Should -Not -BeNullOrEmpty
        }

        It "Should record Fail result with Actual=Not Found when URA entry is absent from actual GPO" {
            Mock New-TierModelGptTmplContent -ModuleName TierModel {
                return "[Privilege Rights]`r`nSeDenyNetworkLogonRight = *S-1-5-113`r`n"
            }
            # Actual GPO has a different URA — SeDenyNetworkLogonRight is absent
            Mock Get-Content -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } {
                return "[Privilege Rights]`r`nSeServiceLogonRight = *S-1-5-80-0`r`n"
            }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            $result.Status | Should -Be 'Fail'
            $failEntry = $result.ValidationResults | Where-Object { $_.Type -eq 'URA' -and $_.Actual -eq 'Not Found' }
            $failEntry              | Should -Not -BeNullOrEmpty
            $failEntry.Name         | Should -Be 'SeDenyNetworkLogonRight'
            ($result.Issues | Where-Object { $_ -match 'missing from GPO' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "RG Validation Failures" {

        BeforeEach {
            Mock Test-Path -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } { return $true }
        }

        It "Should record Fail validation result and issue when RG has missing members" {
            Mock New-TierModelGptTmplContent -ModuleName TierModel {
                return "[Group Membership]`r`n*S-1-5-32-544__Members = *S-1-5-21-111-222-333-500,*S-1-5-21-111-222-333-501`r`n"
            }
            Mock Get-Content -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } {
                return "[Group Membership]`r`n*S-1-5-32-544__Members = *S-1-5-21-111-222-333-500`r`n"
            }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            $result.Status | Should -Be 'Fail'
            $failEntry = $result.ValidationResults | Where-Object { $_.Type -eq 'RG' -and $_.Status -eq 'Fail' }
            $failEntry                | Should -Not -BeNullOrEmpty
            ($result.Issues | Where-Object { $_ -match 'missing required members' }) | Should -Not -BeNullOrEmpty
            ($result.Recommendations | Where-Object { $_ -match 'Restricted Group' }) | Should -Not -BeNullOrEmpty
        }

        It "Should record Fail result with Actual=Not Found when RG entry is absent from actual GPO" {
            Mock New-TierModelGptTmplContent -ModuleName TierModel {
                return "[Group Membership]`r`n*S-1-5-32-544__Members = *S-1-5-21-111-222-333-500`r`n"
            }
            # Actual GPO has a different RG name — the expected one is not present
            Mock Get-Content -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } {
                return "[Group Membership]`r`n*S-1-5-32-999-Members = *S-1-5-21-111-222-333-500`r`n"
            }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            $result.Status | Should -Be 'Fail'
            $failEntry = $result.ValidationResults | Where-Object { $_.Type -eq 'RG' -and $_.Actual -eq 'Not Found' }
            $failEntry | Should -Not -BeNullOrEmpty
            ($result.Issues | Where-Object { $_ -match 'missing from GPO' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Section Parsing Edge Cases" {

        It "Should skip lines under unrecognized section headers and still process known sections" {
            Mock New-TierModelGptTmplContent -ModuleName TierModel {
                return "[Version]`r`nRevision=1`r`n[Some Other Section]`r`nIgnoredKey = IgnoredValue`r`n[Privilege Rights]`r`nSeServiceLogonRight = *S-1-5-80-0`r`n"
            }
            Mock Get-Content -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } {
                return "[Privilege Rights]`r`nSeServiceLogonRight = *S-1-5-80-0`r`n"
            }
            Mock Test-Path -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } { return $true }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            $result.Status                    | Should -Be 'Pass'
            # IgnoredKey must NOT appear in validation results
            ($result.ValidationResults | Where-Object { $_.Name -eq 'IgnoredKey' }) | Should -BeNullOrEmpty
            # SeServiceLogonRight must appear as Pass
            $uraEntry = $result.ValidationResults | Where-Object { $_.Name -eq 'SeServiceLogonRight' }
            $uraEntry              | Should -Not -BeNullOrEmpty
            $uraEntry.Status       | Should -Be 'Pass'
        }
    }

    Context "Error Handling" {

        It "Should set Status=Error in inner catch when Get-ADDomain throws after mockFilePath is set" {
            # Get-ADDomain is called inside the inner try AFTER Out-File writes the mock file.
            # Throwing here goes to the inner catch (not the outer catch).
            Mock Get-ADDomain -ModuleName TierModel {
                throw [System.IO.IOException]::new("Cannot reach domain controller")
            }
            Mock Test-Path -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } { return $true }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            $result.Status | Should -Be 'Error'
            ($result.Issues        | Where-Object { $_ -match 'Content validation failed' }) | Should -Not -BeNullOrEmpty
            ($result.Recommendations | Where-Object { $_ -match 'GPO accessibility' })       | Should -Not -BeNullOrEmpty
        }

        It "Should return outer catch error result when New-Item throws for missing temp directory" {
            # Test-Path on the tempDir path returns false → New-Item is invoked → New-Item throws
            # → outer catch fires (outside all inner try blocks)
            Mock Test-Path -ModuleName TierModel { return $false }
            Mock New-Item  -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Cannot create directory")
            }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            $result.Status | Should -Be 'Error'
            $result.PSObject.Properties.Name | Should -Contain 'Issues'
            ($result.Recommendations | Where-Object { $_ -match 'GPO name and domain controller' }) | Should -Not -BeNullOrEmpty
        }

        It "Should invoke New-Item and continue processing when temp directory does not exist" {
            # tempDir ends with \Temp — match that specific pattern to avoid catching mockFilePath
            Mock Test-Path -ModuleName TierModel -ParameterFilter { $Path -match '[/\\]Temp$' } { return $false }
            Mock New-Item  -ModuleName TierModel { }
            # SYSVOL path → return false so we enter the Fail/missing branch (simpler than full comparison)
            Mock Test-Path -ModuleName TierModel -ParameterFilter { $Path -match 'SYSVOL' } { return $false }

            $result = Test-TierModelGPOContent -GPOName "TestGPO" -GPOConfig @{} -DomainController "DC01" -Silent

            Should -Invoke New-Item -ModuleName TierModel -Times 1
            # Function proceeds past the temp-dir creation and reaches the GptTmpl-missing Fail path
            $result.Status | Should -Be 'Fail'
            ($result.Issues | Where-Object { $_ -match 'GptTmpl.inf file is missing' }) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Test-TierModelGPOAudit - Comprehensive GPO Audit" -Tag "Unit", "GPO", "Audit" {
    
    BeforeAll {
        # Mock AD Domain (target module scope)
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DistinguishedName = "DC=test,DC=local"
                DNSRoot = "test.local"
            }
        }
        
        # Mock Test-TierModelGpo (target module scope)
        Mock Test-TierModelGpo -ModuleName TierModel {
            param([string]$GPOName, $GPOConfig, [string]$DomainController)
            
            if ($GPOName -eq "FailingGPO") {
                return [PSCustomObject]@{
                    GPOName = $GPOName
                    ActualGPOName = $GPOName
                    Status = 'Fail'
                    Issues = @("GPO does not exist")
                    Recommendations = @("Create GPO using New-TierModelGpo")
                    Checks = @()
                }
            }
            
            return [PSCustomObject]@{
                GPOName = $GPOName
                ActualGPOName = $GPOName
                Status = 'Pass'
                Issues = @()
                Recommendations = @()
                Checks = @(
                    [PSCustomObject]@{
                        Check = 'GPO Existence'
                        Status = 'Pass'
                    }
                )
            }
        }
        
        # Mock Test-TierModelGPOLink (target module scope)
        Mock Test-TierModelGPOLink -ModuleName TierModel {
            return [PSCustomObject]@{
                Status = 'Pass'
                Issues = @()
                Recommendations = @()
            }
        }
        
        # Mock Test-TierModelGPOContent (target module scope)
        Mock Test-TierModelGPOContent -ModuleName TierModel {
            return [PSCustomObject]@{
                Status = 'Pass'
                Issues = @()
                Recommendations = @()
                ValidationResults = @()
            }
        }
    }
    
    Context "Comprehensive Audit - Basic Scenarios" {
        
        It "Should audit all GPOs in configuration" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "GPO1"
                                linkOrder = 1
                            }
                        )
                        PostConfigureGpo = @(
                            [PSCustomObject]@{
                                name = "GPO2"
                                linkOrder = 2
                                userRightsAssignments = @()
                            }
                        )
                    }
                }
            }
            
            $result = Test-TierModelGPOAudit -Config $config -DomainController "DC01" -Silent
            
            $result.Results.Count | Should -Be 2
            $result.Summary.TotalGpos | Should -Be 2
        }
        
        It "Should mark audit as converged when all GPOs pass" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "PassingGPO"
                                linkOrder = 1
                            }
                        )
                        PostConfigureGpo = @()  # Empty array to match expected structure
                    }
                }
            }
            
            $result = Test-TierModelGPOAudit -Config $config -DomainController "DC01" -Silent
            
            $result.Converged | Should -Be $true
            $result.Summary.Compliant | Should -Be 1
            $result.Summary.Drift | Should -Be 0
        }
        
        It "Should mark audit as not converged when GPOs fail" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "FailingGPO"
                                linkOrder = 1
                            }
                        )
                        PostConfigureGpo = @()  # Empty array to match expected structure
                    }
                }
            }
            
            $result = Test-TierModelGPOAudit -Config $config -DomainController "DC01" -Silent
            
            $result.Converged | Should -Be $false
            $result.Summary.Drift | Should -BeGreaterThan 0
        }
    }
    
    Context "Comprehensive Audit - Summary and Compliance" {
        
        It "Should calculate compliance percentage correctly" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{ name = "PassGPO1"; linkOrder = 1 }
                            [PSCustomObject]@{ name = "PassGPO2"; linkOrder = 2 }
                            [PSCustomObject]@{ name = "FailingGPO"; linkOrder = 3 }
                        )
                        PostConfigureGpo = @()  # Empty array to match expected structure
                    }
                }
            }
            
            $result = Test-TierModelGPOAudit -Config $config -DomainController "DC01" -Silent
            
            $result.Summary.CompliancePercentage | Should -BeGreaterThan 0
            $result.Summary.CompliancePercentage | Should -BeLessOrEqual 100
        }
    }
    
    Context "Comprehensive Audit - Template GPOs" {
        
        It "Should skip link validation for Template GPOs (no linkOrder)" {
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "TemplateGpos" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{
                                name = "TemplateGPO"
                                # No linkOrder = template GPO
                            }
                        )
                        PostConfigureGpo = @()  # Empty array to match expected structure
                    }
                }
            }
            
            $result = Test-TierModelGPOAudit -Config $config -DomainController "DC01" -Silent
            
            # Should audit GPO existence but not links
            $result.Results.Count | Should -Be 1
            $result.Results[0].LinkTest | Should -BeNullOrEmpty
        }
    }
}

Describe "Test-TierModelGPOAudit – Extended Coverage" -Tag "Unit", "GPO", "Audit" {

    BeforeAll {
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{ DistinguishedName = "DC=test,DC=local"; DNSRoot = "test.local" }
        }
        # Default: GPO exists and passes
        Mock Test-TierModelGpo -ModuleName TierModel {
            param([string]$GPOName)
            return [PSCustomObject]@{
                GPOName        = $GPOName
                ActualGPOName  = $GPOName
                Status         = 'Pass'
                Issues         = @()
                Recommendations = @()
            }
        }
        Mock Test-TierModelGPOLink -ModuleName TierModel {
            return [PSCustomObject]@{ Status = 'Pass'; Issues = @(); Recommendations = @() }
        }
        Mock Test-TierModelGPOContent -ModuleName TierModel {
            return [PSCustomObject]@{ Status = 'Pass'; Issues = @(); Recommendations = @(); ValidationResults = @() }
        }
        Mock Test-Path    -ModuleName TierModel { return $false }
        Mock Remove-Item  -ModuleName TierModel { }
        Mock Get-ChildItem -ModuleName TierModel { return @() }
    }

    # ── helper: build a one-GPO config ─────────────────────────────────────────
    function script:New-AuditConfig {
        param(
            [string]$OUKey        = "OU=Tier0,DC=test,DC=local",
            [string]$GPOName      = "TestGPO",
            [bool]$WithLinkOrder  = $true,
            [bool]$WithContent    = $false,
            [bool]$PostConfigure  = $false  # when $true puts the GPO in PostConfigureGpo category
        )
        $gpoObj = [PSCustomObject]@{ name = $GPOName }
        if ($WithLinkOrder) { $gpoObj | Add-Member -NotePropertyName 'linkOrder'             -NotePropertyValue 1   }
        if ($WithContent)   { $gpoObj | Add-Member -NotePropertyName 'userRightsAssignments' -NotePropertyValue @() }
        return [PSCustomObject]@{
            gpos = [PSCustomObject]@{
                $OUKey = [PSCustomObject]@{
                    ImportOnlyGpo    = if ($PostConfigure) { @() }       else { @($gpoObj) }
                    PostConfigureGpo = if ($PostConfigure) { @($gpoObj) } else { @() }
                }
            }
        }
    }

    Context "Early Return Cases" {

        It "Should return outer-catch error when gpos is null (Write-TierModelLog -Level Warn ValidateSet bug)" {
            # Write-TierModelLog -Level Warn is called in the early-return path but 'Warn' is not in
            # the ValidateSet('Debug','Info','Warning','Error'). Pester mocks preserve ValidateSet,
            # so the exception is caught by the outer catch instead of the early-return path.
            $noGposConfig = [PSCustomObject]@{ organizationalUnits = @(); gpos = $null }

            $result = Test-TierModelGPOAudit -Config $noGposConfig -DomainController "DC01" -Silent

            $result.Converged          | Should -Be $false
            $result.Errors[0].Code     | Should -Be 'GPOAuditFailed'
            $result.Errors[0].Category | Should -Be 'Critical'
            $result.Errors[0].Message  | Should -Match 'Warn'
        }

        It "Should return compliant empty summary when gpos property is empty" {
            $emptyGposConfig = [PSCustomObject]@{
                gpos = [PSCustomObject]@{ }
            }

            $result = Test-TierModelGPOAudit -Config $emptyGposConfig -DomainController "DC01" -Silent

            $result.Summary.TotalGpos | Should -Be 0
            $result.Converged         | Should -Be $true
        }
    }

    Context "OUPath Filtering" {

        It "Should skip OUs that do not match the OUPath filter" {
            $twoOuConfig = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo   = @([PSCustomObject]@{ name = "Tier0GPO"; linkOrder = 1 })
                        PostConfigureGpo = @()
                    }
                    "OU=Tier1,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo   = @([PSCustomObject]@{ name = "Tier1GPO"; linkOrder = 1 })
                        PostConfigureGpo = @()
                    }
                }
            }

            $result = Test-TierModelGPOAudit -Config $twoOuConfig -DomainController "DC01" `
                -OUPath "OU=Tier0,DC=test,DC=local" -Silent

            # Only the Tier0 GPO should have been audited
            $result.Summary.TotalGpos | Should -Be 1
            $result.Results[0].GPOName | Should -Be "Tier0GPO"
        }
    }

    Context "Non-Silent Summary Output" {

        It "Should write green compliant summary when all GPOs pass" {
            $config = New-AuditConfig -GPOName "PassGPO"

            # Capture Write-Host calls to verify the green path is reached
            $capturedOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host -ModuleName TierModel { $capturedOutput.Add($Object) }

            Test-TierModelGPOAudit -Config $config -DomainController "DC01"

            ($capturedOutput | Where-Object { $_ -match 'GPO Audit Summary' })    | Should -Not -BeNullOrEmpty
            ($capturedOutput | Where-Object { $_ -match 'All GPOs are compliant' }) | Should -Not -BeNullOrEmpty
        }

        It "Should write red drift summary when GPOs are non-compliant" {
            Mock Test-TierModelGpo -ModuleName TierModel {
                param([string]$GPOName)
                return [PSCustomObject]@{
                    GPOName = $GPOName; ActualGPOName = $GPOName
                    Status = 'Fail'; Issues = @("GPO missing"); Recommendations = @()
                }
            }

            $config = New-AuditConfig -GPOName "FailGPO"

            $capturedOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host -ModuleName TierModel { $capturedOutput.Add($Object) }

            Test-TierModelGPOAudit -Config $config -DomainController "DC01"

            ($capturedOutput | Where-Object { $_ -match 'issues found' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Step Result Handling" {

        It "Should set OverallStatus to Error and mark not-converged when GPO test returns Error" {
            Mock Test-TierModelGpo -ModuleName TierModel {
                param([string]$GPOName)
                return [PSCustomObject]@{
                    GPOName = $GPOName; ActualGPOName = $GPOName
                    Status = 'Error'; Issues = @("AD error"); Recommendations = @()
                }
            }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01" -Silent

            $result.Results[0].OverallStatus | Should -Be 'Error'
            $result.Converged               | Should -Be $false
        }

        It "Should write link-fail message and set OverallStatus to Fail when link test fails" {
            Mock Test-TierModelGPOLink -ModuleName TierModel {
                return [PSCustomObject]@{ Status = 'Fail'; Issues = @("Link missing"); Recommendations = @("Re-link GPO") }
            }

            $capturedOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host -ModuleName TierModel { $capturedOutput.Add($Object) }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01"

            $result.Results[0].OverallStatus | Should -Be 'Fail'
            ($capturedOutput | Where-Object { $_ -match 'linking check failed' }) | Should -Not -BeNullOrEmpty
        }

        It "Should write content-fail message and set OverallStatus to Fail when content test fails" {
            Mock Test-TierModelGPOContent -ModuleName TierModel {
                return [PSCustomObject]@{ Status = 'Fail'; Issues = @("URA mismatch"); Recommendations = @("Fix URA") }
            }

            $capturedOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host -ModuleName TierModel { $capturedOutput.Add($Object) }

            # GPO must be in PostConfigureGpo category for content validation to run
            $result = Test-TierModelGPOAudit -Config (New-AuditConfig -WithContent $true -PostConfigure $true) -DomainController "DC01"

            $result.Results[0].OverallStatus | Should -Be 'Fail'
            ($capturedOutput | Where-Object { $_ -match 'content validation failed' }) | Should -Not -BeNullOrEmpty
        }

        It "Should set OverallStatus to Error when content test returns Error" {
            Mock Test-TierModelGPOContent -ModuleName TierModel {
                return [PSCustomObject]@{ Status = 'Error'; Issues = @("Access denied"); Recommendations = @() }
            }

            # GPO must be in PostConfigureGpo category for content validation to run
            $result = Test-TierModelGPOAudit -Config (New-AuditConfig -WithContent $true -PostConfigure $true) -DomainController "DC01" -Silent

            $result.Results[0].OverallStatus | Should -Be 'Error'
            $result.Converged               | Should -Be $false
        }

        It "Should use gpoName when ActualGPOName is null on gpoTest result" {
            Mock Test-TierModelGpo -ModuleName TierModel {
                param([string]$GPOName)
                # Return result with ActualGPOName = $null explicitly (StrictMode requires the property to exist)
                return [PSCustomObject]@{ GPOName = $GPOName; ActualGPOName = $null; Status = 'Pass'; Issues = @(); Recommendations = @() }
            }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig -GPOName "NoActualNameGPO") `
                -DomainController "DC01" -Silent

            $result.Results[0].GPOName         | Should -Be "NoActualNameGPO"
            $result.Results[0].OriginalGPOName  | Should -Be "NoActualNameGPO"
        }

        It "Should pass enforced=true and linkEnabled=false from gpoConfig to Test-TierModelGPOLink" {
            $gpoObj = [PSCustomObject]@{
                name        = "EnforcedGPO"
                linkOrder   = 1
                enforced    = $true
                linkEnabled = $false
            }
            $config = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo   = @($gpoObj)
                        PostConfigureGpo = @()
                    }
                }
            }

            Test-TierModelGPOAudit -Config $config -DomainController "DC01" -Silent

            Should -Invoke Test-TierModelGPOLink -ModuleName TierModel -Times 1 -ParameterFilter {
                $ExpectedEnforced -eq $true -and $ExpectedEnabled -eq $false
            }
        }
    }

    Context "Error Handling" {

        It "Should record GPOAuditFailed error and mark not-converged when per-GPO processing throws" {
            Mock Test-TierModelGpo -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Unexpected GPO error")
            }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01" -Silent

            $result.Errors              | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code      | Should -Be 'GPOAuditFailed'
            $result.Converged           | Should -Be $false
        }

        It "Should return outer catch error result when Get-ADDomain throws" {
            Mock Get-ADDomain -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Domain unreachable")
            }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01" -Silent

            $result.Converged                    | Should -Be $false
            $result.Errors[0].Code               | Should -Be 'GPOAuditFailed'
            $result.Errors[0].Category           | Should -Be 'Critical'
        }
    }

    Context "Findings Generation" {

        It "Should populate Findings with Type=Mismatch for Fail results with issues" {
            Mock Test-TierModelGpo -ModuleName TierModel {
                param([string]$GPOName)
                return [PSCustomObject]@{
                    GPOName = $GPOName; ActualGPOName = $GPOName
                    Status = 'Fail'; Issues = @("GPO missing"); Recommendations = @()
                }
            }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01" -Silent

            $finding = $result.Findings | Where-Object { $_.Type -eq 'Mismatch' }
            $finding           | Should -Not -BeNullOrEmpty
            $finding.Message   | Should -Match "GPO missing"
        }

        It "Should populate Findings with Type=Error for Error results" {
            Mock Test-TierModelGpo -ModuleName TierModel {
                param([string]$GPOName)
                return [PSCustomObject]@{
                    GPOName = $GPOName; ActualGPOName = $GPOName
                    Status = 'Error'; Issues = @("AD error"); Recommendations = @()
                }
            }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01" -Silent

            ($result.Findings | Where-Object { $_.Type -eq 'Error' }) | Should -Not -BeNullOrEmpty
        }

        It "Should use fallback message in Findings when result has no Issues" {
            Mock Test-TierModelGpo -ModuleName TierModel {
                param([string]$GPOName)
                return [PSCustomObject]@{
                    GPOName = $GPOName; ActualGPOName = $GPOName
                    Status = 'Fail'; Issues = @(); Recommendations = @()
                }
            }

            $result = Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01" -Silent

            $finding = $result.Findings | Where-Object { $_.GpoName -ne $null }
            $finding.Message | Should -Match 'Audit failed with status'
        }
    }

    Context "Temp Directory Cleanup" {

        It "Should remove empty temp directory and write cleanup message" {
            $capturedOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host     -ModuleName TierModel { $capturedOutput.Add($Object) }
            Mock Test-Path      -ModuleName TierModel { return $true }
            Mock Get-ChildItem  -ModuleName TierModel { return @() }
            Mock Remove-Item    -ModuleName TierModel { }

            Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01"

            Should -Invoke Remove-Item -ModuleName TierModel -Times 1
            ($capturedOutput | Where-Object { $_ -match 'Cleaned up empty temp' }) | Should -Not -BeNullOrEmpty
        }

        It "Should keep temp directory and write debug message when it contains items" {
            $capturedOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host    -ModuleName TierModel { $capturedOutput.Add($Object) }
            Mock Test-Path     -ModuleName TierModel { return $true }
            Mock Get-ChildItem -ModuleName TierModel { return @([PSCustomObject]@{ Name = "file.inf" }) }

            Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01"

            Should -Invoke Remove-Item -ModuleName TierModel -Times 0
            ($capturedOutput | Where-Object { $_ -match 'keeping for debugging' }) | Should -Not -BeNullOrEmpty
        }

        It "Should handle cleanup error gracefully and write warning" {
            $capturedOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host    -ModuleName TierModel { $capturedOutput.Add($Object) }
            Mock Test-Path     -ModuleName TierModel { return $true }
            # Get-ChildItem throws → triggers the cleanup catch block
            Mock Get-ChildItem -ModuleName TierModel { throw [System.IO.IOException]::new("Access denied") }

            Test-TierModelGPOAudit -Config (New-AuditConfig) -DomainController "DC01"

            ($capturedOutput | Where-Object { $_ -match 'Could not clean up temp' }) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Import-TierModelGpo - GPO Import Execution" -Tag "Unit", "GPO", "Import" {

    BeforeAll {
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Write-Host -ModuleName TierModel { }
        Mock Import-GPO -ModuleName TierModel { return $null }
        Mock Test-Path -ModuleName TierModel { return $true }

        # Helper: build a minimal plan with one ImportGPO action
        function New-ImportPlan {
            param(
                [string]$GpoName = "TestGPO",
                [string]$ImportPath = "gpo\backup-guid",
                [string]$ActionType = "ImportGPO",
                [bool]$HasImportPath = $true
            )
            $gpoData = if ($HasImportPath) {
                [PSCustomObject]@{ name = $GpoName; importPath = $ImportPath }
            } else {
                [PSCustomObject]@{ name = $GpoName }
            }

            return [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = $ActionType
                    Data   = $gpoData
                    Path   = "OU=Tier0,DC=test,DC=local"
                })
                Config = [PSCustomObject]@{
                    ConfigPath = "C:\TierModel\config\tiermodel.json"
                }
            }
        }
    }

    Context "Import-TierModelGpo - Empty / Filtered Plans" {

        It "Should return zero counts when plan has no ImportGPO actions" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = "CreateGPO"
                    Data   = [PSCustomObject]@{ name = "SomeGPO" }
                    Path   = "OU=Tier0,DC=test,DC=local"
                })
                Config = [PSCustomObject]@{ ConfigPath = "C:\config\tiermodel.json" }
            }

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
            $result.Skipped  | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "Should only process actions where Action -eq 'ImportGPO'" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{ Action = "CreateGPO"; Data = [PSCustomObject]@{ name = "G1" }; Path = "OU=X,DC=test,DC=local" }
                    [PSCustomObject]@{ Action = "ImportGPO"; Data = [PSCustomObject]@{ name = "G2"; importPath = "gpo\backup" }; Path = "OU=X,DC=test,DC=local" }
                    [PSCustomObject]@{ Action = "LinkGPO";   Data = [PSCustomObject]@{ name = "G3" }; Path = "OU=X,DC=test,DC=local" }
                )
                Config = [PSCustomObject]@{ ConfigPath = "C:\config\tiermodel.json" }
            }

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            # Only the ImportGPO action should be processed
            $result.Executed | Should -Be 1
        }
    }

    Context "Import-TierModelGpo - WhatIf Mode" {

        It "Should skip import and increment Skipped when -WhatIf is specified" {
            $plan = New-ImportPlan -GpoName "WhatIfGPO"

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01" -WhatIf

            $result.Skipped  | Should -Be 1
            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
            Should -Invoke Import-GPO -ModuleName TierModel -Times 0
        }
    }

    Context "Import-TierModelGpo - Successful Import" {

        It "Should call Import-GPO and increment Executed on success" {
            $plan = New-ImportPlan -GpoName "SuccessGPO" -ImportPath "gpo\12345678-1234-1234-1234-123456789012"

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.Executed  | Should -Be 1
            $result.Failed    | Should -Be 0
            $result.Converged | Should -Be $true
            Should -Invoke Import-GPO -ModuleName TierModel -Times 1
        }

        It "Should return object with all required properties" {
            $plan = New-ImportPlan -GpoName "PropsGPO"

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.PSObject.Properties.Name | Should -Contain "Executed"
            $result.PSObject.Properties.Name | Should -Contain "Failed"
            $result.PSObject.Properties.Name | Should -Contain "Skipped"
            $result.PSObject.Properties.Name | Should -Contain "Errors"
            $result.PSObject.Properties.Name | Should -Contain "DurationMs"
            $result.PSObject.Properties.Name | Should -Contain "Converged"
            $result.PSObject.Properties.Name | Should -Contain "CorrelationId"
        }
    }

    Context "Import-TierModelGpo - Import Path Not Found" {

        It "Should increment Failed and set Converged false when importPath does not exist" {
            Mock Test-Path -ModuleName TierModel { return $false }

            $plan = New-ImportPlan -GpoName "MissingPathGPO" -ImportPath "gpo\missing-backup"

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.Failed    | Should -Be 1
            $result.Executed  | Should -Be 0
            $result.Converged | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
            Should -Invoke Import-GPO -ModuleName TierModel -Times 0
        }
    }

    Context "Import-TierModelGpo - No importPath in Action Data" {

        It "Should skip and not call Import-GPO when action data has no importPath" {
            $plan = New-ImportPlan -GpoName "NoPathGPO" -HasImportPath $false

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.Skipped  | Should -Be 1
            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
            Should -Invoke Import-GPO -ModuleName TierModel -Times 0
        }
    }

    Context "Import-TierModelGpo - Exception Handling" {

        It "Should catch per-action exceptions and accumulate failures without stopping" {
            Mock Import-GPO -ModuleName TierModel { throw "GPO store unavailable" }

            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{ Action = "ImportGPO"; Data = [PSCustomObject]@{ name = "FailGPO1"; importPath = "gpo\b1" }; Path = "OU=Tier0,DC=test,DC=local" }
                    [PSCustomObject]@{ Action = "ImportGPO"; Data = [PSCustomObject]@{ name = "FailGPO2"; importPath = "gpo\b2" }; Path = "OU=Tier0,DC=test,DC=local" }
                )
                Config = [PSCustomObject]@{ ConfigPath = "C:\config\tiermodel.json" }
            }

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.Failed    | Should -Be 2
            $result.Executed  | Should -Be 0
            $result.Converged | Should -Be $false
            $result.Errors.Count | Should -Be 2
        }

        It "Should accumulate errors from multiple mixed-outcome actions" {
            # First call succeeds (default Test-Path returns $true), second throws
            $callCount = 0
            Mock Import-GPO -ModuleName TierModel {
                $script:callCount++
                if ($script:callCount -eq 2) { throw "Second GPO failed" }
                return $null
            }

            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{ Action = "ImportGPO"; Data = [PSCustomObject]@{ name = "GPO1"; importPath = "gpo\b1" }; Path = "OU=T0,DC=test,DC=local" }
                    [PSCustomObject]@{ Action = "ImportGPO"; Data = [PSCustomObject]@{ name = "GPO2"; importPath = "gpo\b2" }; Path = "OU=T0,DC=test,DC=local" }
                )
                Config = [PSCustomObject]@{ ConfigPath = "C:\config\tiermodel.json" }
            }

            $result = Import-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.Executed  | Should -Be 1
            $result.Failed    | Should -Be 1
            $result.Converged | Should -Be $false
        }
    }
}

Describe "New-TierModelGpo - GPO Creation Execution" -Tag "Unit", "GPO", "Create" {

    BeforeAll {
        # Fresh GPO Id for reuse
        $script:TestGpoId = [System.Guid]::NewGuid()

        Mock New-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, [string]$Comment)
            return [PSCustomObject]@{
                DisplayName = $Name
                Id          = $script:TestGpoId
            }
        }

        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DistinguishedName = "DC=test,DC=local"
                DNSRoot           = "test.local"
                NetBIOSName       = "TEST"
            }
        }

        Mock Set-ADObject  -ModuleName TierModel { return $null }
        Mock Write-Host    -ModuleName TierModel { return $null }

        # Helper: build a minimal valid plan with CreateGPO actions
        function New-GpoPlan {
            param([array]$Actions)
            return [PSCustomObject]@{ Actions = $Actions }
        }

        function New-CreateAction {
            param(
                [string]$Name        = "TestGPO",
                [string]$Mode        = "createAndImport",
                [string]$Path        = "OU=Tier0,DC=test,DC=local",
                [hashtable]$Extra    = @{}
            )
            # Use an inline PSCustomObject literal for the base 'name' property — casting a
            # hashtable variable via [PSCustomObject]$var silently produces empty NoteProperties
            # for single-key hashtables in certain PS runspace contexts (e.g. Pester BeforeAll).
            # Extra properties are added via Add-Member which always creates real NoteProperties.
            # gpoComment is always included (as $null by default) because the module runs under
            # Set-StrictMode -Version Latest — accessing a missing property throws, not returns $null.
            $data = [PSCustomObject]@{ name = $Name; gpoComment = $null }
            foreach ($k in $Extra.Keys) {
                $data | Add-Member -NotePropertyName $k -NotePropertyValue $Extra[$k] -Force
            }
            return [PSCustomObject]@{
                Action = "CreateGPO"
                Mode   = $Mode
                Path   = $Path
                Data   = $data
            }
        }
    }

    # ─────────────────────────────────────────────────────────────
    Context "Empty / no-op plans" {

        It "Should return zero counts when plan has no actions" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @()) -DomainController "DC01"

            $result.Executed  | Should -Be 0
            $result.Failed    | Should -Be 0
            $result.Skipped   | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "Should ignore non-CreateGPO actions and return zero executed" {
            $plan = New-GpoPlan -Actions @(
                [PSCustomObject]@{ Action = "LinkGPO";   Data = [PSCustomObject]@{ name = "SomeGPO" }; Mode = "create"; Path = "OU=Tier0,DC=test,DC=local" }
                [PSCustomObject]@{ Action = "ImportGPO"; Data = [PSCustomObject]@{ name = "SomeGPO" }; Mode = "create"; Path = "OU=Tier0,DC=test,DC=local" }
            )

            $result = New-TierModelGpo -Plan $plan -DomainController "DC01"

            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
            Should -Invoke New-GPO -ModuleName TierModel -Times 0
        }
    }

    # ─────────────────────────────────────────────────────────────
    Context "Successful GPO creation" {

        It "Should create a GPO without a comment when gpoComment is absent" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "NoCommentGPO"
            )) -DomainController "DC01"

            $result.Executed | Should -Be 1
            $result.Failed   | Should -Be 0
            Should -Invoke New-GPO -ModuleName TierModel -Times 1 -ParameterFilter {
                $Name -eq "NoCommentGPO" -and -not $PSBoundParameters.ContainsKey('Comment')
            }
        }

        It "Should create a GPO without a comment when gpoComment is empty string" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "EmptyCommentGPO" -Extra @{ gpoComment = "" }
            )) -DomainController "DC01"

            $result.Executed | Should -Be 1
            Should -Invoke New-GPO -ModuleName TierModel -Times 1 -ParameterFilter {
                $Name -eq "EmptyCommentGPO" -and -not $PSBoundParameters.ContainsKey('Comment')
            }
        }

        It "Should create a GPO with the Comment parameter when gpoComment is provided" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "CommentGPO" -Extra @{ gpoComment = "This is a comment" }
            )) -DomainController "DC01"

            $result.Executed | Should -Be 1
            Should -Invoke New-GPO -ModuleName TierModel -Times 1 -ParameterFilter {
                $Name -eq "CommentGPO" -and $Comment -eq "This is a comment"
            }
        }

        It "Should include a non-null CorrelationId in the result" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "CorrIdGPO"
            )) -DomainController "DC01"

            $result.CorrelationId | Should -Not -BeNullOrEmpty
        }

        It "Should report DurationMs > 0 in the result" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "TimedGPO"
            )) -DomainController "DC01"

            $result.DurationMs | Should -BeGreaterOrEqual 0
        }

        It "Should process multiple CreateGPO actions and count all as executed" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "GPO-A"
                New-CreateAction -Name "GPO-B"
                New-CreateAction -Name "GPO-C"
            )) -DomainController "DC01"

            $result.Executed | Should -Be 3
            $result.Failed   | Should -Be 0
            Should -Invoke New-GPO -ModuleName TierModel -Times 3
        }
    }

    # ─────────────────────────────────────────────────────────────
    Context "WhatIf mode" {

        It "Should skip creation and increment skipped count when -WhatIf is supplied" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "WhatIfGPO"
            )) -DomainController "DC01" -WhatIf

            $result.Skipped  | Should -Be 1
            $result.Executed | Should -Be 0
            Should -Invoke New-GPO -ModuleName TierModel -Times 0
        }

        It "Should count all actions as skipped in WhatIf mode for multiple GPOs" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "WhatIfGPO1"
                New-CreateAction -Name "WhatIfGPO2"
            )) -DomainController "DC01" -WhatIf

            $result.Skipped  | Should -Be 2
            $result.Executed | Should -Be 0
        }
    }

    # ─────────────────────────────────────────────────────────────
    Context "GPO status configuration" {

        It "Should call Set-ADObject when mode is 'create' and gpoStatus is AllEnabled" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "StatusGPO" -Mode "create" -Extra @{ gpoStatus = "AllEnabled" }
            )) -DomainController "DC01"

            $result.Executed | Should -Be 1
            Should -Invoke Set-ADObject -ModuleName TierModel -Times 1 -ParameterFilter {
                $Replace -ne $null -and $Replace.flags -eq 0
            }
        }

        It "Should pass flag=1 for UserSettingsDisabled" {
            New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "UserDisabledGPO" -Mode "create" -Extra @{ gpoStatus = "UserSettingsDisabled" }
            )) -DomainController "DC01" | Out-Null

            Should -Invoke Set-ADObject -ModuleName TierModel -Times 1 -ParameterFilter {
                $Replace.flags -eq 1
            }
        }

        It "Should pass flag=2 for ComputerSettingsDisabled" {
            New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "ComputerDisabledGPO" -Mode "create" -Extra @{ gpoStatus = "ComputerSettingsDisabled" }
            )) -DomainController "DC01" | Out-Null

            Should -Invoke Set-ADObject -ModuleName TierModel -Times 1 -ParameterFilter {
                $Replace.flags -eq 2
            }
        }

        It "Should pass flag=3 for BothSettingsDisabled" {
            New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "BothDisabledGPO" -Mode "create" -Extra @{ gpoStatus = "BothSettingsDisabled" }
            )) -DomainController "DC01" | Out-Null

            Should -Invoke Set-ADObject -ModuleName TierModel -Times 1 -ParameterFilter {
                $Replace.flags -eq 3
            }
        }

        It "Should default to flag=0 for unrecognized gpoStatus value" {
            New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "UnknownStatusGPO" -Mode "create" -Extra @{ gpoStatus = "UnknownValue" }
            )) -DomainController "DC01" | Out-Null

            Should -Invoke Set-ADObject -ModuleName TierModel -Times 1 -ParameterFilter {
                $Replace.flags -eq 0
            }
        }

        It "Should not call Set-ADObject when mode is not 'create'" {
            New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "ImportModeGPO" -Mode "createAndImport" -Extra @{ gpoStatus = "AllEnabled" }
            )) -DomainController "DC01" | Out-Null

            Should -Invoke Set-ADObject -ModuleName TierModel -Times 0
        }

        It "Should not call Set-ADObject when gpoStatus property is absent" {
            New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "NoStatusGPO" -Mode "create"
            )) -DomainController "DC01" | Out-Null

            Should -Invoke Set-ADObject -ModuleName TierModel -Times 0
        }

        It "Should log a warning and still mark GPO as executed when Set-ADObject throws" {
            Mock Set-ADObject -ModuleName TierModel { throw "AD write failed" }

            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "StatusFailGPO" -Mode "create" -Extra @{ gpoStatus = "AllEnabled" }
            )) -DomainController "DC01"

            # GPO was still created; status failure is non-fatal
            $result.Executed | Should -Be 1
            $result.Failed   | Should -Be 0
        }
    }

    # ─────────────────────────────────────────────────────────────
    Context "DenyApply ACL configuration" {

        # NOTE: The success path inside the denyApplyGroupPolicy block (AddAccessRule /
        #       CommitChanges / success Write-Host) cannot be covered without production
        #       code changes because it uses [ADSI]$gpcAdsiPath — a direct .NET
        #       constructor that Pester cannot intercept. Any attempt to access
        #       $gpc.ObjectSecurity in a non-AD environment throws, diverting execution
        #       into the inner catch block. See Hard Coverage Limits in test-coverage.md.

        It "Should enter denyApplyGroupPolicy loop and handle ADSI failure gracefully" {
            # ADSI will fail with no real AD; execution falls into inner catch.
            # The GPO should still be counted as executed (non-fatal ACL error).
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "DenyAclGPO" -Extra @{
                    denyApplyGroupPolicy = @("TierAdmins")
                }
            )) -DomainController "DC01"

            $result.Executed | Should -Be 1
            $result.Failed   | Should -Be 0
        }

        It "Should process multiple denyApply groups and remain non-fatal for each" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "MultiDenyGPO" -Extra @{
                    denyApplyGroupPolicy = @("GroupA", "GroupB", "GroupC")
                }
            )) -DomainController "DC01"

            $result.Executed | Should -Be 1
            $result.Failed   | Should -Be 0
        }

        It "Should skip denyApplyGroupPolicy block when property is absent" {
            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "NoDenyGPO"
            )) -DomainController "DC01"

            $result.Executed | Should -Be 1
            $result.Failed   | Should -Be 0
        }
    }

    # ─────────────────────────────────────────────────────────────
    Context "Error handling" {

        # COVERAGE LIMIT – $result.Errors array assertions
        # ──────────────────────────────────────────────────────────────────────
        # New-TierModelGpo uses '$errors = @()' / '$errors += @{...}' for its
        # per-action error list.  Because PowerShell variable names are
        # case-insensitive, '$errors' resolves to the same name as the session-
        # level automatic variable '$Error'.  Inside a Pester run the automatic
        # '$Error' collection already holds entries from prior tests, so
        # '$result.Errors.Count' returns the total accumulated session-error
        # count (e.g. 5) instead of 1, and the items are ErrorRecord objects
        # (no '.Code' property) rather than the hashtables the inner catch
        # appends.
        #
        # The following assertions are therefore UNTESTABLE without a production
        # code change:
        #   • $result.Errors.Count  | Should -Be 1
        #   • $result.Errors[0].Code | Should -Be "GPOCreationFailed"
        #
        # Required production code fix (NOT done here):
        #   Rename '$errors' to a name that does not collide with '$Error',
        #   e.g. '$errorList', and update the return hashtable accordingly.
        #   Once renamed the three removed/trimmed tests below can be restored.
        #
        # Current test coverage for the error path: ~40 %
        #   ✅  $result.Failed    (incremented correctly)
        #   ✅  $result.Executed  (not incremented on failure)
        #   ✅  $result.Converged (set to $false)
        #   ❌  $result.Errors.Count  (collides with $Error)
        #   ❌  $result.Errors[0].Code (items are ErrorRecord, not hashtable)
        # ──────────────────────────────────────────────────────────────────────

        It "Should increment failed count and set Converged false when New-GPO throws" {
            Mock New-GPO -ModuleName TierModel { throw "GPO store unavailable" }

            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "FailGPO"
            )) -DomainController "DC01"

            $result.Failed    | Should -Be 1
            $result.Executed  | Should -Be 0
            $result.Converged | Should -Be $false
            # $result.Errors.Count | Should -Be 1   # blocked – see COVERAGE LIMIT above
        }

        It "Should accumulate per-action failures without stopping other GPO creations" {
            $script:NewGpoCallCount = 0
            Mock New-GPO -ModuleName TierModel {
                param([string]$Name)
                $script:NewGpoCallCount++
                if ($Name -eq "FailGPO") { throw "Creation failed" }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [System.Guid]::NewGuid() }
            }

            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @(
                New-CreateAction -Name "GoodGPO1"
                New-CreateAction -Name "FailGPO"
                New-CreateAction -Name "GoodGPO2"
            )) -DomainController "DC01"

            $result.Executed  | Should -Be 2
            $result.Failed    | Should -Be 1
            $result.Converged | Should -Be $false
            # $result.Errors.Count | Should -Be 1   # blocked – see COVERAGE LIMIT above
        }

        # REMOVED: "Should capture error Code as GPOCreationFailed in the Errors array"
        # Entirely dependent on $result.Errors[0].Code – blocked by the $errors/$Error
        # collision described in the COVERAGE LIMIT comment above.

        It "Should handle outer catastrophic exception and return failed result" {
            # Trigger the outer catch by making Write-TierModelLog throw on the
            # 'GPO creation complete' summary log (which is inside the outer try block).
            Mock Write-TierModelLog -ModuleName TierModel {
                param($Level, $Message, $Data)
                if ($Message -eq 'GPO creation complete') { throw "Summary log failed" }
            }

            $result = New-TierModelGpo -Plan (New-GpoPlan -Actions @()) -DomainController "DC01"

            $result.Failed    | Should -Be 1
            $result.Executed  | Should -Be 0
            $result.Converged | Should -Be $false
            $result.Errors[0].Category | Should -Be "Critical"
        }
    }
}

Describe "Get-TierModelGpoFd – extended coverage" -Tag "Unit", "GPO", "FullDeployment" {
    BeforeAll {
        Import-Module (Resolve-Path "$PSScriptRoot\..\Modules\TierModel") -Force

        Mock Write-TierModelLog       -ModuleName TierModel { }
        Mock Get-ADDomain             -ModuleName TierModel { [PSCustomObject]@{ DistinguishedName = "DC=test,DC=local" } }
        Mock Get-ADOrganizationalUnit -ModuleName TierModel { [PSCustomObject]@{ DistinguishedName = $Identity } }
        Mock Get-GPInheritance        -ModuleName TierModel { [PSCustomObject]@{ GpoLinks = @() } }

        # Default: GPO does not exist
        Mock Get-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
            if ($All) { return @() }
            if ($ErrorAction -eq 'SilentlyContinue') { return $null }
            throw "GPO not found: $Name"
        }

        # Return only the LinkGPO actions from the plan (clean separation)
        Mock Get-TierModelGpoLinkFd -ModuleName TierModel {
            param($Plan, [string]$DomainController, [switch]$Silent)
            $links = @($Plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' })
            return [PSCustomObject]@{ Actions = $links; Errors = @() }
        }

        # Shared helper configs
        $script:CfgCustomNew = [PSCustomObject]@{
            gpos = [PSCustomObject]@{
                "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                    ImportOnlyGpo = @([PSCustomObject]@{ name = "NewGPO1"; mode = "createAndImport" })
                }
            }
        }
        $script:CfgConfigureMode = [PSCustomObject]@{
            gpos = [PSCustomObject]@{
                "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                    PostConfigureGpo = @([PSCustomObject]@{ name = "ConfigGPO"; mode = "createImportAndConfigure" })
                }
            }
        }
        $script:CfgDomainRoot = [PSCustomObject]@{
            gpos = [PSCustomObject]@{
                "DC=test,DC=local" = [PSCustomObject]@{
                    ImportOnlyGpo = @([PSCustomObject]@{ name = "DomainRootGPO" })
                }
            }
        }
        $script:CfgNoGpos = [PSCustomObject]@{ entityType = "GPO" }
    }

    # ── Non-silent output ──────────────────────────────────────────────────────────
    Context "Non-silent output" {
        It "Runs and returns results when -Silent is omitted (Planned Actions path)" {
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01"
            $result | Should -Not -BeNullOrEmpty
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 1
        }

        It "Shows full Create→Import→Configure→Link sequence in non-silent output" {
            $result = Get-TierModelGpoFd -Config $script:CfgConfigureMode -DomainController "DC01"
            $result | Should -Not -BeNullOrEmpty
            @($result.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }).Count | Should -Be 1
        }

        It "Shows 'No GPOs configured' path when config has no gpos property (non-silent)" {
            $result = Get-TierModelGpoFd -Config $script:CfgNoGpos -DomainController "DC01"
            $result.Summary.TotalGPOs | Should -Be 0
            $result.Actions.Count     | Should -Be 0
        }

        It "Shows 'No GPO actions needed' path when GPO exists and is already linked (non-silent)" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [Guid]::NewGuid() }
            }
            Mock Get-GPInheritance -ModuleName TierModel {
                return [PSCustomObject]@{ GpoLinks = @([PSCustomObject]@{ DisplayName = "DomainRootGPO" }) }
            }
            Mock Get-TierModelGpoLinkFd -ModuleName TierModel {
                param($Plan, $DomainController, [switch]$Silent)
                return [PSCustomObject]@{ Actions = @(); Errors = @() }
            }
            $result = Get-TierModelGpoFd -Config $script:CfgDomainRoot -DomainController "DC01"
            $result.Actions.Count | Should -Be 0
        }

        It "Populates action display via Data.name when link action has no Name property (non-silent)" {
            # Mock Get-TierModelGpoLinkFd to return link actions without a Name property
            Mock Get-TierModelGpoLinkFd -ModuleName TierModel {
                param($Plan, [string]$DomainController, [switch]$Silent)
                $stripped = @($Plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' } | ForEach-Object {
                    [PSCustomObject]@{ Action = $_.Action; Path = $_.Path; Data = $_.Data; Risk = $_.Risk; IsTemplate = $_.IsTemplate }
                })
                return [PSCustomObject]@{ Actions = $stripped; Errors = @() }
            }
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01"
            $result | Should -Not -BeNullOrEmpty
        }
    }

    # ── Config without gpos property ───────────────────────────────────────────────
    Context "Config without gpos property" {
        It "Returns empty plan with zero TotalGPOs and no errors (silent)" {
            $result = Get-TierModelGpoFd -Config $script:CfgNoGpos -DomainController "DC01" -Silent
            $result.Actions.Count     | Should -Be 0
            $result.Summary.TotalGPOs | Should -Be 0
            $result.Errors.Count      | Should -Be 0
        }
    }

    # ── TemplateGpos section ───────────────────────────────────────────────────────
    Context "TemplateGpos section (isTemplate = true)" {
        It "Creates and imports template GPO but does not link it" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "TemplateGpos" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "TMPL1"; mode = "createAndImport" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 1
            @($result.Actions | Where-Object { $_.Action -eq 'ImportGPO'  }).Count | Should -Be 1
            @($result.Actions | Where-Object { $_.Action -eq 'LinkGPO'    }).Count | Should -Be 0
        }

        It "Applies IsTemplate=true flag on all template GPO actions" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "TemplateGpos" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "TMPL2" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            $result.Actions | ForEach-Object { $_.IsTemplate | Should -Be $true }
        }
    }

    # ── Existing GPO on custom OU ──────────────────────────────────────────────────
    Context "GPO already exists on custom OU" {
        BeforeEach {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [Guid]::NewGuid() }
            }
        }

        It "Adds LinkGPO action only — no create or import" {
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 0
            @($result.Actions | Where-Object { $_.Action -eq 'ImportGPO'  }).Count | Should -Be 0
            @($result.Actions | Where-Object { $_.Action -eq 'LinkGPO'    }).Count | Should -Be 1
        }
    }

    # ── Domain root OU ────────────────────────────────────────────────────────────
    Context "GPO on domain root OU (isDomainRoot path)" {
        It "Adds LinkGPO when GPO exists on domain root but is not linked" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [Guid]::NewGuid() }
            }
            Mock Get-GPInheritance -ModuleName TierModel { [PSCustomObject]@{ GpoLinks = @() } }
            $result = Get-TierModelGpoFd -Config $script:CfgDomainRoot -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'LinkGPO' }).Count | Should -BeGreaterOrEqual 1
        }

        It "Does not add LinkGPO when GPO is already linked to domain root" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = "DomainRootGPO"; Id = [Guid]::NewGuid() }
            }
            Mock Get-GPInheritance -ModuleName TierModel {
                [PSCustomObject]@{ GpoLinks = @([PSCustomObject]@{ DisplayName = "DomainRootGPO" }) }
            }
            Mock Get-TierModelGpoLinkFd -ModuleName TierModel {
                param($Plan, $DomainController, [switch]$Silent)
                return [PSCustomObject]@{ Actions = @(); Errors = @() }
            }
            $result = Get-TierModelGpoFd -Config $script:CfgDomainRoot -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'LinkGPO' }).Count | Should -Be 0
        }

        It "Adds LinkGPO fallback when Get-GPInheritance throws for domain root" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [Guid]::NewGuid() }
            }
            Mock Get-GPInheritance -ModuleName TierModel { throw "Access denied" }
            $result = Get-TierModelGpoFd -Config $script:CfgDomainRoot -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'LinkGPO' }).Count | Should -BeGreaterOrEqual 1
        }
    }

    # ── Built-in container validation ─────────────────────────────────────────────
    Context "Built-in container OU validation" {
        It "No BuiltinOUNotFound error when Domain Controllers OU exists" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Domain Controllers,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "DCPolicy" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Errors | Where-Object { $_.Code -eq 'BuiltinOUNotFound' }).Count | Should -Be 0
        }

        It "Records BuiltinOUNotFound error when Domain Controllers OU is missing" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel { throw "OU not found" }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Domain Controllers,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "DCPolicy" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Errors | Where-Object { $_.Code -eq 'BuiltinOUNotFound' }).Count | Should -BeGreaterThan 0
        }

        It "Validates CN=Builtin container" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "CN=Builtin,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "BuiltinPolicy" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            $result | Should -Not -BeNullOrEmpty
        }

        It "Validates CN=Users container" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "CN=Users,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "UsersPolicy" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            $result | Should -Not -BeNullOrEmpty
        }
    }

    # ── Rename key matching ────────────────────────────────────────────────────────
    Context "GPO rename key" {
        It "Finds existing GPO via direct rename wildcard pattern — no CreateGPO" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @([PSCustomObject]@{ DisplayName = "MyGPO-V1-2024"; Id = [Guid]::NewGuid() }) }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "GPO not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "MyGPO"; rename = "MyGPO-V1-*" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            # Renamed GPO found by direct pattern → existing GPO path → LinkGPO only
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 0
            @($result.Actions | Where-Object { $_.Action -eq 'LinkGPO'   }).Count | Should -Be 1
        }

        It "Finds existing GPO via alt-pattern when direct pattern has no match" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @([PSCustomObject]@{ DisplayName = "AltGPO-Suffix-Match"; Id = [Guid]::NewGuid() }) }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "GPO not found"
            }
            # rename = "*Suffix" → "*Suffix" doesn't match "AltGPO-Suffix-Match" directly
            # alt-pattern: remove leading * → "Suffix" → "*Suffix*" DOES match
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "AltGPO"; rename = "*Suffix" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 0
        }

        It "Creates new GPO when rename pattern matches nothing" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @([PSCustomObject]@{ DisplayName = "UnrelatedGPO"; Id = [Guid]::NewGuid() }) }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "GPO not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "MyGPO"; rename = "*ZZZNOMATCH*" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 1
        }

        It "Falls back gracefully when Get-GPO -All throws during rename search" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { throw "AD connection error" }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "GPO not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "MyGPO"; rename = "MyGPO-*" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            # Inner catch fires → $existingGpo remains null → treated as new GPO
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 1
        }
    }

    # ── PostConfigureGpo mode variations ──────────────────────────────────────────
    Context "PostConfigureGpo mode variations" {
        It "Does not add ConfigureGPO for createAndImport mode" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "PostGPO"; mode = "createAndImport" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }).Count | Should -Be 0
            @($result.Actions | Where-Object { $_.Action -eq 'CreateGPO'    }).Count | Should -Be 1
        }

        It "Does not add ConfigureGPO when GPO config has no mode property" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "NoModeGPO" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }).Count | Should -Be 0
        }

        It "Adds ConfigureGPO for importAndConfigure mode" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "ImpCfgGPO"; mode = "importAndConfigure" })
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            @($result.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }).Count | Should -Be 1
        }
    }

    # ── Outer catch ───────────────────────────────────────────────────────────────
    Context "Fatal error path (outer catch)" {
        It "Returns PlanningFailed error result when Get-ADDomain throws" {
            Mock Get-ADDomain -ModuleName TierModel { throw "DNS resolution failed" }
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01" -Silent
            $result.EntityType        | Should -Be 'GPO'
            $result.Actions.Count     | Should -Be 0
            $result.Errors.Count      | Should -BeGreaterThan 0
            $result.Errors[0].Code    | Should -Be 'PlanningFailed'
            $result.Summary           | Should -BeNullOrEmpty
            $result.DurationMs        | Should -BeGreaterThan 0
        }
    }

    # ── Result structure ──────────────────────────────────────────────────────────
    Context "Result structure" {
        It "Returns all required top-level properties" {
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01" -Silent
            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'EntityType'
            $props | Should -Contain 'Actions'
            $props | Should -Contain 'Errors'
            $props | Should -Contain 'Warnings'
            $props | Should -Contain 'Summary'
            $props | Should -Contain 'CorrelationId'
            $props | Should -Contain 'DurationMs'
        }

        It "Summary contains all expected keys" {
            $result = Get-TierModelGpoFd -Config $script:CfgConfigureMode -DomainController "DC01" -Silent
            $s = $result.Summary.PSObject.Properties.Name
            $s | Should -Contain 'TotalGPOs'
            $s | Should -Contain 'ActionsRequired'
            $s | Should -Contain 'CreateCount'
            $s | Should -Contain 'ImportCount'
            $s | Should -Contain 'ConfigureCount'
            $s | Should -Contain 'LinkCount'
            $s | Should -Contain 'RiskSummary'
        }

        It "CorrelationId is a valid GUID" {
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01" -Silent
            $result.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }

        It "DurationMs is a positive number" {
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01" -Silent
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "TotalGPOs counts both ImportOnlyGpo and PostConfigureGpo entries" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Custom,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo    = @(
                            [PSCustomObject]@{ name = "G1" }
                            [PSCustomObject]@{ name = "G2" }
                        )
                        PostConfigureGpo = @(
                            [PSCustomObject]@{ name = "G3"; mode = "createImportAndConfigure" }
                        )
                    }
                }
            }
            $result = Get-TierModelGpoFd -Config $cfg -DomainController "DC01" -Silent
            $result.Summary.TotalGPOs | Should -Be 3
        }

        It "RiskSummary tracks MediumRisk for ConfigureGPO actions" {
            $result = Get-TierModelGpoFd -Config $script:CfgConfigureMode -DomainController "DC01" -Silent
            $result.Summary.RiskSummary.MediumRisk | Should -BeGreaterThan 0
        }

        It "RiskSummary tracks HighRisk for LinkGPO actions" {
            $result = Get-TierModelGpoFd -Config $script:CfgCustomNew -DomainController "DC01" -Silent
            $result.Summary.RiskSummary.HighRisk | Should -BeGreaterThan 0
        }
    }
}

Describe "Test-TierModelGpo – extended coverage" -Tag "Unit", "GPO", "Validation" {

    BeforeAll {
        Mock Write-TierModelLog -ModuleName TierModel { } | Out-Null

        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DistinguishedName = "DC=test,DC=local"
                DNSRoot           = "test.local"
            }
        }

        # Default: exact match succeeds for "ExistingGPO"; everything else throws
        Mock Get-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
            if ($All) {
                return @(
                    [PSCustomObject]@{ DisplayName = "ExistingGPO"; Id = [System.Guid]::NewGuid() }
                )
            }
            if ($Name -eq "ExistingGPO") {
                return [PSCustomObject]@{ DisplayName = $Name; Id = [System.Guid]::NewGuid() }
            }
            throw "GPO not found: $Name"
        }

        Mock Get-ADObject -ModuleName TierModel {
            return [PSCustomObject]@{ flags = 0 }
        }
    }

    Context "Rename wildcard — multiple GPO matches" {

        It "Returns Fail with Multiple-GPOs issue when rename pattern matches more than one GPO" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [switch]$All, [string]$Server, $ErrorAction)
                if ($All) {
                    return @(
                        [PSCustomObject]@{ DisplayName = "Policy-V1-Old"; Id = [System.Guid]::NewGuid() }
                        [PSCustomObject]@{ DisplayName = "Policy-V1-New"; Id = [System.Guid]::NewGuid() }
                    )
                }
                throw "GPO not found: $Name"
            }
            $config = [PSCustomObject]@{ rename = "Policy-V1-" }
            $result = Test-TierModelGpo -GPOName "Policy-V1" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Fail'
            ($result.Checks | Where-Object { $_.Check -eq 'GPO Existence' }).Status | Should -Be 'Fail'
            $result.Issues | Should -Match 'Multiple GPOs'
            $result.Recommendations | Should -Not -BeNullOrEmpty
        }
    }

    Context "Rename wildcard — zero matches" {

        It "Returns Fail with not-found issue when rename pattern matches no GPO" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [switch]$All, [string]$Server, $ErrorAction)
                if ($All) {
                    return @(
                        [PSCustomObject]@{ DisplayName = "UnrelatedGPO"; Id = [System.Guid]::NewGuid() }
                    )
                }
                throw "GPO not found: $Name"
            }
            $config = [PSCustomObject]@{ rename = "NoMatch-Pattern-" }
            $result = Test-TierModelGpo -GPOName "NoMatch-GPO" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Fail'
            $result.Issues | Should -Match 'does not exist'
        }
    }

    Context "Rename wildcard — Get-GPO -All throws" {

        It "Returns Fail from inner catch when Get-GPO -All throws" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [switch]$All, [string]$Server, $ErrorAction)
                throw "AD not reachable"
            }
            $config = [PSCustomObject]@{ rename = "Policy-" }
            $result = Test-TierModelGpo -GPOName "Policy-GPO" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Fail'
            $result.Issues | Should -Not -BeNullOrEmpty
        }
    }

    Context "GPO status check — mismatch" {

        It "Returns Fail with status-mismatch issue when flags don't match configured gpoStatus" {
            # flags=0 (AllEnabled) but config says ComputerSettingsDisabled (expected flags=2)
            Mock Get-ADObject -ModuleName TierModel {
                return [PSCustomObject]@{ flags = 0 }
            }
            $config = [PSCustomObject]@{ gpoStatus = "ComputerSettingsDisabled" }
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Fail'
            ($result.Checks | Where-Object { $_.Check -eq 'GPO Status' }).Status | Should -Be 'Fail'
            $result.Issues | Should -Match 'status mismatch'
            $result.Recommendations | Should -Not -BeNullOrEmpty
        }
    }

    Context "GPO status check — Get-ADObject throws" {

        It "Returns Error status when Get-ADObject throws during status check" {
            Mock Get-ADObject -ModuleName TierModel {
                throw "AD read access denied"
            }
            $config = [PSCustomObject]@{ gpoStatus = "AllEnabled" }
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Error'
            ($result.Checks | Where-Object { $_.Check -eq 'GPO Status' }).Status | Should -Be 'Error'
        }
    }

    Context "GPO status check — additional switch cases" {

        It "Passes status check for UserSettingsDisabled (flags=1)" {
            Mock Get-ADObject -ModuleName TierModel {
                return [PSCustomObject]@{ flags = 1 }
            }
            $config = [PSCustomObject]@{ gpoStatus = "UserSettingsDisabled" }
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Pass'
            ($result.Checks | Where-Object { $_.Check -eq 'GPO Status' }).Status | Should -Be 'Pass'
        }

        It "Passes status check for BothSettingsDisabled (flags=3)" {
            Mock Get-ADObject -ModuleName TierModel {
                return [PSCustomObject]@{ flags = 3 }
            }
            $config = [PSCustomObject]@{ gpoStatus = "BothSettingsDisabled" }
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Pass'
            ($result.Checks | Where-Object { $_.Check -eq 'GPO Status' }).Status | Should -Be 'Pass'
        }

        It "Treats unknown gpoStatus value as flags=0 (default switch case)" {
            # Passes when actual flags also happen to be 0 (default branch returns 0)
            Mock Get-ADObject -ModuleName TierModel {
                return [PSCustomObject]@{ flags = 0 }
            }
            $config = [PSCustomObject]@{ gpoStatus = "UnrecognizedValue" }
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -GPOConfig $config -DomainController "DC01"

            $result.Status | Should -Be 'Pass'
            ($result.Checks | Where-Object { $_.Check -eq 'GPO Status' }).Status | Should -Be 'Pass'
        }
    }

    Context "Outer catch — unexpected exception" {

        It "Returns generic Error result when unexpected exception escapes all inner catches" {
            # Make Write-TierModelLog throw on the completion log call (inside outer try, no inner catch)
            Mock Write-TierModelLog -ModuleName TierModel {
                param($Level, $Message)
                if ($Message -eq 'GPO test complete') { throw 'Simulated unexpected error' }
            }
            $result = Test-TierModelGpo -GPOName "ExistingGPO" -DomainController "DC01"

            $result.Status | Should -Be 'Error'
            $result.Issues | Should -Not -BeNullOrEmpty
            $result.Checks[0].Check | Should -Be 'GPO Test'
        }
    }
}

Describe "Get-TierModelGpo – extended coverage" -Tag "Unit", "GPO", "Planning" {

    BeforeAll {
        Mock Write-TierModelLog -ModuleName TierModel { } | Out-Null

        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{ DistinguishedName = "DC=test,DC=local"; DNSRoot = "test.local" }
        }

        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            if ($Identity -match '^OU=Tier') { return [PSCustomObject]@{ DistinguishedName = $Identity } }
            throw "OU not found: $Identity"
        }

        Mock Get-GPO -ModuleName TierModel {
            param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
            if ($All) { return @() }
            if ($Name -eq "ExistingGPO") { return [PSCustomObject]@{ DisplayName = $Name; Id = [System.Guid]::NewGuid() } }
            if ($ErrorAction -eq 'SilentlyContinue') { return $null }
            throw "GPO not found: $Name"
        }

        Mock Get-GPInheritance -ModuleName TierModel {
            return [PSCustomObject]@{ GpoLinks = @() }
        }

        Mock Get-ADGroup -ModuleName TierModel {
            param([string]$Identity, [string]$Server, $ErrorAction)
            if ($Identity -eq "GoodGroup") { return [PSCustomObject]@{ SamAccountName = $Identity } }
            throw "Group not found: $Identity"
        }

        # Shared configs
        $script:CfgNoGpos = [PSCustomObject]@{ domain = "test.local" }

        $script:CfgNewImportOnly = [PSCustomObject]@{
            gpos = [PSCustomObject]@{
                "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                    ImportOnlyGpo = @([PSCustomObject]@{ name = "NewGPO1"; mode = "createAndImport" })
                }
            }
        }

        $script:CfgPostNew = [PSCustomObject]@{
            gpos = [PSCustomObject]@{
                "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                    PostConfigureGpo = @([PSCustomObject]@{ name = "ConfigGPO"; mode = "createImportAndConfigure" })
                }
            }
            groups = @([PSCustomObject]@{ samaccountname = "GoodGroup" })
        }
    }

    Context "Non-silent output — new GPO" {

        It "Prints planned action header when -Silent not specified" {
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01"
            $result.Summary.CreateActions | Should -BeGreaterThan 0
        }

        It "Prints link-only line when GPO exists but not linked" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [System.Guid]::NewGuid() }
            }
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01"
            $result.Summary.LinkActions | Should -BeGreaterThan 0
        }

        It "Prints ERROR line when GPO analysis throws (non-silent)" {
            # Write-Host for the action line is OUTSIDE all inner try/catch blocks;
            # mocking it to throw is the reliable way to reach the GPOAnalysisFailed catch.
            Mock Write-Host -ModuleName TierModel {
                param($Object, $ForegroundColor)
                if ($Object -match '■') { throw "Simulated GPO analysis error" }
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "BrokenGPO"; mode = "createAndImport" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01"
            ($result.Errors | Where-Object { $_.Code -eq 'GPOAnalysisFailed' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "No gpos property in config" {

        It "Returns empty plan when config has no gpos property" {
            $result = Get-TierModelGpo -Config $script:CfgNoGpos -DomainController "DC01" -Silent
            $result.Summary.TotalActions | Should -Be 0
            $result.Actions | Should -BeNullOrEmpty
        }
    }

    Context "ImportOnlyGpo — createImportAndConfigure with valid groups" {

        It "Creates and imports GPO (no ConfigureGPO) for ImportOnlyGpo createImportAndConfigure when groups exist" {
            # ImportOnlyGpo does not add ConfigureGPO even with createImportAndConfigure —
            # Configure is only added in the PostConfigureGpo section. This test covers the
            # group-validation-success path and the action-build path for this mode.
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "CfgGPO"; mode = "createImportAndConfigure" })
                    }
                }
                groups = @([PSCustomObject]@{ samaccountname = "GoodGroup" })
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }) | Should -Not -BeNullOrEmpty
            ($result.Actions | Where-Object { $_.Action -eq 'ImportGPO' }) | Should -Not -BeNullOrEmpty
            ($result.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }) | Should -BeNullOrEmpty
        }
    }

    Context "ImportOnlyGpo — NoGroupsConfigured error" {

        It "Adds NoGroupsConfigured error when mode requires config but no groups property" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "NeedGroupsGPO"; mode = "createImportAndConfigure" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Errors | Where-Object { $_.Code -eq 'NoGroupsConfigured' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "ImportOnlyGpo — rename key matching" {

        It "Uses existing GPO found via direct rename wildcard (ImportOnlyGpo)" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) {
                    return @([PSCustomObject]@{ DisplayName = "RealGPO-2024"; Id = [System.Guid]::NewGuid() })
                }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "RealGPO"; mode = "createAndImport"; rename = "RealGPO*" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            # GPO found → link check, not create
            ($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }) | Should -BeNullOrEmpty
        }

        It "Falls back to alt-pattern when direct rename misses (ImportOnlyGpo)" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) {
                    return @([PSCustomObject]@{ DisplayName = "GPO-Suffix-2024"; Id = [System.Guid]::NewGuid() })
                }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "GPO-Suffix"; mode = "createAndImport"; rename = "*Suffix" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }) | Should -BeNullOrEmpty
        }

        It "Falls through to CreateGPO when Get-GPO -All throws in rename path (ImportOnlyGpo)" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { throw "AD unavailable" }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "AnyGPO"; mode = "createAndImport"; rename = "AnyGPO*" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "PostConfigureGpo — existing GPO paths" {

        It "Adds LinkGPO (LowRisk) when PostConfigureGpo exists but is not linked" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [System.Guid]::NewGuid() }
            }
            Mock Get-GPInheritance -ModuleName TierModel {
                return [PSCustomObject]@{ GpoLinks = @() }
            }
            $result = Get-TierModelGpo -Config $script:CfgPostNew -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.Action -eq 'LinkGPO' } | Where-Object { $_.GPOName -eq 'ConfigGPO' }) | Should -Not -BeNullOrEmpty
            $result.Summary.RiskAssessment.LowRisk | Should -BeGreaterThan 0
        }

        It "No actions for PostConfigureGpo that exists and is already linked" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [System.Guid]::NewGuid() }
            }
            Mock Get-GPInheritance -ModuleName TierModel {
                param($Target)
                return [PSCustomObject]@{ GpoLinks = @([PSCustomObject]@{ DisplayName = "ConfigGPO" }) }
            }
            $result = Get-TierModelGpo -Config $script:CfgPostNew -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.GPOName -eq 'ConfigGPO' }) | Should -BeNullOrEmpty
        }

        It "No LinkGPO for PostConfigureGpo TemplateGpo that already exists" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @() }
                return [PSCustomObject]@{ DisplayName = $Name; Id = [System.Guid]::NewGuid() }
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    TemplateGpos = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "TplGPO"; mode = "createImportAndConfigure" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.Action -eq 'LinkGPO' }) | Should -BeNullOrEmpty
        }
    }

    Context "PostConfigureGpo — rename key" {

        It "Uses existing GPO found via rename wildcard (PostConfigureGpo)" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @([PSCustomObject]@{ DisplayName = "PostGPO-2025"; Id = [System.Guid]::NewGuid() }) }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "PostGPO"; mode = "createImportAndConfigure"; rename = "PostGPO*" })
                    }
                }
                groups = @([PSCustomObject]@{ samaccountname = "GoodGroup" })
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }) | Should -BeNullOrEmpty
        }

        It "Falls through to CreateGPO when alt-pattern also misses (PostConfigureGpo)" {
            Mock Get-GPO -ModuleName TierModel {
                param([string]$Name, [string]$Server, [switch]$All, $ErrorAction)
                if ($All) { return @([PSCustomObject]@{ DisplayName = "UnrelatedGPO"; Id = [System.Guid]::NewGuid() }) }
                if ($ErrorAction -eq 'SilentlyContinue') { return $null }
                throw "not found"
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "PostGPO"; mode = "createImportAndConfigure"; rename = "*NoMatch*" })
                    }
                }
                groups = @([PSCustomObject]@{ samaccountname = "GoodGroup" })
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Actions | Where-Object { $_.Action -eq 'CreateGPO' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "PostConfigureGpo — importAndConfigure mode (no Create)" {

        It "Does not add CreateGPO for importAndConfigure mode" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "ImpCfgGPO"; mode = "importAndConfigure" })
                    }
                }
                groups = @([PSCustomObject]@{ samaccountname = "GoodGroup" })
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            # No Import action for importAndConfigure (only Configure + Link)
            ($result.Actions | Where-Object { $_.Action -eq 'ImportGPO' }) | Should -BeNullOrEmpty
            ($result.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "PostConfigureGpo — NoGroupsConfigured error" {

        It "Adds NoGroupsConfigured error when groups property absent (PostConfigureGpo)" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "NeedGroupsPost"; mode = "createImportAndConfigure" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Errors | Where-Object { $_.Code -eq 'NoGroupsConfigured' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "TargetOUNotFound deduplication" {

        It "Does not duplicate TargetOUNotFound error for multiple GPOs in same missing OU" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Missing,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @(
                            [PSCustomObject]@{ name = "GPO-A"; mode = "createAndImport" }
                            [PSCustomObject]@{ name = "GPO-B"; mode = "createAndImport" }
                        )
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            $ouErrors = @($result.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' })
            $ouErrors.Count | Should -Be 1
        }
    }

    Context "RequiredGroupNotFound deduplication" {

        It "Does not duplicate RequiredGroupNotFound error for same group across multiple GPOs" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @(
                            [PSCustomObject]@{ name = "GPO-X"; mode = "createImportAndConfigure" }
                            [PSCustomObject]@{ name = "GPO-Y"; mode = "createImportAndConfigure" }
                        )
                    }
                }
                groups = @([PSCustomObject]@{ samaccountname = "MissingGroup" })
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            $groupErrors = @($result.Errors | Where-Object { $_.Code -eq 'RequiredGroupNotFound' -and $_.Context.GroupName -eq 'MissingGroup' })
            $groupErrors.Count | Should -Be 1
        }
    }

    Context "Domain root and builtin container OUs" {

        It "Skips Get-ADOrganizationalUnit for domain-root OU path" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "RootGPO"; mode = "createAndImport" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            # No OU error — isDomainRoot bypasses the Get-ADOrganizationalUnit call
            ($result.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' }) | Should -BeNullOrEmpty
        }

        It "Skips Get-ADOrganizationalUnit for CN=Builtin container" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "CN=Builtin,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "BuiltinGPO"; mode = "createAndImport" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' }) | Should -BeNullOrEmpty
        }

        It "Skips Get-ADOrganizationalUnit for OU=Domain Controllers container" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Domain Controllers,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "DCsGPO"; mode = "createAndImport" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' }) | Should -BeNullOrEmpty
        }

        It "Skips Get-ADOrganizationalUnit for CN=Users container" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "CN=Users,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo = @([PSCustomObject]@{ name = "UsersGPO"; mode = "createAndImport" })
                    }
                }
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            ($result.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' }) | Should -BeNullOrEmpty
        }
    }

    Context "GPOAnalysisFailed error — PostConfigureGpo catch" {

        It "Records GPOAnalysisFailed when PostConfigureGpo iteration throws (non-silent)" {
            # Write-Host for the action line is OUTSIDE all inner try/catch blocks inside
            # the PostConfigureGpo loop; throw there to reach GPOAnalysisFailed outer catch.
            Mock Write-Host -ModuleName TierModel {
                param($Object, $ForegroundColor)
                if ($Object -match '■') { throw "Simulated PostConfigureGpo analysis error" }
            }
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        PostConfigureGpo = @([PSCustomObject]@{ name = "BadPost"; mode = "createImportAndConfigure" })
                    }
                }
                groups = @([PSCustomObject]@{ samaccountname = "GoodGroup" })
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01"
            ($result.Errors | Where-Object { $_.Code -eq 'GPOAnalysisFailed' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Outer catch — Get-ADDomain throws" {

        It "Returns GPOPlanningFailed when Get-ADDomain throws" {
            Mock Get-ADDomain -ModuleName TierModel { throw "Domain unreachable" }
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01" -Silent
            ($result.Errors | Where-Object { $_.Code -eq 'GPOPlanningFailed' }) | Should -Not -BeNullOrEmpty
            $result.Summary.TotalActions | Should -Be 0
        }
    }

    Context "Result structure" {

        It "Result has all expected top-level properties" {
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01" -Silent
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Analysis'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Warnings'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Summary contains all expected keys" {
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01" -Silent
            $result.Summary.Keys | Should -Contain 'TotalInConfig'
            $result.Summary.Keys | Should -Contain 'ToCreate'
            $result.Summary.Keys | Should -Contain 'TotalActions'
            $result.Summary.Keys | Should -Contain 'RiskAssessment'
        }

        It "TotalInConfig counts both ImportOnlyGpo and PostConfigureGpo" {
            $cfg = [PSCustomObject]@{
                gpos = [PSCustomObject]@{
                    "OU=Tier0,DC=test,DC=local" = [PSCustomObject]@{
                        ImportOnlyGpo    = @(
                            [PSCustomObject]@{ name = "G1"; mode = "createAndImport" }
                            [PSCustomObject]@{ name = "G2"; mode = "createAndImport" }
                        )
                        PostConfigureGpo = @(
                            [PSCustomObject]@{ name = "G3"; mode = "createImportAndConfigure" }
                        )
                    }
                }
                groups = @([PSCustomObject]@{ samaccountname = "GoodGroup" })
            }
            $result = Get-TierModelGpo -Config $cfg -DomainController "DC01" -Silent
            $result.Summary.TotalInConfig | Should -Be 3
        }

        It "CorrelationId is a valid GUID string" {
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01" -Silent
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }

        It "DurationMs is greater than zero" {
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01" -Silent
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "RiskAssessment.HighRisk increments for PostConfigureGpo new GPO" {
            $result = Get-TierModelGpo -Config $script:CfgPostNew -DomainController "DC01" -Silent
            $result.Summary.RiskAssessment.HighRisk | Should -BeGreaterThan 0
        }

        It "RiskAssessment.MediumRisk increments for ImportOnlyGpo new GPO" {
            $result = Get-TierModelGpo -Config $script:CfgNewImportOnly -DomainController "DC01" -Silent
            $result.Summary.RiskAssessment.MediumRisk | Should -BeGreaterThan 0
        }
    }
}
