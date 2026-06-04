#Requires -Modules Pester
<#
.SYNOPSIS
Unit tests for dMSA ACL operation cmdlets (Get-TierModelDmsaAcl, New-TierModelDmsaAcl,
Test-TierModelDmsaAcl, Get-TierModelDmsaAclFd).

.NOTES
Created : 2025-07-18
Tags    : Unit, DmsaAcl
#>

Describe "dMSA ACL Operations" -Tag "Unit", "DmsaAcl" {
    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestDC = "DC01.test.local"
        $script:TestDomainDN = "DC=test,DC=local"

        # dMSA uses a dynamically resolved GUID — use a placeholder value in config
        $script:DmsaPlaceholderGuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

        $script:TestConfig = [PSCustomObject]@{
            organizationalUnits = @(
                @{ name = "Tier1ServiceAccounts"; path = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"; description = "Tier 1 Service Accounts" }
                @{ name = "Tier2ServiceAccounts"; path = "OU=Tier 2 Service Accounts,OU=Tier 2,OU=Tier Model Administration,{{domainDN}}"; description = "Tier 2 Service Accounts" }
            )
            groups = @(
                @{ name = "Tier1Admins"; samAccountName = "Tier1Admins"; path = "OU=Groups,{{domainDN}}"; scope = "DomainLocal"; type = "Security" }
                @{ name = "Tier2Admins"; samAccountName = "Tier2Admins"; path = "OU=Groups,{{domainDN}}"; scope = "DomainLocal"; type = "Security" }
            )
            dmsaAclDelegations = @(
                @{
                    targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                    identityreference = "Tier1Admins"
                    activedirectoryrights = @("CreateChild", "DeleteChild")
                    accesscontroltype = "Allow"
                    objecttype = "msDS-DelegatedManagedServiceAccount"
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
                    inheritedObjectType = "msDS-DelegatedManagedServiceAccount"
                    comment = "Descendents GenericAll delegation"
                    resolveguid = $true
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

        $script:TestConfigEmpty = [PSCustomObject]@{
            organizationalUnits = @()
            groups = @()
            dmsaAclDelegations = @()
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
            dmsaAclDelegations = @(
                @{
                    targetOUPath = "OU=NonExistentOU_XYZ,{{domainDN}}"
                    identityreference = "Tier1Admins"
                    activedirectoryrights = @("CreateChild", "DeleteChild")
                    accesscontroltype = "Allow"
                    objecttype = "msDS-DelegatedManagedServiceAccount"
                    activeDirectorysecurityinheritance = "All"
                    resolveguid = $true
                }
            )
            guidMappings = $script:TestConfig.guidMappings
        }

        $script:TestConfigBadGroup = [PSCustomObject]@{
            dmsaAclDelegations = @(
                @{
                    targetOUPath = "OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}"
                    identityreference = "NonExistentGroup_XYZ_12345"
                    activedirectoryrights = @("CreateChild", "DeleteChild")
                    accesscontroltype = "Allow"
                    objecttype = "msDS-DelegatedManagedServiceAccount"
                    activeDirectorysecurityinheritance = "All"
                    resolveguid = $true
                }
            )
            guidMappings = $script:TestConfig.guidMappings
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
            $acl | Add-Member -MemberType NoteProperty -Name Path   -Value $Path
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
                "User"     = "bf967aba-0de6-11d0-a285-00aa003049e2"
                "Computer" = "bf967a86-0de6-11d0-a285-00aa003049e2"
            }
            if ($map.ContainsKey($Value)) { return $map[$Value] }
            return $null
        }

        # dMSA resolves its GUID dynamically via Resolve-DomainSpecificGuid
        Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
            param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
            if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') {
                return $script:DmsaPlaceholderGuid
            }
            return $null
        }

        Mock Write-TierModelLog -ModuleName TierModel { }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 1: Get-TierModelDmsaAcl Planning
    # ─────────────────────────────────────────────────────────────
    Context "Get-TierModelDmsaAcl - Planning" -Tag "Unit", "DmsaAcl", "Planning" {
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

            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') {
                    return $script:DmsaPlaceholderGuid
                }
                return $null
            }
        }

        It "Returns a plan object with expected structure for valid config" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Analysis'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Returns zero-action plan for empty dmsaAclDelegations" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfigEmpty -DomainController $script:TestDC
            $result.Summary.TotalActions  | Should -Be 0
            $result.Summary.CreateActions | Should -Be 0
            $result.Actions | Should -BeNullOrEmpty
        }

        It "Returns zero-action plan when dmsaAclDelegations property is absent" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfigNoProperty -DomainController $script:TestDC
            $result.Summary.TotalActions | Should -Be 0
            $result.Actions | Should -BeNullOrEmpty
        }

        It "Calls Resolve-DomainSpecificGuid with classSchema for dMSA GUID resolution" {
            Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            Should -Invoke Resolve-DomainSpecificGuid -ModuleName TierModel -ParameterFilter {
                $AttributeName -eq 'msDS-DelegatedManagedServiceAccount' -and
                $SchemaObjectClass -eq 'classSchema'
            }
        }

        It "Throws PlanningFailed when dMSA GUID cannot be resolved" {
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel { return $null }

            $result = Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result.Errors | Should -Not -BeNullOrEmpty

            # Restore
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
        }

        It "Summary contains TotalActions, CreateActions, and RiskAssessment" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result.Summary.TotalActions   | Should -BeOfType [int]
            $result.Summary.CreateActions  | Should -BeOfType [int]
            $result.Summary.RiskAssessment | Should -Not -BeNullOrEmpty
        }

        It "CorrelationId is a valid GUID" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }

        It "DurationMs is a positive number" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result.DurationMs | Should -BeGreaterThan 0
        }

    }

    Context "Get-TierModelDmsaAcl - CreateAcl planning" -Tag "Unit", "DmsaAcl", "Planning" {
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
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
        }
        It "Produces CreateAcl actions when ACLs are absent" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            $result.Actions | Should -Not -BeNullOrEmpty
            $result.Actions[0].Action | Should -Be 'CreateAcl'
        }
    }

    Context "Get-TierModelDmsaAcl - TargetOUNotFound error" -Tag "Unit", "DmsaAcl", "Planning" {
        It "Returns TargetOUNotFound error when target OU does not exist" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfigBadOU -DomainController $script:TestDC
            $result.Errors | Should -Not -BeNullOrEmpty
            ($result.Errors | Where-Object { $_.Code -eq 'TargetOUNotFound' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-TierModelDmsaAcl - SecurityPrincipalNotFound error" -Tag "Unit", "DmsaAcl", "Planning" {
        It "Returns SecurityPrincipalNotFound error when delegation group does not exist" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfigBadGroup -DomainController $script:TestDC
            $result.Errors | Should -Not -BeNullOrEmpty
            ($result.Errors | Where-Object { $_.Code -eq 'SecurityPrincipalNotFound' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-TierModelDmsaAcl - AclReadFailed error" -Tag "Unit", "DmsaAcl", "Planning" {
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
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
            Mock Get-Acl -ModuleName TierModel { param($Path, $ErrorAction) throw "Access denied" }
        }
        It "Returns AclReadFailed error when Get-Acl throws" {
            $result = Get-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC
            ($result.Errors | Where-Object { $_.Code -eq 'AclReadFailed' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-TierModelDmsaAcl - Existing ACL detection" -Tag "Unit", "DmsaAcl", "Planning" {
        BeforeEach {
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
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $dmsaGuid = [Guid]$script:DmsaPlaceholderGuid
                $badRule = [PSCustomObject]@{ AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow }
                $matchingRule = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'TEST\Tier1Admins' }
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents
                    ObjectType = [Guid]::Empty
                    InheritedObjectType = $dmsaGuid
                }
                [PSCustomObject]@{
                    Path = $Path
                    Access = @($badRule, $matchingRule)
                }
            }
        }

        It "Processes inherited ACL definitions with malformed ACEs without errors" {
            $singleEntryConfig = [PSCustomObject]@{
                dmsaAclDelegations = @(
                    @{
                        targetOUPath = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}'
                        identityreference = 'Tier1Admins'
                        activedirectoryrights = @('GenericAll')
                        accesscontroltype = 'Allow'
                        objecttype = 'AllObjectClasses'
                        activeDirectorysecurityinheritance = 'Descendents'
                        inheritedObjectType = $script:DmsaPlaceholderGuid
                    }
                )
                guidMappings = $script:TestConfig.guidMappings
            }

            $result = Get-TierModelDmsaAcl -Config $singleEntryConfig -DomainController $script:TestDC
            $result.Errors | Should -BeNullOrEmpty
            $result.Summary.TotalActions | Should -BeLessOrEqual 1
        }

        It "Handles null object types and explicit inherited GUIDs without analysis errors" {
            Mock Get-Acl -ModuleName TierModel { param($Path, $ErrorAction) [PSCustomObject]@{ Path = $Path; Access = @() } }

            $singleEntryConfig = [PSCustomObject]@{
                dmsaAclDelegations = @(
                    @{
                        targetOUPath = 'OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{domainDN}}'
                        identityreference = 'Tier1Admins'
                        activedirectoryrights = @('GenericAll')
                        accesscontroltype = 'Allow'
                        objecttype = $null
                        activeDirectorysecurityinheritance = 'Descendents'
                        inheritedObjectType = $script:DmsaPlaceholderGuid
                    }
                )
                guidMappings = $script:TestConfig.guidMappings
            }

            $result = Get-TierModelDmsaAcl -Config $singleEntryConfig -DomainController $script:TestDC
            $result.Errors | Should -BeNullOrEmpty
            $result.Summary.CreateActions | Should -BeLessOrEqual 1
        }
    }

    Context "Get-TierModelDmsaAcl - Processing failures" -Tag "Unit", "DmsaAcl", "Planning" {
        BeforeEach {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel { param($Identity, $Server, $ErrorAction) [PSCustomObject]@{ DistinguishedName = $Identity; Name = 'Tier 1 Service Accounts' } }
            Mock Get-ADGroup -ModuleName TierModel { param($Identity, $Server, $ErrorAction) [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Groups,$script:TestDomainDN" } }
            Mock Get-ADUser -ModuleName TierModel { throw 'User not found' }
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
            Mock Get-Acl -ModuleName TierModel { param($Path, $ErrorAction) [PSCustomObject]@{ Path = $Path; Access = @() } }
        }

        It "Returns AclAnalysisFailed when GUID resolution fails during delegation analysis" {
            $badConfig = [PSCustomObject]@{
                dmsaAclDelegations = @([PSCustomObject]@{
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

            $result = Get-TierModelDmsaAcl -Config $badConfig -DomainController $script:TestDC

            ($result.Errors | Where-Object { $_.Code -eq 'AclAnalysisFailed' }).Count | Should -BeGreaterThan 0
        }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 2: Get-TierModelDmsaAclFd Full Deployment Planning
    # ─────────────────────────────────────────────────────────────
    Context "Get-TierModelDmsaAclFd - Full Deployment Planning" -Tag "Unit", "DmsaAcl", "FullDeployment" {

        It "Returns a plan object with expected structure for valid config" {
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Actions'
            $result.PSObject.Properties.Name | Should -Contain 'Summary'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Summary includes ExistingCount property" {
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result.Summary.Keys | Should -Contain 'ExistingCount'
        }

        It "Returns zero-action plan for empty dmsaAclDelegations" {
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfigEmpty -DomainController $script:TestDC
            $result.Summary.TotalActions  | Should -Be 0
            $result.Summary.ExistingCount | Should -Be 0
        }

        It "Returns zero-action plan when dmsaAclDelegations property is absent" {
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfigNoProperty -DomainController $script:TestDC
            $result.Summary.TotalActions | Should -Be 0
        }

        It "Does NOT fail-fast when OUs are missing — creates actions with TargetOUExists=false" {
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfigBadOU -DomainController $script:TestDC
            $createActions = @($result.Actions | Where-Object { $_.Action -eq 'CreateAcl' })
            $createActions.Count | Should -BeGreaterThan 0
            $createActions[0].Validation.TargetOUExists | Should -Be $false
        }

        It "Calls Resolve-DomainSpecificGuid with classSchema for dMSA GUID" {
            Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC | Out-Null
            Should -Invoke Resolve-DomainSpecificGuid -ModuleName TierModel -ParameterFilter {
                $AttributeName -eq 'msDS-DelegatedManagedServiceAccount' -and
                $SchemaObjectClass -eq 'classSchema'
            }
        }

        It "-Silent parameter suppresses Write-Host output" {
            Mock Write-Host -ModuleName TierModel { }
            Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            Should -Invoke Write-Host -ModuleName TierModel -Times 0
        }

        It "CorrelationId is a valid GUID" {
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }

        It "DurationMs is a positive number" {
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "Marks principals as resolvable when they are found as users" {
            Mock Get-ADGroup -ModuleName TierModel { throw 'Group not found' }
            Mock Get-ADUser -ModuleName TierModel { param($Identity, $Server, $ErrorAction) [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Users,$script:TestDomainDN" } }

            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC -IncludeDetails

            if ($result.Actions.Count -gt 0) {
                $result.Actions[0].Validation.PrincipalResolvable | Should -Be $true
            }
        }

        It "Returns DmsaAclFdPlanningFailed on outer initialization failure" {
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel { return $null }

            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC

            $result.Errors[0].Code | Should -Be 'DmsaAclFdPlanningFailed'
        }

        It "Returns DmsaAclFdAnalysisFailed error code on inner processing failure" {
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel { throw "Placeholder resolution failed" }

            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC
            $result.Errors | Should -Not -BeNullOrEmpty
            ($result.Errors | Where-Object { $_.Code -eq 'DmsaAclFdAnalysisFailed' }) | Should -Not -BeNullOrEmpty

            Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
                param($Path, $DomainDN)
                return $Path.Replace("{{domainDN}}", $DomainDN)
            }
        }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 3: New-TierModelDmsaAcl Execution
    # ─────────────────────────────────────────────────────────────
    Context "New-TierModelDmsaAcl - Execution" -Tag "Unit", "DmsaAcl", "Execution" {

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
                            objecttype                      = $script:DmsaPlaceholderGuid
                        }
                    }
                )
            }
        }

        It "Empty plan returns Executed=0, Converged=true" {
            $result = New-TierModelDmsaAcl -Plan $script:EmptyPlan -DomainController $script:TestDC -Config $script:TestConfig
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
            $result = New-TierModelDmsaAcl -Plan $nonCreatePlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Executed | Should -Be 0
        }

        It "-WhatIf single action produces Skipped=1, Executed=0" {
            $result = New-TierModelDmsaAcl -Plan $script:SingleAclPlan -DomainController $script:TestDC -Config $script:TestConfig -WhatIf
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
                            objecttype                      = $script:DmsaPlaceholderGuid
                        }
                    }
                )
            }
            $result = New-TierModelDmsaAcl -Plan $badPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.Converged | Should -Be $false
            $result.Failed    | Should -BeGreaterThan 0
            ($result.Errors | Where-Object { $_.Code -eq 'AclApplicationFailed' }) | Should -Not -BeNullOrEmpty
        }

        It "Result object contains all required properties" {
            $result = New-TierModelDmsaAcl -Plan $script:EmptyPlan -DomainController $script:TestDC -Config $script:TestConfig
            $result.PSObject.Properties.Name | Should -Contain 'Executed'
            $result.PSObject.Properties.Name | Should -Contain 'Failed'
            $result.PSObject.Properties.Name | Should -Contain 'Skipped'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'Converged'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "CorrelationId is a valid GUID" {
            $result = New-TierModelDmsaAcl -Plan $script:EmptyPlan -DomainController $script:TestDC -Config $script:TestConfig
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }
    }

    # ─────────────────────────────────────────────────────────────
    # Context 4: Test-TierModelDmsaAcl Audit
    # ─────────────────────────────────────────────────────────────
    Context "Test-TierModelDmsaAcl - Audit" -Tag "Unit", "DmsaAcl", "Audit" {

        It "Returns audit result object with required properties" {
            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
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
            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            $result.TotalChecked | Should -Be 1
        }

        It "Calls Resolve-DomainSpecificGuid with classSchema during audit" {
            Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            Should -Invoke Resolve-DomainSpecificGuid -ModuleName TierModel -ParameterFilter {
                $AttributeName -eq 'msDS-DelegatedManagedServiceAccount' -and
                $SchemaObjectClass -eq 'classSchema'
            }
        }


        It "Missing count increments when target OU does not exist" {
            $result = Test-TierModelDmsaAcl -Config $script:TestConfigBadOU -DomainController $script:TestDC -Silent
            $result.Missing | Should -BeGreaterThan 0
        }

        It "Missing count increments when security principal does not exist" {
            $result = Test-TierModelDmsaAcl -Config $script:TestConfigBadGroup -DomainController $script:TestDC -Silent
            $result.Missing | Should -BeGreaterThan 0
        }

        It "-Silent suppresses Write-Host output" {
            Mock Write-Host -ModuleName TierModel { }
            Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            Should -Invoke Write-Host -ModuleName TierModel -Times 0
        }

        It "-SuppressSummary suppresses summary output" {
            Mock Write-Host -ModuleName TierModel { }
            Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -SuppressSummary | Out-Null
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter {
                $Object -match 'dMSA ACL Audit Summary'
            } -Times 0
        }

        It "Config without dmsaAclDelegations returns TotalChecked=0" {
            $result = Test-TierModelDmsaAcl -Config $script:TestConfigNoProperty -DomainController $script:TestDC -Silent
            $result.TotalChecked | Should -Be 0
        }

        It "CorrelationId is a valid GUID" {
            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            { [System.Guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        }

        It "DurationMs is a positive number" {
            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It "Calls Resolve-TierModelPlaceholder during audit" {
            Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent | Out-Null
            Should -Invoke Resolve-TierModelPlaceholder -ModuleName TierModel -Times 1
        }

        It "Records configuration resolution failures as audit errors" {
            Mock Resolve-TierModelPlaceholder -ModuleName TierModel { throw 'Placeholder resolution failed' }

            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent

            $result.Errors | Should -BeGreaterOrEqual 1
            ($result.Findings | ForEach-Object { $_.Property } | Select-Object -Unique) | Should -Be @('Config')
            ($result.Findings | ForEach-Object { $_.Details } | Select-Object -Unique) | Should -Be @('Placeholder resolution failed')
        }
    }

    Context "Test-TierModelDmsaAcl - Compliant ACEs" -Tag "Unit", "DmsaAcl", "Audit" {
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
                    "User" = "bf967aba-0de6-11d0-a285-00aa003049e2"
                    "Computer" = "bf967a86-0de6-11d0-a285-00aa003049e2"
                }
                if ($map.ContainsKey($Value)) { return $map[$Value] }
                return $null
            }
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
            Mock Write-TierModelLog -ModuleName TierModel { }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $dmsaGuid = [Guid]$script:DmsaPlaceholderGuid

                $rule1 = New-Object PSObject
                $rule1 | Add-Member -MemberType NoteProperty -Name IdentityReference -Value ([PSCustomObject]@{ Value = "TEST\Tier1Admins" })
                $rule1 | Add-Member -MemberType NoteProperty -Name AccessControlType  -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule1 | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild)
                $rule1 | Add-Member -MemberType NoteProperty -Name InheritanceType -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                $rule1 | Add-Member -MemberType NoteProperty -Name ObjectType -Value $dmsaGuid
                $rule1 | Add-Member -MemberType NoteProperty -Name InheritedObjectType -Value ([Guid]::Empty)

                $rule2 = New-Object PSObject
                $rule2 | Add-Member -MemberType NoteProperty -Name IdentityReference -Value ([PSCustomObject]@{ Value = "TEST\Tier1Admins" })
                $rule2 | Add-Member -MemberType NoteProperty -Name AccessControlType  -Value ([System.Security.AccessControl.AccessControlType]::Allow)
                $rule2 | Add-Member -MemberType NoteProperty -Name ActiveDirectoryRights -Value ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll)
                $rule2 | Add-Member -MemberType NoteProperty -Name InheritanceType -Value ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents)
                $rule2 | Add-Member -MemberType NoteProperty -Name ObjectType -Value ([Guid]::Empty)
                $rule2 | Add-Member -MemberType NoteProperty -Name InheritedObjectType -Value ([Guid]::Empty)

                $acl = New-Object PSObject
                $acl | Add-Member -MemberType NoteProperty -Name Path   -Value $Path
                $acl | Add-Member -MemberType NoteProperty -Name Access -Value @($rule1, $rule2)
                return $acl
            }
        }
        It "Compliant count increments when both expected ACEs are present" {
            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -Silent
            $result.Compliant | Should -BeGreaterThan 0
        }
    }

    # ─────────────────────────────────────────────────────────────

    Context "Get-TierModelDmsaAclFd - Existing ACL analysis" -Tag "Unit", "DmsaAcl", "FullDeployment" {
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
                    "User" = "bf967aba-0de6-11d0-a285-00aa003049e2"
                    "Computer" = "bf967a86-0de6-11d0-a285-00aa003049e2"
                }
                if ($map.ContainsKey($Value)) { return $map[$Value] }
                return $null
            }
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
            Mock Write-TierModelLog -ModuleName TierModel { }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $serviceGuid = [Guid]$script:DmsaPlaceholderGuid

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
            $result = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC -IncludeDetails

            $result.Summary.ExistingCount | Should -BeGreaterThan 0
            $result.Analysis.ConfiguredAcls | Should -Be 2
            $result.Analysis.ExistingAcls | Should -BeGreaterThan 0
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like '*dMSA ACL Exists*' } -Times 1
        }
    }

    Context "New-TierModelDmsaAcl - Successful execution" -Tag "Unit", "DmsaAcl", "Execution" {
        BeforeEach {
            Mock Write-Host -ModuleName TierModel { }
            Mock Write-TierModelLog -ModuleName TierModel { }
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
            Mock Resolve-TierModelGuid -ModuleName TierModel {
                param([string]$Value, [object]$Mappings, [string]$DomainController)
                switch ($Value) {
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
                        objecttype = $script:DmsaPlaceholderGuid
                    }
                })
            }
            $result = New-TierModelDmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 1
            $result.Failed | Should -Be 0
            $result.Converged | Should -BeTrue
            $result.Applied.Count | Should -Be 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like '*Applied dMSA ACL*' } -Times 1
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
                        inheritedObjectType = $script:DmsaPlaceholderGuid
                    }
                })
            }

            $result = New-TierModelDmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

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

            $result = New-TierModelDmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Converged | Should -BeFalse
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

            $result = New-TierModelDmsaAcl -Plan $plan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Converged | Should -BeFalse
            ($result.Errors[0].Message) | Should -Match 'Resolved inheritedObjectType GUID'
        }

        It "Returns a critical error when the dMSA class GUID cannot be resolved during execution" {
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel { return $null }

            $result = New-TierModelDmsaAcl -Plan $script:EmptyPlan -DomainController $script:TestDC -Config $script:TestConfig

            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Converged | Should -BeFalse
            $result.Errors[0].Code | Should -Be 'AclExecutionFailed'
            $result.Errors[0].Message | Should -Match 'Failed to resolve domain-specific GUID'
        }
    }

    Context "Test-TierModelDmsaAcl - Non-silent output" -Tag "Unit", "DmsaAcl", "Audit" {
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
                    'User' = 'bf967aba-0de6-11d0-a285-00aa003049e2'
                    'Computer' = 'bf967a86-0de6-11d0-a285-00aa003049e2'
                }
                if ($map.ContainsKey($Value)) { return $map[$Value] }
                return $null
            }
            Mock Resolve-DomainSpecificGuid -ModuleName TierModel {
                param([string]$AttributeName, [string]$SchemaObjectClass, [string]$DomainController)
                if ($AttributeName -eq 'msDS-DelegatedManagedServiceAccount') { return $script:DmsaPlaceholderGuid }
                return $null
            }
            Mock Write-TierModelLog -ModuleName TierModel { }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $serviceGuid = [Guid]$script:DmsaPlaceholderGuid
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
            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC

            $result.Compliant | Should -BeGreaterThan 0
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq 'Auditing dMSA ACL delegations...' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -like 'Checking dMSA ACL Delegation:*' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ✅ Target OU exists' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq "    ✅ Identity 'Tier1Admins' exists (Group)" }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ✅ OU ACL readable' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ✅ ACL Delegation COMPLIANT' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq "`n=== dMSA ACL Audit Summary ===" }
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

            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC -SuppressSummary

            $result.Missing | Should -Be 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq "    ✅ Identity 'Tier1Admins' exists (User)" }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ❌ Missing expected ACEs' }
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -match 'dMSA ACL Audit Summary' } -Times 0
        }

        It "Writes missing target OU output in non-silent mode" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                throw 'OU not found'
            }

            $result = Test-TierModelDmsaAcl -Config $script:TestConfigBadOU -DomainController $script:TestDC

            $result.Missing | Should -BeGreaterThan 0
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ❌ Target OU missing' }
        }

        It "Detects unexpected ACEs and increments mismatched count" {
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $serviceGuid = [Guid]$script:DmsaPlaceholderGuid
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

            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC

            $result.Mismatched | Should -Be 1
            ($result.Findings | Where-Object { $_.Type -eq 'UnexpectedAcl' }).Count | Should -Be 1
            Should -Invoke Write-Host -ModuleName TierModel -ParameterFilter { $Object -eq '    ⚠️ Unexpected ACEs detected' }
        }

        It "Returns an error result when initialization fails" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { throw 'Domain lookup failed' }

            $result = Test-TierModelDmsaAcl -Config $script:TestConfig -DomainController $script:TestDC

            $result.Errors | Should -Be 1
            $result.Findings[0].Identifier | Should -Be 'dMSA ACL Audit'
            $result.Findings[0].Details | Should -Be 'Domain lookup failed'
        }
    }

    # Context 5: Get-TierModelDmsaAcl vs Get-TierModelDmsaAclFd Comparison
    # ─────────────────────────────────────────────────────────────
    Context "Get-TierModelDmsaAcl vs Get-TierModelDmsaAclFd - Comparison" -Tag "Unit", "DmsaAcl" {

        It "Standalone planner fails-fast with validation errors when OUs missing; Fd planner does not" {
            $standalone = Get-TierModelDmsaAcl   -Config $script:TestConfigBadOU -DomainController $script:TestDC
            $fd         = Get-TierModelDmsaAclFd -Config $script:TestConfigBadOU -DomainController $script:TestDC

            $standalone.Errors.Count | Should -BeGreaterThan 0
            $fd.Actions.Count        | Should -BeGreaterThan 0
        }

        It "Both planners return objects with Actions, Summary, DurationMs, CorrelationId" {
            $standalone = Get-TierModelDmsaAcl   -Config $script:TestConfig -DomainController $script:TestDC
            $fd         = Get-TierModelDmsaAclFd -Config $script:TestConfig -DomainController $script:TestDC

            foreach ($result in @($standalone, $fd)) {
                $result.PSObject.Properties.Name | Should -Contain 'Actions'
                $result.PSObject.Properties.Name | Should -Contain 'Summary'
                $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
                $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
            }
        }
    }
}
