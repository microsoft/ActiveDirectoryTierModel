function Get-TierModelAuthPolicy {
    <#
    .SYNOPSIS
    Load authentication policy desired-state objects from TierModel configuration.

    .DESCRIPTION
    Reads the authenticationPolicies array from the TierModel configuration object
    (populated from tiermodel-authsilos.json) and returns the desired-state policy
    definitions. These are raw config objects — SIDs and SDDL are not resolved here.
    Use Get-TierModelAuthPolicyFd for fully-resolved objects with computed SDDL.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.

    .OUTPUTS
    PSCustomObject[] — array of desired-state authentication policy objects from config.

    .EXAMPLE
    $config  = Get-TierModelConfig
    $policies = Get-TierModelAuthPolicy -Config $config
    $policies | Select-Object name, userTGTLifetimeMinutes

    .EXAMPLE
    # Returns an empty array when tiermodel-authsilos.json is not loaded
    $policies = Get-TierModelAuthPolicy -Config $config
    if ($policies.Count -eq 0) { Write-Warning "No auth policies in config." }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }

    Write-TierModelLog -Level Info -Message "AuthPolicyConfigLoad" -Data @{
        CorrelationId = $CorrelationId
    } | Out-Null

    if (-not $Config.PSObject.Properties['authenticationPolicies'] -or -not $Config.authenticationPolicies) {
        Write-TierModelLog -Level Warning -Message "authenticationPolicies not found in config — ensure tiermodel-authsilos.json is present" -Data @{
            CorrelationId = $CorrelationId
        } | Out-Null
        return @()
    }

    $policies = @($Config.authenticationPolicies)

    Write-TierModelLog -Level Info -Message "AuthPolicyConfigLoaded" -Data @{
        Count         = $policies.Count
        Names         = ($policies | ForEach-Object { $_.name }) -join ', '
        CorrelationId = $CorrelationId
    } | Out-Null

    return $policies
}
