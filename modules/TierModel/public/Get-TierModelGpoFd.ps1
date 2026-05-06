function Get-TierModelGpoFd {
    <#
    .SYNOPSIS
    Analyze TierModel GPO requirements for Full Deployment mode with relaxed validation.
    
    .DESCRIPTION
    Full Deployment variant of Get-TierModelGpo that assumes OUs and Groups from Phases 1-2
    will be created during deployment. Only validates components that must exist (like Domain DN)
    and performs GPO existence checks. Skips OU existence validation for custom OUs.
    
    .PARAMETER Config
    TierModel GPO configuration object containing GPO definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER IncludeDetails
    Include detailed analysis in the planning output for troubleshooting.
    
    .PARAMETER Silent
    Suppress action display output during planning.
    
    .EXAMPLE
    $plan = Get-TierModelGpoFd -Config $gpoConfig -DomainController "DC01"
    
    .OUTPUTS
    PSCustomObject with deployment plan including actions, summary, and analysis details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$IncludeDetails,
        
        [switch]$Silent
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "GPO Full Deployment planning start" -Data @{
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Helper function for GPO action analysis (defined at top to be available throughout)
        function Get-GpoActionsForConfig {
            param(
                [object]$GpoConfig,
                [string]$TargetOU,
                [bool]$IsTemplate,
                [string]$DomainController,
                [bool]$IsImportOnly
            )
            
            $actions = @()
            $gpoName = $GpoConfig.name
            
            try {
                # Check if GPO exists (with rename key support)
                $existingGpo = $null
                $actualGpoName = $gpoName  # Default to original name
                
                # First try direct name lookup
                try {
                    $existingGpo = Get-GPO -Name $gpoName -Server $DomainController -ErrorAction SilentlyContinue
                } catch {
                    # GPO doesn't exist with direct name, try rename key if present
                }
                
                # If not found and GPO has rename key, try wildcard matching
                if (-not $existingGpo -and $GpoConfig.PSObject.Properties.Name -contains 'rename') {
                    try {
                        $renamePattern = $GpoConfig.rename
                        $allGPOs = @(Get-GPO -All -Server $DomainController)
                        
                        # Try direct pattern match first
                        $matchingGPOs = @($allGPOs | Where-Object { $_.DisplayName -like $renamePattern })
                        
                        # If no matches with direct pattern, try alternative approach
                        if ($matchingGPOs.Count -eq 0) {
                            # Remove leading * and wrap with wildcards for better matching
                            $altPattern = $renamePattern -replace '^\*', ''
                            $matchingGPOs = @($allGPOs | Where-Object { $_.DisplayName -like "*$altPattern*" })
                        }
                        
                        if ($matchingGPOs.Count -gt 0) {
                            $existingGpo = $matchingGPOs[0]  # Use first match
                            $actualGpoName = $existingGpo.DisplayName
                        }
                    } catch {
                        # Wildcard search failed, GPO doesn't exist
                    }
                }
                
                if (-not $existingGpo) {
                    # GPO needs to be created - add full sequence
                    $actions += [PSCustomObject]@{
                        Action = 'CreateGPO'
                        Name = $actualGpoName
                        Path = $TargetOU
                        Data = $GpoConfig
                        Risk = 'Low'
                        IsTemplate = $IsTemplate
                    }
                    
                    # Add import action
                    $actions += [PSCustomObject]@{
                        Action = 'ImportGPO'
                        Name = $actualGpoName
                        Path = $TargetOU
                        Data = $GpoConfig
                        Risk = 'Low'
                        IsTemplate = $IsTemplate
                    }
                    
                    # Add configure action if not import-only and mode requires configuration
                    if (-not $IsImportOnly -and $GpoConfig.PSObject.Properties['mode'] -and $GpoConfig.mode -in @('createImportAndConfigure', 'importAndConfigure')) {
                        $actions += [PSCustomObject]@{
                            Action = 'ConfigureGPO'
                            Name = $actualGpoName
                            Path = $TargetOU
                            Data = $GpoConfig
                            Risk = 'Medium'
                            IsTemplate = $IsTemplate
                        }
                    }
                    
                    # Add link action if not template
                    if (-not $IsTemplate) {
                        $actions += [PSCustomObject]@{
                            Action = 'LinkGPO'
                            Name = $actualGpoName
                            Path = $TargetOU
                            Data = $GpoConfig
                            Risk = 'High'
                            IsTemplate = $IsTemplate
                        }
                    }
                } else {
                    # GPO exists - check what actions are still needed
                    if (-not $IsTemplate) {
                        # For Full Deployment: Check if GPO is linked, but only for domain root and built-in containers
                        # For custom OUs, assume linking will be done during deployment
                        $isDomainRoot = $TargetOU -match '^DC=.*,DC=.*$' -and $TargetOU -notmatch '^OU=' -and $TargetOU -notmatch '^CN='
                        $isBuiltinContainer = ($TargetOU -match '^OU=Domain Controllers,DC=') -or ($TargetOU -match '^CN=Builtin,DC=') -or ($TargetOU -match '^CN=Users,DC=')
                        
                        if ($isDomainRoot -or $isBuiltinContainer) {
                            # Check if GPO is linked to the target OU (only for built-in OUs)
                            try {
                                $existingLinks = Get-GPInheritance -Target $TargetOU -Server $DomainController -ErrorAction SilentlyContinue
                                $isLinked = $false
                                
                                if ($existingLinks -and $existingLinks.GpoLinks) {
                                    $isLinked = $existingLinks.GpoLinks | Where-Object { $_.DisplayName -eq $actualGpoName }
                                }
                                
                                if (-not $isLinked) {
                                    $actions += [PSCustomObject]@{
                                        Action = 'LinkGPO'
                                        Name = $actualGpoName
                                        Path = $TargetOU
                                        Data = $GpoConfig
                                        Risk = 'High'
                                        IsTemplate = $IsTemplate
                                    }
                                }
                            } catch {
                                # If we can't check built-in container links, assume linking is needed
                                $actions += [PSCustomObject]@{
                                    Action = 'LinkGPO'
                                    Name = $actualGpoName
                                    Path = $TargetOU
                                    Data = $GpoConfig
                                    Risk = 'High'
                                    IsTemplate = $IsTemplate
                                }
                            }
                        } else {
                            # For custom OUs, assume linking is needed (will be validated during execution)
                            $actions += [PSCustomObject]@{
                                Action = 'LinkGPO'
                                Name = $actualGpoName
                                Path = $TargetOU
                                Data = $GpoConfig
                                Risk = 'High'
                                IsTemplate = $IsTemplate
                            }
                        }
                    }
                }
            } catch {
                Write-Warning "Error analyzing GPO '$actualGpoName' (original: '$gpoName'): $($_.Exception.Message)"
            }
            
            return $actions
        }
        
        # Initialize plan structure
        $planActions = @()
        $planErrors = @()
        $warnings = @()
        $riskSummary = [PSCustomObject]@{
            Create = [int]0
            Import = [int]0
            Update = [int]0
            Link = [int]0
            LowRisk = [int]0
            MediumRisk = [int]0
            HighRisk = [int]0
        }
        
        # Count total GPOs for accurate summary
        $totalGpoCount = 0
        if ($Config.PSObject.Properties['gpos']) {
            foreach ($ouSection in $Config.gpos.PSObject.Properties) {
                $ouGpoData = $ouSection.Value
                if ($ouGpoData.PSObject.Properties['ImportOnlyGpo'] -and $ouGpoData.ImportOnlyGpo) {
                    $totalGpoCount += @($ouGpoData.ImportOnlyGpo).Count
                }
                if ($ouGpoData.PSObject.Properties['PostConfigureGpo'] -and $ouGpoData.PostConfigureGpo) {
                    $totalGpoCount += @($ouGpoData.PostConfigureGpo).Count
                }
            }
        }
        
        Write-TierModelLog -Level Info -Message "GPOs Full Deployment plan generation" | Out-Null
        if (-not $Silent) {
            Write-Host "Analyzing GPO requirements..." -ForegroundColor Cyan
        }
        
        # Get domain DN for placeholder replacement
        $domainDN = (Get-ADDomain -Server $DomainController).DistinguishedName
        
        # Check if GPOs are configured
        if ($Config.PSObject.Properties['gpos']) {
            foreach ($ouSection in $Config.gpos.PSObject.Properties) {
                $ouPath = $ouSection.Name
                $ouGpoData = $ouSection.Value
                
                # Handle TemplateGpos section separately - these are not linked to OUs
                $isTemplate = ($ouPath -eq "TemplateGpos")
                
                # Replace placeholders in OU path
                $resolvedOUPath = $ouPath -replace '\{\{DOMAIN_DN\}\}', $domainDN
                
                # Full Deployment: Only validate OUs that must exist (Domain root, built-in containers)
                # Skip validation for custom OUs as they will be created in Phase 1
                $ouExists = $true
                if (-not $isTemplate) {
                    # Check if this is the domain root or built-in containers (always exist)
                    $isDomainRoot = $resolvedOUPath -match '^DC=.*,DC=.*$' -and $resolvedOUPath -notmatch '^OU=' -and $resolvedOUPath -notmatch '^CN='
                    $isBuiltinContainer = ($resolvedOUPath -match '^OU=Domain Controllers,DC=') -or ($resolvedOUPath -match '^CN=Builtin,DC=') -or ($resolvedOUPath -match '^CN=Users,DC=')
                    
                    # Only validate built-in containers and domain root - assume custom OUs will be created
                    if ($isDomainRoot -or $isBuiltinContainer) {
                        try {
                            Get-ADOrganizationalUnit -Identity $resolvedOUPath -Server $DomainController -ErrorAction Stop | Out-Null
                        } catch {
                            # Extract just the OU name for cleaner error messages
                            $ouName = $resolvedOUPath
                            if ($resolvedOUPath -match '^OU=([^,]+)') {
                                $ouName = $matches[1]
                            } elseif ($resolvedOUPath -match '^CN=([^,]+)') {
                                $ouName = $matches[1]
                            }
                            
                            $planErrors += @{
                                Timestamp = Get-Date
                                Category = 'Validation'
                                Code = 'BuiltinOUNotFound'
                                Message = "Built-in OU/Container '$ouName' does not exist"
                                Context = @{
                                    OUPath = $resolvedOUPath
                                    OUName = $ouName
                                }
                            }
                            $ouExists = $false
                        }
                    }
                    # For custom OUs, assume they exist or will be created - no validation needed
                }
                
                # Process GPOs for this OU (continue even if OU validation failed for built-ins)
                if ($ouExists -or -not ($isDomainRoot -or $isBuiltinContainer)) {
                    # Process ImportOnlyGpo
                    if ($ouGpoData.PSObject.Properties['ImportOnlyGpo'] -and $ouGpoData.ImportOnlyGpo) {
                        foreach ($gpoConfig in $ouGpoData.ImportOnlyGpo) {
                            $gpoActions = Get-GpoActionsForConfig -GpoConfig $gpoConfig -TargetOU $resolvedOUPath -IsTemplate $isTemplate -DomainController $DomainController -IsImportOnly $true
                            $planActions += $gpoActions
                            
                            # Update risk counters
                            foreach ($action in $gpoActions) {
                                switch ($action.Action) {
                                    'CreateGPO' { $riskSummary.Create++ }
                                    'ImportGPO' { $riskSummary.Import++ }
                                    'ConfigureGPO' { $riskSummary.Update++ }
                                    'LinkGPO' { $riskSummary.Link++ }
                                }
                                
                                # Risk assessment
                                if ($action.Action -in @('CreateGPO', 'ImportGPO')) {
                                    $riskSummary.LowRisk++
                                } elseif ($action.Action -eq 'ConfigureGPO') {
                                    $riskSummary.MediumRisk++
                                } else {
                                    $riskSummary.HighRisk++
                                }
                            }
                        }
                    }
                    
                    # Process PostConfigureGpo
                    if ($ouGpoData.PSObject.Properties['PostConfigureGpo'] -and $ouGpoData.PostConfigureGpo) {
                        foreach ($gpoConfig in $ouGpoData.PostConfigureGpo) {
                            $gpoActions = Get-GpoActionsForConfig -GpoConfig $gpoConfig -TargetOU $resolvedOUPath -IsTemplate $isTemplate -DomainController $DomainController -IsImportOnly $false
                            $planActions += $gpoActions
                            
                            # Update risk counters
                            foreach ($action in $gpoActions) {
                                switch ($action.Action) {
                                    'CreateGPO' { $riskSummary.Create++ }
                                    'ImportGPO' { $riskSummary.Import++ }
                                    'ConfigureGPO' { $riskSummary.Update++ }
                                    'LinkGPO' { $riskSummary.Link++ }
                                }
                                
                                # Risk assessment
                                if ($action.Action -in @('CreateGPO', 'ImportGPO')) {
                                    $riskSummary.LowRisk++
                                } elseif ($action.Action -eq 'ConfigureGPO') {
                                    $riskSummary.MediumRisk++
                                } else {
                                    $riskSummary.HighRisk++
                                }
                            }
                        }
                    }
                }
            }
        }
        
        # Validate LinkGPO actions using dedicated link analysis function FIRST
        # This will show "✅ GPO Link Exists" messages during analysis
        if ($planActions | Where-Object { $_.Action -eq 'LinkGPO' }) {
            # Create temporary result object for link validation
            $tempResult = [PSCustomObject]@{
                Actions = $planActions
                Errors = $planErrors
            }
            
            # Get validated link actions (this will show link existence messages)
            if ($Silent) {
                $linkValidationResult = Get-TierModelGpoLinkFd -Plan $tempResult -DomainController $DomainController -Silent
            } else {
                $linkValidationResult = Get-TierModelGpoLinkFd -Plan $tempResult -DomainController $DomainController
            }
            
            # Replace LinkGPO actions with validated ones
            $nonLinkActions = @($planActions | Where-Object { $_.Action -ne 'LinkGPO' })
            $validatedLinkActions = if ($linkValidationResult -and $linkValidationResult.Actions) { @($linkValidationResult.Actions) } else { @() }
            $planActions = $nonLinkActions + $validatedLinkActions
        }
        
        # Show analysis results
        if (-not $Silent) {
            # Collect all GPO names from config
            $allGpoNames = @()
            if ($Config.PSObject.Properties['gpos']) {
                foreach ($ouSection in $Config.gpos.PSObject.Properties) {
                    $ouGpoData = $ouSection.Value
                    if ($ouGpoData.PSObject.Properties['ImportOnlyGpo'] -and $ouGpoData.ImportOnlyGpo) {
                        foreach ($gpo in $ouGpoData.ImportOnlyGpo) {
                            $allGpoNames += $gpo.name
                        }
                    }
                    if ($ouGpoData.PSObject.Properties['PostConfigureGpo'] -and $ouGpoData.PostConfigureGpo) {
                        foreach ($gpo in $ouGpoData.PostConfigureGpo) {
                            $allGpoNames += $gpo.name
                        }
                    }
                }
            }
            
            # GPO existence is now shown during link validation above
            # No need for separate GPO existence checking
            
            # Show planned actions if any exist
            if ($planActions.Count -gt 0) {
                Write-Host "Planned Actions:" -ForegroundColor Cyan
                
                # Group actions by GPO and show step-by-step plan
                # Handle actions that might not have Name property (like LinkGPO from validation)
                $actionsWithNames = @()
                foreach ($action in $planActions) {
                    $hasNameProperty = $action.PSObject.Properties.Name -contains 'Name'
                    if ($hasNameProperty -and $action.Name) {
                        $actionsWithNames += $action
                    } else {
                        # For actions without Name property, try to get GPO name from Data
                        if ($action.PSObject.Properties.Name -contains 'Data' -and $action.Data -and $action.Data.PSObject.Properties.Name -contains 'name') {
                            $actionWithName = $action.PSObject.Copy()
                            Add-Member -InputObject $actionWithName -MemberType NoteProperty -Name 'Name' -Value $action.Data.name -Force
                            $actionsWithNames += $actionWithName
                        }
                    }
                }
                $gpoGroups = $actionsWithNames | Group-Object Name
                
                foreach ($gpoGroup in $gpoGroups) {
                    $gpoName = $gpoGroup.Name
                    $gpoActions = $gpoGroup.Group | Sort-Object { 
                        switch ($_.Action) {
                            'CreateGPO' { 1 }
                            'ImportGPO' { 2 }
                            'ConfigureGPO' { 3 }
                            'LinkGPO' { 4 }
                            default { 5 }
                        }
                    }
                    
                    # Build action sequence display
                    $actionSequence = @()
                    
                    # Show all planned actions regardless of whether GPO exists
                    foreach ($action in $gpoActions) {
                        switch ($action.Action) {
                            'CreateGPO' { $actionSequence += "■ Create" }
                            'ImportGPO' { $actionSequence += "■ Import" }
                            'ConfigureGPO' { $actionSequence += "■ Configure" }
                            'LinkGPO' { $actionSequence += "■ Link" }
                        }
                    }
                    
                    if ($actionSequence.Count -gt 0) {
                        $sequenceDisplay = $actionSequence -join " > "
                        Write-Host "  $sequenceDisplay : $gpoName" -ForegroundColor Yellow
                    }
                }
            } elseif (@($allGpoNames).Count -eq 0) {
                Write-Host "  No GPOs configured." -ForegroundColor Gray
            } else {
                Write-Host "  No GPO actions needed - all GPOs are up to date." -ForegroundColor Green
            }
        }
        
        # Create result object
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        $result = [PSCustomObject]@{
            EntityType = 'GPO'
            Actions = $planActions
            Errors = $planErrors
            Warnings = $warnings
            Summary = [PSCustomObject]@{
                TotalGPOs = $totalGpoCount
                ActionsRequired = $planActions.Count
                CreateCount = @($planActions | Where-Object { $_.Action -eq 'CreateGPO' }).Count
                ImportCount = @($planActions | Where-Object { $_.Action -eq 'ImportGPO' }).Count
                ConfigureCount = @($planActions | Where-Object { $_.Action -eq 'ConfigureGPO' }).Count
                LinkCount = @($planActions | Where-Object { $_.Action -eq 'LinkGPO' }).Count
                ExistingCount = 0  # Full Deployment assumes fresh AD - no existing GPOs
                RiskSummary = $riskSummary
            }
            CorrelationId = $CorrelationId
            DurationMs = [int]$duration
        }
        
        Write-TierModelLog -Level Info -Message "GPO Full Deployment planning completed" -Data @{
            TotalActions = $planActions.Count
            DurationMs = $duration
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $result
        
    } catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        $errorMessage = "GPO Full Deployment planning failed: $($_.Exception.Message)"
        Write-TierModelLog -Level Error -Message $errorMessage -Data @{
            Exception = $_.Exception
            CorrelationId = $CorrelationId
            DurationMs = $duration
        } | Out-Null
        
        return [PSCustomObject]@{
            EntityType = 'GPO'
            Actions = @()
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'SystemError'
                Code = 'PlanningFailed'
                Message = $errorMessage
                Context = @{ Exception = $_.Exception }
            })
            Warnings = @()
            Summary = $null
            CorrelationId = $CorrelationId
            DurationMs = [int]$duration
        }
    }
}