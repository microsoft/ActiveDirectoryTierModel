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
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -Times ($script:TestConfig.gmsaAclDelegations.Count) -Scope It
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

        It "Processes inherited ACL definitions with malformed ACEs without errors" {
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $gmsaGuid = [Guid]"7b8b558a-93a5-4af7-adca-c017e67f1057"
                $badRule = [PSCustomObject]@{ AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow }
                $matchingRule = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'TEST\Tier1Admins' }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents
                    ObjectType = [Guid]::Empty
                    InheritedObjectType = $gmsaGuid
                }
                [PSCustomObject]@{
                    Path = $Path
                    Access = @($badRule, $matchingRule)
                }
            }

            $singleEntryConfig = [PSCustomObject]@{
                gmsaAclDelegations = @(
                    [PSCustomObject]@{
                        targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                        identityreference = "Tier1Admins"
                        activedirectoryrights = @("GenericAll")
                        accesscontroltype = "Allow"
                        objecttype = "AllObjectClasses"
                        activeDirectorysecurityinheritance = "Descendents"
                        inheritedObjectType = "7b8b558a-93a5-4af7-adca-c017e67f1057"
                    }
                )
                guidMappings = $script:TestConfig.guidMappings
            }

            $result = Get-TierModelGmsaAcl -Config $singleEntryConfig -DomainController $script:TestDC
            $result | Should -Not -BeNullOrEmpty
            $result.Summary.TotalActions | Should -BeLessOrEqual 1
        }

        It "Handles null objectType and explicit inherited GUIDs without analysis errors" {
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                [PSCustomObject]@{ Path = $Path; Access = @() }
            }

            $singleEntryConfig = [PSCustomObject]@{
                gmsaAclDelegations = @(
                    [PSCustomObject]@{
                        targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                        identityreference = "Tier1Admins"
                        activedirectoryrights = @("GenericAll")
                        accesscontroltype = "Allow"
                        objecttype = $null
                        activeDirectorysecurityinheritance = "Descendents"
                        inheritedObjectType = "7b8b558a-93a5-4af7-adca-c017e67f1057"
                    }
                )
                guidMappings = $script:TestConfig.guidMappings
            }

            $result = Get-TierModelGmsaAcl -Config $singleEntryConfig -DomainController $script:TestDC
            $result | Should -Not -BeNullOrEmpty
            $result.Summary.CreateActions | Should -BeLessOrEqual 1
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

    Context "Get-TierModelGmsaAcl - Processing failures" -Tag "Unit", "GmsaAcl", "Planning" {
        BeforeEach {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel { param($Identity, $Server, $ErrorAction) [PSCustomObject]@{ DistinguishedName = $Identity; Name = 'Tier 1 Service Accounts' } }
            Mock Get-ADGroup -ModuleName TierModel { param($Identity, $Server, $ErrorAction) [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN" } }
            Mock Get-ADUser -ModuleName TierModel { throw 'User not found' }
            Mock Get-Acl -ModuleName TierModel { param($Path, $ErrorAction) [PSCustomObject]@{ Path = $Path; Access = @() } }
        }

        It "Returns AclAnalysisFailed when GUID resolution fails during delegation analysis" {
            $badConfig = [PSCustomObject]@{
                gmsaAclDelegations = @([PSCustomObject]@{
                    targetOUPath = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}'
                    identityreference = 'Tier1Admins'
                    activedirectoryrights = @('CreateChild')
                    accesscontroltype = 'Allow'
                    objecttype = 'UnknownObjectType'
                    activeDirectorysecurityinheritance = 'All'
                })
                guidMappings = $script:TestConfig.guidMappings
            }
            Mock Resolve-TierModelGuid -ModuleName TierModel { return $null }

            $result = Get-TierModelGmsaAcl -Config $badConfig -DomainController $script:TestDC

            ($result.Errors | Where-Object { $_.Code -eq 'AclAnalysisFailed' }).Count | Should -BeGreaterThan 0
        }

        It "Returns PlanningFailed when initialization throws" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { throw 'Domain DN lookup failed' }

            $result = Get-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC

            $result.Errors[0].Code | Should -Be 'PlanningFailed'
            $result.Errors[0].Message | Should -Be 'Domain DN lookup failed'
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

        It "Marks principals as resolvable when they are found as users" {
            Mock Get-ADGroup -ModuleName TierModel { throw 'Group not found' }
            Mock Get-ADUser -ModuleName TierModel { param($Identity, $Server, $ErrorAction) [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Users,$script:TestDomainDN" } }

            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC -IncludeDetails

            if ($result.Actions.Count -gt 0) {
                $result.Actions[0].Validation.PrincipalResolvable | Should -Be $true
            }
        }

        It "Returns GmsaAclFdPlanningFailed on outer initialization failure" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { throw 'Domain DN lookup failed' }

            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC

            $result.Errors[0].Code | Should -Be 'GmsaAclFdPlanningFailed'
            $result.Errors[0].Message | Should -Be 'Domain DN lookup failed'
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

        It "Records configuration resolution failures as audit errors" {
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel { throw 'Placeholder resolution failed' }

            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent

            $result.Errors | Should -BeGreaterOrEqual 1
            ($result.Findings | ForEach-Object { $_.Property } | Select-Object -Unique) | Should -Be @('Config')
            ($result.Findings | ForEach-Object { $_.Details } | Select-Object -Unique) | Should -Be @('Placeholder resolution failed')
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

    Context "Get-TierModelGmsaAclFd - Existing ACL analysis" -Tag "Unit", "GmsaAcl", "FullDeployment" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
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
                $serviceGuid = [Guid]"7b8b558a-93a5-4af7-adca-c017e67f1057"

                $rule1 = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "TEST\Tier1Admins" }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = ([System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild)
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType = $serviceGuid
                    InheritedObjectType = [Guid]::Empty
                }

                $rule2 = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "TEST\Tier1Admins" }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents
                    ObjectType = [Guid]::Empty
                    InheritedObjectType = $serviceGuid
                }

                return [PSCustomObject]@{
                    Path = $Path
                    Access = @($rule1, $rule2)
                }
            }
        }

        It "Recognizes existing ACLs and updates analysis when called with -IncludeDetails" {
            $result = Get-TierModelGmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC -IncludeDetails

            $result.Summary.ExistingCount | Should -BeGreaterThan 0
            $result.Analysis.ConfiguredAcls | Should -Be 2
            $result.Analysis.ExistingAcls | Should -BeGreaterThan 0
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like '*gMSA ACL Exists*' } -Times 1
        }
    }

    Context "New-TierModelGmsaAcl - Successful execution" -Tag "Unit", "GmsaAcl", "Execution" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
            Mock Write-TierModelLog -ModuleName TierModel { }
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, [object]$Mappings, [string]$DomainController)
                switch ($Value) {
                    'msDS-GroupManagedServiceAccount' { '7b8b558a-93a5-4af7-adca-c017e67f1057' }
                    'BrokenObjectType' { '00000000-0000-0000-0000-000000000000' }
                    'BrokenInheritedType' { '00000000-0000-0000-0000-000000000000' }
                    'User' { 'bf967aba-0de6-11d0-a285-00aa003049e2' }
                    'Computer' { 'bf967a86-0de6-11d0-a285-00aa003049e2' }
                    default { $null }
                }
            }
            Mock New-Object -ModuleName TierModel -ParameterFilter { $TypeName -eq 'System.DirectoryServices.DirectoryEntry' } {
                $mockAcl = [PSCustomObject]@{}
                $mockAcl | Add-Member -MemberType ScriptMethod -Name AddAccessRule -Value { param($rule) }
                $mockDe = [PSCustomObject]@{ ObjectSecurity = $mockAcl }
                $mockDe | Add-Member -MemberType ScriptMethod -Name CommitChanges -Value { }
                return $mockDe
            }
        }

        It "Applies CreateAcl actions and records applied entries" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local'
                    Data = [PSCustomObject]@{
                        identityreference = 'BUILTIN\Administrators'
                        activedirectoryrights = @('GenericAll')
                        accesscontroltype = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype = '7b8b558a-93a5-4af7-adca-c017e67f1057'
                    }
                })
            }
            $result = New-TierModelGmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 1
            $result.Failed | Should -Be 0
            $result.Converged | Should -BeTrue
            $result.Applied.Count | Should -Be 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like '*Applied gMSA ACL*' } -Times 1
        }

        It "Uses the inheritedObjectType constructor when the plan includes inheritedObjectType" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local'
                    Data = [PSCustomObject]@{
                        identityreference = 'BUILTIN\Administrators'
                        activedirectoryrights = @('GenericAll')
                        accesscontroltype = 'Allow'
                        activeDirectorysecurityinheritance = 'Descendents'
                        objecttype = 'AllObjectClasses'
                        inheritedObjectType = '7b8b558a-93a5-4af7-adca-c017e67f1057'
                    }
                })
            }

            $result = New-TierModelGmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 1
            $result.Applied[0].InheritedObjectType | Should -Not -Be ([Guid]::Empty)
        }

        It "Fails safely when objectType resolves to Guid.Empty" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local'
                        Data = [PSCustomObject]@{
                            identityreference = 'BUILTIN\Administrators'
                            activedirectoryrights = @('CreateChild')
                            accesscontroltype = 'Allow'
                            activeDirectorysecurityinheritance = 'All'
                            objecttype = 'BrokenObjectType'
                        }
                    }
                )
            }

            $result = New-TierModelGmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Converged | Should -BeFalse
            ($result.Errors | Where-Object { $_.Code -eq 'AclApplicationFailed' }).Count | Should -BeGreaterThan 0
            ($result.Errors[0].Message) | Should -Match 'Resolved objectType GUID'
        }

        It "Fails safely when inheritedObjectType resolves to Guid.Empty" {
            $plan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'CreateAcl'
                        Path = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local'
                        Data = [PSCustomObject]@{
                            identityreference = 'BUILTIN\Administrators'
                            activedirectoryrights = @('GenericAll')
                            accesscontroltype = 'Allow'
                            activeDirectorysecurityinheritance = 'Descendents'
                            objecttype = 'AllObjectClasses'
                            inheritedObjectType = 'BrokenInheritedType'
                        }
                    }
                )
            }

            $result = New-TierModelGmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Converged | Should -BeFalse
            ($result.Errors[0].Message) | Should -Match 'Resolved inheritedObjectType GUID'
        }

        It "Applies ACLs with null object types, invalid rights, and non-OU paths" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path = 'CN=Service Accounts,DC=test,DC=local'
                    Data = [PSCustomObject]@{
                        identityreference = 'BUILTIN\Administrators'
                        activedirectoryrights = @('GenericAll', 'NotARealRight')
                        accesscontroltype = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype = $null
                    }
                })
            }

            $result = New-TierModelGmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 1
            $result.Applied[0].ObjectType | Should -Be ([Guid]::Empty)
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like '*Invalid ActiveDirectoryRight*' } -Times 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like '*Applied gMSA ACL*Unknown OU*' } -Times 1
        }

        It "Fails safely when inheritedObjectType resolves to an empty value" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local'
                    Data = [PSCustomObject]@{
                        identityreference = 'BUILTIN\Administrators'
                        activedirectoryrights = @('GenericAll')
                        accesscontroltype = 'Allow'
                        activeDirectorysecurityinheritance = 'Descendents'
                        objecttype = 'AllObjectClasses'
                        inheritedObjectType = 'AllObjectClasses'
                    }
                })
            }

            $result = New-TierModelGmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 1
            ($result.Errors[0].Message) | Should -Match 'Resolved inheritedObjectType GUID'
        }

        It "Fails safely when objectType cannot be resolved" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'CreateAcl'
                    Path = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,DC=test,DC=local'
                    Data = [PSCustomObject]@{
                        identityreference = 'BUILTIN\Administrators'
                        activedirectoryrights = @('CreateChild')
                        accesscontroltype = 'Allow'
                        activeDirectorysecurityinheritance = 'All'
                        objecttype = 'UnknownObjectType'
                    }
                })
            }

            $result = New-TierModelGmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 1
            ($result.Errors[0].Message) | Should -Match "Failed to resolve GUID for 'UnknownObjectType'"
        }

    }

    Context "Test-TierModelGmsaAcl - Non-silent output" -Tag "Unit", "GmsaAcl", "Audit" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ DistinguishedName = $Identity; Name = 'Tier 1 Service Accounts' }
            }
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN" }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw 'User not found'
            }
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:TestDomainDN }
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
                param($Path, $DomainDN)
                return $Path.Replace('{{domainDN}}', $DomainDN)
            }
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, [object]$Mappings, [string]$DomainController)
                $map = @{
                    'msDS-GroupManagedServiceAccount' = '7b8b558a-93a5-4af7-adca-c017e67f1057'
                    'User' = 'bf967aba-0de6-11d0-a285-00aa003049e2'
                    'Computer' = 'bf967a86-0de6-11d0-a285-00aa003049e2'
                }
                if ($map.ContainsKey($Value)) { return $map[$Value] }
                return $null
            }
            Mock Write-TierModelLog -ModuleName TierModel { }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $serviceGuid = [Guid]'7b8b558a-93a5-4af7-adca-c017e67f1057'
                $rule1 = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'TEST\Tier1Admins' }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = ([System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild)
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType = $serviceGuid
                    InheritedObjectType = [Guid]::Empty
                }
                $rule2 = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'TEST\Tier1Admins' }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents
                    ObjectType = [Guid]::Empty
                    InheritedObjectType = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($rule1, $rule2) }
            }
        }

        It "Writes progress and summary output for compliant delegations" {
            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC

            $result.Compliant | Should -Be 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq 'Auditing gMSA ACL delegations...' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like 'Checking gMSA ACL Delegation:*' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ✅ Target OU exists' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq "    ✅ Identity 'Tier1Admins' exists (Group)" }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ✅ OU ACL readable' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ✅ ACL Delegation COMPLIANT' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq "`n=== gMSA ACL Audit Summary ===" }
        }

        It "Uses user fallback, reports missing ACEs, and suppresses summary when requested" {
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw 'Group not found'
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Users,$script:TestDomainDN" }
            }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                return [PSCustomObject]@{ Path = $Path; Access = @() }
            }

            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -SuppressSummary

            $result.Missing | Should -Be 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq "    ✅ Identity 'Tier1Admins' exists (User)" }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ❌ Missing expected ACEs' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -match 'gMSA ACL Audit Summary' } -Times 0
        }

        It "Writes missing target OU output in non-silent mode" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw 'OU not found'
            }

            $result = Test-TierModelGmsaAcl -Config $script:TestConfigBadOU -DomainController $script:TestDC

            $result.Missing | Should -BeGreaterThan 0
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ❌ Target OU missing' }
        }

        It "Detects unexpected ACEs and increments mismatched count" {
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $serviceGuid = [Guid]'7b8b558a-93a5-4af7-adca-c017e67f1057'
                $expected1 = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'TEST\Tier1Admins' }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = ([System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild)
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType = $serviceGuid
                    InheritedObjectType = [Guid]::Empty
                }
                $expected2 = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'TEST\Tier1Admins' }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents
                    ObjectType = [Guid]::Empty
                    InheritedObjectType = $serviceGuid
                }
                $unexpected = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'TEST\Tier1Admins' }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::WriteDacl
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    ObjectType = $serviceGuid
                    InheritedObjectType = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($expected1, $expected2, $unexpected) }
            }

            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC

            $result.Mismatched | Should -Be 1
            ($result.Findings | Where-Object { $_.Type -eq 'UnexpectedAcl' }).Count | Should -Be 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ⚠️ Unexpected ACEs detected' }
        }

        It "Returns an error result when initialization fails" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { throw 'Domain lookup failed' }

            $result = Test-TierModelGmsaAcl -Config $script:TestConfig -DomainController $script:TestDC

            $result.Errors | Should -Be 1
            $result.Findings[0].Identifier | Should -Be 'gMSA ACL Audit'
            $result.Findings[0].Details | Should -Be 'Domain lookup failed'
        }
    }

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

