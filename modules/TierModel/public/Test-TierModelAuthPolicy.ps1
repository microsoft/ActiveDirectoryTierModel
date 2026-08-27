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
            $policyName        = $policy.name
            $issues            = @()
            $extraDeviceGroups = @()
            $sidToGroupName    = @{}   # SID → group name for concise error messages

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
                    PolicyName = $policyName; Status = 'Missing'
                    Issues = @("Not found in Active Directory")
                    EnforceState = 'unknown (policy absent)'; ExtraDeviceGroups = @()
                }
                if (-not $Silent) { Write-Host "    ❌ Missing — not found in AD" -ForegroundColor Red }
                Write-TierModelLog -Level Info -Message "AuthPolicyAuditMissing" -Data @{
                    PolicyName = $policyName; CorrelationId = $CorrelationId
                } | Out-Null
                continue
            }

            # ── Enforce state — INFORMATIONAL ONLY, never contributes to pass/fail ────────
            $enforceVal   = $null
            try { $enforceVal = $adPolicy.Enforce } catch {}
            $enforceState = if ($enforceVal -eq $true) { 'ENFORCED' } elseif ($enforceVal -eq $false) { 'audit mode' } else { "unknown ($enforceVal)" }

            # ── Check 2: Description ─────────────────────────────────────────────────────
            if ($adPolicy.Description -ne $policy.description) {
                $issues += "description differs from config"
            }

            # ── Check 3: UserTGTLifetimeMins (skip when config value is null = domain default) ──
            if ($null -ne $policy.userTGTLifetimeMinutes) {
                $existingTgt = $null
                try { $existingTgt = $adPolicy.UserTGTLifetimeMins } catch {}
                if ($null -eq $existingTgt) {
                    try {
                        $rawTgt = $adPolicy.'msDS-UserTGTLifetime'
                        if ($null -ne $rawTgt -and $rawTgt -ne 0) { $existingTgt = [long]$rawTgt / 600000000 }
                    } catch {}
                }
                if ([int]$existingTgt -ne [int]$policy.userTGTLifetimeMinutes) {
                    $issues += "TGT lifetime: expected $($policy.userTGTLifetimeMinutes) min, actual $([int]$existingTgt) min"
                }
            }

            # ── Check 4: AllowedToAuthenticateFrom — SUBSET mode ─────────────────────────
            $existingSddl = $null
            try { $existingSddl = $adPolicy.UserAllowedToAuthenticateFrom } catch {}
            if ($null -eq $existingSddl) { try { $existingSddl = $adPolicy.'msDS-UserAllowedToAuthenticateFrom' } catch {} }

            $resolvedSids = @()
            $sidResolutionFailed = $false
            foreach ($groupName in @($policy.allowedToAuthenticateFromDeviceGroups)) {
                $sidResult = Resolve-TierModelPrincipalSid -Principal $groupName -DomainController $DomainController -CorrelationId $CorrelationId
                if ($sidResult.Success) {
                    $resolvedSids += $sidResult.Sid
                    $sidToGroupName[$sidResult.Sid] = $groupName
                } else {
                    $issues += "cannot resolve device group '$groupName': $($sidResult.Error)"
                    $sidResolutionFailed = $true
                }
            }

            if (-not $sidResolutionFailed) {
                $desiredSddl = Build-TierModelAuthSddl -DeviceSids $resolvedSids
                $sddlResult  = Compare-TierModelAuthSddl -DesiredSddl $desiredSddl -ExistingSddl "$existingSddl" -DomainController $DomainController -RequireSubset
                if (-not $sddlResult.Equal) {
                    # Map missing SIDs back to group names for a concise, actionable message
                    $missingSids = [regex]::Matches($sddlResult.Reason, 'S-1-5-[0-9-]+') | ForEach-Object { $_.Value }
                    $missingGroupNames = @($missingSids | ForEach-Object { if ($sidToGroupName.ContainsKey($_)) { $sidToGroupName[$_] } else { $_ } })
                    $nameStr = if ($missingGroupNames.Count -gt 0) { ": $($missingGroupNames -join ', ')" } else { '' }
                    $issues += "AllowedToAuthenticateFrom: missing required device group$($nameStr)"
                }
                $extraDeviceGroups = $sddlResult.ExtraSids
            }

            # ── Check 5: ProtectedFromAccidentalDeletion = true ──────────────────────────
            $pfad = $null
            try { $pfad = $adPolicy.ProtectedFromAccidentalDeletion } catch {}
            if ($pfad -ne $true) { $issues += "ProtectedFromAccidentalDeletion not set" }

            # NOTE: Enforce is informational only — EnforceState is reported but never fails.

            # ── Record result ─────────────────────────────────────────────────────────────
            if ($issues.Count -eq 0) {
                $compliantCount++
                $findings += [PSCustomObject]@{
                    PolicyName = $policyName; Status = 'Compliant'; Issues = @()
                    EnforceState = $enforceState; ExtraDeviceGroups = $extraDeviceGroups
                }
                if (-not $Silent) {
                    Write-Host "    ✅ Compliant (enforce: $enforceState)" -ForegroundColor Green
                    if ($extraDeviceGroups.Count -gt 0) {
                        Write-Host "    ℹ️  Extra device groups beyond config (allowed): $($extraDeviceGroups -join ', ')" -ForegroundColor Cyan
                    }
                }
            } else {
                $nonCompliant++
                $findings += [PSCustomObject]@{
                    PolicyName = $policyName; Status = 'NonCompliant'; Issues = $issues
                    EnforceState = $enforceState; ExtraDeviceGroups = $extraDeviceGroups
                }
                if (-not $Silent) {
                    foreach ($issue in $issues) {
                        Write-Host "    ❌ NonCompliant — $issue" -ForegroundColor Red
                    }
                    if ($extraDeviceGroups.Count -gt 0) {
                        Write-Host "    ℹ️  Extra device groups beyond config (allowed): $($extraDeviceGroups -join ', ')" -ForegroundColor Cyan
                    }
                    Write-Host "    ℹ️  Enforce state: $enforceState" -ForegroundColor DarkGray
                }
                # Log to file only — no Write-Warning (avoids "WARNING: ..." console spam)
                Write-TierModelLog -Level Info -Message "AuthPolicyAuditNonCompliant" -Data @{
                    PolicyName = $policyName; IssueCount = $issues.Count; EnforceState = $enforceState; CorrelationId = $CorrelationId
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
