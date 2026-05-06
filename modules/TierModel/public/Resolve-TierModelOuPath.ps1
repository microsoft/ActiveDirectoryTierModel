function Resolve-TierModelOuPath {
    <#
    .SYNOPSIS
    Normalize OU path with placeholder replacement.
    
    .DESCRIPTION
    OU-specific path normalization that handles OU creation paths.
    Uses the shared Resolve-TierModelPlaceholder function for common logic.
    
    .PARAMETER OuPath
    Original OU path from configuration.
    
    .PARAMETER DomainDN
    Resolved domain distinguished name.
    
    .EXAMPLE
    $resolved = Resolve-TierModelOuPath -OuPath "OU=Tier0,{{DOMAIN_DN}}" -DomainDN "DC=contoso,DC=com"
    # Returns: "OU=Tier0,DC=contoso,DC=com"
    
    .OUTPUTS
    String containing the resolved OU path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$OuPath,
        
        [Parameter(Mandatory)]
        [string]$DomainDN
    )
    
    # Use shared placeholder resolution logic
    return Resolve-TierModelPlaceholder -Path $OuPath -DomainDN $DomainDN
}