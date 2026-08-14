function Get-TierModelAuditRule {
    <#
    .SYNOPSIS
    Analyze domain-root SACL audit rule requirements and generate a deployment plan.

    .DESCRIPTION
    Examines the configured canonical audit ACE (Everyone/Success/All/9-rights) against
    the current SACL on the domain root distinguished name. Reports existing vs. missing
    rights and produces an action plan for New-TierModelAuditRule.

    Managed scope: ACEs with SID=S-1-1-0, AuditFlags=Success, InheritanceType=All,
    non-inherited. All other ACEs (Failure flag, other SIDs, Inherit=None, inherited)
    are left completely untouched.

    Requires SeSecurityPrivilege to read the SACL. The caller must run as an account
    that holds this privilege (Domain Admin qualifies in standard deployments).

    .PARAMETER Config
    TierModel configuration object. Must contain a domainAuditRule segment
    (loaded from config/tiermodel-audit.json).

    .PARAMETER DomainController
    The domain controller to use for all AD operations. Both read and write are
    bound to this single DC so the SACL is not written to multiple DCs simultaneously.

    .PARAMETER IncludeDetails
    Include additional diagnostic fields in the output for troubleshooting.

    .OUTPUTS
    PSCustomObject with Actions, Summary, Errors, DurationMs, Converged.
    Summary contains TotalActions, ConfigureActions, ExistingCount.
    Each action contains Action, ResourceType, TargetDn, Data (with rights details).

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelAuditRule -Config $config -DomainController 'DC01'

    .EXAMPLE
    $plan = Get-TierModelAuditRule -Config $config -DomainController 'DC01' -IncludeDetails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [switch]$IncludeDetails
    )

    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuditRulePlanningStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    # Build an empty plan result for early-return paths
    $emptyPlan = {
        param($errors, $converged)
        [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalActions = 0; ConfigureActions = 0; ExistingCount = 0 }
            Errors     = $errors
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged  = $converged
            CorrelationId = $CorrelationId
        }
    }

    try {
        if ($IncludeDetails) {
            # IncludeDetails is reserved for future diagnostic expansion; currently all
            # relevant data is returned by default.
            Write-TierModelLog -Level Debug -Message "IncludeDetails requested — all fields are already included" -Data @{ CorrelationId = $CorrelationId } | Out-Null
        }

        # Verify the audit config segment is present
        if (-not ($Config.PSObject.Properties.Name -contains 'domainAuditRule') -or
            -not $Config.domainAuditRule) {

            Write-TierModelLog -Level Warning -Message "No domainAuditRule found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null

            return & $emptyPlan @() $true
        }

        $ruleConfig = $Config.domainAuditRule
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        $targetDn = $ruleConfig.targetDn -replace [regex]::Escape('{{DOMAIN_DN}}'), $domainDN

        # Build the canonical target rights bitmask from config
        $targetRightsInt = 0
        foreach ($right in $ruleConfig.rights) {
            $rightValue = [System.DirectoryServices.ActiveDirectoryRights]$right
            $targetRightsInt = $targetRightsInt -bor [int]$rightValue
        }
        $targetRights = [System.DirectoryServices.ActiveDirectoryRights]$targetRightsInt
        $canonicalSid = 'S-1-1-0'

        # Ensure AD provider is available for Get-Acl "AD:" path
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue

        # Read the current SACL — requires SeSecurityPrivilege
        $acl = $null
        try {
            $acl = Get-Acl -Path "AD:$targetDn" -Audit -ErrorAction Stop
        } catch {
            if ($_.Exception.Message -match 'Privilege') {
                $err = @{
                    Timestamp = Get-Date
                    Category  = 'Security'
                    Code      = 'SeSecurityPrivilegeDenied'
                    Message   = "Cannot read the domain-root SACL. SeSecurityPrivilege is required. Run as an account with Domain Admin rights. Detail: $($_.Exception.Message)"
                    Context   = @{ TargetDn = $targetDn; DomainController = $DomainController }
                }
                return & $emptyPlan @($err) $false
            }
            $err = @{
                Timestamp = Get-Date
                Category  = 'Execution'
                Code      = 'SaclReadFailed'
                Message   = "Failed to read SACL on '$targetDn': $($_.Exception.Message)"
                Context   = @{ TargetDn = $targetDn; DomainController = $DomainController }
            }
            return & $emptyPlan @($err) $false
        }

        # Enumerate ONLY managed ACEs: SID=S-1-1-0, AuditFlags=Success, InheritanceType=All, not inherited
        $managedAces = [System.Collections.Generic.List[object]]::new()
        foreach ($rule in $acl.GetAuditRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.IdentityReference.Value -eq $canonicalSid -and
                $rule.AuditFlags -eq [System.Security.AccessControl.AuditFlags]::Success -and
                $rule.InheritanceType -eq [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All -and
                -not $rule.IsInherited) {
                $managedAces.Add($rule)
            }
        }

        # Compute the UNION of all managed ACE rights
        $presentInt = 0
        foreach ($ace in $managedAces) {
            $presentInt = $presentInt -bor [int]$ace.ActiveDirectoryRights
        }

        # The union target is our canonical 9 rights OR-ed with any existing managed rights
        $unionTargetInt = $targetRightsInt -bor $presentInt
        $unionTargetRights = [System.DirectoryServices.ActiveDirectoryRights]$unionTargetInt

        # Determine which of our 9 canonical rights are still missing
        $missingInt = $targetRightsInt -band (-bnot $presentInt)
        $missingRights = if ($missingInt -ne 0) { [System.DirectoryServices.ActiveDirectoryRights]$missingInt } else { $null }

        # Already converged: exactly 1 managed ACE and it already covers the union target
        $alreadyConverged = ($managedAces.Count -eq 1) -and
                            (($targetRightsInt -band (-bnot $presentInt)) -eq 0) -and
                            ($unionTargetInt -eq $presentInt)

        $actions = @()
        $planErrors = @()

        if ($alreadyConverged) {
            # No action needed — already at the canonical union target
            $actions = @()
        } else {
            # Need to converge: remove managed ACE(s) and apply the union target
            $actions += [PSCustomObject]@{
                Action       = 'ConfigureAuditRule'
                ResourceType = 'DomainAuditRule'
                TargetDn     = $targetDn
                Data         = [PSCustomObject]@{
                    TrusteeSid        = $canonicalSid
                    AuditFlag         = $ruleConfig.auditFlag
                    Inheritance       = $ruleConfig.inheritance
                    TargetRights      = $targetRights.ToString()
                    UnionTargetRights = $unionTargetRights.ToString()
                    ExistingRightsInt = $presentInt
                    MissingRights     = if ($missingRights) { $missingRights.ToString() } else { 'None' }
                    ManagedAceCount   = $managedAces.Count
                    Status            = if ($managedAces.Count -eq 0) { 'ABSENT' } elseif ($missingInt -ne 0) { 'PARTIAL' } else { 'MULTI-ACE' }
                }
            }
        }

        $configureCount = $actions.Count
        $existingCount = if ($alreadyConverged) { 1 } else { 0 }

        Write-TierModelLog -Level Info -Message "AuditRulePlanningComplete" -Data @{
            ConfigureActions = $configureCount
            ExistingCount    = $existingCount
            AlreadyConverged = $alreadyConverged
            ManagedAceCount  = $managedAces.Count
            DomainController = $DomainController
            CorrelationId    = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = $actions
            Summary    = @{
                TotalActions   = $configureCount
                ConfigureActions = $configureCount
                ExistingCount  = $existingCount
            }
            Errors     = $planErrors
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged  = ($planErrors.Count -eq 0)
            CorrelationId = $CorrelationId
        }

    } catch {
        Write-TierModelLog -Level Error -Message "AuditRule planning failed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return & $emptyPlan @(@{
            Timestamp = Get-Date; Category = 'Critical'; Code = 'AuditRulePlanningFailed'
            Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId }
        }) $false
    }
}
