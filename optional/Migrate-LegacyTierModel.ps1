param (
    [Parameter(Mandatory=$true)]
    [string]$preferredDC
)

<#
.SYNOPSIS
    This script is used to create rename legacy Tier Model objects before deploying the latest Tier Model to avoid conflicts where duplicate names exist.

.DESCRIPTION
    RM prefix stands for Remove, mean after migration these objects can will be removed as they are no longer required by the new Tier Model.
    This script will rename legacy Tier Model Groups to include the 'RM_' for both the Group Name and the pre-Windows 2000 name.
    This script will rename legacy Tier Model GPOs to include the 'RM_' for the GPO Name, from *- to *RM-.

.PARAMETER PreferredDC
    Ensure all changes occur on the Preferred Domain Controller to avoid replication issues.

.EXAMPLE
    .\Migrate-LegacyTierModel.ps1 -PreferredDC 'DC01.contoso.com'

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

# Define the prefix to add
$groupPrefix = "RM_"

# Define the array of existing group names
$existingGroupNames = @(
    "AdminDomainJoin",
    "BreakGlassAdmins",
    "Tier 0 Application Operators",
    "Tier 0 Build Domain Controller using MDT",
    "Tier 0 Domain Operators",
    "Tier 0 HGS Admins",
    "Tier 0 HGS gMSA Users",
    "Tier 0 HGS View Admins",
    "Tier 2 Computer Quarantine Operators",
    "Tier0Admins",
    "Tier0Operators",
    "Tier0ServerOperators",
    "Tier1Admins",
    "Tier1ApplicationXOperators",
    "Tier1Operators",
    "Tier1ServerOperators",
    "Tier2AccountOperators",
    "Tier2Admins",
    "Tier2DeviceOperators",
    "Tier2GroupOperators",
    "Tier2HelpdeskOperators",
    "Tier2Operators"
)

foreach ($existingGroupName in $existingGroupNames) {
    # Get the group object
    $group = Get-ADGroup -Identity $existingGroupName

    # Construct the new names
    $newGroupName = $groupPrefix + $group.Name
    $newPreWin2000Name = $groupPrefix + $group.sAMAccountName

    # Rename the group
    Rename-ADObject -Identity $group.DistinguishedName -NewName $newGroupName -Server $preferredDC

    # Update the sAMAccountName (pre-Windows 2000 name)
    Set-ADGroup -Identity $group.SamAccountName -SamAccountName $newPreWin2000Name -Server $preferredDC

    Write-Output "Group renamed successfully to $newGroupName with pre-Windows 2000 name $newPreWin2000Name"
}

$existingGPONames = @(
    "*- Additional Domain Security Settings",
    "*- Computer Quarantine",
    "*- MSFT Windows Server 2022 - Domain Security",
    "*- PAW Staging BitLocker",
    "*- PAW Staging Restricted Groups",
    "*- Tier 0 DCs MSFT Edge Version 107 - Computer",
    "*- Tier 0 DCs MSFT Internet Explorer 11 - Computer",
    "*- Tier 0 DCs MSFT Windows 10 1809 and Server 2019 - Defender Antivirus",
    "*- Tier 0 DCs MSFT Windows 10 and Server 2016 Defender",
    "*- Tier 0 DCs MSFT Windows Server 2012 R2 Domain Controller Baseline",
    "*- Tier 0 DCs MSFT Windows Server 2019 - Domain Controller",
    "*- Tier 0 DCs MSFT Windows Server 2019 - Domain Controller Virtualization Based Security",
    "*- Tier 0 DCs MSFT Windows Server 2022 - Defender Antivirus",
    "*- Tier 0 DCs MSFT Windows Server 2022 - Domain Controller",
    "*- Tier 0 DCs MSFT Windows Server 2022 - Domain Controller Virtualization Based Security",
    "*- Tier 0 DCs SCM Windows Server 2016 - Domain Controller Baseline",
    "*- Tier 0 DCs Windows Server 2019 Disable System Guard Secure Launch",
    "*- Tier 0 PAWs",
    "*- Tier 0 PAWs Admin",
    "*- Tier 0 PAWs BitLocker",
    "*- Tier 0 PAWs Devices Base AppLocker Audit",
    "*- Tier 0 PAWs Devices Base AppLocker Enforce",
    "*- Tier 0 PAWs Internet Access Configuration - User",
    "*- Tier 0 PAWs LAPS",
    "*- Tier 0 PAWs MSFT Edge Version 107 - Computer",
    "*- Tier 0 PAWs MSFT Internet Explorer 11 - Computer",
    "*- Tier 0 PAWs MSFT Internet Explorer 11 - User",
    "*- Tier 0 PAWs MSFT Windows 11 21H2 - BitLocker",
    "*- Tier 0 PAWs MSFT Windows 11 21H2 - Computer",
    "*- Tier 0 PAWs MSFT Windows 11 21H2 - Credential Guard",
    "*- Tier 0 PAWs MSFT Windows 11 21H2 - Defender Antivirus",
    "*- Tier 0 PAWs MSFT Windows 11 21H2 - User",
    "*- Tier 0 PAWs MSFT Windows 11 22H2 - BitLocker",
    "*- Tier 0 PAWs MSFT Windows 11 22H2 - Computer",
    "*- Tier 0 PAWs MSFT Windows 11 22H2 - Credential Guard",
    "*- Tier 0 PAWs MSFT Windows 11 22H2 - Defender Antivirus",
    "*- Tier 0 PAWs MSFT Windows 11 22H2 - User",
    "*- Tier 0 PAWs Telemetry Configuration",
    "*- Tier 0 Servers",
    "*- Tier 0 Servers Host Guardian Service Administration Policy",
    "*- Tier 0 Servers LAPS",
    "*- Tier 0 Servers MSFT Edge Version 107 - Computer",
    "*- Tier 0 Servers MSFT Internet Explorer 11 - Computer",
    "*- Tier 0 Servers MSFT Windows 10 1809 and Server 2019 - Defender Antivirus",
    "*- Tier 0 Servers MSFT Windows 10 1809 and Server 2019 Member Server - Credential Guard",
    "*- Tier 0 Servers MSFT Windows 10 and Server 2016 - Credential Guard",
    "*- Tier 0 Servers MSFT Windows 10 and Server 2016 Defender",
    "*- Tier 0 Servers MSFT Windows Server 2012 R2 Member Server Baseline",
    "*- Tier 0 Servers MSFT Windows Server 2019 - Member Server",
    "*- Tier 0 Servers MSFT Windows Server 2022 - Defender Antivirus",
    "*- Tier 0 Servers MSFT Windows Server 2022 - Member Server",
    "*- Tier 0 Servers MSFT Windows Server 2022 - Member Server Credential Guard",
    "*- Tier 0 Servers SCM Windows Server 2016 - Member Server Baseline - Computer",
    "*- Tier 0 Servers SCM Windows Server 2016 - Member Server Baseline - User",
    "*- Tier 0 Servers Windows Server 2019 Disable System Guard Secure Launch",
    "*- Tier 1 PAWs",
    "*- Tier 1 PAWs Admin",
    "*- Tier 1 PAWs BitLocker",
    "*- Tier 1 PAWs Devices Base AppLocker Audit",
    "*- Tier 1 PAWs Devices Base AppLocker Enforce",
    "*- Tier 1 PAWs Internet Access Configuration - User",
    "*- Tier 1 PAWs LAPS",
    "*- Tier 1 PAWs MSFT Edge Version 107 - Computer",
    "*- Tier 1 PAWs MSFT Internet Explorer 11 - Computer",
    "*- Tier 1 PAWs MSFT Internet Explorer 11 - User",
    "*- Tier 1 PAWs MSFT Windows 11 21H2 - BitLocker",
    "*- Tier 1 PAWs MSFT Windows 11 21H2 - Computer",
    "*- Tier 1 PAWs MSFT Windows 11 21H2 - Credential Guard",
    "*- Tier 1 PAWs MSFT Windows 11 21H2 - Defender Antivirus",
    "*- Tier 1 PAWs MSFT Windows 11 21H2 - User",
    "*- Tier 1 PAWs MSFT Windows 11 22H2 - BitLocker",
    "*- Tier 1 PAWs MSFT Windows 11 22H2 - Computer",
    "*- Tier 1 PAWs MSFT Windows 11 22H2 - Credential Guard",
    "*- Tier 1 PAWs MSFT Windows 11 22H2 - Defender Antivirus",
    "*- Tier 1 PAWs MSFT Windows 11 22H2 - User",
    "*- Tier 1 PAWs Telemetry Configuration",
    "*- Tier 1 Servers",
    "*- Tier 1 Servers LAPS",
    "*- Tier 1 Servers MSFT Edge Version 107 - Computer",
    "*- Tier 1 Servers MSFT Internet Explorer 11 - Computer",
    "*- Tier 1 Servers MSFT Windows 10 1809 and Server 2019 - Defender Antivirus",
    "*- Tier 1 Servers MSFT Windows 10 1809 and Server 2019 Member Server - Credential Guard",
    "*- Tier 1 Servers MSFT Windows 10 and Server 2016 - Credential Guard",
    "*- Tier 1 Servers MSFT Windows 10 and Server 2016 Defender",
    "*- Tier 1 Servers MSFT Windows Server 2012 R2 Member Server Baseline",
    "*- Tier 1 Servers MSFT Windows Server 2019 - Member Server",
    "*- Tier 1 Servers MSFT Windows Server 2022 - Defender Antivirus",
    "*- Tier 1 Servers MSFT Windows Server 2022 - Member Server",
    "*- Tier 1 Servers MSFT Windows Server 2022 - Member Server Credential Guard",
    "*- Tier 1 Servers SCM Windows Server 2016 - Member Server Baseline - Computer",
    "*- Tier 1 Servers SCM Windows Server 2016 - Member Server Baseline - User",
    "*- Tier 1 Servers Staging",
    "*- Tier 1 Servers Windows Server 2019 Disable System Guard Secure Launch",
    "*- Tier 2 Devices Staging",
    "*- Tier 2 LAPS",
    "*- Tier 2 MSFT Edge Version 107 - Computer",
    "*- Tier 2 MSFT Internet Explorer 11 - Computer",
    "*- Tier 2 MSFT Internet Explorer 11 - User",
    "*- Tier 2 MSFT M365 Apps for enterprise 2104 - Computer",
    "*- Tier 2 MSFT M365 Apps for enterprise 2104 - DDE Block - User",
    "*- Tier 2 MSFT M365 Apps for enterprise 2104 - Legacy File Block - User",
    "*- Tier 2 MSFT M365 Apps for enterprise 2104 - Legacy JScript Block - Computer",
    "*- Tier 2 MSFT M365 Apps for enterprise 2104 - Require Macro Signing - User",
    "*- Tier 2 MSFT M365 Apps for enterprise 2104 - User",
    "*- Tier 2 MSFT Windows 11 21H2 - BitLocker",
    "*- Tier 2 MSFT Windows 11 21H2 - Computer",
    "*- Tier 2 MSFT Windows 11 21H2 - Credential Guard",
    "*- Tier 2 MSFT Windows 11 21H2 - Defender Antivirus",
    "*- Tier 2 MSFT Windows 11 21H2 - User",
    "*- Tier 2 MSFT Windows 11 22H2 - BitLocker",
    "*- Tier 2 MSFT Windows 11 22H2 - Computer",
    "*- Tier 2 MSFT Windows 11 22H2 - Credential Guard",
    "*- Tier 2 MSFT Windows 11 22H2 - Defender Antivirus",
    "*- Tier 2 MSFT Windows 11 22H2 - User",
    "*- Tier 2 PAWs",
    "*- Tier 2 PAWs Admin",
    "*- Tier 2 PAWs BitLocker",
    "*- Tier 2 PAWs Devices Base AppLocker Audit",
    "*- Tier 2 PAWs Devices Base AppLocker Enforce",
    "*- Tier 2 PAWs Internet Access Configuration - User",
    "*- Tier 2 PAWs LAPS",
    "*- Tier 2 PAWs MSFT Edge Version 107 - Computer",
    "*- Tier 2 PAWs MSFT Internet Explorer 11 - Computer",
    "*- Tier 2 PAWs MSFT Internet Explorer 11 - User",
    "*- Tier 2 PAWs MSFT Windows 11 21H2 - BitLocker",
    "*- Tier 2 PAWs MSFT Windows 11 21H2 - Computer",
    "*- Tier 2 PAWs MSFT Windows 11 21H2 - Credential Guard",
    "*- Tier 2 PAWs MSFT Windows 11 21H2 - Defender Antivirus",
    "*- Tier 2 PAWs MSFT Windows 11 21H2 - User",
    "*- Tier 2 PAWs MSFT Windows 11 22H2 - BitLocker",
    "*- Tier 2 PAWs MSFT Windows 11 22H2 - Computer",
    "*- Tier 2 PAWs MSFT Windows 11 22H2 - Credential Guard",
    "*- Tier 2 PAWs MSFT Windows 11 22H2 - Defender Antivirus",
    "*- Tier 2 PAWs MSFT Windows 11 22H2 - User",
    "*- Tier 2 PAWs Telemetry Configuration",
    "*- Tier 2 Workstations"
)

foreach ($existingGPOName in $existingGPONames) {
    
    # Get the GPO object
    $gpo = Get-GPO -DisplayName $existingGPOName

    # Replace name with new name
    $newName = $gpo.DisplayName -replace '[*]', '*RM'
        
    # Rename the GPO
    Rename-GPO -Guid $gpo.Id -TargetName $newName -Server $preferredDC
    Write-Output "Renamed GPO '$($gpo.DisplayName)' to '$newName'"

}
