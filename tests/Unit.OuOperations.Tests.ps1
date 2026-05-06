<#
.SYNOPSIS
Unit tests for TierModel OU operation functions.

.DESCRIPTION
Comprehensive Pester v5 tests for OU operations:
- Test-TierModelOuExists.ps1 - OU existence checking
- Get-TierModelOu.ps1 - OU creation plan generation
- New-TierModelOu.ps1 - OU creation execution
- Test-TierModelOu.ps1 - OU audit and validation

.NOTES
Author: TierModel Testing Team
Tags: Unit, OU, Operations
#>

BeforeAll {
    # Import the TierModel module
    $modulePath = Join-Path $PSScriptRoot '..\modules\TierModel\TierModel.psd1'
    Import-Module $modulePath -Force
    
    # Set correlation ID for logging
    InModuleScope TierModel {
        $script:CorrelationId = 'test-ou-ops-' + (New-Guid).ToString()
    }
}

Describe "Test-TierModelOuExists" -Tag 'Unit', 'OU', 'Exists' {
    
    BeforeEach {
        # Mock Write-TierModelLog to suppress output
        Mock Write-TierModelLog { } -ModuleName TierModel
    }
    
    Context "OU Existence - Found" {
        
        It "Should return Exists=true when OU is found" {
            # Arrange
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    Name = 'Tier0'
                    ObjectGUID = [guid]::NewGuid()
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOuExists -DistinguishedName 'OU=Tier0,DC=contoso,DC=com' -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Exists | Should -BeTrue
            $result.OU | Should -Not -BeNullOrEmpty
            $result.OU.Name | Should -Be 'Tier0'
            $result.Error | Should -BeNullOrEmpty
        }
        
        It "Should pass correct parameters to Get-ADOrganizationalUnit" {
            # Arrange
            $script:capturedIdentity = $null
            $script:capturedServer = $null
            
            Mock Get-ADOrganizationalUnit {
                param($Identity, $Server)
                $script:capturedIdentity = $Identity
                $script:capturedServer = $Server
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Admins,OU=Tier0,DC=contoso,DC=com'
                    Name = 'Admins'
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOuExists -DistinguishedName 'OU=Admins,OU=Tier0,DC=contoso,DC=com' -DomainController 'dc02.contoso.com'
            
            # Assert
            $result.Exists | Should -BeTrue
            $script:capturedIdentity | Should -Be 'OU=Admins,OU=Tier0,DC=contoso,DC=com'
            $script:capturedServer | Should -Be 'dc02.contoso.com'
        }
    }
    
    Context "OU Existence - Not Found" {
        
        It "Should return Exists=false when OU is not found" {
            # Arrange
            Mock Get-ADOrganizationalUnit {
                throw "Cannot find an object with identity: 'OU=NonExistent,DC=contoso,DC=com'"
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOuExists -DistinguishedName 'OU=NonExistent,DC=contoso,DC=com' -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Exists | Should -BeFalse
            $result.OU | Should -BeNullOrEmpty
            $result.Error | Should -Not -BeNullOrEmpty
            $result.Error | Should -BeLike "*Cannot find an object*"
        }
        
        It "Should handle AD errors gracefully" {
            # Arrange
            Mock Get-ADOrganizationalUnit {
                throw "Unable to contact the server"
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOuExists -DistinguishedName 'OU=Test,DC=contoso,DC=com' -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Exists | Should -BeFalse
            $result.Error | Should -Match "Unable to contact"
        }
    }
}

Describe "Get-TierModelOu" -Tag 'Unit', 'OU', 'Plan' {
    
    BeforeEach {
        # Mock logging
        Mock Write-TierModelLog { } -ModuleName TierModel
        
        # Mock helper functions
        Mock Resolve-TierModelDomainDN {
            'DC=contoso,DC=com'
        } -ModuleName TierModel
        
        Mock Resolve-TierModelOuPath {
            param($OuPath, $DomainDN)
            if ($OuPath -eq '{{domainDN}}') { return $DomainDN }
            if ($OuPath -eq 'OU=Tier0,{{domainDN}}') { return "OU=Tier0,$DomainDN" }
            return $OuPath
        } -ModuleName TierModel
    }
    
    Context "Plan Generation - Empty Config" {
        
        It "Should handle config without organizationUnits section" {
            # Arrange
            $config = [PSCustomObject]@{
                version = '1.0'
            }
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Actions | Should -BeNullOrEmpty
            $result.Warnings | Should -Contain "No organizationUnits section found in configuration"
            $result.Summary.TotalInConfig | Should -Be 0
        }
        
        It "Should handle config with null organizationUnits" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = $null
            }
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Actions | Should -BeNullOrEmpty
            $result.Warnings | Should -Contain "No organizationUnits section found in configuration"
        }
        
        It "Should handle config with empty organizationUnits array" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @()
            }
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Actions | Should -BeNullOrEmpty
            $result.Summary.TotalInConfig | Should -Be 0
        }
    }
    
    Context "Plan Generation - OU Existence Checking" {
        
        It "Should create action for non-existent OU" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                        description = 'Tier 0 OU'
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $false; OU = $null; Error = $null }
            } -ModuleName TierModel
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Actions.Count | Should -Be 1
            $result.Actions[0].Action | Should -Be 'CreateOU'
            $result.Actions[0].Name | Should -Be 'Tier0'
            $result.Actions[0].Path | Should -Be 'DC=contoso,DC=com'
            $result.Summary.ToCreate | Should -Be 1
        }
        
        It "Should not create action for existing OU" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ 
                    Exists = $true
                    OU = [PSCustomObject]@{ Name = 'Tier0'; DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' }
                    Error = $null 
                }
            } -ModuleName TierModel
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Actions | Should -BeNullOrEmpty
            $result.Summary.ToCreate | Should -Be 0
            $result.Summary.ExistingCount | Should -Be 1
        }
    }
    
    Context "Plan Generation - Dependency Ordering" {
        
        It "Should order OUs by depth (parent before child)" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Admins'
                        path = 'OU=Tier0,{{domainDN}}'
                    }
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists { @{ Exists = $false } } -ModuleName TierModel
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -IncludeDetails
            
            # Assert
            $result.Actions.Count | Should -Be 2
            # Parent OU (Tier0) should come first
            $result.Actions[0].Name | Should -Be 'Tier0'
            # Child OU (Admins) should come second
            $result.Actions[1].Name | Should -Be 'Admins'
            
            # Verify ordering details
            $result.Ordering | Should -Not -BeNullOrEmpty
            $result.Ordering[0].Depth | Should -BeLessOrEqual $result.Ordering[1].Depth
        }
        
        It "Should include ordering details when -IncludeDetails is specified" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists { @{ Exists = $false } } -ModuleName TierModel
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -IncludeDetails
            
            # Assert
            $result.PSObject.Properties.Name | Should -Contain 'Ordering'
            $result.Ordering[0].Name | Should -Be 'Tier0'
            $result.Ordering[0].Depth | Should -Be 0
        }
    }
    
    Context "Plan Generation - Error Handling" {
        
        It "Should collect errors for individual OU failures" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                throw "AD connection failed"
            } -ModuleName TierModel
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Errors.Count | Should -Be 1
            $result.Errors[0].Message | Should -BeLike "*Failed to analyze OU 'Tier0'*"
        }
        
        It "Should continue processing after individual OU error" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{ name = 'BadOU'; path = '{{domainDN}}' }
                    [PSCustomObject]@{ name = 'GoodOU'; path = '{{domainDN}}' }
                )
            }
            
            Mock Test-TierModelOuExists {
                param($DistinguishedName)
                if ($DistinguishedName -like '*BadOU*') {
                    throw "Simulated error"
                }
                @{ Exists = $false }
            } -ModuleName TierModel
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Errors.Count | Should -Be 1
            $result.Actions.Count | Should -Be 1
            $result.Actions[0].Name | Should -Be 'GoodOU'
        }
    }
    
    Context "Plan Generation - Path Resolution" {
        
        It "Should resolve placeholder paths correctly" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists { @{ Exists = $false } } -ModuleName TierModel
            
            # Act
            $null = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke Resolve-TierModelOuPath -ModuleName TierModel -Times 1 -ParameterFilter {
                $OuPath -eq '{{domainDN}}' -and $DomainDN -eq 'DC=contoso,DC=com'
            }
        }
    }
    
    Context "Plan Generation - Summary" {
        
        It "Should provide accurate summary statistics" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{ name = 'OU1'; path = '{{domainDN}}' }
                    [PSCustomObject]@{ name = 'OU2'; path = '{{domainDN}}' }
                    [PSCustomObject]@{ name = 'OU3'; path = '{{domainDN}}' }
                )
            }
            
            $existsCallCount = 0
            Mock Test-TierModelOuExists {
                $script:existsCallCount++
                @{ Exists = ($script:existsCallCount -eq 2) } # Only OU2 exists
            } -ModuleName TierModel
            
            # Act
            $result = Get-TierModelOu -Config $config -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Summary.TotalInConfig | Should -Be 3
            $result.Summary.ToCreate | Should -Be 2
            $result.Summary.ExistingCount | Should -Be 1
        }
    }
}

Describe "New-TierModelOu" -Tag 'Unit', 'OU', 'Create' {
    
    BeforeEach {
        # Mock logging and console output
        Mock Write-TierModelLog { } -ModuleName TierModel
        Mock Write-Host { } -ModuleName TierModel
    }
    
    Context "OU Creation - Basic" {
        
        It "Should create OU with basic properties" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{
                            name = 'Tier0'
                            path = 'DC=contoso,DC=com'
                            description = 'Tier 0 OU'
                        }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    Name = 'Tier0'
                    ObjectGUID = [guid]::NewGuid()
                }
            } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].Name | Should -Be 'Tier0'
            $result.Applied[0].ActionsPerformed | Should -Contain 'CreateOU'
            $result.Converged | Should -BeFalse
        }
        
        It "Should pass correct parameters to New-ADOrganizationalUnit" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'TestOU'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{
                            name = 'TestOU'
                            path = 'DC=contoso,DC=com'
                            description = 'Test OU Description'
                        }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=TestOU,DC=contoso,DC=com'
                    Name = 'TestOU'
                    ObjectGUID = [guid]::NewGuid()
                }
            } -ModuleName TierModel -ParameterFilter {
                $Name -eq 'TestOU' -and
                $Path -eq 'DC=contoso,DC=com' -and
                $Server -eq 'dc01.contoso.com' -and
                $Description -eq 'Test OU Description'
            }
            
            # Act
            $null = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke New-ADOrganizationalUnit -ModuleName TierModel -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'TestOU' -and $Description -eq 'Test OU Description'
            }
        }
        
        It "Should handle OU creation with protectFromAccidentalDeletion" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'ProtectedOU'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{
                            name = 'ProtectedOU'
                            path = 'DC=contoso,DC=com'
                            protectFromAccidentalDeletion = $true
                        }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=ProtectedOU,DC=contoso,DC=com'
                    Name = 'ProtectedOU'
                    ObjectGUID = [guid]::NewGuid()
                }
            } -ModuleName TierModel -ParameterFilter {
                $ProtectedFromAccidentalDeletion -eq $true
            }
            
            # Act
            $null = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke New-ADOrganizationalUnit -ModuleName TierModel -ParameterFilter {
                $ProtectedFromAccidentalDeletion -eq $true
            }
        }
    }
    
    Context "OU Creation - GPO Inheritance Blocking" {
        
        It "Should block GPO inheritance when configured" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{
                            name = 'Tier0'
                            path = 'DC=contoso,DC=com'
                            blockGpoInheritance = $true
                        }
                    }
                )
            }
            
            $mockOU = [PSCustomObject]@{
                DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                Name = 'Tier0'
                ObjectGUID = [guid]::NewGuid()
            }
            
            Mock New-ADOrganizationalUnit { $mockOU } -ModuleName TierModel
            Mock Set-GPInheritance { } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke Set-GPInheritance -ModuleName TierModel -Times 1 -ParameterFilter {
                $Target -eq 'OU=Tier0,DC=contoso,DC=com' -and
                $IsBlocked -eq 'Yes' -and
                $Server -eq 'dc01.contoso.com'
            }
            $result.Applied[0].ActionsPerformed | Should -Contain 'BlockGpoInheritance'
        }
        
        It "Should handle GPO inheritance blocking failure gracefully" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{
                            name = 'Tier0'
                            blockGpoInheritance = $true
                        }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    Name = 'Tier0'
                    ObjectGUID = [guid]::NewGuid()
                }
            } -ModuleName TierModel
            
            Mock Set-GPInheritance {
                throw "GPO inheritance blocking failed"
            } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].Warnings | Should -Not -BeNullOrEmpty
            $result.Applied[0].Warnings[0] | Should -BeLike "*Failed to block GPO inheritance*"
            $result.Applied[0].ActionsPerformed | Should -Not -Contain 'BlockGpoInheritance'
        }
    }
    
    Context "OU Creation - Security Inheritance" {
        
        It "Should disable security inheritance when configured" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{
                            name = 'Tier0'
                            disableInheritance = $true
                        }
                    }
                )
            }
            
            $mockOU = [PSCustomObject]@{
                DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                Name = 'Tier0'
                ObjectGUID = [guid]::NewGuid()
            }
            
            $mockAcl = New-Object System.Security.AccessControl.DirectorySecurity
            
            Mock New-ADOrganizationalUnit { $mockOU } -ModuleName TierModel
            Mock Get-Acl { $mockAcl } -ModuleName TierModel
            Mock Set-Acl { } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke Get-Acl -ModuleName TierModel -Times 1 -ParameterFilter {
                $Path -eq 'AD:\OU=Tier0,DC=contoso,DC=com'
            }
            Should -Invoke Set-Acl -ModuleName TierModel -Times 1
            $result.Applied[0].ActionsPerformed | Should -Contain 'DisableSecurityInheritance'
        }
        
        It "Should handle security inheritance failure gracefully" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{
                            name = 'Tier0'
                            disableInheritance = $true
                        }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    Name = 'Tier0'
                    ObjectGUID = [guid]::NewGuid()
                }
            } -ModuleName TierModel
            
            Mock Get-Acl {
                throw "ACL retrieval failed"
            } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].Warnings | Should -Not -BeNullOrEmpty
            $result.Applied[0].Warnings[0] | Should -BeLike "*Failed to disable security inheritance*"
        }
    }
    
    Context "OU Creation - WhatIf Support" {
        
        It "Should skip creation in WhatIf mode" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{ name = 'Tier0' }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit { } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com' -WhatIf
            
            # Assert
            $result.Applied.Count | Should -Be 0
            $result.Skipped.Count | Should -Be 1
            $result.Skipped[0].Reason | Should -Be 'WhatIf'
            Should -Invoke New-ADOrganizationalUnit -ModuleName TierModel -Times 0
        }
    }
    
    Context "OU Creation - Error Handling" {
        
        It "Should collect errors for failed OU creation" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'BadOU'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{ name = 'BadOU' }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit {
                throw "OU creation failed: Access denied"
            } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Errors.Count | Should -Be 1
            $result.Errors[0].Message | Should -BeLike "*Failed to create OU*"
            $result.Applied.Count | Should -Be 0
        }
        
        It "Should continue processing after individual OU failure" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'BadOU'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{ name = 'BadOU' }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'GoodOU'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{ name = 'GoodOU' }
                    }
                )
            }
            
            Mock New-ADOrganizationalUnit {
                param($Name)
                if ($Name -eq 'BadOU') {
                    throw "Access denied"
                }
                [PSCustomObject]@{
                    DistinguishedName = "OU=$Name,DC=contoso,DC=com"
                    Name = $Name
                    ObjectGUID = [guid]::NewGuid()
                }
            } -ModuleName TierModel
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Errors.Count | Should -Be 1
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].Name | Should -Be 'GoodOU'
        }
    }
    
    Context "OU Creation - Empty Plan" {
        
        It "Should handle plan with no actions" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @()
            }
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Applied.Count | Should -Be 0
            $result.Converged | Should -BeTrue
        }
        
        It "Should handle plan with only non-CreateOU actions" {
            # Arrange
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'SomeOtherAction'
                        Name = 'Test'
                    }
                )
            }
            
            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            
            # Assert
            $result.Applied.Count | Should -Be 0
            $result.Converged | Should -BeTrue
        }
    }
}

Describe "Test-TierModelOu" -Tag 'Unit', 'OU', 'Audit' {
    
    BeforeEach {
        # Mock logging and console output
        Mock Write-TierModelLog { } -ModuleName TierModel
        Mock Write-Host { } -ModuleName TierModel
        
        # Mock helper functions
        Mock Resolve-TierModelDomainDN {
            'DC=contoso,DC=com'
        } -ModuleName TierModel
        
        Mock Resolve-TierModelOuPath {
            param($OuPath, $DomainDN)
            if ($OuPath -eq '{{domainDN}}') { return $DomainDN }
            return $OuPath
        } -ModuleName TierModel
    }
    
    Context "Audit - Missing OUs" {
        
        It "Should detect missing OU" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $false; OU = $null; Error = $null }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.DriftFindings.Count | Should -Be 1
            $result.DriftFindings[0].Type | Should -Be 'Missing'
            $result.DriftFindings[0].Identifier | Should -Be 'Tier0'
            $result.Summary.MissingCount | Should -Be 1
        }
        
        It "Should not report drift for existing OU with no config requirements" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ 
                    Exists = $true
                    OU = [PSCustomObject]@{ 
                        DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                        Name = 'Tier0'
                    }
                }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.DriftFindings.Count | Should -Be 0
            $result.Summary.MissingCount | Should -Be 0
            $result.Summary.MismatchCount | Should -Be 0
        }
    }
    
    Context "Audit - Accidental Deletion Protection" {
        
        It "Should detect missing accidental deletion protection" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                        protectFromAccidentalDeletion = $true
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.DriftFindings.Count | Should -Be 1
            $result.DriftFindings[0].Type | Should -Be 'Mismatch'
            $result.DriftFindings[0].Identifier | Should -BeLike '*AccidentalDeletionProtection'
            $result.DriftFindings[0].ExpectedValue | Should -Be 'Protected'
            $result.Summary.MismatchCount | Should -Be 1
        }
        
        It "Should detect unexpected accidental deletion protection" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                        protectFromAccidentalDeletion = $false
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $true
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.DriftFindings.Count | Should -Be 1
            $result.DriftFindings[0].ExpectedValue | Should -Be 'Not Protected'
            $result.DriftFindings[0].ActualValue | Should -Be 'Protected'
        }
    }
    
    Context "Audit - GPO Inheritance" {
        
        It "Should detect missing GPO inheritance blocking" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                        blockGpoInheritance = $true
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            Mock Get-GPInheritance {
                [PSCustomObject]@{
                    Path = 'OU=Tier0,DC=contoso,DC=com'
                    GpoInheritanceBlocked = $false
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.DriftFindings.Count | Should -Be 1
            $result.DriftFindings[0].Identifier | Should -BeLike '*GpoInheritance'
            $result.DriftFindings[0].ExpectedValue | Should -Be 'Blocked'
            $result.DriftFindings[0].ActualValue | Should -Be 'Not Blocked'
        }
        
        It "Should handle GPO inheritance check failure" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                        blockGpoInheritance = $true
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            Mock Get-GPInheritance {
                throw "GPO module not available"
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.Warnings.Count | Should -BeGreaterThan 0
            $result.Warnings[0] | Should -BeLike "*Failed to check GPO inheritance*"
        }
    }
    
    Context "Audit - Security Inheritance" {
        
        It "Should detect incorrect security inheritance (should be disabled)" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                        disableInheritance = $true
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            $mockAcl = New-Object System.Security.AccessControl.DirectorySecurity
            # AreAccessRulesProtected = false means inheritance is enabled
            
            Mock Get-Acl { $mockAcl } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.DriftFindings.Count | Should -Be 1
            $result.DriftFindings[0].Identifier | Should -BeLike '*SecurityInheritance'
            $result.DriftFindings[0].ExpectedValue | Should -Be 'Disabled'
            $result.DriftFindings[0].ActualValue | Should -Be 'Enabled'
        }
        
        It "Should detect incorrect security inheritance (should be enabled)" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                        disableInheritance = $false
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            $mockAcl = New-Object System.Security.AccessControl.DirectorySecurity
            # Simulate protected ACL (inheritance disabled)
            $mockAcl.SetAccessRuleProtection($true, $false)
            
            Mock Get-Acl { $mockAcl } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.DriftFindings.Count | Should -Be 1
            $result.DriftFindings[0].ExpectedValue | Should -Be 'Enabled'
            $result.DriftFindings[0].ActualValue | Should -Be 'Disabled'
        }
    }
    
    Context "Audit - Summary and Statistics" {
        
        It "Should provide accurate summary statistics" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{ name = 'OU1'; path = '{{domainDN}}' }
                    [PSCustomObject]@{ name = 'OU2'; path = '{{domainDN}}'; protectFromAccidentalDeletion = $true }
                    [PSCustomObject]@{ name = 'OU3'; path = '{{domainDN}}' }
                )
            }
            
            $script:callCount = 0
            Mock Test-TierModelOuExists {
                $script:callCount++
                @{ 
                    Exists = ($script:callCount -ne 1) # OU1 is missing
                    OU = if ($script:callCount -ne 1) { [PSCustomObject]@{ DistinguishedName = "OU=OU$script:callCount,DC=contoso,DC=com" } }
                }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                param($Identity)
                [PSCustomObject]@{
                    DistinguishedName = $Identity
                    ProtectedFromAccidentalDeletion = $false # OU2 should have this as $true
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.Summary.TotalChecked | Should -Be 3
            $result.Summary.MissingCount | Should -Be 1
            $result.Summary.MismatchCount | Should -Be 1
            $result.Summary.DriftCount | Should -Be 2
        }
    }
    
    Context "Audit - IncludeResolvedPaths" {
        
        It "Should include resolved paths when flag is set" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{
                        name = 'Tier0'
                        path = '{{domainDN}}'
                    }
                )
            }
            
            Mock Test-TierModelOuExists {
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -IncludeResolvedPaths -Silent
            
            # Assert
            $result.PSObject.Properties.Name | Should -Contain 'ResolvedPaths'
            $result.ResolvedPaths.Count | Should -Be 1
            $result.ResolvedPaths[0].Name | Should -Be 'Tier0'
            $result.ResolvedPaths[0].OriginalPath | Should -Be '{{domainDN}}'
        }
    }
    
    Context "Audit - Error Handling" {
        
        It "Should handle empty config gracefully" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = $null
            }
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.Warnings | Should -Contain "No organizationUnits section found in configuration"
            $result.Summary.TotalChecked | Should -Be 0
        }
        
        It "Should continue processing after individual OU error" {
            # Arrange
            $config = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{ name = 'BadOU'; path = '{{domainDN}}' }
                    [PSCustomObject]@{ name = 'GoodOU'; path = '{{domainDN}}' }
                )
            }
            
            $script:callCount = 0
            Mock Test-TierModelOuExists {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    throw "AD Error"
                }
                @{ Exists = $true; OU = [PSCustomObject]@{ DistinguishedName = 'OU=GoodOU,DC=contoso,DC=com' } }
            } -ModuleName TierModel
            
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{
                    DistinguishedName = 'OU=GoodOU,DC=contoso,DC=com'
                    ProtectedFromAccidentalDeletion = $false
                }
            } -ModuleName TierModel
            
            # Act
            $result = Test-TierModelOu -Config $config -DomainController 'dc01.contoso.com' -Silent
            
            # Assert
            $result.Errors.Count | Should -Be 1
            $result.Summary.TotalChecked | Should -Be 2
        }
    }
}
