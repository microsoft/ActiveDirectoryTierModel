function Get-TierModelAdmx {
    <#
    .SYNOPSIS
    Plan and analyze ADMX/ADML template deployment needs using hash verification.
    
    .DESCRIPTION
    Analyzes ADMX/ADML files from configuration against SYSVOL destination to determine
    which files need to be imported, updated, or are already current. Performs MD5 hash
    verification to determine file differences without making changes.
    
    .PARAMETER Config
    TierModel configuration object containing ADMX definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations and SYSVOL access.
    
    .PARAMETER AdmlLanguage
    Language code for ADML files (defaults to 'en-US').
    
    .EXAMPLE
    Get-TierModelAdmx -Config $config -DomainController "DC01" -AdmlLanguage "en-US"
    
    .OUTPUTS
    PSCustomObject with analysis results including files that need updates and those up to date.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [Parameter()]
        [string]$AdmlLanguage = 'en-US',
        
        [Parameter()]
        [switch]$Silent
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "ADMX analysis start" -Data @{
        DomainController = $DomainController
        AdmlLanguage = $AdmlLanguage
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Get domain information for SYSVOL path resolution
        $domain = (Get-ADDomain -Server $DomainController).DNSRoot
        Write-TierModelLog -Level Info -Message "Domain information retrieved" -Data @{ Domain = $domain; DomainController = $DomainController } | Out-Null
        
        # Load ADMX and ADML configurations
        # Config directory is at TierModelv2/config (same level as Modules directory)
        $moduleRoot = Split-Path $PSScriptRoot -Parent  # Gets to TierModel module directory
        $modulesRoot = Split-Path $moduleRoot -Parent   # Gets to Modules directory
        $tierModelRoot = Split-Path $modulesRoot -Parent # Gets to TierModelv2 directory
        $admxConfigPath = Join-Path $tierModelRoot 'config\tiermodel-admx.json'
        $admlConfigPath = Join-Path $tierModelRoot "config\tiermodel-adml-$AdmlLanguage.json"
        
        if (-not (Test-Path $admxConfigPath)) {
            throw "ADMX configuration file not found: $admxConfigPath"
        }
        if (-not (Test-Path $admlConfigPath)) {
            throw "ADML configuration file not found for language '$AdmlLanguage': $admlConfigPath"
        }
        
        $admxConfig = Get-Content $admxConfigPath | ConvertFrom-Json
        $admlConfig = Get-Content $admlConfigPath | ConvertFrom-Json
        
        # Get source and destination paths (relative to TierModelv2 directory)
        $admxSourcePath = Join-Path $tierModelRoot $admxConfig.admx.sourcePath.Replace('\\', '\\')
        $admlSourcePath = Join-Path $tierModelRoot $admlConfig.adml.sourcePath.Replace('\\', '\\')
        
        # Get destination paths - use PreferredDc for UNC path, domain for SYSVOL directory
        $admxDestinationPath = $admxConfig.admx.destinationPath -replace '\\\\{{DOMAIN_FQDN}}\\SYSVOL\\{{DOMAIN_FQDN}}\\', "\\$DomainController\SYSVOL\$($domain.ToUpper())\"
        $admlDestinationPath = $admlConfig.adml.destinationPath -replace '\\\\{{DOMAIN_FQDN}}\\SYSVOL\\{{DOMAIN_FQDN}}\\', "\\$DomainController\SYSVOL\$($domain.ToUpper())\"
        
        # Validate source paths exist
        if (-not (Test-Path $admxSourcePath)) {
            throw "ADMX source path not found: $admxSourcePath"
        }
        if (-not (Test-Path $admlSourcePath)) {
            throw "ADML source path not found: $admlSourcePath"
        }
        
        $analysis = @{
            TotalAdmxFiles = 0
            TotalAdmlFiles = 0
            AdmxToUpdate = @()
            AdmlToUpdate = @()
            AdmxUpToDate = @()
            AdmlUpToDate = @()
            Errors = @()
        }
        
        # Analyze ADMX files
        if (-not $Silent) {
            Write-Host "Analyzing ADMX files..." -ForegroundColor Cyan
        }
        foreach ($admxFile in $admxConfig.admx.files.PSObject.Properties) {
            $fileName = $admxFile.Name
            $expectedHash = $admxFile.Value.hash
            $sourcePath = Join-Path $admxSourcePath $fileName
            $destinationFilePath = Join-Path $admxDestinationPath $fileName
            
            $analysis.TotalAdmxFiles++
            
            # Check if source file exists
            if (-not (Test-Path $sourcePath)) {
                $analysis.Errors += "Source ADMX file not found: $sourcePath"
                continue
            }
            
            # Get source file hash
            $sourceHash = (Get-FileHash -Path $sourcePath -Algorithm MD5).Hash
            if ($sourceHash -ne $expectedHash) {
                $analysis.Errors += "Source ADMX file hash mismatch for $fileName. Expected: $expectedHash, Actual: $sourceHash"
                continue
            }
            
            # Check destination file and determine action type
            $needsUpdate = $false
            $actionType = $null
            if (-not (Test-Path $destinationFilePath)) {
                $needsUpdate = $true
                $actionType = "Import"
                $reason = "File not present in SYSVOL - new import"
            } else {
                $destinationHash = (Get-FileHash -Path $destinationFilePath -Algorithm MD5).Hash
                if ($destinationHash -ne $expectedHash) {
                    $needsUpdate = $true
                    $actionType = "Update"
                    $reason = "Hash mismatch - overwrite required"
                } else {
                    $reason = "Hash matches - up to date"
                }
            }
            
            $fileInfo = @{
                Name = $fileName
                SourcePath = $sourcePath
                DestinationPath = $destinationFilePath
                ExpectedHash = $expectedHash
                Reason = $reason
                NeedsUpdate = $needsUpdate
                ActionType = $actionType
            }
            
            if ($needsUpdate) {
                $analysis.AdmxToUpdate += $fileInfo
            } else {
                $analysis.AdmxUpToDate += $fileInfo
            }
        }
        
        # Analyze ADML files for specified language
        if (-not $Silent) {
            Write-Host "Analyzing ADML files ($AdmlLanguage)..." -ForegroundColor Cyan
        }
        
        foreach ($admlFile in $admlConfig.adml.files.PSObject.Properties) {
            $fileName = $admlFile.Name
            $expectedHash = $admlFile.Value.hash
            $sourcePath = Join-Path $admlSourcePath $fileName
            $destinationFilePath = Join-Path $admlDestinationPath $fileName
            
            $analysis.TotalAdmlFiles++
            
            # Check if source file exists
            if (-not (Test-Path $sourcePath)) {
                $analysis.Errors += "Source ADML file not found: $sourcePath"
                continue
            }
            
            # Get source file hash
            $sourceHash = (Get-FileHash -Path $sourcePath -Algorithm MD5).Hash
            if ($sourceHash -ne $expectedHash) {
                $analysis.Errors += "Source ADML file hash mismatch for $fileName. Expected: $expectedHash, Actual: $sourceHash"
                continue
            }
            
            # Check destination file and determine action type
            $needsUpdate = $false
            $actionType = $null
            if (-not (Test-Path $destinationFilePath)) {
                $needsUpdate = $true
                $actionType = "Import"
                $reason = "File not present in SYSVOL - new import"
            } else {
                $destinationHash = (Get-FileHash -Path $destinationFilePath -Algorithm MD5).Hash
                if ($destinationHash -ne $expectedHash) {
                    $needsUpdate = $true
                    $actionType = "Update"
                    $reason = "Hash mismatch - overwrite required"
                } else {
                    $reason = "Hash matches - up to date"
                }
            }
            
            $fileInfo = @{
                Name = $fileName
                SourcePath = $sourcePath
                DestinationPath = $destinationFilePath
                ExpectedHash = $expectedHash
                Reason = $reason
                NeedsUpdate = $needsUpdate
                ActionType = $actionType
                Language = $AdmlLanguage
            }
            
            if ($needsUpdate) {
                $analysis.AdmlToUpdate += $fileInfo
            } else {
                $analysis.AdmlUpToDate += $fileInfo
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "ADMX analysis completed" -Data @{
            TotalAdmxFiles = $analysis.TotalAdmxFiles
            TotalAdmlFiles = $analysis.TotalAdmlFiles
            AdmxToUpdate = $analysis.AdmxToUpdate.Count
            AdmlToUpdate = $analysis.AdmlToUpdate.Count
            AdmxUpToDate = $analysis.AdmxUpToDate.Count
            AdmlUpToDate = $analysis.AdmlUpToDate.Count
            Errors = $analysis.Errors.Count
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Analysis = $analysis
            Summary = [PSCustomObject]@{
                TotalFiles = ($analysis.TotalAdmxFiles + $analysis.TotalAdmlFiles)
                FilesToUpdate = ($analysis.AdmxToUpdate.Count + $analysis.AdmlToUpdate.Count)
                FilesUpToDate = ($analysis.AdmxUpToDate.Count + $analysis.AdmlUpToDate.Count)
                Errors = $analysis.Errors.Count
                RequiresUpdate = (($analysis.AdmxToUpdate.Count + $analysis.AdmlToUpdate.Count) -gt 0)
            }
            Domain = $domain
            AdmlLanguage = $AdmlLanguage
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "ADMX analysis failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Analysis = @{
                TotalAdmxFiles = 0
                TotalAdmlFiles = 0
                AdmxToUpdate = @()
                AdmlToUpdate = @()
                AdmxUpToDate = @()
                AdmlUpToDate = @()
                Errors = @($_.Exception.Message)
            }
            Summary = [PSCustomObject]@{
                TotalFiles = 0
                FilesToUpdate = 0
                FilesUpToDate = 0
                Errors = 1
                RequiresUpdate = $false
            }
            Domain = $null
            AdmlLanguage = $AdmlLanguage
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}