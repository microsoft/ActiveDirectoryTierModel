function Get-TierModelGpoLinkFd {
    <#
    .SYNOPSIS
    Plan TierModel GPO link operations for Full Deployment mode with relaxed validation.
    
    .DESCRIPTION
    Full Deployment variant of Get-TierModelGPOLink that assumes OUs from Phase 1 will be
    created during deployment. Only validates links for built-in containers and domain root,
    assumes custom OUs will be available during linking phase.
    
    .PARAMETER Plan
    Deployment plan object from Get-TierModelGpoFd containing GPO and OU information.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .EXAMPLE
    $gpoplan = Get-TierModelGpoFd -Config $gpoConfig -DomainController "DC01"
    $linkplan = Get-TierModelGpoLinkFd -Plan $gpoplan -DomainController "DC01"
    
    .OUTPUTS
    PSCustomObject with link planning results including actions to execute.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$Silent
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "GPO Link Full Deployment planning start" -Data @{
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $linkActions = @()
        $errors = @()
        $converged = $true
        
        # Process each GPO that needs linking
        $linkGpoActions = @($Plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' })
        
        foreach ($action in $linkGpoActions) {
            try {
                $gpoData = $action.Data
                $gpoName = $gpoData.name
                $targetOUPath = $action.Path
                
                # Extract settings with defaults (matching original working code)
                $requiredEnforced = if ($gpoData.PSObject.Properties.Name -contains 'enforced') { $gpoData.enforced } else { 'No' }

                # Check if GPO exists first - show green check if it does (with rename key support)
                $gpo = $null
                $actualGpoName = $gpoName  # Default to original name
                
                # First try direct name lookup
                try {
                    $gpo = Get-GPO -Name $gpoName -Server $DomainController -ErrorAction SilentlyContinue
                } catch {
                    # GPO doesn't exist with direct name, try rename key if present
                }
                
                # If not found and GPO has rename key, try wildcard matching
                if (-not $gpo -and $gpoData.PSObject.Properties.Name -contains 'rename') {
                    try {
                        $renamePattern = $gpoData.rename
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
                            $gpo = $matchingGPOs[0]
                            $actualGpoName = $gpo.DisplayName
                        }
                    } catch {
                        Write-Warning "Error during rename pattern matching for GPO '$gpoName': $($_.Exception.Message)"
                    }
                }
                
                if ($gpo) {
                    if (-not $Silent) {
                        Write-Host "  ✅ GPO Exists: $actualGpoName" -ForegroundColor Green
                    }
                } else {
                    # GPO doesn't exist - skip link checking and continue planning
                    $linkActions += [PSCustomObject]@{
                        Action = 'LinkGPO'
                        Priority = 'Medium'
                        Risk = 'Medium'
                        Path = $targetOUPath
                        Data = $gpoData
                        RequiredState = @{
                            GPOExists = $false
                            LinkExists = $false
                            Order = $gpoData.linkOrder
                            Enforced = $requiredEnforced
                        }
                        CurrentState = @{
                            GPOExists = $false
                            LinkExists = $false
                            Order = $null
                            Enforced = $null
                        }
                        Reason = "GPO must be created before linking"
                        Dependencies = @("CreateGPO:$gpoName")
                    }
                    continue
                }
                
                # Check current link status
                $existingLinks = @()
                $currentLinkOrder = $null
                $currentEnforced = $null
                $linkExists = $false
                
                try {
                    # Get existing GPO inheritance for this OU (relaxed error handling)
                    $inheritance = Get-GPInheritance -Target $targetOUPath -Server $DomainController -ErrorAction Stop
                    
                    # Find our GPO in the inheritance list
                    $existingLink = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $actualGpoName }
                    
                    if ($existingLink) {
                        $linkExists = $true
                        $currentLinkOrder = $existingLink.Order
                        $currentEnforced = $existingLink.Enforced
                    }
                    
                    # Get all existing links for order analysis
                    $existingLinks = @($inheritance.GpoLinks)
                    
                } catch {
                    # For Full Deployment, continue planning even if we can't check current state
                    # (OU might not exist yet and will be created in Phase 1)
                }
                
                # For Full Deployment: Only check if link exists, ignore order/enforcement settings
                $requiresAction = $false
                $actionReason = ""
                
                if (-not $linkExists) {
                    $requiresAction = $true
                    $actionReason = "Link does not exist"
                } else {
                    # Link exists - show green check message
                    if (-not $Silent) {
                        Write-Host "  ✅ GPO Link Exists: $actualGpoName -> $($targetOUPath -replace '^.*?,OU=([^,]+).*$', '$1')" -ForegroundColor Green
                    }
                    # For Full Deployment, we don't check order or enforcement - just existence
                }
                
                if ($requiresAction) {
                    # Determine priority based on action type
                    $priority = if (-not $linkExists) { 'High' } else { 'Medium' }
                    $risk = if ($existingLinks.Count -gt 0) { 'Medium' } else { 'Low' }
                    
                    $linkActions += [PSCustomObject]@{
                        Action = 'LinkGPO'
                        Priority = $priority
                        Risk = $risk
                        Path = $targetOUPath
                        Data = $gpoData
                        RequiredState = @{
                            GPOExists = $true
                            LinkExists = $true
                            Order = $gpoData.linkOrder
                            Enforced = $requiredEnforced
                        }
                        CurrentState = @{
                            GPOExists = $true
                            LinkExists = $linkExists
                            Order = $currentLinkOrder
                            Enforced = $currentEnforced
                        }
                        Reason = $actionReason.TrimEnd('; ')
                    }
                }
            } catch {
                $errors += [PSCustomObject]@{
                    Timestamp = Get-Date
                    Category = 'SystemError'
                    Code = 'LinkAnalysisFailed'
                    Message = "Failed to analyze GPO link for '$gpoName': $($_.Exception.Message)"
                    Context = @{
                        GPOName = $gpoName
                        TargetOU = $targetOUPath
                        Exception = $_.Exception
                    }
                }
                $converged = $false
            }
        }
        
        # Create result object
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        return [PSCustomObject]@{
            Actions = $linkActions
            Errors = $errors
            DurationMs = [int]$duration
            Converged = $converged
            CorrelationId = $CorrelationId
        }
        
        Write-TierModelLog -Level Info -Message "GPO Link Full Deployment planning completed" -Data @{
            TotalActions = @($linkActions).Count
            DurationMs = $duration
            CorrelationId = $CorrelationId
        } | Out-Null
        
    } catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        $errorMessage = "GPO Link Full Deployment planning failed: $($_.Exception.Message)"
        Write-TierModelLog -Level Error -Message $errorMessage -Data @{
            Exception = $_.Exception
            CorrelationId = $CorrelationId
            DurationMs = $duration
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = @()
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'GPOLinkPlanningFailed'
                Message = $errorMessage
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = [int]$duration
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}