function Get-TierModelGpoExistenceState {
    <#
    .SYNOPSIS
    Internal helper. Classifies whether a Test-TierModelGpo result means the GPO is absent from AD.

    .DESCRIPTION
    Returns 'Found', 'NotFound', 'Ambiguous' or 'Unknown'. Prefers the explicit ExistenceState
    emitted by Test-TierModelGpo and falls back to inspecting the 'GPO Existence' check record so
    that older or substituted result shapes are still classified rather than silently counted as
    present.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$GpoTestResult
    )

    if (-not $GpoTestResult) { return 'Unknown' }

    $props = @($GpoTestResult.PSObject.Properties.Name)

    if ($props -contains 'ExistenceState' -and -not [string]::IsNullOrWhiteSpace([string]$GpoTestResult.ExistenceState)) {
        return [string]$GpoTestResult.ExistenceState
    }

    if ($props -contains 'Exists' -and $null -ne $GpoTestResult.Exists) {
        return $(if ([bool]$GpoTestResult.Exists) { 'Found' } else { 'NotFound' })
    }

    $existenceChecks = @()
    if ($props -contains 'Checks' -and $GpoTestResult.Checks) {
        $existenceChecks = @($GpoTestResult.Checks | Where-Object { $_ -and $_.Check -eq 'GPO Existence' })
    }
    if ($existenceChecks.Count -eq 0) { return 'Unknown' }
    if (@($existenceChecks | Where-Object { $_.Status -eq 'Fail' }).Count -gt 0) { return 'NotFound' }
    if (@($existenceChecks | Where-Object { $_.Status -eq 'Error' }).Count -gt 0) { return 'Unknown' }

    return 'Found'
}

function Get-TierModelGpoDeliveryIssue {
    <#
    .SYNOPSIS
    Internal helper. Returns ADVISORY notes explaining why a present GPO would deliver no settings.

    .DESCRIPTION
    Detect-and-report only, and deliberately never a compliance finding. Both of the states it
    describes - a GPO with its settings disabled, and a disabled OU link - are supported
    customer choices (for example choosing the SHF baseline over the Microsoft SCT baseline,
    or leaving a baseline GPO linked but link-disabled). The caller must treat the returned
    strings as information for the operator, not as issues, and must not let them affect the
    Pass/Fail verdict or the issue totals.

    The link note is suppressed when the configuration itself expects the link to be disabled,
    since in that case there is nothing to tell the operator.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$GpoTestResult,

        [Parameter()]
        [object]$LinkTestResult,

        [Parameter()]
        [string]$TargetOU,

        [Parameter()]
        [bool]$ExpectedLinkEnabled = $true
    )

    $reasons = @()

    if ($GpoTestResult) {
        $gpoProps = @($GpoTestResult.PSObject.Properties.Name)
        if ($gpoProps -contains 'SettingsDisabled' -and $GpoTestResult.SettingsDisabled) {
            $observed = if ($gpoProps -contains 'GpoStatus' -and $GpoTestResult.GpoStatus) { $GpoTestResult.GpoStatus } else { 'AllSettingsDisabled' }
            $reasons += "GPO settings are disabled (GpoStatus: $observed) - the GPO delivers no configuration"
        }
    }

    if ($LinkTestResult -and $ExpectedLinkEnabled) {
        $linkProps = @($LinkTestResult.PSObject.Properties.Name)
        if (($linkProps -contains 'LinkExists') -and $LinkTestResult.LinkExists -and
            ($linkProps -contains 'CurrentEnabled') -and ($LinkTestResult.CurrentEnabled -eq $false)) {
            $reasons += "GPO link to '$TargetOU' is disabled - no settings are applied to that OU"
        }
    }

    return $reasons
}

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
                    MissingGpos = 0
                    NotDeliveringSettings = 0
                    ConfigurationMismatches = 0
                    Errors = 0
                    AuditErrors = 0
                    TotalIssues = 0
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
                        $expectedEnabled = $true
                        $shouldBeLinked = $gpoConfig.PSObject.Properties.Name -contains 'linkOrder'
                        
                        if ($shouldBeLinked) {
                            Write-Host "    Step 2: Checking GPO linking to OU..." -ForegroundColor Gray
                            $expectedEnforced = if ($gpoConfig.PSObject.Properties.Name -contains 'enforced') { $gpoConfig.enforced } else { $false }
                            $expectedEnabled = if ($gpoConfig.PSObject.Properties.Name -contains 'linkEnabled') { $gpoConfig.linkEnabled } else { $true }
                            
                            # Use the actual GPO name that was found (in case it was found via wildcard)
                            $gpoNameForLinking = if ($gpoTest.ActualGPOName) { $gpoTest.ActualGPOName } else { $gpoName }
                            
                            $linkTest = Test-TierModelGPOLink -GPOName $gpoNameForLinking -TargetOU $resolvedOUPath -DomainController $DomainController -ExpectedOrder $gpoConfig.linkOrder -ExpectedEnforced $expectedEnforced -ExpectedEnabled $expectedEnabled
                            
                            if ($linkTest.Status -eq 'Pass') {
                                # Report the OBSERVED link state, not the expected value - printing the
                                # expectation here previously implied a state that had not been verified.
                                $linkProps = @($linkTest.PSObject.Properties.Name)
                                $observedOrder = if (($linkProps -contains 'CurrentOrder') -and $null -ne $linkTest.CurrentOrder) { $linkTest.CurrentOrder } else { $gpoConfig.linkOrder }
                                $observedEnabled = if (($linkProps -contains 'CurrentEnabled') -and $null -ne $linkTest.CurrentEnabled) { $linkTest.CurrentEnabled } else { $expectedEnabled }
                                Write-Host "    ✅ GPO correctly linked with order $observedOrder, enabled=$observedEnabled" -ForegroundColor Green
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
                        
                        # Classify existence and settings-delivery before aggregation so that
                        # "missing" is never inferred from, or merged into, the mismatch bucket.
                        # Delivery notes are ADVISORY - they are not issues and must not affect
                        # the Pass/Fail verdict or the issue totals.
                        $existenceState = Get-TierModelGpoExistenceState -GpoTestResult $gpoTest
                        $deliveryIssues = @(Get-TierModelGpoDeliveryIssue -GpoTestResult $gpoTest -LinkTestResult $linkTest -TargetOU $resolvedOUPath -ExpectedLinkEnabled ([bool]$expectedEnabled) |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

                        if ($existenceState -eq 'NotFound') {
                            Write-Host "    ❌ GPO does not exist in Active Directory: $gpoName" -ForegroundColor Red
                        } elseif ($deliveryIssues.Count -gt 0) {
                            foreach ($reason in $deliveryIssues) {
                                Write-Host "    ℹ Note (not a finding): $reason" -ForegroundColor Gray
                            }
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
                            ExistenceState = $existenceState
                            IsMissing = ($existenceState -eq 'NotFound')
                            DeliversSettings = ($existenceState -eq 'Found' -and $deliveryIssues.Count -eq 0)
                            DeliveryNotes = $deliveryIssues
                            DeliveryIssues = $deliveryIssues  # Retained for compatibility; advisory only
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
                        
                        # NOTE: settings-delivery notes are deliberately NOT appended to
                        # $combinedResult.Issues. A disabled GPO or a disabled link is a
                        # supported customer choice, so it must not read as a finding.
                        
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
        
        # Create findings for failed/error GPOs only. GPOs that pass their configured checks
        # but deliver no settings are NOT findings - that state is a supported customer choice
        # and is surfaced informationally (Summary.NotDeliveringSettings and the per-result
        # DeliveryNotes property) instead.
        $findings = @()
        foreach ($result in $auditResults) {
            if ($result.OverallStatus -ne 'Pass') {
                $issueType = if ($result.IsMissing) {
                    'Missing'
                } else {
                    switch ($result.OverallStatus) {
                        'Error' { 'Error' }
                        'Fail' { 'Mismatch' }
                        default { 'Unknown' }
                    }
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
        
        # Real, mutually exclusive FAILURE counts: Missing -> Error -> Mismatch. Nothing is
        # double counted and no figure is a hardcoded literal or derived by subtraction.
        $missingGpoCount = @($auditResults | Where-Object { $_.IsMissing }).Count
        $gpoErrorCount = @($auditResults | Where-Object {
            -not $_.IsMissing -and $_.OverallStatus -eq 'Error'
        }).Count
        $mismatchCount = @($auditResults | Where-Object {
            -not $_.IsMissing -and $_.OverallStatus -ne 'Error' -and $_.OverallStatus -eq 'Fail'
        }).Count
        # INFORMATIONAL, and deliberately outside the failure buckets: a GPO can legitimately
        # have its settings disabled or its link disabled (for example when a customer uses the
        # SHF baseline instead of the Microsoft SCT baseline). This count overlaps the buckets
        # above by design and is NEVER added to the issue total or used to set Overall Status.
        $disabledGpoCount = @($auditResults | Where-Object { -not $_.IsMissing -and @($_.DeliveryNotes).Count -gt 0 }).Count
        # $errors holds GPOs that threw before a result object could be produced - they are not
        # represented in $auditResults, so they are added rather than merged.
        $auditErrorCount = $gpoErrorCount + $errors.Count
        $totalIssueCount = $missingGpoCount + $auditErrorCount + $mismatchCount
        
        # Display audit summary (blue header section)
        if (-not $Silent) {
            Write-Host "`n=== GPO Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total GPOs Checked: $totalChecked" -ForegroundColor White
            if ($missingGpoCount -eq 0) {
                Write-Host "Missing GPOs: $missingGpoCount ✅" -ForegroundColor Green
            } else {
                Write-Host "Missing GPOs: $missingGpoCount ❌" -ForegroundColor Red
            }
            if ($disabledGpoCount -gt 0) {
                Write-Host "Present but Delivering No Settings (informational, not a finding): $disabledGpoCount ℹ" -ForegroundColor Gray
            }
            if ($mismatchCount -eq 0) {
                Write-Host "Configuration Mismatches (existing GPOs): $mismatchCount ✅" -ForegroundColor Green
            } else {
                Write-Host "Configuration Mismatches (existing GPOs): $mismatchCount ❌" -ForegroundColor Red
            }
            if ($auditErrorCount -eq 0) {
                Write-Host "Audit Errors: $auditErrorCount ✅" -ForegroundColor Green
            } else {
                Write-Host "Audit Errors: $auditErrorCount ❌" -ForegroundColor Red
            }
            if ($totalIssueCount -eq 0) {
                Write-Host "Overall Status: All GPOs are compliant ✅" -ForegroundColor Green
            } else {
                Write-Host "Overall Status: $totalIssueCount issues found ❌" -ForegroundColor Red
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
                MissingGpos = $missingGpoCount
                NotDeliveringSettings = $disabledGpoCount
                ConfigurationMismatches = $mismatchCount
                Errors = $errors.Count
                AuditErrors = $auditErrorCount
                TotalIssues = $totalIssueCount
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