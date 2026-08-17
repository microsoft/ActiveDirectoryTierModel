#Requires -Modules Pester
<#
.SYNOPSIS
Unit tests for the domain-root SACL audit rule cmdlets (-EnableAuditing feature, v1.3.0).

Covers:
  - Get-TierModelAuditRule     (standalone planner)
  - New-TierModelAuditRule     (UNION-converge apply)
  - Test-TierModelAuditRule    (drift detection)
  - Get-TierModelAuditRuleFd   (FullDeployment wrapper)
  - Get-TierModelConfig        (tiermodel-audit.json -> domainAuditRule segment)

.NOTES
Created : 2026-08-14
Tags    : Unit, AuditRule
All AD/SACL operations are mocked — no live AD required.
#>

Describe "Domain Audit Rule Operations" -Tag "Unit", "AuditRule" {

    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        $script:TestDC       = "DC01.test.local"
        $script:TestDomainDN = "DC=test,DC=local"

        # The 9 canonical rights and their bit values
        $script:AllRights = @('CreateChild','DeleteChild','WriteProperty','Self','Delete','DeleteTree','WriteDacl','WriteOwner','ExtendedRight')
        $script:AllRightsInt = 0
        foreach ($r in $script:AllRights) { $script:AllRightsInt = $script:AllRightsInt -bor [int][System.DirectoryServices.ActiveDirectoryRights]$r }

        # Canonical audit config (mimics Get-TierModelConfig with tiermodel-audit.json present)
        $script:AuditConfig = [PSCustomObject]@{
            domainAuditRule = [PSCustomObject]@{
                targetDn    = '{{DOMAIN_DN}}'
                trusteeSid  = 'S-1-1-0'
                auditFlag   = 'Success'
                inheritance = 'All'
                rights      = $script:AllRights
            }
        }

        # Config with no domainAuditRule property at all
        $script:ConfigNoProperty = [PSCustomObject]@{ groups = @() }

        # Config where domainAuditRule is present but null
        $script:ConfigNullRule = [PSCustomObject]@{ domainAuditRule = $null }

        # ── Helper: build a mock ActiveDirectoryAuditRule-shaped ACE ──────────────
        function New-MockAuditAce {
            param(
                $Rights          = 'CreateChild',
                $AuditFlags      = 'Success',
                $InheritanceType = 'All',
                [bool]$IsInherited = $false,
                $Sid             = 'S-1-1-0'
            )
            [PSCustomObject]@{
                IdentityReference     = [PSCustomObject]@{ Value = $Sid }
                ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]$Rights
                AuditFlags            = [System.Security.AccessControl.AuditFlags]$AuditFlags
                InheritanceType       = [System.DirectoryServices.ActiveDirectorySecurityInheritance]$InheritanceType
                IsInherited           = $IsInherited
            }
        }

        # ── Helper: build a mock ACL exposing GetAuditRules/Remove/Add ────────────
        function New-MockAcl {
            param([object[]]$Aces = @())
            $acl = [PSCustomObject]@{ Path = "AD:$script:TestDomainDN" }
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($a in $Aces) { $list.Add($a) }
            $acl | Add-Member -MemberType NoteProperty -Name '_Aces' -Value $list
            $acl | Add-Member -MemberType ScriptMethod -Name 'GetAuditRules' -Value { param($e,$i,$t) return $this._Aces }
            $acl | Add-Member -MemberType ScriptMethod -Name 'RemoveAuditRuleSpecific' -Value { param($rule) [void]$this._Aces.Remove($rule) }
            $acl | Add-Member -MemberType ScriptMethod -Name 'AddAuditRule' -Value { param($rule) $this._Aces.Add($rule) }
            return $acl
        }

        # ── Helper: build a ConfigureAuditRule plan for New-TierModelAuditRule ─────
        function New-AuditPlan {
            param([string]$Status = 'ABSENT', [int]$ManagedAceCount = 0)
            [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action       = 'ConfigureAuditRule'
                        ResourceType = 'DomainAuditRule'
                        TargetDn     = $script:TestDomainDN
                        Data         = [PSCustomObject]@{
                            TrusteeSid        = 'S-1-1-0'
                            AuditFlag         = 'Success'
                            Inheritance       = 'All'
                            TargetRights      = 'CreateChild'
                            UnionTargetRights = 'CreateChild, DeleteChild'
                            ExistingRightsInt = 0
                            MissingRights     = 'CreateChild'
                            ManagedAceCount   = $ManagedAceCount
                            Status            = $Status
                        }
                    }
                )
                Summary       = @{ TotalActions = 1; ConfigureActions = 1; ExistingCount = 0 }
                Errors        = @()
                DurationMs    = 1.0
                Converged     = $true
                CorrelationId = [System.Guid]::NewGuid().ToString()
            }
        }

        # ── Base mocks (happy path) ───────────────────────────────────────────────
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:TestDomainDN }
        Mock Import-Module -ModuleName TierModel { } -ParameterFilter { $Name -eq 'ActiveDirectory' }
        Mock Write-Host -ModuleName TierModel { }

        # Default: an empty ACL (no managed ACEs = ABSENT state)
        $script:mockAcl = New-MockAcl -Aces @()
        Mock Get-Acl -ModuleName TierModel { return $script:mockAcl } -ParameterFilter { $Audit }
        Mock Set-Acl -ModuleName TierModel { }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuditRule — planning
    # ════════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuditRule — Plan Generation" -Tag "Planning" {

        BeforeEach {
            $script:mockAcl = New-MockAcl -Aces @()
        }

        It "Returns a plan object with the required structure" {
            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            $plan | Should -Not -BeNullOrEmpty
            foreach ($p in @('Actions','Summary','Errors','DurationMs','Converged','CorrelationId')) {
                $plan.PSObject.Properties.Name | Should -Contain $p
            }
        }

        It "ABSENT: plans one ConfigureAuditRule action when no managed ACEs exist" {
            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            $configureActions = @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureAuditRule' })
            $configureActions.Count | Should -Be 1
            $configureActions[0].ResourceType | Should -Be 'DomainAuditRule'
            $configureActions[0].TargetDn     | Should -Be $script:TestDomainDN
            $configureActions[0].Data.Status  | Should -Be 'ABSENT'
            $configureActions[0].Data.ManagedAceCount | Should -Be 0
            $plan.Summary.ConfigureActions | Should -Be 1
            $plan.Summary.ExistingCount    | Should -Be 0
        }

        It "PARTIAL: plans a converge action and reports missing rights when some rights present" {
            # One managed ACE holding only CreateChild (missing the other 8)
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights 'CreateChild')

            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            $action = @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureAuditRule' })[0]
            $action.Data.Status          | Should -Be 'PARTIAL'
            $action.Data.ManagedAceCount | Should -Be 1
            $action.Data.MissingRights   | Should -Not -Be 'None'
            $action.Data.MissingRights   | Should -Match 'DeleteChild'
        }

        It "MULTI-ACE: plans a converge action when all rights present but spread across >1 ACE" {
            # Two managed ACEs which together cover all 9 rights
            $half1 = 'CreateChild','DeleteChild','WriteProperty','Self','Delete'
            $half2 = 'DeleteTree','WriteDacl','WriteOwner','ExtendedRight'
            $script:mockAcl = New-MockAcl -Aces @(
                (New-MockAuditAce -Rights ($half1 -join ','))
                (New-MockAuditAce -Rights ($half2 -join ','))
            )

            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            $action = @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureAuditRule' })[0]
            $action.Data.Status          | Should -Be 'MULTI-ACE'
            $action.Data.ManagedAceCount | Should -Be 2
            $action.Data.MissingRights   | Should -Be 'None'
        }

        It "Already converged: zero actions, ExistingCount=1, Converged=true (1 ACE with all 9 rights)" {
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights ($script:AllRights -join ','))

            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            @($plan.Actions).Count      | Should -Be 0
            $plan.Summary.TotalActions  | Should -Be 0
            $plan.Summary.ExistingCount | Should -Be 1
            $plan.Converged             | Should -Be $true
        }

        It "Ignores out-of-scope ACEs (other SID, Failure flag, InheritanceType None, inherited)" {
            $script:mockAcl = New-MockAcl -Aces @(
                (New-MockAuditAce -Rights ($script:AllRights -join ',') -Sid 'S-1-5-32-544')      # other SID
                (New-MockAuditAce -Rights ($script:AllRights -join ',') -AuditFlags 'Failure')     # Failure flag
                (New-MockAuditAce -Rights ($script:AllRights -join ',') -InheritanceType 'None')   # not All
                (New-MockAuditAce -Rights ($script:AllRights -join ',') -IsInherited $true)        # inherited
            )

            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            # None of the above count as managed -> treated as ABSENT -> one action planned
            $action = @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureAuditRule' })[0]
            $action.Data.Status          | Should -Be 'ABSENT'
            $action.Data.ManagedAceCount | Should -Be 0
        }

        It "Empty-config path: returns empty plan when domainAuditRule is null" {
            $plan = Get-TierModelAuditRule -Config $script:ConfigNullRule -DomainController $script:TestDC

            @($plan.Actions).Count     | Should -Be 0
            $plan.Summary.TotalActions | Should -Be 0
            $plan.Converged            | Should -Be $true
            @($plan.Errors).Count      | Should -Be 0
        }

        It "Empty-config path: returns empty plan when config has no domainAuditRule property" {
            $plan = Get-TierModelAuditRule -Config $script:ConfigNoProperty -DomainController $script:TestDC

            @($plan.Actions).Count     | Should -Be 0
            $plan.Converged            | Should -Be $true
        }

        It "IncludeDetails switch is accepted and returns a valid plan" {
            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -IncludeDetails
            $plan | Should -Not -BeNullOrEmpty
            $plan.PSObject.Properties.Name | Should -Contain 'Actions'
        }

        It "SeSecurityPrivilegeDenied: Get-Acl privilege failure produces code=SeSecurityPrivilegeDenied" {
            Mock Get-Acl -ModuleName TierModel { throw "The requested operation requires SeSecurityPrivilege." } -ParameterFilter { $Audit }

            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            $plan.Converged        | Should -Be $false
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'SeSecurityPrivilegeDenied'
        }

        It "SaclReadFailed: generic Get-Acl failure produces code=SaclReadFailed" {
            Mock Get-Acl -ModuleName TierModel { throw "Directory object not found." } -ParameterFilter { $Audit }

            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            $plan.Converged        | Should -Be $false
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'SaclReadFailed'
        }

        It "AuditRulePlanningFailed: outer catch fires when domain DN resolution throws" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { throw "Cannot contact DC" }

            $plan = Get-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            $plan.Converged        | Should -Be $false
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'AuditRulePlanningFailed'
        }

        It "Config parameter is mandatory" {
            $attr = (Get-Command Get-TierModelAuditRule).Parameters['Config'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            ($attr.Mandatory -contains $true) | Should -BeTrue
        }

        It "DomainController parameter is mandatory" {
            $attr = (Get-Command Get-TierModelAuditRule).Parameters['DomainController'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            ($attr.Mandatory -contains $true) | Should -BeTrue
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # New-TierModelAuditRule — apply (UNION converge)
    # ════════════════════════════════════════════════════════════════════════════
    Context "New-TierModelAuditRule — Apply" -Tag "Apply" {

        BeforeEach {
            $script:mockAcl = New-MockAcl -Aces @()
            Mock Set-Acl -ModuleName TierModel { }
        }

        It "Returns result with the required structure" {
            $result = New-TierModelAuditRule -Plan (New-AuditPlan) -DomainController $script:TestDC -Config $script:AuditConfig

            foreach ($p in @('Applied','Executed','Failed','Skipped','Errors','DurationMs','Converged','CorrelationId')) {
                $result.PSObject.Properties.Name | Should -Contain $p
            }
        }

        It "ABSENT: applies the union ACE, calls Set-Acl, Executed=1, Converged=true" {
            $result = New-TierModelAuditRule -Plan (New-AuditPlan -Status 'ABSENT') -DomainController $script:TestDC -Config $script:AuditConfig

            $result.Executed  | Should -Be 1
            $result.Failed    | Should -Be 0
            $result.Converged | Should -Be $true
            Should -Invoke Set-Acl -ModuleName TierModel -Times 1
        }

        It "Idempotent: AlreadyConverged when the SACL already holds 1 ACE with all 9 rights (no write)" {
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights ($script:AllRights -join ','))

            $result = New-TierModelAuditRule -Plan (New-AuditPlan -Status 'ABSENT') -DomainController $script:TestDC -Config $script:AuditConfig

            $result.Executed | Should -Be 0
            @($result.Skipped).Count | Should -Be 1
            $result.Skipped[0].Reason | Should -Be 'AlreadyConverged'
            Should -Invoke Set-Acl -ModuleName TierModel -Times 0
        }

        It "WhatIf: no write occurs, action skipped with Reason=WhatIf" {
            $result = New-TierModelAuditRule -Plan (New-AuditPlan) -DomainController $script:TestDC -Config $script:AuditConfig -WhatIf

            $result.Executed | Should -Be 0
            @($result.Skipped).Count | Should -Be 1
            $result.Skipped[0].Reason | Should -Be 'WhatIf'
            Should -Invoke Set-Acl -ModuleName TierModel -Times 0
        }

        It "Set-Acl privilege failure: error recorded, Converged=false, privilege message surfaced" {
            Mock Set-Acl -ModuleName TierModel { throw "Access is denied. SeSecurityPrivilege required." }

            $result = New-TierModelAuditRule -Plan (New-AuditPlan -Status 'ABSENT') -DomainController $script:TestDC -Config $script:AuditConfig

            $result.Failed    | Should -BeGreaterThan 0
            $result.Converged | Should -Be $false
            $result.Errors[0].Code | Should -Be 'AuditRuleApplyFailed'
            $result.Errors[0].Message | Should -Match 'SeSecurityPrivilege'
        }

        It "Set-Acl generic failure: error recorded, Converged=false" {
            Mock Set-Acl -ModuleName TierModel { throw "Some other write failure" }

            $result = New-TierModelAuditRule -Plan (New-AuditPlan -Status 'ABSENT') -DomainController $script:TestDC -Config $script:AuditConfig

            $result.Failed    | Should -BeGreaterThan 0
            $result.Converged | Should -Be $false
            $result.Errors[0].Code | Should -Be 'AuditRuleApplyFailed'
        }

        It "MULTI-ACE: removes managed ACEs and re-applies a single union ACE" {
            $half1 = 'CreateChild','DeleteChild','WriteProperty','Self','Delete'
            $half2 = 'DeleteTree','WriteDacl','WriteOwner','ExtendedRight'
            $script:mockAcl = New-MockAcl -Aces @(
                (New-MockAuditAce -Rights ($half1 -join ','))
                (New-MockAuditAce -Rights ($half2 -join ','))
            )

            $result = New-TierModelAuditRule -Plan (New-AuditPlan -Status 'MULTI-ACE' -ManagedAceCount 2) -DomainController $script:TestDC -Config $script:AuditConfig

            $result.Executed | Should -Be 1
            $result.Applied[0].RemovedAceCount | Should -Be 2
            Should -Invoke Set-Acl -ModuleName TierModel -Times 1
        }

        It "Non-ConfigureAuditRule actions are skipped (no write, Executed=0)" {
            $plan = [PSCustomObject]@{
                Actions = @([PSCustomObject]@{
                    Action = 'SomethingElse'; ResourceType = 'Other'; TargetDn = $script:TestDomainDN
                    Data = [PSCustomObject]@{ TrusteeSid = 'S-1-1-0' }
                })
                Summary = @{ TotalActions = 0; ConfigureActions = 0; ExistingCount = 0 }
                Errors = @(); Converged = $true; CorrelationId = 'x'
            }

            $result = New-TierModelAuditRule -Plan $plan -DomainController $script:TestDC -Config $script:AuditConfig

            $result.Executed | Should -Be 0
            $result.Failed   | Should -Be 0
            Should -Invoke Set-Acl -ModuleName TierModel -Times 0
        }

        It "Empty plan (no actions) returns Executed=0, Converged=true" {
            $emptyPlan = [PSCustomObject]@{
                Actions = @(); Summary = @{ TotalActions = 0; ConfigureActions = 0; ExistingCount = 0 }
                Errors = @(); Converged = $true; CorrelationId = 'x'
            }

            $result = New-TierModelAuditRule -Plan $emptyPlan -DomainController $script:TestDC -Config $script:AuditConfig

            $result.Executed  | Should -Be 0
            $result.Failed    | Should -Be 0
            $result.Converged | Should -Be $true
        }

        It "SupportsShouldProcess is declared on the cmdlet" {
            (Get-Command New-TierModelAuditRule).Parameters.Keys | Should -Contain 'WhatIf'
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # Test-TierModelAuditRule — drift detection
    # ════════════════════════════════════════════════════════════════════════════
    Context "Test-TierModelAuditRule — Drift Detection" -Tag "Audit" {

        BeforeEach {
            $script:mockAcl = New-MockAcl -Aces @()
        }

        It "Returns result with the required structure" {
            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            foreach ($p in @('TotalChecked','Compliant','Missing','Mismatched','Errors','Drift','Findings','DurationMs','CorrelationId')) {
                $result.PSObject.Properties.Name | Should -Contain $p
            }
        }

        It "COMPLIANT: Compliant=1, Missing=0, Drift=0 when 1 ACE with all 9 rights" {
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights ($script:AllRights -join ','))

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $result.TotalChecked | Should -Be 1
            $result.Compliant    | Should -Be 1
            $result.Missing      | Should -Be 0
            $result.Drift        | Should -Be 0
            ($result.Findings | Where-Object { $_.Type -eq 'Compliant' }) | Should -Not -BeNullOrEmpty
        }

        It "PARTIAL: Missing=1, Drift=1 and status PARTIAL when some rights absent" {
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights 'CreateChild')

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $result.TotalChecked | Should -Be 1
            $result.Missing      | Should -Be 1
            $result.Drift        | Should -Be 1
            $missingFinding = $result.Findings | Where-Object { $_.Type -eq 'MissingAuditRule' }
            $missingFinding.ActualValue | Should -Be 'PARTIAL'
        }

        It "ABSENT: drift reported with status ABSENT when no managed ACEs" {
            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $result.Drift | Should -Be 1
            $missingFinding = $result.Findings | Where-Object { $_.Type -eq 'MissingAuditRule' }
            $missingFinding.ActualValue | Should -Be 'ABSENT'
        }

        It "MULTI-ACE: drift reported with status MULTI-ACE when all rights present across >1 ACE" {
            $half1 = 'CreateChild','DeleteChild','WriteProperty','Self','Delete'
            $half2 = 'DeleteTree','WriteDacl','WriteOwner','ExtendedRight'
            $script:mockAcl = New-MockAcl -Aces @(
                (New-MockAuditAce -Rights ($half1 -join ','))
                (New-MockAuditAce -Rights ($half2 -join ','))
            )

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $result.Drift | Should -Be 1
            $missingFinding = $result.Findings | Where-Object { $_.Type -eq 'MissingAuditRule' }
            $missingFinding.ActualValue | Should -Be 'MULTI-ACE'
        }

        It "Emits one granular AuditRight finding per configured right" {
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights 'CreateChild')

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $rightFindings = @($result.Findings | Where-Object { $_.Type -eq 'AuditRight' })
            $rightFindings.Count | Should -Be 9
            ($rightFindings | Where-Object { $_.Property -eq 'CreateChild' }).Status | Should -Be 'Pass'
            ($rightFindings | Where-Object { $_.Property -eq 'DeleteChild' }).Status | Should -Be 'Fail'
        }

        It "TotalChecked is always 1 when domainAuditRule is configured" {
            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent
            $result.TotalChecked | Should -Be 1
        }

        It "Out-of-scope ACEs are ignored (other SID / Failure / inherited)" {
            $script:mockAcl = New-MockAcl -Aces @(
                (New-MockAuditAce -Rights ($script:AllRights -join ',') -Sid 'S-1-5-32-544')
                (New-MockAuditAce -Rights ($script:AllRights -join ',') -AuditFlags 'Failure')
                (New-MockAuditAce -Rights ($script:AllRights -join ',') -IsInherited $true)
            )

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            # Nothing is managed -> ABSENT drift
            $result.Compliant | Should -Be 0
            $result.Drift     | Should -Be 1
        }

        It "SACL read error: TotalChecked=1, Errors=1, Drift=0" {
            Mock Get-Acl -ModuleName TierModel { throw "Directory object not found." } -ParameterFilter { $Audit }

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $result.TotalChecked | Should -Be 1
            $result.Errors       | Should -Be 1
            $result.Drift        | Should -Be 0
            ($result.Findings | Where-Object { $_.Type -eq 'Error' }) | Should -Not -BeNullOrEmpty
        }

        It "SACL read privilege error surfaces SeSecurityPrivilege detail" {
            Mock Get-Acl -ModuleName TierModel { throw "The requested operation requires SeSecurityPrivilege." } -ParameterFilter { $Audit }

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $result.Errors | Should -Be 1
            $errFinding = $result.Findings | Where-Object { $_.Type -eq 'Error' }
            $errFinding.Details | Should -Match 'SeSecurityPrivilege'
        }

        It "Missing domainAuditRule: TotalChecked=0, Drift=0 (empty result)" {
            $result = Test-TierModelAuditRule -Config $script:ConfigNullRule -DomainController $script:TestDC -Silent

            $result.TotalChecked | Should -Be 0
            $result.Drift        | Should -Be 0
            @($result.Findings).Count | Should -Be 0
        }

        It "Outer catch: Errors=1, TotalChecked=0 when domain DN resolution throws" {
            Mock Resolve-TierModelDomainDN -ModuleName TierModel { throw "Cannot contact DC" }

            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -Silent

            $result.TotalChecked | Should -Be 0
            $result.Errors       | Should -Be 1
            ($result.Findings | Where-Object { $_.Type -eq 'Error' }) | Should -Not -BeNullOrEmpty
        }

        It "Non-silent mode emits host output without throwing" {
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights ($script:AllRights -join ','))
            { Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC } | Should -Not -Throw
        }

        It "SuppressSummary suppresses the summary block but still returns findings" {
            $script:mockAcl = New-MockAcl -Aces @(New-MockAuditAce -Rights ($script:AllRights -join ','))
            $result = Test-TierModelAuditRule -Config $script:AuditConfig -DomainController $script:TestDC -SuppressSummary
            $result.TotalChecked | Should -Be 1
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # Get-TierModelAuditRuleFd — FullDeployment wrapper
    # ════════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelAuditRuleFd — FD Wrapper" -Tag "FdPlanning" {

        BeforeEach {
            $script:mockAcl = New-MockAcl -Aces @()
        }

        It "Delegates to Get-TierModelAuditRule and returns a plan with the same shape" {
            $plan = Get-TierModelAuditRuleFd -Config $script:AuditConfig -DomainController $script:TestDC

            $plan | Should -Not -BeNullOrEmpty
            foreach ($p in @('Actions','Summary','Errors','DurationMs','Converged','CorrelationId')) {
                $plan.PSObject.Properties.Name | Should -Contain $p
            }
            @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureAuditRule' }).Count | Should -Be 1
        }

        It "Re-stamps the returned plan with a valid GUID CorrelationId" {
            $plan = Get-TierModelAuditRuleFd -Config $script:AuditConfig -DomainController $script:TestDC
            $plan.CorrelationId | Should -Not -BeNullOrEmpty
            [System.Guid]::Parse($plan.CorrelationId) | Should -Not -BeNullOrEmpty
        }

        It "Silent switch is accepted without altering the returned plan structure" {
            $plan = Get-TierModelAuditRuleFd -Config $script:AuditConfig -DomainController $script:TestDC -Silent
            $plan.PSObject.Properties.Name | Should -Contain 'Actions'
        }

        It "IncludeDetails switch flows through to the inner planner" {
            $plan = Get-TierModelAuditRuleFd -Config $script:AuditConfig -DomainController $script:TestDC -IncludeDetails
            $plan | Should -Not -BeNullOrEmpty
        }

        It "Error path: returns empty plan with code=AuditRuleFdPlanningFailed when inner planner throws" {
            Mock Get-TierModelAuditRule -ModuleName TierModel { throw "inner planner exploded" }

            $plan = Get-TierModelAuditRuleFd -Config $script:AuditConfig -DomainController $script:TestDC

            @($plan.Actions).Count | Should -Be 0
            $plan.Converged        | Should -Be $false
            ($plan.Errors | ForEach-Object { $_.Code }) | Should -Contain 'AuditRuleFdPlanningFailed'
        }

        It "Passes through an empty plan when domainAuditRule is null" {
            $plan = Get-TierModelAuditRuleFd -Config $script:ConfigNullRule -DomainController $script:TestDC
            @($plan.Actions).Count | Should -Be 0
            $plan.Converged        | Should -Be $true
        }
    }

    # ════════════════════════════════════════════════════════════════════════════
    # Get-TierModelConfig — tiermodel-audit.json -> domainAuditRule
    # ════════════════════════════════════════════════════════════════════════════
    Context "Get-TierModelConfig — Audit Segment" -Tag "Config" {

        BeforeAll {
            $script:RealCfgDir = Join-Path $PSScriptRoot '..' 'config'
            $script:RequiredFiles = @(
                'tiermodel-metadata.json','tiermodel-ous.json','tiermodel-groups.json',
                'tiermodel-users.json','tiermodel-acls.json','tiermodel-gpos.json',
                'tiermodel-admx.json','tiermodel-guid-mappings.json'
            )
        }

        It "Populates domainAuditRule when tiermodel-audit.json is present (real config)" {
            $config = Get-TierModelConfig -ConfigPath $script:RealCfgDir

            $config.PSObject.Properties.Name | Should -Contain 'domainAuditRule'
            $config.domainAuditRule | Should -Not -BeNullOrEmpty
            $config.domainAuditRule.rights.Count | Should -Be 9
        }

        It "Leaves domainAuditRule null when tiermodel-audit.json is absent" {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "TierModelNoAudit_$(New-Guid)"
            $null = New-Item -ItemType Directory -Path $tmp -Force
            try {
                foreach ($f in $script:RequiredFiles) {
                    Copy-Item (Join-Path $script:RealCfgDir $f) (Join-Path $tmp $f)
                }
                # Deliberately do NOT copy tiermodel-audit.json
                $config = Get-TierModelConfig -ConfigPath $tmp
                $config.domainAuditRule | Should -BeNullOrEmpty
            } finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Warns and skips (domainAuditRule null) when tiermodel-audit.json is malformed" {
            $warned = [System.Collections.Generic.List[string]]::new()
            Mock Write-TierModelLog -ModuleName TierModel {
                param($Level, $Message, $Data)
                if ($Level -eq 'Warning' -and $Message -match 'optional segment') { $warned.Add($Message) }
            }

            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "TierModelBadAudit_$(New-Guid)"
            $null = New-Item -ItemType Directory -Path $tmp -Force
            try {
                foreach ($f in $script:RequiredFiles) {
                    Copy-Item (Join-Path $script:RealCfgDir $f) (Join-Path $tmp $f)
                }
                Set-Content -Path (Join-Path $tmp 'tiermodel-audit.json') -Value 'not valid json {{{{' -Encoding UTF8

                $config = Get-TierModelConfig -ConfigPath $tmp

                $config.domainAuditRule | Should -BeNullOrEmpty
                $warned.Count | Should -BeGreaterThan 0
            } finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
