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
                $testResult.Issues += "GPO '$GPOName' does not exist"
                $testResult.Recommendations += "Create GPO using New-TierModelGpo"
            }
        }
                        
        if ($gpoExists -and $GPOConfig) {
            # Check 2: GPO Status Configuration (if provided)
            if ($GPOConfig.PSObject.Properties.Name -contains 'gpoStatus') {
                try {
                    $domain = Get-ADDomain -Server $DomainController
                    $domainDN = $domain.DistinguishedName
                    $gpoADObject = Get-ADObject -Identity "CN={$($gpoObject.Id)},CN=Policies,CN=System,$domainDN" -Properties flags -Server $DomainController
                    $currentFlags = $gpoADObject.flags
                    
                    $expectedFlags = switch ($GPOConfig.gpoStatus) {
                        'AllEnabled'               { 0 }
                        'UserSettingsDisabled'    { 1 }
                        'ComputerSettingsDisabled' { 2 }
                        'BothSettingsDisabled'     { 3 }
                        default { 0 }
                    }
                    
                    if ($currentFlags -eq $expectedFlags) {
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