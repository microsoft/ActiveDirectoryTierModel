function Get-TierModelUserFd {
    <#
    .SYNOPSIS
    Generate deployment plan for TierModel user accounts (Full Deployment variant).
    
    .DESCRIPTION
    Analyzes the TierModel configuration to identify user accounts that need to be created for full deployment scenarios.
    This variant uses lighter validation - only checks if users exist in AD, assumes OUs and Groups will be created by earlier phases.
    Compares configuration against existing Active Directory state and generates a structured deployment plan.
    
    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelUserFd -Config $config -DomainController "DC01.contoso.com"
    
    .OUTPUTS
    PSCustomObject with deployment plan including actions array and summary counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController
    )
    
    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    
    Write-TierModelLog -Level Info -Message "UserFdPlanStart" -Data @{
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $planActions = @()
        $errors = @()
        $warnings = @()
        $riskSummary = @{ Create = 0; Update = 0; LowRisk = 0; }
        
        # Get domain DN for placeholder replacement
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        # Check which Users need to be created by comparing config with existing AD structure
        if ($Config.PSObject.Properties['users']) {
            foreach ($user in $Config.users) {
                try {
                    # Replace placeholders in user OU path
                    $resolvedPath = Resolve-TierModelPlaceholder -Path $user.ouPath -DomainDN $domainDN
                    $userName = $user.displayName
                    $userSamAccountName = $user.samAccountName
                    
                    # Full Deployment variant: Skip OU and Group validation
                    # Assume Phase 1 will create OUs and Phase 2 will create Groups
                    
                    # Check if user already exists - this is the only check we need
                    $existingUser = $null
                    try {
                        $existingUser = Get-ADUser -Identity $userSamAccountName -Server $DomainController -ErrorAction SilentlyContinue
                    } catch {
                        # User doesn't exist, which is fine - we'll create it
                    }
                    
                    if (-not $existingUser) {
                        # User will be created - add to plan actions
                        
                        $planActions += [PSCustomObject]@{
                            Action = 'CreateUser'
                            ResourceType = 'User'
                            Name = $userName
                            Path = $resolvedPath
                            Data = $user
                        }
                        $riskSummary.Create++
                        $riskSummary.LowRisk++
                        
                        # Add separate actions for group memberships if specified
                        if ($user.PSObject.Properties['memberOf'] -and $user.memberOf -and $user.memberOf.Count -gt 0) {
                            foreach ($groupName in $user.memberOf) {
                                $planActions += [PSCustomObject]@{
                                    Action = 'UpdateUserMembership'
                                    ResourceType = 'User'
                                    Name = "$userName -> $groupName"
                                    Path = $resolvedPath
                                    Data = @{
                                        UserName = $userName
                                        UserSamAccountName = $userSamAccountName
                                        GroupName = $groupName
                                    }
                                }
                                $riskSummary.Update++
                                $riskSummary.LowRisk++
                            }
                        }
                    } else {
                        Write-TierModelLog -Level Info -Message "UserFdPlanExists" -Data @{
                            UserName = $userName
                            UserSamAccountName = $userSamAccountName
                            DistinguishedName = $existingUser.DistinguishedName
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    }
                } catch {
                    Write-TierModelLog -Level Error -Message "User Fd analysis failed" -Data @{
                        UserName = $user.displayName
                        UserPath = $user.ouPath
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'External'
                        Code = 'UserFdPlanFailed'
                        Message = "Failed to analyze user '$($user.displayName)': $($_.Exception.Message)"
                        Context = @{
                            UserName = $user.displayName
                            UserPath = $user.ouPath
                            Exception = $_.Exception.Message
                        }
                    }
                }
            }
            
            Write-TierModelLog -Level Info -Message "Users Fd deployment plan completed" -Data @{
                TotalUsersInConfig = $Config.users.Count
                UsersToCreate = @($planActions | Where-Object { $_.Action -eq 'CreateUser' }).Count
                CorrelationId = $CorrelationId
            } | Out-Null
        } else {
            Write-TierModelLog -Level Warning -Message "No users found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No users section found in configuration"
        }
        
        # Return deployment plan
        return [PSCustomObject]@{
            Actions = $planActions
            Summary = @{
                TotalInConfig = if ($Config.PSObject.Properties['users']) { $Config.users.Count } else { 0 }
                ToCreate = @($planActions | Where-Object { $_.Action -eq 'CreateUser' }).Count
                ToUpdate = @($planActions | Where-Object { $_.Action -eq 'UpdateUserMembership' }).Count
                ExistingCount = if ($Config.PSObject.Properties['users']) { $Config.users.Count - (@($planActions | Where-Object { $_.Action -eq 'CreateUser' }).Count) } else { 0 }
            }
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "User Fd planning failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = @()
            Summary = @{
                TotalInConfig = 0
                ToCreate = 0
                ToUpdate = 0
                ExistingCount = 0
            }
            Warnings = @()
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Planning'
                Code = 'UserFdPlanningFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            CorrelationId = $CorrelationId
        }
    }
}