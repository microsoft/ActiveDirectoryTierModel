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
      - Computer membership (subset): every computer from memberComputerGroups is present in
        the silo's Members list. Extra members beyond config are allowed (informational).

    COMPUTER MEMBERSHIP ONLY: User/account silo membership is out of TM scope and is not
    checked. Tier admin account groups are always empty on a fresh TM deploy; account
    siloing is an out-of-band operator task.

    NEVER checks Enforce state (informational only). This function is read-only.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.

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

        if (-not $Silent) {
            Write-Host "Auditing Authentication Policy Silos..." -ForegroundColor Cyan
        }

        foreach ($silo in $silos) {
            $totalChecked++
            $siloName   = $silo.name
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
                    Issues = @("Not found in Active Directory")
                    EnforceState = 'unknown (silo absent)'; ExtraMembers = @()
                }
                if (-not $Silent) { Write-Host "    ❌ Missing — not found in AD" -ForegroundColor Red }
                Write-TierModelLog -Level Info -Message "AuthSiloAuditMissing" -Data @{
                    SiloName = $siloName; CorrelationId = $CorrelationId
                } | Out-Null
                continue
            }

            # ── Check 2: Description ─────────────────────────────────────────────────────
            if ($adSilo.Description -ne $silo.description) {
                $issues += "description differs from config"
            }

            # ── Enforce state — INFORMATIONAL ONLY, never contributes to pass/fail ────────
            $enforceVal   = $null
            try { $enforceVal = $adSilo.Enforce } catch {}
            $enforceState = if ($enforceVal -eq $true) { 'ENFORCED' } elseif ($enforceVal -eq $false) { 'audit mode' } else { "unknown ($enforceVal)" }

            # ── Check 3: Policy links — User, Computer, Service must reference config policy ──
            foreach ($policyProp in @('UserAuthenticationPolicy', 'ComputerAuthenticationPolicy', 'ServiceAuthenticationPolicy')) {
                $currentRef = $null
                try { $currentRef = $adSilo.$policyProp } catch {}
                $currentName = if ("$currentRef" -match '^CN=') {
                    ("$currentRef" -split ',')[0] -replace '^CN=', ''
                } else { "$currentRef" }
                if ($currentName -ne $policyName) {
                    $label = if ([string]::IsNullOrWhiteSpace($currentName)) { 'not linked' } else { "linked to '$currentName'" }
                    $issues += "$policyProp not linked to config policy '$policyName' ($label)"
                }
            }

            # NOTE: Enforce is informational only — EnforceState is reported but never fails.

            # ── Check 4: ProtectedFromAccidentalDeletion = true ──────────────────────────
            $pfad = $null
            try { $pfad = $adSilo.ProtectedFromAccidentalDeletion } catch {}
            if ($pfad -ne $true) { $issues += "ProtectedFromAccidentalDeletion not set" }

            # ── Check 5: Computer membership (subset check — computer groups only) ────────
            # User/account membership is out of TM scope. Only verify computers from
            # memberComputerGroups are in the silo's Members list (mandatory subset).
            $currentMemberDns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            try {
                $siloWithMembers = Get-ADAuthenticationPolicySilo -Identity $siloName -Properties Members -Server $DomainController -ErrorAction Stop
                foreach ($dn in @($siloWithMembers.Members | Where-Object { $_ })) {
                    $currentMemberDns.Add($dn) | Out-Null
                }
            } catch {
                $issues += "Cannot read silo Members list: $($_.Exception.Message)"
            }

            # Expand expected computer members from config
            $expectedMemberDns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($groupName in @($silo.memberComputerGroups)) {
                try {
                    $members = @(Get-ADGroupMember -Identity $groupName -Recursive -Server $DomainController -ErrorAction Stop |
                        Where-Object { $_.objectClass -eq 'computer' })
                    foreach ($m in $members) {
                        $expectedMemberDns.Add($m.DistinguishedName) | Out-Null
                    }
                } catch {
                    $issues += "Cannot expand computer group '$groupName': $($_.Exception.Message)"
                }
            }

            # Missing computers: mandatory subset check
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

            # Extra members: in silo Members list but not in expected set — ALLOWED, informational.
            # Customer may grant additional accounts silo access beyond the config-defined groups.
            # This is a valid operational pattern (e.g. temporary exception accounts) and MUST NOT
            # cause a compliance failure.
            $extraMemberLabels = @()
            $extraMembers = @($currentMemberDns | Where-Object { -not $expectedMemberDns.Contains($_) })
            if ($extraMembers.Count -gt 0) {
                foreach ($dn in $extraMembers) {
                    $sam = $null
                    try {
                        $obj = Get-ADObject -Identity $dn -Properties SamAccountName -Server $DomainController -ErrorAction SilentlyContinue
                        $sam = $obj.SamAccountName
                    } catch {}
                    $extraMemberLabels += if ($sam) { "$sam ($dn)" } else { $dn }
                }
            }

            # ── Record result ─────────────────────────────────────────────────────────────
            if ($issues.Count -eq 0) {
                $compliantCount++
                $findings += [PSCustomObject]@{
                    SiloName = $siloName; Status = 'Compliant'; Issues = @()
                    EnforceState = $enforceState; ExtraMembers = $extraMemberLabels
                }
                if (-not $Silent) {
                    Write-Host "    ✅ Compliant (enforce: $enforceState; members: expected=$($expectedMemberDns.Count), current=$($currentMemberDns.Count))" -ForegroundColor Green
                    if ($extraMemberLabels.Count -gt 0) {
                        Write-Host "    ℹ️  Extra members beyond config (allowed): $($extraMemberLabels.Count)" -ForegroundColor Cyan
                        $extraMemberLabels | ForEach-Object { Write-Host "        $_" -ForegroundColor Cyan }
                    }
                }
            } else {
                $nonCompliant++
                $findings += [PSCustomObject]@{
                    SiloName = $siloName; Status = 'NonCompliant'; Issues = $issues
                    EnforceState = $enforceState; ExtraMembers = $extraMemberLabels
                }
                if (-not $Silent) {
                    foreach ($issue in $issues) {
                        Write-Host "    ❌ NonCompliant — $issue" -ForegroundColor Red
                    }
                    if ($extraMemberLabels.Count -gt 0) {
                        Write-Host "    ℹ️  Extra members beyond config (allowed): $($extraMemberLabels.Count)" -ForegroundColor Cyan
                    }
                    Write-Host "    ℹ️  Enforce state: $enforceState" -ForegroundColor DarkGray
                }
                # Log to file only — no Write-Warning (avoids "WARNING: ..." console spam)
                Write-TierModelLog -Level Info -Message "AuthSiloAuditNonCompliant" -Data @{
                    SiloName = $siloName; IssueCount = $issues.Count; EnforceState = $enforceState; CorrelationId = $CorrelationId
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
