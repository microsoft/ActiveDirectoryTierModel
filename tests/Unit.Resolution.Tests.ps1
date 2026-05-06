<#
.SYNOPSIS
Unit tests for TierModel resolution helper functions.

.DESCRIPTION
Comprehensive Pester v5 tests for resolution functions:
- Resolve-TierModelDomainDN.ps1 - Domain DN resolution with caching
- Resolve-TierModelPlaceholder.ps1 - Placeholder substitution logic
- Resolve-TierModelOuPath.ps1 - OU path resolution wrapper
- Resolve-TierModelGuid.ps1 - GUID mapping resolution
- Resolve-DomainSpecificGuid.ps1 - Schema-based GUID resolution

.NOTES
Author: TierModel Testing Team
Tags: Unit, Resolution, Helpers
#>

BeforeAll {
    # Import the TierModel module
    $modulePath = Join-Path $PSScriptRoot '..\modules\TierModel\TierModel.psd1'
    Import-Module $modulePath -Force
    
    # Load GUID mappings for testing
    $guidMappingsPath = Join-Path $PSScriptRoot '..\config\tiermodel-guid-mappings.json'
    $script:TestGuidMappings = Get-Content $guidMappingsPath -Raw | ConvertFrom-Json
}

Describe "Resolve-TierModelDomainDN" -Tag 'Unit', 'Resolution', 'DomainDN' {
    
    BeforeEach {
        # Clear cached values before each test - must be done in module scope
        InModuleScope TierModel {
            $script:CachedDomainDN = $null
            $script:CachedDomainController = $null
        }
        
        # Mock Write-TierModelLog to suppress output
        Mock Write-TierModelLog { } -ModuleName TierModel
    }
    
    Context "Domain DN Resolution" {
        
        It "Should query Get-ADDomain and return DistinguishedName" {
            # Arrange
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            # Act
            $result = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            
            # Assert
            $result | Should -Be 'DC=contoso,DC=com'
            Should -Invoke Get-ADDomain -ModuleName TierModel -Times 1 -Exactly
        }
        
        It "Should pass DomainController to Get-ADDomain" {
            # Arrange
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=fabrikam,DC=com'
                }
            } -ModuleName TierModel -ParameterFilter { $Server -eq 'dc02.fabrikam.com' }
            
            # Act
            $result = Resolve-TierModelDomainDN -DomainController 'dc02.fabrikam.com'
            
            # Assert
            $result | Should -Be 'DC=fabrikam,DC=com'
            Should -Invoke Get-ADDomain -ModuleName TierModel -ParameterFilter { $Server -eq 'dc02.fabrikam.com' }
        }
    }
    
    Context "Caching Behavior" {
        
        It "Should cache domain DN after first query" {
            # Arrange
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            # Act
            $result1 = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            $result2 = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            
            # Assert
            $result1 | Should -Be 'DC=contoso,DC=com'
            $result2 | Should -Be 'DC=contoso,DC=com'
            Should -Invoke Get-ADDomain -ModuleName TierModel -Times 1 -Exactly
        }
        
        It "Should refresh cache when DomainController changes" {
            # Arrange - Mock different responses based on server
            $script:callCount = 0
            Mock Get-ADDomain {
                param($Server)
                $script:callCount++
                if ($Server -eq 'dc01.contoso.com') {
                    [PSCustomObject]@{ DistinguishedName = 'DC=contoso,DC=com' }
                } else {
                    [PSCustomObject]@{ DistinguishedName = 'DC=fabrikam,DC=com' }
                }
            } -ModuleName TierModel
            
            # Act
            $result1 = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            $result2 = Resolve-TierModelDomainDN -DomainController 'dc02.fabrikam.com'
            
            # Assert
            $result1 | Should -Be 'DC=contoso,DC=com'
            $result2 | Should -Be 'DC=fabrikam,DC=com'
            $script:callCount | Should -Be 2
        }
        
        It "Should use cached value when same DomainController is queried again" {
            # Arrange - First call will cache
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            # Act - First call caches, second call uses cache
            $result1 = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            $result2 = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            
            # Assert
            $result1 | Should -Be 'DC=contoso,DC=com'
            $result2 | Should -Be 'DC=contoso,DC=com'
            Should -Invoke Get-ADDomain -ModuleName TierModel -Times 1 -Exactly
        }
    }
    
    Context "Error Handling" {
        
        It "Should throw error when Get-ADDomain fails" {
            # Arrange
            Mock Get-ADDomain {
                throw "Unable to contact domain controller"
            } -ModuleName TierModel
            
            # Act & Assert
            { Resolve-TierModelDomainDN -DomainController 'invalid.dc.com' } | 
                Should -Throw -ExpectedMessage "*Failed to resolve domain DN*"
        }
        
        It "Should log error when Get-ADDomain fails" {
            # Arrange
            Mock Get-ADDomain {
                throw "Unable to contact domain controller"
            } -ModuleName TierModel
            
            # Act
            try {
                Resolve-TierModelDomainDN -DomainController 'invalid.dc.com'
            } catch {
                # Expected
            }
            
            # Assert
            Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter { 
                $Level -eq 'Error' -and $Message -like "*Failed to resolve domain DN*"
            }
        }
    }
    
    Context "Logging" {
        
        It "Should log debug message on successful resolution" {
            # Arrange
            $script:logCalled = $false
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            Mock Write-TierModelLog {
                param($Level, $Message, $Data)
                if ($Level -eq 'Debug' -and $Message -like "*Domain DN resolved and cached*") {
                    $script:logCalled = $true
                }
            } -ModuleName TierModel
            
            # Act
            Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            
            # Assert
            $script:logCalled | Should -BeTrue
            Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter {
                $Level -eq 'Debug' -and $Message -like "*Domain DN resolved and cached*"
            }
        }
    }
}

Describe "Resolve-TierModelPlaceholder" -Tag 'Unit', 'Resolution', 'Placeholder' {
    
    Context "Placeholder Replacement" {
        
        It "Should replace {{DOMAIN_DN}} with actual domain DN" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path 'OU=Tier0,{{DOMAIN_DN}}' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'OU=Tier0,DC=contoso,DC=com'
        }
        
        It "Should replace multiple {{DOMAIN_DN}} placeholders" {
            # Act - contrived example with multiple placeholders
            $result = Resolve-TierModelPlaceholder -Path 'OU={{DOMAIN_DN}},{{DOMAIN_DN}}' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'OU=DC=contoso,DC=com,DC=contoso,DC=com'
        }
        
        It "Should handle path that is exactly {{DOMAIN_DN}}" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path '{{DOMAIN_DN}}' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'DC=contoso,DC=com'
        }
        
        It "Should handle empty path by returning domain DN" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path '' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'DC=contoso,DC=com'
        }
    }
    
    Context "Path Without Domain DN" {
        
        It "Should append domain DN when path has no DC= component" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path 'OU=Tier0,OU=Admin' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'OU=Tier0,OU=Admin,DC=contoso,DC=com'
        }
        
        It "Should not append domain DN when path already contains DC=" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path 'OU=Tier0,DC=contoso,DC=com' -DomainDN 'DC=fabrikam,DC=com'
            
            # Assert
            $result | Should -Be 'OU=Tier0,DC=contoso,DC=com'
        }
    }
    
    Context "Complex Scenarios" {
        
        It "Should handle path with placeholder and no DC= (replace and append)" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path 'OU=Tier0,OU=Admin,{{DOMAIN_DN}}' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'OU=Tier0,OU=Admin,DC=contoso,DC=com'
        }
        
        It "Should handle path with CN= component" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path 'CN=Users,{{DOMAIN_DN}}' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'CN=Users,DC=contoso,DC=com'
        }
        
        It "Should handle multi-level domain DN" {
            # Act
            $result = Resolve-TierModelPlaceholder -Path 'OU=Tier0,{{DOMAIN_DN}}' -DomainDN 'DC=sub,DC=contoso,DC=com'
            
            # Assert
            $result | Should -Be 'OU=Tier0,DC=sub,DC=contoso,DC=com'
        }
    }
}

Describe "Resolve-TierModelOuPath" -Tag 'Unit', 'Resolution', 'OuPath' {
    
    BeforeEach {
        # Mock Resolve-TierModelPlaceholder to verify it's called correctly
        Mock Resolve-TierModelPlaceholder {
            param($Path, $DomainDN)
            return "RESOLVED:$Path|$DomainDN"
        } -ModuleName TierModel
    }
    
    Context "Delegation to Resolve-TierModelPlaceholder" {
        
        It "Should call Resolve-TierModelPlaceholder with correct parameters" {
            # Act
            $null = Resolve-TierModelOuPath -OuPath 'OU=Tier0,{{DOMAIN_DN}}' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -ParameterFilter {
                $Path -eq 'OU=Tier0,{{DOMAIN_DN}}' -and $DomainDN -eq 'DC=contoso,DC=com'
            }
        }
        
        It "Should return result from Resolve-TierModelPlaceholder" {
            # Act
            $result = Resolve-TierModelOuPath -OuPath 'OU=Test' -DomainDN 'DC=test,DC=com'
            
            # Assert
            $result | Should -Be 'RESOLVED:OU=Test|DC=test,DC=com'
        }
        
        It "Should handle empty OuPath" {
            # Act
            $null = Resolve-TierModelOuPath -OuPath '' -DomainDN 'DC=contoso,DC=com'
            
            # Assert
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -ParameterFilter {
                $Path -eq '' -and $DomainDN -eq 'DC=contoso,DC=com'
            }
        }
    }
}

Describe "Resolve-TierModelGuid" -Tag 'Unit', 'Resolution', 'Guid' {
    
    BeforeEach {
        # Mock Write-TierModelLog to suppress output
        Mock Write-TierModelLog { } -ModuleName TierModel
        
        # Mock Resolve-DomainSpecificGuid
        Mock Resolve-DomainSpecificGuid {
            param($AttributeName)
            return "dynamic-guid-for-$AttributeName"
        } -ModuleName TierModel
    }
    
    Context "GUID Pass-Through (Backward Compatibility)" {
        
        It "Should return valid GUID as-is" {
            # Act
            $result = Resolve-TierModelGuid -Value 'bf967a86-0de6-11d0-a285-00aa003049e2' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be 'bf967a86-0de6-11d0-a285-00aa003049e2'
        }
        
        It "Should handle GUID in different case" {
            # Act
            $result = Resolve-TierModelGuid -Value 'BF967A86-0DE6-11D0-A285-00AA003049E2' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be 'BF967A86-0DE6-11D0-A285-00AA003049E2'
        }
    }
    
    Context "Special Cases" {
        
        It "Should return empty string for AllObjectClasses" {
            # Act
            $result = Resolve-TierModelGuid -Value 'AllObjectClasses' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be ''
        }
    }
    
    Context "Friendly Name Resolution" {
        
        It "Should resolve friendly name alias" {
            # Act - "PasswordReset" maps to "UserForceChangePassword"
            $result = Resolve-TierModelGuid -Value 'PasswordReset' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be '00299570-246d-11d0-a768-00aa006e0529'
        }
        
        It "Should resolve BitLockerRecoveryPassword friendly name" {
            # Act
            $result = Resolve-TierModelGuid -Value 'BitLockerRecoveryPassword' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be '5b47d60f-6090-40b2-9f37-2a4de88f3063'
        }
    }
    
    Context "Static Mapping Resolution" {
        
        It "Should resolve objectClass mapping - Computer" {
            # Act
            $result = Resolve-TierModelGuid -Value 'Computer' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be 'bf967a86-0de6-11d0-a285-00aa003049e2'
        }
        
        It "Should resolve objectClass mapping - User" {
            # Act
            $result = Resolve-TierModelGuid -Value 'User' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be 'bf967aba-0de6-11d0-a285-00aa003049e2'
        }
        
        It "Should resolve extendedRights mapping - UserForceChangePassword" {
            # Act
            $result = Resolve-TierModelGuid -Value 'UserForceChangePassword' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be '00299570-246d-11d0-a768-00aa006e0529'
        }
        
        It "Should resolve attribute mapping - UserAccountControl" {
            # Act
            $result = Resolve-TierModelGuid -Value 'UserAccountControl' -Mappings $TestGuidMappings
            
            # Assert
            $result | Should -Be 'bf967a68-0de6-11d0-a285-00aa003049e2'
        }
    }
    
    Context "Dynamic Mapping Resolution" {
        
        It "Should resolve dynamic mapping by calling Resolve-DomainSpecificGuid" {
            # Act
            $result = Resolve-TierModelGuid -Value 'LockoutTime' -Mappings $TestGuidMappings -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke Resolve-DomainSpecificGuid -ModuleName TierModel -ParameterFilter {
                $AttributeName -eq 'lockoutTime' -and $DomainController -eq 'dc01.contoso.com'
            }
            $result | Should -Be 'dynamic-guid-for-lockoutTime'
        }
    }
    
    Context "Error Handling" {
        
        It "Should throw error for unknown mapping" {
            # Act & Assert
            { Resolve-TierModelGuid -Value 'NonExistentMapping' -Mappings $TestGuidMappings } | 
                Should -Throw -ExpectedMessage "*Unknown GUID mapping*"
        }
        
        It "Should include mapping name in error message" {
            # Act & Assert
            { Resolve-TierModelGuid -Value 'InvalidValue' -Mappings $TestGuidMappings } | 
                Should -Throw -ExpectedMessage "*InvalidValue*"
        }
    }
    
    Context "Complex Mapping Scenarios" {
        
        It "Should prioritize friendly name over direct mapping" {
            # Act - Both "PasswordReset" (friendly) and "UserForceChangePassword" (direct) exist
            $result1 = Resolve-TierModelGuid -Value 'PasswordReset' -Mappings $TestGuidMappings
            $result2 = Resolve-TierModelGuid -Value 'UserForceChangePassword' -Mappings $TestGuidMappings
            
            # Assert - Should resolve to same GUID
            $result1 | Should -Be $result2
            $result1 | Should -Be '00299570-246d-11d0-a768-00aa006e0529'
        }
    }
}

Describe "Resolve-DomainSpecificGuid" -Tag 'Unit', 'Resolution', 'DomainGuid' {
    
    BeforeEach {
        # Mock Write-TierModelLog to suppress output
        Mock Write-TierModelLog { } -ModuleName TierModel
    }
    
    Context "Schema GUID Resolution" {
        
        It "Should resolve attribute GUID from Active Directory schema" {
            # Arrange
            $expectedGuid = '12345678-1234-1234-1234-123456789abc'
            $script:mockGuidBytes = [System.Guid]::Parse($expectedGuid).ToByteArray()
            
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            Mock Get-ADRootDSE {
                [PSCustomObject]@{
                    schemaNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            # Mock DirectorySearcher with proper structure
            Mock -CommandName New-Object {
                param($TypeName, $ArgumentList)
                
                if ($TypeName -eq 'System.DirectoryServices.DirectorySearcher') {
                    $searcher = [PSCustomObject]@{
                        SearchRoot = $null
                        Filter = ''
                        PropertiesToLoad = [System.Collections.ArrayList]::new()
                    }
                    
                    # Create the FindOne method that returns a proper result
                    $searcher | Add-Member -MemberType ScriptMethod -Name 'FindOne' -Value { 
                        # Create a custom object that mimics SearchResult
                        $mockResult = New-Object PSObject
                        # Add Properties as a ScriptProperty that returns a hashtable
                        $mockResult | Add-Member -MemberType ScriptProperty -Name 'Properties' -Value {
                            return @{
                                'schemaIDGUID' = , $script:mockGuidBytes
                            }
                        }
                        return $mockResult
                    }
                    
                    return $searcher
                } elseif ($TypeName -eq 'System.DirectoryServices.DirectoryEntry') {
                    return [PSCustomObject]@{}
                }
                # Fall back to actual New-Object for other types
                & (Get-Command -CommandType Cmdlet -Name New-Object) -TypeName $TypeName -ArgumentList $ArgumentList
            } -ModuleName TierModel
            
            # Act
            $result = Resolve-DomainSpecificGuid -AttributeName 'lockoutTime' -DomainController 'dc01.contoso.com'
            
            # Assert
            $result | Should -Be $expectedGuid
        }
        
        It "Should pass DomainController to Get-ADDomain" {
            # Arrange
            $script:invoked = $false
            Mock Get-ADDomain {
                param($Server)
                if ($Server -eq 'dc02.fabrikam.com') {
                    $script:invoked = $true
                }
                [PSCustomObject]@{
                    DistinguishedName = 'DC=fabrikam,DC=com'
                }
            } -ModuleName TierModel
            
            Mock Get-ADRootDSE {
                [PSCustomObject]@{
                    schemaNamingContext = 'CN=Schema,CN=Configuration,DC=fabrikam,DC=com'
                }
            } -ModuleName TierModel
            
            $script:mockGuidBytes = [System.Guid]::Parse('12345678-1234-1234-1234-123456789abc').ToByteArray()
            
            Mock -CommandName New-Object {
                param($TypeName, $ArgumentList)
                
                if ($TypeName -eq 'System.DirectoryServices.DirectorySearcher') {
                    $searcher = [PSCustomObject]@{
                        SearchRoot = $null
                        Filter = ''
                        PropertiesToLoad = [System.Collections.ArrayList]::new()
                    }
                    
                    # Create the FindOne method that returns a proper result
                    $searcher | Add-Member -MemberType ScriptMethod -Name 'FindOne' -Value { 
                        # Create a custom object that mimics SearchResult
                        $mockResult = New-Object PSObject
                        # Add Properties as a ScriptProperty that returns a hashtable
                        $mockResult | Add-Member -MemberType ScriptProperty -Name 'Properties' -Value {
                            return @{
                                'schemaIDGUID' = , $script:mockGuidBytes
                            }
                        }
                        return $mockResult
                    }
                    
                    return $searcher
                } elseif ($TypeName -eq 'System.DirectoryServices.DirectoryEntry') {
                    return [PSCustomObject]@{}
                }
                & (Get-Command -CommandType Cmdlet -Name New-Object) -TypeName $TypeName -ArgumentList $ArgumentList
            } -ModuleName TierModel
            
            # Act
            $null = Resolve-DomainSpecificGuid -AttributeName 'lockoutTime' -DomainController 'dc02.fabrikam.com'
            
            # Assert
            $invoked | Should -BeTrue
        }
    }
    
    Context "Error Handling" {
        
        It "Should throw error when attribute not found in schema" {
            # Arrange
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            Mock Get-ADRootDSE {
                [PSCustomObject]@{
                    schemaNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            # Mock DirectorySearcher that simulates attribute not found
            Mock -CommandName New-Object {
                param($TypeName, $ArgumentList)
                
                if ($TypeName -eq 'System.DirectoryServices.DirectorySearcher') {
                    $searcher = [PSCustomObject]@{
                        SearchRoot = $null
                        Filter = ''
                        PropertiesToLoad = [System.Collections.ArrayList]::new()
                    }
                    
                    # FindOne returns null to simulate attribute not found
                    $searcher | Add-Member -MemberType ScriptMethod -Name 'FindOne' -Value { 
                        # Return null which will trigger the null check in the function
                        [void]$this
                        $null
                    }
                    
                    return $searcher
                } elseif ($TypeName -eq 'System.DirectoryServices.DirectoryEntry') {
                    # DirectoryEntry needs Properties for fallback path
                    $entry = [PSCustomObject]@{}
                    $entry | Add-Member -MemberType NoteProperty -Name 'Properties' -Value @{
                        'schemaNamingContext' = @('CN=Schema,CN=Configuration,DC=contoso,DC=com')
                    }
                    return $entry
                }
                # Fall back to actual New-Object for other types
                & (Get-Command -CommandType Cmdlet -Name New-Object) -TypeName $TypeName -ArgumentList $ArgumentList
            } -ModuleName TierModel
            
            # Act & Assert
            { Resolve-DomainSpecificGuid -AttributeName 'NonExistentAttribute' -DomainController 'dc01.contoso.com' } | 
                Should -Throw -ExpectedMessage "*not found in domain schema*"
        }
        
        It "Should log error on failure" {
            # Arrange
            Mock Get-ADDomain {
                throw "Unable to contact domain"
            } -ModuleName TierModel
            
            # Act
            try {
                Resolve-DomainSpecificGuid -AttributeName 'testAttr' -DomainController 'invalid.dc.com'
            } catch {
                # Expected
            }
            
            # Assert
            Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter {
                $Level -eq 'Error'
            }
        }
    }
    
    Context "Logging" {
        
        It "Should log debug message on successful resolution" {
            # Arrange
            $script:mockGuidBytes = [System.Guid]::NewGuid().ToByteArray()
            
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            Mock Get-ADRootDSE {
                [PSCustomObject]@{
                    schemaNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            Mock -CommandName New-Object {
                param($TypeName, $ArgumentList)
                
                if ($TypeName -eq 'System.DirectoryServices.DirectorySearcher') {
                    $searcher = [PSCustomObject]@{
                        SearchRoot = $null
                        Filter = ''
                        PropertiesToLoad = [System.Collections.ArrayList]::new()
                    }
                    
                    # Create the FindOne method that returns a proper result
                    $searcher | Add-Member -MemberType ScriptMethod -Name 'FindOne' -Value { 
                        # Create a custom object that mimics SearchResult
                        $mockResult = New-Object PSObject
                        # Add Properties as a ScriptProperty that returns a hashtable
                        $mockResult | Add-Member -MemberType ScriptProperty -Name 'Properties' -Value {
                            return @{
                                'schemaIDGUID' = , $script:mockGuidBytes
                            }
                        }
                        return $mockResult
                    }
                    
                    return $searcher
                } elseif ($TypeName -eq 'System.DirectoryServices.DirectoryEntry') {
                    return [PSCustomObject]@{}
                }
                # Fall back to actual New-Object for other types
                & (Get-Command -CommandType Cmdlet -Name New-Object) -TypeName $TypeName -ArgumentList $ArgumentList
            } -ModuleName TierModel
            
            # Act
            Resolve-DomainSpecificGuid -AttributeName 'lockoutTime' -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter {
                $Level -eq 'Debug' -and $Message -like "*Resolved domain-specific GUID*"
            }
        }
    }
    
    Context "Fallback Mechanism" {
        
        It "Should log warning when falling back to DirectoryServices" {
            # Arrange - Make Get-ADRootDSE fail to trigger fallback
            Mock Get-ADDomain {
                throw "AD cmdlets not available"
            } -ModuleName TierModel
            
            # Mock fallback path
            $script:mockGuidBytes = [System.Guid]::NewGuid().ToByteArray()
            
            Mock -CommandName New-Object {
                param($TypeName, $ArgumentList)
                
                if ($TypeName -eq 'System.DirectoryServices.DirectoryEntry' -and $ArgumentList -eq 'LDAP://RootDSE') {
                    # Mock RootDSE DirectoryEntry
                    $rootDSE = New-Object PSObject
                    $rootDSE | Add-Member -MemberType NoteProperty -Name 'Properties' -Value @{
                        'schemaNamingContext' = @('CN=Schema,CN=Configuration,DC=contoso,DC=com')
                    }
                    return $rootDSE
                } elseif ($TypeName -eq 'System.DirectoryServices.DirectorySearcher') {
                    $searcher = [PSCustomObject]@{
                        SearchRoot = $null
                        Filter = ''
                        PropertiesToLoad = [System.Collections.ArrayList]::new()
                    }
                    
                    # Create the FindOne method that returns a proper result
                    $searcher | Add-Member -MemberType ScriptMethod -Name 'FindOne' -Value { 
                        # Create a custom object that mimics SearchResult
                        $mockResult = New-Object PSObject
                        # Add Properties as a ScriptProperty that returns a hashtable
                        $mockResult | Add-Member -MemberType ScriptProperty -Name 'Properties' -Value {
                            return @{
                                'schemaIDGUID' = , $script:mockGuidBytes
                            }
                        }
                        return $mockResult
                    }
                    
                    return $searcher
                } elseif ($TypeName -eq 'System.DirectoryServices.DirectoryEntry') {
                    return New-Object PSObject
                }
                # Fall back to actual New-Object for other types
                & (Get-Command -CommandType Cmdlet -Name New-Object) -TypeName $TypeName -ArgumentList $ArgumentList
            } -ModuleName TierModel
            
            # Act
            Resolve-DomainSpecificGuid -AttributeName 'lockoutTime' -DomainController 'dc01.contoso.com'
            
            # Assert
            Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like "*DirectoryServices fallback*"
            }
        }
    }
}

Describe "Get-TierModelConditionalGroupNames" -Tag 'Unit', 'Resolution', 'ConditionalGroups' {

    BeforeEach {
        Mock -CommandName Write-TierModelLog -MockWith { } -ModuleName TierModel
    }

    Context "No conditions defined (backwards compatibility)" {

        It "Should return all names when conditions property is absent" {
            $group = [PSCustomObject]@{
                names = @('DnsAdmins', 'DnsUpdateProxy')
            }

            $result = @(InModuleScope TierModel { Get-TierModelConditionalGroupNames -ConditionalGroup $args[0] -DomainController 'DC01' } -ArgumentList $group)

            $result.Count | Should -Be 2
            $result | Should -Contain 'DnsAdmins'
            $result | Should -Contain 'DnsUpdateProxy'
        }

        It "Should return all names when conditions array is empty" {
            $group = [PSCustomObject]@{
                names      = @('DnsAdmins', 'DnsUpdateProxy')
                conditions = @()
            }

            $result = @(InModuleScope TierModel { Get-TierModelConditionalGroupNames -ConditionalGroup $args[0] -DomainController 'DC01' } -ArgumentList $group)

            $result.Count | Should -Be 2
            $result | Should -Contain 'DnsAdmins'
            $result | Should -Contain 'DnsUpdateProxy'
        }
    }

    Context "groupExists condition - group found in AD" {

        It "Should include name when AD group exists" {
            Mock -CommandName Get-ADGroup -MockWith {
                [PSCustomObject]@{ Name = 'DnsAdmins'; DistinguishedName = 'CN=DnsAdmins,CN=Users,DC=contoso,DC=com' }
            } -ModuleName TierModel

            $group = [PSCustomObject]@{
                names      = @('DnsAdmins')
                conditions = @([PSCustomObject]@{ type = 'groupExists'; operator = 'exists' })
            }

            $result = @(InModuleScope TierModel { Get-TierModelConditionalGroupNames -ConditionalGroup $args[0] -DomainController 'DC01' } -ArgumentList $group)

            $result.Count | Should -Be 1
            $result[0] | Should -Be 'DnsAdmins'
        }
    }

    Context "groupExists condition - group not found in AD" {

        It "Should exclude name when AD group does not exist (Get-ADGroup throws)" {
            Mock -CommandName Get-ADGroup -MockWith {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find an object")
            } -ModuleName TierModel

            $group = [PSCustomObject]@{
                names      = @('DnsAdmins')
                conditions = @([PSCustomObject]@{ type = 'groupExists'; operator = 'exists' })
            }

            $result = @(InModuleScope TierModel { Get-TierModelConditionalGroupNames -ConditionalGroup $args[0] -DomainController 'DC01' } -ArgumentList $group)

            $result.Count | Should -Be 0
        }

        It "Should return empty array when no names pass the condition" {
            Mock -CommandName Get-ADGroup -MockWith { throw "Not found" } -ModuleName TierModel

            $group = [PSCustomObject]@{
                names      = @('DnsAdmins', 'DnsUpdateProxy')
                conditions = @([PSCustomObject]@{ type = 'groupExists'; operator = 'exists' })
            }

            $result = @(InModuleScope TierModel { Get-TierModelConditionalGroupNames -ConditionalGroup $args[0] -DomainController 'DC01' } -ArgumentList $group)

            $result.Count | Should -Be 0
        }
    }

    Context "groupExists condition - mixed existence" {

        It "Should include only names whose AD group is found" {
            # $Identity is not bound in mock body when AD module is not loaded (no param definitions).
            # Use a module-scoped call counter instead; production code iterates names in order
            # so call 1 = DnsAdmins (return group), call 2 = DnsUpdateProxy (throw).
            InModuleScope TierModel {
                $script:_mixedTestCallCount = 0
                Mock Get-ADGroup {
                    $script:_mixedTestCallCount++
                    if ($script:_mixedTestCallCount -eq 1) {
                        return [PSCustomObject]@{ Name = 'DnsAdmins' }
                    }
                    throw "Cannot find an object"
                }

                $group = [PSCustomObject]@{
                    names      = @('DnsAdmins', 'DnsUpdateProxy')
                    conditions = @([PSCustomObject]@{ type = 'groupExists'; operator = 'exists' })
                }

                $result = @(Get-TierModelConditionalGroupNames -ConditionalGroup $group -DomainController 'DC01')

                $result.Count | Should -Be 1
                $result[0] | Should -Be 'DnsAdmins'
                $result | Should -Not -Contain 'DnsUpdateProxy'
            }
        }
    }
}

Describe "Resolve-TierModelPrincipalSid" -Tag 'Unit', 'Resolution', 'PrincipalSid' {

    BeforeEach {
        # Clear the module-level SID cache before each test
        InModuleScope TierModel {
            $script:SidCache = @{}
        }
        Mock Write-TierModelLog { } -ModuleName TierModel
        Mock Write-Warning      { } -ModuleName TierModel
    }

    # ------------------------------------------------------------------
    # Direct SID input — already a SID string, no AD needed
    # ------------------------------------------------------------------
    Context "Direct SID Input" {

        It "Should return DirectSID source when input is already a SID" {
            $result = Resolve-TierModelPrincipalSid -Principal 'S-1-5-32-544' -DomainController 'dc01.contoso.com'
            $result.Source    | Should -Be 'DirectSID'
            $result.Sid       | Should -Be 'S-1-5-32-544'
            $result.Principal | Should -Be 'S-1-5-32-544'
            $result.Success   | Should -BeTrue
            $result.Cached    | Should -BeFalse
        }

        It "Should handle full domain SID" {
            $result = Resolve-TierModelPrincipalSid -Principal 'S-1-5-21-123456789-987654321-555555555-512' -DomainController 'dc01.contoso.com'
            $result.Source | Should -Be 'DirectSID'
            $result.Sid    | Should -Be 'S-1-5-21-123456789-987654321-555555555-512'
        }

        It "Should not query AD when input is already a SID" {
            Mock Get-ADDomain          { } -ModuleName TierModel
            Mock Resolve-ADPrincipalSid { } -ModuleName TierModel

            Resolve-TierModelPrincipalSid -Principal 'S-1-5-18' -DomainController 'dc01.contoso.com'

            Should -Invoke Get-ADDomain           -ModuleName TierModel -Times 0
            Should -Invoke Resolve-ADPrincipalSid  -ModuleName TierModel -Times 0
        }

        It "Should return null Error for direct SID result" {
            $result = Resolve-TierModelPrincipalSid -Principal 'S-1-5-32-545' -DomainController 'dc01.contoso.com'
            $result.Error | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    # Administrator special handling — bypass cache, resolve via RID 500
    # ------------------------------------------------------------------
    Context "Administrator Special Handling" {

        BeforeEach {
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DomainSID = [PSCustomObject]@{ Value = 'S-1-5-21-111111111-222222222-333333333' }
                }
            } -ModuleName TierModel

            Mock Get-ADUser {
                [PSCustomObject]@{
                    SamAccountName = 'Administrator'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-111111111-222222222-333333333-500' }
                }
            } -ModuleName TierModel
        }

        It "Should resolve built-in Administrator account via RID 500" {
            $result = Resolve-TierModelPrincipalSid -Principal 'Administrator' -DomainController 'dc01.contoso.com'
            $result.Source  | Should -Be 'ADUser-RID500'
            $result.Success | Should -BeTrue
            $result.Sid     | Should -Be 'S-1-5-21-111111111-222222222-333333333-500'
        }

        It "Should be case-insensitive for Administrator principal name" {
            $result = Resolve-TierModelPrincipalSid -Principal 'administrator' -DomainController 'dc01.contoso.com'
            $result.Source | Should -Be 'ADUser-RID500'
        }

        It "Should return SID for renamed Administrator account" {
            Mock Get-ADUser {
                [PSCustomObject]@{
                    SamAccountName = 'Root'
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-111111111-222222222-333333333-500' }
                }
            } -ModuleName TierModel

            $result = Resolve-TierModelPrincipalSid -Principal 'Administrator' -DomainController 'dc01.contoso.com'
            $result.Sid    | Should -Be 'S-1-5-21-111111111-222222222-333333333-500'
            $result.Source | Should -Be 'ADUser-RID500'
        }

        It "Should not store Administrator result in the SID cache" {
            $null = Resolve-TierModelPrincipalSid -Principal 'Administrator' -DomainController 'dc01.contoso.com'

            InModuleScope TierModel {
                $script:SidCache.ContainsKey('Administrator') | Should -BeFalse
            }
        }

        It "Should fall back to normal AD resolution when RID 500 lookup fails" {
            Mock Get-ADUser { throw "Identity not found" } -ModuleName TierModel

            Mock Resolve-ADPrincipalSid {
                return @{
                    Sid     = 'S-1-5-21-111111111-222222222-333333333-500'
                    Source  = 'ADUser'
                    Success = $true
                    Error   = $null
                }
            } -ModuleName TierModel

            $result = Resolve-TierModelPrincipalSid -Principal 'Administrator' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeTrue
            Should -Invoke Resolve-ADPrincipalSid -ModuleName TierModel -Times 1
        }

        It "Should fall back to well-known resolution when Get-ADDomain fails" {
            Mock Get-ADDomain { throw "Cannot contact DC" } -ModuleName TierModel

            # "Administrator" is not a well-known SID, so this should reach Resolve-ADPrincipalSid
            Mock Resolve-ADPrincipalSid {
                return @{ Sid = 'S-1-5-21-999-999-999-500'; Source = 'ADUser'; Success = $true; Error = $null }
            } -ModuleName TierModel

            $result = Resolve-TierModelPrincipalSid -Principal 'Administrator' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeTrue
        }
    }

    # ------------------------------------------------------------------
    # SID cache — population, hit, and bypass
    # ------------------------------------------------------------------
    Context "SID Cache" {

        BeforeEach {
            Mock Resolve-ADPrincipalSid {
                return @{
                    Sid     = 'S-1-5-21-123-456-789-1001'
                    Source  = 'ADUser'
                    Success = $true
                    Error   = $null
                }
            } -ModuleName TierModel
        }

        It "Should return Cached = false on first call" {
            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Cached | Should -BeFalse
        }

        It "Should return Cached = true on second call" {
            $null = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Cached | Should -BeTrue
        }

        It "Should call AD resolution only once with cache enabled" {
            $null = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $null = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            Should -Invoke Resolve-ADPrincipalSid -ModuleName TierModel -Times 1 -Exactly
        }

        It "Should bypass cache when UseCache = false" {
            $null = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com' -UseCache $false
            $null = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com' -UseCache $false
            Should -Invoke Resolve-ADPrincipalSid -ModuleName TierModel -Times 2 -Exactly
        }

        It "Should preserve SID value in cached result" {
            $null = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Sid | Should -Be 'S-1-5-21-123-456-789-1001'
        }

        It "Should cache a failed AD resolution result" {
            Mock Resolve-ADPrincipalSid {
                return @{ Sid = $null; Source = 'NotFound'; Success = $false; Error = 'Not found' }
            } -ModuleName TierModel

            $null = Resolve-TierModelPrincipalSid -Principal 'NonExistentGroup' -DomainController 'dc01.contoso.com'
            $null = Resolve-TierModelPrincipalSid -Principal 'NonExistentGroup' -DomainController 'dc01.contoso.com'
            Should -Invoke Resolve-ADPrincipalSid -ModuleName TierModel -Times 1 -Exactly
        }

        It "Should not cache when UseCache = false and AD returns failure" {
            Mock Resolve-ADPrincipalSid {
                return @{ Sid = $null; Source = 'NotFound'; Success = $false; Error = 'Not found' }
            } -ModuleName TierModel

            $null = Resolve-TierModelPrincipalSid -Principal 'NoSuchGroup' -DomainController 'dc01.contoso.com' -UseCache $false
            $null = Resolve-TierModelPrincipalSid -Principal 'NoSuchGroup' -DomainController 'dc01.contoso.com' -UseCache $false
            Should -Invoke Resolve-ADPrincipalSid -ModuleName TierModel -Times 2 -Exactly
        }
    }

    # ------------------------------------------------------------------
    # Well-known SID resolution (exercises Get-WellKnownSid internals)
    # ------------------------------------------------------------------
    Context "Well-Known SID Resolution" {

        It "Should resolve BUILTIN\Administrators to S-1-5-32-544" {
            $result = Resolve-TierModelPrincipalSid -Principal 'BUILTIN\Administrators' -DomainController 'dc01.contoso.com'
            $result.Source  | Should -Be 'WellKnown'
            $result.Sid     | Should -Be 'S-1-5-32-544'
            $result.Success | Should -BeTrue
            $result.Cached  | Should -BeFalse
        }

        It "Should resolve NT AUTHORITY\SYSTEM to S-1-5-18" {
            $result = Resolve-TierModelPrincipalSid -Principal 'NT AUTHORITY\SYSTEM' -DomainController 'dc01.contoso.com'
            $result.Source | Should -Be 'WellKnown'
            $result.Sid    | Should -Be 'S-1-5-18'
        }

        It "Should resolve Everyone to S-1-1-0" {
            $result = Resolve-TierModelPrincipalSid -Principal 'Everyone' -DomainController 'dc01.contoso.com'
            $result.Source | Should -Be 'WellKnown'
            $result.Sid    | Should -Be 'S-1-1-0'
        }

        It "Should resolve CREATOR OWNER to S-1-3-0" {
            $result = Resolve-TierModelPrincipalSid -Principal 'CREATOR OWNER' -DomainController 'dc01.contoso.com'
            $result.Sid | Should -Be 'S-1-3-0'
        }

        It "Should resolve NT AUTHORITY\Authenticated Users to S-1-5-11" {
            $result = Resolve-TierModelPrincipalSid -Principal 'NT AUTHORITY\Authenticated Users' -DomainController 'dc01.contoso.com'
            $result.Sid | Should -Be 'S-1-5-11'
        }

        It "Should resolve short-form Administrators to S-1-5-32-544" {
            $result = Resolve-TierModelPrincipalSid -Principal 'Administrators' -DomainController 'dc01.contoso.com'
            $result.Source | Should -Be 'WellKnown'
            $result.Sid    | Should -Be 'S-1-5-32-544'
        }

        It "Should resolve BUILTIN\Users to S-1-5-32-545" {
            $result = Resolve-TierModelPrincipalSid -Principal 'BUILTIN\Users' -DomainController 'dc01.contoso.com'
            $result.Sid | Should -Be 'S-1-5-32-545'
        }

        It "Should resolve NT AUTHORITY\LOCAL SERVICE to S-1-5-19" {
            $result = Resolve-TierModelPrincipalSid -Principal 'NT AUTHORITY\LOCAL SERVICE' -DomainController 'dc01.contoso.com'
            $result.Sid | Should -Be 'S-1-5-19'
        }

        It "Should resolve BUILTIN\Backup Operators to S-1-5-32-551" {
            $result = Resolve-TierModelPrincipalSid -Principal 'BUILTIN\Backup Operators' -DomainController 'dc01.contoso.com'
            $result.Sid | Should -Be 'S-1-5-32-551'
        }

        It "Should cache well-known SID on first call and return Cached = true on second" {
            $null = Resolve-TierModelPrincipalSid -Principal 'Everyone' -DomainController 'dc01.contoso.com'
            $result = Resolve-TierModelPrincipalSid -Principal 'Everyone' -DomainController 'dc01.contoso.com'
            $result.Cached | Should -BeTrue
        }

        It "Should not cache well-known SID when UseCache = false" {
            $r1 = Resolve-TierModelPrincipalSid -Principal 'Everyone' -DomainController 'dc01.contoso.com' -UseCache $false
            $r2 = Resolve-TierModelPrincipalSid -Principal 'Everyone' -DomainController 'dc01.contoso.com' -UseCache $false
            $r1.Cached | Should -BeFalse
            $r2.Cached | Should -BeFalse
        }

        It "Should return WellKnown result even when UseCache = false" {
            $result = Resolve-TierModelPrincipalSid -Principal 'NT AUTHORITY\NETWORK SERVICE' -DomainController 'dc01.contoso.com' -UseCache $false
            $result.Source  | Should -Be 'WellKnown'
            $result.Sid     | Should -Be 'S-1-5-20'
            $result.Success | Should -BeTrue
        }
    }

    # ------------------------------------------------------------------
    # AD resolution via Resolve-ADPrincipalSid internals
    # ------------------------------------------------------------------
    Context "AD Resolution - User Found" {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'ActiveDirectory' }
            } -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable } -ModuleName TierModel

            Mock Import-Module { } -ModuleName TierModel

            Mock Get-ADUser {
                [PSCustomObject]@{
                    SID            = [PSCustomObject]@{ Value = 'S-1-5-21-100-200-300-1001' }
                    SamAccountName = 'svc-tier0'
                }
            } -ModuleName TierModel
        }

        It "Should resolve principal as ADUser" {
            $result = Resolve-TierModelPrincipalSid -Principal 'svc-tier0' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeTrue
            $result.Source  | Should -Be 'ADUser'
            $result.Sid     | Should -Be 'S-1-5-21-100-200-300-1001'
        }

        It "Should store ADUser SID in cache" {
            $null = Resolve-TierModelPrincipalSid -Principal 'svc-tier0' -DomainController 'dc01.contoso.com'
            $result = Resolve-TierModelPrincipalSid -Principal 'svc-tier0' -DomainController 'dc01.contoso.com'
            $result.Cached | Should -BeTrue
            Should -Invoke Get-ADUser -ModuleName TierModel -Times 1 -Exactly
        }
    }

    Context "AD Resolution - Group Found" {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'ActiveDirectory' }
            } -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable } -ModuleName TierModel

            Mock Import-Module { } -ModuleName TierModel

            Mock Get-ADUser  { throw 'Not a user' } -ModuleName TierModel
            Mock Get-ADGroup {
                [PSCustomObject]@{
                    SID = [PSCustomObject]@{ Value = 'S-1-5-21-100-200-300-512' }
                }
            } -ModuleName TierModel
        }

        It "Should resolve principal as ADGroup when user lookup fails" {
            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeTrue
            $result.Source  | Should -Be 'ADGroup'
            $result.Sid     | Should -Be 'S-1-5-21-100-200-300-512'
        }
    }

    Context "AD Resolution - Generic Object Found" {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'ActiveDirectory' }
            } -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable } -ModuleName TierModel

            Mock Import-Module  { } -ModuleName TierModel
            Mock Get-ADUser  { throw 'Not a user'  } -ModuleName TierModel
            Mock Get-ADGroup { throw 'Not a group' } -ModuleName TierModel
            Mock Get-ADObject {
                [PSCustomObject]@{
                    objectSid = [PSCustomObject]@{ Value = 'S-1-5-21-100-200-300-9999' }
                }
            } -ModuleName TierModel
        }

        It "Should resolve principal as ADObject when user and group lookups fail" {
            $result = Resolve-TierModelPrincipalSid -Principal 'CustomObject' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeTrue
            $result.Source  | Should -Be 'ADObject'
            $result.Sid     | Should -Be 'S-1-5-21-100-200-300-9999'
        }
    }

    Context "AD Resolution - Principal Not Found" {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'ActiveDirectory' }
            } -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable } -ModuleName TierModel

            Mock Import-Module  { } -ModuleName TierModel
            Mock Get-ADUser  { throw 'Not found' } -ModuleName TierModel
            Mock Get-ADGroup { throw 'Not found' } -ModuleName TierModel
            Mock Get-ADObject { return $null      } -ModuleName TierModel
        }

        It "Should return Failed when principal not found in AD" {
            $result = Resolve-TierModelPrincipalSid -Principal 'GhostPrincipal' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeFalse
            $result.Source  | Should -Be 'Failed'
            $result.Sid     | Should -BeNullOrEmpty
        }

        It "Should include an error message when not found" {
            $result = Resolve-TierModelPrincipalSid -Principal 'GhostPrincipal' -DomainController 'dc01.contoso.com'
            $result.Error | Should -Not -BeNullOrEmpty
        }

        It "Should cache a not-found result" {
            $null = Resolve-TierModelPrincipalSid -Principal 'GhostPrincipal' -DomainController 'dc01.contoso.com'
            $result = Resolve-TierModelPrincipalSid -Principal 'GhostPrincipal' -DomainController 'dc01.contoso.com'
            $result.Cached | Should -BeTrue
        }
    }

    Context "AD Resolution - Module Not Available" {

        BeforeEach {
            Mock Get-Module {
                return @()
            } -ParameterFilter { $Name -eq 'ActiveDirectory' -and $ListAvailable } -ModuleName TierModel
        }

        It "Should return Failed when ActiveDirectory module is not available" {
            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeFalse
            $result.Source  | Should -Be 'Failed'
        }

        It "Should include error information when AD module missing" {
            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    # Exception handling — outer try/catch in process block
    # ------------------------------------------------------------------
    Context "Exception Handling" {

        It "Should return Exception source when Resolve-ADPrincipalSid throws" {
            # "Domain Admins" is not well-known, so Get-WellKnownSid returns null naturally
            # then Resolve-ADPrincipalSid is called and throws
            Mock Resolve-ADPrincipalSid { throw 'Unexpected error in AD resolution' } -ModuleName TierModel

            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Success | Should -BeFalse
            $result.Source  | Should -Be 'Exception'
            $result.Sid     | Should -BeNullOrEmpty
        }

        It "Should include exception message in Error property" {
            Mock Resolve-ADPrincipalSid { throw 'Unexpected error in AD resolution' } -ModuleName TierModel

            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.Error | Should -Match 'Exception resolving SID'
        }

        It "Should cache exception result when UseCache = true" {
            Mock Resolve-ADPrincipalSid { throw 'Error' } -ModuleName TierModel

            $null = Resolve-TierModelPrincipalSid -Principal 'BadPrincipal' -DomainController 'dc01.contoso.com'
            $result = Resolve-TierModelPrincipalSid -Principal 'BadPrincipal' -DomainController 'dc01.contoso.com'
            $result.Cached | Should -BeTrue
        }

        It "Should not cache exception result when UseCache = false" {
            Mock Resolve-ADPrincipalSid { throw 'Error' } -ModuleName TierModel

            $null = Resolve-TierModelPrincipalSid -Principal 'BadPrincipal' -DomainController 'dc01.contoso.com' -UseCache $false
            $null = Resolve-TierModelPrincipalSid -Principal 'BadPrincipal' -DomainController 'dc01.contoso.com' -UseCache $false
            Should -Invoke Resolve-ADPrincipalSid -ModuleName TierModel -Times 2 -Exactly
        }
    }

    # ------------------------------------------------------------------
    # ActualName on AD result (administrator-path enrichment)
    # ------------------------------------------------------------------
    Context "ActualName Enrichment from AD Result" {

        It "Should add ActualName property when AD result contains it" {
            Mock Get-WellKnownSid { return $null } -ModuleName TierModel

            $adResult = [PSCustomObject]@{
                Sid     = 'S-1-5-21-111-222-333-500'
                Source  = 'ADUser'
                Success = $true
                Error   = $null
            }
            $adResult | Add-Member -NotePropertyName 'ActualName' -NotePropertyValue 'Root' -Force

            Mock Resolve-ADPrincipalSid { return $adResult } -ModuleName TierModel

            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.PSObject.Properties.Name | Should -Contain 'ActualName'
            $result.ActualName | Should -Be 'Root'
        }

        It "Should not add ActualName when AD result has no ActualName property" {
            Mock Get-WellKnownSid { return $null } -ModuleName TierModel
            Mock Resolve-ADPrincipalSid {
                return [PSCustomObject]@{
                    Sid     = 'S-1-5-21-111-222-333-512'
                    Source  = 'ADGroup'
                    Success = $true
                    Error   = $null
                }
            } -ModuleName TierModel

            $result = Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com'
            $result.PSObject.Properties.Name | Should -Not -Contain 'ActualName'
        }
    }

    # ------------------------------------------------------------------
    # CorrelationId parameter
    # ------------------------------------------------------------------
    Context "CorrelationId Parameter" {

        It "Should accept a custom CorrelationId without throwing" {
            Mock Resolve-ADPrincipalSid {
                return @{ Sid = 'S-1-1-0'; Source = 'ADUser'; Success = $true; Error = $null }
            } -ModuleName TierModel

            { Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com' -CorrelationId 'my-test-id' } |
                Should -Not -Throw
        }

        It "Should auto-generate CorrelationId when not provided" {
            Mock Resolve-ADPrincipalSid {
                return @{ Sid = 'S-1-1-0'; Source = 'ADUser'; Success = $true; Error = $null }
            } -ModuleName TierModel

            { Resolve-TierModelPrincipalSid -Principal 'Domain Admins' -DomainController 'dc01.contoso.com' } |
                Should -Not -Throw
        }
    }
}

Describe "Resolution Functions Integration" -Tag 'Unit', 'Resolution', 'Integration' {
    
    BeforeEach {
        # Clear cached values before each test - must be done in module scope
        InModuleScope TierModel {
            $script:CachedDomainDN = $null
            $script:CachedDomainController = $null
        }
        
        # Mock dependencies
        Mock Write-TierModelLog { } -ModuleName TierModel
    }
    
    Context "End-to-End Resolution Workflow" {
        
        It "Should resolve OU path using domain DN from cache" {
            # Arrange
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            # Act - First get domain DN
            $domainDN = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            
            # Then resolve OU path
            $ouPath = Resolve-TierModelOuPath -OuPath 'OU=Tier0,{{DOMAIN_DN}}' -DomainDN $domainDN
            
            # Assert
            $domainDN | Should -Be 'DC=contoso,DC=com'
            $ouPath | Should -Be 'OU=Tier0,DC=contoso,DC=com'
        }
        
        It "Should handle multiple resolution calls efficiently with caching" {
            # Arrange
            Mock Get-ADDomain {
                [PSCustomObject]@{
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            } -ModuleName TierModel
            
            # Act - Multiple calls
            $dn1 = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com'
            $ou1 = Resolve-TierModelOuPath -OuPath 'OU=Tier1,{{DOMAIN_DN}}' -DomainDN $dn1
            $dn2 = Resolve-TierModelDomainDN -DomainController 'dc01.contoso.com' # Should use cache
            $ou2 = Resolve-TierModelOuPath -OuPath 'OU=Tier2,{{DOMAIN_DN}}' -DomainDN $dn2
            
            # Assert
            Should -Invoke Get-ADDomain -ModuleName TierModel -Times 1 -Exactly
            $ou1 | Should -Be 'OU=Tier1,DC=contoso,DC=com'
            $ou2 | Should -Be 'OU=Tier2,DC=contoso,DC=com'
        }
    }
}
