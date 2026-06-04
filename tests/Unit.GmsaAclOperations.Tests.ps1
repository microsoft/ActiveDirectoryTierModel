#Requires -Modules Pester
<#
.SYNOPSIS
Unit tests for gMSA ACL operation cmdlets (Get-TierModelGmsaAcl, New-TierModelGmsaAcl,
Test-TierModelGmsaAcl, Get-TierModelGmsaAclFd).

.NOTES
Created : 2025-07-18
Tags    : Unit, GmsaAcl
#>

Describe "gMSA ACL Operations" -Tag "Unit", "GmsaAcl" {
    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestDC = "DC01.test.local"
        $script:TestDomainDN = "DC=test,DC=local"

        $script:TestConfig = [PSCustomObject]@{
            organizationalUnits = @(
                @{ name = "Tier1ServiceAccounts"; path = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"; description = "Tier 1 Service Accounts" }
                @{ name = "Tier2ServiceAccounts"; path = "OU=Tier 2 Service Accounts,OU=Tier 2,OU=Tier Model Administration,{{domainDN}}"; description = "Tier 2 Service Accounts" }
            )
            groups = @(
                @{ name = "Tier1Admins"; samAccountName = "Tier1Admins"; path = "OU=Groups,{{domainDN}}"; scope = "DomainLocal"; type = "Security" }
                @{ name = "Tier2Admins"; samAccountName = "Tier2Admins"; path = "OU=Groups,{{domainDN}}"; scope = "DomainLocal"; type = "Security" }
            )
            gmsaAclDelegations = @(
                @{
                    targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                    identityreference = "Tier1Admins"
                    activedirectoryrights = @("CreateChild", "DeleteChild")
                    accesscontroltype = "Allow"
                    objecttype = "msDS-GroupManagedServiceAccount"
                    activeDirectorysecurityinheritance = "All"
                    comment = "Create/DeleteChild delegation"
                    resolveguid = $true
                }
                @{
                    targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                    identityreference = "Tier1Admins"
                    activedirectoryrights = @("GenericAll")
                    accesscontroltype = "Allow"
                    objecttype = "AllObjectClasses"
                    activeDirectorysecurityinheritance = "Descendents"
                    inheritedObjectType = "msDS-GroupManagedServiceAccount"
                    comment = "Descendents GenericAll delegation"
                    resolveguid = $true
                }
            )
            guidMappings = @{
                staticMappings = @{
                    objectClasses = @{
                        "msDS-GroupManagedServiceAccount" = "7b8b558a-93a5-4af7-adca-c017e67f1057"
                        User = "bf967aba-0de6-11d0-a285-00aa003049e2"
                        Computer = "bf967a86-0de6-11d0-a285-00aa003049e2"
                    }
                }
                dynamicMappings = @{}
                friendlyNameMappings = @{}
            }
        }

        $script:TestConfigEmpty = [PSCustomObject]@{
            organizationalUnits = @()
            groups = @()
            gmsaAclDelegations = @()
            guidMappings = @{
                staticMappings = @{}
                dynamicMappings = @{}
                friendlyNameMappings = @{}
            }
        }

        $script:TestConfigNoProperty = [PSCustomObject]@{
            organizationalUnits = @()
            groups = @()
            guidMappings = @{
                staticMappings = @{}
                dynamicMappings = @{}
                friendlyNameMappings = @{}
            }
        }

        $script:TestConfigBadOU = [PSCustomObject]@{
            gmsaAclDelegations = @(
                @{
                    targetOUPath = "OU=NonExistentOU_XYZ,{{domainDN}}"
                    identityreference = "Tier1Admins"
                    activedirectoryrights = @("CreateChild", "DeleteChild")
                    accesscontroltype = "Allow"
                    objecttype = "msDS-GroupManagedServiceAccount"
                    activeDirectorysecurityinheritance = "All"
                    resolveguid = $true
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }

        $script:TestConfigBadGroup = [PSCustomObject]@{
            gmsaAclDelegations = @(
                @{
                    targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                    identityreference = "NonExistentGroup_XYZ_12345"
                    activedirectoryrights = @("CreateChild", "DeleteChild")
                    accesscontroltype = "Allow"
                    objecttype = "msDS-GroupManagedServiceAccount"
                    activeDirectorysecurityinheritance = "All"
                    resolveguid = $true
                }
            )
            guidMappings = @{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }

        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            if ($Identity -match "Tier 1 Service Accounts" -or $Identity -match "Tier 2 Service Accounts") {
                return [PSCustomObject]@{
                    DistinguishedName = $Identity
                    Name = if ($Identity -match "Tier 1") { "Tier 1 Service Accounts" } else { "Tier 2 Service Accounts" }
                }
            } else {
                throw "OU not found: $Identity"
            }
        }

        Mock Get-ADGroup -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            if ($Identity -eq "Tier1Admins" -or $Identity -eq "Tier2Admins") {
                return [PSCustomObject]@{
                    SamAccountName = $Identity
                    DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN"
                }
            } else {
                throw "Group not found: $Identity"
            }
        }

        Mock Get-ADUser -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            throw "User not found"
        }

        Mock Get-Acl -ModuleName TierModel {
            param($Path, $ErrorAction)
            $acl = New-Object PSObject
            $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
            $acl | Add-Member -MemberType NoteProperty -Name Access -Value @()
            return $acl
        }

        Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:TestDomainDN }

        Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
            param($Path, $DomainDN)
            return $Path.Replace("{{domainDN}}", $DomainDN)
        }

        Mock Resolve-TierModelGuid -ModuleName TierModel {
            param([string]$Value, [object]$Mappings, [string]$DomainController)
            $map = @{
                "msDS-GroupManagedServiceAccount" = "7b8b558a-93a5-4af7-adca-c017e67f1057"
                "User" = "bf967aba-0de6-11d0-a285-00aa003049e2"
                "Computer" = "bf967a86-0de6-11d0-a285-00aa003049e2"
            }
            if ($map.ContainsKey($Value)) { return $map[$Value] }
            return $null
        }

        Mock Write-TierModelLog -ModuleName TierModel { }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 1: Get-TierModelGmsaAcl Planning
    # ─────────────────────────────────────────────────────────────
    Context "Get-TierModelGmsaAcl - Planning" -Tag "Unit", "GmsaAcl", "Planning" {
        BeforeEach {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                if ($Identity -match "Tier 1 Service Accounts" -or $Identity -match "Tier 2 Service Accounts") {
                    return [PSCustomObject]@{
                        DistinguishedName = $Identity
                        Name = if ($Identity -match "Tier 1") { "Tier 1 Service Accounts" } else { "Tier 2 Service Accounts" }
                    }
                } else {
                    throw "OU not found: $Identity"
                }
            }

            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                if ($Identity -eq "Tier1Admins" -or $Identity -eq "Tier2Admins") {
                    return [PSCustomObject]@{
                        SamAccountName = $Identity
                        DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN"
                    }
                } else {
                    throw "Group not found: $Identity"
                }
            }

            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw "User not found"
            }

            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @()
                return $acl
            }
        }

        It "Returns a plan object with expected structure for valid config" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Analysis'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Returns zero-action plan for empty gmsaAclDelegations" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfigEmpty -DomainController $script:TestDC
            $result.Summary.TotalActions  | Should -Be 0
            $result.Summary.CreateActions | Should -Be 0
            $result.Actions | Should -BeNullOrEmpty
        }

        It "Returns zero-action plan when gmsaAclDelegations property is absent" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfigNoProperty -DomainController $script:TestDC
            $result.Summary.TotalActions | Should -Be 0
            $result.Actions | Should -BeNullOrEmpty
        }


        It "Summary contains TotalActions, CreateActions, and RiskAssessment" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result.Summary.TotalActions  | Should -BeOfType [int]
            $result.Summary.CreateActions | Should -BeOfType [int]
            $result.Summary.RiskAssessment | Should -Not -BeNullOrEmpty
        }

        It "CorrelationId is a valid GUID" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }

        It "DurationMs is a positive number" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "Calls Resolve-TierModelPlaceholder for each delegation" {
            Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -Times ($script:TestConfig.gmsaAclDelegations.Count) -Exactly
        }

    }

    Context "Get-TierModelGmsaAcl - CreateAcl planning" -Tag "Unit", "GmsaAcl", "Planning" {
        BeforeEach {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ DistinguishedName = $Identity; Name = "Tier 1 Service Accounts" }
            }
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN" }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw "User not found"
            }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @()
                return $acl
            }
        }
        It "Produces CreateAcl actions when ACLs are absent" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result.Actions | Should -Not -BeNullOrEmpty
            $result.Actions[0].Action | Should -Be 'CreateAcl'
        }
    }

    Context "Get-TierModelGmsaAcl - Guid resolution" -Tag "Unit", "GmsaAcl", "Planning" {
        BeforeEach {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ DistinguishedName = $Identity; Name = "Tier 1 Service Accounts" }
            }
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN" }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw "User not found"
            }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @()
                return $acl
            }
        }
        It "Calls Resolve-TierModelGuid for object type resolution" {
            Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            Should -Invoke Resolve-TierModelGuid -ModuleName TierModel -Times 1
        }
    }

    Context "Get-TierModelGmsaAcl - TargetOUNotFound error" -Tag "Unit", "GmsaAcl", "Planning" {
        It "Returns TargetOUNotFound error when target OU does not exist" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfigBadOU -DomainController $script:TestDC
            $result.Errors | Should -Not -BeNullOrEmpty
            ($result.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-TierModelGmsaAcl - SecurityPrincipalNotFound error" -Tag "Unit", "GmsaAcl", "Planning" {
        It "Returns SecurityPrincipalNotFound error when delegation group does not exist" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfigBadGroup -DomainController $script:TestDC
            $result.Errors | Should -Not -BeNullOrEmpty
            ($result.Errors | Where-Object { $_.Code -eq 'SecurityPrincipalNotFound' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-TierModelGmsaAcl - Existing ACL detection" -Tag "Unit", "GmsaAcl", "Planning" {
        BeforeAll {
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $gmsaGuid = [Guid]"7b8b558a-93a5-4af7-adca-c017e67f1057"
                $rule = New-Object PSObject
                $rule | Add-Member -MemberType NoteProperty -Name IdentityReference -Value ([PSCustomObject]@{ Value = "TEST\Tier1Admins" })
                $rule | Add-Member -MemberType NoteProperty -Name AccessControlType  -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild)
                $rule | Add-Member -MemberType NoteProperty -Name InheritanceType -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                $rule | Add-Member -MemberType NoteProperty -Name ObjectType -Value $gmsaGuid
                $rule | Add-Member -MemberType NoteProperty -Name InheritedObjectType -Value ([Guid]::Empty)
                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @($rule)
                return $acl
            }
        }
        It "Skips ACL entry that already exists" {
            $singleEntryConfig = [PSCustomObject]@{
                gmsaAclDelegations = @(
                    @{
                        targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                        identityreference = "Tier1Admins"
                        activedirectoryrights = @("CreateChild", "DeleteChild")
                        accesscontroltype = "Allow"
                        objecttype = "msDS-GroupManagedServiceAccount"
                        activeDirectorysecurityinheritance = "All"
                        resolveguid = $true
                    }
                )
                guidMappings = $script:TestConfig.guidMappings
            }
            $result = Get-TierModelGmsaAcl -Config $singleEntryConfig -DomainController $script:TestDC
            $result.Summary.CreateActions | Should -BeLessThan 1
        }
    }

    Context "Get-TierModelGmsaAcl - AclReadFailed error" -Tag "Unit", "GmsaAcl", "Planning" {
        BeforeEach {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ DistinguishedName = $Identity; Name = "Tier 1 Service Accounts" }
            }
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN" }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw "User not found"
            }
            Mock Get-Acl -ModuleName TierModel { param($Path, $ErrorAction) throw "Access denied" }
        }
        It "Returns AclReadFailed error when Get-Acl throws" {
            $result = Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            ($result.Errors | Where-Object { $_.Code -eq 'AclReadFailed' }) | Should -Not -BeNullOrEmpty
        }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 2: Get-TierModelGmsaAclFd Full Deployment Planning
    # ─────────────────────────────────────────────────────────────
    Context "Get-TierModelGmsaAclFd - Full Deployment Planning" -Tag "Unit", "GmsaAcl", "FullDeployment" {

        It "Returns a plan object with expected structure for valid config" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Summary includes ExistingCount property" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result.Summary.Keys | Should -Contain 'ExistingCount'
        }

        It "Returns zero-action plan for empty gmsaAclDelegations" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfigEmpty -DomainController $script:TestDC
            $result.Summary.TotalActions  | Should -Be 0
            $result.Summary.ExistingCount | Should -Be 0
        }

        It "Returns zero-action plan when gmsaAclDelegations property is absent" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfigNoProperty -DomainController $script:TestDC
            $result.Summary.TotalActions | Should -Be 0
        }

        It "Does NOT fail-fast when OUs are missing — creates actions with TargetOUExists=false" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfigBadOU -DomainController $script:TestDC
            $createActions = @($result.Actions | Where-Object { $_.Action -eq 'CreateAcl' })
            $createActions.Count | Should -BeGreaterThan 0
            $createActions[0].Validation.TargetOUExists | Should -Be $false
        }

        It "Sets PrincipalResolvable validation metadata on actions" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            if ($result.Actions.Count -gt 0) {
                $result.Actions[0].Validation.Keys | Should -Contain 'PrincipalResolvable'
            }
        }

        It "-Silent parameter suppresses Write-Host output" {
            Mock Write-Host -ModuleName TierModel { }
            Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            Should -Invoke Write-Host -ModuleName TierModel -Times 0
        }

        It "CorrelationId is a valid GUID" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }

        It "DurationMs is a positive number" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "Returns GmsaAclFdAnalysisFailed error code on inner processing failure" {
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel { throw "Placeholder resolution failed" }

            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result.Errors | Should -Not -BeNullOrEmpty
            ($result.Errors | Where-Object { $_.Code -like '*FdAnalysisFailed*' }) | Should -Not -BeNullOrEmpty

            Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
                param($Path, $DomainDN)
                return $Path.Replace("{{domainDN}}", $DomainDN)
            }
        }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 3: New-TierModelGmsaAcl Execution
    # ─────────────────────────────────────────────────────────────
    Context "New-TierModelGmsaAcl - Execution" -Tag "Unit", "GmsaAcl", "Execution" {

        BeforeAll {
            Mock Write-Host -ModuleName TierModel { }

            $script:EmptyPlan = [PSCustomObject]@{ Actions = @() }

            $script:SingleAclPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local"
                        Data   = [PSCustomObject]@{
                            identityreference               = "TESTDOMAIN\Tier1Admins"
                            activedirectoryrights           = @("CreateChild", "DeleteChild")
                            accesscontroltype               = "Allow"
                            activeDirectorysecurityinheritance = "All"
                            objecttype                      = "7b8b558a-93a5-4af7-adca-c017e67f1057"
                        }
                    }
                )
            }
        }

        It "Empty plan returns Executed=0, Converged=true" {
            $result = New-TierModelGmsaAcl -Plan $script:EmptyPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Executed  | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "Non-CreateAcl action types are ignored" {
            $nonCreatePlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'SkipAcl'
                        Path   = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local"
                        Data   = [PSCustomObject]@{ identityreference = "TESTDOMAIN\Tier1Admins" }
                    }
                )
            }
            $result = New-TierModelGmsaAcl -Plan $nonCreatePlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Executed | Should -Be 0
        }

        It "-WhatIf single action produces Skipped=1, Executed=0" {
            $result = New-TierModelGmsaAcl -Plan $script:SingleAclPlan -DomainController $script:TestDC -Config $script:TestConfig -WhatIf
            $result.Executed      | Should -Be 0
            $result.Skipped.Count | Should -Be 1
        }

        It "NTAccount.Translate failure marks Converged=false and records AclApplicationFailed error" {
            $badPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path   = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local"
                        Data   = [PSCustomObject]@{
                            identityreference               = "INVALID_DOMAIN\NonExistentGroup_$(New-Guid)"
                            activedirectoryrights           = @("CreateChild", "DeleteChild")
                            accesscontroltype               = "Allow"
                            activeDirectorysecurityinheritance = "All"
                            objecttype                      = "7b8b558a-93a5-4af7-adca-c017e67f1057"
                        }
                    }
                )
            }
            $result = New-TierModelGmsaAcl -Plan $badPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Converged | Should -Be $false
            $result.Failed    | Should -BeGreaterThan 0
            ($result.Errors | Where-Object { $_.Code -eq 'AclApplicationFailed' }) | Should -Not -BeNullOrEmpty
        }

        It "Result object contains all required properties" {
            $result = New-TierModelGmsaAcl -Plan $script:EmptyPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.PSObject.Properties.Name | Should -Contain 'Executed'
            $result.PSObject.Properties.Name | Should -Contain 'Failed'
            $result.PSObject.Properties.Name | Should -Contain 'Skipped'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'Converged'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "CorrelationId is a valid GUID" {
            $result = New-TierModelGmsaAcl -Plan $script:EmptyPlan -DomainController $script:TestDC -Config $script:TestConfig
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 4: Test-TierModelGmsaAcl Audit
    # ─────────────────────────────────────────────────────────────
    Context "Test-TierModelGmsaAcl - Audit" -Tag "Unit", "GmsaAcl", "Audit" {

        It "Returns audit result object with required properties" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            $result.PSObject.Properties.Name | Should -Contain 'TotalChecked'
            $result.PSObject.Properties.Name | Should -Contain 'Compliant'
            $result.PSObject.Properties.Name | Should -Contain 'Missing'
            $result.PSObject.Properties.Name | Should -Contain 'Mismatched'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Drift'
            $result.PSObject.Properties.Name | Should -Contain 'Findings'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "TotalChecked equals the number of unique OU/identity delegation groups" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            $result.TotalChecked | Should -Be 1
        }


        It "Missing count increments when target OU does not exist" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfigBadOU -DomainController $script:TestDC -Silent
            $result.Missing | Should -BeGreaterThan 0
        }

        It "Missing count increments when security principal does not exist" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfigBadGroup -DomainController $script:TestDC -Silent
            $result.Missing | Should -BeGreaterThan 0
        }

        It "-Silent suppresses Write-Host output" {
            Mock Write-Host -ModuleName TierModel { }
            Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            Should -Invoke Write-Host -ModuleName TierModel -Times 0
        }

        It "-SuppressSummary suppresses summary output" {
            Mock Write-Host -ModuleName TierModel { }
            Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -SuppressSummary | Out-Null
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter {
                $Object -match 'gMSA ACL Audit Summary'
            } -Times 0
        }

        It "Config without gmsaAclDelegations returns TotalChecked=0" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfigNoProperty -DomainController $script:TestDC -Silent
            $result.TotalChecked | Should -Be 0
        }

        It "CorrelationId is a valid GUID" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }

        It "DurationMs is a positive number" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "Calls Resolve-TierModelPlaceholder during audit" {
            Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -Times 1
        }
    }

    Context "Test-TierModelGmsaAcl - Compliant ACEs" -Tag "Unit", "GmsaAcl", "Audit" {
        BeforeEach {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ DistinguishedName = $Identity; Name = "Tier 1 Service Accounts" }
            }
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN" }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw "User not found"
            }
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:TestDomainDN }
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
                param($Path, $DomainDN)
                return $Path.Replace("{{domainDN}}", $DomainDN)
            }
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, [object]$Mappings, [string]$DomainController)
                $map = @{
                    "msDS-GroupManagedServiceAccount" = "7b8b558a-93a5-4af7-adca-c017e67f1057"
                    "User" = "bf967aba-0de6-11d0-a285-00aa003049e2"
                    "Computer" = "bf967a86-0de6-11d0-a285-00aa003049e2"
                }
                if ($map.ContainsKey($Value)) { return $map[$Value] }
                return $null
            }
            Mock Write-TierModelLog -ModuleName TierModel { }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $gmsaGuid = [Guid]"7b8b558a-93a5-4af7-adca-c017e67f1057"

                $rule1 = New-Object PSObject
                $rule1 | Add-Member -MemberType NoteProperty -Name IdentityReference -Value ([PSCustomObject]@{ Value = "TEST\Tier1Admins" })
                $rule1 | Add-Member -MemberType NoteProperty -Name AccessControlType  -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule1 | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild)
                $rule1 | Add-Member -MemberType NoteProperty -Name InheritanceType -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                $rule1 | Add-Member -MemberType NoteProperty -Name ObjectType -Value $gmsaGuid
                $rule1 | Add-Member -MemberType NoteProperty -Name InheritedObjectType -Value ([Guid]::Empty)

                $rule2 = New-Object PSObject
                $rule2 | Add-Member -MemberType NoteProperty -Name IdentityReference -Value ([PSCustomObject]@{ Value = "TEST\Tier1Admins" })
                $rule2 | Add-Member -MemberType NoteProperty -Name AccessControlType  -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule2 | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll)
                $rule2 | Add-Member -MemberType NoteProperty -Name InheritanceType -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents)
                $rule2 | Add-Member -MemberType NoteProperty -Name ObjectType -Value ([Guid]::Empty)
                $rule2 | Add-Member -MemberType NoteProperty -Name InheritedObjectType -Value ([Guid]::Empty)

                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Path -Value $Path
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @($rule1, $rule2)
                return $acl
            }
        }
        It "Compliant count increments when both expected ACEs are present" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            $result.Compliant | Should -BeGreaterThan 0
        }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 5: Get-TierModelGmsaAcl vs Get-TierModelGmsaAclFd Comparison
    # ─────────────────────────────────────────────────────────────
    Context "Get-TierModelGmsaAcl vs Get-TierModelGmsaAclFd - Comparison" -Tag "Unit", "GmsaAcl" {

        It "Standalone planner fails-fast with validation errors when OUs missing; Fd planner does not" {
            $standalone = Get-TierModelGmsaAcl   -Config $script:TestConfigBadOU -DomainController $script:TestDC
            $fd         = Get-TierModelGmsaAclFd -Config $script:TestConfigBadOU -DomainController $script:TestDC

            $standalone.Errors.Count | Should -BeGreaterThan 0
            $fd.Actions.Count        | Should -BeGreaterThan 0
        }

        It "Both planners return objects with Actions, Summary, DurationMs, CorrelationId" {
            $standalone = Get-TierModelGmsaAcl   -Config $script:TestConfig -DomainController $script:TestDC
            $fd         = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC

            foreach ($result in @($standalone, $fd)) {
                $result.PSObject.Properties.Name | Should -Contain 'Actions'
                $result.PSObject.Properties.Name | Should -Contain 'Summary'
                $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
                $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
            }
        }
    }
}
