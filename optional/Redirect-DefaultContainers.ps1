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
# There is no legitimate "not found" case for the current domain and no graceful fallback. A
# $null $Domain yields an empty $DomainCN, and the redirection targets are built by string
# interpolation, so the failure would surface only as a malformed DN handed to
# redirusr/redircmp. Fail loudly and stop before anything is redirected.
try {
    $Domain = Get-ADDomain -ErrorAction Stop
}
catch {
    throw "Failed to read the current Active Directory domain: $($_.Exception.Message)"
}

$DomainCN = $Domain.DistinguishedName
if ([string]::IsNullOrWhiteSpace($DomainCN)) {
    throw 'Get-ADDomain returned no DistinguishedName; cannot build the container redirection targets.'
}

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
