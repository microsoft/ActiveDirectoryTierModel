#Requires -Modules Pester
<#
.SYNOPSIS
Unit tests for TierModel Authentication Silo DEPLOY cmdlets (-IncludeAuthSilos).

.DESCRIPTION
Tests for the auth-silo deploy pipeline (lab-validated on TierLab-DC01):
  - Build-TierModelAuthSddl
  - Compare-TierModelAuthSddl
  - Get-TierModelAuthPolicy
  - Get-TierModelAuthSilo
  - Get-TierModelAuthPolicyFd         (create-once model: deferred SDDL)
  - Get-TierModelAuthSiloFd           (create-once model)
  - Get-TierModelAuthSiloMembershipFd (read-only membership planner)
  - New-TierModelAuthPolicy           (execution-time SID resolution)
  - New-TierModelAuthSilo
  - Set-TierModelAuthSiloMembership   (computer-only, -OnlyForSilos)
  - Test-TierModelAuthSiloPrerequisite
  - Test-TierModelAuthPolicy
  - Test-TierModelAuthSilo

All AD cmdlets are mocked — no live domain required.

Create-once model: existing policies/silos are NEVER modified by deploy.
SDDL is deferred to execution time; plan actions carry ResolvedSddl=$null + Data.

.NOTES
Tags: Unit, AuthSilo
#>

Describe "Authentication Silo Deploy Operations" -Tag "Unit", "AuthSilo" {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..\modules\TierModel\TierModel.psd1'
        Import-Module $ModulePath -Force

        InModuleScope TierModel {
            $script:CorrelationId = 'test-authsilo-' + (New-Guid).ToString()
        }

        $script:TestDC     = 'DC01.test.local'
        $script:DomainSid  = 'S-1-5-21-111-222-333'

        # ── Config object matching the 4-policy / 4-silo production JSON ─────────
        # User membership (memberAccountGroups) and exempt accounts have been removed
        # from the schema. Silos govern COMPUTERS only (memberComputerGroups).
        $script:AuthSiloConfig = [PSCustomObject]@{
            authenticationPolicies = @(
                [PSCustomObject]@{
                    name        = '*- Tier 0 Admins Authentication Policy'
                    description = 'Authentication Policy for Tier 0 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 0 origin devices, and lowers the Kerberos TGT lifetime to 2 hours (120 minutes).'
                    userTGTLifetimeMinutes = 120
                    allowedToAuthenticateFromDeviceGroups = @('Domain Controllers','Read-only Domain Controllers','Tier0MemberServers','Tier0PAWDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 1 Admins Authentication Policy'
                    description = 'Authentication Policy for Tier 1 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 1 origin devices, and lowers the Kerberos TGT lifetime to 4 hours (240 minutes).'
                    userTGTLifetimeMinutes = 240
                    allowedToAuthenticateFromDeviceGroups = @('Tier1MemberServers','Tier1PAWDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 2 Admins Authentication Policy'
                    description = 'Authentication Policy for Tier 2 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 2 PAW devices, and lowers the Kerberos TGT lifetime to 6 hours (360 minutes).'
                    userTGTLifetimeMinutes = 360
                    allowedToAuthenticateFromDeviceGroups = @('Tier2PAWDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 2 EUD Authentication Policy'
                    description = 'Authentication Policy for Tier 2 End-User Device local device operators. Restricts Kerberos TGT issuance to approved Tier 2 EUD origin devices; the Kerberos TGT lifetime is not lowered here, so EUD accounts inherit the domain-default lifetime (about 10 hours).'
                    userTGTLifetimeMinutes = $null
                    allowedToAuthenticateFromDeviceGroups = @('Tier2EUDDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
            )
            authenticationSilos = @(
                [PSCustomObject]@{
                    name        = '*- Tier 0 Admins Authentication Silo'
                    description = 'Authentication Policy Silo for Tier 0 administrators, operators, server operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 0 devices.'
                    policy      = '*- Tier 0 Admins Authentication Policy'
                    memberComputerGroups = @('Domain Controllers','Read-only Domain Controllers','Tier0MemberServers','Tier0PAWDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 1 Admins Authentication Silo'
                    description = 'Authentication Policy Silo for Tier 1 administrators, operators, server operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 1 devices.'
                    policy      = '*- Tier 1 Admins Authentication Policy'
                    memberComputerGroups = @('Tier1MemberServers','Tier1PAWDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 2 Admins Authentication Silo'
                    description = 'Authentication Policy Silo for Tier 2 administrators, operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 2 PAW devices.'
                    policy      = '*- Tier 2 Admins Authentication Policy'
                    memberComputerGroups = @('Tier2PAWDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 2 EUD Authentication Silo'
                    description = 'Authentication Policy Silo for Tier 2 End-User Device local device operators. Silo members may only obtain Kerberos TGTs from approved Tier 2 EUD devices.'
                    policy      = '*- Tier 2 EUD Authentication Policy'
                    memberComputerGroups = @('Tier2EUDDevices')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
            )
        }

        # Config with no auth-silo properties (simulates config without tiermodel-authsilos.json)
        $script:ConfigEmpty = [PSCustomObject]@{
            authenticationPolicies = $null
            authenticationSilos    = $null
        }

        # Base module-scope mocks active for all contexts
        Mock Write-TierModelLog  -ModuleName TierModel { }
        Mock Write-Host          -ModuleName TierModel { }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Build-TierModelAuthSddl — pure SDDL string construction, no AD
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Build-TierModelAuthSddl — SDDL string construction" {

        It "emits the canonical O:SYG:SYD prefix" {
            $result = Build-TierModelAuthSddl -DeviceSids @('S-1-5-21-111-222-333-1001')
            $result | Should -Match '^O:SYG:SYD:'
        }

        It "single SID — produces exact canonical SDDL format" {
            $result = Build-TierModelAuthSddl -DeviceSids @('S-1-5-21-111-222-333-1001')
            $result | Should -Be 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
        }

        It "multiple SIDs — all SID tokens appear in the output" {
            $sids   = @('S-1-5-21-1-2-3-1001','S-1-5-21-1-2-3-1002','S-1-5-21-1-2-3-1003')
            $result = Build-TierModelAuthSddl -DeviceSids $sids
            foreach ($sid in $sids) {
                $result | Should -Match ([regex]::Escape("SID($sid)"))
            }
        }

        It "always uses Member_of_any (OR-logic) — never Member_of_each (AND-logic)" {
            $result = Build-TierModelAuthSddl -DeviceSids @('S-1-5-21-1-2-3-1001','S-1-5-21-1-2-3-1002')
            $result | Should -Match 'Member_of_any'
            $result | Should -Not -Match 'Member_of_each'
        }

        It "two SIDs — both SID() tokens are present" {
            $result = Build-TierModelAuthSddl -DeviceSids @('S-1-5-21-1-2-3-1001','S-1-5-21-1-2-3-1002')
            $result | Should -Match 'SID\(S-1-5-21-1-2-3-1001\)'
            $result | Should -Match 'SID\(S-1-5-21-1-2-3-1002\)'
        }

        It "output type is string" {
            $result = Build-TierModelAuthSddl -DeviceSids @('S-1-5-21-1-2-3-500')
            $result | Should -BeOfType [string]
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Compare-TierModelAuthSddl — semantic comparison, alias expansion
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Compare-TierModelAuthSddl — semantic SDDL comparison" {

        It "identical SDDLs — Equal=true, Reason=null" {
            $sddl   = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
            $result = Compare-TierModelAuthSddl -DesiredSddl $sddl -ExistingSddl $sddl -DomainController $script:TestDC
            $result.Equal  | Should -BeTrue
            $result.Reason | Should -BeNullOrEmpty
        }

        It "DD alias in existing resolves to full SID — Equal=true" {
            # AD may store Domain Controllers (S-1-5-21-...-516) as the alias 'DD'
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-516)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(DD)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC
            $result.Equal | Should -BeTrue
        }

        It "reordered SIDs — Equal=true (order-insensitive set comparison)" {
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001), SID(S-1-5-21-111-222-333-1002)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1002), SID(S-1-5-21-111-222-333-1001)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC
            $result.Equal | Should -BeTrue
        }

        It "different SID sets — Equal=false with a non-empty Reason" {
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-9999)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC
            $result.Equal  | Should -BeFalse
            $result.Reason | Should -Not -BeNullOrEmpty
        }

        It "existing uses Member_of_each (AND-logic) — Equal=false" {
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any  {SID(S-1-5-21-111-222-333-1001)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_each {SID(S-1-5-21-111-222-333-1001)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC
            $result.Equal  | Should -BeFalse
            $result.Reason | Should -Match 'Member_of_any'
        }

        It "empty existing SDDL — Equal=false with a non-empty Reason" {
            $desired = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
            $result  = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl '' -DomainController $script:TestDC
            $result.Equal  | Should -BeFalse
            $result.Reason | Should -Not -BeNullOrEmpty
        }

        It "RequireSubset — desired SIDs all present, extra SIDs in existing — Equal=true, ExtraSids populated" {
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001), SID(S-1-5-21-111-222-333-9999)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC -RequireSubset
            $result.Equal         | Should -BeTrue
            $result.Reason        | Should -BeNullOrEmpty
            $result.ExtraSids     | Should -Not -BeNullOrEmpty
            $result.ExtraSids     | Should -Contain 'S-1-5-21-111-222-333-9999'
        }

        It "RequireSubset — mandatory SID missing from existing — Equal=false" {
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001), SID(S-1-5-21-111-222-333-1002)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC -RequireSubset
            $result.Equal  | Should -BeFalse
            $result.Reason | Should -Not -BeNullOrEmpty
        }

        It "RequireSubset — exact match — Equal=true, ExtraSids empty" {
            $sddl   = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
            $result = Compare-TierModelAuthSddl -DesiredSddl $sddl -ExistingSddl $sddl -DomainController $script:TestDC -RequireSubset
            $result.Equal         | Should -BeTrue
            @($result.ExtraSids).Count | Should -Be 0
        }

        It "domain SID fallback via Get-ADDomain when desired SDDL has no domain SID" {
            # Desired SDDL uses only well-known SID aliases, so domain SID must be fetched via Get-ADDomain
            Mock Get-ADDomain -ModuleName TierModel {
                [PSCustomObject]@{ DomainSID = [PSCustomObject]@{ Value = 'S-1-5-21-111-222-333' } }
            }
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-516)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(DD)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC
            $result.Equal | Should -BeTrue
        }

        It "exact mode — SID count differs — Equal=false with count-differ reason" {
            $desired  = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001), SID(S-1-5-21-111-222-333-1002)}))'
            $existing = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1001)}))'
            $result   = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController $script:TestDC
            $result.Equal  | Should -BeFalse
            $result.Reason | Should -Match 'count|differ'
        }

        It "whitespace fallback when Get-ADDomain fails — identical SDDLs Equal=true" {
            Mock Get-ADDomain -ModuleName TierModel { throw "AD connection failed" }
            # No domain SID pattern in these SDDLs; Get-ADDomain is the fallback; both match → Equal
            $sddl   = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-1-0)}))'
            $result = Compare-TierModelAuthSddl -DesiredSddl $sddl -ExistingSddl $sddl -DomainController $script:TestDC
            $result.Equal | Should -BeTrue
        }
    }
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuthPolicy — configuration loading" {

        It "returns exactly 4 policies" {
            @(Get-TierModelAuthPolicy -Config $script:AuthSiloConfig).Count | Should -Be 4
        }

        It "all four policy names are present" {
            $names = @(Get-TierModelAuthPolicy -Config $script:AuthSiloConfig) | ForEach-Object { $_.name }
            $names | Should -Contain '*- Tier 0 Admins Authentication Policy'
            $names | Should -Contain '*- Tier 1 Admins Authentication Policy'
            $names | Should -Contain '*- Tier 2 Admins Authentication Policy'
            $names | Should -Contain '*- Tier 2 EUD Authentication Policy'
        }

        It "Tier 0 policy TGT lifetime is 120 minutes" {
            $policy = @(Get-TierModelAuthPolicy -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*Tier 0 Admins*' }
            $policy.userTGTLifetimeMinutes | Should -Be 120
        }

        It "Tier 1 policy TGT lifetime is 240 minutes" {
            $policy = @(Get-TierModelAuthPolicy -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*Tier 1 Admins*' }
            $policy.userTGTLifetimeMinutes | Should -Be 240
        }

        It "Tier 2 Admins policy TGT lifetime is 360 minutes" {
            $policy = @(Get-TierModelAuthPolicy -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*Tier 2 Admins*' }
            $policy.userTGTLifetimeMinutes | Should -Be 360
        }

        It "Tier 2 EUD policy TGT lifetime is null (domain default, no custom lifetime)" {
            $policy = @(Get-TierModelAuthPolicy -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*EUD*' }
            $policy.userTGTLifetimeMinutes | Should -BeNullOrEmpty
        }

        It "Tier 0 device groups include Domain Controllers and Tier0PAWDevices" {
            $policy = @(Get-TierModelAuthPolicy -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*Tier 0 Admins*' }
            $policy.allowedToAuthenticateFromDeviceGroups | Should -Contain 'Domain Controllers'
            $policy.allowedToAuthenticateFromDeviceGroups | Should -Contain 'Tier0PAWDevices'
        }

        It "returns empty array when authenticationPolicies is absent from config" {
            @(Get-TierModelAuthPolicy -Config $script:ConfigEmpty).Count | Should -Be 0
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuthSilo — config parsing (no AD)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuthSilo — configuration loading" {

        It "returns exactly 4 silos" {
            @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig).Count | Should -Be 4
        }

        It "all four silo names are present" {
            $names = @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig) | ForEach-Object { $_.name }
            $names | Should -Contain '*- Tier 0 Admins Authentication Silo'
            $names | Should -Contain '*- Tier 1 Admins Authentication Silo'
            $names | Should -Contain '*- Tier 2 Admins Authentication Silo'
            $names | Should -Contain '*- Tier 2 EUD Authentication Silo'
        }

        It "Tier 0 silo references the Tier 0 policy (1:1 design)" {
            $silo = @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*Tier 0 Admins*' }
            $silo.policy | Should -Be '*- Tier 0 Admins Authentication Policy'
        }

        It "Tier 2 EUD silo references the EUD policy" {
            $silo = @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*EUD*' }
            $silo.policy | Should -Be '*- Tier 2 EUD Authentication Policy'
        }

        It "Tier 0 silo member computer groups include Domain Controllers and Tier0PAWDevices" {
            $silo = @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*Tier 0 Admins*' }
            $silo.memberComputerGroups | Should -Contain 'Domain Controllers'
            $silo.memberComputerGroups | Should -Contain 'Tier0PAWDevices'
        }

        It "Tier 2 EUD silo has exactly one member computer group (Tier2EUDDevices)" {
            $silo = @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*EUD*' }
            @($silo.memberComputerGroups).Count | Should -Be 1
            $silo.memberComputerGroups         | Should -Contain 'Tier2EUDDevices'
        }

        It "returns empty array when authenticationSilos is absent from config" {
            @(Get-TierModelAuthSilo -Config $script:ConfigEmpty).Count | Should -Be 0
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuthPolicyFd — deployment planning (create-once model)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuthPolicyFd — deployment planning" {

        BeforeAll {
            # Default: policy absent from AD (first-deploy scenario)
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel { throw "Policy not found" }
        }

        It "emits one CreateAuthPolicy action per policy absent from AD" {
            $result = Get-TierModelAuthPolicyFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            @($result.Actions | Where-Object { $_.Action -eq 'CreateAuthPolicy' }).Count | Should -Be 4
        }

        It "CreateAuthPolicy action has ResolvedSddl=null — SDDL is deferred to execution time" {
            $result = Get-TierModelAuthPolicyFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $action = $result.Actions | Where-Object { $_.Name -like '*Tier 0*' } | Select-Object -First 1
            $action.ResolvedSddl | Should -BeNullOrEmpty
        }

        It "CreateAuthPolicy action Data carries the policy config (device groups present)" {
            $result = Get-TierModelAuthPolicyFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $action = $result.Actions | Where-Object { $_.Name -like '*Tier 0*' } | Select-Object -First 1
            $action.Data | Should -Not -BeNullOrEmpty
            $action.Data.allowedToAuthenticateFromDeviceGroups | Should -Contain 'Domain Controllers'
        }

        It "create-once — existing policy produces AlreadyExist=1 and zero actions" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = '*- Tier 0 Admins Authentication Policy'
                    DistinguishedName = 'CN=*- Tier 0 Admins Authentication Policy,CN=AuthN Policies,CN=Configuration,DC=test,DC=local'
                }
            }
            $singleCfg = [PSCustomObject]@{ authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies[0]) }
            $result = Get-TierModelAuthPolicyFd -Config $singleCfg -DomainController $script:TestDC
            @($result.Actions).Count     | Should -Be 0
            $result.Summary.AlreadyExist | Should -Be 1
        }

        It "create-once — all 4 policies existing produces AlreadyExist=4 and zero actions" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                param($Identity)
                [PSCustomObject]@{ Name = "$Identity"; DistinguishedName = "CN=$Identity,CN=AuthN Policies,CN=Configuration,DC=test,DC=local" }
            }
            $result = Get-TierModelAuthPolicyFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            @($result.Actions).Count     | Should -Be 0
            $result.Summary.AlreadyExist | Should -Be 4
        }

        It "empty config returns zero actions" {
            $result = Get-TierModelAuthPolicyFd -Config $script:ConfigEmpty -DomainController $script:TestDC
            @($result.Actions).Count | Should -Be 0
        }

        It "result carries required envelope properties" {
            $result = Get-TierModelAuthPolicyFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            foreach ($p in @('Actions','Summary','Warnings','Errors','DurationMs','CorrelationId')) {
                $result.PSObject.Properties.Name | Should -Contain $p
            }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuthSiloFd — deployment planning (mock AD)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuthSiloFd — deployment planning" {

        BeforeAll {
            # Default: silo absent from AD; policy absent from AD (first-deploy scenario)
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel { throw "Silo not found" }
            Mock Get-ADAuthenticationPolicy     -ModuleName TierModel { return $null }
        }

        It "emits one CreateAuthSilo action per silo absent from AD" {
            $result = Get-TierModelAuthSiloFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            @($result.Actions | Where-Object { $_.Action -eq 'CreateAuthSilo' }).Count | Should -Be 4
        }

        It "CreateAuthSilo action carries the correct PolicyName" {
            $result = Get-TierModelAuthSiloFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $t0 = $result.Actions | Where-Object { $_.Name -like '*Tier 0*' } | Select-Object -First 1
            $t0.PolicyName | Should -Be '*- Tier 0 Admins Authentication Policy'
        }

        It "policy pending creation in same run is NOT an error (absent from AD is expected)" {
            # Policy not yet written to AD — this is the normal first-deploy scenario
            Mock Get-ADAuthenticationPolicy     -ModuleName TierModel { return $null }
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel { throw "Silo not found" }
            $result = Get-TierModelAuthSiloFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $result.Errors.Count | Should -Be 0
        }

        It "error emitted when referenced policy is not in config at all" {
            $badCfg = [PSCustomObject]@{
                authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies)
                authenticationSilos    = @(
                    [PSCustomObject]@{
                        name        = 'Orphan Silo'
                        description = 'References a non-existent policy'
                        policy      = 'Non-Existent Policy Name'
                        memberComputerGroups = @()
                        memberAccountGroups  = @()
                    }
                )
            }
            $result = Get-TierModelAuthSiloFd -Config $badCfg -DomainController $script:TestDC
            $result.Errors.Count | Should -BeGreaterThan 0
            ($result.Errors | Where-Object { $_.Code -eq 'ReferencedPolicyNotInConfig' }) | Should -Not -BeNullOrEmpty
        }

        It "AlreadyConverged — zero actions and AlreadyExist=1 when existing silo matches" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name                         = '*- Tier 0 Admins Authentication Silo'
                    Description                  = 'Authentication Policy Silo for Tier 0 administrators, operators, server operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 0 devices.'
                    Enforce                      = $false
                    ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = '*- Tier 0 Admins Authentication Policy'
                    ComputerAuthenticationPolicy = '*- Tier 0 Admins Authentication Policy'
                    ServiceAuthenticationPolicy  = '*- Tier 0 Admins Authentication Policy'
                }
            }
            $singleCfg = [PSCustomObject]@{
                authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies)
                authenticationSilos    = @($script:AuthSiloConfig.authenticationSilos[0])
            }
            $result = Get-TierModelAuthSiloFd -Config $singleCfg -DomainController $script:TestDC
            @($result.Actions).Count    | Should -Be 0
            $result.Summary.AlreadyExist | Should -Be 1
        }

        It "create-once — all 4 silos existing produces AlreadyExist=4 and zero actions" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                param($Identity)
                [PSCustomObject]@{ Name = "$Identity"; DistinguishedName = "CN=$Identity,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=test,DC=local" }
            }
            $result = Get-TierModelAuthSiloFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            @($result.Actions).Count     | Should -Be 0
            $result.Summary.AlreadyExist | Should -Be 4
        }

        It "CreateAuthSilo action carries PolicyDn=null — resolved at execution time" {
            $result = Get-TierModelAuthSiloFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $action = $result.Actions | Where-Object { $_.Name -like '*Tier 0*' } | Select-Object -First 1
            $action.PolicyDn | Should -BeNullOrEmpty
        }

        It "empty config returns zero actions" {
            $result = Get-TierModelAuthSiloFd -Config $script:ConfigEmpty -DomainController $script:TestDC
            @($result.Actions).Count | Should -Be 0
        }

        It "result carries required envelope properties" {
            $result = Get-TierModelAuthSiloFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            foreach ($p in @('Actions','Summary','Warnings','Errors','DurationMs','CorrelationId')) {
                $result.PSObject.Properties.Name | Should -Contain $p
            }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # New-TierModelAuthPolicy — execution (create-once, deferred SDDL)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "New-TierModelAuthPolicy — execution" {

        BeforeAll {
            Mock New-ADAuthenticationPolicy -ModuleName TierModel {
                param($Name, $Description, $UserAllowedToAuthenticateFrom,
                      $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm,
                      $UserTGTLifetimeMins)
                [PSCustomObject]@{
                    Name = $Name
                    DistinguishedName = "CN=$Name,CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=test,DC=local"
                }
            }
            Mock Set-ADAuthenticationPolicy -ModuleName TierModel { }
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                param($Identity)
                [PSCustomObject]@{
                    Name = "$Identity"
                    DistinguishedName = "CN=$Identity,CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=test,DC=local"
                }
            }
            Mock Set-ADObject          -ModuleName TierModel { }
            Mock Resolve-TierModelPrincipalSid -ModuleName TierModel {
                [PSCustomObject]@{ Success = $true; Sid = 'S-1-5-21-111-222-333-1234'; Error = $null }
            }
            Mock Build-TierModelAuthSddl -ModuleName TierModel {
                'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234)}))'
            }

            # Helper: plan with ResolvedSddl=$null and Data (create-once default)
            function NewAuthPolicyPlan {
                param(
                    [string]$Name = 'Test T0 Policy',
                    [object]$TGT  = 120,
                    [string]$ResolvedSddl = $null
                )
                [PSCustomObject]@{
                    Actions = @(
                        [PSCustomObject]@{
                            Action             = 'CreateAuthPolicy'
                            Name               = $Name
                            Description        = 'Test description'
                            TGTLifetimeMinutes = $TGT
                            ResolvedSddl       = $ResolvedSddl
                            Data               = [PSCustomObject]@{
                                allowedToAuthenticateFromDeviceGroups = @('DeviceGroup1')
                            }
                        }
                    )
                }
            }
        }

        It "calls New-ADAuthenticationPolicy for a CreateAuthPolicy action" {
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan) -DomainController $script:TestDC
            Should -Invoke New-ADAuthenticationPolicy -ModuleName TierModel -Times 1
            $result.Applied.Count         | Should -Be 1
            $result.Applied[0].Action     | Should -Be 'CreateAuthPolicy'
        }

        It "always creates in audit mode — Enforce=false is splatted to New-ADAuthenticationPolicy" {
            InModuleScope TierModel {
                $script:NewPolicyCapturedEnforce = $null
                Mock New-ADAuthenticationPolicy {
                    param($Name, $Enforce)
                    $script:NewPolicyCapturedEnforce = $Enforce
                    [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=test" }
                }
            }
            New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan) -DomainController $script:TestDC
            InModuleScope TierModel { $script:NewPolicyCapturedEnforce | Should -BeFalse }
        }

        It "TGT lifetime is passed to New-ADAuthenticationPolicy when config value is non-null" {
            InModuleScope TierModel {
                $script:NewPolicyCapturedTGT = -1
                Mock New-ADAuthenticationPolicy {
                    param($Name, $UserTGTLifetimeMins)
                    $script:NewPolicyCapturedTGT = $UserTGTLifetimeMins
                    [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=test" }
                }
            }
            New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan -TGT 240) -DomainController $script:TestDC
            InModuleScope TierModel { $script:NewPolicyCapturedTGT | Should -Be 240 }
        }

        It "TGT lifetime is NOT passed when config TGT is null (EUD domain-default case)" {
            InModuleScope TierModel {
                $script:NewPolicyTGTBound = $false
                Mock New-ADAuthenticationPolicy {
                    param($Name, $Description, $UserAllowedToAuthenticateFrom,
                          $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm,
                          $UserTGTLifetimeMins)
                    if ($PSBoundParameters.ContainsKey('UserTGTLifetimeMins')) { $script:NewPolicyTGTBound = $true }
                    [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=test" }
                }
            }
            New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan -TGT $null) -DomainController $script:TestDC
            InModuleScope TierModel { $script:NewPolicyTGTBound | Should -BeFalse }
        }

        It "deferred SDDL — executor calls Resolve-TierModelPrincipalSid when ResolvedSddl=null" {
            # Plan has ResolvedSddl=$null; executor must resolve and build
            New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan -ResolvedSddl $null) -DomainController $script:TestDC
            Should -Invoke Resolve-TierModelPrincipalSid -ModuleName TierModel -Times 1
        }

        It "pre-supplied ResolvedSddl is honored — Resolve-TierModelPrincipalSid is NOT called" {
            # Plan has ResolvedSddl pre-set (backward-compat); executor must use it directly
            $preSetSddl = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-5678)}))'
            New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan -ResolvedSddl $preSetSddl) -DomainController $script:TestDC
            Should -Invoke Resolve-TierModelPrincipalSid -ModuleName TierModel -Times 0
        }

        It "SID resolution failure — SidResolutionFailed error recorded, Converged=false" {
            Mock Resolve-TierModelPrincipalSid -ModuleName TierModel {
                [PSCustomObject]@{ Success = $false; Sid = $null; Error = 'Group not found in AD' }
            }
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan -ResolvedSddl $null) -DomainController $script:TestDC
            $result.Converged    | Should -BeFalse
            ($result.Errors | Where-Object { $_.Code -eq 'SidResolutionFailed' }) | Should -Not -BeNullOrEmpty
            Should -Invoke New-ADAuthenticationPolicy -ModuleName TierModel -Times 0
        }

        It "CreatedNames contains the name of the created policy" {
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan -Name 'My Policy') -DomainController $script:TestDC
            $result.CreatedNames | Should -Contain 'My Policy'
        }

        It "already-exists exception — skipped with AlreadyExists reason, Converged=true" {
            Mock New-ADAuthenticationPolicy -ModuleName TierModel {
                throw [System.Exception]::new("Object already exists")
            }
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan) -DomainController $script:TestDC
            $result.Converged    | Should -BeTrue
            ($result.Skipped | Where-Object { $_.Reason -eq 'AlreadyExists' }) | Should -Not -BeNullOrEmpty
        }

        It "empty plan produces no AD write calls and Converged=true" {
            $emptyPlan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelAuthPolicy -Plan $emptyPlan -DomainController $script:TestDC
            Should -Invoke New-ADAuthenticationPolicy -ModuleName TierModel -Times 0
            $result.Converged | Should -BeTrue
        }

        It "WhatIf — no AD writes, skipped entry with Reason=WhatIf" {
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan) -DomainController $script:TestDC -WhatIf
            Should -Invoke New-ADAuthenticationPolicy -ModuleName TierModel -Times 0
            ($result.Skipped | Where-Object { $_.Reason -eq 'WhatIf' }) | Should -Not -BeNullOrEmpty
        }

        It "non-already-exists exception — error recorded, Converged=false" {
            Mock New-ADAuthenticationPolicy -ModuleName TierModel {
                throw [System.Exception]::new("Server is unavailable")
            }
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan) -DomainController $script:TestDC
            $result.Converged     | Should -BeFalse
            $result.Errors.Count  | Should -BeGreaterThan 0
        }

        It "multiple device groups — Resolve called for each group" {
            $multiPlan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action             = 'CreateAuthPolicy'
                    Name               = 'Multi Group Policy'
                    Description        = 'Test'
                    TGTLifetimeMinutes = 120
                    ResolvedSddl       = $null
                    Data               = [PSCustomObject]@{
                        allowedToAuthenticateFromDeviceGroups = @('Group1','Group2','Group3')
                    }
                })
            }
            New-TierModelAuthPolicy -Plan $multiPlan -DomainController $script:TestDC
            Should -Invoke Resolve-TierModelPrincipalSid -ModuleName TierModel -Times 3
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # New-TierModelAuthSilo — apply (mock New-AD* / Set-AD*)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "New-TierModelAuthSilo — execution" {

        BeforeAll {
            Mock New-ADAuthenticationPolicySilo -ModuleName TierModel {
                param($Name, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy,
                      $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion,
                      $Server, $Confirm)
                [PSCustomObject]@{
                    Name = $Name
                    DistinguishedName = "CN=$Name,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=test,DC=local"
                }
            }
            Mock Set-ADAuthenticationPolicySilo -ModuleName TierModel { }
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                param($Identity)
                [PSCustomObject]@{ Name = "$Identity"; DistinguishedName = "CN=$Identity,CN=test" }
            }
            Mock Set-ADObject -ModuleName TierModel { }

            # Helper: minimal auth-silo plan (defined in BeforeAll so It blocks can see it)
            function NewSiloPlan {
                param([string]$Name = 'T0 Silo', [string]$PolicyName = 'T0 Policy', [string]$Action = 'CreateAuthSilo')
                [PSCustomObject]@{
                    Actions = @(
                        [PSCustomObject]@{
                            Action       = $Action
                            Name         = $Name
                            Description  = 'Test silo'
                            PolicyName   = $PolicyName
                            PolicyDn     = $null
                            DriftReasons = @('Description differs')
                            Data         = [PSCustomObject]@{}
                        }
                    )
                }
            }
        }

        It "calls New-ADAuthenticationPolicySilo for a CreateAuthSilo action" {
            $result = New-TierModelAuthSilo -Plan (NewSiloPlan) -DomainController $script:TestDC
            Should -Invoke New-ADAuthenticationPolicySilo -ModuleName TierModel -Times 1
            $result.Applied.Count        | Should -Be 1
            $result.Applied[0].Action    | Should -Be 'CreateAuthSilo'
            $result.Applied[0].PolicyName | Should -Be 'T0 Policy'
        }

        It "always creates in audit mode — Enforce=false is splatted to New-ADAuthenticationPolicySilo" {
            InModuleScope TierModel {
                $script:NewSiloCapturedEnforce = $null
                Mock New-ADAuthenticationPolicySilo {
                    param($Name, $Enforce)
                    $script:NewSiloCapturedEnforce = $Enforce
                    [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=test" }
                }
            }
            New-TierModelAuthSilo -Plan (NewSiloPlan) -DomainController $script:TestDC
            InModuleScope TierModel { $script:NewSiloCapturedEnforce | Should -BeFalse }
        }

        It "sets all three account-class policies to the same policy (1:1 design)" {
            InModuleScope TierModel {
                $script:NewSiloUserPolicy     = $null
                $script:NewSiloComputerPolicy = $null
                $script:NewSiloServicePolicy  = $null
                Mock New-ADAuthenticationPolicySilo {
                    param($Name, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy)
                    $script:NewSiloUserPolicy     = $UserAuthenticationPolicy
                    $script:NewSiloComputerPolicy = $ComputerAuthenticationPolicy
                    $script:NewSiloServicePolicy  = $ServiceAuthenticationPolicy
                    [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=test" }
                }
            }
            New-TierModelAuthSilo -Plan (NewSiloPlan -PolicyName 'T0 Auth Policy') -DomainController $script:TestDC
            InModuleScope TierModel {
                $script:NewSiloUserPolicy     | Should -Be 'T0 Auth Policy'
                $script:NewSiloComputerPolicy | Should -Be 'T0 Auth Policy'
                $script:NewSiloServicePolicy  | Should -Be 'T0 Auth Policy'
            }
        }

        It "empty plan produces no AD write calls and Converged=true" {
            $emptyPlan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelAuthSilo -Plan $emptyPlan -DomainController $script:TestDC
            Should -Invoke New-ADAuthenticationPolicySilo -ModuleName TierModel -Times 0
            $result.Converged | Should -BeTrue
        }

        It "CreatedSiloNames contains the name of the created silo" {
            $result = New-TierModelAuthSilo -Plan (NewSiloPlan -Name 'My New Silo') -DomainController $script:TestDC
            $result.CreatedSiloNames | Should -Contain 'My New Silo'
        }

        It "already-exists exception — skipped with AlreadyExists reason, Converged=true" {
            Mock New-ADAuthenticationPolicySilo -ModuleName TierModel {
                throw [System.Exception]::new("Object already exists")
            }
            $result = New-TierModelAuthSilo -Plan (NewSiloPlan) -DomainController $script:TestDC
            $result.Converged | Should -BeTrue
            ($result.Skipped | Where-Object { $_.Reason -eq 'AlreadyExists' }) | Should -Not -BeNullOrEmpty
        }

        It "WhatIf — no AD writes, skipped entry with Reason=WhatIf" {
            $result = New-TierModelAuthSilo -Plan (NewSiloPlan) -DomainController $script:TestDC -WhatIf
            Should -Invoke New-ADAuthenticationPolicySilo -ModuleName TierModel -Times 0
            ($result.Skipped | Where-Object { $_.Reason -eq 'WhatIf' }) | Should -Not -BeNullOrEmpty
        }

        It "non-already-exists exception — error recorded, Converged=false" {
            Mock New-ADAuthenticationPolicySilo -ModuleName TierModel {
                throw [System.Exception]::new("Server is unavailable")
            }
            $result = New-TierModelAuthSilo -Plan (NewSiloPlan) -DomainController $script:TestDC
            $result.Converged    | Should -BeFalse
            $result.Errors.Count | Should -BeGreaterThan 0
        }

        It "outer catch — AuthSiloExecutionFailed on log failure inside try block" {
            # Make Write-TierModelLog throw on the 2nd call — which is "AuthSiloExecutionComplete"
            # inside the outer try block → triggers the outer function catch
            InModuleScope TierModel {
                $script:_tl_count = 0
                Mock Write-TierModelLog {
                    $script:_tl_count++
                    if ($script:_tl_count -eq 2) { throw "Simulated log failure" }
                }
            }
            $emptyPlan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelAuthSilo -Plan $emptyPlan -DomainController $script:TestDC
            $result.Converged | Should -BeFalse
            ($result.Errors | Where-Object { $_.Code -eq 'AuthSiloExecutionFailed' }) | Should -Not -BeNullOrEmpty
        }
    }
    Context "Set-TierModelAuthSiloMembership — membership assignment" {

        BeforeAll {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                param($Identity, $Properties)
                [PSCustomObject]@{ Name = "$Identity"; Members = @() }
            }
            Mock Get-ADComputer -ModuleName TierModel {
                param($Identity, $Properties, $Server, $ErrorAction)
                [PSCustomObject]@{
                    SamAccountName = "$Identity"
                    DistinguishedName = "CN=$Identity,OU=Computers,DC=test,DC=local"
                    'msDS-AssignedAuthNPolicySilo' = $null
                }
            }
            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'Tier0PAWDevices') {
                    @([PSCustomObject]@{ SamAccountName = 'PAW01$'; DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'; objectClass = 'computer' })
                } else {
                    @()
                }
            }
            Mock Grant-ADAuthenticationPolicySiloAccess -ModuleName TierModel { }
            Mock Set-ADAccountAuthenticationPolicySilo  -ModuleName TierModel { }

            # Computer-only silo config helper (no memberAccountGroups, no exemptAccounts)
            function OneSiloConfig {
                param([string]$SiloName = 'T0 Silo', [string[]]$ComputerGroups = @('Tier0PAWDevices'))
                [PSCustomObject]@{
                    authenticationSilos = @(
                        [PSCustomObject]@{
                            name                 = $SiloName
                            memberComputerGroups = $ComputerGroups
                        }
                    )
                }
            }
        }

        It "computer member is assigned — Grant then Set both called" {
            InModuleScope TierModel {
                $script:SiloMemberCallOrder = [System.Collections.Generic.List[string]]::new()
                Mock Grant-ADAuthenticationPolicySiloAccess { $script:SiloMemberCallOrder.Add('Grant') }
                Mock Set-ADAccountAuthenticationPolicySilo  { $script:SiloMemberCallOrder.Add('Set') }
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            InModuleScope TierModel {
                $script:SiloMemberCallOrder | Should -Contain 'Grant'
                $script:SiloMemberCallOrder | Should -Contain 'Set'
                $script:SiloMemberCallOrder.IndexOf('Grant') | Should -BeLessThan $script:SiloMemberCallOrder.IndexOf('Set')
            }
        }

        It "already-assigned computer — skipped with Reason=AlreadyAssigned, no Grant/Set calls" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @('CN=PAW01,OU=PAWs,DC=test,DC=local') }
            }
            Mock Get-ADComputer -ModuleName TierModel {
                param($Identity, $Properties)
                [PSCustomObject]@{
                    SamAccountName = "$Identity"
                    DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'
                    'msDS-AssignedAuthNPolicySilo' = 'T0 Silo'
                }
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            ($result.Skipped | Where-Object { $_.Reason -eq 'AlreadyAssigned' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Grant-ADAuthenticationPolicySiloAccess -ModuleName TierModel -Times 0
            Should -Invoke Set-ADAccountAuthenticationPolicySilo  -ModuleName TierModel -Times 0
        }

        It "empty computer groups — zero Applied entries and zero Errors" {
            Mock Get-ADGroupMember -ModuleName TierModel { @() }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig -ComputerGroups @('EmptyGroup')) -DomainController $script:TestDC
            $result.Applied.Count | Should -Be 0
            $result.Errors.Count  | Should -Be 0
        }

        It "-OnlyForSilos empty list — no silos processed (create-once noop)" {
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC -OnlyForSilos @()
            $result.Applied.Count | Should -Be 0
            Should -Invoke Grant-ADAuthenticationPolicySiloAccess -ModuleName TierModel -Times 0
        }

        It "-OnlyForSilos with matching silo — only that silo is processed" {
            $twoCfg = [PSCustomObject]@{
                authenticationSilos = @(
                    [PSCustomObject]@{ name = 'T0 Silo'; memberComputerGroups = @('Tier0PAWDevices') }
                    [PSCustomObject]@{ name = 'T1 Silo'; memberComputerGroups = @('Tier0PAWDevices') }
                )
            }
            # Only pass T0 Silo as the created silo
            $result = Set-TierModelAuthSiloMembership -Config $twoCfg -DomainController $script:TestDC -OnlyForSilos @('T0 Silo')
            # T0 Silo processed, T1 Silo skipped — Applied contains only T0 Silo entries
            $t1Applied = $result.Applied | Where-Object { $_.SiloName -eq 'T1 Silo' }
            $t1Applied | Should -BeNullOrEmpty
        }

        It "-OnlyForSilos omitted — all silos are processed (backwards-compat)" {
            $twoCfg = [PSCustomObject]@{
                authenticationSilos = @(
                    [PSCustomObject]@{ name = 'T0 Silo'; memberComputerGroups = @('Tier0PAWDevices') }
                    [PSCustomObject]@{ name = 'T1 Silo'; memberComputerGroups = @() }
                )
            }
            $result = Set-TierModelAuthSiloMembership -Config $twoCfg -DomainController $script:TestDC
            # Should process both silos (T1 has no members so no Grant/Set, but no errors)
            $result.Errors.Count | Should -Be 0
        }

        It "silo not found in AD — error recorded, Converged=false" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel { throw "Silo not found in AD" }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            $result.Converged    | Should -BeFalse
            ($result.Errors | Where-Object { $_.Code -eq 'AuthSiloNotFound' }) | Should -Not -BeNullOrEmpty
        }

        It "WhatIf — no Grant/Set calls, pending computers go to Skipped" {
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC -WhatIf
            Should -Invoke Grant-ADAuthenticationPolicySiloAccess -ModuleName TierModel -Times 0
            Should -Invoke Set-ADAccountAuthenticationPolicySilo  -ModuleName TierModel -Times 0
            ($result.Skipped | Where-Object { $_.Reason -eq 'WhatIf' }) | Should -Not -BeNullOrEmpty
        }

        It "already-granted but not assigned — only Set step called" {
            # Silo already has DN in Members (Grant done) but account's silo ref is wrong
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @('CN=PAW01,OU=PAWs,DC=test,DC=local') }
            }
            Mock Get-ADComputer -ModuleName TierModel {
                [PSCustomObject]@{
                    SamAccountName = 'PAW01$'
                    DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'
                    'msDS-AssignedAuthNPolicySilo' = $null   # Set not done yet
                }
            }
            InModuleScope TierModel {
                $script:GrantCallCount = 0
                $script:SetCallCount   = 0
                Mock Grant-ADAuthenticationPolicySiloAccess { $script:GrantCallCount++ }
                Mock Set-ADAccountAuthenticationPolicySilo  { $script:SetCallCount++ }
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            InModuleScope TierModel {
                $script:GrantCallCount | Should -Be 0   # Grant already done (in Members)
                $script:SetCallCount   | Should -Be 1   # Set still needed
            }
        }

        It "empty config — zero applied" {
            $localEmptyCfg = [PSCustomObject]@{ authenticationSilos = @() }
            $result = Set-TierModelAuthSiloMembership -Config $localEmptyCfg -DomainController $script:TestDC
            $result.Applied.Count | Should -Be 0
        }

        It "group expand failure — GroupExpandFailed error recorded, Converged=false" {
            Mock Get-ADGroupMember -ModuleName TierModel {
                throw "Cannot reach domain controller"
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            $result.Converged | Should -BeFalse
            ($result.Errors | Where-Object { $_.Code -eq 'GroupExpandFailed' }) | Should -Not -BeNullOrEmpty
        }

        It "pre-check Get-ADComputer throws — warning logged, computer assigned anyway" {
            # Pre-check failure is non-fatal: computer is treated as pending and ShouldProcess is called
            Mock Get-ADComputer -ModuleName TierModel {
                throw "Computer read failed"
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            # Applied should contain the computer (pre-check failure → assume pending → write)
            $result.Applied.Count | Should -BeGreaterThan 0
        }

        It "DN-format preCheck silo ref — computed correctly for already-assigned check" {
            # msDS-AssignedAuthNPolicySilo is a full DN — CN= prefix must be stripped
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @('CN=PAW01,OU=PAWs,DC=test,DC=local') }
            }
            Mock Get-ADComputer -ModuleName TierModel {
                [PSCustomObject]@{
                    SamAccountName    = 'PAW01$'
                    DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'
                    'msDS-AssignedAuthNPolicySilo' = 'CN=T0 Silo,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=test,DC=local'
                }
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            # Already assigned (both Grant done + Set done with DN-format ref) → skipped
            ($result.Skipped | Where-Object { $_.Reason -eq 'AlreadyAssigned' }) | Should -Not -BeNullOrEmpty
        }

        It "Grant throws — AssignSiloMembershipFailed error recorded, Converged=false" {
            Mock Grant-ADAuthenticationPolicySiloAccess -ModuleName TierModel {
                throw "Access denied"
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            $result.Converged | Should -BeFalse
            ($result.Errors | Where-Object { $_.Code -eq 'AssignSiloMembershipFailed' }) | Should -Not -BeNullOrEmpty
        }

        It "outer function catch — AuthSiloMembershipFailed on Get-TierModelAuthSilo throw" {
            Mock Get-TierModelAuthSilo -ModuleName TierModel { throw "Config read failure" }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            ($result.Errors | Where-Object { $_.Code -eq 'AuthSiloMembershipFailed' }) | Should -Not -BeNullOrEmpty
            $result.Converged | Should -BeFalse
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Test-TierModelAuthSiloPrerequisite — prerequisite validation (mock Get-ADGroup)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Test-TierModelAuthSiloPrerequisite — prerequisite validation" {

        BeforeAll {
            # Default: all groups exist
            Mock Get-ADGroup  -ModuleName TierModel {
                param($Identity)
                [PSCustomObject]@{ Name = "$Identity"; DistinguishedName = "CN=$Identity,OU=Groups,DC=test,DC=local" }
            }
            Mock Get-ADUser   -ModuleName TierModel { throw "Should not be called" }
            Mock Get-GPO      -ModuleName TierModel { throw "Should not be called" }
        }

        It "Passed=true and zero Failures when all referenced groups exist" {
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $result.Passed          | Should -BeTrue
            @($result.Failures).Count | Should -Be 0
        }

        It "Checked count covers unique groups referenced across device groups and computer groups" {
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:AuthSiloConfig -DomainController $script:TestDC
            # T0: 4 device groups + 4 computer groups; T1: 2+2; T2: 1+1; EUD: 1+1 (unique across silos)
            $result.Checked | Should -BeGreaterThan 5
        }

        It "Passed=false and failure message names the missing device group" {
            $missingGroup = 'Tier0PAWDevices'
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'Tier0PAWDevices') { throw "Group not found: $Identity" }
                [PSCustomObject]@{ Name = "$Identity" }
            }
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $result.Passed | Should -BeFalse
            ($result.Failures | Where-Object { $_ -match $missingGroup }) | Should -Not -BeNullOrEmpty
        }

        It "Passed=false and failure message names the missing computer group" {
            $missingGroup = 'Domain Controllers'
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'Domain Controllers') { throw "Group not found: $Identity" }
                [PSCustomObject]@{ Name = "$Identity" }
            }
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $result.Passed | Should -BeFalse
            ($result.Failures | Where-Object { $_ -match $missingGroup }) | Should -Not -BeNullOrEmpty
        }

        It "does NOT check user accounts — Get-ADUser is never called" {
            # Mock throws if called; clean config means it must not be called
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:AuthSiloConfig -DomainController $script:TestDC
            # If Get-ADUser was called, the test would have thrown above; reaching here proves it was not
            $result | Should -Not -BeNullOrEmpty
        }

        It "Passed=false when no group references exist (empty/null config)" {
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:ConfigEmpty -DomainController $script:TestDC
            $result.Passed | Should -BeFalse
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Test-TierModelAuthPolicy — read-only audit (mock AD)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Test-TierModelAuthPolicy — read-only audit" {

        BeforeAll {
            # Resolve all device groups to the same SID so Build-TierModelAuthSddl
            # produces a deterministic SDDL we can match in the AD mock.
            Mock Resolve-TierModelPrincipalSid -ModuleName TierModel {
                [PSCustomObject]@{ Success = $true; Sid = 'S-1-5-21-111-222-333-1234'; Error = $null }
            }
            # Default: policy absent from AD
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel { throw "Policy not found" }

            # Matching SDDL for the default Resolve mock (SID S-1-5-21-111-222-333-1234)
            $script:MatchingSddl = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234)}))'

            # Minimal single-policy config used by most tests
            $script:OnePolicyCfg = [PSCustomObject]@{
                authenticationPolicies = @(
                    [PSCustomObject]@{
                        name        = 'T0 Audit Policy'
                        description = 'T0 policy desc'
                        userTGTLifetimeMinutes = 120
                        allowedToAuthenticateFromDeviceGroups = @('T0Devices')
                    }
                )
            }
        }

        It "Compliant when AD policy matches config exactly" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'T0 policy desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status           | Should -Be 'Compliant'
            @($f.Issues).Count  | Should -Be 0
            $result.Compliant   | Should -Be 1
            $result.Drift       | Should -Be 0
        }

        It "Missing when policy is absent from AD" {
            # Default mock throws
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status         | Should -Be 'Missing'
            $result.Missing   | Should -Be 1
            $result.Drift     | Should -Be 1
            $result.Compliant | Should -Be 0
        }

        It "NonCompliant on description drift" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'Wrong description'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'Description' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant on UserTGTLifetimeMins drift" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'T0 policy desc'
                    UserTGTLifetimeMins = 999
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'TGT' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant on UserAllowedToAuthenticateFrom SDDL drift (different SID in AD)" {
            # AD stores a different SID; Compare-TierModelAuthSddl runs naturally and detects drift
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'T0 policy desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-9999)}))'
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'AllowedToAuthenticate' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant on ProtectedFromAccidentalDeletion=false" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'T0 policy desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $false; Enforce = $false
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'ProtectedFromAccidentalDeletion' }) | Should -Not -BeNullOrEmpty
        }

        It "TGT check skipped when config userTGTLifetimeMinutes is null (EUD domain-default)" {
            # AD TGT=999 but config TGT=null — check is skipped — Compliant
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'EUD Audit Policy'; Description = 'EUD policy desc'
                    UserTGTLifetimeMins = 999
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $eudCfg = [PSCustomObject]@{
                authenticationPolicies = @([PSCustomObject]@{
                    name        = 'EUD Audit Policy'
                    description = 'EUD policy desc'
                    userTGTLifetimeMinutes = $null
                    allowedToAuthenticateFromDeviceGroups = @('EUDDevices')
                })
            }
            $result = Test-TierModelAuthPolicy -Config $eudCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'Compliant'
            ($f.Issues | Where-Object { $_ -match 'UserTGTLifetimeMins' }) | Should -BeNullOrEmpty
        }

        It "Enforce=true in AD is NEVER audited — policy remains Compliant" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'T0 policy desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $true  # enforced in AD
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'Compliant'
            ($f.Issues | Where-Object { $_ -match 'Enforce' }) | Should -BeNullOrEmpty
        }

        It "DD alias SID(DD) in existing SDDL is NOT false-positive drift vs full S-1-5-21-...-516" {
            # Desired SDDL contains SID(S-1-5-21-111-222-333-516); AD stored the alias SID(DD).
            # Compare-TierModelAuthSddl resolves DD to 516 and returns Equal=true — Compliant.
            Mock Resolve-TierModelPrincipalSid -ModuleName TierModel {
                [PSCustomObject]@{ Success = $true; Sid = 'S-1-5-21-111-222-333-516'; Error = $null }
            }
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'DC Policy'; Description = 'DC policy desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(DD)}))'
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $dcCfg = [PSCustomObject]@{
                authenticationPolicies = @([PSCustomObject]@{
                    name        = 'DC Policy'
                    description = 'DC policy desc'
                    userTGTLifetimeMinutes = 120
                    allowedToAuthenticateFromDeviceGroups = @('Domain Controllers')
                })
            }
            $result = Test-TierModelAuthPolicy -Config $dcCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'Compliant'
        }

        It "result carries all required output properties" {
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            foreach ($p in @('TotalChecked','Compliant','Missing','NonCompliant','Errors','Drift','Findings','DurationMs','CorrelationId')) {
                $result.PSObject.Properties.Name | Should -Contain $p
            }
        }

        It "TotalChecked and counters correct: one Missing + one Compliant" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -like '*Tier 0*') { throw "Policy not found" }
                [PSCustomObject]@{
                    Name = "$Identity"
                    Description = 'Authentication Policy for Tier 1 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 1 origin devices, and lowers the Kerberos TGT lifetime to 4 hours (240 minutes).'
                    UserTGTLifetimeMins = 240
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $twoCfg = [PSCustomObject]@{
                authenticationPolicies = @(
                    $script:AuthSiloConfig.authenticationPolicies[0]   # Tier 0 — Missing
                    $script:AuthSiloConfig.authenticationPolicies[1]   # Tier 1 — Compliant
                )
            }
            $result = Test-TierModelAuthPolicy -Config $twoCfg -DomainController $script:TestDC -Silent
            $result.TotalChecked | Should -Be 2
            $result.Compliant    | Should -Be 1
            $result.Missing      | Should -Be 1
            $result.Drift        | Should -Be 1
        }

        It "Compliant with extra device groups in AD — ExtraDeviceGroups populated, status Compliant" {
            # AD has an ADDITIONAL device group beyond config — allowed, reported as extra
            Mock Resolve-TierModelPrincipalSid -ModuleName TierModel {
                [PSCustomObject]@{ Success = $true; Sid = 'S-1-5-21-111-222-333-1234'; Error = $null }
            }
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'T0 policy desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234), SID(S-1-5-21-111-222-333-9001)}))'
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status                        | Should -Be 'Compliant'
            @($f.ExtraDeviceGroups).Count    | Should -BeGreaterThan 0
        }

        It "non-Silent mode — output paths exercised (Compliant + summary)" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'T0 policy desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            # Call WITHOUT -Silent to exercise Write-Host output branches and summary block
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC
            $result.Compliant | Should -Be 1
        }

        It "non-Silent + NonCompliant — Write-Host per-issue output exercised" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'T0 Audit Policy'; Description = 'Wrong desc'
                    UserTGTLifetimeMins = 120
                    UserAllowedToAuthenticateFrom = $script:MatchingSddl
                    ProtectedFromAccidentalDeletion = $true; Enforce = $false
                }
            }
            $result = Test-TierModelAuthPolicy -Config $script:OnePolicyCfg -DomainController $script:TestDC -SuppressSummary
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Test-TierModelAuthSilo — read-only audit (mock AD)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Test-TierModelAuthSilo — read-only audit" {

        BeforeAll {
            # Default: silo absent from AD
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel { throw "Silo not found" }
            Mock Get-ADObject -ModuleName TierModel {
                param($Identity)
                [PSCustomObject]@{ SamAccountName = ("$Identity" -split ',')[0] -replace '^CN=' }
            }

            # Minimal single-silo config — computer membership only (new model)
            $script:OneSiloAuditCfg = [PSCustomObject]@{
                authenticationSilos = @(
                    [PSCustomObject]@{
                        name        = 'Test T0 Silo'
                        description = 'Test silo desc'
                        policy      = 'Test T0 Policy'
                        memberComputerGroups = @('TestComputerGroup')
                    }
                )
            }

            $script:AuditPawDn = 'CN=TestPAW01,OU=PAWs,DC=test,DC=local'

            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'TestComputerGroup') {
                    @([PSCustomObject]@{ SamAccountName = 'TestPAW01$'; DistinguishedName = $script:AuditPawDn; objectClass = 'computer' })
                } else { @() }
            }
        }

        It "Compliant when silo matches config and all expected computer members are present" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status           | Should -Be 'Compliant'
            @($f.Issues).Count  | Should -Be 0
            $result.Compliant   | Should -Be 1
            $result.Drift       | Should -Be 0
        }

        It "Missing when silo is absent from AD" {
            # Default mock throws "Silo not found"
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status         | Should -Be 'Missing'
            $result.Missing   | Should -Be 1
            $result.Drift     | Should -Be 1
        }

        It "NonCompliant on description drift" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Wrong description'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'description' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant when UserAuthenticationPolicy references wrong policy" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Wrong Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'UserAuthenticationPolicy' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant on ProtectedFromAccidentalDeletion=false" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $false
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'ProtectedFromAccidentalDeletion' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant when expected computer member is absent from silo Members list" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @()
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'Missing from silo Members' }) | Should -Not -BeNullOrEmpty
        }

        It "extra members beyond config are ALLOWED — silo is Compliant, ExtraMembers populated" {
            # Extra members in silo (not in expected computer groups) are allowed (informational)
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditPawDn, 'CN=ExtraDevice,OU=Unknown,DC=test,DC=local')
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status                    | Should -Be 'Compliant'
            @($f.ExtraMembers).Count     | Should -BeGreaterThan 0
        }

        It "Enforce=true in AD is NEVER audited — silo remains Compliant" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $true; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy = 'Test T0 Policy'; ComputerAuthenticationPolicy = 'Test T0 Policy'; ServiceAuthenticationPolicy = 'Test T0 Policy'
                    Members = @($script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'Compliant'
            ($f.Issues | Where-Object { $_ -match 'Enforce' }) | Should -BeNullOrEmpty
        }

        It "empty config groups and empty silo Members — Compliant (zero expected, zero current)" {
            Mock Get-ADGroupMember -ModuleName TierModel { @() }
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy = 'Test T0 Policy'; ComputerAuthenticationPolicy = 'Test T0 Policy'; ServiceAuthenticationPolicy = 'Test T0 Policy'
                    Members = @()
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            ($result.Findings | Select-Object -First 1).Status | Should -Be 'Compliant'
        }

        It "result carries all required output properties" {
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            foreach ($p in @('TotalChecked','Compliant','Missing','NonCompliant','Errors','Drift','Findings','DurationMs','CorrelationId')) {
                $result.PSObject.Properties.Name | Should -Contain $p
            }
        }

        It "group expansion failure — NonCompliant with error message" {
            Mock Get-ADGroupMember -ModuleName TierModel {
                throw "Cannot contact the server"
            }
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy = 'Test T0 Policy'; ComputerAuthenticationPolicy = 'Test T0 Policy'; ServiceAuthenticationPolicy = 'Test T0 Policy'
                    Members = @()
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'Cannot expand|expand computer' }) | Should -Not -BeNullOrEmpty
        }

        It "non-Silent mode — output paths exercised (Compliant + extra members)" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy = 'Test T0 Policy'; ComputerAuthenticationPolicy = 'Test T0 Policy'; ServiceAuthenticationPolicy = 'Test T0 Policy'
                    Members = @($script:AuditPawDn, 'CN=ExtraDevice,OU=Extra,DC=test,DC=local')
                }
            }
            # Without -Silent exercises Write-Host output branches
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC
            ($result.Findings | Select-Object -First 1).Status | Should -Be 'Compliant'
        }

        It "non-Silent + NonCompliant — Write-Host per-issue output exercised" {
            # Without -Silent and SuppressSummary to exercise both issue output and summary block
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -SuppressSummary
            ($result.Findings | Select-Object -First 1).Status | Should -Be 'Missing'
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuthSiloMembershipFd — read-only membership planner
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuthSiloMembershipFd — read-only membership planner" {

        BeforeAll {
            # Default: silo not yet in AD (fresh deploy scenario)
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel { throw "Silo not found" }
            Mock Get-ADComputer -ModuleName TierModel {
                param($Identity, $Properties)
                [PSCustomObject]@{
                    SamAccountName = "$Identity"
                    DistinguishedName = "CN=$Identity,OU=Computers,DC=test,DC=local"
                    'msDS-AssignedAuthNPolicySilo' = $null
                }
            }
            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'Tier0PAWDevices') {
                    @([PSCustomObject]@{ SamAccountName = 'PAW01$'; DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'; objectClass = 'computer' })
                } else {
                    @()
                }
            }

            # Minimal single-silo config for membership planner tests
            $script:MembershipPlanCfg = [PSCustomObject]@{
                authenticationSilos = @(
                    [PSCustomObject]@{
                        name                 = 'T0 Silo'
                        memberComputerGroups = @('Tier0PAWDevices')
                    }
                )
            }
        }

        It "silo absent from AD — all computers show as PENDING (warning, no error)" {
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            $result.Summary.TotalPending | Should -BeGreaterThan 0
            $result.Warnings.Count       | Should -BeGreaterThan 0
        }

        It "all computers already assigned — TotalPending=0, TotalAlreadyAssigned=1" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @('CN=PAW01,OU=PAWs,DC=test,DC=local') }
            }
            Mock Get-ADComputer -ModuleName TierModel {
                [PSCustomObject]@{
                    SamAccountName = 'PAW01$'
                    DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'
                    'msDS-AssignedAuthNPolicySilo' = 'T0 Silo'
                }
            }
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            $result.Summary.TotalPending         | Should -Be 0
            $result.Summary.TotalAlreadyAssigned | Should -Be 1
            @($result.Actions).Count             | Should -Be 0
        }

        It "-OnlyForSilos empty list — no silos processed, TotalPending=0" {
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC -OnlyForSilos @()
            $result.Summary.TotalPending | Should -Be 0
            @($result.Actions).Count     | Should -Be 0
        }

        It "-OnlyForSilos with matching silo — only that silo's computers counted" {
            $twoCfg = [PSCustomObject]@{
                authenticationSilos = @(
                    [PSCustomObject]@{ name = 'T0 Silo'; memberComputerGroups = @('Tier0PAWDevices') }
                    [PSCustomObject]@{ name = 'T1 Silo'; memberComputerGroups = @('Tier0PAWDevices') }
                )
            }
            $result = Get-TierModelAuthSiloMembershipFd -Config $twoCfg -DomainController $script:TestDC -OnlyForSilos @('T0 Silo')
            # Only T0 Silo pending; T1 Silo was filtered out
            ($result.Actions | Where-Object { $_.SiloName -eq 'T1 Silo' }) | Should -BeNullOrEmpty
        }

        It "absent computer group — error recorded, other silos still processed" {
            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                throw "Group '$Identity' not found in AD"
            }
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            $result.Errors.Count | Should -BeGreaterThan 0
            ($result.Errors | Where-Object { $_.Code -eq 'GroupExpandFailed' }) | Should -Not -BeNullOrEmpty
        }

        It "result carries required Summary keys" {
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            $result.Summary.Keys | Should -Contain 'TotalPending'
            $result.Summary.Keys | Should -Contain 'TotalAlreadyAssigned'
            $result.Summary.Keys | Should -Contain 'TotalActions'
            $result.Summary.Keys | Should -Contain 'ExistingCount'
        }

        It "action entries carry SiloName, SamAccountName, ObjectClass" {
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            if (@($result.Actions).Count -gt 0) {
                $action = $result.Actions | Select-Object -First 1
                $action.SiloName       | Should -Not -BeNullOrEmpty
                $action.SamAccountName | Should -Not -BeNullOrEmpty
                $action.ObjectClass    | Should -Be 'computer'
            } else {
                Set-ItResult -Pending -Because "no pending actions to validate"
            }
        }

        It "empty config — zero actions, Converged-style" {
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:ConfigEmpty -DomainController $script:TestDC
            @($result.Actions).Count | Should -Be 0
        }

        It "state (b): granted in Members but silo ref unset — computer classified as PENDING" {
            # Computer DN is in the silo's Members (Grant done) but msDS-AssignedAuthNPolicySilo is null
            # → alreadyGranted=TRUE, fullyAssigned=FALSE → pending
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @('CN=PAW01,OU=PAWs,DC=test,DC=local') }
            }
            Mock Get-ADComputer -ModuleName TierModel {
                [PSCustomObject]@{
                    SamAccountName = 'PAW01$'
                    DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'
                    'msDS-AssignedAuthNPolicySilo' = $null   # Set step not done yet
                }
            }
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            $result.Summary.TotalPending         | Should -Be 1
            $result.Summary.TotalAlreadyAssigned | Should -Be 0
        }

        It "state (d): Get-ADComputer throws during classification — warning logged, computer PENDING" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @() }
            }
            Mock Get-ADComputer -ModuleName TierModel { throw "Cannot reach domain controller" }
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            # Computer must be treated as pending (over-report safe)
            $result.Summary.TotalPending | Should -BeGreaterThan 0
        }

        It "DN-format silo ref — already-assigned path uses CN-prefix extraction" {
            # msDS-AssignedAuthNPolicySilo stored as full DN: CN=T0 Silo,CN=AuthN Policy,...
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @('CN=PAW01,OU=PAWs,DC=test,DC=local') }
            }
            Mock Get-ADComputer -ModuleName TierModel {
                [PSCustomObject]@{
                    SamAccountName    = 'PAW01$'
                    DistinguishedName = 'CN=PAW01,OU=PAWs,DC=test,DC=local'
                    'msDS-AssignedAuthNPolicySilo' = 'CN=T0 Silo,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=test,DC=local'
                }
            }
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            $result.Summary.TotalPending         | Should -Be 0
            $result.Summary.TotalAlreadyAssigned | Should -Be 1
        }

        It "outer function catch — AuthSiloMembershipFdPlanFailed on Get-TierModelAuthSilo throw" {
            Mock Get-TierModelAuthSilo -ModuleName TierModel { throw "Config read failure" }
            $result = Get-TierModelAuthSiloMembershipFd -Config $script:MembershipPlanCfg -DomainController $script:TestDC
            @($result.Actions).Count  | Should -Be 0
            ($result.Errors | Where-Object { $_.Code -eq 'AuthSiloMembershipFdPlanFailed' }) | Should -Not -BeNullOrEmpty
        }
    }
}
