function Test-TierModelPrerequisites {
    <#
    .SYNOPSIS
    Validates all prerequisites required for TierModel deployment and audit operations.

    .DESCRIPTION
    Performs comprehensive validation of system prerequisites including:
    - PowerShell version and elevation status
    - Required modules (ActiveDirectory, GroupPolicy, Pester)
    - Domain connectivity and admin permissions
    - Configuration file accessibility
    - Environment type detection (child domain, enterprise admin availability)

    .PARAMETER PreferredDc
    The preferred domain controller to use for validation and testing.

    .PARAMETER DependenciesPath
    Path to the dependencies.json configuration file. Defaults to 'config/dependencies.json'.

    .OUTPUTS
    [PSCustomObject] Returns a prerequisites validation result with:
    - Valid: Boolean indicating if all prerequisites are met
    - Errors: Array of validation errors found
    - Remediation: Array of recommended remediation steps
    - EnvironmentSnapshot: Detailed environment information
    - CorrelationId: Unique identifier for this validation session

    .EXAMPLE
    $prereqs = Test-TierModelPrerequisites -PreferredDc "DC01.contoso.com"
    if (-not $prereqs.Valid) {
        Write-Warning "Prerequisites failed: $($prereqs.Errors -join '; ')"
        Write-Host "Remediation steps: $($prereqs.Remediation -join '; ')"
    }

    .EXAMPLE
    # Test with custom dependencies file
    $result = Test-TierModelPrerequisites -PreferredDc "DC01.contoso.com" -DependenciesPath "custom/deps.json"
    $result.EnvironmentSnapshot | Format-List

    .NOTES
    This function requires elevated privileges for full validation but will continue
    testing in non-elevated scenarios for development and testing purposes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PreferredDc,
        
        [Parameter(Mandatory = $false)]
        [string]$DependenciesPath = 'config/dependencies.json',
        
        [switch]$IncludeMsa,
        [switch]$IncludeGmsa,
        [switch]$IncludeDmsa,
        [switch]$IncludeWinLaps,

        # When set, the root-canonical check still runs and records truth into
        # EnvironmentSnapshot.RootAclCanonical, but a non-canonical root does NOT
        # set Valid=$false. Used by Audit so Invoke-CanonicalAclAudit can surface
        # the formal Case 1 finding instead of halting at prerequisites.
        [switch]$SkipRootCanonicalCheck
    )
    
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version 3.0
    
    # Use provided CorrelationId or fallback to script-level or generate new one
    $CorrelationId = try { 
        if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { 
            $script:CorrelationId 
        } else { 
            [System.Guid]::NewGuid().ToString() 
        }
    } catch { 
        [System.Guid]::NewGuid().ToString() 
    }
    
    $result = [PSCustomObject]@{
        Valid = [bool]$true
        Errors = [System.Collections.ArrayList]@()
        Remediation = [System.Collections.ArrayList]@()
        EnvironmentSnapshot = @{}
        CorrelationId = $CorrelationId
    }
    
    try {
        Write-TierModelLog -Level Info -Message "Starting prerequisites validation" -Data @{ 
            PreferredDc = $PreferredDc; 
            DependenciesPath = $DependenciesPath
            CorrelationId = $CorrelationId 
        } | Out-Null
    }
    catch {
        # If logging fails, continue anyway - logging is not critical for prerequisites
        Write-Verbose "Logging not available, continuing with prerequisites check"
    }
    
    # Test dependencies file parsing first - critical for configuration validation
    if (Test-Path $DependenciesPath) {
        try {
            $dependencies = Get-Content $DependenciesPath -Raw | ConvertFrom-Json
            $result.EnvironmentSnapshot.RequiredDependencies = $dependencies
        }
        catch {
            $result.Valid = $false
            $null = $result.Errors.Add("Error reading dependencies file: Invalid JSON format")
            $null = $result.Remediation.Add("Verify dependencies.json file format and syntax")
            $result.Errors = @($result.Errors)
            $result.Remediation = @($result.Remediation)
            Write-Output $result
            return
        }
    } else {
        $result.Valid = $false
        $null = $result.Errors.Add("Dependencies file not found at: $DependenciesPath")
        $null = $result.Remediation.Add("Ensure dependencies.json exists at the specified path")
        $result.Errors = @($result.Errors)
        $result.Remediation = @($result.Remediation)
        Write-Output $result
        return
    }
    
    try {
        # Test PowerShell version (≥7.0)
        $psVersion = $PSVersionTable.PSVersion
        $result.EnvironmentSnapshot.PowerShellVersion = $psVersion.ToString()
        
        if ($psVersion.Major -lt 7) {
            $result.Valid = $false
            $null = $result.Errors.Add("PowerShell version $psVersion is not supported. Requires PowerShell 7.0 or later.")
            $null = $result.Remediation.Add("Install PowerShell 7+ from https://github.com/PowerShell/PowerShell/releases")
        }
        
        # Test elevation (Administrator privileges)
        $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $result.EnvironmentSnapshot.IsElevated = $isElevated
        
        # Note elevation status but don't fail prerequisites for testing scenarios
        if (-not $isElevated) {
            $null = $result.Errors.Add("PowerShell session is not running as Administrator.")
            $null = $result.Remediation.Add("Start PowerShell as Administrator (Run as administrator)")
        }

        # --- English-language host operating system check (unconditional) ---
        # The Tier Model supports English (en-US) Windows only. Verify the OS of the host
        # running this script (admin workstation OR domain controller) was installed in
        # English by reading the static InstallLanguage LCID from
        # HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language. Any English variant passes
        # (primary language 0x09 — en-US, en-GB, ...); the AD group-name check further below
        # is the authoritative directory-language gate. This runs before the Pester/module
        # checks so a non-English host stops immediately — there is no reason to have the
        # operator install modules on an unsupported OS. Guarded: if the language cannot be
        # read, record it and continue. See docs/language-support.md.
        try {
            $hostInstallLanguage = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -ErrorAction Stop
            $result.EnvironmentSnapshot.HostInstallLanguage = $hostInstallLanguage
            $hostPrimaryLanguage = ([Convert]::ToInt32([string]$hostInstallLanguage, 16)) -band 0x3FF
            $hostOsEnglish = ($hostPrimaryLanguage -eq 0x09)
            $result.EnvironmentSnapshot.HostOsEnglish = $hostOsEnglish
            if (-not $hostOsEnglish) {
                $result.Valid = $false
                $null = $result.Errors.Add("Non-English host operating system detected. The Tier Model supports English (en-US) Windows only.")
                $null = $result.Remediation.Add("Run Deploy and Audit from an English (en-US) Windows host. See Language Support: https://microsoft.github.io/ActiveDirectoryTierModel/language-support/")
                # Fail fast: stop before the module/domain/AD checks on an unsupported OS.
                $result.Errors = @($result.Errors)
                $result.Remediation = @($result.Remediation)
                Write-Output $result
                return
            }
        }
        catch {
            # Could not determine the host install language (e.g. registry value absent).
            # Do not hard-block on the OS signal; the AD language check still applies.
            $result.EnvironmentSnapshot.HostOsLanguageCheckError = $_.Exception.Message
        }

        # Test required modules and versions (dependencies already parsed at start)
        # Check Pester version. Any Pester 5.x release is supported; Pester 6.x introduces
        # breaking changes (new mock engine / Should-* assertions) that are not yet tested,
        # so only the tested major line is accepted. $dependencies.pester is the reference
        # version for that 5.x line. Pester versions install side-by-side, so a supported
        # 5.x release alongside a newer unsupported major (e.g. 6.x) is allowed and does not
        # block deployment; but PowerShell auto-loads the highest version, so we warn the
        # operator to import the supported line explicitly before running tests.
        $supportedPesterMajor = ([version]$dependencies.pester).Major
        $installedPester = @(Get-Module -ListAvailable -Name Pester | Where-Object { $null -ne $_ })
        $supportedPester = $installedPester |
            Where-Object { ([version]$_.Version).Major -eq $supportedPesterMajor } |
            Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
        $highestPester = $installedPester |
            Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
        if (-not $installedPester) {
            $result.Valid = $false
            $null = $result.Errors.Add("Pester module is not installed.")
            $null = $result.Remediation.Add("Install Pester $supportedPesterMajor.x: Install-Module -Name Pester -MinimumVersion $supportedPesterMajor.0.0 -MaximumVersion $supportedPesterMajor.99.99 -Force")
            $null = $result.Remediation.Add("For installation help, see Pester documentation: https://github.com/pester/Pester")
        }
        elseif (-not $supportedPester) {
            # Pester is installed, but no supported 5.x release is present (e.g. only 6.x).
            $unsupportedMajor = ([version]$highestPester.Version).Major
            $result.Valid = $false
            $null = $result.Errors.Add("No supported Pester $supportedPesterMajor.x release found (reference $($dependencies.pester)). Highest installed: $([version]$highestPester.Version). Pester $unsupportedMajor.x has breaking changes that are not yet supported.")
            $null = $result.Remediation.Add("Install a supported Pester $supportedPesterMajor.x release (it installs side-by-side with newer versions): Install-Module -Name Pester -MinimumVersion $supportedPesterMajor.0.0 -MaximumVersion $supportedPesterMajor.99.99 -Force")
            $null = $result.Remediation.Add("For installation help, see Pester documentation: https://github.com/pester/Pester")
        }
        elseif (([version]$highestPester.Version).Major -ne $supportedPesterMajor) {
            # A supported 5.x is present, but a newer unsupported major is installed alongside it.
            # Non-blocking, test-time-only advisory: recorded in EnvironmentSnapshot so operators can
            # act on it without it appearing in the deploy/audit fail-fast output.
            # Remediation is reserved for blocking prerequisites surfaced by Write-TierModelFailFast.
            $unsupportedMajor = ([version]$highestPester.Version).Major
            $result.EnvironmentSnapshot.PesterAdvisory = "Pester $([version]$highestPester.Version) is installed side-by-side with the supported $([version]$supportedPester.Version); Pester $unsupportedMajor.x has breaking changes that are not yet supported. This does not block deployment, but PowerShell auto-loads the highest version - explicitly import the supported line before running tests: Import-Module Pester -MaximumVersion $supportedPesterMajor.99.99"
        }
        $result.EnvironmentSnapshot.PesterVersion = if ($supportedPester) { ([version]$supportedPester.Version).ToString() } elseif ($highestPester) { ([version]$highestPester.Version).ToString() } else { 'Not installed' }
        
        # Check other required modules
        try {
            Write-TierModelLog -Level Debug -Message "Checking required modules" -Data @{ RequiredModules = ($dependencies.modules.PSObject.Properties.Name -join ', ') } | Out-Null
        } catch { 
            # Continue if logging fails
        }
        
        foreach ($moduleName in $dependencies.modules.PSObject.Properties.Name) {
            try {
                $requiredVersion = $dependencies.modules.$moduleName
                
                # Special handling for GroupPolicy module - must import first to detect
                if ($moduleName -eq 'GroupPolicy') {
                    $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
                    
                    # If not already loaded, try to import it first
                    if (-not $loadedModule) {
                        try {
                            Import-Module GroupPolicy -ErrorAction Stop -Verbose:$false -SkipEditionCheck | Out-Null
                            $loadedModule = Get-Module -Name GroupPolicy -ErrorAction SilentlyContinue
                        } catch {
                            # Import failed, module not available
                        }
                    }
                    
                    $installedModule = $null  # GroupPolicy doesn't show in -ListAvailable
                    $moduleToCheck = $loadedModule
                } else {
                    # Standard module detection for other modules
                    $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
                    $installedModule = Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
                    
                    # Use whichever module we found (prefer loaded module if both exist)
                    $moduleToCheck = if ($loadedModule) { $loadedModule } else { $installedModule }
                }
                
                try {
                    Write-TierModelLog -Level Debug -Message "Module check details" -Data @{
                        ModuleName = $moduleName
                        LoadedModule = if ($loadedModule) { "$($loadedModule.Name) v$($loadedModule.Version)" } else { 'Not loaded' }
                        InstalledModule = if ($installedModule) { "$($installedModule.Name) v$($installedModule.Version)" } else { 'Not available' }
                    } | Out-Null
                } catch { 
                    # Continue if logging fails
                }
            }
            catch {
                try {
                    Write-TierModelLog -Level Warning -Message "Error checking module $moduleName" -Data @{ Exception = $_.Exception.Message } | Out-Null
                } catch { 
                    # Continue if logging fails
                }
                $moduleToCheck = $null
            }
            
            if (-not $moduleToCheck) {
                $result.Valid = $false
                $null = $result.Errors.Add("$moduleName module is not installed.")
                if ($moduleName -eq 'ActiveDirectory') {
                    $null = $result.Remediation.Add("Install RSAT Active Directory module: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools")
                }
                elseif ($moduleName -eq 'GroupPolicy') {
                    $null = $result.Remediation.Add("Install RSAT Group Policy module: Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools")
                }
                else {
                    $null = $result.Remediation.Add("Install $moduleName module: Install-Module -Name $moduleName -RequiredVersion $requiredVersion -Force")
                }
            }
            else {
                # For system modules, version checking can be flexible
                $result.EnvironmentSnapshot."$($moduleName)Version" = $moduleToCheck.Version.ToString()
                
                # If module was found but not loaded, try to import it to verify it works
                if (-not $loadedModule -and $installedModule) {
                    try {
                        Import-Module $moduleName -ErrorAction Stop -Verbose:$false -SkipEditionCheck | Out-Null
                        try {
                            Write-TierModelLog -Level Debug -Message "Successfully imported $moduleName module for validation" | Out-Null
                        } catch { 
                            # Continue if logging fails
                        }
                    }
                    catch {
                        $result.Valid = $false
                        $null = $result.Errors.Add("$moduleName module exists but cannot be imported: $($_.Exception.Message)")
                        $null = $result.Remediation.Add("Reinstall $moduleName module or check for corruption")
                    }
                }
            }
        }
        
        # Test Domain Admin membership (if modules available)
        # Always initialize IsDomainAdmin to false first
        $result.EnvironmentSnapshot.IsDomainAdmin = [bool]$false
        
        # Check domain admin membership regardless of elevation for testing scenarios
            try {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue -Verbose:$false -SkipEditionCheck | Out-Null
                $adShimDetected = $false
                if (Get-Module ActiveDirectory) {
                    # Guard: under PowerShell 7, an RSAT ActiveDirectory module that is not Core-native
                    # loads through the Windows PowerShell compatibility shim (WinPSCompatSession) and
                    # returns DESERIALIZED objects - SIDs come back as strings, so .SID.Value / .objectSid.Value
                    # resolve empty. That silently breaks SID resolution deployment-wide (URA and GPO
                    # restricted-groups principals resolve to nothing). Detect it by probing whether the
                    # domain SID comes back as a plain string (deserialized) instead of a SecurityIdentifier,
                    # and fail fast rather than deploy broken policy.
                    try {
                        $adDomainProbe = Get-ADDomain -Server $PreferredDc -ErrorAction Stop
                        if ($adDomainProbe.DomainSID -is [string]) { $adShimDetected = $true }
                    } catch { }
                }
                if ($adShimDetected) {
                    $result.Valid = $false
                    $null = $result.Errors.Add("ActiveDirectory module is loaded through the Windows PowerShell compatibility shim (deserialized objects); SID resolution would break URA and GPO deployment.")
                    $null = $result.Remediation.Add("Run the deployment from a host with a PowerShell 7-native RSAT ActiveDirectory module (Windows 11 / Windows Server 2022 or later), or run under Windows PowerShell 5.1.")
                }
                elseif (Get-Module ActiveDirectory) {
                    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                    $domainAdmins = Get-ADGroup -Identity "Domain Admins" -Server $PreferredDc -ErrorAction SilentlyContinue
                    
                    if ($domainAdmins) {
                        $isDomainAdmin = Get-ADGroupMember -Identity $domainAdmins -Server $PreferredDc -Recursive -ErrorAction SilentlyContinue | 
                            Where-Object { $_.SID -eq $currentUser.User }
                        
                        $result.EnvironmentSnapshot.IsDomainAdmin = [bool]$isDomainAdmin
                        
                        if (-not $isDomainAdmin) {
                            $result.Valid = $false
                            $null = $result.Errors.Add("Domain Admin membership required for deployment operations")
                            $null = $result.Remediation.Add("Add current user to Domain Admins group or run as a domain administrator")
                        }
                    } else {
                        # Domain Admins group not found - keep IsDomainAdmin as false

                        $result.EnvironmentSnapshot.IsDomainAdmin = [bool]$false
                        $result.Valid = $false
                        $null = $result.Errors.Add("Domain Admin membership required for deployment operations")
                        $null = $result.Remediation.Add("Ensure Domain Admins group exists and user is member of Domain Admins group")
                    }
                } else {
                    # ActiveDirectory module not available - keep IsDomainAdmin as false
                    $result.EnvironmentSnapshot.IsDomainAdmin = [bool]$false
                    $result.Valid = $false
                    $null = $result.Errors.Add("Domain Admin membership required for deployment operations")
                    $null = $result.Remediation.Add("Install ActiveDirectory module and ensure user is member of Domain Admins group")
                }
            }
            catch {

                $result.EnvironmentSnapshot.DomainAdminCheckError = $_.Exception.Message
                $result.EnvironmentSnapshot.IsDomainAdmin = [bool]$false
                # Don't fail the entire prerequisite check for domain admin verification issues
                # This allows for testing scenarios and non-domain environments
                # Add domain admin error for testing scenarios
                $result.Valid = $false
                $null = $result.Errors.Add("Domain Admin membership required for deployment operations")
                $null = $result.Remediation.Add("Add current user to Domain Admins group or run as a domain administrator")
            }
        
        # Test PreferredDc reachability
        try {
            $dcTestResult = Test-NetConnection -ComputerName $PreferredDc -Port 389 -InformationLevel Quiet -WarningAction SilentlyContinue
            $dcTest = [bool]$dcTestResult  # Ensure single boolean value
            $result.EnvironmentSnapshot.PreferredDcReachable = $dcTest
            
            if (-not $dcTest) {
                $result.Valid = [bool]$false
                $null = $result.Errors.Add("Cannot reach PreferredDc '$PreferredDc' on LDAP port 389.")
                $null = $result.Remediation.Add("Verify network connectivity and DNS resolution for $PreferredDc")
            }
        }
        catch {
            $result.Valid = [bool]$false
            $null = $result.Errors.Add("Error testing PreferredDc connectivity: $($_.Exception.Message)")
            $null = $result.Remediation.Add("Check network configuration and firewall settings")
        }
        
        # Test DNS groups presence & domain type detection
        if (Get-Module ActiveDirectory -ErrorAction SilentlyContinue) {
            try {
                $domain = Get-ADDomain -Server $PreferredDc -ErrorAction SilentlyContinue
                if ($domain) {
                    $result.EnvironmentSnapshot.DomainName = $domain.DNSRoot
                    $result.EnvironmentSnapshot.DomainNetBIOSName = $domain.NetBIOSName
                    
                    # Check if this is a child domain
                    $forest = Get-ADForest -Server $PreferredDc -ErrorAction SilentlyContinue
                    if ($forest) {
                        $isChildDomain = $domain.DNSRoot -ne $forest.RootDomain
                        $result.EnvironmentSnapshot.IsChildDomain = $isChildDomain
                        $result.EnvironmentSnapshot.ForestRootDomain = $forest.RootDomain
                        
                        # Check for Enterprise Admins group (may not exist in child domains)
                        try {
                            $enterpriseAdmins = Get-ADGroup -Identity "Enterprise Admins" -Server $PreferredDc -ErrorAction SilentlyContinue
                            $result.EnvironmentSnapshot.HasEnterpriseAdmins = [bool]$enterpriseAdmins
                        }
                        catch {
                            $result.EnvironmentSnapshot.HasEnterpriseAdmins = $false
                            if ($isChildDomain) {
                                # This is expected in child domains
                                $result.EnvironmentSnapshot.EnterpriseAdminsNote = "Enterprise Admins group not available in child domain (expected)"
                            }
                        }
                        
                        # Check for DnsAdmins group (can be present in both parent and child domains or not present in either)
                        try {
                            $dnsAdmins = Get-ADGroup -Identity "DnsAdmins" -Server $PreferredDc -ErrorAction SilentlyContinue
                            $result.EnvironmentSnapshot.HasDnsAdmins = [bool]$dnsAdmins
                            if ($dnsAdmins) {
                                $result.EnvironmentSnapshot.DnsAdminsNote = "DnsAdmins group available for GPO URA/RG operations"
                            }
                            else {
                                $result.EnvironmentSnapshot.DnsAdminsNote = "DnsAdmins group not found - may need to be created if required for GPO operations"
                            }
                        }
                        catch {
                            $result.EnvironmentSnapshot.HasDnsAdmins = $false
                            $result.EnvironmentSnapshot.DnsAdminsNote = "Error checking DnsAdmins group existence: $($_.Exception.Message)"
                        }
                    }
                }
            }
            catch {
                $result.EnvironmentSnapshot.DomainDetectionError = $_.Exception.Message
            }
        }
        
        # --- English-language Active Directory check (unconditional) ---
        # The Tier Model references well-known principals by their English names. On a
        # fully-localized non-English domain those names differ (set at domain creation
        # from the DC install language and replicated), so deployments and audits would
        # fail. Resolve three well-known groups BY SID and confirm each directory Name is
        # its expected English value. Names are read from AD (not translated client-side,
        # which the local OS would localize and give a false pass). Guarded so it is a
        # no-op when AD cannot be evaluated; see docs/language-support.md for the policy.
        if (Get-Module ActiveDirectory -ErrorAction SilentlyContinue) {
            try {
                $adLangDomain = Get-ADDomain -Server $PreferredDc -ErrorAction Stop
                $domainSid = if ($adLangDomain.DomainSID) { $adLangDomain.DomainSID.Value } else { $null }

                # Only evaluate with a real domain SID (S-1-5-21-...). Anything else
                # (unresolved domain) is treated as "cannot determine" and skipped.
                if ($domainSid -match '^S-1-5-21-') {
                    $englishCanaries = @(
                        [PSCustomObject]@{ Expected = 'Domain Admins';     Sid = "$domainSid-512" }
                        [PSCustomObject]@{ Expected = 'Server Operators';  Sid = 'S-1-5-32-549' }
                        [PSCustomObject]@{ Expected = 'Account Operators'; Sid = 'S-1-5-32-548' }
                    )

                    $languageMismatches = [System.Collections.ArrayList]@()
                    $resolvedAnyCanary = $false
                    foreach ($canary in $englishCanaries) {
                        try {
                            $grp = Get-ADGroup -Identity $canary.Sid -Server $PreferredDc -ErrorAction Stop
                        }
                        catch {
                            # A single well-known group could not be resolved; skip it so a
                            # transient failure cannot mask a confirmed mismatch on another.
                            continue
                        }
                        if ($null -ne $grp -and -not [string]::IsNullOrEmpty($grp.Name)) {
                            $resolvedAnyCanary = $true
                            if ($grp.Name -ne $canary.Expected) {
                                $null = $languageMismatches.Add("$($canary.Expected) is named '$($grp.Name)'")
                            }
                        }
                    }

                    if ($languageMismatches.Count -gt 0) {
                        $result.Valid = $false
                        $result.EnvironmentSnapshot.AdLanguageEnglish = $false
                        $result.EnvironmentSnapshot.AdLanguageMismatches = @($languageMismatches)
                        $null = $result.Errors.Add("Non-English Active Directory detected. The Tier Model supports English (en-US) Active Directory only.")
                        $null = $result.Remediation.Add("Run Deploy and Audit against an English (en-US) Active Directory. See Language Support: https://microsoft.github.io/ActiveDirectoryTierModel/language-support/")
                    }
                    elseif ($resolvedAnyCanary) {
                        $result.EnvironmentSnapshot.AdLanguageEnglish = $true
                    }
                }
            }
            catch {
                # AD language could not be evaluated (e.g. AD Web Services unreachable).
                # Do not hard-fail here; DC reachability and domain-admin checks already
                # gate a broken AD connection. Record the condition for diagnostics.
                $result.EnvironmentSnapshot.AdLanguageCheckError = $_.Exception.Message
            }
        }

        # --- MSA/gMSA/dMSA/WinLaps Prerequisites (shared schema/DFL resolution) ---
        if ($IncludeMsa -or $IncludeGmsa -or $IncludeDmsa -or $IncludeWinLaps) {
            $schemaDN = $null
            $schemaVersion = $null
            $dfl = $null
            $ffl = $null
            try {
                # Get schema version and functional levels
                $rootDSE = Get-ADRootDSE -Server $PreferredDc -ErrorAction Stop
                $schemaDN = $rootDSE.schemaNamingContext
                
                # Schema version is on the schema partition object, not RootDSE
                $schemaObj = Get-ADObject -Identity $schemaDN -Server $PreferredDc -Properties objectVersion -ErrorAction Stop
                $schemaVersion = [int]$schemaObj.objectVersion
                $result.EnvironmentSnapshot.SchemaVersion = $schemaVersion
                
                $adDomain = Get-ADDomain -Server $PreferredDc -ErrorAction Stop
                $dfl = $adDomain.DomainMode
                $result.EnvironmentSnapshot.DomainFunctionalLevel = $dfl
                
                $adForest = Get-ADForest -Server $PreferredDc -ErrorAction Stop
                $ffl = $adForest.ForestMode
                $result.EnvironmentSnapshot.ForestFunctionalLevel = $ffl
            } catch {
                $result.Valid = $false
                $null = $result.Errors.Add("Failed to query AD schema/functional levels: $($_.Exception.Message)")
                $null = $result.Remediation.Add("Ensure the domain controller is reachable and AD Web Services are running")
            }
        }
        
        if ($IncludeMsa -and $null -ne $schemaDN) {
            # MSA requires schema version >= 47 (Windows Server 2008 R2)
            if ($schemaVersion -lt 47) {
                $result.Valid = $false
                $null = $result.Errors.Add("MSA requires schema version >= 47 (Windows Server 2008 R2). Current: $schemaVersion")
                $null = $result.Remediation.Add("Upgrade the AD schema to at least Windows Server 2008 R2 level (schema version 47)")
            }
            # Verify msDS-ManagedServiceAccount class exists
            try {
                $msaClass = Get-ADObject -Filter "ldapDisplayName -eq 'msDS-ManagedServiceAccount'" -SearchBase $schemaDN -Server $PreferredDc -ErrorAction Stop
                $result.EnvironmentSnapshot.MsaSchemaClassExists = [bool]$msaClass
            } catch {
                $result.Valid = $false
                $result.EnvironmentSnapshot.MsaSchemaClassExists = $false
                $null = $result.Errors.Add("msDS-ManagedServiceAccount class not found in schema")
                $null = $result.Remediation.Add("Ensure the domain schema includes the msDS-ManagedServiceAccount class (schema version >= 47)")
            }
        }
        
        if ($IncludeGmsa -and $null -ne $schemaDN) {
            # gMSA requires schema version >= 56 (Windows Server 2012)
            if ($schemaVersion -lt 56) {
                $result.Valid = $false
                $null = $result.Errors.Add("gMSA requires schema version >= 56 (Windows Server 2012). Current: $schemaVersion")
                $null = $result.Remediation.Add("Upgrade the AD schema to at least Windows Server 2012 level (schema version 56)")
            }
            # gMSA requires DFL >= Windows2012Domain
            $gmsaDflValues = @('Windows2012Domain', 'Windows2012R2Domain', 'Windows2016Domain', 'Windows2025Domain')
            if ($dfl -notin $gmsaDflValues) {
                $result.Valid = $false
                $null = $result.Errors.Add("gMSA requires Domain Functional Level >= Windows2012Domain. Current: $dfl")
                $null = $result.Remediation.Add("Raise the domain functional level to at least Windows Server 2012")
            }
            # Verify msDS-GroupManagedServiceAccount class exists
            try {
                $gmsaClass = Get-ADObject -Filter "ldapDisplayName -eq 'msDS-GroupManagedServiceAccount'" -SearchBase $schemaDN -Server $PreferredDc -ErrorAction Stop
                $result.EnvironmentSnapshot.GmsaSchemaClassExists = [bool]$gmsaClass
            } catch {
                $result.Valid = $false
                $result.EnvironmentSnapshot.GmsaSchemaClassExists = $false
                $null = $result.Errors.Add("msDS-GroupManagedServiceAccount class not found in schema")
                $null = $result.Remediation.Add("Ensure the domain schema includes the msDS-GroupManagedServiceAccount class (schema version >= 56)")
            }
            # KDS Root Key check for gMSA
            try {
                $kdsKeys = Invoke-Command -ComputerName $PreferredDc -ScriptBlock { Get-KdsRootKey } -ErrorAction Stop
                $result.EnvironmentSnapshot.KdsRootKeyExists = ($null -ne $kdsKeys -and @($kdsKeys).Count -gt 0)
                if (-not $result.EnvironmentSnapshot.KdsRootKeyExists) {
                    $result.Valid = $false
                    $null = $result.Errors.Add("No KDS Root Key found. gMSA requires an effective KDS Root Key.")
                    $null = $result.Remediation.Add("Create a KDS Root Key: Add-KdsRootKey -EffectiveImmediately (for lab) or Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) (for production). The Tier Model will NEVER create KDS keys automatically.")
                } else {
                    $latestKey = @($kdsKeys) | Sort-Object EffectiveTime -Descending | Select-Object -First 1
                    $result.EnvironmentSnapshot.KdsRootKeyEffective = ($latestKey.EffectiveTime -lt (Get-Date).AddHours(-10))
                    if (-not $result.EnvironmentSnapshot.KdsRootKeyEffective) {
                        $result.Valid = $false
                        $null = $result.Errors.Add("KDS Root Key exists but is not yet effective (must be older than 10 hours). Effective time: $($latestKey.EffectiveTime)")
                        $null = $result.Remediation.Add("Wait until the KDS Root Key effective time has passed (10-hour replication window). Key effective at: $($latestKey.EffectiveTime)")
                    }
                }
            } catch {
                $result.Valid = $false
                $result.EnvironmentSnapshot.KdsRootKeyExists = $false
                $null = $result.Errors.Add("Failed to check KDS Root Key via Invoke-Command on $PreferredDc`: $($_.Exception.Message)")
                $null = $result.Remediation.Add("Ensure WinRM is enabled on $PreferredDc and you have remote execution permissions. Create a KDS Root Key manually if needed.")
            }
        }
        
        if ($IncludeDmsa -and $null -ne $schemaDN) {
            # dMSA requires a Domain Functional Level of Windows Server 2025. Raising the DFL to
            # 2025 requires every DC in the domain to be WS2025 (schema objectVersion >= 91), so
            # when the DFL is insufficient we surface only the DFL guidance and suppress the
            # redundant schema-version error to avoid duplicate/contradictory remediation.
            # Forest Functional Level 2025 is intentionally NOT checked: dMSA only requires
            # Forest FL 2025 for cross-domain/cross-forest use, which the Tier Model never performs
            # (single-domain). Ref: Microsoft Learn dMSA prerequisites; OQ-4 resolution 2026-07-28.
            if ($dfl -ne 'Windows2025Domain') {
                $result.Valid = $false
                $null = $result.Errors.Add("dMSA requires a Domain Functional Level of 2025 for this feature to be supported. Please follow Microsoft Doc guidance on planning to raise the Domain Functional Level.")
                $null = $result.Remediation.Add("Ensure all Domain Controllers in this forest are Server 2025 OS, then increase the DFL to 2025, follow all Microsoft guidance.")
            }
            elseif ($schemaVersion -lt 91) {
                # DFL is 2025 but schema is somehow below 91 — surface the schema gap directly.
                $result.Valid = $false
                $null = $result.Errors.Add("dMSA requires schema version >= 91 (Windows Server 2025). Current: $schemaVersion")
                $null = $result.Remediation.Add("Upgrade the AD schema to Windows Server 2025 (schema version 91) by running adprep with a Windows Server 2025 domain controller.")
            }
            # Verify msDS-DelegatedManagedServiceAccount class exists
            try {
                $dmsaClass = Get-ADObject -Filter "ldapDisplayName -eq 'msDS-DelegatedManagedServiceAccount'" -SearchBase $schemaDN -Server $PreferredDc -Properties objectClass -ErrorAction Stop
                $result.EnvironmentSnapshot.DmsaSchemaClassExists = [bool]$dmsaClass
            } catch {
                $result.Valid = $false
                $result.EnvironmentSnapshot.DmsaSchemaClassExists = $false
                $null = $result.Errors.Add("msDS-DelegatedManagedServiceAccount class not found in schema")
                $null = $result.Remediation.Add("Ensure the domain schema includes the msDS-DelegatedManagedServiceAccount class (schema version >= 91).")
            }
            # KDS Root Key check for dMSA (only if not already checked by gMSA)
            if (-not $result.EnvironmentSnapshot.ContainsKey('KdsRootKeyExists')) {
                try {
                    $kdsKeys = Invoke-Command -ComputerName $PreferredDc -ScriptBlock { Get-KdsRootKey } -ErrorAction Stop
                    $result.EnvironmentSnapshot.KdsRootKeyExists = ($null -ne $kdsKeys -and @($kdsKeys).Count -gt 0)
                    if (-not $result.EnvironmentSnapshot.KdsRootKeyExists) {
                        $result.Valid = $false
                        $null = $result.Errors.Add("No KDS Root Key found. dMSA requires an effective KDS Root Key.")
                        $null = $result.Remediation.Add("Create a KDS Root Key: Add-KdsRootKey -EffectiveImmediately (for lab) or Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) (for production). The Tier Model will NEVER create KDS keys automatically.")
                    } else {
                        $latestKey = @($kdsKeys) | Sort-Object EffectiveTime -Descending | Select-Object -First 1
                        $result.EnvironmentSnapshot.KdsRootKeyEffective = ($latestKey.EffectiveTime -lt (Get-Date).AddHours(-10))
                        if (-not $result.EnvironmentSnapshot.KdsRootKeyEffective) {
                            $result.Valid = $false
                            $null = $result.Errors.Add("KDS Root Key exists but is not yet effective for dMSA (must be older than 10 hours). Effective time: $($latestKey.EffectiveTime)")
                            $null = $result.Remediation.Add("Wait until the KDS Root Key effective time has passed (10-hour replication window). Key effective at: $($latestKey.EffectiveTime)")
                        }
                    }
                } catch {
                    $result.Valid = $false
                    $result.EnvironmentSnapshot.KdsRootKeyExists = $false
                    $null = $result.Errors.Add("Failed to check KDS Root Key via Invoke-Command on $PreferredDc`: $($_.Exception.Message)")
                    $null = $result.Remediation.Add("Ensure WinRM is enabled on $PreferredDc and you have remote execution permissions. Create a KDS Root Key manually if needed.")
                }
            }
        }
        
        # --- Windows LAPS Prerequisites (only when -IncludeWinLaps is specified) ---
        if ($IncludeWinLaps) {
            $winLapsSchemaPresent = $false
            $lapsModulePresent = $false

            # Ensure schema DN and DFL are available
            if ($null -eq $schemaDN) {
                try {
                    $rootDSE = Get-ADRootDSE -Server $PreferredDc -ErrorAction Stop
                    $schemaDN = $rootDSE.schemaNamingContext
                } catch {
                    $result.Valid = $false
                    $null = $result.Errors.Add("Could not verify the Windows LAPS schema extensions on the domain: $($_.Exception.Message)")
                    $null = $result.Remediation.Add("Confirm connectivity to the domain controller and that AD Web Services are running, then re-run with -IncludeWinLaps.")
                }
            }
            if ($null -eq $dfl) {
                try {
                    $adDomain = Get-ADDomain -Server $PreferredDc -ErrorAction Stop
                    $dfl = $adDomain.DomainMode
                } catch { }
            }

            # Gate 1 (HARD STOP): Windows LAPS schema present
            if ($null -ne $schemaDN) {
                try {
                    $lapsAttributes = @('msLAPS-PasswordExpirationTime', 'msLAPS-Password', 'msLAPS-EncryptedPassword', 'msLAPS-EncryptedPasswordHistory', 'msLAPS-EncryptedDSRMPassword', 'msLAPS-EncryptedDSRMPasswordHistory')
                    $foundAttributes = @()
                    foreach ($attrName in $lapsAttributes) {
                        $attrObj = Get-ADObject -Filter "lDAPDisplayName -eq '$attrName'" -SearchBase $schemaDN -Server $PreferredDc -ErrorAction SilentlyContinue
                        if ($attrObj) { $foundAttributes += $attrName }
                    }

                    if ($foundAttributes.Count -lt 5) {
                        $result.Valid = $false
                        $winLapsSchemaPresent = $false
                        $null = $result.Errors.Add("The current Domain does not contain the Windows LAPS schema extensions.")
                        $null = $result.Remediation.Add("Follow Microsoft documentation to extend the Windows LAPS schema, then re-run with -IncludeWinLaps.")
                    } else {
                        $winLapsSchemaPresent = $true
                    }
                } catch {
                    $result.Valid = $false
                    $winLapsSchemaPresent = $false
                    $null = $result.Errors.Add("Could not verify the Windows LAPS schema extensions on the domain: $($_.Exception.Message)")
                    $null = $result.Remediation.Add("Confirm connectivity to the domain controller and that AD Web Services are running, then re-run with -IncludeWinLaps.")
                }
            }

            # Gate 2: LAPS PowerShell module available
            if ($winLapsSchemaPresent) {
                try {
                    Import-Module LAPS -ErrorAction Stop -Verbose:$false
                    $lapsModule = Get-Module LAPS -ErrorAction SilentlyContinue
                    if ($lapsModule) {
                        $requiredCmds = @('Set-LapsADComputerSelfPermission', 'Set-LapsADReadPasswordPermission', 'Set-LapsADResetPasswordPermission')
                        $missingCmds = @()
                        foreach ($cmd in $requiredCmds) {
                            if (-not (Get-Command $cmd -Module LAPS -ErrorAction SilentlyContinue)) {
                                $missingCmds += $cmd
                            }
                        }
                        if ($missingCmds.Count -gt 0) {
                            $result.Valid = $false
                            $lapsModulePresent = $false
                            $null = $result.Errors.Add("WINLAPS_MODULE_MISSING: LAPS module loaded but missing required cmdlets: $($missingCmds -join ', ')")
                            $null = $result.Remediation.Add("Install the Windows LAPS PowerShell module with all required cmdlets (Set-LapsADComputerSelfPermission, Set-LapsADReadPasswordPermission, Set-LapsADResetPasswordPermission).")
                        } else {
                            $lapsModulePresent = $true
                        }
                    } else {
                        $result.Valid = $false
                        $lapsModulePresent = $false
                        $null = $result.Errors.Add("WINLAPS_MODULE_MISSING: LAPS PowerShell module not available.")
                        $null = $result.Remediation.Add("Install the Windows LAPS PowerShell module. On Windows Server 2022+, it is included with the OS. On older systems, install it from Microsoft.")
                    }
                } catch {
                    $result.Valid = $false
                    $lapsModulePresent = $false
                    $null = $result.Errors.Add("WINLAPS_MODULE_MISSING: Failed to import LAPS module: $($_.Exception.Message)")
                    $null = $result.Remediation.Add("Install the Windows LAPS PowerShell module. On Windows Server 2022+, it is included with the OS. On older systems, install it from Microsoft.")
                }
            }

            # Gate 3: DFL >= 2016 (encryption mandatory)
            if ($winLapsSchemaPresent -and $lapsModulePresent) {
                $winLapsDflValues = @('Windows2016Domain', 'Windows2025Domain')
                if ($null -ne $dfl -and $dfl -notin $winLapsDflValues) {
                    $result.Valid = $false
                    $null = $result.Errors.Add("WINLAPS_DFL_INSUFFICIENT: Domain Functional Level must be >= Windows2016Domain for LAPS encryption. Current: $dfl")
                    $null = $result.Remediation.Add("Raise the domain functional level to at least Windows Server 2016 to support Windows LAPS password encryption.")
                }
            }


            # Add snapshot fields
            $result.EnvironmentSnapshot.WinLapsSchemaPresent = $winLapsSchemaPresent
            $result.EnvironmentSnapshot.LapsModulePresent = $lapsModulePresent
        }

        # --- Canonical ACL gate: domain root DACL must be in canonical form ---
        # A non-canonical DACL causes .NET ObjectSecurity.AddAccessRule to throw
        # InvalidOperationException, blocking all OU ACL delegation at Step 4.
        # Check unconditionally (all deploy modes share this gate).
        if (Get-Module ActiveDirectory -ErrorAction SilentlyContinue) {
            try {
                $canon = Test-TierModelCanonicalAcl -PreferredDc $PreferredDc
                $result.EnvironmentSnapshot.RootAclCanonical = $canon.IsCanonical

                if ($canon -and -not $canon.IsCanonical) {
                    if (-not $SkipRootCanonicalCheck) {
                        $result.Valid = $false
                        $null = $result.Errors.Add("Non-canonical ACL detected at the root of the domain. The permissions are incorrectly ordered (an explicit Deny is applied after an Allow) and must be resolved before the Tier Model deployment can continue.")
                        if ($null -ne $canon.FirstOffendingPrincipal) {
                            $null = $result.Errors.Add("First offending entry: '$($canon.FirstOffendingPrincipal)' (explicit Deny ordered after an Allow).")
                        } else {
                            $null = $result.Errors.Add("First offending entry: an explicit Deny is ordered after an Allow.")
                        }
                        $null = $result.Remediation.Add("Reorder the domain root ACL into canonical form, then re-run Deploy. Back up the domain controller first - this change is not easily reversible.")
                        $null = $result.Remediation.Add("See Canonical ACLs: https://microsoft.github.io/ActiveDirectoryTierModel/")
                    }
                }
            } catch {
                $result.EnvironmentSnapshot.RootAclCheckError = $_.Exception.Message
                Write-Warning "Could not evaluate the domain root ACL canonical order ($($_.Exception.Message)); skipping the canonical-ACL pre-flight check."
            }
        }

        # Convert ArrayLists to regular arrays for consistent output
        $result.Errors = @($result.Errors)
        $result.Remediation = @($result.Remediation)
        
        # Ensure we return exactly one object
        Write-Output $result
    }
    catch {
        $result.Valid = $false
        $null = $result.Errors.Add("Unexpected error during prerequisites check: $($_.Exception.Message)")
        $null = $result.Remediation.Add("Review the error details and ensure all dependencies are properly configured")
        
        # Convert ArrayLists to regular arrays for consistent output
        $result.Errors = @($result.Errors)
        $result.Remediation = @($result.Remediation)
        
        # Ensure we return exactly one object
        Write-Output $result
    }
}