<#
.SYNOPSIS
    Stub functions for Active Directory and Group Policy cmdlets.

.DESCRIPTION
    Provides function stubs so Pester can mock AD/GPO cmdlets
    in CI environments where RSAT is not installed.
    Stubs are only defined when the real cmdlets are not available.
    Parameters match the real cmdlets to support Pester ParameterFilter mocking.
#>

if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) {

    # ActiveDirectory module stubs
    function Get-ADDomain { param($Server, $Identity) }
    function Get-ADForest { param($Server, $Identity) }
    function Get-ADGroup { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADGroupMember { param($Identity, $Server, $Recursive) }
    function Get-ADUser { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADOrganizationalUnit { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADObject { param($Identity, $Server, $Filter, $SearchBase, $Properties, $LDAPFilter, $ErrorAction) }
    function Get-ADRootDSE { param($Server) }
    function New-ADGroup { param($Name, $GroupScope, $GroupCategory, $Path, $Server, $Description, $DisplayName, $SamAccountName, $ErrorAction) }
    function New-ADOrganizationalUnit { param($Name, $Path, $Server, $Description, $ProtectedFromAccidentalDeletion, $ErrorAction) }
    function New-ADUser { param($Name, $SamAccountName, $UserPrincipalName, $Path, $Server, $AccountPassword, $Enabled, $DisplayName, $Description, $GivenName, $Surname, $ErrorAction) }
    function Add-ADGroupMember { param($Identity, $Members, $Server, $ErrorAction) }
    function Set-ADObject { param($Identity, $Server, $Replace, $Add, $Remove, $Clear, $ErrorAction) }
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
}

if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {

    # Security cmdlet stubs
    function Get-Acl { param($Path, $ErrorAction) }
    function Set-Acl { param($Path, $AclObject, $ErrorAction) }
}
