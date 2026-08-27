function Get-TierModelConfig {
    <#
    .SYNOPSIS
    Loads and validates segmented TierModel configuration from fixed path.
    
    .DESCRIPTION
    Loads configuration from multiple JSON files in the fixed config directory:
    - tiermodel-metadata.json
    - tiermodel-ous.json
    - tiermodel-groups.json
    - tiermodel-users.json
    - tiermodel-acls.json
    - tiermodel-gpos.json
    - tiermodel-admx.json
    
    Merges them into a single logical configuration object and validates schema.
    
    .PARAMETER ConfigPath
    Override path to config directory. Defaults to module-relative config path.
    
    .OUTPUTS
    PSCustomObject representing the merged TierModel configuration
    
    .EXAMPLE
    $config = Get-TierModelConfig
    
    .EXAMPLE
    # Load from custom config directory
    $config = Get-TierModelConfig -ConfigPath "C:\CustomConfig"
    
    .NOTES
    This function requires access to the TierModel configuration files and
    depends on Write-TierModelLog for structured logging.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigPath = $script:ConfigPath
    )
    
    $CorrelationId = $script:CorrelationId
    Write-TierModelLog -Level Info -Message "Loading segmented configuration" -Data @{ ConfigPath = $ConfigPath; CorrelationId = $CorrelationId }
    
    # Required configuration files (FR-021: fixed path, no user override)
    $requiredFiles = @(
        'tiermodel-metadata.json',
        'tiermodel-ous.json', 
        'tiermodel-groups.json',
        'tiermodel-users.json',
        'tiermodel-acls.json',
        'tiermodel-gpos.json',
        'tiermodel-admx.json',
        'tiermodel-guid-mappings.json'
    )
    
    if (-not (Test-Path $ConfigPath)) {
        $configNotFoundMessage = "Configuration directory not found: $ConfigPath"
        Write-TierModelLog -Level Error -Message $configNotFoundMessage -Data @{ CorrelationId = $CorrelationId }
        throw $configNotFoundMessage
    }
    
    # Fail-fast validation: ensure all required files exist
    $missingFiles = @()
    foreach ($fileName in $requiredFiles) {
        $filePath = Join-Path $ConfigPath $fileName
        if (-not (Test-Path $filePath)) {
            $missingFiles += $fileName
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        $missingFilesMessage = "Missing required configuration files: $($missingFiles -join ', ')"
        Write-TierModelLog -Level Error -Message $missingFilesMessage -Data @{ MissingFiles = $missingFiles; CorrelationId = $CorrelationId }
        throw $missingFilesMessage
    }
    
    # Load and parse each segment
    $segments = @{}
    foreach ($fileName in $requiredFiles) {
        $filePath = Join-Path $ConfigPath $fileName
        try {
            Write-TierModelLog -Level Debug -Message "Loading configuration segment" -Data @{ File = $fileName; CorrelationId = $CorrelationId }
            $content = Get-Content -Path $filePath -Raw -Encoding UTF8
            $segments[$fileName] = $content | ConvertFrom-Json -Depth 20
        } catch {
            $parseFailureMessage = "Failed to parse $fileName`: $($_.Exception.Message)"
            Write-TierModelLog -Level Error -Message $parseFailureMessage -Data @{ File = $fileName; CorrelationId = $CorrelationId }
            throw $parseFailureMessage
        }
    }
    
    # Load optional MSA/gMSA/dMSA add-on configuration files (not in $requiredFiles — only loaded when present)
    $optionalFiles = @(
        'tiermodel-msa.json',
        'tiermodel-gmsa.json',
        'tiermodel-dmsa.json',
        'tiermodel-winlaps.json',
        'tiermodel-audit.json',
        'tiermodel-authsilos.json'
    )
    $optionalSegments = @{}
    foreach ($fileName in $optionalFiles) {
        $filePath = Join-Path $ConfigPath $fileName
        if (Test-Path $filePath) {
            try {
                Write-TierModelLog -Level Debug -Message "Loading optional configuration segment" -Data @{ File = $fileName; CorrelationId = $CorrelationId }
                $content = Get-Content -Path $filePath -Raw -Encoding UTF8
                $optionalSegments[$fileName] = $content | ConvertFrom-Json -Depth 20
            } catch {
                Write-TierModelLog -Level Warning -Message "Failed to parse optional segment $fileName — skipping" -Data @{ File = $fileName; Error = $_.Exception.Message; CorrelationId = $CorrelationId }
            }
        }
    }

    # Merge segments into unified configuration
    try {
        # Store GUID mappings for later resolution during deployment/audit operations
        # Note: We don't resolve GUIDs here since we don't have domain controller information yet
        # GUID resolution will happen in the specific cmdlets (Get-TierModelOuAcl, etc.)
        $guidMappings = $segments['tiermodel-guid-mappings.json']
        
        # Debug: Check what's in the metadata segment
        $metadataSegment = $segments['tiermodel-metadata.json']
        try {
            Write-TierModelLog -Level Debug -Message "Metadata segment debug" -Data @{ 
                HasVersion = ($null -ne $metadataSegment.version)
                VersionValue = $metadataSegment.version
                MetadataProperties = ($metadataSegment | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -join ', '
                CorrelationId = $CorrelationId 
            } | Out-Null
        } catch { 
            # Continue if logging fails
        }
        
        # Create configuration object with explicit property checking
        $config = [PSCustomObject]@{
            version = if ($metadataSegment.PSObject.Properties['version']) { $metadataSegment.version } else { '1.0.0' }
            metadata = if ($metadataSegment.PSObject.Properties['metadata']) { $metadataSegment.metadata } else { @{} }
            conditionalLogic = if ($metadataSegment.PSObject.Properties['conditionalLogic']) { $metadataSegment.conditionalLogic } else { @{} }
            organizationUnits = if ($segments['tiermodel-ous.json'].PSObject.Properties['organizationUnits']) { $segments['tiermodel-ous.json'].organizationUnits } else { @() }
            groups = if ($segments['tiermodel-groups.json'].PSObject.Properties['groups']) { $segments['tiermodel-groups.json'].groups } else { @() }
            users = if ($segments['tiermodel-users.json'].PSObject.Properties['users']) { $segments['tiermodel-users.json'].users } else { @() }
            aclDelegations = if ($segments['tiermodel-acls.json'].PSObject.Properties['aclDelegations']) { $segments['tiermodel-acls.json'].aclDelegations } else { @() }
            gpos = if ($segments['tiermodel-gpos.json'].PSObject.Properties['gpos']) { $segments['tiermodel-gpos.json'].gpos } else { @{} }
            admx = if ($segments['tiermodel-admx.json'].PSObject.Properties['admx']) { $segments['tiermodel-admx.json'].admx } else { @{} }
            guidMappings = $guidMappings
            msaAclDelegations = if ($optionalSegments['tiermodel-msa.json'] -and $optionalSegments['tiermodel-msa.json'].PSObject.Properties['aclDelegations']) { $optionalSegments['tiermodel-msa.json'].aclDelegations } else { $null }
            gmsaAclDelegations = if ($optionalSegments['tiermodel-gmsa.json'] -and $optionalSegments['tiermodel-gmsa.json'].PSObject.Properties['aclDelegations']) { $optionalSegments['tiermodel-gmsa.json'].aclDelegations } else { $null }
            dmsaAclDelegations = if ($optionalSegments['tiermodel-dmsa.json'] -and $optionalSegments['tiermodel-dmsa.json'].PSObject.Properties['aclDelegations']) { $optionalSegments['tiermodel-dmsa.json'].aclDelegations } else { $null }
            winLapsDelegations = if ($optionalSegments['tiermodel-winlaps.json'] -and $optionalSegments['tiermodel-winlaps.json'].PSObject.Properties['winLapsDelegations']) { $optionalSegments['tiermodel-winlaps.json'].winLapsDelegations } else { $null }
            domainAuditRule = if ($optionalSegments['tiermodel-audit.json'] -and $optionalSegments['tiermodel-audit.json'].PSObject.Properties['domainAuditRule']) { $optionalSegments['tiermodel-audit.json'].domainAuditRule } else { $null }
            authenticationPolicies = if ($optionalSegments['tiermodel-authsilos.json'] -and $optionalSegments['tiermodel-authsilos.json'].PSObject.Properties['authenticationPolicies']) { $optionalSegments['tiermodel-authsilos.json'].authenticationPolicies } else { $null }
            authenticationSilos = if ($optionalSegments['tiermodel-authsilos.json'] -and $optionalSegments['tiermodel-authsilos.json'].PSObject.Properties['authenticationSilos']) { $optionalSegments['tiermodel-authsilos.json'].authenticationSilos } else { $null }
        }
        
        # Compute composite hash for provenance (FR-005)
        $allContent = $requiredFiles | ForEach-Object { 
            Get-Content -Path (Join-Path $ConfigPath $_) -Raw 
        }
        # Include optional segments in hash when loaded
        foreach ($optFile in $optionalFiles) {
            $optPath = Join-Path $ConfigPath $optFile
            if (Test-Path $optPath) {
                $allContent += Get-Content -Path $optPath -Raw
            }
        }
        $combinedContent = $allContent -join ''
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($combinedContent)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($bytes)
        $configHash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        
        # Add computed properties
        $config | Add-Member -NotePropertyName 'ConfigHash' -NotePropertyValue $configHash
        $config | Add-Member -NotePropertyName 'LoadedAt' -NotePropertyValue (Get-Date)
        $config | Add-Member -NotePropertyName 'ConfigPath' -NotePropertyValue $ConfigPath
        
        # Debug: Verify config object has version property
        try {
            Write-TierModelLog -Level Debug -Message "Final config object debug" -Data @{ 
                HasVersionProperty = ($null -ne $config.version)
                VersionValue = $config.version
                ConfigProperties = ($config | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -join ', '
                CorrelationId = $CorrelationId 
            } | Out-Null
        } catch { 
            # Continue if logging fails
        }
        
        Write-TierModelLog -Level Info -Message "Configuration loaded successfully" -Data @{ 
            ConfigHash = $configHash.Substring(0,16) + '...'
            Version = $config.version
            OuCount = $config.organizationUnits.Count
            GroupCount = $config.groups.Count
            UserCount = $config.users.Count
            GpoCount = $config.gpos.Count
            CorrelationId = $CorrelationId 
        }
        
        return $config
        
    } catch {
        $mergeFailureMessage = "Failed to merge configuration segments: $($_.Exception.Message)"
        Write-TierModelLog -Level Error -Message $mergeFailureMessage -Data @{ CorrelationId = $CorrelationId }
        throw $mergeFailureMessage
    }
}