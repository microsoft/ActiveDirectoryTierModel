[cmdletbinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$false)]
	[string]$TieredUsersOU = "OU=Tier 0 Accounts,OU=Tier 0,OU=Tier Model Administration",
    
    [Parameter(Mandatory=$false)]
    [string]$TieredServiceAccountsOU = "OU=Tier 0 Service Accounts,OU=Tier 0,OU=Tier Model Administration",
	   
	[Parameter(Mandatory=$false)]
	[string]$KerberosPolicyName = "*- Tier 0 Authentication Silo",
    
    [Parameter (Mandatory=$false)]
    [string]$ExcludeTieredUser = "svc-pawdomainjoin",
    
    [Parameter(Mandatory=$false)]
    [switch]$MultiDomainForest = $false,

    [Parameter(Mandatory=$false)]
    [bool]$RemoveUserFromPrivilegedGroups = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExcludeProtectedUsersGroup
)
<#
.Synopsis
    This scripts is meant to maintain the Tier 0 Users and ensure they are assigned to the Tier 0 Authentication Silo policy.

.DESCRIPTION
    The script will get all Tier 0 User objects within the Tier 0 Accounts OU and assign them to the Tier 0 Authentication Silo policy. 
    Any users not within the Tier 0 Accounts OU will be removed from the Tier 0 Authentication Silo policy. 
    The script will also ensure that the Tier 0 Users are marked as sensitive and cannot be delegated.
    The script will also add the users to the Protected Users group.
    By default the script will not add any Tier 0 Servers Accounts, Tier 0 MSA, Tier 0 gMSA, or Tier 0 dMSA accounts automatically, thus must be manually added to the Tier 0 Authentication Silo policy.

.PARAMETER TieredUsersOU
    Path of the Tier 0 Accounts OU which contains all Tier 0 User objects

.PARAMETER KerberosPolicyName
    Name of the Tier 0 Authentication Silo policy to assign to all Tier 0 Users objects

.PARAMETER TieredServiceAccountsOU
    Name of the Tier 0 Service Accounts OU which contains all Tier 0 Service Account objects, this is used to exclude these accounts from the Tier 0 Authentication Silo policy.

.PARAMETER ExcludeTieredUser
    List of any Tier 0 User accounts to be excluded from the Tier 0 Authentication Silo policy such as a Domain join account which requires NTLM authentication.

.PARAMETER MultiDomainForest
    The script will manage all privileged users / groups in every domain of the forest.

.PARAMETER RemoveUserFromPrivilegedGroups
    Default is $true. If set to $true, the script will remove any users from the following groups: Administrators, Domain Admins, Backup Operators, Server Managers, Account

.EXAMPLE
    Tier0UserManagement.ps1 -PrivilegedOUPath "OU=Privileged Accounts,OU=Tier 0,OU=Admin" -KerberosPolicyName "Tier 0 Isolation" -PrivilegedServiceAcocuntOU "OU=service accounts,OU=Tier 0,OU=Admin"  -EnableMultiDomainSupport

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
function Write-Log {
    param (
        # status message
        [Parameter(Mandatory=$true)]
        [string]
        $Message,
        #Severity of the message
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

function validateAndRemoveUser{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        #The SID uof the group
        [string] $SID,
        #The DNS domain Name
        [string] $DomainDNSName
    )
    $Group = Get-ADGroup -Identity $SID -Properties members,canonicalName -Server $DomainDNSName 
    #validate the SID exists
    if ($null -eq $Group){
        Write-Log "Can't validate $SID. This SID is not available" -Severity Warning
        return
    }
    #walk through all members of the group and check this member is a valid user or group
    foreach ($Groupmember in $Group.members)
    {
        $member = Get-ADObject -Filter {DistinguishedName -eq $Groupmember} -Properties * -server "$($DomainDNSName):3268"
        switch ($member.ObjectClass){
            "user"{
                if (($member.ObjectSid.value   -notlike "*-500")                              -and ` #ignore if the member is Built-In Administrator
                    ($member.objectSid.value   -notlike "*-512")                              -and ` #ignore if the member is Domain Admins group
                    ($member.ObjectSid.value   -notlike "*-518")                              -and ` #ignore if the member is Schema Admins
                    ($member.ObjectSid.Value   -notlike "*-519")                              -and ` #ignore if the member is Enterprise Admins
                    ($member.objectSid.Value   -notlike "*-520")                              -and ` #ignore if the member is Group Policy Creator
                    ($member.objectSid.Value   -notlike "*-522")                              -and ` #ignore if the member is cloneable domain controllers
                    ($member.objectSid.Value   -notlike "*-527")                              -and ` #ignore if the member is Enterprise Key Admins
                    ($member.objectClass       -ne "msDS-GroupManagedServiceAccount")         -and ` #ignore if the member is a GMSA
                    ($member.distinguishedName -notlike "*,$TieredUsersOU,*")              -and ` #ignore if the member is located in the Tier 0 user OU
                    ($member.distinguishedName -notlike "*,$TieredServiceAccountsOU*") -and ` #ignore if the member is located in the service account OU
                    ($ExcludeTieredUser              -notlike "*$($member.DistinguishedName)*" )           #ignore if the member is in the exclude user list
                    ){    
                        try{
                            Write-Log -Message "remove $member from $($Group.DistinguishedName)" -Severity Information
                            Set-ADObject -Identity $Group -Remove @{member="$($member.DistinguishedName)"} -Server $DomainDNSName
                        }
                        catch [Microsoft.ActiveDirectory.Management.ADServerDownException]{
                            Write-Log -Message "can't connect to AD-WebServices. $($member.DistinguishedName) is not remove from $($Group.DistinguishedName)" -Severity Error
                        }
                        catch [Microsoft.ActiveDirectory.Management.ADException]{
                            Write-Log -Message "Cannot remove $($member.DistinguishedName) from $($Error[0].CategoryInfo.TargetName) $($Error[0].Exception.Message)" -Severity Error
                        }
                        catch{
                            Write-Log -Message $Error[0].GetType().Name -Severity Error
                        }
                    }
            }
            "group"{
                $MemberDomainDN = [regex]::Match($member.DistinguishedName,"DC=.*").value
                $MemberDNSroot = (Get-ADObject -Filter "ncName -eq '$MemberDomainDN'" -SearchBase (Get-ADForest).Partitionscontainer -Properties dnsRoot).dnsRoot
                validateAndRemoveUser -SID $member.ObjectSid.Value -DomainDNSName $MemberDNSroot
            }
        }
    }        
}

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

#Validate the Kerberos Authentication policy exists. If not terminate the script with error code 0xA3. 
$KerberosAuthenticationPolicy = Get-ADAuthenticationPolicy -Filter {Name -eq $KerberosPolicyName}
if ($null -eq $KerberosAuthenticationPolicy){
    Write-Log -Message "Kerberos Authentication Policy '$KerberosPolicyName' not found on AD. Script terminates with error 0xA3" -Severity Error
    exit 0xA3
}
# enumerate the target domains. If the EnableMultiDomain switch is enabled in a multi domain forest, any domain will be part of the 
# Tier 0 user management. This is the recommended configuration, because the security boundary of Active Directory is the forest not the 
# domain. Any target domain will be captured in the $aryDomainName variable
$aryDomainName = @() #contains all domains for script validation
if ($MultiDomainForest){
    #MultidomainSupport is enabled get all forest domains
    $aryDomainName += (Get-ADForest).Domains
    Write-Log -Message "Multidomain mode is enabled. Found $((Get-ADDomain).Domains.count) domains" -Severity Debug
} else {
    $aryDomainName += (Get-ADDomain).DNSRoot
    Write-Log -Message "Single domain mode is enabled" -Severity Information
}

foreach ($DomainName in $aryDomainName){
    #validating Web-Services are running on this domain
    try {
    Write-Log "Connect to $((Get-ADDomain -Server $DomainName).DistinguishedName) AD web services" -Severity Debug    
    #region Validate the group membership and authentication policy settings in the Tier 0 OU 
        try{
            $oProtectedUsersGroup = Get-ADGroup -Identity "$((Get-ADDomain -Server $domainName).DomainSID)-525" -Server $DomainName -Properties members
            #search for any user in the privileged OU
            foreach ($user in Get-ADUser -SearchBase "$TieredUsersOU,$((Get-ADDomain -Server $DomainName).DistinguishedName)" -Filter * -Properties msDS-AssignedAuthNPolicy,memberOf,UserAccountControl -SearchScope Subtree -Server $DomainName){
                Write-Log -Message "Working on $($User.Distiguishedname)" -Severity Debug
                
                if (($user.UserAccountControl -BAND 1048576) -ne 1048576){
                    try {
                        Set-ADAccountControl -Identity $user -AccountNotDelegated $True
                        Write-Log "Mark $($User.DistinguishedName) as sensitive and cannot be delegated" -Severity Information
                    }
                    catch [Microsoft.ActiveDirectory.Management.ADException]{
                        Write-Log "Cannot add Sensitive flag to the $($user.DistinguishedName)" -Severity Error
                    }
                }
                if ($ExcludeProtectedUsersGroup -ne $true){
                    try{
                        if (($oProtectedUsersGroup.members -notlike $user.DistinguishedName) -or ($oProtectedUsersGroup.Members.Count -eq 0)) {
                            Add-ADGroupMember -Identity $oProtectedUsersGroup $user -Server $DomainName
                            
                            Write-Log "User $($user.Distiguishedname) is addeded to protected users in $Domain" -Severity Information
                        }
                    }
                    catch [Microsoft.ActiveDirectory.Management.ADException]{
                        Write-Log "A access denied error has occured on User $($user.DistinguishedName) while adding user to the protected users group)" -Severity Error
                    }
                }
                #validate the Kerberos Authentication policy is assigned to the user
                if ($user.'msDS-AssignedAuthNPolicy' -ne $KerberosAuthenticationPolicy.DistinguishedName){
                    try {
                        Write-Log "Adding Kerberos Authentication Policy $KerberosPolicyName on $User" -Severity Information
                        Set-ADUser $user -AuthenticationPolicy $KerberosPolicyName -Server $DomainName
                        #if the Kerberos Authentication policy is assigned to a user, the user will be marked as "This user is sensitive and cannot be delegated"
                        #This attribute will only applied to the user, while adding the KerbAuthPol. If the attribute will be removed afterwards it will not be 
                        #reapplied
                        Set-ADAccountControl -Identity $user -AccountNotDelegated $True
                    }
                    catch {
                        Write-Log -Message "The Kerberos Authenticatin Policy $KerberosPolicyName could not be added to $($user.DistinguishedName))" -Severity Error
                    }
                }
            }
        } 
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]{
            Write-Log "Can't get the users in $TieredUsersOU on $domain. ADIdentityNotFoundException" -Severity Error
        }
        catch {
            Write-Log "A unexpected error has occured $($Error[0])" -Severity Error
        }
        #endregion

        #region validate Critical Group Membership
        #any user / group object who is not fulfill the criteria will be removed from the privileged groups
        #store any well-known critical domain group with relative domain sid in $PrivilegedDomainSID
        #groups like Backup Operators, Print Operators, Administrators have a well-known SID without domain SID 
        #Using the SID, provides language independency
        $PrivlegeDomainSid = @(
            "512", #Domain Admins
            "520", #Group Policy Creator Owner
            "522" #Cloneable Domain Controllers
        #   "527" #Enterprise Key Admins
        )
        if ($RemoveUserFromPrivilegedGroups){
            Write-Log "searching for unexpected users in critical groups" -Severity Debug
            foreach ($relativeSid in $PrivlegeDomainSid) {
                validateAndRemoveUser -SID "$((Get-ADDomain -server $DomainName).DomainSID)-$RelativeSid" -DomainDNSName $DomainName
            }
            #Backup Operators
            validateAndRemoveUser -SID "S-1-5-32-551" -DomainDNSName $DomainName
            #Print Operators
            validateAndRemoveUser -SID "S-1-5-32-550" -DomainDNSName $DomainName
            #Server Operators
            validateAndRemoveUser -SID "S-1-5-32-549" -DomainDNSName $DomainName
            #Server Operators
            validateAndRemoveUser -SID "S-1-5-32-548" -DomainDNSName $DomainName
            #Administrators
            validateAndRemoveUser -SID "S-1-5-32-544" -DomainDNSName $DomainName
    }
}
catch {
    Write-Log -Message "Failed to connect to AD Webservices on $DomainName" -Severity Error
}

#endregion
}
#Schema and Enterprise Admins only exists in Forest root domain
if ($RemoveUserFromPrivilegedGroups){
    $forestDNS = (Get-ADDomain).Forest
    $forestSID = (Get-ADDomain -Server $forestDNS).DomainSID.Value
    Write-Log "searching for unexpected users in schema admins" -Severity Debug
    validateAndRemoveUser -SID "$forestSID-518" -DomainDNSName $forestDNS
    Write-Log "searching for unexpteded users in enterprise admins" -Severity Debug
    validateAndRemoveUser -SID "$forestSID-519" -DomainDNSName $forestDNS
}
