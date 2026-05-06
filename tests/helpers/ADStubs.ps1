<#
.SYNOPSIS
    Stub functions for Active Directory and Group Policy cmdlets.

.DESCRIPTION
    Provides empty function stubs so Pester can mock AD/GPO cmdlets
    in CI environments where RSAT is not installed.
    Stubs are only defined when the real cmdlets are not available.
#>

if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) {

    # ActiveDirectory module stubs
    function Get-ADDomain { }
    function Get-ADForest { }
    function Get-ADGroup { }
    function Get-ADGroupMember { }
    function Get-ADUser { }
    function Get-ADOrganizationalUnit { }
    function Get-ADObject { }
    function Get-ADRootDSE { }
    function New-ADGroup { }
    function New-ADOrganizationalUnit { }
    function Set-ADObject { }
}

if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {

    # GroupPolicy module stubs
    function Get-GPO { }
    function Get-GPInheritance { }
    function New-GPLink { }
    function Set-GPLink { }
    function Set-GPInheritance { }
    function Import-GPO { }
    function New-GPO { }
}

if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {

    # Security cmdlet stubs
    function Get-Acl { }
    function Set-Acl { }
}
