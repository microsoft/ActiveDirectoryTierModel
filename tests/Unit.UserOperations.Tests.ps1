<#
.SYNOPSIS
Unit tests for TierModel User operation functions.

.DESCRIPTION
Tests all User operation functions using Pester 5.x:
- Get-TierModelUser.ps1 - Plan generation
- Get-TierModelUserFd.ps1 - Full deployment planning (lightweight validation)
- New-TierModelUser.ps1 - User creation
- Test-TierModelUser.ps1 - Audit & compliance validation

All tests use mocks to avoid requiring Active Directory connectivity.
#>

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'TierModel.psd1'
    Import-Module $ModulePath -Force
    
    # Setup mock configuration with users
    $script:MockConfig = [PSCustomObject]@{
        users = @(
            [PSCustomObject]@{
                displayName = "Test Admin User"
                samAccountName = "tadmin"
                ouPath = "OU=Admins,{{domainDN}}"
                description = "Test administrator account"
                enabled = $true
                memberOf = @("Domain Admins", "Tier0-Administrators")
            }
            [PSCustomObject]@{
                displayName = "Test Standard User"
                samAccountName = "tuser"
                ouPath = "OU=Users,{{domainDN}}"
                enabled = $true
            }
            [PSCustomObject]@{
                displayName = "Test Disabled User"
                samAccountName = "tdisabled"
                ouPath = "OU=Disabled,{{domainDN}}"
                description = "Disabled test account"
                enabled = $false
            }
        )
    }
    
    $script:MockDomainController = "DC01.contoso.com"
    $script:MockDomainDN = "DC=contoso,DC=com"
    
    # Mock common AD cmdlets
    Mock -ModuleName TierModel Get-ADOrganizationalUnit {
        return [PSCustomObject]@{
            DistinguishedName = $Identity
            Name = ($Identity -split ',')[0] -replace 'OU=', ''
        }
    }
    
    Mock -ModuleName TierModel Get-ADGroup {
        param($Identity)
        
        # Return group object for known groups
        $knownGroups = @{
            "Domain Admins" = [PSCustomObject]@{
                Name = "Domain Admins"
                SamAccountName = "Domain Admins"
                DistinguishedName = "CN=Domain Admins,CN=Users,$script:MockDomainDN"
            }
            "Tier0-Administrators" = [PSCustomObject]@{
                Name = "Tier0-Administrators"
                SamAccountName = "Tier0-Administrators"
                DistinguishedName = "CN=Tier0-Administrators,OU=Groups,$script:MockDomainDN"
            }
        }
        
        if ($knownGroups.ContainsKey($Identity.ToString())) {
            return $knownGroups[$Identity.ToString()]
        } else {
            throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find an object with identity: '$Identity'")
        }
    }
    
    Mock -ModuleName TierModel Add-ADGroupMember { }
    
    Mock -ModuleName TierModel New-ADUser { 
        # Return nothing (cmdlet doesn't return output by default)
    }
    
    Mock -ModuleName TierModel Write-TierModelLog { }
    Mock -ModuleName TierModel Resolve-TierModelDomainDN { return $script:MockDomainDN }
    Mock -ModuleName TierModel Resolve-TierModelPlaceholder {
        param($Path, $DomainDN)
        return $Path -replace '\{\{domainDN\}\}', $DomainDN
    }
}

Describe "Get-TierModelUser" -Tag "Unit", "User", "Planning" {
    
    Context "Plan Generation - New Users" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find an object with identity: '$Identity'")
            }
        }
        
        It "Should generate deployment plan for users that don't exist" {
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result | Should -Not -BeNullOrEmpty
            $result.Actions | Should -HaveCount 5  # 3 CreateUser + 2 UpdateUserMembership
            $result.Summary.ToCreate | Should -Be 3
        }
        
        It "Should create CreateUser actions for missing users" {
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $createActions = @($result.Actions | Where-Object { $_.Action -eq 'CreateUser' })
            $createActions | Should -HaveCount 3
            $createActions[0].ResourceType | Should -Be 'User'
            $createActions[0].Name | Should -Be "Test Admin User"
            $createActions[0].Path | Should -Be "OU=Admins,$script:MockDomainDN"
        }
        
        It "Should create UpdateUserMembership actions for group assignments" {
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $membershipActions = @($result.Actions | Where-Object { $_.Action -eq 'UpdateUserMembership' })
            $membershipActions | Should -HaveCount 2
            $membershipActions[0].Data.UserSamAccountName | Should -Be "tadmin"
            $membershipActions[0].Data.GroupName | Should -Match "Domain Admins|Tier0-Administrators"
        }
        
        It "Should resolve placeholder paths correctly" {
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $adminAction = $result.Actions | Where-Object { $_.Name -eq "Test Admin User" }
            $adminAction.Path | Should -Be "OU=Admins,$script:MockDomainDN"
        }
        
        It "Should include user data in plan actions" {
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $adminAction = $result.Actions | Where-Object { $_.Name -eq "Test Admin User" }
            $adminAction.Data.samAccountName | Should -Be "tadmin"
            $adminAction.Data.description | Should -Be "Test administrator account"
            $adminAction.Data.enabled | Should -Be $true
        }
    }
    
    Context "Plan Generation - Existing Users" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                return [PSCustomObject]@{
                    SamAccountName = $Identity
                    DistinguishedName = "CN=$Identity,OU=Users,$script:MockDomainDN"
                    Enabled = $true
                }
            }
        }
        
        It "Should skip existing users from plan" {
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Actions | Should -HaveCount 0
            $result.Summary.ExistingCount | Should -Be 3
        }
        
        It "Should correctly count existing users in summary" {
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Summary.TotalInConfig | Should -Be 3
            $result.Summary.ToCreate | Should -Be 0
            $result.Summary.ExistingCount | Should -Be 3
        }
    }
    
    Context "Validation - OU and Group Dependencies" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find an object with identity: '$Identity'")
            }
        }
        
        It "Should add error when target OU doesn't exist" {
            Mock -ModuleName TierModel Get-ADOrganizationalUnit {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find OU")
            }
            
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code | Should -Be 'TargetOUNotFound'
            $result.Actions | Should -HaveCount 0  # No actions when OU missing
        }
        
        It "Should add error when required group doesn't exist" {
            Mock -ModuleName TierModel Get-ADGroup {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find group")
            }
            
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Errors | Should -Not -BeNullOrEmpty
            $groupErrors = @($result.Errors | Where-Object { $_.Code -eq 'RequiredGroupNotFound' })
            $groupErrors.Count | Should -BeGreaterOrEqual 1
        }
        
        It "Should skip users when dependencies missing" {
            Mock -ModuleName TierModel Get-ADOrganizationalUnit {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find OU")
            }
            
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            # Should have errors but no actions (users skipped)
            $result.Errors.Count | Should -BeGreaterOrEqual 1
            $result.Actions | Should -HaveCount 0
        }
    }
    
    Context "Error Handling" {
        
        It "Should handle missing users section in config" {
            $emptyConfig = [PSCustomObject]@{}
            
            $result = Get-TierModelUser -Config $emptyConfig -DomainController $script:MockDomainController -Silent
            
            $result.Summary.TotalInConfig | Should -Be 0
            $result.Warnings | Should -Contain "No users section found in configuration"
        }
        
        It "Should return error result when planning fails critically" {
            Mock -ModuleName TierModel Resolve-TierModelDomainDN {
                throw "Mock critical failure"
            }
            
            $result = Get-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code | Should -Be 'UserPlanningFailed'
        }
    }
}

Describe "Get-TierModelUserFd" -Tag "Unit", "User", "FullDeployment" {
    
    Context "Full Deployment Planning - Lightweight Validation" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find an object with identity: '$Identity'")
            }
        }
        
        It "Should generate plan without validating OUs" {
            # Mock OU check to fail, but Fd variant should not call it
            Mock -ModuleName TierModel Get-ADOrganizationalUnit {
                throw "OU validation should be skipped in Fd variant"
            }
            
            $result = Get-TierModelUserFd -Config $script:MockConfig -DomainController $script:MockDomainController
            
            # Should succeed even though OU mock would fail
            $result.Actions | Should -Not -BeNullOrEmpty
            $result.Summary.ToCreate | Should -Be 3
        }
        
        It "Should generate plan without validating Groups" {
            # Mock group check to fail, but Fd variant should not call it during planning
            Mock -ModuleName TierModel Get-ADGroup {
                throw "Group validation should be skipped in Fd variant"
            }
            
            $result = Get-TierModelUserFd -Config $script:MockConfig -DomainController $script:MockDomainController
            
            # Should succeed even though Group mock would fail
            $result.Actions | Should -Not -BeNullOrEmpty
            $result.Summary.ToCreate | Should -Be 3
        }
        
        It "Should create same plan actions as Get-TierModelUser (when deps exist)" {
            $result = Get-TierModelUserFd -Config $script:MockConfig -DomainController $script:MockDomainController
            
            $result.Actions | Should -HaveCount 5  # 3 CreateUser + 2 UpdateUserMembership
            $createActions = @($result.Actions | Where-Object { $_.Action -eq 'CreateUser' })
            $createActions | Should -HaveCount 3
        }
        
        It "Should only check if users exist (not dependencies)" {
            $null = Get-TierModelUserFd -Config $script:MockConfig -DomainController $script:MockDomainController
            
            # Should call Get-ADUser for existence check
            Should -Invoke -ModuleName TierModel Get-ADUser -Times 3
            # Should NOT call Get-ADOrganizationalUnit or Get-ADGroup for validation
            Should -Invoke -ModuleName TierModel Get-ADOrganizationalUnit -Times 0
            Should -Invoke -ModuleName TierModel Get-ADGroup -Times 0
        }
    }
    
    Context "Existing Users Handling" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                return [PSCustomObject]@{
                    SamAccountName = $Identity
                    DistinguishedName = "CN=$Identity,OU=Users,$script:MockDomainDN"
                }
            }
        }
        
        It "Should skip existing users from plan" {
            $result = Get-TierModelUserFd -Config $script:MockConfig -DomainController $script:MockDomainController
            
            $result.Actions | Should -HaveCount 0
            $result.Summary.ExistingCount | Should -Be 3
        }
    }
    
    Context "Error Handling" {
        
        It "Should handle missing users section in config" {
            $emptyConfig = [PSCustomObject]@{}
            
            $result = Get-TierModelUserFd -Config $emptyConfig -DomainController $script:MockDomainController
            
            $result.Summary.TotalInConfig | Should -Be 0
            $result.Warnings | Should -Contain "No users section found in configuration"
        }
        
        It "Should return error result when planning fails critically" {
            Mock -ModuleName TierModel Resolve-TierModelDomainDN {
                throw "Mock critical failure"
            }
            
            $result = Get-TierModelUserFd -Config $script:MockConfig -DomainController $script:MockDomainController
            
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code | Should -Be 'UserFdPlanningFailed'
        }
    }
}

Describe "New-TierModelUser" -Tag "Unit", "User", "Execution" {
    
    BeforeEach {
        # Reset mock configurations
        Mock -ModuleName TierModel Get-ADUser {
            throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find user")
        }
        
        Mock -ModuleName TierModel New-ADUser { }
        Mock -ModuleName TierModel Add-ADGroupMember { }
        
        # Create a sample plan
        $script:SamplePlan = [PSCustomObject]@{
            Actions = @(
                [PSCustomObject]@{
                    Action = 'CreateUser'
                    ResourceType = 'User'
                    Name = "Test Admin User"
                    Path = "OU=Admins,$script:MockDomainDN"
                    Data = [PSCustomObject]@{
                        displayName = "Test Admin User"
                        samAccountName = "tadmin"
                        description = "Test administrator"
                        enabled = $true
                        memberOf = @("Domain Admins", "Tier0-Administrators")
                    }
                }
            )
        }
    }
    
    Context "User Creation" {
        
        It "Should create users from plan" {
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            Should -Invoke -ModuleName TierModel New-ADUser -Times 1
            $result.Executed | Should -Be 1
            $result.Failed | Should -Be 0
        }
        
        It "Should pass correct parameters to New-ADUser" {
            $global:capturedParams = $null
            Mock -ModuleName TierModel New-ADUser {
                param(
                    $Name,
                    $DisplayName,
                    $SamAccountName,
                    $Path,
                    $Enabled,
                    $Server,
                    $Confirm,
                    $Description,
                    [SecureString]$AccountPassword,
                    [bool]$ChangePasswordAtLogon
                )
                $global:capturedParams = $PSBoundParameters
            }
            
            $null = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $global:capturedParams.Name | Should -Be "Test Admin User"
            $global:capturedParams.DisplayName | Should -Be "Test Admin User"
            $global:capturedParams.SamAccountName | Should -Be "tadmin"
            $global:capturedParams.Path | Should -Be "OU=Admins,$script:MockDomainDN"
            $global:capturedParams.Enabled | Should -Be $true
            $global:capturedParams.Description | Should -Be "Test administrator"
            $global:capturedParams.Server | Should -Be $script:MockDomainController
        }
        
        It "Should generate secure password for new users" {
            $global:capturedParams = $null
            Mock -ModuleName TierModel New-ADUser {
                param(
                    $Name,
                    $DisplayName,
                    $SamAccountName,
                    $Path,
                    $Enabled,
                    $Server,
                    $Confirm,
                    $Description,
                    [SecureString]$AccountPassword,
                    [bool]$ChangePasswordAtLogon
                )
                $global:capturedParams = $PSBoundParameters
            }
            
            $null = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $global:capturedParams.AccountPassword | Should -Not -BeNullOrEmpty
            $global:capturedParams.AccountPassword | Should -BeOfType [System.Security.SecureString]
            $global:capturedParams.ChangePasswordAtLogon | Should -Be $true
        }
        
        It "Should add users to groups when memberOf is specified" {
            $null = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            Should -Invoke -ModuleName TierModel Add-ADGroupMember -Times 2
        }
        
        It "Should pass correct parameters to Add-ADGroupMember" {
            $script:capturedCalls = @()
            Mock -ModuleName TierModel Add-ADGroupMember {
                param($Identity, $Members, $Server, $Confirm)
                $script:capturedCalls += @{
                    Identity = $Identity
                    Members = $Members
                }
            }
            
            $null = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $script:capturedCalls | Should -HaveCount 2
            $script:capturedCalls[0].Members | Should -Be "tadmin"
            $script:capturedCalls[0].Identity | Should -Match "Domain Admins|Tier0-Administrators"
        }
        
        It "Should handle users without description property" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateUser'
                        ResourceType = 'User'
                        Name = "Simple User"
                        Path = "OU=Users,$script:MockDomainDN"
                        Data = [PSCustomObject]@{
                            displayName = "Simple User"
                            samAccountName = "suser"
                            enabled = $true
                        }
                    }
                )
            }
            
            $global:capturedParams = $null
            Mock -ModuleName TierModel New-ADUser {
                $global:capturedParams = $PSBoundParameters  # PSScriptAnalyzer incorrectly flags this in mock context
            }
            
            $null = New-TierModelUser -Plan $plan -DomainController $script:MockDomainController -Confirm:$false
            
            $global:capturedParams.Keys | Should -Not -Contain 'Description'
        }
        
        It "Should handle users without memberOf property" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateUser'
                        ResourceType = 'User'
                        Name = "Simple User"
                        Path = "OU=Users,$script:MockDomainDN"
                        Data = [PSCustomObject]@{
                            displayName = "Simple User"
                            samAccountName = "suser"
                            enabled = $true
                        }
                    }
                )
            }
            
            $result = New-TierModelUser -Plan $plan -DomainController $script:MockDomainController -Confirm:$false
            
            Should -Invoke -ModuleName TierModel Add-ADGroupMember -Times 0
            $result.Executed | Should -Be 1
        }
        
        It "Should respect enabled property from config" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateUser'
                        ResourceType = 'User'
                        Name = "Disabled User"
                        Path = "OU=Disabled,$script:MockDomainDN"
                        Data = [PSCustomObject]@{
                            displayName = "Disabled User"
                            samAccountName = "duser"
                            enabled = $false
                        }
                    }
                )
            }
            
            $global:capturedParams = $null
            Mock -ModuleName TierModel New-ADUser {
                param(
                    $Name,
                    $DisplayName,
                    $SamAccountName,
                    $Path,
                    $Enabled,
                    $Server,
                    $Confirm,
                    $Description,
                    [SecureString]$AccountPassword,
                    [bool]$ChangePasswordAtLogon
                )
                $global:capturedParams = $PSBoundParameters
            }
            
            $null = New-TierModelUser -Plan $plan -DomainController $script:MockDomainController -Confirm:$false
            
            $global:capturedParams.Enabled | Should -Be $false
        }
    }
    
    Context "WhatIf Support" {
        
        It "Should not create users in WhatIf mode" {
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -WhatIf
            
            Should -Invoke -ModuleName TierModel New-ADUser -Times 0
            $result.Skipped | Should -Be 1
            $result.Executed | Should -Be 0
        }
        
        It "Should not add group memberships in WhatIf mode" {
            $null = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -WhatIf
            
            Should -Invoke -ModuleName TierModel Add-ADGroupMember -Times 0
        }
    }
    
    Context "Error Handling" {
        
        It "Should handle user creation failures" {
            Mock -ModuleName TierModel New-ADUser {
                throw "Mock user creation failure"
            }
            
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $result.Failed | Should -Be 1
            $result.Executed | Should -Be 0
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Converged | Should -Be $false
        }
        
        It "Should continue processing after group membership failure" {
            Mock -ModuleName TierModel Add-ADGroupMember {
                throw "Mock group membership failure"
            }
            
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            # User creation should still succeed
            $result.Executed | Should -Be 1
            Should -Invoke -ModuleName TierModel New-ADUser -Times 1
        }
        
        It "Should handle critical execution failures" {
            # Mock Write-TierModelLog to throw only when called from inside execution loop
            Mock -ModuleName TierModel Write-TierModelLog {
                param($Level, $Message, $Data)
                if ($Message -eq "Creating user account") {
                    throw "Mock critical failure during execution"
                }
            }
            
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $result.Failed | Should -Be 1
            $result.Converged | Should -Be $false
            $result.Errors[0].Code | Should -Be 'UserCreationFailed'
        }
    }
    
    Context "Execution Metrics" {
        
        It "Should track execution duration" {
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $result.DurationMs | Should -BeGreaterThan 0
        }
        
        It "Should set converged to true when all succeed" {
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $result.Converged | Should -Be $true
        }
        
        It "Should include correlation ID in result" {
            $result = New-TierModelUser -Plan $script:SamplePlan -DomainController $script:MockDomainController -Confirm:$false
            
            $result.CorrelationId | Should -Not -BeNullOrEmpty
            $result.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }
}

Describe "Test-TierModelUser" -Tag "Unit", "User", "Audit" {
    
    BeforeEach {
        # Reset to default mock - users don't exist
        Mock -ModuleName TierModel Get-ADUser {
            throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Cannot find user")
        }
    }
    
    Context "Missing User Detection" {
        
        It "Should detect missing users" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.DriftFindings | Should -HaveCount 3
            $result.Summary.MissingCount | Should -Be 3
            $result.Summary.MismatchCount | Should -Be 0
        }
        
        It "Should create drift findings for missing users" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $missingFindings = @($result.DriftFindings | Where-Object { $_.Type -eq 'Missing' })
            $missingFindings | Should -HaveCount 3
            $missingFindings[0].ResourceType | Should -Be 'User'
            $missingFindings[0].ExpectedValue | Should -Be 'Present'
            $missingFindings[0].ActualValue | Should -Be 'Missing'
        }
    }
    
    Context "User Location Validation" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                param($Identity, $Properties)
                
                # User exists but in wrong OU
                return [PSCustomObject]@{
                    SamAccountName = $Identity.ToString()
                    DistinguishedName = "CN=$($Identity.ToString()),OU=WrongOU,$script:MockDomainDN"
                    Enabled = $true
                    MemberOf = @()
                }
            }
        }
        
        It "Should detect users in wrong OU" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.DriftFindings | Should -Not -BeNullOrEmpty
            $locationFindings = @($result.DriftFindings | Where-Object { $_.Identifier -like "*/Location" })
            $locationFindings | Should -HaveCount 3
        }
        
        It "Should report correct location mismatches" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $locationFinding = $result.DriftFindings | Where-Object { $_.Identifier -eq "Test Admin User/Location" }
            $locationFinding.ExpectedValue | Should -Be "OU=Admins,$script:MockDomainDN"
            $locationFinding.ActualValue | Should -Be "OU=WrongOU,$script:MockDomainDN"
        }
    }
    
    Context "Group Membership Validation" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                param($Identity, $Properties)
                
                # User exists in correct OU but missing group memberships
                if ($Identity.ToString() -eq 'tadmin') {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity.ToString()
                        DistinguishedName = "CN=$($Identity.ToString()),OU=Admins,$script:MockDomainDN"
                        Enabled = $true
                        MemberOf = @()  # Should have Domain Admins and Tier0-Administrators
                    }
                } else {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity.ToString()
                        DistinguishedName = "CN=$($Identity.ToString()),OU=Users,$script:MockDomainDN"
                        Enabled = $true
                        MemberOf = @()
                    }
                }
            }
        }
        
        It "Should detect missing group memberships" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $membershipFindings = @($result.DriftFindings | Where-Object { $_.Identifier -like "*/GroupMembership" })
            $membershipFindings | Should -HaveCount 1  # Only tadmin has memberOf requirements
        }
        
        It "Should report which groups are missing" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $membershipFinding = $result.DriftFindings | Where-Object { $_.Identifier -eq "Test Admin User/GroupMembership" }
            $membershipFinding.Details | Should -Match "Domain Admins"
            $membershipFinding.Details | Should -Match "Tier0-Administrators"
        }
    }
    
    Context "Compliant Users" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                param($Identity, $Properties)
                
                # All users exist in correct locations with correct properties
                if ($Identity.ToString() -eq 'tadmin') {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity.ToString()
                        DistinguishedName = "CN=$($Identity.ToString()),OU=Admins,$script:MockDomainDN"
                        Enabled = $true
                        MemberOf = @(
                            "CN=Domain Admins,CN=Users,$script:MockDomainDN"
                            "CN=Tier0-Administrators,OU=Groups,$script:MockDomainDN"
                        )
                    }
                } elseif ($Identity.ToString() -eq 'tuser') {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity.ToString()
                        DistinguishedName = "CN=$($Identity.ToString()),OU=Users,$script:MockDomainDN"
                        Enabled = $true
                        MemberOf = @()
                    }
                } else {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity.ToString()
                        DistinguishedName = "CN=$($Identity.ToString()),OU=Disabled,$script:MockDomainDN"
                        Enabled = $false
                        MemberOf = @()
                    }
                }
            }
        }
        
        It "Should report no drift when all users are compliant" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Summary.DriftCount | Should -Be 0
            $result.DriftFindings | Should -HaveCount 0
        }
        
        It "Should count all checked users in summary" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Summary.TotalChecked | Should -Be 3
        }
    }
    
    Context "Resolved Paths Option" {
        
        BeforeEach {
            Mock -ModuleName TierModel Get-ADUser {
                param($Identity)
                return [PSCustomObject]@{
                    SamAccountName = $Identity
                    DistinguishedName = "CN=$Identity,OU=Users,$script:MockDomainDN"
                    Enabled = $true
                    MemberOf = @()
                }
            }
        }
        
        It "Should include resolved paths when IncludeResolvedPaths is specified" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent -IncludeResolvedPaths
            
            $result.PSObject.Properties.Name | Should -Contain 'ResolvedPaths'
            $result.ResolvedPaths | Should -Not -BeNullOrEmpty
            $result.ResolvedPaths | Should -HaveCount 3
        }
        
        It "Should not include resolved paths by default" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.PSObject.Properties.Name | Should -Not -Contain 'ResolvedPaths'
        }
        
        It "Should include correct path information in ResolvedPaths" {
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent -IncludeResolvedPaths
            
            $adminPath = $result.ResolvedPaths | Where-Object { $_.SamAccountName -eq 'tadmin' }
            $adminPath.Name | Should -Be "Test Admin User"
            $adminPath.OriginalPath | Should -Be "OU=Admins,{{domainDN}}"
            $adminPath.ResolvedPath | Should -Be "OU=Admins,$script:MockDomainDN"
            $adminPath.ExpectedGroups | Should -Contain "Domain Admins"
        }
    }
    
    Context "Error Handling" {
        
        It "Should handle missing users section in config" {
            $emptyConfig = [PSCustomObject]@{}
            
            $result = Test-TierModelUser -Config $emptyConfig -DomainController $script:MockDomainController -Silent
            
            $result.Warnings | Should -Contain "No users section found in configuration"
            $result.Summary.TotalChecked | Should -Be 0
        }
        
        It "Should handle AD query failures gracefully" {
            Mock -ModuleName TierModel Get-ADUser {
                throw "Mock AD connection failure"
            }
            
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            # Should not throw, but should log errors
            $result | Should -Not -BeNullOrEmpty
            # May have errors for individual users that failed to query
        }
        
        It "Should return error result when audit fails critically" {
            Mock -ModuleName TierModel Resolve-TierModelDomainDN {
                throw "Mock critical failure"
            }
            
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0].Code | Should -Be 'UserAuditFailed'
            $result.Summary.TotalChecked | Should -Be 0
        }
    }
    
    Context "Summary Statistics" {
        
        It "Should calculate drift count as sum of missing and mismatch" {
            # Mock: 1 missing, 2 with location mismatches
            $script:callCount = 0
            Mock -ModuleName TierModel Get-ADUser {
                param($Identity)
                $script:callCount++
                if ($script:callCount -eq 1) {
                    throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("User not found")
                } else {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity
                        DistinguishedName = "CN=$Identity,OU=WrongOU,$script:MockDomainDN"
                        Enabled = $true
                        MemberOf = @()
                    }
                }
            }
            
            $result = Test-TierModelUser -Config $script:MockConfig -DomainController $script:MockDomainController -Silent
            
            $result.Summary.MissingCount | Should -Be 1
            $result.Summary.MismatchCount | Should -Be 2
            $result.Summary.DriftCount | Should -Be 3
        }
    }
}
