function New-TierModelAuthPolicy {
    <#
    .SYNOPSIS
    Idempotently create or update AD Authentication Policies for the Tier Model.

    .DESCRIPTION
    Executes the authentication policy deployment plan produced by Get-TierModelAuthPolicyFd.
    For each CreateAuthPolicy action: creates a new AD Authentication Policy with
    New-ADAuthenticationPolicy. For each UpdateAuthPolicy action: reconciles drift with
    Set-ADAuthenticationPolicy and, if required, Set-ADObject for ProtectedFromAccidentalDeletion.

    All policies are created and maintained in AUDIT mode (Enforce:$false). Enforcement is
    a separate lifecycle step and is explicitly out of scope here. ProtectedFromAccidentalDeletion
    is always set to $true.

    The -UserTGTLifetimeMins parameter is set only when the config's userTGTLifetimeMinutes
    is non-null. A null value means the account class inherits the domain-default TGT
    lifetime (typically 10 hours) and no lifetime attribute is written.

    Safe to re-run: policies that are already in the desired state are skipped.

    .PARAMETER Plan
    Deployment plan from Get-TierModelAuthPolicyFd.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .OUTPUTS
    PSCustomObject with Applied, Skipped, Errors, DurationMs, Converged, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan   = Get-TierModelAuthPolicyFd -Config $config -DomainController 'DC01'
    New-TierModelAuthPolicy -Plan $plan -DomainController 'DC01'

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

    $actionCount = @($Plan.Actions | Where-Object { $_.Action -in @('CreateAuthPolicy', 'UpdateAuthPolicy') }).Count

    Write-TierModelLog -Level Info -Message "AuthPolicyExecutionStart" -Data @{
        ActionCount      = $actionCount
        DomainController = $DomainController
        WhatIf           = $WhatIfPreference
        CorrelationId    = $CorrelationId
    } | Out-Null

    $applied   = @()
    $skipped   = @()
    $errors    = @()
    $converged = $true

    try {
        foreach ($action in $Plan.Actions) {
            if ($action.Action -notin @('CreateAuthPolicy', 'UpdateAuthPolicy')) { continue }

            $policyName = $action.Name

            try {
                if ($action.Action -eq 'CreateAuthPolicy') {
                    # ── Create new Authentication Policy ──────────────────────────────────
                    if ($PSCmdlet.ShouldProcess("Authentication Policy: $policyName", "New-ADAuthenticationPolicy (audit mode, not enforced)")) {
                        Write-Host "  ✅ Creating Authentication Policy: $policyName" -ForegroundColor Green

                        $newParams = @{
                            Name                            = $policyName
                            Description                     = $action.Description
                            UserAllowedToAuthenticateFrom   = $action.ResolvedSddl
                            Enforce                         = $false   # Audit mode — never enforce; splatted bool binds correctly
                            ProtectedFromAccidentalDeletion = $true
                            Server                          = $DomainController
                            Confirm                         = $false
                        }

                        # Only set TGT lifetime when config specifies one (null = domain default, no attribute written)
                        if ($null -ne $action.TGTLifetimeMinutes) {
                            $newParams['UserTGTLifetimeMins'] = [int]$action.TGTLifetimeMinutes
                        }

                        $newPolicy = New-ADAuthenticationPolicy @newParams -PassThru

                        Write-TierModelLog -Level Info -Message "AuthPolicyCreated" -Data @{
                            PolicyName        = $policyName
                            DistinguishedName = $newPolicy.DistinguishedName
                            TGTLifetimeMinutes = $action.TGTLifetimeMinutes
                            CorrelationId     = $CorrelationId
                        } | Out-Null

                        $applied += [PSCustomObject]@{
                            Action            = 'CreateAuthPolicy'
                            Name              = $policyName
                            DistinguishedName = $newPolicy.DistinguishedName
                        }
                    } else {
                        Write-Host "  [WhatIf] Would create Authentication Policy: $policyName" -ForegroundColor DarkYellow
                        $skipped += [PSCustomObject]@{
                            Action = 'CreateAuthPolicy'
                            Name   = $policyName
                            Reason = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }
                        }
                    }

                } elseif ($action.Action -eq 'UpdateAuthPolicy') {
                    # ── Reconcile drift on existing Authentication Policy ─────────────────
                    if ($PSCmdlet.ShouldProcess("Authentication Policy: $policyName", "Set-ADAuthenticationPolicy (reconcile: $($action.DriftReasons -join '; '))")) {
                        Write-Host "  ✅ Updating Authentication Policy: $policyName ($($action.DriftReasons -join ', '))" -ForegroundColor Green

                        $setParams = @{
                            Identity                      = $policyName
                            Description                   = $action.Description
                            UserAllowedToAuthenticateFrom = $action.ResolvedSddl
                            Enforce                       = $false   # Audit mode — never enforce
                            Server                        = $DomainController
                            Confirm                       = $false
                        }

                        if ($null -ne $action.TGTLifetimeMinutes) {
                            $setParams['UserTGTLifetimeMins'] = [int]$action.TGTLifetimeMinutes
                        }

                        Set-ADAuthenticationPolicy @setParams

                        # ProtectedFromAccidentalDeletion is an object-level attribute,
                        # not a parameter of Set-ADAuthenticationPolicy — use Set-ADObject.
                        if ($action.DriftReasons | Where-Object { $_ -match 'ProtectedFromAccidentalDeletion' }) {
                            $policyObj = Get-ADAuthenticationPolicy -Identity $policyName -Server $DomainController
                            Set-ADObject -Identity $policyObj.DistinguishedName -ProtectedFromAccidentalDeletion $true -Server $DomainController
                        }

                        Write-TierModelLog -Level Info -Message "AuthPolicyUpdated" -Data @{
                            PolicyName    = $policyName
                            DriftReasons  = $action.DriftReasons
                            CorrelationId = $CorrelationId
                        } | Out-Null

                        $applied += [PSCustomObject]@{
                            Action       = 'UpdateAuthPolicy'
                            Name         = $policyName
                            DriftReasons = $action.DriftReasons
                        }
                    } else {
                        Write-Host "  [WhatIf] Would update Authentication Policy: $policyName ($($action.DriftReasons -join ', '))" -ForegroundColor DarkYellow
                        $skipped += [PSCustomObject]@{
                            Action = 'UpdateAuthPolicy'
                            Name   = $policyName
                            Reason = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }
                        }
                    }
                }
            } catch {
                Write-Host "  ERROR: Failed to apply policy '$policyName' — $($_.Exception.Message)" -ForegroundColor Red
                Write-TierModelLog -Level Error -Message "AuthPolicyExecutionFailed" -Data @{
                    PolicyName    = $policyName
                    Action        = $action.Action
                    Exception     = $_.Exception.Message
                    CorrelationId = $CorrelationId
                } | Out-Null
                $errors += @{
                    Timestamp = Get-Date
                    Category  = 'Execution'
                    Code      = 'AuthPolicyApplyFailed'
                    Message   = "Failed to apply policy '$policyName': $($_.Exception.Message)"
                    Context   = @{ PolicyName = $policyName; Action = $action.Action; CorrelationId = $CorrelationId }
                }
                $converged = $false
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        Write-TierModelLog -Level Info -Message "AuthPolicyExecutionComplete" -Data @{
            AppliedCount  = $applied.Count
            SkippedCount  = $skipped.Count
            ErrorCount    = $errors.Count
            DurationMs    = $durationMs
            Converged     = $converged
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied       = $applied
            Skipped       = $skipped
            Errors        = $errors
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
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged  = $false
            CorrelationId = $CorrelationId
        }
    }
}
