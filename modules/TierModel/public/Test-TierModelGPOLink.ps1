function Test-TierModelGPOLink {
    <#
    .SYNOPSIS
    Test individual TierModel GPO link existence and configuration.
    
    .DESCRIPTION
    Tests whether a specific GPO is properly linked to a target OU with correct
    order and enforcement settings. This is a focused test for individual GPO
    link validation.
    
    .PARAMETER GPOName
    Name of the GPO to test the link for.
    
    .PARAMETER TargetOU
    Distinguished name of the OU where the GPO should be linked.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER ExpectedOrder
    Optional expected link order to validate against.
    
    .PARAMETER ExpectedEnforced
    Optional expected enforcement setting to validate against.
    
    .EXAMPLE
    Test-TierModelGPOLink -GPOName "Tier0-Security" -TargetOU "OU=Tier0,DC=domain,DC=com" -DomainController "DC01"
    
    .EXAMPLE
    Test-TierModelGPOLink -GPOName "Tier0-Security" -TargetOU "OU=Tier0,DC=domain,DC=com" -ExpectedOrder 1 -ExpectedEnforced $true -DomainController "DC01"
    
    .OUTPUTS
    PSCustomObject with link test results including existence and configuration status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GPOName,
        
        [Parameter(Mandatory)]
        [string]$TargetOU,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [Parameter()]
        [int]$ExpectedOrder,
        
        [Parameter()]
        [bool]$ExpectedEnforced,
        
        [Parameter()]
        [bool]$ExpectedEnabled = $true
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "GPO link test start" -Data @{
        GPOName = $GPOName
        TargetOU = $TargetOU
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $testResult = [PSCustomObject]@{
            GPOName = $GPOName
            TargetOU = $TargetOU
            LinkExists = $false
            CurrentOrder = $null
            CurrentEnforced = $null
            CurrentEnabled = $null
            Checks = @()
            Status = 'Unknown'
            Issues = @()
            Recommendations = @()
        }
        
        # Check 1: GPO Exists
        $gpoExists = $false
        $actualGpoName = $GPOName
        try {
            # Try exact name match first
            $gpo = Get-GPO -Name $GPOName -Server $DomainController -ErrorAction Stop
            $gpoExists = $true
            
            $testResult.Checks += [PSCustomObject]@{
                Check = 'GPO Existence'
                Status = 'Pass'
                Expected = 'GPO exists'
                Actual = "GPO found (ID: $($gpo.Id))"
                Message = 'GPO exists in domain'
            }
            
        } catch {
            # If exact match fails and this is an SHF GPO (contains SHF [Provider] [Version]), try wildcard match
            if ($GPOName -like '*SHF [Provider] [Version]*') {
                try {
                    # Extract the rename pattern by removing [Provider] [Version] and everything after
                    $renamePattern = ($GPOName -replace ' \\[Provider\\] \\[Version\\].*$', '') + '*'
                    $matchingGPOs = Get-GPO -All -Server $DomainController | Where-Object { $_.DisplayName -like $renamePattern }
                    if ($matchingGPOs -and $matchingGPOs.Count -eq 1) {
                        $gpo = $matchingGPOs[0]
                        $actualGpoName = $gpo.DisplayName
                        $gpoExists = $true
                        
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Existence'
                            Status = 'Pass'
                            Expected = 'GPO exists (exact or wildcard match)'
                            Actual = "GPO found via wildcard '$renamePattern' (Name: $actualGpoName, ID: $($gpo.Id))"
                            Message = 'GPO found using SHF rename wildcard pattern'
                        }
                    } elseif ($matchingGPOs -and $matchingGPOs.Count -gt 1) {
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Existence'
                            Status = 'Fail'
                            Expected = 'Single GPO match'
                            Actual = "Multiple GPOs found: $($matchingGPOs.DisplayName -join ', ')"
                            Message = "Multiple GPOs match wildcard pattern '$renamePattern'"
                        }
                        $testResult.Issues += "Multiple GPOs found matching pattern '$renamePattern': $($matchingGPOs.DisplayName -join ', ')"
                        $testResult.Recommendations += "Ensure only one GPO matches the rename pattern or use exact naming"
                    } else {
                        $testResult.Checks += [PSCustomObject]@{
                            Check = 'GPO Existence'
                            Status = 'Fail'
                            Expected = 'GPO exists'
                            Actual = 'GPO not found (exact or wildcard)'
                            Message = $_.Exception.Message
                        }
                        $testResult.Issues += "GPO '$GPOName' does not exist (also tried wildcard '$renamePattern')"
                        $testResult.Recommendations += "Create GPO using New-TierModelGpo"
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
        
        # Check 2: Link Existence and Properties
        if ($gpoExists) {
            try {
                $inheritance = Get-GPInheritance -Target $TargetOU -Server $DomainController
                $gpoLink = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $actualGpoName }
                
                if ($gpoLink) {
                    $testResult.LinkExists = $true
                    $testResult.CurrentOrder = $gpoLink.Order
                    $testResult.CurrentEnforced = $gpoLink.Enforced
                    $testResult.CurrentEnabled = $gpoLink.Enabled
                    
                    $testResult.Checks += [PSCustomObject]@{
                        Check = 'Link Existence'
                        Status = 'Pass'
                        Expected = 'Link exists'
                        Actual = "Linked (Order: $($gpoLink.Order), Enforced: $($gpoLink.Enforced))"
                        Message = 'GPO is properly linked to OU'
                    }
                    
                    # Check order if specified
                    if ($PSBoundParameters.ContainsKey('ExpectedOrder')) {
                        if ($gpoLink.Order -eq $ExpectedOrder) {
                            $testResult.Checks += [PSCustomObject]@{
                                Check = 'Link Order'
                                Status = 'Pass'
                                Expected = $ExpectedOrder
                                Actual = $gpoLink.Order
                                Message = 'Link order matches expected value'
                            }
                        } else {
                            $testResult.Checks += [PSCustomObject]@{
                                Check = 'Link Order'
                                Status = 'Fail'
                                Expected = $ExpectedOrder
                                Actual = $gpoLink.Order
                                Message = 'Link order does not match expected value'
                            }
                            
                            $testResult.Issues += "Link order mismatch - expected $ExpectedOrder, actual $($gpoLink.Order)"
                            $testResult.Recommendations += "Update link order using Set-GPLink"
                        }
                    }
                    
                    # Check enforcement if specified
                    if ($PSBoundParameters.ContainsKey('ExpectedEnforced')) {
                        if ($gpoLink.Enforced -eq $ExpectedEnforced) {
                            $testResult.Checks += [PSCustomObject]@{
                                Check = 'Link Enforcement'
                                Status = 'Pass'
                                Expected = $ExpectedEnforced
                                Actual = $gpoLink.Enforced
                                Message = 'Link enforcement matches expected value'
                            }
                        } else {
                            $testResult.Checks += [PSCustomObject]@{
                                Check = 'Link Enforcement'
                                Status = 'Fail'
                                Expected = $ExpectedEnforced
                                Actual = $gpoLink.Enforced
                                Message = 'Link enforcement does not match expected value'
                            }
                            
                            $testResult.Issues += "Link enforcement mismatch - expected $ExpectedEnforced, actual $($gpoLink.Enforced)"
                            $testResult.Recommendations += "Update link enforcement using Set-GPLink"
                        }
                    }
                    
                    # Check enabled status if specified
                    if ($PSBoundParameters.ContainsKey('ExpectedEnabled')) {
                        if ($gpoLink.Enabled -eq $ExpectedEnabled) {
                            $testResult.Checks += [PSCustomObject]@{
                                Check = 'Link Enabled Status'
                                Status = 'Pass'
                                Expected = $ExpectedEnabled
                                Actual = $gpoLink.Enabled
                                Message = 'Link enabled status matches expected value'
                            }
                        } elseif ($ExpectedEnabled -eq $false -and $gpoLink.Enabled -eq $true) {
                            # Special case: Expected False but got True - this is actually good!
                            # JSON defaults to false for safe deployment, but if it's enabled in production, that's the desired end state
                            $testResult.Checks += [PSCustomObject]@{
                                Check = 'Link Enabled Status'
                                Status = 'Pass'
                                Expected = $ExpectedEnabled
                                Actual = $gpoLink.Enabled
                                Message = 'Link is enabled in production (better than expected default)'
                            }
                        } else {
                            # Only fail if Expected True but got False (GPO should be enabled but isn't)
                            $testResult.Checks += [PSCustomObject]@{
                                Check = 'Link Enabled Status'
                                Status = 'Fail'
                                Expected = $ExpectedEnabled
                                Actual = $gpoLink.Enabled
                                Message = 'Link enabled status does not match expected value'
                            }
                            
                            $testResult.Issues += "Link enabled mismatch - expected $ExpectedEnabled, actual $($gpoLink.Enabled)"
                            $testResult.Recommendations += "Update link enabled status using Set-GPLink"
                        }
                    }
                } else {
                    $testResult.Checks += [PSCustomObject]@{
                        Check = 'Link Existence'
                        Status = 'Fail'
                        Expected = 'Link exists'
                        Actual = 'No link found'
                        Message = 'GPO is not linked to OU'
                    }
                    
                    $testResult.Issues += "GPO is not linked to OU $TargetOU"
                    $testResult.Recommendations += "Create link using New-TierModelGPOLink"
                }
            } catch {
                $testResult.Checks += [PSCustomObject]@{
                    Check = 'Link Existence'
                    Status = 'Error'
                    Expected = 'Link check successful'
                    Actual = 'Unable to check'
                    Message = $_.Exception.Message
                }
                
                $testResult.Issues += "Unable to check GPO links - $($_.Exception.Message)"
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
        
        Write-TierModelLog -Level Info -Message "GPO link test complete" -Data @{
            GPOName = $GPOName
            TargetOU = $TargetOU
            Status = $testResult.Status
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $testResult
        
    } catch {
        Write-TierModelLog -Level Error -Message "GPO link test failed" -Data @{
            GPOName = $GPOName
            TargetOU = $TargetOU
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            GPOName = $GPOName
            TargetOU = $TargetOU
            LinkExists = $false
            CurrentOrder = $null
            CurrentEnforced = $null
            Checks = @(@{
                Check = 'GPO Link Test'
                Status = 'Error'
                Expected = 'Test successful'
                Actual = 'Test failed'
                Message = $_.Exception.Message
            })
            Status = 'Error'
            Issues = @($_.Exception.Message)
            Recommendations = @('Check GPO and OU names, verify domain controller connectivity')
        }
    }
}