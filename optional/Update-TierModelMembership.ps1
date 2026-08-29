<#
.SYNOPSIS
    Reconciles Tier Model group membership and Authentication Policy assignments.

.DESCRIPTION
    A scheduled reconciliation script that keeps the Tier Model's Authentication
    Policy coverage current as accounts are created and machines join the domain.

    Group membership is ADDITIVE (never removes). Policy assignment is ENFORCING
    (assigns to non-excluded, clears from excluded). This script never modifies
    Authentication Policies, Silos, or SDDL - those are create-once via the deploy
    module.

    Designed to run as a local scheduled task on a Domain Controller in SYSTEM
    context. Requires the ActiveDirectory PowerShell module.

.PARAMETER All
    Run all 15 granular switches. This is the DEFAULT if no switches are specified.

.PARAMETER AllTier0
    Run all Tier 0 granular switches.

.PARAMETER AllTier1
    Run all Tier 1 granular switches.

.PARAMETER AllTier2
    Run all Tier 2 granular switches.

.PARAMETER Tier0Operators
    Reconcile Tier 0 Accounts OU users -> Tier0Operators group + Tier 0 auth policy.

.PARAMETER Tier0ServiceActt
    Reconcile Tier 0 Service Accounts OU -> Tier0ServiceAccounts group + Tier 0 auth policy.

.PARAMETER Tier0PawDevices
    Reconcile Tier 0 PAW Devices OU computers -> Tier0PAWDevices group.

.PARAMETER Tier0MemberServers
    Reconcile Tier 0 Member Servers OU computers (excluding Staging) -> Tier0MemberServers group.

.PARAMETER Tier0Staging
    Reconcile Tier 0 Server Staging OU computers -> Tier0MemberServers group.

.PARAMETER Tier1Operators
    Reconcile Tier 1 Accounts OU users -> Tier1Operators group + Tier 1 auth policy.

.PARAMETER Tier1ServiceActt
    Reconcile Tier 1 Service Accounts OU -> Tier1ServiceAccounts group + Tier 1 auth policy.

.PARAMETER Tier1PawDevices
    Reconcile Tier 1 PAW Devices OU computers -> Tier1PAWDevices group.

.PARAMETER Tier1MemberServers
    Reconcile Tier 1 Member Servers OU computers (excluding Staging) -> Tier1MemberServers group.

.PARAMETER Tier1Staging
    Reconcile Tier 1 Server Staging OU computers -> Tier1MemberServers group.

.PARAMETER Tier2Operators
    Reconcile Tier 2 Accounts OU users -> Tier2Operators group + Tier 2 auth policy.

.PARAMETER Tier2Eud
    Assign Tier 2 EUD Authentication Policy to Tier2LocalDeviceOperators members.

.PARAMETER Tier2ServiceActt
    Reconcile Tier 2 Service Accounts OU -> Tier2ServiceAccounts group + Tier 2 auth policy.

.PARAMETER Tier2PawDevices
    Reconcile Tier 2 PAW Devices OU computers -> Tier2PAWDevices group.

.PARAMETER Tier2EudDevices
    Reconcile Tier 2 End-User Devices OU computers -> Tier2EUDDevices group.

.PARAMETER ExclusionAttribute
    AD attribute to check for customer-defined exclusions. Objects where this
    attribute equals ExclusionValue are excluded from policy assignment.

.PARAMETER ExclusionValue
    Value that marks an object as excluded. Mandatory when ExclusionAttribute is set.

.PARAMETER EnableLogging
    Write a human-readable change log to %ProgramData%\TierModel\Logs. One file
    per run, 7-day default retention.

.PARAMETER EnableDebug
    Reserved for future use. Deep per-decision troubleshooting dump.

.PARAMETER LogEventID
    Reserved for future use. Windows Event Log heartbeat for monitoring integration.

.EXAMPLE
    .\Update-TierModelMembership.ps1
    Runs all 15 switches (default = -All).

.EXAMPLE
    .\Update-TierModelMembership.ps1 -Tier0Operators
    Reconciles only Tier 0 Operators.

.EXAMPLE
    .\Update-TierModelMembership.ps1 -AllTier0 -ExclusionAttribute adminDescription -ExclusionValue "TierModelExclude"
    Runs all Tier 0 switches with customer exclusion.

.EXAMPLE
    .\Update-TierModelMembership.ps1 -All -WhatIf
    Dry run - shows what changes would be made without modifying AD.

.NOTES
    Target: Windows PowerShell 5.1 + ActiveDirectory module on a Domain Controller.
    Execution: Local scheduled task, SYSTEM context. NOT SYSVOL/NETLOGON.
    Version: 1.3.0 (Milestones 1-4: Tier 0 + Tier 1 Operators, Service Accounts, Computers)
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # --- Tier-level aggregates ---
    [switch]$All,
    [switch]$AllTier0,
    [switch]$AllTier1,
    [switch]$AllTier2,

    # --- Tier 0 granular ---
    [switch]$Tier0Operators,
    [switch]$Tier0ServiceActt,
    [switch]$Tier0PawDevices,
    [switch]$Tier0MemberServers,
    [switch]$Tier0Staging,

    # --- Tier 1 granular ---
    [switch]$Tier1Operators,
    [switch]$Tier1ServiceActt,
    [switch]$Tier1PawDevices,
    [switch]$Tier1MemberServers,
    [switch]$Tier1Staging,

    # --- Tier 2 granular ---
    [switch]$Tier2Operators,
    [switch]$Tier2Eud,
    [switch]$Tier2ServiceActt,
    [switch]$Tier2PawDevices,
    [switch]$Tier2EudDevices,

    # --- Exclusion ---
    [string]$ExclusionAttribute,
    [string]$ExclusionValue,

    # --- Logging ---
    [switch]$EnableLogging,

    # --- Reserved (not yet implemented) ---
    [switch]$EnableDebug,
    [int]$LogEventID
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# SCRIPT-SCOPE STATE
# ============================================================================
$script:PreferredDc       = $null
$script:DomainDN          = $null
$script:BuiltInExclusions = $null  # HashSet of sAMAccountNames (case-insensitive)
$script:LogFilePath       = $null
$script:ConfigRoot        = $null

# ============================================================================
# LOGGING
# ============================================================================
function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to the log file (if enabled) and host output.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Information','Warning','Error')]
        [string]$Level = 'Information'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine   = "$timestamp [$Level] $Message"

    if ($script:LogFilePath) {
        Add-Content -Path $script:LogFilePath -Value $logLine -Encoding UTF8
    }

    switch ($Level) {
        'Error'       { Write-Host $logLine -ForegroundColor Red }
        'Warning'     { Write-Host $logLine -ForegroundColor Yellow }
        'Information' { Write-Host $logLine }
    }
}

function Initialize-Logging {
    <#
    .SYNOPSIS
        Sets up the log directory and file; prunes logs older than 7 days.
    #>
    if (-not $EnableLogging) { return }

    $logDir = Join-Path $env:ProgramData 'TierModel\Logs'
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFilePath = Join-Path $logDir "Update-TierModelMembership.$timestamp.log"

    # Prune logs older than 7 days
    $cutoff = (Get-Date).AddDays(-7)
    Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# PARAMETER RESOLUTION
# ============================================================================
function Resolve-ActiveSwitches {
    <#
    .SYNOPSIS
        Resolves the hierarchy of switches into an ordered list of action names.
    .DESCRIPTION
        If no switches are specified, treats as -All. -All expands to -AllTier0 +
        -AllTier1 + -AllTier2. Each -AllTierX expands to its 5 (or 5) granular
        switches. Returns an ordered list for mandatory execution sequence.
    #>

    $allGranular = @(
        'Tier0Operators','Tier0ServiceActt','Tier0PawDevices','Tier0MemberServers','Tier0Staging',
        'Tier1Operators','Tier1ServiceActt','Tier1PawDevices','Tier1MemberServers','Tier1Staging',
        'Tier2Operators','Tier2Eud','Tier2ServiceActt','Tier2PawDevices','Tier2EudDevices'
    )

    $tier0Granular = @('Tier0Operators','Tier0ServiceActt','Tier0PawDevices','Tier0MemberServers','Tier0Staging')
    $tier1Granular = @('Tier1Operators','Tier1ServiceActt','Tier1PawDevices','Tier1MemberServers','Tier1Staging')
    $tier2Granular = @('Tier2Operators','Tier2Eud','Tier2ServiceActt','Tier2PawDevices','Tier2EudDevices')

    # Check if any switch was explicitly provided
    $anyExplicit = $All.IsPresent -or $AllTier0.IsPresent -or $AllTier1.IsPresent -or $AllTier2.IsPresent
    foreach ($name in $allGranular) {
        $switchVar = Get-Variable -Name $name -ErrorAction SilentlyContinue
        if ($switchVar -and $switchVar.Value.IsPresent) {
            $anyExplicit = $true
            break
        }
    }

    # Default: no explicit switch => treat as -All
    if (-not $anyExplicit) {
        $All = [switch]$true
    }

    # Expand -All to tier-level aggregates
    if ($All.IsPresent) {
        $AllTier0 = [switch]$true
        $AllTier1 = [switch]$true
        $AllTier2 = [switch]$true
    }

    # Build the activated set (preserving mandatory execution order)
    $activated = New-Object System.Collections.Generic.List[string]

    foreach ($name in $allGranular) {
        # Check if explicitly set by the user
        $switchVar = Get-Variable -Name $name -ErrorAction SilentlyContinue
        $isExplicit = ($switchVar -and $switchVar.Value.IsPresent)

        # Check if activated by a tier-level aggregate
        $isTierActivated = $false
        if ($AllTier0.IsPresent -and $tier0Granular -contains $name) { $isTierActivated = $true }
        if ($AllTier1.IsPresent -and $tier1Granular -contains $name) { $isTierActivated = $true }
        if ($AllTier2.IsPresent -and $tier2Granular -contains $name) { $isTierActivated = $true }

        if ($isExplicit -or $isTierActivated) {
            if (-not $activated.Contains($name)) {
                $activated.Add($name)
            }
        }
    }

    return $activated.ToArray()
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================
function Assert-Preflight {
    <#
    .SYNOPSIS
        Fail-fast preflight: AD module, writable DC, DC identity, GC, ADWS.
    #>

    # (a) ActiveDirectory module
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        throw "PREFLIGHT FAILED: ActiveDirectory module is not available. $_"
    }

    # (b) Local machine is a Domain Controller and is WRITABLE (non-RODC)
    $dcObj = $null
    try {
        $localName = $env:COMPUTERNAME
        $dcObj = Get-ADDomainController -Identity $localName -ErrorAction Stop
    }
    catch {
        throw "PREFLIGHT FAILED: This machine ('$localName') is not a Domain Controller or cannot be resolved as one. $_"
    }

    if ($dcObj.IsReadOnly) {
        throw "PREFLIGHT FAILED: This Domain Controller is an RODC (Read-Only). The script requires a writable DC."
    }

    # (c) Resolve the DC's REAL dNSHostName (not constructed from env vars)
    $script:PreferredDc = $dcObj.HostName
    if ([string]::IsNullOrWhiteSpace($script:PreferredDc)) {
        throw "PREFLIGHT FAILED: Could not resolve dNSHostName for local DC '$localName'."
    }

    # (d) Global Catalog check (deployment preference; usually a no-op since DCs are GCs)
    # NOTE: In a single-domain forest this is a deployment hygiene check, not a strict
    # correctness requirement. However, Joel requested it as a preflight gate.
    if (-not $dcObj.IsGlobalCatalog) {
        throw "PREFLIGHT FAILED: This Domain Controller ('$($script:PreferredDc)') is not a Global Catalog. " +
              "The Tier Model reconciliation script requires a GC-enabled DC. " +
              "This is a deployment preference - DCs are typically GCs by default."
    }

    # (e) ADWS reachable - probe with Get-ADDomain
    try {
        $domainInfo = Get-ADDomain -Server $script:PreferredDc -ErrorAction Stop
        $script:DomainDN = $domainInfo.DistinguishedName
    }
    catch {
        throw "PREFLIGHT FAILED: Cannot reach Active Directory Web Services on '$($script:PreferredDc)'. $_"
    }

    Write-Log -Message "Preflight passed. DC: $($script:PreferredDc)  Domain DN: $($script:DomainDN)"
}

# ============================================================================
# CONFIG LOADING
# ============================================================================
function Import-TierModelConfig {
    <#
    .SYNOPSIS
        Loads the 4 config JSON files and resolves the {{DOMAIN_DN}} token.
    .DESCRIPTION
        Lightweight standalone config loader (no dependency on the TierModel module).
        Returns a hashtable with keys: OUs, Groups, AuthSilos, Users.
    #>

    # Resolve config root relative to this script's location
    $scriptDir = Split-Path -Parent $PSCommandPath
    $repoRoot  = Split-Path -Parent $scriptDir
    $script:ConfigRoot = Join-Path $repoRoot 'config'

    $configFiles = @{
        OUs       = 'tiermodel-ous.json'
        Groups    = 'tiermodel-groups.json'
        AuthSilos = 'tiermodel-authsilos.json'
        Users     = 'tiermodel-users.json'
    }

    $config = @{}
    foreach ($key in $configFiles.Keys) {
        $filePath = Join-Path $script:ConfigRoot $configFiles[$key]
        if (-not (Test-Path $filePath)) {
            throw "CONFIG ERROR: Required config file not found: $filePath"
        }
        try {
            $raw = Get-Content -Path $filePath -Raw -Encoding UTF8
            $raw = $raw -replace '\{\{DOMAIN_DN\}\}', $script:DomainDN
            $config[$key] = ConvertFrom-Json $raw
        }
        catch {
            throw "CONFIG ERROR: Failed to parse '$filePath'. $_"
        }
    }

    return $config
}

function Resolve-OuDn {
    <#
    .SYNOPSIS
        Resolves the full DN for a named OU from the config OU list.
    .DESCRIPTION
        Finds the OU entry by name, then constructs the DN from its path.
        Paths in config may be the domain DN (from {{DOMAIN_DN}} replacement)
        or a relative OU chain (e.g., "OU=Tier 0,OU=Tier Model Administration").
        Relative paths are appended with the domain DN to form a complete DN.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OuName,

        [Parameter(Mandatory)]
        [object]$OuConfig
    )

    $entry = $OuConfig.organizationUnits | Where-Object { $_.name -eq $OuName }
    if (-not $entry) {
        throw "CONFIG ERROR: OU '$OuName' not found in tiermodel-ous.json."
    }

    $path = $entry.path

    # If path already contains the domain DN (starts with DC=), it is a full path.
    # Otherwise, it is a relative OU chain that needs the domain DN appended.
    if ($path -like 'DC=*') {
        $dn = "OU=$OuName,$path"
    }
    else {
        $dn = "OU=$OuName,$path,$($script:DomainDN)"
    }

    return $dn
}

function Resolve-GroupSam {
    <#
    .SYNOPSIS
        Resolves the sAMAccountName for a group by its display name from config.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,

        [Parameter(Mandatory)]
        [object]$GroupConfig
    )

    $entry = $GroupConfig.groups | Where-Object { $_.name -eq $GroupName }
    if (-not $entry) {
        throw "CONFIG ERROR: Group '$GroupName' not found in tiermodel-groups.json."
    }

    return $entry.samaccountname
}

function Resolve-PolicyName {
    <#
    .SYNOPSIS
        Resolves and validates an Authentication Policy name from config.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PolicyName,

        [Parameter(Mandatory)]
        [object]$AuthSiloConfig
    )

    $entry = $AuthSiloConfig.authenticationPolicies | Where-Object { $_.name -eq $PolicyName }
    if (-not $entry) {
        throw "CONFIG ERROR: Authentication Policy '$PolicyName' not found in tiermodel-authsilos.json."
    }

    return $entry.name
}

# ============================================================================
# EXCLUSION PREDICATES
# ============================================================================
function Initialize-BuiltInExclusions {
    <#
    .SYNOPSIS
        Builds the HashSet of built-in excluded sAMAccountNames from config.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$UsersConfig
    )

    $script:BuiltInExclusions = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($user in $UsersConfig.users) {
        [void]$script:BuiltInExclusions.Add($user.samAccountName)
    }

    Write-Log -Message "Built-in exclusions loaded: $($script:BuiltInExclusions.Count) accounts ($($script:BuiltInExclusions -join ', '))"
}

function Test-IsBuiltInExcluded {
    <#
    .SYNOPSIS
        Returns $true if the sAMAccountName is a built-in excluded account.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName
    )

    return $script:BuiltInExclusions.Contains($SamAccountName)
}

function Test-IsCustomerExcluded {
    <#
    .SYNOPSIS
        Returns $true if the AD object has the customer exclusion attribute set
        to the exclusion value.
    #>
    param(
        [Parameter(Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADObject]$AdObject
    )

    if ([string]::IsNullOrEmpty($ExclusionAttribute)) {
        return $false
    }

    $val = $AdObject.$ExclusionAttribute
    if ($null -eq $val) { return $false }

    return ($val -eq $ExclusionValue)
}

function Test-IsExcludedFromPolicy {
    <#
    .SYNOPSIS
        Universal exclusion predicate for policy assignment. Returns $true if
        the account should NOT receive an auth policy (built-in OR customer excluded).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADObject]$AdObject
    )

    if (Test-IsBuiltInExcluded -SamAccountName $SamAccountName) { return $true }
    if (Test-IsCustomerExcluded -AdObject $AdObject) { return $true }
    return $false
}

# ============================================================================
# TYPE-AGNOSTIC AUTH POLICY HELPERS
# ============================================================================
# These use Set-ADObject to write msDS-AssignedAuthNPolicy directly, which
# works uniformly for user, gMSA, dMSA, and sMSA objects (unlike Set-ADUser
# -AuthenticationPolicy, which only works on user objects).

function Set-TmObjectAuthPolicy {
    <#
    .SYNOPSIS
        Assigns an authentication policy to any AD object via msDS-AssignedAuthNPolicy.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ObjectDn,

        [Parameter(Mandatory)]
        [string]$PolicyDn
    )

    Set-ADObject -Identity $ObjectDn `
        -Replace @{ 'msDS-AssignedAuthNPolicy' = $PolicyDn } `
        -Server $script:PreferredDc -ErrorAction Stop
}

function Clear-TmObjectAuthPolicy {
    <#
    .SYNOPSIS
        Removes the authentication policy from any AD object via msDS-AssignedAuthNPolicy.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ObjectDn
    )

    Set-ADObject -Identity $ObjectDn `
        -Clear 'msDS-AssignedAuthNPolicy' `
        -Server $script:PreferredDc -ErrorAction Stop
}

# ============================================================================
# BUILT-IN EXCLUSION ENFORCEMENT (Phase 1)
# ============================================================================
function Invoke-BuiltInExclusionEnforcement {
    <#
    .SYNOPSIS
        Phase 1: Ensures the 3 domain-join service accounts have NO auth policy.
        Runs every execution, regardless of which switches are active.
    #>

    Write-Log -Message '--- Phase 1: Built-in exclusion enforcement ---'

    foreach ($sam in $script:BuiltInExclusions) {
        $acct = $null
        try {
            $acct = Get-ADUser -Identity $sam -Properties 'msDS-AssignedAuthNPolicy' `
                        -Server $script:PreferredDc -ErrorAction Stop
        }
        catch {
            # The built-in account may not exist yet (pre-deploy). That is fine.
            Write-Log -Message "Built-in exclusion: '$sam' not found in AD (may not be deployed yet). Skipping." -Level Warning
            continue
        }

        $currentPolicy = $acct.'msDS-AssignedAuthNPolicy'
        if (-not [string]::IsNullOrEmpty($currentPolicy)) {
            if ($PSCmdlet.ShouldProcess($sam, "Remove Authentication Policy '$currentPolicy'")) {
                Clear-TmObjectAuthPolicy -ObjectDn $acct.DistinguishedName
                Write-Log -Message "Removed policy '$currentPolicy' from built-in excluded account '$sam'"
            }
        }
        else {
            Write-Log -Message "Built-in exclusion: '$sam' has no policy assigned (correct)."
        }
    }
}

# ============================================================================
# REUSABLE PER-TIER RECONCILIATION FUNCTION
# ============================================================================
function Invoke-TierReconciliation {
    <#
    .SYNOPSIS
        Core reconciliation logic - reused by every tier/switch with different parameters.

    .DESCRIPTION
        Enumerates objects from a source OU, assigns an authentication policy (if
        applicable), and adds objects to a target group. The function is parameterized
        so that Tier 0/1/2 Operators, ServiceAccounts, etc. all call this same function
        with tier-specific values.

        FAIL-CLOSED ORDERING: policy is assigned FIRST, then group membership is added.
        If policy assignment fails, the account is NOT added to the group.

    .PARAMETER SwitchName
        Display name for logging (e.g., 'Tier0Operators').

    .PARAMETER SourceOuDn
        Distinguished Name of the source OU to enumerate.

    .PARAMETER TargetGroupSam
        sAMAccountName of the target group.

    .PARAMETER PolicyName
        Name of the Authentication Policy to assign. $null if no policy assignment.

    .PARAMETER ObjectFilter
        LDAP filter for objects to enumerate. Default: '(objectClass=user)' for accounts.

    .PARAMETER SearchScope
        AD search scope. Default: Subtree.

    .PARAMETER ApplyExclusionToGroup
        If $true, customer/built-in exclusions also skip the group add (for ServiceAccounts).
        If $false, all enumerated objects are added to the group regardless of exclusion
        (for Operators - all tier users are operators).

    .PARAMETER ExcludeChildOuDn
        DN of a child OU to exclude from enumeration (e.g., Staging OU under Member Servers).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter(Mandatory)]
        [string]$SourceOuDn,

        [Parameter(Mandatory)]
        [string]$TargetGroupSam,

        [string]$PolicyName,

        [string]$ObjectFilter = '(objectClass=user)',

        [string]$SearchScope = 'Subtree',

        [bool]$ApplyExclusionToGroup = $false,

        [string]$ExcludeChildOuDn
    )

    Write-Log -Message "--- $SwitchName ---"

    # Validate source OU exists in AD
    try {
        Get-ADOrganizationalUnit -Identity $SourceOuDn -Server $script:PreferredDc -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$SwitchName FAILED: Source OU '$SourceOuDn' does not exist in AD. $_"
    }

    # Validate target group exists in AD
    $targetGroup = $null
    try {
        $targetGroup = Get-ADGroup -Identity $TargetGroupSam -Server $script:PreferredDc -ErrorAction Stop
    }
    catch {
        throw "$SwitchName FAILED: Target group '$TargetGroupSam' does not exist in AD. $_"
    }

    # Validate policy exists in AD and resolve its DN (for type-agnostic assignment)
    $policyDn = $null
    if ($PolicyName) {
        try {
            $configNC = (Get-ADRootDSE -Server $script:PreferredDc).configurationNamingContext
            $searchBase = "CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,$configNC"
            $policyObjs = @(Get-ADObject -Filter "name -eq '$PolicyName'" `
                -SearchBase $searchBase `
                -Server $script:PreferredDc -ErrorAction Stop)
            if ($policyObjs.Count -eq 0) {
                throw "Authentication Policy '$PolicyName' not found."
            }
            $policyDn = $policyObjs[0].DistinguishedName
        }
        catch {
            throw "$SwitchName FAILED: Authentication Policy '$PolicyName' does not exist in AD. $_"
        }
    }

    # Build properties list for the AD query
    $propsToFetch = @('sAMAccountName', 'DistinguishedName')
    if ($PolicyName) {
        $propsToFetch += 'msDS-AssignedAuthNPolicy'
    }
    if (-not [string]::IsNullOrEmpty($ExclusionAttribute)) {
        $propsToFetch += $ExclusionAttribute
    }

    # Enumerate source OU
    $objects = @(Get-ADObject -LDAPFilter $ObjectFilter -SearchBase $SourceOuDn `
                    -SearchScope $SearchScope -Properties $propsToFetch `
                    -Server $script:PreferredDc -ErrorAction Stop)

    # Post-filter: exclude child OU if specified
    if (-not [string]::IsNullOrEmpty($ExcludeChildOuDn)) {
        $excludeSuffix = $ExcludeChildOuDn
        $objects = @($objects | Where-Object {
            -not $_.DistinguishedName.EndsWith(",$excludeSuffix", [System.StringComparison]::OrdinalIgnoreCase) -and
            -not $_.DistinguishedName.Equals($excludeSuffix, [System.StringComparison]::OrdinalIgnoreCase)
        })
    }

    Write-Log -Message "$SwitchName : Enumerated $($objects.Count) objects from '$SourceOuDn'"

    # Cache current group membership as a HashSet for O(1) lookups
    $currentMembers = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    try {
        $members = @(Get-ADGroupMember -Identity $TargetGroupSam -Server $script:PreferredDc -ErrorAction Stop)
        foreach ($m in $members) {
            [void]$currentMembers.Add($m.distinguishedName)
        }
    }
    catch {
        # Group may be empty; Get-ADGroupMember may return nothing or error
        Write-Log -Message "$SwitchName : Could not read current members of '$TargetGroupSam' (may be empty). $_" -Level Warning
    }

    # Counters
    $counters = @{
        Scanned        = $objects.Count
        PolicyAssigned = 0
        PolicyCleared  = 0
        GroupAdded     = 0
        Excluded       = 0
        AlreadyCurrent = 0
    }

    foreach ($obj in $objects) {
        $sam = $obj.sAMAccountName
        $madeChange = $false

        # Universal built-in exclusion filter (applies to ALL phases)
        $isBuiltInExcl   = Test-IsBuiltInExcluded -SamAccountName $sam
        $isCustomerExcl  = Test-IsCustomerExcluded -AdObject $obj
        $isPolicyExcluded = $isBuiltInExcl -or $isCustomerExcl

        # ----------------------------------------------------------------
        # POLICY ASSIGNMENT (fail-closed: policy first, then group)
        # ----------------------------------------------------------------
        if ($PolicyName) {
            $currentPol = $obj.'msDS-AssignedAuthNPolicy'
            # Normalize: AD stores the DN; extract the CN for comparison
            $currentPolName = $null
            if (-not [string]::IsNullOrEmpty($currentPol)) {
                if ($currentPol -match '^CN=(.+?),') {
                    $currentPolName = $Matches[1]
                }
                else {
                    $currentPolName = $currentPol
                }
            }

            if ($isPolicyExcluded) {
                $counters.Excluded++

                # Clear policy from excluded users who currently have one
                if (-not [string]::IsNullOrEmpty($currentPol)) {
                    if ($PSCmdlet.ShouldProcess($sam, "Clear policy '$currentPolName' (excluded)")) {
                        Clear-TmObjectAuthPolicy -ObjectDn $obj.DistinguishedName
                        Write-Log -Message "Cleared policy '$currentPolName' from excluded account '$sam'"
                        $counters.PolicyCleared++
                        $madeChange = $true
                    }
                }
            }
            else {
                if ($currentPolName -ne $PolicyName) {
                    if ($PSCmdlet.ShouldProcess($sam, "Assign Authentication Policy '$PolicyName'")) {
                        Set-TmObjectAuthPolicy -ObjectDn $obj.DistinguishedName -PolicyDn $policyDn
                        Write-Log -Message "Assigned policy '$PolicyName' to '$sam'"
                        $counters.PolicyAssigned++
                        $madeChange = $true
                    }
                }
            }
        }

        # ----------------------------------------------------------------
        # GROUP MEMBERSHIP (only after policy succeeds or no policy needed)
        # ----------------------------------------------------------------
        $skipGroup = $false
        if ($ApplyExclusionToGroup -and ($isBuiltInExcl -or $isCustomerExcl)) {
            $skipGroup = $true
        }

        if (-not $skipGroup) {
            if (-not $currentMembers.Contains($obj.DistinguishedName)) {
                if ($PSCmdlet.ShouldProcess($sam, "Add to group '$TargetGroupSam'")) {
                    Add-ADGroupMember -Identity $TargetGroupSam -Members $obj.DistinguishedName `
                        -Server $script:PreferredDc -ErrorAction Stop
                    [void]$currentMembers.Add($obj.DistinguishedName)
                    Write-Log -Message "Added '$sam' to group '$TargetGroupSam'"
                    $counters.GroupAdded++
                    $madeChange = $true
                }
            }
        }

        if (-not $madeChange) {
            $counters.AlreadyCurrent++
        }
    }

    # Summary for this switch
    $summary = "$SwitchName : Scanned=$($counters.Scanned) " +
               "GroupAdded=$($counters.GroupAdded) " +
               "PolicyAssigned=$($counters.PolicyAssigned) " +
               "PolicyCleared=$($counters.PolicyCleared) " +
               "Excluded=$($counters.Excluded) " +
               "AlreadyCurrent=$($counters.AlreadyCurrent)"
    Write-Log -Message $summary

    return [PSCustomObject]$counters
}

# ============================================================================
# TIER-SPECIFIC DISPATCH
# ============================================================================
function Invoke-Tier0Operators {
    <#
    .SYNOPSIS
        Tier 0 Operators: Tier 0 Accounts OU users -> Tier0Operators + Tier 0 policy.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 0 Accounts' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 0 Operators' -GroupConfig $Config.Groups
    $policyName     = Resolve-PolicyName -PolicyName '*- Tier 0 Authentication Policy' -AuthSiloConfig $Config.AuthSilos

    # Validate all resolved values exist in AD (Invoke-TierReconciliation does this too)
    Invoke-TierReconciliation `
        -SwitchName        'Tier0Operators' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $policyName `
        -ObjectFilter      '(objectClass=user)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false  # All Tier 0 users are operators - exclusion does NOT apply to group
}

# ============================================================================
# STUBS - Future milestones (Tier 0 devices, Tier 1, Tier 2)
# ============================================================================

function Invoke-Tier0ServiceActt {
    <#
    .SYNOPSIS
        Tier 0 Service Accounts: Tier 0 Service Accounts OU (user + gMSA + dMSA + sMSA)
        -> Tier0ServiceAccounts group + Tier 0 auth policy.
        Exclusion applies to BOTH group and policy.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 0 Service Accounts' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 0 Service Accounts' -GroupConfig $Config.Groups
    $policyName     = Resolve-PolicyName -PolicyName '*- Tier 0 Authentication Policy' -AuthSiloConfig $Config.AuthSilos

    # LDAP filter: user (with person category to exclude computers) + gMSA + dMSA + sMSA.
    # gMSA/dMSA/sMSA classes may be absent in some environments - the filter simply
    # returns zero results for absent classes (safe). Do NOT use Get-ADServiceAccount.
    $svcAcctFilter = '(|(&(objectClass=user)(objectCategory=person))(objectClass=msDS-GroupManagedServiceAccount)(objectClass=msDS-DelegatedManagedServiceAccount)(objectClass=msDS-ManagedServiceAccount))'

    Invoke-TierReconciliation `
        -SwitchName        'Tier0ServiceActt' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $policyName `
        -ObjectFilter      $svcAcctFilter `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $true  # Exclusion applies to BOTH group and policy for Service Accounts
}

function Invoke-Tier0PawDevices {
    <#
    .SYNOPSIS
        Tier 0 PAW Devices: Tier 0 PAW Devices OU computers -> Tier0PAWDevices group.
        No policy assignment (computers get policy via device group SDDL).
        No exclusions (exclusions never apply to computers).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 0 PAW Devices' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 0 PAW Devices' -GroupConfig $Config.Groups

    Invoke-TierReconciliation `
        -SwitchName        'Tier0PawDevices' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false
}

function Invoke-Tier0MemberServers {
    <#
    .SYNOPSIS
        Tier 0 Member Servers: computers in the Tier 0 Member Servers OU
        (subtree) -> Tier0MemberServers group, EXCLUDING the Tier 0 Server
        Staging child OU (handled by Invoke-Tier0Staging).
        No policy assignment. No exclusions.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 0 Member Servers' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 0 Member Servers' -GroupConfig $Config.Groups
    $stagingOuDn    = Resolve-OuDn -OuName 'Tier 0 Server Staging' -OuConfig $Config.OUs

    Invoke-TierReconciliation `
        -SwitchName        'Tier0MemberServers' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false `
        -ExcludeChildOuDn  $stagingOuDn
}

function Invoke-Tier0Staging {
    <#
    .SYNOPSIS
        Tier 0 Staging: computers in the Tier 0 Server Staging OU (subtree)
        -> Tier0MemberServers group (same target group as -Tier0MemberServers).
        No policy assignment. No exclusions.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 0 Server Staging' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 0 Member Servers' -GroupConfig $Config.Groups

    Invoke-TierReconciliation `
        -SwitchName        'Tier0Staging' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false
}

function Invoke-Tier1Operators {
    <#
    .SYNOPSIS
        Tier 1 Operators: Tier 1 Accounts OU users -> Tier1Operators + Tier 1 policy.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 1 Accounts' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 1 Operators' -GroupConfig $Config.Groups
    $policyName     = Resolve-PolicyName -PolicyName '*- Tier 1 Authentication Policy' -AuthSiloConfig $Config.AuthSilos

    Invoke-TierReconciliation `
        -SwitchName        'Tier1Operators' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $policyName `
        -ObjectFilter      '(objectClass=user)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false  # All Tier 1 users are operators - exclusion does NOT apply to group
}

function Invoke-Tier1ServiceActt {
    <#
    .SYNOPSIS
        Tier 1 Service Accounts: Tier 1 Service Accounts OU (user + gMSA + dMSA + sMSA)
        -> Tier1ServiceAccounts group + Tier 1 auth policy.
        Exclusion applies to BOTH group and policy.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 1 Service Accounts' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 1 Service Accounts' -GroupConfig $Config.Groups
    $policyName     = Resolve-PolicyName -PolicyName '*- Tier 1 Authentication Policy' -AuthSiloConfig $Config.AuthSilos

    $svcAcctFilter = '(|(&(objectClass=user)(objectCategory=person))(objectClass=msDS-GroupManagedServiceAccount)(objectClass=msDS-DelegatedManagedServiceAccount)(objectClass=msDS-ManagedServiceAccount))'

    Invoke-TierReconciliation `
        -SwitchName        'Tier1ServiceActt' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $policyName `
        -ObjectFilter      $svcAcctFilter `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $true  # Exclusion applies to BOTH group and policy for Service Accounts
}

function Invoke-Tier1PawDevices {
    <#
    .SYNOPSIS
        Tier 1 PAW Devices: Tier 1 PAW Devices OU computers -> Tier1PAWDevices group.
        No policy assignment (computers get policy via device group SDDL).
        No exclusions (exclusions never apply to computers).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 1 PAW Devices' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 1 PAW Devices' -GroupConfig $Config.Groups

    Invoke-TierReconciliation `
        -SwitchName        'Tier1PawDevices' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false
}

function Invoke-Tier1MemberServers {
    <#
    .SYNOPSIS
        Tier 1 Member Servers: computers in the Tier 1 Member Servers OU
        (subtree) -> Tier1MemberServers group, EXCLUDING the Tier 1 Server
        Staging child OU (handled by Invoke-Tier1Staging).
        No policy assignment. No exclusions.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 1 Member Servers' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 1 Member Servers' -GroupConfig $Config.Groups
    $stagingOuDn    = Resolve-OuDn -OuName 'Tier 1 Server Staging' -OuConfig $Config.OUs

    Invoke-TierReconciliation `
        -SwitchName        'Tier1MemberServers' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false `
        -ExcludeChildOuDn  $stagingOuDn
}

function Invoke-Tier1Staging {
    <#
    .SYNOPSIS
        Tier 1 Staging: computers in the Tier 1 Server Staging OU (subtree)
        -> Tier1MemberServers group (same target group as -Tier1MemberServers).
        No policy assignment. No exclusions.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 1 Server Staging' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 1 Member Servers' -GroupConfig $Config.Groups

    Invoke-TierReconciliation `
        -SwitchName        'Tier1Staging' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false
}

function Invoke-Tier2Operators {
    # STUB: Milestone 4 - Tier 2 Accounts OU; Tier2LocalDeviceOperators disambiguation
    param([hashtable]$Config)
    Write-Log -Message 'Tier2Operators: NOT YET IMPLEMENTED (stub)' -Level Warning
}

function Invoke-Tier2Eud {
    # STUB: Milestone 4 - assigns EUD policy to Tier2LocalDeviceOperators members (not in Tier2Operators)
    param([hashtable]$Config)
    Write-Log -Message 'Tier2Eud: NOT YET IMPLEMENTED (stub)' -Level Warning
}

function Invoke-Tier2ServiceActt {
    # STUB: Milestone 4
    param([hashtable]$Config)
    Write-Log -Message 'Tier2ServiceActt: NOT YET IMPLEMENTED (stub)' -Level Warning
}

function Invoke-Tier2PawDevices {
    # STUB: Milestone 4
    param([hashtable]$Config)
    Write-Log -Message 'Tier2PawDevices: NOT YET IMPLEMENTED (stub)' -Level Warning
}

function Invoke-Tier2EudDevices {
    # STUB: Milestone 4
    param([hashtable]$Config)
    Write-Log -Message 'Tier2EudDevices: NOT YET IMPLEMENTED (stub)' -Level Warning
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
try {
    # Validate exclusion parameter pairing
    if (-not [string]::IsNullOrEmpty($ExclusionAttribute) -and [string]::IsNullOrEmpty($ExclusionValue)) {
        throw 'PARAMETER ERROR: -ExclusionValue is mandatory when -ExclusionAttribute is specified.'
    }

    # Reserved parameter warnings
    if ($EnableDebug) {
        Write-Warning '-EnableDebug is reserved for future use and is not yet implemented.'
    }
    if ($LogEventID -gt 0) {
        Write-Warning '-LogEventID is reserved for future use and is not yet implemented.'
    }

    # Initialize logging (creates dir/file if -EnableLogging)
    Initialize-Logging

    Write-Log -Message '============================================================'
    Write-Log -Message 'Update-TierModelMembership - Starting'
    Write-Log -Message '============================================================'

    # Preflight
    Assert-Preflight

    # Load config
    $config = Import-TierModelConfig

    # Initialize built-in exclusions
    Initialize-BuiltInExclusions -UsersConfig $config.Users

    # Resolve active switches
    $activeSwitches = Resolve-ActiveSwitches
    Write-Log -Message "Active switches: $($activeSwitches -join ', ')"

    # Phase 1: Built-in exclusion enforcement (always runs)
    Invoke-BuiltInExclusionEnforcement

    # Phase 2: Reconciliation - dispatch in mandatory execution order
    $switchDispatch = @{
        'Tier0Operators'     = { Invoke-Tier0Operators -Config $config }
        'Tier0ServiceActt'   = { Invoke-Tier0ServiceActt -Config $config }
        'Tier0PawDevices'    = { Invoke-Tier0PawDevices -Config $config }
        'Tier0MemberServers' = { Invoke-Tier0MemberServers -Config $config }
        'Tier0Staging'       = { Invoke-Tier0Staging -Config $config }
        'Tier1Operators'     = { Invoke-Tier1Operators -Config $config }
        'Tier1ServiceActt'   = { Invoke-Tier1ServiceActt -Config $config }
        'Tier1PawDevices'    = { Invoke-Tier1PawDevices -Config $config }
        'Tier1MemberServers' = { Invoke-Tier1MemberServers -Config $config }
        'Tier1Staging'       = { Invoke-Tier1Staging -Config $config }
        'Tier2Operators'     = { Invoke-Tier2Operators -Config $config }
        'Tier2Eud'           = { Invoke-Tier2Eud -Config $config }
        'Tier2ServiceActt'   = { Invoke-Tier2ServiceActt -Config $config }
        'Tier2PawDevices'    = { Invoke-Tier2PawDevices -Config $config }
        'Tier2EudDevices'    = { Invoke-Tier2EudDevices -Config $config }
    }

    foreach ($switch in $activeSwitches) {
        $action = $switchDispatch[$switch]
        if ($action) {
            & $action
        }
        else {
            Write-Log -Message "No dispatch found for switch '$switch'" -Level Warning
        }
    }

    Write-Log -Message '============================================================'
    Write-Log -Message 'Update-TierModelMembership - Completed successfully'
    Write-Log -Message '============================================================'
}
catch {
    $errMsg = "FATAL ERROR: $($_.Exception.Message)"
    if ($script:LogFilePath) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $script:LogFilePath -Value "$timestamp [Error] $errMsg" -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    Write-Host $errMsg -ForegroundColor Red
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
}
