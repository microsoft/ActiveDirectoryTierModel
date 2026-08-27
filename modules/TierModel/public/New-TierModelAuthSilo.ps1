function New-TierModelAuthSilo {
    <#
    .SYNOPSIS
    Idempotently create or update AD Authentication Policy Silos for the Tier Model.

    .DESCRIPTION
    Executes the authentication silo deployment plan produced by Get-TierModelAuthSiloFd.
    For each CreateAuthSilo action: creates a new AD Authentication Policy Silo with
    New-ADAuthenticationPolicySilo. For each UpdateAuthSilo action: reconciles drift with
    Set-ADAuthenticationPolicySilo and, if required, Set-ADObject for
    ProtectedFromAccidentalDeletion.

    Each silo links the same policy for User, Computer, and Service account classes
    (1:1 silo-to-policy design from config). All three class-policy parameters
    (-UserAuthenticationPolicy, -ComputerAuthenticationPolicy, -ServiceAuthenticationPolicy)
    are set to the same policy. This ensures all account classes within a tier share the
    same origin-device restrictions.

    All silos are created in AUDIT mode (Enforce:$false). Enforcement is a separate lifecycle
    step and is explicitly out of scope here. ProtectedFromAccidentalDeletion = $true always.

    Safe to re-run: silos that are already in the desired state are skipped.

    .PARAMETER Plan
    Deployment plan from Get-TierModelAuthSiloFd.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .OUTPUTS
    PSCustomObject with Applied, Skipped, Errors, DurationMs, Converged, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan   = Get-TierModelAuthSiloFd -Config $config -DomainController 'DC01'
    New-TierModelAuthSilo -Plan $plan -DomainController 'DC01'

    .EXAMPLE
    New-TierModelAuthSilo -Plan $plan -DomainController 'DC01' -WhatIf
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

    $actionCount = @($Plan.Actions | Where-Object { $_.Action -in @('CreateAuthSilo', 'UpdateAuthSilo') }).Count

    Write-TierModelLog -Level Info -Message "AuthSiloExecutionStart" -Data @{
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
            if ($action.Action -notin @('CreateAuthSilo', 'UpdateAuthSilo')) { continue }

            $siloName  = $action.Name
            $policyName = $action.PolicyName

            try {
                if ($action.Action -eq 'CreateAuthSilo') {
                    # ── Create new Authentication Policy Silo ─────────────────────────────
                    if ($PSCmdlet.ShouldProcess("Authentication Policy Silo: $siloName", "New-ADAuthenticationPolicySilo (audit mode, not enforced; policy: $policyName)")) {
                        Write-Host "  ✅ Creating Authentication Policy Silo: $siloName" -ForegroundColor Green

                        # All three account-class policies set to the same policy (1:1 design).
                        # Setting ComputerAuthenticationPolicy and ServiceAuthenticationPolicy
                        # to the same policy ensures complete coverage without requiring
                        # separate per-class policies — consistent with the 1:1 silo-policy model.
                        $newParams = @{
                            Name                          = $siloName
                            Description                   = $action.Description
                            UserAuthenticationPolicy      = $policyName
                            ComputerAuthenticationPolicy  = $policyName
                            ServiceAuthenticationPolicy   = $policyName
                            Enforce                       = $false   # Audit mode — never enforce
                            ProtectedFromAccidentalDeletion = $true
                            Server                        = $DomainController
                            Confirm                       = $false
                        }

                        $newSilo = New-ADAuthenticationPolicySilo @newParams -PassThru

                        Write-TierModelLog -Level Info -Message "AuthSiloCreated" -Data @{
                            SiloName          = $siloName
                            PolicyName        = $policyName
                            DistinguishedName = $newSilo.DistinguishedName
                            CorrelationId     = $CorrelationId
                        } | Out-Null

                        $applied += [PSCustomObject]@{
                            Action            = 'CreateAuthSilo'
                            Name              = $siloName
                            PolicyName        = $policyName
                            DistinguishedName = $newSilo.DistinguishedName
                        }
                    } else {
                        Write-Host "  [WhatIf] Would create Authentication Policy Silo: $siloName (policy: $policyName)" -ForegroundColor DarkYellow
                        $skipped += [PSCustomObject]@{
                            Action = 'CreateAuthSilo'
                            Name   = $siloName
                            Reason = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }
                        }
                    }

                } elseif ($action.Action -eq 'UpdateAuthSilo') {
                    # ── Reconcile drift on existing silo ─────────────────────────────────
                    if ($PSCmdlet.ShouldProcess("Authentication Policy Silo: $siloName", "Set-ADAuthenticationPolicySilo (reconcile: $($action.DriftReasons -join '; '))")) {
                        Write-Host "  ✅ Updating Authentication Policy Silo: $siloName ($($action.DriftReasons -join ', '))" -ForegroundColor Green

                        $setParams = @{
                            Identity                     = $siloName
                            Description                  = $action.Description
                            UserAuthenticationPolicy     = $policyName
                            ComputerAuthenticationPolicy = $policyName
                            ServiceAuthenticationPolicy  = $policyName
                            Enforce                      = $false   # Audit mode — never enforce
                            Server                       = $DomainController
                            Confirm                      = $false
                        }

                        Set-ADAuthenticationPolicySilo @setParams

                        # ProtectedFromAccidentalDeletion requires Set-ADObject
                        if ($action.DriftReasons | Where-Object { $_ -match 'ProtectedFromAccidentalDeletion' }) {
                            $siloObj = Get-ADAuthenticationPolicySilo -Identity $siloName -Server $DomainController
                            Set-ADObject -Identity $siloObj.DistinguishedName -ProtectedFromAccidentalDeletion $true -Server $DomainController
                        }

                        Write-TierModelLog -Level Info -Message "AuthSiloUpdated" -Data @{
                            SiloName      = $siloName
                            DriftReasons  = $action.DriftReasons
                            CorrelationId = $CorrelationId
                        } | Out-Null

                        $applied += [PSCustomObject]@{
                            Action       = 'UpdateAuthSilo'
                            Name         = $siloName
                            DriftReasons = $action.DriftReasons
                        }
                    } else {
                        Write-Host "  [WhatIf] Would update Authentication Policy Silo: $siloName ($($action.DriftReasons -join ', '))" -ForegroundColor DarkYellow
                        $skipped += [PSCustomObject]@{
                            Action = 'UpdateAuthSilo'
                            Name   = $siloName
                            Reason = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }
                        }
                    }
                }
            } catch {
                Write-Host "  ERROR: Failed to apply silo '$siloName' — $($_.Exception.Message)" -ForegroundColor Red
                Write-TierModelLog -Level Error -Message "AuthSiloExecutionFailed" -Data @{
                    SiloName      = $siloName
                    Action        = $action.Action
                    Exception     = $_.Exception.Message
                    CorrelationId = $CorrelationId
                } | Out-Null
                $errors += @{
                    Timestamp = Get-Date
                    Category  = 'Execution'
                    Code      = 'AuthSiloApplyFailed'
                    Message   = "Failed to apply silo '$siloName': $($_.Exception.Message)"
                    Context   = @{ SiloName = $siloName; Action = $action.Action; CorrelationId = $CorrelationId }
                }
                $converged = $false
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        Write-TierModelLog -Level Info -Message "AuthSiloExecutionComplete" -Data @{
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
        Write-TierModelLog -Level Error -Message "AuthSiloExecutionFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied = @(); Skipped = @()
            Errors  = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthSiloExecutionFailed'
                           Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged  = $false
            CorrelationId = $CorrelationId
        }
    }
}
