param (
    [Parameter(Mandatory=$true)]
    [string]$PreferredDC
)

<#
.SYNOPSIS
    This script is used to create the Authentication Silos for the Microsoft Tier Model.

.DESCRIPTION
    This script will deploy a Tier 0 and Tier 1 Authentication Silo for the Microsoft Tier Model.
    The script will create the necessary Active Directory Authentication Policies for the Tier 0 and Tier 1 Authentication Silos.
    Using the SID of the Enterprise Domain Controllers, Tier0PAWDevices, and Tier0MemberServers, the script will create the necessary SDDL for the AuthSilo EA.
    Also using the SID of the Tier1PAWDevices and Tier1MemberServers, the script will create the necessary SDDL for the AuthSilo EA.

.PARAMETER PreferredDC
    Ensure all changes occur on the Preferred Domain Controller to avoid replication issues.

.EXAMPLE
    .\Deploy-TierModelAuthSilo.ps1 -PreferredDC 'DC01.contoso.com'

.NOTES
    This sample script is not supported under any Microsoft standard support program or service. 
    The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
    all implied warranties including, without limitation, any implied warranties of merchantability 
    or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
    the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
    or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
    damages whatsoever (including, without limitation, damages for loss of business profits, business 
    interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
    inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
    possibility of such damages
#>

# Import the Active Directory module
Import-Module ActiveDirectory

# Variables
$T0KerberosAuthenticationPolicy = '*- Tier 0 Authentication Silo'
$T1KerberosAuthenticationPolicy = '*- Tier 1 Authentication Silo'
$T0KerberosAuthenticationPolicyDescription = 'Tier 0 Authentication Silo - Only Tier 0 PAW Devices, Domain Controllers, and Tier 0 Member Servers are allowed to authenticate to this policy'
$T1KerberosAuthenticationPolicyDescription = 'Tier 1 Authentication Silo - Only Tier 1 PAW Devices and Tier 1 Member Servers are allowed to authenticate to this policy'
$TGTLifeTime = 240

# Check if the Authentication Policies already exist, else create the Tier 0 Authentication Policy
try {
    if ([bool](Get-ADAuthenticationPolicy -Filter "Name -eq '$T0KerberosAuthenticationPolicy'")){
        Write-Debug "Kerberos Authentication Policy $T0KerberosAuthenticationPolicy already exists"
    } else {
    #Get the SID for the Enterprise Domain Controllers, Tier0PAWDevices, and Tier0MemberServers
    $T0PawDeviceSID = (Get-ADGroup -Identity 'Tier0PAWDevices' -Properties ObjectSid -Server $PreferredDC).ObjectSid.Value
    $T0MemberServerSID = (Get-ADGroup -Identity 'Tier0MemberServers' -Properties ObjectSid -Server $PreferredDC).ObjectSid.Value

    #SDDL for the AuthSilo EA = Enterprise Domain Controllers, Tier0PAWDevices, and Tier0MemberServers
    $T0AllowToAuthenticateFromSDDL = "O:SYG:SYD:(XA;OICI;CR;;;WD;((Member_of {SID(ED)}) || ((Member_of {SID($T0PawDeviceSID)}) && (Member_of {SID($T0MemberServerSID)}))))"

    #Create the Authentication Policies for Tier 0
    New-ADAuthenticationPolicy -Name $T0KerberosAuthenticationPolicy `
    -UserTGTLifetimeMins $TGTLifeTime `
    -Description $T0KerberosAuthenticationPolicyDescription `
    -UserAllowedToAuthenticateFrom $T0AllowToAuthenticateFromSDDL `
    -ProtectedFromAccidentalDeletion $true `
    -Server $PreferredDC                         
    }
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]{
    Write-Host "Can't find group $($Error[0].CategoryInfo.TargetName). Script aborted" -ForegroundColor Red 
    Write-Host "script aborted" -ForegroundColor Red
    exit
}
catch [System.UnauthorizedAccessException]{
    Write-Host "Enterprise Administrator Privileges required to create Kerberos Authentication Policy" -ForegroundColor Red
    Write-Host $($Error[0].Exception.Message) -ForegroundColor Red
    Write-Host "script aborted " -ForegroundColor Red
    exit
}

# Check if the Authentication Policies already exist, else create the Tier 1 Authentication Policy
try {
    if ([bool](Get-ADAuthenticationPolicy -Filter "Name -eq '$T1KerberosAuthenticationPolicy'")){
        Write-Debug "Kerberos Authentication Policy $T1KerberosAuthenticationPolicy already exists"
    } else {
    #Get the SID for the Tier1PAWDevices and Tier1MemberServers
    $T1PawDeviceSID = (Get-ADGroup -Identity 'Tier1PAWDevices' -Properties ObjectSid -Server $PreferredDC).ObjectSid.Value
    $T1MemberServerSID = (Get-ADGroup -Identity 'Tier1MemberServers' -Properties ObjectSid -Server $PreferredDC).ObjectSid.Value

    #SDDL for the AuthSilo EA = Enterprise Domain Controllers, Tier0PAWDevices, and Tier0MemberServers
    $T1AllowToAuthenticateFromSDDL = "O:SYG:SYD:(XA;OICI;CR;;;WD;((Member_of {SID($T1PawDeviceSID)}) && (Member_of {SID($T1MemberServerSID)})))"

    #Create the Authentication Policies for Tier 1
    New-ADAuthenticationPolicy -Name $T1KerberosAuthenticationPolicy `
    -UserTGTLifetimeMins $TGTLifeTime `
    -Description $T1KerberosAuthenticationPolicyDescription `
    -UserAllowedToAuthenticateFrom $T1AllowToAuthenticateFromSDDL `
    -ProtectedFromAccidentalDeletion $true `
    -Server $PreferredDC                            
    }
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]{
    Write-Host "Can't find group $($Error[0].CategoryInfo.TargetName). Script aborted" -ForegroundColor Red 
    Write-Host "script aborted" -ForegroundColor Red
    exit
}
catch [System.UnauthorizedAccessException]{
    Write-Host "Enterprise Administrator Privileges required to create Kerberos Authentication Policy" -ForegroundColor Red
    Write-Host $($Error[0].Exception.Message) -ForegroundColor Red
    Write-Host "script aborted " -ForegroundColor Red
    exit
}
