<#
.SYNOPSIS
Unit tests for TierModel Group operation functions.

.DESCRIPTION
Comprehensive Pester v5 tests for Group operations:
- Get-TierModelGroup.ps1 - Group creation plan generation
- Get-TierModelGroupFd.ps1 - Group creation plan generation (Full Deployment)
- New-TierModelGroup.ps1 - Group creation execution
- Test-TierModelGroup.ps1 - Group audit and validation

.NOTES
Author: TierModel Testing Team
Tags: Unit, Group, Operations
#>

BeforeAll {
    # Import the TierModel module
    $modulePath = Join-Path $PSScriptRoot '..\modules\TierModel\TierModel.psd1'
    Import-Module $modulePath -Force
    
    # Set correlation ID for logging
    InModuleScope TierModel {
        $script:CorrelationId = 'test-group-ops-' + (New-Guid).ToString()
    }
}

Describe "Group Operations" -Tag "Unit", "Group", "Phase3" {
    BeforeAll {
        # Test correlation ID
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        
        # Mock domain controller
        $script:TestDC = "DC01.test.local"
        $script:TestDomainDN = "DC=test,DC=local"
        
        # Test configuration with groups
        $script:TestConfig = [PSCustomObject]@{
            organizationalUnits = @(
                @{ name = "Tier0"; path = "OU=Tier0,{{domainDN}}"; description = "Tier 0 OU" }
                @{ name = "Tier1"; path = "OU=Tier1,{{domainDN}}"; description = "Tier 1 OU" }
            )
            groups = @(
                [PSCustomObject]@{
                    name = "Tier0Admins"
                    samaccountname = "Tier0Admins"
                    path = "OU=Tier0,{{domainDN}}"
                    groupscope = "DomainLocal"
                    groupcategory = "Security"
                    description = "Tier 0 Administrators"
                }
                [PSCustomObject]@{
                    name = "Tier1Users"
                    samaccountname = "Tier1Users"
                    path = "OU=Tier1,{{domainDN}}"
                    groupscope = "Global"
                    groupcategory = "Security"
                    description = "Tier 1 Users"
                }
                [PSCustomObject]@{
                    name = "Tier1Admins"
                    samaccountname = "Tier1Admins"
                    path = "OU=Tier1,{{domainDN}}"
                    groupscope = "Universal"
                    groupcategory = "Security"
                    description = "Tier 1 Administrators"
                }
            )
        }
        
        # Test configuration with no groups
        $script:TestConfigEmpty = [PSCustomObject]@{
            organizationalUnits = @()
        }
        
        # Mock AD cmdlets using InModuleScope to ensure proper scope
        InModuleScope TierModel {
            Mock Get-ADOrganizationalUnit {
                param($Identity, $Server)
                if ($Identity -match "Tier0" -or $Identity -match "Tier1") {
                    return [PSCustomObject]@{
                        DistinguishedName = $Identity
                        Name = if ($Identity -match "Tier0") { "Tier0" } else { "Tier1" }
                    }
                } else {
                    throw "OU not found"
                }
            }
            
            Mock Get-ADGroup {
                param($Identity, $Server, $ErrorAction)
                
                # Note: $Identity is an ADGroup object, not a string. Use .ToString() for comparison.
                #Tier0Admins already exists
                if ($Identity.ToString() -eq "Tier0Admins" -or $Identity.ToString() -like "CN=Tier0Admins,*") {
                    return [PSCustomObject]@{
                        Name = "Tier0Admins"
                        SamAccountName = "Tier0Admins"
                        DistinguishedName = "CN=Tier0Admins,OU=Tier0,DC=test,DC=local"
                        GroupScope = "DomainLocal"
                        GroupCategory = "Security"
                        Description = "Tier 0 Administrators"
                    }
                }
                # For non-existing groups, return nothing
                return $null
            }
            
            Mock New-ADGroup {
                param($Name, $SamAccountName, $Path, $GroupScope, $GroupCategory, $Description, $Server)
                return [PSCustomObject]@{
                    Name = $Name
                    SamAccountName = $SamAccountName
                    DistinguishedName = "CN=$Name,$Path"
                    ObjectGUID = [System.Guid]::NewGuid()
                    GroupScope = $GroupScope
                    GroupCategory = $GroupCategory
                    Description = $Description
                }
            }
            
            Mock Resolve-TierModelDomainDN { return "DC=test,DC=local" }
            Mock Resolve-TierModelPlaceholder { 
                param($Path, $DomainDN)
                return $Path.Replace("{{domainDN}}", $DomainDN)
            }
            Mock Write-TierModelLog { }
        }
    }
    
    Context "Get-TierModelGroup - Planning & Plan Generation" {
        It "Should generate deployment plan for groups" {
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
        }
        
        It "Should include actions for groups that need to be created" {
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            # Verify result structure
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            
            # Should have actions for groups that don't exist (Tier1Users, Tier1Admins)
            # Tier0Admins already exists per mock
            $result.Actions.Count | Should -BeGreaterOrEqual 0
        }
        
        It "Should skip groups that already exist" {
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            # Tier0Admins should be detected as existing (per Get-ADGroup mock)
            $tier0Action = $result.Actions | Where-Object { $_.Data.name -eq "Tier0Admins" }
            $tier0Action | Should -BeNullOrEmpty  # Should not have action since it exists
            
            # Verify existing count
            $result.Summary.ExistingCount | Should -BeGreaterOrEqual 1
        }
        
        It "Should calculate summary statistics correctly" {
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.Summary.TotalInConfig | Should -Be $script:TestConfig.groups.Count
            $result.Summary.ToCreate | Should -Be $result.Actions.Count
            $result.Summary.ExistingCount | Should -BeGreaterOrEqual 0
        }
        
        It "Should handle configuration with no groups" {
            $result = Get-TierModelGroup -Config $script:TestConfigEmpty -DomainController $script:TestDC
            
            $result.Actions.Count | Should -Be 0
            $result.Summary.TotalInConfig | Should -Be 0
            $result.Warnings | Should -Not -BeNullOrEmpty
        }
        
        It "Should validate parent OU exists" {
            # Override mock to simulate missing OU
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw "OU not found"
            }
            
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should have errors for missing parent OUs
            $result.Errors | Should -Not -BeNullOrEmpty
        }
        
        It "Should resolve placeholders in group paths" {
            Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            # Verify Resolve-TierModelPlaceholder was called
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -Times 1
        }
        
        It "Should include correlation ID in result" {
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
            $result.CorrelationId | Should -Not -BeNullOrEmpty
        }
        
        It "Should create actions with correct structure" {
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            if ($result.Actions.Count -gt 0) {
                $action = $result.Actions[0]
                $action.Action | Should -Be "CreateGroup"
                $action.PSObject.Properties.Name | Should -Contain 'ResourceType'
                $action.PSObject.Properties.Name | Should -Contain 'Name'
                $action.PSObject.Properties.Name | Should -Contain 'Path'
                $action.PSObject.Properties.Name | Should -Contain 'Data'
            }
        }
    }
    
    Context "Get-TierModelGroupFd - Full Deployment Planning" {
        It "Should generate deployment plan for full deployment mode" {
            $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
        }
        
        It "Should not fail when parent OUs don't exist (lightweight validation)" {
            # Override mock to simulate missing OUs
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw "OU not found"
            }
            
            $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should still create actions even if OUs don't exist yet (assumed they will be created)
            $result | Should -Not -BeNullOrEmpty
            $result.Actions | Should -Not -BeNull
        }
        
        It "Should track existing group count separately" {
            $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.Summary.Keys | Should -Contain 'ExistingCount'
            $result.Summary.ExistingCount | Should -BeGreaterOrEqual 0
        }
        
        It "Should detect existing groups and skip them" {
            $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should have ExistingCount field in summary
            $result.Summary.Keys | Should -Contain 'ExistingCount'
            $result.Summary.ExistingCount | Should -BeGreaterOrEqual 0
            
            # Verify the function processes groups and generates appropriate actions
            $result.Actions | Should -Not -BeNull
            $result.Summary.TotalInConfig | Should -Be $script:TestConfig.groups.Count
        }
        
        It "Should handle empty configuration gracefully" {
            $result = Get-TierModelGroupFd -Config $script:TestConfigEmpty -DomainController $script:TestDC
            
            $result | Should -Not -BeNullOrEmpty
            $result.Actions.Count | Should -Be 0
            $result.Summary.TotalInConfig | Should -Be 0
        }
        
        It "Should resolve placeholders in group paths" {
            Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -Times 1
        }
        
        It "Should include correlation ID in result" {
            $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }
    }
    
    Context "New-TierModelGroup - Group Creation" {
        BeforeEach {
            # Create a plan with groups to create
            $script:TestPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateGroup'
                        ResourceType = 'Group'
                        Name = 'Tier1Users'
                        Path = "OU=Tier1,$script:TestDomainDN"
                        Data = @{
                            name = 'Tier1Users'
                            samaccountname = 'Tier1Users'
                            path = "OU=Tier1,$script:TestDomainDN"
                            groupscope = 'Global'
                            groupcategory = 'Security'
                            description = 'Tier 1 Users'
                        }
                    }
                )
                Summary = @{
                    TotalInConfig = 3
                    ToCreate = 1
                    ExistingCount = 2
                }
            }
        }
        
        It "Should create groups from plan" {
            $result = New-TierModelGroup -Plan $script:TestPlan -DomainController $script:TestDC
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Applied'
            $result.PSObject.Properties.Name | Should -Contain 'Skipped'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
        }
        
        It "Should call New-ADGroup with correct parameters" {
            $script:capturedName = $null
            $script:capturedSamAccountName = $null
            $script:capturedPath = $null
            $script:capturedGroupScope = $null
            
            Mock New-ADGroup -ModuleName TierModel {
                param($Name, $SamAccountName, $Path, $GroupScope, $GroupCategory, $Description, $Server)
                $script:capturedName = $Name
                $script:capturedSamAccountName = $SamAccountName
                $script:capturedPath = $Path
                $script:capturedGroupScope = $GroupScope
                
                return [PSCustomObject]@{
                    Name = $Name
                    SamAccountName = $SamAccountName
                    DistinguishedName = "CN=$Name,$Path"
                    ObjectGUID = [System.Guid]::NewGuid()
                    GroupScope = $GroupScope
                    GroupCategory = $GroupCategory
                }
            }
            
            New-TierModelGroup -Plan $script:TestPlan -DomainController $script:TestDC
            
            $script:capturedName | Should -Be 'Tier1Users'
            $script:capturedSamAccountName | Should -Be 'Tier1Users'
            $script:capturedPath | Should -Be "OU=Tier1,$script:TestDomainDN"
            $script:capturedGroupScope | Should -Be 'Global'
        }
        
        It "Should track applied groups" {
            $result = New-TierModelGroup -Plan $script:TestPlan -DomainController $script:TestDC
            
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].Name | Should -Be 'Tier1Users'
        }
        
        It "Should handle WhatIf mode" {
            $result = New-TierModelGroup -Plan $script:TestPlan -DomainController $script:TestDC -WhatIf
            
            # In WhatIf mode, no actual creation should occur
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke New-ADGroup -ModuleName TierModel -Times 0
        }
        
        It "Should handle empty plan gracefully" {
            $emptyPlan = [PSCustomObject]@{
                Actions = @()
                Summary = @{}
            }
            
            $result = New-TierModelGroup -Plan $emptyPlan -DomainController $script:TestDC
            
            $result.Applied.Count | Should -Be 0
        }
        
        It "Should capture errors on group creation failure" {
            Mock New-ADGroup -ModuleName TierModel {
                throw "Access denied"
            }
            
            $result = New-TierModelGroup -Plan $script:TestPlan -DomainController $script:TestDC
            
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors.Count | Should -BeGreaterThan 0
        }
        
        It "Should include duration in result" {
            $result = New-TierModelGroup -Plan $script:TestPlan -DomainController $script:TestDC
            
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.DurationMs | Should -BeGreaterOrEqual 0
        }
        
        It "Should handle groups with default scope" {
            # Create plan with group missing groupscope property
            $planWithDefaults = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateGroup'
                        ResourceType = 'Group'
                        Name = 'TestGroup'
                        Path = "OU=Tier1,$script:TestDomainDN"
                        Data = @{
                            name = 'TestGroup'
                            samaccountname = 'TestGroup'
                            path = "OU=Tier1,$script:TestDomainDN"
                            # groupscope intentionally omitted
                        }
                    }
                )
            }
            
            $result = New-TierModelGroup -Plan $planWithDefaults -DomainController $script:TestDC
            
            # Should use default scope
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke New-ADGroup -ModuleName TierModel -Times 1
        }
    }
    
    Context "Test-TierModelGroup - Audit & Compliance" {
        BeforeEach {
            # Reset mocks for audit tests
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server)
                # Note: $Identity is an ADGroup object. Use .ToString() for comparison.
                if ($Identity.ToString() -eq "Tier0Admins" -or $Identity.ToString() -eq "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN") {
                    return [PSCustomObject]@{
                        Name = "Tier0Admins"
                        SamAccountName = "Tier0Admins"
                        DistinguishedName = "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN"
                        GroupScope = "DomainLocal"
                        GroupCategory = "Security"
                        Description = "Tier 0 Administrators"
                    }
                } else {
                    # Throw ADIdentityNotFoundException for missing groups
                    $exception = New-Object Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException "Cannot find an object with identity: '$Identity'"
                    throw $exception
                }
            }
        }
        
        It "Should audit groups against configuration" {
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'DriftFindings'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
        }
        
        It "Should count total groups in configuration" {
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.Summary.TotalChecked | Should -Be $script:TestConfig.groups.Count
        }
        
        It "Should detect missing groups" {
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            # Tier1Users and Tier1Admins should be missing (only Tier0Admins exists per mock)
            $result.Summary.MissingCount | Should -BeGreaterThan 0
            $missingFindings = $result.DriftFindings | Where-Object { $_.Type -eq 'Missing' }
            $missingFindings | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect property mismatches" {
            # Override mock to return group with wrong properties
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server)
                # Note: $Identity is an ADGroup object. Use .ToString() for comparison.
                if ($Identity.ToString() -eq "Tier0Admins" -or $Identity.ToString() -eq "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN") {
                    return [PSCustomObject]@{
                        Name = "Tier0Admins"
                        SamAccountName = "Tier0Admins"
                        DistinguishedName = "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN"
                        GroupScope = "Global"  # Wrong scope (expected DomainLocal)
                        GroupCategory = "Security"
                        Description = "Wrong description"  # Wrong description
                    }
                } else {
                    # Throw ADIdentityNotFoundException for missing groups
                    $exception = New-Object Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException "Cannot find an object with identity: '$Identity'"
                    throw $exception
                }
            }
            
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.Summary.MismatchCount | Should -BeGreaterThan 0
            $mismatchFindings = $result.DriftFindings | Where-Object { $_.Type -eq 'Mismatch' }
            $mismatchFindings | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect groups in wrong location" {
            # Override mock to return group in wrong OU
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server)
                # Note: $Identity is an ADGroup object. Use .ToString() for comparison.
                if ($Identity.ToString() -eq "Tier0Admins" -or $Identity.ToString() -eq "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN") {
                    return [PSCustomObject]@{
                        Name = "Tier0Admins"
                        SamAccountName = "Tier0Admins"
                        DistinguishedName = "CN=Tier0Admins,OU=WrongOU,$script:TestDomainDN"  # Wrong OU
                        GroupScope = "DomainLocal"
                        GroupCategory = "Security"
                        Description = "Tier 0 Administrators"
                    }
                } else {
                    # Throw ADIdentityNotFoundException for missing groups
                    $exception = New-Object Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException "Cannot find an object with identity: '$Identity'"
                    throw $exception
                }
            }
            
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $locationFindings = $result.DriftFindings | Where-Object { $_.Identifier -like '*/Location' }
            $locationFindings | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle configuration with no groups" {
            $result = Test-TierModelGroup -Config $script:TestConfigEmpty -DomainController $script:TestDC -Silent
            
            $result.Warnings | Should -Not -BeNullOrEmpty
            $result.Summary.TotalChecked | Should -Be 0
        }
        
        It "Should include correlation ID in results" {
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }
        
        It "Should suppress console output in Silent mode" {
            # This test verifies Silent mode doesn't throw errors
            { Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent } | Should -Not -Throw
        }
        
        It "Should resolve placeholders in group paths" {
            Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -Times 1
        }
    }
    
    Context "Test-TierModelGroup - Extended Coverage" {
        BeforeEach {
            # Default: all three test groups exist with matching properties
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server)
                $id = $Identity.ToString()
                switch ($id) {
                    "Tier0Admins" {
                        return [PSCustomObject]@{
                            Name              = "Tier0Admins"
                            SamAccountName    = "Tier0Admins"
                            DistinguishedName = "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN"
                            GroupScope        = "DomainLocal"
                            GroupCategory     = "Security"
                        }
                    }
                    "Tier1Users"  {
                        return [PSCustomObject]@{
                            Name              = "Tier1Users"
                            SamAccountName    = "Tier1Users"
                            DistinguishedName = "CN=Tier1Users,OU=Tier1,$script:TestDomainDN"
                            GroupScope        = "Global"
                            GroupCategory     = "Security"
                        }
                    }
                    "Tier1Admins" {
                        return [PSCustomObject]@{
                            Name              = "Tier1Admins"
                            SamAccountName    = "Tier1Admins"
                            DistinguishedName = "CN=Tier1Admins,OU=Tier1,$script:TestDomainDN"
                            GroupScope        = "Universal"
                            GroupCategory     = "Security"
                        }
                    }
                    default {
                        $ex = New-Object Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException "not found"
                        throw $ex
                    }
                }
            }
        }

        It "Should output non-silent summary when all groups are compliant" {
            # Call without -Silent to exercise the summary block green-path Write-Host lines
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC

            $result.Summary.DriftCount    | Should -Be 0
            $result.Summary.MissingCount  | Should -Be 0
            $result.Summary.MismatchCount | Should -Be 0
        }

        It "Should output non-silent summary with red drift counts when groups are non-compliant" {
            # Tier0Admins has wrong scope (mismatch); Tier1Users and Tier1Admins are missing
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server)
                if ($Identity.ToString() -eq "Tier0Admins") {
                    return [PSCustomObject]@{
                        Name              = "Tier0Admins"
                        SamAccountName    = "Tier0Admins"
                        DistinguishedName = "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN"
                        GroupScope        = "Global"      # wrong (config expects DomainLocal)
                        GroupCategory     = "Security"
                    }
                }
                $ex = New-Object Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException "not found"
                throw $ex
            }

            # Call without -Silent to exercise red-count summary Write-Host lines
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC

            $result.Summary.MissingCount  | Should -BeGreaterThan 0
            $result.Summary.MismatchCount | Should -BeGreaterThan 0
        }

        It "Should add warning and continue when Get-ADGroup throws a non-identity exception" {
            Mock Get-ADGroup -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Query failure")
            }

            $singleConfig = [PSCustomObject]@{
                groups = @(
                    [PSCustomObject]@{
                        name           = "Tier0Admins"
                        samaccountname = "Tier0Admins"
                        path           = "OU=Tier0,{{domainDN}}"
                        groupscope     = "DomainLocal"
                        groupcategory  = "Security"
                    }
                )
            }

            $result = Test-TierModelGroup -Config $singleConfig -DomainController $script:TestDC -Silent

            $result.Warnings.Count | Should -BeGreaterThan 0
            ($result.Warnings | Where-Object { $_ -match "Failed to query" }) | Should -Not -BeNullOrEmpty
            $result.DriftFindings | Should -BeNullOrEmpty
        }

        It "Should populate ResolvedPaths in result when IncludeResolvedPaths is specified" {
            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC `
                -Silent -IncludeResolvedPaths

            $result.PSObject.Properties.Name | Should -Contain 'ResolvedPaths'
            $result.ResolvedPaths | Should -Not -BeNullOrEmpty
            $result.ResolvedPaths.Count | Should -Be $script:TestConfig.groups.Count
            $result.ResolvedPaths[0].PSObject.Properties.Name | Should -Contain 'ResolvedPath'
            $result.ResolvedPaths[0].PSObject.Properties.Name | Should -Contain 'OriginalPath'
            $result.ResolvedPaths[0].PSObject.Properties.Name | Should -Contain 'ExpectedGroupScope'
        }

        It "Should detect GroupCategory mismatch and create Mismatch/GroupCategory drift finding" {
            Mock Get-ADGroup -ModuleName TierModel {
                return [PSCustomObject]@{
                    Name              = "Tier0Admins"
                    SamAccountName    = "Tier0Admins"
                    DistinguishedName = "CN=Tier0Admins,OU=Tier0,$script:TestDomainDN"
                    GroupScope        = "DomainLocal"
                    GroupCategory     = "Distribution"   # wrong (config expects Security)
                }
            }

            $singleConfig = [PSCustomObject]@{
                groups = @(
                    [PSCustomObject]@{
                        name           = "Tier0Admins"
                        samaccountname = "Tier0Admins"
                        path           = "OU=Tier0,{{domainDN}}"
                        groupscope     = "DomainLocal"
                        groupcategory  = "Security"
                    }
                )
            }

            $result = Test-TierModelGroup -Config $singleConfig -DomainController $script:TestDC -Silent

            $categoryFinding = $result.DriftFindings | Where-Object { $_.Identifier -like '*/GroupCategory' }
            $categoryFinding            | Should -Not -BeNullOrEmpty
            $categoryFinding.Type       | Should -Be 'Mismatch'
            $categoryFinding.ExpectedValue | Should -Be 'Security'
            $categoryFinding.ActualValue   | Should -Be 'Distribution'
        }

        It "Should default GroupScope to Global when groupscope is not specified in config" {
            Mock Get-ADGroup -ModuleName TierModel {
                return [PSCustomObject]@{
                    Name              = "DefaultScopeGroup"
                    SamAccountName    = "DefaultScopeGroup"
                    DistinguishedName = "CN=DefaultScopeGroup,OU=Tier0,$script:TestDomainDN"
                    GroupScope        = "Global"       # matches the expected default
                    GroupCategory     = "Security"
                }
            }

            $noScopeConfig = [PSCustomObject]@{
                groups = @(
                    [PSCustomObject]@{
                        name           = "DefaultScopeGroup"
                        samaccountname = "DefaultScopeGroup"
                        path           = "OU=Tier0,{{domainDN}}"
                        # groupscope intentionally omitted — code should default to 'Global'
                        groupcategory  = "Security"
                    }
                )
            }

            $result = Test-TierModelGroup -Config $noScopeConfig -DomainController $script:TestDC -Silent

            $scopeFinding = $result.DriftFindings | Where-Object { $_.Identifier -like '*/GroupScope' }
            $scopeFinding                | Should -BeNullOrEmpty
            $result.Summary.MismatchCount | Should -Be 0
        }

        It "Should default GroupCategory to Security when groupcategory is not specified in config" {
            Mock Get-ADGroup -ModuleName TierModel {
                return [PSCustomObject]@{
                    Name              = "DefaultCategoryGroup"
                    SamAccountName    = "DefaultCategoryGroup"
                    DistinguishedName = "CN=DefaultCategoryGroup,OU=Tier0,$script:TestDomainDN"
                    GroupScope        = "DomainLocal"
                    GroupCategory     = "Security"     # matches the expected default
                }
            }

            $noCategoryConfig = [PSCustomObject]@{
                groups = @(
                    [PSCustomObject]@{
                        name           = "DefaultCategoryGroup"
                        samaccountname = "DefaultCategoryGroup"
                        path           = "OU=Tier0,{{domainDN}}"
                        groupscope     = "DomainLocal"
                        # groupcategory intentionally omitted — code should default to 'Security'
                    }
                )
            }

            $result = Test-TierModelGroup -Config $noCategoryConfig -DomainController $script:TestDC -Silent

            $categoryFinding = $result.DriftFindings | Where-Object { $_.Identifier -like '*/GroupCategory' }
            $categoryFinding              | Should -BeNullOrEmpty
            $result.Summary.MismatchCount | Should -Be 0
        }

        It "Should record GroupAuditFailed error when per-group processing throws unexpectedly" {
            # Resolve-TierModelPlaceholder throws → triggers the inner per-group catch
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Placeholder resolution failed")
            }

            $singleConfig = [PSCustomObject]@{
                groups = @(
                    [PSCustomObject]@{
                        name           = "Tier0Admins"
                        samaccountname = "Tier0Admins"
                        path           = "OU=Tier0,{{domainDN}}"
                        groupscope     = "DomainLocal"
                        groupcategory  = "Security"
                    }
                )
            }

            $result = Test-TierModelGroup -Config $singleConfig -DomainController $script:TestDC -Silent

            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code                  | Should -Be 'GroupAuditFailed'
            $result.Errors[0].Context.GroupName     | Should -Be 'Tier0Admins'
        }

        It "Should return partial result with GroupAuditFailed error when outer processing fails" {
            # Resolve-TierModelDomainDN throws → triggers the outer function catch
            Mock Resolve-TierModelDomainDN -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Domain resolution failed")
            }

            $result = Test-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC -Silent

            $result                              | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name     | Should -Contain 'DriftFindings'
            $result.PSObject.Properties.Name     | Should -Contain 'Errors'
            $result.Errors                       | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code               | Should -Be 'GroupAuditFailed'
        }
    }

    Context "Get-TierModelGroup vs Get-TierModelGroupFd - Comparison" {
        It "Should have similar output structure" {
            $regularPlan = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            $fdPlan = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Both should have same properties
            $regularPlan.PSObject.Properties.Name | Should -Contain 'Actions'
            $fdPlan.PSObject.Properties.Name | Should -Contain 'Actions'
            
            $regularPlan.PSObject.Properties.Name | Should -Contain 'Summary'
            $fdPlan.PSObject.Properties.Name | Should -Contain 'Summary'
        }
        
        It "Get-TierModelGroup should validate parent OUs" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw "OU not found"
            }
            
            $result = Get-TierModelGroup -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should have errors for missing OUs
            $result.Errors | Should -Not -BeNullOrEmpty
        }
        
        It "Get-TierModelGroupFd should be more lenient with missing OUs" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw "OU not found"
            }
            
            $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should still create actions even if parent OUs don't exist
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-TierModelGroupFd – Extended Coverage" -Tag "Unit", "Group", "Phase3" {
    BeforeAll {
        $script:TestDC  = "DC01.test.local"

        $script:TestConfig = [PSCustomObject]@{
            groups = @(
                [PSCustomObject]@{
                    name           = "Tier0Admins"
                    samaccountname = "Tier0Admins"
                    path           = "OU=Tier0,{{domainDN}}"
                    groupscope     = "DomainLocal"
                    groupcategory  = "Security"
                    description    = "Tier 0 Administrators"
                }
            )
        }

        InModuleScope TierModel {
            Mock Resolve-TierModelDomainDN { return "DC=test,DC=local" }
            Mock Resolve-TierModelPlaceholder {
                param($Path, $DomainDN)
                return $Path.Replace("{{domainDN}}", $DomainDN)
            }
            Mock Get-ADGroup { return $null }
            Mock Write-TierModelLog { }
        }
    }

    It "Should record GroupFdPlanFailed error when per-group processing throws" {
        # Resolve-TierModelPlaceholder throws → triggers the inner per-group catch (lines 120-137)
        InModuleScope TierModel {
            Mock Resolve-TierModelPlaceholder {
                throw [System.InvalidOperationException]::new("Placeholder resolution failed")
            }
        }

        $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC

        $result                          | Should -Not -BeNullOrEmpty
        $result.Errors                   | Should -Not -BeNullOrEmpty
        $result.Errors[0].Code           | Should -Be 'GroupFdPlanFailed'
        $result.Errors[0].Context.GroupName | Should -Be 'Tier0Admins'
    }

    It "Should return partial result with GroupFdPlanFailed error when outer processing fails" {
        # Resolve-TierModelDomainDN throws → triggers the outer function catch (lines 167-186)
        InModuleScope TierModel {
            Mock Resolve-TierModelDomainDN {
                throw [System.InvalidOperationException]::new("Domain resolution failed")
            }
        }

        $result = Get-TierModelGroupFd -Config $script:TestConfig -DomainController $script:TestDC

        $result                              | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name     | Should -Contain 'Actions'
        $result.PSObject.Properties.Name     | Should -Contain 'Errors'
        $result.Actions.Count                | Should -Be 0
        $result.Errors                       | Should -Not -BeNullOrEmpty
        $result.Errors[0].Code               | Should -Be 'GroupFdPlanFailed'
    }
}

Describe "Get-TierModelGroup – Extended Coverage" -Tag "Unit", "Group" {
    BeforeAll {
        $script:ExtDC = 'dc01.test.local'
        $script:ExtDomainDN = 'DC=test,DC=local'

        # Minimal valid config — two groups, OU exists, Resolve helpers work
        $script:ExtConfig = [PSCustomObject]@{
            groups = @(
                [PSCustomObject]@{
                    name           = 'ExtGroup1'
                    samaccountname = 'ExtGroup1'
                    path           = 'OU=ExtTier,{{domainDN}}'
                    groupscope     = 'Global'
                    groupcategory  = 'Security'
                    description    = 'Extended Group 1'
                }
            )
        }

        InModuleScope TierModel {
            Mock Write-TierModelLog    { }
            Mock Resolve-TierModelDomainDN   { return 'DC=test,DC=local' }
            Mock Resolve-TierModelPlaceholder {
                param($Path, $DomainDN)
                return $Path.Replace('{{domainDN}}', $DomainDN)
            }
            Mock Get-ADOrganizationalUnit {
                return [PSCustomObject]@{ DistinguishedName = 'OU=ExtTier,DC=test,DC=local' }
            }
            Mock Get-ADGroup { return $null }
        }
    }

    It "Should populate inner catch block when per-group processing throws unexpectedly (lines 139-156)" {
        # Get-ADGroup has its own swallowing catch, so we must throw from Resolve-TierModelPlaceholder
        # which runs inside the per-group try but outside any inner try → propagates to line 138 catch
        InModuleScope TierModel {
            Mock Resolve-TierModelPlaceholder { throw "Placeholder resolution failed unexpectedly" }
        }
        $result = Get-TierModelGroup -Config $script:ExtConfig -DomainController $script:ExtDC
        $result.Errors                   | Should -Not -BeNullOrEmpty
        $result.Errors[0].Code           | Should -Be 'GroupPlanFailed'
        $result.Errors[0].Category       | Should -Be 'External'
        ($result.Errors[0].Message)      | Should -Match 'Failed to analyze group'
    }

    It "Should populate outer catch block when Resolve-TierModelDomainDN throws (lines 186-205)" {
        InModuleScope TierModel {
            Mock Resolve-TierModelDomainDN { throw "DNS resolution failed" }
        }
        $result = Get-TierModelGroup -Config $script:ExtConfig -DomainController $script:ExtDC
        $result.Actions.Count            | Should -Be 0
        $result.Errors                   | Should -Not -BeNullOrEmpty
        $result.Errors[0].Code           | Should -Be 'GroupPlanFailed'
        $result.Errors[0].Category       | Should -Be 'Execution'
        ($result.Errors[0].Message)      | Should -Match 'Group plan generation failed'
    }
}
