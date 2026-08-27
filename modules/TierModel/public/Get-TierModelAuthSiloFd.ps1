function Get-TierModelAuthSiloFd {
    <#
    .SYNOPSIS
    Build the Authentication Policy Silo deployment plan with fully-resolved policy references.

    .DESCRIPTION
    Analyzes each authenticationSilo from tiermodel-authsilos.json against the current
    Active Directory state and produces a deployment plan (Actions array). For each silo:
      1. Validates that the referenced authentication policy (1:1 mapping) exists in AD.
      2. Checks whether the silo itself exists in AD (Get-ADAuthenticationPolicySilo).
      3. If absent: emits a CreateAuthSilo action.
         If present: compares Description, linked policy, Enforce state, and
         ProtectedFromAccidentalDeletion; emits UpdateAuthSilo for any drift.

    The silo links the same policy for User, Computer, and Service account classes
    (1:1 policy-to-silo design). This is intentional: all account classes in a given
    tier use the same origin-device restrictions.

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

    .EXAMPLE
    $plan = Get-TierModelAuthSiloFd -Config $config -DomainController 'DC01' -IncludeDetails
    $plan.Actions | Select-Object Name, Action, DriftReasons
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
    $toUpdate     = 0
    $alreadyExist = 0

    try {
        $silos = Get-TierModelAuthSilo -Config $Config

        if ($silos.Count -eq 0) {
            $warnings += "No authentication silos found in configuration. Ensure tiermodel-authsilos.json is present."
        }

        foreach ($silo in $silos) {
            try {
                Write-TierModelLog -Level Debug -Message "AuthSiloFdPlanCheck" -Data @{
                    SiloName      = $silo.name
                    CorrelationId = $CorrelationId
                } | Out-Null

                # ── Step 1: Validate the referenced policy is defined in config ─────────
                # Validate against config — NOT against AD — so a first-deploy that creates
                # both policies and silos in the same run never fails here. Policies are
                # applied before silos in the deploy segment, so the policy may not yet exist
                # in AD when this planner runs. A policy name absent from config is a real
                # configuration error; a policy pending creation in the same run is not.
                $policyName = $silo.policy
                $configPolicies = if ($Config.PSObject.Properties['authenticationPolicies'] -and $Config.authenticationPolicies) { @($Config.authenticationPolicies) } else { @() }
                $policyInConfig = $configPolicies | Where-Object { $_.name -eq $policyName } | Select-Object -First 1

                if (-not $policyInConfig) {
                    $errors += @{
                        Timestamp = Get-Date
                        Category  = 'Configuration'
                        Code      = 'ReferencedPolicyNotInConfig'
                        Message   = "Silo '$($silo.name)' references policy '$policyName' which is not defined in authenticationPolicies config. Check tiermodel-authsilos.json."
                        Context   = @{ SiloName = $silo.name; PolicyName = $policyName; CorrelationId = $CorrelationId }
                    }
                    continue
                }

                # Attempt to resolve the policy DN from AD for drift-detection context only.
                # Not finding it in AD is expected on a first deploy and is NOT an error here.
                $referencedPolicy = $null
                try { $referencedPolicy = Get-ADAuthenticationPolicy -Identity $policyName -Server $DomainController -ErrorAction SilentlyContinue } catch {}

                # ── Step 2: Check AD state ────────────────────────────────────────────
                $existingSilo = $null
                try {
                    $existingSilo = Get-ADAuthenticationPolicySilo -Identity $silo.name -Properties * -Server $DomainController -ErrorAction Stop
                } catch {
                    # Silo does not exist — will be created
                }

                if (-not $existingSilo) {
                    $action = [PSCustomObject]@{
                        Action       = 'CreateAuthSilo'
                        ResourceType = 'AuthenticationPolicySilo'
                        Name         = $silo.name
                        Description  = $silo.description
                        PolicyName   = $policyName
                        PolicyDn     = if ($referencedPolicy) { $referencedPolicy.DistinguishedName } else { $null }
                        DriftReasons = @()
                        Data         = $silo
                    }
                    $actions += $action
                    $toCreate++

                    Write-TierModelLog -Level Info -Message "AuthSiloFdPlanCreate" -Data @{
                        SiloName      = $silo.name
                        PolicyName    = $policyName
                        CorrelationId = $CorrelationId
                    } | Out-Null
                } else {
                    # ── Step 3: Drift detection ──────────────────────────────────────────
                    $driftReasons = @()

                    # ProtectedFromAccidentalDeletion
                    $pfad = $null
                    try { $pfad = $existingSilo.ProtectedFromAccidentalDeletion } catch {}
                    if ($pfad -ne $true) {
                        $driftReasons += "ProtectedFromAccidentalDeletion should be True (actual: $pfad)"
                    }

                    # Enforce must be false
                    $enforceVal = $null
                    try { $enforceVal = $existingSilo.Enforce } catch {}
                    if ($null -ne $enforceVal -and $enforceVal -eq $true) {
                        $driftReasons += "Enforce should be False/audit mode (actual: True)"
                    }

                    # Description
                    if ($existingSilo.Description -ne $silo.description) {
                        $driftReasons += "Description differs"
                    }

                    # Verify all three policy class links point to the configured policy.
                    # The 1:1 silo-policy design sets User, Computer, and Service policies
                    # all to the same policy — drift if any of the three diverges.
                    foreach ($policyProp in @('UserAuthenticationPolicy', 'ComputerAuthenticationPolicy', 'ServiceAuthenticationPolicy')) {
                        $currentPolicyRef = $null
                        try { $currentPolicyRef = $existingSilo.$policyProp } catch {}
                        # The property may be a DN or a name; normalize to check
                        $currentPolicyName = if ($currentPolicyRef -match '^CN=') {
                            ($currentPolicyRef -split ',')[0] -replace '^CN=', ''
                        } else {
                            "$currentPolicyRef"
                        }
                        if ($currentPolicyName -ne $policyName) {
                            $driftReasons += "$policyProp differs (expected '$policyName', actual '$currentPolicyName')"
                        }
                    }

                    if ($driftReasons.Count -gt 0) {
                        $action = [PSCustomObject]@{
                            Action       = 'UpdateAuthSilo'
                            ResourceType = 'AuthenticationPolicySilo'
                            Name         = $silo.name
                            Description  = $silo.description
                            PolicyName   = $policyName
                            PolicyDn     = if ($referencedPolicy) { $referencedPolicy.DistinguishedName } else { $null }
                            DriftReasons = $driftReasons
                            Data         = $silo
                        }
                        if ($IncludeDetails) {
                            $action | Add-Member -NotePropertyName 'ExistingDn' -NotePropertyValue $existingSilo.DistinguishedName
                        }
                        $actions += $action
                        $toUpdate++

                        Write-TierModelLog -Level Info -Message "AuthSiloFdPlanUpdate" -Data @{
                            SiloName      = $silo.name
                            DriftReasons  = $driftReasons
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        $alreadyExist++
                        Write-TierModelLog -Level Info -Message "AuthSiloFdPlanConverged" -Data @{
                            SiloName      = $silo.name
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    }
                }
            } catch {
                $errors += @{
                    Timestamp = Get-Date
                    Category  = 'Execution'
                    Code      = 'AuthSiloFdPlanItemFailed'
                    Message   = "Failed to plan silo '$($silo.name)': $($_.Exception.Message)"
                    Context   = @{ SiloName = $silo.name; CorrelationId = $CorrelationId }
                }
                Write-TierModelLog -Level Error -Message "AuthSiloFdPlanItemFailed" -Data @{
                    SiloName      = $silo.name
                    Exception     = $_.Exception.Message
                    CorrelationId = $CorrelationId
                } | Out-Null
            }
        }

        $summary = @{
            TotalInConfig  = @($silos).Count
            ToCreate       = $toCreate
            ToUpdate       = $toUpdate
            AlreadyExist   = $alreadyExist
            TotalActions   = $toCreate + $toUpdate
            CreateActions  = $toCreate
            ExistingCount  = $alreadyExist
        }

        Write-TierModelLog -Level Info -Message "AuthSiloFdPlanComplete" -Data @{
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
        Write-TierModelLog -Level Error -Message "AuthSiloFdPlanFailed" -Data @{
            Exception     = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalInConfig = 0; ToCreate = 0; ToUpdate = 0; AlreadyExist = 0; TotalActions = 0; CreateActions = 0; ExistingCount = 0 }
            Warnings   = $warnings
            Errors     = @(@{
                Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthSiloFdPlanFailed'
                Message   = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
