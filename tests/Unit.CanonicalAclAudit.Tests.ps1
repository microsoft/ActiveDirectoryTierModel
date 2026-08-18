#Requires -Modules Pester
# Unit tests for Invoke-CanonicalAclAudit — offline, no live AD.
# Strategy: extract the function from Audit-TierModel.ps1 into test scope via brace-matching,
# then mock all AD boundaries (Test-TierModelCanonicalAcl, Test-TierModelOuExists,
# Resolve-TierModelPlaceholder, Get-ADDomain). Never mock the logic under test.

Describe "Invoke-CanonicalAclAudit" -Tag 'Unit', 'CanonicalAcl', 'Audit' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'TierModel.psd1'
        Import-Module $ModulePath -Force

        # Extract Invoke-CanonicalAclAudit from Audit-TierModel.ps1 into this test scope.
        # Brace-counting to find function boundaries — resilient to internal line changes.
        $auditScriptLines = Get-Content (Join-Path $PSScriptRoot '..' 'Audit-TierModel.ps1')
        $funcStartIdx = -1
        for ($i = 0; $i -lt $auditScriptLines.Count; $i++) {
            if ($auditScriptLines[$i] -match '^function Invoke-CanonicalAclAudit\s*\{') {
                $funcStartIdx = $i; break
            }
        }
        if ($funcStartIdx -lt 0) { throw 'Could not find Invoke-CanonicalAclAudit in Audit-TierModel.ps1' }
        $depth = 0; $funcEndIdx = $funcStartIdx
        for ($i = $funcStartIdx; $i -lt $auditScriptLines.Count; $i++) {
            $depth += ([regex]::Matches($auditScriptLines[$i], '\{').Count -
                       [regex]::Matches($auditScriptLines[$i], '\}').Count)
            if ($i -gt $funcStartIdx -and $depth -le 0) { $funcEndIdx = $i; break }
        }
        $funcBlock = ($auditScriptLines[$funcStartIdx..$funcEndIdx]) -join "`n"
        . ([scriptblock]::Create($funcBlock))

        # Minimal config: 2 OUs, simple paths
        $script:MinimalConfig = [PSCustomObject]@{
            organizationUnits = @(
                [PSCustomObject]@{ name = 'Tier 0';       path = 'DC={{DOMAIN_DN}}' }
                [PSCustomObject]@{ name = 'Tier 1';       path = 'DC={{DOMAIN_DN}}' }
            )
        }
        $script:Dc = 'dc01.contoso.com'
        $script:DomainDn = 'DC=contoso,DC=com'
    }

    BeforeEach {
        Mock Get-ADDomain { [PSCustomObject]@{ DistinguishedName = $script:DomainDn } }
        Mock Resolve-TierModelPlaceholder {
            param($Path, $DomainDN)
            $Path -replace '\{\{DOMAIN_DN\}\}', $DomainDN
        }
        Mock Write-Host { }
        Mock Write-Warning { }
    }

    # -------------------------------------------------------------------------
    Context "Case 1 — domain root non-canonical" {

        It "Case 1: Mismatched=1 and Drift=1 when root is non-canonical" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = 'CONTOSO\Admins' }
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Mismatched | Should -Be 1
            $result.Drift      | Should -Be 1
            $result.Compliant  | Should -Be 0
        }

        It "Case 1: Findings[0].Case='Case1'" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Findings.Count        | Should -Be 1
            $result.Findings[0].Case      | Should -Be 'Case1'
            $result.Findings[0].LogCode   | Should -Be 'AuditNonCanonicalAclDomainRoot'
            $result.Findings[0].ResourceType | Should -Be 'DomainRoot'
            $result.Findings[0].Type      | Should -Be 'Mismatch'
        }

        It "Case 1: Identifier is the domain DN" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Findings[0].Identifier | Should -Be $script:DomainDn
        }

        It "Case 1: Details string mentions domain root and docs/canonical-acl.md" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = 'CONTOSO\Everyone' }
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Findings[0].Details | Should -Match 'domain root'
            $result.Findings[0].Details | Should -Match 'canonical-acl\.md'
            $result.Findings[0].Details | Should -Match 'CONTOSO\\Everyone'
        }

        It "Case 1: all-OUs-absent → TotalChecked=1 (root only)" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.TotalChecked | Should -Be 1
        }
    }

    # -------------------------------------------------------------------------
    Context "Case 2 — Tier Model OU non-canonical" {

        It "Case 2: Mismatched=1 Drift=1 when one OU is non-canonical" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            # Only Tier 0 exists, and it's non-canonical
            Mock Test-TierModelOuExists -ParameterFilter { $DistinguishedName -like '*Tier 0*' } {
                [PSCustomObject]@{ Exists = $true }
            }
            Mock Test-TierModelOuExists -ParameterFilter { $DistinguishedName -notlike '*Tier 0*' } {
                [PSCustomObject]@{ Exists = $false }
            }
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = 'CONTOSO\Tier0Admins' }
            }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Mismatched | Should -Be 1
            $result.Drift      | Should -Be 1
            $result.Compliant  | Should -Be 1  # root is canonical
        }

        It "Case 2: Findings[0].Case='Case2' for OU finding" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            Mock Test-TierModelOuExists -ParameterFilter { $DistinguishedName -like '*Tier 0*' } {
                [PSCustomObject]@{ Exists = $true }
            }
            Mock Test-TierModelOuExists -ParameterFilter { $DistinguishedName -notlike '*Tier 0*' } {
                [PSCustomObject]@{ Exists = $false }
            }
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = $null }
            }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Findings.Count        | Should -Be 1
            $result.Findings[0].Case      | Should -Be 'Case2'
            $result.Findings[0].LogCode   | Should -Be 'AuditNonCanonicalAclTierOu'
            $result.Findings[0].ResourceType | Should -Be 'TierModelOU'
            $result.Findings[0].Type      | Should -Be 'Mismatch'
        }

        It "Case 2: Details string mentions OU name and New-TierModelOu.ps1" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            Mock Test-TierModelOuExists -ParameterFilter { $DistinguishedName -like '*Tier 0*' } {
                [PSCustomObject]@{ Exists = $true }
            }
            Mock Test-TierModelOuExists -ParameterFilter { $DistinguishedName -notlike '*Tier 0*' } {
                [PSCustomObject]@{ Exists = $false }
            }
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = $null }
            }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Findings[0].Details | Should -Match 'New-TierModelOu\.ps1'
            $result.Findings[0].Details | Should -Match 'Tier 0'
        }
    }

    # -------------------------------------------------------------------------
    Context "No false positive — all canonical" {

        It "All canonical → Drift=0, no findings, TotalChecked=Compliant" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $true } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Drift     | Should -Be 0
            $result.Findings  | Should -HaveCount 0
            $result.TotalChecked | Should -Be $result.Compliant
            $result.Mismatched | Should -Be 0
        }

        It "All canonical → Missing=0 always" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $true } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Missing | Should -Be 0
        }
    }

    # -------------------------------------------------------------------------
    Context "Counts — mix of canonical, non-canonical, and throwing" {

        It "Mix: Compliant/Mismatched/Errors counts are correct" {
            # Root: canonical. OU1: non-canonical. OU2: throws.
            Mock Get-ADDomain { [PSCustomObject]@{ DistinguishedName = $script:DomainDn } }
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            # OU1 exists and non-canonical, OU2 exists and throws
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $true } }
            $global:_canonMixCall = 0
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                $global:_canonMixCall++
                if ($global:_canonMixCall -eq 1) {
                    [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = $null }
                } else {
                    throw 'Simulated LDAP error'
                }
            }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Compliant  | Should -Be 1   # root
            $result.Mismatched | Should -Be 1   # OU1
            $result.Errors     | Should -Be 1   # OU2 threw
            $result.TotalChecked | Should -Be 2  # root + OU1 (OU2 threw before incrementing)
            Remove-Variable -Name _canonMixCall -Scope Global -ErrorAction SilentlyContinue
        }

        It "Drift == Mismatched invariant holds across mix scenario" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $false; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $true } }
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = $null }
            }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Drift | Should -Be $result.Mismatched
        }
    }

    # -------------------------------------------------------------------------
    Context "Exception path — one check throws, continues" {

        It "Exception on root check → Errors=1, no Mismatch finding, TotalChecked=OU only" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                throw 'Simulated root LDAP error'
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $true } }
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = $null }
            }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Errors     | Should -Be 1
            $result.Mismatched | Should -Be 0
            $result.Findings   | Should -HaveCount 0
            $result.TotalChecked | Should -Be 2  # 2 OUs (root threw so not counted)
        }

        It "Exception on OU check → Errors=1, no Mismatch for that OU, audit continues" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $true } }
            $global:_canonExceptCall = 0
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                $global:_canonExceptCall++
                if ($global:_canonExceptCall -eq 1) { throw 'Simulated OU LDAP error' }
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = $null }
            }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Errors     | Should -Be 1
            $result.Mismatched | Should -Be 0
            $result.Compliant  | Should -BeGreaterThan 0   # root + OU2 are compliant
            Remove-Variable -Name _canonExceptCall -Scope Global -ErrorAction SilentlyContinue
        }
    }

    # -------------------------------------------------------------------------
    Context "Missing-OU skip — Test-TierModelCanonicalAcl NOT called for absent OUs" {

        It "Absent OU → Test-TierModelCanonicalAcl not called for that DN" {
            Mock Test-TierModelCanonicalAcl -ParameterFilter { [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null }
            }
            # Both OUs absent
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }
            # OU-level canonical check (DistinguishedName present) — should never be called
            Mock Test-TierModelCanonicalAcl -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) } {
                [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $DistinguishedName; FirstOffendingPrincipal = $null }
            }

            $null = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            # Module-scope mock for OU DN calls should have 0 invocations
            Should -Invoke Test-TierModelCanonicalAcl -Times 0 -ParameterFilter { -not [string]::IsNullOrEmpty($DistinguishedName) }
        }

        It "Absent OU → TotalChecked = 1 (root only)" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.TotalChecked | Should -Be 1
        }
    }

    # -------------------------------------------------------------------------
    Context "Return object shape" {

        It "Returns all required fields" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc
            $props = $result.PSObject.Properties.Name

            $props | Should -Contain 'TotalChecked'
            $props | Should -Contain 'Compliant'
            $props | Should -Contain 'Mismatched'
            $props | Should -Contain 'Missing'
            $props | Should -Contain 'Errors'
            $props | Should -Contain 'Drift'
            $props | Should -Contain 'Findings'
            $props | Should -Contain 'DurationMs'
            $props | Should -Contain 'CorrelationId'
        }

        It "CorrelationId is a valid GUID string" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            [guid]::TryParse($result.CorrelationId, [ref][guid]::Empty) | Should -Be $true
        }

        It "DurationMs is a non-negative integer" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.DurationMs | Should -BeGreaterOrEqual 0
        }

        It "Return object has a Skipped property" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.PSObject.Properties.Name | Should -Contain 'Skipped'
        }
    }

    # -------------------------------------------------------------------------
    Context "Skipped counter — absent OUs are tracked but not counted in TotalChecked" {

        It "All OUs absent: Skipped = OU count, TotalChecked = 1 (root only), Compliant = 1, Drift = 0" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = $script:DomainDn; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $false } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Skipped      | Should -Be ($script:MinimalConfig.organizationUnits.Count)
            $result.TotalChecked | Should -Be 1
            $result.Compliant    | Should -Be 1
            $result.Drift        | Should -Be 0
        }

        It "All OUs present + canonical: Skipped = 0, TotalChecked = 1 + OU count" {
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }
            Mock Test-TierModelOuExists { [PSCustomObject]@{ Exists = $true } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Skipped      | Should -Be 0
            $result.TotalChecked | Should -Be (1 + $script:MinimalConfig.organizationUnits.Count)
        }

        It "Partial presence: Skipped = absent count, TotalChecked = 1 + present count" {
            # MinimalConfig has 2 OUs; mock first present, second absent
            $script:_existsCall = 0
            Mock Test-TierModelOuExists {
                $script:_existsCall++
                [PSCustomObject]@{ Exists = ($script:_existsCall -eq 1) }
            }
            Mock Test-TierModelCanonicalAcl { [PSCustomObject]@{ IsCanonical = $true; DistinguishedName = 'DC=contoso,DC=com'; FirstOffendingPrincipal = $null } }

            $result = Invoke-CanonicalAclAudit -Config $script:MinimalConfig -DomainController $script:Dc

            $result.Skipped      | Should -Be 1   # one absent
            $result.TotalChecked | Should -Be 2   # root + 1 present OU
            Remove-Variable -Name _existsCall -Scope Script -ErrorAction SilentlyContinue
        }
    }
}
