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
                $domainSid = ConvertTo-TierModelSidString -InputSid (Get-ADDomain -Server $DomainController).DomainSID -Context "the domain SID of '$DomainController'"
                
                # Build the Administrator SID (RID 500)
                $adminSid = "$domainSid-500"
                
                # Look up the renamed built-in Administrator account by SID
                $adminUser = Get-ADUser -Identity $adminSid -Server $DomainController -ErrorAction Stop
                
                Write-Verbose "Found built-in Administrator account (RID 500) with current name: '$($adminUser.SamAccountName)' (CorrelationId: $CorrelationId)"
                
                return @{
                    Principal = $Principal
                    Sid = ConvertTo-TierModelSidString -InputSid $adminUser.SID -Context "built-in Administrator account (RID 500)"
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
        
        # Try AD resolution
        try {
            $adResult = Resolve-ADPrincipalSid -Principal $Principal -CorrelationId $CorrelationId
            
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

function ConvertTo-TierModelSidString {
    <#
    .SYNOPSIS
    Normalises a "SID-ish" value returned by an AD cmdlet into a validated SID string.

    .DESCRIPTION
    Private helper (not exported). AD cmdlets normally return a live
    [System.Security.Principal.SecurityIdentifier] for .SID / .objectSid. On platforms where
    the ActiveDirectory module loads through the Windows PowerShell Compatibility shim
    (WinPSCompatSession — platform-dependent; not reproduced on Windows Server 2025 /
    PowerShell 7.5.1), the objects are DESERIALIZED and those properties come back as plain
    [String]. Reading .Value off a String yields $null, which previously produced BLANK
    principals in GPO GptTmpl.inf (User Rights Assignment and Restricted Groups) - a silent
    security-configuration failure. The helper also defends against any other code path that
    returns a SID as a string rather than as a SecurityIdentifier.

    This helper accepts every shape safely (SecurityIdentifier, String, byte[],
    deserialized PSObject exposing .Value) and THROWS when the result cannot be
    validated as a real SID, so callers fail loudly instead of writing empty values.

    .PARAMETER InputSid
    The raw value read from .SID / .objectSid / .DomainSID.

    .PARAMETER Context
    Human-readable description of what was being resolved, used in the error message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        $InputSid,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $candidate = $null

    if ($null -eq $InputSid) {
        $candidate = $null
    }
    elseif ($InputSid -is [System.Security.Principal.SecurityIdentifier]) {
        $candidate = $InputSid.Value
    }
    elseif ($InputSid -is [string]) {
        # String shape (deserialized on some platforms, or returned directly by certain cmdlets):
        $candidate = $InputSid
    }
    elseif ($InputSid -is [byte[]]) {
        try { $candidate = ([System.Security.Principal.SecurityIdentifier]::new($InputSid, 0)).Value } catch { $candidate = $null }
    }
    else {
        # PSObject / deserialized wrapper: prefer an explicit .Value property, else ToString().
        $valueProperty = $InputSid.PSObject.Properties['Value']
        if ($valueProperty -and -not [string]::IsNullOrWhiteSpace([string]$valueProperty.Value)) {
            $candidate = [string]$valueProperty.Value
        }
        else {
            $candidate = [string]$InputSid
        }
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw "SID resolution returned an empty value for $Context (a deserialized [String] was received where a live [System.Security.Principal.SecurityIdentifier] was expected; cause undetermined). Refusing to emit a blank SID into security policy."
    }

    $candidate = $candidate.Trim()

    if ($candidate -notmatch '^S-1-\d+(-\d+)+$') {
        throw "SID resolution returned a malformed value ('$candidate') for $Context. Refusing to emit an invalid SID into security policy."
    }

    try {
        $null = [System.Security.Principal.SecurityIdentifier]::new($candidate)
    }
    catch {
        throw "SID resolution returned a value ('$candidate') for $Context that is not a valid security identifier: $($_.Exception.Message)"
    }

    return $candidate
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
        "BUILTIN\Network Configuration Operators" = "S-1-5-32-556"
        "BUILTIN\Performance Monitor Users" = "S-1-5-32-558"
        "BUILTIN\Performance Log Users" = "S-1-5-32-559"
        "BUILTIN\Distributed COM Users" = "S-1-5-32-562"
        "BUILTIN\IIS_IUSRS" = "S-1-5-32-568"
        "BUILTIN\Event Log Readers" = "S-1-5-32-573"
        
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
        "SYSTEM" = "S-1-5-18"
        "Authenticated Users" = "S-1-5-11"
        "ANONYMOUS LOGON" = "S-1-5-7"
        "Local account" = "S-1-5-113"
        "IUSR" = "S-1-5-17"
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
        
        [string]$CorrelationId
    )
    
    try {
        # Load ActiveDirectory module if available
        if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
            throw "ActiveDirectory module is not available"
        }
        
        Import-Module ActiveDirectory -ErrorAction Stop
        
        # Try to resolve as user first.
        # The lookup itself is allowed to fail (fall through to group), but SID
        # NORMALISATION is done outside the swallowing catch so a blank/deserialized SID
        # surfaces as a loud ADError instead of being mistaken for "not a user".
        $adUser = $null
        try {
            $adUser = Get-ADUser -Identity $Principal -Server $DomainController -ErrorAction Stop
        }
        catch {
            # Not a user, try as group
            $adUser = $null
        }

        if ($adUser) {
            return @{
                Sid = ConvertTo-TierModelSidString -InputSid $adUser.SID -Context "user '$Principal'"
                Source = "ADUser"
                Success = $true
                Error = $null
            }
        }
        
        # Try to resolve as group
        $adGroup = $null
        try {
            $adGroup = Get-ADGroup -Identity $Principal -Server $DomainController -ErrorAction Stop
        }
        catch {
            # Not a group either
            $adGroup = $null
        }

        if ($adGroup) {
            return @{
                Sid = ConvertTo-TierModelSidString -InputSid $adGroup.SID -Context "group '$Principal'"
                Source = "ADGroup" 
                Success = $true
                Error = $null
            }
        }
        
        # Try generic AD object search
        $adObject = $null
        try {
            $adObject = Get-ADObject -Filter "Name -eq '$Principal' -or SamAccountName -eq '$Principal'" -Properties objectSid -Server $DomainController | Select-Object -First 1
        }
        catch {
            # Generic search also failed
            $adObject = $null
        }

        if ($adObject -and $adObject.objectSid) {
            return @{
                Sid = ConvertTo-TierModelSidString -InputSid $adObject.objectSid -Context "directory object '$Principal'"
                Source = "ADObject"
                Success = $true
                Error = $null
            }
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

# Initialize module-level SID cache
$script:SidCache = @{}