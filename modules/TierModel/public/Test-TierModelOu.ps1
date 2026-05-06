function Test-TierModelOu {
    <#
    .SYNOPSIS
    Audit existing OUs against TierModel configuration expectations.
    
    .DESCRIPTION
    Compares current Active Directory organizational unit state with TierModel
    configuration to identify missing OUs and inheritance setting mismatches.
    Returns structured drift findings for reporting and remediation.
    
    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.
    
    .PARAMETER DomainController
    Preferred domain controller for queries.
    
    .PARAMETER IncludeResolvedPaths
    Include resolved path information in output for diagnostics.
    
    .OUTPUTS
    PSCustomObject with DriftFindings, Summary, Warnings, and Errors.
    
    .EXAMPLE
    $config = Get-TierModelConfig
    $audit = Test-TierModelOu -Config $config -DomainController "DC01.contoso.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$IncludeResolvedPaths,
        
        [switch]$Silent
    )
    
    $CorrelationId = $script:CorrelationId
    Write-TierModelLog -Level Info -Message "OuAuditStart" -Data @{
        CorrelationId = $CorrelationId
        DomainController = $DomainController
        IncludeResolvedPaths = $IncludeResolvedPaths.IsPresent
    } | Out-Null
    
    $driftFindings = @()
    $warnings = @()
    $errors = @()
    $resolvedPaths = @()
    $totalChecked = 0
    $missingCount = 0
    $mismatchCount = 0
    
    try {
        # Resolve domain DN
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        # Check if organizationUnits exists in config
        if (-not $Config.PSObject.Properties['organizationUnits'] -or -not $Config.organizationUnits) {
            Write-TierModelLog -Level Warning -Message "No organizationUnits found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No organizationUnits section found in configuration"
        } else {
            foreach ($ou in $Config.organizationUnits) {
                $totalChecked++
                
                try {
                    # Resolve path with placeholder replacement (same logic as deployment)
                    $resolvedPath = Resolve-TierModelOuPath -OuPath $ou.path -DomainDN $domainDN
                    $ouDistinguishedName = "OU=$($ou.name),$resolvedPath"
                    
                    if ($IncludeResolvedPaths) {
                        $resolvedPaths += [PSCustomObject]@{
                            Name = $ou.name
                            OriginalPath = $ou.path
                            ResolvedPath = $resolvedPath
                            DistinguishedName = $ouDistinguishedName
                        }
                    }
                    
                    Write-TierModelLog -Level Debug -Message "OuAuditCheck" -Data @{
                        Name = $ou.name
                        DistinguishedName = $ouDistinguishedName
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    Write-Host "Checking OU: $($ou.name)" -ForegroundColor Cyan
                    
                    # Check if OU exists
                    $existenceTest = Test-TierModelOuExists -DistinguishedName $ouDistinguishedName -DomainController $DomainController
                    
                    if (-not $existenceTest.Exists) {
                        Write-Host "  ❌ OU Existence: Missing" -ForegroundColor Red
                        $driftFindings += [PSCustomObject]@{
                            Type = 'Missing'
                            ResourceType = 'OrganizationalUnit'
                            Identifier = $ou.name
                            ExpectedValue = $ouDistinguishedName
                            ActualValue = 'Not Found'
                            Details = "OU '$($ou.name)' is missing from Active Directory"
                        }
                        $missingCount++
                        
                        Write-TierModelLog -Level Info -Message "OuAuditMissing" -Data @{
                            Name = $ou.name
                            DistinguishedName = $ouDistinguishedName
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        continue
                    }
                    
                    Write-Host "  ✅ OU Existence: Found" -ForegroundColor Green
                    
                    Write-TierModelLog -Level Info -Message "OuAuditExist" -Data @{
                        Name = $ou.name
                        DistinguishedName = $ouDistinguishedName
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Get the OU object for further checks
                    $adOU = Get-ADOrganizationalUnit -Identity $ouDistinguishedName -Server $DomainController -Properties ProtectedFromAccidentalDeletion
                    
                    # Check accidental deletion protection if configured
                    if ($ou.PSObject.Properties.Name -contains 'protectFromAccidentalDeletion' -and $ou.protectFromAccidentalDeletion -eq $true) {
                        if ($adOU.ProtectedFromAccidentalDeletion -eq $true) {
                            Write-Host "  ✅ Accidental Deletion Protection: Enabled" -ForegroundColor Green
                        } else {
                            Write-Host "  ❌ Accidental Deletion Protection: Disabled (Expected: Enabled)" -ForegroundColor Red
                            $driftFindings += [PSCustomObject]@{
                                Type = 'Mismatch'
                                ResourceType = 'OrganizationalUnit'
                                Identifier = "$($ou.name)/AccidentalDeletionProtection"
                                ExpectedValue = 'Protected'
                                ActualValue = 'Not Protected'
                                Details = "OU '$($ou.name)' should be protected from accidental deletion but it is not protected"
                            }
                            $mismatchCount++
                            
                            Write-TierModelLog -Level Info -Message "OuAuditMismatch" -Data @{
                                Name = $ou.name
                                Property = 'AccidentalDeletionProtection'
                                Expected = 'Protected'
                                Actual = 'Not Protected'
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        }
                    } elseif ($ou.PSObject.Properties.Name -contains 'protectFromAccidentalDeletion' -and $ou.protectFromAccidentalDeletion -eq $false) {
                        if ($adOU.ProtectedFromAccidentalDeletion -eq $false) {
                            Write-Host "  ✅ Accidental Deletion Protection: Disabled" -ForegroundColor Green
                        } else {
                            Write-Host "  ❌ Accidental Deletion Protection: Enabled (Expected: Disabled)" -ForegroundColor Red
                            $driftFindings += [PSCustomObject]@{
                                Type = 'Mismatch'
                                ResourceType = 'OrganizationalUnit'
                                Identifier = "$($ou.name)/AccidentalDeletionProtection"
                                ExpectedValue = 'Not Protected'
                                ActualValue = 'Protected'
                                Details = "OU '$($ou.name)' should not be protected from accidental deletion but it is protected"
                            }
                            $mismatchCount++
                            
                            Write-TierModelLog -Level Info -Message "OuAuditMismatch" -Data @{
                                Name = $ou.name
                                Property = 'AccidentalDeletionProtection'
                                Expected = 'Not Protected'
                                Actual = 'Protected'
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        }
                    }
                    
                    # Check GPO inheritance blocking if configured
                    if ($ou.PSObject.Properties.Name -contains 'blockGpoInheritance' -and $ou.blockGpoInheritance -eq $true) {
                        try {
                            $gpoInheritance = Get-GPInheritance -Target $ouDistinguishedName -Server $DomainController
                            if ($gpoInheritance.GpoInheritanceBlocked -eq $true) {
                                Write-Host "  ✅ GPO Inheritance: Blocked" -ForegroundColor Green
                            } else {
                                Write-Host "  ❌ GPO Inheritance: Not Blocked (Expected: Blocked)" -ForegroundColor Red
                                $driftFindings += [PSCustomObject]@{
                                    Type = 'Mismatch'
                                    ResourceType = 'OrganizationalUnit'
                                    Identifier = "$($ou.name)/GpoInheritance"
                                    ExpectedValue = 'Blocked'
                                    ActualValue = 'Not Blocked'
                                    Details = "OU '$($ou.name)' should have GPO inheritance blocked but it is not blocked"
                                }
                                $mismatchCount++
                                
                                Write-TierModelLog -Level Info -Message "OuAuditMismatch" -Data @{
                                    Name = $ou.name
                                    Property = 'GpoInheritance'
                                    Expected = 'Blocked'
                                    Actual = 'Not Blocked'
                                    CorrelationId = $CorrelationId
                                } | Out-Null
                            }
                        } catch {
                            Write-Host "  ⚠️ GPO Inheritance: Check Failed" -ForegroundColor Yellow
                            $warnings += "Failed to check GPO inheritance for OU '$($ou.name)': $($_.Exception.Message)"
                            Write-TierModelLog -Level Warning -Message "Failed to check GPO inheritance" -Data @{
                                OUName = $ou.name
                                Error = $_.Exception.Message
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        }
                    }
                    
                    # Check security inheritance disabling if configured
                    if ($ou.PSObject.Properties.Name -contains 'disableInheritance' -and $ou.disableInheritance -eq $true) {
                        try {
                            $acl = Get-Acl -Path "AD:\$ouDistinguishedName"
                            if ($acl.AreAccessRulesProtected -eq $true) {
                                Write-Host "  ✅ Security Inheritance: Disabled" -ForegroundColor Green
                            } else {
                                Write-Host "  ❌ Security Inheritance: Enabled (Expected: Disabled)" -ForegroundColor Red
                                $driftFindings += [PSCustomObject]@{
                                    Type = 'Mismatch'
                                    ResourceType = 'OrganizationalUnit'
                                    Identifier = "$($ou.name)/SecurityInheritance"
                                    ExpectedValue = 'Disabled'
                                    ActualValue = 'Enabled'
                                    Details = "OU '$($ou.name)' should have security inheritance disabled but it is enabled"
                                }
                                $mismatchCount++
                                
                                Write-TierModelLog -Level Info -Message "OuAuditMismatch" -Data @{
                                    Name = $ou.name
                                    Property = 'SecurityInheritance'
                                    Expected = 'Disabled'
                                    Actual = 'Enabled'
                                    CorrelationId = $CorrelationId
                                } | Out-Null
                            }
                        } catch {
                            Write-Host "  ⚠️ Security Inheritance: Check Failed" -ForegroundColor Yellow
                            $warnings += "Failed to check security inheritance for OU '$($ou.name)': $($_.Exception.Message)"
                            Write-TierModelLog -Level Warning -Message "Failed to check security inheritance" -Data @{
                                OUName = $ou.name
                                Error = $_.Exception.Message
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        }
                    } elseif ($ou.PSObject.Properties.Name -contains 'disableInheritance' -and $ou.disableInheritance -eq $false) {
                        try {
                            $acl = Get-Acl -Path "AD:\$ouDistinguishedName"
                            if ($acl.AreAccessRulesProtected -eq $false) {
                                Write-Host "  ✅ Security Inheritance: Enabled" -ForegroundColor Green
                            } else {
                                Write-Host "  ❌ Security Inheritance: Disabled (Expected: Enabled)" -ForegroundColor Red
                                $driftFindings += [PSCustomObject]@{
                                    Type = 'Mismatch'
                                    ResourceType = 'OrganizationalUnit'
                                    Identifier = "$($ou.name)/SecurityInheritance"
                                    ExpectedValue = 'Enabled'
                                    ActualValue = 'Disabled'
                                    Details = "OU '$($ou.name)' should have security inheritance enabled but it is disabled"
                                }
                                $mismatchCount++
                                
                                Write-TierModelLog -Level Info -Message "OuAuditMismatch" -Data @{
                                    Name = $ou.name
                                    Property = 'SecurityInheritance'
                                    Expected = 'Enabled'
                                    Actual = 'Disabled'
                                    CorrelationId = $CorrelationId
                                } | Out-Null
                            }
                        } catch {
                            Write-Host "  ⚠️ Security Inheritance: Check Failed" -ForegroundColor Yellow
                            $warnings += "Failed to check security inheritance for OU '$($ou.name)': $($_.Exception.Message)"
                            Write-TierModelLog -Level Warning -Message "Failed to check security inheritance" -Data @{
                                OUName = $ou.name
                                Error = $_.Exception.Message
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        }
                    }
                    
                } catch {
                    $errorMsg = "Failed to audit OU '$($ou.name)': $($_.Exception.Message)"
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'External'
                        Code = 'OuAuditFailed'
                        Message = $errorMsg
                        Context = @{
                            OUName = $ou.name
                            Exception = $_.Exception.Message
                        }
                    }
                    Write-TierModelLog -Level Error -Message "OU audit failed" -Data @{
                        OUName = $ou.name
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    }
                }
            }
        }
        
        $driftCount = $missingCount + $mismatchCount
        $summary = @{
            TotalChecked = $totalChecked
            MissingCount = $missingCount
            MismatchCount = $mismatchCount
            DriftCount = $driftCount
        }
        
        # Display audit summary (only if not Silent)
        if (-not $Silent) {
            Write-Host "`n=== OU Audit Summary ===" -ForegroundColor Blue
        Write-Host "Total OUs Checked: $totalChecked" -ForegroundColor White
        if ($missingCount -eq 0) {
            Write-Host "Missing OUs: $missingCount ✅" -ForegroundColor Green
        } else {
            Write-Host "Missing OUs: $missingCount ❌" -ForegroundColor Red
        }
        if ($mismatchCount -eq 0) {
            Write-Host "Configuration Mismatches: $mismatchCount ✅" -ForegroundColor Green
        } else {
            Write-Host "Configuration Mismatches: $mismatchCount ❌" -ForegroundColor Red
        }
        if ($driftCount -eq 0) {
            Write-Host "Overall Status: All OUs are compliant ✅" -ForegroundColor Green
        } else {
            Write-Host "Overall Status: $driftCount issues found ❌" -ForegroundColor Red
        }
        }
        
        Write-TierModelLog -Level Info -Message "OuAuditComplete" -Data @{
            Summary = $summary
            DriftFindingsCount = $driftFindings.Count
            WarningCount = $warnings.Count
            ErrorCount = $errors.Count
            CorrelationId = $CorrelationId
        } | Out-Null
        
        $result = [PSCustomObject]@{
            DriftFindings = $driftFindings
            Summary = $summary
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
        
        if ($IncludeResolvedPaths) {
            $result | Add-Member -NotePropertyName 'ResolvedPaths' -NotePropertyValue $resolvedPaths
        }
        
        return $result
        
    } catch {
        $errors += @{
            Timestamp = Get-Date
            Category = 'Execution'
            Code = 'OuAuditFailed'
            Message = "OU audit failed: $($_.Exception.Message)"
            Context = @{
                Exception = $_.Exception.Message
            }
        }
        Write-TierModelLog -Level Error -Message "OU audit failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        }
        
        return [PSCustomObject]@{
            DriftFindings = $driftFindings
            Summary = @{ TotalChecked = $totalChecked; MissingCount = $missingCount; MismatchCount = $mismatchCount; DriftCount = $missingCount + $mismatchCount }
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
    }
}