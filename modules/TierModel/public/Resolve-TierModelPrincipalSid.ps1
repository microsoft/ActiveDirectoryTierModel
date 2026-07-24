# TierModel SID Resolution Module
# Handles resolution of security principals to SIDs for GPO editing

function Resolve-TierModelPrincipalSid {
    <#
    .SYNOPSIS
    Resolves security principal names to SIDs with caching
    
    .DESCRIPTION
    Converts security principal names (users, groups, well-known principals) to SIDs.
    Supports caching for performance and handles well-known SIDs directly.
    
    Special handling for "Administrator" account:
    - When resolving "Administrator", first attempts to find the built-in Administrator account (RID 500)
    - This handles scenarios where the Administrator account has been renamed (e.g., to "Root")
    - Returns the actual SID even if the account name has changed
    - Protects against honeypot accounts that may have taken the "Administrator" name
    
    .PARAMETER Principal
    The security principal name to resolve (e.g., "Domain Admins", "BUILTIN\Users", "Administrator", "S-1-5-32-544")
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations
    
    .PARAMETER UseCache
    Whether to use the SID cache for resolved principals (default: $true)
    
    .PARAMETER CorrelationId
    Tracking ID for logging correlation
    
    .EXAMPLE
    $sid = Resolve-TierModelPrincipalSid -Principal "Domain Admins"
    
    .EXAMPLE
    $sid = Resolve-TierModelPrincipalSid -Principal "BUILTIN\Administrators" -UseCache $false
    
    .EXAMPLE
    $sid = Resolve-TierModelPrincipalSid -Principal "Administrator"
    # Returns the SID for the built-in Administrator account (RID 500) even if renamed
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Principal,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [bool]$UseCache = $true,
        
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )
    
    begin {
        Write-Verbose "Starting SID resolution for principals (CorrelationId: $CorrelationId)"
        
        # Initialize cache if not exists
        if (-not $script:SidCache) {
            $script:SidCache = @{}
        }
    }
    
    process {
        Write-Verbose "Resolving SID for principal: '$Principal' (CorrelationId: $CorrelationId)"
        
        # Check if already a SID
        if ($Principal -match '^S-\d+-\d+') {
            Write-Verbose "Principal is already a SID: $Principal (CorrelationId: $CorrelationId)"
            return [PSCustomObject]@{
                Principal = $Principal
                Sid = $Principal
                Source = "DirectSID"
                Cached = $false
                Success = $true
                Error = $null
            }
        }
        
        # Special handling for "Administrator" account - bypass cache since it's domain-specific
        if ($Principal -ieq "Administrator") {
            try {
                # Get the domain SID from specified domain controller
                $domainSid = (Get-ADDomain -Server $DomainController).DomainSID.Value
                
                # Build the Administrator SID (RID 500)
                $adminSid = "$domainSid-500"
                
                # Look up the renamed built-in Administrator account by SID
                $adminUser = Get-ADUser -Identity $adminSid -Server $DomainController -ErrorAction Stop
                
                Write-Verbose "Found built-in Administrator account (RID 500) with current name: '$($adminUser.SamAccountName)' (CorrelationId: $CorrelationId)"
                
                return @{
                    Principal = $Principal
                    Sid = $adminUser.SID.Value
                    Source = "ADUser-RID500"
                    Success = $true
                    Error = $null
                    ActualName = $adminUser.SamAccountName
                    Cached = $false
                }
            } catch {
                Write-Verbose "Failed to resolve Administrator account via RID 500: $($_.Exception.Message) (CorrelationId: $CorrelationId)"
                # Continue to normal resolution if RID 500 lookup fails
            }
        }
        
        # Check cache first (except for Administrator which is handled above)
        if ($UseCache -and $script:SidCache.ContainsKey($Principal)) {
            Write-Verbose "Found cached SID for '$Principal' (CorrelationId: $CorrelationId)"
            $cachedResult = $script:SidCache[$Principal]
            return [PSCustomObject]@{
                Principal = $Principal
                Sid = $cachedResult.Sid
                Source = $cachedResult.Source
                Cached = $true
                Success = $cachedResult.Success
                Error = $cachedResult.Error
            }
        }
        
        # Try well-known SIDs first
        $wellKnownSid = Get-WellKnownSid -Principal $Principal
        if ($wellKnownSid) {
            Write-Verbose "Resolved well-known SID for '$Principal': $wellKnownSid (CorrelationId: $CorrelationId)"
            $result = @{
                Sid = $wellKnownSid
                Source = "WellKnown" 
                Success = $true
                Error = $null
            }
            
            if ($UseCache) {
                $script:SidCache[$Principal] = $result
            }
            
            return [PSCustomObject]@{
                Principal = $Principal
                Sid = $wellKnownSid
                Source = "WellKnown"
                Cached = $false
                Success = $true
                Error = $null
            }
        }
        
        # Try domain-relative well-known RIDs (language-independent).
        # Groups like "Domain Admins" have localized names in non-English ADs
        # (e.g. "Domänen-Admins" in German), but their RID is fixed. Resolving
        # via <DomainSID>-<RID> works in every AD language and also protects
        # against spoofed groups that reuse a well-known English name.
        $ridSid = $null
        try {
            $ridSid = Get-WellKnownDomainRidSid -Principal $Principal -DomainController $DomainController
        }
        catch {
            Write-Verbose "Domain RID resolution unavailable for '$Principal': $($_.Exception.Message) (CorrelationId: $CorrelationId)"
        }
        if ($ridSid) {
            Write-Verbose "Resolved well-known domain RID SID for '$Principal': $ridSid (CorrelationId: $CorrelationId)"
            $result = @{
                Sid = $ridSid
                Source = "WellKnownRid"
                Success = $true
                Error = $null
            }

            if ($UseCache) {
                $script:SidCache[$Principal] = $result
            }

            return [PSCustomObject]@{
                Principal = $Principal
                Sid = $ridSid
                Source = "WellKnownRid"
                Cached = $false
                Success = $true
                Error = $null
            }
        }

        # Try AD resolution
        try {
            $adResult = Resolve-ADPrincipalSid -Principal $Principal -DomainController $DomainController -CorrelationId $CorrelationId
            
            if ($adResult.Success) {
                Write-Verbose "Resolved AD SID for '$Principal': $($adResult.Sid) (CorrelationId: $CorrelationId)"
                
                # Special logging for Administrator account resolution
                if ($Principal -ieq "Administrator" -and $adResult.PSObject.Properties.Name -contains 'ActualName') {
                    Write-Verbose "Administrator account resolved to actual account name: '$($adResult.ActualName)' (CorrelationId: $CorrelationId)"
                }
                
                if ($UseCache) {
                    $script:SidCache[$Principal] = @{
                        Sid = $adResult.Sid
                        Source = $adResult.Source
                        Success = $true
                        Error = $null
                    }
                }
                
                # Build result object with optional ActualName property
                $resultObj = [PSCustomObject]@{
                    Principal = $Principal
                    Sid = $adResult.Sid
                    Source = $adResult.Source
                    Cached = $false
                    Success = $true
                    Error = $null
                }
                
                # Add ActualName if it exists (for renamed Administrator account)
                if ($adResult.PSObject.Properties.Name -contains 'ActualName') {
                    $resultObj | Add-Member -NotePropertyName 'ActualName' -NotePropertyValue $adResult.ActualName -Force
                }
                
                return $resultObj
            }
            else {
                Write-Warning "Failed to resolve SID for '$Principal': $($adResult.Error) (CorrelationId: $CorrelationId)"
                
                $result = @{
                    Sid = $null
                    Source = "Failed"
                    Success = $false
                    Error = $adResult.Error
                }
                
                if ($UseCache) {
                    $script:SidCache[$Principal] = $result
                }
                
                return [PSCustomObject]@{
                    Principal = $Principal
                    Sid = $null
                    Source = "Failed"
                    Cached = $false
                    Success = $false
                    Error = $adResult.Error
                }
            }
        }
        catch {
            $errorMsg = "Exception resolving SID for '$Principal': $($_.Exception.Message)"
            Write-Warning "$errorMsg (CorrelationId: $CorrelationId)"
            
            $result = @{
                Sid = $null
                Source = "Exception"
                Success = $false
                Error = $errorMsg
            }
            
            if ($UseCache) {
                $script:SidCache[$Principal] = $result
            }
            
            return [PSCustomObject]@{
                Principal = $Principal
                Sid = $null
                Source = "Exception" 
                Cached = $false
                Success = $false
                Error = $errorMsg
            }
        }
    }
}

function Get-WellKnownSid {
    <#
    .SYNOPSIS
    Returns SID for well-known security principals
    
    .DESCRIPTION
    Maps common security principal names to their well-known SIDs without AD queries
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Principal
    )
    
    # Well-known SID mappings
    $wellKnownSids = @{
        # Built-in groups
        "BUILTIN\Administrators" = "S-1-5-32-544"
        "BUILTIN\Users" = "S-1-5-32-545"
        "BUILTIN\Guests" = "S-1-5-32-546"
        "BUILTIN\Power Users" = "S-1-5-32-547"
        "BUILTIN\Account Operators" = "S-1-5-32-548"
        "BUILTIN\Server Operators" = "S-1-5-32-549"
        "BUILTIN\Print Operators" = "S-1-5-32-550"
        "BUILTIN\Backup Operators" = "S-1-5-32-551"
        "BUILTIN\Replicator" = "S-1-5-32-552"
        "BUILTIN\Pre-Windows 2000 Compatible Access" = "S-1-5-32-554"
        "BUILTIN\Remote Desktop Users" = "S-1-5-32-555"
        "BUILTIN\Network Configuration Operators" = "S-1-5-32-556"
        "BUILTIN\Incoming Forest Trust Builders" = "S-1-5-32-557"
        "BUILTIN\Performance Monitor Users" = "S-1-5-32-558"
        "BUILTIN\Performance Log Users" = "S-1-5-32-559"
        "BUILTIN\Windows Authorization Access Group" = "S-1-5-32-560"
        "BUILTIN\Terminal Server License Servers" = "S-1-5-32-561"
        "BUILTIN\Distributed COM Users" = "S-1-5-32-562"
        "BUILTIN\IIS_IUSRS" = "S-1-5-32-568"
        "BUILTIN\Cryptographic Operators" = "S-1-5-32-569"
        "BUILTIN\Event Log Readers" = "S-1-5-32-573"
        "BUILTIN\Certificate Service DCOM Access" = "S-1-5-32-574"
        "BUILTIN\RDS Remote Access Servers" = "S-1-5-32-575"
        "BUILTIN\RDS Endpoint Servers" = "S-1-5-32-576"
        "BUILTIN\RDS Management Servers" = "S-1-5-32-577"
        "BUILTIN\Hyper-V Administrators" = "S-1-5-32-578"
        "BUILTIN\Access Control Assistance Operators" = "S-1-5-32-579"
        "BUILTIN\Remote Management Users" = "S-1-5-32-580"
        "BUILTIN\Storage Replica Administrators" = "S-1-5-32-582"
        "BUILTIN\Device Owners" = "S-1-5-32-583"
        "BUILTIN\User Mode Hardware Operators" = "S-1-5-32-584"
        "BUILTIN\OpenSSH Users" = "S-1-5-32-585"
        
        # NT Authority
        "NT AUTHORITY\SYSTEM" = "S-1-5-18"
        "NT AUTHORITY\LOCAL SERVICE" = "S-1-5-19"
        "NT AUTHORITY\NETWORK SERVICE" = "S-1-5-20"
        "NT AUTHORITY\Authenticated Users" = "S-1-5-11"
        "NT AUTHORITY\ANONYMOUS LOGON" = "S-1-5-7"
        "NT AUTHORITY\BATCH" = "S-1-5-3"
        "NT AUTHORITY\INTERACTIVE" = "S-1-5-4"
        "NT AUTHORITY\SERVICE" = "S-1-5-6"
        "NT AUTHORITY\DIALUP" = "S-1-5-1"
        "NT AUTHORITY\NETWORK" = "S-1-5-2"
        "NT AUTHORITY\TERMINAL SERVER USER" = "S-1-5-13"
        "NT AUTHORITY\REMOTE INTERACTIVE LOGON" = "S-1-5-14"
        "NT AUTHORITY\Local account" = "S-1-5-113"
        "NT AUTHORITY\Local account and member of Administrators group" = "S-1-5-114"
        
        # Everyone and other common principals
        "Everyone" = "S-1-1-0"
        "CREATOR OWNER" = "S-1-3-0"
        "CREATOR GROUP" = "S-1-3-1"
        
        # Short names (case-insensitive lookups)
        "Administrators" = "S-1-5-32-544"
        "Users" = "S-1-5-32-545"
        "Guests" = "S-1-5-32-546"
        "Power Users" = "S-1-5-32-547"
        "Account Operators" = "S-1-5-32-548"
        "Server Operators" = "S-1-5-32-549"
        "Print Operators" = "S-1-5-32-550"
        "Backup Operators" = "S-1-5-32-551"
        "Replicator" = "S-1-5-32-552"
        "Pre-Windows 2000 Compatible Access" = "S-1-5-32-554"
        "Remote Desktop Users" = "S-1-5-32-555"
        "Network Configuration Operators" = "S-1-5-32-556"
        "Incoming Forest Trust Builders" = "S-1-5-32-557"
        "Performance Monitor Users" = "S-1-5-32-558"
        "Performance Log Users" = "S-1-5-32-559"
        "Windows Authorization Access Group" = "S-1-5-32-560"
        "Terminal Server License Servers" = "S-1-5-32-561"
        "Distributed COM Users" = "S-1-5-32-562"
        "IIS_IUSRS" = "S-1-5-32-568"
        "Cryptographic Operators" = "S-1-5-32-569"
        "Event Log Readers" = "S-1-5-32-573"
        "Certificate Service DCOM Access" = "S-1-5-32-574"
        "RDS Remote Access Servers" = "S-1-5-32-575"
        "RDS Endpoint Servers" = "S-1-5-32-576"
        "RDS Management Servers" = "S-1-5-32-577"
        "Hyper-V Administrators" = "S-1-5-32-578"
        "Access Control Assistance Operators" = "S-1-5-32-579"
        "Remote Management Users" = "S-1-5-32-580"
        "Storage Replica Administrators" = "S-1-5-32-582"
        "Device Owners" = "S-1-5-32-583"
        "User Mode Hardware Operators" = "S-1-5-32-584"
        "OpenSSH Users" = "S-1-5-32-585"
        "SYSTEM" = "S-1-5-18"
        "Authenticated Users" = "S-1-5-11"
        "ANONYMOUS LOGON" = "S-1-5-7"
        "Local account" = "S-1-5-113"
        "IUSR" = "S-1-5-17"
        "ENTERPRISE DOMAIN CONTROLLERS" = "S-1-5-9"
    }
    
    # Try exact match first
    if ($wellKnownSids.ContainsKey($Principal)) {
        return $wellKnownSids[$Principal]
    }
    
    # Try case-insensitive match
    $matchingKey = $wellKnownSids.Keys | Where-Object { $_ -ieq $Principal } | Select-Object -First 1
    if ($matchingKey) {
        return $wellKnownSids[$matchingKey]
    }
    
    return $null
}

function Get-TierModelDomainSid {
    <#
    .SYNOPSIS
    Returns the domain SID (or forest root domain SID) for a domain controller, with caching

    .DESCRIPTION
    Queries the domain SID once per domain controller and caches it for the session.
    With -ForestRoot, returns the SID of the forest root domain instead (needed for
    forest-level groups such as Enterprise Admins and Schema Admins).
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DomainController,

        [switch]$ForestRoot
    )

    if (-not $script:DomainSidCache) {
        $script:DomainSidCache = @{}
    }

    $cacheKey = "$DomainController|ForestRoot=$([bool]$ForestRoot)"
    if ($script:DomainSidCache.ContainsKey($cacheKey)) {
        return $script:DomainSidCache[$cacheKey]
    }

    $domain = Get-ADDomain -Server $DomainController -ErrorAction Stop

    if ($ForestRoot) {
        $forest = Get-ADForest -Server $DomainController -ErrorAction Stop
        if ($forest.RootDomain -and $forest.RootDomain -ne $domain.DNSRoot) {
            # Child domain: forest-level groups live in the forest root domain.
            # Target the root domain by name so the AD module locates a DC of
            # that domain within the forest we are already talking to.
            $domain = Get-ADDomain -Identity $forest.RootDomain -Server $forest.RootDomain -ErrorAction Stop
        }
    }

    $domainSid = $domain.DomainSID.Value
    if (-not $domainSid) {
        throw "Could not determine domain SID via domain controller '$DomainController'"
    }

    $script:DomainSidCache[$cacheKey] = $domainSid
    return $domainSid
}

function Get-WellKnownDomainRidSid {
    <#
    .SYNOPSIS
    Resolves well-known domain groups to their SID via fixed RIDs (language-independent)

    .DESCRIPTION
    Maps canonical (English) names of well-known domain groups to <DomainSID>-<RID>.
    This makes resolution independent of the AD display language (e.g. "Domain Admins"
    is "Domänen-Admins" in a German AD, but always <DomainSID>-512).
    Forest-level groups (Enterprise Admins, Schema Admins, ...) are resolved against
    the forest root domain SID.
    Returns $null if the principal is not a well-known domain group.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Principal,

        [Parameter(Mandatory)]
        [string]$DomainController
    )

    # Domain-relative well-known RIDs (hashtable literal keys are case-insensitive)
    $domainRids = @{
        "Guest"                         = 501
        "krbtgt"                        = 502
        "Domain Admins"                 = 512
        "Domain Users"                  = 513
        "Domain Guests"                 = 514
        "Domain Computers"              = 515
        "Domain Controllers"            = 516
        "Cert Publishers"               = 517
        "Group Policy Creator Owners"   = 520
        "Read-only Domain Controllers"  = 521
        "Cloneable Domain Controllers"  = 522
        "Protected Users"               = 525
        "Key Admins"                    = 526
        "RAS and IAS Servers"           = 553
        "Allowed RODC Password Replication Group" = 571
        "Denied RODC Password Replication Group"  = 572
    }

    # Forest-root-relative well-known RIDs
    $forestRootRids = @{
        "Enterprise Read-only Domain Controllers" = 498
        "Schema Admins"                           = 518
        "Enterprise Admins"                       = 519
        "Enterprise Key Admins"                   = 527
    }

    if ($domainRids.ContainsKey($Principal)) {
        $domainSid = Get-TierModelDomainSid -DomainController $DomainController
        return "$domainSid-$($domainRids[$Principal])"
    }

    if ($forestRootRids.ContainsKey($Principal)) {
        $rootDomainSid = Get-TierModelDomainSid -DomainController $DomainController -ForestRoot
        return "$rootDomainSid-$($forestRootRids[$Principal])"
    }

    return $null
}

function Resolve-ADPrincipalSid {
    <#
    .SYNOPSIS
    Resolves security principal using Active Directory
    
    .DESCRIPTION
    Attempts to resolve security principal to SID using AD cmdlets
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Principal,

        [string]$DomainController,

        [string]$CorrelationId
    )

    try {
        # Load ActiveDirectory module if available
        if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
            throw "ActiveDirectory module is not available"
        }
        
        Import-Module ActiveDirectory -ErrorAction Stop
        
        # Try to resolve as user first
        try {
            $adUser = Get-ADUser -Identity $Principal -Server $DomainController -ErrorAction Stop
            return @{
                Sid = $adUser.SID.Value
                Source = "ADUser"
                Success = $true
                Error = $null
            }
        }
        catch {
            # Not a user, try as group
        }
        
        # Try to resolve as group
        try {
            $adGroup = Get-ADGroup -Identity $Principal -Server $DomainController -ErrorAction Stop
            return @{
                Sid = $adGroup.SID.Value
                Source = "ADGroup" 
                Success = $true
                Error = $null
            }
        }
        catch {
            # Not a group either
        }
        
        # Try generic AD object search
        try {
            $adObject = Get-ADObject -Filter "Name -eq '$Principal' -or SamAccountName -eq '$Principal'" -Properties objectSid -Server $DomainController | Select-Object -First 1
            if ($adObject -and $adObject.objectSid) {
                return @{
                    Sid = $adObject.objectSid.Value
                    Source = "ADObject"
                    Success = $true
                    Error = $null
                }
            }
        }
        catch {
            # Generic search also failed
        }
        
        # Principal not found in AD
        return @{
            Sid = $null
            Source = "NotFound"
            Success = $false
            Error = "Principal '$Principal' not found in Active Directory"
        }
    }
    catch {
        return @{
            Sid = $null
            Source = "ADError"
            Success = $false
            Error = "AD query failed: $($_.Exception.Message)"
        }
    }
}

function Get-TierModelConditionalGroupNames {
    <#
    .SYNOPSIS
    Evaluates conditional group conditions and returns only the group names that should be included.

    .DESCRIPTION
    For each name in a conditionalGroup entry, evaluates all conditions before including the name.
    Currently supports:
      - type: "groupExists", operator: "exists" — includes the name only if the AD group is found.
    Names that fail any condition are silently skipped.
    If no conditions are defined, all names are returned unconditionally (backwards compatible).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ConditionalGroup,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    $resolvedNames = @()

    # No conditions defined — include all names unconditionally (backwards compatible)
    if (-not $ConditionalGroup.PSObject.Properties['conditions'] -or
        -not $ConditionalGroup.conditions -or
        @($ConditionalGroup.conditions).Count -eq 0) {
        foreach ($name in $ConditionalGroup.names) { $resolvedNames += $name }
        return $resolvedNames
    }

    foreach ($name in $ConditionalGroup.names) {
        $include = $true

        foreach ($condition in $ConditionalGroup.conditions) {
            if ($condition.type -eq 'groupExists' -and $condition.operator -eq 'exists') {
                try {
                    $adGroup = Get-ADGroup -Identity $name -Server $DomainController -ErrorAction Stop
                } catch {
                    $adGroup = $null
                }
                if (-not $adGroup) {
                    Write-Verbose "Conditional group '$name' not found in AD - skipping (CorrelationId: $CorrelationId)"
                    $include = $false
                    break
                }
            }
            # Future condition types can be added here
        }

        if ($include) {
            $resolvedNames += $name
        }
    }

    return $resolvedNames
}

# Initialize module-level SID caches
$script:SidCache = @{}
$script:DomainSidCache = @{}