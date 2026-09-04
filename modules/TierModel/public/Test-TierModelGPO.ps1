function Test-TierModelGpo {
    <#
    .SYNOPSIS
    Test individual TierModel GPO existence and basic configuration.
    
    .DESCRIPTION
    Tests whether a specific GPO exists and matches basic configuration requirements.
    This is a focused test for individual GPO validation, while Test-TierModelGPO
    provides comprehensive multi-GPO auditing across the entire configuration.
    
    .PARAMETER GPOName
    Name of the specific GPO to test.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER GPOConfig
    Optional GPO configuration object to validate against. If not provided, only tests existence.
    
    .EXAMPLE
    Test-TierModelGpo -GPOName "Tier0-Security" -DomainController "DC01"
    
    .EXAMPLE
    Test-TierModelGpo -GPOName "Tier0-Security" -GPOConfig $gpoConfig -DomainController "DC01"
    
    .OUTPUTS
    PSCustomObject with test results including existence and configuration status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GPOName,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [Parameter()]
        [object]$GPOConfig
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "GPO test start" -Data @{
        GPOName = $GPOName
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $testResult = [PSCustomObject]@{
            GPOName = $GPOName
            ActualGPOName = $GPOName  # Will be updated if found via wildcard
            Exists = $false           # $true only when a single GPO object was resolved in AD
            ExistenceState = 'Unknown' # Found | NotFound | Ambiguous | Unknown
            GpoStatus = $null         # Reported GpoStatus (AllSettingsEnabled / ... / AllSettingsDisabled)
            SettingsDisabled = $false # $true when the GPO delivers no settings at all
            Checks = @()
            Status = 'Unknown'
            Issues = @()
            Recommendations = @()
        }
        # Check 1: GPO Exists
        $gpoExists = $false
        $gpoObject = $null
        $actualGpoName = $GPOName
        try {
            # Try exact name match first
            $gpoObject = Get-GPO -Name $GPOName -Server $DomainController -ErrorAction Stop
            $gpoExists = $true
            $testResult.Exists = $true
            $testResult.ExistenceState = 'Found'
            
            $testResult.Checks += [PSCustomObject]@{
                Check = 'GPO Existence'
                Status = 'Pass'
                Expected = 'GPO exists'
                Actual = "GPO found (ID: $($gpoObject.Id))"
                Message = 'GPO exists in domain'
            }
            
        } catch {
            # If exact match fails and GPOConfig has rename key, try wildcard match
            if ($GPOConfig -and $GPOConfig.PSObject.Properties.Name -contains 'rename') {
                try {
                    $renamePattern = "$($GPOConfig.rename)*"
                    $allGPOs = Get-GPO -All -Server $DomainController
                    $matchingGPOs = $allGPOs | Where-Object { $_.DisplayName -like $renamePattern }
                    if ($matchingGPOs -and @($matchingGPOs).Count -eq 1) {
                        $gpoObject = $matchingGPOs[0]
                        $actualGpoName = $gpoObject.DisplayName
                        $testResult.ActualGPOName = $actualGpoName  # Update the actual name found
                        $gpoExists = $true
                        $testResult.Exists = $true
                        $testResult.ExistenceState = 'Found'
                        
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Existence'
                            Status = 'Pass'
                            Expected = 'GPO exists (exact or wildcard match)'
                            Actual = "GPO found via wildcard '$renamePattern' (Name: $actualGpoName, ID: $($gpoObject.Id))"
                            Message = 'GPO found using rename wildcard pattern'
                        }
                    } elseif ($matchingGPOs -and @($matchingGPOs).Count -gt 1) {
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Existence'
                            Status = 'Fail'
                            Expected = 'Single GPO match'
                            Actual = "Multiple GPOs found: $($matchingGPOs.DisplayName -join ', ')"
                            Message = "Multiple GPOs match wildcard pattern '$renamePattern'"
                        }
                        $testResult.ExistenceState = 'Ambiguous'
                        $testResult.Issues += "Multiple GPOs found matching rename pattern '$renamePattern': $($matchingGPOs.DisplayName -join ', ')"
                        $testResult.Recommendations += "Ensure only one GPO matches the rename pattern or use exact naming"
                    } else {
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Existence'
                            Status = 'Fail'
                            Expected = 'GPO exists'
                            Actual = 'GPO not found (exact or wildcard)'
                            Message = $_.Exception.Message
                        }
                        $testResult.ExistenceState = 'NotFound'
                        $testResult.Issues += "GPO '$GPOName' does not exist (also tried rename wildcard '$renamePattern')"
                        $testResult.Recommendations += "Create GPO using New-TierModelGpo or check if GPO was renamed"
                    }
                } catch {
                    $testResult.Checks += [PSCustomObject]@{
                        Check = 'GPO Existence'
                        Status = 'Fail'
                        Expected = 'GPO exists'
                        Actual = 'GPO not found'
                        Message = $_.Exception.Message
                    }
                    # Wildcard enumeration itself failed - existence cannot be proven either way
                    $testResult.ExistenceState = 'Unknown'
                    $testResult.Issues += "GPO '$GPOName' does not exist"
                    $testResult.Recommendations += "Create GPO using New-TierModelGpo"
                }
            } else {
                $testResult.Checks += [PSCustomObject]@{
                    Check = 'GPO Existence'
                    Status = 'Fail'
                    Expected = 'GPO exists'
                    Actual = 'GPO not found'
                    Message = $_.Exception.Message
                }
                $testResult.ExistenceState = 'NotFound'
                $testResult.Issues += "GPO '$GPOName' does not exist"
                $testResult.Recommendations += "Create GPO using New-TierModelGpo"
            }
        }
                        
        $observedGpoFlags = $null

        if ($gpoExists -and $GPOConfig) {
            # Check 2: GPO Status Configuration (if provided)
            if ($GPOConfig.PSObject.Properties.Name -contains 'gpoStatus') {
                try {
                    $domain = Get-ADDomain -Server $DomainController
                    $domainDN = $domain.DistinguishedName
                    $gpoADObject = Get-ADObject -Identity "CN={$($gpoObject.Id)},CN=Policies,CN=System,$domainDN" -Properties flags -Server $DomainController
                    $currentFlags = $gpoADObject.flags
                    $observedGpoFlags = $currentFlags
                    
                    # Valid gpoStatus values and their AD 'flags' attribute values.
                    #
                    # ⚠ CRITICAL: these are AD 'flags' attribute values, NOT .NET GpoStatus
                    # enum ordinals. The ordinals are inverted for AllSettingsEnabled (ordinal 3)
                    # and AllSettingsDisabled (ordinal 0) — do NOT "fix" that inversion.
                    # Empirically verified on TierLab-DC01 by Joel Platek, 2026-09-04:
                    #   AllSettingsEnabled       → flags 0
                    #   UserSettingsDisabled     → flags 1
                    #   ComputerSettingsDisabled → flags 2
                    #   AllSettingsDisabled      → flags 3
                    #
                    # Must stay in exact agreement with the deploy lookup in
                    # New-TierModelGpo.ps1. If these tables drift a status deployed as
                    # flags=X will audit as a different value — unresolvable drift because
                    # re-running deploy keeps writing the wrong flags value.
                    #
                    # Exactly 4 real .NET GpoStatus members (BUG-016: AllEnabled and
                    # BothSettingsDisabled were invented and have been removed).
                    $validGpoStatus = [ordered]@{
                        'AllSettingsEnabled'       = 0
                        'UserSettingsDisabled'     = 1
                        'ComputerSettingsDisabled' = 2
                        'AllSettingsDisabled'      = 3
                    }

                    # No silent default: an unrecognised value used to mean "expect AllSettingsEnabled",
                    # so a config typo could be reported as Pass. $null marks it as unrecognised and the
                    # check below fails loudly for this GPO only — deliberately NOT a throw, because
                    # this is the audit path and one bad config value must not abort the whole run.
                    $expectedFlags = if ($validGpoStatus.Contains([string]$GPOConfig.gpoStatus)) {
                        $validGpoStatus[[string]$GPOConfig.gpoStatus]
                    } else {
                        $null
                    }

                    if ($null -eq $expectedFlags) {
                        $validList = ($validGpoStatus.Keys -join ', ')
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Status'
                            Status = 'Fail'
                            Expected = "one of: $validList"
                            Actual = "configured value '$($GPOConfig.gpoStatus)' (observed flags: $currentFlags)"
                            Message = "Unrecognized gpoStatus value '$($GPOConfig.gpoStatus)' - cannot determine expected flags. Valid values: $validList"
                        }

                        $testResult.Issues += "Unrecognized gpoStatus value '$($GPOConfig.gpoStatus)' in configuration for GPO '$GPOName'. Valid values: $validList"
                        $testResult.Recommendations += "Correct the 'gpoStatus' value for GPO '$GPOName' in configuration to one of: $validList"
                    } elseif ($currentFlags -eq $expectedFlags) {
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Status'
                            Status = 'Pass'
                            Expected = "$($GPOConfig.gpoStatus) (flags: $expectedFlags)"
                            Actual = "flags: $currentFlags"
                            Message = 'GPO status is configured correctly'
                        }
                    } else {
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Status'
                            Status = 'Fail'
                            Expected = "$($GPOConfig.gpoStatus) (flags: $expectedFlags)"
                            Actual = "flags: $currentFlags"
                            Message = 'GPO status does not match configuration'
                        }
                        
                        $testResult.Issues += "GPO status mismatch - expected $($GPOConfig.gpoStatus), current flags: $currentFlags"
                        $testResult.Recommendations += "Update GPO status using Set-ADObject"
                    }
                } catch {
                    $testResult.Checks += [PSCustomObject]@{
                        Check = 'GPO Status'
                        Status = 'Error'
                        Expected = $GPOConfig.gpoStatus
                        Actual = 'Unable to check'
                        Message = $_.Exception.Message
                    }
                }
            }
        }
        
        # Check 3: Effective settings-delivery state - INFORMATIONAL ONLY.
        #
        # Runs for every existing GPO, independent of whether 'gpoStatus' is configured.
        # A GPO whose settings are all disabled delivers no configuration, which is worth
        # surfacing because it explains "my setting isn't applying".
        #
        # It is deliberately NEVER a failure. Disabling a GPO's settings is a supported
        # customer choice: e.g. choosing the SHF baseline instead of the Microsoft SCT
        # baseline and disabling the SCT GPO. Failing that configuration would be a false
        # positive and would push operators to re-enable something they turned off on
        # purpose. This check therefore records an 'Info' status only - it does not write to
        # $testResult.Issues and does not influence the Pass/Fail verdict below, which
        # counts only 'Fail' and 'Error' checks.
        if ($gpoExists) {
            $reportedStatus = $null
            if ($gpoObject -and ($gpoObject.PSObject.Properties.Name -contains 'GpoStatus') -and $null -ne $gpoObject.GpoStatus) {
                $reportedStatus = [string]$gpoObject.GpoStatus
            } elseif ($null -ne $observedGpoFlags) {
                $reportedStatus = switch ([int]$observedGpoFlags) {
                    0 { 'AllSettingsEnabled' }
                    1 { 'UserSettingsDisabled' }
                    2 { 'ComputerSettingsDisabled' }
                    3 { 'AllSettingsDisabled' }
                    default { $null }
                }
            }
            
            $testResult.GpoStatus = $reportedStatus
            
            if ([string]::IsNullOrWhiteSpace($reportedStatus)) {
                $testResult.Checks += [PSCustomObject]@{
                    Check = 'GPO Enabled State'
                    Status = 'Skipped'
                    Expected = 'GPO delivers settings'
                    Actual = 'Enabled state not reported'
                    Message = 'Unable to determine GPO enabled state - GpoStatus was not returned by the directory'
                }
            } elseif ($reportedStatus -in @('AllSettingsDisabled')) {
                # Advisory only - see the note above. Never a Fail, never an Issue.
                $testResult.SettingsDisabled = $true
                $testResult.Checks += [PSCustomObject]@{
                    Check = 'GPO Enabled State'
                    Status = 'Info'
                    Expected = 'Not asserted - disabling settings is a supported choice'
                    Actual = $reportedStatus
                    Message = "GPO '$actualGpoName' has all settings disabled, so it delivers no configuration. This is informational only - it is a supported configuration (for example when a baseline GPO is intentionally not used) and is not treated as a finding."
                }
            } else {
                $testResult.Checks += [PSCustomObject]@{
                    Check = 'GPO Enabled State'
                    Status = 'Info'
                    Expected = 'Not asserted - disabling settings is a supported choice'
                    Actual = $reportedStatus
                    Message = 'GPO is enabled and able to deliver settings'
                }
            }
        }
        
        # Determine overall status
        $failedChecks = @($testResult.Checks | Where-Object { $_.Status -eq 'Fail' })
        $errorChecks = @($testResult.Checks | Where-Object { $_.Status -eq 'Error' })
        
        if ($failedChecks.Count -eq 0 -and $errorChecks.Count -eq 0) {
            $testResult.Status = 'Pass'
        } elseif ($errorChecks.Count -gt 0) {
            $testResult.Status = 'Error'
        } else {
            $testResult.Status = 'Fail'
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "GPO test complete" -Data @{
            GPOName = $GPOName
            Status = $testResult.Status
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $testResult
        
    } catch {
        Write-TierModelLog -Level Error -Message "GPO test failed" -Data @{
            GPOName = $GPOName
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            GPOName = $GPOName
            ActualGPOName = $GPOName
            Exists = $null
            ExistenceState = 'Unknown'
            GpoStatus = $null
            SettingsDisabled = $false
            Checks = @(@{
                Check = 'GPO Test'
                Status = 'Error'
                Expected = 'Test successful'
                Actual = 'Test failed'
                Message = $_.Exception.Message
            })
            Status = 'Error'
            Issues = @($_.Exception.Message)
            Recommendations = @('Check GPO name and domain controller connectivity')
        }
    }
}