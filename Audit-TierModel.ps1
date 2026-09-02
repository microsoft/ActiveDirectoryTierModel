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
Required when OutputFormat is specified.

.PARAMETER AdmlLanguage
Language code for ADMX template processing in format 'xx-XX' (e.g., 'en-US').
Used when auditing ADMX configurations to match appropriate language templates.

.PARAMETER LogPath
Directory path where output files will be created when OutputFormat is specified.
If not provided, files are created in the current directory. Directory will be
created automatically if it doesn't exist.

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
Version: 2.0
Requires: TierModel PowerShell module, appropriate Active Directory permissions
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
    [string]$LogPath
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
}

# Check PowerShell version before importing the module
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-TierModelFailFast -Message @(
        "Deploying and Auditing of the Tier Model requires PowerShell 7.x or later.",
        "Current version: PowerShell $($PSVersionTable.PSVersion)"
    ) -Remediation @(
        "Run the Tier Model from a PowerShell 7 (pwsh) console. If PowerShell 7 is not installed, obtain it from https://aka.ms/powershell."
    )
    return
}

# Validate output file requirements and prompt if needed
if ($OutputFormat -and -not $OutputFileBase) {
    $OutputFileBase = Read-Host "Enter base filename for output (timestamp and extension will be added automatically)"
    if ([string]::IsNullOrWhiteSpace($OutputFileBase)) {
        throw "OutputFileBase cannot be empty when OutputFormat is specified"
    }
}

# Import TierModel module with all public functions
Import-Module (Join-Path $PSScriptRoot 'Modules\TierModel\TierModel.psd1') -Force -Verbose:$false

Write-Host "TierModel module loaded successfully." -ForegroundColor Green

# Validate prerequisites
Write-Host "Validating prerequisites..." -ForegroundColor Cyan
try {
    $prereqResult = Test-TierModelPrerequisites -PreferredDc $PreferredDc -SkipRootCanonicalCheck
    
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
        exit 1
    }
    
    Write-Host "Prerequisites validation passed." -ForegroundColor Green
}
catch {
    Write-Host "Error running prerequisites check: $($_.Exception.Message)" -ForegroundColor Red
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
    exit 1
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
        Write-Host "  Total Drift: $($audit.Summary.DriftCount)" -ForegroundColor $(if ($audit.Summary.DriftCount -eq 0) { 'Green' } else { 'Red' })
        
        # Calculate and display compliance percentage
        $compliancePercentage = if ($audit.Summary.TotalChecked -gt 0) {
            [math]::Round((($audit.Summary.TotalChecked - $audit.Summary.DriftCount) / $audit.Summary.TotalChecked) * 100, 2)
        } else {
            100
        }
        Write-Host "  Compliance: $compliancePercentage%" -ForegroundColor $(if ($compliancePercentage -ge 90) { 'Green' } elseif ($compliancePercentage -ge 70) { 'Yellow' } else { 'Red' })
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
                $color = if ($_.Type -eq 'Missing') { 'Red' } else { 'Yellow' }
                Write-Host "  [$($_.Type)] $($_.Identifier): $($_.Details)" -ForegroundColor $color
            }
        } else {
            Write-Host "  ✅ All OUs match configuration expectations." -ForegroundColor Green
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
        Write-Host "  Total Drift: $($audit.Summary.DriftCount)" -ForegroundColor $(if ($audit.Summary.DriftCount -eq 0) { 'Green' } else { 'Red' })
        
        # Calculate and display compliance percentage
        $compliancePercentage = if ($audit.Summary.TotalChecked -gt 0) {
            [math]::Round((($audit.Summary.TotalChecked - $audit.Summary.DriftCount) / $audit.Summary.TotalChecked) * 100, 2)
        } else {
            100
        }
        Write-Host "  Compliance: $compliancePercentage%" -ForegroundColor $(if ($compliancePercentage -ge 90) { 'Green' } elseif ($compliancePercentage -ge 70) { 'Yellow' } else { 'Red' })
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
                $color = if ($_.Type -eq 'Missing') { 'Red' } else { 'Yellow' }
                Write-Host "  [$($_.Type)] $($_.Identifier): $($_.Details)" -ForegroundColor $color
            }
        } else {
            Write-Host "  ✅ All Groups match configuration expectations." -ForegroundColor Green
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
        Write-Host "  Total Drift: $($audit.Summary.DriftCount)" -ForegroundColor $(if ($audit.Summary.DriftCount -eq 0) { 'Green' } else { 'Red' })
        
        # Calculate and display compliance percentage
        $compliancePercentage = if ($audit.Summary.TotalChecked -gt 0) {
            [math]::Round((($audit.Summary.TotalChecked - $audit.Summary.DriftCount) / $audit.Summary.TotalChecked) * 100, 2)
        } else {
            100
        }
        Write-Host "  Compliance: $compliancePercentage%" -ForegroundColor $(if ($compliancePercentage -ge 90) { 'Green' } elseif ($compliancePercentage -ge 70) { 'Yellow' } else { 'Red' })
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
                $color = if ($_.Type -eq 'Missing') { 'Red' } else { 'Yellow' }
                Write-Host "  [$($_.Type)] $($_.Identifier): $($_.Details)" -ForegroundColor $color
            }
        } else {
            Write-Host "  ✅ All Users match configuration expectations." -ForegroundColor Green
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
        Write-Host "  Missing: 0" -ForegroundColor Red
        Write-Host "  Mismatched: $($audit.Summary.Drift + $audit.Summary.Errors)" -ForegroundColor Yellow
        Write-Host "  Total Drift: $($audit.Summary.Drift + $audit.Summary.Errors)" -ForegroundColor $(if (($audit.Summary.Drift + $audit.Summary.Errors) -eq 0) { 'Green' } else { 'Red' })
        Write-Host "  Compliance: $($audit.Summary.CompliancePercentage)%" -ForegroundColor $(
            if ($audit.Summary.CompliancePercentage -ge 90) { 'Green' } 
            elseif ($audit.Summary.CompliancePercentage -ge 70) { 'Yellow' } 
            else { 'Red' }
        )
        Write-Host "" # Blank line for spacing
        
        # Display findings if any
        if ($audit.Findings.Count -gt 0) {
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
            Write-Host "  ✅ All GPOs match configuration expectations." -ForegroundColor Green
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

    # Resolve domain DN once for placeholder substitution
    $domainDn = (Get-ADDomain -Server $DomainController).DistinguishedName

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

    # Console summary — explicit breakdown so "Total Checked" is never ambiguous
    $compliancePct = if ($totalChecked -gt 0) {
        [math]::Round(($compliant / $totalChecked) * 100, 2)
    } else { 100 }

    Write-Host ""
    Write-Host "Canonical ACL Audit Summary:" -ForegroundColor White
    Write-Host "  Total Checked: $totalChecked  (domain root + $ouPresent of $totalOuConfigured Tier OUs present)" -ForegroundColor Gray
    Write-Host "  Skipped (not present in AD): $skipped Tier OU(s)" -ForegroundColor $(if ($skipped -gt 0) { 'DarkYellow' } else { 'Gray' })
    Write-Host "  Compliant: $compliant" -ForegroundColor Gray
    Write-Host "  Non-Canonical (Drift): $mismatched" -ForegroundColor $(if ($mismatched -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "  Errors: $errors" -ForegroundColor $(if ($errors -eq 0) { 'Gray' } else { 'Red' })
    Write-Host "  Compliance: $compliancePct% (of checked objects)" -ForegroundColor $(if ($compliancePct -ge 90) { 'Green' } elseif ($compliancePct -ge 70) { 'Yellow' } else { 'Red' })
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
        Write-Host "  Warning: Canonical ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
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
    
    # Calculate totals handling different property names across entity types
    $totalChecked = 0
    $totalDrift = 0
    $totalMissing = 0
    $totalMismatched = 0
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
        
        # Handle different drift property names - use safe property access for both hashtables and PSObjects
        if ($result.Summary -is [hashtable]) {
            $totalDrift += if ($result.Summary.ContainsKey('Drift')) { $result.Summary['Drift'] } else { 0 }
            $totalDrift += if ($result.Summary.ContainsKey('DriftCount')) { $result.Summary['DriftCount'] } else { 0 }
            $totalMissing += if ($result.Summary.ContainsKey('Missing')) { $result.Summary['Missing'] } else { 0 }
            $totalMismatched += if ($result.Summary.ContainsKey('Mismatched')) { $result.Summary['Mismatched'] } else { 0 }
        } else {
            $totalDrift += Get-SafePropertyValue $result 'Summary.Drift'
            $totalDrift += Get-SafePropertyValue $result 'Summary.DriftCount'
            $totalMissing += Get-SafePropertyValue $result 'Summary.Missing'
            $totalMismatched += Get-SafePropertyValue $result 'Summary.Mismatched'
        }
        
        # Handle different error property names - use safe property access for both hashtables and PSObjects
        if ($result.Summary -is [hashtable]) {
            $totalErrors += if ($result.Summary.ContainsKey('Errors')) { $result.Summary['Errors'] } else { 0 }
        } else {
            $totalErrors += Get-SafePropertyValue $result 'Summary.Errors'
        }
        $totalErrors += Get-SafePropertyValue $result 'Errors'
        
        # Handle findings-based errors
        if ($result.PSObject.Properties.Name -contains 'Findings' -and $result.Findings) {
            $errorFindings = $result.Findings | Where-Object {
                ($_.PSObject.Properties.Name -contains 'Type'   -and $_.Type   -eq 'Error') -or
                ($_.PSObject.Properties.Name -contains 'Status' -and $_.Status -eq 'Error')
            }
            if ($errorFindings) { 
                $totalErrors += if ($errorFindings -is [array]) { $errorFindings.Count } else { 1 }
            }
        }
    }
    
    # Calculate total drift from missing + mismatched (prioritize new structure)
    if ($totalMissing -gt 0 -or $totalMismatched -gt 0) {
        $totalDrift = $totalMissing + $totalMismatched
    }
    
    Write-Host "Overall Audit Status: $(if ($totalDrift -eq 0) { '✅ COMPLIANT' } else { "❌ $totalDrift DRIFT ITEMS" })" -ForegroundColor $(if ($totalDrift -eq 0) { 'Green' } else { 'Red' })
    Write-Host "Overall Summary:" -ForegroundColor White
    Write-Host "  Total Checked: $totalChecked" -ForegroundColor Gray
    Write-Host "  Missing: $totalMissing" -ForegroundColor Red
    Write-Host "  Mismatched: $totalMismatched" -ForegroundColor Yellow
    Write-Host "  Total Drift: $totalDrift" -ForegroundColor $(if ($totalDrift -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  Total Errors: $totalErrors" -ForegroundColor Red
    
    # Calculate and display compliance percentage
    $compliancePercentage = if ($totalChecked -gt 0) {
        [math]::Round((($totalChecked - $totalDrift) / $totalChecked) * 100, 2)
    } else {
        100
    }
    Write-Host "  Compliance: $compliancePercentage%" -ForegroundColor $(if ($compliancePercentage -ge 90) { 'Green' } elseif ($compliancePercentage -ge 70) { 'Yellow' } else { 'Red' })
    Write-Host "" # Blank line after compliance
    
    # Show per-entity breakdown
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
        
        $entityDrift = (Get-SafePropertyValue $result 'Summary.Drift') + 
                      (Get-SafePropertyValue $result 'Summary.DriftCount') +
                      (Get-SafePropertyValue $result 'Summary.Missing') +
                      (Get-SafePropertyValue $result 'Summary.Mismatched')
        
        $entityErrors = (Get-SafePropertyValue $result 'Summary.Errors') + 
                       (Get-SafePropertyValue $result 'Errors')
        
        # Handle findings-based errors safely
        if ($result.PSObject.Properties.Name -contains 'Findings' -and $result.Findings) {
            $errorFindings = $result.Findings | Where-Object {
                ($_.PSObject.Properties.Name -contains 'Type'   -and $_.Type   -eq 'Error') -or
                ($_.PSObject.Properties.Name -contains 'Status' -and $_.Status -eq 'Error')
            }
            if ($errorFindings) { 
                $entityErrors += if ($errorFindings -is [array]) { $errorFindings.Count } else { 1 }
            }
        }
        
        Write-Host "${entityType}:" -ForegroundColor Cyan
        Write-Host "  Checked: $entityChecked, Drift: $entityDrift, Errors: $entityErrors" -ForegroundColor Gray
        
        # Show drift findings safely
        $driftFindings = @()
        if ($result.PSObject.Properties.Name -contains 'DriftFindings' -and $result.DriftFindings) {
            $driftCount = Get-SafePropertyValue $result 'DriftFindings'
            if ($driftCount -gt 0) { 
                $driftFindings += $result.DriftFindings 
            }
        }
        if ($result.PSObject.Properties.Name -contains 'Findings' -and $result.Findings) {
            $driftFromFindings = $result.Findings | Where-Object {
                ($_.PSObject.Properties.Name -contains 'Type') -and $_.Type -eq 'Drift'
            }
            if ($driftFromFindings) { $driftFindings += $driftFromFindings }
        }
        
        if ($driftFindings.Count -gt 0) {
            $driftFindings | ForEach-Object {
                $color = if ($_.Type -eq 'Missing') { 'Red' } else { 'Yellow' }
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
            Write-Host "  Warning: Canonical ACL audit failed: $($_.Exception.Message)" -ForegroundColor Yellow
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
            $auditSummary.ErrorCount = $ouAclResult.Summary.Errors
            $auditSummary.CompliantCount = $ouAclResult.Summary.Compliant
        }
        if ($ouAclResult -and $ouAclResult.Findings) {
            # Convert OU ACL findings to match expected drift findings format
            $driftFindings = @($ouAclResult.Findings | ForEach-Object {
                [PSCustomObject]@{
                    Type = if ($_.Type -eq 'Drift') { 
                        if ($_.ActualValue -eq 'Missing' -or $_.Details -like "*missing*" -or $_.Details -like "*No Access Control Entry*") { 
                            'Missing' 
                        } else { 
                            'Mismatch' 
                        }
                    } else { 
                        'Error' 
                    }
                    ResourceType = $_.ResourceType
                    Identifier = $_.Identifier
                    Details = $_.Details
                }
            })
        }
    }
    if ($GposOnly) { 
        Write-Host "=== GPO-Only Audit ===" -ForegroundColor Magenta
        $gpoResult = Invoke-GpoAudit -Config $config -DomainController $PreferredDc
        
        # Update audit summary from GPO results
        if ($gpoResult -and $gpoResult.Summary) {
            $auditSummary.TotalChecked = $gpoResult.Summary.TotalGpos
            $auditSummary.DriftCount = $gpoResult.Summary.Drift
            $auditSummary.ErrorCount = $gpoResult.Summary.Errors
            $auditSummary.CompliantCount = $gpoResult.Summary.Compliant
        }
        if ($gpoResult -and $gpoResult.Findings) {
            # Convert GPO findings to match expected drift findings format
            $driftFindings = @($gpoResult.Findings | ForEach-Object {
                [PSCustomObject]@{
                    Type = $_.Type
                    Identifier = $_.GpoName
                    Details = $_.Message
                }
            })
        }
    }
    if ($AdmxOnly) {
        Write-Host "Auditing ADMX/ADML templates..." -ForegroundColor Cyan
        
        $admxAudit = Test-TierModelAdmx -Config $config -DomainController $PreferredDc -AdmlLanguage $AdmlLanguage
        
        # Add entity type to audit result for consolidated reporting
        $admxAudit | Add-Member -NotePropertyName 'EntityType' -NotePropertyValue 'ADMX' -Force
        
        Write-Host "" # Blank line for spacing
        # Display audit summary with consistent format
        Write-Host "ADMX Audit Summary:" -ForegroundColor White
        Write-Host "  Total Checked: $($admxAudit.Summary.TotalFiles)" -ForegroundColor Gray
        Write-Host "  Missing: 0" -ForegroundColor Red
        Write-Host "  Mismatched: $($admxAudit.Summary.Drift)" -ForegroundColor Yellow
        Write-Host "  Total Drift: $($admxAudit.Summary.Drift)" -ForegroundColor $(if ($admxAudit.Summary.Drift -eq 0) { 'Green' } else { 'Red' })
        Write-Host "  Compliance: $($admxAudit.Summary.CompliancePercentage)%" -ForegroundColor $(
            if ($admxAudit.Summary.CompliancePercentage -ge 90) { 'Green' } 
            elseif ($admxAudit.Summary.CompliancePercentage -ge 70) { 'Yellow' } 
            else { 'Red' }
        )
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
            Write-Host "  ✅ All ADMX/ADML files match configuration expectations." -ForegroundColor Green
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
    $prereqSplat = @{ PreferredDc = $PreferredDc }
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
    
    if ($IncludeMsa) {
        try {
            $msaAudit = Test-TierModelMsaAcl -Config $config -DomainController $PreferredDc
            if ($msaAudit) {
                $standaloneTotalChecked += $msaAudit.TotalChecked
                $standaloneTotalDrift += $msaAudit.Drift
                $standaloneTotalErrors += $msaAudit.Errors
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
                $standaloneTotalErrors += $gmsaAudit.Errors
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
                $standaloneTotalErrors += $dmsaAudit.Errors
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
                $standaloneTotalErrors  += $winLapsAclAudit.Errors
            }
        } catch {
            Write-Host "  ❌ WinLaps ACL audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        try {
            $winLapsDecryptorAudit = Test-TierModelWinLapsDecryptor -Config $config -DomainController $PreferredDc
            if ($winLapsDecryptorAudit) {
                $standaloneTotalChecked += $winLapsDecryptorAudit.TotalChecked
                $standaloneTotalDrift   += $winLapsDecryptorAudit.Drift
                $standaloneTotalErrors  += $winLapsDecryptorAudit.Errors
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
                $standaloneTotalErrors  += $auditRuleAudit.Errors
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
                $standaloneTotalErrors  += $authPoliciesStandaloneAudit.Errors
            }
        } catch {
            Write-Host "  ❌ Auth Policy audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        try {
            $authSilosStandaloneAudit = Test-TierModelAuthSilo -Config $config -DomainController $PreferredDc
            if ($authSilosStandaloneAudit) {
                $standaloneTotalChecked += $authSilosStandaloneAudit.TotalChecked
                $standaloneTotalDrift   += $authSilosStandaloneAudit.Drift
                $standaloneTotalErrors  += $authSilosStandaloneAudit.Errors
            }
        } catch {
            Write-Host "  ❌ Auth Silo audit failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n=== $resultsHeader ===" -ForegroundColor Magenta
    Write-Host "Overall Status: $(if ($standaloneTotalDrift -eq 0) { '✅ COMPLIANT' } else { "❌ $standaloneTotalDrift DRIFT ITEMS" })" -ForegroundColor $(if ($standaloneTotalDrift -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  Total Checked: $standaloneTotalChecked" -ForegroundColor White
    Write-Host "  Total Drift: $standaloneTotalDrift" -ForegroundColor $(if ($standaloneTotalDrift -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Total Errors: $standaloneTotalErrors" -ForegroundColor $(if ($standaloneTotalErrors -gt 0) { 'Red' } else { 'Green' })
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
    
    # Use LogPath directory if provided, otherwise use current directory
    $outputFileName = "$OutputFileBase-$timestamp$extension"
    if ($LogPath) {
        # Ensure the directory exists
        if (-not (Test-Path $LogPath)) {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            Write-Host "Created output directory: $LogPath" -ForegroundColor Gray
        }
        $outputPath = Join-Path $LogPath $outputFileName
    } else {
        $outputPath = $outputFileName
    }
    
    Write-Host "Generating audit report: $outputPath" -ForegroundColor Cyan
    
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
- Orphaned GPO Links: $($auditSummary.OrphanedGpoLinkCount)
- Security Deltas: $($auditSummary.SecurityDeltaCount)

=== FINDINGS ===
$(if ($driftFindings.Count -eq 0) { "No drift detected - configuration matches AD state" } else { $driftFindings | ForEach-Object { "[$($_.Type)] $($_.ResourceType)/$($_.Identifier): $($_.Details)" } })
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

Write-Host "" # Blank line before completion message
Write-Host "Audit script completed." -ForegroundColor Green
