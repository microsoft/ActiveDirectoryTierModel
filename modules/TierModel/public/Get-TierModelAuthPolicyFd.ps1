function Get-TierModelAuthPolicyFd {
    <#
    .SYNOPSIS
    Build the Authentication Policy deployment plan with fully-resolved SIDs and SDDL.

    .DESCRIPTION
    Analyzes each authenticationPolicy from tiermodel-authsilos.json against the current
    Active Directory state and produces a deployment plan (Actions array). For each policy:
      1. Resolves every allowedToAuthenticateFromDeviceGroups group name to a SID via
         Resolve-TierModelPrincipalSid.
      2. Builds the AllowedToAuthenticateFrom SDDL using OR-logic (Member_of_any) via
         Build-TierModelAuthSddl.
      3. Checks whether the policy already exists in AD.
      4. If absent: emits a CreateAuthPolicy action.
         If present: compares Description, UserTGTLifetimeMins, UserAllowedToAuthenticateFrom
         SDDL, Enforce state, and ProtectedFromAccidentalDeletion; emits UpdateAuthPolicy for
         any drift, or marks as AlreadyConverged.

    All actions carry the resolved SDDL and TGT lifetime so that New-TierModelAuthPolicy
    does not need to repeat AD lookups.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .PARAMETER IncludeDetails
    Include additional diagnostic fields in action objects (resolved SIDs, drift reasons).

    .PARAMETER Silent
    Suppress host output for use in consolidated-pipeline contexts.

    .OUTPUTS
    PSCustomObject with Actions, Summary, Warnings, Errors, DurationMs, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan   = Get-TierModelAuthPolicyFd -Config $config -DomainController 'DC01'

    .EXAMPLE
    $plan = Get-TierModelAuthPolicyFd -Config $config -DomainController 'DC01' -IncludeDetails
    $plan.Actions | Where-Object { $_.Action -eq 'UpdateAuthPolicy' } | ForEach-Object {
        Write-Host "$($_.Name): $($_.DriftReasons -join ', ')"
    }
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
    $toUpdate     = 0
    $alreadyExist = 0

    try {
        $policies = Get-TierModelAuthPolicy -Config $Config

        if ($policies.Count -eq 0) {
            $warnings += "No authentication policies found in configuration. Ensure tiermodel-authsilos.json is present."
        }

        foreach ($policy in $policies) {
            try {
                Write-TierModelLog -Level Debug -Message "AuthPolicyFdPlanCheck" -Data @{
                    PolicyName    = $policy.name
                    CorrelationId = $CorrelationId
                } | Out-Null

                # ── Step 1: Resolve device group SIDs ─────────────────────────────────────
                $resolvedSids = @()
                $sidResolutionErrors = @()

                foreach ($groupName in $policy.allowedToAuthenticateFromDeviceGroups) {
                    $sidResult = Resolve-TierModelPrincipalSid -Principal $groupName -DomainController $DomainController -CorrelationId $CorrelationId
                    if ($sidResult.Success) {
                        $resolvedSids += $sidResult.Sid
                        Write-TierModelLog -Level Debug -Message "AuthPolicyDeviceGroupResolved" -Data @{
                            PolicyName    = $policy.name
                            GroupName     = $groupName
                            Sid           = $sidResult.Sid
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        $sidResolutionErrors += "Cannot resolve SID for device group '$groupName': $($sidResult.Error)"
                    }
                }

                if ($sidResolutionErrors.Count -gt 0) {
                    foreach ($e in $sidResolutionErrors) {
                        $errors += @{
                            Timestamp = Get-Date
                            Category  = 'External'
                            Code      = 'SidResolutionFailed'
                            Message   = $e
                            Context   = @{ PolicyName = $policy.name; CorrelationId = $CorrelationId }
                        }
                    }
                    Write-TierModelLog -Level Error -Message "AuthPolicyFdSidResolutionFailed" -Data @{
                        PolicyName = $policy.name
                        Errors     = $sidResolutionErrors
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    continue
                }

                # ── Step 2: Build SDDL (OR-logic) ────────────────────────────────────────
                $resolvedSddl = Build-TierModelAuthSddl -DeviceSids $resolvedSids

                # ── Step 3: Check AD state ────────────────────────────────────────────────
                $existingPolicy = $null
                try {
                    $existingPolicy = Get-ADAuthenticationPolicy -Identity $policy.name -Properties * -Server $DomainController -ErrorAction Stop
                } catch {
                    # Policy does not exist — will be created
                }

                if (-not $existingPolicy) {
                    $action = [PSCustomObject]@{
                        Action             = 'CreateAuthPolicy'
                        ResourceType       = 'AuthenticationPolicy'
                        Name               = $policy.name
                        Description        = $policy.description
                        TGTLifetimeMinutes = $policy.userTGTLifetimeMinutes
                        ResolvedSddl       = $resolvedSddl
                        DriftReasons       = @()
                        Data               = $policy
                    }
                    if ($IncludeDetails) {
                        $action | Add-Member -NotePropertyName 'ResolvedSids' -NotePropertyValue $resolvedSids
                    }
                    $actions += $action
                    $toCreate++

                    Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanCreate" -Data @{
                        PolicyName    = $policy.name
                        CorrelationId = $CorrelationId
                    } | Out-Null
                } else {
                    # ── Step 4: Drift detection ──────────────────────────────────────────
                    $driftReasons = @()

                    # ProtectedFromAccidentalDeletion must be true
                    $pfad = $null
                    try { $pfad = $existingPolicy.ProtectedFromAccidentalDeletion } catch {}
                    if ($pfad -ne $true) {
                        $driftReasons += "ProtectedFromAccidentalDeletion should be True (actual: $pfad)"
                    }

                    # Enforce must be false (audit mode — never enforce)
                    $enforceVal = $null
                    try { $enforceVal = $existingPolicy.Enforce } catch {}
                    if ($null -ne $enforceVal -and $enforceVal -eq $true) {
                        $driftReasons += "Enforce should be False/audit mode (actual: True)"
                    }

                    # Description
                    if ($existingPolicy.Description -ne $policy.description) {
                        $driftReasons += "Description differs"
                    }

                    # TGT lifetime — only check when config specifies a value (null = domain default, skip)
                    if ($null -ne $policy.userTGTLifetimeMinutes) {
                        $existingTgt = $null
                        try { $existingTgt = $existingPolicy.UserTGTLifetimeMins } catch {}
                        # Fall back to raw AD attribute (stored as 100-ns intervals)
                        if ($null -eq $existingTgt) {
                            try {
                                $rawTgt = $existingPolicy.'msDS-UserTGTLifetime'
                                if ($null -ne $rawTgt -and $rawTgt -ne 0) {
                                    $existingTgt = [long]$rawTgt / 600000000
                                }
                            } catch {}
                        }
                        if ([int]$existingTgt -ne [int]$policy.userTGTLifetimeMinutes) {
                            $driftReasons += "UserTGTLifetimeMins differs (expected $($policy.userTGTLifetimeMinutes), actual $existingTgt)"
                        }
                    }

                    # SDDL — use alias-aware, order-insensitive SID-set comparison.
                    # AD may store the policy with SDDL well-known aliases for domain groups
                    # (e.g. DD for Domain Controllers / RID 516) even when a full SID was
                    # written. Compare-TierModelAuthSddl normalizes both sides before comparing.
                    $existingSddl = $null
                    try { $existingSddl = $existingPolicy.UserAllowedToAuthenticateFrom } catch {}
                    if ($null -eq $existingSddl) {
                        try { $existingSddl = $existingPolicy.'msDS-UserAllowedToAuthenticateFrom' } catch {}
                    }
                    $sddlResult = Compare-TierModelAuthSddl `
                        -DesiredSddl  $resolvedSddl `
                        -ExistingSddl "$existingSddl" `
                        -DomainController $DomainController
                    if (-not $sddlResult.Equal) {
                        $driftReasons += "UserAllowedToAuthenticateFrom SDDL differs: $($sddlResult.Reason)"
                    }

                    if ($driftReasons.Count -gt 0) {
                        $action = [PSCustomObject]@{
                            Action             = 'UpdateAuthPolicy'
                            ResourceType       = 'AuthenticationPolicy'
                            Name               = $policy.name
                            Description        = $policy.description
                            TGTLifetimeMinutes = $policy.userTGTLifetimeMinutes
                            ResolvedSddl       = $resolvedSddl
                            DriftReasons       = $driftReasons
                            Data               = $policy
                        }
                        if ($IncludeDetails) {
                            $action | Add-Member -NotePropertyName 'ResolvedSids'       -NotePropertyValue $resolvedSids
                            $action | Add-Member -NotePropertyName 'ExistingDn'         -NotePropertyValue $existingPolicy.DistinguishedName
                        }
                        $actions += $action
                        $toUpdate++

                        Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanUpdate" -Data @{
                            PolicyName    = $policy.name
                            DriftReasons  = $driftReasons
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        $alreadyExist++
                        Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanConverged" -Data @{
                            PolicyName    = $policy.name
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    }
                }
            } catch {
                $errors += @{
                    Timestamp = Get-Date
                    Category  = 'Execution'
                    Code      = 'AuthPolicyFdPlanItemFailed'
                    Message   = "Failed to plan policy '$($policy.name)': $($_.Exception.Message)"
                    Context   = @{ PolicyName = $policy.name; CorrelationId = $CorrelationId }
                }
                Write-TierModelLog -Level Error -Message "AuthPolicyFdPlanItemFailed" -Data @{
                    PolicyName    = $policy.name
                    Exception     = $_.Exception.Message
                    CorrelationId = $CorrelationId
                } | Out-Null
            }
        }

        $summary = @{
            TotalInConfig  = @($policies).Count
            ToCreate       = $toCreate
            ToUpdate       = $toUpdate
            AlreadyExist   = $alreadyExist
            TotalActions   = $toCreate + $toUpdate
            CreateActions  = $toCreate
            ExistingCount  = $alreadyExist
        }

        Write-TierModelLog -Level Info -Message "AuthPolicyFdPlanComplete" -Data @{
            Summary       = $summary
            ErrorCount    = $errors.Count
            WarningCount  = $warnings.Count
            CorrelationId = $CorrelationId
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
            Exception     = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalInConfig = 0; ToCreate = 0; ToUpdate = 0; AlreadyExist = 0; TotalActions = 0; CreateActions = 0; ExistingCount = 0 }
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
