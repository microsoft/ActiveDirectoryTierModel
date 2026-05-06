function Test-TierModelUser {
    <#
    .SYNOPSIS
    Audit existing users against TierModel configuration expectations.
    
    .DESCRIPTION
    Compares current Active Directory user state with TierModel
    configuration to identify missing users, incorrect OU placement,
    and group membership mismatches. Returns structured drift findings.
    
    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER IncludeResolvedPaths
    Include resolved paths in the output for detailed reporting.
    
    .EXAMPLE
    $config = Get-TierModelConfig
    $audit = Test-TierModelUser -Config $config -DomainController "DC01.contoso.com"
    
    .OUTPUTS
    PSCustomObject with audit results including drift findings and summary counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$Silent,
        
        [Parameter()]
        [switch]$IncludeResolvedPaths
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    
    Write-TierModelLog -Level Info -Message "UserAuditStart" -Data @{
        DomainController = $DomainController
        IncludeResolvedPaths = $IncludeResolvedPaths.IsPresent
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $driftFindings = @()
        $warnings = @()
        $errors = @()
        $totalChecked = 0
        $missingCount = 0
        $mismatchCount = 0
        $resolvedPaths = @()
        
        # Get domain DN for placeholder replacement
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        # Check if users exists in config
        if (-not $Config.PSObject.Properties['users'] -or -not $Config.users) {
            Write-Host "  ⚠️  No user accounts found in configuration" -ForegroundColor Yellow
            Write-TierModelLog -Level Warning -Message "No users found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No users section found in configuration"
        } else {
            foreach ($user in $Config.users) {
                $totalChecked++
                
                try {
                    # Replace placeholders in user OU path
                    $resolvedPath = Resolve-TierModelPlaceholder -Path $user.ouPath -DomainDN $domainDN
                    $userName = $user.displayName
                    $expectedSamAccountName = $user.samAccountName
                    
                    # Expected user properties
                    $expectedGroups = if ($user.PSObject.Properties.Name -contains 'memberOf') { 
                        @($user.memberOf)
                    } else { 
                        @() 
                    }
                    
                    if ($IncludeResolvedPaths) {
                        $resolvedPaths += [PSCustomObject]@{
                            Name = $userName
                            SamAccountName = $expectedSamAccountName
                            OriginalPath = $user.ouPath
                            ResolvedPath = $resolvedPath
                            ExpectedGroups = $expectedGroups
                        }
                    }
                    
                    Write-Host "  Checking User: $userName ($expectedSamAccountName)" -ForegroundColor Cyan
                    
                    Write-TierModelLog -Level Debug -Message "UserAuditCheck" -Data @{
                        Name = $userName
                        SamAccountName = $expectedSamAccountName
                        Path = $resolvedPath
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Check if user exists
                    $actualUser = $null
                    try {
                        $actualUser = Get-ADUser -Identity $expectedSamAccountName -Properties DistinguishedName,Enabled,MemberOf -Server $DomainController -ErrorAction Stop
                        Write-Host "    ✅ User exists" -ForegroundColor Green
                    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                        # User doesn't exist
                        Write-Host "    ❌ User missing" -ForegroundColor Red
                        $driftFindings += [PSCustomObject]@{
                            Type = 'Missing'
                            ResourceType = 'User'
                            Identifier = $userName
                            ExpectedValue = 'Present'
                            ActualValue = 'Missing'
                            Details = "User '$userName' ($expectedSamAccountName) is missing from Active Directory"
                        }
                        $missingCount++
                        
                        Write-TierModelLog -Level Info -Message "UserAuditMissing" -Data @{
                            Name = $userName
                            SamAccountName = $expectedSamAccountName
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        continue
                    } catch {
                        Write-Host "    ❌ User query failed: $($_.Exception.Message)" -ForegroundColor Red
                        Write-TierModelLog -Level Warning -Message "Failed to query user" -Data @{
                            UserName = $userName
                            SamAccountName = $expectedSamAccountName
                            Exception = $_.Exception.Message
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        continue
                    }
                    
                    Write-TierModelLog -Level Info -Message "UserAuditExists" -Data @{
                        Name = $userName
                        SamAccountName = $expectedSamAccountName
                        DistinguishedName = $actualUser.DistinguishedName
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Check if user is in correct OU
                    $expectedOUPath = $resolvedPath
                    $actualOUPath = ($actualUser.DistinguishedName -split ',', 2)[1] # Remove CN=username, part
                    
                    if ($actualOUPath -ne $expectedOUPath) {
                        Write-Host "    ❌ User in wrong OU (Expected: $expectedOUPath)" -ForegroundColor Red
                        $driftFindings += [PSCustomObject]@{
                            Type = 'Mismatch'
                            ResourceType = 'User'
                            Identifier = "$userName/Location"
                            ExpectedValue = $expectedOUPath
                            ActualValue = $actualOUPath
                            Details = "User '$userName' is in wrong OU. Expected: $expectedOUPath, Actual: $actualOUPath"
                        }
                        $mismatchCount++
                        
                        Write-TierModelLog -Level Info -Message "UserAuditMismatch" -Data @{
                            Name = $userName
                            Property = 'Location'
                            Expected = $expectedOUPath
                            Actual = $actualOUPath
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        Write-Host "    ✅ User in correct OU" -ForegroundColor Green
                    }
                    
                    # Check group memberships
                    if ($expectedGroups -and (@($expectedGroups).Count -gt 0)) {
                        # Get actual group SamAccountNames from the user's MemberOf property
                        $actualGroupSamNames = @()
                        if ($actualUser.MemberOf) {
                            foreach ($groupDN in $actualUser.MemberOf) {
                                try {
                                    $groupObj = Get-ADGroup -Identity $groupDN -Properties SamAccountName -Server $DomainController -ErrorAction Stop
                                    $actualGroupSamNames += $groupObj.SamAccountName
                                } catch {
                                    # Group might not exist or be accessible, try to extract from DN
                                    $actualGroupSamNames += ($groupDN -split ',')[0] -replace 'CN=', ''
                                }
                            }
                        }
                        
                        $missingGroups = @()
                        foreach ($expectedGroup in $expectedGroups) {
                            if ($expectedGroup -notin $actualGroupSamNames) {
                                $missingGroups += $expectedGroup
                            }
                        }
                        
                        if ((@($missingGroups).Count -gt 0)) {
                            Write-Host "    ❌ Missing group memberships: $($missingGroups -join ', ')" -ForegroundColor Red
                            $driftFindings += [PSCustomObject]@{
                                Type = 'Mismatch'
                                ResourceType = 'User'
                                Identifier = "$userName/GroupMembership"
                                ExpectedValue = ($expectedGroups -join ', ')
                                ActualValue = ($actualGroupSamNames -join ', ')
                                Details = "User '$userName' is missing group memberships. Missing: $($missingGroups -join ', ')"
                            }
                            $mismatchCount++
                            
                            Write-TierModelLog -Level Info -Message "UserAuditMismatch" -Data @{
                                Name = $userName
                                Property = 'GroupMembership'
                                Expected = ($expectedGroups -join ', ')
                                Actual = ($actualGroupSamNames -join ', ')
                                MissingGroups = ($missingGroups -join ', ')
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        } else {
                            Write-Host "    ✅ Group memberships correct ($($expectedGroups -join ', '))" -ForegroundColor Green
                        }
                    } else {
                        Write-Host "    ✅ No group memberships required" -ForegroundColor Green
                    }
                    
                } catch {
                    $errorMsg = "Failed to audit user '$($user.displayName)': $($_.Exception.Message)"
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'External'
                        Code = 'UserAuditFailed'
                        Message = $errorMsg
                        Context = @{
                            UserName = $user.displayName
                            Exception = $_.Exception.Message
                        }
                    }
                    Write-TierModelLog -Level Error -Message "User audit failed" -Data @{
                        UserName = $user.displayName
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
            Write-Host "`n=== User Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total Users Checked: $totalChecked" -ForegroundColor White
            if ($missingCount -eq 0) {
                Write-Host "Missing Users: $missingCount ✅" -ForegroundColor Green
            } else {
                Write-Host "Missing Users: $missingCount ❌" -ForegroundColor Red
            }
            if ($mismatchCount -eq 0) {
                Write-Host "Configuration Mismatches: $mismatchCount ✅" -ForegroundColor Green
            } else {
                Write-Host "Configuration Mismatches: $mismatchCount ❌" -ForegroundColor Red
            }
            if ($driftCount -eq 0) {
                Write-Host "Overall Status: All Users are compliant ✅" -ForegroundColor Green
            } else {
                Write-Host "Overall Status: $driftCount issues found ❌" -ForegroundColor Red
            }
        }

        Write-TierModelLog -Level Info -Message "UserAuditComplete" -Data @{
            Summary = $summary
            DriftFindings = $driftFindings.Count
            CorrelationId = $CorrelationId
        } | Out-Null        # Build result object
        $result = [PSCustomObject]@{
            DriftFindings = $driftFindings
            Summary = $summary
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
        
        # Add resolved paths if requested
        if ($IncludeResolvedPaths) {
            $result | Add-Member -NotePropertyName 'ResolvedPaths' -NotePropertyValue $resolvedPaths
        }
        
        return $result
        
    } catch {
        Write-TierModelLog -Level Error -Message "User audit failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            DriftFindings = @()
            Summary = @{ TotalChecked = 0; MissingCount = 0; MismatchCount = 0; DriftCount = 0 }
            Warnings = @()
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'UserAuditFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            CorrelationId = $CorrelationId
        }
    }
}