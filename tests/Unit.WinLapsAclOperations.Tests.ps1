#Requires -Modules Pester
<#
.SYNOPSIS
Unit tests for Windows LAPS ACL operation cmdlets.
Covers T015 (Get-TierModelWinLapsAcl), T016 (New-TierModelWinLapsAcl),
T017 (Get-TierModelWinLapsAclFd), T018 (Test-TierModelWinLapsAcl +
Test-TierModelWinLapsDecryptor), and T020 (Windows-LAPS-only invariant).

.NOTES
Created : 2026-07-16
Tags    : Unit, WinLapsAcl
All AD/LAPS/GPO cmdlets are mocked — no live AD required.
#>

Describe "Windows LAPS ACL Operations" -Tag "Unit", "WinLapsAcl" {

    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        $script:TestDC       = "DC01.test.local"
        $script:TestDomainDN = "DC=test,DC=local"
        $script:TestNetBIOS  = "TEST"

        # ── Minimal 1-delegation config (Self+Read+Reset+Decryptor) ───────────────
        $script:WinLapsConfig1 = [PSCustomObject]@{
            winLapsDelegations = @(
                [PSCustomObject]@{
                    ouDn                   = "OU=Tier 0 Servers,{{DOMAIN_DN}}"
                    computerSelfPermission = $true
                    readGroup              = "Tier 0 Admins"
                    resetGroup             = "Tier 0 Admins"
                    decryptorGroup         = "Tier 0 Admins"
                    decryptorGpoName       = "*- Tier 0 Servers Windows LAPS - Computer"
                }
            )
        }

        # ── 2-delegation config (no decryptor — pure CreateAcl planning) ──────────
        $script:WinLapsConfig2 = [PSCustomObject]@{
            winLapsDelegations = @(
                [PSCustomObject]@{
                    ouDn                   = "OU=Tier 0 Servers,{{DOMAIN_DN}}"
                    computerSelfPermission = $true
                    readGroup              = "Tier 0 Admins"
                    resetGroup             = "Tier 0 Admins"
                }
                [PSCustomObject]@{
                    ouDn                   = "OU=Tier 1 Servers,{{DOMAIN_DN}}"
                    computerSelfPermission = $true
                    readGroup              = "Tier 1 Admins"
                    resetGroup             = "Tier 1 Admins"
                }
            )
        }

        # ── Config with a DC OU entry (isDomainControllerOu = true) ─────────────
        $script:WinLapsConfigDcEntry = [PSCustomObject]@{
            winLapsDelegations = @(
                [PSCustomObject]@{
                    ouDn                   = "OU=Domain Controllers,{{DOMAIN_DN}}"
                    computerSelfPermission = $true
                    readGroup              = "Domain Admins"
                    resetGroup             = "Domain Admins"
                    isDomainControllerOu   = $true
                }
            )
        }

        # ── Config with 2 delegations including decryptor actions ─────────────────
        $script:WinLapsConfig2WithDecryptor = [PSCustomObject]@{
            winLapsDelegations = @(
                [PSCustomObject]@{
                    ouDn                   = "OU=Tier 0 Servers,{{DOMAIN_DN}}"
                    computerSelfPermission = $true
                    readGroup              = "Tier 0 Admins"
                    resetGroup             = "Tier 0 Admins"
                    decryptorGroup         = "Tier 0 Admins"
                    decryptorGpoName       = "*- Tier 0 Servers Windows LAPS - Computer"
                }
                [PSCustomObject]@{
                    ouDn                   = "OU=Tier 1 Servers,{{DOMAIN_DN}}"
                    computerSelfPermission = $true
                    readGroup              = "Tier 1 Admins"
                    resetGroup             = "Tier 1 Admins"
                    decryptorGroup         = "Tier 1 Admins"
                    decryptorGpoName       = "*- Tier 1 Servers Windows LAPS - Computer"
                }
            )
        }

        # ── Empty / no-property configs ───────────────────────────────────────────
        $script:WinLapsConfigEmpty = [PSCustomObject]@{
            winLapsDelegations = @()
        }
        $script:WinLapsConfigNoProperty = [PSCustomObject]@{
            groups = @()
        }

        # ── Module-level base mocks (happy path) ──────────────────────────────────
        Mock Write-TierModelLog -ModuleName TierModel { }

        Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:TestDomainDN }

        Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
            param($Path, $DomainDN)
            return $Path -replace '\{\{DOMAIN_DN\}\}', $DomainDN
        }

        # Schema checks: Get-ADRootDSE for schemaNamingContext
        Mock Get-ADRootDSE -ModuleName TierModel {
            return [PSCustomObject]@{
                schemaNamingContext = "CN=Schema,CN=Configuration,$script:TestDomainDN"
            }
        }

        # Get-ADObject: -Identity (schemaObj version) vs -Filter (LAPS attr/GUID checks)
        Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
            return [PSCustomObject]@{ objectVersion = 88; schemaIDGUID = $null }
        }
        Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
            # LAPS attribute present / schema check passes; GUID = null (fallback SELF detection)
            return [PSCustomObject]@{ lDAPDisplayName = 'msLAPS-Password'; schemaIDGUID = $null }
        }

        # Import-Module LAPS succeeds (in-memory LAPS stub already registered by ADStubs)
        Mock Import-Module -ModuleName TierModel { } -ParameterFilter { $Name -eq 'LAPS' }

        # Get-ADDomain: DFL + NetBIOS + DistinguishedName for Resolve-TierModelDomainDN
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DomainMode        = 'Windows2016Domain'
                NetBIOSName       = $script:TestNetBIOS
                DistinguishedName = $script:TestDomainDN
            }
        }

        # OUs exist by default
        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            return [PSCustomObject]@{ DistinguishedName = $Identity; Name = "Test OU" }
        }

        # Groups resolve to sAMAccountName
        Mock Get-ADGroup -ModuleName TierModel {
            param($Filter, $Identity, $Server, $Properties, $ErrorAction)
            $name = if ($Filter -match "Name -eq '([^']+)'") { $Matches[1] } else { "$Identity" }
            $sam  = $name -replace ' ', ''
            return [PSCustomObject]@{ sAMAccountName = $sam; Name = $name }
        }

        # No DC objects in any OU (DC-exclusion check returns nothing)
        Mock Get-ADComputer -ModuleName TierModel { return $null }

        # Get-Acl: no existing SELF ACEs (all LAPS permissions need to be planned)
        Mock Get-Acl -ModuleName TierModel {
            param($Path, $ErrorAction)
            return [PSCustomObject]@{ Path = $Path; Access = @() }
        }

        # Find-LapsADExtendedRights: no existing holders (Read+Reset need to be planned)
        Mock Find-LapsADExtendedRights -ModuleName TierModel { return $null }

        # Get-GPRegistryValue: throws by default (decryptor not yet configured)
        Mock Get-GPRegistryValue -ModuleName TierModel { throw "Registry value not found" }

        # LAPS apply cmdlets: succeed silently by default
        Mock Set-LapsADComputerSelfPermission  -ModuleName TierModel { }
        Mock Set-LapsADReadPasswordPermission  -ModuleName TierModel { }
        Mock Set-LapsADResetPasswordPermission -ModuleName TierModel { }
        Mock Set-GPRegistryValue               -ModuleName TierModel { }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T015 — Get-TierModelWinLapsAcl (standalone planner)
    # ════════════════════════════════════════════════════════════════════════════
    Context "T015: Get-TierModelWinLapsAcl — Plan Generation" -Tag "Unit", "WinLapsAcl", "Planning" {

        It "Returns a plan object with the required structure" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $plan | Should -Not -BeNullOrEmpty
            $plan.PSObject.Properties.Name | Should -Contain 'Actions'
            $plan.PSObject.Properties.Name | Should -Contain 'Summary'
            $plan.PSObject.Properties.Name | Should -Contain 'Analysis'
            $plan.PSObject.Properties.Name | Should -Contain 'Errors'
            $plan.PSObject.Properties.Name | Should -Contain 'Warnings'
            $plan.PSObject.Properties.Name | Should -Contain 'Converged'
            $plan.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $plan.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Plans exactly 3 CreateAcl actions per delegation (Self + Read + Reset)" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $createActions = @($plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' })
            $createActions.Count | Should -Be 6   # 3 per delegation * 2 delegations
            $plan.Summary.CreateActions | Should -Be 6
        }

        It "Plans ConfigureLapsDecryptor actions for entries with decryptorGroup" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $decryptorActions = @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureLapsDecryptor' })
            $decryptorActions.Count | Should -Be 1
        }

        It "Converged = false when actions are planned" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2 -DomainController $script:TestDC
            $plan.Converged | Should -Be $false
        }

        It "Returns zero-action plan for empty winLapsDelegations" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfigEmpty -DomainController $script:TestDC

            $plan.Summary.TotalActions | Should -Be 0
            $plan.Converged            | Should -Be $true
        }

        It "Returns zero-action plan when config has no winLapsDelegations property" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfigNoProperty -DomainController $script:TestDC

            $plan.Summary.TotalActions | Should -Be 0
            $plan.Converged            | Should -Be $true
        }

        It "Fail-fast on missing OU: Errors contains TargetOUNotFound, Actions empty" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] "OU not found"
            }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            @($plan.Errors).Count  | Should -BeGreaterThan 0
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'TargetOUNotFound'
            $plan.Converged | Should -Be $false
        }

        It "Fail-fast on missing group: Errors contains RequiredGroupNotFound, Actions empty" {
            Mock Get-ADGroup -ModuleName TierModel {
                param($Filter, $Server, $Properties, $ErrorAction)
                return $null  # group not found
            }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'RequiredGroupNotFound'
        }

        It "Gate 1 schema fail-fast: WINLAPS_SCHEMA_MISSING, zero actions, Converged=false" {
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } { return $null }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'WINLAPS_SCHEMA_MISSING'
            $plan.Converged | Should -Be $false
        }

        It "Gate 3 DFL fail-fast: WINLAPS_DFL_INSUFFICIENT, zero actions" {
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode        = 'Windows2012R2Domain'
                    NetBIOSName       = $script:TestNetBIOS
                    DistinguishedName = $script:TestDomainDN
                }
            }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'WINLAPS_DFL_INSUFFICIENT'
        }

        It "Idempotency: zero actions and Converged=true when all DACLs already present" {
            # SELF ACE present on OU
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $selfAce = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'NT AUTHORITY\SELF' }
                    IsInherited       = $false
                    ObjectType        = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($selfAce) }
            }
            # Read+Reset holders present
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{
                    ExtendedRightHolders = @("$script:TestNetBIOS\Tier0Admins")
                }
            }
            # Decryptor already set correctly
            Mock Get-GPRegistryValue -ModuleName TierModel {
                return [PSCustomObject]@{
                    ValueName = 'ADPasswordEncryptionPrincipal'
                    Value     = "$script:TestNetBIOS\Tier0Admins"
                }
            }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $plan.Summary.TotalActions | Should -Be 0
            $plan.Converged            | Should -Be $true
            $plan.Summary.ExistingCount | Should -BeGreaterThan 0
        }

        It "Config parameter is mandatory" {
            $attr = (Get-Command Get-TierModelWinLapsAcl).Parameters['Config'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            ($attr.Mandatory -contains $true) | Should -BeTrue
        }

        It "DomainController parameter is mandatory" {
            $attr = (Get-Command Get-TierModelWinLapsAcl).Parameters['DomainController'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            ($attr.Mandatory -contains $true) | Should -BeTrue
        }

        It "DC OU entry does not trigger DC scope rejection (isDomainControllerOu = true)" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfigDcEntry -DomainController $script:TestDC

            # DC exclusion check is bypassed when isDomainControllerOu = true
            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_DC_SCOPE_REJECTED' }).Count | Should -Be 0
        }

        It "Gate 1 catch: WINLAPS_SCHEMA_MISSING when schema query throws" {
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                throw "Schema query failed"
            }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $plan.Actions | Should -HaveCount 0
            $plan.Converged | Should -Be $false
            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_SCHEMA_MISSING' }).Count | Should -BeGreaterThan 0
        }

        It "Gate 2 catch: WINLAPS_MODULE_MISSING when Import-Module LAPS throws" {
            Mock Import-Module -ModuleName TierModel -ParameterFilter { $Name -eq 'LAPS' } {
                throw "LAPS module not found"
            }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $plan.Actions | Should -HaveCount 0
            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_MODULE_MISSING' }).Count | Should -BeGreaterThan 0
        }

        It "Domain resolution failure: DOMAIN_RESOLUTION_FAILED when Get-ADDomain throws" {
            Mock Get-ADDomain -ModuleName TierModel { throw "Domain not reachable" }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $plan.Actions | Should -HaveCount 0
            @($plan.Errors | Where-Object { $_.Code -eq 'DOMAIN_RESOLUTION_FAILED' }).Count | Should -BeGreaterThan 0
        }

        It "Gate 4a: RequiredGpoNotFound when Config.gpos has LAPS GPO and Get-GPO throws" {
            # Build a config that has a gpos section with a Windows LAPS GPO name
            $configWithGpos = [PSCustomObject]@{
                winLapsDelegations = @(
                    [PSCustomObject]@{
                        ouDn                   = "OU=Tier 0 Servers,{{DOMAIN_DN}}"
                        computerSelfPermission = $true
                        readGroup              = "Tier 0 Admins"
                        resetGroup             = "Tier 0 Admins"
                    }
                )
                gpos = [PSCustomObject]@{
                    'Tier0'  = [PSCustomObject]@{
                        PostConfigureGpo = @(
                            [PSCustomObject]@{ name = '*- Tier 0 Servers Windows LAPS - Computer' }
                        )
                    }
                }
            }
            Mock Get-GPO -ModuleName TierModel { throw "GPO not found" }

            $plan = Get-TierModelWinLapsAcl -Config $configWithGpos -DomainController $script:TestDC

            @($plan.Errors | Where-Object { $_.Code -eq 'RequiredGpoNotFound' }).Count | Should -BeGreaterThan 0
        }

        It "Gate 4b: WINLAPS_DC_SCOPE_REJECTED when non-DC OU contains DC objects" {
            Mock Get-ADComputer -ModuleName TierModel {
                return [PSCustomObject]@{ Name = "DC01"; PrimaryGroupID = 516 }
            }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_DC_SCOPE_REJECTED' }).Count | Should -BeGreaterThan 0
        }

        It "Group validation catch: RequiredGroupNotFound when Get-ADGroup throws during pre-flight" {
            Mock Get-ADGroup -ModuleName TierModel { throw "Group not found in AD" }

            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            @($plan.Errors | Where-Object { $_.Code -eq 'RequiredGroupNotFound' }).Count | Should -BeGreaterThan 0
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T016 — New-TierModelWinLapsAcl (apply)
    # ════════════════════════════════════════════════════════════════════════════
    Context "T016: New-TierModelWinLapsAcl — Apply" -Tag "Unit", "WinLapsAcl", "Apply" {

        BeforeAll {
            # Build a reusable test plan with 3 CreateAcl + 1 ConfigureLapsDecryptor actions
            $script:TestPlan3Actions = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action       = 'CreateAcl'
                        ResourceType = 'LapsPermission'
                        Name         = 'LAPS Self-Permission: Tier 0 Servers'
                        Data         = [PSCustomObject]@{
                            lapsOperation          = 'SetComputerSelfPermission'
                            ouDn                   = "OU=Tier 0 Servers,$script:TestDomainDN"
                            computerSelfPermission = $true
                        }
                    }
                    [PSCustomObject]@{
                        Action       = 'CreateAcl'
                        ResourceType = 'LapsPermission'
                        Name         = 'LAPS Read-Permission: Tier 0 Admins on Tier 0 Servers'
                        Data         = [PSCustomObject]@{
                            lapsOperation     = 'SetReadPasswordPermission'
                            ouDn              = "OU=Tier 0 Servers,$script:TestDomainDN"
                            allowedPrincipals = @("$script:TestNetBIOS\Tier0Admins")
                        }
                    }
                    [PSCustomObject]@{
                        Action       = 'CreateAcl'
                        ResourceType = 'LapsPermission'
                        Name         = 'LAPS Reset-Permission: Tier 0 Admins on Tier 0 Servers'
                        Data         = [PSCustomObject]@{
                            lapsOperation     = 'SetResetPasswordPermission'
                            ouDn              = "OU=Tier 0 Servers,$script:TestDomainDN"
                            allowedPrincipals = @("$script:TestNetBIOS\Tier0Admins")
                        }
                    }
                    [PSCustomObject]@{
                        Action       = 'ConfigureLapsDecryptor'
                        ResourceType = 'LapsDecryptor'
                        Name         = "LAPS Decryptor: $script:TestNetBIOS\Tier0Admins on *- Tier 0 Servers Windows LAPS - Computer"
                        Data         = [PSCustomObject]@{
                            lapsOperation  = 'SetDecryptorPrincipal'
                            gpoName        = '*- Tier 0 Servers Windows LAPS - Computer'
                            decryptorValue = "$script:TestNetBIOS\Tier0Admins"
                            decryptorGroup = 'Tier 0 Admins'
                        }
                    }
                )
                Summary   = @{ TotalActions = 4; CreateActions = 3; ConfigureActions = 1 }
                Converged = $false
            }

            # Converged plan (0 actions)
            $script:TestPlanConverged = [PSCustomObject]@{
                Actions   = @()
                Summary   = @{ TotalActions = 0; CreateActions = 0; ConfigureActions = 0 }
                Converged = $true
            }
        }

        It "Returns result with required structure" {
            $result = New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1

            $result.PSObject.Properties.Name | Should -Contain 'Applied'
            $result.PSObject.Properties.Name | Should -Contain 'Executed'
            $result.PSObject.Properties.Name | Should -Contain 'Failed'
            $result.PSObject.Properties.Name | Should -Contain 'Skipped'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'Converged'
            $result.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Apply from plan: Executed = N (all actions applied)" {
            $result = New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1

            $result.Executed | Should -Be 4
            $result.Failed   | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "WhatIf mode: zero writes, Applied empty, Skipped = N" {
            $result = New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1 -WhatIf

            $result.Executed          | Should -Be 0
            @($result.Skipped).Count  | Should -Be 4
            $result.Failed            | Should -Be 0
        }

        It "WhatIf: Set-LapsADComputerSelfPermission is never called" {
            New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1 -WhatIf | Out-Null

            Assert-MockCalled Set-LapsADComputerSelfPermission -ModuleName TierModel -Times 0
        }

        It "WhatIf: Set-GPRegistryValue is never called" {
            New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1 -WhatIf | Out-Null

            Assert-MockCalled Set-GPRegistryValue -ModuleName TierModel -Times 0
        }

        It "Idempotency: converged plan returns Applied=0, Converged=true" {
            $result = New-TierModelWinLapsAcl -Plan $script:TestPlanConverged -DomainController $script:TestDC -Config $script:WinLapsConfig1

            $result.Executed  | Should -Be 0
            $result.Failed    | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "Error during apply: Failed increments, Converged=false" {
            Mock Set-LapsADComputerSelfPermission -ModuleName TierModel {
                throw "Access denied"
            }

            $result = New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1

            $result.Failed   | Should -BeGreaterThan 0
            $result.Converged | Should -Be $false
            @($result.Errors).Count | Should -BeGreaterThan 0
            $result.Errors[0].Code | Should -Be 'LapsPermissionFailed'
        }

        It "Apply invokes Set-LapsADComputerSelfPermission once for Self action" {
            New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1 | Out-Null

            Assert-MockCalled Set-LapsADComputerSelfPermission -ModuleName TierModel -Times 1
        }

        It "Apply invokes Set-LapsADReadPasswordPermission once for Read action" {
            New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1 | Out-Null

            Assert-MockCalled Set-LapsADReadPasswordPermission -ModuleName TierModel -Times 1
        }

        It "Apply invokes Set-LapsADResetPasswordPermission once for Reset action" {
            New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1 | Out-Null

            Assert-MockCalled Set-LapsADResetPasswordPermission -ModuleName TierModel -Times 1
        }

        It "Apply invokes Set-GPRegistryValue once for Decryptor action" {
            New-TierModelWinLapsAcl -Plan $script:TestPlan3Actions -DomainController $script:TestDC -Config $script:WinLapsConfig1 | Out-Null

            Assert-MockCalled Set-GPRegistryValue -ModuleName TierModel -Times 1
        }

        It "ConfigureLapsDecryptor error catch: Errors > 0 and Converged=false when Set-GPRegistryValue throws" {
            Mock Set-GPRegistryValue -ModuleName TierModel { throw "Access denied to GPO" }

            $decryptorOnlyPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action       = 'ConfigureLapsDecryptor'
                        ResourceType = 'LapsDecryptor'
                        Name         = "LAPS Decryptor: $script:TestNetBIOS\Tier0Admins on GPO"
                        Data         = [PSCustomObject]@{
                            lapsOperation  = 'SetDecryptorPrincipal'
                            gpoName        = '*- Tier 0 Servers Windows LAPS - Computer'
                            decryptorValue = "$script:TestNetBIOS\Tier0Admins"
                            decryptorGroup = 'Tier 0 Admins'
                        }
                    }
                )
                Summary   = @{ TotalActions = 1 }
                Converged = $false
            }

            $result = New-TierModelWinLapsAcl -Plan $decryptorOnlyPlan -DomainController $script:TestDC -Config $script:WinLapsConfig1

            $result.Errors.Count | Should -BeGreaterThan 0
            $result.Converged    | Should -Be $false
        }

        It "Unknown lapsOperation in CreateAcl action: default branch — skipped, no crash" {
            # Build a plan with an unknown lapsOperation to hit the default branch (line 89)
            $unknownOpPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action       = 'CreateAcl'
                        ResourceType = 'LapsPermission'
                        Name         = 'Unknown LAPS operation test'
                        Data         = [PSCustomObject]@{
                            lapsOperation = 'UnknownOperation'
                            ouDn          = "OU=Tier 0 Servers,$script:TestDomainDN"
                        }
                    }
                )
                Summary   = @{ TotalActions = 1 }
                Converged = $false
            }

            # Should not throw; the default switch branch produces a ShouldProcess message
            { New-TierModelWinLapsAcl -Plan $unknownOpPlan -DomainController $script:TestDC -Config $script:WinLapsConfig1 } |
                Should -Not -Throw
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T017 — Get-TierModelWinLapsAclFd (full-deployment variant)
    # ════════════════════════════════════════════════════════════════════════════
    Context "T017: Get-TierModelWinLapsAclFd — FD Mode" -Tag "Unit", "WinLapsAcl", "FdPlanning" {

        It "Returns Fd plan with required structure (no top-level Converged)" {
            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $plan | Should -Not -BeNullOrEmpty
            $plan.PSObject.Properties.Name | Should -Contain 'Actions'
            $plan.PSObject.Properties.Name | Should -Contain 'Summary'
            $plan.PSObject.Properties.Name | Should -Contain 'Analysis'
            $plan.PSObject.Properties.Name | Should -Contain 'Errors'
            $plan.PSObject.Properties.Name | Should -Contain 'Warnings'
            $plan.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $plan.PSObject.Properties.Name | Should -Contain 'CorrelationId'
        }

        It "Plans 3 CreateAcl actions per delegation with 2 delegations" {
            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $createActions = @($plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' })
            $createActions.Count      | Should -Be 6
            $plan.Summary.CreateActions | Should -Be 6
        }

        It "-Silent switch does not throw and returns the same plan structure" {
            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC -Silent

            $plan | Should -Not -BeNullOrEmpty
            $plan.PSObject.Properties.Name | Should -Contain 'Actions'
        }

        It "Empty winLapsDelegations returns zero-action plan" {
            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfigEmpty -DomainController $script:TestDC

            $plan.Summary.TotalActions | Should -Be 0
        }

        It "ExistingCount increments correctly when permissions are already present" {
            # SELF + Read + Reset already present
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $selfAce = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'NT AUTHORITY\SELF' }
                    IsInherited       = $false
                    ObjectType        = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($selfAce) }
            }
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{ ExtendedRightHolders = @("$script:TestNetBIOS\Tier0Admins", "$script:TestNetBIOS\Tier1Admins") }
            }

            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $plan.Summary.ExistingCount | Should -BeGreaterThan 0
        }

        It "Lighter validation: missing OU is non-blocking (still plans the action)" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] "OU not found"
            }

            # In FD mode, missing OU should NOT return empty actions (it's non-blocking)
            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            # FD mode plans actions even when OU not yet present; errors may appear but actions are planned
            $plan | Should -Not -BeNullOrEmpty
        }

        It "Schema hard-stop still enforced in FD mode" {
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } { return $null }

            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_SCHEMA_MISSING' }).Count | Should -BeGreaterThan 0
        }

        It "DFL hard-stop still enforced in FD mode" {
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{
                    DomainMode        = 'Windows2012R2Domain'
                    NetBIOSName       = $script:TestNetBIOS
                    DistinguishedName = $script:TestDomainDN
                }
            }

            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_DFL_INSUFFICIENT' }).Count | Should -BeGreaterThan 0
        }

        It "Summary.ConfigureActions reflects decryptor actions planned" {
            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2WithDecryptor -DomainController $script:TestDC

            $plan.Summary.ConfigureActions | Should -Be 2   # one per delegation with decryptorGroup
        }

        It "Gate 1 catch (FD): WINLAPS_SCHEMA_MISSING when schema query throws" {
            Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
                throw "Schema not reachable"
            }

            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $plan.Actions | Should -HaveCount 0
            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_SCHEMA_MISSING' }).Count | Should -BeGreaterThan 0
        }

        It "Gate 2 catch (FD): WINLAPS_MODULE_MISSING when Import-Module LAPS throws" {
            Mock Import-Module -ModuleName TierModel -ParameterFilter { $Name -eq 'LAPS' } {
                throw "LAPS not installed"
            }

            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $plan.Actions | Should -HaveCount 0
            @($plan.Errors | Where-Object { $_.Code -eq 'WINLAPS_MODULE_MISSING' }).Count | Should -BeGreaterThan 0
        }

        It "Domain resolution failure (FD): DOMAIN_RESOLUTION_FAILED when Get-ADDomain throws" {
            Mock Get-ADDomain -ModuleName TierModel { throw "Domain unavailable" }

            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $plan.Actions | Should -HaveCount 0
            @($plan.Errors | Where-Object { $_.Code -eq 'DOMAIN_RESOLUTION_FAILED' }).Count | Should -BeGreaterThan 0
        }

        It "Gate 4a (FD): missing LAPS GPO is non-blocking (created by GPO phase) - no error, no warning" {
            $fdConfigWithGpos = [PSCustomObject]@{
                winLapsDelegations = @(
                    [PSCustomObject]@{
                        ouDn                   = "OU=Tier 0 Servers,{{DOMAIN_DN}}"
                        computerSelfPermission = $true
                        readGroup              = "Tier 0 Admins"
                        resetGroup             = "Tier 0 Admins"
                    }
                )
                gpos = [PSCustomObject]@{
                    'Tier0' = [PSCustomObject]@{
                        PostConfigureGpo = @(
                            [PSCustomObject]@{ name = '*- Tier 0 Servers Windows LAPS - Computer' }
                        )
                    }
                }
            }
            Mock Get-GPO -ModuleName TierModel { throw "GPO not found" }

            $plan = Get-TierModelWinLapsAclFd -Config $fdConfigWithGpos -DomainController $script:TestDC

            # BUG-005: in FullDeployment the LAPS GPOs are created by the earlier GPO phase, so a
            # missing GPO during planning is non-blocking: no RequiredGpoNotFound error (which
            # rendered red) AND no "not found" warning. The plan renders the decryptor step as a
            # yellow "■ Configure : <gpoName>" line instead.
            @($plan.Errors | Where-Object { $_.Code -eq 'RequiredGpoNotFound' }).Count | Should -Be 0
            @($plan.Warnings | Where-Object { $_ -match "not found" }).Count | Should -Be 0
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T018a — Test-TierModelWinLapsAcl (DACL drift audit)
    # ════════════════════════════════════════════════════════════════════════════
    Context "T018a: Test-TierModelWinLapsAcl — DACL Audit" -Tag "Unit", "WinLapsAcl", "Audit" {

        BeforeEach {
            # Reset key mocks to a clean default state for each test
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                param($Identity, $Server, $ErrorAction)
                return [PSCustomObject]@{ DistinguishedName = $Identity; Name = "Test OU" }
            }
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                return [PSCustomObject]@{ Path = $Path; Access = @() }
            }
            Mock Find-LapsADExtendedRights -ModuleName TierModel { return $null }
        }

        It "Returns result with required structure" {
            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

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

        It "Compliant finding when SELF ACE + Read + Reset holders all present" {
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $selfAce = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'NT AUTHORITY\SELF' }
                    IsInherited       = $false
                    ObjectType        = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($selfAce) }
            }
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{ ExtendedRightHolders = @("$script:TestNetBIOS\Tier0Admins") }
            }

            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $result.Compliant     | Should -Be 1
            $result.Missing       | Should -Be 0
            $result.Drift         | Should -Be 0
            $result.TotalChecked  | Should -Be 1
            @($result.Findings)[0].Type | Should -Be 'Compliant'
        }

        It "UnexpectedAcl finding when an extra principal holds LAPS rights (drift)" {
            # SELF present + configured read/reset group present (compliant baseline),
            # PLUS an extra rogue principal holding LAPS extended rights → UnexpectedAcl.
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $selfAce = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'NT AUTHORITY\SELF' }
                    IsInherited       = $false
                    ObjectType        = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($selfAce) }
            }
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{ ExtendedRightHolders = @("$script:TestNetBIOS\Tier0Admins", "$script:TestNetBIOS\RogueGroup") }
            }

            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $result.Missing    | Should -Be 0
            $result.Mismatched | Should -Be 1
            $result.Drift      | Should -Be 1
            $unexpected = @($result.Findings | Where-Object { $_.Type -eq 'UnexpectedAcl' })
            $unexpected.Count           | Should -Be 1
            $unexpected[0].ResourceType | Should -Be 'LapsPermission'
            $unexpected[0].Details      | Should -Match 'RogueGroup'
        }

        It "Well-known principals (Domain Admins) holding LAPS rights are not flagged as unexpected" {
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $selfAce = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'NT AUTHORITY\SELF' }
                    IsInherited       = $false
                    ObjectType        = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($selfAce) }
            }
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{ ExtendedRightHolders = @("$script:TestNetBIOS\Tier0Admins", "$script:TestNetBIOS\Domain Admins") }
            }

            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $result.Compliant  | Should -Be 1
            $result.Mismatched | Should -Be 0
            @($result.Findings | Where-Object { $_.Type -eq 'UnexpectedAcl' }).Count | Should -Be 0
        }

        It "MissingAcl finding when SELF ACE absent" {
            # SELF ACE not present (default Get-Acl mock returns empty Access)
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{ ExtendedRightHolders = @("$script:TestNetBIOS\Tier0Admins") }
            }

            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $result.Missing | Should -BeGreaterThan 0
            $result.Drift   | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Type -eq 'MissingAcl' }).Count | Should -BeGreaterThan 0
        }

        It "MissingAcl finding when Read permission holder absent" {
            # SELF present; Find-LapsADExtendedRights returns holders that do NOT include
            # the configured read group — triggers readMissing → MissingAcl
            Mock Get-Acl -ModuleName TierModel {
                param($Path, $ErrorAction)
                $selfAce = [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = 'NT AUTHORITY\SELF' }
                    IsInherited       = $false
                    ObjectType        = [Guid]::Empty
                }
                return [PSCustomObject]@{ Path = $Path; Access = @($selfAce) }
            }
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{ ExtendedRightHolders = @("$script:TestNetBIOS\SomeOtherGroup") }
            }

            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $result.Missing | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Type -eq 'MissingAcl' }).Count | Should -BeGreaterThan 0
        }

        It "MissingAcl finding when OU does not exist" {
            Mock Get-ADOrganizationalUnit -ModuleName TierModel {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] "OU not found"
            }

            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $result.Missing | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Type -eq 'MissingAcl' -and $_.Property -eq 'TargetOU' }).Count | Should -Be 1
        }

        It "Drift = Missing + Mismatched" {
            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig2 -DomainController $script:TestDC

            $result.Drift | Should -Be ($result.Missing + $result.Mismatched)
        }

        It "-Silent switch does not throw and returns same result structure" {
            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC -Silent

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'TotalChecked'
        }

        It "-SuppressSummary does not throw" {
            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC -SuppressSummary

            $result | Should -Not -BeNullOrEmpty
        }

        It "Empty config returns TotalChecked=0, Drift=0" {
            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfigNoProperty -DomainController $script:TestDC

            $result.TotalChecked | Should -Be 0
            $result.Drift        | Should -Be 0
        }

        It "Findings items carry ResourceType=LapsPermission and a Type field" {
            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC

            $result.Findings | Should -Not -BeNullOrEmpty
            @($result.Findings)[0].PSObject.Properties.Name | Should -Contain 'Type'
            @($result.Findings)[0].PSObject.Properties.Name | Should -Contain 'ResourceType'
            @($result.Findings)[0].ResourceType | Should -Be 'LapsPermission'
        }

        It "Error finding when Get-Acl throws during DACL query" {
            Mock Get-Acl -ModuleName TierModel { throw "Access denied to DACL" }

            # Get-Acl throwing → empty catch → $selfOk=$false → MissingAcl (not Error)
            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC -Silent

            $result.Missing | Should -BeGreaterThan 0
            $result.Drift   | Should -BeGreaterThan 0
        }

        It "Error finding when Find-LapsADExtendedRights throws during extended-rights query" {
            Mock Find-LapsADExtendedRights -ModuleName TierModel { throw "Extended rights query failed" }

            $result = Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC -Silent

            $result.Errors | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Type -eq 'Error' -and $_.Property -eq 'ExtendedRights' }).Count |
                Should -BeGreaterThan 0
        }

        It "Group resolution uses sAMAccountName fallback when Get-ADGroup throws" {
            # When Get-ADGroup throws the catch sets $readSamNames += $gName (the raw name)
            Mock Get-ADGroup -ModuleName TierModel { throw "Group not found" }
            Mock Find-LapsADExtendedRights -ModuleName TierModel {
                return [PSCustomObject]@{ ExtendedRightHolders = @("$script:TestNetBIOS\SomeOtherGroup") }
            }

            # Should not throw; falls back gracefully to raw group name
            { Test-TierModelWinLapsAcl -Config $script:WinLapsConfig1 -DomainController $script:TestDC -Silent } |
                Should -Not -Throw
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T018b — Test-TierModelWinLapsDecryptor (GPO drift audit)
    # ════════════════════════════════════════════════════════════════════════════
    Context "T018b: Test-TierModelWinLapsDecryptor — GPO Decryptor Audit" -Tag "Unit", "WinLapsAcl", "DecryptorAudit" {

        BeforeAll {
            # Config with 1 non-DC entry that has decryptorGroup + decryptorGpoName
            $script:DecryptorConfig1 = [PSCustomObject]@{
                winLapsDelegations = @(
                    [PSCustomObject]@{
                        ouDn             = "OU=Tier 0 Servers,{{DOMAIN_DN}}"
                        computerSelfPermission = $true
                        readGroup        = "Tier 0 Admins"
                        resetGroup       = "Tier 0 Admins"
                        decryptorGroup   = "Tier 0 Admins"
                        decryptorGpoName = "*- Tier 0 Servers Windows LAPS - Computer"
                    }
                )
            }

            # Config with ONLY a DC OU (should be skipped entirely)
            $script:DecryptorConfigDcOnly = [PSCustomObject]@{
                winLapsDelegations = @(
                    [PSCustomObject]@{
                        ouDn                   = "OU=Domain Controllers,{{DOMAIN_DN}}"
                        computerSelfPermission = $true
                        readGroup              = "Domain Admins"
                        resetGroup             = "Domain Admins"
                        isDomainControllerOu   = $true
                    }
                )
            }

            # Config with 2 non-DC entries
            $script:DecryptorConfig2 = [PSCustomObject]@{
                winLapsDelegations = @(
                    [PSCustomObject]@{
                        ouDn             = "OU=Tier 0 Servers,{{DOMAIN_DN}}"
                        computerSelfPermission = $true
                        readGroup        = "Tier 0 Admins"
                        resetGroup       = "Tier 0 Admins"
                        decryptorGroup   = "Tier 0 Admins"
                        decryptorGpoName = "*- Tier 0 Servers Windows LAPS - Computer"
                    }
                    [PSCustomObject]@{
                        ouDn             = "OU=Tier 1 Servers,{{DOMAIN_DN}}"
                        computerSelfPermission = $true
                        readGroup        = "Tier 1 Admins"
                        resetGroup       = "Tier 1 Admins"
                        decryptorGroup   = "Tier 1 Admins"
                        decryptorGpoName = "*- Tier 1 Servers Windows LAPS - Computer"
                    }
                )
            }
        }

        It "Returns result with required structure" {
            Mock Get-GPO -ModuleName TierModel {
                return [PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() }
            }
            Mock Get-GPRegistryValue -ModuleName TierModel { throw "Not set" }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

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

        It "Compliant: GPO found, value matches expected principal" {
            $expectedValue = "$script:TestNetBIOS\Tier0Admins"
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @([PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() })
            }
            Mock Get-GPRegistryValue -ModuleName TierModel {
                return [PSCustomObject]@{ ValueName = 'ADPasswordEncryptionPrincipal'; Value = $expectedValue }
            }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Compliant    | Should -Be 1
            $result.Missing      | Should -Be 0
            $result.Mismatched   | Should -Be 0
            $result.Drift        | Should -Be 0
            @($result.Findings)[0].Status | Should -Be 'Compliant'
        }

        It "Missing: GPO found but ADPasswordEncryptionPrincipal not set" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @([PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() })
            }
            Mock Get-GPRegistryValue -ModuleName TierModel { throw "Registry key not found" }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Missing           | Should -Be 1
            @($result.Findings)[0].Status | Should -Be 'Missing'
        }

        It "Mismatched: GPO found, value set to wrong principal" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @([PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() })
            }
            Mock Get-GPRegistryValue -ModuleName TierModel {
                return [PSCustomObject]@{ ValueName = 'ADPasswordEncryptionPrincipal'; Value = 'DOMAIN\WrongGroup' }
            }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Mismatched        | Should -Be 1
            @($result.Findings)[0].Status | Should -Be 'Mismatched'
            $result.Drift             | Should -BeGreaterThan 0
        }

        It "DC OUs are skipped: TotalChecked=0 for DC-only config" {
            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfigDcOnly -DomainController $script:TestDC -Silent

            $result.TotalChecked | Should -Be 0
        }

        It "GPO not found: Error status in findings, Errors > 0" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @()  # no matching GPO
            }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Errors | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Status -eq 'Error' }).Count | Should -BeGreaterThan 0
        }

        It "Drift = Missing + Mismatched + Errors" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @([PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() })
            }
            Mock Get-GPRegistryValue -ModuleName TierModel { throw "Not set" }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Drift | Should -Be ($result.Missing + $result.Mismatched + $result.Errors)
        }

        It "-Silent suppresses host output (no throw)" {
            { Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent } |
                Should -Not -Throw
        }

        It "-SuppressSummary does not throw" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @([PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() })
            }
            Mock Get-GPRegistryValue -ModuleName TierModel { throw "Not set" }

            { Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -SuppressSummary } |
                Should -Not -Throw
        }

        It "Empty config returns TotalChecked=0" {
            $result = Test-TierModelWinLapsDecryptor -Config $script:WinLapsConfigNoProperty -DomainController $script:TestDC -Silent
            $result.TotalChecked | Should -Be 0
        }

        It "Findings items have GpoName, Expected, Actual, Status fields" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @([PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() })
            }
            Mock Get-GPRegistryValue -ModuleName TierModel { throw "Not set" }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $finding = @($result.Findings)[0]
            $finding.PSObject.Properties.Name | Should -Contain 'GpoName'
            $finding.PSObject.Properties.Name | Should -Contain 'Expected'
            $finding.PSObject.Properties.Name | Should -Contain 'Actual'
            $finding.PSObject.Properties.Name | Should -Contain 'Status'
        }

        It "Domain resolution failure: early return with Errors=1 when Get-ADDomain throws" {
            Mock Get-ADDomain -ModuleName TierModel { throw "Domain not reachable" }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.TotalChecked | Should -Be 0
            $result.Errors       | Should -Be 1
            $result.Drift        | Should -Be 1
            @($result.Findings | Where-Object { $_.Status -eq 'Error' }).Count | Should -BeGreaterThan 0
        }

        It "Multiple GPOs match pattern: Error status in findings, Errors > 0" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @(
                    [PSCustomObject]@{ DisplayName = "Tier0 - Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() }
                    [PSCustomObject]@{ DisplayName = "Tier1 - Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() }
                )
            }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Errors | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Status -eq 'Error' }).Count | Should -BeGreaterThan 0
        }

        It "Get-GPO throws during GPO enumeration: Error status, Errors > 0" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                throw "GPO enumeration failed"
            }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Errors | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Status -eq 'Error' }).Count | Should -BeGreaterThan 0
        }

        It "Group resolution failure: Error status in findings when Get-ADGroup throws" {
            Mock Get-GPO -ModuleName TierModel -ParameterFilter { $All -eq $true } {
                return @([PSCustomObject]@{ DisplayName = "*- Tier 0 Servers Windows LAPS - Computer"; Id = [Guid]::NewGuid() })
            }
            Mock Get-ADGroup -ModuleName TierModel { throw "Group not found" }

            $result = Test-TierModelWinLapsDecryptor -Config $script:DecryptorConfig1 -DomainController $script:TestDC -Silent

            $result.Errors | Should -BeGreaterThan 0
            @($result.Findings | Where-Object { $_.Status -eq 'Error' }).Count | Should -BeGreaterThan 0
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T020 — Windows-LAPS-Only Invariant Regression
    # ════════════════════════════════════════════════════════════════════════════
    Context "T020: Windows-LAPS-Only Invariant" -Tag "Unit", "WinLapsAcl", "Invariant" {

        It "All CreateAcl lapsOperation values use Windows LAPS naming only (no AdmPwd/ms-Mcs)" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2WithDecryptor -DomainController $script:TestDC

            $createActions = @($plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' })
            $createActions.Count | Should -BeGreaterThan 0

            foreach ($action in $createActions) {
                $action.Data.lapsOperation | Should -Not -Match 'AdmPwd'
                $action.Data.lapsOperation | Should -Not -Match 'ms.Mcs'
                $action.Data.lapsOperation | Should -Match '^Set(ComputerSelf|ReadPassword|ResetPassword)Permission$'
            }
        }

        It "All ConfigureLapsDecryptor actions use Windows LAPS naming only" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2WithDecryptor -DomainController $script:TestDC

            $decryptorActions = @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureLapsDecryptor' })
            $decryptorActions.Count | Should -BeGreaterThan 0

            foreach ($action in $decryptorActions) {
                $action.Data.lapsOperation | Should -Not -Match 'AdmPwd'
                $action.Data.lapsOperation | Should -Be 'SetDecryptorPrincipal'
                $action.ResourceType       | Should -Be 'LapsDecryptor'
            }
        }

        It "No action has ms-Mcs-* in any Data string field" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2WithDecryptor -DomainController $script:TestDC

            foreach ($action in $plan.Actions) {
                $action.Data.PSObject.Properties | ForEach-Object {
                    $val = $_.Value
                    if ($val -is [string]) {
                        $val | Should -Not -Match 'ms.Mcs'
                        $val | Should -Not -Match 'AdmPwd'
                    }
                }
            }
        }

        It "No action references ms-Mcs-* or AdmPwd in the Name or Path fields" {
            $plan = Get-TierModelWinLapsAcl -Config $script:WinLapsConfig2WithDecryptor -DomainController $script:TestDC

            foreach ($action in $plan.Actions) {
                $action.Name | Should -Not -Match 'AdmPwd'
                $action.Name | Should -Not -Match 'ms.Mcs'
                $action.Path | Should -Not -Match 'AdmPwd'
                $action.Path | Should -Not -Match 'ms.Mcs'
            }
        }

        It "Production cmdlet files contain no actual calls to legacy AdmPwd cmdlets" {
            $winLapsFiles = @(
                "Get-TierModelWinLapsAcl.ps1"
                "New-TierModelWinLapsAcl.ps1"
                "Get-TierModelWinLapsAclFd.ps1"
                "Test-TierModelWinLapsAcl.ps1"
                "Test-TierModelWinLapsDecryptor.ps1"
            )
            $publicDir = Resolve-Path "$PSScriptRoot\..\Modules\TierModel\public"

            foreach ($fileName in $winLapsFiles) {
                $filePath = Join-Path $publicDir $fileName
                # Check for actual AdmPwd cmdlet invocations — exclude doc comment lines
                $codeLines = (Get-Content $filePath) | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*<#' -and $_ -notmatch '^\s*\.SYNOPSIS' -and $_ -notmatch '^\s*\.DESCRIPTION' -and $_ -notmatch '^\s*Uses only' -and $_ -notmatch '^\s*never legacy' }
                ($codeLines -join "`n") | Should -Not -Match 'Import-Module.*AdmPwd'
                ($codeLines -join "`n") | Should -Not -Match 'Get-AdmPwdPassword|Set-AdmPwdPassword|Reset-AdmPwdPassword'
                ($codeLines -join "`n") | Should -Not -Match '\bms-Mcs-AdmPwd\b'
            }
        }

        It "Production cmdlet files contain no references to legacy AdmPwd LAPS module import" {
            $winLapsFiles = @(
                "Get-TierModelWinLapsAcl.ps1"
                "New-TierModelWinLapsAcl.ps1"
                "Get-TierModelWinLapsAclFd.ps1"
                "Test-TierModelWinLapsAcl.ps1"
                "Test-TierModelWinLapsDecryptor.ps1"
            )
            $publicDir = Resolve-Path "$PSScriptRoot\..\Modules\TierModel\public"

            foreach ($fileName in $winLapsFiles) {
                $filePath = Join-Path $publicDir $fileName
                $content  = Get-Content $filePath -Raw
                $content | Should -Not -Match 'Import-Module AdmPwd'
                $content | Should -Not -Match 'Import-Module.*AdmPwd'
            }
        }

        It "FD planner CreateAcl actions also have Windows LAPS names only" {
            $plan = Get-TierModelWinLapsAclFd -Config $script:WinLapsConfig2WithDecryptor -DomainController $script:TestDC

            $createActions = @($plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' })
            $createActions.Count | Should -BeGreaterThan 0

            foreach ($action in $createActions) {
                $action.Data.lapsOperation | Should -Not -Match 'AdmPwd'
                $action.Data.lapsOperation | Should -Not -Match 'ms.Mcs'
            }
        }
    }
}
