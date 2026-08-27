function Get-TierModelAuthSilo {
    <#
    .SYNOPSIS
    Load authentication silo desired-state objects from TierModel configuration.

    .DESCRIPTION
    Reads the authenticationSilos array from the TierModel configuration object
    (populated from tiermodel-authsilos.json) and returns the desired-state silo
    definitions. These are raw config objects — policy references and group memberships
    are not resolved here. Use Get-TierModelAuthSiloFd for fully-resolved objects.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.

    .OUTPUTS
    PSCustomObject[] — array of desired-state authentication silo objects from config.

    .EXAMPLE
    $config = Get-TierModelConfig
    $silos  = Get-TierModelAuthSilo -Config $config
    $silos | Select-Object name, policy

    .EXAMPLE
    # Returns an empty array when tiermodel-authsilos.json is not loaded
    $silos = Get-TierModelAuthSilo -Config $config
    if ($silos.Count -eq 0) { Write-Warning "No auth silos in config." }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }

    Write-TierModelLog -Level Info -Message "AuthSiloConfigLoad" -Data @{
        CorrelationId = $CorrelationId
    } | Out-Null

    if (-not $Config.PSObject.Properties['authenticationSilos'] -or -not $Config.authenticationSilos) {
        Write-TierModelLog -Level Warning -Message "authenticationSilos not found in config — ensure tiermodel-authsilos.json is present" -Data @{
            CorrelationId = $CorrelationId
        } | Out-Null
        return @()
    }

    $silos = @($Config.authenticationSilos)

    Write-TierModelLog -Level Info -Message "AuthSiloConfigLoaded" -Data @{
        Count         = $silos.Count
        Names         = ($silos | ForEach-Object { $_.name }) -join ', '
        CorrelationId = $CorrelationId
    } | Out-Null

    return $silos
}
