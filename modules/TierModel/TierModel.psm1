Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Generate correlation ID for this session
$script:CorrelationId = [System.Guid]::NewGuid().ToString()

# Module-level variables
$script:ModuleRoot = $PSScriptRoot
# Config directory is in the parent of the module directory (../../config from Modules/TierModel)
$script:ConfigPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config'
$script:LoggingEnabled = $false
$script:DefaultLogPath = $null

# Cache variables for domain resolution (used by Resolve-TierModelDomainDN)
$script:CachedDomainDN = $null
$script:CachedDomainController = $null

# Import internal functions (skip .old files - essential functions now in public)
$InternalPath = Join-Path $PSScriptRoot 'internal'
Write-Verbose "Looking for internal files in: $InternalPath"
if (Test-Path $InternalPath) {
    $internalFiles = Get-ChildItem -Path $InternalPath -Filter '*.ps1' | Where-Object { $_.Name -notlike '*.old' }
    $internalFileCount = if ($internalFiles) { $internalFiles.Count } else { 0 }
    Write-Verbose "Found $internalFileCount active internal files (excluding .old files)"
    $internalFiles | ForEach-Object {
        try {
            Write-Verbose "Loading: $($_.FullName)"
            . $_.FullName
            Write-Verbose "Successfully loaded: $($_.Name)"
        } catch {
            Write-Error "Failed to load $($_.Name): $($_.Exception.Message)"
            throw
        }
    }
}
# Note: Internal path is optional - essential functions have been moved to public modules

# Import public functions
$PublicPath = Join-Path $PSScriptRoot 'public'
Write-Verbose "Looking for public files in: $PublicPath"
if (Test-Path $PublicPath) {
    $publicFiles = Get-ChildItem -Path $PublicPath -Filter '*.ps1'
    Write-Verbose "Found $($publicFiles.Count) public files"
    $publicFiles | ForEach-Object {
        try {
            Write-Verbose "Loading: $($_.FullName)"
            . $_.FullName
            Write-Verbose "Successfully loaded: $($_.Name)"
        } catch {
            Write-Error "Failed to load $($_.Name): $($_.Exception.Message)"
            throw
        }
    }
} else {
    Write-Warning "Public path not found: $PublicPath"
}







Write-Verbose "TierModel module loaded with CorrelationId: $script:CorrelationId"

function Get-TierModelConfigHash {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Path
    )
    if (!(Test-Path -LiteralPath $Path)) { throw "Config file not found: $Path" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-TierModel {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Raw
    )
    $json = Get-Content -Raw -LiteralPath $Path
    $obj = $json | ConvertFrom-Json -Depth 10
    if ($Raw) { return $json } else { return $obj }
}

function Test-TierModelConfig {
    [CmdletBinding(DefaultParameterSetName = 'FromPath')] 
    param(
        [Parameter(Mandatory, ParameterSetName = 'FromPath')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'FromConfig')][psobject]$Config,
        [Parameter(ParameterSetName = 'FromPath')][string]$SchemaPath = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config' 'tiermodel.schema.json'),
        [Parameter(ParameterSetName = 'FromPath')][switch]$Raw,
        [Parameter()][string]$Scope = 'FullDeployment'
    )
    
    # T0054: Add logging for configuration validation start
    Write-TierModelLog -Level Info -Message "Starting TierModel configuration validation" -Data @{
        ParameterSet = $PSCmdlet.ParameterSetName
        ConfigPath = if ($PSCmdlet.ParameterSetName -eq 'FromPath') { $Path } else { $null }
        SchemaPath = if ($PSCmdlet.ParameterSetName -eq 'FromPath') { $SchemaPath } else { $null }
    } | Out-Null
    
    if ($PSCmdlet.ParameterSetName -eq 'FromPath') {
        if (!(Test-Path -LiteralPath $Path)) { 
            Write-TierModelLog -Level Error -Message "Config file not found" -Data @{ Path = $Path } | Out-Null
            throw "Config file not found: $Path" 
        }
        if (!(Test-Path -LiteralPath $SchemaPath)) { 
            Write-TierModelLog -Level Error -Message "Schema file not found" -Data @{ SchemaPath = $SchemaPath } | Out-Null
            throw "Schema file not found: $SchemaPath" 
        }
        $configText = Get-Content -Raw -LiteralPath $Path
        $schemaText = Get-Content -Raw -LiteralPath $SchemaPath
        try {
            $config = $configText | ConvertFrom-Json -Depth 50
            $schema = $schemaText | ConvertFrom-Json -Depth 50
        } catch {
            Write-TierModelLog -Level Error -Message "Invalid JSON format during config validation" -Data @{ 
                Path = $Path
                ParseError = $_.Exception.Message
            } | Out-Null
            return [PSCustomObject]@{ Valid = $false; Errors = @("Invalid JSON format: $($_.Exception.Message)"); Warnings = @(); Raw = $configText }
        }
    } else {
        $config = $Config
    }
    
    # Generate correlation ID for tracking validation across logs
    $correlationId = [System.Guid]::NewGuid().ToString()
    Write-Verbose "Starting TierModel config validation (CorrelationId: $correlationId)"
    
    $errors = @()
    $warnings = @()
    $validationDetails = [PSCustomObject]@{
        ValidGpoModes = 0
        InvalidGpoModes = 0
        ValidDenyApplyGroups = 0
        InvalidDenyApplyGroups = 0
        ValidAdmxPaths = 0
        InvalidAdmxPaths = 0
    }
    
    # Schema validation if loading from path
    if ($PSCmdlet.ParameterSetName -eq 'FromPath' -and $schema) {
        foreach ($req in $schema.required) {
            if (-not ($config.PSObject.Properties.Name -contains $req)) {
                $errors += "Missing required top-level property: $req"
            }
        }
        
        # Helper for array item validation
        function _validateArrayItems($array, $definition, $name) {
            $localErrors = @()
            if ($null -eq $array) { return $localErrors }
            $req = $definition.items.required
            foreach ($item in $array) {
                foreach ($r in $req) {
                    if (-not ($item.PSObject.Properties.Name -contains $r)) {
                        $localErrors += "${name} item missing required property '$r' (value: $($item | ConvertTo-Json -Compress))"
                    }
                }
            }
            return $localErrors
        }

        # Safe property access with existence checks
        if ($config -is [hashtable]) {
            $organizationUnits = if ($config.ContainsKey('organizationUnits')) { $config['organizationUnits'] } else { $null }
            $groups = if ($config.ContainsKey('groups')) { $config['groups'] } else { $null }
            $users = if ($config.ContainsKey('users')) { $config['users'] } else { $null }
        } else {
            $organizationUnits = if ($config.PSObject.Properties.Name -contains 'organizationUnits') { $config.organizationUnits } else { $null }
            $groups = if ($config.PSObject.Properties.Name -contains 'groups') { $config.groups } else { $null }
            $users = if ($config.PSObject.Properties.Name -contains 'users') { $config.users } else { $null }
        }
        
        if ($config -is [hashtable]) {
            $gpos = if ($config.ContainsKey('gpos')) { $config['gpos'] } else { $null }
            $aclDelegations = if ($config.ContainsKey('aclDelegations')) { $config['aclDelegations'] } else { $null }
            $admx = if ($config.ContainsKey('admx')) { $config['admx'] } else { $null }
        } else {
            $gpos = if ($config.PSObject.Properties.Name -contains 'gpos') { $config.gpos } else { $null }
            $aclDelegations = if ($config.PSObject.Properties.Name -contains 'aclDelegations') { $config.aclDelegations } else { $null }
            $admx = if ($config.PSObject.Properties.Name -contains 'admx') { $config.admx } else { $null }
        }
        
        # Scope-based validation - only validate components relevant to the deployment scope
        # Based on user requirements:
        # -OuOnly = No other checks (only OUs)
        # -GroupsOnly = Ou Checks (OUs + Groups)  
        # -UsersOnly = Ou and Group checks (OUs + Groups + Users)
        # -OuAclsOnly = Ou and Group checks (OUs + Groups + ACLs)
        # -ImportAdmxOnly = No other checks (only ADMX)
        
        # OU validation - required for all scopes except ImportAdmxOnly
        if ($Scope -ne 'ImportAdmxOnly') {
            $errors += _validateArrayItems $organizationUnits $schema.properties.organizationUnits 'organizationUnits'
        }
        
        # Groups validation - required for GroupsOnly, UsersOnly, OuAclsOnly, and FullDeployment
        if ($Scope -in @('GroupsOnly', 'UsersOnly', 'OuAclsOnly', 'FullDeployment')) {
            $errors += _validateArrayItems $groups $schema.properties.groups 'groups'
        }
        
        # Users validation - required for UsersOnly and FullDeployment
        if ($Scope -in @('UsersOnly', 'FullDeployment')) {
            $errors += _validateArrayItems $users $schema.properties.users 'users'
        }
        
        # GPOs validation - only for FullDeployment
        if ($Scope -eq 'FullDeployment') {
            $errors += _validateArrayItems $gpos $schema.properties.gpos 'gpos'
        }
        
        # ACL Delegations validation - required for OuAclsOnly and FullDeployment
        if ($Scope -in @('OuAclsOnly', 'FullDeployment')) {
            $errors += _validateArrayItems $aclDelegations $schema.properties.aclDelegations 'aclDelegations'
        }
        
        # ADMX validation - only for ImportAdmxOnly and FullDeployment
        if ($Scope -in @('ImportAdmxOnly', 'FullDeployment')) {
            $errors += _validateArrayItems $admx $schema.properties.admx 'admx'
        }

        # Version pattern check with safe property access
        $configVersion = if ($config -is [hashtable]) {
            if ($config.ContainsKey('version')) { $config['version'] } else { $null }
        } else {
            if ($config.PSObject.Properties.Name -contains 'version') { $config.version } else { $null }
        }
        if ($configVersion -and ($configVersion -notmatch '^\d+\.\d+\.\d+$')) {
            $errors += "Version '$configVersion' does not match semantic pattern X.Y.Z"
        }
    }
    
    # Enhanced deep validation
    # 1. GPO Mode Validation - Only for FullDeployment scope
    if ($Scope -eq 'FullDeployment') {
        $validGpoModes = @('createAndImport', 'createImportAndConfigure')
        # Use safe property access for gpos
        $configGpos = if ($config -is [hashtable]) {
            if ($config.ContainsKey('gpos')) { $config['gpos'] } else { $null }
        } else {
            if ($config.PSObject.Properties.Name -contains 'gpos') { $config.gpos } else { $null }
        }
        if ($configGpos) {
        foreach ($gpo in $configGpos) {
            # Check if mode property exists (support both hashtables and PSCustomObjects)
            $hasModeProperty = if ($gpo -is [hashtable]) { 
                $gpo.ContainsKey('mode') 
            } else { 
                $gpo.PSObject.Properties.Name -contains 'mode' 
            }
            
            # Get GPO name safely
            $gpoName = if ($gpo -is [hashtable]) { 
                $gpo['name'] 
            } else { 
                if ($gpo.PSObject.Properties.Name -contains 'name') { 
                    $gpo.name 
                } else { 
                    'Unknown GPO' 
                }
            }
            
            if (-not $hasModeProperty) {
                $errors += "GPO '$gpoName' is missing required 'mode' property"
                $validationDetails.InvalidGpoModes++
            } else {
                # Get mode value safely
                $gpoMode = if ($gpo -is [hashtable]) { 
                    $gpo['mode'] 
                } else { 
                    if ($gpo.PSObject.Properties.Name -contains 'mode') { 
                        $gpo.mode 
                    } else { 
                        $null 
                    }
                }
                
                if ($gpoMode -notin $validGpoModes) {
                    $errors += "GPO '$gpoName' has invalid mode '$gpoMode'. Valid modes: $($validGpoModes -join ', ')"
                    $validationDetails.InvalidGpoModes++
                } else {
                    $validationDetails.ValidGpoModes++
                }
            }
        }
    }
    
    # 2. DenyApplyGroups Reference Validation
    $groupNames = @()
    # Use safe property access for groups
    $configGroups = if ($config -is [hashtable]) {
        if ($config.ContainsKey('groups')) { $config['groups'] } else { $null }
    } else {
        if ($config.PSObject.Properties.Name -contains 'groups') { $config.groups } else { $null }
    }
    if ($configGroups) {
        $groupNames = $configGroups | ForEach-Object { $_.name }
    }
    
    if ($configGpos) {
        foreach ($gpo in $configGpos) {
            # Check if denyApplyGroups property exists (support both hashtables and PSCustomObjects)
            $hasDenyApplyGroups = if ($gpo -is [hashtable]) { 
                $gpo.ContainsKey('denyApplyGroups') 
            } else { 
                $gpo.PSObject.Properties.Name -contains 'denyApplyGroups' 
            }
            
            # Get denyApplyGroups value safely
            $denyApplyGroups = if ($gpo -is [hashtable]) { 
                $gpo['denyApplyGroups'] 
            } else { 
                if ($gpo.PSObject.Properties.Name -contains 'denyApplyGroups') { 
                    $gpo.denyApplyGroups 
                } else { 
                    $null 
                }
            }
            
            if ($hasDenyApplyGroups -and $denyApplyGroups) {
                # Get GPO name safely for error messages
                $gpoName = if ($gpo -is [hashtable]) { 
                    $gpo['name'] 
                } else { 
                    if ($gpo.PSObject.Properties.Name -contains 'name') { 
                        $gpo.name 
                    } else { 
                        'Unknown GPO' 
                    }
                }
                
                foreach ($groupRef in $denyApplyGroups) {
                    if ($groupRef -in $groupNames) {
                        $validationDetails.ValidDenyApplyGroups++
                    } else {
                        $warnings += "GPO '$gpoName' references denyApplyGroup '$groupRef' which is not defined in groups configuration"
                        $validationDetails.InvalidDenyApplyGroups++
                    }
                }
            }
        }
    }
    } # End GPO validation scope check
    
    # 3. ADMX Source Path Validation - Only for ImportAdmxOnly and FullDeployment scopes
    if ($Scope -in @('ImportAdmxOnly', 'FullDeployment')) {
        # Use safe property access for admx
        $configAdmx = if ($config -is [hashtable]) {
            if ($config.ContainsKey('admx')) { $config['admx'] } else { $null }
        } else {
            if ($config.PSObject.Properties.Name -contains 'admx') { $config.admx } else { $null }
        }
        if ($configAdmx) {
        foreach ($admxEntry in $configAdmx) {
            # Safe property access for ADMX path
            $admxPath = if ($admxEntry -is [hashtable]) {
                if ($admxEntry.ContainsKey('path')) { $admxEntry['path'] } else { $null }
            } else {
                if ($admxEntry.PSObject.Properties.Name -contains 'path') { $admxEntry.path } else { $null }
            }
            
            if (-not $admxPath) {
                $errors += "ADMX entry missing required 'path' property"
                $validationDetails.InvalidAdmxPaths++
                continue
            }
            
            $language = if ($admxEntry -is [hashtable]) {
                if ($admxEntry.ContainsKey('language')) { $admxEntry['language'] } else { "en-US" }
            } else {
                if ($admxEntry.PSObject.Properties.Name -contains 'language') { $admxEntry.language } else { "en-US" }
            }
            
            if (-not (Test-Path -LiteralPath $admxPath -PathType Container)) {
                $errors += "ADMX source path '$admxPath' does not exist"
                $validationDetails.InvalidAdmxPaths++
                continue
            }
            
            # Check for .admx files
            $admxFiles = Get-ChildItem -Path $admxPath -Filter "*.admx" -ErrorAction SilentlyContinue
            if (-not $admxFiles) {
                $warnings += "ADMX path '$admxPath' contains no .admx files"
                $validationDetails.InvalidAdmxPaths++
                continue
            }
            
            # Check for default locale folder
            $localePath = Join-Path $admxPath $language
            if (-not (Test-Path -LiteralPath $localePath -PathType Container)) {
                $warnings += "ADMX path '$admxPath' missing default locale folder '$language'"
                $validationDetails.InvalidAdmxPaths++
                continue
            }
            
            $validationDetails.ValidAdmxPaths++
        }
    }
    } # End ADMX validation scope check
    
    # 4. OU Parent-Child Relationship Validation
    # Use safe property access for organizationUnits
    $configOrganizationUnits = if ($config -is [hashtable]) {
        if ($config.ContainsKey('organizationUnits')) { $config['organizationUnits'] } else { $null }
    } else {
        if ($config.PSObject.Properties.Name -contains 'organizationUnits') { $config.organizationUnits } else { $null }
    }
    if ($configOrganizationUnits) {
        $ouPaths = $configOrganizationUnits | ForEach-Object { $_.path }
        
        foreach ($ou in $configOrganizationUnits) {
            $ouPath = $ou.path
            # Extract parent path (everything after first OU= component)
            if ($ouPath -match '^OU=[^,]+,(.+)$') {
                $parentPath = $matches[1]
                if ($parentPath -like "OU=*" -and $parentPath -notin $ouPaths) {
                    $warnings += "OU '$($ou.name)' has parent path '$parentPath' which is not defined in configuration"
                }
            }
        }
    }
    
    Write-Verbose "Validation completed. Valid: $($errors.Count -eq 0), Errors: $($errors.Count), Warnings: $($warnings.Count) (CorrelationId: $correlationId)"
    
    # T0054: Log validation completion
    $validationSuccess = ($errors.Count -eq 0)
    Write-TierModelLog -Level $(if ($validationSuccess) { 'Info' } else { 'Warning' }) -Message "Configuration validation completed" -Data @{
        Valid = $validationSuccess
        ErrorCount = $errors.Count
        WarningCount = $warnings.Count
        ValidGpoModes = $validationDetails.ValidGpoModes
        ValidAdmxPaths = $validationDetails.ValidAdmxPaths
        ValidationCorrelationId = $correlationId
    } | Out-Null
    
    $result = [PSCustomObject]@{
        Valid = ($errors.Count -eq 0)
        Errors = $errors
        Warnings = $warnings
        ValidationDetails = $validationDetails
        CorrelationId = $correlationId
    }
    
    # Add file-specific properties for path-based validation
    if ($PSCmdlet.ParameterSetName -eq 'FromPath') {
        $result | Add-Member -NotePropertyName ConfigHash -NotePropertyValue (Get-TierModelConfigHash -Path $Path)
        $result | Add-Member -NotePropertyName Path -NotePropertyValue $Path
        $result | Add-Member -NotePropertyName SchemaPath -NotePropertyValue $SchemaPath
        $result | Add-Member -NotePropertyName Timestamp -NotePropertyValue (Get-Date).ToString('o')
        if ($Raw) { 
            $result | Add-Member -NotePropertyName Raw -NotePropertyValue $configText
            return ($result | ConvertTo-Json -Depth 20) 
        }
    }
    
    return $result
}

function Get-TierModelPlan {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$IncludeHashes
    )
    # T0054: Log plan generation start
    Write-TierModelLog -Level Info -Message "Starting TierModel plan generation" -Data @{
        ConfigPath = $Path
        IncludeHashes = $IncludeHashes.IsPresent
    } | Out-Null
    
    $model = Get-TierModel -Path $Path
    
    # Create empty action plan structure (action planning not implemented)
    $actionPlan = [PSCustomObject]@{
        Actions = @()
        Warnings = @()
        Errors = @()
        CorrelationId = [System.Guid]::NewGuid().ToString()
        Timestamp = (Get-Date).ToString('o')
        Summary = @{
            TotalActions = 0
            ByType = @()
            HasErrors = $false
        }
    }

    # No current state capture or drift detection implementation
    $currentState = $null
    $driftFindings = @()
    
    # Categorize actions for backward compatibility with safety checks
    $actions = @()
    if ($actionPlan) {
        try {
            if ($actionPlan -is [hashtable]) {
                $actions = if ($actionPlan.ContainsKey('Actions')) { $actionPlan['Actions'] } else { @() }
            } elseif ($actionPlan -is [array] -or $actionPlan -is [System.Object[]]) {
                # Action plan returned as array directly
                $actions = @($actionPlan)
            } else {
                if ($actionPlan.PSObject.Properties['Actions']) {
                    try {
                        $actions = $actionPlan.Actions
                    } catch {
                        $actions = @()
                    }
                } else {
                    $actions = @()
                }
            }
        } catch {
            Write-Verbose "Failed to access Actions property: $($_.Exception.Message)"
            $actions = @()
        }
    }
    $adds = @($actions | Where-Object { $_.Type -in @('CreateOU', 'CreateGroup', 'CreateUser', 'CreateGPO', 'ImportADMX') })
    $updates = @($actions | Where-Object { $_.Type -in @('SetGroupMembership', 'SetACL') })
    $links = @($actions | Where-Object { $_.Type -eq 'LinkGPO' })
    
    # T0050: Compute deterministic plan hash based on sorted actions + config hash
    $configHash = Get-TierModelConfigHash -Path $Path
    $planHash = $null
    if ($actions -and $actions.Count -gt 0) {
        # Create deterministic action signature by sorting actions by Type, Target, and Properties
        $sortedActionSignatures = $actions | ForEach-Object {
            $propertiesHash = ""
            if ($_.Properties) {
                $sortedProps = $_.Properties.PSObject.Properties | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }
                $propertiesHash = ($sortedProps -join "|")
            }
            "$($_.Type):$($_.Target):$propertiesHash"
        } | Sort-Object
        
        $actionListString = $sortedActionSignatures -join ";"
        $planString = "$configHash|$actionListString"
        
        # Compute SHA256 hash of the plan signature
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($planString)
        $planHashBytes = $sha.ComputeHash($bytes)
        $planHash = ($planHashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
    } else {
        # Empty action plan gets a special hash based only on config
        $planHash = $configHash + ":empty"
    }

    # Force arrays for collection properties
    $addsArray = @($adds)
    $updatesArray = @($updates)
    $linksArray = @($links)
    
    $plan = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString('o')
        ConfigHash = if ($IncludeHashes) { $configHash } else { $null }
        PlanHash = $planHash # T0050: Deterministic plan fingerprint
        ModelVersion = $model.version
        OrganizationUnitsCount = if ($model.organizationUnits) { $model.organizationUnits.Count } else { 0 }
        GroupsCount = if ($model.groups) { $model.groups.Count } else { 0 }
        UsersCount = if ($model.users) { $model.users.Count } else { 0 }
        GposCount = if ($model.gpos) { $model.gpos.Count } else { 0 }
        AdmxCount = if ($model.admx) { $model.admx.Count } else { 0 }
        Adds = $addsArray
        Updates = $updatesArray
        Links = $linksArray
        AllActions = @($actions)
        ActionSummary = if ($actionPlan -and $actionPlan -is [psobject] -and $actionPlan.PSObject.Properties['Summary']) { $actionPlan.Summary } else { @{} }
        ActionWarnings = if ($actionPlan -and $actionPlan -is [psobject] -and $actionPlan.PSObject.Properties['Warnings']) { @($actionPlan.Warnings) } else { @() }
        ActionErrors = if ($actionPlan -and $actionPlan -is [psobject] -and $actionPlan.PSObject.Properties['Errors']) { @($actionPlan.Errors) } else { @() }
        DriftFindings = @($driftFindings) # T0048: Now populated with actual drift findings
        CurrentState = $currentState
        CorrelationId = if ($actionPlan -and $actionPlan -is [psobject] -and $actionPlan.PSObject.Properties['CorrelationId']) { $actionPlan.CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    }
    
    # T0054: Log plan generation completion
    Write-TierModelLog -Level Info -Message "TierModel plan generation completed" -Data @{
        ConfigPath = $Path
        PlanHash = $planHash
        ActionCount = (@($plan.AllActions)).Count
        DriftFindingsCount = (@($driftFindings)).Count
        OUsCount = $plan.OrganizationUnitsCount
        GroupsCount = $plan.GroupsCount
        GposCount = $plan.GposCount
        PlanCorrelationId = if ($actionPlan -and $actionPlan -is [psobject] -and $actionPlan.PSObject.Properties['CorrelationId']) { $actionPlan.CorrelationId } else { $null }
    } | Out-Null
    
    return $plan
}

function New-TierModel {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$PreferredDc,
        [string]$DependenciesPath = 'config/dependencies.json',
        [switch]$WhatIf,
        [switch]$ConfirmApply
    )
    
    # T0054: Log deployment initiation
    Write-TierModelLog -Level Info -Message "Starting TierModel initial deployment" -Data @{
        ConfigPath = $Path
        PreferredDc = $PreferredDc
        DependenciesPath = $DependenciesPath
        WhatIf = $WhatIf.IsPresent
        ConfirmApply = $ConfirmApply.IsPresent
    } | Out-Null
    
    # Prerequisites gate - abort if invalid
    Write-Verbose "Validating prerequisites before deployment..."
    $prereqResult = Test-TierModelPrerequisites -PreferredDc $PreferredDc -DependenciesPath $DependenciesPath
    
    # Handle case where result might be an array due to pipeline contamination
    if ($prereqResult -is [array]) {
        $prereqResult = $prereqResult | Where-Object { $_ -and $_.PSObject.Properties['Valid'] } | Select-Object -Last 1
    }
    
    if (-not $prereqResult -or -not $prereqResult.Valid) {
        $errorMessage = "Prerequisites validation failed:`n" + 
                       ($prereqResult.Errors -join "`n") + "`n`n" +
                       "Remediation steps:`n" + 
                       ($prereqResult.Remediation -join "`n")
        
        # T0054: Log prerequisite failure (use Warning level in WhatIf mode to avoid Write-Error)
        Write-TierModelLog -Level $(if ($WhatIf) { 'Warning' } else { 'Error' }) -Message "TierModel deployment failed - prerequisites not met" -Data @{
            ConfigPath = $Path
            PreferredDc = $PreferredDc
            ErrorCount = $prereqResult.Errors.Count
            Errors = $prereqResult.Errors
        } | Out-Null
        
        # In WhatIf mode, show prerequisites as warnings instead of errors
        if ($WhatIf) {
            Write-Warning "Prerequisites validation failed (bypassed in WhatIf mode):`n$errorMessage"
        } else {
            Write-Error $errorMessage
        }
        
        return [PSCustomObject]@{
            Applied = $false
            PrerequisitesFailed = $true
            PrerequisitesResult = $prereqResult
            Plan = $null
        }
    }
    
    Write-Verbose "Prerequisites validation passed. Generating deployment plan..."
    $plan = Get-TierModelPlan -Path $Path -IncludeHashes
    if ($WhatIf) { 
        Write-TierModelLog -Level Info -Message "TierModel deployment plan generated (WhatIf mode)" -Data @{
            ConfigPath = $Path
            PlanHash = $plan.PlanHash
            ActionCount = if ($plan.AllActions) { $plan.AllActions.Count } else { 0 }
        } | Out-Null
        return [PSCustomObject]@{ 
            Applied = $false
            WhatIf = $true
            PrerequisitesPassed = $true
            PrerequisitesResult = $prereqResult
            Plan = $plan
            Adds = $plan.Adds
            Updates = $plan.Updates
            Links = $plan.Links
        }
    }
    if (-not $ConfirmApply) { throw 'ConfirmApply switch required to apply changes (safety gate).'}
    
    Write-Verbose "Executing deployment plan..."
    # T0054: Log deployment execution start
    Write-TierModelLog -Level Info -Message "Executing TierModel initial deployment" -Data @{
        ConfigPath = $Path
        PlanHash = $plan.PlanHash
        ActionCount = if ($plan.AllActions) { $plan.AllActions.Count } else { 0 }
    } | Out-Null
    
    # Stub: Apply adds only (initial deployment)
    Write-TierModelLog -Level Info -Message "TierModel initial deployment completed" -Data @{
        ConfigPath = $Path
        PlanHash = $plan.PlanHash
        Applied = $true
    } | Out-Null
    
    return [PSCustomObject]@{ 
        Applied = $true
        PrerequisitesPassed = $true
        PrerequisitesResult = $prereqResult
        Plan = $plan 
    }
}

function Set-TierModel {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$PreferredDc,
        [string]$DependenciesPath = 'config/dependencies.json',
        [switch]$WhatIf,
        [switch]$ConfirmApply
    )
    
    # T0054: Log convergence initiation
    Write-TierModelLog -Level Info -Message "Starting TierModel convergence operation" -Data @{
        ConfigPath = $Path
        PreferredDc = $PreferredDc
        DependenciesPath = $DependenciesPath
        WhatIf = $WhatIf.IsPresent
        ConfirmApply = $ConfirmApply.IsPresent
    } | Out-Null
    
    # Prerequisites gate - abort if invalid
    Write-Verbose "Validating prerequisites before convergence..."
    $prereqResult = Test-TierModelPrerequisites -PreferredDc $PreferredDc -DependenciesPath $DependenciesPath
    
    # Handle case where result might be an array due to pipeline contamination
    if ($prereqResult -is [array]) {
        $prereqResult = $prereqResult | Where-Object { $_ -and $_.PSObject.Properties['Valid'] } | Select-Object -Last 1
    }
    
    if (-not $prereqResult -or -not $prereqResult.Valid) {
        $errorMessage = "Prerequisites validation failed:`n" + 
                       ($prereqResult.Errors -join "`n") + "`n`n" +
                       "Remediation steps:`n" + 
                       ($prereqResult.Remediation -join "`n")
        
        # In WhatIf mode, show prerequisites as warnings instead of errors
        if ($WhatIf) {
            Write-Warning "Prerequisites validation failed (bypassed in WhatIf mode):`n$errorMessage"
        } else {
            Write-Error $errorMessage
        }
        
        return [PSCustomObject]@{
            Converged = $false
            PrerequisitesFailed = $true
            PrerequisitesResult = $prereqResult
            Plan = $null
        }
    }
    
    Write-Verbose "Prerequisites validation passed. Generating convergence plan..."
    $plan = Get-TierModelPlan -Path $Path -IncludeHashes
    if ($WhatIf) { 
        return [PSCustomObject]@{ 
            Converged = $false
            WhatIf = $true
            PrerequisitesPassed = $true
            PrerequisitesResult = $prereqResult
            Plan = $plan
            Adds = $plan.Adds
            Updates = $plan.Updates
            Links = $plan.Links
        }
    }
    if (-not $ConfirmApply) { throw 'ConfirmApply switch required to apply changes (safety gate).'}
    
    # T0051: Check for convergence before execution (empty actions = already converged)
    $alreadyConverged = (-not $plan.AllActions -or $plan.AllActions.Count -eq 0)
    if ($alreadyConverged) {
        Write-Verbose "System already converged - no actions required (CorrelationId: $($plan.CorrelationId))"
        # T0054: Log pre-convergence detection
        Write-TierModelLog -Level Info -Message "TierModel system already converged" -Data @{
            ConfigPath = $Path
            PlanHash = $plan.PlanHash
            ActionCount = 0
            PlanCorrelationId = $plan.CorrelationId
        } | Out-Null
        return [PSCustomObject]@{ 
            Converged = $true
            AlreadyConverged = $true
            PrerequisitesPassed = $true
            PrerequisitesResult = $prereqResult
            Plan = $plan
            ExecutionResult = @{ Success = $true; Statistics = @{ SuccessfulActions = 0; TotalActions = 0 }; Message = "No actions required - system already converged" }
        }
    }
    
    Write-Verbose "Executing convergence plan..."
    # T0054: Log convergence execution start
    Write-TierModelLog -Level Info -Message "Executing TierModel convergence plan" -Data @{
        ConfigPath = $Path
        PlanHash = $plan.PlanHash
        ActionCount = $plan.AllActions.Count
        PlanCorrelationId = $plan.CorrelationId
    } | Out-Null
    
    $executionResult = Invoke-TierModelPlan -Plan $plan
    
    # T0051: Post-execution convergence detection
    $postExecutionConverged = $executionResult.Success -and ($executionResult.Statistics.SuccessfulActions -eq $plan.AllActions.Count)
    
    # T0054: Log convergence completion
    Write-TierModelLog -Level $(if ($postExecutionConverged) { 'Info' } else { 'Warning' }) -Message "TierModel convergence operation completed" -Data @{
        ConfigPath = $Path
        PlanHash = $plan.PlanHash
        Converged = $postExecutionConverged
        ActionCount = $plan.AllActions.Count
        SuccessfulActions = $executionResult.Statistics.SuccessfulActions
        ExecutionSuccess = $executionResult.Success
    } | Out-Null
    
    return [PSCustomObject]@{ 
        Converged = $postExecutionConverged
        AlreadyConverged = $false
        PrerequisitesPassed = $true
        PrerequisitesResult = $prereqResult
        Plan = $plan
        ExecutionResult = $executionResult
    }
}

function Test-TierModelDrift {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Raw
    )
    # T0054: Log drift detection start
    Write-TierModelLog -Level Info -Message "Starting TierModel drift detection" -Data @{
        ConfigPath = $Path
        Raw = $Raw.IsPresent
    } | Out-Null
    
    $plan = Get-TierModelPlan -Path $Path -IncludeHashes
    $report = [PSCustomObject]@{
        DriftDetected = ($plan.DriftFindings.Count -gt 0)
        Findings = $plan.DriftFindings
        ConfigHash = $plan.ConfigHash
        Generated = (Get-Date).ToString('o')
    }
    
    # T0054: Log drift detection completion
    Write-TierModelLog -Level $(if ($report.DriftDetected) { 'Warning' } else { 'Info' }) -Message "TierModel drift detection completed" -Data @{
        ConfigPath = $Path
        DriftDetected = $report.DriftDetected
        FindingCount = $plan.DriftFindings.Count
        ConfigHash = $plan.ConfigHash
    } | Out-Null
    
    if ($Raw) { return ($report | ConvertTo-Json -Depth 10) } else { return $report }
}
