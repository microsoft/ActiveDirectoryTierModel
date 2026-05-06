param (
    [bool]$RedirectUsers = $false,
    [bool]$RedirectComputers = $false
)

<#
.SYNOPSIS
    This script is used to Redirect the default Computer and User containers to Microsoft Tier Model specific OUs.

.DESCRIPTION
    This script can be used to direct each or both of the default User and Computer Containers. User container 
    will be directed to the Tier 2 End-User Accounts OU and Computer container will be directed to the 
    Tier Model Computer Quarantine OU.

.PARAMETER RedirectUsers
    Redirect the default User Container to the Tier 2 End-User Accounts OU.

.PARAMETER RedirectComputers
    Redirect the default Computer Container to the Tier Model Computer Quarantine OU.

.EXAMPLE
    .\Redirect-DefaultContainers.ps1 -RedirectUsers $true -RedirectComputers $true

.Example
    .\Redirect-DefaultContainers.ps1 -RedirectUsers $true

.EXAMPLE
    .\Redirect-DefaultContainers.ps1 -RedirectComputers $true

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

Import-Module ActiveDirectory

# Get the CN and Name of the current domain
$Domain = Get-ADDomain
$DomainCN = $Domain.DistinguishedName

if ($RedirectUsers) {
    # Redirecting the User Container
    $OU = "OU=Tier 2 End-User Accounts,$DomainCN"
    redirusr $OU
}

if ($RedirectComputers) {
    # Redirecting the Computer Container
    $OU = "OU=Tier Model Computer Quarantine,$DomainCN"
    redircmp $OU
}
