[cmdletbinding(SupportsShouldProcess=$true)]
Param (
    [Parameter (Mandatory=$false)]
    [String]$TieredComputerGroupName  = "Tier0MemberServers",

    [Parameter(Mandatory=$false)]
    [string]$TieredComputerOU = "OU=Tier 0 Member Servers",

    [Parameter (Mandatory=$false)]
    [bool]$MultiDomainForest = $false
)

<#
.Synopsis
    This scripts is meant to maintain the Tier 0 Member Server group membership in order to support Authentication Silo policies

.DESCRIPTION
    The script will get all computer objects under the Tier 0 Member Servers OU and add them to the Tier0MemberServers group. The group is part of an authentication silo policy.

.EXAMPLE
	.\Tier0ComputerManagement.ps1

.EXAMPLE
	.\Tier0ComputerManagement.ps1 -MultiDomainForest $true
    
.PARAMETER Tier0ComputerGroupName
    Name of the Group that contains all Tier 0 Computers objects

.PARAMETER Tier0ComputerOU
    The relative DistinguishedName of the Tier 0 computer OU path

.PARAMETER MultiDomainForest
    If the value is $true, the script will search for the Tier 0 computer OU in all domains of the forest. If the value is $false, the script will search for the Tier 0 computer OU in the current domain only.    

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

# Function to write to the Event Log
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Message,
        
        [Parameter (Mandatory = $true)]
        [Validateset('Error', 'Warning', 'Information', 'Debug') ]
        $Severity
    )
    #Format the log message and write it to the log file
    $LogLine = "$(Get-Date -Format o), [$Severity], $Message"
    Add-Content -Path $LogFile -Value $LogLine 
    switch ($Severity) {
        'Error'   { 
            Write-Host $Message -ForegroundColor Red
            Add-Content -Path $LogFile -Value $Error[0].ScriptStackTrace  
        }
        'Warning' { Write-Host $Message -ForegroundColor Yellow}
        'Information' { Write-Host $Message }
    }
}

#######################################################
# Main Program starts here                            #
#######################################################

#region Manage log file
[int]$MaxLogFileSize = 1048576 #Maximum size of the log file
$LogFile = "$($env:LOCALAPPDATA)\$($MyInvocation.MyCommand).log" #Name and path of the log file
#rename existing log files to *.sav if the currentlog file exceed the size of $MaxLogFileSize
if (Test-Path $LogFile){
    if ((Get-Item $LogFile ).Length -gt $MaxLogFileSize){
        if (Test-Path "$LogFile.sav"){
            Remove-Item "$LogFile.sav"
        }
        Rename-Item -Path $LogFile -NewName "$logFile.sav"
    }
}
#endregion
Write-Log -Message $MyInvocation.Line -Severity Debug

#for compatibility reason the Domain component will be removed from the OU path
$aryTier0Computer = @()
Foreach ($T0OU in $TieredComputerOU.Split(";")){
    $aryTier0Computer += [regex]::Replace($T0OU,",DC=.+","")
}
#searching for the T0 computers group in all domains
try{
    $adoGroup = Get-ADObject -Filter {(SamaccountName -eq $TieredComputerGroupName) -and (Objectclass -eq "Group")} -Properties member
}
catch [Microsoft.ActiveDirectory.Management.ADServerDownException]{
    Write-Log "The AD web service is not available. The group $TieredComputerGroupName cannot be updates" -Severity Error
    Write-EventLog -LogName "Application" -source "Application" -EventId 0 -EntryType Error -Message "The AD web service is not available. The group $Tier0ComputerGorupName cannot be updates"
    exit 0x3E9
}
if ($null -eq $adoGroup){
    Write-Log "Tier 0 computer management: Can't find the group $TieredComputerGroupName in the current domain. Script aborted" -Severity Error
    Write-Eventlog -LogName "Application" -Source "Application" -EventId 0 -EntryType Error -Category 1 -Message "Tier 0 computer management: Can't find the group $TieredComputerGroupName in the current domain. Script aborted"
    exit 0x3E8
}

#on multi domain mode write all domains into the array otherwise us the current domain name
if ($MultiDomainForest -eq $false){
    $domains = (Get-ADDomain).DNSRoot
} else {
    $domains = (Get-ADForest).Domains
}
$bGroupMemberchanged = $false
Foreach ($OU in $aryTier0Computer){
    Foreach ($domain in $domains){
        #validate the Tier 0 OU path
        try {
            if ($null -eq (Get-ADObject "$OU,$((Get-ADDomain -Server $domain).DistinguishedName)" -Server $domain)){
                Write-Log "Missing the Tier 0 computer OU $OU,$((Get-ADDomain -Server $domain).DistinguishedName)" -Severity Warning
                Write-EventLog -LogName "Application" -source "Application" -EventId 0 -EntryType Error -Message "Missing the Tier 0 computer OU $OU,$((Get-ADDomain -Server $domain).DistinguishedName)"
            } else{
                $T0computers = Get-ADObject -Filter {ObjectClass -eq "Computer"} -SearchBase "$OU,$((Get-ADDomain -Server $domain).DistinguishedName)" -Properties ObjectSid -SearchScope Subtree -Server $domain
                #validate the computer ain the Tier 0 OU are member of the tier 0 computers group
                Write-Log -Message "Found $($T0computers.Count) Tier 0 computers in $domain" -Severity Debug
                Foreach ($T0Computer in $T0computers){
                    if ($adoGroup.member -notcontains $T0Computer ){
                        $adoGroup.member += $T0Computer.DistinguishedName
                        $bGroupMemberchanged = $true
                        Write-Log "Added $T0computer to $adoGroup" -Severity Information
                        Write-EventLog -LogName "Application" -source "Application" -EventID 0 -EntryType information -Message "Added $T0Computer to $adoGroup"
                    }
                }
            }
        }
        catch [Microsoft.ActiveDirectory.Management.ADServerDownException]{
            Write-Log "The domain $domain WebService is down or not reachable" -Severity Error
            Write-EventLog -LogName "Application" -Source "Application" -EventID 0 -EntryType Warning -Message "The domain $domain WebService is down or not reachable"
        }
    }
}
try{
    if ($bGroupMemberchanged){
        Set-ADObject -Instance $adoGroup    
        Write-Log "Adding new computers to the Tier 0 computer group" -Severity Debug
        $bGroupMemberchanged = $false
    }
    #remove any object from Tier 0 computer group who is not member of the tier 0 computers list
    $updatedGroupMembers = @()
    Foreach ($member in ($adoGroup.member)){
        $isMember = $false
        foreach ($ComputerOU in $aryTier0Computer){
            if ($member -like "*$ComputerOU*"){
                $isMember = $true
                break
            }
        }
        if ($isMember){
            $updatedGroupMembers += $member
        } else {
            Write-Log "Unexpected computer object $member removed from $($adoGroup.DistinguishedName)" -Severity Warning
            Write-EventLog -LogName "Application" -source "Application" -EventID 0 -EntryType Warning -Message "Unexpected computer object $member removed from $($adoGroup.DistinguishedName)"
            $bGroupMemberchanged = $true
        }
    }
    if ($bGroupMemberchanged){
        $adoGroup.member = $updatedGroupMembers
        Set-ADObject -Instance $adoGroup
        Write-Log "Removing non-tier 0 computers from the Tier 0 computer group" -Severity Debug
    }
}
catch [Microsoft.ActiveDirectory.Management.ADServerDownException]{
    Write-Log "The AD web service is not available. The group $adogroup cannot be updates"
    Write-EventLog -LogName "Application" -source "Application" -EventId 0 -EntryType Error -Message "The AD web service is not available. The group $adogroup cannot be updates"
    exit 0x3E9
}
