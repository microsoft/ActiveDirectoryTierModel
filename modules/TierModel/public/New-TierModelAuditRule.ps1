function New-TierModelAuditRule {
    <#
    .SYNOPSIS
    Apply the domain-root SACL audit rule using UNION converge logic.

    .DESCRIPTION
    Applies the canonical audit ACE (Everyone/Success/All/9-rights) to the domain root
    distinguished name. Uses UNION converge: the final ACE contains the union of the
    9 canonical rights AND any rights already present on existing managed ACEs.
    Customer rights beyond the 9 are preserved; all 9 are guaranteed.

    Managed scope: ACEs with SID=S-1-1-0, AuditFlags=Success, InheritanceType=All,
    non-inherited. All other ACEs (Failure flag, other SIDs, Inherit=None, inherited)
    are left completely untouched.

    Converge mechanics (lab-validated):
      - Read SACL via Get-Acl -Audit on the same ACL object used for Set-Acl.
      - If already converged (1 managed ACE, all 9 rights present) — NO-OP (idempotent).
      - Otherwise: RemoveAuditRuleSpecific each managed ACE, AddAuditRule the union target,
        then Set-Acl.

    Requires SeSecurityPrivilege — fails with a clear error if the write is denied.

    .PARAMETER Plan
    Deployment plan object from Get-TierModelAuditRule or Get-TierModelAuditRuleFd.

    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.

    .PARAMETER Config
    The TierModel configuration object (passed for consistency with other New-TierModel* cmdlets).

    .OUTPUTS
    PSCustomObject with Applied, Executed, Failed, Skipped, Errors, DurationMs, Converged.

    .EXAMPLE
    $plan = Get-TierModelAuditRule -Config $config -DomainController 'DC01'
    New-TierModelAuditRule -Plan $plan -DomainController 'DC01' -Config $config

    .EXAMPLE
    New-TierModelAuditRule -Plan $plan -DomainController 'DC01' -Config $config -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [Parameter(Mandatory)]
        [object]$Config
    )

    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date

    $configureCount = @($Plan.Actions | Where-Object { $_.Action -eq 'ConfigureAuditRule' }).Count

    Write-TierModelLog -Level Info -Message "AuditRuleExecutionStart" -Data @{
        TotalActions     = $configureCount
        DomainController = $DomainController
        WhatIf           = $WhatIfPreference
        CorrelationId    = $CorrelationId
    } | Out-Null

    $applied  = @()
    $skipped  = @()
    $errors   = @()
    $converged = $true

    try {
        foreach ($action in $Plan.Actions) {
            if ($action.Action -ne 'ConfigureAuditRule' -or $action.ResourceType -ne 'DomainAuditRule') {
                continue
            }

            $targetDn    = $action.TargetDn
            $canonicalSid = $action.Data.TrusteeSid   # S-1-1-0

            try {
                Write-TierModelLog -Level Info -Message "Applying domain-root audit rule" -Data @{
                    TargetDn         = $targetDn
                    UnionTargetRights = $action.Data.UnionTargetRights
                    ManagedAceCount  = $action.Data.ManagedAceCount
                    DomainController = $DomainController
                    CorrelationId    = $CorrelationId
                } | Out-Null

                if ($PSCmdlet.ShouldProcess("Domain root: $targetDn", "Set-Acl SACL (UNION converge: $($action.Data.UnionTargetRights))")) {

                    # Ensure AD provider is available
                    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

                    # Read the SACL — bind read + write to the SAME object for RemoveAuditRuleSpecific to work
                    $acl = Get-Acl -Path "AD:$targetDn" -Audit -ErrorAction Stop

                    # Re-enumerate managed ACEs from this acl object (same object required for Remove to work)
                    $managedAces = [System.Collections.Generic.List[object]]::new()
                    foreach ($rule in $acl.GetAuditRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
                        if ($rule.IdentityReference.Value -eq $canonicalSid -and
                            $rule.AuditFlags -eq [System.Security.AccessControl.AuditFlags]::Success -and
                            $rule.InheritanceType -eq [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All -and
                            -not $rule.IsInherited) {
                            $managedAces.Add($rule)
                        }
                    }

                    # Re-compute union target from the freshly-read ACL
                    $presentInt = 0
                    foreach ($ace in $managedAces) {
                        $presentInt = $presentInt -bor [int]$ace.ActiveDirectoryRights
                    }

                    # Rebuild canonical target from config rights
                    $targetRightsInt = 0
                    foreach ($right in $Config.domainAuditRule.rights) {
                        $targetRightsInt = $targetRightsInt -bor [int][System.DirectoryServices.ActiveDirectoryRights]$right
                    }

                    # Re-check idempotency with fresh read
                    $alreadyDone = ($managedAces.Count -eq 1) -and
                                  (($targetRightsInt -band (-bnot $presentInt)) -eq 0) -and
                                  (($targetRightsInt -bor $presentInt) -eq $presentInt)

                    if ($alreadyDone) {
                        Write-Host "  ✅ Domain-root audit rule already converged — no write needed" -ForegroundColor Green
                        $skipped += [PSCustomObject]@{
                            Action   = 'ConfigureAuditRule'
                            TargetDn = $targetDn
                            Reason   = 'AlreadyConverged'
                        }
                        continue
                    }

                    $unionTargetInt = $targetRightsInt -bor $presentInt
                    $unionTargetRights = [System.DirectoryServices.ActiveDirectoryRights]$unionTargetInt

                    # Build the canonical audit rule to add
                    $everybodySid = [System.Security.Principal.SecurityIdentifier]::new($canonicalSid)
                    $newRule = [System.DirectoryServices.ActiveDirectoryAuditRule]::new(
                        $everybodySid,
                        $unionTargetRights,
                        [System.Security.AccessControl.AuditFlags]::Success,
                        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                    )

                    # Remove all existing managed ACEs first (must be from the SAME acl object)
                    foreach ($ace in $managedAces) {
                        $acl.RemoveAuditRuleSpecific($ace)
                    }

                    # Add the single canonical union ACE
                    $acl.AddAuditRule($newRule)

                    # Write back — SeSecurityPrivilege required
                    try {
                        Set-Acl -Path "AD:$targetDn" -AclObject $acl -ErrorAction Stop
                    } catch {
                        if ($_.Exception.Message -match 'Privilege') {
                            throw "Cannot write the domain-root SACL. SeSecurityPrivilege is required. Run as an account with Domain Admin rights. Detail: $($_.Exception.Message)"
                        }
                        throw
                    }

                    Write-Host "  ✅ Domain-root audit rule applied (UNION: $($unionTargetRights))" -ForegroundColor Green

                    Write-TierModelLog -Level Info -Message "Domain-root audit rule applied successfully" -Data @{
                        TargetDn         = $targetDn
                        UnionTargetRights = $unionTargetRights.ToString()
                        RemovedAceCount  = $managedAces.Count
                        DomainController = $DomainController
                        CorrelationId    = $CorrelationId
                    } | Out-Null

                    $applied += [PSCustomObject]@{
                        Action            = 'ConfigureAuditRule'
                        TargetDn          = $targetDn
                        UnionTargetRights = $unionTargetRights.ToString()
                        RemovedAceCount   = $managedAces.Count
                    }

                } else {
                    Write-Host "  [WhatIf] Would apply domain-root audit rule (UNION: $($action.Data.UnionTargetRights)) on $targetDn" -ForegroundColor DarkYellow
                    $skipped += [PSCustomObject]@{
                        Action   = 'ConfigureAuditRule'
                        TargetDn = $targetDn
                        Reason   = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }
                    }
                }

            } catch {
                Write-TierModelLog -Level Error -Message "Failed to apply domain-root audit rule" -Data @{
                    TargetDn         = $targetDn
                    DomainController = $DomainController
                    Exception        = $_.Exception.Message
                    CorrelationId    = $CorrelationId
                } | Out-Null

                Write-Host "  ERROR: Failed to apply audit rule on '$targetDn' - $($_.Exception.Message)" -ForegroundColor Red
                $errors += @{
                    Timestamp = Get-Date
                    Category  = 'Execution'
                    Code      = 'AuditRuleApplyFailed'
                    Message   = $_.Exception.Message
                    Context   = @{ Action = $action.Action; TargetDn = $targetDn }
                }
                $converged = $false
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        Write-TierModelLog -Level Info -Message "AuditRuleExecutionComplete" -Data @{
            AppliedActions = $applied.Count
            FailedActions  = $errors.Count
            SkippedActions = $skipped.Count
            DurationMs     = $durationMs
            CorrelationId  = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied       = $applied
            Executed      = $applied.Count
            Failed        = $errors.Count
            Skipped       = $skipped
            Errors        = $errors
            DurationMs    = $durationMs
            Converged     = $converged
            CorrelationId = $CorrelationId
        }

    } catch {
        Write-TierModelLog -Level Error -Message "Audit rule execution failed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied = @(); Executed = 0; Failed = 1; Skipped = @()
            Errors = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'AuditRuleExecutionFailed'; Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; Converged = $false; CorrelationId = $CorrelationId
        }
    }
}
