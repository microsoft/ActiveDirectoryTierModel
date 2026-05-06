function Resolve-TierModelDomainDN {
    <#
    .SYNOPSIS
    Resolve and cache domain distinguished name for TierModel operations.
    
    .DESCRIPTION
    Centralized domain DN resolution with caching to minimize AD queries
    across all TierModel cmdlets (OU, Groups, Users, GPOs, etc.).
    
    .PARAMETER DomainController
    Preferred domain controller for AD operations.
    
    .EXAMPLE
    $domainDN = Resolve-TierModelDomainDN -DomainController "dc01.contoso.com"
    # Returns: "DC=contoso,DC=com"
    
    .OUTPUTS
    String containing the domain distinguished name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DomainController
    )
    
    # Check cache first
    if (-not $script:CachedDomainDN -or $script:CachedDomainController -ne $DomainController) {
        try {
            $domain = Get-ADDomain -Server $DomainController
            $script:CachedDomainDN = $domain.DistinguishedName
            $script:CachedDomainController = $DomainController
            Write-TierModelLog -Level Debug -Message "Domain DN resolved and cached" -Data @{
                DomainController = $DomainController
                DomainDN = $script:CachedDomainDN
            } | Out-Null
        } catch {
            Write-TierModelLog -Level Error -Message "Failed to resolve domain DN" -Data @{
                DomainController = $DomainController
                Error = $_.Exception.Message
            }
            throw "Failed to resolve domain DN: $($_.Exception.Message)"
        }
    }
    
    return $script:CachedDomainDN
}