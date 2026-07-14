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
        [switch]$IncludeWinLaps
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
        
        # Test required modules and versions (dependencies already parsed at start)
        # Check Pester version
        $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $pesterModule) {
            $result.Valid = $false
            $null = $result.Errors.Add("Pester module is not installed.")
            $null = $result.Remediation.Add("Install Pester: Install-Module -Name Pester -RequiredVersion $($dependencies.pester) -Force")
            $null = $result.Remediation.Add("For installation help, see Pester documentation: https://github.com/pester/Pester")
        }
        elseif ($pesterModule.Version -ne [version]$dependencies.pester) {
            $result.Valid = $false
            $null = $result.Errors.Add("Pester version mismatch. Required: $($dependencies.pester), Found: $($pesterModule.Version)")
            $null = $result.Remediation.Add("Install correct Pester version: Install-Module -Name Pester -RequiredVersion $($dependencies.pester) -Force")
            $null = $result.Remediation.Add("For installation help, see Pester documentation: https://github.com/pester/Pester")
        }
        $result.EnvironmentSnapshot.PesterVersion = if ($pesterModule) { $pesterModule.Version.ToString() } else { 'Not installed' }
        
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
                        Import-Module $moduleName -ErrorAction Stop -Verbose:$false | Out-Null
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
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue -Verbose:$false | Out-Null
                if (Get-Module ActiveDirectory) {
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
            # dMSA requires schema version >= 91 (Windows Server 2025)
            if ($schemaVersion -lt 91) {
                $result.Valid = $false
                $null = $result.Errors.Add("dMSA requires schema version >= 91 (Windows Server 2025). Current: $schemaVersion")
            }
            # dMSA requires DFL = Windows2025Domain
            if ($dfl -ne 'Windows2025Domain') {
                $result.Valid = $false
                $null = $result.Errors.Add("dMSA requires Domain Functional Level = Windows2025Domain. Current: $dfl")
            }
            # Verify msDS-DelegatedManagedServiceAccount class exists
            try {
                $dmsaClass = Get-ADObject -Filter "ldapDisplayName -eq 'msDS-DelegatedManagedServiceAccount'" -SearchBase $schemaDN -Server $PreferredDc -Properties objectClass -ErrorAction Stop
                $result.EnvironmentSnapshot.DmsaSchemaClassExists = [bool]$dmsaClass
            } catch {
                $result.Valid = $false
                $result.EnvironmentSnapshot.DmsaSchemaClassExists = $false
                $null = $result.Errors.Add("msDS-DelegatedManagedServiceAccount class not found in schema")
            }
            # KDS Root Key check for dMSA (only if not already checked by gMSA)
            if (-not $result.EnvironmentSnapshot.ContainsKey('KdsRootKeyExists')) {
                try {
                    $kdsKeys = Invoke-Command -ComputerName $PreferredDc -ScriptBlock { Get-KdsRootKey } -ErrorAction Stop
                    $result.EnvironmentSnapshot.KdsRootKeyExists = ($null -ne $kdsKeys -and @($kdsKeys).Count -gt 0)
                    if (-not $result.EnvironmentSnapshot.KdsRootKeyExists) {
                        $result.Valid = $false
                        $null = $result.Errors.Add("No KDS Root Key found. dMSA requires an effective KDS Root Key.")
                    } else {
                        $latestKey = @($kdsKeys) | Sort-Object EffectiveTime -Descending | Select-Object -First 1
                        $result.EnvironmentSnapshot.KdsRootKeyEffective = ($latestKey.EffectiveTime -lt (Get-Date).AddHours(-10))
                        if (-not $result.EnvironmentSnapshot.KdsRootKeyEffective) {
                            $result.Valid = $false
                            $null = $result.Errors.Add("KDS Root Key exists but is not yet effective for dMSA (must be older than 10 hours). Effective time: $($latestKey.EffectiveTime)")
                        }
                    }
                } catch {
                    $result.Valid = $false
                    $result.EnvironmentSnapshot.KdsRootKeyExists = $false
                    $null = $result.Errors.Add("Failed to check KDS Root Key via Invoke-Command on $PreferredDc`: $($_.Exception.Message)")
                }
            }
        }
        
        # --- Windows LAPS Prerequisites (only when -IncludeWinLaps is specified) ---
        if ($IncludeWinLaps) {
            $winLapsSchemaPresent = $false
            $lapsModulePresent = $false
            $winLapsOUsExist = $true
            $winLapsGroupsExist = $true

            # Ensure schema DN and DFL are available
            if ($null -eq $schemaDN) {
                try {
                    $rootDSE = Get-ADRootDSE -Server $PreferredDc -ErrorAction Stop
                    $schemaDN = $rootDSE.schemaNamingContext
                } catch {
                    $result.Valid = $false
                    $null = $result.Errors.Add("WINLAPS_SCHEMA_MISSING: Failed to query AD schema: $($_.Exception.Message)")
                    $null = $result.Remediation.Add("The Windows LAPS schema is not present in this directory. The -IncludeWinLaps parameter requires the Windows LAPS schema to be extended first. Extend the schema using your organization's controlled schema-change process before running with -IncludeWinLaps. Alternatively, deploy the Tier Model now without -IncludeWinLaps and add Windows LAPS later (post-deployment) once the schema is extended. The Tier Model will NEVER extend the schema automatically.")
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
                        $null = $result.Errors.Add("WINLAPS_SCHEMA_MISSING: Windows LAPS schema attributes not found ($($foundAttributes.Count)/6 detected).")
                        $null = $result.Remediation.Add("The Windows LAPS schema is not present in this directory. The -IncludeWinLaps parameter requires the Windows LAPS schema to be extended first. Extend the schema using your organization's controlled schema-change process before running with -IncludeWinLaps. Alternatively, deploy the Tier Model now without -IncludeWinLaps and add Windows LAPS later (post-deployment) once the schema is extended. The Tier Model will NEVER extend the schema automatically.")
                    } else {
                        $winLapsSchemaPresent = $true
                    }
                } catch {
                    $result.Valid = $false
                    $winLapsSchemaPresent = $false
                    $null = $result.Errors.Add("WINLAPS_SCHEMA_MISSING: Failed to query LAPS schema attributes: $($_.Exception.Message)")
                    $null = $result.Remediation.Add("The Windows LAPS schema is not present in this directory. The -IncludeWinLaps parameter requires the Windows LAPS schema to be extended first. Extend the schema using your organization's controlled schema-change process before running with -IncludeWinLaps. Alternatively, deploy the Tier Model now without -IncludeWinLaps and add Windows LAPS later (post-deployment) once the schema is extended. The Tier Model will NEVER extend the schema automatically.")
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

            # Gate 4: Target OUs exist + DC exclusion check
            if ($winLapsSchemaPresent -and $lapsModulePresent) {
                try {
                    $winLapsConfig = Get-TierModelConfig
                    if ($winLapsConfig.winLapsDelegations) {
                        $domainDN = Resolve-TierModelDomainDN -DomainController $PreferredDc
                        foreach ($delegation in @($winLapsConfig.winLapsDelegations)) {
                            $resolvedOuDn = Resolve-TierModelPlaceholder -Path $delegation.ouDn -DomainDN $domainDN
                            # Check OU exists
                            try {
                                Get-ADOrganizationalUnit -Identity $resolvedOuDn -Server $PreferredDc -ErrorAction Stop | Out-Null
                            } catch {
                                $result.Valid = $false
                                $winLapsOUsExist = $false
                                $null = $result.Errors.Add("WINLAPS_OU_MISSING: Target OU not found: '$resolvedOuDn'. Deploy OUs first with -OuOnly or -FullDeployment.")
                                $null = $result.Remediation.Add("Deploy the Tier Model OUs first using -OuOnly or -FullDeployment before running with -IncludeWinLaps.")
                                continue
                            }
                            # DC exclusion: unless isDomainControllerOu is true, check for DC objects
                            $isDcOu = if ($delegation.PSObject.Properties['isDomainControllerOu']) { $delegation.isDomainControllerOu } else { $false }
                            if (-not $isDcOu) {
                                try {
                                    $dcObjects = Get-ADComputer -Filter { PrimaryGroupID -eq 516 } -SearchBase $resolvedOuDn -Server $PreferredDc -ErrorAction SilentlyContinue
                                    if ($dcObjects) {
                                        $result.Valid = $false
                                        $null = $result.Errors.Add("WINLAPS_DC_SCOPE_REJECTED: OU '$resolvedOuDn' contains Domain Controller objects. Set isDomainControllerOu=true in config to explicitly opt in, or remove DC objects from this OU.")
                                        $null = $result.Remediation.Add("Either set isDomainControllerOu=true for this entry in tiermodel-winlaps.json (explicit DC opt-in) or move Domain Controller objects out of this OU.")
                                    }
                                } catch { }
                            }
                        }
                    }
                } catch { }
            }

            # Gate 5: Required groups exist
            if ($winLapsSchemaPresent -and $lapsModulePresent) {
                try {
                    $winLapsConfig2 = Get-TierModelConfig
                    if ($winLapsConfig2.winLapsDelegations) {
                        $uniqueGroups = @($winLapsConfig2.winLapsDelegations | ForEach-Object { @($_.readGroup); @($_.resetGroup) } | Select-Object -Unique)
                        foreach ($groupName in $uniqueGroups) {
                            try {
                                $escapedName = $groupName -replace "'", "''"
                                $adGroup = Get-ADGroup -Filter "Name -eq '$escapedName'" -Server $PreferredDc -ErrorAction Stop
                                if (-not $adGroup) { throw "Group not found" }
                            } catch {
                                $result.Valid = $false
                                $winLapsGroupsExist = $false
                                $null = $result.Errors.Add("WINLAPS_GROUP_MISSING: Required group '$groupName' not found in AD. Deploy groups first.")
                                $null = $result.Remediation.Add("Deploy the Tier Model groups first using -GroupOnly or -FullDeployment before running with -IncludeWinLaps.")
                            }
                        }
                    }
                } catch { }
            }

            # Add snapshot fields
            $result.EnvironmentSnapshot.WinLapsSchemaPresent = $winLapsSchemaPresent
            $result.EnvironmentSnapshot.LapsModulePresent = $lapsModulePresent
            $result.EnvironmentSnapshot.WinLapsOUsExist = $winLapsOUsExist
            $result.EnvironmentSnapshot.WinLapsGroupsExist = $winLapsGroupsExist
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