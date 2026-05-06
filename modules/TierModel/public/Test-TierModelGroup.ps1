function Test-TierModelGroup {
    <#
    .SYNOPSIS
    Audit existing groups against TierModel configuration expectations.
    
    .DESCRIPTION
    Compares current Active Directory group state with TierModel
    configuration to identify missing groups, incorrect properties,
    and location mismatches. Returns structured drift findings.
    
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
    $audit = Test-TierModelGroup -Config $config -DomainController "DC01.contoso.com"
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
    Write-TierModelLog -Level Info -Message "GroupAuditStart" -Data @{
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
        
        # Check if groups exists in config
        if (-not $Config.PSObject.Properties['groups'] -or -not $Config.groups) {
            Write-Host "  ⚠️  No security groups found in configuration" -ForegroundColor Yellow
            Write-TierModelLog -Level Warning -Message "No groups found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No groups section found in configuration"
        } else {
            foreach ($group in $Config.groups) {
                $totalChecked++
                
                try {
                    # Replace placeholders in group path
                    $resolvedPath = Resolve-TierModelPlaceholder -Path $group.path -DomainDN $domainDN
                    $groupName = $group.name
                    $expectedSamAccountName = $group.samaccountname
                    
                    # Expected properties with defaults
                    $expectedGroupScope = if ($group.PSObject.Properties.Name -contains 'groupscope') { 
                        $group.groupscope 
                    } else { 
                        'Global' 
                    }
                    $expectedGroupCategory = if ($group.PSObject.Properties.Name -contains 'groupcategory') { 
                        $group.groupcategory 
                    } else { 
                        'Security' 
                    }
                    
                    if ($IncludeResolvedPaths) {
                        $resolvedPaths += [PSCustomObject]@{
                            Name = $groupName
                            SamAccountName = $expectedSamAccountName
                            OriginalPath = $group.path
                            ResolvedPath = $resolvedPath
                            ExpectedGroupScope = $expectedGroupScope
                            ExpectedGroupCategory = $expectedGroupCategory
                        }
                    }
                    
                    Write-Host "  Checking Group: $groupName ($expectedSamAccountName)" -ForegroundColor Cyan
                    
                    Write-TierModelLog -Level Debug -Message "GroupAuditCheck" -Data @{
                        Name = $groupName
                        SamAccountName = $expectedSamAccountName
                        Path = $resolvedPath
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Check if group exists
                    $actualGroup = $null
                    try {
                        $actualGroup = Get-ADGroup -Identity $expectedSamAccountName -Properties DistinguishedName,GroupScope,GroupCategory -Server $DomainController -ErrorAction Stop
                        Write-Host "    ✅ Group exists" -ForegroundColor Green
                    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                        # Group doesn't exist
                        Write-Host "    ❌ Group missing" -ForegroundColor Red
                        $driftFindings += [PSCustomObject]@{
                            Type = 'Missing'
                            ResourceType = 'Group'
                            Identifier = $groupName
                            ExpectedValue = 'Present'
                            ActualValue = 'Missing'
                            Details = "Group '$groupName' ($expectedSamAccountName) is missing from Active Directory"
                        }
                        $missingCount++
                        
                        Write-TierModelLog -Level Info -Message "GroupAuditMissing" -Data @{
                            Name = $groupName
                            SamAccountName = $expectedSamAccountName
                            Path = $resolvedPath
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        continue
                    } catch {
                        Write-Host "  ⚠️ Group Existence: Query Failed" -ForegroundColor Yellow
                        $warnings += "Failed to query group '$groupName': $($_.Exception.Message)"
                        Write-TierModelLog -Level Warning -Message "Failed to query group" -Data @{
                            GroupName = $groupName
                            SamAccountName = $expectedSamAccountName
                            Error = $_.Exception.Message
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        continue
                    }
                    
                    Write-TierModelLog -Level Info -Message "GroupAuditExists" -Data @{
                        Name = $groupName
                        SamAccountName = $expectedSamAccountName
                        DistinguishedName = $actualGroup.DistinguishedName
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Check if group is in correct OU
                    $expectedOUPath = $resolvedPath
                    $actualOUPath = ($actualGroup.DistinguishedName -split ',', 2)[1] # Remove CN=groupname, part
                    
                    if ($actualOUPath -ne $expectedOUPath) {
                        Write-Host "    ❌ Group in wrong OU (Expected: $expectedOUPath)" -ForegroundColor Red
                        $driftFindings += [PSCustomObject]@{
                            Type = 'Mismatch'
                            ResourceType = 'Group'
                            Identifier = "$groupName/Location"
                            ExpectedValue = $expectedOUPath
                            ActualValue = $actualOUPath
                            Details = "Group '$groupName' is in wrong OU. Expected: $expectedOUPath, Actual: $actualOUPath"
                        }
                        $mismatchCount++
                        
                        Write-TierModelLog -Level Info -Message "GroupAuditMismatch" -Data @{
                            Name = $groupName
                            Property = 'Location'
                            Expected = $expectedOUPath
                            Actual = $actualOUPath
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        Write-Host "    ✅ Group in correct OU" -ForegroundColor Green
                    }
                    
                    # Check group scope (Global, Universal, DomainLocal)
                    if ($actualGroup.GroupScope -ne $expectedGroupScope) {
                        Write-Host "    ❌ Group scope incorrect ($($actualGroup.GroupScope), should be $expectedGroupScope)" -ForegroundColor Red
                        $driftFindings += [PSCustomObject]@{
                            Type = 'Mismatch'
                            ResourceType = 'Group'
                            Identifier = "$groupName/GroupScope"
                            ExpectedValue = $expectedGroupScope
                            ActualValue = $actualGroup.GroupScope
                            Details = "Group '$groupName' has incorrect scope. Expected: $expectedGroupScope, Actual: $($actualGroup.GroupScope)"
                        }
                        $mismatchCount++
                        
                        Write-TierModelLog -Level Info -Message "GroupAuditMismatch" -Data @{
                            Name = $groupName
                            Property = 'GroupScope'
                            Expected = $expectedGroupScope
                            Actual = $actualGroup.GroupScope
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        Write-Host "    ✅ Group scope correct ($expectedGroupScope)" -ForegroundColor Green
                    }
                    
                    # Check group category (Security, Distribution)
                    if ($actualGroup.GroupCategory -ne $expectedGroupCategory) {
                        Write-Host "    ❌ Group category incorrect ($($actualGroup.GroupCategory), should be $expectedGroupCategory)" -ForegroundColor Red
                        $driftFindings += [PSCustomObject]@{
                            Type = 'Mismatch'
                            ResourceType = 'Group'
                            Identifier = "$groupName/GroupCategory"
                            ExpectedValue = $expectedGroupCategory
                            ActualValue = $actualGroup.GroupCategory
                            Details = "Group '$groupName' has incorrect category. Expected: $expectedGroupCategory, Actual: $($actualGroup.GroupCategory)"
                        }
                        $mismatchCount++
                        
                        Write-TierModelLog -Level Info -Message "GroupAuditMismatch" -Data @{
                            Name = $groupName
                            Property = 'GroupCategory'
                            Expected = $expectedGroupCategory
                            Actual = $actualGroup.GroupCategory
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        Write-Host "    ✅ Group category correct ($expectedGroupCategory)" -ForegroundColor Green
                    }
                    
                } catch {
                    $errorMsg = "Failed to audit group '$($group.name)': $($_.Exception.Message)"
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'External'
                        Code = 'GroupAuditFailed'
                        Message = $errorMsg
                        Context = @{
                            GroupName = $group.name
                            Exception = $_.Exception.Message
                        }
                    }
                    Write-TierModelLog -Level Error -Message "Group audit failed" -Data @{
                        GroupName = $group.name
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
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
        
        # Display audit summary
        if (-not $Silent) {
            Write-Host "`n=== Group Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total Groups Checked: $totalChecked" -ForegroundColor White
            if ($missingCount -eq 0) {
                Write-Host "Missing Groups: $missingCount ✅" -ForegroundColor Green
            } else {
                Write-Host "Missing Groups: $missingCount ❌" -ForegroundColor Red
            }
            if ($mismatchCount -eq 0) {
                Write-Host "Configuration Mismatches: $mismatchCount ✅" -ForegroundColor Green
            } else {
                Write-Host "Configuration Mismatches: $mismatchCount ❌" -ForegroundColor Red
            }
            if ($driftCount -eq 0) {
                Write-Host "Overall Status: All Groups are compliant ✅" -ForegroundColor Green
            } else {
                Write-Host "Overall Status: $driftCount issues found ❌" -ForegroundColor Red
            }
        }
        
        Write-TierModelLog -Level Info -Message "GroupAuditComplete" -Data @{
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
            Code = 'GroupAuditFailed'
            Message = "Group audit failed: $($_.Exception.Message)"
            Context = @{
                Exception = $_.Exception.Message
            }
        }
        Write-TierModelLog -Level Error -Message "Group audit failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            DriftFindings = $driftFindings
            Summary = @{ TotalChecked = $totalChecked; MissingCount = $missingCount; MismatchCount = $mismatchCount; DriftCount = $missingCount + $mismatchCount }
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
    }
}