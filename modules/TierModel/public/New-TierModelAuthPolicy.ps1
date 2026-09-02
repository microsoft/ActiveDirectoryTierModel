function New-TierModelAuthPolicy {
    <#
    .SYNOPSIS
    Create AD Authentication Policies for the Tier Model (create-once model).

    .DESCRIPTION
    Executes CreateAuthPolicy actions from the plan produced by Get-TierModelAuthPolicyFd.
    Each policy is created once with New-ADAuthenticationPolicy. If the policy already
    exists in AD the creation is silently skipped — NO modifications are made to existing
    policies (create-once model).

    All policies are created in AUDIT mode (Enforce=$false). ProtectedFromAccidentalDeletion=$true.
    UserTGTLifetimeMins is set only when the config value is non-null (null = domain default).

    .PARAMETER Plan
    Deployment plan from Get-TierModelAuthPolicyFd.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .OUTPUTS
    PSCustomObject with Applied, Skipped, Errors, CreatedNames, DurationMs, Converged, CorrelationId.
    CreatedNames is the [string[]] of policy names actually created in this run.

    .EXAMPLE
    $plan = Get-TierModelAuthPolicyFd -Config $config -DomainController 'DC01'
    $result = New-TierModelAuthPolicy -Plan $plan -DomainController 'DC01'
    Write-Host "Created: $($result.CreatedNames -join ', ')"

    .EXAMPLE
    New-TierModelAuthPolicy -Plan $plan -DomainController 'DC01' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [string]$DomainController
    )

    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuthPolicyExecutionStart" -Data @{
        ActionCount = @($Plan.Actions | Where-Object { $_.Action -eq 'CreateAuthPolicy' }).Count
        DomainController = $DomainController; WhatIf = $WhatIfPreference; CorrelationId = $CorrelationId
    } | Out-Null

    $applied      = @()
    $skipped      = @()
    $errors       = @()
    $createdNames = [System.Collections.Generic.List[string]]::new()
    $converged    = $true

    try {
        foreach ($action in $Plan.Actions) {
            if ($action.Action -ne 'CreateAuthPolicy') { continue }

            $policyName = $action.Name

            try {
                if ($PSCmdlet.ShouldProcess("Authentication Policy: $policyName", "New-ADAuthenticationPolicy (audit mode, not enforced)")) {
                    # Resolve approved-device group SIDs and build the SDDL at EXECUTION time.
                    # Create-once defers this from plan time so a fresh -FullDeployment can create
                    # the tier device groups earlier in the same run. Honor a planner-supplied SDDL
                    # if present; otherwise resolve now from the policy config. A genuinely missing
                    # group at execution time is a clean red failure for this policy only.
                    $resolvedSddl = $action.ResolvedSddl
                    if ([string]::IsNullOrWhiteSpace($resolvedSddl)) {
                        $resolvedSids        = @()
                        $sidResolutionErrors = @()
                        foreach ($groupName in @($action.Data.allowedToAuthenticateFromDeviceGroups)) {
                            $sidResult = Resolve-TierModelPrincipalSid -Principal $groupName -DomainController $DomainController -CorrelationId $CorrelationId -WarningAction SilentlyContinue
                            if ($sidResult.Success) {
                                $resolvedSids += $sidResult.Sid
                            } else {
                                $sidResolutionErrors += "device group '$groupName' not found in Active Directory"
                            }
                        }
                        if ($sidResolutionErrors.Count -gt 0) {
                            $reason = $sidResolutionErrors -join '; '
                            Write-Host "  `u{274C} Failed to create Authentication Policy: $policyName - $reason" -ForegroundColor Red
                            $errors += @{ Timestamp = Get-Date; Category = 'External'; Code = 'SidResolutionFailed'
                                          Message = "Failed to create policy '$policyName': $reason"
                                          Context = @{ PolicyName = $policyName; CorrelationId = $CorrelationId } }
                            $converged = $false
                            continue
                        }
                        $resolvedSddl = Build-TierModelAuthSddl -DeviceSids $resolvedSids
                    }

                    $newParams = @{
                        Name                            = $policyName
                        Description                     = $action.Description
                        UserAllowedToAuthenticateFrom   = $resolvedSddl
                        Enforce                         = $false
                        ProtectedFromAccidentalDeletion = $true
                        Server                          = $DomainController
                        Confirm                         = $false
                    }
                    if ($null -ne $action.TGTLifetimeMinutes) {
                        $newParams['UserTGTLifetimeMins'] = [int]$action.TGTLifetimeMinutes
                    }

                    $newPolicy = New-ADAuthenticationPolicy @newParams -PassThru
                    Write-Host "  `u{2705} Created Authentication Policy: $policyName" -ForegroundColor Green
                    Write-TierModelLog -Level Info -Message "AuthPolicyCreated" -Data @{
                        PolicyName = $policyName; Dn = $newPolicy.DistinguishedName; CorrelationId = $CorrelationId
                    } | Out-Null

                    $createdNames.Add($policyName)
                    $applied += [PSCustomObject]@{ Action = 'CreateAuthPolicy'; Name = $policyName; DistinguishedName = $newPolicy.DistinguishedName }
                } else {
                    Write-Host "  [WhatIf] Would create Authentication Policy: $policyName" -ForegroundColor DarkYellow
                    $skipped += [PSCustomObject]@{ Action = 'CreateAuthPolicy'; Name = $policyName; Reason = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' } }
                }
            } catch {
                # If it already exists (race/idempotency), skip silently rather than error
                if ($_.Exception.Message -match 'already exists|ObjectClass.*Violation|EntryAlreadyExists') {
                    Write-Host "  ℹ️  Policy already exists (skipping): $policyName" -ForegroundColor DarkGray
                    $skipped += [PSCustomObject]@{ Action = 'CreateAuthPolicy'; Name = $policyName; Reason = 'AlreadyExists' }
                } else {
                    Write-Host "  `u{274C} Failed to create Authentication Policy: $policyName - $($_.Exception.Message)" -ForegroundColor Red
                    $errors += @{ Timestamp = Get-Date; Category = 'Execution'; Code = 'AuthPolicyCreateFailed'
                                  Message = "Failed to create policy '$policyName': $($_.Exception.Message)"
                                  Context = @{ PolicyName = $policyName; CorrelationId = $CorrelationId } }
                    $converged = $false
                }
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        Write-TierModelLog -Level Info -Message "AuthPolicyExecutionComplete" -Data @{
            AppliedCount = $applied.Count; SkippedCount = $skipped.Count; ErrorCount = $errors.Count
            DurationMs = $durationMs; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied       = $applied
            Skipped       = $skipped
            Errors        = $errors
            CreatedNames  = [string[]]$createdNames
            DurationMs    = $durationMs
            Converged     = $converged
            CorrelationId = $CorrelationId
        }
    } catch {
        Write-TierModelLog -Level Error -Message "AuthPolicyExecutionFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied = @(); Skipped = @()
            Errors  = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthPolicyExecutionFailed'
                           Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            CreatedNames  = [string[]]@()
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            Converged     = $false; CorrelationId = $CorrelationId
        }
    }
}