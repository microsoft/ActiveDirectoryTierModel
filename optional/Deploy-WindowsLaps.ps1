param (
    [Parameter(Mandatory=$true)]
    [string]$PreferredDC
)

# Must update schema first cmdlet for Windows LAPS part of Windows Server 2022 Domain Controller
# Should have been completed as part of the Deployment Guide, Update-LapsADSchema cmdlet

# AD and LAPS module are required
Import-Module ActiveDirectory
Import-Module LAPS

# Get the CN and Name of the current domain
$Domain = Get-ADDomain
$DomainName = $Domain.Name
$DomainCN = $Domain.DistinguishedName

## Setting Computer Self Permission on OUs
# Domain Controller OU
Set-LapsADComputerSelfPermission -Identity "OU=Domain Controllers,$DomainCN" -DomainController $PreferredDC
# Tier 0 Member Server OU
Set-LapsADComputerSelfPermission -Identity "OU=Tier 0 Member Servers,$DomainCN" -DomainController $PreferredDC
# Tier 1 Member Server OU
Set-LapsADComputerSelfPermission -Identity "OU=Tier 1 Member Servers,$DomainCN" -DomainController $PreferredDC
# Tier 2 End-User Devices
Set-LapsADComputerSelfPermission -Identity "OU=Tier 2 End-User Devices,$DomainCN" -DomainController $PreferredDC
# Tier 0 PAW Devices
Set-LapsADComputerSelfPermission -Identity "OU=Tier 0 PAW Devices,OU=Tier 0,OU=Tier Model Administration,$DomainCN" -DomainController $PreferredDC
# Tier 1 PAW Devices
Set-LapsADComputerSelfPermission -Identity "OU=Tier 1 PAW Devices,OU=Tier 1,OU=Tier Model Administration,$DomainCN" -DomainController $PreferredDC
# Tier 2 PAW Devices
Set-LapsADComputerSelfPermission -Identity "OU=Tier 2 PAW Devices,OU=Tier 2,OU=Tier Model Administration,$DomainCN" -DomainController $PreferredDC


## Setting Read Permission for Tier Model Admins
# Domain Controller OU
Set-LapsADReadPasswordPermission -Identity "OU=Domain Controllers,$DomainCN" -AllowedPrincipals "$DomainName\Domain Admins" -DomainController $PreferredDC
# Tier 0 Member Server OU
Set-LapsADReadPasswordPermission -Identity "OU=Tier 0 Member Servers,$DomainCN" -AllowedPrincipals "$DomainName\Tier0ServerOperators" -DomainController $PreferredDC
# Tier 1 Member Server OU
Set-LapsADReadPasswordPermission -Identity "OU=Tier 1 Member Servers,$DomainCN" -AllowedPrincipals "$DomainName\Tier1ServerOperators" -DomainController $PreferredDC
# Tier 2 End-User Devices
Set-LapsADReadPasswordPermission -Identity "OU=Tier 2 End-User Devices,$DomainCN" -AllowedPrincipals @("$DomainName\Tier2DeviceOperators","$DomainName\Tier2HelpdeskOperators") -DomainController $PreferredDC
# Tier 0 PAW Devices
Set-LapsADReadPasswordPermission -Identity "OU=Tier 0 PAW Devices,OU=Tier 0,OU=Tier Model Administration,$DomainCN" -AllowedPrincipals "$DomainName\Tier0Admins" -DomainController $PreferredDC
# Tier 1 PAW Devices
Set-LapsADReadPasswordPermission -Identity "OU=Tier 1 PAW Devices,OU=Tier 1,OU=Tier Model Administration,$DomainCN" -AllowedPrincipals "$DomainName\Tier1Admins" -DomainController $PreferredDC
# Tier 2 PAW Devices
Set-LapsADReadPasswordPermission -Identity "OU=Tier 2 PAW Devices,OU=Tier 2,OU=Tier Model Administration,$DomainCN" -AllowedPrincipals "$DomainName\Tier2Admins" -DomainController $PreferredDC


# Setting Reset Password Permission for Tier Model Admins
# Domain Controller OU
Set-LapsADResetPasswordPermission -Identity "OU=Domain Controllers,$DomainCN" -AllowedPrincipals "$DomainName\Domain Admins" -DomainController $PreferredDC
# Tier 0 Member Server OU
Set-LapsADResetPasswordPermission -Identity "OU=Tier 0 Member Servers,$DomainCN" -AllowedPrincipals "$DomainName\Tier0ServerOperators" -DomainController $PreferredDC
# Tier 1 Member Server OU
Set-LapsADResetPasswordPermission -Identity "OU=Tier 1 Member Servers,$DomainCN" -AllowedPrincipals "$DomainName\Tier1ServerOperators" -DomainController $PreferredDC
# Tier 2 End-User Devices
Set-LapsADResetPasswordPermission -Identity "OU=Tier 2 End-User Devices,$DomainCN" -AllowedPrincipals @("$DomainName\Tier2DeviceOperators","$DomainName\Tier2HelpdeskOperators") -DomainController $PreferredDC
# Tier 0 PAW Devices
Set-LapsADResetPasswordPermission -Identity "OU=Tier 0 PAW Devices,OU=Tier 0,OU=Tier Model Administration,$DomainCN" -AllowedPrincipals "$DomainName\Tier0Admins" -DomainController $PreferredDC
# Tier 1 PAW Devices
Set-LapsADResetPasswordPermission -Identity "OU=Tier 1 PAW Devices,OU=Tier 1,OU=Tier Model Administration,$DomainCN" -AllowedPrincipals "$DomainName\Tier1Admins" -DomainController $PreferredDC
# Tier 2 PAW Devices
Set-LapsADResetPasswordPermission -Identity "OU=Tier 2 PAW Devices,OU=Tier 2,OU=Tier Model Administration,$DomainCN" -AllowedPrincipals "$DomainName\Tier2Admins"

