#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for Update-TierModelMembership.ps1 (v1.7.2, standalone script).

.DESCRIPTION
    Covers all testable pure/mockable functions:
      Resolve-ActiveSwitches, Initialize-BuiltInExclusions, Test-IsBuiltInExcluded,
      Test-IsCustomerExcluded, Resolve-OuDn, Resolve-GroupSam, Write-TmEvent,
      Initialize-Logging, Write-Log, Write-DebugLog, Invoke-TierReconciliation,
      Invoke-Tier2Operators, Invoke-Tier2Eud.

    No live Active Directory required. All AD cmdlets and internal AD-write helpers
    (Set-TmObjectAuthPolicy, Clear-TmObjectAuthPolicy) are mocked.

    Dot-source seam: the script returns early when InvocationName is '.', so
    dot-sourcing loads functions without executing main.

    NOT UNIT-TESTABLE (inline in main try-block, integration-covered by Joel lab UAT):
      - Exclusion parameter-pairing validation (-ExclusionAttribute without -ExclusionValue)
      - -NoExclusions safety gate (mutually exclusive with -ExclusionAttribute)
    RECOMMENDATION: Beast should extract these two gates into a Test-ExclusionParams
    function to make them independently unit-testable.

.NOTES
    Tags   : Unit, Membership
    Pester : 5.9.0 (pinned)
#>

# ---------------------------------------------------------------------------
# Switch order used in TestCases (discovery-time, so defined outside BeforeAll)
# ---------------------------------------------------------------------------
$script:AllGranularSwitches = @(
    'Tier0Operators', 'Tier0ServiceActt', 'Tier0PawDevices',
    'Tier0MemberServers', 'Tier0Staging',
    'Tier1Operators', 'Tier1ServiceActt', 'Tier1PawDevices',
    'Tier1MemberServers', 'Tier1Staging',
    'Tier2Operators', 'Tier2Eud', 'Tier2ServiceActt',
    'Tier2PawDevices', 'Tier2EudDevices'
)

Describe "Update-TierModelMembership" -Tag "Unit", "Membership" {

    BeforeAll {
        # ---- ADObject stub only when real ADObject (RSAT) is unavailable ----
        # When RSAT is installed, use the real ADObject with Add-Member NoteProperties.
        # When RSAT is absent (CI), define a minimal stub so New-TestAdObj still works.
        if (-not ('Microsoft.ActiveDirectory.Management.ADObject' -as [type])) {
            Add-Type -TypeDefinition @'
namespace Microsoft.ActiveDirectory.Management {
    public class ADObject {}
}
'@ -ErrorAction SilentlyContinue
        }

        # ---- Dot-source the script (loads functions; main block skipped) ----
        $script:ScriptUnderTest = Join-Path $PSScriptRoot '..\optional\Update-TierModelMembership.ps1'
        . $script:ScriptUnderTest

        # ---- Script-scope state expected by the functions -------------------
        $script:PreferredDc   = 'DC01.contoso.com'
        $script:DomainDN      = 'DC=contoso,DC=com'
        $script:CorrelationId = [guid]'aaaaaaaa-0000-0000-0000-000000000001'
        $script:TierChanges   = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
        $script:ScriptVersion = '1.7.2'
        $script:LogFilePath   = $null
        $script:DebugFilePath = $null
        $script:EventLogReady = $false

        # ---- Built-in exclusion users config (3 domain-join service accounts)
        $script:BuiltInUsersCfg = [PSCustomObject]@{
            users = @(
                [PSCustomObject]@{ samAccountName = 'svc-pawdomainjoin' }
                [PSCustomObject]@{ samAccountName = 'svc-t1srvdomainjoin' }
                [PSCustomObject]@{ samAccountName = 'svc-t2euddomainjoin' }
            )
        }
        Initialize-BuiltInExclusions -UsersConfig $script:BuiltInUsersCfg

        # ---- Test config objects --------------------------------------------
        $script:OuCfg = [PSCustomObject]@{
            organizationUnits = @(
                [PSCustomObject]@{ name = 'Tier 0 Accounts';
                    path = 'OU=Tier 0,OU=Tier Model Administration,DC=contoso,DC=com' }
                [PSCustomObject]@{ name = 'Tier 0 Service Accounts';
                    path = 'OU=Tier 0,OU=Tier Model Administration,DC=contoso,DC=com' }
                [PSCustomObject]@{ name = 'Tier 0 PAW Devices';
                    path = 'OU=Tier 0,OU=Tier Model Administration,DC=contoso,DC=com' }
                [PSCustomObject]@{ name = 'Tier 0 Member Servers'; path = 'DC=contoso,DC=com' }
                [PSCustomObject]@{ name = 'Tier 0 Server Staging';
                    path = 'OU=Tier 0 Member Servers,DC=contoso,DC=com' }
                [PSCustomObject]@{ name = 'Tier 2 Accounts';
                    path = 'OU=Tier 2,OU=Tier Model Administration,DC=contoso,DC=com' }
                [PSCustomObject]@{ name = 'Tier 2 End-User Devices'; path = 'DC=contoso,DC=com' }
                [PSCustomObject]@{ name = 'Disabled End-User Devices';
                    path = 'OU=Tier 2 End-User Devices,DC=contoso,DC=com' }
            )
        }
        $script:GroupCfg = [PSCustomObject]@{
            groups = @(
                [PSCustomObject]@{ name = 'Tier 0 Operators';              samaccountname = 'Tier0Operators' }
                [PSCustomObject]@{ name = 'Tier 0 Service Accounts';       samaccountname = 'Tier0ServiceAccounts' }
                [PSCustomObject]@{ name = 'Tier 2 Operators';              samaccountname = 'Tier2Operators' }
                [PSCustomObject]@{ name = 'Tier 2 Local Device Operators'; samaccountname = 'Tier2LocalDeviceOperators' }
                [PSCustomObject]@{ name = 'Tier 2 EUD Devices';            samaccountname = 'Tier2EUDDevices' }
            )
        }
        $script:AuthSiloCfg = [PSCustomObject]@{
            authenticationPolicies = @(
                [PSCustomObject]@{ name = '*- Tier 0 Authentication Policy' }
                [PSCustomObject]@{ name = '*- Tier 1 Authentication Policy' }
                [PSCustomObject]@{ name = '*- Tier 2 Authentication Policy' }
                [PSCustomObject]@{ name = '*- Tier 2 EUD Authentication Policy' }
            )
        }
        $script:TestCfg = @{
            OUs       = $script:OuCfg
            Groups    = $script:GroupCfg
            AuthSilos = $script:AuthSiloCfg
            Users     = $script:BuiltInUsersCfg
        }

        # Policy DN used across reconciliation tests
        $script:T0PolicyDN = ('CN=*- Tier 0 Authentication Policy,' +
            'CN=AuthN Policies,CN=AuthN Policy Configuration,' +
            'CN=Services,CN=Configuration,DC=contoso,DC=com')

        # ---- Helper: create a test AD object -----------------------------------
        # Uses PSObject.Properties.Add to bypass the ADEntityAdapter that is
        # registered when the real ActiveDirectory module loads. Add-Member goes
        # through the adapter and throws; PSObject.Properties.Add does not.
        # The ADObject stub type is created in the outer BeforeAll, but
        # New-TestAdObj defensively re-checks so it is safe to call from any
        # Context even if the outer BeforeAll's Add-Type executed before this.
        function New-TestAdObj {
            param([hashtable]$Props = @{})
            if (-not ('Microsoft.ActiveDirectory.Management.ADObject' -as [type])) {
                Add-Type -TypeDefinition @'
namespace Microsoft.ActiveDirectory.Management { public class ADObject {} }
'@ -ErrorAction SilentlyContinue
            }
            $o = New-Object 'Microsoft.ActiveDirectory.Management.ADObject'
            foreach ($kv in $Props.GetEnumerator()) {
                $o.PSObject.Properties.Add(
                    [System.Management.Automation.PSNoteProperty]::new($kv.Key, $kv.Value)
                )
            }
            return $o
        }

        # Wrapper: invokes Resolve-ActiveSwitches with specified switches set,
        # all others $false. Uses dynamic scoping so the function sees the vars.
        function Invoke-ResolveSwitches {
            param([string[]]$SetSwitches = @())
            $All              = [switch]$false
            $AllTier0         = [switch]$false
            $AllTier1         = [switch]$false
            $AllTier2         = [switch]$false
            $Tier0Operators   = [switch]$false
            $Tier0ServiceActt = [switch]$false
            $Tier0PawDevices  = [switch]$false
            $Tier0MemberServers = [switch]$false
            $Tier0Staging     = [switch]$false
            $Tier1Operators   = [switch]$false
            $Tier1ServiceActt = [switch]$false
            $Tier1PawDevices  = [switch]$false
            $Tier1MemberServers = [switch]$false
            $Tier1Staging     = [switch]$false
            $Tier2Operators   = [switch]$false
            $Tier2Eud         = [switch]$false
            $Tier2ServiceActt = [switch]$false
            $Tier2PawDevices  = [switch]$false
            $Tier2EudDevices  = [switch]$false
            foreach ($n in $SetSwitches) { Set-Variable -Name $n -Value ([switch]$true) }
            Resolve-ActiveSwitches
        }

        # Suppress all host output
        Mock Write-Host { }
    }

    # =========================================================================
    # 1. Resolve-ActiveSwitches
    # =========================================================================
    Context "Resolve-ActiveSwitches" {

        It "no explicit switch defaults to all 15" {
            (Invoke-ResolveSwitches).Count | Should -Be 15
        }

        It "no explicit switch returns switches in the mandatory 15-switch order" {
            Invoke-ResolveSwitches | Should -Be @(
                'Tier0Operators','Tier0ServiceActt','Tier0PawDevices',
                'Tier0MemberServers','Tier0Staging',
                'Tier1Operators','Tier1ServiceActt','Tier1PawDevices',
                'Tier1MemberServers','Tier1Staging',
                'Tier2Operators','Tier2Eud','Tier2ServiceActt',
                'Tier2PawDevices','Tier2EudDevices'
            )
        }

        It "-All expands to all 15" {
            (Invoke-ResolveSwitches -SetSwitches @('All')).Count | Should -Be 15
        }

        It "-All returns switches in the mandatory order" {
            Invoke-ResolveSwitches -SetSwitches @('All') | Should -Be @(
                'Tier0Operators','Tier0ServiceActt','Tier0PawDevices',
                'Tier0MemberServers','Tier0Staging',
                'Tier1Operators','Tier1ServiceActt','Tier1PawDevices',
                'Tier1MemberServers','Tier1Staging',
                'Tier2Operators','Tier2Eud','Tier2ServiceActt',
                'Tier2PawDevices','Tier2EudDevices'
            )
        }

        It "-AllTier0 returns exactly the 5 Tier0 switches in order" {
            Invoke-ResolveSwitches -SetSwitches @('AllTier0') |
                Should -Be @('Tier0Operators','Tier0ServiceActt','Tier0PawDevices',
                             'Tier0MemberServers','Tier0Staging')
        }

        It "-AllTier1 returns exactly the 5 Tier1 switches in order" {
            Invoke-ResolveSwitches -SetSwitches @('AllTier1') |
                Should -Be @('Tier1Operators','Tier1ServiceActt','Tier1PawDevices',
                             'Tier1MemberServers','Tier1Staging')
        }

        It "-AllTier2 returns exactly the 5 Tier2 switches in order" {
            Invoke-ResolveSwitches -SetSwitches @('AllTier2') |
                Should -Be @('Tier2Operators','Tier2Eud','Tier2ServiceActt',
                             'Tier2PawDevices','Tier2EudDevices')
        }

        It "-<Switch> alone returns only that switch" -TestCases @(
            @{ Switch = 'Tier0Operators' },   @{ Switch = 'Tier0ServiceActt' },
            @{ Switch = 'Tier0PawDevices' },  @{ Switch = 'Tier0MemberServers' },
            @{ Switch = 'Tier0Staging' },     @{ Switch = 'Tier1Operators' },
            @{ Switch = 'Tier1ServiceActt' }, @{ Switch = 'Tier1PawDevices' },
            @{ Switch = 'Tier1MemberServers' }, @{ Switch = 'Tier1Staging' },
            @{ Switch = 'Tier2Operators' },   @{ Switch = 'Tier2Eud' },
            @{ Switch = 'Tier2ServiceActt' }, @{ Switch = 'Tier2PawDevices' },
            @{ Switch = 'Tier2EudDevices' }
        ) {
            param($Switch)
            $r = Invoke-ResolveSwitches -SetSwitches @($Switch)
            $r | Should -HaveCount 1
            $r | Should -Be $Switch
        }

        It "two switches passed in reverse order are returned in mandatory order" {
            $r = Invoke-ResolveSwitches -SetSwitches @('Tier2Eud','Tier0Operators')
            $r | Should -Be @('Tier0Operators','Tier2Eud')
        }

        It "-AllTier0 -AllTier2 returns 10 switches with no Tier1 entries" {
            $r = Invoke-ResolveSwitches -SetSwitches @('AllTier0','AllTier2')
            $r | Should -HaveCount 10
            $r | Should -Not -Contain 'Tier1Operators'
            $r | Should -Not -Contain 'Tier1Staging'
        }

        It "-AllTier0 -AllTier2 preserves Tier0 first, Tier2 last in result" {
            $r = Invoke-ResolveSwitches -SetSwitches @('AllTier0','AllTier2')
            $r[0] | Should -Be 'Tier0Operators'
            $r[9] | Should -Be 'Tier2EudDevices'
        }

        It "-AllTier0 combined with explicit Tier0Operators produces no duplicates" {
            $r = Invoke-ResolveSwitches -SetSwitches @('AllTier0','Tier0Operators')
            $r | Should -HaveCount 5
            @($r | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
        }
    }

    # =========================================================================
    # 2. Built-in exclusions
    # =========================================================================
    Context "Initialize-BuiltInExclusions and Test-IsBuiltInExcluded" {

        BeforeEach {
            Initialize-BuiltInExclusions -UsersConfig $script:BuiltInUsersCfg
        }

        It "loads exactly 3 built-in exclusion accounts" {
            $script:BuiltInExclusions.Count | Should -Be 3
        }

        It "svc-pawdomainjoin is excluded" {
            Test-IsBuiltInExcluded -SamAccountName 'svc-pawdomainjoin' | Should -BeTrue
        }

        It "svc-t1srvdomainjoin is excluded" {
            Test-IsBuiltInExcluded -SamAccountName 'svc-t1srvdomainjoin' | Should -BeTrue
        }

        It "svc-t2euddomainjoin is excluded" {
            Test-IsBuiltInExcluded -SamAccountName 'svc-t2euddomainjoin' | Should -BeTrue
        }

        It "lookup is case-insensitive -- SVC-PAWDOMAINJOIN matches" {
            Test-IsBuiltInExcluded -SamAccountName 'SVC-PAWDOMAINJOIN' | Should -BeTrue
        }

        It "lookup is case-insensitive -- SVC-T2EUDdomainjoin matches" {
            Test-IsBuiltInExcluded -SamAccountName 'SVC-T2EUDdomainjoin' | Should -BeTrue
        }

        It "arbitrary account is NOT excluded" {
            Test-IsBuiltInExcluded -SamAccountName 'jdoe' | Should -BeFalse
        }

        It "partial SAM (svc-paw) does NOT match svc-pawdomainjoin" {
            Test-IsBuiltInExcluded -SamAccountName 'svc-paw' | Should -BeFalse
        }

        It "Initialize with empty users list yields 0 exclusions" {
            Initialize-BuiltInExclusions -UsersConfig ([PSCustomObject]@{ users = @() })
            $script:BuiltInExclusions.Count | Should -Be 0
        }
    }

    # =========================================================================
    # 3. Customer exclusion predicate
    # =========================================================================
    Context "Test-IsCustomerExcluded" {

        It "returns false when ExclusionAttribute is empty (disabled)" {
            $ExclusionAttribute = ''
            $ExclusionValue     = ''
            $obj = New-TestAdObj @{ sAMAccountName = 'u1'; adminDescription = 'TierModelExclude' }
            Test-IsCustomerExcluded -AdObject $obj | Should -BeFalse
        }

        It "returns true when attribute value matches ExclusionValue" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            $obj = New-TestAdObj @{ sAMAccountName = 'u2'; adminDescription = 'TierModelExclude' }
            Test-IsCustomerExcluded -AdObject $obj | Should -BeTrue
        }

        It "returns false when attribute value differs from ExclusionValue" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            $obj = New-TestAdObj @{ sAMAccountName = 'u3'; adminDescription = 'NotExcluded' }
            Test-IsCustomerExcluded -AdObject $obj | Should -BeFalse
        }

        It "returns false when attribute is present but null (production: Get-ADObject always returns requested property)" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            # Production: Get-ADObject -Properties adminDescription returns the
            # property even when unset in AD (value is $null, not absent).
            $obj = New-TestAdObj @{ sAMAccountName = 'u4'; adminDescription = $null }
            Test-IsCustomerExcluded -AdObject $obj | Should -BeFalse
        }

        It "returns false when attribute is an empty string on the object" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            $obj = New-TestAdObj @{ sAMAccountName = 'u5'; adminDescription = '' }
            Test-IsCustomerExcluded -AdObject $obj | Should -BeFalse
        }

        It "uses the configured attribute name not a hardcoded one" {
            $ExclusionAttribute = 'description'
            $ExclusionValue     = 'Exclude'
            $obj = New-TestAdObj @{ sAMAccountName = 'u6'; description = 'Exclude'; adminDescription = 'Other' }
            Test-IsCustomerExcluded -AdObject $obj | Should -BeTrue
        }

        It "wrong attribute configured -- value on different attribute returns false" {
            $ExclusionAttribute = 'description'
            $ExclusionValue     = 'TierModelExclude'
            # description = $null (configured attribute, no match); adminDescription
            # has the value but is on the wrong (unconfigured) attribute.
            $obj = New-TestAdObj @{ sAMAccountName = 'u7'; adminDescription = 'TierModelExclude'; description = $null }
            Test-IsCustomerExcluded -AdObject $obj | Should -BeFalse
        }
    }

    # =========================================================================
    # 4. Config resolver helpers (pure -- no AD)
    # =========================================================================
    Context "Resolve-OuDn" {

        It "returns DN starting with OU=OuName for a known OU" {
            $dn = Resolve-OuDn -OuName 'Tier 0 Accounts' -OuConfig $script:OuCfg
            $dn | Should -Match '^OU=Tier 0 Accounts,'
        }

        It "full-path OU (path already starts DC=) appends no extra DomainDN" {
            $dn = Resolve-OuDn -OuName 'Tier 0 Member Servers' -OuConfig $script:OuCfg
            ($dn -split 'DC=contoso').Count | Should -Be 2
        }

        It "relative-path OU appends DomainDN suffix" {
            $dn = Resolve-OuDn -OuName 'Tier 0 Server Staging' -OuConfig $script:OuCfg
            $dn | Should -Match 'DC=contoso,DC=com$'
        }

        It "unknown OU name throws with CONFIG ERROR" {
            { Resolve-OuDn -OuName 'NoSuchOU' -OuConfig $script:OuCfg } |
                Should -Throw '*CONFIG ERROR*'
        }
    }

    Context "Resolve-GroupSam" {

        It "returns correct SAM for Tier 0 Operators" {
            Resolve-GroupSam -GroupName 'Tier 0 Operators' -GroupConfig $script:GroupCfg |
                Should -Be 'Tier0Operators'
        }

        It "returns correct SAM for Tier 0 Service Accounts" {
            Resolve-GroupSam -GroupName 'Tier 0 Service Accounts' -GroupConfig $script:GroupCfg |
                Should -Be 'Tier0ServiceAccounts'
        }

        It "unknown group name throws with CONFIG ERROR" {
            { Resolve-GroupSam -GroupName 'NoSuchGroup' -GroupConfig $script:GroupCfg } |
                Should -Throw '*CONFIG ERROR*'
        }
    }

    # =========================================================================
    # 5. Write-TmEvent -- opt-in, no-throw, WhatIf detection
    #    NOTE: the exact pipe-delimited message text is built inside a try-block
    #    that calls [System.Diagnostics.EventLog]::WriteEntry (a .NET static).
    #    Pester 5.x cannot mock .NET static methods, so message-format assertions
    #    are integration-only (lab-validated by Joel). These tests cover the
    #    behavioural contract: opt-in gate, no-throw on failure, WhatIf.
    # =========================================================================
    Context "Write-TmEvent" {

        BeforeEach {
            $script:EventLogReady = $false
            $script:TierChanges   = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
            $script:CorrelationId = [guid]'bbbbbbbb-0000-0000-0000-000000000001'
        }

        It "is a no-op when EnableEventLog is false regardless of EventLogReady" {
            $EnableEventLog = [switch]$false
            $script:EventLogReady = $true
            { Write-TmEvent -Action START -ActiveSwitches @('Tier0Operators') } | Should -Not -Throw
        }

        It "is a no-op when EventLogReady is false even when EnableEventLog is true" {
            $EnableEventLog = [switch]$true
            $script:EventLogReady = $false
            { Write-TmEvent -Action START -ActiveSwitches @() } | Should -Not -Throw
        }

        It "START does not throw when EventLog source does not exist (best-effort)" {
            $EnableEventLog = [switch]$true
            $script:EventLogReady = $true
            { Write-TmEvent -Action START -ActiveSwitches @('Tier0Operators','Tier1Operators') } |
                Should -Not -Throw
        }

        It "COMPLETE does not throw when EventLog source does not exist" {
            $EnableEventLog = [switch]$true
            $script:EventLogReady = $true
            { Write-TmEvent -Action COMPLETE -ActiveSwitches @('Tier0Operators') `
                -Duration ([timespan]::Zero) } | Should -Not -Throw
        }

        It "ERROR does not throw when EventLog source does not exist" {
            $EnableEventLog = [switch]$true
            $script:EventLogReady = $true
            { Write-TmEvent -Action ERROR } | Should -Not -Throw
        }

        It "WhatIf mode with EnableEventLog false is a no-op and does not throw" {
            $EnableEventLog = [switch]$false
            $WhatIfPreference = $true
            { Write-TmEvent -Action START -ActiveSwitches @() } | Should -Not -Throw
        }
    }

    # =========================================================================
    # 6. Initialize-Logging
    # =========================================================================
    Context "Initialize-Logging" {

        BeforeEach {
            $script:LogFilePath = $null
            Mock Test-Path  { $false }
            Mock New-Item   { }
            Mock Get-ChildItem { @() }
            Mock Remove-Item { }
        }

        It "is a no-op when EnableLogging is false" {
            $EnableLogging = [switch]$false
            Initialize-Logging
            $script:LogFilePath | Should -BeNullOrEmpty
        }

        It "sets LogFilePath (non-null) when EnableLogging is true" {
            $EnableLogging = [switch]$true
            $JobId = 'TestJob'
            Initialize-Logging
            $script:LogFilePath | Should -Not -BeNullOrEmpty
        }

        It "LogFilePath contains the JobId" {
            $EnableLogging = [switch]$true
            $JobId = 'UniqueJob42'
            Initialize-Logging
            $script:LogFilePath | Should -Match 'UniqueJob42'
        }

        It "LogFilePath matches name.JobId.YYYYMMDD-HHmmss.log pattern" {
            $EnableLogging = [switch]$true
            $JobId = 'Adhoc'
            Initialize-Logging
            $script:LogFilePath | Should -Match `
                'Update-TierModelMembership\.[A-Za-z0-9._-]+\.\d{8}-\d{6}\.log$'
        }

        It "prunes log files older than 7 days" {
            $EnableLogging = [switch]$true
            $JobId = 'Prune'
            $stale = [PSCustomObject]@{
                LastWriteTime = (Get-Date).AddDays(-8)
                FullName      = 'C:\fake\stale.log'
            }
            Mock Get-ChildItem { @($stale) }
            Initialize-Logging
            Should -Invoke Remove-Item -Times 1
        }

        It "does not prune log files that are 6 days old" {
            $EnableLogging = [switch]$true
            $JobId = 'Prune'
            $fresh = [PSCustomObject]@{
                LastWriteTime = (Get-Date).AddDays(-6)
                FullName      = 'C:\fake\fresh.log'
            }
            Mock Get-ChildItem { @($fresh) }
            Initialize-Logging
            Should -Invoke Remove-Item -Times 0
        }
    }

    # =========================================================================
    # 7. Write-Log -- content and WhatIf immunity
    # =========================================================================
    Context "Write-Log" {

        It "writes the message to LogFilePath" {
            $script:LogFilePath = Join-Path $TestDrive 'wl-msg.log'
            Write-Log -Message 'Hello log'
            Get-Content $script:LogFilePath | Should -Match 'Hello log'
        }

        It "prepends a yyyy-MM-dd HH:mm:ss timestamp" {
            $script:LogFilePath = Join-Path $TestDrive 'wl-ts.log'
            Write-Log -Message 'ts check'
            Get-Content $script:LogFilePath | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
        }

        It "default level tag is [Information]" {
            $script:LogFilePath = Join-Path $TestDrive 'wl-lvl.log'
            Write-Log -Message 'info msg'
            Get-Content $script:LogFilePath | Should -Match '\[Information\]'
        }

        It "Warning level produces [Warning] tag" {
            $script:LogFilePath = Join-Path $TestDrive 'wl-warn.log'
            Write-Log -Message 'warn msg' -Level Warning
            Get-Content $script:LogFilePath | Should -Match '\[Warning\]'
        }

        It "null LogFilePath: no file I/O, does not throw" {
            $script:LogFilePath = $null
            { Write-Log -Message 'silent' } | Should -Not -Throw
        }

        It "WhatIf immunity: file is created and line is written when WhatIfPreference=true" {
            $script:LogFilePath = Join-Path $TestDrive 'wl-wi.log'
            $WhatIfPreference = $true
            Write-Log -Message 'WHATIF: preview line'
            Test-Path $script:LogFilePath | Should -BeTrue
            Get-Content $script:LogFilePath | Should -Match 'WHATIF: preview line'
        }
    }

    # =========================================================================
    # 8. Write-DebugLog
    # =========================================================================
    Context "Write-DebugLog" {

        It "is a no-op when DebugFilePath is null" {
            $script:DebugFilePath = $null
            { Write-DebugLog -Message 'debug msg' } | Should -Not -Throw
        }

        It "writes the message to DebugFilePath" {
            $script:DebugFilePath = Join-Path $TestDrive 'dl-msg.log'
            Write-DebugLog -Message 'debug payload'
            Get-Content $script:DebugFilePath -Raw | Should -Match 'debug payload'
        }

        It "appends Data pairs as key=value separated by semicolons" {
            $script:DebugFilePath = Join-Path $TestDrive 'dl-data.log'
            Write-DebugLog -Message 'ctx' -Data @{ Alpha = 'A'; Beta = 'B' }
            $c = Get-Content $script:DebugFilePath -Raw
            $c | Should -Match 'Alpha=A'
            $c | Should -Match 'Beta=B'
        }

        It "WhatIf immunity: file is written when WhatIfPreference=true" {
            $script:DebugFilePath = Join-Path $TestDrive 'dl-wi.log'
            $WhatIfPreference = $true
            Write-DebugLog -Message 'wi debug'
            Test-Path $script:DebugFilePath | Should -BeTrue
        }
    }

    # =========================================================================
    # 9. Invoke-TierReconciliation -- happy path and counters
    # =========================================================================
    Context "Invoke-TierReconciliation -- happy path" {

        BeforeAll {
            $script:HappyUserA = New-TestAdObj @{
                sAMAccountName             = 'userA'
                DistinguishedName          = 'CN=userA,OU=T0,DC=contoso,DC=com'
                'msDS-AssignedAuthNPolicy' = $null
            }
            $script:HappyUserB = New-TestAdObj @{
                sAMAccountName             = 'userB'
                DistinguishedName          = 'CN=userB,OU=T0,DC=contoso,DC=com'
                'msDS-AssignedAuthNPolicy' = $script:T0PolicyDN
            }

            Mock Get-ADOrganizationalUnit { }
            Mock Get-ADGroup { [PSCustomObject]@{ DistinguishedName = 'CN=G,DC=contoso,DC=com' } }
            Mock Get-ADRootDSE {
                [PSCustomObject]@{ configurationNamingContext = 'CN=Configuration,DC=contoso,DC=com' }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $Filter } {
                [PSCustomObject]@{ DistinguishedName = $script:T0PolicyDN }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:HappyUserA, $script:HappyUserB)
            }
            Mock Get-ADGroupMember {
                @([PSCustomObject]@{ distinguishedName = 'CN=userB,OU=T0,DC=contoso,DC=com' })
            }
            Mock Set-TmObjectAuthPolicy { }
            Mock Clear-TmObjectAuthPolicy { }
            Mock Add-ADGroupMember { }
        }

        BeforeEach {
            $ExclusionAttribute = ''
            $script:TierChanges = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
        }

        It "returns a result object" {
            $r = Invoke-TierReconciliation -SwitchName 'T0Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r | Should -Not -BeNullOrEmpty
        }

        It "Scanned equals the number of enumerated objects (2)" {
            $r = Invoke-TierReconciliation -SwitchName 'T0Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r.Scanned | Should -Be 2
        }

        It "PolicyAssigned = 1 (userA has no policy)" {
            $r = Invoke-TierReconciliation -SwitchName 'T0Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r.PolicyAssigned | Should -Be 1
            Should -Invoke Set-TmObjectAuthPolicy -Times 1
        }

        It "GroupAdded = 1 (userA not yet a member)" {
            $r = Invoke-TierReconciliation -SwitchName 'T0Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r.GroupAdded | Should -Be 1
            Should -Invoke Add-ADGroupMember -Times 1
        }

        It "AlreadyCurrent = 1 (userB already has correct policy and is a member)" {
            $r = Invoke-TierReconciliation -SwitchName 'T0Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r.AlreadyCurrent | Should -Be 1
        }

        It "PolicyCleared = 0 in happy path" {
            $r = Invoke-TierReconciliation -SwitchName 'T0Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r.PolicyCleared | Should -Be 0
        }

        It "group-only reconciliation (null PolicyName) adds member, no policy calls" {
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:HappyUserA)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Computers' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName $null -ObjectFilter '(objectClass=computer)'
            $r.GroupAdded    | Should -Be 1
            $r.PolicyAssigned | Should -Be 0
            Should -Invoke Set-TmObjectAuthPolicy -Times 0
        }

        It "already-member user is not added again; only userA is added" {
            $ExclusionAttribute = ''
            $r = Invoke-TierReconciliation -SwitchName 'T0Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            # userB is already a member; only userA gets GroupAdded
            $r.GroupAdded | Should -Be 1
        }
    }

    # =========================================================================
    # 10. Invoke-TierReconciliation -- exclusion enforcement
    # =========================================================================
    Context "Invoke-TierReconciliation -- exclusion enforcement" {

        BeforeAll {
            $script:ExclWithPol = New-TestAdObj @{
                sAMAccountName             = 'excl-acct'
                DistinguishedName          = 'CN=excl-acct,OU=T0,DC=contoso,DC=com'
                'msDS-AssignedAuthNPolicy' = $script:T0PolicyDN
                adminDescription           = 'TierModelExclude'
            }
            $script:ExclNoPol = New-TestAdObj @{
                sAMAccountName             = 'excl-nopol'
                DistinguishedName          = 'CN=excl-nopol,OU=T0,DC=contoso,DC=com'
                'msDS-AssignedAuthNPolicy' = $null
                adminDescription           = 'TierModelExclude'
            }
            $script:BuiltInUser = New-TestAdObj @{
                sAMAccountName             = 'svc-pawdomainjoin'
                DistinguishedName          = 'CN=svc-pawdomainjoin,OU=T0,DC=contoso,DC=com'
                'msDS-AssignedAuthNPolicy' = $script:T0PolicyDN
            }
            $script:NormalUser = New-TestAdObj @{
                sAMAccountName             = 'normal'
                DistinguishedName          = 'CN=normal,OU=T0,DC=contoso,DC=com'
                'msDS-AssignedAuthNPolicy' = $null
            }

            Mock Get-ADOrganizationalUnit { }
            Mock Get-ADGroup { [PSCustomObject]@{ DistinguishedName = 'CN=G,DC=contoso,DC=com' } }
            Mock Get-ADRootDSE {
                [PSCustomObject]@{ configurationNamingContext = 'CN=Configuration,DC=contoso,DC=com' }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $Filter } {
                [PSCustomObject]@{ DistinguishedName = $script:T0PolicyDN }
            }
            Mock Set-TmObjectAuthPolicy { }
            Mock Clear-TmObjectAuthPolicy { }
            Mock Add-ADGroupMember { }
        }

        BeforeEach {
            Initialize-BuiltInExclusions -UsersConfig $script:BuiltInUsersCfg
            $script:TierChanges = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
        }

        It "customer-excluded user with policy: Excluded++ and policy cleared" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:ExclWithPol)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Svc' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0ServiceAccounts' `
                -PolicyName '*- Tier 0 Authentication Policy' -ApplyExclusionToGroup $true
            $r.Excluded      | Should -Be 1
            $r.PolicyCleared | Should -Be 1
            Should -Invoke Clear-TmObjectAuthPolicy -Times 1
        }

        It "customer-excluded user with ApplyExclusionToGroup=true is NOT added to group" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:ExclWithPol)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Svc' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0ServiceAccounts' `
                -PolicyName '*- Tier 0 Authentication Policy' -ApplyExclusionToGroup $true
            $r.GroupAdded | Should -Be 0
            Should -Invoke Add-ADGroupMember -Times 0
        }

        It "customer-excluded operator (ApplyExclusionToGroup=false): policy cleared but added to group" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:ExclWithPol)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy' -ApplyExclusionToGroup $false
            $r.PolicyCleared | Should -Be 1
            $r.GroupAdded    | Should -Be 1
        }

        It "customer-excluded user with NO policy: no clear call, Excluded incremented" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:ExclNoPol)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Svc' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0ServiceAccounts' `
                -PolicyName '*- Tier 0 Authentication Policy' -ApplyExclusionToGroup $true
            $r.Excluded      | Should -Be 1
            $r.PolicyCleared | Should -Be 0
            Should -Invoke Clear-TmObjectAuthPolicy -Times 0
        }

        It "built-in excluded account clears policy (no customer exclusion needed)" {
            $ExclusionAttribute = ''
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:BuiltInUser)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy' -ApplyExclusionToGroup $false
            $r.Excluded      | Should -Be 1
            $r.PolicyCleared | Should -Be 1
            Should -Invoke Clear-TmObjectAuthPolicy -Times 1
        }

        It "non-excluded user with empty ExclusionAttribute receives policy normally" {
            $ExclusionAttribute = ''
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:NormalUser)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy' -ApplyExclusionToGroup $false
            $r.PolicyAssigned | Should -Be 1
            $r.Excluded       | Should -Be 0
        }

        It "Excluded counter is separate from PolicyCleared (excluded-no-policy still counts Excluded)" {
            $ExclusionAttribute = 'adminDescription'
            $ExclusionValue     = 'TierModelExclude'
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:ExclNoPol)
            }
            Mock Get-ADGroupMember { @() }
            $r = Invoke-TierReconciliation -SwitchName 'Svc' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0ServiceAccounts' `
                -PolicyName '*- Tier 0 Authentication Policy' -ApplyExclusionToGroup $true
            $r.Excluded | Should -Be 1
            $r.AlreadyCurrent | Should -Be 1
        }
    }

    # =========================================================================
    # 11. Invoke-TierReconciliation -- WhatIf mode
    # =========================================================================
    Context "Invoke-TierReconciliation -- WhatIf mode" {

        BeforeAll {
            $script:WiUser = New-TestAdObj @{
                sAMAccountName             = 'wiUser'
                DistinguishedName          = 'CN=wiUser,OU=T0,DC=contoso,DC=com'
                'msDS-AssignedAuthNPolicy' = $null
            }

            Mock Get-ADOrganizationalUnit { }
            Mock Get-ADGroup { [PSCustomObject]@{ DistinguishedName = 'CN=G,DC=contoso,DC=com' } }
            Mock Get-ADRootDSE {
                [PSCustomObject]@{ configurationNamingContext = 'CN=Configuration,DC=contoso,DC=com' }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $Filter } {
                [PSCustomObject]@{ DistinguishedName = $script:T0PolicyDN }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } { @($script:WiUser) }
            Mock Get-ADGroupMember { @() }
            Mock Set-TmObjectAuthPolicy { }
            Mock Clear-TmObjectAuthPolicy { }
            Mock Add-ADGroupMember { }
        }

        BeforeEach {
            $ExclusionAttribute = ''
            $script:TierChanges = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
            $script:LogFilePath = $null
        }

        It "WhatIf: Set-TmObjectAuthPolicy is never called" {
            $WhatIfPreference = $true
            Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            Should -Invoke Set-TmObjectAuthPolicy -Times 0
        }

        It "WhatIf: Add-ADGroupMember is never called" {
            $WhatIfPreference = $true
            Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            Should -Invoke Add-ADGroupMember -Times 0
        }

        It "WhatIf: GroupAdded counter stays at 0" {
            $WhatIfPreference = $true
            $r = Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r.GroupAdded | Should -Be 0
        }

        It "WhatIf: PolicyAssigned counter stays at 0" {
            $WhatIfPreference = $true
            $r = Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            $r.PolicyAssigned | Should -Be 0
        }

        It "WhatIf: WHATIF preview lines are written to log (WhatIf immunity)" {
            $WhatIfPreference = $true
            $script:LogFilePath = Join-Path $TestDrive 'wi-recon.log'
            Invoke-TierReconciliation -SwitchName 'Ops' `
                -SourceOuDn 'OU=T0,DC=contoso,DC=com' -TargetGroupSam 'Tier0Operators' `
                -PolicyName '*- Tier 0 Authentication Policy'
            Test-Path $script:LogFilePath | Should -BeTrue
            Get-Content $script:LogFilePath -Raw | Should -Match 'WHATIF:'
        }
    }

    # =========================================================================
    # 12. Invoke-TierReconciliation -- ExcludeChildOuDn filtering
    # =========================================================================
    Context "Invoke-TierReconciliation -- ExcludeChildOuDn" {

        BeforeAll {
            $script:StagingOU  = 'OU=Tier 0 Server Staging,OU=Tier 0 Member Servers,DC=contoso,DC=com'
            $script:StagingCmp = New-TestAdObj @{
                sAMAccountName    = 'SRV-STAGING'
                DistinguishedName = "CN=SRV-STAGING,$script:StagingOU"
            }
            $script:ProdCmp = New-TestAdObj @{
                sAMAccountName    = 'SRV-PROD'
                DistinguishedName = 'CN=SRV-PROD,OU=Tier 0 Member Servers,DC=contoso,DC=com'
            }

            Mock Get-ADOrganizationalUnit { }
            Mock Get-ADGroup { [PSCustomObject]@{ DistinguishedName = 'CN=G,DC=contoso,DC=com' } }
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:StagingCmp, $script:ProdCmp)
            }
            Mock Get-ADGroupMember { @() }
            Mock Add-ADGroupMember { }
        }

        BeforeEach {
            $ExclusionAttribute = ''
            $script:TierChanges = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
        }

        It "ExcludeChildOuDn: Scanned = 1 (staging computer is post-filtered out)" {
            $r = Invoke-TierReconciliation -SwitchName 'T0MemberSvr' `
                -SourceOuDn 'OU=Tier 0 Member Servers,DC=contoso,DC=com' `
                -TargetGroupSam 'Tier0MemberServers' -PolicyName $null `
                -ObjectFilter '(objectClass=computer)' -ExcludeChildOuDn $script:StagingOU
            $r.Scanned | Should -Be 1
        }

        It "ExcludeChildOuDn: only production computer is added to the group" {
            $r = Invoke-TierReconciliation -SwitchName 'T0MemberSvr' `
                -SourceOuDn 'OU=Tier 0 Member Servers,DC=contoso,DC=com' `
                -TargetGroupSam 'Tier0MemberServers' -PolicyName $null `
                -ObjectFilter '(objectClass=computer)' -ExcludeChildOuDn $script:StagingOU
            $r.GroupAdded | Should -Be 1
        }

        It "without ExcludeChildOuDn both computers are scanned and added" {
            $r = Invoke-TierReconciliation -SwitchName 'T0MemberSvr' `
                -SourceOuDn 'OU=Tier 0 Member Servers,DC=contoso,DC=com' `
                -TargetGroupSam 'Tier0MemberServers' -PolicyName $null `
                -ObjectFilter '(objectClass=computer)'
            $r.Scanned   | Should -Be 2
            $r.GroupAdded | Should -Be 2
        }

        It "production computer DN is passed to Add-ADGroupMember when staging is excluded" {
            Invoke-TierReconciliation -SwitchName 'T0MemberSvr' `
                -SourceOuDn 'OU=Tier 0 Member Servers,DC=contoso,DC=com' `
                -TargetGroupSam 'Tier0MemberServers' -PolicyName $null `
                -ObjectFilter '(objectClass=computer)' -ExcludeChildOuDn $script:StagingOU
            Should -Invoke Add-ADGroupMember -Times 1 `
                -ParameterFilter { $Members -like '*SRV-PROD*' }
        }
    }

    # =========================================================================
    # 13. Invoke-Tier2Operators -- operator/EUD disambiguation
    # =========================================================================
    Context "Invoke-Tier2Operators -- disambiguation" {

        BeforeAll {
            $script:T2Op_opDN   = 'CN=opUser,OU=T2,DC=contoso,DC=com'
            $script:T2Op_ldoDN  = 'CN=ldoUser,OU=T2,DC=contoso,DC=com'
            $script:T2Op_bothDN = 'CN=bothUser,OU=T2,DC=contoso,DC=com'
            $script:T2Op_noDN   = 'CN=noGrpUser,OU=T2,DC=contoso,DC=com'

            $script:T2OpUser    = New-TestAdObj @{ sAMAccountName = 'opUser';
                DistinguishedName = $script:T2Op_opDN;   'msDS-AssignedAuthNPolicy' = $null }
            $script:T2LdoUser   = New-TestAdObj @{ sAMAccountName = 'ldoUser';
                DistinguishedName = $script:T2Op_ldoDN;  'msDS-AssignedAuthNPolicy' = $null }
            $script:T2BothUser  = New-TestAdObj @{ sAMAccountName = 'bothUser';
                DistinguishedName = $script:T2Op_bothDN; 'msDS-AssignedAuthNPolicy' = $null }
            $script:T2NoGrpUser = New-TestAdObj @{ sAMAccountName = 'noGrpUser';
                DistinguishedName = $script:T2Op_noDN;   'msDS-AssignedAuthNPolicy' = $null }

            Mock Get-ADOrganizationalUnit { }
            Mock Get-ADGroup { [PSCustomObject]@{ DistinguishedName = 'CN=G,DC=contoso,DC=com' } }
            Mock Get-ADRootDSE {
                [PSCustomObject]@{ configurationNamingContext = 'CN=Configuration,DC=contoso,DC=com' }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $Filter } {
                [PSCustomObject]@{ DistinguishedName =
                    'CN=*- Tier 2 Authentication Policy,CN=AuthN Policies,' +
                    'CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=contoso,DC=com' }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:T2OpUser, $script:T2LdoUser, $script:T2BothUser, $script:T2NoGrpUser)
            }
            # Invoke-Tier2Operators calls Get-ADGroupMember TWICE, always in this order:
            #   call 1: Tier2Operators members  (opUser + bothUser)
            #   call 2: Tier2LocalDeviceOperators members  (ldoUser + bothUser)
            # A script-scope counter differentiates the two calls reliably.
            $script:T2OpGrpCall = 0
            Mock Get-ADGroupMember {
                $script:T2OpGrpCall++
                if ($script:T2OpGrpCall % 2 -eq 1) {
                    @([PSCustomObject]@{ distinguishedName = $script:T2Op_opDN }
                      [PSCustomObject]@{ distinguishedName = $script:T2Op_bothDN })
                } else {
                    @([PSCustomObject]@{ distinguishedName = $script:T2Op_ldoDN }
                      [PSCustomObject]@{ distinguishedName = $script:T2Op_bothDN })
                }
            }
            Mock Set-TmObjectAuthPolicy { }
            Mock Add-ADGroupMember { }
        }

        BeforeEach {
            $ExclusionAttribute = ''
            $script:TierChanges = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
            Initialize-BuiltInExclusions -UsersConfig $script:BuiltInUsersCfg
            $script:T2OpGrpCall = 0
        }

        It "Scanned includes all 4 users from the OU" {
            $r = Invoke-Tier2Operators -Config $script:TestCfg
            $r.Scanned | Should -Be 4
        }

        It "pure LDO user (ldoUser) is skipped as EUD: SkippedEud = 1" {
            $r = Invoke-Tier2Operators -Config $script:TestCfg
            $r.SkippedEud | Should -Be 1
        }

        It "both-groups user (bothUser) is classified as operator (not skipped)" {
            $r = Invoke-Tier2Operators -Config $script:TestCfg
            # 4 scanned - 1 ldoUser skipped = 3 operators processed
            $r.Scanned - $r.SkippedEud | Should -Be 3
        }

        It "no-group user (noGrpUser) defaults to operator and is added to group" {
            $r = Invoke-Tier2Operators -Config $script:TestCfg
            # noGrpUser is not in isOpSet, so it gets added
            $r.GroupAdded | Should -BeGreaterOrEqual 1
        }

        It "3 operator users each receive policy assignment (all had no policy)" {
            $r = Invoke-Tier2Operators -Config $script:TestCfg
            $r.PolicyAssigned | Should -Be 3
        }

        It "does not throw" {
            { Invoke-Tier2Operators -Config $script:TestCfg } | Should -Not -Throw
        }
    }

    # =========================================================================
    # 14. Invoke-Tier2Eud -- EUD/operator disambiguation
    # =========================================================================
    Context "Invoke-Tier2Eud -- disambiguation" {

        BeforeAll {
            $script:T2Eud_opDN2   = 'CN=opUser2,OU=T2,DC=contoso,DC=com'
            $script:T2Eud_ldoDN2  = 'CN=ldoUser2,OU=T2,DC=contoso,DC=com'
            $script:T2Eud_bothDN2 = 'CN=bothUser2,OU=T2,DC=contoso,DC=com'
            $script:T2Eud_noDN2   = 'CN=noGrpUser2,OU=T2,DC=contoso,DC=com'

            $script:E2OpUser    = New-TestAdObj @{ sAMAccountName = 'opUser2';
                DistinguishedName = $script:T2Eud_opDN2;   'msDS-AssignedAuthNPolicy' = $null }
            $script:E2LdoUser   = New-TestAdObj @{ sAMAccountName = 'ldoUser2';
                DistinguishedName = $script:T2Eud_ldoDN2;  'msDS-AssignedAuthNPolicy' = $null }
            $script:E2BothUser  = New-TestAdObj @{ sAMAccountName = 'bothUser2';
                DistinguishedName = $script:T2Eud_bothDN2; 'msDS-AssignedAuthNPolicy' = $null }
            $script:E2NoGrpUser = New-TestAdObj @{ sAMAccountName = 'noGrpUser2';
                DistinguishedName = $script:T2Eud_noDN2;   'msDS-AssignedAuthNPolicy' = $null }

            Mock Get-ADOrganizationalUnit { }
            Mock Get-ADGroup { [PSCustomObject]@{ DistinguishedName = 'CN=G,DC=contoso,DC=com' } }
            Mock Get-ADRootDSE {
                [PSCustomObject]@{ configurationNamingContext = 'CN=Configuration,DC=contoso,DC=com' }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $Filter } {
                [PSCustomObject]@{ DistinguishedName =
                    'CN=*- Tier 2 EUD Authentication Policy,CN=AuthN Policies,' +
                    'CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=contoso,DC=com' }
            }
            Mock Get-ADObject -ParameterFilter { $null -ne $LDAPFilter } {
                @($script:E2OpUser, $script:E2LdoUser, $script:E2BothUser, $script:E2NoGrpUser)
            }
            $script:T2EudGrpCall = 0
            Mock Get-ADGroupMember {
                $script:T2EudGrpCall++
                if ($script:T2EudGrpCall % 2 -eq 1) {
                    @([PSCustomObject]@{ distinguishedName = $script:T2Eud_opDN2 }
                      [PSCustomObject]@{ distinguishedName = $script:T2Eud_bothDN2 })
                } else {
                    @([PSCustomObject]@{ distinguishedName = $script:T2Eud_ldoDN2 }
                      [PSCustomObject]@{ distinguishedName = $script:T2Eud_bothDN2 })
                }
            }
            Mock Set-TmObjectAuthPolicy { }
            Mock Add-ADGroupMember { }
        }

        BeforeEach {
            $ExclusionAttribute = ''
            $script:TierChanges = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }
            Initialize-BuiltInExclusions -UsersConfig $script:BuiltInUsersCfg
            $script:T2EudGrpCall = 0
        }

        It "Scanned includes all 4 users" {
            $r = Invoke-Tier2Eud -Config $script:TestCfg
            $r.Scanned | Should -Be 4
        }

        It "operator-only user (opUser2) is skipped: SkippedOperator incremented" {
            $r = Invoke-Tier2Eud -Config $script:TestCfg
            $r.SkippedOperator | Should -BeGreaterOrEqual 1
        }

        It "both-groups user (bothUser2) is skipped -- operator wins" {
            $r = Invoke-Tier2Eud -Config $script:TestCfg
            # opUser2 (op-only) + bothUser2 (both) + noGrpUser2 (no group) all skipped
            $r.SkippedOperator | Should -Be 3
        }

        It "pure LDO user (ldoUser2) receives EUD policy (PolicyAssigned = 1)" {
            $r = Invoke-Tier2Eud -Config $script:TestCfg
            $r.PolicyAssigned | Should -Be 1
            Should -Invoke Set-TmObjectAuthPolicy -Times 1
        }

        It "never calls Add-ADGroupMember (LDO membership is customer-managed)" {
            Invoke-Tier2Eud -Config $script:TestCfg
            Should -Invoke Add-ADGroupMember -Times 0
        }

        It "does not throw" {
            { Invoke-Tier2Eud -Config $script:TestCfg } | Should -Not -Throw
        }
    }
}
