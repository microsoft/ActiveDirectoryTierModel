function Test-TierModelAuthSilo {
    <#
    .SYNOPSIS
    Audit AD Authentication Policy Silos against TierModel configuration (read-only).

    .DESCRIPTION
    For each authentication silo defined in tiermodel-authsilos.json, verifies that the
    silo exists in Active Directory and matches the desired configuration. Checks:
      - Silo exists (Missing if absent)
      - Description matches config
      - UserAuthenticationPolicy, ComputerAuthenticationPolicy, ServiceAuthenticationPolicy
        all reference the configured 1:1 policy
      - ProtectedFromAccidentalDeletion = $true
      - Membership: every expected member account and computer (expanded from
        memberAccountGroups and memberComputerGroups, minus exemptAccounts including the
        RID-500 built-in Administrator) is present in the silo's Members list
        (msDS-AuthNPolicySiloMembers). Members in AD that are not expected by config are
        also flagged as unexpected.

    NEVER checks Enforce state. Enforcement is a separate lifecycle step; auditing it here
    would produce false-positive alerts on a correctly deployed audit-mode environment.

    This function is read-only. It makes no changes to Active Directory.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig (must include auth silo config
    from tiermodel-authsilos.json including authSilosExemptAccounts).

    .PARAMETER DomainController
    Preferred domain controller for all AD queries.

    .PARAMETER Silent
    Suppress all host output. For use in consolidated pipeline contexts.

    .PARAMETER SuppressSummary
    Suppress the per-run summary block while retaining per-silo status output.

    .OUTPUTS
    PSCustomObject with TotalChecked, Compliant, Missing, NonCompliant, Errors, Drift,
    Findings (per-silo details), DurationMs, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    $result = Test-TierModelAuthSilo -Config $config -DomainController 'DC01'
    $result.Findings | Where-Object Status -ne 'Compliant'

    .EXAMPLE
    Test-TierModelAuthSilo -Config $config -DomainController 'DC01' -Silent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [switch]$Silent,

        [switch]$SuppressSummary
    )

    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuthSiloAuditStart" -Data @{
        DomainController = $DomainController
        Silent           = $Silent.IsPresent
        CorrelationId    = $CorrelationId
    } | Out-Null

    $totalChecked   = 0
    $compliantCount = 0
    $missingCount   = 0
    $nonCompliant   = 0
    $errorCount     = 0
    $findings       = @()

    try {
        $silos = Get-TierModelAuthSilo -Config $Config

        if ($silos.Count -eq 0) {
            Write-TierModelLog -Level Warning -Message "No auth silos in config — nothing to audit" -Data @{ CorrelationId = $CorrelationId } | Out-Null
            if (-not $Silent) { Write-Host "  ⚠️  No authentication silos found in configuration." -ForegroundColor Yellow }
        }

        # ── Build runtime exemption set (same logic as Set-TierModelAuthSiloMembership) ──
        $configuredExempts = @()
        if ($Config.PSObject.Properties['authSilosExemptAccounts'] -and $Config.authSilosExemptAccounts) {
            $configuredExempts = @($Config.authSilosExemptAccounts.samaccountnames)
        }

        $rid500SamName = $null
        try {
            $domainSidVal  = (Get-ADDomain -Server $DomainController -ErrorAction Stop).DomainSID.Value
            $adminSid      = "$domainSidVal-500"
            $adminAccount  = Get-ADUser -Identity $adminSid -Server $DomainController -ErrorAction Stop
            $rid500SamName = $adminAccount.SamAccountName
        } catch {
            Write-TierModelLog -Level Warning -Message "Test-TierModelAuthSilo: RID-500 resolution failed — proceeding without explicit RID-500 exemption" -Data @{
                Exception = $_.Exception.Message; CorrelationId = $CorrelationId
            } | Out-Null
        }

        $exemptSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $configuredExempts) { $exemptSet.Add($name) | Out-Null }
        if ($null -ne $rid500SamName) { $exemptSet.Add($rid500SamName) | Out-Null }

        if (-not $Silent) {
            Write-Host "Auditing Authentication Policy Silos..." -ForegroundColor Cyan
        }

        foreach ($silo in $silos) {
            $totalChecked++
            $siloName  = $silo.name
            $policyName = $silo.policy
            $issues     = @()

            if (-not $Silent) {
                Write-Host "  Checking Silo: $siloName" -ForegroundColor Cyan
            }

            # ── Check 1: Silo exists in AD ───────────────────────────────────────────────
            $adSilo = $null
            try {
                $adSilo = Get-ADAuthenticationPolicySilo -Identity $siloName -Properties * -Server $DomainController -ErrorAction Stop
            } catch {
                $missingCount++
                $findings += [PSCustomObject]@{
                    SiloName = $siloName; Status = 'Missing'
                    Issues   = @("Silo '$siloName' not found in Active Directory")
                }
                if (-not $Silent) { Write-Host "    ❌ Missing — silo not found in AD" -ForegroundColor Red }
                Write-TierModelLog -Level Warning -Message "AuthSiloAuditMissing" -Data @{
                    SiloName = $siloName; CorrelationId = $CorrelationId
                } | Out-Null
                continue
            }

            # ── Check 2: Description ─────────────────────────────────────────────────────
            if ($adSilo.Description -ne $silo.description) {
                $issues += "Description differs (expected: '$($silo.description)', actual: '$($adSilo.Description)')"
            }

            # ── Check 3: Policy links — User, Computer, Service must all reference config policy ──
            foreach ($policyProp in @('UserAuthenticationPolicy', 'ComputerAuthenticationPolicy', 'ServiceAuthenticationPolicy')) {
                $currentRef = $null
                try { $currentRef = $adSilo.$policyProp } catch {}
                # The property may be a DN or a name; normalize to name for comparison
                $currentName = if ("$currentRef" -match '^CN=') {
                    ("$currentRef" -split ',')[0] -replace '^CN=', ''
                } else { "$currentRef" }
                if ($currentName -ne $policyName) {
                    $issues += "$policyProp should be '$policyName' (actual: '$currentName')"
                }
            }

            # NOTE: Enforce is intentionally NOT checked. Enforcement is a separate lifecycle
            # step; checking it here would false-positive on a correctly deployed audit-mode env.

            # ── Check 4: ProtectedFromAccidentalDeletion = true ──────────────────────────
            $pfad = $null
            try { $pfad = $adSilo.ProtectedFromAccidentalDeletion } catch {}
            if ($pfad -ne $true) {
                $issues += "ProtectedFromAccidentalDeletion should be True (actual: $pfad)"
            }

            # ── Check 5: Membership ──────────────────────────────────────────────────────
            # Get the silo's current Members list (msDS-AuthNPolicySiloMembers — DNs of all
            # granted accounts and computers).
            $currentMemberDns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            try {
                $siloWithMembers = Get-ADAuthenticationPolicySilo -Identity $siloName -Properties Members -Server $DomainController -ErrorAction Stop
                foreach ($dn in @($siloWithMembers.Members | Where-Object { $_ })) {
                    $currentMemberDns.Add($dn) | Out-Null
                }
            } catch {
                $issues += "Cannot read silo Members list: $($_.Exception.Message)"
            }

            # Build expected member DN set by expanding config groups (minus exempts)
            $expectedMemberDns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($groupName in @($silo.memberAccountGroups)) {
                try {
                    $members = @(Get-ADGroupMember -Identity $groupName -Recursive -Server $DomainController -ErrorAction Stop |
                        Where-Object { $_.objectClass -eq 'user' })
                    foreach ($m in $members) {
                        if (-not $exemptSet.Contains($m.SamAccountName)) {
                            $expectedMemberDns.Add($m.DistinguishedName) | Out-Null
                        }
                    }
                } catch {
                    $issues += "Cannot expand account group '$groupName': $($_.Exception.Message)"
                }
            }

            foreach ($groupName in @($silo.memberComputerGroups)) {
                try {
                    $members = @(Get-ADGroupMember -Identity $groupName -Recursive -Server $DomainController -ErrorAction Stop |
                        Where-Object { $_.objectClass -eq 'computer' })
                    foreach ($m in $members) {
                        # Exempt set check is defensive; normally no computers are exempt
                        if (-not $exemptSet.Contains($m.SamAccountName)) {
                            $expectedMemberDns.Add($m.DistinguishedName) | Out-Null
                        }
                    }
                } catch {
                    $issues += "Cannot expand computer group '$groupName': $($_.Exception.Message)"
                }
            }

            # Missing members: expected but not in silo Members list
            $missingMembers = @($expectedMemberDns | Where-Object { -not $currentMemberDns.Contains($_) })
            if ($missingMembers.Count -gt 0) {
                foreach ($dn in $missingMembers) {
                    # Attempt a friendly display name lookup
                    $sam = $null
                    try {
                        $obj = Get-ADObject -Identity $dn -Properties SamAccountName -Server $DomainController -ErrorAction SilentlyContinue
                        $sam = $obj.SamAccountName
                    } catch {}
                    $label = if ($sam) { "$sam ($dn)" } else { $dn }
                    $issues += "Missing from silo Members: $label"
                }
            }

            # Unexpected members: in silo Members list but not in expected set
            $unexpectedMembers = @($currentMemberDns | Where-Object { -not $expectedMemberDns.Contains($_) })
            if ($unexpectedMembers.Count -gt 0) {
                foreach ($dn in $unexpectedMembers) {
                    $sam = $null
                    try {
                        $obj = Get-ADObject -Identity $dn -Properties SamAccountName -Server $DomainController -ErrorAction SilentlyContinue
                        $sam = $obj.SamAccountName
                    } catch {}
                    $label = if ($sam) { "$sam ($dn)" } else { $dn }
                    $issues += "Unexpected member in silo (not in config groups): $label"
                }
            }

            # ── Record result ─────────────────────────────────────────────────────────────
            if ($issues.Count -eq 0) {
                $compliantCount++
                $findings += [PSCustomObject]@{
                    SiloName = $siloName; Status = 'Compliant'; Issues = @()
                }
                if (-not $Silent) {
                    Write-Host "    ✅ Compliant (members: expected=$($expectedMemberDns.Count), current=$($currentMemberDns.Count))" -ForegroundColor Green
                }
            } else {
                $nonCompliant++
                $findings += [PSCustomObject]@{
                    SiloName = $siloName; Status = 'NonCompliant'; Issues = $issues
                }
                if (-not $Silent) {
                    Write-Host "    ❌ NonCompliant" -ForegroundColor Red
                    $issues | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
                }
                Write-TierModelLog -Level Warning -Message "AuthSiloAuditNonCompliant" -Data @{
                    SiloName = $siloName; IssueCount = $issues.Count; CorrelationId = $CorrelationId
                } | Out-Null
            }
        }

        $drift      = $missingCount + $nonCompliant
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        if (-not $Silent -and -not $SuppressSummary) {
            Write-Host "`n  Authentication Silo Audit Summary:" -ForegroundColor White
            Write-Host "    Total Checked: $totalChecked" -ForegroundColor Gray
            Write-Host "    Compliant:     $compliantCount" -ForegroundColor $(if ($compliantCount -eq $totalChecked) { 'Green' } else { 'White' })
            Write-Host "    Missing:       $missingCount"   -ForegroundColor $(if ($missingCount   -gt 0) { 'Red' }   else { 'Green' })
            Write-Host "    Non-Compliant: $nonCompliant"   -ForegroundColor $(if ($nonCompliant   -gt 0) { 'Red' }   else { 'Green' })
            Write-Host "    Drift Total:   $drift"          -ForegroundColor $(if ($drift -gt 0) { 'Red' } else { 'Green' })
        }

        Write-TierModelLog -Level Info -Message "AuthSiloAuditComplete" -Data @{
            TotalChecked = $totalChecked; Compliant = $compliantCount
            Missing      = $missingCount; NonCompliant = $nonCompliant
            Drift        = $drift; DurationMs = $durationMs; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked  = $totalChecked
            Compliant     = $compliantCount
            Missing       = $missingCount
            NonCompliant  = $nonCompliant
            Errors        = $errorCount
            Drift         = $drift
            Findings      = $findings
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        }

    } catch {
        Write-TierModelLog -Level Error -Message "AuthSiloAuditFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked = $totalChecked; Compliant = $compliantCount
            Missing      = $missingCount; NonCompliant = $nonCompliant; Errors = 1
            Drift        = $missingCount + $nonCompliant
            Findings     = $findings
            DurationMs   = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
