function Test-TierModelAuthPolicy {
    <#
    .SYNOPSIS
    Audit AD Authentication Policies against TierModel configuration (read-only).

    .DESCRIPTION
    For each authentication policy defined in tiermodel-authsilos.json, verifies that the
    policy exists in Active Directory and matches the desired configuration. Checks:
      - Policy exists (Missing if absent)
      - Description matches config
      - UserTGTLifetimeMins equals config (skipped when config value is null — null means
        "inherit domain default", so no attribute is expected in AD for that policy)
      - UserAllowedToAuthenticateFrom SDDL matches the desired SID set — uses
        Compare-TierModelAuthSddl so SDDL domain aliases (e.g. DD for Domain Controllers)
        are normalized before comparison and the check is order-insensitive
      - ProtectedFromAccidentalDeletion = $true

    NEVER checks Enforce state. Enforcement is a separate lifecycle step; auditing it here
    would produce false-positive alerts on a correctly deployed audit-mode environment.

    This function is read-only. It makes no changes to Active Directory.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig (must include auth silo config
    from tiermodel-authsilos.json).

    .PARAMETER DomainController
    Preferred domain controller for all AD queries.

    .PARAMETER Silent
    Suppress all host output. For use in consolidated pipeline contexts.

    .PARAMETER SuppressSummary
    Suppress the per-run summary block while retaining per-policy status output.

    .OUTPUTS
    PSCustomObject with TotalChecked, Compliant, Missing, NonCompliant, Errors, Drift,
    Findings (per-policy details), DurationMs, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    $result = Test-TierModelAuthPolicy -Config $config -DomainController 'DC01'
    $result.Findings | Where-Object Status -ne 'Compliant' | ForEach-Object { Write-Host "$($_.PolicyName): $($_.Issues -join '; ')" }

    .EXAMPLE
    Test-TierModelAuthPolicy -Config $config -DomainController 'DC01' -Silent
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

    Write-TierModelLog -Level Info -Message "AuthPolicyAuditStart" -Data @{
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
        $policies = Get-TierModelAuthPolicy -Config $Config

        if ($policies.Count -eq 0) {
            Write-TierModelLog -Level Warning -Message "No auth policies in config — nothing to audit" -Data @{ CorrelationId = $CorrelationId } | Out-Null
            if (-not $Silent) { Write-Host "  ⚠️  No authentication policies found in configuration." -ForegroundColor Yellow }
        }

        if (-not $Silent) {
            Write-Host "Auditing Authentication Policies..." -ForegroundColor Cyan
        }

        foreach ($policy in $policies) {
            $totalChecked++
            $policyName = $policy.name
            $issues     = @()

            if (-not $Silent) {
                Write-Host "  Checking Policy: $policyName" -ForegroundColor Cyan
            }

            # ── Check 1: Policy exists in AD ────────────────────────────────────────────
            $adPolicy = $null
            try {
                $adPolicy = Get-ADAuthenticationPolicy -Identity $policyName -Properties * -Server $DomainController -ErrorAction Stop
            } catch {
                $missingCount++
                $findings += [PSCustomObject]@{
                    PolicyName = $policyName
                    Status     = 'Missing'
                    Issues     = @("Policy '$policyName' not found in Active Directory")
                }
                if (-not $Silent) { Write-Host "    ❌ Missing — policy not found in AD" -ForegroundColor Red }
                Write-TierModelLog -Level Warning -Message "AuthPolicyAuditMissing" -Data @{
                    PolicyName = $policyName; CorrelationId = $CorrelationId
                } | Out-Null
                continue
            }

            # ── Check 2: Description ─────────────────────────────────────────────────────
            if ($adPolicy.Description -ne $policy.description) {
                $issues += "Description differs (expected: '$($policy.description)', actual: '$($adPolicy.Description)')"
            }

            # ── Check 3: UserTGTLifetimeMins (skip when config value is null = domain default) ──
            if ($null -ne $policy.userTGTLifetimeMinutes) {
                $existingTgt = $null
                try { $existingTgt = $adPolicy.UserTGTLifetimeMins } catch {}
                if ($null -eq $existingTgt) {
                    try {
                        $rawTgt = $adPolicy.'msDS-UserTGTLifetime'
                        if ($null -ne $rawTgt -and $rawTgt -ne 0) {
                            $existingTgt = [long]$rawTgt / 600000000
                        }
                    } catch {}
                }
                if ([int]$existingTgt -ne [int]$policy.userTGTLifetimeMinutes) {
                    $issues += "UserTGTLifetimeMins differs (expected: $($policy.userTGTLifetimeMinutes), actual: $existingTgt)"
                }
            }

            # ── Check 4: UserAllowedToAuthenticateFrom SDDL (alias- and order-insensitive) ──
            $existingSddl = $null
            try { $existingSddl = $adPolicy.UserAllowedToAuthenticateFrom } catch {}
            if ($null -eq $existingSddl) {
                try { $existingSddl = $adPolicy.'msDS-UserAllowedToAuthenticateFrom' } catch {}
            }

            # Resolve device group SIDs to build the desired SDDL for comparison
            $resolvedSids      = @()
            $sidResolutionFailed = $false
            foreach ($groupName in @($policy.allowedToAuthenticateFromDeviceGroups)) {
                $sidResult = Resolve-TierModelPrincipalSid -Principal $groupName -DomainController $DomainController -CorrelationId $CorrelationId
                if ($sidResult.Success) {
                    $resolvedSids += $sidResult.Sid
                } else {
                    $issues += "Cannot resolve SID for device group '$groupName' — SDDL check skipped: $($sidResult.Error)"
                    $sidResolutionFailed = $true
                }
            }

            if (-not $sidResolutionFailed) {
                $desiredSddl  = Build-TierModelAuthSddl -DeviceSids $resolvedSids
                $sddlResult   = Compare-TierModelAuthSddl -DesiredSddl $desiredSddl -ExistingSddl "$existingSddl" -DomainController $DomainController
                if (-not $sddlResult.Equal) {
                    $issues += "UserAllowedToAuthenticateFrom SDDL differs: $($sddlResult.Reason)"
                }
            }

            # ── Check 5: ProtectedFromAccidentalDeletion = true ──────────────────────────
            $pfad = $null
            try { $pfad = $adPolicy.ProtectedFromAccidentalDeletion } catch {}
            if ($pfad -ne $true) {
                $issues += "ProtectedFromAccidentalDeletion should be True (actual: $pfad)"
            }

            # NOTE: Enforce is intentionally NOT checked. Enforcement is a separate lifecycle
            # step; checking it here would false-positive on a correctly deployed audit-mode env.

            # ── Record result ─────────────────────────────────────────────────────────────
            if ($issues.Count -eq 0) {
                $compliantCount++
                $findings += [PSCustomObject]@{
                    PolicyName = $policyName
                    Status     = 'Compliant'
                    Issues     = @()
                }
                if (-not $Silent) { Write-Host "    ✅ Compliant" -ForegroundColor Green }
            } else {
                $nonCompliant++
                $findings += [PSCustomObject]@{
                    PolicyName = $policyName
                    Status     = 'NonCompliant'
                    Issues     = $issues
                }
                if (-not $Silent) {
                    Write-Host "    ❌ NonCompliant" -ForegroundColor Red
                    $issues | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
                }
                Write-TierModelLog -Level Warning -Message "AuthPolicyAuditNonCompliant" -Data @{
                    PolicyName = $policyName; Issues = $issues; CorrelationId = $CorrelationId
                } | Out-Null
            }
        }

        $drift      = $missingCount + $nonCompliant
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        if (-not $Silent -and -not $SuppressSummary) {
            Write-Host "`n  Authentication Policy Audit Summary:" -ForegroundColor White
            Write-Host "    Total Checked: $totalChecked" -ForegroundColor Gray
            Write-Host "    Compliant:     $compliantCount" -ForegroundColor $(if ($compliantCount -eq $totalChecked) { 'Green' } else { 'White' })
            Write-Host "    Missing:       $missingCount"   -ForegroundColor $(if ($missingCount   -gt 0) { 'Red' }   else { 'Green' })
            Write-Host "    Non-Compliant: $nonCompliant"   -ForegroundColor $(if ($nonCompliant   -gt 0) { 'Red' }   else { 'Green' })
            Write-Host "    Drift Total:   $drift"          -ForegroundColor $(if ($drift -gt 0) { 'Red' } else { 'Green' })
        }

        Write-TierModelLog -Level Info -Message "AuthPolicyAuditComplete" -Data @{
            TotalChecked  = $totalChecked; Compliant = $compliantCount
            Missing       = $missingCount; NonCompliant = $nonCompliant
            Drift         = $drift; DurationMs = $durationMs
            CorrelationId = $CorrelationId
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
        Write-TierModelLog -Level Error -Message "AuthPolicyAuditFailed" -Data @{
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
