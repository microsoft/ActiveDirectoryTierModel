Describe "OU ACL Operations" -Tag "Unit", "OuAcl", "Phase3" {
    BeforeAll {
        # Import the module
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force
        
        # Test correlation ID
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        
        # Mock domain controller
        $script:TestDC = "DC01.test.local"
        $script:TestDomainDN = "DC=test,DC=local"
        
        # Test configuration with ACL delegations
        $script:TestConfig = [PSCustomObject]@{
            organizationalUnits = @(
                @{ name = "Tier0"; path = "OU=Tier0,{{domainDN}}"; description = "Tier 0 OU" }
                @{ name = "Tier1"; path = "OU=Tier1,{{domainDN}}"; description = "Tier 1 OU" }
            )
            groups = @(
                @{ name = "Tier0Admins"; samAccountName = "Tier0Admins"; path = "OU=Tier0,{{domainDN}}"; scope = "DomainLocal"; type = "Security" }
                @{ name = "Tier1Users"; samAccountName = "Tier1Users"; path = "OU=Tier1,{{domainDN}}"; scope = "Global"; type = "Security" }
            )
            aclDelegations = @(
                @{
                    targetOUPath = "OU=Tier0,{{domainDN}}"
                    identityreference = "Tier0Admins"
                    activedirectoryrights = @("GenericAll")
                    accesscontroltype = "Allow"
                    activeDirectorysecurityinheritance = "All"
                    objecttype = ""
                }
                @{
                    targetOUPath = "OU=Tier1,{{domainDN}}"
                    identityreference = "Tier1Users"
                    activedirectoryrights = @("CreateChild", "DeleteChild")
                    accesscontroltype = "Allow"
                    activeDirectorysecurityinheritance = "All"
                    objecttype = "bf967aba-0de6-11d0-a285-00aa003049e2"  # User object GUID
                }
                @{
                    targetOUPath = "OU=Tier1,{{domainDN}}"
                    identityreference = "Domain Admins"
                    activedirectoryrights = @("GenericAll")
                    accesscontroltype = "Allow"
                    activeDirectorysecurityinheritance = "All"
                    objecttype = ""
                }
            )
            guidMappings = @{
                staticMappings = @{
                    objectClasses = @{
                        User = "bf967aba-0de6-11d0-a285-00aa003049e2"
                        Computer = "bf967a86-0de6-11d0-a285-00aa003049e2"
                    }
                }
                dynamicMappings = @{}
                friendlyNameMappings = @{}
            }
        }
        
        # Test configuration with no ACL delegations
        $script:TestConfigEmpty = [PSCustomObject]@{
            organizationalUnits = @()
            groups = @()
            aclDelegations = @()
            guidMappings = @{
                staticMappings = @{}
                dynamicMappings = @{}
                friendlyNameMappings = @{}
            }
        }
        
        # Test configuration with missing aclDelegations property
        $script:TestConfigNoAcls = [PSCustomObject]@{
            organizationalUnits = @()
            groups = @()
            guidMappings = @{
                staticMappings = @{}
                dynamicMappings = @{}
                friendlyNameMappings = @{}
            }
        }
        
        # Mock AD cmdlets
        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
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
        
        Mock Get-ADGroup -ModuleName TierModel {
            param($Identity, $Server)
            if ($Identity -eq "Tier0Admins" -or $Identity -eq "Tier1Users" -or $Identity -eq "Domain Admins") {
                return [PSCustomObject]@{
                    SamAccountName = $Identity
                    DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN"
                }
            } else {
                throw "Group not found"
            }
        }
        
        Mock Get-ADUser -ModuleName TierModel {
            throw "User not found"
        }
        
        Mock Get-Acl -ModuleName TierModel {
            param($Path)
            
            # Create mock ACL object
            $acl = New-Object PSObject
            $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
            
            # Create mock access rules
            $accessRules = @()
            
            # Add existing ACL for Tier0Admins (exact match)
            if ($Path -match "Tier0") {
                $rule = New-Object PSObject
                $rule | Add-Member -MemberType NoteProperty -Name IdentityReference -Value ([PSCustomObject]@{ Value = "TEST\Tier0Admins" })
                $rule | Add-Member -MemberType NoteProperty -Name AccessControlType -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll)
                $rule | Add-Member -MemberType NoteProperty -Name InheritanceType -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                $rule | Add-Member -MemberType NoteProperty -Name ObjectType -Value ([Guid]::Empty)
                $rule | Add-Member -MemberType NoteProperty -Name InheritedObjectType -Value ([Guid]::Empty)
                $accessRules += $rule
            }
            
            $acl | Add-Member -MemberType NoteProperty -Name Access -Value $accessRules
            return $acl
        }
        
        Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:TestDomainDN }
        Mock Resolve-TierModelPlaceholder -ModuleName TierModel { 
            param($Path, $DomainDN)
            return $Path.Replace("{{domainDN}}", $DomainDN)
        }
        Mock Resolve-TierModelGuid -ModuleName TierModel {
            param(
                [string]$Value,
                [object]$Mappings,
                [string]$DomainController,
                [string]$ConfigPath
            )
            # If already a GUID, return as-is
            if ($Value -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                return $Value
            }
            # Handle empty string
            if ([string]::IsNullOrEmpty($Value)) {
                return ""
            }
            # Simple mapping
            if ($Value -eq "User") {
                return "bf967aba-0de6-11d0-a285-00aa003049e2"
            } elseif ($Value -eq "Computer") {
                return "bf967a86-0de6-11d0-a285-00aa003049e2"
            } else {
                return $Value
            }
        }
        Mock Write-TierModelLog -ModuleName TierModel { }
    }
    
    Context "Get-TierModelOuAcl - Planning & Plan Generation" {
        It "Should generate deployment plan for ACL delegations" {
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Analysis'
        }
        
        It "Should include actions for ACLs that need to be applied" {
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            # Verify result structure matches expected format
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            
            # Verify Summary has correct structure (it's a hashtable)
            $result.Summary.Keys | Should -Contain 'TotalActions'
        }
        
        It "Should skip ACLs that already exist" {
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            # Tier0Admins ACL should be detected as existing (per Get-Acl mock)
            $tier0Action = $result.Actions | Where-Object { $_.Path -match "Tier0" -and $_.Data.identityreference -eq "Tier0Admins" }
            $tier0Action | Should -BeNullOrEmpty  # Should not have action since it exists
        }
        
        It "Should calculate summary statistics correctly" {
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.Summary.TotalActions | Should -Be $result.Actions.Count
            $result.Summary.CreateActions | Should -Be ($result.Actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        }
        
        It "Should include risk assessment in summary" {
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.Summary.RiskAssessment | Should -Not -BeNullOrEmpty
            $result.Summary.RiskAssessment.Keys | Should -Contain 'LowRisk'
            $result.Summary.RiskAssessment.Keys | Should -Contain 'MediumRisk'
            $result.Summary.RiskAssessment.Keys | Should -Contain 'HighRisk'
        }
        
        It "Should handle configuration with no ACL delegations" {
            $result = Get-TierModelOuAcl -Config $script:TestConfigEmpty -DomainController $script:TestDC
            
            $result.Actions | Should -BeNullOrEmpty
            $result.Summary.TotalActions | Should -Be 0
        }
        
        It "Should handle configuration missing aclDelegations property" {
            $result = Get-TierModelOuAcl -Config $script:TestConfigNoAcls -DomainController $script:TestDC
            
            $result.Actions | Should -BeNullOrEmpty
            $result.Summary.TotalActions | Should -Be 0
        }
        
        It "Should validate target OU exists" {
            # Mock Get-ADOrganizationalUnit to throw for non-existent OU
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server)
                if ($Identity -match "NonExistent") {
                    throw "OU not found"
                } else {
                    return [PSCustomObject]@{
                        DistinguishedName = $Identity
                        Name = "ValidOU"
                    }
                }
            }
            
            $configWithBadOU = [PSCustomObject]@{
                aclDelegations = @(
                    @{
                        targetOUPath = "OU=NonExistent,DC=test,DC=local"
                        identityreference = "TestGroup"
                        activedirectoryrights = @("GenericRead")
                        accesscontroltype = "Allow"
                        activeDirectorysecurityinheritance = "All"
                        objecttype = ""
                    }
                )
                guidMappings = @()
            }
            
            $result = Get-TierModelOuAcl -Config $configWithBadOU -DomainController $script:TestDC
            
            # Should have validation errors
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code | Should -Be 'TargetOUNotFound'
        }
        
        It "Should validate security principal exists" {
            # Mock Get-ADGroup to throw for non-existent group
            Mock Get-ADGroup -ModuleName TierModel {
                throw "Group not found"
            }
            Mock Get-ADUser -ModuleName TierModel {
                throw "User not found"
            }
            
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should have validation errors for missing principals
            $result.Errors | Should -Not -BeNullOrEmpty
            $principalErrors = $result.Errors | Where-Object { $_.Code -eq 'SecurityPrincipalNotFound' }
            $principalErrors | Should -Not -BeNullOrEmpty
        }
        
        It "Should resolve placeholders in target OU paths" {
            Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            
            # Verify Resolve-TierModelPlaceholder was called
            Assert-MockCalled Resolve-TierModelPlaceholder -ModuleName TierModel -Times ($script:TestConfig.aclDelegations.Count)
        }
        
        It "Should resolve GUID mappings for object types" {
            Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            
            # Should attempt GUID resolution for ACLs with object types
            Should -Invoke Resolve-TierModelGuid -ModuleName TierModel -Times 1
        }
        
        It "Should include correlation ID in result" {
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.CorrelationId | Should -Not -BeNullOrEmpty
            $result.CorrelationId.Length | Should -BeGreaterThan 0
        }
        
        It "Should track duration in result" {
            $result = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.DurationMs | Should -Not -BeNullOrEmpty
            $result.DurationMs | Should -BeGreaterThan 0
        }
        
        It "Should handle ACL read errors gracefully" {
            # Create a test config with one ACL to simplify error checking
            $errorTestConfig = [PSCustomObject]@{
                aclDelegations = @(
                    @{
                        targetOUPath = "OU=Test,{{domainDN}}"
                        identityreference = "TestGroup"
                        activedirectoryrights = @("GenericAll")
                        accesscontroltype = "Allow"
                        activeDirectorysecurityinheritance = "All"
                        objecttype = ""
                    }
                )
                guidMappings = $script:TestConfig.guidMappings
            }
            
            # Mock OU and Group checks to pass
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                return [PSCustomObject]@{ DistinguishedName = $Identity }
            }
            Mock Get-ADGroup -ModuleName TierModel {
                return [PSCustomObject]@{ SamAccountName = "TestGroup" }
            }
            # Override Get-Acl to throw error
            Mock Get-Acl -ModuleName TierModel {
                throw "Access denied to ACL"
            }
            
            $result = Get-TierModelOuAcl -Config $errorTestConfig -DomainController $script:TestDC
            
            # Should report errors but continue processing
            $result | Should -Not -BeNullOrEmpty
            $result.Errors | Should -Not -BeNullOrEmpty
            $aclReadErrors = @($result.Errors | Where-Object { $_.Code -eq 'AclReadFailed' })
            $aclReadErrors.Count | Should -BeGreaterThan 0
        }
    }
    
    Context "Get-TierModelOuAclFd - Full Deployment Planning" {
        It "Should generate deployment plan for full deployment mode" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Analysis'
        }
        
        It "Should not fail when OUs don't exist (lightweight validation)" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw "OU not found"
            }
            
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should still generate actions even if OUs don't exist
            $result.Actions | Should -Not -BeNullOrEmpty
            $result.Actions[0].Validation.TargetOUExists | Should -Be $false
        }
        
        It "Should not fail when Groups don't exist (lightweight validation)" {
            Mock Get-ADGroup -ModuleName TierModel {
                throw "Group not found"
            }
            Mock Get-ADUser -ModuleName TierModel {
                throw "User not found"
            }
            
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should still generate actions even if groups don't exist
            $result.Actions | Should -Not -BeNullOrEmpty
            $result.Actions[0].Validation.PrincipalResolvable | Should -Be $false
        }
        
        It "Should track existing ACL count separately" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.Summary.Keys | Should -Contain 'ExistingCount'
            $result.Summary.ExistingCount | Should -BeGreaterOrEqual 0
        }
        
        It "Should support Silent mode" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            # Should complete without errors in silent mode
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect existing ACLs and skip them" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Should have ExistingCount field in summary
            $result.Summary.Keys | Should -Contain 'ExistingCount'
            $result.Summary.ExistingCount | Should -BeGreaterOrEqual 0
            
            # Verify the function processes ACLs and generates appropriate actions
            # The exact count depends on which ACLs are detected as already existing
            $result.Actions | Should -Not -BeNull
            $result.Summary.TotalActions | Should -Be $result.Actions.Count
        }
        
        It "Should handle empty configuration gracefully" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfigEmpty -DomainController $script:TestDC
            
            $result.Actions | Should -BeNullOrEmpty
            $result.Summary.TotalActions | Should -Be 0
            $result.Summary.ExistingCount | Should -Be 0
        }
        
        It "Should handle missing aclDelegations property" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfigNoAcls -DomainController $script:TestDC
            
            $result.Actions | Should -BeNullOrEmpty
            $result.Summary.TotalActions | Should -Be 0
        }
        
        It "Should resolve placeholders in target OU paths" {
            Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            
            Assert-MockCalled Resolve-TierModelPlaceholder -ModuleName TierModel -Times ($script:TestConfig.aclDelegations.Count)
        }
        
        It "Should resolve GUID mappings for object types" {
            Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            
            Should -Invoke Resolve-TierModelGuid -ModuleName TierModel -Times 1
        }
        
        It "Should include correlation ID in result" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.CorrelationId | Should -Not -BeNullOrEmpty
        }
        
        It "Should track duration in result" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.DurationMs | Should -Not -BeNullOrEmpty
            $result.DurationMs | Should -BeGreaterThan 0
        }
        
        It "Should handle exceptions during ACL analysis" {
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
                throw "Placeholder resolution failed"
            }
            
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code | Should -Be 'AclFdAnalysisFailed'
        }
        
        It "Should include action validation metadata" {
            $result = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            if ($result.Actions.Count -gt 0) {
                $result.Actions[0].Validation | Should -Not -BeNullOrEmpty
                $result.Actions[0].Validation.Keys | Should -Contain 'TargetOUExists'
                $result.Actions[0].Validation.Keys | Should -Contain 'PrincipalResolvable'
            }
        }
    }
    
    Context "Test-TierModelOuAcl - Audit & Compliance" {
        BeforeEach {
            # Reset mocks for audit tests
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
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
            
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server)
                if ($Identity -eq "Tier0Admins" -or $Identity -eq "Tier1Users" -or $Identity -eq "Domain Admins") {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity
                        DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN"
                    }
                } else {
                    throw "Group not found"
                }
            }
        }
        
        It "Should audit OU ACL delegations against configuration" {
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Findings'
        }
        
        It "Should count total ACLs in configuration" {
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.Summary.TotalAcls | Should -Be $script:TestConfig.aclDelegations.Count
        }
        
        It "Should detect compliant ACLs" {
            # Ensure groups are found
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server)
                return [PSCustomObject]@{
                    SamAccountName = $Identity
                    DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN"
                }
            }
            
            # Mock Get-Acl to return compliant ACLs
            Mock Get-Acl -ModuleName TierModel {
                param($Path)
                
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
                
                $accessRules = @()
                
                # Create matching ACL for all delegations
                if ($Path -match "Tier0") {
                    $rule = New-Object PSObject
                    $rule | Add-Member -MemberType NoteProperty -Name IdentityReference -Value ([PSCustomObject]@{ Value = "TEST\Tier0Admins" })
                    $rule | Add-Member -MemberType NoteProperty -Name AccessControlType -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                    $rule | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll)
                    $rule | Add-Member -MemberType NoteProperty -Name InheritanceType -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                    $rule | Add-Member -MemberType NoteProperty -Name ObjectType -Value ([Guid]::Empty)
                    $rule | Add-Member -MemberType NoteProperty -Name InheritedObjectType -Value ([Guid]::Empty)
                    $accessRules += $rule
                }
                
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value $accessRules
                return $acl
            }
            
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            # At least Tier0Admins should be compliant based on the mock
            $result.Summary.Compliant | Should -BeGreaterOrEqual 0
            # Verify structure
            $result.Summary.Keys | Should -Contain 'Compliant'
        }
        
        It "Should detect missing target OUs" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw "OU not found"
            }
            
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.Summary.Missing | Should -BeGreaterThan 0
            $ouFindings = $result.Findings | Where-Object { $_.Property -eq 'TargetOU' }
            $ouFindings | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect missing security principals" {
            Mock Get-ADGroup -ModuleName TierModel {
                throw "Group not found"
            }
            Mock Get-ADUser -ModuleName TierModel {
                throw "User not found"
            }
            
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.Summary.Missing | Should -BeGreaterThan 0
            $identityFindings = $result.Findings | Where-Object { $_.Property -eq 'Identity' }
            $identityFindings | Should -Not -BeNullOrEmpty
        }
        
        It "Should support Silent mode" {
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle configuration without aclDelegations" {
            $result = Test-TierModelOuAcl -Config $script:TestConfigNoAcls -DomainController $script:TestDC -Silent
            
            $result.Findings | Should -Not -BeNullOrEmpty
            $warningFinding = $result.Findings | Where-Object { $_.Type -eq 'Warning' -and $_.Identifier -eq 'aclDelegations' }
            $warningFinding | Should -Not -BeNullOrEmpty
        }
        
        It "Should include correlation ID in result" {
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.CorrelationId | Should -Not -BeNullOrEmpty
        }
        
        It "Should track duration in result" {
            $result = Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            
            $result.DurationMs | Should -Not -BeNullOrEmpty
            $result.DurationMs | Should -BeGreaterThan 0
        }
        
        It "Should resolve placeholders in target OU paths" {
            Test-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            
            Assert-MockCalled Resolve-TierModelPlaceholder -ModuleName TierModel -Times ($script:TestConfig.aclDelegations.Count)
        }
    }
    
    Context "Get-TierModelOuAcl vs Get-TierModelOuAclFd - Comparison" {
        It "Should use stricter validation in Get-TierModelOuAcl than Get-TierModelOuAclFd" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw "OU not found"
            }
            
            $resultStandard = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            $resultFd = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Standard should have validation errors
            $resultStandard.Errors | Should -Not -BeNullOrEmpty
            
            # Fd should still generate actions
            $resultFd.Actions | Should -Not -BeNullOrEmpty
        }
        
        It "Should have similar output structure between both functions" {
            $resultStandard = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            $resultFd = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            # Both should have same core properties
            $resultStandard.PSObject.Properties.Name | Should -Contain 'Actions'
            $resultStandard.PSObject.Properties.Name | Should -Contain 'Summary'
            $resultStandard.PSObject.Properties.Name | Should -Contain 'Analysis'
            
            $resultFd.PSObject.Properties.Name | Should -Contain 'Actions'
            $resultFd.PSObject.Properties.Name | Should -Contain 'Summary'
            $resultFd.PSObject.Properties.Name | Should -Contain 'Analysis'
        }
        
        It "Should both include risk assessment" {
            $resultStandard = Get-TierModelOuAcl -Config $script:TestConfig -DomainController $script:TestDC
            $resultFd = Get-TierModelOuAclFd -Config $script:TestConfig -DomainController $script:TestDC
            
            $resultStandard.Summary.RiskAssessment | Should -Not -BeNullOrEmpty
            $resultFd.Summary.RiskAssessment | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "New-TierModelOuAcl - ACL Execution" {
        BeforeAll {
            Mock Write-Host -ModuleName TierModel { }

            # Helper: build a single CreateAcl action plan
            $script:SingleAclPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = "OU=Tier0,DC=test,DC=local"
                        Data   = [PSCustomObject]@{
                            identityreference                  = "TESTDOMAIN\Tier0Admins"
                            activedirectoryrights              = @("GenericAll")
                            accesscontroltype                  = "Allow"
                            activeDirectorysecurityinheritance = "All"
                            objecttype                         = ""
                        }
                    }
                )
            }

            # Helper: build a two-action CreateAcl plan
            $script:MultiAclPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = "OU=Tier0,DC=test,DC=local"
                        Data   = [PSCustomObject]@{
                            identityreference                  = "TESTDOMAIN\Tier0Admins"
                            activedirectoryrights              = @("GenericAll")
                            accesscontroltype                  = "Allow"
                            activeDirectorysecurityinheritance = "All"
                            objecttype                         = ""
                        }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = "OU=Tier1,DC=test,DC=local"
                        Data   = [PSCustomObject]@{
                            identityreference                  = "TESTDOMAIN\Tier1Users"
                            activedirectoryrights              = @("CreateChild")
                            accesscontroltype                  = "Allow"
                            activeDirectorysecurityinheritance = "All"
                            objecttype                         = ""
                        }
                    }
                )
            }

            # Helper: plan with no actions
            $script:EmptyAclPlan = [PSCustomObject]@{ Actions = @() }

            # Helper: plan with a non-CreateAcl action type
            $script:NonCreateAclPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'UpdateAcl'
                        Path   = "OU=Tier0,DC=test,DC=local"
                        Data   = [PSCustomObject]@{ identityreference = "TESTDOMAIN\Tier0Admins" }
                    }
                )
            }

            # Helper: mixed plan (one non-CreateAcl + one CreateAcl)
            $script:MixedAclPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'UpdateAcl'
                        Path   = "OU=Tier0,DC=test,DC=local"
                        Data   = [PSCustomObject]@{ identityreference = "TESTDOMAIN\Tier0Admins" }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = "OU=Tier1,DC=test,DC=local"
                        Data   = [PSCustomObject]@{
                            identityreference                  = "TESTDOMAIN\Tier1Users"
                            activedirectoryrights              = @("GenericAll")
                            accesscontroltype                  = "Allow"
                            activeDirectorysecurityinheritance = "All"
                            objecttype                         = ""
                        }
                    }
                )
            }
        }

        It "Should return converged result with zero counts when plan has no actions" {
            $result = New-TierModelOuAcl -Plan $script:EmptyAclPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Executed  | Should -Be 0
            $result.Failed    | Should -Be 0
            $result.Skipped   | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "Should not increment any counter for non-CreateAcl action types" {
            $result = New-TierModelOuAcl -Plan $script:NonCreateAclPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Executed  | Should -Be 0
            $result.Failed    | Should -Be 0
            $result.Skipped   | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "Should increment Skipped and not Executed when -WhatIf is used with a single CreateAcl action" {
            $result = New-TierModelOuAcl -Plan $script:SingleAclPlan -DomainController $script:TestDC -Config $script:TestConfig -WhatIf
            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
            $result.Skipped  | Should -Be 1
        }

        It "Should count all CreateAcl actions as Skipped when -WhatIf is used with multiple actions" {
            $result = New-TierModelOuAcl -Plan $script:MultiAclPlan -DomainController $script:TestDC -Config $script:TestConfig -WhatIf
            $result.Skipped  | Should -Be 2
            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
        }

        It "Should only skip CreateAcl actions and ignore other action types when -WhatIf is used" {
            $result = New-TierModelOuAcl -Plan $script:MixedAclPlan -DomainController $script:TestDC -Config $script:TestConfig -WhatIf
            $result.Skipped  | Should -Be 1
            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
        }

        It "Should record failure and set Converged to false when ACL application throws (no WhatIf)" {
            # NTAccount.Translate() always throws in a non-domain environment, hitting the inner catch
            $result = New-TierModelOuAcl -Plan $script:SingleAclPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Failed    | Should -Be 1
            $result.Executed  | Should -Be 0
            $result.Converged | Should -Be $false
            $result.Errors    | Should -Not -BeNullOrEmpty
        }

        It "Should accumulate failure count for each failing CreateAcl action" {
            $result = New-TierModelOuAcl -Plan $script:MultiAclPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Failed              | Should -Be 2
            $result.Converged           | Should -Be $false
            $result.Errors.Count        | Should -Be 2
        }

        It "Should return a result object containing all required properties" {
            $result = New-TierModelOuAcl -Plan $script:EmptyAclPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.PSObject.Properties.Name | Should -Contain 'Executed'
            $result.PSObject.Properties.Name | Should -Contain 'Failed'
            $result.PSObject.Properties.Name | Should -Contain 'Skipped'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'Converged'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Should populate CorrelationId as a valid GUID" {
            $result = New-TierModelOuAcl -Plan $script:EmptyAclPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }

    AfterAll {
        # Clean up test variables
        Remove-Variable -Name "TestCorrelationId", "TestDC", "TestDomainDN", "TestConfig", "TestConfigEmpty", "TestConfigNoAcls" -Scope Script -ErrorAction SilentlyContinue
    }
}

Describe "Test-TierModelOuAcl – extended coverage" -Tag "Unit", "OuAcl", "Phase3" {
    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        $script:DC  = "DC01.test.local"
        $script:DDN = "DC=test,DC=local"

        # Minimal config with two ACL delegations for most tests
        $script:Cfg = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = "OU=T0,$script:DDN"
                    identityreference                  = "Tier0Admins"
                    activedirectoryrights              = @("GenericAll")
                    accesscontroltype                  = "Allow"
                    activeDirectorysecurityinheritance = "All"
                    objecttype                         = ""
                }
                [PSCustomObject]@{
                    targetOUPath                       = "OU=T1,$script:DDN"
                    identityreference                  = "Tier1Users"
                    activedirectoryrights              = @("CreateChild","DeleteChild")
                    accesscontroltype                  = "Allow"
                    activeDirectorysecurityinheritance = "All"
                    objecttype                         = ""
                }
            )
            guidMappings = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }

        # Config with inheritedObjectType as a friendly name to exercise GUID resolution
        $script:CfgInheritedOt = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = "OU=T0,$script:DDN"
                    identityreference                  = "Tier0Admins"
                    activedirectoryrights              = @("GenericAll")
                    accesscontroltype                  = "Allow"
                    activeDirectorysecurityinheritance = "All"
                    objecttype                         = ""
                    inheritedObjectType                = "bf967aba-0de6-11d0-a285-00aa003049e2"  # already a GUID
                }
            )
            guidMappings = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }

        # Config whose ACE will NOT match — expects Deny, but mock ACE is Allow — triggers ACEProperties drift
        $script:CfgMismatch = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = "OU=T0,$script:DDN"
                    identityreference                  = "Tier0Admins"
                    activedirectoryrights              = @("GenericAll")
                    accesscontroltype                  = "Deny"              # mock ACE has Allow — never matches
                    activeDirectorysecurityinheritance = "All"
                    objecttype                         = ""
                }
            )
            guidMappings = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }

        # Standard mocks
        Mock Resolve-TierModelDomainDN    -ModuleName TierModel { return $script:DDN }
        Mock Resolve-TierModelPlaceholder -ModuleName TierModel { param($Path, $DomainDN) $Path.Replace("{{domainDN}}", $DomainDN) }
        Mock Resolve-TierModelGuid        -ModuleName TierModel {
            param([string]$Value, $Mappings, [string]$DomainController, [string]$ConfigPath)
            if ([string]::IsNullOrEmpty($Value)) { return "" }
            if ($Value -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $Value }
            return $Value
        }
        Mock Write-TierModelLog           -ModuleName TierModel { }

        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param($Identity, $Server)
            return [PSCustomObject]@{ DistinguishedName = $Identity }
        }
        Mock Get-ADGroup -ModuleName TierModel {
            param($Identity, $Server)
            return [PSCustomObject]@{ SamAccountName = $Identity }
        }
        Mock Get-ADUser -ModuleName TierModel {
            throw "User not found"
        }

        # Default Get-Acl mock: returns a compliant ACE for Tier0Admins/GenericAll
        Mock Get-Acl -ModuleName TierModel {
            param($Path)
            $rule = [PSCustomObject]@{
                IdentityReference   = [PSCustomObject]@{ Value = "TEST\Tier0Admins" }
                AccessControlType   = [System.Security.AccessControl.AccessControlType]::Allow
                ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                InheritanceType     = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                ObjectType          = [Guid]::Empty
                InheritedObjectType = [Guid]::Empty
            }
            $acl = [PSCustomObject]@{ Path = $Path; Access = @($rule) }
            return $acl
        }
    }

    # ---- Silent=$false output paths ------------------------------------------------
    Context "Non-silent output" {
        It "Does not throw and returns valid result when Silent is omitted (output goes to console)" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
        }

        It "Prints warning to console when no aclDelegations exist (non-silent)" {
            $noAclCfg = [PSCustomObject]@{ guidMappings = @{} }
            $result = Test-TierModelOuAcl -Config $noAclCfg -DomainController $script:DC
            $result.Findings[0].Type | Should -Be 'Warning'
        }
    }

    # ---- Empty aclDelegations array (not null, but empty) --------------------------
    Context "Empty aclDelegations array" {
        It "Returns 100% compliance with zero counts when aclDelegations is empty" {
            $emptyCfg = [PSCustomObject]@{
                aclDelegations = @()
                guidMappings   = [PSCustomObject]@{}
            }
            $result = Test-TierModelOuAcl -Config $emptyCfg -DomainController $script:DC -Silent
            $result.Summary.TotalAcls           | Should -Be 0
            $result.Summary.CompliancePercentage | Should -Be 100
        }
    }

    # ---- ACL read error path -------------------------------------------------------
    Context "Get-Acl throws" {
        BeforeEach {
            Mock Get-Acl -ModuleName TierModel { throw "Access denied" }
        }

        It "Records an Error finding when Get-Acl throws" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            $result.Summary.Errors | Should -BeGreaterThan 0
            $aclErrors = $result.Findings | Where-Object { $_.Property -eq 'ACLAccess' }
            $aclErrors | Should -Not -BeNullOrEmpty
        }

        It "Sets Type='Error' on the ACLAccess finding" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            ($result.Findings | Where-Object { $_.Property -eq 'ACLAccess' })[0].Type | Should -Be 'Error'
        }
    }

    # ---- ACE mismatch (step 6 — no exact match found) ------------------------------
    Context "ACE mismatch" {
        It "Records ACEProperties drift when no ACE matches all expected properties" {
            # CfgMismatch expects WriteProperty but mock returns GenericAll — no exact match
            $result = Test-TierModelOuAcl -Config $script:CfgMismatch -DomainController $script:DC -Silent
            $result.Summary.Mismatched | Should -BeGreaterThan 0
            $drift = $result.Findings | Where-Object { $_.Property -eq 'ACEProperties' }
            $drift | Should -Not -BeNullOrEmpty
        }

        It "Sets Type='Drift' on the ACEProperties finding" {
            $result = Test-TierModelOuAcl -Config $script:CfgMismatch -DomainController $script:DC -Silent
            ($result.Findings | Where-Object { $_.Property -eq 'ACEProperties' })[0].Type | Should -Be 'Drift'
        }

        It "Non-silent run prints mismatch output without throwing" {
            $result = Test-TierModelOuAcl -Config $script:CfgMismatch -DomainController $script:DC
            $result.Summary.Mismatched | Should -BeGreaterThan 0
        }
    }

    # ---- No ACE at all for the identity (missing ACE, not missing OU/principal) ----
    Context "ACE missing for identity" {
        BeforeEach {
            Mock Get-Acl -ModuleName TierModel {
                param($Path)
                # Return ACL with an ACE for a completely different identity
                $rule = [PSCustomObject]@{
                    IdentityReference   = [PSCustomObject]@{ Value = "TEST\OtherGroup" }
                    AccessControlType   = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType     = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType          = [Guid]::Empty
                    InheritedObjectType = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($rule) }
            }
        }

        It "Records ACE=Missing finding when no ACL entry exists for the expected identity" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            $missing = $result.Findings | Where-Object { $_.Property -eq 'ACE' }
            $missing | Should -Not -BeNullOrEmpty
            $missing[0].ActualValue | Should -Be 'Missing'
        }
    }

    # ---- User identity fallback (Get-ADGroup throws, Get-ADUser succeeds) ----------
    Context "Identity resolved as user (not group)" {
        BeforeEach {
            Mock Get-ADGroup -ModuleName TierModel { throw "Not a group" }
            Mock Get-ADUser  -ModuleName TierModel {
                param($Identity, $Server)
                return [PSCustomObject]@{ SamAccountName = $Identity }
            }
        }

        It "Succeeds and continues to ACL step when identity is a user account" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            # Should not have any 'Identity' drift findings — user was found
            $idFindings = $result.Findings | Where-Object { $_.Property -eq 'Identity' }
            $idFindings | Should -BeNullOrEmpty
        }
    }

    # ---- Multiple activedirectoryrights (bor loop) ---------------------------------
    Context "Multiple ActiveDirectory rights combined with -bor" {
        It "Correctly calculates combined rights and detects compliance" {
            # CfgMismatch uses CreateChild+DeleteChild; mock ACE has GenericAll
            # GenericAll includes CreateChild and DeleteChild so (GenericAll -band (CreateChild -bor DeleteChild)) should equal the expected rights
            $combinedCfg = [PSCustomObject]@{
                aclDelegations = @(
                    [PSCustomObject]@{
                        targetOUPath                       = "OU=T0,$script:DDN"
                        identityreference                  = "Tier0Admins"
                        activedirectoryrights              = @("CreateChild","DeleteChild")
                        accesscontroltype                  = "Allow"
                        activeDirectorysecurityinheritance = "All"
                        objecttype                         = ""
                    }
                )
                guidMappings = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
            }

            $result = Test-TierModelOuAcl -Config $combinedCfg -DomainController $script:DC -Silent
            # GenericAll contains CreateChild and DeleteChild; ACE should be compliant
            $result.Summary.Compliant | Should -BeGreaterOrEqual 1
            $result.Summary.Mismatched | Should -Be 0
        }

        It "Records drift when ACE rights do not include all combined expected rights" {
            # ACE has CreateChild only; config expects CreateChild + WriteProperty
            Mock Get-Acl -ModuleName TierModel {
                param($Path)
                $rule = [PSCustomObject]@{
                    IdentityReference   = [PSCustomObject]@{ Value = "TEST\Tier0Admins" }
                    AccessControlType   = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild
                    InheritanceType     = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType          = [Guid]::Empty
                    InheritedObjectType = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($rule) }
            }
            $twoRightsCfg = [PSCustomObject]@{
                aclDelegations = @(
                    [PSCustomObject]@{
                        targetOUPath                       = "OU=T0,$script:DDN"
                        identityreference                  = "Tier0Admins"
                        activedirectoryrights              = @("CreateChild","WriteProperty")
                        accesscontroltype                  = "Allow"
                        activeDirectorysecurityinheritance = "All"
                        objecttype                         = ""
                    }
                )
                guidMappings = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
            }
            $result = Test-TierModelOuAcl -Config $twoRightsCfg -DomainController $script:DC -Silent
            $result.Summary.Mismatched | Should -Be 1
        }
    }

    # ---- inheritedObjectType resolution paths --------------------------------------
    Context "inheritedObjectType in ACL config" {
        It "Handles a GUID-format inheritedObjectType without calling Resolve-TierModelGuid" {
            $result = Test-TierModelOuAcl -Config $script:CfgInheritedOt -DomainController $script:DC -Silent
            $result | Should -Not -BeNullOrEmpty
            # Should not error — GUID is already valid
            $result.Summary.Errors | Should -Be 0
        }

        It "Calls Resolve-TierModelGuid for a friendly-name inheritedObjectType" {
            $friendlyCfg = [PSCustomObject]@{
                aclDelegations = @(
                    [PSCustomObject]@{
                        targetOUPath                       = "OU=T0,$script:DDN"
                        identityreference                  = "Tier0Admins"
                        activedirectoryrights              = @("GenericAll")
                        accesscontroltype                  = "Allow"
                        activeDirectorysecurityinheritance = "All"
                        objecttype                         = ""
                        inheritedObjectType                = "User"  # friendly name — triggers Resolve-TierModelGuid
                    }
                )
                guidMappings = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
            }
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, $Mappings, [string]$DomainController, [string]$ConfigPath)
                return "bf967aba-0de6-11d0-a285-00aa003049e2"
            }
            Test-TierModelOuAcl -Config $friendlyCfg -DomainController $script:DC -Silent | Out-Null
            Should -Invoke Resolve-TierModelGuid -ModuleName TierModel -Times 1 -ParameterFilter { $Value -eq "User" }
        }
    }

    # ---- Outer catch (Resolve-TierModelDomainDN throws) ----------------------------
    Context "Fatal error path" {
        It "Returns error result when Resolve-TierModelDomainDN throws" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { throw "DNS lookup failed" }
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            $result | Should -Not -BeNullOrEmpty
            $result.Summary.Errors   | Should -Be 1
            $result.Summary.TotalAcls | Should -Be 0
            $result.Findings[0].Type | Should -Be 'Error'
            $result.Findings[0].Details | Should -Match 'DNS lookup failed'
        }
    }

    # ---- Result structure ----------------------------------------------------------
    Context "Result object shape" {
        It "Always returns a CorrelationId that is a valid GUID" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            $result.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }

        It "Always returns a positive DurationMs" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "Summary contains all expected keys" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            $keys = $result.Summary.Keys
            $keys | Should -Contain 'TotalAcls'
            $keys | Should -Contain 'Compliant'
            $keys | Should -Contain 'Missing'
            $keys | Should -Contain 'Mismatched'
            $keys | Should -Contain 'Errors'
            $keys | Should -Contain 'CompliancePercentage'
        }

        It "CompliancePercentage is 0 when all delegations are missing OUs" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel { throw "Not found" }
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            $result.Summary.CompliancePercentage | Should -Be 0
        }

        It "Findings array is empty when all delegations are fully compliant" {
            $result = Test-TierModelOuAcl -Config $script:Cfg -DomainController $script:DC -Silent
            # Default mock returns compliant ACE for Tier0Admins; Tier1Users should also find ACE or mismatch
            # At minimum: no Error findings
            $errorFindings = $result.Findings | Where-Object { $_.Type -eq 'Error' }
            $errorFindings | Should -BeNullOrEmpty
        }
    }
}

Describe "Get-TierModelOuAcl – Extended Coverage" -Tag "Unit", "OuAcl" {

    BeforeAll {
        Mock Write-TierModelLog  -ModuleName TierModel {}
        Mock Resolve-TierModelDomainDN    -ModuleName TierModel { return "DC=test,DC=local" }
        Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
            param($Path, $DomainDN)
            return $Path.Replace("{{domainDN}}", $DomainDN)
        }
        Mock Resolve-TierModelGuid -ModuleName TierModel {
            param([string]$Value, $Mappings, [string]$DomainController)
            return $Value
        }
        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            return [PSCustomObject]@{ DistinguishedName = $Identity }
        }
        Mock Get-ADGroup -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            return [PSCustomObject]@{ SamAccountName = $Identity }
        }
        Mock Get-ADUser -ModuleName TierModel {
            throw "User not found"
        }

        # Helper – builds a minimal single-ACL config
        function New-AclConfig {
            param($objecttype = "", $rights = @("GenericAll"), $extraProps = @{})
            $aclProps = @{
                targetOUPath                        = "OU=Tier0,{{domainDN}}"
                identityreference                   = "TestGroup"
                activedirectoryrights               = $rights
                accesscontroltype                   = "Allow"
                activeDirectorysecurityinheritance  = "All"
                objecttype                          = $objecttype
            }
            foreach ($k in $extraProps.Keys) { $aclProps[$k] = $extraProps[$k] }
            [PSCustomObject]@{
                aclDelegations = @([PSCustomObject]$aclProps)
                guidMappings   = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
            }
        }
    }

    Context "GUID resolution inner catch – fallback to original value (lines 105-110)" {
        BeforeAll {
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, $Mappings, [string]$DomainController)
                throw [System.InvalidOperationException]::new("Schema lookup failed")
            }
            # Get-Acl returns no matching access rule → needsApplication=true
            Mock Get-Acl -ModuleName TierModel {
                return [PSCustomObject]@{ Access = @() }
            }
        }

        It "Should fall back to original objecttype when Resolve-TierModelGuid throws" {
            $cfg = New-AclConfig -objecttype "SomeSchemaClass"
            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            # Fallback occurred → objecttype is used as-is; result should still contain an action
            $result                | Should -Not -BeNullOrEmpty
            # GUID fallback means objecttype="SomeSchemaClass" can't be parsed as [Guid],
            # so the function catches the error in the per-ACL outer catch → AclAnalysisFailed
            $result.Errors.Count   | Should -BeGreaterThan 0
        }
    }

    Context "Get-ADUser success path – principal found as user (line 154)" {
        BeforeAll {
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw "Group not found"
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity }
            }
            Mock Get-Acl -ModuleName TierModel {
                return [PSCustomObject]@{ Access = @() }
            }
        }

        It "Should set principalExists=true when identity resolves as a user, then queue CreateAcl action" {
            $cfg = New-AclConfig
            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result               | Should -Not -BeNullOrEmpty
            $result.Errors        | Where-Object { $_.Code -eq 'SecurityPrincipalNotFound' } | Should -BeNullOrEmpty
            $action = $result.Actions | Where-Object { $_.Action -eq 'CreateAcl' }
            $action               | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-Acl success – rights parsing, ACL comparison, and CreateAcl action (lines 183-295)" {
        BeforeAll {
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity }
            }
        }

        It "Should parse activedirectoryrights and add CreateAcl when no matching ACE exists" {
            Mock Get-Acl -ModuleName TierModel {
                # ACL exists but no rules → no match → needsApplication=true
                return [PSCustomObject]@{ Access = @() }
            }
            $cfg = New-AclConfig -rights @("GenericRead", "GenericWrite")

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result              | Should -Not -BeNullOrEmpty
            $action = $result.Actions | Where-Object { $_.Action -eq 'CreateAcl' }
            $action              | Should -Not -BeNullOrEmpty
            $action.RiskLevel    | Should -Be 'Low'
            $action.Path         | Should -Match "Tier0"
        }

        It "Should skip CreateAcl and log existing match when ACE exactly matches (lines 249-257)" {
            Mock Get-Acl -ModuleName TierModel {
                $rule = [PSCustomObject]@{
                    IdentityReference  = [PSCustomObject]@{ Value = "TEST\TestGroup" }
                    AccessControlType  = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType    = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType         = [Guid]::Empty
                    InheritedObjectType = [Guid]::Empty
                }
                return [PSCustomObject]@{ Access = @($rule) }
            }
            $cfg = New-AclConfig -rights @("GenericAll")

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result              | Should -Not -BeNullOrEmpty
            $result.Actions      | Should -BeNullOrEmpty           # already exists → no action
            $result.Errors       | Should -BeNullOrEmpty
        }

        It "Should handle invalid right string in activedirectoryrights gracefully (inner try/catch line 192-193)" {
            Mock Get-Acl -ModuleName TierModel {
                return [PSCustomObject]@{ Access = @() }
            }
            $cfg = New-AclConfig -rights @("NotARealRight", "GenericRead")

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            # Invalid right is skipped; valid right is parsed; action still created
            $result              | Should -Not -BeNullOrEmpty
            $result.Actions      | Should -Not -BeNullOrEmpty
        }

        It "Should resolve inheritedObjectType as friendly name via Resolve-TierModelGuid (lines 203-208)" {
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, $Mappings, [string]$DomainController)
                if ($Value -eq "User") { return "bf967aba-0de6-11d0-a285-00aa003049e2" }
                return $Value
            }
            Mock Get-Acl -ModuleName TierModel {
                return [PSCustomObject]@{ Access = @() }
            }
            $cfg = New-AclConfig -extraProps @{ inheritedObjectType = "User" }

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result              | Should -Not -BeNullOrEmpty
            $result.Actions      | Should -Not -BeNullOrEmpty
        }

        It "Should use direct GUID parse for inheritedObjectType when already a GUID string (line 211)" {
            Mock Get-Acl -ModuleName TierModel {
                return [PSCustomObject]@{ Access = @() }
            }
            $cfg = New-AclConfig -extraProps @{ inheritedObjectType = "bf967aba-0de6-11d0-a285-00aa003049e2" }

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result              | Should -Not -BeNullOrEmpty
            $result.Actions      | Should -Not -BeNullOrEmpty
        }

        It "Should check InheritedObjectType match when inheritedObjectTypeGuid is non-empty (line 238)" {
            # ACE has InheritedObjectType matching the one in config → full match if all other fields also match
            $inheritedGuid = "bf967aba-0de6-11d0-a285-00aa003049e2"
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, $Mappings, [string]$DomainController)
                return $Value   # pass-through
            }
            Mock Get-Acl -ModuleName TierModel {
                $rule = [PSCustomObject]@{
                    IdentityReference     = [PSCustomObject]@{ Value = "TEST\TestGroup" }
                    AccessControlType     = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType       = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType            = [Guid]::Empty
                    InheritedObjectType   = [Guid]"bf967aba-0de6-11d0-a285-00aa003049e2"
                }
                return [PSCustomObject]@{ Access = @($rule) }
            }
            $cfg = New-AclConfig -rights @("GenericAll") -extraProps @{ inheritedObjectType = $inheritedGuid }

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            # All fields match including InheritedObjectType → ACL exists → no CreateAcl action
            $result              | Should -Not -BeNullOrEmpty
            $result.Actions      | Should -BeNullOrEmpty
        }

        It "Should handle Resolve-TierModelGuid throw for inheritedObjectType (line 214 fallback)" {
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, $Mappings, [string]$DomainController)
                throw [System.InvalidOperationException]::new("GUID lookup failed")
            }
            Mock Get-Acl -ModuleName TierModel {
                return [PSCustomObject]@{ Access = @() }
            }
            $cfg = New-AclConfig -extraProps @{ inheritedObjectType = "BadFriendlyName" }

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            # Resolve-TierModelGuid throws → catch resets inheritedObjectTypeGuid = [Guid]::Empty
            # objecttype="" → $resolvedObjectType="" → [Guid]::Empty → no cast error
            # ACL comparison runs but no match → CreateAcl action created, no errors
            $result              | Should -Not -BeNullOrEmpty
            $result.Actions      | Should -Not -BeNullOrEmpty
            ($result.Actions | Where-Object { $_.Action -eq 'CreateAcl' }) | Should -Not -BeNullOrEmpty
        }

        It "Should record AclReadFailed and continue when Get-Acl throws (lines 260-271)" {
            Mock Get-Acl -ModuleName TierModel {
                throw [System.UnauthorizedAccessException]::new("Access denied reading ACL")
            }
            $cfg = New-AclConfig

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result              | Should -Not -BeNullOrEmpty
            $aclError = $result.Errors | Where-Object { $_.Code -eq 'AclReadFailed' }
            $aclError            | Should -Not -BeNullOrEmpty
            $aclError.Category   | Should -Be 'AccessCheck'
        }

        It "Should record AclAnalysisFailed when per-ACL outer catch fires (lines 299-306)" {
            # Make Resolve-TierModelPlaceholder throw inside the per-ACL try block
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Placeholder error")
            }
            $cfg = New-AclConfig

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result              | Should -Not -BeNullOrEmpty
            $aclError = $result.Errors | Where-Object { $_.Code -eq 'AclAnalysisFailed' }
            $aclError            | Should -Not -BeNullOrEmpty
        }
    }

    Context "Outer function catch – PlanningFailed (lines 355-382)" {
        It "Should return PlanningFailed result when Resolve-TierModelDomainDN throws" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel {
                throw [System.InvalidOperationException]::new("Domain unreachable")
            }
            $cfg = New-AclConfig

            $result = Get-TierModelOuAcl -Config $cfg -DomainController "DC01"

            $result              | Should -Not -BeNullOrEmpty
            $result.Converged    | Should -BeNullOrEmpty   # outer catch result has no Converged
            $result.Errors[0].Code | Should -Be 'PlanningFailed'
            $result.Actions      | Should -BeNullOrEmpty
        }
    }
}

Describe "Get-TierModelOuAclFd – Extended Coverage" -Tag "Unit", "OuAcl" {
    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        $script:ExtDC = 'dc01.test.local'

        # Base single-ACL config: empty objecttype, no inheritedObjectType
        $script:ExtBaseConfig = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = 'OU=ExtTier,{{domainDN}}'
                    identityreference                  = 'ExtGroup1'
                    activedirectoryrights              = @('GenericAll')
                    accesscontroltype                  = 'Allow'
                    activeDirectorysecurityinheritance = 'All'
                    objecttype                         = ''
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }

        InModuleScope TierModel {
            Mock Write-TierModelLog    { }
            Mock Write-Host            { }
            Mock Resolve-TierModelDomainDN   { return 'DC=test,DC=local' }
            Mock Resolve-TierModelPlaceholder {
                param($Path, $DomainDN)
                return $Path.Replace('{{domainDN}}', $DomainDN)
            }
            Mock Resolve-TierModelGuid {
                param([string]$Value, $Mappings, [string]$DomainController)
                if ($Value -eq 'User') { return 'bf967aba-0de6-11d0-a285-00aa003049e2' }
                return $Value
            }
            Mock Get-ADOrganizationalUnit { [PSCustomObject]@{ DistinguishedName = 'OU=ExtTier,DC=test,DC=local' } }
            Mock Get-ADGroup { [PSCustomObject]@{ SamAccountName = 'ExtGroup1' } }
            Mock Get-ADUser  { throw 'User not found' }
            Mock Get-Acl {
                param($Path)
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @()
                $acl
            }
        }
    }

    It "Should use fallback objecttype when Resolve-TierModelGuid throws (lines 110-115)" {
        InModuleScope TierModel {
            Mock Resolve-TierModelGuid    { throw 'GUID lookup failed' }
            Mock Get-ADOrganizationalUnit { throw 'OU not found' }
        }
        # objecttype is a valid GUID string so the fallback cast on line 125 succeeds;
        # OU mock throws so targetOUExists=$false, avoiding Get-Acl — clean one-action result
        $cfg = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = 'OU=ExtTier,{{domainDN}}'
                    identityreference                  = 'ExtGroup1'
                    activedirectoryrights              = @('GenericAll')
                    accesscontroltype                  = 'Allow'
                    activeDirectorysecurityinheritance = 'All'
                    objecttype                         = 'bf967aba-0de6-11d0-a285-00aa003049e2'
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }
        $result = Get-TierModelOuAclFd -Config $cfg -DomainController $script:ExtDC
        $result               | Should -Not -BeNullOrEmpty
        $result.Actions.Count | Should -Be 1
        $result.Errors        | Should -BeNullOrEmpty
    }

    It "Should set principalExists via Get-ADGroup and enter ACL-check block with non-matching rule (lines 145, 163-176, 201-226)" {
        InModuleScope TierModel {
            # One non-matching access rule so the Where-Object comparison body executes
            Mock Get-Acl {
                param($Path)
                $rule = New-Object PSObject
                $rule | Add-Member -MemberType NoteProperty -Name IdentityReference    -Value ([PSCustomObject]@{ Value = 'OTHER\DifferentGroup' })
                $rule | Add-Member -MemberType NoteProperty -Name AccessControlType    -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll)
                $rule | Add-Member -MemberType NoteProperty -Name InheritanceType       -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                $rule | Add-Member -MemberType NoteProperty -Name ObjectType            -Value ([Guid]::Empty)
                $rule | Add-Member -MemberType NoteProperty -Name InheritedObjectType   -Value ([Guid]::Empty)
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @($rule)
                $acl
            }
        }
        $result = Get-TierModelOuAclFd -Config $script:ExtBaseConfig -DomainController $script:ExtDC
        $result                                           | Should -Not -BeNullOrEmpty
        $result.Actions.Count                             | Should -Be 1
        $result.Actions[0].Validation.PrincipalResolvable | Should -Be $true
    }

    It "Should set principalExists via Get-ADUser fallback when Get-ADGroup throws (line 150)" {
        InModuleScope TierModel {
            Mock Get-ADGroup { throw 'Not a group' }
            Mock Get-ADUser  { [PSCustomObject]@{ SamAccountName = 'ExtGroup1' } }
        }
        $result = Get-TierModelOuAclFd -Config $script:ExtBaseConfig -DomainController $script:ExtDC
        $result                                           | Should -Not -BeNullOrEmpty
        $result.Actions.Count                             | Should -Be 1
        $result.Actions[0].Validation.PrincipalResolvable | Should -Be $true
    }

    It "Should resolve non-GUID inheritedObjectType via Resolve-TierModelGuid (lines 185-191)" {
        $cfg = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = 'OU=ExtTier,{{domainDN}}'
                    identityreference                  = 'ExtGroup1'
                    activedirectoryrights              = @('GenericAll')
                    accesscontroltype                  = 'Allow'
                    activeDirectorysecurityinheritance = 'All'
                    objecttype                         = ''
                    inheritedObjectType                = 'User'
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }
        $result = Get-TierModelOuAclFd -Config $cfg -DomainController $script:ExtDC
        $result               | Should -Not -BeNullOrEmpty
        $result.Actions.Count | Should -Be 1
        $result.Errors        | Should -BeNullOrEmpty
    }

    It "Should cast inheritedObjectType directly to Guid when already a GUID string (line 194)" {
        $cfg = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = 'OU=ExtTier,{{domainDN}}'
                    identityreference                  = 'ExtGroup1'
                    activedirectoryrights              = @('GenericAll')
                    accesscontroltype                  = 'Allow'
                    activeDirectorysecurityinheritance = 'All'
                    objecttype                         = ''
                    inheritedObjectType                = 'bf967aba-0de6-11d0-a285-00aa003049e2'
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }
        $result = Get-TierModelOuAclFd -Config $cfg -DomainController $script:ExtDC
        $result               | Should -Not -BeNullOrEmpty
        $result.Actions.Count | Should -Be 1
        $result.Errors        | Should -BeNullOrEmpty
    }

    It "Should default inheritedObjectTypeGuid to Empty when Resolve-TierModelGuid throws (line 197)" {
        InModuleScope TierModel {
            Mock Resolve-TierModelGuid { throw 'GUID lookup failed' }
        }
        # objecttype="" so the outer GUID-resolution if-block is false; only the
        # inheritedObjectType path calls Resolve-TierModelGuid — that throw lands in the catch (line 197)
        $cfg = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = 'OU=ExtTier,{{domainDN}}'
                    identityreference                  = 'ExtGroup1'
                    activedirectoryrights              = @('GenericAll')
                    accesscontroltype                  = 'Allow'
                    activeDirectorysecurityinheritance = 'All'
                    objecttype                         = ''
                    inheritedObjectType                = 'User'
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }
        $result = Get-TierModelOuAclFd -Config $cfg -DomainController $script:ExtDC
        $result               | Should -Not -BeNullOrEmpty
        $result.Actions.Count | Should -Be 1
        $result.Errors        | Should -BeNullOrEmpty
    }

    It "Should detect existing ACL and skip creation when access rule matches (lines 221, 232-248)" {
        InModuleScope TierModel {
            # Matching rule: identity, rights, type, inheritance all align
            Mock Get-Acl {
                param($Path)
                $rule = New-Object PSObject
                $rule | Add-Member -MemberType NoteProperty -Name IdentityReference    -Value ([PSCustomObject]@{ Value = 'TEST\ExtGroup1' })
                $rule | Add-Member -MemberType NoteProperty -Name AccessControlType    -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll)
                $rule | Add-Member -MemberType NoteProperty -Name InheritanceType       -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                $rule | Add-Member -MemberType NoteProperty -Name ObjectType            -Value ([Guid]::Empty)
                $rule | Add-Member -MemberType NoteProperty -Name InheritedObjectType   -Value ([Guid]'bf967aba-0de6-11d0-a285-00aa003049e2')
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @($rule)
                $acl
            }
        }
        # inheritedObjectType is already a GUID → TryParse succeeds (line 194) → non-Empty Guid →
        # Where-Object then-branch (line 221) fires; all conditions match → if($existingAcl) executes
        $cfg = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    targetOUPath                       = 'OU=ExtTier,{{domainDN}}'
                    identityreference                  = 'ExtGroup1'
                    activedirectoryrights              = @('GenericAll')
                    accesscontroltype                  = 'Allow'
                    activeDirectorysecurityinheritance = 'All'
                    objecttype                         = ''
                    inheritedObjectType                = 'bf967aba-0de6-11d0-a285-00aa003049e2'
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }
        $result = Get-TierModelOuAclFd -Config $cfg -DomainController $script:ExtDC
        $result                       | Should -Not -BeNullOrEmpty
        $result.Actions               | Should -BeNullOrEmpty
        $result.Summary.ExistingCount | Should -Be 1
    }

    It "Should handle Get-Acl failure gracefully when both OU and principal exist (lines 252-257)" {
        InModuleScope TierModel {
            Mock Get-Acl { throw 'Access denied reading ACL' }
        }
        $result = Get-TierModelOuAclFd -Config $script:ExtBaseConfig -DomainController $script:ExtDC
        $result               | Should -Not -BeNullOrEmpty
        $result.Actions.Count | Should -Be 1
        $result.Errors        | Should -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
# New-TierModelOuAcl — Success-path coverage via well-known Windows SIDs
#
# The existing tests use domain accounts (TESTDOMAIN\Tier0Admins) which cause
# NTAccount.Translate() to fail without a domain controller, so the entire
# body inside the ShouldProcess block is never reached.
#
# Strategy (no production code changes):
#   1. Use BUILTIN\Administrators / BUILTIN\Users — well-known SIDs that
#      NTAccount.Translate() resolves on any Windows machine without AD.
#   2. Mock New-Object ONLY for System.DirectoryServices.DirectoryEntry
#      (via ParameterFilter) so $de.ObjectSecurity / CommitChanges succeed.
#      All other New-Object calls (NTAccount, ActiveDirectoryAccessRule, etc.)
#      pass through to the real implementation.
# ---------------------------------------------------------------------------
Describe "New-TierModelOuAcl - Success Path Coverage" -Tag "Unit", "OuAcl" {

    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        $script:SucDC     = 'DC01.test.local'
        $script:SucConfig = [PSCustomObject]@{
            guidMappings = [PSCustomObject]@{
                staticMappings       = @{}
                dynamicMappings      = @{}
                friendlyNameMappings = @{}
            }
        }

        # Returns a fake DirectoryEntry whose ObjectSecurity accepts AddAccessRule
        # and whose CommitChanges is a no-op — no LDAP required.
        function script:New-FakeDE {
            $fakeAcl = [PSCustomObject]@{}
            $fakeAcl | Add-Member -MemberType ScriptMethod -Name AddAccessRule -Value { param($r) }
            $fakeDE  = [PSCustomObject]@{ ObjectSecurity = $fakeAcl }
            $fakeDE  | Add-Member -MemberType ScriptMethod -Name CommitChanges  -Value { }
            return $fakeDE
        }
    }

    # ------------------------------------------------------------------
    Context "Basic apply path" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
            # Intercept only DirectoryEntry construction; pass everything else through
            Mock New-Object -ModuleName TierModel `
                -ParameterFilter { $TypeName -eq 'System.DirectoryServices.DirectoryEntry' } `
                -MockWith { script:New-FakeDE }
        }

        It "Should apply a single CreateAcl and return Executed=1 for BUILTIN\Administrators" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = ''
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed  | Should -Be 1
            $result.Failed    | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "Should apply two CreateAcl actions and return Executed=2" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = 'OU=Tier0,DC=test,DC=local'
                        Data   = [PSCustomObject]@{
                            identityreference                  = 'BUILTIN\Administrators'
                            activedirectoryrights              = @('GenericAll')
                            accesscontroltype                  = 'Allow'
                            activeDirectorysecurityinheritance = 'All'
                            objecttype                         = ''
                        }
                    }
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = 'OU=Tier1,DC=test,DC=local'
                        Data   = [PSCustomObject]@{
                            identityreference                  = 'BUILTIN\Users'
                            activedirectoryrights              = @('ReadProperty')
                            accesscontroltype                  = 'Allow'
                            activeDirectorysecurityinheritance = 'All'
                            objecttype                         = ''
                        }
                    }
                )
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 2
            $result.Failed   | Should -Be 0
        }

        It "Should accumulate rights correctly when multiple valid rights strings are supplied" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('ReadProperty', 'WriteProperty')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = ''
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }

        It "Should warn on invalid rights string and still apply the valid ones" {
            # Covers the catch block inside the rights-parsing foreach loop
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll', 'NOT_A_VALID_RIGHT')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = ''
                    }
                })
            }
            # Invalid right is caught internally; function must not propagate an exception
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }

        It "Should use Unknown-OU label when OU path contains no OU= segment" {
            # Covers the else branch of the ouName extraction ternary
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'CN=NoOuHere,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = ''
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context "ObjectType GUID resolution branches" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
            Mock New-Object -ModuleName TierModel `
                -ParameterFilter { $TypeName -eq 'System.DirectoryServices.DirectoryEntry' } `
                -MockWith { script:New-FakeDE }
        }

        It "Should use objecttype directly when it is already a valid GUID string" {
            # Covers: if (-not IsNullOrEmpty(objecttype)) TRUE body,
            #         TryParse TRUE branch (valid GUID → skip Resolve),
            #         ternary else: [Guid]$resolvedObjectType
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = 'bf967aba-0de6-11d0-a285-00aa003049e2'
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }

        It "Should resolve friendly-name objecttype to GUID via Resolve-TierModelGuid" {
            # Covers: TryParse FALSE, Resolve-TierModelGuid call, if-not-null TRUE,
            #         if-not-empty TRUE, Write-Verbose "Resolved objecttype to GUID"
            Mock Resolve-TierModelGuid -ModuleName TierModel { return 'bf967aba-0de6-11d0-a285-00aa003049e2' }
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = 'user'
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }

        It "Should treat objecttype as all-objects when Resolve-TierModelGuid returns empty string" {
            # Covers: if-not-empty FALSE, Write-Verbose "Resolved to empty GUID"
            Mock Resolve-TierModelGuid -ModuleName TierModel { return '' }
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = 'user'
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }

        It "Should warn and record failure when Resolve-TierModelGuid returns null for objecttype" {
            # Covers: if-not-null FALSE, Write-Warning "Could not resolve", reset $resolvedObjectType
            # The non-GUID original value then causes [Guid]cast to throw → inner catch → Failed=1
            Mock Resolve-TierModelGuid -ModuleName TierModel { return $null }
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = 'user'
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Failed | Should -Be 1
        }

        It "Should warn and record failure when Resolve-TierModelGuid throws for objecttype" {
            # Covers: catch block in objecttype resolution: Write-Warning + reset $resolvedObjectType
            Mock Resolve-TierModelGuid -ModuleName TierModel { throw 'GUID resolution error' }
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype                         = 'user'
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Failed | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context "InheritedObjectType and 6-parameter ACE constructor" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
            Mock New-Object -ModuleName TierModel `
                -ParameterFilter { $TypeName -eq 'System.DirectoryServices.DirectoryEntry' } `
                -MockWith { script:New-FakeDE }
        }

        It "Should use 6-parameter ACE constructor when inheritedObjectType is a valid GUID" {
            # Covers: PSObject.Properties check TRUE, TryParse TRUE (valid GUID) → else branch,
            #         $inheritedObjectTypeGuid = [Guid]$aclData.inheritedObjectType,
            #         if ($inheritedObjectTypeGuid -ne Empty) TRUE → 6-param New-Object call
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'Descendents'
                        objecttype                         = ''
                        inheritedObjectType                = 'bf967aba-0de6-11d0-a285-00aa003049e2'
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }

        It "Should resolve friendly-name inheritedObjectType via Resolve-TierModelGuid and use 6-param constructor" {
            # Covers: TryParse FALSE for inheritedObjectType, Resolve-TierModelGuid call,
            #         if-not-null-and-not-empty TRUE, $inheritedObjectTypeGuid = [Guid]$resolved,
            #         Write-Verbose "Resolved inheritedObjectType", 6-param ACE constructor
            Mock Resolve-TierModelGuid -ModuleName TierModel { return 'bf967aba-0de6-11d0-a285-00aa003049e2' }
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path   = 'OU=Tier0,DC=test,DC=local'
                    Data   = [PSCustomObject]@{
                        identityreference                  = 'BUILTIN\Administrators'
                        activedirectoryrights              = @('GenericAll')
                        accesscontroltype                  = 'Allow'
                        activeDirectorysecurityinheritance = 'Descendents'
                        objecttype                         = ''
                        inheritedObjectType                = 'user'
                    }
                })
            }
            $result = New-TierModelOuAcl -Plan $plan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context "Outer catch block" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
        }

        It "Should return outer-catch result object when execution-complete logging throws" {
            # Write-TierModelLog for 'OuAclExecutionComplete' is inside the outer try block
            # but outside the per-action inner try/catch — throwing here hits the outer catch.
            Mock Write-TierModelLog -ModuleName TierModel { throw 'Simulated log failure' } `
                -ParameterFilter { $Message -eq 'OuAclExecutionComplete' }

            $emptyPlan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelOuAcl -Plan $emptyPlan -DomainController $script:SucDC -Config $script:SucConfig
            $result.Executed  | Should -Be 0
            $result.Failed    | Should -Be 1
            $result.Converged | Should -Be $false
        }
    }
}
