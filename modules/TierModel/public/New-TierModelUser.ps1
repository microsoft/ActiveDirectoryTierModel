function New-TierModelUser {
    <#
    .SYNOPSIS
    Execute TierModel user account deployment plan.
    
    .DESCRIPTION
    Creates user accounts in Active Directory based on the deployment plan generated
    by Get-TierModelUser. Handles user creation with proper properties, password 
    generation, and group membership assignments.
    
    .PARAMETER Plan
    Deployment plan object from Get-TierModelUser containing actions to execute.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .EXAMPLE
    $plan = Get-TierModelUser -Config $config -DomainController "DC01"
    New-TierModelUser -Plan $plan -DomainController "DC01"
    
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
    
    Write-TierModelLog -Level Info -Message "UserExecutionStart" -Data @{
        TotalActions = $Plan.Actions.Count
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
        
        foreach ($action in $Plan.Actions) {
            if ($action.Action -eq 'CreateUser') {
                try {
                    $userData = $action.Data
                    $userName = $userData.displayName
                    $userSamAccountName = $userData.samAccountName
                    $userOUPath = $action.Path
                    
                    # Get user properties
                    $userDescription = if ($userData.PSObject.Properties.Name -contains 'description') { 
                        $userData.description 
                    } else { 
                        $null 
                    }
                    
                    $userEnabled = if ($userData.PSObject.Properties.Name -contains 'enabled') { 
                        $userData.enabled 
                    } else { 
                        $true 
                    }
                    
                    Write-TierModelLog -Level Info -Message "Creating user account" -Data @{
                        DisplayName = $userName
                        SamAccountName = $userSamAccountName
                        Path = $userOUPath
                        Enabled = $userEnabled
                        Description = $userDescription
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    Write-Host "  ✅ Creating User: $userName ($userSamAccountName)" -ForegroundColor Green
                    
                    if ($PSCmdlet.ShouldProcess("User: $userName", "Create User Account")) {
                        # Create the User using New-ADUser
                        $newUserParams = @{
                            Name = $userName
                            DisplayName = $userName
                            SamAccountName = $userSamAccountName
                            Path = $userOUPath
                            Enabled = $userEnabled
                            Server = $DomainController
                            Confirm = $false
                        }
                        
                        # Add optional properties if they exist
                        if ($userDescription) {
                            $newUserParams['Description'] = $userDescription
                        }
                        
                        # Generate a secure temporary password (user should change on first logon)
                        $passwordLength = 16
                        $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*'
                        $tempPasswordString = -join ((1..$passwordLength) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
                        $tempPassword = ConvertTo-SecureString -String $tempPasswordString -AsPlainText -Force
                        $newUserParams['AccountPassword'] = $tempPassword
                        $newUserParams['ChangePasswordAtLogon'] = $true
                        
                        New-ADUser @newUserParams | Out-Null
                        
                        # Add user to groups if specified
                        if ($userData.PSObject.Properties.Name -contains 'memberOf' -and $userData.memberOf) {
                            foreach ($groupName in $userData.memberOf) {
                                try {
                                    Add-ADGroupMember -Identity $groupName -Members $userSamAccountName -Server $DomainController -Confirm:$false | Out-Null
                                    Write-Host "  ✅ Added to group: $groupName" -ForegroundColor Green
                                } catch {
                                    Write-TierModelLog -Level Warning -Message "Failed to add user to group" -Data @{
                                        UserName = $userName
                                        GroupName = $groupName
                                        Exception = $_.Exception.Message
                                        CorrelationId = $CorrelationId
                                    } | Out-Null
                                    Write-Host "  WARNING: Failed to add user to group '$groupName' - $($_.Exception.Message)" -ForegroundColor Yellow
                                }
                            }
                        }
                        
                        Write-TierModelLog -Level Info -Message "User account created successfully" -Data @{
                            DisplayName = $userName
                            SamAccountName = $userSamAccountName
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        # User creation already indicated by the initial checkmark message
                        $executed++
                    } else {
                        Write-Host "  [WhatIf] Would create User: $userName" -ForegroundColor DarkYellow
                        $skipped++
                    }
                    
                } catch {
                    Write-TierModelLog -Level Error -Message "Failed to create user account" -Data @{
                        Name = $action.Name
                        Path = $action.Path
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    Write-Host "  ERROR: Failed to create User '$($action.Name)' - $($_.Exception.Message)" -ForegroundColor Red
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'Execution'
                        Code = 'UserCreationFailed'
                        Message = $_.Exception.Message
                        Context = @{
                            Action = $action.Action
                            Name = $action.Name
                            Path = $action.Path
                        }
                    }
                    $failed++
                    $converged = $false
                }
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "UserExecutionComplete" -Data @{
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
        Write-TierModelLog -Level Error -Message "User execution failed" -Data @{
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
                Code = 'UserExecutionFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = 0
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}