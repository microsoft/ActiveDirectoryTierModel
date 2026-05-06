function Get-TierModelGpo {
    <#
    .SYNOPSIS
    Analyze TierModel GPO requirements and generate deployment plan.
    
    .DESCRIPTION
    Examines the TierModel GPO configuration and current Active Directory GPO state
    to generate a deployment plan for GPO creation, import, configuration, and linking.
    Validates target OUs exist, checks GPO existence, and determines which GPO operations need to be performed.
    
    .PARAMETER Config
    TierModel GPO configuration object containing GPO definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER IncludeDetails
    Include detailed analysis in the planning output for troubleshooting.
    
    .PARAMETER Silent
    Suppress action display output during planning. Used to prevent showing planned actions when dependency errors exist.
    
    .EXAMPLE
    $plan = Get-TierModelGpo -Config $gpoConfig -DomainController "DC01"
    
    .EXAMPLE
    $plan = Get-TierModelGpo -Config $gpoConfig -DomainController "DC01" -IncludeDetails
    
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
    
    Write-TierModelLog -Level Info -Message "GPO planning start" -Data @{
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Initialize plan structure
        $planActions = @()
        $planErrors = @()
        $warnings = @()
        $errors = @()
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
                    $totalGpoCount += $ouGpoData.ImportOnlyGpo.Count
                }
                if ($ouGpoData.PSObject.Properties['PostConfigureGpo'] -and $ouGpoData.PostConfigureGpo) {
                    $totalGpoCount += $ouGpoData.PostConfigureGpo.Count
                }
            }
        }
        
        Write-TierModelLog -Level Info -Message "GPOs-only deployment plan generation" | Out-Null
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
                
                # Validate target OU exists (skip for template GPOs)
                $ouExists = $true
                if (-not $isTemplate) {
                    # Check if this is the domain root or built-in containers (always exist)
                    $isDomainRoot = $resolvedOUPath -match '^DC=.*,DC=.*$' -and $resolvedOUPath -notmatch '^OU=' -and $resolvedOUPath -notmatch '^CN='
                    $isBuiltinContainer = ($resolvedOUPath -match '^OU=Domain Controllers,DC=') -or ($resolvedOUPath -match '^CN=Builtin,DC=') -or ($resolvedOUPath -match '^CN=Users,DC=')
                    
                    if (-not $isDomainRoot -and -not $isBuiltinContainer) {
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
                            
                            # Only add error if not already added for this OU
                            $existingError = $planErrors | Where-Object { $_.Code -eq 'TargetOUNotFound' -and $_.Context.OUPath -eq $resolvedOUPath }
                            if (-not $existingError) {
                                $planErrors += @{
                                    Timestamp = Get-Date
                                    Category = 'Validation'
                                    Code = 'TargetOUNotFound'
                                    Message = "Target OU '$ouName' does not exist - create OUs first"
                                    Context = @{
                                        OUPath = $resolvedOUPath
                                        GPOSection = $ouPath
                                    }
                                }
                            }
                            $ouExists = $false
                        }
                    }
                }
                
                # Skip entire OU section if OU doesn't exist, but only for non-template GPOs (template GPOs don't need linking)
                if (-not $ouExists -and -not $isTemplate) {
                    continue
                }
                
                # Process ImportOnlyGpo array
                if ($ouGpoData.PSObject.Properties['ImportOnlyGpo'] -and $ouGpoData.ImportOnlyGpo) {
                    foreach ($gpo in $ouGpoData.ImportOnlyGpo) {
                        try {
                            $gpoName = $gpo.name
                            $gpoMode = $gpo.mode
                            
                            # Check if GPO already exists (with rename key support)
                            $existingGPO = $null
                            $actualGpoName = $gpoName  # Default to original name
                            
                            # First try direct name lookup
                            try {
                                $existingGPO = Get-GPO -Name $gpoName -Server $DomainController -ErrorAction SilentlyContinue
                            } catch {
                                # GPO doesn't exist with direct name, try rename key if present
                            }
                            
                            # If not found and GPO has rename key, try wildcard matching
                            if (-not $existingGPO -and $gpo.PSObject.Properties.Name -contains 'rename') {
                                try {
                                    $renamePattern = $gpo.rename
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
                                        $existingGPO = $matchingGPOs[0]  # Use first match
                                        $actualGpoName = $existingGPO.DisplayName
                                    }
                                } catch {
                                    # Wildcard search failed, GPO doesn't exist
                                }
                            }
                            
                            # Validate required groups exist if GPO mode requires configuration
                            $allGroupsExist = $true
                            if ($gpoMode -in @('createImportAndConfigure')) {
                                # For Template GPOs, we can skip group validation since they're just templates
                                if (-not $isTemplate) {
                                    # Check if any groups from the TierModel configuration exist in AD
                                    if ($Config.PSObject.Properties['groups'] -and $Config.groups) {
                                        foreach ($group in $Config.groups) {
                                            if ($group.PSObject.Properties['samaccountname'] -and $group.samaccountname) {
                                                $groupName = $group.samaccountname
                                                try {
                                                    Get-ADGroup -Identity $groupName -Server $DomainController -ErrorAction Stop | Out-Null
                                                } catch {
                                                    # Only add error if not already added for this group
                                                    $existingError = $planErrors | Where-Object { $_.Code -eq 'RequiredGroupNotFound' -and $_.Context.GroupName -eq $groupName }
                                                    if (-not $existingError) {
                                                        $planErrors += @{
                                                            Timestamp = Get-Date
                                                            Category = 'Validation'
                                                            Code = 'RequiredGroupNotFound'
                                                            Message = "Required group '$groupName' does not exist - create Groups first"
                                                            Context = @{
                                                                GPOName = $gpoName
                                                                GroupName = $groupName
                                                                GPOMode = $gpoMode
                                                            }
                                                        }
                                                    }
                                                    $allGroupsExist = $false
                                                }
                                            }
                                        }
                                    } else {
                                        # No groups configured, but GPO needs configuration
                                        $allGroupsExist = $false
                                        $existingError = $planErrors | Where-Object { $_.Code -eq 'NoGroupsConfigured' }
                                        if (-not $existingError) {
                                            $planErrors += @{
                                                Timestamp = Get-Date
                                                Category = 'Validation'
                                                Code = 'NoGroupsConfigured'
                                                Message = "No groups configured but GPO requires configuration - create Groups first"
                                                Context = @{
                                                    GPOName = $gpoName
                                                    GPOMode = $gpoMode
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            # Skip this GPO if dependencies don't exist (except for Template GPOs which don't need dependencies)
                            if (-not $allGroupsExist -and -not $isTemplate) {
                                continue
                            }
                            
                            if (-not $existingGPO) {
                                
                                # Show yellow square for GPO that needs to be created
                                $actions = @('Create')
                                if ($gpoMode -in @('createAndImport', 'createImportAndConfigure')) {
                                    $actions += 'Import'
                                }
                                if ($gpoMode -in @('createImportAndConfigure')) {
                                    $actions += 'Configure'
                                }
                                if (-not $isTemplate) {
                                    $actions += 'Link'
                                }
                                $actionDesc = $actions -join ' → '
                                if (-not $Silent) {
                                    Write-Host "  ■ $actionDesc GPO: $gpoName" -ForegroundColor Yellow
                                }
                                
                                # Phase 1: Create GPO
                                $planActions += [PSCustomObject]@{
                                    Action = 'CreateGPO'
                                    ResourceType = 'GPO'
                                    Name = $actualGpoName
                                    Path = $resolvedOUPath
                                    Data = $gpo
                                    Mode = $gpoMode
                                    Phase = 1
                                }
                                
                                # Phase 2: Import settings if required
                                if ($gpoMode -in @('createAndImport', 'createImportAndConfigure')) {
                                    $planActions += [PSCustomObject]@{
                                        Action = 'ImportGPO'
                                        ResourceType = 'GPO'
                                        Name = "$actualGpoName (Import)"
                                        Path = $resolvedOUPath
                                        Data = $gpo
                                        GPOName = $actualGpoName
                                        Phase = 2
                                    }
                                    $riskSummary.Import++
                                }
                                
                                # Phase 5: Link GPO (skip for template GPOs)
                                if (-not $isTemplate) {
                                    $planActions += [PSCustomObject]@{
                                        Action = 'LinkGPO'
                                        ResourceType = 'GPO'
                                        Name = "$actualGpoName -> $resolvedOUPath"
                                        Path = $resolvedOUPath
                                        Data = $gpo
                                        GPOName = $actualGpoName
                                        Phase = 4
                                    }
                                }
                                
                                $riskSummary.Create++
                                if (-not $isTemplate) {
                                    $riskSummary.Link++
                                }
                                $riskSummary.MediumRisk++
                            } else {
                                # GPO exists, check if it's linked to the target OU
                                $gpoLinked = $false
                                try {
                                    # Check if GPO is linked to this OU
                                    $links = Get-GPInheritance -Target $resolvedOUPath -Server $DomainController -ErrorAction SilentlyContinue
                                    if ($links -and $links.GpoLinks) {
                                        $gpoLinked = $links.GpoLinks | Where-Object { $_.DisplayName -eq $actualGpoName } | Select-Object -First 1
                                    }
                                } catch {
                                    # OU might not exist yet or other error - we'll still plan the link
                                }
                                
                                if (-not $gpoLinked -and -not $isTemplate) {
                                    if (-not $Silent) {
                                        Write-Host "  ■ Link GPO: $actualGpoName" -ForegroundColor Yellow
                                    }
                                    
                                    # Phase 4: Link existing GPO
                                    $planActions += [PSCustomObject]@{
                                        Action = 'LinkGPO'
                                        ResourceType = 'GPO'
                                        Name = "$actualGpoName -> $resolvedOUPath"
                                        Path = $resolvedOUPath
                                        Data = $gpo
                                        GPOName = $actualGpoName
                                        Phase = 4
                                    }
                                    $riskSummary.Link++
                                    $riskSummary.LowRisk++
                                } elseif ($isTemplate) {
                                    # Template GPO exists - no message needed in plan mode
                                } else {
                                    # GPO exists and is properly linked - no message needed in plan mode
                                }
                            }
                        } catch {
                            Write-TierModelLog -Level Error -Message "GPO analysis failed" -Data @{
                                GPOName = $gpo.name
                                OUPath = $resolvedOUPath
                                Exception = $_.Exception.Message
                            }
                            if (-not $Silent) {
                                Write-Host "  ERROR: Failed to analyze GPO '$($gpo.name)' - $($_.Exception.Message)" -ForegroundColor Red
                            }
                            
                            $planErrors += @{
                                Timestamp = Get-Date
                                Category = 'Analysis'
                                Code = 'GPOAnalysisFailed'
                                Message = $_.Exception.Message
                                Context = @{
                                    GPOName = $gpo.name
                                    OUPath = $resolvedOUPath
                                }
                            }
                        }
                    }
                }
                
                # Process PostConfigureGpo array 
                if ($ouGpoData.PSObject.Properties['PostConfigureGpo'] -and $ouGpoData.PostConfigureGpo) {
                    foreach ($gpo in $ouGpoData.PostConfigureGpo) {
                        try {
                            $gpoName = $gpo.name
                            $gpoMode = $gpo.mode
                            
                            # Check if GPO already exists (with rename key support)
                            $existingGPO = $null
                            $actualGpoName = $gpoName  # Default to original name
                            
                            # First try direct name lookup
                            try {
                                $existingGPO = Get-GPO -Name $gpoName -Server $DomainController -ErrorAction SilentlyContinue
                            } catch {
                                # GPO doesn't exist with direct name, try rename key if present
                            }
                            
                            # If not found and GPO has rename key, try wildcard matching
                            if (-not $existingGPO -and $gpo.PSObject.Properties.Name -contains 'rename') {
                                try {
                                    $renamePattern = $gpo.rename
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
                                        $existingGPO = $matchingGPOs[0]  # Use first match
                                        $actualGpoName = $existingGPO.DisplayName
                                    }
                                } catch {
                                    # Wildcard search failed, GPO doesn't exist
                                }
                            }
                            
                            # Validate required groups exist if GPO mode requires configuration
                            $allGroupsExist = $true
                            if ($gpoMode -in @('createImportAndConfigure', 'importAndConfigure')) {
                                # For Template GPOs, we can skip group validation since they're just templates
                                if (-not $isTemplate) {
                                    # Check if any groups from the TierModel configuration exist in AD
                                    if ($Config.PSObject.Properties['groups'] -and $Config.groups) {
                                        foreach ($group in $Config.groups) {
                                            if ($group.PSObject.Properties['samaccountname'] -and $group.samaccountname) {
                                                $groupName = $group.samaccountname
                                                try {
                                                    Get-ADGroup -Identity $groupName -Server $DomainController -ErrorAction Stop | Out-Null
                                                } catch {
                                                    # Only add error if not already added for this group
                                                    $existingError = $planErrors | Where-Object { $_.Code -eq 'RequiredGroupNotFound' -and $_.Context.GroupName -eq $groupName }
                                                    if (-not $existingError) {
                                                        $planErrors += @{
                                                            Timestamp = Get-Date
                                                            Category = 'Validation'
                                                            Code = 'RequiredGroupNotFound'
                                                            Message = "Required group '$groupName' does not exist - create Groups first"
                                                            Context = @{
                                                                GPOName = $gpoName
                                                                GroupName = $groupName
                                                                GPOMode = $gpoMode
                                                            }
                                                        }
                                                    }
                                                    $allGroupsExist = $false
                                                }
                                            }
                                        }
                                    } else {
                                        # No groups configured, but GPO needs configuration
                                        $allGroupsExist = $false
                                        $existingError = $planErrors | Where-Object { $_.Code -eq 'NoGroupsConfigured' }
                                        if (-not $existingError) {
                                            $planErrors += @{
                                                Timestamp = Get-Date
                                                Category = 'Validation'
                                                Code = 'NoGroupsConfigured'
                                                Message = "No groups configured but GPO requires configuration - create Groups first"
                                                Context = @{
                                                    GPOName = $gpoName
                                                    GPOMode = $gpoMode
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            # Skip this GPO if dependencies don't exist (except for Template GPOs which don't need dependencies)
                            if (-not $allGroupsExist -and -not $isTemplate) {
                                continue
                            }
                            
                            if (-not $existingGPO) {
                                # Show yellow square for GPO that needs to be created
                                $actions = @('Create')
                                if ($gpoMode -in @('createAndImport', 'createImportAndConfigure')) {
                                    $actions += 'Import'
                                }
                                if ($gpoMode -in @('createImportAndConfigure', 'importAndConfigure')) {
                                    $actions += 'Configure'
                                }
                                if (-not $isTemplate) {
                                    $actions += 'Link'
                                }
                                $actionDesc = $actions -join ' → '
                                if (-not $Silent) {
                                    Write-Host "  ■ $actionDesc GPO: $gpoName" -ForegroundColor Yellow
                                }
                                
                                # Phase 1: Create GPO
                                $planActions += [PSCustomObject]@{
                                    Action = 'CreateGPO'
                                    ResourceType = 'GPO'
                                    Name = $gpoName
                                    Path = $resolvedOUPath
                                    Data = $gpo
                                    Mode = $gpoMode
                                    Phase = 1
                                }
                                
                                # Phase 2: Import settings if required
                                if ($gpoMode -in @('createAndImport', 'createImportAndConfigure')) {
                                    $planActions += [PSCustomObject]@{
                                        Action = 'ImportGPO'
                                        ResourceType = 'GPO'
                                        Name = "$actualGpoName (Import)"
                                        Path = $resolvedOUPath
                                        Data = $gpo
                                        GPOName = $actualGpoName
                                        Phase = 2
                                    }
                                    $riskSummary.Import++
                                }
                                
                                # Phase 3: Configure GPO if required
                                if ($gpoMode -in @('createImportAndConfigure', 'importAndConfigure')) {
                                    $planActions += [PSCustomObject]@{
                                        Action = 'ConfigureGPO'
                                        ResourceType = 'GPO'
                                        Name = "$actualGpoName (Configure)"
                                        Path = $resolvedOUPath
                                        Data = $gpo
                                        GPOName = $actualGpoName
                                        Phase = 3
                                    }
                                    $riskSummary.Update++
                                }
                                
                                # Phase 4: Link GPO (skip for template GPOs)
                                if (-not $isTemplate) {
                                    $planActions += [PSCustomObject]@{
                                        Action = 'LinkGPO'
                                        ResourceType = 'GPO'
                                        Name = "$actualGpoName -> $resolvedOUPath"
                                        Path = $resolvedOUPath
                                        Data = $gpo
                                        GPOName = $actualGpoName
                                        Phase = 4
                                    }
                                }
                                
                                $riskSummary.Create++
                                if (-not $isTemplate) {
                                    $riskSummary.Link++
                                }
                                $riskSummary.HighRisk++
                            } else {
                                # GPO exists, check if it's linked to the target OU
                                $gpoLinked = $false
                                try {
                                    # Check if GPO is linked to this OU
                                    $links = Get-GPInheritance -Target $resolvedOUPath -Server $DomainController -ErrorAction SilentlyContinue
                                    if ($links -and $links.GpoLinks) {
                                        $gpoLinked = $links.GpoLinks | Where-Object { $_.DisplayName -eq $actualGpoName } | Select-Object -First 1
                                    }
                                } catch {
                                    # OU might not exist yet or other error - we'll still plan the link
                                }
                                
                                if (-not $gpoLinked -and -not $isTemplate) {
                                    # Show yellow square for GPO that needs to be linked
                                    if (-not $Silent) {
                                        Write-Host "  ■ Link GPO: $actualGpoName" -ForegroundColor Yellow
                                    }
                                    
                                    # Phase 4: Link existing GPO
                                    $planActions += [PSCustomObject]@{
                                        Action = 'LinkGPO'
                                        ResourceType = 'GPO'
                                        Name = "$actualGpoName -> $resolvedOUPath"
                                        Path = $resolvedOUPath
                                        Data = $gpo
                                        GPOName = $actualGpoName
                                        Phase = 4
                                    }
                                    $riskSummary.Link++
                                    $riskSummary.LowRisk++
                                } elseif ($isTemplate) {
                                    # Template GPO exists - no message needed in plan mode
                                } else {
                                    # GPO exists and is properly linked - no message needed in plan mode
                                }
                            }
                        } catch {
                            Write-TierModelLog -Level Error -Message "GPO analysis failed" -Data @{
                                GPOName = $gpo.name
                                OUPath = $resolvedOUPath
                                Exception = $_.Exception.Message
                            }
                            if (-not $Silent) {
                                Write-Host "  ERROR: Failed to analyze GPO '$($gpo.name)' - $($_.Exception.Message)" -ForegroundColor Red
                            }
                            
                            $planErrors += @{
                                Timestamp = Get-Date
                                Category = 'Analysis'
                                Code = 'GPOAnalysisFailed'
                                Message = $_.Exception.Message
                                Context = @{
                                    GPOName = $gpo.name
                                    OUPath = $resolvedOUPath
                                }
                            }
                        }
                    }
                }
            }
            
            $createCount = if ($planActions) { @($planActions | Where-Object { $_.Action -eq 'CreateGPO' }).Count } else { 0 }
            $linkCount = if ($planActions) { @($planActions | Where-Object { $_.Action -eq 'LinkGPO' }).Count } else { 0 }
            $configureCount = if ($planActions) { @($planActions | Where-Object { $_.Action -eq 'ConfigureGPO' }).Count } else { 0 }
            
            Write-TierModelLog -Level Info -Message "GPOs deployment plan completed" -Data @{
                TotalGPOsToCreate = $createCount
                TotalGPOsToLink = $linkCount
                TotalGPOsToConfigure = $configureCount
            } | Out-Null
        } else {
            Write-TierModelLog -Level Warning -Message "No GPOs found in configuration" | Out-Null
            Write-TierModelLog -Level Info -Message "GPOs deployment plan completed" -Data @{
                TotalGPOsToCreate = 0
                TotalGPOsToLink = 0  
                TotalGPOsToConfigure = 0
            } | Out-Null
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "GPO planning complete" -Data @{
            TotalActions = if ($planActions) { $planActions.Count } else { 0 }
            CreateActions = @($planActions | Where-Object { $_.Action -eq 'CreateGPO' } | ForEach-Object { $_ }).Count
            ImportActions = @($planActions | Where-Object { $_.Action -eq 'ImportGPO' } | ForEach-Object { $_ }).Count
            ConfigureActions = @($planActions | Where-Object { $_.Action -eq 'ConfigureGPO' } | ForEach-Object { $_ }).Count
            LinkActions = @($planActions | Where-Object { $_.Action -eq 'LinkGPO' } | ForEach-Object { $_ }).Count
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        # Combine all errors
        $allErrors = $planErrors + $errors
        
        # Calculate action counts for the summary
        $totalActionCount = if ($planActions) { $planActions.Count } else { 0 }
        $existingGpoCount = $totalGpoCount - $totalActionCount  # GPOs that need no action
        
        return [PSCustomObject]@{
            Actions = $planActions
            Summary = @{
                TotalInConfig = $totalGpoCount
                ToCreate = @($planActions | Where-Object { $_.Action -eq 'CreateGPO' }).Count
                ExistingCount = $existingGpoCount
                TotalActions = $totalActionCount
                CreateActions = @($planActions | Where-Object { $_.Action -eq 'CreateGPO' } | ForEach-Object { $_ }).Count
                ImportActions = @($planActions | Where-Object { $_.Action -eq 'ImportGPO' } | ForEach-Object { $_ }).Count
                ConfigureActions = @($planActions | Where-Object { $_.Action -eq 'ConfigureGPO' } | ForEach-Object { $_ }).Count
                LinkActions = @($planActions | Where-Object { $_.Action -eq 'LinkGPO' } | ForEach-Object { $_ }).Count
                RiskAssessment = $riskSummary
            }
            Analysis = @{
                ConfiguredGpos = if ($Config.gpos) { $Config.gpos.Count } else { 0 }
                ValidationErrors = if ($allErrors) { $allErrors.Count } else { 0 }
            }
            Errors = $allErrors
            Warnings = $warnings
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "GPO planning failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = @()
            Summary = @{
                TotalActions = 0
                CreateActions = 0
                ImportActions = 0
                ConfigureActions = 0
                LinkActions = 0
                RiskAssessment = @{
                    Create = 0; Import = 0; Update = 0; Link = 0
                    LowRisk = 0; MediumRisk = 0; HighRisk = 1
                }
            }
            Analysis = @{
                ConfiguredGpos = 0
                ValidationErrors = 1
            }
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'GPOPlanningFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            Warnings = @()
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}