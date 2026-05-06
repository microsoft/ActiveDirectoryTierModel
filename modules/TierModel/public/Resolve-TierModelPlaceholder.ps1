function Resolve-TierModelPlaceholder {
    <#
    .SYNOPSIS
    Generic placeholder replacement for TierModel path resolution.
    
    .DESCRIPTION
    Handles {{DOMAIN_DN}} and other common placeholder patterns used
    across different TierModel entity types (OUs, Groups, Users, etc.).
    
    .PARAMETER Path
    Original path from configuration that may contain placeholders.
    
    .PARAMETER DomainDN
    Resolved domain distinguished name for replacement.
    
    .EXAMPLE
    $resolved = Resolve-TierModelPlaceholder -Path "CN=Users,{{DOMAIN_DN}}" -DomainDN "DC=contoso,DC=com"
    # Returns: "CN=Users,DC=contoso,DC=com"
    
    .OUTPUTS
    String containing the resolved path with placeholders replaced.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$DomainDN
    )
    
    $resolvedPath = if ([string]::IsNullOrEmpty($Path)) {
        # Empty path: use domain root
        $DomainDN
    } elseif ($Path -eq '{{DOMAIN_DN}}') {
        # Replace {{DOMAIN_DN}} placeholder with actual domain DN
        $DomainDN
    } else {
        # Replace any {{DOMAIN_DN}} placeholders and ensure domain DN is included
        $pathWithPlaceholders = $Path -replace '\{\{DOMAIN_DN\}\}', $DomainDN
        # If path doesn't already contain domain DN, append it
        if ($pathWithPlaceholders -notmatch 'DC=') {
            "$pathWithPlaceholders,$DomainDN"
        } else {
            $pathWithPlaceholders
        }
    }
    
    return $resolvedPath
}