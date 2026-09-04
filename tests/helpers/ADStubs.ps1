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
    function Get-ADGroupMember { param($Identity, $Server, [switch]$Recursive, $ErrorAction) }
    function Get-ADUser { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADOrganizationalUnit { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADObject { param($Identity, $Server, $Filter, $SearchBase, $Properties, $LDAPFilter, $SearchScope, $ErrorAction) }
    function Get-ADComputer { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
    function Get-ADRootDSE { param($Server) }
    function New-ADGroup {
        param($Name, $GroupScope, $GroupCategory, $Path, $Server, $Description, $DisplayName, $SamAccountName, [switch]$PassThru, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; SamAccountName = $SamAccountName; DistinguishedName = "CN=$Name,$Path"; ObjectClass = 'group'; ObjectGUID = [guid]::NewGuid() } }
    }
    function New-ADOrganizationalUnit {
        param($Name, $Path, $Server, $Description, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "OU=$Name,$Path"; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
    }
    function Set-ADOrganizationalUnit {
        param($Identity, $Server, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
    }
    function New-ADUser { param($Name, $SamAccountName, $UserPrincipalName, $Path, $Server, $AccountPassword, $Enabled, $DisplayName, $Description, $GivenName, $Surname, $ErrorAction) }
    function Add-ADGroupMember { param($Identity, $Members, $Server, $ErrorAction) }
    function Set-ADObject {
        param($Identity, $Server, $Replace, $Add, $Remove, $Clear, [switch]$PassThru, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'top'; ObjectGUID = [guid]::NewGuid() } }
    }
    # Authentication Policy cmdlets (used by auth-silo module functions)
    function Get-ADAuthenticationPolicy { param($Identity, $Properties, $Server, $ErrorAction) }
    function Get-ADAuthenticationPolicySilo { param($Identity, $Properties, $Server, $ErrorAction) }
    function New-ADAuthenticationPolicy {
        param($Name, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicy'; ObjectGUID = [guid]::NewGuid() } }
    }
    function New-ADAuthenticationPolicySilo {
        param($Name, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
    }
    function Set-ADAuthenticationPolicy { param($Identity, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm, $ErrorAction) }
    function Set-ADAuthenticationPolicySilo { param($Identity, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm, $ErrorAction) }
    function Set-ADAccountAuthenticationPolicySilo {
        param($Identity, $AuthenticationPolicySilo, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,DC=stub,DC=test"; ObjectClass = 'computer'; ObjectGUID = [guid]::NewGuid() } }
    }
    function Grant-ADAuthenticationPolicySiloAccess {
        param($Identity, $Account, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
        if ($PassThru) { [PSCustomObject]@{ Name = $Identity; DistinguishedName = "CN=$Identity,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
    }

    # Register as in-memory module so Get-Module ActiveDirectory returns a result
    New-Module -Name ActiveDirectory -ScriptBlock {
        function Get-ADDomain { param($Server, $Identity) }
        function Get-ADForest { param($Server, $Identity) }
        function Get-ADGroup { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADGroupMember { param($Identity, $Server, [switch]$Recursive, $ErrorAction) }
        function Get-ADUser { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADOrganizationalUnit { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADObject { param($Identity, $Server, $Filter, $SearchBase, $Properties, $LDAPFilter, $SearchScope, $ErrorAction) }
        function Get-ADComputer { param($Identity, $Server, $Filter, $SearchBase, $Properties, $ErrorAction) }
        function Get-ADRootDSE { param($Server) }
        function New-ADGroup {
            param($Name, $GroupScope, $GroupCategory, $Path, $Server, $Description, $DisplayName, $SamAccountName, [switch]$PassThru, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; SamAccountName = $SamAccountName; DistinguishedName = "CN=$Name,$Path"; ObjectClass = 'group'; ObjectGUID = [guid]::NewGuid() } }
        }
        function New-ADOrganizationalUnit {
            param($Name, $Path, $Server, $Description, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "OU=$Name,$Path"; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
        }
        function Set-ADOrganizationalUnit {
            param($Identity, $Server, $ProtectedFromAccidentalDeletion, [switch]$PassThru, $Confirm, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'organizationalUnit'; ObjectGUID = [guid]::NewGuid() } }
        }
        function New-ADUser { param($Name, $SamAccountName, $UserPrincipalName, $Path, $Server, $AccountPassword, $Enabled, $DisplayName, $Description, $GivenName, $Surname, $ErrorAction) }
        function Add-ADGroupMember { param($Identity, $Members, $Server, $ErrorAction) }
        function Set-ADObject {
            param($Identity, $Server, $Replace, $Add, $Remove, $Clear, [switch]$PassThru, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ DistinguishedName = $Identity; ObjectClass = 'top'; ObjectGUID = [guid]::NewGuid() } }
        }
        # Authentication Policy cmdlets
        function Get-ADAuthenticationPolicy { param($Identity, $Properties, $Server, $ErrorAction) }
        function Get-ADAuthenticationPolicySilo { param($Identity, $Properties, $Server, $ErrorAction) }
        function New-ADAuthenticationPolicy {
            param($Name, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicy'; ObjectGUID = [guid]::NewGuid() } }
        }
        function New-ADAuthenticationPolicySilo {
            param($Name, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ Name = $Name; DistinguishedName = "CN=$Name,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
        }
        function Set-ADAuthenticationPolicy { param($Identity, $Description, $UserAllowedToAuthenticateFrom, $UserTGTLifetimeMins, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm, $ErrorAction) }
        function Set-ADAuthenticationPolicySilo { param($Identity, $Description, $UserAuthenticationPolicy, $ComputerAuthenticationPolicy, $ServiceAuthenticationPolicy, $Enforce, $ProtectedFromAccidentalDeletion, $Server, $Confirm, $ErrorAction) }
        function Set-ADAccountAuthenticationPolicySilo {
            param($Identity, $AuthenticationPolicySilo, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,DC=stub,DC=test"; ObjectClass = 'computer'; ObjectGUID = [guid]::NewGuid() } }
        }
        function Grant-ADAuthenticationPolicySiloAccess {
            param($Identity, $Account, $Server, [switch]$Confirm, [switch]$PassThru, $ErrorAction)
            if ($PassThru) { [PSCustomObject]@{ Name = $Identity; DistinguishedName = "CN=$Identity,CN=AuthN Silos,CN=AuthN Policy Configuration,CN=Services,CN=Configuration,DC=stub,DC=test"; ObjectClass = 'msDS-AuthNPolicySilo'; ObjectGUID = [guid]::NewGuid() } }
        }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}

if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {

    # GroupPolicy module stubs
    function Get-GPO { param($Name, $Guid, [switch]$All, $Server, $Domain, $ErrorAction) }
    function Get-GPInheritance { param($Target, $Server, $Domain) }
    function New-GPLink {
        param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction)
        [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
    }
    function Set-GPLink {
        param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction)
        [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
    }
    function Set-GPInheritance { param($Target, $IsBlocked, $Server, $Domain) }
    function Import-GPO { param($BackupGpoName, $Path, $TargetName, $TargetGuid, $Server, $Domain, $CreateIfNeeded, $ErrorAction) }
    function New-GPO {
        param($Name, $Server, $Domain, $Comment, $ErrorAction)
        [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = $Comment; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
    }
    function Get-GPRegistryValue { param($Name, $Guid, $Key, $ValueName, $Server, $Domain, $ErrorAction) }
    function Set-GPRegistryValue {
        param($Name, $Guid, $Key, $ValueName, $Value, $Type, $Server, $Domain, $ErrorAction)
        [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = ''; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
    }

    # Register as in-memory module so Get-Module GroupPolicy returns a result
    New-Module -Name GroupPolicy -ScriptBlock {
        function Get-GPO { param($Name, $Guid, [switch]$All, $Server, $Domain, $ErrorAction) }
        function Get-GPInheritance { param($Target, $Server, $Domain) }
        function New-GPLink {
            param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction)
            [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
        }
        function Set-GPLink {
            param($Name, $Guid, $Target, $Server, $Domain, $Order, $Enforced, $LinkEnabled, $ErrorAction)
            [PSCustomObject]@{ DisplayName = $Name; GpoId = [guid]::NewGuid(); Target = $Target; Order = if ($Order) { $Order } else { 1 }; Enabled = $true; Enforced = $false; GpoDomainName = $Domain }
        }
        function Set-GPInheritance { param($Target, $IsBlocked, $Server, $Domain) }
        function Import-GPO { param($BackupGpoName, $Path, $TargetName, $TargetGuid, $Server, $Domain, $CreateIfNeeded, $ErrorAction) }
        function New-GPO {
            param($Name, $Server, $Domain, $Comment, $ErrorAction)
            [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = $Comment; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
        }
        function Get-GPRegistryValue { param($Name, $Guid, $Key, $ValueName, $Server, $Domain, $ErrorAction) }
        function Set-GPRegistryValue {
            param($Name, $Guid, $Key, $ValueName, $Value, $Type, $Server, $Domain, $ErrorAction)
            [PSCustomObject]@{ DisplayName = $Name; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; DomainName = $Domain; Description = ''; CreationTime = [datetime]::UtcNow; ModificationTime = [datetime]::UtcNow }
        }
        Export-ModuleMember -Function *
    } | Import-Module -Global -Force
}

if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {

    # Security cmdlet stubs
    function Get-Acl { param($Path, $ErrorAction) }
    function Set-Acl { param($Path, $AclObject, $ErrorAction) }
}

if (-not (Get-Command Find-LapsADExtendedRights -ErrorAction SilentlyContinue)) {

    # Windows LAPS module stubs -- required for WinLaps deployment/audit cmdlets
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

# Legacy AdmPwd.PS LAPS stubs (admpwd.ps module -- not the same as Windows LAPS above)
if (-not (Get-Command Get-AdmPwdPassword -ErrorAction SilentlyContinue)) {
    function Get-AdmPwdPassword { param($ComputerName, $Server, $ErrorAction) }
    function Set-AdmPwdPassword { param($ComputerName, $NewPassword, $Server, $ErrorAction) }
}
