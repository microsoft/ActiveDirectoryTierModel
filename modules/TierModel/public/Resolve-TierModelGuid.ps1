function Resolve-TierModelGuid {
    <#
    .SYNOPSIS
    Resolves a friendly name or GUID to its actual GUID value for Active Directory operations.
    
    .DESCRIPTION
    Takes a friendly name (like "Computer", "User", "PasswordReset") or existing GUID and resolves 
    it to the actual GUID value needed for AD ACL operations. Supports both static mappings 
    (universal GUIDs) and dynamic mappings (domain-specific GUIDs that require runtime resolution).
    
    .PARAMETER Value
    The friendly name or GUID to resolve. Can be a human-readable name like "Computer" or 
    an existing GUID string for backward compatibility.
    
    .PARAMETER Mappings
    The GUID mappings object loaded from tiermodel-guid-mappings.json containing static 
    and dynamic mappings.
    
    .PARAMETER DomainController
    The domain controller to use for resolving domain-specific GUIDs.
    
    .PARAMETER ConfigPath
    The configuration path for accessing the domain controller for dynamic GUID resolution.
    Used when resolving domain-specific GUIDs.
    
    .EXAMPLE
    $guid = Resolve-TierModelGuid -Value "Computer" -Mappings $guidMappings
    # Returns: bf967a86-0de6-11d0-a285-00aa003049e2
    
    .EXAMPLE
    $guid = Resolve-TierModelGuid -Value "BitLockerRecoveryPassword" -Mappings $guidMappings -DomainController "DC01.contoso.com"
    # Returns: resolved GUID from domain schema (domain-specific)
    
    .EXAMPLE
    $guid = Resolve-TierModelGuid -Value "bf967a86-0de6-11d0-a285-00aa003049e2" -Mappings $guidMappings
    # Returns: bf967a86-0de6-11d0-a285-00aa003049e2 (backward compatibility)
    
    .OUTPUTS
    String representing the resolved GUID
    
    .NOTES
    This function supports backward compatibility with existing GUID values and provides
    forward compatibility with friendly names from the mapping file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        
        [Parameter(Mandatory)]
        [object]$Mappings,
        
        [Parameter()]
        [string]$DomainController,
        
        [Parameter()]
        [string]$ConfigPath
    )
    
    # If the value is already a valid GUID, return it as-is (backward compatibility)
    if ($Value -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        return $Value
    }
    
    # Handle special case for empty string (all object types)
    if ([string]::IsNullOrEmpty($Value) -or $Value -eq "AllObjectClasses") {
        return ""
    }
    
    # First, check if it's a friendly name alias
    if ($Mappings.PSObject.Properties['friendlyNameMappings'] -and 
        $Mappings.friendlyNameMappings.PSObject.Properties[$Value]) {
        $Value = $Mappings.friendlyNameMappings.$Value
    }
    
    # Check static mappings (universal GUIDs)
    if ($Mappings.PSObject.Properties['staticMappings']) {
        foreach ($category in $Mappings.staticMappings.PSObject.Properties) {
            if ($category.Value.PSObject.Properties[$Value]) {
                return $category.Value.$Value
            }
        }
    }
    
    # Check dynamic mappings (domain-specific GUIDs)
    if ($Mappings.PSObject.Properties['dynamicMappings']) {
        foreach ($category in $Mappings.dynamicMappings.PSObject.Properties) {
            if ($category.Value.PSObject.Properties[$Value]) {
                $placeholder = $category.Value.$Value
                if ($placeholder -match '\{\{resolve_guid:(.+)\}\}') {
                    $attributeName = $matches[1]
                    return Resolve-DomainSpecificGuid -AttributeName $attributeName -DomainController $DomainController
                }
            }
        }
    }
    
    # If we get here, the value wasn't found in any mappings
    throw "Unknown GUID mapping: '$Value'. Check tiermodel-guid-mappings.json for valid values."
}