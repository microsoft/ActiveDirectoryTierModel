function Get-TierModelGroup {
    <#
    .SYNOPSIS
    Generate deployment plan for security groups based on TierModel configuration.
    
    .DESCRIPTION
    Analyzes TierModel configuration to identify groups that need to be created.
    Compares configuration with current Active Directory state and returns
    structured actions for group creation, including required metadata.
    
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
    $plan = Get-TierModelGroup -Config $config -DomainController "DC01.contoso.com"
    
    .EXAMPLE
    $plan = Get-TierModelGroup -Config $config -DomainController "DC01.contoso.com" -IncludeDetails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$IncludeDetails
    )
    
    $CorrelationId = $script:CorrelationId
    Write-TierModelLog -Level Info -Message "GroupPlanStart" -Data @{
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
                    
                    Write-TierModelLog -Level Debug -Message "GroupPlanCheck" -Data @{
                        Name = $groupName
                        SamAccountName = $groupSamAccountName
                        Path = $resolvedPath
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Validate target OU exists before checking group
                    try {
                        Get-ADOrganizationalUnit -Identity $resolvedPath -Server $DomainController -ErrorAction Stop | Out-Null
                    } catch {
                        # Extract just the OU name for cleaner error messages
                        $ouName = if ($resolvedPath -match '^OU=([^,]+)') { $matches[1] } else { $resolvedPath }
                        $errors += @{
                            Timestamp = Get-Date
                            Category = 'Validation'
                            Code = 'TargetOUNotFound'
                            Message = "Target OU '$ouName' does not exist - create OUs first"
                            Context = @{
                                GroupName = $groupName
                                GroupSamAccountName = $groupSamAccountName
                                TargetOUPath = $resolvedPath
                            }
                        }
                        continue  # Skip this group if OU doesn't exist
                    }
                    
                    # Check if group already exists
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
                        
                        Write-TierModelLog -Level Info -Message "GroupPlanCreate" -Data @{
                            Name = $groupName
                            SamAccountName = $groupSamAccountName
                            Path = $resolvedPath
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    } else {
                        # Group already exists
                        $existingCount++
                        
                        Write-TierModelLog -Level Info -Message "GroupPlanExists" -Data @{
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
                        Code = 'GroupPlanFailed'
                        Message = $errorMsg
                        Context = @{
                            GroupName = $group.name
                            GroupPath = $group.path
                            Exception = $_.Exception.Message
                        }
                    }
                    Write-TierModelLog -Level Error -Message "Group plan failed" -Data @{
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
        
        Write-TierModelLog -Level Info -Message "GroupPlanComplete" -Data @{
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
            Code = 'GroupPlanFailed'
            Message = "Group plan generation failed: $($_.Exception.Message)"
            Context = @{
                Exception = $_.Exception.Message
            }
        }
        Write-TierModelLog -Level Error -Message "Group plan generation failed" -Data @{
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