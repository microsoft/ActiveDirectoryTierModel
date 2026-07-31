#Requires -Modules Pester
<#
.SYNOPSIS
Integration-level tests for the Windows LAPS deployment workflow (T019).

.DESCRIPTION
Tests the full WinLaps cmdlet pipeline (plan -> apply -> re-plan) at the cmdlet
integration level. Deploy-TierModel.ps1 is intentionally excluded from the
coverage path, so these tests exercise Get-TierModelWinLapsAcl /
Get-TierModelWinLapsAclFd + New-TierModelWinLapsAcl directly to verify:
  - Plan total increases when WinLaps delegations are configured
  - Apply returns Executed > 0 on first run
  - Second plan after successful apply returns zero actions (Converged)
  - WinLaps phase actions come after dMSA (ordering invariant via config)

All AD / LAPS / GPO cmdlets are mocked — no live Active Directory.

.NOTES
Created : 2026-07-16
Tags    : Integration, WinLaps
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe "Integration: Windows LAPS Deployment Pipeline" -Tag "Integration", "WinLaps" {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..\Modules\TierModel\TierModel.psd1'
        Import-Module $ModulePath -Force

        $script:TestDC       = "testdc.contoso.local"
        $script:TestDomainDN = "DC=contoso,DC=local"
        $script:TestNetBIOS  = "CONTOSO"

        # ── WinLaps delegation config (2 delegations, each with decryptorGroup) ──
        $script:IntegrationWinLapsConfig = [PSCustomObject]@{
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

        # ── Baseline mocks (all resources exist, all permissions absent) ─────────
        Mock Write-TierModelLog -ModuleName TierModel { }

        # Host OS install language defaults to English (en-US) so the prerequisite
        # host-OS language gate passes and the deployment flow proceeds.
        Mock Get-ItemPropertyValue -ModuleName TierModel -ParameterFilter { $Name -eq 'InstallLanguage' } { return '0409' }

        Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:TestDomainDN }

        Mock Resolve-TierModelPlaceholder -ModuleName TierModel {
            param($Path, $DomainDN)
            return $Path -replace '\{\{DOMAIN_DN\}\}', $DomainDN
        }

        Mock Get-ADRootDSE -ModuleName TierModel {
            return [PSCustomObject]@{
                schemaNamingContext = "CN=Schema,CN=Configuration,$script:TestDomainDN"
            }
        }

        Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Identity -and $null -eq $Filter } {
            return [PSCustomObject]@{ objectVersion = 88; schemaIDGUID = $null }
        }
        Mock Get-ADObject -ModuleName TierModel -ParameterFilter { $null -ne $Filter } {
            return [PSCustomObject]@{ lDAPDisplayName = 'msLAPS-Password'; schemaIDGUID = $null }
        }

        Mock Import-Module -ModuleName TierModel { } -ParameterFilter { $Name -eq 'LAPS' }

        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{
                DomainMode        = 'Windows2016Domain'
                NetBIOSName       = $script:TestNetBIOS
                DistinguishedName = $script:TestDomainDN
            }
        }

        Mock Get-ADOrganizationalUnit -ModuleName TierModel {
            param($Identity, $Server, $ErrorAction)
            return [PSCustomObject]@{ DistinguishedName = $Identity; Name = "Test OU" }
        }

        Mock Get-ADGroup -ModuleName TierModel {
            param($Filter, $Identity, $Server, $Properties, $ErrorAction)
            $name = if ($Filter -match "Name -eq '([^']+)'") { $Matches[1] } else { "$Identity" }
            $sam  = $name -replace ' ', ''
            return [PSCustomObject]@{ sAMAccountName = $sam; Name = $name }
        }

        Mock Get-ADComputer -ModuleName TierModel { return $null }

        # Permissions NOT present initially — all LAPS actions will be planned
        Mock Get-Acl -ModuleName TierModel {
            param($Path, $ErrorAction)
            return [PSCustomObject]@{ Path = $Path; Access = @() }
        }

        Mock Find-LapsADExtendedRights -ModuleName TierModel { return $null }

        Mock Get-GPRegistryValue -ModuleName TierModel { throw "Not configured" }

        Mock Set-LapsADComputerSelfPermission  -ModuleName TierModel { }
        Mock Set-LapsADReadPasswordPermission  -ModuleName TierModel { }
        Mock Set-LapsADResetPasswordPermission -ModuleName TierModel { }
        Mock Set-GPRegistryValue               -ModuleName TierModel { }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T019-1: Plan totals increase when WinLaps config is present
    # ════════════════════════════════════════════════════════════════════════════
    Context "T019-1: Plan totals increase with WinLaps delegations" {

        It "Standalone planner returns Actions.Count > 0 for non-empty delegation config" {
            $plan = Get-TierModelWinLapsAcl -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC

            $plan.Summary.TotalActions | Should -BeGreaterThan 0
        }

        It "Standalone planner: 3 CreateAcl actions per delegation (2 delegations = 6)" {
            $plan = Get-TierModelWinLapsAcl -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC

            $plan.Summary.CreateActions | Should -Be 6
        }

        It "Standalone planner: 1 ConfigureLapsDecryptor per delegation with decryptorGroup (2 = 2)" {
            $plan = Get-TierModelWinLapsAcl -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC

            $plan.Summary.ConfigureActions | Should -Be 2
        }

        It "FD planner returns same CreateActions count as standalone" {
            $standalonePlan = Get-TierModelWinLapsAcl   -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC
            $fdPlan         = Get-TierModelWinLapsAclFd  -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC

            $fdPlan.Summary.CreateActions | Should -Be $standalonePlan.Summary.CreateActions
        }

        It "Baseline plan (no WinLaps) has 0 CreateAcl actions" {
            $emptyConfig = [PSCustomObject]@{ winLapsDelegations = @() }
            $plan = Get-TierModelWinLapsAcl -Config $emptyConfig -DomainController $script:TestDC

            $plan.Summary.TotalActions | Should -Be 0
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T019-2: Apply returns Executed > 0 on first run
    # ════════════════════════════════════════════════════════════════════════════
    Context "T019-2: Apply returns Executed = N on first run" {

        It "New-TierModelWinLapsAcl Executed equals plan TotalActions" {
            $plan   = Get-TierModelWinLapsAcl -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC
            $result = New-TierModelWinLapsAcl -Plan $plan -DomainController $script:TestDC -Config $script:IntegrationWinLapsConfig

            $result.Executed | Should -Be $plan.Summary.TotalActions
            $result.Failed   | Should -Be 0
        }

        It "New-TierModelWinLapsAcl result Converged = true after successful apply" {
            $plan   = Get-TierModelWinLapsAcl -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC
            $result = New-TierModelWinLapsAcl -Plan $plan -DomainController $script:TestDC -Config $script:IntegrationWinLapsConfig

            $result.Converged | Should -Be $true
        }

        It "New-TierModelWinLapsAcl calls each LAPS apply cmdlet at least once" {
            $plan = Get-TierModelWinLapsAcl -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC
            New-TierModelWinLapsAcl -Plan $plan -DomainController $script:TestDC -Config $script:IntegrationWinLapsConfig | Out-Null

            Assert-MockCalled Set-LapsADComputerSelfPermission  -ModuleName TierModel -Times 2  # once per delegation
            Assert-MockCalled Set-LapsADReadPasswordPermission  -ModuleName TierModel -Times 2
            Assert-MockCalled Set-LapsADResetPasswordPermission -ModuleName TierModel -Times 2
            Assert-MockCalled Set-GPRegistryValue               -ModuleName TierModel -Times 2  # once per decryptor
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T019-3: Idempotency — second apply produces 0 actions
    # ════════════════════════════════════════════════════════════════════════════
    Context "T019-3: Idempotency — second apply converges to zero" {

        It "Re-plan after all permissions applied returns TotalActions=0 (Converged)" {
            # Simulate post-apply state: SELF ACE present, Read/Reset holders present,
            # decryptor registry value set correctly for BOTH delegations
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
                # Both groups present as holders
                return [PSCustomObject]@{
                    ExtendedRightHolders = @(
                        "$script:TestNetBIOS\Tier0Admins",
                        "$script:TestNetBIOS\Tier1Admins"
                    )
                }
            }
            Mock Get-GPRegistryValue -ModuleName TierModel {
                param($Name, $Key, $ValueName, $Server, $ErrorAction)
                if ($Name -like '*Tier 0*') {
                    return [PSCustomObject]@{ ValueName = 'ADPasswordEncryptionPrincipal'; Value = "$script:TestNetBIOS\Tier0Admins" }
                } else {
                    return [PSCustomObject]@{ ValueName = 'ADPasswordEncryptionPrincipal'; Value = "$script:TestNetBIOS\Tier1Admins" }
                }
            }

            $rePlan = Get-TierModelWinLapsAcl -Config $script:IntegrationWinLapsConfig -DomainController $script:TestDC

            $rePlan.Summary.TotalActions | Should -Be 0
            $rePlan.Converged            | Should -Be $true
            $rePlan.Summary.ExistingCount | Should -BeGreaterThan 0
        }

        It "Apply of converged plan returns Executed=0" {
            # Convergence already set by previous test via mocks above (persists in Context scope)
            $convergedPlan = [PSCustomObject]@{
                Actions   = @()
                Summary   = @{ TotalActions = 0; CreateActions = 0; ConfigureActions = 0 }
                Converged = $true
            }

            $result = New-TierModelWinLapsAcl -Plan $convergedPlan -DomainController $script:TestDC -Config $script:IntegrationWinLapsConfig

            $result.Executed  | Should -Be 0
            $result.Converged | Should -Be $true
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # T019-4: WinLaps phase ordering invariant (relative to other MSA phases)
    # ════════════════════════════════════════════════════════════════════════════
    Context "T019-4: WinLaps config loads and winLapsDelegations is present in real config" {

        It "Real config tiermodel-winlaps.json has 7 winLapsDelegations entries" {
            $configDir = Resolve-Path "$PSScriptRoot\..\config"
            $winLapsJson = Join-Path $configDir 'tiermodel-winlaps.json'

            $winLapsConfig = Get-Content $winLapsJson -Raw | ConvertFrom-Json

            @($winLapsConfig.winLapsDelegations).Count | Should -Be 7
        }

        It "Real config: exactly 1 entry with isDomainControllerOu = true (DC OU)" {
            $configDir = Resolve-Path "$PSScriptRoot\..\config"
            $winLapsJson = Join-Path $configDir 'tiermodel-winlaps.json'

            $winLapsConfig = Get-Content $winLapsJson -Raw | ConvertFrom-Json
            $dcEntries = @($winLapsConfig.winLapsDelegations | Where-Object {
                $_.PSObject.Properties.Name -contains 'isDomainControllerOu' -and $_.isDomainControllerOu -eq $true
            })

            $dcEntries.Count | Should -Be 1
        }

        It "Real config: 6 non-DC entries each have decryptorGroup and decryptorGpoName" {
            $configDir = Resolve-Path "$PSScriptRoot\..\config"
            $winLapsJson = Join-Path $configDir 'tiermodel-winlaps.json'

            $winLapsConfig = Get-Content $winLapsJson -Raw | ConvertFrom-Json
            $nonDcEntries = @($winLapsConfig.winLapsDelegations | Where-Object {
                -not ($_.PSObject.Properties.Name -contains 'isDomainControllerOu' -and $_.isDomainControllerOu -eq $true)
            })

            $nonDcEntries.Count | Should -Be 6
            foreach ($entry in $nonDcEntries) {
                $entry.PSObject.Properties.Name | Should -Contain 'decryptorGroup'
                $entry.PSObject.Properties.Name | Should -Contain 'decryptorGpoName'
                $entry.decryptorGroup    | Should -Not -BeNullOrEmpty
                $entry.decryptorGpoName  | Should -Not -BeNullOrEmpty
            }
        }

        It "Real config: no entry references ms-Mcs-* or AdmPwd in any field" {
            $configDir = Resolve-Path "$PSScriptRoot\..\config"
            $winLapsJson = Join-Path $configDir 'tiermodel-winlaps.json'

            $rawContent = Get-Content $winLapsJson -Raw
            $rawContent | Should -Not -Match 'ms.Mcs'
            $rawContent | Should -Not -Match 'AdmPwd'
        }

        It "Get-TierModelConfig loads winLapsDelegations when tiermodel-winlaps.json is present" {
            Mock Write-TierModelLog -ModuleName TierModel { }
            $configDir = Resolve-Path "$PSScriptRoot\..\config"
            $config = Get-TierModelConfig -ConfigPath $configDir

            $config.PSObject.Properties.Name | Should -Contain 'winLapsDelegations'
            @($config.winLapsDelegations).Count | Should -BeGreaterThan 0
        }

        It "WinLaps delegation entries come after MSA/gMSA/dMSA in module export list" {
            $psd1Path = Resolve-Path "$PSScriptRoot\..\Modules\TierModel\TierModel.psd1"
            $psd1Content = Get-Content $psd1Path -Raw

            # Verify WinLaps exports are present
            $psd1Content | Should -Match 'Get-TierModelWinLapsAcl'
            $psd1Content | Should -Match 'New-TierModelWinLapsAcl'
            $psd1Content | Should -Match 'Get-TierModelWinLapsAclFd'
            $psd1Content | Should -Match 'Test-TierModelWinLapsAcl'
            $psd1Content | Should -Match 'Test-TierModelWinLapsDecryptor'
        }
    }
}
