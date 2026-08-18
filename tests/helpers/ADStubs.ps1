<#
.SYNOPSIS
    Stub functions for Active Directory and Group Policy cmdlets.

.DESCRIPTION
    Provides function stubs so Pester can mock AD/GPO cmdlets
    in CI environments where RSAT is not installed.
    Stubs are only defined when the real cmdlets are not available.
    Parameters match the real cmdlets to support Pester ParameterFilter mocking.
#>

# Stub AD exception types used in test mocks
if (-not ('Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException' -as [type])) {
    Add-Type -TypeDefinition @'
namespace Microsoft.ActiveDirectory.Management {
    public class ADIdentityNotFoundException : System.Exception {
        public ADIdentityNotFoundException() : base() { }
        public ADIdentityNotFoundException(string message) : base(message) { }
        public ADIdentityNotFoundException(string message, System.Exception inner) : base(message, inner) { }
    }
}
'@
}

if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) {

    # ActiveDirectory module stubs
    function Get-ADDomain { param($Server, $Identity) }
    function Get-ADForest { param($Server, $Identity) }
    function Get-ADGroup { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADGroupMember { param($Identity, $Server, $Recursive) }
    function Get-ADUser { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADOrganizationalUnit { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADObject { param($Identity, $Server, $Filter, $SearchBase, $Properties, $LDAPFilter, $ErrorAction) }
    function Get-ADComputer { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADRootDSE { param($Server) }
    function New-ADGroup { param($Name, $GroupScope, $GroupCategory, $Path, $Server, $Description, $DisplayName, $SamAccountName, $ErrorAction) }
    function New-ADOrganizationalUnit { param($Name, $Path, $Server, $Description, $ProtectedFromAccidentalDeletion, $PassThru, $Confirm, $ErrorAction) }
    function Set-ADOrganizationalUnit { param($Identity, $Server, $ProtectedFromAccidentalDeletion, $Confirm, $ErrorAction) }
    function New-ADUser { param($Name, $SamAccountName, $UserPrincipalName, $Path, $Server, $AccountPassword, $Enabled, $DisplayName, $Description, $GivenName, $Surname, $ErrorAction) }
    function Add-ADGroupMember { param($Identity, $Members, $Server, $ErrorAction) }
    function Set-ADObject { param($Identity, $Server, $Replace, $Add, $Remove, $Clear, $ErrorAction) }

    # Register as in-memory module so Get-Module ActiveDirectory returns a result
    New-Module -Name ActiveDirectory -ScriptBlock {
        function Get-ADDomain { param($Server, $Identity) }
        function Get-ADForest { param($Server, $Identity) }
        function Get-ADGroup { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADGroupMember { param($Identity, $Server, $Recursive) }
        function Get-ADUser { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADOrganizationalUnit { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADObject { param($Identity, $Server, $Filter, $SearchBase, $Properties, $LDAPFilter, $ErrorAction) }
        function Get-ADComputer { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADRootDSE { param($Server) }
        function New-ADGroup { param($Name, $GroupScope, $GroupCategory, $Path, $Server, $Description, $DisplayName, $SamAccountName, $ErrorAction) }
        function New-ADOrganizationalUnit { param($Name, $Path, $Server, $Description, $ProtectedFromAccidentalDeletion, $PassThru, $Confirm, $ErrorAction) }
        function Set-ADOrganizationalUnit { param($Identity, $Server, $ProtectedFromAccidentalDeletion, $Confirm, $ErrorAction) }
        function New-ADUser { param($Name, $SamAccountName, $UserPrincipalName, $Path, $Server, $AccountPassword, $Enabled, $DisplayName, $Description, $GivenName, $Surname, $ErrorAction) }
        function Add-ADGroupMember { param($Identity, $Members, $Server, $ErrorAction) }
        function Set-ADObject { param($Identity, $Server, $Replace, $Add, $Remove, $Clear, $ErrorAction) }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}

if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {

    # GroupPolicy module stubs
    function Get-GPO { param($Name, $Guid, [switch]$All, $Server, $Domain, $ErrorAction) }
    function Get-GPInheritance { param($Target, $Server, $Domain) }
    function New-GPLink { param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction) }
    function Set-GPLink { param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction) }
    function Set-GPInheritance { param($Target, $IsBlocked, $Server, $Domain) }
    function Import-GPO { param($BackupGpoName, $Path, $TargetName, $TargetGuid, $Server, $Domain, $CreateIfNeeded, $ErrorAction) }
    function New-GPO { param($Name, $Server, $Domain, $Comment, $ErrorAction) }
    function Get-GPRegistryValue { param($Name, $Guid, $Key, $ValueName, $Server, $Domain, $ErrorAction) }
    function Set-GPRegistryValue { param($Name, $Guid, $Key, $ValueName, $Value, $Type, $Server, $Domain, $ErrorAction) }

    # Register as in-memory module so Get-Module GroupPolicy returns a result
    New-Module -Name GroupPolicy -ScriptBlock {
        function Get-GPO { param($Name, $Guid, [switch]$All, $Server, $Domain, $ErrorAction) }
        function Get-GPInheritance { param($Target, $Server, $Domain) }
        function New-GPLink { param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction) }
        function Set-GPLink { param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction) }
        function Set-GPInheritance { param($Target, $IsBlocked, $Server, $Domain) }
        function Import-GPO { param($BackupGpoName, $Path, $TargetName, $TargetGuid, $Server, $Domain, $CreateIfNeeded, $ErrorAction) }
        function New-GPO { param($Name, $Server, $Domain, $Comment, $ErrorAction) }
        function Get-GPRegistryValue { param($Name, $Guid, $Key, $ValueName, $Server, $Domain, $ErrorAction) }
        function Set-GPRegistryValue { param($Name, $Guid, $Key, $ValueName, $Value, $Type, $Server, $Domain, $ErrorAction) }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}

if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {

    # Security cmdlet stubs
    function Get-Acl { param($Path, $ErrorAction) }
    function Set-Acl { param($Path, $AclObject, $ErrorAction) }
}

if (-not (Get-Command Find-LapsADExtendedRights -ErrorAction SilentlyContinue)) {

    # Windows LAPS module stubs — required for WinLaps deployment/audit cmdlets
    function Find-LapsADExtendedRights { param($Identity, $DomainController, $Credential, $ErrorAction) }
    function Set-LapsADComputerSelfPermission { param($Identity, $DomainController, $Credential, $ErrorAction) }
    function Set-LapsADReadPasswordPermission { param($Identity, $AllowedPrincipals, $DomainController, $Credential, $ErrorAction) }
    function Set-LapsADResetPasswordPermission { param($Identity, $AllowedPrincipals, $DomainController, $Credential, $ErrorAction) }

    # Register as in-memory module so Import-Module LAPS and Get-Module LAPS both succeed
    New-Module -Name LAPS -ScriptBlock {
        function Find-LapsADExtendedRights { param($Identity, $DomainController, $Credential, $ErrorAction) }
        function Set-LapsADComputerSelfPermission { param($Identity, $DomainController, $Credential, $ErrorAction) }
        function Set-LapsADReadPasswordPermission { param($Identity, $AllowedPrincipals, $DomainController, $Credential, $ErrorAction) }
        function Set-LapsADResetPasswordPermission { param($Identity, $AllowedPrincipals, $DomainController, $Credential, $ErrorAction) }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}
