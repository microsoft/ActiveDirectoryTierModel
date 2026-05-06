function Get-TierModelUser {
    <#
    .SYNOPSIS
    Generate deployment plan for TierModel user accounts.
    
    .DESCRIPTION
    Analyzes the TierModel configuration to identify user accounts that need to be created.
    Compares configuration against existing Active Directory state and generates
    a structured deployment plan with creation actions.
    
    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelUser -Config $config -DomainController "DC01.contoso.com"
    
    .OUTPUTS
    PSCustomObject with deployment plan including actions array and summary counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$Silent
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    
    Write-TierModelLog -Level Info -Message "UserPlanStart" -Data @{
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
                    
                    # Validate target OU exists before checking user
                    $targetOUExists = $false
                    try {
                        Get-ADOrganizationalUnit -Identity $resolvedPath -Server $DomainController -ErrorAction Stop | Out-Null
                        $targetOUExists = $true
                    } catch {
                        # Extract just the OU name for cleaner error messages
                        $ouName = if ($resolvedPath -match '^OU=([^,]+)') { $matches[1] } else { $resolvedPath }
                        $errors += @{
                            Timestamp = Get-Date
                            Category = 'Validation'
                            Code = 'TargetOUNotFound'
                            Message = "Target OU '$ouName' does not exist - create OUs first"
                            Context = @{
                                UserName = $userName
                                UserSamAccountName = $userSamAccountName
                                TargetOUPath = $resolvedPath
                            }
                        }
                    }
                    
                    # Validate required groups exist if memberOf is specified
                    $allGroupsExist = $true
                    if ($user.PSObject.Properties['memberOf'] -and $user.memberOf -and $user.memberOf.Count -gt 0) {
                        foreach ($groupName in $user.memberOf) {
                            try {
                                Get-ADGroup -Identity $groupName -Server $DomainController -ErrorAction Stop | Out-Null
                            } catch {
                                $errors += @{
                                    Timestamp = Get-Date
                                    Category = 'Validation'
                                    Code = 'RequiredGroupNotFound'
                                    Message = "Required group '$groupName' does not exist - create Groups first"
                                    Context = @{
                                        UserName = $userName
                                        UserSamAccountName = $userSamAccountName
                                        RequiredGroup = $groupName
                                    }
                                }
                                $allGroupsExist = $false
                            }
                        }
                    }
                    
                    # Skip this user if dependencies don't exist
                    if (-not $targetOUExists -or -not $allGroupsExist) {
                        continue
                    }
                    
                    # Check if user already exists
                    $existingUser = $null
                    try {
                        $existingUser = Get-ADUser -Identity $userSamAccountName -Server $DomainController -ErrorAction SilentlyContinue
                    } catch {
                        # User doesn't exist, which is fine - we'll create it
                    }
                    
                    if (-not $existingUser) {
                        # User will be created - add to plan actions (output will be shown in Planned Actions section)
                        
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
                        if (-not $Silent) {
                            Write-Host "  User exists: $userName ($userSamAccountName)" -ForegroundColor Green
                        }
                    }
                } catch {
                    Write-TierModelLog -Level Error -Message "User analysis failed" -Data @{
                        UserName = $user.displayName
                        UserPath = $user.ouPath
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    Write-Host "  ERROR: Failed to analyze user '$($user.displayName)' - $($_.Exception.Message)" -ForegroundColor Red
                    throw
                }
            }
            
            Write-TierModelLog -Level Info -Message "Users deployment plan completed" -Data @{
                TotalUsersInConfig = $Config.users.Count
                UsersToCreate = @($planActions | Where-Object { $_.Action -eq 'CreateUser' }).Count
                CorrelationId = $CorrelationId
            } | Out-Null
        } else {
            Write-TierModelLog -Level Warning -Message "No users found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No users section found in configuration"
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
        Write-TierModelLog -Level Error -Message "User planning failed" -Data @{
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
                Code = 'UserPlanningFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            CorrelationId = $CorrelationId
        }
    }
}