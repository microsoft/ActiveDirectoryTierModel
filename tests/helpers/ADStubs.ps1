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
    function Get-ADDomain { [CmdletBinding()] param($Server, $Identity) }
    function Get-ADForest { [CmdletBinding()] param($Server, $Identity) }
    function Get-ADGroup { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
    function Get-ADGroupMember { [CmdletBinding()] param($Identity, $Server, [switch]$Recursive) }
    function Get-ADUser { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
    function Get-ADOrganizationalUnit { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
    function Get-ADObject { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties, $LDAPFilter, $SearchScope) }
    function Get-ADComputer { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
    function Get-ADRootDSE { [CmdletBinding()] param($Server) }
    function New-ADGroup {
        [CmdletBinding()]
        param($Name, $GroupScope, $GroupCategory, $Path, $Server, $Description, $DisplayName, $SamAccountName, [switch]$PassThru, $Confirm)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; SamAccountName = $SamAccountName; DistinguishedName = "CN=$Name,$Path"; ObjectClass = 'group'; ObjectGUID = [guid]::NewGuid() } }
    }
    function New-ADOrganizationalUnit {
        [CmdletBinding()]
        param($Name, $Path, $Server, $Description, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "OU=$Name,$Path"; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
    }
    function Set-ADOrganizationalUnit {
        [CmdletBinding()]
        param($Identity, $Server, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm)
        if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
    }
    function New-ADUser { [CmdletBinding()] param($Name, $SamAccountName, $UserPrincipalName, $Path, $Server, $AccountPassword, $Enabled, $DisplayName, $Description, $GivenName, $Surname, $ChangePasswordAtLogon, $Confirm) }
    function Add-ADGroupMember { [CmdletBinding()] param($Identity, $Members, $Server, $Confirm) }
    function Set-ADObject {
        [CmdletBinding()]
        param($Identity, $Server, $Replace, $Add, $Remove, $Clear, [switch]$PassThru)
        if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'top'; ObjectGUID = [guid]::NewGuid() } }
    }
    # Authentication Policy cmdlets (used by auth-silo module functions)
    function Get-ADAuthenticationPolicy { [CmdletBinding()] param($Identity, $Properties, $Server) }
    function Get-ADAuthenticationPolicySilo { [CmdletBinding()] param($Identity, $Properties, $Server) }
    function New-ADAuthenticationPolicy {
        [CmdletBinding()]
        param($Name, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicy'; ObjectGUID = [guid]::NewGuid() } }
    }
    function New-ADAuthenticationPolicySilo {
        [CmdletBinding()]
        param($Name, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
    }
    function Set-ADAuthenticationPolicy { [CmdletBinding()] param($Identity, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm) }
    function Set-ADAuthenticationPolicySilo { [CmdletBinding()] param($Identity, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm) }
    function Set-ADAccountAuthenticationPolicySilo {
        [CmdletBinding()]
        param($Identity, $AuthenticationPolicySilo, $Server, [switch]$Confirm, [switch]$PassThru)
        if ($PassThru) { [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,DC=stub,DC=test"; ObjectClass = 'computer'; ObjectGUID = [guid]::NewGuid() } }
    }
    function Grant-ADAuthenticationPolicySiloAccess {
        [CmdletBinding()]
        param($Identity, $Account, $Server, [switch]$Confirm, [switch]$PassThru)
        if ($PassThru) { [PSCustomObject]@{ Name = $Identity; DistinguishedName = "CN=$Identity,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
    }

    # Register as in-memory module so Get-Module ActiveDirectory returns a result
    New-Module -Name ActiveDirectory -ScriptBlock {
        function Get-ADDomain { [CmdletBinding()] param($Server, $Identity) }
        function Get-ADForest { [CmdletBinding()] param($Server, $Identity) }
        function Get-ADGroup { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
        function Get-ADGroupMember { [CmdletBinding()] param($Identity, $Server, [switch]$Recursive) }
        function Get-ADUser { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
        function Get-ADOrganizationalUnit { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
        function Get-ADObject { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties, $LDAPFilter, $SearchScope) }
        function Get-ADComputer { [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $Properties) }
        function Get-ADRootDSE { [CmdletBinding()] param($Server) }
        function New-ADGroup {
            [CmdletBinding()]
            param($Name, $GroupScope, $GroupCategory, $Path, $Server, $Description, $DisplayName, $SamAccountName, [switch]$PassThru, $Confirm)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; SamAccountName = $SamAccountName; DistinguishedName = "CN=$Name,$Path"; ObjectClass = 'group'; ObjectGUID = [guid]::NewGuid() } }
        }
        function New-ADOrganizationalUnit {
            [CmdletBinding()]
            param($Name, $Path, $Server, $Description, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "OU=$Name,$Path"; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
        }
        function Set-ADOrganizationalUnit {
            [CmdletBinding()]
            param($Identity, $Server, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm)
            if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
        }
        function New-ADUser { [CmdletBinding()] param($Name, $SamAccountName, $UserPrincipalName, $Path, $Server, $AccountPassword, $Enabled, $DisplayName, $Description, $GivenName, $Surname, $ChangePasswordAtLogon, $Confirm) }
        function Add-ADGroupMember { [CmdletBinding()] param($Identity, $Members, $Server, $Confirm) }
        function Set-ADObject {
            [CmdletBinding()]
            param($Identity, $Server, $Replace, $Add, $Remove, $Clear, [switch]$PassThru)
            if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'top'; ObjectGUID = [guid]::NewGuid() } }
        }
        # Authentication Policy cmdlets
        function Get-ADAuthenticationPolicy { [CmdletBinding()] param($Identity, $Properties, $Server) }
        function Get-ADAuthenticationPolicySilo { [CmdletBinding()] param($Identity, $Properties, $Server) }
        function New-ADAuthenticationPolicy {
            [CmdletBinding()]
            param($Name, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicy'; ObjectGUID = [guid]::NewGuid() } }
        }
        function New-ADAuthenticationPolicySilo {
            [CmdletBinding()]
            param($Name, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
        }
        function Set-ADAuthenticationPolicy { [CmdletBinding()] param($Identity, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm) }
        function Set-ADAuthenticationPolicySilo { [CmdletBinding()] param($Identity, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm) }
        function Set-ADAccountAuthenticationPolicySilo {
            [CmdletBinding()]
            param($Identity, $AuthenticationPolicySilo, $Server, [switch]$Confirm, [switch]$PassThru)
            if ($PassThru) { [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,DC=stub,DC=test"; ObjectClass = 'computer'; ObjectGUID = [guid]::NewGuid() } }
        }
        function Grant-ADAuthenticationPolicySiloAccess {
            [CmdletBinding()]
            param($Identity, $Account, $Server, [switch]$Confirm, [switch]$PassThru)
            if ($PassThru) { [PSCustomObject]@{ Name = $Identity; DistinguishedName = "CN=$Identity,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
        }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}

if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {

    # GroupPolicy module stubs
    function Get-GPO { [CmdletBinding()] param($Name, $Guid, [switch]$All, $Server, $Domain) }
    function Get-GPInheritance { [CmdletBinding()] param($Target, $Server, $Domain) }
    function New-GPLink {
        [CmdletBinding()]
        param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled)
        [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
    }
    function Set-GPLink {
        [CmdletBinding()]
        param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled)
        [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
    }
    function Set-GPInheritance { [CmdletBinding()] param($Target, $IsBlocked, $Server, $Domain) }
    function Import-GPO { [CmdletBinding()] param($BackupGpoName, $BackupId, $Path, $TargetName, $TargetGuid, $Server, $Domain, $CreateIfNeeded, $MigrationTable, [switch]$AsJob) }
    function New-GPO {
        [CmdletBinding()]
        param($Name, $Server, $Domain, $Comment)
        [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = $Comment; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
    }
    function Get-GPRegistryValue { [CmdletBinding()] param($Name, $Guid, $Key, $ValueName, $Server, $Domain) }
    function Set-GPRegistryValue {
        [CmdletBinding()]
        param($Name, $Guid, $Key, $ValueName, $Value, $Type, $Server, $Domain)
        [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = ''; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
    }

    # Register as in-memory module so Get-Module GroupPolicy returns a result
    New-Module -Name GroupPolicy -ScriptBlock {
        function Get-GPO { [CmdletBinding()] param($Name, $Guid, [switch]$All, $Server, $Domain) }
        function Get-GPInheritance { [CmdletBinding()] param($Target, $Server, $Domain) }
        function New-GPLink {
            [CmdletBinding()]
            param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled)
            [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
        }
        function Set-GPLink {
            [CmdletBinding()]
            param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled)
            [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
        }
        function Set-GPInheritance { [CmdletBinding()] param($Target, $IsBlocked, $Server, $Domain) }
        function Import-GPO { [CmdletBinding()] param($BackupGpoName, $BackupId, $Path, $TargetName, $TargetGuid, $Server, $Domain, $CreateIfNeeded, $MigrationTable, [switch]$AsJob) }
        function New-GPO {
            [CmdletBinding()]
            param($Name, $Server, $Domain, $Comment)
            [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = $Comment; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
        }
        function Get-GPRegistryValue { [CmdletBinding()] param($Name, $Guid, $Key, $ValueName, $Server, $Domain) }
        function Set-GPRegistryValue {
            [CmdletBinding()]
            param($Name, $Guid, $Key, $ValueName, $Value, $Type, $Server, $Domain)
            [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = ''; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
        }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}

if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {

    # Security cmdlet stubs
    function Get-Acl { [CmdletBinding()] param($Path, $LiteralPath, $InputObject, [switch]$Audit, [switch]$AllCentralAccessPolicies, $Filter, $Include, $Exclude) }
    function Set-Acl { [CmdletBinding()] param($Path, $AclObject) }
}

if (-not (Get-Command Find-LapsADExtendedRights -ErrorAction SilentlyContinue)) {

    # Windows LAPS module stubs -- required for WinLaps deployment/audit cmdlets
    function Find-LapsADExtendedRights { [CmdletBinding()] param($Identity, $DomainController, $Credential) }
    function Set-LapsADComputerSelfPermission { [CmdletBinding()] param($Identity, $DomainController, $Credential) }
    function Set-LapsADReadPasswordPermission { [CmdletBinding()] param($Identity, $AllowedPrincipals, $DomainController, $Credential) }
    function Set-LapsADResetPasswordPermission { [CmdletBinding()] param($Identity, $AllowedPrincipals, $DomainController, $Credential) }

    # Register as in-memory module so Import-Module LAPS and Get-Module LAPS both succeed
    New-Module -Name LAPS -ScriptBlock {
        function Find-LapsADExtendedRights { [CmdletBinding()] param($Identity, $DomainController, $Credential) }
        function Set-LapsADComputerSelfPermission { [CmdletBinding()] param($Identity, $DomainController, $Credential) }
        function Set-LapsADReadPasswordPermission { [CmdletBinding()] param($Identity, $AllowedPrincipals, $DomainController, $Credential) }
        function Set-LapsADResetPasswordPermission { [CmdletBinding()] param($Identity, $AllowedPrincipals, $DomainController, $Credential) }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}

# Legacy AdmPwd.PS LAPS stubs (admpwd.ps module -- not the same as Windows LAPS above)
if (-not (Get-Command Get-AdmPwdPassword -ErrorAction SilentlyContinue)) {
    function Get-AdmPwdPassword { [CmdletBinding()] param($ComputerName, $Server) }
    function Set-AdmPwdPassword { [CmdletBinding()] param($ComputerName, $NewPassword, $Server) }
}
