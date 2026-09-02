function Get-TierModelAuthSiloFd {
    <#
    .SYNOPSIS
    Build the Authentication Policy Silo deployment plan (create-once model).

    .DESCRIPTION
    Analyzes each authenticationSilo from tiermodel-authsilos.json against the current
    Active Directory state. For each silo:
      - Validates the referenced policy name is defined in config (guards against typos).
      - If the silo does NOT exist in AD: emits a CreateAuthSilo action.
      - If the silo ALREADY EXISTS in AD: marks AlreadyExists and does nothing else.
        No drift detection, no update actions — existing silos are never modified by deploy.

    This create-once model means re-running deploy after a full deployment is a safe no-op.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .PARAMETER IncludeDetails
    Include additional diagnostic fields in action objects.

    .PARAMETER Silent
    Suppress host output for use in consolidated-pipeline contexts.

    .OUTPUTS
    PSCustomObject with Actions, Summary, Warnings, Errors, DurationMs, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan   = Get-TierModelAuthSiloFd -Config $config -DomainController 'DC01'
    $plan.Summary   # ToCreate = N, AlreadyExist = M

    .EXAMPLE
    $plan.Actions | Select-Object Name, PolicyName   # only CreateAuthSilo actions
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

    Write-TierModelLog -Level Info -Message "AuthSiloFdPlanStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    $actions      = @()
    $warnings     = @()
    $errors       = @()
    $toCreate     = 0
    $alreadyExist = 0

    try {
        $silos = Get-TierModelAuthSilo -Config $Config

        if ($silos.Count -eq 0) {
            $warnings += "No authentication silos found in configuration. Ensure tiermodel-authsilos.json is present."
        }

        foreach ($silo in $silos) {
            try {
                $policyName = $silo.policy

                # Validate the referenced policy is defined in config (guards against config typos)
                $configPolicies = if ($Config.PSObject.Properties['authenticationPolicies'] -and $Config.authenticationPolicies) { @($Config.authenticationPolicies) } else { @() }
                $policyInConfig = $configPolicies | Where-Object { $_.name -eq $policyName } | Select-Object -First 1

                if (-not $policyInConfig) {
                    $errors += @{
                        Timestamp = Get-Date; Category = 'Configuration'; Code = 'ReferencedPolicyNotInConfig'
                        Message   = "Silo '$($silo.name)' references policy '$policyName' which is not defined in authenticationPolicies config."
                        Context   = @{ SiloName = $silo.name; PolicyName = $policyName; CorrelationId = $CorrelationId }
                    }
                    continue
                }

                # ── Create-once model: check existence only, NO drift detection ────────────
                $existsInAd = $false
                try {
                    Get-ADAuthenticationPolicySilo -Identity $silo.name -Server $DomainController -ErrorAction Stop | Out-Null
                    $existsInAd = $true
                } catch {
                    # Does not exist — will be created
                }

                if ($existsInAd) {
                    $alreadyExist++
                    Write-TierModelLog -Level Info -Message "AuthSiloFdPlanAlreadyExists" -Data @{
                        SiloName = $silo.name; CorrelationId = $CorrelationId
                    } | Out-Null
                } else {
                    $action = [PSCustomObject]@{
                        Action       = 'CreateAuthSilo'
                        ResourceType = 'AuthenticationPolicySilo'
                        Name         = $silo.name
                        Description  = $silo.description
                        PolicyName   = $policyName
                        PolicyDn     = $null   # resolved at execution time when policy exists
                        Data         = $silo
                    }
                    $actions += $action
                    $toCreate++

                    Write-TierModelLog -Level Info -Message "AuthSiloFdPlanCreate" -Data @{
                        SiloName = $silo.name; PolicyName = $policyName; CorrelationId = $CorrelationId
                    } | Out-Null
                }
            } catch {
                $errors += @{
                    Timestamp = Get-Date; Category = 'Execution'; Code = 'AuthSiloFdPlanItemFailed'
                    Message   = "Failed to plan silo '$($silo.name)': $($_.Exception.Message)"
                    Context   = @{ SiloName = $silo.name; CorrelationId = $CorrelationId }
                }
                Write-TierModelLog -Level Error -Message "AuthSiloFdPlanItemFailed" -Data @{
                    SiloName = $silo.name; Exception = $_.Exception.Message; CorrelationId = $CorrelationId
                } | Out-Null
            }
        }

        $summary = @{
            TotalInConfig = @($silos).Count
            ToCreate      = $toCreate
            AlreadyExist  = $alreadyExist
            TotalActions  = $toCreate
            CreateActions = $toCreate
            ExistingCount = $alreadyExist
        }

        Write-TierModelLog -Level Info -Message "AuthSiloFdPlanComplete" -Data @{
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
        Write-TierModelLog -Level Error -Message "AuthSiloFdPlanFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalInConfig = 0; ToCreate = 0; AlreadyExist = 0; TotalActions = 0; CreateActions = 0; ExistingCount = 0 }
            Warnings   = $warnings
            Errors     = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthSiloFdPlanFailed'
                               Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}