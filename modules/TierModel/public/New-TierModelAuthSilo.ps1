function New-TierModelAuthSilo {
    <#
    .SYNOPSIS
    Create AD Authentication Policy Silos for the Tier Model (create-once model).

    .DESCRIPTION
    Executes CreateAuthSilo actions from the plan produced by Get-TierModelAuthSiloFd.
    Each silo is created once with New-ADAuthenticationPolicySilo. If the silo already
    exists in AD the creation is silently skipped — NO modifications are made to existing
    silos (create-once model).

    Each silo links the same policy for User, Computer, and Service account classes
    (1:1 silo-to-policy design). Enforce=$false (audit mode). ProtectedFromAccidentalDeletion=$true.

    Returns CreatedSiloNames so the caller can scope membership assignment to only
    newly created silos (create-once membership model).

    .PARAMETER Plan
    Deployment plan from Get-TierModelAuthSiloFd.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .OUTPUTS
    PSCustomObject with Applied, Skipped, Errors, CreatedSiloNames, DurationMs, Converged, CorrelationId.
    CreatedSiloNames is the [string[]] of silo names actually created in this run.

    .EXAMPLE
    $plan   = Get-TierModelAuthSiloFd -Config $config -DomainController 'DC01'
    $result = New-TierModelAuthSilo -Plan $plan -DomainController 'DC01'
    # Wire membership only for newly created silos:
    Set-TierModelAuthSiloMembership -Config $config -DomainController 'DC01' -OnlyForSilos $result.CreatedSiloNames

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

    Write-TierModelLog -Level Info -Message "AuthSiloExecutionStart" -Data @{
        ActionCount = @($Plan.Actions | Where-Object { $_.Action -eq 'CreateAuthSilo' }).Count
        DomainController = $DomainController; WhatIf = $WhatIfPreference; CorrelationId = $CorrelationId
    } | Out-Null

    $applied           = @()
    $skipped           = @()
    $errors            = @()
    $createdSiloNames  = [System.Collections.Generic.List[string]]::new()
    $converged         = $true

    try {
        foreach ($action in $Plan.Actions) {
            if ($action.Action -ne 'CreateAuthSilo') { continue }

            $siloName  = $action.Name
            $policyName = $action.PolicyName

            try {
                if ($PSCmdlet.ShouldProcess("Authentication Policy Silo: $siloName", "New-ADAuthenticationPolicySilo (audit mode; policy: $policyName)")) {
                    $newParams = @{
                        Name                            = $siloName
                        Description                     = $action.Description
                        UserAuthenticationPolicy        = $policyName
                        ComputerAuthenticationPolicy    = $policyName
                        ServiceAuthenticationPolicy     = $policyName
                        Enforce                         = $false
                        ProtectedFromAccidentalDeletion = $true
                        Server                          = $DomainController
                        Confirm                         = $false
                    }

                    $newSilo = New-ADAuthenticationPolicySilo @newParams -PassThru
                    Write-Host "  `u{2705} Created Authentication Policy Silo: $siloName" -ForegroundColor Green
                    Write-TierModelLog -Level Info -Message "AuthSiloCreated" -Data @{
                        SiloName = $siloName; PolicyName = $policyName; Dn = $newSilo.DistinguishedName; CorrelationId = $CorrelationId
                    } | Out-Null

                    $createdSiloNames.Add($siloName)
                    $applied += [PSCustomObject]@{ Action = 'CreateAuthSilo'; Name = $siloName; PolicyName = $policyName; DistinguishedName = $newSilo.DistinguishedName }
                } else {
                    Write-Host "  [WhatIf] Would create Authentication Policy Silo: $siloName (policy: $policyName)" -ForegroundColor DarkYellow
                    $skipped += [PSCustomObject]@{ Action = 'CreateAuthSilo'; Name = $siloName; Reason = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' } }
                }
            } catch {
                if ($_.Exception.Message -match 'already exists|ObjectClass.*Violation|EntryAlreadyExists') {
                    Write-Host "  ℹ️  Silo already exists (skipping): $siloName" -ForegroundColor DarkGray
                    $skipped += [PSCustomObject]@{ Action = 'CreateAuthSilo'; Name = $siloName; Reason = 'AlreadyExists' }
                } else {
                    Write-Host "  `u{274C} Failed to create Authentication Policy Silo: $siloName - $($_.Exception.Message)" -ForegroundColor Red
                    $errors += @{ Timestamp = Get-Date; Category = 'Execution'; Code = 'AuthSiloCreateFailed'
                                  Message = "Failed to create silo '$siloName': $($_.Exception.Message)"
                                  Context = @{ SiloName = $siloName; CorrelationId = $CorrelationId } }
                    $converged = $false
                }
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        Write-TierModelLog -Level Info -Message "AuthSiloExecutionComplete" -Data @{
            AppliedCount = $applied.Count; SkippedCount = $skipped.Count; ErrorCount = $errors.Count
            DurationMs = $durationMs; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied           = $applied
            Skipped           = $skipped
            Errors            = $errors
            CreatedSiloNames  = [string[]]$createdSiloNames
            DurationMs        = $durationMs
            Converged         = $converged
            CorrelationId     = $CorrelationId
        }
    } catch {
        Write-TierModelLog -Level Error -Message "AuthSiloExecutionFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied = @(); Skipped = @()
            Errors  = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthSiloExecutionFailed'
                           Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            CreatedSiloNames  = [string[]]@()
            DurationMs        = ((Get-Date) - $startTime).TotalMilliseconds
            Converged         = $false; CorrelationId = $CorrelationId
        }
    }
}