<#
.SYNOPSIS
Modular TierModel audit using dedicated cmdlets per entity type.

.DESCRIPTION
Performs drift detection and compliance auditing for TierModel components including 
organizational units, groups, users, GPOs, OU ACL delegations, and ADMX configurations.
Uses modular cmdlet architecture for improved maintainability and testing.

.PARAMETER PreferredDc
The preferred domain controller to use for all Active Directory operations.
Must be accessible and have appropriate permissions for querying AD objects.

.PARAMETER OuOnly
Audit only organizational units. When specified, only OU configuration 
compliance will be checked against the TierModel specification.

.PARAMETER GroupOnly
Audit only security groups. When specified, only group membership and 
configuration compliance will be checked. (Not yet implemented in v0.2)

.PARAMETER UserOnly
Audit only user accounts. When specified, only user account configuration 
and placement compliance will be checked. (Not yet implemented in v0.2)

.PARAMETER GposOnly
Audit only Group Policy Objects. When specified, only GPO configuration,
settings, and linkage compliance will be checked. (Not yet implemented in v0.2)

.PARAMETER OuAclsOnly
Audit only OU ACL delegations. When specified, only organizational unit
access control list delegations will be checked. (Not yet implemented in v0.2)

.PARAMETER AdmxOnly
Audit only ADMX template compliance. When specified, only administrative 
template imports and configurations will be checked. (Not yet implemented in v0.2)

.PARAMETER FullDeployment
Perform comprehensive audit of all TierModel components in dependency order:
OUs -> Groups -> Users -> OU ACL Delegations -> GPOs -> ADMX.
Provides consolidated reporting at completion.

.PARAMETER IncludeWinLaps
Audit Windows LAPS ACL delegations and GPO decryptor settings as an optional feature.
Can be used standalone (without any scope parameter) or combined with -FullDeployment.
When active, audits all configured winLapsDelegations for SELF/Read/Reset DACL
compliance (via Test-TierModelWinLapsAcl) and verifies the ADPasswordEncryptionPrincipal
registry policy on each non-DC LAPS GPO (via Test-TierModelWinLapsDecryptor).
Requires Windows LAPS schema extended and LAPS PowerShell module installed.
A plain -FullDeployment without -IncludeWinLaps does NOT audit LAPS.

.PARAMETER IncludeAuthSilos
Audit AD Authentication Policies and Authentication Policy Silos from the
tiermodel-authsilos.json configuration segment. For each policy: verifies it exists,
checks Description, UserTGTLifetimeMins (skipped when null = domain default), and
UserAllowedToAuthenticateFrom SDDL (alias- and order-insensitive via Compare-TierModelAuthSddl).
For each silo: verifies it exists, checks policy links (User/Computer/Service), and verifies
that all expected member accounts and computers (expanded from config groups, minus the
permanent domain-join exemptions and the built-in Administrator/RID-500) are present.
NEVER checks the Enforce state (enforcement is a separate lifecycle step).
Can be used standalone or combined with -FullDeployment.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.

.PARAMETER EnableAuditing
Audit the domain-root Active Directory object auditing SACL (Everyone / AuditFlags=Success /
InheritanceType=All, 9 rights: CreateChild, DeleteChild, WriteProperty, Self, Delete,
DeleteTree, WriteDacl, WriteOwner, ExtendedRight) via Test-TierModelAuditRule.
Can be used standalone (without any scope parameter) or combined with -FullDeployment.
A plain -FullDeployment without -EnableAuditing does NOT audit the domain-root SACL.
Cannot be combined with any -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly,
or -AdmxOnly scope parameter.
Requires SeSecurityPrivilege to read the SACL (Domain Admin qualifies).

.PARAMETER OutputFormat
Specifies the format for audit report output. Valid options:
- Text: Human-readable text format
- Json: Structured JSON format for automated processing
- Html: HTML format for web viewing
- NUnitXml: XML format compatible with NUnit test frameworks

.PARAMETER OutputFileBase
Base filename for generated audit reports (without extension or timestamp).
The actual filename will include a timestamp and appropriate extension.
When -OutputFormat is specified without it you are prompted for one; pressing Enter accepts
the default 'Audit-TierModel' rather than stopping the run.

.PARAMETER AdmlLanguage
Language code for ADMX template processing in format 'xx-XX' (e.g., 'en-US').
Used when auditing ADMX configurations to match appropriate language templates.

.PARAMETER Logging
Enable structured logging to a timestamped file. When specified, audit operations and
results are written to a log file in the directory specified by -LogPath (or the current
working directory if -LogPath is omitted). This also enables module-scope logging, so
entries raised inside the TierModel module itself - including every -Level Error - reach
the file rather than the console alone. You are prompted for -OutputFileBase if it is
omitted; pressing Enter accepts the default 'Audit-TierModel'.

.PARAMETER LogPath
Directory path with three jobs: it is where -OutputFormat report files are created, where
the -Logging log file is created, and the parent of the 'Debug' folder used for the
diagnostics transcript. All three are derived from the same resolved path, so a relative
-LogPath can never split them across directories.
If not provided, files are created in the current directory. Directory will be
created automatically if it doesn't exist.

.PARAMETER EnableVerbose
Enable verbose diagnostic output for troubleshooting. Console output becomes considerably
more detailed and interleaves with the normal progress output - that is expected, and is the
point of the switch. This switch also enables -Logging automatically, so a diagnostic run
always leaves a log file behind; if -OutputFileBase is omitted it defaults to
'Audit-TierModel' without prompting, keeping a re-run copy-pasteable.
Diagnostic switches change only what is recorded, never what is decided or read from
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
Diagnostic switches change only what is recorded, never what is decided or read from
Active Directory.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -GposOnly -EnableVerbose
Audit GPOs with verbose diagnostics. Logging is enabled automatically and written to
'Audit-TierModel-<timestamp>.log' in the current directory. No transcript is started,
because only one diagnostics switch was supplied.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -FullDeployment -EnableVerbose -EnableDebug -LogPath "C:\Reports"
Full audit with both diagnostics switches. Writes C:\Reports\Audit-TierModel-<timestamp>.log
and an UNREDACTED console transcript under C:\Reports\Debug\. Review the transcript for
sensitive environment detail before sharing it.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -OuOnly
Audit only organizational units using DC01 as the preferred domain controller.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -FullDeployment -OutputFormat Json -OutputFileBase "TierModel-Audit" -LogPath "C:\Reports"
Perform full TierModel audit and save results as JSON in the C:\Reports directory.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -GposOnly -OutputFormat Html -OutputFileBase "GPO-Compliance"
Audit only GPOs and generate an HTML report in the current directory.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -IncludeWinLaps
Standalone audit of Windows LAPS ACL delegations and GPO decryptor settings.
Expects 0 drift when the tier model with WinLaps has been fully deployed.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -EnableAuditing
Standalone audit of the domain-root SACL audit rule. Expects Compliant / 0 drift
when -EnableAuditing has been applied via Deploy-TierModel.ps1.

.EXAMPLE
.\Audit-TierModel.ps1 -PreferredDc "DC01.contoso.com" -FullDeployment -IncludeWinLaps
Full TierModel audit including Windows LAPS ACL delegations and decryptor GPO settings.

.NOTES
Version: 2.1.0
Requires: TierModel PowerShell module (v2.1.0+), PowerShell 7.0+, appropriate Active Directory
permissions. SeSecurityPrivilege required to read the domain-root SACL with -EnableAuditing
(Domain Admin qualifies).
#>
[CmdletBinding()]
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
    
    [switch]$IncludeMsa,
    [switch]$IncludeGmsa,
    [switch]$IncludeDmsa,
    [switch]$IncludeWinLaps,
    [switch]$IncludeAuthSilos,
    [switch]$EnableAuditing,
    
    [Parameter()]
    [ValidateSet('Text', 'Json', 'Html', 'NUnitXml')]
    [string]$OutputFormat,
    
    [Parameter()]
    [string]$OutputFileBase,
    
    [Parameter()]
    [ValidatePattern('^[a-zA-Z]{2}-[a-zA-Z]{2}$')]
    [string]$AdmlLanguage = 'en-US',
    
    [Parameter()]
    [switch]$Logging,
    
    [Parameter()]
    [string]$LogPath,
    
    # --- Diagnostics ---
    [Parameter()]
    [switch]$EnableVerbose,
    
    [Parameter()]
    [switch]$EnableDebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate that only one audit scope parameter is specified
$scopeParameters = @($OuOnly, $GroupOnly, $UserOnly, $GposOnly, $OuAclsOnly, $AdmxOnly, $FullDeployment)
$activeScopeCount = @($scopeParameters | Where-Object { $_ }).Count
$includeParameters = @($IncludeMsa, $IncludeGmsa, $IncludeDmsa, $IncludeWinLaps, $IncludeAuthSilos, $EnableAuditing)
$activeIncludeCount = @($includeParameters | Where-Object { $_ }).Count

if ($activeScopeCount -eq 0 -and $activeIncludeCount -eq 0) {
    Write-Error "You must specify exactly one audit scope parameter (-OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly, -AdmxOnly, -FullDeployment) or one or more -Include* switches (-IncludeMsa, -IncludeGmsa, -IncludeDmsa, -IncludeWinLaps, -IncludeAuthSilos, -EnableAuditing)." -ErrorAction Stop
}
elseif ($activeScopeCount -gt 1) {
    Write-Error "You can only specify one audit scope parameter at a time. Cannot combine -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly, -AdmxOnly, and -FullDeployment" -ErrorAction Stop
}
elseif ($activeIncludeCount -gt 0 -and $activeScopeCount -eq 1 -and -not $FullDeployment) {
    Write-Error "-IncludeMsa, -IncludeGmsa, -IncludeDmsa, -IncludeWinLaps, -IncludeAuthSilos, and -EnableAuditing can only be used standalone or combined with -FullDeployment. They cannot be used with -OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly, or -AdmxOnly." -ErrorAction Stop
}

Write-Host "Audit TierModel orchestration starting." -ForegroundColor Cyan
Write-Host "Preferred DC: $PreferredDc" -ForegroundColor DarkCyan

function Write-TierModelFailFast {
    <#
    .SYNOPSIS
    Renders a consistent fail-fast prerequisite message and closing line.
    .DESCRIPTION
    Produces the standard fail-fast layout used by every up-front gate: a blank line, the
    indented message line(s) in red, an optional "Remediation steps:" block in yellow
    (blank-line separated), and the closing "Audit script completed." line — so all
    fail-fast paths (PowerShell version and the general prerequisite check) look identical,
    matching Deploy-TierModel.ps1.
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
    Write-Host "Audit script completed." -ForegroundColor Green

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
                Script         = 'Audit-TierModel.ps1'
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

function ConvertTo-TierModelDriftFinding {
    <#
    .SYNOPSIS
    Normalises an audit finding into the shape the Text/Json/Html reports render.
    .DESCRIPTION
    The audit functions do not agree on a finding shape: Test-TierModelAdmx emits FileName/Message,
    the standalone ACL audits emit Property/ExpectedValue/ActualValue and carry no Details. The
    report interpolates Type/ResourceType/Identifier/Details, so a raw finding throws under
    Set-StrictMode -Version Latest. This guarantees all four exist. Compliant findings are dropped -
    they are not drift.
    #>
    param(
        [Parameter(ValueFromPipeline)]$Finding,
        # The audit functions do not all carry a ResourceType. Callers that know the resource
        # class they are normalising supply it here so the report renders 'GPO/<name>' rather
        # than 'Unknown/<name>'. Defaults to 'Unknown' so existing callers are unaffected.
        [string]$DefaultResourceType = 'Unknown'
    )
    process {
        if (-not $Finding) { return }
        $names = @($Finding.PSObject.Properties.Name)

        $findingType = if (($names -contains 'Type') -and $Finding.Type) { [string]$Finding.Type } else { 'Drift' }

        # Two verdict conventions exist. Most producers carry 'Type'; AuthPolicy, AuthSilo and
        # WinLapsDecryptor carry only 'Status'; AuditRule carries both, with a descriptive Type and the
        # real verdict in Status. Type wins whenever it is present and Status is consulted only as a
        # fallback, so every Type-bearing shape passes through unchanged.
        $findingStatus = if ($names -contains 'Status') { [string]$Finding.Status } else { $null }
        if ($findingStatus -and -not (($names -contains 'Type') -and $Finding.Type)) {
            $findingType = $findingStatus
        }

        # A compliant item is not drift, whichever convention reported it. Without this, an
        # audit-right that PASSED was rendered into the drift report as '[AuditRight] ...'
        # because 'AuditRight' is not the literal 'Compliant'. Matched exactly, never by
        # wildcard: 'NonCompliant' must NOT be treated as compliant.
        if ($findingType -eq 'Compliant') { return }
        if ($findingStatus -and $findingStatus -in @('Pass', 'Compliant', 'OK', 'Success', 'True')) { return }

        # 'AuditRight' is state-AGNOSTIC. Test-TierModelAuditRule emits it for BOTH outcomes from a
        # single hashtable, carrying the real verdict in Status ('Pass'/'Fail') and the observed
        # state in ActualValue ('Present'/'Missing'). The Pass rows are already dropped by the
        # guard above, so in practice everything reaching here is a failure - but the label is
        # still DERIVED from the finding's own state rather than rewritten wholesale, so an
        # 'AuditRight' emitted one day for some non-absent reason cannot be mislabelled as an
        # absence.
        #
        # Renamed to 'MissingAuditRule' and deliberately NOT to 'MissingAcl': these are SACL
        # AUDIT rules, not DACL access rules, and 'MissingAuditRule' is already the spelling this
        # same producer uses for the summary row of the very same drift.
        if ($findingType -eq 'AuditRight') {
            $actualState = if ($names -contains 'ActualValue') { [string]$Finding.ActualValue } else { $null }
            if ($actualState -eq 'Missing' -or $findingStatus -eq 'Fail') {
                $findingType = 'MissingAuditRule'
            }
        }

        $identifier = 'Unknown'
        foreach ($key in @('Identifier', 'FileName', 'GpoName', 'PolicyName', 'SiloName', 'Name', 'DistinguishedName')) {
            if (($names -contains $key) -and $Finding.$key) { $identifier = [string]$Finding.$key; break }
        }

        $details = $null
        foreach ($key in @('Details', 'Message', 'Reason')) {
            if (($names -contains $key) -and $Finding.$key) { $details = [string]$Finding.$key; break }
        }
        if (-not $details -and ($names -contains 'Issues') -and $Finding.Issues) {
            # Auth policy/silo findings carry a collection of issue strings rather than prose.
            # Checked AFTER Details/Message/Reason so their precedence is unchanged.
            $details = ((@($Finding.Issues) | Where-Object { $_ }) -join '; ')
        }
        if (-not $details) {
            # The standalone ACL audits describe drift as a property triple rather than prose.
            # ExpectedValue/ActualValue are tested FIRST so shapes that carry them render
            # exactly as before; Expected/Actual are the WinLapsDecryptor spelling.
            $parts = @()
            if (($names -contains 'Property') -and $Finding.Property) { $parts += "Property=$($Finding.Property)" }
            if ($names -contains 'ExpectedValue')  { $parts += "Expected=$($Finding.ExpectedValue)" }
            elseif ($names -contains 'Expected')   { $parts += "Expected=$($Finding.Expected)" }
            if ($names -contains 'ActualValue')    { $parts += "Actual=$($Finding.ActualValue)" }
            elseif ($names -contains 'Actual')     { $parts += "Actual=$($Finding.Actual)" }
            $details = if ($parts.Count -gt 0) { $parts -join '; ' } else { 'No further detail reported.' }
        }

        $resourceType = if (($names -contains 'ResourceType') -and $Finding.ResourceType) { [string]$Finding.ResourceType } else { $DefaultResourceType }

        [PSCustomObject]@{
            Type         = $findingType
            ResourceType = $resourceType
            Identifier   = $identifier
            Details      = $details
        }
    }
}

function Get-TierModelFindingColor {
    <#
    .SYNOPSIS
    Maps a drift-finding Type to a console colour by SEVERITY CLASS, never by exact string match.
    .DESCRIPTION
    The rule this replaces coloured a finding red only when its Type was the exact literal
    'Missing', and yellow for everything else. That was written in the initial v1.0.0 codebase,
    when the only producers were Test-TierModelOu/Group/User and every Type genuinely was the
    literal 'Missing' or 'Mismatch'. The -IncludeMsa / -IncludeGmsa / -IncludeDmsa /
    -IncludeWinLaps / -IncludeAuthSilos producers added afterwards publish 'MissingAcl',
    'MissingAuditRule', 'AuditRight' and 'Error'. None of those equal the literal, so every one
    of them fell to the else branch and rendered YELLOW - including outright 'Error' findings,
    which is a worse outcome than the under-coloured drift that was actually reported.

    Classification is therefore by severity CLASS rather than by enumerating the names that
    happen to exist today, so a producer that invents a new type name tomorrow is coloured
    sensibly instead of being silently downgraded to yellow:

      Red    - undeterminable: Error / Unverified / Failed. An audit that could not establish
               compliance is the most severe line on the page and must never render yellow.
      Red    - absent: any type CONTAINING 'Missing' - so 'Missing', 'MissingAcl' and
               'MissingAuditRule' all land here without this function needing to know any
               producer's spelling - plus NotFound / Absent.
      Yellow - present but wrong: Mismatch / Unexpected / NonCompliant / Extra / Drift / Warning.
      Red    - UNKNOWN. An unrecognised type is escalated rather than demoted, so a producer
               inventing a new type name is never under-stated.
    #>
    param([string]$Type)

    if ([string]::IsNullOrWhiteSpace($Type)) { return 'Red' }

    if ($Type -match '(?i)error|unverified|failed|failure')                      { return 'Red' }
    if ($Type -match '(?i)missing|notfound|not_found|absent')                    { return 'Red' }
    if ($Type -match '(?i)mismatch|unexpected|noncompliant|extra|drift|warning') { return 'Yellow' }

    return 'Red'
}

function Get-TierModelUnverifiedCount {
    <#
    .SYNOPSIS
    Reads a producer's unverified (read-failure) count from either Summary shape.
    .DESCRIPTION
    An object whose state could not be read is neither missing nor mismatched. Without this
    count a section shows Missing 0 and Mismatched 0 above a non-zero Total Drift, and the
    breakdown cannot be reconciled against the total printed beneath it.

    Summary arrives as a hashtable from some producers and a PSCustomObject from others, and
    Set-StrictMode -Version Latest throws on a missing property, so both shapes are probed
    explicitly. An absent count means "not reported", which is zero unverified.
    #>
    param($Summary)

    if ($null -eq $Summary) { return 0 }

    if ($Summary -is [System.Collections.IDictionary]) {
        if ($Summary.Contains('UnverifiedCount')) { return [int]$Summary['UnverifiedCount'] }
        return 0
    }

    if ($Summary.PSObject.Properties.Name -contains 'UnverifiedCount') { return [int]$Summary.UnverifiedCount }
    return 0
}

function Write-TierModelComplianceLine {
    <#
    .SYNOPSIS
    Renders a compliance line, keeping three different outcomes visibly distinct.
    .DESCRIPTION
    A percentage is only meaningful when objects were checked and the audit that checked them
    completed. Three outcomes are therefore reported differently:

      Errors present  - "N/A (could not be determined)", red. The checks that did run are an
                        incomplete picture, so a percentage over them overstates what is known.
      Nothing checked - "Not checked - nothing configured", grey. A scope with no configured
                        objects has neither passed nor failed. It contributes nothing to the
                        numerator or the denominator, and must never render green - a percentage
                        here reports an unexamined scope as compliant.
      Otherwise       - the percentage, coloured by band.

    A scope that IS configured but whose objects are absent from the directory still reports a
    real check count and real drift, so it takes the percentage branch and is reported as drift.
    "Nothing to check" and "everything is missing" are different results and stay that way.

    Percentage is accepted from callers whose producer already publishes one, so this never
    restates a figure that is already correct; it is computed only when not supplied.
    #>
    param(
        [int]$TotalChecked,
        [int]$DriftCount = 0,
        [int]$ErrorCount = 0,
        $Percentage = $null,
        [string]$Label = '  Compliance',
        [string]$Suffix = ''
    )

    if ($ErrorCount -gt 0) {
        Write-Host "$($Label): N/A (could not be determined)" -ForegroundColor Red
        return
    }

    if ($TotalChecked -le 0) {
        Write-Host "$($Label): Not checked - nothing configured" -ForegroundColor Gray
        return
    }

    $pct = if ($null -ne $Percentage) { [double]$Percentage } else {
        [math]::Round((($TotalChecked - $DriftCount) / $TotalChecked) * 100, 2)
    }

    Write-Host "$($Label): $pct%$Suffix" -ForegroundColor $(if ($pct -ge 90) { 'Green' } elseif ($pct -ge 70) { 'Yellow' } else { 'Red' })
}

function Stop-TierModelDiagnosticsTranscript {
    <#
    .SYNOPSIS
    Stops the diagnostics transcript, but ONLY if this script started it (WI-16).
    .DESCRIPTION
    Identical to the helper in Deploy-TierModel.ps1 — kept character-for-character equivalent so
    the two scripts behave the same way.

    ⛔ NEVER call Stop-Transcript unguarded. POC-3 inverted our original assumption: a *nested*
    Start-Transcript is harmless, but an unpaired Stop is not. If our Start-Transcript failed
    while the OPERATOR'S OWN transcript is running, a bare Stop-Transcript SUCCEEDS and stops
    theirs — silently destroying their session record. Nothing throws, so a try/catch cannot
    save you.

    $script:TranscriptStarted is therefore load-bearing: it is set only after Test-Path has
    CONFIRMED our transcript file exists, and it is the sole authority for whether we may stop
    anything. It is cleared afterwards so a second exit path cannot stop a transcript we no
    longer own.

    ⚠️ KNOWN GAP (Ctrl-C): after a genuine Ctrl-C the transcript is left open and keeps
    capturing until the console exits. Closing that gap needs a try/finally around the whole
    script body; the trade is with Joel. If that option is ever chosen, the only change needed
    is to wrap the body and call this function from the finally — every call site stays as-is.
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
    Prints a copy-pasteable re-run line that adds -EnableVerbose -EnableDebug (WI-16).
    .DESCRIPTION
    Identical in shape to the Deploy helper. Reconstructs the operator's actual invocation from
    the bound parameters captured at script start, then appends the two diagnostics switches.
    The result must be literally pasteable and non-interactive — which is exactly why the
    auto-enable path never prompts for -OutputFileBase.

    Deliberately worded "for full diagnostics" rather than anything implying the switches will
    reveal the cause: they may not, and promising a cause is how an operator ends up running the
    same failure twice and losing confidence in the tooling.

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
    # the command line — Audit prompts for it both when -OutputFormat is given without one (L241)
    # and when -Logging is given without one — in which case it is absent from $PSBoundParameters.
    # Replaying the invocation verbatim would emit -Logging/-OutputFormat with no base name; on the
    # re-run $Logging is already $true, so $script:LoggingAutoEnabled stays $false, the
    # silent-default branch is NOT taken, and the script hits Read-Host again — dying outright in a
    # non-interactive host. Emit the RESOLVED value instead.
    if (-not $script:InvocationBoundParameters.ContainsKey('OutputFileBase') -and
        -not [string]::IsNullOrWhiteSpace($OutputFileBase)) {
        $parts += "-OutputFileBase '$OutputFileBase'"
    }

    $parts += '-EnableVerbose'
    $parts += '-EnableDebug'

    $scriptRef = if ($PSCommandPath) { $PSCommandPath } else { '.\Audit-TierModel.ps1' }

    Write-Host ""
    Write-Host "Re-run with the following for full diagnostics:" -ForegroundColor Yellow
    Write-Host "  & '$scriptRef' $($parts -join ' ')" -ForegroundColor Yellow
    Write-Host "  (writes a log file, and — with both switches — an UNREDACTED transcript under Debug\)" -ForegroundColor DarkYellow
}


# Validate output file requirements and prompt if needed
if ($OutputFormat -and -not $OutputFileBase) {
    # Empty input falls back to the default; an operator pressing Enter must not stop the run.
    $defaultOutputFileBase = 'Audit-TierModel'
    $OutputFileBase = Read-Host "Enter base filename for output (timestamp and extension will be added automatically) [$defaultOutputFileBase]"
    if ([string]::IsNullOrWhiteSpace($OutputFileBase)) {
        $OutputFileBase = $defaultOutputFileBase
        Write-Host "Using default base filename for output: $OutputFileBase" -ForegroundColor DarkGray
    }
}

# --- Logging enablement -------------------------------------------------------------------
# $script:LoggingAutoEnabled distinguishes the two ways -Logging can become active, because
# they have different rules about prompting:
#   explicit — the operator passed -Logging          -> prompt for a missing -OutputFileBase,
#                                                       exactly like the -OutputFormat prompt
#                                                       above and like Deploy-TierModel.ps1.
#   implicit — a diagnostics switch forced it on     -> never prompt (D8); a diagnostics
#                                                       re-run must stay copy-pasteable and
#                                                       runnable in a non-interactive host.
$script:LoggingAutoEnabled = $false

# --- Diagnostics resolution (WI-13) ---------------------------------------------------------
# Mirrors Deploy-TierModel.ps1 exactly. D8: the diagnostics switches auto-enable -Logging, so a
# diagnostic run always leaves a log file behind. The auto-enabled path must NEVER prompt — a
# diagnostics re-run has to stay copy-pasteable and runnable in a non-interactive host — so it
# sets $script:LoggingAutoEnabled and the validation block below takes the silent-default branch.
$script:DiagnosticsEnabled = $EnableVerbose -or $EnableDebug
# Captured while still at script scope: $PSBoundParameters is per-scope, so inside a function it
# would be that function's own bound parameters, not the operator's invocation.
$script:InvocationBoundParameters = $PSBoundParameters
if ($script:DiagnosticsEnabled -and -not $Logging) {
    $Logging = $true
    $script:LoggingAutoEnabled = $true
}

# Validate logging parameters and prompt if needed
if ($Logging -and -not $OutputFileBase) {
    if ($script:LoggingAutoEnabled) {
        $OutputFileBase = 'Audit-TierModel'
    }
    else {
        # Empty input falls back to the default; an operator pressing Enter must not stop the run.
        $defaultLogFileBase = 'Audit-TierModel'
        $OutputFileBase = Read-Host "Enter base filename for logs (timestamp and extension will be added automatically) [$defaultLogFileBase]"
        if ([string]::IsNullOrWhiteSpace($OutputFileBase)) {
            $OutputFileBase = $defaultLogFileBase
            Write-Host "Using default base filename for logs: $OutputFileBase" -ForegroundColor DarkGray
        }
    }
}

# Initialize logging if requested - same file naming/location convention as Deploy-TierModel.ps1
$script:LogFilePath = $null
$script:LogDirectory = $null
if ($Logging) {
    $logTimestamp = Get-Date -Format 'MMddyy-HHmm'
    $logFileName = "$OutputFileBase-$logTimestamp.log"

    # Resolve the log DIRECTORY exactly once, then derive both the log file and the Debug\
    # folder from that single absolutised base so the two can never end up in different places.
    #
    # POC-6: GetUnresolvedProviderPathFromPSPath is the only correct idiom here.
    #   Resolve-Path / Convert-Path  -> throw on a path that does not exist yet.
    #   [System.IO.Path]::GetFullPath() -> BANNED. It resolves against the .NET process current
    #     directory, which does NOT track PowerShell's location, so a *relative* -LogPath would
    #     put the log file and the Debug\ folder in different directories. Absolute paths hide
    #     the bug, so a test that only uses absolute paths will not catch it.
    if ($LogPath) {
        $script:LogDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
    } else {
        # No -LogPath: use the current working directory.
        $script:LogDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Get-Location).Path)
    }

    # Audit is plain [CmdletBinding()] with no -WhatIf, so these New-Item calls need no
    # -WhatIf:$false as Deploy's do. The asymmetry is deliberate. The Test-Path confirmation is
    # not optional - success must be confirmed, never announced.
    if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
        try {
            New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
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

# Check PowerShell version before importing the module. Placed immediately after log-path
# resolution so a version fail-fast can still be written to the log, and before the
# diagnostics/transcript block and Import-Module so no unnecessary work runs first.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-TierModelFailFast -Message @(
        "Deploying and Auditing of the Tier Model requires PowerShell 7.x or later.",
        "Current version: PowerShell $($PSVersionTable.PSVersion)"
    ) -Remediation @(
        "Run the Tier Model from a PowerShell 7 (pwsh) console. If PowerShell 7 is not installed, obtain it from https://aka.ms/powershell."
    )
    return
}

# --- Diagnostics folder (WI-13) -------------------------------------------------------------
# Debug\ lives beside the resolved log file, derived from the SAME absolutised base above so a
# relative -LogPath cannot split them. Failure to create it is never fatal: diagnostics are
# best-effort and must not abort an audit.
$script:DebugFolderPath   = $null
$script:TranscriptPath    = $null
$script:TranscriptStarted = $false
if ($script:DiagnosticsEnabled -and $script:LogDirectory) {
    $candidateDebugFolder = Join-Path $script:LogDirectory 'Debug'
    try {
        if (-not (Test-Path -LiteralPath $candidateDebugFolder)) {
            New-Item -Path $candidateDebugFolder -ItemType Directory -Force | Out-Null
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

# Import TierModel module with all public functions
# -Verbose:$false is load-bearing (suppresses module-load narration); -PassThru is required
# so the module-scope logging initialisation below has a module object to run inside.
$script:TierModelModule = Import-Module (Join-Path $PSScriptRoot 'Modules\TierModel\TierModel.psd1') -Force -Verbose:$false -PassThru

Write-Host "TierModel module loaded successfully." -ForegroundColor Green

# Enable module-scope file logging so Write-TierModelLog calls made *inside* the module
# also reach disk. Audit has no call sites of its own that pass -LogPath, so without this
# every module-level entry (including -Level Error) is console-only and the log file comes
# out effectively empty. Opt-in only: this runs solely when the operator supplied -Logging.
if ($Logging -and $script:LogFilePath) {
    & $script:TierModelModule {
        param($TargetLogFilePath)
        Initialize-TierModelLogging -LogFilePath $TargetLogFilePath | Out-Null
    } $script:LogFilePath
    
    Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "TierModel audit started" -Data @{
        PreferredDc  = $PreferredDc
        OutputFormat = if ($OutputFormat) { $OutputFormat } else { 'None' }
        AdmlLanguage = $AdmlLanguage
    }
    Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "TierModel module loaded successfully"
}

# --- Diagnostics preferences (WI-14) --------------------------------------------------------
# Identical to Deploy-TierModel.ps1. ORDERING IS LOAD-BEARING: these are set AFTER
# Import-Module, never before.
#   POC-8: TierModel.psm1 emits Write-Verbose "Loading: <file>" per public file from inside the
#   module body. -Verbose:$false on the import does NOT suppress those (163 records survive);
#   only importing first, while VerbosePreference is still SilentlyContinue, gets it to 0.
# Both mechanisms are required. -Verbose:$false must stay on the import above, because it is
# what covers the bare ActiveDirectory/GroupPolicy imports that run AFTER preferences go live,
# which ordering alone cannot protect.
#
# POC-9: $script: alone reaches 0 records — module functions resolve preference variables
# function-local -> module scope -> global, and never see the caller's script scope. The
# module-scope assignment via & $module { ... } is therefore genuinely required. It reproduces
# $global: output exactly and, unlike $global:, cannot leak into the operator's session on
# Ctrl-C, so there is no restore/finally and no $Original*Preference capture. The module-scope
# value persists for the rest of the session, but Import-Module -Force above resets module
# scope on every run, so it self-heals.
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

# --- Transcript (WI-15) ---------------------------------------------------------------------
# A transcript is started ONLY when BOTH switches are supplied — identical rule to Deploy.
# -EnableVerbose alone is the routine "show me more" case and must not produce an unredacted
# console capture; requiring both makes the transcript a deliberate act.
#
# Audit has no -WhatIf (plain [CmdletBinding()]), so unlike Deploy it does not need
# -WhatIf:$false here. The Test-Path confirmation still applies and is NOT optional: success
# must never be inferred from the absence of an exception.
#
# POC-3: a nested Start-Transcript is harmless, so there is deliberately no "is a transcript
# already running" pre-check.
if ($script:DiagnosticsEnabled -and $EnableVerbose -and $EnableDebug -and $script:DebugFolderPath) {
    $transcriptStamp = Get-Date -Format 'MMddyy-HHmmss'
    $candidateTranscript = Join-Path $script:DebugFolderPath "Audit-TierModel.transcript.$transcriptStamp.log"
    try {
        Start-Transcript -Path $candidateTranscript -Force -ErrorAction Stop | Out-Null
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
        # Diagnostics are best-effort: warn and carry on, never abort the audit.
        Write-Warning "Diagnostics transcript was not created; continuing without one."
    }
}

# Validate prerequisites
Write-Host "Validating prerequisites..." -ForegroundColor Cyan
try {
    # DependenciesPath must be absolute: the module default is CWD-relative, so the audit would
    # otherwise fail to start whenever it is launched from any directory but its own.
    $prereqResult = Test-TierModelPrerequisites -PreferredDc $PreferredDc -SkipRootCanonicalCheck -DependenciesPath (Join-Path $PSScriptRoot 'config\dependencies.json')
    
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
        # WI-16: offer the diagnostics re-run, then stop the transcript ONLY if we started it.
        Write-TierModelDiagnosticsHint
        Stop-TierModelDiagnosticsTranscript
        exit 1
    }
    
    Write-Host "Prerequisites validation passed." -ForegroundColor Green
}
catch {
    Write-Host "Error running prerequisites check: $($_.Exception.Message)" -ForegroundColor Red
    # WI-16: offer the diagnostics re-run, then stop the transcript ONLY if we started it.
    Write-TierModelDiagnosticsHint
    Stop-TierModelDiagnosticsTranscript
    exit 1
}

# Initialize audit tracking variables
$auditSummary = @{
    TotalChecked = 0
    DriftCount = 0
    MissingCount = 0
    UnexpectedCount = 0
    MismatchCount = 0
    OrphanedGpoLinkCount = 0
    SecurityDeltaCount = 0
    ErrorCount = 0
    # Every key consumed by the report/XML/log MUST be initialized here. Under
    # Set-StrictMode -Version Latest a missing hashtable key throws on read, so an
    # uninitialized key would take down report generation on the scopes that never set it.
    UnverifiedCount = 0
}
$driftFindings = @()
$selectedScope = if ($OuOnly) { 'OuOnly' } elseif ($GroupOnly) { 'GroupOnly' } elseif ($UserOnly) { 'UserOnly' } elseif ($GposOnly) { 'GposOnly' } elseif ($OuAclsOnly) { 'OuAclsOnly' } elseif ($AdmxOnly) { 'AdmxOnly' } else { 'FullDeployment' }

# Load configuration
Write-Host "Loading configuration..." -ForegroundColor Cyan
try {
    $config = Get-TierModelConfig
    Write-Host "Configuration loaded successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    # WI-16: offer the diagnostics re-run, then stop the transcript ONLY if we started it.
    Write-TierModelDiagnosticsHint
    Stop-TierModelDiagnosticsTranscript
    exit 1
}

# Validate configuration against schema. Audit is read-only and cannot damage the
# environment, so a validation failure produces a prominent warning and continues rather
# than exiting — refusing to run would remove the operator's diagnostic tool exactly when
# they need it most. Findings computed from an invalid config may be unreliable.
# Three mutually exclusive branches — threw / ran-with-errors / ran-clean.
Write-Host "Validating configuration for scope '$selectedScope'..." -ForegroundColor Cyan
try {
    $configValidation = Test-TierModelConfig -Config $config -Scope $selectedScope
} catch {
    Write-Host ""
    Write-Host "⚠️  WARNING: Configuration validation threw an unexpected error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "   Audit is proceeding. Findings may be unreliable." -ForegroundColor Yellow
    Write-Host ""
    $configValidation = $null
}
if ($null -eq $configValidation) {
    # Threw — already warned above. Do NOT claim success.
} elseif ($configValidation.Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠️  WARNING: Configuration validation found the following errors. Audit is proceeding" -ForegroundColor Yellow
    Write-Host "   but findings computed from an invalid config may be unreliable. Resolve these" -ForegroundColor Yellow
    Write-Host "   errors before acting on audit results:" -ForegroundColor Yellow
    foreach ($err in $configValidation.Errors) {
        Write-Host "   ❌ $err" -ForegroundColor Red
    }
    Write-Host ""
} else {
    if ($configValidation.Warnings.Count -gt 0) {
        Write-Host "Configuration validation warnings:" -ForegroundColor Yellow
        foreach ($warn in $configValidation.Warnings) {
            Write-Host "  $warn" -ForegroundColor Yellow
        }
    }
    Write-Host "Configuration validation passed." -ForegroundColor Green
    Write-Host ""
}

# Planned orchestration pattern (placeholder):
# 1. Load config via Get-TierModelConfig
# 2. For scope-only (e.g. -OuOnly): Call Test-TierModelOu for audit report
# 3. FullDeployment: Sequence all Test-* respecting dependency order
#    Order target: OU -> Groups -> Users -> OU ACL Delegations -> GPOs -> ADMX
# 4. Consolidate per-entity discrepancies into single audit report

function Invoke-OuAudit {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Auditing organizational units..." -ForegroundColor Cyan
    }
    
    # Perform OU audit
    $audit = Test-TierModelOu -Config $Config -DomainController $DomainController -IncludeResolvedPaths -Silent:$Silent
    
    # Add entity type to audit result for consolidated reporting
    $audit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'OU' -Force
    
    # Display audit summary (only if not Silent)
    if (-not $Silent) {
        Write-Host "" # Blank line for spacing
        Write-Host "OU Audit Summary:" -ForegroundColor White
        Write-Host "  Total Checked: $($audit.Summary.TotalChecked)" -ForegroundColor Gray
        Write-Host "  Missing: $($audit.Summary.MissingCount)" -ForegroundColor Red
        Write-Host "  Mismatched: $($audit.Summary.MismatchCount)" -ForegroundColor Yellow
        # Objects whose state could not be read are neither missing nor mismatched, so without
        # this line the breakdown above does not sum to the Total Drift below it.
        $unverifiedCount = Get-TierModelUnverifiedCount $audit.Summary
        Write-Host "  Unverified (read failures): $unverifiedCount" -ForegroundColor $(if ($unverifiedCount -eq 0) { 'Gray' } else { 'Red' })
        Write-Host "  Total Drift: $($audit.Summary.DriftCount)" -ForegroundColor $(if ($audit.Summary.DriftCount -eq 0) { 'Green' } else { 'Red' })
        
        # Errors, nothing-configured and a real percentage are three different outcomes. The
        # shared renderer keeps them distinct here and at every other section.
        Write-TierModelComplianceLine -TotalChecked $audit.Summary.TotalChecked -DriftCount $audit.Summary.DriftCount -ErrorCount $audit.Errors.Count
        Write-Host "" # Blank line for spacing
        
        if ($audit.Warnings.Count -gt 0) {
            Write-Host "Warnings:" -ForegroundColor Yellow
            $audit.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
        
        if ($audit.Errors.Count -gt 0) {
            Write-Host "Errors:" -ForegroundColor Red
            $audit.Errors | ForEach-Object { Write-Host "  - $($_.Message)" -ForegroundColor Red }
        }
        
        # Display drift findings
        if ($audit.DriftFindings.Count -gt 0) {
            Write-Host "Drift Findings:" -ForegroundColor Red
            $audit.DriftFindings | ForEach-Object {
                $color = Get-TierModelFindingColor $_.Type
                Write-Host "  [$($_.Type)] $($_.Identifier): $($_.Details)" -ForegroundColor $color
            }
        } else {
            # FINAL-2: no drift findings is only good news if the audit actually completed.
            # A total failure produces zero findings because nothing ever ran.
            if ($audit.Errors.Count -gt 0) {
                Write-Host "  ⚠️  OU compliance could NOT be determined - the audit reported errors above." -ForegroundColor Red
            } else {
                Write-Host "  ✅ All OUs match configuration expectations." -ForegroundColor Green
            }
        }
        Write-Host "" # Blank line before script completion message
    }
    
    return $audit
}

function Invoke-GroupAudit {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Auditing groups..." -ForegroundColor Cyan
    }
    
    # Perform Group audit  
    $audit = Test-TierModelGroup -Config $Config -DomainController $DomainController -Silent:$Silent
    
    # Add entity type to audit result for consolidated reporting
    $audit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'Group' -Force
    
    # Display audit summary (only if not Silent)
    if (-not $Silent) {
        Write-Host "" # Blank line for spacing
        Write-Host "Group Audit Summary:" -ForegroundColor White
        Write-Host "  Total Checked: $($audit.Summary.TotalChecked)" -ForegroundColor Gray
        Write-Host "  Missing: $($audit.Summary.MissingCount)" -ForegroundColor Red
        Write-Host "  Mismatched: $($audit.Summary.MismatchCount)" -ForegroundColor Yellow
        # Objects whose state could not be read are neither missing nor mismatched, so without
        # this line the breakdown above does not sum to the Total Drift below it.
        $unverifiedCount = Get-TierModelUnverifiedCount $audit.Summary
        Write-Host "  Unverified (read failures): $unverifiedCount" -ForegroundColor $(if ($unverifiedCount -eq 0) { 'Gray' } else { 'Red' })
        Write-Host "  Total Drift: $($audit.Summary.DriftCount)" -ForegroundColor $(if ($audit.Summary.DriftCount -eq 0) { 'Green' } else { 'Red' })
        
        # Same three outcomes as every other section.
        Write-TierModelComplianceLine -TotalChecked $audit.Summary.TotalChecked -DriftCount $audit.Summary.DriftCount -ErrorCount $audit.Errors.Count
        Write-Host "" # Blank line for spacing
        
        if ($audit.Warnings.Count -gt 0) {
            Write-Host "Warnings:" -ForegroundColor Yellow
            $audit.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
        
        if ($audit.Errors.Count -gt 0) {
            Write-Host "Errors:" -ForegroundColor Red
            $audit.Errors | ForEach-Object { Write-Host "  - $($_.Message)" -ForegroundColor Red }
        }
        
        # Display drift findings
        if ($audit.DriftFindings.Count -gt 0) {
            Write-Host "Drift Findings:" -ForegroundColor Red
            $audit.DriftFindings | ForEach-Object {
                $color = Get-TierModelFindingColor $_.Type
                Write-Host "  [$($_.Type)] $($_.Identifier): $($_.Details)" -ForegroundColor $color
            }
        } else {
            # Zero findings is only good news if the audit completed (see FINAL-2).
            if ($audit.Errors.Count -gt 0) {
                Write-Host "  ⚠️  Group compliance could NOT be determined - the audit reported errors above." -ForegroundColor Red
            } else {
                Write-Host "  ✅ All Groups match configuration expectations." -ForegroundColor Green
            }
        }
        Write-Host "" # Blank line before script completion message
    }
    
    return $audit
}

function Invoke-UserAudit {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Silent  # For FullDeployment - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Auditing users..." -ForegroundColor Cyan
    }
    
    # Perform User audit
    $audit = Test-TierModelUser -Config $Config -DomainController $DomainController -Silent:$Silent
    
    # Add entity type to audit result for consolidated reporting
    $audit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'User' -Force
    
    # Display audit summary (only if not Silent)
    if (-not $Silent) {
        Write-Host "" # Blank line for spacing
        Write-Host "User Audit Summary:" -ForegroundColor White
        Write-Host "  Total Checked: $($audit.Summary.TotalChecked)" -ForegroundColor Gray
        Write-Host "  Missing: $($audit.Summary.MissingCount)" -ForegroundColor Red
        Write-Host "  Mismatched: $($audit.Summary.MismatchCount)" -ForegroundColor Yellow
        # Objects whose state could not be read are neither missing nor mismatched, so without
        # this line the breakdown above does not sum to the Total Drift below it.
        $unverifiedCount = Get-TierModelUnverifiedCount $audit.Summary
        Write-Host "  Unverified (read failures): $unverifiedCount" -ForegroundColor $(if ($unverifiedCount -eq 0) { 'Gray' } else { 'Red' })
        Write-Host "  Total Drift: $($audit.Summary.DriftCount)" -ForegroundColor $(if ($audit.Summary.DriftCount -eq 0) { 'Green' } else { 'Red' })
        
        # Same three outcomes as every other section.
        Write-TierModelComplianceLine -TotalChecked $audit.Summary.TotalChecked -DriftCount $audit.Summary.DriftCount -ErrorCount $audit.Errors.Count
        Write-Host "" # Blank line for spacing
        
        if ($audit.Warnings.Count -gt 0) {
            Write-Host "Warnings:" -ForegroundColor Yellow
            $audit.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
        
        if ($audit.Errors.Count -gt 0) {
            Write-Host "Errors:" -ForegroundColor Red
            $audit.Errors | ForEach-Object { Write-Host "  - $($_.Message)" -ForegroundColor Red }
        }
        
        # Display drift findings
        if ($audit.DriftFindings.Count -gt 0) {
            Write-Host "Drift Findings:" -ForegroundColor Red
            $audit.DriftFindings | ForEach-Object {
                $color = Get-TierModelFindingColor $_.Type
                Write-Host "  [$($_.Type)] $($_.Identifier): $($_.Details)" -ForegroundColor $color
            }
        } else {
            # Zero findings is only good news if the audit completed (see FINAL-2).
            if ($audit.Errors.Count -gt 0) {
                Write-Host "  ⚠️  User compliance could NOT be determined - the audit reported errors above." -ForegroundColor Red
            } else {
                Write-Host "  ✅ All Users match configuration expectations." -ForegroundColor Green
            }
        }
        Write-Host "" # Blank line before script completion message
    }
    
    return $audit
}

function Invoke-OuAclAudit {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Silent  # For FullAudit - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Auditing OU ACL delegations..." -ForegroundColor Cyan
    }
    
    # Ensure GUID resolution functions are loaded (required by ACL processing)
    if (-not (Get-Command Resolve-TierModelGuid -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Resolve-TierModelGuid.ps1"
    }
    if (-not (Get-Command Resolve-DomainSpecificGuid -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\modules\TierModel\public\Resolve-DomainSpecificGuid.ps1"
    }
    
    # Perform OU ACL audit - the Test function will display its own summary
    $audit = Test-TierModelOuAcl -Config $Config -DomainController $DomainController -Silent:$Silent
    
    # Add entity type to audit result for consolidated reporting
    $audit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'OU ACL' -Force

    # Project the audit's findings into the DriftFindings shape the report consumers render.
    # Routed through the shared normaliser so this scope uses the same vocabulary as every other
    # producer: each finding keeps its own Type, and the console colour is derived from that
    # Type's severity class. A configuration warning therefore renders as '[Warning]' in yellow
    # rather than being reported as an error the audit did not encounter, while 'Error' findings
    # continue to render as errors.
    $ouAclDriftFindings = @()
    if (($audit.PSObject.Properties.Name -contains 'Findings') -and $audit.Findings) {
        $ouAclDriftFindings = @($audit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'ACL')
    }
    $audit | Add-Member -NotePropertyName 'DriftFindings' -NotePropertyValue $ouAclDriftFindings -Force

    return $audit
}

function Invoke-GpoAudit {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$Silent  # For FullAudit - suppress progress output, return data only
    )
    
    if (-not $Silent) {
        Write-Host "Auditing GPOs..." -ForegroundColor Cyan
    }
    
    # Perform GPO audit
    $audit = Test-TierModelGPOAudit -Config $Config -DomainController $DomainController -Silent:$Silent
    
    # Add entity type to audit result for consolidated reporting
    $audit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'GPO' -Force
    
    if (-not $Silent) {
        Write-Host "" # Blank line for spacing
        # Display audit summary with consistent format
        Write-Host "GPO Audit Summary:" -ForegroundColor White
        Write-Host "  Total Checked: $($audit.Summary.TotalGpos)" -ForegroundColor Gray
        # The producer publishes three mutually exclusive failure buckets - Missing, Error,
        # Mismatch - and the console reports each as its own line. The three sum to the Total
        # Drift printed below. A shape that does not publish the buckets reports the whole of
        # drift as Mismatched.
        $gpoSummaryKeys = $audit.Summary.PSObject.Properties.Name
        $gpoHasBuckets = ($gpoSummaryKeys -contains 'MissingGpos') -and
                         ($gpoSummaryKeys -contains 'ConfigurationMismatches') -and
                         ($gpoSummaryKeys -contains 'AuditErrors')
        $gpoMissing    = if ($gpoHasBuckets) { [int]$audit.Summary.MissingGpos } else { 0 }
        $gpoMismatched = if ($gpoHasBuckets) { [int]$audit.Summary.ConfigurationMismatches } else { $audit.Summary.Drift }
        $gpoErrors     = if ($gpoHasBuckets) { [int]$audit.Summary.AuditErrors } else { [int]$audit.Summary.Errors }
        Write-Host "  Missing: $gpoMissing" -ForegroundColor Red
        Write-Host "  Mismatched: $gpoMismatched" -ForegroundColor Yellow
        Write-Host "  Errors: $gpoErrors" -ForegroundColor Red
        Write-Host "  Total Drift: $($audit.Summary.Drift + $audit.Summary.Errors)" -ForegroundColor $(if (($audit.Summary.Drift + $audit.Summary.Errors) -eq 0) { 'Green' } else { 'Red' })
        Write-TierModelComplianceLine -TotalChecked $audit.Summary.TotalGpos -ErrorCount $gpoErrors -Percentage $audit.Summary.CompliancePercentage
        Write-Host "" # Blank line for spacing
        
        # Display findings if any.
        # Read defensively: the wholesale-failure shape returned by Test-TierModelGPOAudit
        # has no Findings property at all, and Set-StrictMode -Version Latest throws on a
        # missing property.
        $gpoErrorCount = 0
        if (($audit.PSObject.Properties.Name -contains 'Errors') -and $audit.Errors) {
            $gpoErrorCount = @($audit.Errors).Count
        }
        $gpoFindingCount = 0
        if (($audit.PSObject.Properties.Name -contains 'Findings') -and $audit.Findings) {
            $gpoFindingCount = @($audit.Findings).Count
        }
        if ($gpoFindingCount -gt 0) {
            Write-Host "GPO Audit Findings:" -ForegroundColor Yellow
            $audit.Findings | ForEach-Object {
                $color = switch ($_.Type) {
                    'Missing' { 'Red' }
                    'Mismatch' { 'Yellow' }
                    'Error' { 'Red' }
                    default { 'Gray' }
                }
                Write-Host "  [$($_.Type)] $($_.GpoName): $($_.Message)" -ForegroundColor $color
            }
        } else {
            # Zero findings is only good news if the audit completed (see FINAL-2).
            if ($gpoErrorCount -gt 0) {
                Write-Host "  ⚠️  GPO compliance could NOT be determined - the audit reported errors above." -ForegroundColor Red
            } else {
                Write-Host "  ✅ All GPOs match configuration expectations." -ForegroundColor Green
            }
        }
        Write-Host "" # Blank line before script completion message
    }
    
    return $audit
}

function Invoke-CanonicalAclAudit {
    <#
    .SYNOPSIS
    Audits canonical DACL order on the domain root and all Tier Model OUs present in AD.
    .DESCRIPTION
    Checks the domain root and each configured Tier Model OU for non-canonical DACLs using
    Test-TierModelCanonicalAcl. Non-canonical DACLs are classified as:
      Case 1 (domain root) — blocker, operator must remediate manually before re-running Deploy.
      Case 2 (Tier OU)     — drift, operator should delete the OU and redeploy.
    Read-only throughout. Makes no writes to Active Directory.
    #>
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController
    )

    $correlationId      = [System.Guid]::NewGuid().ToString()
    $startTime          = Get-Date
    $findings           = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalChecked       = 0
    $compliant          = 0
    $mismatched         = 0
    $errors             = 0
    $skipped            = 0   # Tier OUs absent in AD (not yet deployed); not included in TotalChecked
    $ouPresent          = 0   # Tier OUs that were found in AD and had their DACL checked
    $totalOuConfigured  = $Config.organizationUnits.Count

    # Resolve domain DN once for placeholder substitution.
    # There is no legitimate "not found" case and no graceful fallback: a $null domain DN would turn
    # every downstream placeholder substitution into a garbage DN and the audit would report a
    # confident, wrong verdict. Both callers wrap this in try/catch, so later phases still run.
    try {
        $domainDn = (Get-ADDomain -Server $DomainController -ErrorAction Stop).DistinguishedName
    }
    catch {
        $message = "Failed to resolve the domain distinguished name from '$DomainController': $($_.Exception.Message)"
        Write-TierModelLog -Level 'Error' -Message $message -Data @{
            LogCode          = 'AuditDomainDnResolutionFailed'
            DomainController = $DomainController
        }
        throw $message
    }
    if ([string]::IsNullOrWhiteSpace($domainDn)) {
        $message = "Resolved an empty domain distinguished name from '$DomainController'. Cannot substitute OU placeholders."
        Write-TierModelLog -Level 'Error' -Message $message -Data @{
            LogCode          = 'AuditDomainDnResolutionFailed'
            DomainController = $DomainController
        }
        throw $message
    }

    # --- Domain root check (Case 1) ---
    try {
        $rootResult = Test-TierModelCanonicalAcl -PreferredDc $DomainController
        $totalChecked++
        if ($rootResult.IsCanonical) {
            $compliant++
        } else {
            $mismatched++
            $principal = if ($rootResult.FirstOffendingPrincipal) { $rootResult.FirstOffendingPrincipal } else { '(unknown)' }
            Write-Warning "AuditNonCanonicalAclDomainRoot: Non-canonical DACL detected on domain root $($rootResult.DistinguishedName). First offending entry: $principal"
            $findings.Add([PSCustomObject]@{
                Type                    = 'Mismatch'
                ResourceType            = 'DomainRoot'
                Identifier              = $rootResult.DistinguishedName
                Case                    = 'Case1'
                LogCode                 = 'AuditNonCanonicalAclDomainRoot'
                FirstOffendingPrincipal = $rootResult.FirstOffendingPrincipal
                Details                 = "Non-canonical DACL on domain root. An explicit Deny ACE sits below an explicit Allow ACE. This blocks OU ACL delegation. Remediate manually before re-running Deploy (see docs/canonical-acl.md). First offending entry: $principal"
            })
        }
    } catch {
        Write-Warning "AuditNonCanonicalAcl: check skipped for '$domainDn': $($_.Exception.Message)"
        $errors++
    }

    # --- Tier Model OU checks (Case 2) ---
    # Build DN per OU using the same Resolve-TierModelPlaceholder logic as New-TierModelOu;
    # skip any OU not yet present in AD (existence is Invoke-OuAudit's responsibility).
    foreach ($ouDef in $Config.organizationUnits) {
        $resolvedPath = Resolve-TierModelPlaceholder -Path $ouDef.path -DomainDN $domainDn
        $ouDn = "OU=$($ouDef.name),$resolvedPath"

        $existsCheck = Test-TierModelOuExists -DistinguishedName $ouDn -DomainController $DomainController
        if (-not $existsCheck.Exists) { $skipped++; continue }

        $ouPresent++
        try {
            $ouResult = Test-TierModelCanonicalAcl -PreferredDc $DomainController -DistinguishedName $ouDn
            $totalChecked++
            if ($ouResult.IsCanonical) {
                $compliant++
            } else {
                $mismatched++
                $principal = if ($ouResult.FirstOffendingPrincipal) { $ouResult.FirstOffendingPrincipal } else { '(unknown)' }
                Write-Warning "AuditNonCanonicalAclTierOu: Non-canonical DACL detected on Tier OU $ouDn. First offending entry: $principal"
                $findings.Add([PSCustomObject]@{
                    Type                    = 'Mismatch'
                    ResourceType            = 'TierModelOU'
                    Identifier              = $ouDn
                    Case                    = 'Case2'
                    LogCode                 = 'AuditNonCanonicalAclTierOu'
                    FirstOffendingPrincipal = $ouResult.FirstOffendingPrincipal
                    Details                 = "Non-canonical DACL on Tier Model OU '$($ouDef.name)'. Indicates a failed or pre-fix Deploy run (disable-inheritance promoted a Deny ACE). Delete this OU and redeploy with the patched New-TierModelOu.ps1. First offending entry: $principal"
                })
            }
        } catch {
            Write-Warning "AuditNonCanonicalAcl: check skipped for '$ouDn': $($_.Exception.Message)"
            $errors++
        }
    }

    $durationMs = [long](New-TimeSpan -Start $startTime -End (Get-Date)).TotalMilliseconds

    # Console summary — explicit breakdown so "Total Checked" is never ambiguous.
    # Zero checks or any error means compliance is unknown, not 100%. Reported inline rather
    # than through the shared renderer: this function is extracted and executed on its own,
    # so it must not depend on a sibling helper. The domain root is always checked, so the
    # "nothing configured" state cannot arise here.
    $complianceUnknown = ($totalChecked -le 0) -or ($errors -gt 0)
    $compliancePct = if ($complianceUnknown) { 0 } else { [math]::Round(($compliant / $totalChecked) * 100, 2) }

    Write-Host ""
    Write-Host "Canonical ACL Audit Summary:" -ForegroundColor White
    Write-Host "  Total Checked: $totalChecked  (domain root + $ouPresent of $totalOuConfigured Tier OUs present)" -ForegroundColor Gray
    Write-Host "  Skipped (not present in AD): $skipped Tier OU(s)" -ForegroundColor $(if ($skipped -gt 0) { 'DarkYellow' } else { 'Gray' })
    Write-Host "  Compliant: $compliant" -ForegroundColor Gray
    Write-Host "  Non-Canonical (Drift): $mismatched" -ForegroundColor $(if ($mismatched -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "  Errors: $errors" -ForegroundColor $(if ($errors -eq 0) { 'Gray' } else { 'Red' })
    if ($complianceUnknown) {
        Write-Host "  Compliance: N/A (could not be determined)" -ForegroundColor Red
    } else {
        Write-Host "  Compliance: $compliancePct% (of checked objects)" -ForegroundColor $(if ($compliancePct -ge 90) { 'Green' } elseif ($compliancePct -ge 70) { 'Yellow' } else { 'Red' })
    }
    Write-Host ""

    foreach ($f in $findings) {
        $caseLabel = if ($f.Case -eq 'Case1') { 'Case 1 - Domain Root' } else { 'Case 2 - Tier OU' }
        $color     = if ($f.Case -eq 'Case1') { 'Red' } else { 'Yellow' }
        Write-Host "[$caseLabel] $($f.Identifier): $($f.Details)" -ForegroundColor $color
    }

    if ($mismatched -eq 0 -and $errors -eq 0) {
        Write-Host "  ✅ All $totalChecked checked object(s) have canonical DACLs." -ForegroundColor Green
        if ($skipped -gt 0) {
            Write-Host "  ⏭️  $skipped Tier OU(s) skipped — not present in AD (create them, then re-audit)." -ForegroundColor Gray
        }
    }
    Write-Host ""

    return [PSCustomObject]@{
        TotalChecked  = $totalChecked
        Compliant     = $compliant
        Mismatched    = $mismatched
        Missing       = 0
        Errors        = $errors
        Drift         = $mismatched
        Skipped       = $skipped
        Findings      = $findings
        DurationMs    = $durationMs
        CorrelationId = $correlationId
    }
}

# Execute audit based on scope
if ($FullDeployment) {
    Write-Host "FullAudit sequence:" -ForegroundColor Magenta
    $auditResults = @()
    
    # Phase 1: OUs (silent mode - no intermediate reporting)
    Write-Host "Phase 1: Auditing OUs..." -ForegroundColor Cyan
    try {
        $ouAudit = Invoke-OuAudit -Config $config -DomainController $PreferredDc -Silent
        if ($ouAudit) { $auditResults += $ouAudit }
    } catch {
        Write-Host "  Warning: OU audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Phase 1b: OU Canonical ACLs — runs immediately after Phase 1 so non-canonical DACL
    # findings contextualise any Phase 4 (OU ACL Delegation) failures.
    Write-Host "Phase 1b: Auditing OU Canonical ACLs..." -ForegroundColor Cyan
    try {
        $canonicalAudit = Invoke-CanonicalAclAudit -Config $config -DomainController $PreferredDc
        if ($canonicalAudit) {
            $canonicalWrapped = [PSCustomObject]@{
                EntityType = 'OU Canonical ACL'
                Summary = @{
                    TotalAcls  = $canonicalAudit.TotalChecked
                    Compliant  = $canonicalAudit.Compliant
                    Missing    = 0
                    Mismatched = $canonicalAudit.Mismatched
                    Errors     = $canonicalAudit.Errors
                    Drift      = $canonicalAudit.Drift
                    Skipped    = $canonicalAudit.Skipped
                }
                Findings      = $canonicalAudit.Findings
                DurationMs    = $canonicalAudit.DurationMs
                CorrelationId = $canonicalAudit.CorrelationId
            }
            $auditResults += $canonicalWrapped
        }
    } catch {
        # NON-BLOCKING-5: the hard-stop inside Invoke-CanonicalAclAudit is correct — the phase
        # must fail loudly rather than return a partial verdict — but catching it here without
        # touching the verdict made the whole canonical-ACL phase silently vanish from the
        # summary. A phase that did not run is not a phase that passed.
        $auditSummary.ErrorCount++
        Write-Host "  Warning: Canonical ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  The canonical ACL phase did NOT complete - its compliance is UNKNOWN, not compliant." -ForegroundColor Yellow
    }

    # Phase 2: Groups
    Write-Host "Phase 2: Auditing Groups..." -ForegroundColor Cyan
    try {
        $groupAudit = Invoke-GroupAudit -Config $config -DomainController $PreferredDc -Silent
        if ($groupAudit) { $auditResults += $groupAudit }
    } catch {
        Write-Host "  Warning: Group audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Phase 3: Users
    Write-Host "Phase 3: Auditing Users..." -ForegroundColor Cyan
    try {
        $userAudit = Invoke-UserAudit -Config $config -DomainController $PreferredDc -Silent
        if ($userAudit) { $auditResults += $userAudit }
    } catch {
        Write-Host "  Warning: User audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Phase 4: OU ACL Delegations
    Write-Host "Phase 4: Auditing OU ACL Delegations..." -ForegroundColor Cyan
    try {
        $ouAclAudit = Invoke-OuAclAudit -Config $config -DomainController $PreferredDc -Silent
        if ($ouAclAudit) { $auditResults += $ouAclAudit }
    } catch {
        Write-Host "  Warning: OU ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Phase 5: GPOs
    Write-Host "Phase 5: Auditing GPOs..." -ForegroundColor Cyan
    try {
        $gpoAudit = Invoke-GpoAudit -Config $config -DomainController $PreferredDc -Silent
        if ($gpoAudit) { $auditResults += $gpoAudit }
    } catch {
        Write-Host "  Warning: GPO audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Phase 6: ADMX Templates
    Write-Host "Phase 6: Auditing ADMX Templates..." -ForegroundColor Cyan
    try {
        $admxAudit = Test-TierModelAdmx -Config $config -DomainController $PreferredDc -AdmlLanguage $AdmlLanguage -Silent
        if ($admxAudit) { 
            $admxAudit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'ADMX' -Force
            $auditResults += $admxAudit 
        }
    } catch {
        Write-Host "  Warning: ADMX audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # === Optional Features: MSA/gMSA/dMSA ACL Audit ===
    if ($activeIncludeCount -gt 0) {
        Write-Host "`n=== Optional Features: MSA/gMSA/dMSA/WinLaps ACL & Decryptor Audit ===" -ForegroundColor Magenta
        
        if ($IncludeMsa) {
            try {
                $msaAudit = Test-TierModelMsaAcl -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($msaAudit) {
                    # Wrap flat result into structure with Summary property for consolidated reporting
                    $msaWrapped = [PSCustomObject]@{
                        EntityType = 'MSA ACL'
                        Summary = @{
                            TotalAcls = $msaAudit.TotalChecked
                            Compliant = $msaAudit.Compliant
                            Missing = $msaAudit.Missing
                            Mismatched = $msaAudit.Mismatched
                            Errors = $msaAudit.Errors
                            Drift = $msaAudit.Drift
                        }
                        Findings = $msaAudit.Findings
                        DurationMs = $msaAudit.DurationMs
                        CorrelationId = $msaAudit.CorrelationId
                    }
                    $auditResults += $msaWrapped
                }
            } catch {
                Write-Host "  Warning: MSA ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        if ($IncludeGmsa) {
            try {
                $gmsaAudit = Test-TierModelGmsaAcl -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($gmsaAudit) {
                    # Wrap flat result into structure with Summary property for consolidated reporting
                    $gmsaWrapped = [PSCustomObject]@{
                        EntityType = 'gMSA ACL'
                        Summary = @{
                            TotalAcls = $gmsaAudit.TotalChecked
                            Compliant = $gmsaAudit.Compliant
                            Missing = $gmsaAudit.Missing
                            Mismatched = $gmsaAudit.Mismatched
                            Errors = $gmsaAudit.Errors
                            Drift = $gmsaAudit.Drift
                        }
                        Findings = $gmsaAudit.Findings
                        DurationMs = $gmsaAudit.DurationMs
                        CorrelationId = $gmsaAudit.CorrelationId
                    }
                    $auditResults += $gmsaWrapped
                }
            } catch {
                Write-Host "  Warning: gMSA ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        if ($IncludeDmsa) {
            try {
                $dmsaAudit = Test-TierModelDmsaAcl -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($dmsaAudit) {
                    # Wrap flat result into structure with Summary property for consolidated reporting
                    $dmsaWrapped = [PSCustomObject]@{
                        EntityType = 'dMSA ACL'
                        Summary = @{
                            TotalAcls = $dmsaAudit.TotalChecked
                            Compliant = $dmsaAudit.Compliant
                            Missing = $dmsaAudit.Missing
                            Mismatched = $dmsaAudit.Mismatched
                            Errors = $dmsaAudit.Errors
                            Drift = $dmsaAudit.Drift
                        }
                        Findings = $dmsaAudit.Findings
                        DurationMs = $dmsaAudit.DurationMs
                        CorrelationId = $dmsaAudit.CorrelationId
                    }
                    $auditResults += $dmsaWrapped
                }
            } catch {
                Write-Host "  Warning: dMSA ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        if ($IncludeWinLaps) {
            try {
                $winLapsAclAudit = Test-TierModelWinLapsAcl -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($winLapsAclAudit) {
                    $winLapsAclWrapped = [PSCustomObject]@{
                        EntityType = 'WinLaps ACL'
                        Summary = @{
                            TotalAcls = $winLapsAclAudit.TotalChecked
                            Compliant = $winLapsAclAudit.Compliant
                            Missing   = $winLapsAclAudit.Missing
                            Mismatched = $winLapsAclAudit.Mismatched
                            Errors    = $winLapsAclAudit.Errors
                            Drift     = $winLapsAclAudit.Drift
                        }
                        Findings      = $winLapsAclAudit.Findings
                        DurationMs    = $winLapsAclAudit.DurationMs
                        CorrelationId = $winLapsAclAudit.CorrelationId
                    }
                    $auditResults += $winLapsAclWrapped
                }
            } catch {
                Write-Host "  Warning: WinLaps ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            try {
                $winLapsDecryptorAudit = Test-TierModelWinLapsDecryptor -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($winLapsDecryptorAudit) {
                    $winLapsDecryptorWrapped = [PSCustomObject]@{
                        EntityType = 'WinLaps Decryptor'
                        Summary = @{
                            TotalAcls = $winLapsDecryptorAudit.TotalChecked
                            Compliant = $winLapsDecryptorAudit.Compliant
                            Missing   = $winLapsDecryptorAudit.Missing
                            Mismatched = $winLapsDecryptorAudit.Mismatched
                            Errors    = $winLapsDecryptorAudit.Errors
                            Drift     = $winLapsDecryptorAudit.Drift
                        }
                        Findings      = $winLapsDecryptorAudit.Findings
                        DurationMs    = $winLapsDecryptorAudit.DurationMs
                        CorrelationId = $winLapsDecryptorAudit.CorrelationId
                    }
                    $auditResults += $winLapsDecryptorWrapped
                }
            } catch {
                Write-Host "  Warning: WinLaps Decryptor audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        if ($EnableAuditing) {
            try {
                $auditRuleAudit = Test-TierModelAuditRule -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($auditRuleAudit) {
                    $auditRuleWrapped = [PSCustomObject]@{
                        EntityType = 'Domain Audit Rule'
                        Summary = @{
                            TotalAcls  = $auditRuleAudit.TotalChecked
                            Compliant  = $auditRuleAudit.Compliant
                            Missing    = $auditRuleAudit.Missing
                            Mismatched = $auditRuleAudit.Mismatched
                            Errors     = $auditRuleAudit.Errors
                            Drift      = $auditRuleAudit.Drift
                        }
                        Findings      = $auditRuleAudit.Findings
                        DurationMs    = $auditRuleAudit.DurationMs
                        CorrelationId = $auditRuleAudit.CorrelationId
                    }
                    $auditResults += $auditRuleWrapped
                }
            } catch {
                Write-Host "  Warning: Domain Audit Rule audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        if ($IncludeAuthSilos) {
            try {
                $authPoliciesAudit = Test-TierModelAuthPolicy -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($authPoliciesAudit) {
                    $auditResults += [PSCustomObject]@{
                        EntityType = 'Auth Policies'
                        Summary = @{
                            TotalChecked = $authPoliciesAudit.TotalChecked
                            Compliant    = $authPoliciesAudit.Compliant
                            Missing      = $authPoliciesAudit.Missing
                            Mismatched   = $authPoliciesAudit.NonCompliant
                            Errors       = $authPoliciesAudit.Errors
                            Drift        = $authPoliciesAudit.Drift
                        }
                        Findings      = $authPoliciesAudit.Findings
                        DurationMs    = $authPoliciesAudit.DurationMs
                        CorrelationId = $authPoliciesAudit.CorrelationId
                    }
                }
            } catch {
                Write-Host "  Warning: Auth Policy audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            try {
                $authSilosAudit = Test-TierModelAuthSilo -Config $config -DomainController $PreferredDc -SuppressSummary
                if ($authSilosAudit) {
                    $auditResults += [PSCustomObject]@{
                        EntityType = 'Auth Silos'
                        Summary = @{
                            TotalChecked = $authSilosAudit.TotalChecked
                            Compliant    = $authSilosAudit.Compliant
                            Missing      = $authSilosAudit.Missing
                            Mismatched   = $authSilosAudit.NonCompliant
                            Errors       = $authSilosAudit.Errors
                            Drift        = $authSilosAudit.Drift
                        }
                        Findings      = $authSilosAudit.Findings
                        DurationMs    = $authSilosAudit.DurationMs
                        CorrelationId = $authSilosAudit.CorrelationId
                    }
                }
            } catch {
                Write-Host "  Warning: Auth Silo audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    # Show consolidated audit report at the end
    Write-Host "`n=== Full Audit Results ===" -ForegroundColor Magenta
    
    # Helper function to safely get property values
    function Get-SafePropertyValue($obj, $propertyPath) {
        if ($null -eq $obj) { return 0 }
        $parts = $propertyPath -split '\.'
        $current = $obj
        foreach ($part in $parts) {
            if ($current.PSObject.Properties.Name -contains $part) {
                $current = $current.$part
                if ($null -eq $current) { return 0 }
            } else {
                return 0
            }
        }
        if ($current -is [array]) { return $current.Count }
        if ($current -is [System.Collections.ICollection]) { return $current.Count }
        try { return [int]$current } catch { return 0 }
    }
    
    # Presence and value readers that work for BOTH Summary representations
    # (hashtable from Test-TierModelOu/Group/User, PSCustomObject from the ACL family).
    # Presence must be distinguishable from a zero VALUE: "this producer publishes no drift
    # total at all" and "this producer published a drift total of 0" require opposite
    # treatment below, and Get-SafePropertyValue collapses them both to 0.
    function Test-SummaryKey($summary, [string]$key) {
        if ($null -eq $summary) { return $false }
        if ($summary -is [System.Collections.IDictionary]) { return $summary.Contains($key) }
        return ($summary.PSObject.Properties.Name -contains $key)
    }

    function Get-SummaryCount($summary, [string]$key) {
        if (-not (Test-SummaryKey $summary $key)) { return 0 }
        $raw = if ($summary -is [System.Collections.IDictionary]) { $summary[$key] } else { $summary.$key }
        if ($null -eq $raw) { return 0 }
        if ($raw -is [array] -or $raw -is [System.Collections.ICollection]) { return $raw.Count }
        try { return [int]$raw } catch { return 0 }
    }

    # ONE definition of "what did this entity report", called by BOTH the grand-total loop below
    # and the per-section counter further down, so the two cannot disagree.
    #
    # Summary is read through the hashtable-aware helpers above rather than a dotted-path
    # property walk. Every standalone producer (MSA/gMSA/dMSA ACL, WinLaps ACL, WinLaps
    # Decryptor, Domain Audit Rule, Auth Policies, Auth Silos) publishes its Summary as a
    # hashtable literal, and a hashtable's PSObject.Properties are IsReadOnly/Keys/Values/Count
    # - never its keys - so a property walk cannot reach Drift/Missing/Mismatched.
    #
    # Sharing the computation, rather than patching the second copy to match the first, is what
    # stops the section line and the grand total from ever drifting apart again.
    function Get-EntityDriftTotals($result) {
        $summary = if ($result.PSObject.Properties.Name -contains 'Summary') { $result.Summary } else { $null }

        $missing    = (Get-SummaryCount $summary 'Missing')    + (Get-SummaryCount $summary 'MissingCount')
        $mismatched = (Get-SummaryCount $summary 'Mismatched') + (Get-SummaryCount $summary 'MismatchCount')
        $unverified = Get-SummaryCount $summary 'UnverifiedCount'

        # No producer publishes both spellings of the drift total (AST-verified), so preferring
        # 'Drift' over 'DriftCount' matches today's behaviour and cannot double-count if a
        # future shape carries both.
        $drift = if (Test-SummaryKey $summary 'Drift') {
            Get-SummaryCount $summary 'Drift'
        } elseif (Test-SummaryKey $summary 'DriftCount') {
            Get-SummaryCount $summary 'DriftCount'
        } else {
            $missing + $mismatched + $unverified
        }

        [PSCustomObject]@{
            Missing    = $missing
            Mismatched = $mismatched
            Unverified = $unverified
            Drift      = $drift
        }
    }

    # Summary.Errors (a count), the top-level Errors collection, and findings whose verdict is
    # 'Error' are THREE representations of the SAME error set - producers emit two or three of
    # them for one underlying failure. The standalone family increments its error counter on
    # exactly the same line that appends the Error finding (AST-verified across MSA/gMSA/dMSA
    # ACL, WinLaps ACL, WinLaps Decryptor, Domain Audit Rule, Auth Policy, Auth Silo and OU ACL),
    # so adding them together double-counts. OU/Group/User publish DriftFindings rather than
    # Findings, so the third source is simply absent for them.
    #
    # Taking the MAXIMUM of all three cannot double-count and cannot under-count relative to any
    # single source: a producer that publishes a count but no findings still reports its count,
    # and a producer that emits Error findings but leaves Summary.Errors at 0 (Test-TierModelAdmx
    # does exactly this) still reports its findings. The previous form - Max(summary, topLevel)
    # PLUS findings - is why an audit that failed once rendered "Errors: 2" above a single error
    # line. That was invisible while the section counter was hashtable-blind and would have
    # become visible the moment it was fixed, so it is corrected here rather than shipped.
    function Get-EntityErrorTotal($result) {
        $summary = if ($result.PSObject.Properties.Name -contains 'Summary') { $result.Summary } else { $null }

        $summaryErrorCount  = Get-SummaryCount $summary 'Errors'
        $topLevelErrorCount = [int](Get-SafePropertyValue $result 'Errors')

        $findingErrorCount = 0
        if (($result.PSObject.Properties.Name -contains 'Findings') -and $result.Findings) {
            $findingErrorCount = @($result.Findings | Where-Object {
                ($_.PSObject.Properties.Name -contains 'Type'   -and $_.Type   -eq 'Error') -or
                ($_.PSObject.Properties.Name -contains 'Status' -and $_.Status -eq 'Error')
            }).Count
        }

        return [Math]::Max([Math]::Max($summaryErrorCount, $topLevelErrorCount), $findingErrorCount)
    }

    # Calculate totals handling different property names across entity types
    $totalChecked = 0
    $totalDrift = 0
    $totalMissing = 0
    $totalMismatched = 0
    $totalUnverified = 0
    $totalErrors = 0
    
    foreach ($result in $auditResults) {
        # Debug: Log result object properties for troubleshooting
        Write-Verbose "Processing audit result with properties: $($result.PSObject.Properties.Name -join ', ')"
        
        # Skip results that lack a Summary property (defensive guard under StrictMode)
        if (-not ($result.PSObject.Properties.Name -contains 'Summary')) {
            Write-Verbose "Skipping result without Summary property (EntityType: $($result.EntityType))"
            continue
        }
        
        # Each audit result has ONE total count - handle both hashtable and PSObject Summary objects
        if ($result.PSObject.Properties.Name -contains 'EntityType' -and $result.EntityType) {
            switch ($result.EntityType) {
                'OU' { 
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] } else { $result.Summary.TotalChecked }
                }
                'Group' { 
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] } else { $result.Summary.TotalChecked }
                }
                'User' { 
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] } else { $result.Summary.TotalChecked }
                }
                'GPO' { 
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalGpos'] } else { $result.Summary.TotalGpos }
                }
                'ADMX' { 
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalFiles'] } else { $result.Summary.TotalFiles }
                }
                'OU ACL' { 
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalAcls'] } else { $result.Summary.TotalAcls }
                }
                { $_ -in 'MSA ACL', 'gMSA ACL', 'dMSA ACL', 'WinLaps ACL', 'WinLaps Decryptor', 'Domain Audit Rule', 'OU Canonical ACL' } {
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalAcls'] } else { $result.Summary.TotalAcls }
                }
                { $_ -in 'Auth Policies', 'Auth Silos' } {
                    $totalChecked += if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] } else { $result.Summary.TotalChecked }
                }
            }
        } else {
            # Fallback - no EntityType, try to find any total count
            $checked = if ($result.Summary -is [hashtable]) {
                $result.Summary['TotalChecked'] -or $result.Summary['TotalAcls'] -or $result.Summary['TotalGpos'] -or $result.Summary['TotalFiles'] -or 0
            } else {
                $result.Summary.TotalChecked -or $result.Summary.TotalAcls -or $result.Summary.TotalGpos -or $result.Summary.TotalFiles -or 0
            }
            $totalChecked += $checked
        }
        
        # Handle different drift property names - one shared computation with the section counter.
        $entityTotals = Get-EntityDriftTotals $result

        $totalMissing    += $entityTotals.Missing
        $totalMismatched += $entityTotals.Mismatched
        $totalUnverified += $entityTotals.Unverified
        $totalDrift      += $entityTotals.Drift

        # Handle error counts - same shared computation the section counter uses.
        $totalErrors += Get-EntityErrorTotal $result
    }
    
    # $totalDrift is accumulated per result in the loop above, honouring each producer's own drift
    # total when it publishes one. Do NOT recompute it globally from Missing/Mismatched/Unverified:
    # the producers fall into two disjoint families and any single formula silently drops one of
    # them. If a producer's own drift total is wrong, fix the producer.

    # $auditSummary.ErrorCount holds increments from phases that THREW and therefore never reached
    # $auditResults, so $totalErrors cannot see them. Folded into $totalErrors itself, not into a
    # display-only variable, so the verdict and the compliance line below both consult it. A run
    # whose phase died has not established compliance and must never render green.
    $totalErrors += $auditSummary.ErrorCount

    # A run that errored has not established compliance, and a run that checked nothing has not
    # established it either. Both outrank the drift verdict, and neither may render green.
    if ($totalErrors -gt 0) {
        Write-Host "Overall Audit Status: ⚠️  COMPLIANCE COULD NOT BE FULLY DETERMINED ($totalErrors error(s))" -ForegroundColor Red
    } elseif ($totalChecked -le 0) {
        Write-Host "Overall Audit Status: ⚪ NOT CHECKED - nothing configured" -ForegroundColor Gray
    } else {
        Write-Host "Overall Audit Status: $(if ($totalDrift -eq 0) { '✅ COMPLIANT' } else { "❌ $totalDrift DRIFT ITEMS" })" -ForegroundColor $(if ($totalDrift -eq 0) { 'Green' } else { 'Red' })
    }
    Write-Host "Overall Summary:" -ForegroundColor White
    Write-Host "  Total Checked: $totalChecked" -ForegroundColor Gray
    Write-Host "  Missing: $totalMissing" -ForegroundColor Red
    Write-Host "  Mismatched: $totalMismatched" -ForegroundColor Yellow
    Write-Host "  Unverified (read failures): $totalUnverified" -ForegroundColor $(if ($totalUnverified -eq 0) { 'Gray' } else { 'Red' })
    Write-Host "  Total Drift: $totalDrift" -ForegroundColor $(if ($totalDrift -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  Total Errors: $totalErrors" -ForegroundColor Red

    Write-TierModelComplianceLine -TotalChecked $totalChecked -DriftCount $totalDrift -ErrorCount $totalErrors
    Write-Host "" # Blank line after compliance
    
    # Show per-entity breakdown
    # Accumulator for the report/Json/Html consumers. It MUST live outside the loop -
    # the per-entity scratch list below is reset on every iteration.
    $consolidatedDriftFindings = @()
    foreach ($result in $auditResults) {
        # Skip results that lack a Summary property (defensive guard under StrictMode)
        if (-not ($result.PSObject.Properties.Name -contains 'Summary')) {
            continue
        }
        
        # Determine entity type safely
        $entityType = if ($result.PSObject.Properties.Name -contains 'EntityType' -and $result.EntityType) { 
            switch ($result.EntityType) {
                'OU' { 'OU' }
                'Group' { 'Group' }
                'User' { 'User' }
                'GPO' { 'GPO' }
                'ADMX' { 'ADMX' }
                'MSA ACL' { 'MSA ACL' }
                'gMSA ACL' { 'gMSA ACL' }
                'dMSA ACL' { 'dMSA ACL' }
                'WinLaps ACL' { 'WinLaps ACL' }
                'WinLaps Decryptor' { 'WinLaps Decryptor' }
                'Domain Audit Rule' { 'Domain Audit Rule' }
                'OU Canonical ACL' { 'OU Canonical ACL' }
                'Auth Policies'    { 'Auth Policies' }
                'Auth Silos'       { 'Auth Silos' }
                default { 'OU ACL' }
            }
        } elseif (Get-SafePropertyValue $result 'Summary.TotalOUs' -gt 0) { "OU" }
          elseif (Get-SafePropertyValue $result 'Summary.TotalGroups' -gt 0) { "Group" }
          elseif (Get-SafePropertyValue $result 'Summary.TotalUsers' -gt 0) { "User" }
          elseif (Get-SafePropertyValue $result 'Summary.TotalAcls' -gt 0) { "OU ACL" }
          elseif (Get-SafePropertyValue $result 'Summary.TotalGpos' -gt 0) { "GPO" }
          else { "OU ACL" }
        
        # Calculate entity totals safely - handle both hashtable and PSObject Summary objects
        $entityChecked = if ($result.PSObject.Properties.Name -contains 'EntityType' -and $result.EntityType) {
            switch ($result.EntityType) {
                'OU' { 
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] } 
                    else { $result.Summary.TotalChecked }
                }
                'Group' { 
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] } 
                    else { $result.Summary.TotalChecked }
                }
                'User' { 
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] } 
                    else { $result.Summary.TotalChecked }
                }
                'GPO' { 
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalGpos'] } 
                    else { $result.Summary.TotalGpos }
                }
                'ADMX' { 
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalFiles'] } 
                    else { $result.Summary.TotalFiles }
                }
                'OU ACL' { 
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalAcls'] } 
                    else { $result.Summary.TotalAcls }
                }
                { $_ -in 'MSA ACL', 'gMSA ACL', 'dMSA ACL', 'WinLaps ACL', 'WinLaps Decryptor', 'Domain Audit Rule', 'OU Canonical ACL' } {
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalAcls'] } 
                    else { $result.Summary.TotalAcls }
                }
                { $_ -in 'Auth Policies', 'Auth Silos' } {
                    if ($result.Summary -is [hashtable]) { $result.Summary['TotalChecked'] }
                    else { $result.Summary.TotalChecked }
                }
                default { 
                    # Unknown entity type - try common property names
                    if ($result.Summary -is [hashtable]) {
                        $result.Summary['TotalChecked'] -or $result.Summary['TotalAcls'] -or 0
                    } else {
                        $result.Summary.TotalChecked -or $result.Summary.TotalAcls -or 0
                    }
                }
            }
        } else {
            # Fallback - no EntityType, try to find any total count
            if ($result.Summary -is [hashtable]) {
                $result.Summary['TotalChecked'] -or $result.Summary['TotalAcls'] -or $result.Summary['TotalGpos'] -or $result.Summary['TotalFiles'] -or 0
            } else {
                $result.Summary.TotalChecked -or $result.Summary.TotalAcls -or $result.Summary.TotalGpos -or $result.Summary.TotalFiles -or 0
            }
        }
        
        # The SAME two helpers the grand total above consumes, so the per-section line and the
        # Overall Summary are now guaranteed to reconcile: the sum of every section's Drift is
        # exactly $totalDrift, and the sum of every section's Errors is exactly $totalErrors
        # (before the phase-level throws that never reached $auditResults are folded in).
        $entityTotals = Get-EntityDriftTotals $result
        $entityDrift  = $entityTotals.Drift
        $entityErrors = Get-EntityErrorTotal $result
        Write-Host "${entityType}:" -ForegroundColor Cyan
        Write-Host "  Checked: $entityChecked, Drift: $entityDrift, Errors: $entityErrors" -ForegroundColor Gray
        
        # Show drift findings safely
        # Branch, never accumulate both: Invoke-OuAclAudit publishes DriftFindings AND the raw Findings
        # that projection was built from, so normalising both would itemise every OU ACL finding twice.
        # Test for the property being PRESENT, not non-empty: a compliant result publishes an EMPTY
        # DriftFindings and must stay empty rather than falling through.
        # Everything else is routed through ConvertTo-TierModelDriftFinding rather than a wider
        # Where-clause: it drops the compliant shapes by EXACT match and guarantees the
        # Type/ResourceType/Identifier/Details the console block below interpolates.
        $entityDriftFindings = @()
        if ($result.PSObject.Properties.Name -contains 'DriftFindings') {
            if ($result.DriftFindings) { $entityDriftFindings += @($result.DriftFindings) }
        }
        elseif (($result.PSObject.Properties.Name -contains 'Findings') -and $result.Findings) {
            # The SAME -DefaultResourceType values the standalone branches pass, so the two
            # paths cannot describe one finding differently. Inert for producers whose findings
            # already carry a ResourceType of their own (ADMX, OU Canonical ACL) because the
            # normaliser prefers the finding's own value; load-bearing for the rest.
            $entityResourceType = switch ($entityType) {
                'GPO'               { 'GPO' }
                'MSA ACL'           { 'ACL' }
                'gMSA ACL'          { 'ACL' }
                'dMSA ACL'          { 'ACL' }
                'WinLaps ACL'       { 'LapsPermission' }
                'WinLaps Decryptor' { 'LapsDecryptor' }
                'Domain Audit Rule' { 'DomainAuditRule' }
                'Auth Policies'     { 'AuthPolicy' }
                'Auth Silos'        { 'AuthSilo' }
                'OU Canonical ACL'  { 'CanonicalAcl' }
                default             { 'Unknown' }
            }
            $entityDriftFindings += @($result.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType $entityResourceType)
        }

        # Carry this entity's findings out of the loop for the report consumers.
        $consolidatedDriftFindings += $entityDriftFindings

        if ($entityDriftFindings.Count -gt 0) {
            $entityDriftFindings | ForEach-Object {
                $color = Get-TierModelFindingColor $_.Type
                Write-Host "    [$($_.Type)] $($_.Identifier): $($_.Details)" -ForegroundColor $color
            }
        }
        
        # Show errors safely
        if ($result.PSObject.Properties.Name -contains 'Errors' -and $result.Errors) {
            $errorCount = Get-SafePropertyValue $result 'Errors'
            if ($errorCount -gt 0) {
                $result.Errors | ForEach-Object { Write-Host "    ERROR: $($_.Message)" -ForegroundColor Red }
            }
        }
    }

    # Publish the accumulated findings. The five single-entity branches below assign
    # $driftFindings with '=' from their own result and are unaffected by this.
    $driftFindings = $consolidatedDriftFindings

    # Publish the consolidated totals into $auditSummary: the report body, the NUnit XML, the log
    # record and the drift-triggered diagnostics hint all read it, and everything above accumulated
    # into locals only. This must stay at the END of the consolidated block, before those consumers.
    # ErrorCount uses '=' and NOT '+=': $totalErrors already had $auditSummary.ErrorCount folded
    # into it above, so '+=' here would double-count every phase-level throw.
    $auditSummary.TotalChecked    = $totalChecked
    $auditSummary.DriftCount      = $totalDrift
    $auditSummary.MissingCount    = $totalMissing
    $auditSummary.MismatchCount   = $totalMismatched
    $auditSummary.UnverifiedCount = $totalUnverified
    $auditSummary.ErrorCount      = $totalErrors
}
else {
    # Single-entity operations show immediate reports
    if ($OuOnly) { 
        Write-Host "=== OU-Only Audit ===" -ForegroundColor Magenta
        try {
            $ouResult = Invoke-OuAudit -Config $config -DomainController $PreferredDc
            
            # Update audit summary from OU results
            if ($ouResult -and $ouResult.Summary) {
                $auditSummary.TotalChecked = $ouResult.Summary.TotalChecked
                $auditSummary.DriftCount = $ouResult.Summary.DriftCount
                $auditSummary.MissingCount = $ouResult.Summary.MissingCount
                $auditSummary.MismatchCount = $ouResult.Summary.MismatchCount
            }
            if ($ouResult -and $ouResult.DriftFindings) {
                $driftFindings = @($ouResult.DriftFindings)
            }
        } catch {
            Write-Host "Error during OU audit: $($_.Exception.Message)" -ForegroundColor Red
            # Continue script execution - error is logged but not fatal
        }

        # === Canonical ACL Check (§7 — runs after OU existence audit in OuOnly scope) ===
        Write-Host "=== Canonical ACL Check ===" -ForegroundColor Magenta
        try {
            $canonicalResult = Invoke-CanonicalAclAudit -Config $config -DomainController $PreferredDc
            if ($canonicalResult.Drift -gt 0 -or $canonicalResult.Errors -gt 0) {
                $auditSummary.DriftCount   += $canonicalResult.Drift
                $auditSummary.MismatchCount += $canonicalResult.Mismatched
                $auditSummary.ErrorCount   += $canonicalResult.Errors
            }
            $auditSummary.TotalChecked += $canonicalResult.TotalChecked
        } catch {
            # NON-BLOCKING-5: see the companion catch in the full-audit path. The phase failing
            # loudly is correct; letting it disappear from the verdict is not.
            $auditSummary.ErrorCount++
            Write-Host "  Warning: Canonical ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  The canonical ACL phase did NOT complete - its compliance is UNKNOWN, not compliant." -ForegroundColor Yellow
        }
    }
    if ($GroupOnly) {
        Write-Host "=== Group-Only Audit ===" -ForegroundColor Magenta
        $groupResult = Invoke-GroupAudit -Config $config -DomainController $PreferredDc
        
        # Update audit summary from Group results
        if ($groupResult -and $groupResult.Summary) {
            $auditSummary.TotalChecked = $groupResult.Summary.TotalChecked
            $auditSummary.DriftCount = $groupResult.Summary.DriftCount
            $auditSummary.MissingCount = $groupResult.Summary.MissingCount
            $auditSummary.MismatchCount = $groupResult.Summary.MismatchCount
        }
        if ($groupResult -and $groupResult.DriftFindings) {
            $driftFindings = @($groupResult.DriftFindings)
        }
    }
    if ($UserOnly) { 
        Write-Host "=== User-Only Audit ===" -ForegroundColor Magenta
        $userResult = Invoke-UserAudit -Config $config -DomainController $PreferredDc
        
        # Update audit summary from User results
        if ($userResult -and $userResult.Summary) {
            $auditSummary.TotalChecked = $userResult.Summary.TotalChecked
            $auditSummary.DriftCount = $userResult.Summary.DriftCount
            $auditSummary.MissingCount = $userResult.Summary.MissingCount
            $auditSummary.MismatchCount = $userResult.Summary.MismatchCount
        }
        if ($userResult -and $userResult.DriftFindings) {
            $driftFindings = @($userResult.DriftFindings)
        }
    }
    if ($OuAclsOnly) { 
        Write-Host "=== OU ACL-Only Audit ===" -ForegroundColor Magenta
        $ouAclResult = Invoke-OuAclAudit -Config $config -DomainController $PreferredDc
        
        # Update audit summary from OU ACL results
        if ($ouAclResult -and $ouAclResult.Summary) {
            $auditSummary.TotalChecked = $ouAclResult.Summary.TotalAcls
            $auditSummary.DriftCount = ($ouAclResult.Summary.Missing + $ouAclResult.Summary.Mismatched)
            $auditSummary.MissingCount = $ouAclResult.Summary.Missing
            $auditSummary.MismatchCount = $ouAclResult.Summary.Mismatched
            $auditSummary.ErrorCount = $ouAclResult.Summary.Errors
            $auditSummary.CompliantCount = $ouAclResult.Summary.Compliant
        }
        if ($ouAclResult -and $ouAclResult.DriftFindings) {
            $driftFindings = @($ouAclResult.DriftFindings)
        }
    }
    if ($GposOnly) { 
        Write-Host "=== GPO-Only Audit ===" -ForegroundColor Magenta
        $gpoResult = Invoke-GpoAudit -Config $config -DomainController $PreferredDc
        
        # Update audit summary from GPO results
        if ($gpoResult -and $gpoResult.Summary) {
            $auditSummary.TotalChecked = $gpoResult.Summary.TotalGpos
            $auditSummary.DriftCount = $gpoResult.Summary.Drift
            # Test-TierModelGPOAudit names these MissingGpos/ConfigurationMismatches; they are its own
            # mutually-exclusive failure buckets, not derived by subtraction. Summary.Drift additionally
            # counts GPOs whose audit ERRORED, so Missing + Mismatch is legitimately LESS than Drift
            # Findings by that error count. Do NOT close the gap - the errored GPOs are already reported in
            # ErrorCount, and UnverifiedCount means "read failures".
            # Both reads stay GUARDED: these keys are optional across the Summary shapes this branch must
            # accept, and an unguarded read throws under StrictMode at report time, so a drifted run would
            # produce no report at all.
            $auditSummary.MissingCount = if ($gpoResult.Summary.PSObject.Properties.Name -contains 'MissingGpos') { [int]$gpoResult.Summary.MissingGpos } else { 0 }
            $auditSummary.MismatchCount = if ($gpoResult.Summary.PSObject.Properties.Name -contains 'ConfigurationMismatches') { [int]$gpoResult.Summary.ConfigurationMismatches } else { 0 }
            $auditSummary.ErrorCount = $gpoResult.Summary.Errors
            $auditSummary.CompliantCount = $gpoResult.Summary.Compliant
        }
        if ($gpoResult -and $gpoResult.Findings) {
            # Routed through the shared normaliser rather than hand-building the shape.
            # Test-TierModelGPOAudit emits Type/GpoName/Message only, which the normaliser maps
            # to Type/Identifier/Details; -DefaultResourceType supplies the ResourceType the
            # report requires. Using the normaliser removes the last hand-built findings shape in this file.
            $driftFindings = @($gpoResult.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'GPO')
        }
    }
    if ($AdmxOnly) {
        Write-Host "Auditing ADMX/ADML templates..." -ForegroundColor Cyan
        
        $admxAudit = Test-TierModelAdmx -Config $config -DomainController $PreferredDc -AdmlLanguage $AdmlLanguage
        
        # Add entity type to audit result for consolidated reporting
        $admxAudit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'ADMX' -Force
        
        if ($admxAudit -and ($admxAudit.PSObject.Properties.Name -contains 'Summary') -and $admxAudit.Summary) {
            $auditSummary.TotalChecked  = [int]$admxAudit.Summary.TotalFiles
            $auditSummary.DriftCount    = [int]$admxAudit.Summary.Drift
            # Missing and Mismatched are the producer's breakdown of Drift. When a shape does
            # not publish them the whole of Drift is reported as Mismatched, as before.
            $admxSummaryKeys = $admxAudit.Summary.PSObject.Properties.Name
            $auditSummary.MissingCount  = if ($admxSummaryKeys -contains 'Missing') { [int]$admxAudit.Summary.Missing } else { 0 }
            $auditSummary.MismatchCount = if ($admxSummaryKeys -contains 'Mismatched') { [int]$admxAudit.Summary.Mismatched } else { [int]$admxAudit.Summary.Drift }
            if ($admxAudit.Summary.PSObject.Properties.Name -contains 'Errors') {
                $auditSummary.ErrorCount += [int]$admxAudit.Summary.Errors
            }
        }

        if ($admxAudit -and ($admxAudit.PSObject.Properties.Name -contains 'Findings') -and $admxAudit.Findings) {
            $driftFindings = @($admxAudit.Findings | ConvertTo-TierModelDriftFinding)
        }
        
        Write-Host "" # Blank line for spacing
        # Display audit summary with consistent format
        $admxErrors = if ($admxAudit.Summary.PSObject.Properties.Name -contains 'Errors') { [int]$admxAudit.Summary.Errors } else { 0 }
        Write-Host "ADMX Audit Summary:" -ForegroundColor White
        Write-Host "  Total Checked: $($admxAudit.Summary.TotalFiles)" -ForegroundColor Gray
        Write-Host "  Missing: $($auditSummary.MissingCount)" -ForegroundColor Red
        Write-Host "  Mismatched: $($auditSummary.MismatchCount)" -ForegroundColor Yellow
        Write-Host "  Total Drift: $($admxAudit.Summary.Drift)" -ForegroundColor $(if ($admxAudit.Summary.Drift -eq 0) { 'Green' } else { 'Red' })
        Write-TierModelComplianceLine -TotalChecked $admxAudit.Summary.TotalFiles -ErrorCount $admxErrors -Percentage $admxAudit.Summary.CompliancePercentage
        Write-Host "" # Blank line for spacing
        
        # Display findings if any
        if ($admxAudit.Findings.Count -gt 0) {
            Write-Host "ADMX Audit Findings:" -ForegroundColor Yellow
            $admxAudit.Findings | ForEach-Object {
                $color = switch ($_.Type) {
                    'Missing' { 'Red' }
                    'Mismatch' { 'Yellow' }
                    'Error' { 'Red' }
                    default { 'Gray' }
                }
                Write-Host "  [$($_.Type)] $($_.ResourceType)/$($_.FileName): $($_.Message)" -ForegroundColor $color
            }
        } else {
            # Zero findings is only good news if the audit completed (see FINAL-2).
            # Test-TierModelAdmx reports failure as Summary.Errors, an int on both shapes.
            $admxErrorCount = 0
            if ($admxAudit.Summary.PSObject.Properties.Name -contains 'Errors') {
                $admxErrorCount = [int]$admxAudit.Summary.Errors
            }
            if ($admxErrorCount -gt 0) {
                Write-Host "  ⚠️  ADMX/ADML compliance could NOT be determined - the audit reported errors." -ForegroundColor Red
            } else {
                Write-Host "  ✅ All ADMX/ADML files match configuration expectations." -ForegroundColor Green
            }
        }
        Write-Host "" # Blank line before script completion message
    }
}

# === Standalone -Include* Audit Mode (no scope parameter) ===
if ($activeScopeCount -eq 0 -and $activeIncludeCount -gt 0) {
    # Build a feature-aware label for headers
    $aclLabel = @()
    if ($IncludeMsa)      { $aclLabel += 'MSA' }
    if ($IncludeGmsa)     { $aclLabel += 'gMSA' }
    if ($IncludeDmsa)     { $aclLabel += 'dMSA' }
    if ($IncludeWinLaps)   { $aclLabel += 'WinLaps' }
    if ($IncludeAuthSilos) { $aclLabel += 'Auth Silos' }
    $hasAclIncludes   = $aclLabel.Count -gt 0

    # Build top header: conditionalize "ACL & Decryptor" on whether ACL includes are selected
    if ($hasAclIncludes -and $EnableAuditing) {
        $topHeader     = "Standalone $($aclLabel -join '/') ACL & Decryptor / Domain Audit Rule Audit"
        $resultsHeader = "$($aclLabel -join '/') ACL & Decryptor / Domain Audit Rule Results"
    } elseif ($hasAclIncludes) {
        $topHeader     = "Standalone $($aclLabel -join '/') ACL & Decryptor Audit"
        $resultsHeader = "$($aclLabel -join '/') ACL & Decryptor Audit Results"
    } else {
        # -EnableAuditing only — no ACL includes
        $topHeader     = 'Standalone Domain Audit Rule Audit'
        $resultsHeader = 'Domain Audit Rule Results'
    }
    # $standaloneLabelStr kept for reference; headers built via $topHeader / $resultsHeader above
    Write-Host "`n=== $topHeader ===" -ForegroundColor Magenta
    
    # Load config
    $config = Get-TierModelConfig
    Write-Host "TierModel module loaded successfully." -ForegroundColor Green
    
    # Run prerequisites with Include switches
    Write-Host "Validating prerequisites..." -ForegroundColor Yellow
    # DependenciesPath must be absolute: the module default is CWD-relative, so the audit would
    # otherwise fail to start whenever it is launched from any directory but its own.
    $prereqSplat = @{
        PreferredDc      = $PreferredDc
        DependenciesPath = (Join-Path $PSScriptRoot 'config\dependencies.json')
    }
    if ($IncludeMsa) { $prereqSplat['IncludeMsa'] = $true }
    if ($IncludeGmsa) { $prereqSplat['IncludeGmsa'] = $true }
    if ($IncludeDmsa) { $prereqSplat['IncludeDmsa'] = $true }
    if ($IncludeWinLaps) { $prereqSplat['IncludeWinLaps'] = $true }
    $prereqSplat['SkipRootCanonicalCheck'] = $true
    $prereqs = Test-TierModelPrerequisites @prereqSplat
    
    if (-not $prereqs.Valid) {
        Write-Host "❌ Prerequisites failed:" -ForegroundColor Red
        $prereqs.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Error "Prerequisites validation failed. Cannot proceed with audit." -ErrorAction Stop
    }
    Write-Host "Prerequisites validation passed." -ForegroundColor Green
    
    $standaloneTotalChecked = 0
    $standaloneTotalDrift = 0
    $standaloneTotalErrors = 0
    # Every producer on this path publishes the breakdown - Missing plus either Mismatched or
    # NonCompliant - accumulated in step with $standaloneTotalDrift so the two cannot drift apart.
    # Test-TierModelWinLapsDecryptor is the exception: it defines Drift as Missing + Mismatched +
    # Errors, so when it errors Missing + Mismatch is legitimately LESS than Drift Findings by that
    # error count. Do NOT close the gap - those errors are already carried in ErrorCount, and
    # UnverifiedCount means "read failures".
    $standaloneTotalMissing = 0
    $standaloneTotalMismatched = 0
    # Guarded reader: these are flat result objects under Set-StrictMode -Version Latest, and
    # two of the eight (AuthPolicy/AuthSilo) name the mismatch bucket 'NonCompliant'. Returns a
    # value rather than mutating an outer variable - a '+=' inside a nested function writes a
    # NEW LOCAL and silently discards the result.
    function Get-StandaloneBreakdownCount($auditObject, [string[]]$names) {
        if ($null -eq $auditObject) { return 0 }
        foreach ($n in $names) {
            if ($auditObject.PSObject.Properties.Name -contains $n) {
                $raw = $auditObject.$n
                if ($null -eq $raw) { return 0 }
                try { return [int]$raw } catch { return 0 }
            }
        }
        return 0
    }
    $standaloneFindings = @()
    
    if ($IncludeMsa) {
        try {
            $msaAudit = Test-TierModelMsaAcl -Config $config -DomainController $PreferredDc
            if ($msaAudit) {
                $standaloneTotalChecked += $msaAudit.TotalChecked
                $standaloneTotalDrift += $msaAudit.Drift
                # Accumulate the breakdown in step with the total.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $msaAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $msaAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors += $msaAudit.Errors
                # Capture findings, not just counts.
                if (($msaAudit.PSObject.Properties.Name -contains 'Findings') -and $msaAudit.Findings) { $standaloneFindings += @($msaAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'ACL') }
            }
        } catch {
            Write-Host "  ❌ MSA ACL audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    if ($IncludeGmsa) {
        try {
            $gmsaAudit = Test-TierModelGmsaAcl -Config $config -DomainController $PreferredDc
            if ($gmsaAudit) {
                $standaloneTotalChecked += $gmsaAudit.TotalChecked
                $standaloneTotalDrift += $gmsaAudit.Drift
                # Accumulate the breakdown in step with the total.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $gmsaAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $gmsaAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors += $gmsaAudit.Errors
                # Capture findings, not just counts.
                if (($gmsaAudit.PSObject.Properties.Name -contains 'Findings') -and $gmsaAudit.Findings) { $standaloneFindings += @($gmsaAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'ACL') }
            }
        } catch {
            Write-Host "  ❌ gMSA ACL audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    if ($IncludeDmsa) {
        try {
            $dmsaAudit = Test-TierModelDmsaAcl -Config $config -DomainController $PreferredDc
            if ($dmsaAudit) {
                $standaloneTotalChecked += $dmsaAudit.TotalChecked
                $standaloneTotalDrift += $dmsaAudit.Drift
                # Accumulate the breakdown in step with the total.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $dmsaAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $dmsaAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors += $dmsaAudit.Errors
                # Capture findings, not just counts.
                if (($dmsaAudit.PSObject.Properties.Name -contains 'Findings') -and $dmsaAudit.Findings) { $standaloneFindings += @($dmsaAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'ACL') }
            }
        } catch {
            Write-Host "  ❌ dMSA ACL audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    if ($IncludeWinLaps) {
        try {
            $winLapsAclAudit = Test-TierModelWinLapsAcl -Config $config -DomainController $PreferredDc
            if ($winLapsAclAudit) {
                $standaloneTotalChecked += $winLapsAclAudit.TotalChecked
                $standaloneTotalDrift   += $winLapsAclAudit.Drift
                # Accumulate the breakdown in step with the total.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $winLapsAclAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $winLapsAclAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors  += $winLapsAclAudit.Errors
                # Capture findings, not just counts.
                if (($winLapsAclAudit.PSObject.Properties.Name -contains 'Findings') -and $winLapsAclAudit.Findings) { $standaloneFindings += @($winLapsAclAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'LapsPermission') }
            }
        } catch {
            Write-Host "  ❌ WinLaps ACL audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        try {
            $winLapsDecryptorAudit = Test-TierModelWinLapsDecryptor -Config $config -DomainController $PreferredDc
            if ($winLapsDecryptorAudit) {
                $standaloneTotalChecked += $winLapsDecryptorAudit.TotalChecked
                $standaloneTotalDrift   += $winLapsDecryptorAudit.Drift
                # Accumulate the breakdown in step with the total. This is the one
                # producer whose Drift also includes its error count, so Missing + Mismatch can
                # be less than Drift here by exactly that many - see the note at the declaration.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $winLapsDecryptorAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $winLapsDecryptorAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors  += $winLapsDecryptorAudit.Errors
                # Capture findings, not just counts.
                if (($winLapsDecryptorAudit.PSObject.Properties.Name -contains 'Findings') -and $winLapsDecryptorAudit.Findings) { $standaloneFindings += @($winLapsDecryptorAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'LapsDecryptor') }
            }
        } catch {
            Write-Host "  ❌ WinLaps Decryptor audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if ($EnableAuditing) {
        try {
            $auditRuleAudit = Test-TierModelAuditRule -Config $config -DomainController $PreferredDc
            if ($auditRuleAudit) {
                $standaloneTotalChecked += $auditRuleAudit.TotalChecked
                $standaloneTotalDrift   += $auditRuleAudit.Drift
                # Accumulate the breakdown in step with the total.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $auditRuleAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $auditRuleAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors  += $auditRuleAudit.Errors
                # Capture findings, not just counts.
                if (($auditRuleAudit.PSObject.Properties.Name -contains 'Findings') -and $auditRuleAudit.Findings) { $standaloneFindings += @($auditRuleAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'DomainAuditRule') }
            }
        } catch {
            Write-Host "  ❌ Domain Audit Rule audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if ($IncludeAuthSilos) {
        Write-Host "`nPhase: Authentication Policy Silos" -ForegroundColor Cyan
        try {
            $authPoliciesStandaloneAudit = Test-TierModelAuthPolicy -Config $config -DomainController $PreferredDc
            if ($authPoliciesStandaloneAudit) {
                $standaloneTotalChecked += $authPoliciesStandaloneAudit.TotalChecked
                $standaloneTotalDrift   += $authPoliciesStandaloneAudit.Drift
                # Accumulate the breakdown in step with the total. This producer names
                # its mismatch bucket 'NonCompliant'.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $authPoliciesStandaloneAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $authPoliciesStandaloneAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors  += $authPoliciesStandaloneAudit.Errors
                # Capture findings, not just counts.
                if (($authPoliciesStandaloneAudit.PSObject.Properties.Name -contains 'Findings') -and $authPoliciesStandaloneAudit.Findings) { $standaloneFindings += @($authPoliciesStandaloneAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'AuthPolicy') }
            }
        } catch {
            Write-Host "  ❌ Auth Policy audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        try {
            $authSilosStandaloneAudit = Test-TierModelAuthSilo -Config $config -DomainController $PreferredDc
            if ($authSilosStandaloneAudit) {
                $standaloneTotalChecked += $authSilosStandaloneAudit.TotalChecked
                $standaloneTotalDrift   += $authSilosStandaloneAudit.Drift
                # Accumulate the breakdown in step with the total. This producer names
                # its mismatch bucket 'NonCompliant'.
                $standaloneTotalMissing += Get-StandaloneBreakdownCount $authSilosStandaloneAudit @('Missing')
                $standaloneTotalMismatched += Get-StandaloneBreakdownCount $authSilosStandaloneAudit @('Mismatched','NonCompliant')
                $standaloneTotalErrors  += $authSilosStandaloneAudit.Errors
                # Capture findings, not just counts.
                if (($authSilosStandaloneAudit.PSObject.Properties.Name -contains 'Findings') -and $authSilosStandaloneAudit.Findings) { $standaloneFindings += @($authSilosStandaloneAudit.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'AuthSilo') }
            }
        } catch {
            Write-Host "  ❌ Auth Silo audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n=== $resultsHeader ===" -ForegroundColor Magenta
    # Same verdict rule as the consolidated path: errors outrank drift, and a scope with nothing
    # configured has not passed. Only a completed run over real objects can render green.
    if ($standaloneTotalErrors -gt 0) {
        Write-Host "Overall Status: ⚠️  COMPLIANCE COULD NOT BE FULLY DETERMINED ($standaloneTotalErrors error(s))" -ForegroundColor Red
    } elseif ($standaloneTotalChecked -le 0) {
        Write-Host "Overall Status: ⚪ NOT CHECKED - nothing configured" -ForegroundColor Gray
    } else {
        Write-Host "Overall Status: $(if ($standaloneTotalDrift -eq 0) { '✅ COMPLIANT' } else { "❌ $standaloneTotalDrift DRIFT ITEMS" })" -ForegroundColor $(if ($standaloneTotalDrift -eq 0) { 'Green' } else { 'Red' })
    }
    Write-Host "  Total Checked: $standaloneTotalChecked" -ForegroundColor White
    Write-Host "  Total Drift: $standaloneTotalDrift" -ForegroundColor $(if ($standaloneTotalDrift -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Total Errors: $standaloneTotalErrors" -ForegroundColor $(if ($standaloneTotalErrors -gt 0) { 'Red' } else { 'Green' })

    $auditSummary.TotalChecked = $standaloneTotalChecked
    $auditSummary.DriftCount   = $standaloneTotalDrift
    $auditSummary.MissingCount  = $standaloneTotalMissing
    $auditSummary.MismatchCount = $standaloneTotalMismatched
    $auditSummary.ErrorCount  += $standaloneTotalErrors

    # Already normalised at the eight append sites above, where each producer supplies its own
    # -DefaultResourceType. Normalising once here could only pass a single default, so the three
    # producers that emit no ResourceType would all render as 'Unknown/<name>'. Plain assignment -
    # do not re-pipe it through the normaliser.
    if ($standaloneFindings.Count -gt 0) {
        $driftFindings = @($standaloneFindings)
    }
}

# Generate output file if requested
$outputResult = $null
if ($OutputFormat -and $OutputFileBase) {
    $timestamp = Get-Date -Format 'MMddyy-HHmm'
    $extension = switch ($OutputFormat) {
        'Text' { '.txt' }
        'Json' { '.json' }
        'Html' { '.html' }
        'NUnitXml' { '.xml' }
    }
    
    # NON-BLOCKING-6: derive the report path from the SAME resolved base as the log file and the
    # Debug\ folder, so the .PARAMETER LogPath promise that all three land together actually holds
    # for a relative -LogPath. And confirm the directory with Test-Path instead of announcing it
    # for a relative -LogPath. And confirm the directory with Test-Path instead of announcing it
    # unconditionally. Audit has no -WhatIf (plain [CmdletBinding()]), so unlike Deploy this
    # New-Item needs no -WhatIf:$false; the confirmation is still required.
    $outputFileName = "$OutputFileBase-$timestamp$extension"
    if ($LogPath) {
        $outputDirectory = if ($script:LogDirectory) {
            $script:LogDirectory
        } else {
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
        }
        if (-not (Test-Path -LiteralPath $outputDirectory)) {
            try {
                New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
            }
            catch {
                Write-Warning "Could not create output directory '$outputDirectory': $($_.Exception.Message)"
            }
            if (Test-Path -LiteralPath $outputDirectory) {
                Write-Host "Created output directory: $outputDirectory" -ForegroundColor Gray
            }
            else {
                Write-Warning "Output directory '$outputDirectory' does not exist and could not be created; the report may fail to save."
            }
        }
        $outputPath = Join-Path $outputDirectory $outputFileName
    } else {
        $outputPath = $outputFileName
    }
    
    Write-Host "Generating audit report: $outputPath" -ForegroundColor Cyan
    
    # The FINDINGS list below MUST be joined explicitly. A subexpression that yields an array
    # inside an expandable string is flattened using $OFS, which defaults to a single SPACE, so
    # every finding lands on ONE physical line that no line-based tool can parse. Do not
    # "simplify" the -join away.
    $reportContent = switch ($OutputFormat) {
        'Text' {
            @"
TierModel Drift Audit Report (v0.2)
Generated: $(Get-Date)
Scope: $selectedScope
PreferredDc: $PreferredDc

=== SUMMARY ===
Total Checked: $($auditSummary.TotalChecked)
Drift Findings: $($auditSummary.DriftCount)
- Missing: $($auditSummary.MissingCount)
- Unexpected: $($auditSummary.UnexpectedCount)
- Mismatch: $($auditSummary.MismatchCount)
- Unverified (read failures): $($auditSummary.UnverifiedCount)
- Orphaned GPO Links: $($auditSummary.OrphanedGpoLinkCount)
- Security Deltas: $($auditSummary.SecurityDeltaCount)
Errors: $($auditSummary.ErrorCount)

=== FINDINGS ===
$(if ($driftFindings.Count -eq 0) { "No drift detected - configuration matches AD state" } else { ($driftFindings | ForEach-Object { "[$($_.Type)] $($_.ResourceType)/$($_.Identifier): $($_.Details)" }) -join [Environment]::NewLine })
"@
        }
        'Json' {
            @{
                auditSummary = $auditSummary
                driftFindings = $driftFindings
                metadata = @{
                    scope = $selectedScope
                    preferredDc = $PreferredDc
                    timestamp = Get-Date
                    version = 'v0.2'
                    configHash = if ($config) { $config.ConfigHash } else { 'N/A' }
                }
            } | ConvertTo-Json -Depth 10
        }
        'Html' {
            "<html><body><h1>TierModel Audit Report (v0.2)</h1><p>Scope: $selectedScope</p><p>Findings: $($driftFindings.Count)</p><p>Generated: $(Get-Date)</p></body></html>"
        }
        'NUnitXml' {
            "<?xml version=`"1.0`"?><test-results name=`"TierModelAudit`" total=`"$($auditSummary.TotalChecked)`" failures=`"$($auditSummary.DriftCount)`"></test-results>"
        }
    }
    
    Set-Content -Path $outputPath -Value $reportContent -Encoding UTF8
    $outputResult = $outputPath
    Write-Host "Report saved: $outputResult" -ForegroundColor Cyan
}

if ($Logging -and $script:LogFilePath) {
    Write-TierModelLog -LogPath $script:LogFilePath -Level 'Info' -Message "TierModel audit completed" -Data @{
        TotalChecked = $auditSummary.TotalChecked
        DriftCount   = $auditSummary.DriftCount
        # An operator's log that omits errors and unverified reads loses exactly the
        # signal that distinguishes "compliant" from "could not be determined".
        ErrorCount      = $auditSummary.ErrorCount
        UnverifiedCount = $auditSummary.UnverifiedCount
    }
    Write-Host "Log file saved: $script:LogFilePath" -ForegroundColor Gray
}

Write-Host "" # Blank line before completion message
Write-Host "Audit script completed." -ForegroundColor Green

# NON-BLOCKING-4: mirror Deploy's tail hint. An audit that finishes with drift or with phase
# errors is exactly when the operator wants the diagnostics re-run line; previously Audit's tail
# offered none, so only Deploy did. Self-suppressing when both switches are already on.
if ($auditSummary.DriftCount -gt 0 -or $auditSummary.ErrorCount -gt 0) {
    Write-TierModelDiagnosticsHint
}

# WI-16: final guarded stop. Printed last so the transcript path is the last thing the operator
# sees. Guarded by $script:TranscriptStarted, which whichever exit path ran first has already
# cleared, so this can never stop a transcript we do not own.
Stop-TierModelDiagnosticsTranscript
