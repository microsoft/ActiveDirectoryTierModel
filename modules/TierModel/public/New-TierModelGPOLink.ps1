function New-TierModelGPOLink {
    <#
    .SYNOPSIS
    Execute TierModel GPO link operations from deployment plan.
    
    .DESCRIPTION
    Creates and manages GPO links to OUs based on the deployment plan generated
    by Get-TierModelGPOLink. Handles link creation, order management, and
    enforcement setting configuration.
    
    .PARAMETER Plan
    Deployment plan object from Get-TierModelGPOLink containing GPO link actions to execute.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .EXAMPLE
    $linkplan = Get-TierModelGPOLink -Plan $gpoplan -DomainController "DC01"
    New-TierModelGPOLink -Plan $linkplan -DomainController "DC01"
    
    .OUTPUTS
    PSCustomObject with execution results including success/failure counts and details.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,
        
        [Parameter(Mandatory)]
        [string]$DomainController
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    # Filter to only LinkGPO actions
    $linkActions = @($Plan.Actions | Where-Object { $_.Action -eq 'LinkGPO' })
    
    Write-TierModelLog -Level Info -Message "GPO link execution start" -Data @{
        TotalActions = $linkActions.Count
        DomainController = $DomainController
        WhatIf = $PSCmdlet.ShouldProcess
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $executed = 0
        $failed = 0
        $skipped = 0
        $errors = @()
        $converged = $true
        
        # Sort actions by OU path, then by linkOrder within each OU (CRITICAL for proper GPO linking)
        Write-Host "  Sorting GPO links by OU and link order..." -ForegroundColor Cyan
        $sortedActions = $linkActions | Sort-Object { 
            # First sort by OU path to group by OU
            $_.Path
        }, {
            # Then sort by linkOrder within each OU (lowest first)
            if ($_.Data.PSObject.Properties.Name -contains 'linkOrder') {
                [int]$_.Data.linkOrder
            } else {
                999
            }
        }
        
        # Execute GPO link actions in sorted order
        foreach ($action in $sortedActions) {
                try {
                    $gpoData = $action.Data
                    $gpoName = $gpoData.name
                    $targetOUPath = $action.Path
                    
                    # Extract link settings with defaults (matching original working code)
                    $requiredOrder = if ($gpoData.PSObject.Properties.Name -contains 'linkOrder') { $gpoData.linkOrder } else { -1 }
                    $linkEnabled = if ($gpoData.PSObject.Properties.Name -contains 'linkEnabled') { $gpoData.linkEnabled } else { $true }
                    $requiredEnforced = if ($gpoData.PSObject.Properties.Name -contains 'enforced') { $gpoData.enforced } else { 'No' }
                    
                    Write-TierModelLog -Level Info -Message "Linking GPO" -Data @{
                        Name = $gpoName
                        TargetOU = $targetOUPath
                        Order = $requiredOrder
                        LinkEnabled = $linkEnabled
                        Enforced = $requiredEnforced
                    }
                    
                    # Linking GPO: $gpoName -> $targetOUPath (removed verbose message)
                
                if ($PSCmdlet.ShouldProcess("GPO: $gpoName to OU: $targetOUPath", "Link GPO")) {
                    
                    # Verify GPO exists
                    try {
                        Get-GPO -Name $gpoName -Server $DomainController | Out-Null
                    } catch {
                        throw "GPO '$gpoName' not found - create GPO first"
                    }
                    
                    # Check current link state
                    $linkExists = $false
                    $currentOrder = $null
                    $currentEnforced = $null
                    
                    try {
                        $inheritance = Get-GPInheritance -Target $targetOUPath -Server $DomainController
                        $existingLink = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
                        
                        if ($existingLink) {
                            $linkExists = $true
                            $currentOrder = $existingLink.Order
                            $currentEnforced = $existingLink.Enforced
                            Write-Host "    Found existing link: Order=$currentOrder, Enforced=$currentEnforced" -ForegroundColor Cyan
                        }
                    } catch {
                        Write-Host "    Warning: Cannot check existing links - $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                    
                    # Create or update the link
                    if (-not $linkExists) {
                        # Create the link with all settings at once (matching original working code)
                        $linkEnabledParam = if ($linkEnabled) { 'Yes' } else { 'No' }
                        $enforcedParam = if ($requiredEnforced -eq 'Yes' -or $requiredEnforced -eq $true) { 'Yes' } else { 'No' }
                        
                        New-GPLink -Name $gpoName -Target $targetOUPath -LinkEnabled $linkEnabledParam -Order $requiredOrder -Enforced $enforcedParam -Server $DomainController | Out-Null
                        
                        Write-Host "  ✅ Created GPO link: $gpoName" -ForegroundColor Green
                        
                    } else {
                        # Link exists, check if updates are needed
                        $needsUpdate = $false
                        $updateActions = @()
                        
                        if ($requiredOrder -and $requiredOrder -ne $currentOrder) {
                            $needsUpdate = $true
                            $updateActions += "Order: $currentOrder -> $requiredOrder"
                        }
                        
                        if ($null -ne $requiredEnforced -and $requiredEnforced -ne $currentEnforced) {
                            $needsUpdate = $true
                            $enforcedText = if ($requiredEnforced) { 'Yes' } else { 'No' }
                            $currentText = if ($currentEnforced) { 'Yes' } else { 'No' }
                            $updateActions += "Enforced: $currentText -> $enforcedText"
                        }
                        
                        if ($needsUpdate) {
                            Write-Host "    Updating existing link: $($updateActions -join ', ')" -ForegroundColor Cyan
                            
                            # Update order if needed
                            if ($requiredOrder -and $requiredOrder -ne $currentOrder) {
                                Set-GPLink -Name $gpoName -Target $targetOUPath -Order $requiredOrder -Server $DomainController | Out-Null
                            }
                            
                            # Update enforcement if needed  
                            if ($null -ne $requiredEnforced -and $requiredEnforced -ne $currentEnforced) {
                                $enforcedAction = if ($requiredEnforced) { 'Yes' } else { 'No' }
                                Set-GPLink -Name $gpoName -Target $targetOUPath -Enforced $enforcedAction -Server $DomainController | Out-Null
                            }
                            
                            Write-Host "  Updated GPO link: $gpoName" -ForegroundColor Green
                        } else {
                            Write-Host "  GPO link already converged: $gpoName" -ForegroundColor Green
                        }
                    }
                    
                    Write-TierModelLog -Level Info -Message "GPO link completed" -Data @{
                        GPOName = $gpoName
                        TargetOU = $targetOUPath
                        Order = $requiredOrder
                        Enforced = $requiredEnforced
                        Action = if ($linkExists) { 'Updated' } else { 'Created' }
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    $executed++
                    
                } else {
                    Write-Host "  [WhatIf] Would link GPO: $gpoName to $targetOUPath" -ForegroundColor DarkYellow
                    $skipped++
                }
                
            } catch {
                Write-TierModelLog -Level Error -Message "Failed to link GPO" -Data @{
                    GPOName = $action.Data.name
                    TargetOU = $action.Path
                    Exception = $_.Exception.Message
                    CorrelationId = $CorrelationId
                } | Out-Null
                
                Write-Host "  ERROR: Failed to link GPO '$($action.Data.name)' - $($_.Exception.Message)" -ForegroundColor Red
                $errors += @{
                    Timestamp = Get-Date
                    Category = 'Execution'
                    Code = 'GPOLinkFailed'
                    Message = $_.Exception.Message
                    Context = @{
                        Action = $action.Action
                        GPOName = $action.Data.name
                        TargetOU = $action.Path
                        CorrelationId = $CorrelationId
                    }
                }
                $failed++
                $converged = $false
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "GPO link execution complete" -Data @{
            ExecutedActions = $executed
            FailedActions = $failed
            SkippedActions = $skipped
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Executed = $executed
            Failed = $failed
            Skipped = $skipped
            Errors = $errors
            DurationMs = $durationMs
            Converged = $converged
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "GPO link execution failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Executed = 0
            Failed = 1
            Skipped = 0
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'GPOLinkExecutionFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}