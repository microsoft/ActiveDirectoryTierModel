function Test-TierModelOuExists {
    <#
    .SYNOPSIS
    Test if a specific OU exists in Active Directory.
    
    .DESCRIPTION
    Low-level helper function that checks for OU existence with structured
    error handling. Used by both Get-TierModelOu (planning) and Test-TierModelOu (auditing).
    
    This is different from Test-TierModelOu which performs comprehensive drift detection.
    This function only answers: "Does this specific OU exist? Yes/No + details."
    
    .PARAMETER DistinguishedName
    Full OU distinguished name to check.
    
    .PARAMETER DomainController
    Domain controller to query.
    
    .EXAMPLE
    $result = Test-TierModelOuExists -DistinguishedName "OU=Tier0,DC=contoso,DC=com" -DomainController "dc01.contoso.com"
    if ($result.Exists) { Write-Host "OU found: $($result.OU.Name)" }
    
    .OUTPUTS
    Hashtable with Exists (bool), OU (object if found), Error (string if failed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DistinguishedName,
        
        [Parameter(Mandatory)]
        [string]$DomainController
    )
    
    try {
        $ou = Get-ADOrganizationalUnit -Identity $DistinguishedName -Server $DomainController -ErrorAction Stop
        return @{
            Exists = $true
            OU = $ou
            Error = $null
        }
    } catch {
        return @{
            Exists = $false
            OU = $null
            Error = $_.Exception.Message
        }
    }
}