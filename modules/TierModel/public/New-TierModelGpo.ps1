function Get-TierModelWriteFailureDetail {
    <#
    .SYNOPSIS
    Private helper (not exported). Builds diagnostics for a directory write that did not
    produce a verifiable result.

    .DESCRIPTION
    Under PowerShell 7 the ActiveDirectory and GroupPolicy modules are loaded through the
    Windows PowerShell compatibility shim as script proxy functions that report failure via
    $PSCmdlet.WriteError(). That path does not honour an inherited 'Stop' preference the way a
    binary cmdlet does, so a failed write can fall through without terminating and leave the
    result variable $null. Callers therefore null-check the result and, when it is $null, use
    this helper to recover the error that the proxy emitted.

    Because the shim marshals errors across a runspace boundary the exception is flattened -
    InnerException is normally absent - but FullyQualifiedErrorId and CategoryInfo survive, so
    those are captured explicitly alongside the message.

    .PARAMETER Operation
    Name of the cmdlet or operation that was attempted, e.g. 'New-GPO'.

    .PARAMETER Target
    Name or distinguished name of the object the write targeted.

    .PARAMETER ErrorRecord
    Optional explicit error record. When omitted the most recent error record is used.

    .OUTPUTS
    Hashtable with Operation, Target, Message, FullyQualifiedErrorId, CategoryInfo,
    ExceptionType and Summary keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string]$Target,

        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $record = $ErrorRecord
    if ($null -eq $record -and $global:Error.Count -gt 0) {
        $record = $global:Error[0] -as [System.Management.Automation.ErrorRecord]
    }

    $message       = 'no error record was emitted'
    $fqeid         = 'None'
    $category      = 'None'
    $exceptionType = 'None'

    if ($null -ne $record) {
        if ($null -ne $record.Exception) {
            $message       = $record.Exception.Message
            $exceptionType = $record.Exception.GetType().FullName
        }
        if ($null -ne $record.FullyQualifiedErrorId) { $fqeid = [string]$record.FullyQualifiedErrorId }
        if ($null -ne $record.CategoryInfo)          { $category = $record.CategoryInfo.ToString() }
    }

    $summary = "$Operation returned no result for '$Target' - the write did not succeed. " +
               "Message: $message; FullyQualifiedErrorId: $fqeid; CategoryInfo: $category"

    return @{
        Operation             = $Operation
        Target                = $Target
        Message               = $message
        FullyQualifiedErrorId = $fqeid
        CategoryInfo          = $category
        ExceptionType         = $exceptionType
        Summary               = $summary
    }
}

function New-TierModelGpo {
    <#
    .SYNOPSIS
    Execute TierModel GPO creation from deployment plan.
    
    .DESCRIPTION
    Creates new GPOs in Active Directory based on the deployment plan generated
    by Get-TierModelGpo. Handles GPO creation with comments, status configuration,
    and security ACL settings.
    
    .PARAMETER Plan
    Deployment plan object from Get-TierModelGpo containing GPO creation actions to execute.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .EXAMPLE
    $plan = Get-TierModelGpo -Config $gpoConfig -DomainController "DC01"
    New-TierModelGpo -Plan $plan -DomainController "DC01"
    
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
    
    # Filter to only CreateGPO actions
    $createActions = @($Plan.Actions | Where-Object { $_.Action -eq 'CreateGPO' })
    
    Write-TierModelLog -Level Info -Message "GPO creation start" -Data @{
        TotalActions = $createActions.Count
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
        
        foreach ($action in $createActions) {
            try {
                $gpoData = $action.Data
                $gpoName = $gpoData.name
                $gpoMode = $action.Mode
                $targetOUPath = $action.Path
                
                Write-TierModelLog -Level Info -Message "Creating GPO" -Data @{
                    Name = $gpoName
                    Mode = $gpoMode
                    TargetOU = $targetOUPath
                }
                
                # GPO creation starts (removed verbose Creating message)
                
                if ($PSCmdlet.ShouldProcess("GPO: $gpoName", "Create GPO")) {
                    
                    # Create the GPO - only include Comment parameter if we have a non-empty comment
                    if ([string]::IsNullOrWhiteSpace($gpoData.gpoComment)) {
                        $newGPO = New-GPO -Name $gpoName -Server $DomainController -ErrorAction Stop
                    } else {
                        $newGPO = New-GPO -Name $gpoName -Server $DomainController -Comment $gpoData.gpoComment -ErrorAction Stop
                    }

                    # Verify the write before claiming success. See Get-TierModelWriteFailureDetail.
                    if ($null -eq $newGPO) {
                        throw (Get-TierModelWriteFailureDetail -Operation 'New-GPO' -Target $gpoName).Summary
                    }

                    # Show Created GPO message immediately after creation
                    Write-Host "  ✅ Created GPO: $gpoName" -ForegroundColor Green
                    
                    # Configure GPO status (User/Computer settings enabled/disabled) for create-only mode GPOs
                    # Only needed for 'create' mode because import operations will set status from imported GPO
                    if ($gpoMode -eq 'create' -and $gpoData.PSObject.Properties.Name -contains 'gpoStatus') {
                        try {
                            $domain = Get-ADDomain -Server $DomainController
                            $domainDN = $domain.DistinguishedName
                            
                            # Map gpoStatus values to AD flags. Must stay in exact agreement with the
                            # audit switch in Test-TierModelGPO.ps1, otherwise a value handled there
                            # but not here deploys as flags 0 and audits as a different value —
                            # unresolvable drift, because re-running deploy keeps writing 0.
                            $flagValue = switch ($gpoData.gpoStatus) {
                                'AllEnabled'               { 0 }
                                'AllSettingsEnabled'       { 0 }
                                'UserSettingsDisabled'    { 1 }
                                'ComputerSettingsDisabled' { 2 }
                                'BothSettingsDisabled'     { 3 }
                                'AllSettingsDisabled'      { 3 }
                                default { 0 } # Default to all enabled if unrecognized
                            }
                            
                            # Set the flags attribute on the GPO AD object
                            $statusResult = Set-ADObject -Identity "CN={$($newGPO.Id)},CN=Policies,CN=System,$domainDN" -Replace @{ flags = $flagValue } -Server $DomainController -PassThru -ErrorAction Stop
                            if ($null -eq $statusResult) {
                                throw (Get-TierModelWriteFailureDetail -Operation 'Set-ADObject (gpoStatus)' -Target $gpoName).Summary
                            }

                            Write-Host "    ✅ Set GPO status to: $($gpoData.gpoStatus)" -ForegroundColor Green
                        } catch {
                            Write-Host "    Warning: Failed to set GPO status '$($gpoData.gpoStatus)' - $($_.Exception.Message)" -ForegroundColor Yellow
                            Write-TierModelLog -Level Warning -Message "Failed to set GPO status" -Data @{
                                GPOName = $gpoName
                                GPOStatus = $gpoData.gpoStatus
                                Exception = $_.Exception.Message
                                FullyQualifiedErrorId = [string]$_.FullyQualifiedErrorId
                                CategoryInfo = $_.CategoryInfo.ToString()
                            }
                        }
                    }
                    
                    # Set GPO ACLs (like DenyApply groups) using direct ACL manipulation
                    if ($gpoData.PSObject.Properties.Name -contains 'denyApplyGroupPolicy' -and $gpoData.denyApplyGroupPolicy) {
                        foreach ($denyGroup in $gpoData.denyApplyGroupPolicy) {
                            try {
                                
                                # Get domain info for building ADSI path
                                $domain = Get-ADDomain -Server $DomainController
                                $domainDN = $domain.DistinguishedName
                                $domainNetbios = $domain.NetBIOSName
                                
                                # Build ADSI path to GPO container (GPC) in AD, targeting the
                                # preferred DC so the Deny-Apply ACL is written to the SAME DC as
                                # every other ACL (serverless binding would hit a random DC and
                                # cause replication-dependent inconsistency in multi-DC environments).
                                $gpcAdsiPath = "LDAP://$DomainController/CN={$($newGPO.Id)},CN=Policies,CN=System,$domainDN"
                                $gpc = [ADSI]$gpcAdsiPath
                                
                                # Resolve group identity to NTAccount
                                $ntAccount = New-Object System.Security.Principal.NTAccount("$domainNetbios", $denyGroup)
                                
                                # Apply GPO extended right GUID (documented standard)
                                $applyGpoGuid = [Guid]"edacfd8f-ffb3-11d1-b41d-00a0c968f939"
                                
                                # Build a Deny ACE for Apply GPO extended right
                                $denyAce = New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
                                    ($ntAccount, "ExtendedRight", "Deny", $applyGpoGuid)
                                
                                # Add ACE and commit
                                $acl = $gpc.ObjectSecurity
                                $acl.AddAccessRule($denyAce)
                                $gpc.ObjectSecurity = $acl
                                $gpc.CommitChanges()
                                
                                Write-Host "    ✅ Added DENY Apply GPO ACL for: $denyGroup" -ForegroundColor Green
                            } catch {
                                Write-Host "    Warning: Failed to set Deny Apply ACL for group '$denyGroup' - $($_.Exception.Message)" -ForegroundColor Yellow
                                Write-TierModelLog -Level Warning -Message "Failed to set GPO Deny Apply ACL" -Data @{
                                    GPOName = $gpoName
                                    Group = $denyGroup
                                    Exception = $_.Exception.Message
                                }
                            }
                        }
                    }
                    
                    Write-TierModelLog -Level Info -Message "GPO created successfully" -Data @{
                        GPOName = $gpoName
                        GPOId = $newGPO.Id
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    $executed++
                } else {
                    Write-Host "  [WhatIf] Would create GPO: $gpoName" -ForegroundColor DarkYellow
                    $skipped++
                }
                
            } catch {
                Write-TierModelLog -Level Error -Message "Failed to create GPO" -Data @{
                    GPOName = $action.Data.name
                    Exception = $_.Exception.Message
                    FullyQualifiedErrorId = [string]$_.FullyQualifiedErrorId
                    CategoryInfo = $_.CategoryInfo.ToString()
                    CorrelationId = $CorrelationId
                } | Out-Null
                
                Write-Host "  ERROR: Failed to create GPO '$($action.Data.name)' - $($_.Exception.Message)" -ForegroundColor Red
                $errors += @{
                    Timestamp = Get-Date
                    Category = 'Execution'
                    Code = 'GPOCreationFailed'
                    Message = $_.Exception.Message
                    Context = @{
                        Action = $action.Action
                        GPOName = $action.Data.name
                    }
                }
                $failed++
                $converged = $false
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "GPO creation complete" -Data @{
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
        Write-TierModelLog -Level Error -Message "GPO creation failed" -Data @{
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
                Code = 'GPOCreationFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}