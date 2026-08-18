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

    BeforeAll {
        Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction SilentlyContinue

        # FakeLdapAttr used by LdapConnection mocks in Phase-2 tests (same as Unit.CanonicalAcl.Tests.ps1)
        if (-not ('FakeLdapAttrOu' -as [type])) {
            Add-Type @'
using System;
public class FakeLdapAttrOu {
    public byte[] Bytes;
    public FakeLdapAttrOu(byte[] bytes) { Bytes = bytes; }
    public object[] GetValues(Type t) { return new object[] { Bytes }; }
}
'@
        }

        # Build canonical SD bytes (explicit Deny -> explicit Allow) for Phase-2 read mocks.
        $owner = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'
        $ev    = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'
        $au    = [System.Security.Principal.SecurityIdentifier]'S-1-5-11'
        $daclC = New-Object System.Security.AccessControl.RawAcl([System.Security.AccessControl.GenericAcl]::AclRevision, 4)
        $denyE  = New-Object System.Security.AccessControl.CommonAce([System.Security.AccessControl.AceFlags]::None, [System.Security.AccessControl.AceQualifier]::AccessDenied,  0x20094, $ev, $false, $null)
        $allowA = New-Object System.Security.AccessControl.CommonAce([System.Security.AccessControl.AceFlags]::None, [System.Security.AccessControl.AceQualifier]::AccessAllowed, 0x20094, $au, $false, $null)
        $daclC.InsertAce(0, $denyE); $daclC.InsertAce(1, $allowA)
        # Build with DiscretionaryAclProtected flag so AreAccessRulesProtected = true on readback
        $ctrlProtected = [System.Security.AccessControl.ControlFlags]::DiscretionaryAclPresent -bor [System.Security.AccessControl.ControlFlags]::DiscretionaryAclProtected
        $sdProtected = New-Object System.Security.AccessControl.RawSecurityDescriptor($ctrlProtected, $owner, $owner, $null, $daclC)
        $script:OuProtectedSdBytes = New-Object byte[] $sdProtected.BinaryLength
        $sdProtected.GetBinaryForm($script:OuProtectedSdBytes, 0)

        # Also plain canonical (not protected) for Phase-2 initial read
        $ctrlPlain = [System.Security.AccessControl.ControlFlags]::DiscretionaryAclPresent
        $sdPlain = New-Object System.Security.AccessControl.RawSecurityDescriptor($ctrlPlain, $owner, $owner, $null, $daclC)
        $script:OuCanonicalSdBytes = New-Object byte[] $sdPlain.BinaryLength
        $sdPlain.GetBinaryForm($script:OuCanonicalSdBytes, 0)
    }

    BeforeEach {
        # Mock logging and console output
        Mock Write-TierModelLog { } -ModuleName TierModel
        Mock Write-Host { } -ModuleName TierModel
        # Phase-1 canonical verify — return canonical immediately so no remediation is needed
        Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true } } -ModuleName TierModel
        Mock Repair-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; WasAlreadyCanonical = $false; AceCountBefore = 2; AceCountAfter = 2 } } -ModuleName TierModel
        # Set-ADOrganizationalUnit stub for PFAD final step
        Mock Set-ADOrganizationalUnit { } -ModuleName TierModel
        # Start-Sleep stub to keep retry loops fast
        Mock Start-Sleep { } -ModuleName TierModel
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
        
        It "Should handle OU creation with protectFromAccidentalDeletion — PFAD applied in Phase-1 final step via Set-ADOrganizationalUnit" {
            # Phase-1 final step: New-ADOrganizationalUnit is called WITHOUT ProtectedFromAccidentalDeletion,
            # then Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $true is called separately.
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
            } -ModuleName TierModel

            # Act
            $null = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Assert: New-ADOrganizationalUnit was called WITHOUT -ProtectedFromAccidentalDeletion
            Should -Invoke New-ADOrganizationalUnit -ModuleName TierModel -Times 1 -Exactly
            Should -Invoke New-ADOrganizationalUnit -ModuleName TierModel -Times 0 -ParameterFilter {
                $PSBoundParameters.ContainsKey('ProtectedFromAccidentalDeletion') -and $ProtectedFromAccidentalDeletion -eq $true
            }
            # Assert: Set-ADOrganizationalUnit was called WITH -ProtectedFromAccidentalDeletion $true
            Should -Invoke Set-ADOrganizationalUnit -ModuleName TierModel -Times 1 -ParameterFilter {
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
            Mock Get-GPInheritance { [PSCustomObject]@{ GpoInheritanceBlocked = $true } } -ModuleName TierModel
            
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
            Mock Get-GPInheritance { [PSCustomObject]@{ GpoInheritanceBlocked = $false } } -ModuleName TierModel
            Mock Start-Sleep { } -ModuleName TierModel

            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Assert - OU is still created, but the unverified block is a surfaced ERROR (not a hidden warning)
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].ActionsPerformed | Should -Not -Contain 'BlockGpoInheritance'
            @($result.Errors | Where-Object { $_.Code -eq 'BlockGpoInheritanceUnverified' }).Count | Should -BeGreaterThan 0
            @($result.Errors)[0].Message | Should -BeLike "*Block GPO Inheritance flag was not set for OU*"
        }

        It "Should record an error when GPO inheritance cannot be verified (silent no-op)" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{ name = 'Tier0'; blockGpoInheritance = $true }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel
            # Set-GPInheritance returns without error, but the setting never persists (silent no-op)
            Mock Set-GPInheritance { } -ModuleName TierModel
            Mock Get-GPInheritance { [PSCustomObject]@{ GpoInheritanceBlocked = $false } } -ModuleName TierModel
            Mock Start-Sleep { } -ModuleName TierModel

            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            $result.Applied[0].ActionsPerformed | Should -Not -Contain 'BlockGpoInheritance'
            @($result.Errors | Where-Object { $_.Code -eq 'BlockGpoInheritanceUnverified' }).Count | Should -BeGreaterThan 0
        }

        It "Should converge when GPO inheritance verifies on a later retry" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'
                        Name = 'Tier0'
                        Path = 'DC=contoso,DC=com'
                        Data = [PSCustomObject]@{ name = 'Tier0'; blockGpoInheritance = $true }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel
            Mock Set-GPInheritance { } -ModuleName TierModel
            $global:tmGpoVerifyCall = 0
            Mock Get-GPInheritance {
                $global:tmGpoVerifyCall++
                [PSCustomObject]@{ GpoInheritanceBlocked = ($global:tmGpoVerifyCall -ge 2) }
            } -ModuleName TierModel
            Mock Start-Sleep { } -ModuleName TierModel

            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Verified on the 2nd attempt -> success recorded, no error
            $result.Applied[0].ActionsPerformed | Should -Contain 'BlockGpoInheritance'
            @($result.Errors | Where-Object { $_.Code -eq 'BlockGpoInheritanceUnverified' }).Count | Should -Be 0
            Remove-Variable -Name tmGpoVerifyCall -Scope Global -ErrorAction SilentlyContinue
        }
    }
    
    Context "OU Creation - Security Inheritance" {

        # Phase-2 uses DC-pinned LdapConnection (no Get-Acl / Set-Acl).
        # BUG-03 (product bug): Phase-2 verify checks $rbCsd.AreAccessRulesProtected but CommonSecurityDescriptor
        # has no such property (it's on ObjectSecurity); the check always returns $null (falsy), so Phase 2
        # always emits DisableSecurityInheritanceUnverified even on success.
        # The correct check is ($rbCsd.ControlFlags -band DiscretionaryAclProtected) -ne 0.
        # Tests below reflect the ACTUAL (buggy) behavior until BUG-03 is fixed.

        BeforeEach {
            $global:_OuPhase2SdBytes = $script:OuProtectedSdBytes

            Mock New-Object -ModuleName TierModel `
                -ParameterFilter { $TypeName -eq 'System.DirectoryServices.Protocols.LdapConnection' } `
                -MockWith {
                    $conn = [PSCustomObject]@{ SessionOptions = [PSCustomObject]@{ Signing = $false; Sealing = $false } }
                    $conn | Add-Member -MemberType ScriptMethod -Name Bind -Value { }
                    $conn | Add-Member -MemberType ScriptMethod -Name SendRequest -Value {
                        param($r)
                        if ($r -is [System.DirectoryServices.Protocols.ModifyRequest]) { return $null }
                        $attr  = [FakeLdapAttrOu]::new([byte[]]$global:_OuPhase2SdBytes)
                        $entry = [PSCustomObject]@{ Attributes = @{ 'ntSecurityDescriptor' = $attr } }
                        return [PSCustomObject]@{ Entries = @($entry) }
                    }
                    return $conn
                }
        }

        AfterEach {
            Remove-Variable -Name _OuPhase2SdBytes -Scope Global -ErrorAction SilentlyContinue
        }

        It "OU without disableInheritance skips Phase 2 — no DisableSecurityInheritanceUnverified error" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }   # no disableInheritance
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel

            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            $result.Applied.Count | Should -Be 1
            @($result.Errors | Where-Object { $_.Code -eq 'DisableSecurityInheritanceUnverified' }).Count | Should -Be 0
        }
    }

    Context "OU Creation - WhatIf Support" {

        It "Should skip creation in WhatIf mode — Skipped populated, New-ADOrganizationalUnit not called" {
            # NOTE (product bug BUG-01): New-TierModelOu WhatIf path returns Applied = $skipped.ToArray()
            # instead of @().  Applied.Count == Skipped.Count until fixed.  Skipped.Count and Reason are correct.
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

            # Assert core WhatIf semantics
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

        It "Phase 1 hard-stops after OU creation failure — GoodOU is NOT processed (new phased design)" {
            # The old design continued to the next OU on failure.
            # The new phased design throws Phase1Abort on first CreateOU failure and halts Phase 1.
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

            # Assert: Phase 1 hard-stops on BadOU failure — GoodOU is NOT created
            $result.Errors.Count | Should -Be 1
            $result.Errors[0].Code | Should -Be 'CreateOuFailed'
            $result.Applied.Count | Should -Be 0   # hard-stop: no OU processed after failure
        }
    }
    
    Context "OU Creation - Empty Plan" {

        It "Should handle plan with no actions" {
            # Arrange
            $plan = [PSCustomObject]@{ Actions = @() }

            # Act
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Assert
            $result.Applied.Count | Should -Be 0
            $result.Converged | Should -BeTrue
        }

        It "Should handle plan with only non-CreateOU actions" {
            $plan = [PSCustomObject]@{ Actions = @([PSCustomObject]@{ Action = 'SomeOtherAction'; Name = 'Test' }) }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            $result.Applied.Count | Should -Be 0
            $result.Converged | Should -BeTrue
        }
    }

    # =========================================================================
    Context "Phase orchestration — P1 creates OUs WITHOUT PFAD then applies it" {

        It "New-ADOrganizationalUnit is called WITHOUT -ProtectedFromAccidentalDeletion" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0'; protectFromAccidentalDeletion = $true }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel

            $null = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Must have been called without the PFAD param
            Should -Invoke New-ADOrganizationalUnit -ModuleName TierModel -Times 1 -Exactly
            Should -Invoke New-ADOrganizationalUnit -ModuleName TierModel -Times 0 -ParameterFilter {
                $PSBoundParameters.ContainsKey('ProtectedFromAccidentalDeletion') -and $ProtectedFromAccidentalDeletion -eq $true
            }
        }

        It "Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion is called AFTER create (Phase-1 final step)" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0'; protectFromAccidentalDeletion = $true }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel

            $null = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            Should -Invoke Set-ADOrganizationalUnit -ModuleName TierModel -Times 1 -ParameterFilter {
                $ProtectedFromAccidentalDeletion -eq $true
            }
        }

        It "Result object carries CanonicalRemediations field" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel

            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            $result.PSObject.Properties.Name | Should -Contain 'CanonicalRemediations'
        }
    }

    Context "Phase orchestration — canonical remediation is SILENT (not an error)" {

        It "Non-canonical OU after create is repaired silently — no Errors entry" {
            # Test-TierModelCanonicalAcl returns non-canonical on first call, canonical after repair
            $script:canonCallCount = 0
            Mock Test-TierModelCanonicalAcl -ModuleName TierModel {
                $script:canonCallCount++
                # First call: non-canonical; second call (post-repair): canonical
                if ($script:canonCallCount -le 1) {
                    [PSCustomObject]@{ IsCanonical = $false }
                } else {
                    [PSCustomObject]@{ IsCanonical = $true }
                }
            }
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel

            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Repair was called but no error entry added
            Should -Invoke Repair-TierModelCanonicalAcl -ModuleName TierModel -Times 1
            $result.Errors.Count | Should -Be 0
            $result.Applied.Count | Should -Be 1
        }

        It "CanonicalRemediations counter is incremented for each silent repair" {
            # NOTE (product bug BUG-02): $script:canonicalRemediations++ in Invoke-CanonicalVerifyAndRemediate
            # increments the TierModel module script-scope variable, but the return value reads the outer
            # function's local $canonicalRemediations (stays 0). Counter is always 0 until fixed.
            # We verify the repair DID happen via Should -Invoke instead.
            $script:canonCallCount2 = 0
            Mock Test-TierModelCanonicalAcl -ModuleName TierModel {
                $script:canonCallCount2++
                if ($script:canonCallCount2 -le 1) { [PSCustomObject]@{ IsCanonical = $false } }
                else                               { [PSCustomObject]@{ IsCanonical = $true  } }
            }
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel

            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Verify repair was invoked (confirms silent remediation path executed)
            Should -Invoke Repair-TierModelCanonicalAcl -ModuleName TierModel -Times 1
            $result.CanonicalRemediations | Should -Be 1
        }
    }

    Context "Phase orchestration — CanonicalRemediationFailed hard-stops Phase 1" {

        It "Persistent non-canonical after max attempts -> CanonicalRemediationFailed error and Phase 1 aborts" {
            # Test-TierModelCanonicalAcl always returns non-canonical (remediation never helps)
            Mock Test-TierModelCanonicalAcl -ModuleName TierModel { [PSCustomObject]@{ IsCanonical = $false } }
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier1'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier1' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit {
                param($Name)
                [PSCustomObject]@{ DistinguishedName = "OU=$Name,DC=contoso,DC=com"; Name = $Name; ObjectGUID = [guid]::NewGuid() }
            } -ModuleName TierModel

            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            # Hard stop: CanonicalRemediationFailed error present
            @($result.Errors | Where-Object { $_.Code -eq 'CanonicalRemediationFailed' }).Count | Should -BeGreaterThan 0
            # Tier1 was NOT processed (hard stop after Tier0 failure)
            ($result.Applied | Where-Object { $_.Name -eq 'Tier1' }) | Should -BeNullOrEmpty
        }
    }

    Context "Phase orchestration — top-down ordering" {

        It "OUs are created parent-before-child (top-down); order of New-ADOrganizationalUnit calls matches plan order" {
            $callOrder = [System.Collections.Generic.List[string]]::new()
            Mock New-ADOrganizationalUnit -ModuleName TierModel {
                param($Name, $Path)
                $callOrder.Add($Name)
                [PSCustomObject]@{ DistinguishedName = "OU=$Name,$Path"; Name = $Name; ObjectGUID = [guid]::NewGuid() }
            }

            # Plan is already top-down (parent first, then child)
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Admins'; Path = 'OU=Tier0,DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Admins' }
                    }
                )
            }

            $null = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'

            $callOrder[0] | Should -Be 'Tier0'
            $callOrder[1] | Should -Be 'Admins'
        }
    }

    Context "Phase orchestration — result object shape" {

        It "Result has all required fields: Applied, Skipped, Errors, DurationMs, Converged, CorrelationId, CanonicalRemediations" {
            $plan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'Applied'
            $props | Should -Contain 'Skipped'
            $props | Should -Contain 'Errors'
            $props | Should -Contain 'DurationMs'
            $props | Should -Contain 'Converged'
            $props | Should -Contain 'CorrelationId'
            $props | Should -Contain 'CanonicalRemediations'
        }

        It "CorrelationId is a non-empty string" {
            $plan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            $result.CorrelationId | Should -Not -BeNullOrEmpty
        }
    }

    # =========================================================================
    Context "BUG-01 regression — WhatIf returns Applied=@() not the skipped entries" {

        It "BUG-01: WhatIf Applied.Count is 0 (not equal to Skipped.Count)" {
            # BUG-01 was: WhatIf path returned Applied = $skipped.ToArray() instead of @().
            # Fixed: WhatIf path now explicitly returns Applied = @().
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier1'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier1' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit { } -ModuleName TierModel
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com' -WhatIf
            $result.Applied.Count | Should -Be 0
            $result.Skipped.Count | Should -Be 2   # sanity: skipped is still populated
        }

        It "BUG-01: WhatIf Applied is an empty array (not from Skipped)" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit { } -ModuleName TierModel
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com' -WhatIf
            # Applied must be an array with 0 elements (not $null, and not the skipped entries)
            $result.Applied | Should -HaveCount 0
            # If BUG-01 were still present, Applied[0].Reason would be 'WhatIf'
            ($result.Applied | Where-Object { $_.Reason -eq 'WhatIf' }) | Should -BeNullOrEmpty
        }

        It "BUG-01: WhatIf CanonicalRemediations is 0" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit { } -ModuleName TierModel
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com' -WhatIf
            $result.CanonicalRemediations | Should -Be 0
        }
    }

    # =========================================================================
    Context "BUG-02 regression — CanonicalRemediations counter increments correctly" {

        It "BUG-02: CanonicalRemediations is >0 when a remediation was performed (not stuck at 0)" {
            # BUG-02 was: Invoke-CanonicalVerifyAndRemediate used $script:canonicalRemediations++ which
            # increments the module script-scope variable, not the outer function's local counter.
            # Fixed: Set-Variable -Name canonicalRemediations -Value ($canonicalRemediations + 1) -Scope 1
            $global:_bug02VerifyCall = 0
            Mock Test-TierModelCanonicalAcl -ModuleName TierModel {
                $global:_bug02VerifyCall = $global:_bug02VerifyCall + 1
                # First call (post-create): non-canonical; second call (post-repair): canonical
                [PSCustomObject]@{ IsCanonical = ($global:_bug02VerifyCall -gt 1) }
            }
            Mock Repair-TierModelCanonicalAcl -ModuleName TierModel {
                [PSCustomObject]@{ IsCanonical = $true; WasAlreadyCanonical = $false }
            }
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit -ModuleName TierModel {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            $result.CanonicalRemediations | Should -BeGreaterThan 0
            Remove-Variable -Name _bug02VerifyCall -Scope Global -ErrorAction SilentlyContinue
        }

        It "BUG-02: CanonicalRemediations stays 0 when all OUs are already canonical (no spurious increment)" {
            # All canonical → no Repair call → counter must be exactly 0, never falsely incremented
            Mock Test-TierModelCanonicalAcl -ModuleName TierModel { [PSCustomObject]@{ IsCanonical = $true } }
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0' }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier1'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier1' }
                    }
                )
            }
            Mock New-ADOrganizationalUnit -ModuleName TierModel {
                param($Name)
                [PSCustomObject]@{ DistinguishedName = "OU=$Name,DC=contoso,DC=com"; Name = $Name; ObjectGUID = [guid]::NewGuid() }
            }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            $result.CanonicalRemediations | Should -Be 0
        }

        It "BUG-02: CanonicalRemediations reflects count for multiple OUs (lab-confirmed: N DI-protected OUs → N remediations)" {
            # Lab proved: 7 OUs with disableInheritance under an inherited root Deny all need remediation.
            # Here: 3 OUs all require one remediation each → counter must equal 3.
            $global:_bug02MultiCall = 0
            Mock Test-TierModelCanonicalAcl -ModuleName TierModel {
                $global:_bug02MultiCall = $global:_bug02MultiCall + 1
                # Every other call: first call per OU = non-canonical; second call (post-repair) = canonical
                $isEven = ($global:_bug02MultiCall % 2) -eq 0
                [PSCustomObject]@{ IsCanonical = $isEven }
            }
            Mock Repair-TierModelCanonicalAcl -ModuleName TierModel {
                [PSCustomObject]@{ IsCanonical = $true; WasAlreadyCanonical = $false }
            }
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{ Action = 'CreateOU'; Name = 'OU1'; Path = 'DC=contoso,DC=com'; Data = [PSCustomObject]@{ name = 'OU1' } }
                    [PSCustomObject]@{ Action = 'CreateOU'; Name = 'OU2'; Path = 'DC=contoso,DC=com'; Data = [PSCustomObject]@{ name = 'OU2' } }
                    [PSCustomObject]@{ Action = 'CreateOU'; Name = 'OU3'; Path = 'DC=contoso,DC=com'; Data = [PSCustomObject]@{ name = 'OU3' } }
                )
            }
            Mock New-ADOrganizationalUnit -ModuleName TierModel {
                param($Name)
                [PSCustomObject]@{ DistinguishedName = "OU=$Name,DC=contoso,DC=com"; Name = $Name; ObjectGUID = [guid]::NewGuid() }
            }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            $result.CanonicalRemediations | Should -Be 3
            Remove-Variable -Name _bug02MultiCall -Scope Global -ErrorAction SilentlyContinue
        }
    }

    # =========================================================================
    Context "BUG-03 regression — Phase 2 verify uses ControlFlags.DiscretionaryAclProtected" {

        # BUG-03 context has BeforeEach / AfterEach that sets up the LdapConnection mock
        # (sets $global:_OuPhase2SdBytes = $script:OuProtectedSdBytes).
        # These tests are nested INSIDE the Phase 2 LdapConnection mock context.
        # We need to reference the BeforeEach in "OU Creation - Security Inheritance" context.
        # Since Pester scoping doesn't allow nesting across Contexts, we replicate the mock inline.

        BeforeEach {
            $global:_OuPhase2SdBytes = $script:OuProtectedSdBytes
            Mock New-Object -ModuleName TierModel `
                -ParameterFilter { $TypeName -eq 'System.DirectoryServices.Protocols.LdapConnection' } `
                -MockWith {
                    $conn = [PSCustomObject]@{ SessionOptions = [PSCustomObject]@{ Signing = $false; Sealing = $false } }
                    $conn | Add-Member -MemberType ScriptMethod -Name Bind -Value { }
                    $conn | Add-Member -MemberType ScriptMethod -Name SendRequest -Value {
                        param($r)
                        if ($r -is [System.DirectoryServices.Protocols.ModifyRequest]) { return $null }
                        $attr  = [FakeLdapAttrOu]::new([byte[]]$global:_OuPhase2SdBytes)
                        $entry = [PSCustomObject]@{ Attributes = @{ 'ntSecurityDescriptor' = $attr } }
                        return [PSCustomObject]@{ Entries = @($entry) }
                    }
                    return $conn
                }
        }

        AfterEach {
            Remove-Variable -Name _OuPhase2SdBytes -Scope Global -ErrorAction SilentlyContinue
        }

        It "BUG-03: Phase 2 verify succeeds when DiscretionaryAclProtected ControlFlag bit IS set in readback" {
            # BUG-03 was: ($rbCsd.AreAccessRulesProtected) — property doesn't exist on CommonSecurityDescriptor,
            # always returns $null (falsy), Phase 2 always emitted DisableSecurityInheritanceUnverified.
            # Fixed: ($rbCsd.ControlFlags -band DiscretionaryAclProtected) -ne 0.
            # OuProtectedSdBytes has DiscretionaryAclProtected set → secVerified=$true → no error.
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0'; disableInheritance = $true }
                    }
                )
            }
            Mock New-ADOrganizationalUnit -ModuleName TierModel {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            @($result.Errors | Where-Object { $_.Code -eq 'DisableSecurityInheritanceUnverified' }).Count | Should -Be 0
            $result.Applied[0].ActionsPerformed | Should -Contain 'DisableSecurityInheritance'
        }

        It "BUG-03: Phase 2 records DisableSecurityInheritanceUnverified when DiscretionaryAclProtected bit NOT set" {
            # Override to use non-protected SD bytes for readback
            $global:_OuPhase2SdBytes = $script:OuCanonicalSdBytes   # canonical DACL but NOT protected
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateOU'; Name = 'Tier0'; Path = 'DC=contoso,DC=com'
                        Data   = [PSCustomObject]@{ name = 'Tier0'; disableInheritance = $true }
                    }
                )
            }
            Mock New-ADOrganizationalUnit -ModuleName TierModel {
                [PSCustomObject]@{ DistinguishedName = 'OU=Tier0,DC=contoso,DC=com'; Name = 'Tier0'; ObjectGUID = [guid]::NewGuid() }
            }
            $result = New-TierModelOu -Plan $plan -DomainController 'dc01.contoso.com'
            @($result.Errors | Where-Object { $_.Code -eq 'DisableSecurityInheritanceUnverified' }).Count | Should -BeGreaterThan 0
        }

        It "BUG-03: ControlFlags.DiscretionaryAclProtected bit correctly classifies a protected SD" {
            # Direct offline test of the exact ControlFlags check (no New-TierModelOu call needed)
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $script:OuProtectedSdBytes, 0)
            $isProtected = (($csd.ControlFlags -band [System.Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0)
            $isProtected | Should -Be $true
        }

        It "BUG-03: ControlFlags.DiscretionaryAclProtected correctly classifies a NON-protected SD as unprotected" {
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $script:OuCanonicalSdBytes, 0)
            $isProtected = (($csd.ControlFlags -band [System.Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0)
            $isProtected | Should -Be $false
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
