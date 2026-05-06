function Copy-TierModelAdmx {
    <#
    .SYNOPSIS
    Deploy ADMX/ADML template files to SYSVOL with hash verification.
    
    .DESCRIPTION
    Copies ADMX/ADML files from source to SYSVOL PolicyDefinitions directory,
    creating necessary directories and performing MD5 hash verification after copy.
    Only copies files that need updating based on hash comparison.
    
    .PARAMETER Config
    TierModel configuration object containing ADMX definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations and SYSVOL access.
    
    .PARAMETER AdmlLanguage
    Language code for ADML files (defaults to 'en-US').
    
    .PARAMETER Analysis
    Optional pre-computed analysis from Get-TierModelAdmx to avoid re-analysis.
    
    .EXAMPLE
    Copy-TierModelAdmx -Config $config -DomainController "DC01" -AdmlLanguage "en-US"
    
    .EXAMPLE
    $analysis = Get-TierModelAdmx -Config $config -DomainController "DC01"
    Copy-TierModelAdmx -Config $config -DomainController "DC01" -Analysis $analysis.Analysis
    
    .OUTPUTS
    PSCustomObject with deployment results including success/failure counts and details.
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
        [object]$Analysis
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "ADMX deployment start" -Data @{
        DomainController = $DomainController
        AdmlLanguage = $AdmlLanguage
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Get analysis if not provided
        if (-not $Analysis) {
            Write-Host "Analyzing ADMX/ADML files for deployment..." -ForegroundColor Cyan
            $analysisResult = Get-TierModelAdmx -Config $Config -DomainController $DomainController -AdmlLanguage $AdmlLanguage
            $Analysis = $analysisResult.Analysis
        }
        
        $deploymentResult = @{
            AdmxSuccessful = @()
            AdmlSuccessful = @()
            AdmxFailed = @()
            AdmlFailed = @()
            AdmxSkipped = @()
            AdmlSkipped = @()
        }
        
        # Check for errors in analysis
        if ($Analysis.Errors.Count -gt 0) {
            Write-Host "Analysis errors detected:" -ForegroundColor Red
            foreach ($analysisError in $Analysis.Errors) {
                Write-Host "  ❌ $analysisError" -ForegroundColor Red
            }
            throw "Cannot proceed with deployment due to analysis errors"
        }
        
        # Deploy ADMX files that need updates
        if ($Analysis.AdmxToUpdate.Count -gt 0) {
            Write-Host "Deploying ADMX files..." -ForegroundColor Cyan
            
            # Create all required directories first to avoid mixed messaging
            $requiredDirs = @()
            foreach ($fileInfo in $Analysis.AdmxToUpdate) {
                $destinationDir = Split-Path $fileInfo.DestinationPath -Parent
                if (-not (Test-Path $destinationDir) -and $requiredDirs -notcontains $destinationDir) {
                    $requiredDirs += $destinationDir
                }
            }
            foreach ($dir in $requiredDirs) {
                Write-Host "✅ Created ADMX directory: $dir" -ForegroundColor Green
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            
            foreach ($fileInfo in $Analysis.AdmxToUpdate) {
                try {
                    # Validate source file exists
                    if (-not (Test-Path $fileInfo.SourcePath)) {
                        throw "Source file not found: $($fileInfo.SourcePath)"
                    }
                    
                    # Copy file with hash verification
                    Copy-Item -Path $fileInfo.SourcePath -Destination $fileInfo.DestinationPath -Force
                    
                    # Verify the copy
                    $newHash = (Get-FileHash -Path $fileInfo.DestinationPath -Algorithm MD5).Hash
                    if ($newHash -eq $fileInfo.ExpectedHash) {
                        Write-Host "  ✅ ADMX deployed: $($fileInfo.Name)" -ForegroundColor Green
                        Write-TierModelLog -Level Info -Message "ADMX file deployed successfully" -Data @{
                            FileName = $fileInfo.Name
                            ActionType = $fileInfo.ActionType
                            Hash = $newHash
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        $deploymentResult.AdmxSuccessful += $fileInfo
                    } else {
                        throw "Hash verification failed after copy. Expected: $($fileInfo.ExpectedHash), Actual: $newHash"
                    }
                    
                } catch {
                    Write-Host "  ❌ Failed to deploy ADMX: $($fileInfo.Name) - $($_.Exception.Message)" -ForegroundColor Red
                    Write-TierModelLog -Level Error -Message "ADMX file deployment failed" -Data @{ 
                        FileName = $fileInfo.Name
                        Error = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    $deploymentResult.AdmxFailed += [PSCustomObject]@{
                        FileInfo = $fileInfo
                        Error = $_.Exception.Message
                    }
                }
            }
        } else {
            Write-Host "  All ADMX files are up to date" -ForegroundColor Green
            $deploymentResult.AdmxSkipped = $Analysis.AdmxUpToDate
        }
        
        # Deploy ADML files that need updates
        if ($Analysis.AdmlToUpdate.Count -gt 0) {
            Write-Host "Deploying ADML files ($AdmlLanguage)..." -ForegroundColor Cyan
            
            # Create all required language directories first to avoid mixed messaging
            $requiredLangDirs = @()
            foreach ($fileInfo in $Analysis.AdmlToUpdate) {
                $destinationDir = Split-Path $fileInfo.DestinationPath -Parent
                if (-not (Test-Path $destinationDir) -and $requiredLangDirs -notcontains $destinationDir) {
                    $requiredLangDirs += $destinationDir
                }
            }
            foreach ($dir in $requiredLangDirs) {
                Write-Host "✅ Created ADML language directory: $dir" -ForegroundColor Green
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            
            foreach ($fileInfo in $Analysis.AdmlToUpdate) {
                try {
                    # Validate source file exists
                    if (-not (Test-Path $fileInfo.SourcePath)) {
                        throw "Source file not found: $($fileInfo.SourcePath)"
                    }
                    
                    # Copy file with hash verification
                    Copy-Item -Path $fileInfo.SourcePath -Destination $fileInfo.DestinationPath -Force
                    
                    # Verify the copy
                    $newHash = (Get-FileHash -Path $fileInfo.DestinationPath -Algorithm MD5).Hash
                    if ($newHash -eq $fileInfo.ExpectedHash) {
                        Write-Host "  ✅ ADML deployed: $($fileInfo.Name)" -ForegroundColor Green
                        Write-TierModelLog -Level Info -Message "ADML file deployed successfully" -Data @{
                            FileName = $fileInfo.Name
                            Language = $AdmlLanguage
                            ActionType = $fileInfo.ActionType
                            Hash = $newHash
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        $deploymentResult.AdmlSuccessful += $fileInfo
                    } else {
                        throw "Hash verification failed after copy. Expected: $($fileInfo.ExpectedHash), Actual: $newHash"
                    }
                    
                } catch {
                    Write-Host "  ❌ Failed to deploy ADML: $($fileInfo.Name) - $($_.Exception.Message)" -ForegroundColor Red
                    Write-TierModelLog -Level Error -Message "ADML file deployment failed" -Data @{ 
                        FileName = $fileInfo.Name
                        Error = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    $deploymentResult.AdmlFailed += [PSCustomObject]@{
                        FileInfo = $fileInfo
                        Error = $_.Exception.Message
                    }
                }
            }
        } else {
            Write-Host "  All ADML files ($AdmlLanguage) are up to date" -ForegroundColor Green
            $deploymentResult.AdmlSkipped = $Analysis.AdmlUpToDate
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        $totalSuccessful = $deploymentResult.AdmxSuccessful.Count + $deploymentResult.AdmlSuccessful.Count
        $totalFailed = $deploymentResult.AdmxFailed.Count + $deploymentResult.AdmlFailed.Count
        $totalSkipped = $deploymentResult.AdmxSkipped.Count + $deploymentResult.AdmlSkipped.Count
        
        Write-TierModelLog -Level Info -Message "ADMX deployment completed" -Data @{
            TotalSuccessful = $totalSuccessful
            TotalFailed = $totalFailed
            TotalSkipped = $totalSkipped
            AdmxSuccessful = $deploymentResult.AdmxSuccessful.Count
            AdmlSuccessful = $deploymentResult.AdmlSuccessful.Count
            AdmxFailed = $deploymentResult.AdmxFailed.Count
            AdmlFailed = $deploymentResult.AdmlFailed.Count
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        # Summary will be displayed by caller
        
        return [PSCustomObject]@{
            Results = $deploymentResult
            Summary = [PSCustomObject]@{
                TotalFiles = ($totalSuccessful + $totalFailed + $totalSkipped)
                Successful = $totalSuccessful
                Failed = $totalFailed
                Skipped = $totalSkipped
                Success = ($totalFailed -eq 0)
            }
            AdmlLanguage = $AdmlLanguage
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "ADMX deployment failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Results = @{
                AdmxSuccessful = @()
                AdmlSuccessful = @()
                AdmxFailed = @()
                AdmlFailed = @()
                AdmxSkipped = @()
                AdmlSkipped = @()
            }
            Summary = [PSCustomObject]@{
                TotalFiles = 0
                Successful = 0
                Failed = 1
                Skipped = 0
                Success = $false
            }
            AdmlLanguage = $AdmlLanguage
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}