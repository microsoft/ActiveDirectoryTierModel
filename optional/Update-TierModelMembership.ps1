#requires -Version 7.0
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
    Disambiguates from EUD via Tier2LocalDeviceOperators membership; operator wins
    for both-groups users. New no-group users default to operator.

.PARAMETER Tier2Eud
    Assign Tier 2 EUD Authentication Policy to pure Tier2LocalDeviceOperators
    members in the Tier 2 Accounts OU. Does not add to any group (LDO membership
    is customer-managed). Skips users also in Tier2Operators (operator wins).

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
    Enables deep per-decision troubleshooting dump to %ProgramData%\TierModel\Debug.
    Each run produces a timestamped debug file with a unique CorrelationId in the
    filename (Update-TierModelMembership.debug.<timestamp>.<CorrelationId>.log).
    The same CorrelationId appears in the -EnableLogging change log for correlation.
    Bounded retention: files older than 7 days, more than 30 files, or exceeding
    200 MB total are pruned at init. Free-space precheck requires 50 MB minimum.
    FAIL-FAST: if the debug file cannot be created, the script aborts before any
    AD modification.

.PARAMETER EnableEventLog
    Emit Windows Event Log entries (Application log, Source 'TierModel') for
    monitoring integration. Writes event 1000 (START), 1001 (COMPLETE), or
    1009 (ERROR). Opt-in and best-effort: a write failure warns and continues.

.PARAMETER JobId
    Stable job identifier for multi-schedule correlation. Embedded in events,
    the log file name, and the log file header. Grammar: [A-Za-z0-9._-]{1,64}.
    Default: 'Adhoc'.

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
    Requires: PowerShell 7.0+ (pwsh.exe). Windows PowerShell 5.1 is blocked.
    The scheduled task action MUST run pwsh.exe, not powershell.exe.
    The TierModel deployment already requires PowerShell 7.
    ActiveDirectory module required. Run on a Domain Controller in SYSTEM context.
    Execution: Local scheduled task, SYSTEM context. NOT SYSVOL/NETLOGON.
    Version: 1.7.0 (Milestones 1-8: all tiers + EnableDebug + EnableEventLog)
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

    # --- Debug ---
    [switch]$EnableDebug,

    # --- Event Log ---
    [switch]$EnableEventLog,

    [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
    [string]$JobId = 'Adhoc'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# SCRIPT-SCOPE STATE
# ============================================================================
$script:ScriptVersion     = '1.7.0'
$script:PreferredDc       = $null
$script:DomainDN          = $null
$script:BuiltInExclusions = $null  # HashSet of sAMAccountNames (case-insensitive)
$script:LogFilePath       = $null
$script:DebugFilePath     = $null
$script:CorrelationId     = $null
$script:ConfigRoot        = $null
$script:EventLogReady     = $false
$script:TierChanges       = $null  # Populated per-run in main block

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

function Write-DebugLog {
    <#
    .SYNOPSIS
        Writes a structured line to the debug file (if -EnableDebug). No-op otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [hashtable]$Data
    )

    if (-not $script:DebugFilePath) { return }

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "$ts [$($script:CorrelationId)] $Message"

    if ($Data -and $Data.Count -gt 0) {
        $pairs = foreach ($k in ($Data.Keys | Sort-Object)) {
            "$k=$($Data[$k])"
        }
        $line += " | $($pairs -join '; ')"
    }

    Add-Content -Path $script:DebugFilePath -Value $line -Encoding UTF8
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
    $script:LogFilePath = Join-Path $logDir "Update-TierModelMembership.$JobId.$timestamp.log"

    # Prune logs older than 7 days
    $cutoff = (Get-Date).AddDays(-7)
    Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Initialize-Debug {
    <#
    .SYNOPSIS
        Sets up the debug directory, file, and bounded retention. Fail-fast
        if the debug file cannot be created (no AD changes will be made).
    #>
    if (-not $EnableDebug) { return }

    $debugDir = Join-Path $env:ProgramData 'TierModel\Debug'
    if (-not (Test-Path $debugDir)) {
        try {
            New-Item -Path $debugDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            throw "DEBUG INIT FAILED: Cannot create debug directory '$debugDir'. $_"
        }
    }

    # FREE-SPACE precheck (50 MB minimum on the target volume)
    $volRoot = [System.IO.Path]::GetPathRoot($debugDir)
    $driveInfo = [System.IO.DriveInfo]::new($volRoot)
    if ($driveInfo.AvailableFreeSpace -lt (50 * 1MB)) {
        $freeMB = [math]::Round($driveInfo.AvailableFreeSpace / 1MB, 1)
        throw ("DEBUG INIT FAILED: Drive '$volRoot' has only $freeMB MB free " +
               "(minimum: 50 MB). Refusing to start with -EnableDebug.")
    }

    # BOUNDED RETENTION: age (>7 days), count (max 30), total size (max 200 MB)
    $debugFiles = @(Get-ChildItem -Path $debugDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)

    # Age-based pruning
    $ageCutoff = (Get-Date).AddDays(-7)
    foreach ($f in $debugFiles) {
        if ($f.LastWriteTime -lt $ageCutoff) {
            Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # Re-read after age pruning
    $debugFiles = @(Get-ChildItem -Path $debugDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)

    # Count-based pruning (keep max 30 newest)
    $maxFileCount = 30
    if ($debugFiles.Count -gt $maxFileCount) {
        foreach ($f in $debugFiles[$maxFileCount..($debugFiles.Count - 1)]) {
            Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
        }
        $debugFiles = @($debugFiles[0..($maxFileCount - 1)])
    }

    # Size-based pruning (cap total at 200 MB, delete oldest beyond cap)
    $maxTotalBytes = 200 * 1MB
    $totalSize = 0
    foreach ($df in $debugFiles) { $totalSize += [long]$df.Length }
    if ($totalSize -gt $maxTotalBytes) {
        for ($i = $debugFiles.Count - 1; $i -ge 0; $i--) {
            if ($totalSize -le $maxTotalBytes) { break }
            $totalSize -= $debugFiles[$i].Length
            Remove-Item -Path $debugFiles[$i].FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # PRE-OPEN: create the debug file BEFORE any AD write
    $dbgTs = Get-Date -Format 'yyyyMMdd-HHmmss'
    $fileName = "Update-TierModelMembership.debug.$dbgTs.$($script:CorrelationId).log"
    $script:DebugFilePath = Join-Path $debugDir $fileName

    try {
        $header = "# Debug log CorrelationId=$($script:CorrelationId) Created=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Set-Content -Path $script:DebugFilePath -Value $header -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        throw ("DEBUG INIT FAILED: Cannot create debug file '$($script:DebugFilePath)'. " +
               "-EnableDebug was requested but the file cannot be written. " +
               "No AD changes will be made. $_")
    }

    Write-DebugLog -Message 'Debug logging initialized' -Data @{
        DebugDir = $debugDir
        DebugFile = $script:DebugFilePath
        FreeMB = [math]::Round($driveInfo.AvailableFreeSpace / 1MB, 0)
    }
}

# ============================================================================
# EVENT LOG
# ============================================================================
function Initialize-TmEventLog {
    <#
    .SYNOPSIS
        Idempotently ensures the 'TierModel' event source exists in the
        Application log. Sets $script:EventLogReady. No-op if -EnableEventLog
        is not set. Never throws.
    #>
    if (-not $EnableEventLog) { return }

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists('TierModel')) {
            [System.Diagnostics.EventLog]::CreateEventSource('TierModel', 'Application')
        }
        $script:EventLogReady = $true
    }
    catch {
        $script:EventLogReady = $false
        Write-Warning "Event log source init failed (events will be skipped): $_"
    }
}

function Write-TmEvent {
    <#
    .SYNOPSIS
        Writes a pipe-delimited event to the Application log under the
        'TierModel' source. No-throw: warns and continues on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('START','COMPLETE','ERROR')]
        [string]$Action,

        [string[]]$ActiveSwitches,

        [System.TimeSpan]$Duration
    )

    if (-not $EnableEventLog -or -not $script:EventLogReady) { return }

    $ver      = $script:ScriptVersion
    $runMode  = if ($WhatIfPreference) { 'WhatIf' } else { 'Apply' }
    $corrId   = $script:CorrelationId
    $hostName = $env:COMPUTERNAME

    switch ($Action) {
        'START' {
            $tierSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            foreach ($sw in $ActiveSwitches) {
                if     ($sw -like 'Tier0*') { [void]$tierSet.Add('Tier0') }
                elseif ($sw -like 'Tier1*') { [void]$tierSet.Add('Tier1') }
                elseif ($sw -like 'Tier2*') { [void]$tierSet.Add('Tier2') }
            }
            $scope = ($tierSet | Sort-Object) -join ';'

            $msg = "Schema=1.0 | Script=Update-TierModelMembership" +
                   " | ScriptVersion=$ver | Action=START | RunMode=$runMode" +
                   " | JobId=$JobId | CorrelationId=$corrId" +
                   " | Host=$hostName | Scope=$scope"

            try {
                [System.Diagnostics.EventLog]::WriteEntry(
                    'TierModel', $msg,
                    [System.Diagnostics.EventLogEntryType]::Information, 1000)
            }
            catch { Write-Warning "Event log write failed (START): $_" }
        }
        'COMPLETE' {
            $tierSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            foreach ($sw in $ActiveSwitches) {
                if     ($sw -like 'Tier0*') { [void]$tierSet.Add('Tier0') }
                elseif ($sw -like 'Tier1*') { [void]$tierSet.Add('Tier1') }
                elseif ($sw -like 'Tier2*') { [void]$tierSet.Add('Tier2') }
            }
            $scope = ($tierSet | Sort-Object) -join ';'

            $changed = @()
            foreach ($t in @('Tier0','Tier1','Tier2')) {
                if ($script:TierChanges[$t] -gt 0) { $changed += $t }
            }
            $tiersChanged = if ($changed.Count -gt 0) { $changed -join ';' } else { 'None' }
            $durationStr  = $Duration.ToString('hh\:mm\:ss')

            $msg = "Schema=1.0 | Script=Update-TierModelMembership" +
                   " | ScriptVersion=$ver | Action=COMPLETE | RunMode=$runMode" +
                   " | JobId=$JobId | CorrelationId=$corrId" +
                   " | Host=$hostName | Scope=$scope" +
                   " | TiersChanged=$tiersChanged" +
                   " | Tier0Changed=$($script:TierChanges.Tier0)" +
                   " | Tier1Changed=$($script:TierChanges.Tier1)" +
                   " | Tier2Changed=$($script:TierChanges.Tier2)" +
                   " | Duration=$durationStr"

            try {
                [System.Diagnostics.EventLog]::WriteEntry(
                    'TierModel', $msg,
                    [System.Diagnostics.EventLogEntryType]::Information, 1001)
            }
            catch { Write-Warning "Event log write failed (COMPLETE): $_" }
        }
        'ERROR' {
            $msg = "Schema=1.0 | Script=Update-TierModelMembership" +
                   " | ScriptVersion=$ver | Action=ERROR | RunMode=$runMode" +
                   " | JobId=$JobId | CorrelationId=$corrId" +
                   " | Host=$hostName" +
                   " | Message=The script encountered an error and stopped." +
                   " Re-run with -EnableLogging or -EnableDebug to identify and resolve it."

            try {
                [System.Diagnostics.EventLog]::WriteEntry(
                    'TierModel', $msg,
                    [System.Diagnostics.EventLogEntryType]::Error, 1009)
            }
            catch { Write-Warning "Event log write failed (ERROR): $_" }
        }
    }
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
        Fail-fast preflight: PS version, AD module, writable DC, DC identity, GC, ADWS.
    #>

    # (0) PowerShell version guard (belt-and-suspenders with #requires -Version 7.0)
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw ('PREFLIGHT FAILED: This script requires PowerShell 7.0 or later. ' +
               'Windows PowerShell 5.1 is closed-source, no longer updated, and is blocked. ' +
               'The TierModel deployment already requires PowerShell 7. ' +
               'Configure the scheduled task action to run pwsh.exe (not powershell.exe).')
    }

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

    Write-DebugLog -Message "Resolved OU" -Data @{ OuName = $OuName; DN = $dn }
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

    $resolvedSam = $entry.samaccountname
    Write-DebugLog -Message "Resolved group" -Data @{ GroupName = $GroupName; SAM = $resolvedSam }
    return $resolvedSam
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

    Write-DebugLog -Message "Resolved policy" -Data @{ PolicyName = $PolicyName; ResolvedName = $entry.name }
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

    foreach ($excl in $script:BuiltInExclusions) {
        Write-DebugLog -Message 'Built-in exclusion account' -Data @{ sAMAccountName = $excl }
    }
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
    $phase1Timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-DebugLog -Message 'Phase 1 start: built-in exclusion enforcement'

    # Tier attribution for built-in exclusion policy clears (event log aggregation)
    $builtInTierMap = @{
        'svc-pawdomainjoin'    = 'Tier0'
        'svc-t1srvdomainjoin'  = 'Tier1'
        'svc-t2euddomainjoin'  = 'Tier2'
    }

    foreach ($sam in $script:BuiltInExclusions) {
        $acct = $null
        try {
            $acct = Get-ADUser -Identity $sam -Properties 'msDS-AssignedAuthNPolicy' `
                        -Server $script:PreferredDc -ErrorAction Stop
        }
        catch {
            # The built-in account may not exist yet (pre-deploy). That is fine.
            Write-Log -Message "Built-in exclusion: '$sam' not found in AD (may not be deployed yet). Skipping." -Level Warning
            Write-DebugLog -Message 'Built-in exclusion check' -Data @{
                sAMAccountName = $sam; Result = 'not-found'; Decision = 'skip'
            }
            continue
        }

        $currentPolicy = $acct.'msDS-AssignedAuthNPolicy'
        if (-not [string]::IsNullOrEmpty($currentPolicy)) {
            Write-DebugLog -Message 'Built-in exclusion check' -Data @{
                sAMAccountName = $sam; DN = $acct.DistinguishedName
                Result = 'has-policy'; CurrentPolicy = "$currentPolicy"; Decision = 'clear'
            }
            if ($PSCmdlet.ShouldProcess($sam, "Remove Authentication Policy '$currentPolicy'")) {
                Clear-TmObjectAuthPolicy -ObjectDn $acct.DistinguishedName
                Write-Log -Message "Removed policy '$currentPolicy' from built-in excluded account '$sam'"
                # Attribute this clear to the account's tier for event log aggregation
                $acctTier = $builtInTierMap[$sam]
                if ($acctTier -and $null -ne $script:TierChanges) {
                    $script:TierChanges[$acctTier]++
                }
            }
        }
        else {
            Write-Log -Message "Built-in exclusion: '$sam' has no policy assigned (correct)."
            Write-DebugLog -Message 'Built-in exclusion check' -Data @{
                sAMAccountName = $sam; DN = $acct.DistinguishedName
                Result = 'no-policy'; Decision = 'already-correct'
            }
        }
    }

    $phase1Timer.Stop()
    Write-DebugLog -Message 'Phase 1 end' -Data @{ ElapsedMs = $phase1Timer.ElapsedMilliseconds }
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
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-DebugLog -Message "$SwitchName phase start" -Data @{
        SourceOuDn = $SourceOuDn
        TargetGroupSam = $TargetGroupSam
        PolicyName = $(if ($PolicyName) { $PolicyName } else { '(none)' })
        ObjectFilter = $ObjectFilter
        SearchScope = $SearchScope
        ApplyExclusionToGroup = $ApplyExclusionToGroup.ToString()
        ExcludeChildOuDn = $(if ($ExcludeChildOuDn) { $ExcludeChildOuDn } else { '(none)' })
    }

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
        $debugPolicyAction = $null
        $debugGroupAction = $null
        $currentPolName = $null

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
                    $debugPolicyAction = 'clear'
                    if ($PSCmdlet.ShouldProcess($sam, "Clear policy '$currentPolName' (excluded)")) {
                        Clear-TmObjectAuthPolicy -ObjectDn $obj.DistinguishedName
                        Write-Log -Message "Cleared policy '$currentPolName' from excluded account '$sam'"
                        $counters.PolicyCleared++
                        $madeChange = $true
                    }
                }
                else {
                    $debugPolicyAction = 'excluded-no-policy'
                }
            }
            else {
                if ($currentPolName -ne $PolicyName) {
                    $debugPolicyAction = 'assign'
                    if ($PSCmdlet.ShouldProcess($sam, "Assign Authentication Policy '$PolicyName'")) {
                        Set-TmObjectAuthPolicy -ObjectDn $obj.DistinguishedName -PolicyDn $policyDn
                        Write-Log -Message "Assigned policy '$PolicyName' to '$sam'"
                        $counters.PolicyAssigned++
                        $madeChange = $true
                    }
                }
                else {
                    $debugPolicyAction = 'already-current'
                }
            }
        }
        else {
            $debugPolicyAction = 'no-policy-configured'
        }

        # ----------------------------------------------------------------
        # GROUP MEMBERSHIP (only after policy succeeds or no policy needed)
        # ----------------------------------------------------------------
        $skipGroup = $false
        if ($ApplyExclusionToGroup -and ($isBuiltInExcl -or $isCustomerExcl)) {
            $skipGroup = $true
            $debugGroupAction = 'skip-excluded'
        }

        if (-not $skipGroup) {
            if (-not $currentMembers.Contains($obj.DistinguishedName)) {
                $debugGroupAction = 'add'
                if ($PSCmdlet.ShouldProcess($sam, "Add to group '$TargetGroupSam'")) {
                    Add-ADGroupMember -Identity $TargetGroupSam -Members $obj.DistinguishedName `
                        -Server $script:PreferredDc -ErrorAction Stop
                    [void]$currentMembers.Add($obj.DistinguishedName)
                    Write-Log -Message "Added '$sam' to group '$TargetGroupSam'"
                    $counters.GroupAdded++
                    $madeChange = $true
                }
            }
            else {
                $debugGroupAction = 'already-member'
            }
        }

        Write-DebugLog -Message "$SwitchName object" -Data @{
            sAMAccountName = $sam
            DN = $obj.DistinguishedName
            BuiltInExcluded = $isBuiltInExcl.ToString()
            CustomerExcluded = $isCustomerExcl.ToString()
            ExclAttrValue = $(if ($ExclusionAttribute) { "$($obj.$ExclusionAttribute)" } else { 'N/A' })
            CurrentPolicy = $(if ($null -ne $currentPolName) { $currentPolName } else { '(none)' })
            DesiredPolicy = $(if ($PolicyName -and -not $isPolicyExcluded) { $PolicyName } elseif ($isPolicyExcluded) { '(excluded)' } else { 'N/A' })
            PolicyAction = $debugPolicyAction
            GroupAction = $debugGroupAction
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

    $phaseTimer.Stop()
    Write-DebugLog -Message "$SwitchName phase end" -Data @{
        ElapsedMs = $phaseTimer.ElapsedMilliseconds
        Scanned = $counters.Scanned
        GroupAdded = $counters.GroupAdded
        PolicyAssigned = $counters.PolicyAssigned
        PolicyCleared = $counters.PolicyCleared
        Excluded = $counters.Excluded
        AlreadyCurrent = $counters.AlreadyCurrent
    }

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
    <#
    .SYNOPSIS
        Tier 2 Operators: Tier 2 Accounts OU users -> Tier2Operators group +
        Tier 2 Authentication Policy.  Disambiguates from EUD users via
        Tier2LocalDeviceOperators group membership (Option X).
    .DESCRIPTION
        Both -Tier2Operators and -Tier2Eud enumerate the SAME OU (Tier 2 Accounts).
        A user's role is determined by group membership, not OU:

          OPERATOR: (NOT isLDO) OR (isOp)
                    Anyone not purely-LDO, including both-groups and no-group users.
          EUD:      (isLDO AND NOT isOp)
                    Pure LDO only -- handled by -Tier2Eud, skipped here.

        New no-group users default to OPERATOR (fail-secure, OQ-1 resolution).
        Operator ALWAYS wins for the single-valued msDS-AssignedAuthNPolicy.

        Fail-closed ordering: policy FIRST, then group membership.
        Exclusion applies to policy only -- NOT to the operator group (all tier
        users are operators, matching Tier 0/1 Operators behavior).

        Must run BEFORE -Tier2Eud when both are active (-AllTier2 / -All).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $switchName = 'Tier2Operators'
    Write-Log -Message "--- $switchName ---"
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()

    # Resolve config-driven names
    $sourceOuDn  = Resolve-OuDn -OuName 'Tier 2 Accounts' -OuConfig $Config.OUs
    $opGroupSam  = Resolve-GroupSam -GroupName 'Tier 2 Operators' -GroupConfig $Config.Groups
    $ldoGroupSam = Resolve-GroupSam -GroupName 'Tier 2 Local Device Operators' -GroupConfig $Config.Groups
    $policyName  = Resolve-PolicyName -PolicyName '*- Tier 2 Authentication Policy' -AuthSiloConfig $Config.AuthSilos

    # Validate source OU exists
    try {
        Get-ADOrganizationalUnit -Identity $sourceOuDn -Server $script:PreferredDc -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$switchName FAILED: Source OU '$sourceOuDn' does not exist in AD. $_"
    }

    # Validate operator group exists
    try {
        Get-ADGroup -Identity $opGroupSam -Server $script:PreferredDc -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$switchName FAILED: Operator group '$opGroupSam' does not exist in AD. $_"
    }

    # Validate LDO group exists
    try {
        Get-ADGroup -Identity $ldoGroupSam -Server $script:PreferredDc -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$switchName FAILED: LDO group '$ldoGroupSam' does not exist in AD. $_"
    }

    # Resolve policy DN
    $policyDn = $null
    try {
        $configNC   = (Get-ADRootDSE -Server $script:PreferredDc).configurationNamingContext
        $searchBase = "CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,$configNC"
        $policyObjs = @(Get-ADObject -Filter "name -eq '$policyName'" `
            -SearchBase $searchBase `
            -Server $script:PreferredDc -ErrorAction Stop)
        if ($policyObjs.Count -eq 0) {
            throw "Authentication Policy '$policyName' not found."
        }
        $policyDn = $policyObjs[0].DistinguishedName
    }
    catch {
        throw "$switchName FAILED: Authentication Policy '$policyName' does not exist in AD. $_"
    }

    # Build properties list
    $propsToFetch = @('sAMAccountName', 'DistinguishedName', 'msDS-AssignedAuthNPolicy')
    if (-not [string]::IsNullOrEmpty($ExclusionAttribute)) {
        $propsToFetch += $ExclusionAttribute
    }

    # Enumerate ALL user objects in Tier 2 Accounts OU
    $users = @(Get-ADObject -LDAPFilter '(objectClass=user)' -SearchBase $sourceOuDn `
                   -SearchScope Subtree -Properties $propsToFetch `
                   -Server $script:PreferredDc -ErrorAction Stop)

    Write-Log -Message "$switchName : Enumerated $($users.Count) user objects from '$sourceOuDn'"

    # Build isOp HashSet (DNs of current Tier2Operators members)
    $isOpSet = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    try {
        $opMembers = @(Get-ADGroupMember -Identity $opGroupSam -Server $script:PreferredDc -ErrorAction Stop)
        foreach ($m in $opMembers) {
            [void]$isOpSet.Add($m.distinguishedName)
        }
    }
    catch {
        Write-Log -Message "$switchName : Could not read members of '$opGroupSam' (may be empty). $_" -Level Warning
    }

    # Build isLDO HashSet (DNs of current Tier2LocalDeviceOperators members)
    $isLdoSet = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    try {
        $ldoMembers = @(Get-ADGroupMember -Identity $ldoGroupSam -Server $script:PreferredDc -ErrorAction Stop)
        foreach ($m in $ldoMembers) {
            [void]$isLdoSet.Add($m.distinguishedName)
        }
    }
    catch {
        Write-Log -Message "$switchName : Could not read members of '$ldoGroupSam' (may be empty). $_" -Level Warning
    }

    Write-Log -Message "$switchName : Tier2Operators members=$($isOpSet.Count), Tier2LocalDeviceOperators members=$($isLdoSet.Count)"

    Write-DebugLog -Message "$switchName phase config" -Data @{
        SourceOuDn = $sourceOuDn; OpGroupSam = $opGroupSam; LdoGroupSam = $ldoGroupSam
        PolicyName = $policyName; PolicyDn = $policyDn
        OpMembers = $isOpSet.Count; LdoMembers = $isLdoSet.Count; Objects = $users.Count
    }

    # Counters
    $counters = @{
        Scanned        = $users.Count
        PolicyAssigned = 0
        PolicyCleared  = 0
        GroupAdded     = 0
        Excluded       = 0
        SkippedEud     = 0
        AlreadyCurrent = 0
    }

    foreach ($user in $users) {
        $sam = $user.sAMAccountName
        $dn  = $user.DistinguishedName
        $madeChange = $false
        $debugPolicyAction = $null
        $debugGroupAction = $null

        # Classify: OPERATOR or EUD
        $userIsOp  = $isOpSet.Contains($dn)
        $userIsLdo = $isLdoSet.Contains($dn)

        # EUD = pure LDO only (isLDO AND NOT isOp) -- handled by -Tier2Eud
        if ($userIsLdo -and -not $userIsOp) {
            Write-DebugLog -Message "$switchName skip-eud" -Data @{
                sAMAccountName = $sam; DN = $dn
                IsOp = $userIsOp.ToString(); IsLDO = $userIsLdo.ToString()
                Role = 'EUD'; Decision = 'skip-handled-by-Tier2Eud'
            }
            $counters.SkippedEud++
            continue
        }

        # This user is an OPERATOR (not in LDO, in both groups, or no group)
        $isBuiltInExcl    = Test-IsBuiltInExcluded -SamAccountName $sam
        $isCustomerExcl   = Test-IsCustomerExcluded -AdObject $user
        $isPolicyExcluded = $isBuiltInExcl -or $isCustomerExcl

        # ----------------------------------------------------------------
        # POLICY ASSIGNMENT (fail-closed: policy first, then group)
        # ----------------------------------------------------------------
        $currentPol = $user.'msDS-AssignedAuthNPolicy'
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

            # Clear policy from excluded operators who currently have one
            if (-not [string]::IsNullOrEmpty($currentPol)) {
                $debugPolicyAction = 'clear'
                if ($PSCmdlet.ShouldProcess($sam, "Clear policy '$currentPolName' (excluded)")) {
                    Clear-TmObjectAuthPolicy -ObjectDn $dn
                    Write-Log -Message "Cleared policy '$currentPolName' from excluded operator '$sam'"
                    $counters.PolicyCleared++
                    $madeChange = $true
                }
            }
            else {
                $debugPolicyAction = 'excluded-no-policy'
            }
        }
        else {
            if ($currentPolName -ne $policyName) {
                $debugPolicyAction = 'assign'
                if ($PSCmdlet.ShouldProcess($sam, "Assign Authentication Policy '$policyName'")) {
                    Set-TmObjectAuthPolicy -ObjectDn $dn -PolicyDn $policyDn
                    Write-Log -Message "Assigned policy '$policyName' to operator '$sam'"
                    $counters.PolicyAssigned++
                    $madeChange = $true
                }
            }
            else {
                $debugPolicyAction = 'already-current'
            }
        }

        # ----------------------------------------------------------------
        # GROUP MEMBERSHIP -- exclusion does NOT apply to operator group
        # All tier users are operators (matching Tier 0/1 Operators behavior)
        # ----------------------------------------------------------------
        if (-not $isOpSet.Contains($dn)) {
            $debugGroupAction = 'add'
            if ($PSCmdlet.ShouldProcess($sam, "Add to group '$opGroupSam'")) {
                Add-ADGroupMember -Identity $opGroupSam -Members $dn `
                    -Server $script:PreferredDc -ErrorAction Stop
                [void]$isOpSet.Add($dn)
                Write-Log -Message "Added operator '$sam' to group '$opGroupSam'"
                $counters.GroupAdded++
                $madeChange = $true
            }
        }
        else {
            $debugGroupAction = 'already-member'
        }

        Write-DebugLog -Message "$switchName operator" -Data @{
            sAMAccountName = $sam; DN = $dn
            IsOp = $userIsOp.ToString(); IsLDO = $userIsLdo.ToString(); Role = 'OPERATOR'
            BuiltInExcluded = $isBuiltInExcl.ToString()
            CustomerExcluded = $isCustomerExcl.ToString()
            ExclAttrValue = $(if ($ExclusionAttribute) { "$($user.$ExclusionAttribute)" } else { 'N/A' })
            CurrentPolicy = $(if ($null -ne $currentPolName) { $currentPolName } else { '(none)' })
            DesiredPolicy = $(if (-not $isPolicyExcluded) { $policyName } else { '(excluded)' })
            PolicyAction = $debugPolicyAction
            GroupAction = $debugGroupAction
        }

        if (-not $madeChange) {
            $counters.AlreadyCurrent++
        }
    }

    # Summary
    $summary = "$switchName : Scanned=$($counters.Scanned) " +
               "Operators=$($counters.Scanned - $counters.SkippedEud) " +
               "SkippedEud=$($counters.SkippedEud) " +
               "GroupAdded=$($counters.GroupAdded) " +
               "PolicyAssigned=$($counters.PolicyAssigned) " +
               "PolicyCleared=$($counters.PolicyCleared) " +
               "Excluded=$($counters.Excluded) " +
               "AlreadyCurrent=$($counters.AlreadyCurrent)"
    Write-Log -Message $summary

    $phaseTimer.Stop()
    Write-DebugLog -Message "$switchName phase end" -Data @{
        ElapsedMs = $phaseTimer.ElapsedMilliseconds
        Scanned = $counters.Scanned
        Operators = ($counters.Scanned - $counters.SkippedEud)
        SkippedEud = $counters.SkippedEud
        GroupAdded = $counters.GroupAdded
        PolicyAssigned = $counters.PolicyAssigned
        PolicyCleared = $counters.PolicyCleared
        Excluded = $counters.Excluded
        AlreadyCurrent = $counters.AlreadyCurrent
    }

    return [PSCustomObject]$counters
}

function Invoke-Tier2Eud {
    <#
    .SYNOPSIS
        Tier 2 EUD: assigns Tier 2 EUD Authentication Policy to pure
        Tier2LocalDeviceOperators members in the Tier 2 Accounts OU.
    .DESCRIPTION
        Both -Tier2Operators and -Tier2Eud enumerate the SAME OU (Tier 2 Accounts).
        A user is classified as EUD only if they are in Tier2LocalDeviceOperators
        AND NOT in Tier2Operators (pure LDO).  All other users (including
        both-groups and no-group) are skipped (handled by -Tier2Operators).

        This function does NOT add users to any group.  LDO membership is
        customer-managed; the script never writes to Tier2LocalDeviceOperators.

        Exclusion applies to policy assignment (skip excluded; clear EUD policy
        from an excluded LDO user that has it).

        Single-valued msDS-AssignedAuthNPolicy interaction: a user who transitions
        from pure-LDO to both-groups will have their EUD policy overwritten by
        the Tier 2 operator policy on the next -Tier2Operators run (Set-ADObject
        -Replace sets the single value).  This is correct: operator wins.

        Must run AFTER -Tier2Operators when both are active (-AllTier2 / -All).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $switchName = 'Tier2Eud'
    Write-Log -Message "--- $switchName ---"
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()

    # Resolve config-driven names
    $sourceOuDn  = Resolve-OuDn -OuName 'Tier 2 Accounts' -OuConfig $Config.OUs
    $opGroupSam  = Resolve-GroupSam -GroupName 'Tier 2 Operators' -GroupConfig $Config.Groups
    $ldoGroupSam = Resolve-GroupSam -GroupName 'Tier 2 Local Device Operators' -GroupConfig $Config.Groups
    $policyName  = Resolve-PolicyName -PolicyName '*- Tier 2 EUD Authentication Policy' -AuthSiloConfig $Config.AuthSilos

    # Validate source OU exists
    try {
        Get-ADOrganizationalUnit -Identity $sourceOuDn -Server $script:PreferredDc -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$switchName FAILED: Source OU '$sourceOuDn' does not exist in AD. $_"
    }

    # Validate both groups exist
    try {
        Get-ADGroup -Identity $opGroupSam -Server $script:PreferredDc -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$switchName FAILED: Operator group '$opGroupSam' does not exist in AD. $_"
    }
    try {
        Get-ADGroup -Identity $ldoGroupSam -Server $script:PreferredDc -ErrorAction Stop | Out-Null
    }
    catch {
        throw "$switchName FAILED: LDO group '$ldoGroupSam' does not exist in AD. $_"
    }

    # Resolve EUD policy DN
    $policyDn = $null
    try {
        $configNC   = (Get-ADRootDSE -Server $script:PreferredDc).configurationNamingContext
        $searchBase = "CN=AuthN Policies,CN=AuthN Policy Configuration,CN=Services,$configNC"
        $policyObjs = @(Get-ADObject -Filter "name -eq '$policyName'" `
            -SearchBase $searchBase `
            -Server $script:PreferredDc -ErrorAction Stop)
        if ($policyObjs.Count -eq 0) {
            throw "Authentication Policy '$policyName' not found."
        }
        $policyDn = $policyObjs[0].DistinguishedName
    }
    catch {
        throw "$switchName FAILED: Authentication Policy '$policyName' does not exist in AD. $_"
    }

    # Build properties list
    $propsToFetch = @('sAMAccountName', 'DistinguishedName', 'msDS-AssignedAuthNPolicy')
    if (-not [string]::IsNullOrEmpty($ExclusionAttribute)) {
        $propsToFetch += $ExclusionAttribute
    }

    # Enumerate ALL user objects in Tier 2 Accounts OU
    $users = @(Get-ADObject -LDAPFilter '(objectClass=user)' -SearchBase $sourceOuDn `
                   -SearchScope Subtree -Properties $propsToFetch `
                   -Server $script:PreferredDc -ErrorAction Stop)

    Write-Log -Message "$switchName : Enumerated $($users.Count) user objects from '$sourceOuDn'"

    # Build isOp HashSet
    $isOpSet = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    try {
        $opMembers = @(Get-ADGroupMember -Identity $opGroupSam -Server $script:PreferredDc -ErrorAction Stop)
        foreach ($m in $opMembers) {
            [void]$isOpSet.Add($m.distinguishedName)
        }
    }
    catch {
        Write-Log -Message "$switchName : Could not read members of '$opGroupSam' (may be empty). $_" -Level Warning
    }

    # Build isLDO HashSet
    $isLdoSet = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    try {
        $ldoMembers = @(Get-ADGroupMember -Identity $ldoGroupSam -Server $script:PreferredDc -ErrorAction Stop)
        foreach ($m in $ldoMembers) {
            [void]$isLdoSet.Add($m.distinguishedName)
        }
    }
    catch {
        Write-Log -Message "$switchName : Could not read members of '$ldoGroupSam' (may be empty). $_" -Level Warning
    }

    Write-Log -Message "$switchName : Tier2Operators members=$($isOpSet.Count), Tier2LocalDeviceOperators members=$($isLdoSet.Count)"

    Write-DebugLog -Message "$switchName phase config" -Data @{
        SourceOuDn = $sourceOuDn; OpGroupSam = $opGroupSam; LdoGroupSam = $ldoGroupSam
        PolicyName = $policyName; PolicyDn = $policyDn
        OpMembers = $isOpSet.Count; LdoMembers = $isLdoSet.Count; Objects = $users.Count
    }

    # Counters
    $counters = @{
        Scanned         = $users.Count
        PolicyAssigned  = 0
        PolicyCleared   = 0
        Excluded        = 0
        SkippedOperator = 0
        AlreadyCurrent  = 0
    }

    foreach ($user in $users) {
        $sam = $user.sAMAccountName
        $dn  = $user.DistinguishedName
        $debugPolicyAction = $null

        # Classify: OPERATOR or EUD
        $userIsOp  = $isOpSet.Contains($dn)
        $userIsLdo = $isLdoSet.Contains($dn)

        # Not EUD => skip (handled by -Tier2Operators)
        if (-not $userIsLdo -or $userIsOp) {
            Write-DebugLog -Message "$switchName skip-operator" -Data @{
                sAMAccountName = $sam; DN = $dn
                IsOp = $userIsOp.ToString(); IsLDO = $userIsLdo.ToString()
                Role = 'OPERATOR'; Decision = 'skip-handled-by-Tier2Operators'
            }
            $counters.SkippedOperator++
            continue
        }

        # This user is EUD (pure LDO: isLDO AND NOT isOp)
        $madeChange       = $false
        $isBuiltInExcl    = Test-IsBuiltInExcluded -SamAccountName $sam
        $isCustomerExcl   = Test-IsCustomerExcluded -AdObject $user
        $isPolicyExcluded = $isBuiltInExcl -or $isCustomerExcl

        # ----------------------------------------------------------------
        # POLICY ASSIGNMENT (EUD policy; no group add ever)
        # ----------------------------------------------------------------
        $currentPol = $user.'msDS-AssignedAuthNPolicy'
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

            if (-not [string]::IsNullOrEmpty($currentPol)) {
                $debugPolicyAction = 'clear'
                if ($PSCmdlet.ShouldProcess($sam, "Clear EUD policy '$currentPolName' (excluded)")) {
                    Clear-TmObjectAuthPolicy -ObjectDn $dn
                    Write-Log -Message "Cleared EUD policy '$currentPolName' from excluded LDO account '$sam'"
                    $counters.PolicyCleared++
                    $madeChange = $true
                }
            }
            else {
                $debugPolicyAction = 'excluded-no-policy'
            }
        }
        else {
            if ($currentPolName -ne $policyName) {
                $debugPolicyAction = 'assign'
                if ($PSCmdlet.ShouldProcess($sam, "Assign EUD Authentication Policy '$policyName'")) {
                    Set-TmObjectAuthPolicy -ObjectDn $dn -PolicyDn $policyDn
                    Write-Log -Message "Assigned EUD policy '$policyName' to LDO account '$sam'"
                    $counters.PolicyAssigned++
                    $madeChange = $true
                }
            }
            else {
                $debugPolicyAction = 'already-current'
            }
        }

        # NO group add -- LDO membership is customer-managed

        Write-DebugLog -Message "$switchName eud-user" -Data @{
            sAMAccountName = $sam; DN = $dn
            IsOp = $userIsOp.ToString(); IsLDO = $userIsLdo.ToString(); Role = 'EUD'
            BuiltInExcluded = $isBuiltInExcl.ToString()
            CustomerExcluded = $isCustomerExcl.ToString()
            ExclAttrValue = $(if ($ExclusionAttribute) { "$($user.$ExclusionAttribute)" } else { 'N/A' })
            CurrentPolicy = $(if ($null -ne $currentPolName) { $currentPolName } else { '(none)' })
            DesiredPolicy = $(if (-not $isPolicyExcluded) { $policyName } else { '(excluded)' })
            PolicyAction = $debugPolicyAction
            GroupAction = 'N/A (LDO is customer-managed)'
        }

        if (-not $madeChange) {
            $counters.AlreadyCurrent++
        }
    }

    # Summary
    $summary = "$switchName : Scanned=$($counters.Scanned) " +
               "EudCandidates=$($counters.Scanned - $counters.SkippedOperator) " +
               "SkippedOperator=$($counters.SkippedOperator) " +
               "PolicyAssigned=$($counters.PolicyAssigned) " +
               "PolicyCleared=$($counters.PolicyCleared) " +
               "Excluded=$($counters.Excluded) " +
               "AlreadyCurrent=$($counters.AlreadyCurrent)"
    Write-Log -Message $summary

    $phaseTimer.Stop()
    Write-DebugLog -Message "$switchName phase end" -Data @{
        ElapsedMs = $phaseTimer.ElapsedMilliseconds
        Scanned = $counters.Scanned
        EudCandidates = ($counters.Scanned - $counters.SkippedOperator)
        SkippedOperator = $counters.SkippedOperator
        PolicyAssigned = $counters.PolicyAssigned
        PolicyCleared = $counters.PolicyCleared
        Excluded = $counters.Excluded
        AlreadyCurrent = $counters.AlreadyCurrent
    }

    return [PSCustomObject]$counters
}

function Invoke-Tier2ServiceActt {
    <#
    .SYNOPSIS
        Tier 2 Service Accounts: Tier 2 Service Accounts OU (user + gMSA + dMSA + sMSA)
        -> Tier2ServiceAccounts group + Tier 2 auth policy.
        Exclusion applies to BOTH group and policy.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 2 Service Accounts' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 2 Service Accounts' -GroupConfig $Config.Groups
    $policyName     = Resolve-PolicyName -PolicyName '*- Tier 2 Authentication Policy' -AuthSiloConfig $Config.AuthSilos

    $svcAcctFilter = '(|(&(objectClass=user)(objectCategory=person))(objectClass=msDS-GroupManagedServiceAccount)(objectClass=msDS-DelegatedManagedServiceAccount)(objectClass=msDS-ManagedServiceAccount))'

    Invoke-TierReconciliation `
        -SwitchName        'Tier2ServiceActt' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $policyName `
        -ObjectFilter      $svcAcctFilter `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $true  # Exclusion applies to BOTH group and policy for Service Accounts
}

function Invoke-Tier2PawDevices {
    <#
    .SYNOPSIS
        Tier 2 PAW Devices: Tier 2 PAW Devices OU computers -> Tier2PAWDevices group.
        No policy assignment (computers get policy via device group SDDL).
        No exclusions (exclusions never apply to computers).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn     = Resolve-OuDn -OuName 'Tier 2 PAW Devices' -OuConfig $Config.OUs
    $targetGroupSam = Resolve-GroupSam -GroupName 'Tier 2 PAW Devices' -GroupConfig $Config.Groups

    Invoke-TierReconciliation `
        -SwitchName        'Tier2PawDevices' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false
}

function Invoke-Tier2EudDevices {
    <#
    .SYNOPSIS
        Tier 2 EUD Devices: computers in the Tier 2 End-User Devices OU
        (subtree) -> Tier2EUDDevices group, EXCLUDING the Disabled End-User
        Devices child OU.
        No policy assignment. No exclusions.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sourceOuDn      = Resolve-OuDn -OuName 'Tier 2 End-User Devices' -OuConfig $Config.OUs
    $targetGroupSam  = Resolve-GroupSam -GroupName 'Tier 2 EUD Devices' -GroupConfig $Config.Groups
    $disabledOuDn    = Resolve-OuDn -OuName 'Disabled End-User Devices' -OuConfig $Config.OUs

    Invoke-TierReconciliation `
        -SwitchName        'Tier2EudDevices' `
        -SourceOuDn        $sourceOuDn `
        -TargetGroupSam    $targetGroupSam `
        -PolicyName        $null `
        -ObjectFilter      '(objectClass=computer)' `
        -SearchScope       'Subtree' `
        -ApplyExclusionToGroup $false `
        -ExcludeChildOuDn  $disabledOuDn
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
try {
    # Validate exclusion parameter pairing
    if (-not [string]::IsNullOrEmpty($ExclusionAttribute) -and [string]::IsNullOrEmpty($ExclusionValue)) {
        throw 'PARAMETER ERROR: -ExclusionValue is mandatory when -ExclusionAttribute is specified.'
    }

    # Generate per-run CorrelationId (used by debug, log files, and events)
    $script:CorrelationId = [guid]::NewGuid()

    # Initialize tier-change tracking for event log aggregation
    $script:TierChanges = @{ Tier0 = 0; Tier1 = 0; Tier2 = 0 }

    # Initialize logging (creates dir/file if -EnableLogging)
    Initialize-Logging

    $runTimer = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Log -Message "JobId=$JobId CorrelationId=$($script:CorrelationId)"
    Write-Log -Message '============================================================'
    Write-Log -Message "Update-TierModelMembership - Starting (CorrelationId=$($script:CorrelationId))"
    Write-Log -Message '============================================================'

    # Initialize event log source (opt-in/best-effort; before preflight)
    Initialize-TmEventLog

    # Resolve active switches early (AD-free) so Scope is known before preflight
    $activeSwitches = Resolve-ActiveSwitches
    Write-Log -Message "Active switches: $($activeSwitches -join ', ')"

    # Emit START event before preflight (a preflight failure still yields START then ERROR)
    Write-TmEvent -Action START -ActiveSwitches $activeSwitches

    # Preflight
    Assert-Preflight

    # Initialize debug (fail-fast if file cannot be created -- before any AD write)
    Initialize-Debug

    Write-DebugLog -Message 'Run started' -Data @{
        CorrelationId = $script:CorrelationId.ToString()
        ScriptVersion = $script:ScriptVersion
        PSVersion = $PSVersionTable.PSVersion.ToString()
        DcDnsHostName = $script:PreferredDc
        IsGlobalCatalog = 'True'
        IsReadOnly = 'False'
        DomainDN = $script:DomainDN
        EnableLogging = $EnableLogging.IsPresent.ToString()
        EnableDebug = $EnableDebug.IsPresent.ToString()
        EnableEventLog = $EnableEventLog.IsPresent.ToString()
        JobId = $JobId
        WhatIf = $WhatIfPreference.ToString()
        ExclusionAttribute = $(if ($ExclusionAttribute) { $ExclusionAttribute } else { '(none)' })
        ExclusionValue = $(if ($ExclusionValue) { $ExclusionValue } else { '(none)' })
    }

    # Load config
    $config = Import-TierModelConfig

    # Initialize built-in exclusions
    Initialize-BuiltInExclusions -UsersConfig $config.Users

    Write-DebugLog -Message 'Switches resolved' -Data @{
        ActiveSwitches = ($activeSwitches -join ', ')
        SwitchCount = @($activeSwitches).Count
    }

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
            $r = & $action
            if ($r) {
                $changeCount = $r.PolicyAssigned + $r.PolicyCleared
                if ($r.PSObject.Properties.Name -contains 'GroupAdded') {
                    $changeCount += $r.GroupAdded
                }
                $tier = if     ($switch -like 'Tier0*') { 'Tier0' }
                        elseif ($switch -like 'Tier1*') { 'Tier1' }
                        elseif ($switch -like 'Tier2*') { 'Tier2' }
                        else   { $null }
                if ($tier) { $script:TierChanges[$tier] += $changeCount }
            }
        }
        else {
            Write-Log -Message "No dispatch found for switch '$switch'" -Level Warning
        }
    }

    $runTimer.Stop()

    # Emit COMPLETE event (clean success only)
    Write-TmEvent -Action COMPLETE -ActiveSwitches $activeSwitches -Duration $runTimer.Elapsed

    Write-Log -Message '============================================================'
    Write-Log -Message "Update-TierModelMembership - Completed successfully (CorrelationId=$($script:CorrelationId))"
    Write-Log -Message '============================================================'

    Write-DebugLog -Message 'Run completed' -Data @{
        CorrelationId = $script:CorrelationId.ToString()
        TotalElapsedMs = $runTimer.ElapsedMilliseconds
        SwitchesExecuted = ($activeSwitches -join ', ')
    }
}
catch {
    # Emit ERROR event FIRST (best-effort; before any other catch handling)
    Write-TmEvent -Action ERROR

    $errMsg = "FATAL ERROR: $($_.Exception.Message)"
    if ($script:LogFilePath) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $script:LogFilePath -Value "$timestamp [Error] $errMsg" -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    Write-DebugLog -Message 'FATAL ERROR' -Data @{
        Error = $_.Exception.Message
        StackTrace = $_.ScriptStackTrace
    }
    Write-Host $errMsg -ForegroundColor Red
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
}
