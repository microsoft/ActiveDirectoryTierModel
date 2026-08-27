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
  - Get-TierModelAuthPolicyFd
  - Get-TierModelAuthSiloFd
  - New-TierModelAuthPolicy
  - New-TierModelAuthSilo
  - Set-TierModelAuthSiloMembership
  - Test-TierModelAuthSiloPrerequisite

All AD cmdlets are mocked — no live domain required.

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
                    memberAccountGroups  = @('Tier0Admins','Tier0Operators','Tier0ServerOperators','Tier0ServiceAccounts')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 1 Admins Authentication Silo'
                    description = 'Authentication Policy Silo for Tier 1 administrators, operators, server operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 1 devices.'
                    policy      = '*- Tier 1 Admins Authentication Policy'
                    memberComputerGroups = @('Tier1MemberServers','Tier1PAWDevices')
                    memberAccountGroups  = @('Tier1Admins','Tier1Operators','Tier1ServerOperators','Tier1ServiceAccounts')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 2 Admins Authentication Silo'
                    description = 'Authentication Policy Silo for Tier 2 administrators, operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 2 PAW devices.'
                    policy      = '*- Tier 2 Admins Authentication Policy'
                    memberComputerGroups = @('Tier2PAWDevices')
                    memberAccountGroups  = @('Tier2Admins','Tier2Operators','Tier2ServiceAccounts')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
                [PSCustomObject]@{
                    name        = '*- Tier 2 EUD Authentication Silo'
                    description = 'Authentication Policy Silo for Tier 2 End-User Device local device operators. Silo members may only obtain Kerberos TGTs from approved Tier 2 EUD devices.'
                    policy      = '*- Tier 2 EUD Authentication Policy'
                    memberComputerGroups = @('Tier2EUDDevices')
                    memberAccountGroups  = @('Tier2LocalDeviceOperators')
                    enforce                       = $false
                    protectedFromAccidentalDeletion = $true
                }
            )
            authSilosExemptAccounts = [PSCustomObject]@{
                samaccountnames = @('svc-pawdomainjoin','svc-t1srvdomainjoin','svc-t2euddomainjoin')
            }
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
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuthPolicy — config parsing (no AD)
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

        It "Tier 0 silo member account groups include Tier0Admins and Tier0ServiceAccounts" {
            $silo = @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*Tier 0 Admins*' }
            $silo.memberAccountGroups | Should -Contain 'Tier0Admins'
            $silo.memberAccountGroups | Should -Contain 'Tier0ServiceAccounts'
        }

        It "Tier 2 EUD silo has exactly one member account group (Tier2LocalDeviceOperators)" {
            $silo = @(Get-TierModelAuthSilo -Config $script:AuthSiloConfig) | Where-Object { $_.name -like '*EUD*' }
            @($silo.memberAccountGroups).Count | Should -Be 1
            $silo.memberAccountGroups         | Should -Contain 'Tier2LocalDeviceOperators'
        }

        It "returns empty array when authenticationSilos is absent from config" {
            @(Get-TierModelAuthSilo -Config $script:ConfigEmpty).Count | Should -Be 0
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuthPolicyFd — deployment planning (mock AD)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuthPolicyFd — deployment planning" {

        BeforeAll {
            # Default happy-path mocks for this context
            Mock Resolve-TierModelPrincipalSid -ModuleName TierModel {
                [PSCustomObject]@{ Success = $true; Sid = 'S-1-5-21-111-222-333-1234'; Error = $null }
            }
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel { throw "Policy not found" }
            Mock Compare-TierModelAuthSddl -ModuleName TierModel {
                [PSCustomObject]@{ Equal = $true; Reason = $null }
            }
        }

        It "emits one CreateAuthPolicy action per policy absent from AD" {
            $result = Get-TierModelAuthPolicyFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            @($result.Actions | Where-Object { $_.Action -eq 'CreateAuthPolicy' }).Count | Should -Be 4
        }

        It "CreateAuthPolicy action carries ResolvedSddl with Member_of_any (OR-logic)" {
            $result = Get-TierModelAuthPolicyFd -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $action = $result.Actions | Where-Object { $_.Name -like '*Tier 0*' } | Select-Object -First 1
            $action.ResolvedSddl | Should -Match 'Member_of_any'
            $action.ResolvedSddl | Should -Not -Match 'Member_of_each'
        }

        It "AlreadyConverged — zero actions and AlreadyExist=1 when existing policy matches" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name            = '*- Tier 0 Admins Authentication Policy'
                    Description     = 'Authentication Policy for Tier 0 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 0 origin devices, and lowers the Kerberos TGT lifetime to 2 hours (120 minutes).'
                    UserTGTLifetimeMins              = 120
                    UserAllowedToAuthenticateFrom    = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234)}))'
                    Enforce                          = $false
                    ProtectedFromAccidentalDeletion  = $true
                }
            }
            $singleCfg = [PSCustomObject]@{ authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies[0]) }
            $result = Get-TierModelAuthPolicyFd -Config $singleCfg -DomainController $script:TestDC
            @($result.Actions).Count   | Should -Be 0
            $result.Summary.AlreadyExist | Should -Be 1
        }

        It "UpdateAuthPolicy — emitted when TGT lifetime drifts" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name            = '*- Tier 0 Admins Authentication Policy'
                    Description     = 'Authentication Policy for Tier 0 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 0 origin devices, and lowers the Kerberos TGT lifetime to 2 hours (120 minutes).'
                    UserTGTLifetimeMins              = 999  # drifted
                    UserAllowedToAuthenticateFrom    = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234)}))'
                    Enforce                          = $false
                    ProtectedFromAccidentalDeletion  = $true
                }
            }
            $singleCfg = [PSCustomObject]@{ authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies[0]) }
            $result = Get-TierModelAuthPolicyFd -Config $singleCfg -DomainController $script:TestDC
            $drift = $result.Actions | Where-Object { $_.Action -eq 'UpdateAuthPolicy' }
            $drift | Should -Not -BeNullOrEmpty
            ($drift.DriftReasons | Where-Object { $_ -match 'UserTGTLifetimeMins' }) | Should -Not -BeNullOrEmpty
        }

        It "UpdateAuthPolicy — emitted when SDDL drifts" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name            = '*- Tier 0 Admins Authentication Policy'
                    Description     = 'Authentication Policy for Tier 0 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 0 origin devices, and lowers the Kerberos TGT lifetime to 2 hours (120 minutes).'
                    UserTGTLifetimeMins              = 120
                    UserAllowedToAuthenticateFrom    = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-9999)}))'
                    Enforce                          = $false
                    ProtectedFromAccidentalDeletion  = $true
                }
            }
            Mock Compare-TierModelAuthSddl -ModuleName TierModel {
                [PSCustomObject]@{ Equal = $false; Reason = 'Device group SID sets differ' }
            }
            $singleCfg = [PSCustomObject]@{ authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies[0]) }
            $result = Get-TierModelAuthPolicyFd -Config $singleCfg -DomainController $script:TestDC
            $drift = $result.Actions | Where-Object { $_.Action -eq 'UpdateAuthPolicy' }
            $drift | Should -Not -BeNullOrEmpty
            ($drift.DriftReasons | Where-Object { $_ -match 'SDDL' }) | Should -Not -BeNullOrEmpty
        }

        It "UpdateAuthPolicy — emitted when ProtectedFromAccidentalDeletion is false" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name            = '*- Tier 0 Admins Authentication Policy'
                    Description     = 'Authentication Policy for Tier 0 administrative accounts. Restricts Kerberos TGT issuance to approved Tier 0 origin devices, and lowers the Kerberos TGT lifetime to 2 hours (120 minutes).'
                    UserTGTLifetimeMins              = 120
                    UserAllowedToAuthenticateFrom    = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234)}))'
                    Enforce                          = $false
                    ProtectedFromAccidentalDeletion  = $false  # drift
                }
            }
            $singleCfg = [PSCustomObject]@{ authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies[0]) }
            $result = Get-TierModelAuthPolicyFd -Config $singleCfg -DomainController $script:TestDC
            $drift = $result.Actions | Where-Object { $_.Action -eq 'UpdateAuthPolicy' }
            $drift | Should -Not -BeNullOrEmpty
            ($drift.DriftReasons | Where-Object { $_ -match 'ProtectedFromAccidentalDeletion' }) | Should -Not -BeNullOrEmpty
        }

        It "error recorded and policy skipped when SID resolution fails" {
            Mock Resolve-TierModelPrincipalSid -ModuleName TierModel {
                [PSCustomObject]@{ Success = $false; Sid = $null; Error = 'Group not found in AD' }
            }
            $singleCfg = [PSCustomObject]@{ authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies[0]) }
            $result = Get-TierModelAuthPolicyFd -Config $singleCfg -DomainController $script:TestDC
            $result.Errors.Count      | Should -BeGreaterThan 0
            @($result.Actions).Count  | Should -Be 0
        }

        It "null TGT config (EUD) — no TGT drift when existing TGT is also absent" {
            Mock Get-ADAuthenticationPolicy -ModuleName TierModel {
                [PSCustomObject]@{
                    Name            = '*- Tier 2 EUD Authentication Policy'
                    Description     = 'Authentication Policy for Tier 2 End-User Device local device operators. Restricts Kerberos TGT issuance to approved Tier 2 EUD origin devices; the Kerberos TGT lifetime is not lowered here, so EUD accounts inherit the domain-default lifetime (about 10 hours).'
                    UserTGTLifetimeMins              = $null
                    UserAllowedToAuthenticateFrom    = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234)}))'
                    Enforce                          = $false
                    ProtectedFromAccidentalDeletion  = $true
                }
            }
            # Index 3 = EUD policy with null TGT
            $eudCfg = [PSCustomObject]@{ authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies[3]) }
            $result = Get-TierModelAuthPolicyFd -Config $eudCfg -DomainController $script:TestDC
            $tgtDrift = $result.Actions | Where-Object { $_.Action -eq 'UpdateAuthPolicy' } |
                        ForEach-Object { $_.DriftReasons } |
                        Where-Object { $_ -match 'UserTGTLifetimeMins' }
            $tgtDrift | Should -BeNullOrEmpty
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

        It "UpdateAuthSilo — emitted when description drifts" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name                         = '*- Tier 0 Admins Authentication Silo'
                    Description                  = 'Old description'  # drift
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
            $drift = $result.Actions | Where-Object { $_.Action -eq 'UpdateAuthSilo' }
            $drift | Should -Not -BeNullOrEmpty
            ($drift.DriftReasons | Where-Object { $_ -match 'Description' }) | Should -Not -BeNullOrEmpty
        }

        It "UpdateAuthSilo — emitted when ProtectedFromAccidentalDeletion is false" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name                         = '*- Tier 0 Admins Authentication Silo'
                    Description                  = 'Authentication Policy Silo for Tier 0 administrators, operators, server operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 0 devices.'
                    Enforce                      = $false
                    ProtectedFromAccidentalDeletion = $false  # drift
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
            $drift = $result.Actions | Where-Object { $_.Action -eq 'UpdateAuthSilo' }
            $drift | Should -Not -BeNullOrEmpty
            ($drift.DriftReasons | Where-Object { $_ -match 'ProtectedFromAccidentalDeletion' }) | Should -Not -BeNullOrEmpty
        }

        It "UpdateAuthSilo — emitted when UserAuthenticationPolicy reference drifts" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name                         = '*- Tier 0 Admins Authentication Silo'
                    Description                  = 'Authentication Policy Silo for Tier 0 administrators, operators, server operators, and service accounts. Silo members may only obtain Kerberos TGTs from approved Tier 0 devices.'
                    Enforce                      = $false
                    ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Wrong Policy'  # drift
                    ComputerAuthenticationPolicy = '*- Tier 0 Admins Authentication Policy'
                    ServiceAuthenticationPolicy  = '*- Tier 0 Admins Authentication Policy'
                }
            }
            $singleCfg = [PSCustomObject]@{
                authenticationPolicies = @($script:AuthSiloConfig.authenticationPolicies)
                authenticationSilos    = @($script:AuthSiloConfig.authenticationSilos[0])
            }
            $result = Get-TierModelAuthSiloFd -Config $singleCfg -DomainController $script:TestDC
            $drift = $result.Actions | Where-Object { $_.Action -eq 'UpdateAuthSilo' }
            $drift | Should -Not -BeNullOrEmpty
            ($drift.DriftReasons | Where-Object { $_ -match 'UserAuthenticationPolicy' }) | Should -Not -BeNullOrEmpty
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # New-TierModelAuthPolicy — apply (mock New-AD* / Set-AD*)
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
            Mock Set-ADObject -ModuleName TierModel { }

            # Helper: minimal auth-policy plan (defined in BeforeAll so It blocks can see it)
            function NewAuthPolicyPlan {
                param([string]$Name = 'Test T0 Policy', [object]$TGT = 120, [string]$Action = 'CreateAuthPolicy')
                [PSCustomObject]@{
                    Actions = @(
                        [PSCustomObject]@{
                            Action             = $Action
                            Name               = $Name
                            Description        = 'Test description'
                            TGTLifetimeMinutes = $TGT
                            ResolvedSddl       = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-111-222-333-1234)}))'
                            DriftReasons       = @('Description differs')
                            Data               = [PSCustomObject]@{}
                        }
                    )
                }
            }
        }

        It "calls New-ADAuthenticationPolicy for a CreateAuthPolicy action" {
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan) -DomainController $script:TestDC
            Should -Invoke New-ADAuthenticationPolicy -ModuleName TierModel -Times 1
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].Action | Should -Be 'CreateAuthPolicy'
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

        It "calls Set-ADAuthenticationPolicy for an UpdateAuthPolicy action" {
            $result = New-TierModelAuthPolicy -Plan (NewAuthPolicyPlan -Action 'UpdateAuthPolicy') -DomainController $script:TestDC
            Should -Invoke Set-ADAuthenticationPolicy -ModuleName TierModel -Times 1
            $result.Applied.Count | Should -Be 1
            $result.Applied[0].Action | Should -Be 'UpdateAuthPolicy'
        }

        It "empty plan produces no AD write calls and Converged=true" {
            $emptyPlan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelAuthPolicy -Plan $emptyPlan -DomainController $script:TestDC
            Should -Invoke New-ADAuthenticationPolicy -ModuleName TierModel -Times 0
            Should -Invoke Set-ADAuthenticationPolicy -ModuleName TierModel -Times 0
            $result.Converged | Should -BeTrue
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

        It "calls Set-ADAuthenticationPolicySilo for an UpdateAuthSilo action" {
            $result = New-TierModelAuthSilo -Plan (NewSiloPlan -Action 'UpdateAuthSilo') -DomainController $script:TestDC
            Should -Invoke Set-ADAuthenticationPolicySilo -ModuleName TierModel -Times 1
            $result.Applied.Count     | Should -Be 1
            $result.Applied[0].Action | Should -Be 'UpdateAuthSilo'
        }

        It "empty plan produces no AD write calls and Converged=true" {
            $emptyPlan = [PSCustomObject]@{ Actions = @() }
            $result = New-TierModelAuthSilo -Plan $emptyPlan -DomainController $script:TestDC
            Should -Invoke New-ADAuthenticationPolicySilo -ModuleName TierModel -Times 0
            Should -Invoke Set-ADAuthenticationPolicySilo -ModuleName TierModel -Times 0
            $result.Converged | Should -BeTrue
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Set-TierModelAuthSiloMembership — membership assignment (mock all AD)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Set-TierModelAuthSiloMembership — membership assignment" {

        BeforeAll {
            Mock Get-ADDomain -ModuleName TierModel {
                [PSCustomObject]@{ DomainSID = [PSCustomObject]@{ Value = 'S-1-5-21-111-222-333' } }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity, $Properties, $Server, $ErrorAction)
                if ("$Identity" -eq 'S-1-5-21-111-222-333-500') {
                    [PSCustomObject]@{ SamAccountName = 'Administrator'; DistinguishedName = 'CN=Administrator,CN=Users,DC=test,DC=local' }
                } else {
                    [PSCustomObject]@{ SamAccountName = "$Identity"; DistinguishedName = "CN=$Identity,OU=T0,DC=test,DC=local"; 'msDS-AssignedAuthNPolicySilo' = $null }
                }
            }
            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'Tier0Admins') {
                    @([PSCustomObject]@{ SamAccountName = 'Tier0Admin1'; DistinguishedName = 'CN=Tier0Admin1,OU=T0,DC=test,DC=local'; objectClass = 'user' })
                } else {
                    @()
                }
            }
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @() }
            }
            Mock Grant-ADAuthenticationPolicySiloAccess     -ModuleName TierModel { }
            Mock Set-ADAccountAuthenticationPolicySilo      -ModuleName TierModel { }

            # Helper: minimal config for one silo (defined in BeforeAll so It blocks can see it)
            function OneSiloConfig {
                param([string]$SiloName = 'T0 Silo', [string[]]$AccountGroups = @('Tier0Admins'), [string[]]$ExemptSams = @())
                [PSCustomObject]@{
                    authenticationSilos = @(
                        [PSCustomObject]@{
                            name                 = $SiloName
                            memberComputerGroups = @()
                            memberAccountGroups  = $AccountGroups
                        }
                    )
                    authSilosExemptAccounts = [PSCustomObject]@{ samaccountnames = $ExemptSams }
                }
            }
        }

        It "Grant-ADAuthenticationPolicySiloAccess is called BEFORE Set-ADAccountAuthenticationPolicySilo" {
            InModuleScope TierModel {
                $script:SiloMemberCallOrder = [System.Collections.Generic.List[string]]::new()
                Mock Grant-ADAuthenticationPolicySiloAccess { $script:SiloMemberCallOrder.Add('Grant') }
                Mock Set-ADAccountAuthenticationPolicySilo  { $script:SiloMemberCallOrder.Add('Set') }
            }
            Set-TierModelAuthSiloMembership -Config (OneSiloConfig) -DomainController $script:TestDC
            InModuleScope TierModel {
                $script:SiloMemberCallOrder.Count | Should -BeGreaterThan 1
                $script:SiloMemberCallOrder[0]    | Should -Be 'Grant'
                $script:SiloMemberCallOrder[1]    | Should -Be 'Set'
            }
        }

        It "configured exempt accounts (svc-pawdomainjoin) are skipped — not assigned, Reason=ExemptAccount" {
            Mock Get-ADGroupMember -ModuleName TierModel {
                @(
                    [PSCustomObject]@{ SamAccountName = 'svc-pawdomainjoin'; DistinguishedName = 'CN=svc-pawdomainjoin,OU=SVC,DC=test,DC=local'; objectClass = 'user' }
                    [PSCustomObject]@{ SamAccountName = 'Tier0Admin1';       DistinguishedName = 'CN=Tier0Admin1,OU=T0,DC=test,DC=local';          objectClass = 'user' }
                )
            }
            $cfg = OneSiloConfig -ExemptSams @('svc-pawdomainjoin','svc-t1srvdomainjoin','svc-t2euddomainjoin')
            $result = Set-TierModelAuthSiloMembership -Config $cfg -DomainController $script:TestDC
            $exemptSkip = $result.Skipped | Where-Object { $_.SamAccountName -eq 'svc-pawdomainjoin' }
            $exemptSkip          | Should -Not -BeNullOrEmpty
            $exemptSkip.Reason   | Should -Be 'ExemptAccount'
            # Non-exempt account is still applied
            ($result.Applied | Where-Object { $_.SamAccountName -eq 'Tier0Admin1' }) | Should -Not -BeNullOrEmpty
        }

        It "RID-500 built-in Administrator is skipped — not assigned to any silo" {
            Mock Get-ADGroupMember -ModuleName TierModel {
                @(
                    [PSCustomObject]@{ SamAccountName = 'Administrator'; DistinguishedName = 'CN=Administrator,CN=Users,DC=test,DC=local'; objectClass = 'user' }
                    [PSCustomObject]@{ SamAccountName = 'Tier0Admin1';   DistinguishedName = 'CN=Tier0Admin1,OU=T0,DC=test,DC=local';       objectClass = 'user' }
                )
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig -ExemptSams @()) -DomainController $script:TestDC
            ($result.Skipped | Where-Object { $_.SamAccountName -eq 'Administrator' }) | Should -Not -BeNullOrEmpty
        }

        It "already-assigned account — skipped with Reason=AlreadyAssigned, no Grant/Set calls" {
            # Silo already holds the account's DN in Members; account already has silo stamped
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{ Name = 'T0 Silo'; Members = @('CN=Tier0Admin1,OU=T0,DC=test,DC=local') }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'S-1-5-21-111-222-333-500') {
                    [PSCustomObject]@{ SamAccountName = 'Administrator' }
                } else {
                    [PSCustomObject]@{ SamAccountName = "$Identity"; DistinguishedName = "CN=$Identity,OU=T0,DC=test,DC=local"; 'msDS-AssignedAuthNPolicySilo' = 'T0 Silo' }
                }
            }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig -ExemptSams @()) -DomainController $script:TestDC
            ($result.Skipped | Where-Object { $_.Reason -eq 'AlreadyAssigned' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Grant-ADAuthenticationPolicySiloAccess -ModuleName TierModel -Times 0
            Should -Invoke Set-ADAccountAuthenticationPolicySilo  -ModuleName TierModel -Times 0
        }

        It "empty groups — zero Applied entries and zero Errors" {
            Mock Get-ADGroupMember -ModuleName TierModel { @() }
            $result = Set-TierModelAuthSiloMembership -Config (OneSiloConfig -AccountGroups @('EmptyGroup') -ExemptSams @()) -DomainController $script:TestDC
            $result.Applied.Count | Should -Be 0
            $result.Errors.Count  | Should -Be 0
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

        It "Checked count covers unique groups across all three reference lists (device/computer/account)" {
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:AuthSiloConfig -DomainController $script:TestDC
            # 4 device groups (T0) + 2+1+1 more (T1/T2/EUD) + computer/account groups = well above 5
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

        It "Passed=false and failure message names the missing member account group" {
            Mock Get-ADGroup -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'Tier0Admins') { throw "Group not found: $Identity" }
                [PSCustomObject]@{ Name = "$Identity" }
            }
            $result = Test-TierModelAuthSiloPrerequisite -Config $script:AuthSiloConfig -DomainController $script:TestDC
            $result.Passed | Should -BeFalse
            ($result.Failures | Where-Object { $_ -match 'Tier0Admins' }) | Should -Not -BeNullOrEmpty
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
            ($f.Issues | Where-Object { $_ -match 'UserTGTLifetimeMins' }) | Should -Not -BeNullOrEmpty
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
            ($f.Issues | Where-Object { $_ -match 'SDDL' }) | Should -Not -BeNullOrEmpty
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
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Test-TierModelAuthSilo — read-only audit (mock AD)
    # ═══════════════════════════════════════════════════════════════════════════
    Context "Test-TierModelAuthSilo — read-only audit" {

        BeforeAll {
            Mock Get-ADDomain -ModuleName TierModel {
                [PSCustomObject]@{ DomainSID = [PSCustomObject]@{ Value = 'S-1-5-21-111-222-333' } }
            }
            Mock Get-ADUser -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'S-1-5-21-111-222-333-500') {
                    [PSCustomObject]@{ SamAccountName = 'Administrator' }
                }
            }
            # Default: silo absent from AD
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel { throw "Silo not found" }
            Mock Get-ADObject -ModuleName TierModel {
                param($Identity)
                [PSCustomObject]@{ SamAccountName = ("$Identity" -split ',')[0] -replace '^CN=' }
            }

            # Minimal single-silo config used by most tests
            $script:OneSiloAuditCfg = [PSCustomObject]@{
                authenticationSilos = @(
                    [PSCustomObject]@{
                        name        = 'Test T0 Silo'
                        description = 'Test silo desc'
                        policy      = 'Test T0 Policy'
                        memberComputerGroups = @('TestComputerGroup')
                        memberAccountGroups  = @('TestAccountGroup')
                    }
                )
                authSilosExemptAccounts = [PSCustomObject]@{
                    samaccountnames = @('svc-pawdomainjoin','svc-t1srvdomainjoin','svc-t2euddomainjoin')
                }
            }

            # Expected member DNs used across tests
            $script:AuditAdminDn = 'CN=TestAdmin1,OU=T0,DC=test,DC=local'
            $script:AuditPawDn   = 'CN=TestPAW01,OU=PAWs,DC=test,DC=local'

            # Default group expansion: TestAccountGroup→TestAdmin1, TestComputerGroup→TestPAW01
            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'TestAccountGroup') {
                    @([PSCustomObject]@{ SamAccountName = 'TestAdmin1'; DistinguishedName = $script:AuditAdminDn; objectClass = 'user' })
                } elseif ("$Identity" -eq 'TestComputerGroup') {
                    @([PSCustomObject]@{ SamAccountName = 'TestPAW01$'; DistinguishedName = $script:AuditPawDn; objectClass = 'computer' })
                } else { @() }
            }
        }

        It "Compliant when silo matches config and all expected members are present" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditAdminDn, $script:AuditPawDn)
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
                    Members = @($script:AuditAdminDn, $script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'Description' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant when UserAuthenticationPolicy references wrong policy" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Wrong Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditAdminDn, $script:AuditPawDn)
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
                    Members = @($script:AuditAdminDn, $script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'ProtectedFromAccidentalDeletion' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant when expected member is absent from silo Members list" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @()  # expected members absent
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'Missing from silo Members' }) | Should -Not -BeNullOrEmpty
        }

        It "NonCompliant when silo contains an unexpected member not in config groups" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy     = 'Test T0 Policy'
                    ComputerAuthenticationPolicy = 'Test T0 Policy'
                    ServiceAuthenticationPolicy  = 'Test T0 Policy'
                    Members = @($script:AuditAdminDn, $script:AuditPawDn, 'CN=Intruder,OU=Unknown,DC=test,DC=local')
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            $f = $result.Findings | Select-Object -First 1
            $f.Status | Should -Be 'NonCompliant'
            ($f.Issues | Where-Object { $_ -match 'Unexpected member' }) | Should -Not -BeNullOrEmpty
        }

        It "exempt account (svc-pawdomainjoin) excluded from expected — silo Compliant without it" {
            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'TestAccountGroup') {
                    @(
                        [PSCustomObject]@{ SamAccountName = 'svc-pawdomainjoin'; DistinguishedName = 'CN=svc-pawdomainjoin,OU=SVC,DC=test,DC=local'; objectClass = 'user' }
                        [PSCustomObject]@{ SamAccountName = 'TestAdmin1';        DistinguishedName = $script:AuditAdminDn;                            objectClass = 'user' }
                    )
                } elseif ("$Identity" -eq 'TestComputerGroup') {
                    @([PSCustomObject]@{ SamAccountName = 'TestPAW01$'; DistinguishedName = $script:AuditPawDn; objectClass = 'computer' })
                } else { @() }
            }
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy = 'Test T0 Policy'; ComputerAuthenticationPolicy = 'Test T0 Policy'; ServiceAuthenticationPolicy = 'Test T0 Policy'
                    Members = @($script:AuditAdminDn, $script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            ($result.Findings | Select-Object -First 1).Status | Should -Be 'Compliant'
        }

        It "RID-500 Administrator excluded from expected — silo Compliant without it" {
            Mock Get-ADGroupMember -ModuleName TierModel {
                param($Identity)
                if ("$Identity" -eq 'TestAccountGroup') {
                    @(
                        [PSCustomObject]@{ SamAccountName = 'Administrator'; DistinguishedName = 'CN=Administrator,CN=Users,DC=test,DC=local'; objectClass = 'user' }
                        [PSCustomObject]@{ SamAccountName = 'TestAdmin1';    DistinguishedName = $script:AuditAdminDn;                        objectClass = 'user' }
                    )
                } elseif ("$Identity" -eq 'TestComputerGroup') {
                    @([PSCustomObject]@{ SamAccountName = 'TestPAW01$'; DistinguishedName = $script:AuditPawDn; objectClass = 'computer' })
                } else { @() }
            }
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $false; ProtectedFromAccidentalDeletion = $true
                    UserAuthenticationPolicy = 'Test T0 Policy'; ComputerAuthenticationPolicy = 'Test T0 Policy'; ServiceAuthenticationPolicy = 'Test T0 Policy'
                    Members = @($script:AuditAdminDn, $script:AuditPawDn)
                }
            }
            $result = Test-TierModelAuthSilo -Config $script:OneSiloAuditCfg -DomainController $script:TestDC -Silent
            ($result.Findings | Select-Object -First 1).Status | Should -Be 'Compliant'
        }

        It "Enforce=true in AD is NEVER audited — silo remains Compliant" {
            Mock Get-ADAuthenticationPolicySilo -ModuleName TierModel {
                [PSCustomObject]@{
                    Name = 'Test T0 Silo'; Description = 'Test silo desc'
                    Enforce = $true; ProtectedFromAccidentalDeletion = $true  # enforced in AD
                    UserAuthenticationPolicy = 'Test T0 Policy'; ComputerAuthenticationPolicy = 'Test T0 Policy'; ServiceAuthenticationPolicy = 'Test T0 Policy'
                    Members = @($script:AuditAdminDn, $script:AuditPawDn)
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
    }
}
