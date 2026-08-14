function Get-TierModelAuditRuleFd {
    <#
    .SYNOPSIS
    Analyze domain-root SACL audit rule requirements for full deployment mode.

    .DESCRIPTION
    Examines the configured canonical audit ACE against the current SACL on the domain
    root DN. Designed for the FullDeployment pipeline — assumes prerequisites (AD module,
    DC connectivity) were already validated. Produces the same action shape as
    Get-TierModelAuditRule for consumption by New-TierModelAuditRule.

    Managed scope: ACEs with SID=S-1-1-0, AuditFlags=Success, InheritanceType=All,
    non-inherited. All other ACEs are untouched.

    .PARAMETER Config
    TierModel configuration object. Must contain a domainAuditRule segment.

    .PARAMETER DomainController
    The domain controller to use for all AD operations.

    .PARAMETER IncludeDetails
    Include additional diagnostic fields in the output for troubleshooting.

    .PARAMETER Silent
    Suppress host output for consolidated reporting.

    .OUTPUTS
    PSCustomObject with Actions, Summary, Errors, DurationMs, Converged.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelAuditRuleFd -Config $config -DomainController 'DC01' -Silent

    .EXAMPLE
    $plan = Get-TierModelAuditRuleFd -Config $config -DomainController 'DC01' -IncludeDetails
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

    Write-TierModelLog -Level Info -Message "AuditRuleFdPlanningStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    # Delegate to the standard planner; Fd variant exists for FullDeployment pipeline parity
    # (matches the WinLAPS *Fd pattern: lighter outer context, same internal logic).
    # -Silent is accepted for API symmetry but suppression is handled by the calling pipeline.
    if ($Silent) {
        Write-TierModelLog -Level Debug -Message "AuditRuleFd running in silent mode" -Data @{ CorrelationId = $CorrelationId } | Out-Null
    }
    try {
        $innerPlan = Get-TierModelAuditRule -Config $Config -DomainController $DomainController -IncludeDetails:$IncludeDetails

        # Re-stamp with FullDeployment correlation context
        $innerPlan | Add-Member -NotePropertyName 'CorrelationId' -NotePropertyValue $CorrelationId -Force

        Write-TierModelLog -Level Info -Message "AuditRuleFdPlanningComplete" -Data @{
            ConfigureActions = $innerPlan.Summary.ConfigureActions
            ExistingCount    = $innerPlan.Summary.ExistingCount
            CorrelationId    = $CorrelationId
        } | Out-Null

        return $innerPlan

    } catch {
        Write-TierModelLog -Level Error -Message "AuditRuleFd planning failed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalActions = 0; ConfigureActions = 0; ExistingCount = 0 }
            Errors     = @(@{
                Timestamp = Get-Date; Category = 'Critical'; Code = 'AuditRuleFdPlanningFailed'
                Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            Converged     = $false
            CorrelationId = $CorrelationId
        }
    }
}
