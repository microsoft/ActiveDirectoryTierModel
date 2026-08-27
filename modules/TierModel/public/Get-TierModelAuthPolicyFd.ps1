function Get-TierModelAuthPolicyFd {
    <#
    .SYNOPSIS
    Build the Authentication Policy deployment plan with fully-resolved SIDs and SDDL.

    .DESCRIPTION
    Analyzes each authenticationPolicy from tiermodel-authsilos.json against the current
    Active Directory state and produces a deployment plan (Actions array). For each policy:
      - If the policy does NOT exist in AD: resolves device group SIDs, builds the SDDL,
        emits a CreateAuthPolicy action.
      - If the policy ALREADY EXISTS in AD: marks AlreadyExists and does nothing else.
        No drift detection, no update actions — existing policies are never modified by deploy.

    This create-once model means re-running deploy after a full deployment is a safe no-op.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .PARAMETER IncludeDetails
    Include additional diagnostic fields in action objects (resolved SIDs).

    .PARAMETER Silent
    Suppress host output for use in consolidated-pipeline contexts.

    .OUTPUTS
    PSCustomObject with Actions, Summary, Warnings, Errors, DurationMs, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan   = Get-TierModelAuthPolicyFd -Config $config -DomainController 'DC01'

    .EXAMPLE
    $plan.Actions | Select-Object Name, TGTLifetimeMinutes   # only CreateAuthPolicy actions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [switch]$IncludeDetails,

        [switch]$Silent
    )

    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    $actions      = @()
    $warnings     = @()
    $errors       = @()
    $toCreate     = 0
    $alreadyExist = 0

    try {
        $policies = Get-TierModelAuthPolicy -Config $Config

        if ($policies.Count -eq 0) {
            $warnings += "No authentication policies found in configuration. Ensure tiermodel-authsilos.json is present."
        }

        foreach ($policy in $policies) {
            try {
                # ── Create-once model: check existence only, NO drift detection ────────────
                # If the policy exists in AD it is left untouched regardless of any property
                # difference. Modifications to existing policies are an out-of-band operation.
                $existsInAd = $false
                try {
                    Get-ADAuthenticationPolicy -Identity $policy.name -Server $DomainController -ErrorAction Stop | Out-Null
                    $existsInAd = $true
                } catch {
                    # Does not exist — will be created
                }

                if ($existsInAd) {
                    $alreadyExist++
                    Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanAlreadyExists" -Data @{
                        PolicyName = $policy.name; CorrelationId = $CorrelationId
                    } | Out-Null
                } else {
                    # Create-once model: device-group SID resolution and SDDL construction are
                    # DEFERRED to execution time (New-TierModelAuthPolicy). At plan time the
                    # approved-device groups may not exist yet — a fresh -FullDeployment creates
                    # the tier device groups earlier in the same run, so resolving here would fail
                    # before those groups exist. This mirrors the silo planner deferring PolicyDn
                    # to execution time. The plan simply enumerates what will be created.
                    $action = [PSCustomObject]@{
                        Action             = 'CreateAuthPolicy'
                        ResourceType       = 'AuthenticationPolicy'
                        Name               = $policy.name
                        Description        = $policy.description
                        TGTLifetimeMinutes = $policy.userTGTLifetimeMinutes
                        ResolvedSddl       = $null   # resolved at execution from Data.allowedToAuthenticateFromDeviceGroups
                        Data               = $policy
                    }
                    $actions += $action
                    $toCreate++

                    Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanCreate" -Data @{
                        PolicyName = $policy.name; CorrelationId = $CorrelationId
                    } | Out-Null
                }
            } catch {
                $errors += @{
                    Timestamp = Get-Date; Category = 'Execution'; Code = 'AuthPolicyFdPlanItemFailed'
                    Message   = "Failed to plan policy '$($policy.name)': $($_.Exception.Message)"
                    Context   = @{ PolicyName = $policy.name; CorrelationId = $CorrelationId }
                }
                Write-TierModelLog -Level Error -Message "AuthPolicyFdPlanItemFailed" -Data @{
                    PolicyName = $policy.name; Exception = $_.Exception.Message; CorrelationId = $CorrelationId
                } | Out-Null
            }
        }

        $summary = @{
            TotalInConfig = @($policies).Count
            ToCreate      = $toCreate
            AlreadyExist  = $alreadyExist
            TotalActions  = $toCreate
            CreateActions = $toCreate
            ExistingCount = $alreadyExist
        }

        Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanComplete" -Data @{
            Summary = $summary; ErrorCount = $errors.Count; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions       = $actions
            Summary       = $summary
            Warnings      = $warnings
            Errors        = $errors
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }

    } catch {
        Write-TierModelLog -Level Error -Message "AuthPolicyFdPlanFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalInConfig = 0; ToCreate = 0; AlreadyExist = 0; TotalActions = 0; CreateActions = 0; ExistingCount = 0 }
            Warnings   = $warnings
            Errors     = @(@{
                Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthPolicyFdPlanFailed'
                Message   = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
