function Get-TierModelGroupFd {
    <#
    .SYNOPSIS
    Generate deployment plan for security groups based on TierModel configuration (Full Deployment variant).
    
    .DESCRIPTION
    Analyzes TierModel configuration to identify groups that need to be created for full deployment scenarios.
    This variant uses lighter validation - only checks if groups exist in AD, assumes OUs will be created by Phase 1.
    Compares configuration with current Active Directory state and returns structured actions for group creation.
    
    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.
    
    .PARAMETER DomainController
    Preferred domain controller for AD queries.
    
    .PARAMETER IncludeDetails
    Include additional planning details in output (paths, dependencies, etc.).
    
    .OUTPUTS
    PSCustomObject with Actions, Summary, Warnings, Errors, and optional details.
    
    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelGroupFd -Config $config -DomainController "DC01.contoso.com"
    
    .EXAMPLE
    $plan = Get-TierModelGroupFd -Config $config -DomainController "DC01.contoso.com" -IncludeDetails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$IncludeDetails
    )
    
    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    Write-TierModelLog -Level Info -Message "GroupFdPlanStart" -Data @{
        CorrelationId = $CorrelationId
        DomainController = $DomainController
        IncludeDetails = $IncludeDetails.IsPresent
    } | Out-Null
    
    $actions = @()
    $warnings = @()
    $errors = @()
    $totalInConfig = 0
    $toCreate = 0
    $existingCount = 0
    
    try {
        # Resolve domain DN
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        # Check if groups exists in config
        if (-not $Config.PSObject.Properties['groups'] -or -not $Config.groups) {
            Write-TierModelLog -Level Warning -Message "No groups found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No groups section found in configuration"
        } else {
            $totalInConfig = $Config.groups.Count
            
            foreach ($group in $Config.groups) {
                try {
                    # Replace placeholders in group path
                    $resolvedPath = Resolve-TierModelPlaceholder -Path $group.path -DomainDN $domainDN
                    $groupName = $group.name
                    $groupSamAccountName = $group.samaccountname
                    
                    Write-TierModelLog -Level Debug -Message "GroupFdPlanCheck" -Data @{
                        Name = $groupName
                        SamAccountName = $groupSamAccountName
                        Path = $resolvedPath
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Full Deployment variant: Skip OU validation - assume Phase 1 will create OUs
                    # Only check if group already exists in AD
                    $existingGroup = $null
                    try {
                        $existingGroup = Get-ADGroup -Identity $groupSamAccountName -Server $DomainController -ErrorAction SilentlyContinue
                    } catch {
                        # Group doesn't exist, which is expected for planning
                    }
                    
                    if (-not $existingGroup) {
                        # Group needs to be created
                        $actions += [PSCustomObject]@{
                            Action = 'CreateGroup'
                            ResourceType = 'Group'
                            Name = $groupName
                            Path = $resolvedPath
                            Data = $group
                        }
                        $toCreate++
                        
                        Write-TierModelLog -Level Info -Message "GroupFdPlanCreate" -Data @{
                            Name = $groupName
                            SamAccountName = $groupSamAccountName
                            Path = $resolvedPath
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        # Group already exists
                        $existingCount++
                        
                        Write-TierModelLog -Level Info -Message "GroupFdPlanExists" -Data @{
                            Name = $groupName
                            SamAccountName = $groupSamAccountName
                            DistinguishedName = $existingGroup.DistinguishedName
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    }
                } catch {
                    $errorMsg = "Failed to analyze group '$($group.name)': $($_.Exception.Message)"
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'External'
                        Code = 'GroupFdPlanFailed'
                        Message = $errorMsg
                        Context = @{
                            GroupName = $group.name
                            GroupPath = $group.path
                            Exception = $_.Exception.Message
                        }
                    }
                    Write-TierModelLog -Level Error -Message "Group Fd plan failed" -Data @{
                        GroupName = $group.name
                        GroupPath = $group.path
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                }
            }
        }
        
        $summary = @{
            TotalInConfig = $totalInConfig
            ToCreate = $toCreate
            ExistingCount = $existingCount
        }
        
        Write-TierModelLog -Level Info -Message "GroupFdPlanComplete" -Data @{
            Summary = $summary
            ActionsCount = $actions.Count
            WarningCount = $warnings.Count
            ErrorCount = $errors.Count
            CorrelationId = $CorrelationId
        } | Out-Null
        
        $result = [PSCustomObject]@{
            Actions = $actions
            Summary = $summary
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
        
        return $result
        
    } catch {
        $errors += @{
            Timestamp = Get-Date
            Category = 'Execution'
            Code = 'GroupFdPlanFailed'
            Message = "Group Fd plan generation failed: $($_.Exception.Message)"
            Context = @{
                Exception = $_.Exception.Message
            }
        }
        Write-TierModelLog -Level Error -Message "Group Fd plan generation failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = @()
            Summary = @{ TotalInConfig = $totalInConfig; ToCreate = $toCreate; ExistingCount = $existingCount }
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
    }
}