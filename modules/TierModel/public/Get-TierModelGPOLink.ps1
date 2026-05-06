function Get-TierModelGPOLink {
    <#
    .SYNOPSIS
    Plan TierModel GPO link operations from deployment configuration.
    
    .DESCRIPTION
    Analyzes existing GPO links and generates deployment plan for linking GPOs to OUs
    with proper order management. This function handles link existence checks, order
    validation, and enforcement setting verification.
    
    .PARAMETER Plan
    Deployment plan object from Get-TierModelGpo containing GPO and OU information.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .EXAMPLE
    $gpoplan = Get-TierModelGpo -Config $gpoConfig -DomainController "DC01"
    $linkplan = Get-TierModelGPOLink -Plan $gpoplan -DomainController "DC01"
    
    .OUTPUTS
    PSCustomObject with link planning results including actions to execute.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,
        
        [Parameter(Mandatory)]
        [string]$DomainController
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "GPO link planning start" -Data @{
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

                # Analyzing GPO link: $gpoName -> $targetOUPath (removed verbose message)
                # Get GPO object
                try {
                    Get-GPO -Name $gpoName -Server $DomainController -ErrorAction Stop | Out-Null
                } catch {
                    Write-Host "    WARNING: GPO '$gpoName' not found, will need creation first" -ForegroundColor Yellow
                    # Add dependency note but continue planning
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
                    # Get existing GPO inheritance for this OU
                    $inheritance = Get-GPInheritance -Target $targetOUPath -Server $DomainController
                    
                    # Find our GPO in the inheritance list
                    $existingLink = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
                    
                    if ($existingLink) {
                        $linkExists = $true
                        $currentLinkOrder = $existingLink.Order
                        $currentEnforced = $existingLink.Enforced
                        
                        Write-Host "    Current link: Order=$currentLinkOrder, Enforced=$currentEnforced" -ForegroundColor Gray
                    } else {
                        # No existing link found
                    }
                    
                    # Get all existing links for order analysis
                    $existingLinks = @($inheritance.GpoLinks)
                    
                } catch {
                    Write-Host "    WARNING: Cannot retrieve GPO inheritance for OU - $($_.Exception.Message)" -ForegroundColor Yellow
                    # Continue planning even if we can't check current state
                }
                
                # Determine required action based on configuration
                $requiresAction = $false
                $actionReason = ""
                
                if (-not $linkExists) {
                    $requiresAction = $true
                    $actionReason = "Link does not exist"
                } else {
                    # Check if order needs adjustment
                    if ($gpoData.PSObject.Properties.Name -contains 'linkOrder' -and 
                        $gpoData.linkOrder -ne $currentLinkOrder) {
                        $requiresAction = $true
                        $actionReason += "Order mismatch (current: $currentLinkOrder, required: $($gpoData.linkOrder)); "
                    }
                    
                    # Check if enforcement setting needs adjustment
                    if ($requiredEnforced -ne $currentEnforced) {
                        $requiresAction = $true
                        $actionReason += "Enforcement mismatch (current: $currentEnforced, required: $requiredEnforced); "
                    }
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
                            ExistingLinksCount = $existingLinks.Count
                        }
                        Reason = $actionReason.TrimEnd('; ')
                        Dependencies = @()
                    }
                } else {
                    Write-Host "    No action needed - link is converged" -ForegroundColor Green
                }
                
            } catch {
                Write-TierModelLog -Level Error -Message "Failed to analyze GPO link" -Data @{
                    GPOName = $action.Data.name
                    TargetOU = $action.Path
                    Exception = $_.Exception.Message
                    CorrelationId = $CorrelationId
                } | Out-Null
                
                Write-Host "    ERROR: Failed to analyze GPO link - $($_.Exception.Message)" -ForegroundColor Red
                $errors += @{
                    Timestamp = Get-Date
                    Category = 'Analysis'
                    Code = 'GPOLinkAnalysisFailed'
                    Message = $_.Exception.Message
                    Context = @{
                        GPOName = $action.Data.name
                        TargetOU = $action.Path
                    }
                }
                $converged = $false
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        # Sort actions by priority and risk
        $priorityOrder = @{ 'High' = 1; 'Medium' = 2; 'Low' = 3 }
        $riskOrder = @{ 'Low' = 1; 'Medium' = 2; 'High' = 3 }
        
        $linkActions = $linkActions | Sort-Object {
            $priorityOrder[$_.Priority] * 10 + $riskOrder[$_.Risk]
        }
        
        Write-TierModelLog -Level Info -Message "GPO link planning complete" -Data @{
            TotalActions = $linkActions.Count
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = $linkActions
            Errors = $errors
            DurationMs = $durationMs
            Converged = $converged
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "GPO link planning failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = @()
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'GPOLinkPlanningFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}