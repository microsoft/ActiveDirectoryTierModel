function Resolve-DomainSpecificGuid {
    <#
    .SYNOPSIS
    Resolves domain-specific attribute or class GUIDs by querying the Active Directory schema.
    
    .DESCRIPTION
    Some attributes like BitLocker recovery passwords and LAPS passwords have GUIDs that are 
    unique to each domain/forest. This function queries the domain's schema to resolve 
    these attribute or class names to their actual GUIDs at runtime.
    
    .PARAMETER AttributeName
    The schema attribute or class name to resolve (e.g., "msFVE-RecoveryPassword", "ms-Mcs-AdmPwd",
    "msDS-DelegatedManagedServiceAccount").
    
    .PARAMETER ConfigPath
    The configuration path, used to determine domain controller if needed.
    
    .PARAMETER DomainController
    Optional domain controller to use for the schema query. If not provided, will use 
    the default domain controller.
    
    .PARAMETER SchemaObjectClass
    The schema object class to search within. Default is 'attributeSchema'.
    Use 'classSchema' when resolving object class GUIDs (e.g., for dMSA).
    
    .EXAMPLE
    $guid = Resolve-DomainSpecificGuid -AttributeName "msFVE-RecoveryPassword"
    # Returns the domain-specific GUID for the BitLocker recovery password attribute
    
    .EXAMPLE
    $guid = Resolve-DomainSpecificGuid -AttributeName "lockoutTime" -DomainController "DC01.contoso.com"
    # Returns the domain-specific GUID for the lockout time attribute
    
    .EXAMPLE
    $guid = Resolve-DomainSpecificGuid -AttributeName "msDS-DelegatedManagedServiceAccount" -SchemaObjectClass "classSchema" -DomainController "DC01.contoso.com"
    # Returns the schema GUID for the dMSA object class
    
    .OUTPUTS
    String representing the resolved GUID
    
    .NOTES
    This function requires appropriate permissions to query the Active Directory schema.
    It uses the SchemaIDGUID property of schema attributes/classes to get the correct GUID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$AttributeName,
        
        [Parameter()]
        [string]$ConfigPath,
        
        [Parameter()]
        [string]$DomainController,
        
        [Parameter()]
        [ValidateSet('attributeSchema', 'classSchema')]
        [string]$SchemaObjectClass = 'attributeSchema'
    )
    
    try {
        # Get the domain context for schema queries
        if (-not $DomainController) {
            # Try to get a domain controller from the current domain
            $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
            $DomainController = $domain.PdcRoleOwner.Name
        }
        
        # Connect to the schema naming context
        $schemaDN = "CN=Schema,CN=Configuration," + (Get-ADDomain -Server $DomainController).DistinguishedName -replace '^DC=', '' -replace ',DC=', ',DC='
        $schemaDN = (Get-ADRootDSE -Server $DomainController).schemaNamingContext
        
        # Query for the specific attribute
        Write-TierModelLog -Level Debug -Message "Resolving domain-specific GUID" -Data @{
            AttributeName = $AttributeName
            DomainController = $DomainController
            SchemaDN = $schemaDN
        } | Out-Null
        
        # Search for the attribute/class in the schema
        $searchFilter = "(&(objectClass=$SchemaObjectClass)(ldapDisplayName=$AttributeName))"
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainController/$schemaDN")
        $searcher.Filter = $searchFilter
        $searcher.PropertiesToLoad.Add("schemaIDGUID") | Out-Null
        
        $result = $searcher.FindOne()
        
        if (-not $result) {
            throw "Attribute '$AttributeName' not found in domain schema"
        }
        
        # Get the schema GUID and convert it to string format
        $guidBytes = $result.Properties["schemaIDGUID"][0]
        $guid = [System.Guid]::new($guidBytes)
        $guidString = $guid.ToString()
        
        Write-TierModelLog -Level Debug -Message "Resolved domain-specific GUID" -Data @{
            AttributeName = $AttributeName
            ResolvedGuid = $guidString
            DomainController = $DomainController
        } | Out-Null
        
        return $guidString
        
    } catch {
        # If AD cmdlets are not available, try alternative approach using .NET DirectoryServices
        try {
            Write-TierModelLog -Level Warning -Message "AD cmdlets not available, using DirectoryServices fallback" -Data @{
                AttributeName = $AttributeName
                Error = $_.Exception.Message
            } | Out-Null
            
            # Alternative approach using pure .NET DirectoryServices
            $rootDSE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE")
            $schemaDN = $rootDSE.Properties["schemaNamingContext"][0]
            
            $searcher = New-Object System.DirectoryServices.DirectorySearcher
            $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$schemaDN")
            $searcher.Filter = "(&(objectClass=$SchemaObjectClass)(ldapDisplayName=$AttributeName))"
            $searcher.PropertiesToLoad.Add("schemaIDGUID") | Out-Null
            
            $result = $searcher.FindOne()
            
            if (-not $result) {
                throw "Attribute '$AttributeName' not found in domain schema (DirectoryServices fallback)"
            }
            
            $guidBytes = $result.Properties["schemaIDGUID"][0]
            $guid = [System.Guid]::new($guidBytes)
            return $guid.ToString()
            
        } catch {
            $errorMessage = "Failed to resolve domain-specific GUID for attribute '$AttributeName': $($_.Exception.Message)"
            Write-TierModelLog -Level Error -Message $errorMessage -Data @{
                AttributeName = $AttributeName
                DomainController = $DomainController
            }
            throw $errorMessage
        }
    }
}