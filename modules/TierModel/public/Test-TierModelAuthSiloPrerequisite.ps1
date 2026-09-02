function Test-TierModelAuthSiloPrerequisite {
    <#
    .SYNOPSIS
    Validate that all groups referenced by the Authentication Policy Silo configuration exist.

    .DESCRIPTION
    Performs a pre-deployment dependency gate for -IncludeAuthSilos. Checks that every
    security group referenced in the auth silos configuration exists in Active Directory:
      - authenticationPolicies[*].allowedToAuthenticateFromDeviceGroups
      - authenticationSilos[*].memberComputerGroups

    If all referenced groups exist, their containing OUs also exist (an AD group cannot
    exist without its parent OU), so no separate OU check is needed.

    This gate does NOT check:
      - Individual user accounts (group membership is populated separately)
      - GPO existence (GPOs are an enforcement-time concern, not a deploy dependency)
      - Whether silos or policies already exist (handled by New-TierModelAuthPolicy /
        New-TierModelAuthSilo which are idempotent)

    Call this before New-TierModelAuthPolicy to fail fast with a clear message rather
    than surfacing an ambiguous error deep in the deployment.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.

    .PARAMETER DomainController
    Preferred domain controller for all AD queries.

    .OUTPUTS
    PSCustomObject with:
      - Passed     [bool]     — true only when every referenced group exists
      - Failures   [string[]] — list of missing-group descriptions
      - Checked    [int]      — number of unique group names checked
      - DurationMs [double]

    .EXAMPLE
    $config = Get-TierModelConfig
    $result = Test-TierModelAuthSiloPrerequisite -Config $config -DomainController 'DC01'
    if (-not $result.Passed) {
        $result.Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController
    )

    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuthSiloPrerequisiteStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    $failures  = @()
    $checkedGroups = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # ── Collect all unique group names across all three reference locations ────────────
    $allGroupNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $policies = Get-TierModelAuthPolicy -Config $Config
    foreach ($policy in $policies) {
        foreach ($groupName in @($policy.allowedToAuthenticateFromDeviceGroups)) {
            $allGroupNames.Add($groupName) | Out-Null
        }
    }

    $silos = Get-TierModelAuthSilo -Config $Config
    foreach ($silo in $silos) {
        foreach ($groupName in @($silo.memberComputerGroups)) {
            $allGroupNames.Add($groupName) | Out-Null
        }
    }

    if ($allGroupNames.Count -eq 0) {
        Write-TierModelLog -Level Warning -Message "No groups to check — auth silos config may not be loaded" -Data @{ CorrelationId = $CorrelationId } | Out-Null
        return [PSCustomObject]@{
            Passed    = $false
            Failures  = @("No group references found. Ensure tiermodel-authsilos.json is present and loaded.")
            Checked   = 0
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
        }
    }

    # ── Check each group ───────────────────────────────────────────────────────────────
    foreach ($groupName in $allGroupNames) {
        $checkedGroups.Add($groupName) | Out-Null
        try {
            Get-ADGroup -Identity $groupName -Server $DomainController -ErrorAction Stop | Out-Null
            Write-TierModelLog -Level Debug -Message "AuthSiloPrerequisiteGroupOk" -Data @{
                GroupName = $groupName; CorrelationId = $CorrelationId
            } | Out-Null
        } catch {
            $failures += "Group '$groupName' not found in Active Directory (required by auth silo config)"
            Write-TierModelLog -Level Warning -Message "AuthSiloPrerequisiteGroupMissing" -Data @{
                GroupName     = $groupName
                Exception     = $_.Exception.Message
                CorrelationId = $CorrelationId
            } | Out-Null
        }
    }

    $passed    = $failures.Count -eq 0
    $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

    Write-TierModelLog -Level Info -Message "AuthSiloPrerequisiteComplete" -Data @{
        Passed        = $passed
        FailureCount  = $failures.Count
        Checked       = $checkedGroups.Count
        DurationMs    = $durationMs
        CorrelationId = $CorrelationId
    } | Out-Null

    return [PSCustomObject]@{
        Passed     = $passed
        Failures   = $failures
        Checked    = $checkedGroups.Count
        DurationMs = $durationMs
    }
}
