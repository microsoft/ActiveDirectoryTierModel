function Test-TierModelAdmx {
    <#
    .SYNOPSIS
    Audit ADMX/ADML template compliance in SYSVOL using hash verification.
    
    .DESCRIPTION
    Performs compliance auditing of ADMX/ADML files in SYSVOL PolicyDefinitions
    directory by checking file existence and MD5 hash verification against
    expected configuration values.
    
    .PARAMETER Config
    TierModel configuration object containing ADMX definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations and SYSVOL access.
    
    .PARAMETER AdmlLanguage
    Language code for ADML files (defaults to 'en-US').
    
    .EXAMPLE
    Test-TierModelAdmx -Config $config -DomainController "DC01" -AdmlLanguage "en-US"
    
    .OUTPUTS
    PSCustomObject with audit results including compliance status and detailed findings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$Silent,
        
        [Parameter()]
        [string]$AdmlLanguage = 'en-US'
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "ADMX audit start" -Data @{
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
        
        # Get destination paths - use PreferredDc for UNC path, domain for SYSVOL directory
        $admxDestinationPath = $admxConfig.admx.destinationPath -replace '\\\\{{DOMAIN_FQDN}}\\SYSVOL\\{{DOMAIN_FQDN}}\\', "\\$DomainController\SYSVOL\$($domain.ToUpper())\"
        $admlDestinationPath = $admlConfig.adml.destinationPath -replace '\\\\{{DOMAIN_FQDN}}\\SYSVOL\\{{DOMAIN_FQDN}}\\', "\\$DomainController\SYSVOL\$($domain.ToUpper())\"
        
        $auditResults = @()
        $findings = @()
        $totalChecked = 0
        $totalPassed = 0
        $totalFailed = 0
        $converged = $true
        
        # Audit ADMX files
        Write-Host "Auditing ADMX files..." -ForegroundColor Cyan
        foreach ($admxFile in $admxConfig.admx.files.PSObject.Properties) {
            $fileName = $admxFile.Name
            $expectedHash = $admxFile.Value.hash
            $destinationFilePath = Join-Path $admxDestinationPath $fileName
            
            $totalChecked++
            
            $result = [PSCustomObject]@{
                Type = 'ADMX'
                FileName = $fileName
                ExpectedHash = $expectedHash
                ActualHash = $null
                Path = $destinationFilePath
                Status = 'Unknown'
                Issues = @()
                Exists = $false
            }
            
            # Check if file exists
            if (-not (Test-Path $destinationFilePath)) {
                $result.Status = 'Missing'
                $result.Issues += "ADMX file not found in SYSVOL"
                $totalFailed++
                $converged = $false
                
                Write-Host "  ❌ Missing ADMX: $fileName" -ForegroundColor Red
                
                $findings += [PSCustomObject]@{
                    Type = 'Missing'
                    ResourceType = 'ADMX'
                    FileName = $fileName
                    Message = "ADMX file not found in SYSVOL: $destinationFilePath"
                }
            } else {
                $result.Exists = $true
                
                # Check hash
                $actualHash = (Get-FileHash -Path $destinationFilePath -Algorithm MD5).Hash
                $result.ActualHash = $actualHash
                
                if ($actualHash -eq $expectedHash) {
                    $result.Status = 'Pass'
                    $totalPassed++
                    Write-Host "  ✅ ADMX OK: $fileName" -ForegroundColor Green
                } else {
                    $result.Status = 'Mismatch'
                    $result.Issues += "Hash mismatch - file content differs from expected"
                    $totalFailed++
                    $converged = $false
                    
                    Write-Host "  ❌ ADMX Hash Mismatch: $fileName" -ForegroundColor Red
                    
                    $findings += [PSCustomObject]@{
                        Type = 'Mismatch'
                        ResourceType = 'ADMX'
                        FileName = $fileName
                        Message = "ADMX file hash does not match expected value (Expected: $expectedHash, Actual: $actualHash)"
                    }
                }
            }
            
            $auditResults += $result
        }
        
        # Audit ADML files
        Write-Host "Auditing ADML files ($AdmlLanguage)..." -ForegroundColor Cyan
        foreach ($admlFile in $admlConfig.adml.files.PSObject.Properties) {
            $fileName = $admlFile.Name
            $expectedHash = $admlFile.Value.hash
            $destinationFilePath = Join-Path $admlDestinationPath $fileName
            
            $totalChecked++
            
            $result = [PSCustomObject]@{
                Type = 'ADML'
                FileName = $fileName
                ExpectedHash = $expectedHash
                ActualHash = $null
                Path = $destinationFilePath
                Language = $AdmlLanguage
                Status = 'Unknown'
                Issues = @()
                Exists = $false
            }
            
            # Check if file exists
            if (-not (Test-Path $destinationFilePath)) {
                $result.Status = 'Missing'
                $result.Issues += "ADML file not found in SYSVOL"
                $totalFailed++
                $converged = $false
                
                Write-Host "  ❌ Missing ADML: $fileName" -ForegroundColor Red
                
                $findings += [PSCustomObject]@{
                    Type = 'Missing'
                    ResourceType = 'ADML'
                    FileName = $fileName
                    Message = "ADML file not found in SYSVOL: $destinationFilePath"
                }
            } else {
                $result.Exists = $true
                
                # Check hash
                $actualHash = (Get-FileHash -Path $destinationFilePath -Algorithm MD5).Hash
                $result.ActualHash = $actualHash
                
                if ($actualHash -eq $expectedHash) {
                    $result.Status = 'Pass'
                    $totalPassed++
                    Write-Host "  ✅ ADML OK: $fileName" -ForegroundColor Green
                } else {
                    $result.Status = 'Mismatch'
                    $result.Issues += "Hash mismatch - file content differs from expected"
                    $totalFailed++
                    $converged = $false
                    
                    Write-Host "  ❌ ADML Hash Mismatch: $fileName" -ForegroundColor Red
                    
                    $findings += [PSCustomObject]@{
                        Type = 'Mismatch'
                        ResourceType = 'ADML'
                        FileName = $fileName
                        Message = "ADML file hash does not match expected value (Expected: $expectedHash, Actual: $actualHash)"
                    }
                }
            }
            
            $auditResults += $result
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        # Display audit summary (blue header section)
        $driftCount = $totalFailed
        if (-not $Silent) {
            Write-Host "`n=== ADMX Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total ADMX Files Checked: $totalChecked" -ForegroundColor White
            if ($driftCount -eq 0) {
                Write-Host "Missing ADMX Files: 0 ✅" -ForegroundColor Green
            } else {
                Write-Host "Missing ADMX Files: 0 ❌" -ForegroundColor Red
            }
            if ($driftCount -eq 0) {
                Write-Host "Configuration Mismatches: 0 ✅" -ForegroundColor Green
            } else {
                Write-Host "Configuration Mismatches: $driftCount ❌" -ForegroundColor Red
            }
            Write-Host "" # Blank line for spacing before Overall Status
            if ($driftCount -eq 0) {
                Write-Host "Overall Status: All ADMX Files are compliant ✅" -ForegroundColor Green
            } else {
                Write-Host "Overall Status: $driftCount issues found ❌" -ForegroundColor Red
            }
        }
        
        Write-TierModelLog -Level Info -Message "ADMX audit completed" -Data @{
            TotalChecked = $totalChecked
            TotalPassed = $totalPassed
            TotalFailed = $totalFailed
            AdmlLanguage = $AdmlLanguage
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Results = $auditResults
            Summary = [PSCustomObject]@{
                TotalFiles = $totalChecked
                Compliant = $totalPassed
                Drift = $totalFailed
                Errors = 0
                CompliancePercentage = if ($totalChecked -gt 0) { [math]::Round(($totalPassed / $totalChecked) * 100, 2) } else { 100 }
            }
            Findings = $findings
            Domain = $domain
            AdmlLanguage = $AdmlLanguage
            DurationMs = $durationMs
            Converged = $converged
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "ADMX audit failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Results = @()
            Summary = [PSCustomObject]@{
                TotalFiles = 0
                Compliant = 0
                Drift = 0
                Errors = 1
                CompliancePercentage = 0
            }
            Findings = @([PSCustomObject]@{
                Type = 'Error'
                ResourceType = 'ADMX'
                FileName = 'N/A'
                Message = "ADMX audit failed: $($_.Exception.Message)"
            })
            Domain = $null
            AdmlLanguage = $AdmlLanguage
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}