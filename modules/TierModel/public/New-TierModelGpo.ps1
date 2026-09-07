function Get-TierModelWriteFailureDetail {
    <#
    .SYNOPSIS
    Private helper (not exported). Builds diagnostics for a directory write that did not
    produce a verifiable result.

    .DESCRIPTION
    Null-return verification for AD and GroupPolicy write cmdlets: a failed write can leave the
    result variable $null without terminating. Root cause on any given platform is not yet
    established (see NOTE). Callers null-check the result and, when it is $null, use this helper
    to recover the most recent error record.

    NOTE (2026-09-04): Earlier versions of this comment attributed silent write failures to the
    Windows PowerShell Compatibility (WinPSCompat) shim — proxy functions calling
    $PSCmdlet.WriteError() that ignore an inherited Stop preference. This mechanism was NOT
    reproduced on Windows Server 2025 / PowerShell 7.5.1 (TierLab-DC01): every AD and
    GroupPolicy cmdlet loaded natively (CommandType=Cmdlet, not Function). The shim may still
    apply on older RSAT management workstations where GroupPolicy is not Core-native. Root
    cause for the original GPO silent-fail incident is not yet established.

    FullyQualifiedErrorId and CategoryInfo are captured explicitly because InnerException may
    be absent when exceptions cross runspace or serialisation boundaries.

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
                        # Validate gpoStatus BEFORE the inner try so an unrecognised value propagates
                        # to the outer catch (proper GPO-failure accounting + red ERROR console line)
                        # rather than the gpoStatus-specific inner catch (warning-only, GPO counted
                        # as executed). This is the fail-loud-per-GPO convention used throughout.
                        $validGpoStatusValues = @(
                            'AllSettingsEnabled',
                            'UserSettingsDisabled',
                            'ComputerSettingsDisabled',
                            'AllSettingsDisabled'
                        )
                        if ([string]$gpoData.gpoStatus -notin $validGpoStatusValues) {
                            $validList = $validGpoStatusValues -join ', '
                            throw "GPO '$gpoName' has unrecognized gpoStatus '$($gpoData.gpoStatus)'. Valid values: $validList"
                        }

                        try {
                            $domain = Get-ADDomain -Server $DomainController -ErrorAction Stop
                            $domainDN = $domain.DistinguishedName
                            
                            # Map gpoStatus names to AD 'flags' attribute values.
                            #
                            # ⚠ CRITICAL: these are AD 'flags' attribute values, NOT .NET GpoStatus
                            # enum ordinals. The ordinals are inverted for AllSettingsEnabled (ordinal 3)
                            # and AllSettingsDisabled (ordinal 0) — do NOT "fix" that inversion.
                            # Empirically verified on TierLab-DC01 by Joel Platek, 2026-09-04:
                            #   AllSettingsEnabled       → flags 0
                            #   UserSettingsDisabled     → flags 1
                            #   ComputerSettingsDisabled → flags 2
                            #   AllSettingsDisabled      → flags 3
                            #
                            # Must stay in exact agreement with the audit lookup in
                            # Test-TierModelGPO.ps1. If these tables drift a status written here
                            # audits as a different value — unresolvable drift because re-running
                            # deploy keeps writing the wrong flags value.
                            #
                            # Exactly 4 real .NET GpoStatus members.
                            $flagValue = switch ($gpoData.gpoStatus) {
                                'AllSettingsEnabled'       { 0 }
                                'UserSettingsDisabled'     { 1 }
                                'ComputerSettingsDisabled' { 2 }
                                'AllSettingsDisabled'      { 3 }
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
                                $domain = Get-ADDomain -Server $DomainController -ErrorAction Stop
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