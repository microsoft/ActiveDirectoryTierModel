function Test-TierModelGPOAudit {
    <#
    .SYNOPSIS
    Comprehensive TierModel GPO deployment audit across entire configuration.
    
    .DESCRIPTION
    Performs comprehensive auditing of all GPOs in the TierModel configuration,
    validating existence, settings, links, and inheritance status across all OUs.
    This function orchestrates individual GPO and GPO link tests for complete
    configuration validation.
    
    .PARAMETER Config
    TierModel configuration object containing GPO definitions and requirements.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER OUPath
    Optional specific OU path to audit. If not specified, audits all configured GPOs.
    
    .EXAMPLE
    Test-TierModelGPOAudit -Config $config -DomainController "DC01"
    
    .EXAMPLE
    Test-TierModelGPOAudit -Config $config -DomainController "DC01" -OUPath "OU=Tier0,DC=domain,DC=com"
    
    .OUTPUTS
    PSCustomObject with comprehensive audit results including compliance status and detailed findings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$Silent,
        
        [Parameter()]
        [string]$OUPath
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "GPO comprehensive audit start" -Data @{
        DomainController = $DomainController
        OUPath = $OUPath
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Get current domain DN for placeholder resolution
        $domain = Get-ADDomain -Server $DomainController
        $domainDN = $domain.DistinguishedName
        
        $auditResults = @()
        $errors = @()
        $totalChecked = 0
        $totalPassed = 0
        $totalFailed = 0
        $converged = $true
        
        # Check if GPOs config exists and has properties
        if (-not $Config.gpos -or -not $Config.gpos.PSObject.Properties) {
            Write-TierModelLog -Level Warn -Message "No GPO configuration found" -Data @{ CorrelationId = $CorrelationId } | Out-Null
            Write-Host "No GPO configuration found or GPO configuration is empty" -ForegroundColor Yellow
            
            return [PSCustomObject]@{
                Results = @()
                Summary = [PSCustomObject]@{
                    TotalGpos = 0
                    Compliant = 0
                    Drift = 0
                    Errors = 0
                    CompliancePercentage = 100
                }
                Findings = @()
                Errors = @()
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                Converged = $true
                CorrelationId = $CorrelationId
            }
        }
        
        # Process each OU section in the configuration
        foreach ($ouSection in $Config.gpos.PSObject.Properties) {
            $rawOUPath = $ouSection.Name
            $ouGpoData = $ouSection.Value
            
            # Resolve domain DN placeholder in OU path
            $resolvedOUPath = Resolve-TierModelPlaceholder -Path $rawOUPath -DomainDN $domainDN
            
            # Skip if specific OU path is specified and this doesn't match
            if ($OUPath -and $resolvedOUPath -ne $OUPath) {
                continue
            }
            Write-Host "Auditing GPOs for OU: $resolvedOUPath" -ForegroundColor Cyan
            
            # Process GPOs in different categories
            $gpoCategories = @(
                @{ Name = 'ImportOnlyGpo'; GPOs = $ouGpoData.ImportOnlyGpo },
                @{ Name = 'PostConfigureGpo'; GPOs = $ouGpoData.PostConfigureGpo }
            )
            
            foreach ($category in $gpoCategories) {
                if (-not $category.GPOs -or $category.GPOs.Count -eq 0) { continue }
                
                foreach ($gpoRef in $category.GPOs) {
                    try {
                        $totalChecked++
                        
                        # GPO reference is the GPO config object itself
                        $gpoConfig = $gpoRef
                        $gpoName = $gpoConfig.name
                        Write-Host "  Auditing GPO: $gpoName ($($category.Name))" -ForegroundColor Cyan
                        
                        # Step 1: Test if GPO exists and has correct status
                        Write-Host "    Step 1: Checking GPO existence and status..." -ForegroundColor Gray
                        $gpoTest = Test-TierModelGpo -GPOName $gpoName -GPOConfig $gpoConfig -DomainController $DomainController
                        
                        if ($gpoTest.Status -eq 'Pass') {
                            Write-Host "    ✅ GPO exists with correct status" -ForegroundColor Green
                        } else {
                            Write-Host "    ✗ GPO existence/status check failed: $($gpoTest.Issues -join '; ')" -ForegroundColor Red
                        }
                        
                        # Step 2: Test GPO linking (only if GPO should be linked - has linkOrder)
                        $linkTest = $null
                        $shouldBeLinked = $gpoConfig.PSObject.Properties.Name -contains 'linkOrder'
                        
                        if ($shouldBeLinked) {
                            Write-Host "    Step 2: Checking GPO linking to OU..." -ForegroundColor Gray
                            $expectedEnforced = if ($gpoConfig.PSObject.Properties.Name -contains 'enforced') { $gpoConfig.enforced } else { $false }
                            $expectedEnabled = if ($gpoConfig.PSObject.Properties.Name -contains 'linkEnabled') { $gpoConfig.linkEnabled } else { $true }
                            
                            # Use the actual GPO name that was found (in case it was found via wildcard)
                            $gpoNameForLinking = if ($gpoTest.ActualGPOName) { $gpoTest.ActualGPOName } else { $gpoName }
                            
                            $linkTest = Test-TierModelGPOLink -GPOName $gpoNameForLinking -TargetOU $resolvedOUPath -DomainController $DomainController -ExpectedOrder $gpoConfig.linkOrder -ExpectedEnforced $expectedEnforced -ExpectedEnabled $expectedEnabled
                            
                            if ($linkTest.Status -eq 'Pass') {
                                Write-Host "    ✅ GPO correctly linked with order $($gpoConfig.linkOrder), enabled=$expectedEnabled" -ForegroundColor Green
                            } else {
                                Write-Host "    ✗ GPO linking check failed: $($linkTest.Issues -join '; ')" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "    Step 2: Skipping link check - Template GPO (not linked to OUs)" -ForegroundColor Gray
                        }
                        
                        # Step 3: Test GPO content validation for PostConfigureGpo (mock file comparison)
                        $contentTest = $null
                        $hasContentToValidate = ($category.Name -eq 'PostConfigureGpo' -and ($gpoConfig.PSObject.Properties.Name -contains 'userRightsAssignments' -or $gpoConfig.PSObject.Properties.Name -contains 'restrictedGroups'))
                        
                        if ($hasContentToValidate) {
                            Write-Host "    Step 3: Validating GPO content against mock files..." -ForegroundColor Gray
                            $contentTest = Test-TierModelGPOContent -GPOName $gpoName -GPOConfig $gpoConfig -DomainController $DomainController
                            
                            if ($contentTest.Status -eq 'Pass') {
                                Write-Host "    ✅ GPO content matches expected configuration" -ForegroundColor Green
                            } else {
                                Write-Host "    ✗ GPO content validation failed: $($contentTest.Issues -join '; ')" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "    Step 3: Skipping content validation - No mock content configured" -ForegroundColor Gray
                        }
                        
                        # Combine results
                        $actualGpoName = if ($gpoTest.ActualGPOName) { $gpoTest.ActualGPOName } else { $gpoName }
                        $combinedResult = [PSCustomObject]@{
                            GPOName = $actualGpoName  # Use the actual found GPO name
                            OriginalGPOName = $gpoName  # Keep track of the original JSON name
                            Category = $category.Name
                            OUPath = $resolvedOUPath
                            GPOTest = $gpoTest
                            LinkTest = $linkTest
                            ContentTest = $contentTest
                            OverallStatus = 'Unknown'
                            Issues = @()
                            Recommendations = @()
                        }
                        
                        # Aggregate issues and recommendations (handle null test results)
                        if ($gpoTest -and $gpoTest.Issues) {
                            $combinedResult.Issues += $gpoTest.Issues
                        }
                        if ($gpoTest -and $gpoTest.Recommendations) {
                            $combinedResult.Recommendations += $gpoTest.Recommendations
                        }
                        
                        if ($linkTest -and $linkTest.Issues) {
                            $combinedResult.Issues += $linkTest.Issues
                        }
                        if ($linkTest -and $linkTest.Recommendations) {
                            $combinedResult.Recommendations += $linkTest.Recommendations
                        }
                        
                        if ($contentTest -and $contentTest.Issues) {
                            $combinedResult.Issues += $contentTest.Issues
                        }
                        if ($contentTest -and $contentTest.Recommendations) {
                            $combinedResult.Recommendations += $contentTest.Recommendations
                        }
                        
                        # Determine overall status (handle null test results)
                        $gpoTestPass = ($gpoTest -and $gpoTest.Status -eq 'Pass')
                        $linkTestPass = (-not $linkTest -or $linkTest.Status -eq 'Pass')  # Null linkTest is considered Pass for template GPOs
                        $contentTestPass = (-not $contentTest -or $contentTest.Status -eq 'Pass')  # Null contentTest is considered Pass
                        
                        $gpoTestError = ($gpoTest -and $gpoTest.Status -eq 'Error')
                        $linkTestError = ($linkTest -and $linkTest.Status -eq 'Error')
                        $contentTestError = ($contentTest -and $contentTest.Status -eq 'Error')
                        
                        $allTestsPass = ($gpoTestPass -and $linkTestPass -and $contentTestPass)
                        $anyTestError = ($gpoTestError -or $linkTestError -or $contentTestError)
                        
                        if ($allTestsPass) {
                            $combinedResult.OverallStatus = 'Pass'
                            $totalPassed++
                            Write-Host "    ✅ GPO audit passed: $actualGpoName" -ForegroundColor Green
                        } elseif ($anyTestError) {
                            $combinedResult.OverallStatus = 'Error'
                            $totalFailed++
                            $converged = $false
                            Write-Host "    ⚠ GPO audit error: $actualGpoName" -ForegroundColor Red
                        } else {
                            $combinedResult.OverallStatus = 'Fail'
                            $totalFailed++
                            $converged = $false
                            Write-Host "    ✗ GPO audit failed: $actualGpoName" -ForegroundColor Red
                        }
                        
                        $auditResults += $combinedResult
                        
                    } catch {
                        $gpoNameForLogging = if ($gpoConfig -and $gpoConfig.name) { $gpoConfig.name } else { "Unknown GPO" }
                        
                        Write-TierModelLog -Level Error -Message "Failed to audit GPO" -Data @{
                            GPOName = $gpoNameForLogging
                            OUPath = $resolvedOUPath
                            Exception = $_.Exception.Message
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        Write-Host "    ERROR: Failed to audit GPO '$gpoNameForLogging' - $($_.Exception.Message)" -ForegroundColor Red
                        
                        $errors += @{
                            Timestamp = Get-Date
                            Category = 'Audit'
                            Code = 'GPOAuditFailed'
                            Message = $_.Exception.Message
                            Context = @{
                                GPOName = $gpoNameForLogging
                                OUPath = $resolvedOUPath
                            }
                        }
                        
                        $totalFailed++
                        $converged = $false
                    }
                }
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "GPO comprehensive audit complete" -Data @{
            TotalChecked = $totalChecked
            TotalPassed = $totalPassed
            TotalFailed = $totalFailed
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        # Create findings for failed/error GPOs only (matches expected structure)
        $findings = @()
        foreach ($result in $auditResults) {
            if ($result.OverallStatus -ne 'Pass') {
                $issueType = switch ($result.OverallStatus) {
                    'Error' { 'Error' }
                    'Fail' { 'Mismatch' }
                    default { 'Unknown' }
                }
                
                $issueDetails = @()
                if ($result.Issues -and $result.Issues.Count -gt 0) {
                    $issueDetails += $result.Issues
                } else {
                    $issueDetails += "Audit failed with status: $($result.OverallStatus)"
                }
                
                $findings += [PSCustomObject]@{
                    Type = $issueType
                    GpoName = $result.GPOName
                    Message = $issueDetails -join '; '
                }
            }
        }
        
        # Display audit summary (blue header section)
        $driftCount = $totalFailed + $errors.Count
        if (-not $Silent) {
            Write-Host "`n=== GPO Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total GPOs Checked: $totalChecked" -ForegroundColor White
            if ($driftCount -eq 0) {
                Write-Host "Missing GPOs: 0 ✅" -ForegroundColor Green
            } else {
                Write-Host "Missing GPOs: 0 ❌" -ForegroundColor Red
            }
            if ($driftCount -eq 0) {
                Write-Host "Configuration Mismatches: 0 ✅" -ForegroundColor Green
            } else {
                Write-Host "Configuration Mismatches: $driftCount ❌" -ForegroundColor Red
            }
            if ($driftCount -eq 0) {
                Write-Host "Overall Status: All GPOs are compliant ✅" -ForegroundColor Green
            } else {
                Write-Host "Overall Status: $driftCount issues found ❌" -ForegroundColor Red
            }
        }
        
        # Clean up temp directory if it's empty (all mock files were deleted due to successful validations)
        try {
            $basePath = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent  # Up to TierModel parent folder
            $tempDir = Join-Path $basePath 'Temp'
            if ((Test-Path $tempDir)) {
                $remainingItems = @(Get-ChildItem $tempDir -Force -ErrorAction SilentlyContinue)  # Ensure array, include hidden files/folders
                if ($remainingItems.Count -eq 0) {
                    Remove-Item $tempDir -Force -ErrorAction SilentlyContinue
                    Write-Host "    🗑️  Cleaned up empty temp directory" -ForegroundColor Gray
                } else {
                    Write-Host "    📁 Temp directory contains $($remainingItems.Count) items - keeping for debugging" -ForegroundColor Yellow
                }
            }
        } catch {
            # Ignore cleanup errors - not critical
            Write-Host "    ⚠️  Could not clean up temp directory: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        return [PSCustomObject]@{
            Results = $auditResults
            Summary = [PSCustomObject]@{
                TotalGpos = $totalChecked
                Compliant = $totalPassed
                Drift = $totalFailed
                Errors = $errors.Count
                CompliancePercentage = if ($totalChecked -gt 0) { [math]::Round(($totalPassed / $totalChecked) * 100, 2) } else { 100 }
            }
            Findings = $findings
            Errors = $errors
            DurationMs = $durationMs
            Converged = $converged
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "GPO comprehensive audit failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Results = @()
            Summary = @{
                TotalChecked = 0
                TotalPassed = 0
                TotalFailed = 1
                PassRate = 0
            }
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'GPOAuditFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}