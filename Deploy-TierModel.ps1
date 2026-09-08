<#
.SYNOPSIS
Modular TierModel deployment using dedicated cmdlets per entity type.

.DESCRIPTION
Performs TierModel component deployment across all supported entity types: organizational
units, security groups, user accounts, OU ACL delegations, Group Policy Objects, and ADMX
configurations. Also supports optional add-on features: MSA/gMSA/dMSA managed-service-account
ACL delegations (-IncludeMsa / -IncludeGmsa / -IncludeDmsa), Windows LAPS DACL delegations
(-IncludeWinLaps), AD Authentication Policy Silos (-IncludeAuthSilos), and domain-root AD
object auditing for Sentinel monitoring (-EnableAuditing).

Uses a modular cmdlet architecture for maintainability and testing. Default mode is planning
(shows what would change without writing anything). Pass -ConfirmApply to execute.

Scope parameters (-OuOnly, -GroupOnly, etc.) run a single entity type in isolation.
-FullDeployment runs all entity types in dependency order with consolidated reporting.
Optional add-on switches (-Include* / -EnableAuditing) may run standalone or alongside
-FullDeployment, but cannot be combined with any single-scope (-*Only) parameter.

.PARAMETER PreferredDc
The preferred domain controller to use for all Active Directory operations.
Must be accessible and have appropriate permissions for creating AD objects.

.PARAMETER OuOnly
Deploy only organizational units. OU creation and configuration will be performed
based on the TierModel specification. Cannot be combined with -Include* or -EnableAuditing.

.PARAMETER GroupOnly
Deploy only security groups. Group creation and membership configuration will be
performed. Cannot be combined with -Include* or -EnableAuditing.

.PARAMETER UserOnly
Deploy only user accounts. User account creation and configuration will be performed.
Cannot be combined with -Include* or -EnableAuditing.

.PARAMETER GposOnly
Deploy only Group Policy Objects. GPO creation, configuration, and linking will be
performed. Cannot be combined with -Include* or -EnableAuditing.

.PARAMETER OuAclsOnly
Deploy only OU ACL delegations. Organizational unit access control list delegations
will be applied. Cannot be combined with -Include* or -EnableAuditing.

.PARAMETER AdmxOnly
Deploy only ADMX template configurations. Administrative template imports and
configurations will be applied. Cannot be combined with -Include* or -EnableAuditing.

.PARAMETER FullDeployment
Perform comprehensive deployment of all TierModel components in dependency order:
OUs -> Groups -> Users -> OU ACL Delegations -> GPOs -> ADMX -> optional add-ons.
Provides consolidated reporting at completion. Compatible with -Include* and -EnableAuditing.

.PARAMETER ConfirmApply
Execute the deployment plan. Without this switch the script runs in planning mode only,
showing what changes would be made without applying them. When -EnableAuditing is also
specified, two Y confirmations are required: an auditing-specific warning about event log
volume is presented first, followed by the standard deployment confirmation. Both must be
accepted; either cancellation aborts before any changes are made.

.PARAMETER IncludeMsa
Deploy Managed Service Account (MSA) ACL delegations from the tiermodel-msa.json
configuration segment. May be run standalone or combined with -FullDeployment.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.

.PARAMETER IncludeGmsa
Deploy group Managed Service Account (gMSA) ACL delegations from the tiermodel-gmsa.json
configuration segment. May be run standalone or combined with -FullDeployment.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.

.PARAMETER IncludeDmsa
Deploy delegated Managed Service Account (dMSA) ACL delegations from the tiermodel-dmsa.json
configuration segment. Requires Domain Functional Level Windows Server 2025; the script
performs a pre-flight DFL check and fails fast if the requirement is not met.
May be run standalone or combined with -FullDeployment.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.

.PARAMETER IncludeWinLaps
Deploy Windows LAPS DACL delegations (read-password, reset-password, computer self-permission)
from the tiermodel-winlaps.json configuration segment. Requires the Windows LAPS schema
extensions to be present in Active Directory.
May be run standalone or combined with -FullDeployment.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.

.PARAMETER IncludeAuthSilos
Deploy AD Authentication Policies and Authentication Policy Silos from the
tiermodel-authsilos.json configuration segment. Creates 4 policies and 4 silos (one per
administrative tier: Tier 0 Admin, Tier 1 Admin, Tier 2 Admin, Tier 2 EUD) in AUDIT mode
(not enforced). Assigns account and computer membership by expanding the configured
memberAccountGroups and memberComputerGroups. Permanently exempt accounts (domain-join
service accounts and the built-in Administrator/RID-500) are never assigned.
May be run standalone or combined with -FullDeployment.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.

.PARAMETER EnableAuditing
Enable domain-root Active Directory object auditing for Sentinel monitoring. Applies a
canonical SACL audit ACE (Everyone / AuditFlags=Success / InheritanceType=All) covering
nine rights (CreateChild, DeleteChild, WriteProperty, Self, Delete, DeleteTree, WriteDacl,
WriteOwner, ExtendedRight) to the domain root distinguished name. Uses UNION converge logic:
any rights the customer already has on a matching ACE are preserved and our nine are
guaranteed. Requires SeSecurityPrivilege (Domain Admin qualifies).

When combined with -ConfirmApply, prompts a second, auditing-specific Y confirmation BEFORE
the standard deployment confirmation. The warning reads: "Enabling auditing will increase
the events being generated in the Domain Controller Event Logs..." and requires explicit
acceptance that event log sizing and retention are sufficient.

May be run standalone or combined with -FullDeployment.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.

Note: the SACL alone does not generate Security events. The DC advanced-audit GPO
(Directory Service Changes) must also be configured and its link enabled (on by default
in the TierModel GPO set) for Sentinel to receive events.

.PARAMETER AdmlLanguage
The ADML language culture code used when importing ADMX/ADML administrative templates.
Defaults to 'en-US'. Must match the language folder present in the ADMX source path.

.PARAMETER Logging
Enable structured logging to a timestamped file. When specified, all deployment operations
and results are written to a log file in the directory specified by -LogPath (or the current
working directory if -LogPath is omitted).

.PARAMETER LogPath
Directory path where the log file will be created when -Logging is enabled.
The directory will be created automatically if it does not exist.
If not provided, the log file is created in the current working directory.

.PARAMETER OutputFileBase
Base filename for generated log files (without extension or timestamp).
The actual filename will include a timestamp suffix and appropriate extension.
When -Logging is specified without it you are prompted for one; pressing Enter accepts the
default 'Deploy-TierModel' rather than stopping the run.

.PARAMETER EnableVerbose
Enable verbose diagnostic output for troubleshooting. Console output becomes considerably
more detailed and interleaves with the normal progress output - that is expected, and is the
point of the switch. This switch also enables -Logging automatically, so a diagnostic run
always leaves a log file behind; if -OutputFileBase is omitted it defaults to
'Deploy-TierModel' without prompting, keeping a re-run copy-pasteable.
Diagnostic switches change only what is recorded, never what is decided or written to
Active Directory.

.PARAMETER EnableDebug
Enable debug diagnostic output for troubleshooting. As with -EnableVerbose, this also
enables -Logging automatically and makes console output substantially more detailed.
When -EnableVerbose and -EnableDebug are supplied together, a PowerShell transcript is
also started in a 'Debug' folder beneath the resolved log directory, capturing the full
console session.
WARNING: the transcript is NOT redacted. It may contain distinguished names, SIDs, SDDL,
group memberships and other sensitive Tier 0 detail. Review it before sharing it with
anyone, including support.
If a run is interrupted with Ctrl-C the transcript is left open and continues capturing
until the console exits; run Stop-Transcript manually if that happens.
Diagnostic switches change only what is recorded, never what is decided or written to
Active Directory.

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -OuOnly -EnableVerbose
Plan mode with verbose diagnostics. Logging is enabled automatically and written to
Deploy-TierModel-<timestamp>.log in the current directory.

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -FullDeployment -EnableVerbose -EnableDebug -LogPath "C:\Logs"
Full diagnostic escalation: verbose and debug output, automatic logging to C:\Logs, plus an
unredacted transcript in C:\Logs\Debug. Review the transcript before sharing it.

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -OuOnly
Generate a deployment plan for organizational units only (planning mode — no changes made).

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -OuOnly -ConfirmApply -Logging -LogPath "C:\Logs"
Deploy organizational units and write a structured log to C:\Logs.

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -FullDeployment -ConfirmApply -Logging -OutputFileBase "TierModel-Deploy"
Full TierModel deployment (all entity types) with logging to a timestamped file.

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -EnableAuditing
Plan mode: show the domain-root audit rule that would be configured (no changes made).

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -EnableAuditing -ConfirmApply
Apply the domain-root audit SACL standalone. Presents the auditing event-log warning first
(Prompt 1), then the standard deployment confirmation (Prompt 2). Both must be 'Y' to proceed.

.EXAMPLE
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -FullDeployment -EnableAuditing -ConfirmApply
Full deployment including the domain-root audit SACL. Same two-prompt confirmation sequence:
auditing warning (Prompt 1), then deployment confirmation (Prompt 2).

.NOTES
Version: 2.1.0
Requires: TierModel PowerShell module (v2.1.0+), PowerShell 7.0+, appropriate Active Directory
permissions. SeSecurityPrivilege required for -EnableAuditing (Domain Admin qualifies).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$PreferredDc,
    
    [switch]$OuOnly,
    [switch]$GroupOnly,
    [switch]$UserOnly,
    [switch]$GposOnly,
    [switch]$OuAclsOnly,
    [switch]$AdmxOnly,
    [switch]$FullDeployment,
    [switch]$ConfirmApply,
    
    [switch]$IncludeMsa,
    [switch]$IncludeGmsa,
    [switch]$IncludeDmsa,
    [switch]$IncludeWinLaps,
    [switch]$IncludeAuthSilos,
    [switch]$EnableAuditing,
    
    [Parameter()]
    [string]$AdmlLanguage = 'en-US',
    
    [Parameter()]
    [switch]$Logging,
    
    [Parameter()]
    [string]$LogPath,
    
    [Parameter()]
    [string]$OutputFileBase,
    
    # --- Diagnostics ---
    [Parameter()]
    [switch]$EnableVerbose,
    
    [Parameter()]
    [switch]$EnableDebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate that only one deployment scope parameter is specified
$scopeParameters = @($OuOnly, $GroupOnly, $UserOnly, $GposOnly, $OuAclsOnly, $AdmxOnly, $FullDeployment)
$activeScopeCount = @($scopeParameters | Where-Object { $_ }).Count
$includeParameters = @($IncludeMsa, $IncludeGmsa, $IncludeDmsa, $IncludeWinLaps, $IncludeAuthSilos, $EnableAuditing)
$activeIncludeCount = @($includeParameters | Where-Object { $_ }).Count

if ($activeScopeCount -eq 0 -and $activeIncludeCount -eq 0) {
    Write-Error "You must specify exactly one deployment scope parameter (-OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly, -AdmxOnly, -FullDeployment) or one or more -Include* switches (-IncludeMsa, -IncludeGmsa, -IncludeDmsa, -IncludeWinLaps, -IncludeAuthSilos, -EnableAuditing)." -ErrorAction Stop
}
elseif ($activeScopeCount -gt 1) {
    Write-Error "You can only specify one deployment scope parameter at a time. Cannot combine -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly, -AdmxOnly, and -FullDeployment" -ErrorAction Stop
}
elseif ($activeIncludeCount -gt 0 -and $activeScopeCount -eq 1 -and -not $FullDeployment) {
    Write-Error "-IncludeMsa, -IncludeGmsa, -IncludeDmsa, -IncludeWinLaps, -IncludeAuthSilos, and -EnableAuditing can only be used standalone or combined with -FullDeployment. They cannot be used with -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly, or -AdmxOnly." -ErrorAction Stop
}

Write-Host "Deploy TierModel orchestration starting." -ForegroundColor Cyan
Write-Host "Preferred DC: $PreferredDc" -ForegroundColor DarkCyan

# Resolve the active scope to a string once, unconditionally, so the start-log entry and
# config validation both use the same authoritative value. $null when no scope switch is
# active (Include-only run) — that string never reaches Test-TierModelConfig's ValidateSet.
$selectedScope = if ($FullDeployment) { 'FullDeployment' } elseif ($OuOnly) { 'OuOnly' } elseif ($GroupOnly) { 'GroupOnly' } elseif ($UserOnly) { 'UserOnly' } elseif ($GposOnly) { 'GposOnly' } elseif ($OuAclsOnly) { 'OuAclsOnly' } elseif ($AdmxOnly) { 'AdmxOnly' } else { $null }

# --- Logging enablement -------------------------------------------------------------------
# $script:LoggingAutoEnabled distinguishes the two ways -Logging can become active, because
# they have different rules about prompting:
#   explicit — the operator passed -Logging          -> prompt for a missing -OutputFileBase.
#                                                       This is pre-existing shipped behaviour
#                                                       and is preserved unchanged below.
#   implicit — a diagnostics switch forced it on     -> never prompt (D8); a diagnostics
#                                                       re-run must stay copy-pasteable and
#                                                       runnable in a non-interactive host.
# Mirrors the identical seam in Audit-TierModel.ps1 so that -OutputFileBase behaves the same
# way in both scripts and an operator never has to remember which is which.
$script:LoggingAutoEnabled = $false

# --- Diagnostics resolution (WI-05) ---------------------------------------------------------
# D8: the diagnostics switches auto-enable -Logging, so a diagnostic run always leaves a log
# file behind. The auto-enabled path must NEVER prompt -- a diagnostics re-run has to stay
# copy-pasteable and runnable in a non-interactive host -- so it sets $script:LoggingAutoEnabled
# and the validation block below takes the silent-default branch instead of Read-Host.
$script:DiagnosticsEnabled = $EnableVerbose -or $EnableDebug
# Captured here so Write-TierModelDiagnosticsHint can rebuild the operator's exact invocation.
# $PSBoundParameters is per-scope: inside a function it is that function's own bound parameters,
# so the script-level set has to be stashed while we are still at script scope.
$script:InvocationBoundParameters = $PSBoundParameters
if ($script:DiagnosticsEnabled -and -not $Logging) {
    $Logging = $true
    $script:LoggingAutoEnabled = $true
}

# Validate logging parameters and prompt if needed
if ($Logging -and -not $OutputFileBase) {
    if ($script:LoggingAutoEnabled) {
        $OutputFileBase = 'Deploy-TierModel'
    }
    else {
        # Empty input falls back to the default; an operator pressing Enter must not stop the run.
        $defaultOutputFileBase = 'Deploy-TierModel'
        $OutputFileBase = Read-Host "Enter base filename for logs (timestamp and extension will be added automatically) [$defaultOutputFileBase]"
        if ([string]::IsNullOrWhiteSpace($OutputFileBase)) {
            $OutputFileBase = $defaultOutputFileBase
            Write-Host "Using default base filename for logs: $OutputFileBase" -ForegroundColor DarkGray
        }
    }
}

# Initialize logging if requested
$script:LogDirectory = $null
if ($Logging) {
    $timestamp = Get-Date -Format 'MMddyy-HHmm'
    $logFileName = "$OutputFileBase-$timestamp.log"

    # Resolve the log DIRECTORY exactly once, then derive both the log file and the Debug\
    # folder from that single absolutised base so the two can never end up in different places.
    #
    # POC-6: GetUnresolvedProviderPathFromPSPath is the only correct idiom here.
    #   Resolve-Path / Convert-Path  -> throw on a path that does not exist yet.
    #   [System.IO.Path]::GetFullPath() -> BANNED. It resolves against the .NET process current
    #     directory, which does NOT track PowerShell's location. With a *relative* -LogPath it
    #     silently resolves to a different directory than PowerShell would, so the log file and
    #     the Debug\ folder land apart. Absolute paths hide the bug, so tests miss it.
    if ($LogPath) {
        $script:LogDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
    } else {
        # No -LogPath: use the current working directory.
        $script:LogDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Get-Location).Path)
    }

    # Deploy is [CmdletBinding(SupportsShouldProcess)], so -WhatIf suppresses New-Item. The
    # logging/diagnostics apparatus is NOT part of the change being previewed - it is what RECORDS
    # the preview - so it must be created for real even under -WhatIf. Success must be CONFIRMED
    # with Test-Path, never announced unconditionally.
    if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
        try {
            New-Item -Path $script:LogDirectory -ItemType Directory -Force -WhatIf:$false | Out-Null
        }
        catch {
            Write-Warning "Could not create log directory '$script:LogDirectory': $($_.Exception.Message)"
        }
        if (Test-Path -LiteralPath $script:LogDirectory) {
            Write-Host "Created log directory: $script:LogDirectory" -ForegroundColor Gray
        }
        else {
            Write-Warning "Log directory '$script:LogDirectory' does not exist and could not be created; log entries may not reach disk."
        }
    }

    $script:LogFilePath = Join-Path $script:LogDirectory $logFileName

    Write-Host "Logging enabled: $script:LogFilePath" -ForegroundColor Gray

    if ($script:LoggingAutoEnabled) {
        Write-Host "-EnableVerbose/-EnableDebug also enabled -Logging. Log file: $script:LogFilePath" -ForegroundColor Gray
    }
}

# --- Diagnostics folder (WI-05) -------------------------------------------------------------
# Debug\ lives beside the resolved log file, derived from the SAME absolutised base above so a
# relative -LogPath cannot split them. Created up front (also with -WhatIf:$false, same
# reasoning as the log directory) so the transcript has somewhere to go. Failure to create it
# is never fatal: diagnostics are best-effort and must not abort a deployment.
$script:DebugFolderPath  = $null
$script:TranscriptPath   = $null
$script:TranscriptStarted = $false
if ($script:DiagnosticsEnabled -and $script:LogDirectory) {
    $candidateDebugFolder = Join-Path $script:LogDirectory 'Debug'
    try {
        if (-not (Test-Path -LiteralPath $candidateDebugFolder)) {
            New-Item -Path $candidateDebugFolder -ItemType Directory -Force -WhatIf:$false | Out-Null
        }
    }
    catch {
        Write-Warning "Could not create diagnostics folder '$candidateDebugFolder': $($_.Exception.Message)"
    }
    if (Test-Path -LiteralPath $candidateDebugFolder) {
        $script:DebugFolderPath = $candidateDebugFolder
        Write-Host "Diagnostics folder: $script:DebugFolderPath" -ForegroundColor Gray
    }
    else {
        Write-Warning "Diagnostics folder '$candidateDebugFolder' is unavailable; continuing without a transcript."
    }
}

# Check PowerShell version before importing the module
function Write-TierModelFailFast {
    <#
    .SYNOPSIS
    Renders a consistent fail-fast prerequisite message and closing line.
    .DESCRIPTION
    Produces the standard fail-fast layout used by every up-front gate: a blank line, the
    indented message line(s) in red, an optional "Remediation steps:" block in yellow
    (blank-line separated), and the closing "Deploy script completed." line — so all
    fail-fast paths (PowerShell version, dMSA DFL, and the general prerequisite check) look
    identical.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Message,
        [AllowEmptyCollection()][string[]]$Remediation = @()
    )
    Write-Host ""
    foreach ($line in $Message) { Write-Host "  $line" -ForegroundColor Red }
    if (@($Remediation).Count -gt 0) {
        Write-Host ""
        Write-Host "Remediation steps:" -ForegroundColor Yellow
        foreach ($line in $Remediation) { Write-Host "  - $line" -ForegroundColor Yellow }
    }
    Write-Host ""
    Write-Host "Deploy script completed." -ForegroundColor Green

    try {
        # StrictMode: $script:LogFilePath is not yet DECLARED at the PowerShell-version gate, so
        # it must be probed rather than read. Get-Variable avoids the strict-mode throw.
        $ffLogPath = $null
        $ffLogVar = Get-Variable -Name 'LogFilePath' -Scope Script -ErrorAction SilentlyContinue
        if ($ffLogVar) { $ffLogPath = $ffLogVar.Value }

        if ($ffLogPath) {
            $ffMessage = 'FAIL-FAST (terminal): ' + ((@($Message) | Where-Object { $_ }) -join ' ')
            $ffData = @{
                FailFast       = $true
                Terminal       = $true
                Script         = 'Deploy-TierModel.ps1'
                ConsoleMessage = @($Message)
                Remediation    = @($Remediation)
            }

            if (Get-Command -Name 'Write-TierModelLog' -ErrorAction SilentlyContinue) {
                Write-TierModelLog -LogPath $ffLogPath -Level 'Error' -Message $ffMessage -Data $ffData
            }
            else {
                # The PowerShell-version gate fires BEFORE Import-Module, so the logger does not
                # exist yet. Emit the identical JSON record directly rather than lose the failure.
                $ffEntry = [PSCustomObject]@{
                    Timestamp     = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
                    Level         = 'Error'
                    Message       = $ffMessage
                    Data          = $ffData
                    CorrelationId = [Guid]::NewGuid().ToString()
                }
                $ffDir = Split-Path -Path $ffLogPath -Parent
                if ($ffDir -and -not (Test-Path -LiteralPath $ffDir)) {
                    New-Item -Path $ffDir -ItemType Directory -Force -WhatIf:$false | Out-Null
                }
                Add-Content -Path $ffLogPath -Value ($ffEntry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8 -WhatIf:$false
            }
        }
    }
    catch {
        # A failure while REPORTING a failure must never become the operator's error.
        Write-Warning "Fail-fast details could not be written to the log: $($_.Exception.Message)"
    }
}

function Stop-TierModelDiagnosticsTranscript {
    <#
    .SYNOPSIS
    Stops the diagnostics transcript, but ONLY if this script started it.
    .DESCRIPTION
    ⛔ NEVER call Stop-Transcript unguarded. POC-3 inverted our original assumption: a *nested*
    Start-Transcript is harmless, but an unpaired Stop is not. If our Start-Transcript failed
    (for example under -WhatIf, where it silently creates nothing) while the OPERATOR'S OWN
    transcript is running, a bare Stop-Transcript SUCCEEDS and stops theirs — silently
    destroying their change record. Nothing throws, so a try/catch cannot save you.

    $script:TranscriptStarted is therefore load-bearing: it is set only after Test-Path has
    CONFIRMED that our transcript file exists, and it is the sole authority for whether we are
    allowed to stop anything. The flag is cleared afterwards so a second exit path cannot stop
    a transcript we no longer own.

    This is WI-08 "Option A": a guarded stop at each normal exit path (completion, throw, exit).
    ⚠️ KNOWN GAP (Ctrl-C): after a genuine Ctrl-C the transcript is left open and keeps
    capturing until the console exits. Closing that gap needs a try/finally around the whole
    2,000-line script body, which POC-9 eliminated the need for elsewhere and which is not worth
    the review cost; the trade is with Joel. If Option B is ever chosen, the only change needed
    is to wrap the script body and call this function from the finally — every call site below
    stays exactly as it is.
    #>
    if (-not $script:TranscriptStarted) { return }
    $script:TranscriptStarted = $false
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Stop-Transcript throws when no transcript is running. Nothing actionable — we are on
        # an exit path and the transcript content is already on disk.
    }
    if ($script:TranscriptPath) {
        Write-Host "Diagnostics transcript written: $script:TranscriptPath" -ForegroundColor Gray
    }
}

function Write-TierModelDiagnosticsHint {
    <#
    .SYNOPSIS
    Prints a copy-pasteable re-run line that adds -EnableVerbose -EnableDebug (WI-09).
    .DESCRIPTION
    Reconstructs the operator's actual invocation from the bound parameters captured at script
    start, then appends the two diagnostics switches. The result must be literally pasteable and
    non-interactive — which is why the auto-enable path never prompts for -OutputFileBase.

    Deliberately worded "for full diagnostics" rather than anything that implies the switches
    will reveal the cause: they may not, and promising a cause is how an operator ends up
    running the same failure twice and losing confidence in the tooling.

    Suppressed when both switches are already active — there is nothing left to suggest.
    #>
    if ($EnableVerbose -and $EnableDebug) { return }

    $parts = @()
    foreach ($name in $script:InvocationBoundParameters.Keys) {
        if ($name -in @('EnableVerbose', 'EnableDebug')) { continue }
        $value = $script:InvocationBoundParameters[$name]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $parts += "-$name" }
            else { $parts += "-${name}:`$false" }
        }
        elseif ($value -is [bool]) {
            $parts += "-${name}:`$$($value.ToString().ToLowerInvariant())"
        }
        elseif ($value -is [System.Array]) {
            $parts += "-$name $((@($value) | ForEach-Object { "'$_'" }) -join ',')"
        }
        else {
            $parts += "-$name '$value'"
        }
    }
    # NON-BLOCKING-3: -OutputFileBase may have been supplied by a Read-Host PROMPT rather than on
    # the command line, in which case it is absent from $PSBoundParameters. Replaying the
    # invocation verbatim would emit -Logging with no base name; on the re-run $Logging is already
    # $true, so $script:LoggingAutoEnabled stays $false, the silent-default branch is NOT taken,
    # and the script hits Read-Host again — dying outright in a non-interactive host. That defeats
    # the entire point of a copy-pasteable diagnostics line. Emit the RESOLVED value instead.
    if (-not $script:InvocationBoundParameters.ContainsKey('OutputFileBase') -and
        -not [string]::IsNullOrWhiteSpace($OutputFileBase)) {
        $parts += "-OutputFileBase '$OutputFileBase'"
    }

    $parts += '-EnableVerbose'
    $parts += '-EnableDebug'

    $scriptRef = if ($PSCommandPath) { $PSCommandPath } else { '.\Deploy-TierModel.ps1' }

    Write-Host ""
    Write-Host "Re-run with the following for full diagnostics:" -ForegroundColor Yellow
    Write-Host "  & '$scriptRef' $($parts -join ' ')" -ForegroundColor Yellow
    Write-Host "  (writes a log file, and — with both switches — an UNREDACTED transcript under Debug\)" -ForegroundColor DarkYellow
}

function Get-TierModelAdmxFatalError {
    <#
    .SYNOPSIS
    Returns only the ADMX analysis errors that genuinely block the whole phase.
    .DESCRIPTION
    Copy-TierModelAdmx is per-file resilient: a missing or hash-mismatched SOURCE file is
    skipped and every other file still deploys. Only errors outside that shape (unreadable
    config, unreachable domain controller or central store) abort the phase. The planning
    view must use the same split, otherwise it reports a blocking condition that
    -ConfirmApply would in fact deploy straight through.
    #>
    param(
        [AllowEmptyCollection()][AllowNull()][object[]]$Errors = @()
    )
    $perFilePattern = '^Source (ADMX|ADML) file (not found|hash mismatch)'
    return @(@($Errors) | Where-Object { $_ -and $_ -notmatch $perFilePattern })
}

# Tracks whether the run ended without applying changes because of blocking errors.
# Consumed by the closing summary so the LOG FILE never reports success for a blocked run.
$script:DeploymentBlocked = $false
$script:BlockedPhases = @()

function Write-TierModelBlockedOutcome {
    <#
    .SYNOPSIS
    Marks the current run as blocked and records the blocking errors in the log file.
    .DESCRIPTION
    The dependency-error display path only used Write-Host, so a blocked deployment produced
    a log file that contained no errors and ended with "completed successfully". This helper
    flags the run as blocked and writes every (deduplicated) blocking error, plus any GPOs
    that were dropped from the plan, to the structured log at Error level.
    Console output is unchanged - this only adds log-file fidelity.
    #>
    param(
        [Parameter(Mandatory)][string]$Phase,
        [AllowEmptyCollection()][object[]]$Errors = @(),
        [AllowEmptyCollection()][object[]]$SkippedItems = @()
    )

    $script:DeploymentBlocked = $true
    if ($script:BlockedPhases -notcontains $Phase) { $script:BlockedPhases += $Phase }

    if (-not $Logging -or -not $script:LogFilePath) { return }

    $messages = @(
        @($Errors) | ForEach-Object {
            if ($_ -is [hashtable]) { $_['Message'] }
            elseif ($_ -and $_.PSObject.Properties.Name -contains 'Message') { $_.Message }
            else { "$_" }
        } | Where-Object { $_ } | Select-Object -Unique | Sort-Object
    )

    foreach ($message in $messages) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "$Phase dependency error: $message"
    }

    foreach ($skipped in @($SkippedItems)) {
        $skippedName = if ($skipped.PSObject.Properties.Name -contains 'GPOName') { $skipped.GPOName } else { "$skipped" }
        $skippedReason = if ($skipped.PSObject.Properties.Name -contains 'Reason') { $skipped.Reason } else { 'Unmet dependency' }
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "$Phase not deployed: '$skippedName' - $skippedReason"
    }

    Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "$Phase deployment BLOCKED by dependency errors - no changes were applied" -Data @{
        Phase = $Phase
        DependencyErrorCount = @($messages).Count
        NotDeployedCount = @($SkippedItems).Count
    }
}

function Write-TierModelSkippedGpoReport {
    <#
    .SYNOPSIS
    Tells the operator exactly WHICH GPOs were excluded from the plan, and why.
    .DESCRIPTION
    Dependency errors are deduplicated per group/OU, so previously the operator saw
    "Required group 'X' does not exist" with no indication of which GPOs depended on it.
    This renders the skipped-GPO collection produced by Get-TierModelGpo, grouped by reason.
    #>
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Plan
    )

    if (-not $Plan -or -not ($Plan.PSObject.Properties.Name -contains 'SkippedGpos')) { return }
    $skipped = @($Plan.SkippedGpos)
    if ($skipped.Count -eq 0) { return }

    Write-Host ""
    Write-Host "GPOs NOT deployed because of the dependency errors above: $($skipped.Count)" -ForegroundColor Red
    foreach ($group in ($skipped | Group-Object -Property Reason | Sort-Object Name)) {
        Write-Host "  ⛔ $($group.Name)" -ForegroundColor Red
        foreach ($item in $group.Group) {
            Write-Host "     - $($item.GPOName)" -ForegroundColor DarkYellow
        }
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-TierModelFailFast -Message @(
        "Deploying and Auditing of the Tier Model requires PowerShell 7.x or later.",
        "Current version: PowerShell $($PSVersionTable.PSVersion)"
    ) -Remediation @(
        "Run the Tier Model from a PowerShell 7 (pwsh) console. If PowerShell 7 is not installed, obtain it from https://aka.ms/powershell."
    )
    return
}

# Import TierModel module with all public functions
$script:TierModelModule = Import-Module (Join-Path $PSScriptRoot 'Modules\TierModel\TierModel.psd1') -Force -Verbose:$false -PassThru

Write-Host "TierModel module loaded successfully." -ForegroundColor Green

# Enable module-scope file logging so Write-TierModelLog calls made *inside* the module
# also reach disk. Without this only the ~23 call sites in this script that pass -LogPath
# explicitly are ever written; every module-level entry (including -Level Error) is lost.
# Opt-in only: this runs solely when the operator supplied -Logging.
if ($Logging -and $script:LogFilePath) {
    & $script:TierModelModule {
        param($TargetLogFilePath)
        Initialize-TierModelLogging -LogFilePath $TargetLogFilePath | Out-Null
    } $script:LogFilePath
}

# --- Diagnostics preferences (WI-06) --------------------------------------------------------
# ORDERING IS LOAD-BEARING. These are set AFTER Import-Module, never before.
#   POC-8: TierModel.psm1 emits Write-Verbose "Loading: <file>" per public file from inside the
#   module body. -Verbose:$false on the import does NOT suppress those (163 records survive);
#   only doing the import first, while VerbosePreference is still SilentlyContinue, gets it to 0.
# Both mechanisms are required and neither replaces the other: -Verbose:$false must stay on the
# import above, because it is what covers the four bare ActiveDirectory/GroupPolicy imports that
# run AFTER preferences go live, which ordering alone cannot protect.
#
# POC-9: $script: alone reaches 0 records — module functions resolve preference variables
# function-local -> module scope -> global, and never see the caller's script scope. So the
# module-scope assignment via & $module { ... } is genuinely required. It reproduces $global:
# output exactly (4 verbose / 1 debug from real TierModel functions) and, unlike $global:,
# cannot leak into the operator's session on Ctrl-C — so no restore/finally is needed and no
# $Original*Preference capture exists. The module-scope value does persist for the remainder of
# the session, but both scripts Import-Module -Force at startup, which resets module scope, so
# it self-heals between runs.
#
# NOTE: -Debug is NEVER forwarded as an explicit parameter to an AD or GroupPolicy cmdlet.
# Lab-proven to throw "Object reference not set to an instance of an object" in a
# non-interactive host. Setting the preference variable is the safe mechanism.
if ($script:DiagnosticsEnabled) {
    if ($EnableVerbose) { $script:VerbosePreference = 'Continue' }
    if ($EnableDebug) { $script:DebugPreference = 'Continue' }

    & $script:TierModelModule {
        param($WantVerbose, $WantDebug)
        if ($WantVerbose) { $script:VerbosePreference = 'Continue' }
        if ($WantDebug) { $script:DebugPreference = 'Continue' }
    } $EnableVerbose.IsPresent $EnableDebug.IsPresent

    $enabledSwitches = @()
    if ($EnableVerbose) { $enabledSwitches += '-EnableVerbose' }
    if ($EnableDebug) { $enabledSwitches += '-EnableDebug' }
    Write-Host "Diagnostics enabled: $($enabledSwitches -join ' ')" -ForegroundColor Gray
}

# --- Transcript (WI-07) ---------------------------------------------------------------------
# A transcript is started ONLY when BOTH switches are supplied. -EnableVerbose alone is the
# routine "show me more" case and must not produce an unredacted console capture; requiring
# both makes the transcript a deliberate act.
#
# ⚠️ Under -WhatIf, Start-Transcript throws NOTHING and creates NO file (POC-2). A plain
# try/catch therefore reports success and prints a path to a file that does not exist. Success
# is confirmed with Test-Path and $script:TranscriptStarted is set ONLY on confirmed success.
# Never infer success from the absence of an exception.
# is set ONLY on confirmed success. Never infer success from the absence of an exception.
#
# POC-3: a nested Start-Transcript is harmless, so there is deliberately no "is a transcript
# already running" pre-check here — an earlier version of this plan had one and it was wrong.
if ($script:DiagnosticsEnabled -and $EnableVerbose -and $EnableDebug -and $script:DebugFolderPath) {
    $transcriptStamp = Get-Date -Format 'MMddyy-HHmmss'
    $candidateTranscript = Join-Path $script:DebugFolderPath "Deploy-TierModel.transcript.$transcriptStamp.log"
    try {
        Start-Transcript -Path $candidateTranscript -Force -WhatIf:$false -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "Could not start diagnostics transcript: $($_.Exception.Message)"
    }
    if (Test-Path -LiteralPath $candidateTranscript) {
        $script:TranscriptPath = $candidateTranscript
        $script:TranscriptStarted = $true
        Write-Host "Diagnostics transcript: $script:TranscriptPath" -ForegroundColor Gray
        Write-Host "  WARNING: the transcript is an UNREDACTED capture of this console session." -ForegroundColor Yellow
        Write-Host "  Review it for host names, account names and other environment detail before sharing it." -ForegroundColor Yellow
        Write-Host "  If this run is interrupted with Ctrl-C the transcript is left open and keeps capturing" -ForegroundColor Yellow
        Write-Host "  until the console exits; close it with Stop-Transcript if that happens." -ForegroundColor Yellow
    }
    else {
        # Reached under -WhatIf (Start-Transcript is suppressed silently) and on any other
        # failure. Diagnostics are best-effort: warn and carry on, never abort the deployment.
        Write-Warning "Diagnostics transcript was not created; continuing without one."
    }
}
# ── Critical pre-flight gate: dMSA Domain Functional Level ───────────────────────
# dMSA delegation (-IncludeDmsa) has a hard dependency on a Domain Functional Level of
# Windows Server 2025 — the dMSA schema attributes do not exist below DFL 2025. Like the
# PowerShell-version gate above, fail fast here with a clean message BEFORE running any
# further prerequisite sub-checks or deployment phases, rather than letting the dMSA ACL
# planner surface a confusing "attribute not found in schema" error deep in the run.
# Only gate on a DFL we actually read; if the query fails (e.g. DC unreachable) fall through
# to the standard prerequisite validation below, which reports connectivity problems properly.
if ($IncludeDmsa) {
    $dmsaDfl = $null
    try {
        $dmsaDomain = Get-ADDomain -Server $PreferredDc -ErrorAction Stop
        if ($dmsaDomain -and $dmsaDomain.PSObject.Properties['DomainMode']) {
            $dmsaDfl = [string]$dmsaDomain.DomainMode
        }
    } catch { }
    if ($dmsaDfl -and $dmsaDfl -ne 'Windows2025Domain') {
        $dmsaDflFriendly = (($dmsaDfl -replace 'Windows(\d{4})(R2)?Domain', 'Windows Server $1 $2') -replace '\s+', ' ').Trim()
        Write-TierModelFailFast -Message @(
            "dMSA delegation (-IncludeDmsa) requires a Domain Functional Level of Windows Server 2025.",
            "Current Domain Functional Level: $dmsaDflFriendly"
        ) -Remediation @(
            "Ensure all Domain Controllers in this forest are Server 2025 OS, then increase the DFL to 2025, follow all Microsoft guidance."
        )
        # WI-08: guarded — stops the transcript only if THIS script started it.
        Stop-TierModelDiagnosticsTranscript
        return
    }
}

# Second confirmation gate: -EnableAuditing requires an explicit additional acknowledgement
# about Event Log sizing BEFORE the general deploy confirmation.
# Behavior: -EnableAuditing -ConfirmApply = 2 prompts (audit then deploy)
#           -FullDeployment -EnableAuditing -ConfirmApply = 2 prompts
#           -FullDeployment -ConfirmApply (no auditing) = 1 prompt
#           no -ConfirmApply = 0 prompts (plan only)
if ($EnableAuditing -and $ConfirmApply) {
    Write-Host ""
    Write-Host "WARNING: Enabling auditing will increase the events being generated in the Domain Controller Event Logs." -ForegroundColor Yellow
    Write-Host "By confirming 'Y' you accept that the current event logs are configured with enough size" -ForegroundColor Yellow
    Write-Host "and log retention to not rollover before being shipped for long term retention." -ForegroundColor Yellow
    Write-Host ""

    $auditConfirmation = Read-Host "Type 'Y' to accept the auditing event log impact, any other key to cancel"

    if ($auditConfirmation -ne 'Y') {
        Write-Host ""
        Write-Host "Deployment cancelled by user." -ForegroundColor Red
        Write-Host "Run without -ConfirmApply to see the deployment plan first." -ForegroundColor Cyan
        # WI-08: guarded — stops the transcript only if THIS script started it.
        Stop-TierModelDiagnosticsTranscript
        exit 0
    }

    Write-Host ""
}

# Confirmation prompt for ConfirmApply to prevent accidental execution
if ($ConfirmApply) {
    Write-Host ""
    Write-Host "WARNING: You are about to execute Active Directory changes!" -ForegroundColor Yellow
    Write-Host "These changes, while low risk, will modify your Active Directory environment." -ForegroundColor Yellow
    Write-Host "Please confirm you want to proceed with execution." -ForegroundColor Yellow
    Write-Host ""
    
    $confirmation = Read-Host "Type 'Y' to continue with execution, any other key to cancel"
    
    if ($confirmation -ne 'Y') {
        Write-Host ""
        Write-Host "Deployment cancelled by user." -ForegroundColor Red
        Write-Host "Run without -ConfirmApply to see the deployment plan first." -ForegroundColor Cyan
        # WI-08: guarded — stops the transcript only if THIS script started it.
        Stop-TierModelDiagnosticsTranscript
        exit 0
    }
    
    Write-Host ""
    Write-Host "Proceeding with deployment execution..." -ForegroundColor Green
    Write-Host ""
}

if ($Logging) {
    # Initialize the log file with deployment start information
    Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "TierModel deployment started" -Data @{
        PreferredDc = $PreferredDc
        Mode = if ($ConfirmApply) { 'EXECUTION' } else { 'PLANNING' }
        Scope = if ($null -ne $selectedScope) { $selectedScope } else { 'IncludeOnly' }
        Version = 'v0.2'
        UserConfirmed = $ConfirmApply
    }
    Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "TierModel module loaded successfully"
}

# Validate prerequisites
Write-Host "Validating prerequisites..." -ForegroundColor Cyan
$depsPath = Join-Path $PSScriptRoot 'config\dependencies.json'

try {
    $prereqSplat = @{ PreferredDc = $PreferredDc; DependenciesPath = $depsPath }
    if ($IncludeMsa) { $prereqSplat['IncludeMsa'] = $true }
    if ($IncludeGmsa) { $prereqSplat['IncludeGmsa'] = $true }
    if ($IncludeDmsa) { $prereqSplat['IncludeDmsa'] = $true }
    if ($IncludeWinLaps) { $prereqSplat['IncludeWinLaps'] = $true }
    # Validate feature-specific prerequisites (gMSA KDS root key, Windows LAPS schema, dMSA
    # schema/KDS, etc.) HERE, up front, so any unmet -Include prerequisite fails fast before
    # a single deployment phase runs — rather than surfacing as a confusing planner error deep
    # in a -FullDeployment run.
    $prereqResult = Test-TierModelPrerequisites @prereqSplat
    
    # Handle array results
    if ($prereqResult -is [array] -and $prereqResult.Count -gt 0) {
        $prereqResult = $prereqResult[0]
    }
    
    if (-not $prereqResult -or -not $prereqResult.PSObject.Properties['Valid'] -or -not $prereqResult.Valid) {
        $ffMessages = @()
        if ($prereqResult -and $prereqResult.Errors) { $ffMessages = @($prereqResult.Errors) }
        if ($ffMessages.Count -eq 0) { $ffMessages = @('Prerequisites were not met.') }
        $ffRemediation = @()
        if ($prereqResult -and $prereqResult.Remediation) { $ffRemediation = @($prereqResult.Remediation) }
        Write-TierModelFailFast -Message $ffMessages -Remediation $ffRemediation
        # WI-09: suppressed automatically when both switches are already active.
        Write-TierModelDiagnosticsHint
        # WI-08: guarded — stops the transcript only if THIS script started it.
        Stop-TierModelDiagnosticsTranscript
        exit 1
    }
    
    Write-Host "Prerequisites validation passed." -ForegroundColor Green
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Prerequisites validation passed"
    }
}
catch {
    Write-Host "Error running prerequisites check: $($_.Exception.Message)" -ForegroundColor Red
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "Prerequisites check failed: $($_.Exception.Message)"
    }
    # WI-09: suppressed automatically when both switches are already active.
    Write-TierModelDiagnosticsHint
    # WI-08: guarded — stops the transcript only if THIS script started it.
    Stop-TierModelDiagnosticsTranscript
    exit 1
}

# Load configuration
Write-Host "Loading configuration..." -ForegroundColor Cyan
try {
    $config = Get-TierModelConfig
    Write-Host "Configuration loaded successfully." -ForegroundColor Green
    Write-Host "" # Blank line for spacing
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Configuration loaded successfully"
    }
} catch {
    Write-Host "Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "Failed to load configuration: $($_.Exception.Message)"
    }
    # WI-09: suppressed automatically when both switches are already active.
    Write-TierModelDiagnosticsHint
    # WI-08: guarded — stops the transcript only if THIS script started it.
    Stop-TierModelDiagnosticsTranscript
    exit 1
}

# Validate configuration against schema before any AD work begins.
# Three mutually exclusive branches — no path is silent.
# Get-TierModelConfig always sets ConfigPath on its return object (Get-TierModelConfig.ps1:177).
if ($null -eq $selectedScope) {
    # Include-only run: the 7 scope validators cover OUs, Groups, Users, GPOs, ACLs, and ADMX
    # only — not the MSA, gMSA, dMSA, WinLaps, AuthSilos, or Audit config sections consumed
    # by the -Include* switches. Expected and documented skip.
    Write-Host "Configuration validation skipped: no scope switch active (Include-only run); the 7 scope validators do not cover MSA, gMSA, dMSA, WinLaps, AuthSilos, or Audit config sections." -ForegroundColor Yellow
    Write-Host ""
} elseif ($config.PSObject.Properties.Name -notcontains 'ConfigPath') {
    # ANOMALOUS: a scope is active but the config object has no ConfigPath, meaning it was
    # not produced by Get-TierModelConfig. Schema validation cannot run. This is unexpected
    # in any normal deployment and must be surfaced loudly — never silently skipped.
    Write-Host ""
    Write-Host "⚠️  WARNING: Configuration validation could not run for scope '$selectedScope': the config object has no ConfigPath property and was not loaded from disk by Get-TierModelConfig. Schema validation is being skipped — deployment is proceeding with an UNVALIDATED config." -ForegroundColor Yellow
    Write-Host ""
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Warning' -Message "Configuration validation skipped: config has no ConfigPath (not loaded by Get-TierModelConfig)" -Data @{ Scope = $selectedScope }
    }
} else {
    Write-Host "Validating configuration for scope '$selectedScope'..." -ForegroundColor Cyan
    try {
        $configValidation = Test-TierModelConfig -Config $config -Scope $selectedScope
    } catch {
        Write-TierModelFailFast -Message @(
            "Configuration validation threw an unexpected error for scope '$selectedScope':",
            $_.Exception.Message
        )
        if ($Logging) {
            Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "Configuration validation threw: $($_.Exception.Message)" -Data @{ Scope = $selectedScope }
        }
        # WI-09: suppressed automatically when both switches are already active.
        Write-TierModelDiagnosticsHint
        # WI-08: guarded — stops the transcript only if THIS script started it.
        Stop-TierModelDiagnosticsTranscript
        exit 1
    }
    if ($configValidation.Errors.Count -gt 0) {
        Write-TierModelFailFast -Message (@("Configuration validation failed for scope '$selectedScope'. Deployment cannot proceed:") + @($configValidation.Errors))
        if ($Logging) {
            Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "Configuration validation failed" -Data @{ Scope = $selectedScope; Errors = $configValidation.Errors }
        }
        # WI-09: suppressed automatically when both switches are already active.
        Write-TierModelDiagnosticsHint
        # WI-08: guarded — stops the transcript only if THIS script started it.
        Stop-TierModelDiagnosticsTranscript
        exit 1
    }
    if ($configValidation.Warnings.Count -gt 0) {
        Write-Host "Configuration validation warnings:" -ForegroundColor Yellow
        foreach ($warn in $configValidation.Warnings) {
            Write-Host "  $warn" -ForegroundColor Yellow
        }
        if ($Logging) {
            Write-TierModelLog -LogPath $script:LogFilePath -Level 'Warning' -Message "Configuration validation passed with warnings" -Data @{ Scope = $selectedScope; Warnings = $configValidation.Warnings }
        }
    }
    Write-Host "Configuration validation passed." -ForegroundColor Green
    Write-Host ""
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Configuration validation passed" -Data @{ Scope = $selectedScope; WarningCount = $configValidation.Warnings.Count }
    }
}

# Planned orchestration pattern (placeholder):
# 1. Always: Load config via Get-TierModelConfig
# 2. For each scope-only (e.g. -OuOnly): Call Get-TierModelOu for plan
#    If -ConfirmApply also supplied: Call New-TierModelOu then summarize results
# 3. FullDeployment: Sequence all Get-* then conditionally New-* respecting dependencies
#    Order target: OU -> Groups -> Users -> OU ACL Delegations -> GPOs -> ADMX
# 4. Reporting: Aggregate per-entity plan/changes into unified deployment summary

function Invoke-OuDeployment {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Apply,
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Analyzing OU requirements..." -ForegroundColor Cyan
    }
    
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Starting OU deployment - Mode: $(if ($Apply) { 'EXECUTION' } else { 'PLANNING' })"
    }
    
    # Generate OU plan
    $plan = Get-TierModelOu -Config $Config -DomainController $DomainController -IncludeDetails
    
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "OU plan generated - Total: $($plan.Summary.TotalInConfig), ToCreate: $($plan.Summary.ToCreate), Existing: $($plan.Summary.ExistingCount)"
    }
    
    # Display plan summary (only if not Silent)
    if (-not $Silent) {
        Write-Host "OU Plan Summary:" -ForegroundColor White
        Write-Host "  Total in Config: $($plan.Summary.TotalInConfig)" -ForegroundColor Gray
        Write-Host "  To Create: $($plan.Summary.ToCreate)" -ForegroundColor Yellow
        Write-Host "  Already Exist: $($plan.Summary.ExistingCount)" -ForegroundColor Green
        
        if ($plan.Warnings.Count -gt 0) {
            Write-Host "Warnings:" -ForegroundColor Yellow
            $plan.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
        
        if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and @($plan.Errors).Count -gt 0) {
            Write-Host "Errors:" -ForegroundColor Red
            $plan.Errors | ForEach-Object { Write-Host "  - $($_.Message)" -ForegroundColor Red }
            return $plan
        }
        
        # Show planned actions
        if ($plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0) {
            Write-Host "" # Blank line for spacing
            Write-Host "Planned Actions:" -ForegroundColor Cyan
            $plan.Actions | ForEach-Object {
                Write-Host "  ■ Create OU: $($_.Name)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No actions needed - all OUs exist." -ForegroundColor Green
        }
    }
    
    # Return early if errors (regardless of Silent mode)
    if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and @($plan.Errors).Count -gt 0) {
        # Create a consistent result object when there are plan errors
        $errorResult = [PSCustomObject]@{
            EntityType = 'OU'
            Applied = @()
            Skipped = @()
            Errors = $plan.Errors
            DurationMs = 0
            Converged = $false
            PlanErrors = $true
        }
        return $errorResult
    }
    
    # Apply changes if requested
    if ($Apply) {
        if ($plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0) {
            # Execute the deployment
            if (-not $Silent) {
                Write-Host "Applying OU changes..." -ForegroundColor Cyan
            }
            if ($Logging) {
                Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Applying OU changes - $($plan.Actions.Count) actions to execute"
            }
            try {
                $result = New-TierModelOu -Plan $plan -DomainController $DomainController
                
                # Validate that we got the expected result structure
                if (-not $result) {
                    throw "New-TierModelOu returned null"
                }
                if (-not ($result.PSObject.Properties.Name -contains 'Applied')) {
                    throw "New-TierModelOu returned object without Applied property. Properties: $($result.PSObject.Properties.Name -join ', ')"
                }
                
                # Add entity type to result for consolidated reporting
                $result | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'OU' -Force
            }
            catch {
                # Create fallback result if New-TierModelOu fails
                Write-Host "ERROR: OU deployment failed: $($_.Exception.Message)" -ForegroundColor Red
                $result = [PSCustomObject]@{
                    EntityType = 'OU'
                    Applied = @()
                    Skipped = @()
                    Errors = @(@{
                        Message = "OU deployment failed: $($_.Exception.Message)"
                        Timestamp = Get-Date
                    })
                    DurationMs = 0
                    Converged = $false
                }
            }

            # Store result details for consolidated results section (removed individual Application Results for cleaner output)
            
            if ($Logging) {
                Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "OU deployment completed - Applied: $($result.Applied.Count), Skipped: $($result.Skipped.Count), Errors: $($result.Errors.Count), Duration: $($result.DurationMs)ms"
            }
            
            return $result
        } else {
            # No actions needed - create execution result object
            $result = [PSCustomObject]@{
                EntityType = 'OU'
                Applied = @()
                Skipped = @()
                Errors = @()
                DurationMs = 0
                Converged = $true
            }
            # No need to display message here since it was already shown in the planning phase
            return $result
        }
    }    # Planning mode - return plan structure with execution properties for consistency
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "OU planning completed - $($plan.Actions.Count) actions identified"
    }
    
    $planningResult = [PSCustomObject]@{
        EntityType = 'OU'
        Actions = $plan.Actions
        Summary = $plan.Summary
        Warnings = $plan.Warnings
        Errors = $plan.Errors
        Applied = @()  # Empty for planning mode
        Skipped = @()  # Empty for planning mode
        DurationMs = 0
        Converged = (-not ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and @($plan.Errors).Count -gt 0)) -and (-not ($plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0))
        PlanMode = $true
    }
    return $planningResult
}

function Invoke-GroupDeployment {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Apply,
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Analyzing Group requirements..." -ForegroundColor Cyan
    }
    
    # Generate deployment plan
    $plan = Get-TierModelGroup -Config $Config -DomainController $DomainController -IncludeDetails
    
    if (-not $Silent) {
        Write-Host "Group Plan Summary:" -ForegroundColor White
        Write-Host "  Total in Config: $($plan.Summary.TotalInConfig)" -ForegroundColor Gray
        Write-Host "  To Create: $($plan.Summary.ToCreate)" -ForegroundColor Yellow
        Write-Host "  Already Exist: $($plan.Summary.ExistingCount)" -ForegroundColor Green
        
        if ($plan.PSObject.Properties.Name -contains 'Warnings' -and $plan.Warnings -and @($plan.Warnings).Count -gt 0) {
            Write-Host "Warnings:" -ForegroundColor Yellow
            $plan.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
        
        if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and @($plan.Errors).Count -gt 0) {
            Write-Host "Dependency Errors:" -ForegroundColor Red
            # Deduplicate error messages for cleaner output by grouping by Message property
            $uniqueErrors = $plan.Errors | Group-Object -Property Message | ForEach-Object { $_.Group[0] }
            $uniqueErrors | Sort-Object Message | ForEach-Object { Write-Host "  ❌ $($_.Message)" -ForegroundColor Red }
            return $plan
        }
        
        # Show planned actions
        if ($plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0) {
            Write-Host "" # Blank line for spacing
            Write-Host "Planned Actions:" -ForegroundColor Cyan
            $plan.Actions | ForEach-Object {
                Write-Host "  ■ Create Group: $($_.Name) ($($_.Data.samaccountname))" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No actions needed - all Groups exist." -ForegroundColor Green
        }
    }
    
    # Return early if errors (regardless of Silent mode)
    if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and @($plan.Errors).Count -gt 0) {
        # Create a consistent result object when there are plan errors
        $errorResult = [PSCustomObject]@{
            EntityType = 'Group'
            Actions = $plan.Actions
            Applied = @()
            Skipped = @()
            Errors = $plan.Errors
            DurationMs = 0
            Converged = $false
            PlanMode = $true
        }
        return $errorResult
    }
    
    # Apply changes if requested
    if ($Apply) {
        if ($plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0) {
            # Execute the deployment
            if (-not $Silent) {
                Write-Host "Applying Group changes..." -ForegroundColor Cyan
            }
            if ($Logging) {
                Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Applying Group changes - $($plan.Actions.Count) actions to execute"
            }
            try {
                $result = New-TierModelGroup -Plan $plan -DomainController $DomainController
                
                # Validate that we got the expected result structure
                if (-not $result) {
                    throw "New-TierModelGroup returned null"
                }
                if (-not ($result.PSObject.Properties.Name -contains 'Applied')) {
                    throw "New-TierModelGroup returned object without Applied property. Properties: $($result.PSObject.Properties.Name -join ', ')"
                }
                
                # Add entity type to result for consolidated reporting
                $result | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'Group' -Force
            }
            catch {
                # Create fallback result if New-TierModelGroup fails
                Write-Host "ERROR: Group deployment failed: $($_.Exception.Message)" -ForegroundColor Red
                $result = [PSCustomObject]@{
                    EntityType = 'Group'
                    Applied = @()
                    Skipped = @()
                    Errors = @(@{
                        Message = "Group deployment failed: $($_.Exception.Message)"
                        Timestamp = Get-Date
                    })
                    DurationMs = 0
                    Converged = $false
                }
            }

            # Store result details for consolidated results section (removed individual Application Results for cleaner output)
            
            if ($Logging) {
                Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Group deployment completed - Applied: $($result.Applied.Count), Skipped: $($result.Skipped.Count), Errors: $($result.Errors.Count), Duration: $($result.DurationMs)ms"
            }
            
            return $result
        } else {
            # No actions needed - create execution result object
            $result = [PSCustomObject]@{
                EntityType = 'Group'
                Applied = @()
                Skipped = @()
                Errors = @()
                DurationMs = 0
                Converged = $true
            }
            # No need to display message here since it was already shown in the planning phase
            return $result
        }
    }    # Planning mode - return plan structure with execution properties for consistency
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Group planning completed - $($plan.Actions.Count) actions identified"
    }
    
    $planningResult = [PSCustomObject]@{
        EntityType = 'Group'
        Actions = $plan.Actions
        Summary = $plan.Summary
        Warnings = $plan.Warnings
        Errors = $plan.Errors
        Applied = @()  # Empty for planning mode
        Skipped = @()  # Empty for planning mode
        DurationMs = 0
        Converged = (-not ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and @($plan.Errors).Count -gt 0)) -and (-not ($plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0))
        PlanMode = $true
    }
    return $planningResult
}

function Invoke-UserDeployment {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Apply,  # When true, execute changes; when false, plan only
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Analyzing User requirements..." -ForegroundColor Cyan
    }
    
    # Generate deployment plan. Always suppress Get-TierModelUser's per-user "User exists"
    # output so the -UserOnly console matches -GroupOnly (Get-TierModelGroup has no per-entity
    # existence spam); the "User Plan Summary" below reports the counts instead.
    $plan = Get-TierModelUser -Config $Config -DomainController $DomainController -Silent
    
    # Show deployment plan summary (only if not Silent)
    if (-not $Silent) {
        Write-Host "User Plan Summary:" -ForegroundColor White
        Write-Host "  Total in Config: $($plan.Summary.TotalInConfig)" -ForegroundColor Gray
        Write-Host "  To Create: $($plan.Summary.ToCreate)" -ForegroundColor Yellow
        Write-Host "  To Update: $($plan.Summary.ToUpdate)" -ForegroundColor Yellow
        Write-Host "  Already Exist: $($plan.Summary.ExistingCount)" -ForegroundColor Green
        
        # Handle optional Warnings property (may not exist in Get-TierModelUser)
        if ($plan.PSObject.Properties.Name -contains 'Warnings' -and $plan.Warnings -and $plan.Warnings.Count -gt 0) {
            Write-Host "Warnings:" -ForegroundColor Yellow
            $plan.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
        
        # Handle optional Errors property (may not exist in Get-TierModelUser)
        if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and $plan.Errors.Count -gt 0) {
            Write-Host "Dependency Errors:" -ForegroundColor Red
            # Deduplicate error messages for cleaner output by grouping by Message property
            $uniqueErrors = $plan.Errors | Group-Object -Property Message | ForEach-Object { $_.Group[0] }
            $uniqueErrors | Sort-Object Message | ForEach-Object { Write-Host "  ❌ $($_.Message)" -ForegroundColor Red }
            return $plan
        }
        
        # Show planned actions
        if ($plan.Actions.Count -gt 0) {
            Write-Host "" # Blank line for spacing
            Write-Host "Planned Actions:" -ForegroundColor Cyan
            $plan.Actions | ForEach-Object {
                $actionName = if ($_.PSObject.Properties.Name -contains 'Name' -and $_.Name) { $_.Name } else { "Unknown" }
                switch ($_.Action) {
                    'CreateUser' { Write-Host "  ■ Create User: $actionName" -ForegroundColor Yellow }
                    'UpdateUserMembership' { Write-Host "  ■ Add to Group: $actionName" -ForegroundColor Yellow }
                    default { Write-Host "  ■ $($_.Action): $actionName" -ForegroundColor Yellow }
                }
            }
        } else {
            Write-Host "  No actions needed - all Users exist." -ForegroundColor Green
        }
    }
    
    # Return early if errors (regardless of Silent mode)
    if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and $plan.Errors.Count -gt 0) {
        # Create a consistent result object when there are plan errors
        $errorResult = [PSCustomObject]@{
            EntityType = 'User'
            Actions = $plan.Actions
            Applied = @()
            Skipped = @()
            Errors = $plan.Errors
            DurationMs = 0
            Converged = $false
            PlanMode = $true
        }
        return $errorResult
    }
    
    # Execute deployment plan if Apply is specified
    if ($Apply -and $plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0) {
        if (-not $Silent) {
            Write-Host "Applying User deployment changes..." -ForegroundColor Cyan
        }
        
        # Explicitly pass parameters to avoid WhatIf parameter conflicts
        $newUserParams = @{
            Plan = $plan
            DomainController = $DomainController
        }
        $executionResult = New-TierModelUser @newUserParams
        
        # Convert execution result to match expected structure
        $result = [PSCustomObject]@{
            EntityType = 'User'
            Applied = @(if ($executionResult.Executed -gt 0) { 1..$executionResult.Executed | ForEach-Object { [PSCustomObject]@{ Action = 'CreateUser'; Status = 'Success' } } })
            Skipped = @(if ($executionResult.Skipped -gt 0) { 1..$executionResult.Skipped | ForEach-Object { [PSCustomObject]@{ Action = 'CreateUser'; Status = 'Skipped' } } })
            Errors = $executionResult.Errors
            DurationMs = $executionResult.DurationMs
            Converged = $executionResult.Converged
        }
        
        # Store result details for consolidated results section (removed individual Application Results for cleaner output)
        
        return $result
    } else {
        # No actions needed or planning mode - create execution result object
        $hasErrors = $plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and $plan.Errors.Count -gt 0
        $result = [PSCustomObject]@{
            EntityType = 'User'
            Actions = $plan.Actions
            Applied = @()
            Skipped = @()
            Errors = if ($hasErrors) { $plan.Errors } else { @() }
            DurationMs = 0
            Converged = -not $hasErrors
            PlanMode = $true
        }
        # No need to display message here since it was already shown in the planning phase
        return $result
    }
}

function Invoke-OuAclDeployment {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Apply,  # When true, execute changes; when false, plan only
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Analyzing OU ACL requirements..." -ForegroundColor Cyan
    }
    
    # Ensure GUID resolution functions are loaded (required by ACL processing)
    if (-not (Get-Command Resolve-TierModelGuid -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Resolve-TierModelGuid.ps1"
    }
    if (-not (Get-Command Resolve-DomainSpecificGuid -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Resolve-DomainSpecificGuid.ps1"
    }
    
    # Generate deployment plan
    $plan = Get-TierModelOuAcl -Config $Config -DomainController $DomainController
    
    # Show deployment plan summary (only if not Silent)
    if (-not $Silent) {
        # Debug: Check plan structure
        if (-not $plan) {
            Write-Host "ERROR: Plan is null" -ForegroundColor Red
            return [PSCustomObject]@{ EntityType = 'OuAcl'; Applied = @(); Skipped = @(); Errors = @("Plan is null"); DurationMs = 0; Converged = $false }
        }
        if (-not $plan.PSObject.Properties.Name -contains 'Summary' -or -not $plan.Summary) {
            Write-Host "ERROR: Plan Summary is missing" -ForegroundColor Red
            return [PSCustomObject]@{ EntityType = 'OuAcl'; Applied = @(); Skipped = @(); Errors = @("Plan Summary is missing"); DurationMs = 0; Converged = $false }
        }
        
        Write-Host "OU ACL Plan Summary:" -ForegroundColor White
        # Get-TierModelOuAcl emits ONLY 'CreateAcl' actions, so TotalActions always equals
        # CreateActions and the old "TotalActions - CreateActions" expression was always 0.
        # Report the configured delegation total and the real already-present count instead.
        $ouAclTotalInConfig = if ($plan.Summary.PSObject.Properties.Name -contains 'TotalInConfig' -or ($plan.Summary -is [hashtable] -and $plan.Summary.ContainsKey('TotalInConfig'))) {
            $plan.Summary.TotalInConfig
        } else {
            $plan.Summary.TotalActions
        }
        $ouAclExisting = if ($plan.Summary.PSObject.Properties.Name -contains 'ExistingCount' -or ($plan.Summary -is [hashtable] -and $plan.Summary.ContainsKey('ExistingCount'))) {
            $plan.Summary.ExistingCount
        } else {
            0
        }
        Write-Host "  Total in Config: $ouAclTotalInConfig" -ForegroundColor Gray
        Write-Host "  To Create: $($plan.Summary.CreateActions)" -ForegroundColor Yellow
        Write-Host "  Already Exist: $ouAclExisting" -ForegroundColor Green
        
        # Handle optional Errors property and show dependency errors
        if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and $plan.Errors.Count -gt 0) {
            Write-Host "Dependency Errors:" -ForegroundColor Red
            # Deduplicate error messages for cleaner output by grouping by Message property
            $uniqueErrors = $plan.Errors | Group-Object -Property Message | ForEach-Object { $_.Group[0] }
            $uniqueErrors | Sort-Object Message | ForEach-Object { Write-Host "  ❌ $($_.Message)" -ForegroundColor Red }
        }
        
        # Show planned actions
        if ($plan.Actions -and @($plan.Actions).Count -gt 0) {
            Write-Host "" # Blank line for spacing
            Write-Host "Planned Actions ($($plan.Actions.Count) ACEs):" -ForegroundColor Cyan
            
            # Group by identity reference to show all ACEs for each principal
            $groupedActions = $plan.Actions | Group-Object -Property { 
                if ($_.Data -and $_.Data.identityreference) { 
                    $_.Data.identityreference 
                } else { 
                    'Unknown' 
                }
            }
            
            foreach ($group in $groupedActions) {
                Write-Host "  Principal: $($group.Name) ($($group.Count) ACE(s))" -ForegroundColor Yellow
                foreach ($action in $group.Group) {
                    if ($action.Data) {
                        $rights = if ($action.Data.activedirectoryrights) { $action.Data.activedirectoryrights -join ', ' } else { 'Unknown' }
                        $objectType = if ($action.Data.objecttype) { $action.Data.objecttype } else { 'All Objects' }
                        $inheritance = if ($action.Data.activeDirectorysecurityinheritance) { $action.Data.activeDirectorysecurityinheritance } else { 'Unknown' }
                        Write-Host "    ■ Rights: [$rights] | ObjectType: $objectType | Inheritance: $inheritance" -ForegroundColor White
                    } else {
                        Write-Host "    ■ Create ACL (details unavailable)" -ForegroundColor White
                    }
                }
            }
        } elseif ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and $plan.Errors.Count -eq 0) {
            Write-Host "  No actions needed - all OU ACL delegations exist." -ForegroundColor Green
        }
    }
    
    # Execute deployment plan if Apply is specified
    if ($Apply -and $plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -gt 0) {
        if (-not $Silent) {
            Write-Host "Applying OU ACL deployment changes..." -ForegroundColor Cyan
        }
        
        # Explicitly pass parameters to avoid WhatIf parameter conflicts
        $newOuAclParams = @{
            Plan = $plan
            DomainController = $DomainController
            Config = $config
        }
        $executionResult = New-TierModelOuAcl @newOuAclParams
        
        # Convert execution result to match expected structure
        $result = [PSCustomObject]@{
            EntityType = 'OuAcl'
            Applied = @(if ($executionResult.Executed -gt 0) { 1..$executionResult.Executed | ForEach-Object { [PSCustomObject]@{ Action = 'CreateAcl'; Status = 'Success' } } })
            Skipped = @(if ($executionResult.Skipped -gt 0) { 1..$executionResult.Skipped | ForEach-Object { [PSCustomObject]@{ Action = 'CreateAcl'; Status = 'Skipped' } } })
            Errors = $executionResult.Errors
            DurationMs = $executionResult.DurationMs
            Converged = $executionResult.Converged
        }
        
        # Application Results are now shown in the consolidated section - removed duplicate display
        
        return $result
    } else {
        # No actions needed or planning mode - create execution result object
        $hasErrors = $plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and @($plan.Errors).Count -gt 0
        $result = [PSCustomObject]@{
            EntityType = 'OuAcl'
            Actions = $plan.Actions  # Include Actions for planning mode count display
            Applied = @()
            Skipped = @()
            Errors = if ($hasErrors) { $plan.Errors } else { @() }
            DurationMs = 0
            Converged = -not $hasErrors
        }
        if (-not $Silent -and $plan.PSObject.Properties.Name -contains 'Actions' -and $plan.Actions -and @($plan.Actions).Count -eq 0 -and -not $hasErrors) {
            Write-Host "No OU ACL changes needed - all ACL delegations already exist." -ForegroundColor Green
        }
        return $result
    }
}

function Invoke-GpoDeployment {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Apply,  # When true, execute changes; when false, plan only
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "$(if ($Apply) { 'Executing' } else { 'Planning' }) GPO deployment..." -ForegroundColor Cyan
    }
    
    # First, check for dependency errors with silent mode
    $planCheck = Get-TierModelGpo -Config $Config -DomainController $DomainController -Silent
    
    # If there are dependency errors, generate plan again with silent mode and return early
    if ($planCheck.PSObject.Properties.Name -contains 'Errors' -and $planCheck.Errors -and $planCheck.Errors.Count -gt 0) {
        $plan = $planCheck  # Use the silent plan
        if (-not $Silent) {
            Write-Host "Dependency Errors:" -ForegroundColor Red
            # Deduplicate error messages for cleaner output by grouping by Message property
            $uniqueErrors = $plan.Errors | Group-Object -Property Message | ForEach-Object { $_.Group[0] }
            $uniqueErrors | Sort-Object Message | ForEach-Object { Write-Host "  ❌ $($_.Message)" -ForegroundColor Red }
        }
        return $plan
    }
    
    # No dependency errors, use the silent plan and show the visual output manually (unless Silent mode)
    $plan = $planCheck  # Use the existing silent plan for all cases
    
    if (-not $Silent) {
        # Show GPO Plan Summary before the individual actions (like Users deployment)
        Write-Host "GPO Plan Summary:" -ForegroundColor White
        Write-Host "  Total in Config: $($plan.Summary.TotalInConfig)" -ForegroundColor Gray
        Write-Host "  To Create: $($plan.Summary.CreateActions)" -ForegroundColor Yellow
        Write-Host "  To Import: $($plan.Summary.ImportActions)" -ForegroundColor Yellow
        Write-Host "  To Configure: $($plan.Summary.ConfigureActions)" -ForegroundColor Yellow
        Write-Host "  To Link: $($plan.Summary.LinkActions)" -ForegroundColor Yellow
        Write-Host "  Already Exist: $($plan.Summary.ExistingCount)" -ForegroundColor Green
        Write-Host "" # Blank line before actions
        
        # Generate the visual GPO analysis output (the format you want to keep)
        $null = Get-TierModelGpo -Config $Config -DomainController $DomainController
        
        # Show warnings if present
        if ($plan.PSObject.Properties.Name -contains 'Warnings' -and $plan.Warnings -and $plan.Warnings.Count -gt 0) {
            Write-Host "" # Blank line for spacing
            Write-Host "Warnings:" -ForegroundColor Yellow
            $plan.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
    }
    
    # Return early if errors (regardless of Silent mode)
    if ($plan.PSObject.Properties.Name -contains 'Errors' -and $plan.Errors -and $plan.Errors.Count -gt 0) {
        # Create a consistent result object when there are plan errors
        $errorResult = [PSCustomObject]@{
            EntityType = 'GPO'
            Actions = $plan.Actions
            Applied = @()
            Skipped = @()
            Errors = $plan.Errors
            DurationMs = 0
            Converged = $false
            PlanMode = $true
        }
        return $errorResult
    }
    
    # Execute deployment plan if Apply is specified
    if ($Apply -and $plan -and $plan.Actions -and $plan.Actions.Count -gt 0) {
        if (-not $Silent) {
            Write-Host "Applying GPO deployment changes..." -ForegroundColor Cyan
        }
        
        $totalExecuted = 0
        $totalFailed = 0
        $totalSkipped = 0
        $allErrors = @()
        $overallConverged = $true
        $totalDuration = 0
        
        # Phase 1: Create GPOs
        $createActions = @($plan.Actions | Where-Object { $_.Action -eq 'CreateGPO' })
        if ($createActions.Count -gt 0) {
            if (-not $Silent) { Write-Host "  Phase 1: Creating GPOs..." -ForegroundColor Cyan }
            $createPlan = [PSCustomObject]@{ Actions = $createActions; Config = $Config }
            $createResult = New-TierModelGpo -Plan $createPlan -DomainController $DomainController
            $totalExecuted += $createResult.Executed
            $totalFailed += $createResult.Failed
            $totalSkipped += $createResult.Skipped
            $allErrors += $createResult.Errors
            $totalDuration += $createResult.DurationMs
            if (-not $createResult.Converged) { $overallConverged = $false }
            
            # Stop if all GPOs failed in this phase
            if ($createResult.Failed -gt 0 -and $createResult.Executed -eq 0) {
                if (-not $Silent) { Write-Host "  Phase 1 failed completely - stopping GPO deployment" -ForegroundColor Red }
                return [PSCustomObject]@{
                    Executed = $totalExecuted; Failed = $totalFailed; Skipped = $totalSkipped
                    Errors = $allErrors; Converged = $false; DurationMs = $totalDuration
                }
            }
        }
        
        # Phase 2: Import GPO settings
        $importActions = @($plan.Actions | Where-Object { $_.Action -eq 'ImportGPO' })
        if ($importActions.Count -gt 0) {
            if (-not $Silent) { Write-Host "  Phase 2: Importing GPO settings..." -ForegroundColor Cyan }
            $importPlan = [PSCustomObject]@{ Actions = $importActions; Config = $Config }
            try {
                $importResult = Import-TierModelGpo -Plan $importPlan -DomainController $DomainController
                if ($importResult) {
                    $totalExecuted += $importResult.Executed
                    $totalFailed += $importResult.Failed
                    $totalSkipped += $importResult.Skipped
                $allErrors += $importResult.Errors
                $totalDuration += $importResult.DurationMs
                if (-not $importResult.Converged) { $overallConverged = $false }
                } else {
                    Write-Host "    WARNING: Import result is null" -ForegroundColor Yellow
                    $totalFailed += $importActions.Count
                }
            } catch {
                Write-Host "    ERROR: Import-TierModelGpo failed - $($_.Exception.Message)" -ForegroundColor Red
                $allErrors += $_.Exception.Message
                $totalFailed += $importActions.Count
                $overallConverged = $false
            }
            
            # Stop if all GPOs failed in this phase
            if ($importResult.Failed -gt 0 -and $importResult.Executed -eq 0) {
                if (-not $Silent) { Write-Host "  Phase 2 failed completely - stopping GPO deployment" -ForegroundColor Red }
                return [PSCustomObject]@{
                    Executed = $totalExecuted; Failed = $totalFailed; Skipped = $totalSkipped
                    Errors = $allErrors; Converged = $false; DurationMs = $totalDuration
                }
            }
        }
        
        # Phase 3: Configure GPO security templates
        $configActions = @($plan.Actions | Where-Object { $_.Action -eq 'ConfigureGPO' })
        if ($configActions.Count -gt 0) {
            if (-not $Silent) { Write-Host "  Phase 3: Configuring GPO security templates..." -ForegroundColor Cyan }
            $configPlan = [PSCustomObject]@{ Actions = $configActions; Config = $Config }
            
            $configResult = Update-TierModelGPOConfig -Plan $configPlan -DomainController $DomainController
            $totalExecuted += $configResult.Executed
            $totalFailed += $configResult.Failed
            $totalSkipped += $configResult.Skipped
            $allErrors += $configResult.Errors
            $totalDuration += $configResult.DurationMs
            if (-not $configResult.Converged) { $overallConverged = $false }
            
            # Stop if any GPOs failed in this phase (SID resolution failures should be treated as errors)
            if ($configResult.Failed -gt 0) {
                if (-not $Silent) { Write-Host "  Phase 3 failed - stopping GPO deployment" -ForegroundColor Red }
                return [PSCustomObject]@{
                    Executed = $totalExecuted; Failed = $totalFailed; Skipped = $totalSkipped
                    Errors = $allErrors; Converged = $false; DurationMs = $totalDuration
                }
            }
        }
        
        # Phase 4: Link GPOs to OUs
        $linkActions = @($plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' })
        if ($linkActions.Count -gt 0) {
            if (-not $Silent) { Write-Host "  Phase 4: Linking GPOs to OUs..." -ForegroundColor Cyan }
            $linkPlan = Get-TierModelGPOLink -Plan $plan -DomainController $DomainController
            $linkResult = New-TierModelGPOLink -Plan $linkPlan -DomainController $DomainController
            $totalExecuted += $linkResult.Executed
            $totalFailed += $linkResult.Failed
            $totalSkipped += $linkResult.Skipped
            $allErrors += $linkResult.Errors
            $totalDuration += $linkResult.DurationMs
            if (-not $linkResult.Converged) { $overallConverged = $false }
        }
        
        # Create consolidated result
        $result = [PSCustomObject]@{
            EntityType = 'Gpo'
            Plan = $plan  # Include the plan for action breakdown in deployment summary
            Executed = $totalExecuted
            Failed = $totalFailed
            Skipped = $totalSkipped
            Errors = $allErrors
            DurationMs = $totalDuration
            Converged = $overallConverged
            Silent = $Silent
        }
        
        # Application results are handled in the deployment plan section
        if (-not $Silent -and $result.Errors.Count -gt 0) {
            Write-Host "Application Errors:" -ForegroundColor Red
            $result.Errors | ForEach-Object { Write-Host "  - $($_.Message)" -ForegroundColor Red }
        }
        
        return $result
    } else {
        # No actions needed or planning mode
        $result = [PSCustomObject]@{
            EntityType = 'Gpo'
            Plan = $plan
            Executed = 0
            Failed = 0
            Skipped = 0
            Errors = if ($plan -and $plan.Errors) { $plan.Errors } else { @() }
            DurationMs = 0
            Converged = if ($plan) { $plan.Errors.Count -eq 0 } else { $true }
            Silent = $Silent
        }
        if (-not $Silent -and $plan -and $plan.Errors -and $plan.Errors.Count -gt 0) {
            Write-Host "GPO planning failed - check logs for details." -ForegroundColor Red
            # WI-09: suppressed automatically when both switches are already active.
            Write-TierModelDiagnosticsHint
        } elseif (-not $Silent -and $plan -and $plan.Actions -and $plan.Actions.Count -eq 0) {
            Write-Host "No GPO changes needed - all GPOs already configured and linked." -ForegroundColor Green
        }
        return $result
    }
}

function Write-IncludeAclPlanActions {
    param(
        [Parameter(Mandatory)] [object[]]$Actions
    )

    @($Actions) | ForEach-Object {
        if ($_.Action -eq 'CreateAcl') {
            $ouName = if ($_.Path -match '^OU=([^,]+)') { $matches[1] } else { 'Unknown OU' }
            if ($_.ResourceType -eq 'LapsPermission') {
                # Strip NetBIOS domain prefix for display parity with MSA/gMSA/dMSA (data keeps domain-qualified form for the Set-LapsAD* calls)
                $principals = if ($_.Data.PSObject.Properties['allowedPrincipals']) { (@($_.Data.allowedPrincipals) | ForEach-Object { ($_ -split '\\')[-1] }) -join ', ' } else { 'SELF' }
                Write-Host "  ■ Create ACL: $principals on $ouName" -ForegroundColor Yellow
            } else {
                $principal = $_.Data.identityreference
                Write-Host "  ■ Create ACL: $principal on $ouName" -ForegroundColor Yellow
            }
        } elseif ($_.Action -eq 'ConfigureLapsDecryptor') {
            Write-Host "  ■ Configure : $($_.Data.gpoName)" -ForegroundColor Yellow
        } elseif ($_.Action -eq 'ConfigureAuditRule') {
            Write-Host "  ■ Configure : $($_.TargetDn)" -ForegroundColor Yellow
        }
    }
}

function Add-IncludeAclPhaseToDeploymentPlan {
    param(
        [Parameter(Mandatory)] [hashtable]$DeploymentPlan,
        [Parameter(Mandatory)] [int]$PhaseNumber,
        [Parameter(Mandatory)] [string]$PhaseName,
        [Parameter(Mandatory)] [object]$Plan
    )

    $actionCount = if ($Plan.Summary -and $Plan.Summary.PSObject.Properties.Name -contains 'TotalActions') {
        [int]$Plan.Summary.TotalActions
    } elseif ($Plan.Summary -is [hashtable] -and $Plan.Summary.ContainsKey('TotalActions')) {
        [int]$Plan.Summary['TotalActions']
    } else {
        @($Plan.Actions | Where-Object { $_.Action -in @('CreateAcl', 'ConfigureAuditRule') }).Count
    }
    $createCount = if ($Plan.Summary -and $Plan.Summary.PSObject.Properties.Name -contains 'CreateActions') {
        [int]$Plan.Summary.CreateActions
    } elseif ($Plan.Summary -is [hashtable] -and $Plan.Summary.ContainsKey('CreateActions')) {
        [int]$Plan.Summary['CreateActions']
    } else {
        @($Plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
    }
    # ConfigureActions (e.g. audit SACL converge) fold into ConfigureCount, not CreateCount
    $configureCount = if ($Plan.Summary -and $Plan.Summary.PSObject.Properties.Name -contains 'ConfigureActions') {
        [int]$Plan.Summary.ConfigureActions
    } elseif ($Plan.Summary -is [hashtable] -and $Plan.Summary.ContainsKey('ConfigureActions')) {
        [int]$Plan.Summary['ConfigureActions']
    } else {
        @($Plan.Actions | Where-Object { $_.Action -eq 'ConfigureAuditRule' }).Count
    }
    # When ConfigureActions is present, TotalActions already includes them; avoid double-counting CreateCount
    if ($configureCount -gt 0) { $createCount = 0 }

    $existingCount = if ($Plan.Summary -and $Plan.Summary.PSObject.Properties.Name -contains 'ExistingCount') {
        [int]$Plan.Summary.ExistingCount
    } elseif ($Plan.Summary -is [hashtable] -and $Plan.Summary.ContainsKey('ExistingCount')) {
        [int]$Plan.Summary['ExistingCount']
    } else {
        0
    }

    $DeploymentPlan.CreateCount += $createCount
    $DeploymentPlan.ConfigureCount += $configureCount
    $DeploymentPlan.TotalActions += $actionCount
    $DeploymentPlan.AlreadyExistCount += $existingCount
    $DeploymentPlan.Actions += @($Plan.Actions)
    $DeploymentPlan.Phases += [PSCustomObject]@{
        Phase = $PhaseNumber
        Name = $PhaseName
        ActionCount = $actionCount
        ExistingCount = $existingCount
        Actions = @($Plan.Actions)
    }
}

# Execute deployment based on scope
if ($FullDeployment) {
    Write-Host "=== Full Deployment ===" -ForegroundColor Magenta
    if ($Logging) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Starting Full Deployment sequence"
    }
    
    # Initialize deployment plan tracking
    $deploymentPlan = @{
        TotalActions = 0
        CreateCount = 0
        UpdateCount = 0
        LinkCount = 0
        ConfigureCount = 0
        AlreadyExistCount = 0
        Actions = @()
        Phases = @()
    }
    
    if (-not $ConfirmApply) {
        Write-Host "Building deployment plan..." -ForegroundColor Cyan
        Write-Host "" # Blank line
    }
    
    # Phase 1: OUs - Check what needs to be created
    if (-not $ConfirmApply) {
        Write-Host "Phase 1: Analyzing OUs..." -ForegroundColor Cyan
    }
    $ouResult = Get-TierModelOu -Config $config -DomainController $PreferredDc
    
    if ($ouResult) {
        # Safely handle Actions property - ensure we always get an array
        $ouActions = @()
        if ($ouResult.PSObject.Properties.Name -contains 'Actions' -and $ouResult.Actions) {
            $ouActions = @($ouResult.Actions)
        }
        $ouCreateCount = $ouActions.Count
        $ouExistingCount = if ($ouResult.Summary -and $ouResult.Summary.ExistingCount) { $ouResult.Summary.ExistingCount } else { 0 }
        
        # Add to deployment plan
        $deploymentPlan.CreateCount += $ouCreateCount
        $deploymentPlan.TotalActions += $ouCreateCount
        $deploymentPlan.AlreadyExistCount += $ouExistingCount
        
        # Add phase info
        $deploymentPlan.Phases += [PSCustomObject]@{
            Phase = 1
            Name = "OUs"
            ActionCount = $ouCreateCount
            ExistingCount = $ouExistingCount
            Actions = $ouActions
        }
        
        # Show analysis results for this phase (only if not applying changes)
        if (-not $ConfirmApply -and ($ouCreateCount -gt 0 -or $ouExistingCount -gt 0)) {
            # Show existing OUs first (if any)
            if ($ouExistingCount -gt 0 -and $Config.PSObject.Properties['organizationUnits'] -and $Config.organizationUnits) {
                $Config.organizationUnits | ForEach-Object {
                    $ouName = $_.name
                    # Check if this OU is not in the actions list (meaning it exists)
                    $needsCreation = $ouActions | Where-Object { $_.Name -eq $ouName }
                    if (-not $needsCreation) {
                        Write-Host "  ✅ OU Exists: $ouName" -ForegroundColor Green
                    }
                }
            }
            
            # Show planned actions
            if ($ouCreateCount -gt 0) {
                Write-Host "Planned Actions:" -ForegroundColor Cyan
                $ouActions | ForEach-Object { 
                    Write-Host "  ■ Create OU: $($_.Name)" -ForegroundColor Yellow 
                }
            } elseif ($ouExistingCount -gt 0) {
                Write-Host "  No OU actions needed - all OUs are up to date." -ForegroundColor Green
            }
        }
    }
    
    if (-not $ConfirmApply) {
        Write-Host "" # Blank line
    }
    # Phase 2: Groups - Check what needs to be created (Full Deployment variant)
    if (-not $ConfirmApply) {
        Write-Host "Phase 2: Analyzing Groups..." -ForegroundColor Cyan
    }
    
    # Ensure Get-TierModelGroupFd is loaded (temporary workaround for module loading)
    if (-not (Get-Command Get-TierModelGroupFd -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Get-TierModelGroupFd.ps1"
    }
    
    $groupResult = Get-TierModelGroupFd -Config $config -DomainController $PreferredDc
    
    if ($groupResult) {
        # Safely handle Actions property - ensure we always get an array
        $groupActions = @()
        if ($groupResult.PSObject.Properties.Name -contains 'Actions' -and $groupResult.Actions) {
            $groupActions = @($groupResult.Actions)
        }
        $groupCreateCount = $groupActions.Count
        $groupExistingCount = if ($groupResult.Summary -and $groupResult.Summary.ExistingCount) { $groupResult.Summary.ExistingCount } else { 0 }
        
        # Add to deployment plan
        $deploymentPlan.CreateCount += $groupCreateCount
        $deploymentPlan.TotalActions += $groupCreateCount
        $deploymentPlan.AlreadyExistCount += $groupExistingCount
        
        # Add phase info
        $deploymentPlan.Phases += [PSCustomObject]@{
            Phase = 2
            Name = "Groups"
            ActionCount = $groupCreateCount
            ExistingCount = $groupExistingCount
            Actions = $groupActions
        }
        
        # Show analysis results for this phase (only if not applying changes)
        if (-not $ConfirmApply -and ($groupCreateCount -gt 0 -or $groupExistingCount -gt 0)) {
            # Show existing groups first (if any)
            if ($groupExistingCount -gt 0 -and $Config.PSObject.Properties['groups'] -and $Config.groups) {
                $Config.groups | ForEach-Object {
                    $groupName = $_.name
                    # Check if this group is not in the actions list (meaning it exists)
                    $needsCreation = $groupActions | Where-Object { $_.Name -eq $groupName }
                    if (-not $needsCreation) {
                        Write-Host "  ✅ Group Exists: $groupName" -ForegroundColor Green
                    }
                }
            }
            
            # Show planned actions
            if ($groupCreateCount -gt 0) {
                Write-Host "Planned Actions:" -ForegroundColor Cyan
                $groupActions | ForEach-Object { 
                    Write-Host "  ■ Create Group: $($_.Name)" -ForegroundColor Yellow 
                }
            } elseif ($groupExistingCount -gt 0) {
                Write-Host "  No Group actions needed - all Groups are up to date." -ForegroundColor Green
            }
        }
    }
    
    if (-not $ConfirmApply) {
        Write-Host "" # Blank line
    }
    # Phase 3: Users - Check what needs to be created (Full Deployment variant)
    if (-not $ConfirmApply) {
        Write-Host "Phase 3: Analyzing Users..." -ForegroundColor Cyan
    }
    
    # Ensure Get-TierModelUserFd is loaded (temporary workaround for module loading)
    if (-not (Get-Command Get-TierModelUserFd -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Get-TierModelUserFd.ps1"
    }
    
    $userResult = Get-TierModelUserFd -Config $config -DomainController $PreferredDc
    
    if ($userResult) {
        # Safely handle Actions property - ensure we always get an array
        $userActions = @()
        if ($userResult.PSObject.Properties.Name -contains 'Actions' -and $userResult.Actions) {
            $userActions = @($userResult.Actions)
        }
        $userCreateCount = @($userActions | Where-Object { $_.Action -eq 'CreateUser' }).Count
        $userUpdateCount = @($userActions | Where-Object { $_.Action -eq 'UpdateUserMembership' }).Count
        $userExistingCount = if ($userResult.Summary -and $userResult.Summary.ExistingCount) { $userResult.Summary.ExistingCount } else { 0 }
        
        # Add to deployment plan
        $deploymentPlan.CreateCount += $userCreateCount
        $deploymentPlan.UpdateCount += $userUpdateCount
        $deploymentPlan.TotalActions += ($userCreateCount + $userUpdateCount)
        $deploymentPlan.AlreadyExistCount += $userExistingCount
        
        # Add phase info
        $deploymentPlan.Phases += [PSCustomObject]@{
            Phase = 3
            Name = "Users"
            ActionCount = ($userCreateCount + $userUpdateCount)
            CreateCount = $userCreateCount
            UpdateCount = $userUpdateCount
            ExistingCount = $userExistingCount
            Actions = $userActions
        }
        
        # Show analysis results for this phase (only if not applying changes)
        if (-not $ConfirmApply -and (($userCreateCount + $userUpdateCount) -gt 0 -or $userExistingCount -gt 0)) {
            # Show existing users first (if any)
            if ($userExistingCount -gt 0 -and $Config.PSObject.Properties['users'] -and $Config.users) {
                $Config.users | ForEach-Object {
                    $userName = $_.displayName
                    # Check if this user is not in the actions list (meaning it exists)
                    $needsCreation = $userActions | Where-Object { $_.Action -eq 'CreateUser' -and $_.Name -eq $userName }
                    if (-not $needsCreation) {
                        Write-Host "  ✅ User Exists: $userName" -ForegroundColor Green
                    }
                }
            }
            
            # Show planned actions
            if (($userCreateCount + $userUpdateCount) -gt 0) {
                Write-Host "Planned Actions:" -ForegroundColor Cyan
                $userActions | ForEach-Object {
                    if ($_.Action -eq 'CreateUser') {
                        Write-Host "  ■ Create User: $($_.Name)" -ForegroundColor Yellow 
                    } elseif ($_.Action -eq 'UpdateUserMembership') {
                        Write-Host "  ■ Add to Group: $($_.Name)" -ForegroundColor Yellow 
                    }
                }
            } elseif ($userExistingCount -gt 0) {
                Write-Host "  No User actions needed - all Users are up to date." -ForegroundColor Green
            }
        }
    }
    
    if (-not $ConfirmApply) {
        Write-Host "" # Blank line
    }
    # Phase 4: OU ACLs - Check what needs to be applied (Full Deployment variant)
    if (-not $ConfirmApply) {
        Write-Host "Phase 4: Analyzing OU ACLs..." -ForegroundColor Cyan
    }
    
    # Ensure Get-TierModelOuAclFd is loaded (temporary workaround for module loading)
    if (-not (Get-Command Get-TierModelOuAclFd -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Get-TierModelOuAclFd.ps1"
    }
    
    # Ensure GUID resolution functions are loaded (required by ACL processing)
    if (-not (Get-Command Resolve-TierModelGuid -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Resolve-TierModelGuid.ps1"
    }
    if (-not (Get-Command Resolve-DomainSpecificGuid -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Resolve-DomainSpecificGuid.ps1"
    }
    
    if ($ConfirmApply) {
        $ouAclResult = Get-TierModelOuAclFd -Config $config -DomainController $PreferredDc -Silent
    } else {
        $ouAclResult = Get-TierModelOuAclFd -Config $config -DomainController $PreferredDc
    }
    
    if ($ouAclResult) {
        # Safely handle Actions property - ensure we always get an array
        $ouAclActions = @()
        if ($ouAclResult.PSObject.Properties.Name -contains 'Actions' -and $ouAclResult.Actions) {
            $ouAclActions = @($ouAclResult.Actions)
        }
        $ouAclCreateCount = @($ouAclActions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        $ouAclExistingCount = if ($ouAclResult.Summary -and $ouAclResult.Summary.ExistingCount) { $ouAclResult.Summary.ExistingCount } else { 0 }
        
        # Add to deployment plan
        $deploymentPlan.CreateCount += $ouAclCreateCount  # ACL operations are creates (new ACL entries)
        $deploymentPlan.TotalActions += $ouAclCreateCount
        $deploymentPlan.AlreadyExistCount += $ouAclExistingCount
        
        # Add phase info
        $deploymentPlan.Phases += [PSCustomObject]@{
            Phase = 4
            Name = "OU ACLs"
            ActionCount = $ouAclCreateCount
            ExistingCount = $ouAclExistingCount
            Actions = $ouAclActions
        }
        
        # Show analysis results for this phase (only if not applying changes)
        if (-not $ConfirmApply) {
            if ($ouAclCreateCount -gt 0) {
                $ouAclActions | ForEach-Object {
                    if ($_.Action -eq 'CreateAcl') {
                        # Extract OU name and principal for cleaner display
                        $ouName = if ($_.Path -match '^OU=([^,]+)') { $matches[1] } else { 'Unknown OU' }
                        $principal = $_.Data.identityreference
                        Write-Host "  ■ Create ACL: $principal on $ouName" -ForegroundColor Yellow 
                    }
                }
            } elseif ($Config.PSObject.Properties['aclDelegations'] -and $Config.aclDelegations) {
                Write-Host "  No ACL actions needed - all ACLs are up to date." -ForegroundColor Green
            } else {
                Write-Host "  No ACL delegations configured." -ForegroundColor Gray
            }
        }
    }
    
    if (-not $ConfirmApply) {
        Write-Host "" # Blank line
    }
    # Phase 5: GPOs - Check what needs to be deployed (Full Deployment variant)
    if (-not $ConfirmApply) {
        Write-Host "Phase 5: Analyzing GPOs..." -ForegroundColor Cyan
    }
    
    # Ensure GPO functions are loaded (temporary workaround for module loading)
    if (-not (Get-Command Get-TierModelGpoFd -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Get-TierModelGpoFd.ps1"
    }
    if (-not (Get-Command Get-TierModelGpoLinkFd -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Get-TierModelGpoLinkFd.ps1"
    }
    
    # Use Silent mode when ConfirmApply to suppress detailed output
    if ($ConfirmApply) {
        $gpoResult = Get-TierModelGpoFd -Config $config -DomainController $PreferredDc -Silent
    } else {
        $gpoResult = Get-TierModelGpoFd -Config $config -DomainController $PreferredDc
    }
    
    if ($gpoResult) {
        # Safely handle Actions property - ensure we always get an array
        $gpoActions = @()
        if ($gpoResult.PSObject.Properties.Name -contains 'Actions' -and $gpoResult.Actions) {
            $gpoActions = @($gpoResult.Actions)
        }
        $gpoCreateCount = @($gpoActions | Where-Object { $_.Action -eq 'CreateGPO' }).Count
        $gpoImportCount = @($gpoActions | Where-Object { $_.Action -eq 'ImportGPO' }).Count
        $gpoConfigureCount = @($gpoActions | Where-Object { $_.Action -eq 'ConfigureGPO' }).Count
        $gpoExistingCount = if ($gpoResult.Summary -and $gpoResult.Summary.ExistingCount) { $gpoResult.Summary.ExistingCount } else { 0 }
        
        # Get corrected link analysis from dedicated link function
        if ($ConfirmApply) {
            $gpoLinkResult = Get-TierModelGpoLinkFd -Plan $gpoResult -DomainController $PreferredDc -Silent
        } else {
            $gpoLinkResult = Get-TierModelGpoLinkFd -Plan $gpoResult -DomainController $PreferredDc
        }
        $correctedLinkCount = if ($gpoLinkResult -and $gpoLinkResult.Actions) { @($gpoLinkResult.Actions).Count } else { 0 }
        
        # Replace incorrect LinkGPO actions with corrected ones
        $nonLinkActions = @($gpoActions | Where-Object { $_.Action -ne 'LinkGPO' })
        $correctedLinkActions = if ($gpoLinkResult -and $gpoLinkResult.Actions) { @($gpoLinkResult.Actions) } else { @() }
        $gpoActions = $nonLinkActions + $correctedLinkActions
        
        # Use corrected link count
        $totalGpoLinkCount = $correctedLinkCount
        
        # Add to deployment plan
        $deploymentPlan.CreateCount += $gpoCreateCount  # Creating new GPOs
        $deploymentPlan.UpdateCount += $gpoImportCount  # Updating GPOs with content
        $deploymentPlan.ConfigureCount += $gpoConfigureCount  # Configuring GPO settings
        $deploymentPlan.LinkCount += $totalGpoLinkCount  # Linking GPOs to OUs (from both analyses)
        $deploymentPlan.TotalActions += ($gpoCreateCount + $gpoImportCount + $gpoConfigureCount + $totalGpoLinkCount)
        $deploymentPlan.AlreadyExistCount += $gpoExistingCount
        
        # Add phase info
        $deploymentPlan.Phases += [PSCustomObject]@{
            Phase = 5
            Name = "GPOs"
            ActionCount = ($gpoCreateCount + $gpoImportCount + $gpoConfigureCount + $totalGpoLinkCount)
            ExistingCount = $gpoExistingCount
            Actions = $gpoActions
            CreateCount = $gpoCreateCount
            ImportCount = $gpoImportCount
            ConfigureCount = $gpoConfigureCount
            LinkCount = $totalGpoLinkCount
            LinkResult = $gpoLinkResult
        }
        
        # Analysis results are displayed by the Fd function only in planning mode
        # Skip detailed output when ConfirmApply is specified
    }
    
    if (-not $ConfirmApply) {
        Write-Host "" # Blank line
    }
    # Phase 6: ADMX - Check what needs to be imported/updated
    if (-not $ConfirmApply) {
        Write-Host "Phase 6: Analyzing ADMX templates..." -ForegroundColor Cyan
    }
    
    # Use Silent mode when ConfirmApply to suppress detailed output  
    if ($ConfirmApply) {
        $admxResult = Get-TierModelAdmx -Config $config -DomainController $PreferredDc -Silent
    } else {
        $admxResult = Get-TierModelAdmx -Config $config -DomainController $PreferredDc
    }
    
    if ($admxResult) {
        $admxTotalFiles = if ($admxResult.Summary -and $admxResult.Summary.TotalFiles) { $admxResult.Summary.TotalFiles } else { 0 }
        $admxUpdateCount = if ($admxResult.Summary -and $admxResult.Summary.FilesToUpdate) { $admxResult.Summary.FilesToUpdate } else { 0 }
        $admxUpToDateCount = if ($admxResult.Summary -and $admxResult.Summary.FilesUpToDate) { $admxResult.Summary.FilesUpToDate } else { 0 }
        
        # Add to deployment plan - All ADMX operations are creates (creating files in SYSVOL)
        $deploymentPlan.CreateCount += $admxUpdateCount  # All ADMX files are creates
        $deploymentPlan.TotalActions += $admxUpdateCount
        $deploymentPlan.AlreadyExistCount += $admxUpToDateCount
        
        # Add phase info
        $deploymentPlan.Phases += [PSCustomObject]@{
            Phase = 6
            Name = "ADMX"
            ActionCount = $admxUpdateCount
            ExistingCount = $admxUpToDateCount
            TotalFiles = $admxTotalFiles
            Result = $admxResult
        }
        
        # Show analysis results for this phase (only if not applying changes)
        if (-not $ConfirmApply) {
            if ($admxUpdateCount -gt 0 -or $admxUpToDateCount -gt 0) {
                # Show files that are up to date first (if any)
                if ($admxUpToDateCount -gt 0 -and $admxResult.Analysis) {
                    if ($admxResult.Analysis.AdmxUpToDate) {
                        $admxResult.Analysis.AdmxUpToDate | ForEach-Object {
                            Write-Host "  ✅ ADMX Current: $($_.Name)" -ForegroundColor Green
                        }
                    }
                    if ($admxResult.Analysis.AdmlUpToDate) {
                        $admxResult.Analysis.AdmlUpToDate | ForEach-Object {
                            Write-Host "  ✅ ADML Current: $($_.Name) ($($_.Language))" -ForegroundColor Green
                        }
                    }
                }
                
                # Show planned actions
                if ($admxUpdateCount -gt 0) {
                    Write-Host "Planned Actions:" -ForegroundColor Cyan
                    if ($admxResult.Analysis -and $admxResult.Analysis.AdmxToUpdate) {
                        $admxResult.Analysis.AdmxToUpdate | ForEach-Object {
                            Write-Host "  ■ $($_.ActionType) ADMX: $($_.Name)" -ForegroundColor Yellow
                        }
                    }
                    if ($admxResult.Analysis -and $admxResult.Analysis.AdmlToUpdate) {
                        $admxResult.Analysis.AdmlToUpdate | ForEach-Object {
                            Write-Host "  ■ $($_.ActionType) ADML: $($_.Name) ($($_.Language))" -ForegroundColor Yellow
                        }
                    }
                }
            } elseif ($admxTotalFiles -eq 0) {
                Write-Host "  No ADMX templates configured." -ForegroundColor Gray
            } else {
                Write-Host "  No ADMX actions needed - all templates are current." -ForegroundColor Green
            }
        }
    }
    
    # Phases 7-9: Optional MSA/gMSA/dMSA ACL delegations
    if ($activeIncludeCount -gt 0) {
        if (-not $ConfirmApply) {
            Write-Host "" # Blank line
        }

        if ($IncludeMsa) {
            if (-not $ConfirmApply) {
                Write-Host "Phase 7: MSA ACL Delegations" -ForegroundColor Cyan
            }

            $msaFdPlanParams = @{
                Config = $config
                DomainController = $PreferredDc
                IncludeDetails = $true
            }
            if ($ConfirmApply) { $msaFdPlanParams['Silent'] = $true }
            $msaFdPlan = Get-TierModelMsaAclFd @msaFdPlanParams

            if ($msaFdPlan.Errors -and $msaFdPlan.Errors.Count -gt 0) {
                if (-not $ConfirmApply) {
                    Write-Host "  ❌ MSA planning errors:" -ForegroundColor Red
                    $msaFdPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                }
            } else {
                Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $deploymentPlan -PhaseNumber 7 -PhaseName 'MSA ACL Delegations' -Plan $msaFdPlan
                if (-not $ConfirmApply) {
                    if ($msaFdPlan.Summary.TotalActions -gt 0) {
                        Write-Host "  Actions planned: $($msaFdPlan.Summary.TotalActions)" -ForegroundColor Yellow
                        Write-IncludeAclPlanActions -Actions $msaFdPlan.Actions
                    } else {
                        Write-Host "  ✅ MSA ACL delegations already up to date" -ForegroundColor Green
                    }
                }
            }
        }

        if ($IncludeGmsa) {
            if (-not $ConfirmApply) {
                Write-Host "Phase 8: gMSA ACL Delegations" -ForegroundColor Cyan
            }

            $gmsaFdPlanParams = @{
                Config = $config
                DomainController = $PreferredDc
                IncludeDetails = $true
            }
            if ($ConfirmApply) { $gmsaFdPlanParams['Silent'] = $true }
            $gmsaFdPlan = Get-TierModelGmsaAclFd @gmsaFdPlanParams

            if ($gmsaFdPlan.Errors -and $gmsaFdPlan.Errors.Count -gt 0) {
                if (-not $ConfirmApply) {
                    Write-Host "  ❌ gMSA planning errors:" -ForegroundColor Red
                    $gmsaFdPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                }
            } else {
                Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $deploymentPlan -PhaseNumber 8 -PhaseName 'gMSA ACL Delegations' -Plan $gmsaFdPlan
                if (-not $ConfirmApply) {
                    if ($gmsaFdPlan.Summary.TotalActions -gt 0) {
                        Write-Host "  Actions planned: $($gmsaFdPlan.Summary.TotalActions)" -ForegroundColor Yellow
                        Write-IncludeAclPlanActions -Actions $gmsaFdPlan.Actions
                    } else {
                        Write-Host "  ✅ gMSA ACL delegations already up to date" -ForegroundColor Green
                    }
                }
            }
        }

        if ($IncludeDmsa) {
            if (-not $ConfirmApply) {
                Write-Host "Phase 9: dMSA ACL Delegations" -ForegroundColor Cyan
            }

            $dmsaFdPlanParams = @{
                Config = $config
                DomainController = $PreferredDc
                IncludeDetails = $true
            }
            if ($ConfirmApply) { $dmsaFdPlanParams['Silent'] = $true }
            $dmsaFdPlan = Get-TierModelDmsaAclFd @dmsaFdPlanParams

            if ($dmsaFdPlan.Errors -and $dmsaFdPlan.Errors.Count -gt 0) {
                if (-not $ConfirmApply) {
                    Write-Host "  ❌ dMSA planning errors:" -ForegroundColor Red
                    $dmsaFdPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                }
            } else {
                Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $deploymentPlan -PhaseNumber 9 -PhaseName 'dMSA ACL Delegations' -Plan $dmsaFdPlan
                if (-not $ConfirmApply) {
                    if ($dmsaFdPlan.Summary.TotalActions -gt 0) {
                        Write-Host "  Actions planned: $($dmsaFdPlan.Summary.TotalActions)" -ForegroundColor Yellow
                        Write-IncludeAclPlanActions -Actions $dmsaFdPlan.Actions
                    } else {
                        Write-Host "  ✅ dMSA ACL delegations already up to date" -ForegroundColor Green
                    }
                }
            }
        }

        if ($IncludeWinLaps) {
            if (-not $ConfirmApply) {
                Write-Host "Phase 10: Windows LAPS ACL Delegations" -ForegroundColor Cyan
            }

            $winLapsFdPlanParams = @{
                Config = $config
                DomainController = $PreferredDc
                IncludeDetails = $true
            }
            if ($ConfirmApply) { $winLapsFdPlanParams['Silent'] = $true }
            $winLapsFdPlan = Get-TierModelWinLapsAclFd @winLapsFdPlanParams

            if ($winLapsFdPlan.Errors -and $winLapsFdPlan.Errors.Count -gt 0) {
                if (-not $ConfirmApply) {
                    Write-Host "  ❌ Windows LAPS planning errors:" -ForegroundColor Red
                    $winLapsFdPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                }
            } else {
                Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $deploymentPlan -PhaseNumber 10 -PhaseName 'Windows LAPS ACL Delegations' -Plan $winLapsFdPlan
                if (-not $ConfirmApply) {
                    if ($winLapsFdPlan.Summary.TotalActions -gt 0) {
                        Write-Host "  Actions planned: $($winLapsFdPlan.Summary.TotalActions)" -ForegroundColor Yellow
                        Write-IncludeAclPlanActions -Actions $winLapsFdPlan.Actions
                    } else {
                        Write-Host "  ✅ Windows LAPS ACL delegations already up to date" -ForegroundColor Green
                    }
                }
            }
        }

        if ($EnableAuditing) {
            if (-not $ConfirmApply) {
                Write-Host "Phase 11: Domain Audit Rule (SACL)" -ForegroundColor Cyan
            }

            $auditFdPlanParams = @{
                Config           = $config
                DomainController = $PreferredDc
                IncludeDetails   = $true
            }
            if ($ConfirmApply) { $auditFdPlanParams['Silent'] = $true }
            $auditFdPlan = Get-TierModelAuditRuleFd @auditFdPlanParams

            if ($auditFdPlan.Errors -and $auditFdPlan.Errors.Count -gt 0) {
                if (-not $ConfirmApply) {
                    Write-Host "  ❌ Audit rule planning errors:" -ForegroundColor Red
                    $auditFdPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                }
            } else {
                Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $deploymentPlan -PhaseNumber 11 -PhaseName 'Domain Audit Rule' -Plan $auditFdPlan
                if (-not $ConfirmApply) {
                    if ($auditFdPlan.Summary.TotalActions -gt 0) {
                        Write-Host "  Actions planned: $($auditFdPlan.Summary.TotalActions)" -ForegroundColor Yellow
                        Write-IncludeAclPlanActions -Actions $auditFdPlan.Actions
                    } else {
                        Write-Host "  ✅ Domain audit rule already up to date" -ForegroundColor Green
                    }
                }
            }
        }

        if ($IncludeAuthSilos) {
            if (-not $ConfirmApply) {
                Write-Host "Phase 12: Authentication Policy Silos" -ForegroundColor Cyan
            }

            $authPolicyFdPlan = Get-TierModelAuthPolicyFd -Config $config -DomainController $PreferredDc -IncludeDetails
            $authSiloFdPlan   = Get-TierModelAuthSiloFd   -Config $config -DomainController $PreferredDc -IncludeDetails

            $authSilosHasErrors = ($authPolicyFdPlan.Errors -and $authPolicyFdPlan.Errors.Count -gt 0) -or
                                  ($authSiloFdPlan.Errors   -and $authSiloFdPlan.Errors.Count   -gt 0)

            if ($authSilosHasErrors) {
                if (-not $ConfirmApply) {
                    Write-Host "  ❌ Auth silo planning errors:" -ForegroundColor Red
                    @($authPolicyFdPlan.Errors) + @($authSiloFdPlan.Errors) | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                }
            } else {
                $authSiloPlanTotal = $authPolicyFdPlan.Summary.TotalActions + $authSiloFdPlan.Summary.TotalActions
                $deploymentPlan.TotalActions      += $authSiloPlanTotal
                $deploymentPlan.CreateCount       += $authPolicyFdPlan.Summary.ToCreate + $authSiloFdPlan.Summary.ToCreate
                $deploymentPlan.AlreadyExistCount += $authPolicyFdPlan.Summary.AlreadyExist + $authSiloFdPlan.Summary.AlreadyExist
                $deploymentPlan.Phases += [PSCustomObject]@{
                    Phase       = 12
                    Name        = 'Authentication Policy Silos'
                    ActionCount = $authSiloPlanTotal
                }
                if (-not $ConfirmApply) {
                    # Policy plan line
                    if ($authPolicyFdPlan.Summary.ToCreate -eq 0) {
                        Write-Host "  Auth Policies: all $($authPolicyFdPlan.Summary.TotalInConfig) already deployed" -ForegroundColor Green
                    } else {
                        $authPolicyFdPlan.Actions | Where-Object { $_.Action -eq 'CreateAuthPolicy' } | ForEach-Object { Write-Host "  `u{25A0} Create Authentication Policy: $($_.Name)" -ForegroundColor Yellow }
                    }
                    # Silo plan line
                    if ($authSiloFdPlan.Summary.ToCreate -eq 0) {
                        Write-Host "  Auth Silos:    all $($authSiloFdPlan.Summary.TotalInConfig) already deployed" -ForegroundColor Green
                    } else {
                        $authSiloFdPlan.Actions | Where-Object { $_.Action -eq 'CreateAuthSilo' } | ForEach-Object { Write-Host "  `u{25A0} Create Authentication Policy Silo: $($_.Name)" -ForegroundColor Yellow }
                    }
                    # Membership — only pending for silos that WOULD be created
                    $newSiloNamesForPlan = @($authSiloFdPlan.Actions | Where-Object { $_.Action -eq 'CreateAuthSilo' } | ForEach-Object { $_.Name })
                    $membershipFdPlan = Get-TierModelAuthSiloMembershipFd -Config $config -DomainController $PreferredDc -OnlyForSilos $newSiloNamesForPlan
                    $deploymentPlan.TotalActions      += $membershipFdPlan.Summary.TotalPending
                    $deploymentPlan.AlreadyExistCount += $membershipFdPlan.Summary.TotalAlreadyAssigned
                    if ($membershipFdPlan.Summary.TotalPending -eq 0) {
                        Write-Host "  Membership:    0 pending (all silos already deployed)" -ForegroundColor Gray
                    } else {
                        Write-Host "  Membership:    will assign for $($newSiloNamesForPlan.Count) new silo(s)" -ForegroundColor Yellow
                    }
                }
            }
        }
    }
    
    # Show deployment plan summary (only if not applying changes)
    if (-not $ConfirmApply) {
        Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
        Write-Host "Action count: $($deploymentPlan.TotalActions)" -ForegroundColor White
        Write-Host "Create count: $($deploymentPlan.CreateCount)" -ForegroundColor Yellow
        Write-Host "Update count: $($deploymentPlan.UpdateCount)" -ForegroundColor Yellow
        Write-Host "Link count: $($deploymentPlan.LinkCount)" -ForegroundColor Yellow
        Write-Host "Configure count: $($deploymentPlan.ConfigureCount)" -ForegroundColor Yellow
        Write-Host "Already exist: $($deploymentPlan.AlreadyExistCount)" -ForegroundColor Green
        
        if ($deploymentPlan.TotalActions -gt 0) {
            Write-Host "" # Blank line
            Write-Host "Use -ConfirmApply to execute the deployment plan" -ForegroundColor DarkCyan
            Write-Host "" # Blank line
        }
    }
    
    $ouExecutionResult = $null
    $groupExecutionResult = $null
    $userExecutionResult = $null
    $ouAclExecutionResult = $null
    $gpoExecutionResult = $null
    $admxExecutionResult = $null
    
    if ($ConfirmApply -and $deploymentPlan.TotalActions -gt 0) {
        Write-Host "`nApplying Full Deployment changes..." -ForegroundColor Cyan
        
        # Execute Phase 1: OUs
        if ($deploymentPlan.Phases | Where-Object { $_.Phase -eq 1 -and $_.ActionCount -gt 0 }) {
            Write-Host "Phase 1: Creating OUs..." -ForegroundColor Cyan
            $ouExecutionResult = Invoke-OuDeployment -Config $config -DomainController $PreferredDc -Apply -Silent
            Write-Host "" # Blank line for readability

            $ouCanonCount = if ($ouExecutionResult -and ($ouExecutionResult.PSObject.Properties.Name -contains 'CanonicalRemediations')) { [int]$ouExecutionResult.CanonicalRemediations } else { 0 }
            Write-Host "  Canonical remediation: $ouCanonCount OU DACL(s) auto-corrected during disable-inheritance." -ForegroundColor Cyan

            # HARD-STOP GATE: Halt before Groups (Phase 2) on ANY OU error code.
            # Auto-remediated canonical issues are silent (not in Errors), so no false-halts.
            # Catches: CreateOuFailed, CanonicalRemediationFailed, PfadApplyFailed,
            #          DisableSecurityInheritanceUnverified, BlockGpoInheritanceUnverified.
            $ouHardErrors = @()
            if ($ouExecutionResult -and ($ouExecutionResult.PSObject.Properties.Name -contains 'Errors')) {
                $ouHardErrors = @($ouExecutionResult.Errors | Where-Object {
                    $ouErrCode = if ($_ -is [hashtable]) { $_['Code'] } elseif ($_ -and $_.PSObject.Properties.Name -contains 'Code') { $_.Code } else { $null }
                    $null -ne $ouErrCode
                })
            }
            if (@($ouHardErrors).Count -gt 0) {
                Write-Host "❌ OU deployment errors — halting before Groups (Phase 2)." -ForegroundColor Red
                foreach ($ouErr in $ouHardErrors) {
                    $ouErrMsg = if ($ouErr -is [hashtable]) { $ouErr['Message'] } elseif ($ouErr.PSObject.Properties.Name -contains 'Message') { $ouErr.Message } else { "$ouErr" }
                    Write-Host "    - $ouErrMsg" -ForegroundColor Red
                }
                Write-Host ""
                Write-Host "Remediation steps:" -ForegroundColor Yellow
                Write-Host "  - Delete the affected OU(s) listed above and re-run the deployment to recreate them cleanly." -ForegroundColor Yellow
                Write-Host "  - Do NOT modify these OUs manually. Delete and re-run." -ForegroundColor Yellow
                Write-Host "  - Do NOT modify live/production OUs outside an approved change window; confirm with the audit script." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Deploy script completed." -ForegroundColor Green
                # WI-09: suppressed automatically when both switches are already active.
                Write-TierModelDiagnosticsHint
                # WI-08: guarded — stops the transcript only if THIS script started it.
                Stop-TierModelDiagnosticsTranscript
                exit 1
            }
        }
        
        # Execute Phase 2: Groups
        if ($deploymentPlan.Phases | Where-Object { $_.Phase -eq 2 -and $_.ActionCount -gt 0 }) {
            Write-Host "Phase 2: Creating Groups..." -ForegroundColor Cyan
            $groupExecutionResult = Invoke-GroupDeployment -Config $config -DomainController $PreferredDc -Apply -Silent
            Write-Host "" # Blank line for readability
        }
        
        # Execute Phase 3: Users
        if ($deploymentPlan.Phases | Where-Object { $_.Phase -eq 3 -and $_.ActionCount -gt 0 }) {
            Write-Host "Phase 3: Creating Users..." -ForegroundColor Cyan
            $userExecutionResult = Invoke-UserDeployment -Config $config -DomainController $PreferredDc -Apply -Silent
            Write-Host "" # Blank line for readability
        }
        
        # Execute Phase 4: OU ACLs
        if ($deploymentPlan.Phases | Where-Object { $_.Phase -eq 4 -and $_.ActionCount -gt 0 }) {
            Write-Host "Phase 4: Configuring OU ACLs..." -ForegroundColor Cyan
            $ouAclExecutionResult = Invoke-OuAclDeployment -Config $config -DomainController $PreferredDc -Apply -Silent
            Write-Host "" # Blank line for readability
        }
        
        # Execute Phase 5: GPOs
        if ($deploymentPlan.Phases | Where-Object { $_.Phase -eq 5 -and $_.ActionCount -gt 0 }) {
            Write-Host "Phase 5: Deploying GPOs..." -ForegroundColor Cyan
            $gpoExecutionResult = Invoke-GpoDeployment -Config $config -DomainController $PreferredDc -Apply -Silent
            Write-Host "" # Blank line for readability
        }
        
        # Execute Phase 6: ADMX
        if ($deploymentPlan.Phases | Where-Object { $_.Phase -eq 6 -and $_.ActionCount -gt 0 }) {
            Write-Host "Phase 6: Importing ADMX templates..." -ForegroundColor Cyan
            $phaseResult = ($deploymentPlan.Phases | Where-Object { $_.Phase -eq 6 }).Result
            
            # Use the proper Copy-TierModelAdmx function with the pre-computed analysis
            $copyParams = @{
                Config = $config
                DomainController = $PreferredDc
            }
            
            # Add the analysis if available to avoid re-computation
            if ($phaseResult -and $phaseResult.Analysis) {
                $copyParams.Analysis = $phaseResult.Analysis
            }
            
            try {
                $admxExecutionResult = Copy-TierModelAdmx @copyParams
                if ($admxExecutionResult -and $admxExecutionResult.Summary) {
                    if ($admxExecutionResult.Summary.Successful -gt 0) {
                        Write-Host "  ✅ Successfully deployed $($admxExecutionResult.Summary.Successful) ADMX/ADML files" -ForegroundColor Green
                    }
                    if ($admxExecutionResult.Summary.Failed -gt 0) {
                        Write-Host "  ❌ Failed to deploy $($admxExecutionResult.Summary.Failed) ADMX/ADML files" -ForegroundColor Red
                    }
                    if ($admxExecutionResult.Summary.Successful -eq 0 -and $admxExecutionResult.Summary.Failed -eq 0) {
                        Write-Host "  ✅ No ADMX/ADML files needed deployment" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  ✅ No ADMX/ADML files needed deployment" -ForegroundColor Green
                }
            } catch {
                Write-Host "  ❌ ADMX deployment failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Warning "Failed to deploy ADMX templates: $($_.Exception.Message)"
            }
            
            Write-Host "" # Blank line for readability
        }
        
        Write-Host "Full deployment execution completed." -ForegroundColor Green
        
        # Check if standard deployment had errors (before running optional features)
        $standardDeployHadErrors = $false
        foreach ($r in @($ouExecutionResult, $groupExecutionResult, $userExecutionResult, $ouAclExecutionResult, $gpoExecutionResult, $admxExecutionResult)) {
            if ($null -ne $r) {
                if ($r.PSObject.Properties.Name -contains 'Errors' -and $r.Errors -and @($r.Errors).Count -gt 0) { $standardDeployHadErrors = $true }
                if ($r.PSObject.Properties.Name -contains 'Failed' -and $r.Failed -gt 0) { $standardDeployHadErrors = $true }
                if ($r.PSObject.Properties.Name -contains 'Summary' -and $r.Summary -and $r.Summary.PSObject.Properties.Name -contains 'Failed' -and $r.Summary.Failed -gt 0) { $standardDeployHadErrors = $true }
            }
        }
        
        # === OPTIONAL FEATURES: MSA/gMSA/dMSA/WinLaps ACL Delegations ===
        if ($activeIncludeCount -gt 0 -and -not $standardDeployHadErrors) {
            Write-Host "`n=== Optional Features: MSA/gMSA/dMSA/WinLaps ACL Delegations ===" -ForegroundColor Magenta
            
            # Pass Include switches to prerequisites
            $prereqSplat = @{ PreferredDc = $PreferredDc; DependenciesPath = (Join-Path $PSScriptRoot 'config\dependencies.json') }
            if ($IncludeMsa) { $prereqSplat['IncludeMsa'] = $true }
            if ($IncludeGmsa) { $prereqSplat['IncludeGmsa'] = $true }
            if ($IncludeDmsa) { $prereqSplat['IncludeDmsa'] = $true }
            if ($IncludeWinLaps) { $prereqSplat['IncludeWinLaps'] = $true }
            $msaPrereqs = Test-TierModelPrerequisites @prereqSplat
            
            if (-not $msaPrereqs.Valid) {
                Write-Host "  ❌ MSA/gMSA/dMSA/WinLaps prerequisites failed:" -ForegroundColor Red
                $msaPrereqs.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            } else {
                if ($IncludeMsa) {
                    Write-Host "  Deploying MSA ACL delegations..." -ForegroundColor Cyan
                    $msaPlan = if (Get-Variable msaFdPlan -ErrorAction SilentlyContinue) { $msaFdPlan } else { Get-TierModelMsaAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent }
                    if ($msaPlan.Errors -and $msaPlan.Errors.Count -gt 0) {
                        Write-Host "  ❌ MSA planning errors:" -ForegroundColor Red
                        $msaPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                    } elseif (@($msaPlan.Actions).Count -gt 0) {
                        $msaExecResult = New-TierModelMsaAcl -Plan $msaPlan -DomainController $PreferredDc -Config $config
                    } else {
                        Write-Host "  ✅ MSA ACL delegations already up to date" -ForegroundColor Green
                    }
                }
                if ($IncludeGmsa) {
                    Write-Host "  Deploying gMSA ACL delegations..." -ForegroundColor Cyan
                    $gmsaPlan = if (Get-Variable gmsaFdPlan -ErrorAction SilentlyContinue) { $gmsaFdPlan } else { Get-TierModelGmsaAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent }
                    if ($gmsaPlan.Errors -and $gmsaPlan.Errors.Count -gt 0) {
                        Write-Host "  ❌ gMSA planning errors:" -ForegroundColor Red
                        $gmsaPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                    } elseif (@($gmsaPlan.Actions).Count -gt 0) {
                        $gmsaExecResult = New-TierModelGmsaAcl -Plan $gmsaPlan -DomainController $PreferredDc -Config $config
                    } else {
                        Write-Host "  ✅ gMSA ACL delegations already up to date" -ForegroundColor Green
                    }
                }
                if ($IncludeDmsa) {
                    Write-Host "  Deploying dMSA ACL delegations..." -ForegroundColor Cyan
                    $dmsaPlan = if (Get-Variable dmsaFdPlan -ErrorAction SilentlyContinue) { $dmsaFdPlan } else { Get-TierModelDmsaAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent }
                    if ($dmsaPlan.Errors -and $dmsaPlan.Errors.Count -gt 0) {
                        Write-Host "  ❌ dMSA planning errors:" -ForegroundColor Red
                        $dmsaPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                    } elseif (@($dmsaPlan.Actions).Count -gt 0) {
                        $dmsaExecResult = New-TierModelDmsaAcl -Plan $dmsaPlan -DomainController $PreferredDc -Config $config
                    } else {
                        Write-Host "  ✅ dMSA ACL delegations already up to date" -ForegroundColor Green
                    }
                }
                if ($IncludeWinLaps) {
                    Write-Host "  Deploying Windows LAPS ACL delegations..." -ForegroundColor Cyan
                    # Always regenerate plan fresh at execution time — groups now exist after Phase 2
                    $winLapsPlan = Get-TierModelWinLapsAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent
                    if ($winLapsPlan.Errors -and $winLapsPlan.Errors.Count -gt 0) {
                        Write-Host "  ❌ Windows LAPS planning errors:" -ForegroundColor Red
                        $winLapsPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                    } elseif (@($winLapsPlan.Actions).Count -gt 0) {
                        $winLapsExecResult = New-TierModelWinLapsAcl -Plan $winLapsPlan -DomainController $PreferredDc -Config $config
                    } else {
                        Write-Host "  ✅ Windows LAPS ACL delegations already up to date" -ForegroundColor Green
                    }
                }
                if ($EnableAuditing) {
                    Write-Host "  Deploying domain audit rule (SACL)..." -ForegroundColor Cyan
                    $auditExecPlan = Get-TierModelAuditRuleFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent
                    if ($auditExecPlan.Errors -and $auditExecPlan.Errors.Count -gt 0) {
                        Write-Host "  ❌ Audit rule planning errors:" -ForegroundColor Red
                        $auditExecPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                    } elseif (@($auditExecPlan.Actions).Count -gt 0) {
                        $auditExecResult = New-TierModelAuditRule -Plan $auditExecPlan -DomainController $PreferredDc -Config $config
                    } else {
                        Write-Host "  ✅ Domain audit rule already up to date" -ForegroundColor Green
                    }
                }
                if ($IncludeAuthSilos) {
                    Write-Host "  Deploying Authentication Policy Silos..." -ForegroundColor Cyan
                    # Prerequisite gate — fail fast if groups or OUs are missing
                    $authSilosPrereqFd = Test-TierModelAuthSiloPrerequisite -Config $config -DomainController $PreferredDc
                    if (-not $authSilosPrereqFd.Passed) {
                        Write-Host "  ❌ Auth silo prerequisites not met — skipping silo deployment:" -ForegroundColor Red
                        $authSilosPrereqFd.Failures | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
                    } else {
                        # Auth Policies — create-only, fresh plan at execution time
                        $authPolicyExecPlan = Get-TierModelAuthPolicyFd -Config $config -DomainController $PreferredDc
                        if ($authPolicyExecPlan.Errors -and $authPolicyExecPlan.Errors.Count -gt 0) {
                            Write-Host "  ❌ Auth policy planning errors:" -ForegroundColor Red
                            $authPolicyExecPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                        } elseif (@($authPolicyExecPlan.Actions).Count -gt 0) {
                            $authPolicyExecResult = New-TierModelAuthPolicy -Plan $authPolicyExecPlan -DomainController $PreferredDc
                        }
                        # Auth Silos — create-only
                        $authSiloExecPlan = Get-TierModelAuthSiloFd -Config $config -DomainController $PreferredDc
                        if ($authSiloExecPlan.Errors -and $authSiloExecPlan.Errors.Count -gt 0) {
                            Write-Host "  ❌ Auth silo planning errors:" -ForegroundColor Red
                            $authSiloExecPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                        } elseif (@($authSiloExecPlan.Actions).Count -gt 0) {
                            $authSiloExecResult = New-TierModelAuthSilo -Plan $authSiloExecPlan -DomainController $PreferredDc
                        }
                        # Membership — create-once: only assign for silos created in this run
                        $newlyCreatedSilosFd = @(if (Get-Variable authSiloExecResult -ErrorAction SilentlyContinue) { $authSiloExecResult.CreatedSiloNames } else { @() })
                        if ($newlyCreatedSilosFd.Count -gt 0) {
                            $authMembershipExecResult = Set-TierModelAuthSiloMembership -Config $config -DomainController $PreferredDc -OnlyForSilos $newlyCreatedSilosFd
                        } elseif (@($authPolicyExecPlan.Actions).Count -eq 0 -and @($authSiloExecPlan.Actions).Count -eq 0) {
                            Write-Host "  ✅ Already deployed — nothing to create" -ForegroundColor Green
                        }
                    }
                }
            }
        } elseif ($activeIncludeCount -gt 0 -and $standardDeployHadErrors) {
            Write-Host "`n⚠️  Skipping optional MSA/gMSA/dMSA/WinLaps features due to errors in standard deployment." -ForegroundColor Yellow
        }
        
        # Show consolidated deployment results
        Write-Host "`n=== Deployment Results ===" -ForegroundColor Blue
        
        # Collect all execution results
        $allResults = @()
        if (Get-Variable ouExecutionResult -ErrorAction SilentlyContinue) { $allResults += $ouExecutionResult }
        if (Get-Variable groupExecutionResult -ErrorAction SilentlyContinue) { $allResults += $groupExecutionResult }
        if (Get-Variable userExecutionResult -ErrorAction SilentlyContinue) { $allResults += $userExecutionResult }
        if (Get-Variable ouAclExecutionResult -ErrorAction SilentlyContinue) { $allResults += $ouAclExecutionResult }
        if (Get-Variable gpoExecutionResult -ErrorAction SilentlyContinue) { $allResults += $gpoExecutionResult }
        if (Get-Variable admxExecutionResult -ErrorAction SilentlyContinue) { $allResults += $admxExecutionResult }
        if (Get-Variable msaExecResult -ErrorAction SilentlyContinue) { $allResults += $msaExecResult }
        if (Get-Variable gmsaExecResult -ErrorAction SilentlyContinue) { $allResults += $gmsaExecResult }
        if (Get-Variable dmsaExecResult -ErrorAction SilentlyContinue) { $allResults += $dmsaExecResult }
        if (Get-Variable winLapsExecResult -ErrorAction SilentlyContinue) { $allResults += $winLapsExecResult }
        if (Get-Variable auditExecResult -ErrorAction SilentlyContinue) { $allResults += $auditExecResult }
        if (Get-Variable authPolicyExecResult -ErrorAction SilentlyContinue) { $allResults += $authPolicyExecResult }
        if (Get-Variable authSiloExecResult -ErrorAction SilentlyContinue) { $allResults += $authSiloExecResult }
        if (Get-Variable authMembershipExecResult -ErrorAction SilentlyContinue) { $allResults += $authMembershipExecResult }
        
        # Calculate consolidated counts
        $totalApplied = 0
        $totalSkipped = 0
        $totalErrors = 0
        $totalDuration = 0
        $overallConverged = $true
        
        foreach ($result in $allResults) {
            if ($result) {
                # Handle different result object structures
                if ($result.PSObject.Properties.Name -contains 'Applied' -and $result.Applied) {
                    $totalApplied += @($result.Applied).Count
                }
                if ($result.PSObject.Properties.Name -contains 'Executed' -and $result.Executed) {
                    $totalApplied += $result.Executed
                }
                if ($result.PSObject.Properties.Name -contains 'Summary' -and $result.Summary -and $result.Summary.PSObject.Properties.Name -contains 'Successful') {
                    $totalApplied += $result.Summary.Successful
                }
                
                if ($result.PSObject.Properties.Name -contains 'Skipped' -and $result.Skipped) {
                    $totalSkipped += if ($result.Skipped -is [int]) { $result.Skipped } else { @($result.Skipped).Count }
                }
                
                if ($result.PSObject.Properties.Name -contains 'Errors' -and $result.Errors) {
                    $totalErrors += @($result.Errors).Count
                }
                if ($result.PSObject.Properties.Name -contains 'Failed' -and $result.Failed) {
                    $totalErrors += $result.Failed
                }
                if ($result.PSObject.Properties.Name -contains 'Summary' -and $result.Summary -and $result.Summary.PSObject.Properties.Name -contains 'Failed') {
                    $totalErrors += $result.Summary.Failed
                }
                
                if ($result.PSObject.Properties.Name -contains 'DurationMs' -and $result.DurationMs) {
                    $totalDuration += $result.DurationMs
                }
                
                if ($result.PSObject.Properties.Name -contains 'Converged' -and -not $result.Converged) {
                    $overallConverged = $false
                }
            }
        }
        
        # Display consolidated results
        Write-Host "Applied: $totalApplied" -ForegroundColor Green
        Write-Host "Skipped: $totalSkipped" -ForegroundColor Yellow
        Write-Host "Errors: $totalErrors" -ForegroundColor $(if ($totalErrors -gt 0) { 'Red' } else { 'Green' })
        Write-Host "Duration: $(Format-TierModelDuration $totalDuration)" -ForegroundColor Gray
        Write-Host "Converged: $overallConverged" -ForegroundColor $(if ($overallConverged) { 'Green' } else { 'Yellow' })
        
    } elseif ($ConfirmApply -and $deploymentPlan.TotalActions -eq 0) {
        Write-Host "`nNo actions required - all components are up to date." -ForegroundColor Green
        
        # Show deployment results even when no actions needed
        Write-Host "`n=== Deployment Results ===" -ForegroundColor Blue
        Write-Host "Applied: 0" -ForegroundColor Green
        Write-Host "Skipped: 0" -ForegroundColor Yellow
        Write-Host "Errors: 0" -ForegroundColor Green
        Write-Host "Duration: $(Format-TierModelDuration 0)" -ForegroundColor Gray
        Write-Host "Converged: True" -ForegroundColor Green
    }
}
else {
    # Single-entity operations show immediate reports
    if ($OuOnly) { 
        Write-Host "=== OU-Only Deployment ===" -ForegroundColor Magenta
        if ($Logging) {
            Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Starting OU-Only deployment"
        }
        $ouResult = Invoke-OuDeployment -Config $config -DomainController $PreferredDc -Apply:$ConfirmApply
        
        # Show deployment plan summary for OU-only operations
        if ($ouResult) {
            Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
            
            # Determine action count based on whether this is a plan or execution result
            $actionCount = 0
            try {
                # Check for planning mode result (has Actions property)
                if ($ouResult.PSObject.Properties.Name -contains 'Actions') {
                    $actionCount = if ($ouResult.Actions) { @($ouResult.Actions).Count } else { 0 }
                }
                # Check for execution mode result (has Applied property)  
                elseif ($ouResult.PSObject.Properties.Name -contains 'Applied') {
                    $actionCount = if ($ouResult.Applied) { @($ouResult.Applied).Count } else { 0 }
                }
                # Fallback: check if it has PlanErrors indicating error during planning
                elseif ($ouResult.PSObject.Properties.Name -contains 'PlanErrors') {
                    $actionCount = 0  # No actions possible if planning failed
                }
                else {
                    Write-Host "Warning: Unknown result object structure, defaulting to 0 actions" -ForegroundColor Yellow
                    $actionCount = 0
                }
            }
            catch {
                Write-Host "Warning: Could not determine action count from result object: $($_.Exception.Message)" -ForegroundColor Yellow
                $actionCount = 0
            }
            
            $createCount = $actionCount  # For OUs, all actions are creates
            $lowRiskCount = $actionCount  # OU operations are considered low risk
            
            Write-Host "Action count: $actionCount" -ForegroundColor White
            Write-Host "Create count: $createCount" -ForegroundColor Yellow  
            Write-Host "Low risk: $lowRiskCount" -ForegroundColor Cyan
            
            # Add duration and convergence info when using ConfirmApply
            if ($ConfirmApply -and $ouResult.PSObject.Properties.Name -contains 'DurationMs') {
                Write-Host "Duration: $(Format-TierModelDuration $ouResult.DurationMs)" -ForegroundColor Gray
                Write-Host "Converged: $($ouResult.Converged)" -ForegroundColor $(if ($ouResult.Converged) { 'Green' } else { 'Yellow' })
            }
            if ($ConfirmApply) {
                $canonCount = if ($ouResult.PSObject.Properties.Name -contains 'CanonicalRemediations') { [int]$ouResult.CanonicalRemediations } else { 0 }
                Write-Host "Canonical remediation: $canonCount OU DACL(s) auto-corrected during disable-inheritance." -ForegroundColor Cyan
            }
        }
    }
    if ($GroupOnly) {
        Write-Host "=== Groups-Only Deployment ===" -ForegroundColor Magenta
        if ($Logging) {
            Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Starting Groups-Only deployment"
        }
        $groupResult = Invoke-GroupDeployment -Config $config -DomainController $PreferredDc -Apply:$ConfirmApply
        
        # Show deployment plan summary for Groups-only operations
        if ($groupResult) {
            Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
            
            # Check if there are dependency errors
            $hasErrors = $groupResult.PSObject.Properties.Name -contains 'Errors' -and $groupResult.Errors -and @($groupResult.Errors).Count -gt 0
            
            if ($hasErrors) {
                Write-Host "Resolve all dependency errors before proceeding with Group deployment" -ForegroundColor Red
                Write-TierModelBlockedOutcome -Phase 'Group' -Errors @($groupResult.Errors)
            } else {
                # Only show detailed counts when there are no dependency errors
                $actionCount = 0
                try {
                    # Check for planning mode result (has Actions property)
                    if ($groupResult.PSObject.Properties.Name -contains 'Actions') {
                        $actionCount = if ($groupResult.Actions) { @($groupResult.Actions).Count } else { 0 }
                    }
                    # Check for execution mode result (has Applied property)  
                    elseif ($groupResult.PSObject.Properties.Name -contains 'Applied') {
                        $actionCount = if ($groupResult.Applied) { @($groupResult.Applied).Count } else { 0 }
                    }
                }
                catch {
                    $actionCount = 0
                }
                
                $createCount = $actionCount  # For Groups, all actions are creates
                $lowRiskCount = $actionCount  # Group operations are considered low risk
                
                Write-Host "Action count: $actionCount" -ForegroundColor White
                Write-Host "Create count: $createCount" -ForegroundColor Yellow  
                Write-Host "Low risk: $lowRiskCount" -ForegroundColor Cyan
                
                # Add duration and convergence info when using ConfirmApply
                if ($ConfirmApply -and $groupResult.PSObject.Properties.Name -contains 'DurationMs') {
                    Write-Host "Duration: $(Format-TierModelDuration $groupResult.DurationMs)" -ForegroundColor Gray
                    Write-Host "Converged: $($groupResult.Converged)" -ForegroundColor $(if ($groupResult.Converged) { 'Green' } else { 'Yellow' })
                }
            }
        }
    }
    if ($UserOnly) { 
        Write-Host "=== User-Only Deployment ===" -ForegroundColor Magenta
        # Explicitly pass parameters to avoid WhatIf parameter conflicts
        $userParams = @{
            Config = $config
            DomainController = $PreferredDc
            Apply = $ConfirmApply
        }
        # Non-Silent (mirrors -GroupOnly): Invoke-UserDeployment prints "Analyzing User
        # requirements..." + "User Plan Summary" + "Dependency Errors". Per-user existence
        # noise is suppressed inside the function via Get-TierModelUser -Silent.
        $userResult = Invoke-UserDeployment @userParams
        
        # Show deployment plan summary for User-only operations
        if ($userResult) {
            Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
            
            # Check if there are dependency errors
            $hasErrors = $userResult.PSObject.Properties.Name -contains 'Errors' -and $userResult.Errors -and @($userResult.Errors).Count -gt 0
            
            if ($hasErrors) {
                Write-Host "Resolve all dependency errors before proceeding with User deployment" -ForegroundColor Red
                Write-TierModelBlockedOutcome -Phase 'User' -Errors @($userResult.Errors)
            } else {
                # Only show detailed counts when there are no dependency errors
                $createCount = 0
                $updateCount = 0
                $actionCount = 0
                
                # Count different action types separately for both planning and execution modes
                if ($userResult.PSObject.Properties.Name -contains 'Actions' -and $userResult.Actions) {
                    # Planning mode - count planned actions by type
                    $createCount = (@($userResult.Actions | Where-Object { $_.Action -eq 'CreateUser' })).Count
                    $updateCount = (@($userResult.Actions | Where-Object { $_.Action -eq 'UpdateUserMembership' })).Count
                    $actionCount = $createCount + $updateCount
                }
                elseif ($userResult.PSObject.Properties.Name -contains 'Applied' -and $userResult.Applied) {
                    # Execution mode - the Applied array only shows CreateUser actions, but we need to account for group memberships too
                    # For Users, each successful user creation also includes group membership updates
                    # So if we executed N users successfully, we had N creates + N updates (assuming each user has group memberships)
                    $executedUsers = @($userResult.Applied).Count
                    $createCount = $executedUsers  # One create per user
                    $updateCount = $executedUsers  # One update per user (group membership)
                    $actionCount = $createCount + $updateCount  # Total actions performed
                }
                
                $lowRiskCount = $actionCount  # User operations are considered low risk
                
                Write-Host "Action count: $actionCount" -ForegroundColor White
                Write-Host "Create count: $createCount" -ForegroundColor Yellow
                Write-Host "Update count: $updateCount" -ForegroundColor Yellow
                Write-Host "Low risk: $lowRiskCount" -ForegroundColor Cyan
                
                # Add duration and convergence info when using ConfirmApply
                if ($ConfirmApply -and $userResult.PSObject.Properties.Name -contains 'DurationMs') {
                    Write-Host "Duration: $(Format-TierModelDuration $userResult.DurationMs)" -ForegroundColor Gray
                    Write-Host "Converged: $($userResult.Converged)" -ForegroundColor $(if ($userResult.Converged) { 'Green' } else { 'Yellow' })
                }
            }
        }
        
        # Results are now shown in the consolidated Deployment Results section
    }
    if ($OuAclsOnly) {
        Write-Host "=== OU ACL-Only Deployment ===" -ForegroundColor Magenta
        # Explicitly pass parameters to avoid WhatIf parameter conflicts
        $ouAclParams = @{
            Config = $config
            DomainController = $PreferredDc
            Apply = $ConfirmApply
        }
        $ouAclResult = Invoke-OuAclDeployment @ouAclParams
        
        # Show deployment plan summary for OU ACL-only operations
        if ($ouAclResult) {
            if ($ConfirmApply) {
                Write-Host "`n=== Deployment Results ===" -ForegroundColor Blue
            } else {
                Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
            }
            
            # Check if there are dependency errors
            $hasErrors = $ouAclResult.PSObject.Properties.Name -contains 'Errors' -and $ouAclResult.Errors -and @($ouAclResult.Errors).Count -gt 0
            
            if ($hasErrors) {
                Write-Host "Resolve all dependency errors before proceeding with OU ACL deployment" -ForegroundColor Red
                Write-TierModelBlockedOutcome -Phase 'OU ACL' -Errors @($ouAclResult.Errors)
            } else {
                # Only show detailed counts when there are no dependency errors
                $actionCount = 0
                try {
                    # Check for planning mode result (has Actions property)
                    if ($ouAclResult.PSObject.Properties.Name -contains 'Actions') {
                        $actionCount = if ($ouAclResult.Actions) { @($ouAclResult.Actions).Count } else { 0 }
                    }
                    # Check for execution mode result (has Applied property)  
                    elseif ($ouAclResult.PSObject.Properties.Name -contains 'Applied') {
                        $actionCount = if ($ouAclResult.Applied) { @($ouAclResult.Applied).Count } else { 0 }
                    }
                }
                catch {
                    $actionCount = 0
                }
                
                $createCount = $actionCount  # For OU ACLs, all actions are creates
                $lowRiskCount = $actionCount  # OU ACL operations are considered low risk
                
                Write-Host "Action count: $actionCount" -ForegroundColor White
                Write-Host "Create count: $createCount" -ForegroundColor Yellow  
                Write-Host "Low risk: $lowRiskCount" -ForegroundColor Cyan
                
                # Add duration and convergence info when using ConfirmApply
                if ($ConfirmApply -and $ouAclResult.PSObject.Properties.Name -contains 'DurationMs') {
                    Write-Host "Duration: $(Format-TierModelDuration $ouAclResult.DurationMs)" -ForegroundColor Gray
                    Write-Host "Converged: $($ouAclResult.Converged)" -ForegroundColor $(if ($ouAclResult.Converged) { 'Green' } else { 'Yellow' })
                }
            }
        }
        
        # Results are now shown in the consolidated Deployment Results section above
    }
    if ($GposOnly) {
        Write-Host "=== GPO-Only Deployment ===" -ForegroundColor Magenta
        if ($Logging) {
            Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Starting GPO-Only deployment"
        }
        $gpoParams = @{
            Config = $config
            DomainController = $PreferredDc
            Apply = $ConfirmApply
        }
        $gpoResult = Invoke-GpoDeployment @gpoParams
        
        # Show deployment plan summary for GPO-only operations
        if ($gpoResult) {
            Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
            
            # Check if there are dependency errors
            $hasErrors = $gpoResult.PSObject.Properties.Name -contains 'Errors' -and $gpoResult.Errors -and $gpoResult.Errors.Count -gt 0
            
            if ($hasErrors) {
                Write-Host "Resolve all dependency errors before proceeding with GPO deployment" -ForegroundColor Red
                Write-TierModelSkippedGpoReport -Plan $gpoResult
                $gpoSkipped = if ($gpoResult.PSObject.Properties.Name -contains 'SkippedGpos') { @($gpoResult.SkippedGpos) } else { @() }
                Write-TierModelBlockedOutcome -Phase 'GPO' -Errors @($gpoResult.Errors) -SkippedItems $gpoSkipped
            } else {
                # Access the plan data from the result object
                $plan = $null
                if ($gpoResult.PSObject.Properties.Name -contains 'Plan' -and $gpoResult.Plan) {
                    $plan = $gpoResult.Plan
                }
                
                # Calculate action counts from the plan Summary
                $actionCount = 0
                $createCount = 0
                $importCount = 0
                $configureCount = 0
                $linkCount = 0
                
                try {
                    if ($ConfirmApply) {
                        # For execution mode, get total executed count but also show breakdown from the plan that was executed
                        $actionCount = if ($gpoResult.Executed) { $gpoResult.Executed } else { 0 }
                        
                        # Get the actual action breakdown from the plan that was executed
                        if ($plan -and $plan.PSObject.Properties.Name -contains 'Summary' -and $plan.Summary) {
                            $createCount = if ($plan.Summary.CreateActions) { $plan.Summary.CreateActions } else { 0 }
                            $importCount = if ($plan.Summary.ImportActions) { $plan.Summary.ImportActions } else { 0 }
                            $configureCount = if ($plan.Summary.ConfigureActions) { $plan.Summary.ConfigureActions } else { 0 }
                            $linkCount = if ($plan.Summary.LinkActions) { $plan.Summary.LinkActions } else { 0 }
                        } else {
                            # Fallback if no plan breakdown available
                            $createCount = $actionCount
                            $importCount = 0
                            $configureCount = 0
                            $linkCount = 0
                        }
                    } else {
                        # For planning mode, get counts from plan Summary
                        if ($plan -and $plan.PSObject.Properties.Name -contains 'Summary' -and $plan.Summary) {
                            $actionCount = if ($plan.Summary.TotalActions) { $plan.Summary.TotalActions } else { 0 }
                            $createCount = if ($plan.Summary.CreateActions) { $plan.Summary.CreateActions } else { 0 }
                            $importCount = if ($plan.Summary.ImportActions) { $plan.Summary.ImportActions } else { 0 }
                            $configureCount = if ($plan.Summary.ConfigureActions) { $plan.Summary.ConfigureActions } else { 0 }
                            $linkCount = if ($plan.Summary.LinkActions) { $plan.Summary.LinkActions } else { 0 }
                        }
                    }
                }
                catch {
                    $actionCount = 0
                }
                
                Write-Host "Action count: $actionCount" -ForegroundColor White
                Write-Host "To Create: $createCount" -ForegroundColor Yellow
                Write-Host "To Import: $importCount" -ForegroundColor Yellow  
                Write-Host "To Configure: $configureCount" -ForegroundColor Yellow
                Write-Host "To Link: $linkCount" -ForegroundColor Yellow
                
                # Add duration and convergence info when using ConfirmApply
                if ($ConfirmApply -and $gpoResult.PSObject.Properties.Name -contains 'DurationMs') {
                    Write-Host "Duration: $(Format-TierModelDuration $gpoResult.DurationMs)" -ForegroundColor Gray
                    Write-Host "Converged: $($gpoResult.Converged)" -ForegroundColor $(if ($gpoResult.Converged) { 'Green' } else { 'Yellow' })
                }
                
                if (-not $ConfirmApply) {
                    Write-Host "" # Blank line
                    Write-Host "Use -ConfirmApply to execute the deployment plan" -ForegroundColor DarkCyan
                    Write-Host "" # Blank line
                }
            }
        }
        
        # GPO deployment results are now handled in the deployment plan section above
    }
    if ($AdmxOnly) {
        Write-Host "=== ADMX-Only Deployment ===" -ForegroundColor Magenta
        Write-Host "Deploying ADMX/ADML templates..." -ForegroundColor Cyan
        
        if ($ConfirmApply) {
            # Execute ADMX deployment
            $admxResult = Copy-TierModelAdmx -Config $config -DomainController $PreferredDc -AdmlLanguage $AdmlLanguage
            
            if ($admxResult.Results.AdmxFailed -and $admxResult.Results.AdmxFailed.Count -gt 0) {
                Write-Host "`nADMX Deployment Errors:" -ForegroundColor Red
                $admxResult.Results.AdmxFailed | ForEach-Object { Write-Host "  ❌ $($_.FileInfo.Name): $($_.Error)" -ForegroundColor Red }
            }
            if ($admxResult.Results.AdmlFailed -and $admxResult.Results.AdmlFailed.Count -gt 0) {
                Write-Host "`nADML Deployment Errors:" -ForegroundColor Red
                $admxResult.Results.AdmlFailed | ForEach-Object { Write-Host "  ❌ $($_.FileInfo.Name): $($_.Error)" -ForegroundColor Red }
            }
        } else {
            # Planning mode - analyze what needs to be done
            $admxPlan = Get-TierModelAdmx -Config $config -DomainController $PreferredDc -AdmlLanguage $AdmlLanguage
            
            # Calculate create vs update counts based on action types
            $createCount = 0
            $updateCount = 0
            
            # Count creates (new files) and updates (existing files needing replacement)
            if ($admxPlan.Analysis.AdmxToUpdate) {
                $admxPlan.Analysis.AdmxToUpdate | ForEach-Object { 
                    if ($_.ActionType -eq 'Import') { $createCount++ } else { $updateCount++ }
                }
            }
            if ($admxPlan.Analysis.AdmlToUpdate) {
                $admxPlan.Analysis.AdmlToUpdate | ForEach-Object { 
                    if ($_.ActionType -eq 'Import') { $createCount++ } else { $updateCount++ }
                }
            }
            
            # Split analysis errors the same way Copy-TierModelAdmx does, so the plan matches
            # what -ConfirmApply will actually do. A per-file source problem no longer aborts
            # the phase, so it must not be reported here as a blocking dependency error.
            $admxPerFilePattern = '^Source (ADMX|ADML) file (not found|hash mismatch)'
            $admxAllErrors = @($admxPlan.Analysis.Errors)
            $admxSkipErrors = @($admxAllErrors | Where-Object { $_ -and $_ -match $admxPerFilePattern })
            # @() is mandatory: PowerShell unrolls a returned array, so an empty result comes
            # back as $null and .Count then throws under Set-StrictMode.
            $admxFatalErrors = @(Get-TierModelAdmxFatalError -Errors $admxAllErrors)

            Write-Host "ADMX Plan Summary:" -ForegroundColor White
            Write-Host "  Total in Config: $($admxPlan.Summary.TotalFiles)" -ForegroundColor Gray
            Write-Host "  To Create: $createCount" -ForegroundColor Yellow
            Write-Host "  To Update: $updateCount" -ForegroundColor Yellow
            Write-Host "  Already Exist: $($admxPlan.Summary.FilesUpToDate)" -ForegroundColor Green
            if ($admxSkipErrors.Count -gt 0) {
                # Files failing source validation are counted in TotalFiles but are in neither
                # ToUpdate nor UpToDate - report them so the numbers reconcile.
                Write-Host "  Will Be Skipped: $($admxSkipErrors.Count)" -ForegroundColor Yellow
            }

            if ($admxSkipErrors.Count -gt 0) {
                Write-Host "Source file validation warnings - these files will be SKIPPED:" -ForegroundColor Yellow
                $admxSkipErrors | ForEach-Object { Write-Host "  ⚠️  $_" -ForegroundColor Yellow }
                Write-Host "  All remaining files will still be deployed." -ForegroundColor Yellow
            }
            if ($admxFatalErrors.Count -gt 0) {
                Write-Host "Dependency Errors:" -ForegroundColor Red
                $admxFatalErrors | ForEach-Object { Write-Host "  ❌ $_" -ForegroundColor Red }
            }
            
            # Show planned actions
            if ($admxPlan.Summary.FilesToUpdate -gt 0) {
                Write-Host "" # Blank line for spacing
                Write-Host "Planned Actions:" -ForegroundColor Cyan
                $admxPlan.Analysis.AdmxToUpdate | ForEach-Object { 
                    $actionType = if ($_.ActionType -eq 'Import') { if ($_.Reason -like "*not present*" -or $_.Reason -like "*new import*") { 'Import' } else { 'Update' } } else { 'Update' }
                    Write-Host "  ■ ADMX: [$actionType] $($_.Name) - $($_.Reason)" -ForegroundColor Yellow 
                }
                $admxPlan.Analysis.AdmlToUpdate | ForEach-Object { 
                    $actionType = if ($_.ActionType -eq 'Import') { if ($_.Reason -like "*not present*" -or $_.Reason -like "*new import*") { 'Import' } else { 'Update' } } else { 'Update' }
                    Write-Host "  ■ ADML: [$actionType] $($_.Name) - $($_.Reason)" -ForegroundColor Yellow 
                }
            } else {
                Write-Host "  No actions needed - all ADMX/ADML files are up to date." -ForegroundColor Green
            }
        }
        
        # Show appropriate summary section based on mode
        if ($ConfirmApply -and $admxResult) {
            # Execution mode - show deployment results
            Write-Host "`n=== Deployment Results ===" -ForegroundColor Blue
            $totalActions = $admxResult.Summary.Successful + $admxResult.Summary.Failed
            $createCount = if ($admxResult.Results.AdmxSuccessful) { @($admxResult.Results.AdmxSuccessful | Where-Object { $_.ActionType -eq 'Import' }).Count } else { 0 }
            $createCount += if ($admxResult.Results.AdmlSuccessful) { @($admxResult.Results.AdmlSuccessful | Where-Object { $_.ActionType -eq 'Import' }).Count } else { 0 }
            $updateCount = $totalActions - $createCount
            
            Write-Host "Action count: $totalActions" -ForegroundColor White
            Write-Host "Create count: $createCount" -ForegroundColor Yellow
            Write-Host "Update count: $updateCount" -ForegroundColor Yellow
            Write-Host "Low risk: $totalActions" -ForegroundColor Cyan
            Write-Host "Duration: $(Format-TierModelDuration $admxResult.DurationMs)" -ForegroundColor Gray
            Write-Host "Converged: $(if ($admxResult.Summary.Failed -eq 0) { 'True' } else { 'False' })" -ForegroundColor $(if ($admxResult.Summary.Failed -eq 0) { 'Green' } else { 'Yellow' })
        } elseif ($admxPlan) {
            # Planning mode - show deployment plan
            Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
            
            # Check if there are dependency errors
            # Only genuinely fatal analysis errors block the ADMX phase - per-file source
            # problems are skipped by Copy-TierModelAdmx and the rest still deploys.
            $admxBlockingErrors = @(Get-TierModelAdmxFatalError -Errors @($admxPlan.Analysis.Errors))
            $hasErrors = $admxBlockingErrors.Count -gt 0
            
            if ($hasErrors) {
                Write-Host "Resolve all dependency errors before proceeding with ADMX deployment" -ForegroundColor Red
                Write-TierModelBlockedOutcome -Phase 'ADMX' -Errors $admxBlockingErrors
            } else {
                # Calculate total actions (creates + updates)
                $actionCount = $createCount + $updateCount
                $lowRiskCount = $actionCount  # ADMX operations are considered low risk
                
                Write-Host "Action count: $actionCount" -ForegroundColor White
                Write-Host "Import count: $createCount" -ForegroundColor Yellow
                Write-Host "Update count: $updateCount" -ForegroundColor Yellow
                Write-Host "Low risk: $lowRiskCount" -ForegroundColor Cyan
            }
        }
    }
}

# === Standalone -Include* Mode (no scope parameter) ===
if ($activeScopeCount -eq 0 -and $activeIncludeCount -gt 0) {
    Write-Host "`n=== Standalone MSA/gMSA/dMSA/WinLaps ACL Deployment ===" -ForegroundColor Magenta
    
    # Load config
    $config = Get-TierModelConfig
    Write-Host "TierModel module loaded successfully." -ForegroundColor Green
    
    # Feature prerequisites (-Include*) were already validated up front (fail-fast) before any
    # scope/standalone work began, so no re-validation is needed here.
    $standaloneResults = @()
    $standaloneTotalApplied = 0
    $standaloneTotalSkipped = 0
    $standaloneTotalErrors = 0
    $standaloneTotalDuration = 0
    $standaloneConverged = $true
    $standaloneDeploymentPlan = @{
        TotalActions = 0
        CreateCount = 0
        UpdateCount = 0
        LinkCount = 0
        ConfigureCount = 0
        AlreadyExistCount = 0
        Actions = @()
        Phases = @()
    }
    
    if ($IncludeMsa) {
        Write-Host "`nPhase: MSA ACL Delegations" -ForegroundColor Cyan
        $msaPlan = Get-TierModelMsaAcl -Config $config -DomainController $PreferredDc
        if ($msaPlan.Errors -and $msaPlan.Errors.Count -gt 0) {
            Write-Host "  ❌ MSA planning errors:" -ForegroundColor Red
            $msaPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
            $standaloneTotalErrors += $msaPlan.Errors.Count
        } else {
            Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $standaloneDeploymentPlan -PhaseNumber 1 -PhaseName 'MSA ACL Delegations' -Plan $msaPlan
            if ($msaPlan.Summary.TotalActions -gt 0) {
                Write-Host "  Actions planned: $($msaPlan.Summary.TotalActions)" -ForegroundColor Yellow
                if (-not $ConfirmApply) {
                    Write-IncludeAclPlanActions -Actions $msaPlan.Actions
                }
                if ($ConfirmApply) {
                    $msaResult = New-TierModelMsaAcl -Plan $msaPlan -DomainController $PreferredDc -Config $config
                    $standaloneResults += $msaResult
                    $standaloneTotalApplied += if ($msaResult.Applied) { @($msaResult.Applied).Count } else { 0 }
                    $standaloneTotalErrors += if ($msaResult.Errors) { @($msaResult.Errors).Count } else { 0 }
                    $standaloneTotalDuration += if ($msaResult.DurationMs) { $msaResult.DurationMs } else { 0 }
                    if ($msaResult.PSObject.Properties.Name -contains 'Converged' -and -not $msaResult.Converged) { $standaloneConverged = $false }
                }
            } else {
                Write-Host "  ✅ MSA ACL delegations already up to date" -ForegroundColor Green
            }
        }
    }
    
    if ($IncludeGmsa) {
        Write-Host "`nPhase: gMSA ACL Delegations" -ForegroundColor Cyan
        $gmsaPlan = Get-TierModelGmsaAcl -Config $config -DomainController $PreferredDc
        if ($gmsaPlan.Errors -and $gmsaPlan.Errors.Count -gt 0) {
            Write-Host "  ❌ gMSA planning errors:" -ForegroundColor Red
            $gmsaPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
            $standaloneTotalErrors += $gmsaPlan.Errors.Count
        } else {
            Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $standaloneDeploymentPlan -PhaseNumber 2 -PhaseName 'gMSA ACL Delegations' -Plan $gmsaPlan
            if ($gmsaPlan.Summary.TotalActions -gt 0) {
                Write-Host "  Actions planned: $($gmsaPlan.Summary.TotalActions)" -ForegroundColor Yellow
                if (-not $ConfirmApply) {
                    Write-IncludeAclPlanActions -Actions $gmsaPlan.Actions
                }
                if ($ConfirmApply) {
                    $gmsaResult = New-TierModelGmsaAcl -Plan $gmsaPlan -DomainController $PreferredDc -Config $config
                    $standaloneResults += $gmsaResult
                    $standaloneTotalApplied += if ($gmsaResult.Applied) { @($gmsaResult.Applied).Count } else { 0 }
                    $standaloneTotalErrors += if ($gmsaResult.Errors) { @($gmsaResult.Errors).Count } else { 0 }
                    $standaloneTotalDuration += if ($gmsaResult.DurationMs) { $gmsaResult.DurationMs } else { 0 }
                    if ($gmsaResult.PSObject.Properties.Name -contains 'Converged' -and -not $gmsaResult.Converged) { $standaloneConverged = $false }
                }
            } else {
                Write-Host "  ✅ gMSA ACL delegations already up to date" -ForegroundColor Green
            }
        }
    }
    
    if ($IncludeDmsa) {
        Write-Host "`nPhase: dMSA ACL Delegations" -ForegroundColor Cyan
        $dmsaPlan = Get-TierModelDmsaAcl -Config $config -DomainController $PreferredDc
        if ($dmsaPlan.Errors -and $dmsaPlan.Errors.Count -gt 0) {
            Write-Host "  ❌ dMSA planning errors:" -ForegroundColor Red
            $dmsaPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
            $standaloneTotalErrors += $dmsaPlan.Errors.Count
        } else {
            Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $standaloneDeploymentPlan -PhaseNumber 3 -PhaseName 'dMSA ACL Delegations' -Plan $dmsaPlan
            if ($dmsaPlan.Summary.TotalActions -gt 0) {
                Write-Host "  Actions planned: $($dmsaPlan.Summary.TotalActions)" -ForegroundColor Yellow
                if (-not $ConfirmApply) {
                    Write-IncludeAclPlanActions -Actions $dmsaPlan.Actions
                }
                if ($ConfirmApply) {
                    $dmsaResult = New-TierModelDmsaAcl -Plan $dmsaPlan -DomainController $PreferredDc -Config $config
                    $standaloneResults += $dmsaResult
                    $standaloneTotalApplied += if ($dmsaResult.Applied) { @($dmsaResult.Applied).Count } else { 0 }
                    $standaloneTotalErrors += if ($dmsaResult.Errors) { @($dmsaResult.Errors).Count } else { 0 }
                    $standaloneTotalDuration += if ($dmsaResult.DurationMs) { $dmsaResult.DurationMs } else { 0 }
                    if ($dmsaResult.PSObject.Properties.Name -contains 'Converged' -and -not $dmsaResult.Converged) { $standaloneConverged = $false }
                }
            } else {
                Write-Host "  ✅ dMSA ACL delegations already up to date" -ForegroundColor Green
            }
        }
    }
    
    if ($IncludeWinLaps) {
        Write-Host "`nPhase: Windows LAPS ACL Delegations" -ForegroundColor Cyan
        $winLapsPlan = Get-TierModelWinLapsAcl -Config $config -DomainController $PreferredDc
        if ($winLapsPlan.Errors -and $winLapsPlan.Errors.Count -gt 0) {
            Write-Host "Dependency Errors:" -ForegroundColor Red
            $winLapsPlan.Errors | ForEach-Object { Write-Host "  ❌ $($_.Message)" -ForegroundColor Red }
            $standaloneTotalErrors += $winLapsPlan.Errors.Count
        } else {
            Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $standaloneDeploymentPlan -PhaseNumber 4 -PhaseName 'Windows LAPS ACL Delegations' -Plan $winLapsPlan
            if ($winLapsPlan.Summary.TotalActions -gt 0) {
                Write-Host "  Actions planned: $($winLapsPlan.Summary.TotalActions)" -ForegroundColor Yellow
                if (-not $ConfirmApply) {
                    Write-IncludeAclPlanActions -Actions $winLapsPlan.Actions
                }
                if ($ConfirmApply) {
                    $winLapsResult = New-TierModelWinLapsAcl -Plan $winLapsPlan -DomainController $PreferredDc -Config $config
                    $standaloneResults += $winLapsResult
                    $standaloneTotalApplied += if ($winLapsResult.Applied) { @($winLapsResult.Applied).Count } else { 0 }
                    $standaloneTotalErrors += if ($winLapsResult.Errors) { @($winLapsResult.Errors).Count } else { 0 }
                    $standaloneTotalDuration += if ($winLapsResult.DurationMs) { $winLapsResult.DurationMs } else { 0 }
                    if ($winLapsResult.PSObject.Properties.Name -contains 'Converged' -and -not $winLapsResult.Converged) { $standaloneConverged = $false }
                }
            } else {
                Write-Host "  ✅ Windows LAPS ACL delegations already up to date" -ForegroundColor Green
            }
        }
    }

    if ($EnableAuditing) {
        Write-Host "`nPhase: Domain Audit Rule (SACL)" -ForegroundColor Cyan
        $auditPlan = Get-TierModelAuditRule -Config $config -DomainController $PreferredDc
        if ($auditPlan.Errors -and $auditPlan.Errors.Count -gt 0) {
            Write-Host "Planning Errors:" -ForegroundColor Red
            $auditPlan.Errors | ForEach-Object { Write-Host "  ❌ $($_.Message)" -ForegroundColor Red }
            $standaloneTotalErrors += $auditPlan.Errors.Count
        } else {
            Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $standaloneDeploymentPlan -PhaseNumber 5 -PhaseName 'Domain Audit Rule' -Plan $auditPlan
            if ($auditPlan.Summary.TotalActions -gt 0) {
                Write-Host "  Actions planned: $($auditPlan.Summary.TotalActions)" -ForegroundColor Yellow
                if (-not $ConfirmApply) {
                    Write-IncludeAclPlanActions -Actions $auditPlan.Actions
                }
                if ($ConfirmApply) {
                    $auditResult = New-TierModelAuditRule -Plan $auditPlan -DomainController $PreferredDc -Config $config
                    $standaloneResults += $auditResult
                    $standaloneTotalApplied += if ($auditResult.Applied) { @($auditResult.Applied).Count } else { 0 }
                    $standaloneTotalErrors += if ($auditResult.Errors) { @($auditResult.Errors).Count } else { 0 }
                    $standaloneTotalDuration += if ($auditResult.DurationMs) { $auditResult.DurationMs } else { 0 }
                    if ($auditResult.PSObject.Properties.Name -contains 'Converged' -and -not $auditResult.Converged) { $standaloneConverged = $false }
                }
            } else {
                Write-Host "  ✅ Domain audit rule already up to date" -ForegroundColor Green
            }
        }
    }

    if ($IncludeAuthSilos) {
        Write-Host "`nPhase: Authentication Policy Silos" -ForegroundColor Cyan

        # Prerequisite gate — fail fast if referenced groups are missing
        $authSilosPrereq = Test-TierModelAuthSiloPrerequisite -Config $config -DomainController $PreferredDc
        if (-not $authSilosPrereq.Passed) {
            Write-Host "  ❌ Prerequisites not met — all referenced groups must exist before silo deployment:" -ForegroundColor Red
            $authSilosPrereq.Failures | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            $standaloneTotalErrors += $authSilosPrereq.Failures.Count
        } else {
            # ── Step A: Authentication Policies — plan + (if -ConfirmApply) execute first ──
            $authPolicyStandalonePlan = Get-TierModelAuthPolicyFd -Config $config -DomainController $PreferredDc
            if ($authPolicyStandalonePlan.Errors -and $authPolicyStandalonePlan.Errors.Count -gt 0) {
                Write-Host "  ❌ Auth policy planning errors:" -ForegroundColor Red
                $authPolicyStandalonePlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                $standaloneTotalErrors += $authPolicyStandalonePlan.Errors.Count
            } else {
                $standaloneDeploymentPlan.TotalActions      += $authPolicyStandalonePlan.Summary.TotalActions
                $standaloneDeploymentPlan.CreateCount       += $authPolicyStandalonePlan.Summary.ToCreate
                $standaloneDeploymentPlan.AlreadyExistCount += $authPolicyStandalonePlan.Summary.AlreadyExist
                if ($authPolicyStandalonePlan.Summary.ToCreate -eq 0) {
                    if (-not $ConfirmApply) { Write-Host "  Auth Policies: all $($authPolicyStandalonePlan.Summary.TotalInConfig) already deployed" -ForegroundColor Green }
                } else {
                    if (-not $ConfirmApply) { $authPolicyStandalonePlan.Actions | Where-Object { $_.Action -eq 'CreateAuthPolicy' } | ForEach-Object { Write-Host "  `u{25A0} Create Authentication Policy: $($_.Name)" -ForegroundColor Yellow } }
                    if ($ConfirmApply) {
                        $authPolicyStandaloneResult = New-TierModelAuthPolicy -Plan $authPolicyStandalonePlan -DomainController $PreferredDc
                        $standaloneResults      += $authPolicyStandaloneResult
                        $standaloneTotalApplied += if ($authPolicyStandaloneResult.Applied) { @($authPolicyStandaloneResult.Applied).Count } else { 0 }
                        $standaloneTotalErrors  += if ($authPolicyStandaloneResult.Errors)  { @($authPolicyStandaloneResult.Errors).Count  } else { 0 }
                        $standaloneTotalDuration += if ($authPolicyStandaloneResult.DurationMs) { $authPolicyStandaloneResult.DurationMs } else { 0 }
                        if ($authPolicyStandaloneResult.PSObject.Properties.Name -contains 'Converged' -and -not $authPolicyStandaloneResult.Converged) { $standaloneConverged = $false }
                    }
                }
            }

            # ── Step B: Authentication Silos — plan + (if -ConfirmApply) execute ──────────
            if ($standaloneTotalErrors -eq 0) {
                $authSiloStandalonePlan = Get-TierModelAuthSiloFd -Config $config -DomainController $PreferredDc
                if ($authSiloStandalonePlan.Errors -and $authSiloStandalonePlan.Errors.Count -gt 0) {
                    Write-Host "  ❌ Auth silo planning errors:" -ForegroundColor Red
                    $authSiloStandalonePlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
                    $standaloneTotalErrors += $authSiloStandalonePlan.Errors.Count
                } else {
                    $standaloneDeploymentPlan.TotalActions      += $authSiloStandalonePlan.Summary.TotalActions
                    $standaloneDeploymentPlan.CreateCount       += $authSiloStandalonePlan.Summary.ToCreate
                    $standaloneDeploymentPlan.AlreadyExistCount += $authSiloStandalonePlan.Summary.AlreadyExist

                    if ($authSiloStandalonePlan.Summary.ToCreate -eq 0) {
                        if (-not $ConfirmApply) { Write-Host "  Auth Silos:    all $($authSiloStandalonePlan.Summary.TotalInConfig) already deployed" -ForegroundColor Green }
                    } else {
                        if (-not $ConfirmApply) { $authSiloStandalonePlan.Actions | Where-Object { $_.Action -eq 'CreateAuthSilo' } | ForEach-Object { Write-Host "  `u{25A0} Create Authentication Policy Silo: $($_.Name)" -ForegroundColor Yellow } }
                        if ($ConfirmApply) {
                            $authSiloStandaloneResult = New-TierModelAuthSilo -Plan $authSiloStandalonePlan -DomainController $PreferredDc
                            $standaloneResults      += $authSiloStandaloneResult
                            $standaloneTotalApplied += if ($authSiloStandaloneResult.Applied) { @($authSiloStandaloneResult.Applied).Count } else { 0 }
                            $standaloneTotalErrors  += if ($authSiloStandaloneResult.Errors)  { @($authSiloStandaloneResult.Errors).Count  } else { 0 }
                            $standaloneTotalDuration += if ($authSiloStandaloneResult.DurationMs) { $authSiloStandaloneResult.DurationMs } else { 0 }
                            if ($authSiloStandaloneResult.PSObject.Properties.Name -contains 'Converged' -and -not $authSiloStandaloneResult.Converged) { $standaloneConverged = $false }
                        }
                    }

                    # Membership plan/execute — create-once: only for silos created in this run
                    $newSiloNamesStandalone = @($authSiloStandalonePlan.Actions | Where-Object { $_.Action -eq 'CreateAuthSilo' } | ForEach-Object { $_.Name })
                    if (-not $ConfirmApply) {
                        $membershipFdPlanStandalone = Get-TierModelAuthSiloMembershipFd -Config $config -DomainController $PreferredDc -OnlyForSilos $newSiloNamesStandalone
                        $standaloneDeploymentPlan.TotalActions      += $membershipFdPlanStandalone.Summary.TotalPending
                        $standaloneDeploymentPlan.AlreadyExistCount += $membershipFdPlanStandalone.Summary.TotalAlreadyAssigned
                        if ($membershipFdPlanStandalone.Summary.TotalPending -eq 0) {
                            Write-Host "  Membership:    0 pending (all silos already deployed)" -ForegroundColor Gray
                        } else {
                            Write-Host "  Membership:    will assign for $($newSiloNamesStandalone.Count) new silo(s)" -ForegroundColor Yellow
                        }
                    }
                    if ($ConfirmApply -and $standaloneTotalErrors -eq 0) {
                        $createdSilosStandalone = @(if (Get-Variable authSiloStandaloneResult -ErrorAction SilentlyContinue) { $authSiloStandaloneResult.CreatedSiloNames } else { @() })
                        if ($createdSilosStandalone.Count -gt 0) {
                            $authMembershipStandaloneResult = Set-TierModelAuthSiloMembership -Config $config -DomainController $PreferredDc -OnlyForSilos $createdSilosStandalone
                            $standaloneResults      += $authMembershipStandaloneResult
                            $standaloneTotalApplied += if ($authMembershipStandaloneResult.Applied) { @($authMembershipStandaloneResult.Applied).Count } else { 0 }
                            $standaloneTotalErrors  += if ($authMembershipStandaloneResult.Errors)  { @($authMembershipStandaloneResult.Errors).Count  } else { 0 }
                            $standaloneTotalDuration += if ($authMembershipStandaloneResult.DurationMs) { $authMembershipStandaloneResult.DurationMs } else { 0 }
                            if ($authMembershipStandaloneResult.PSObject.Properties.Name -contains 'Converged' -and -not $authMembershipStandaloneResult.Converged) { $standaloneConverged = $false }
                        } elseif ($authPolicyStandalonePlan.Summary.ToCreate -eq 0 -and $authSiloStandalonePlan.Summary.ToCreate -eq 0) {
                            Write-Host "  ✅ Already deployed — nothing to create" -ForegroundColor Green
                        }
                    }
                }
            }
        }
    }
    
    if ($ConfirmApply) {
        Write-Host "`n=== Deployment Results ===" -ForegroundColor Blue
        Write-Host "Applied: $standaloneTotalApplied" -ForegroundColor Green
        Write-Host "Skipped: $standaloneTotalSkipped" -ForegroundColor Yellow
        Write-Host "Errors: $standaloneTotalErrors" -ForegroundColor $(if ($standaloneTotalErrors -gt 0) { 'Red' } else { 'Green' })
        Write-Host "Duration: $(Format-TierModelDuration $standaloneTotalDuration)" -ForegroundColor Gray
        Write-Host "Converged: $standaloneConverged" -ForegroundColor $(if ($standaloneConverged) { 'Green' } else { 'Yellow' })
    } elseif ($standaloneTotalErrors -eq 0) {
        Write-Host "`n=== Deployment Plan ===" -ForegroundColor Blue
        Write-Host "Action count: $($standaloneDeploymentPlan.TotalActions)" -ForegroundColor White
        Write-Host "Create count: $($standaloneDeploymentPlan.CreateCount)" -ForegroundColor Yellow
        Write-Host "Update count: $($standaloneDeploymentPlan.UpdateCount)" -ForegroundColor Yellow
        Write-Host "Link count: $($standaloneDeploymentPlan.LinkCount)" -ForegroundColor Yellow
        Write-Host "Configure count: $($standaloneDeploymentPlan.ConfigureCount)" -ForegroundColor Yellow
        Write-Host "Already exist: $($standaloneDeploymentPlan.AlreadyExistCount)" -ForegroundColor Green
        if ($standaloneDeploymentPlan.TotalActions -gt 0) {
            Write-Host ""
            Write-Host "Use -ConfirmApply to execute the deployment plan" -ForegroundColor DarkCyan
        }
    }
}

# Show ConfirmApply message for single-entity operations if in planning mode
if (-not $FullDeployment -and -not $ConfirmApply) {
    # Check if any actions were planned and no errors exist
    $hasActions = $false
    $hasErrors = $false
    
    # Check for actions
    if ($OuOnly -and $ouResult -and $ouResult.PSObject.Properties.Name -contains 'Actions' -and $ouResult.Actions.Count -gt 0) { $hasActions = $true }
    if ($GroupOnly -and $groupResult -and $groupResult.PSObject.Properties.Name -contains 'Actions' -and $groupResult.Actions.Count -gt 0) { $hasActions = $true }
    if ($UserOnly -and $userResult -and $userResult.PSObject.Properties.Name -contains 'Actions' -and $userResult.Actions -and $userResult.Actions.Count -gt 0) { $hasActions = $true }
    if ($OuAclsOnly -and $ouAclResult -and $ouAclResult.PSObject.Properties.Name -contains 'Actions' -and @($ouAclResult.Actions).Count -gt 0) { $hasActions = $true }
    if ($GposOnly -and $gpoResult -and $gpoResult.PSObject.Properties.Name -contains 'Actions' -and $gpoResult.Actions.Count -gt 0) { $hasActions = $true }
    if ($AdmxOnly -and $admxPlan -and $admxPlan.Summary.FilesToUpdate -gt 0) { $hasActions = $true }
    
    # Check for errors
    if ($OuOnly -and $ouResult -and $ouResult.PSObject.Properties.Name -contains 'Errors' -and $ouResult.Errors.Count -gt 0) { $hasErrors = $true }
    if ($GroupOnly -and $groupResult -and $groupResult.PSObject.Properties.Name -contains 'Errors' -and $groupResult.Errors.Count -gt 0) { $hasErrors = $true }
    if ($UserOnly -and $userResult -and $userResult.PSObject.Properties.Name -contains 'Errors' -and $userResult.Errors -and $userResult.Errors.Count -gt 0) { $hasErrors = $true }
    if ($OuAclsOnly -and $ouAclResult -and $ouAclResult.PSObject.Properties.Name -contains 'Errors' -and @($ouAclResult.Errors).Count -gt 0) { $hasErrors = $true }
    if ($GposOnly -and $gpoResult -and $gpoResult.PSObject.Properties.Name -contains 'Errors' -and $gpoResult.Errors -and @($gpoResult.Errors).Count -gt 0) { $hasErrors = $true }
    if ($AdmxOnly -and $admxPlan -and $admxPlan.PSObject.Properties.Name -contains 'Analysis' -and @(Get-TierModelAdmxFatalError -Errors @($admxPlan.Analysis.Errors)).Count -gt 0) { $hasErrors = $true }
    
    # Only show ConfirmApply if there are actions and no errors
    if ($hasActions -and -not $hasErrors) {
        Write-Host ""
        Write-Host "Use -ConfirmApply to execute the deployment plan" -ForegroundColor DarkCyan
        Write-Host ""
    }
}

Write-Host ""
if ($script:DeploymentBlocked) {
    Write-Host "Deploy script completed - DEPLOYMENT BLOCKED, no changes were applied." -ForegroundColor Red
} else {
    Write-Host "Deploy script completed." -ForegroundColor Green
}
if ($Logging) {
    if ($script:DeploymentBlocked) {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Error' -Message "Deploy script completed with BLOCKED deployment - dependency errors prevented changes from being applied" -Data @{
            BlockedPhases = ($script:BlockedPhases -join ', ')
            Outcome = 'Blocked'
        }
    } else {
        Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "Deploy script completed successfully"
    }
    Write-Host "Log file saved: $script:LogFilePath" -ForegroundColor Gray
}

# WI-09: offer the diagnostics re-run only when the run did not fully succeed. Suppressed
# automatically when both switches are already on.
if ($script:DeploymentBlocked) {
    Write-TierModelDiagnosticsHint
}

# WI-08: final guarded stop. Printed last so the transcript path is the last thing the operator
# sees. Guarded by $script:TranscriptStarted, which is cleared by whichever exit path ran first,
# so this can never stop a transcript we do not own.
Stop-TierModelDiagnosticsTranscript
