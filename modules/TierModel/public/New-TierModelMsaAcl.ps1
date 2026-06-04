function New-TierModelMsaAcl {
    <#
    .SYNOPSIS
    Execute TierModel MSA ACL delegation deployment plan.
    
    .DESCRIPTION
    Applies MSA ACL delegations in Active Directory based on the deployment plan generated
    by Get-TierModelMsaAcl. Handles ACL creation with proper rights assignment, inheritance,
    GUID resolution, and principal resolution.
    
    .PARAMETER Plan
    Deployment plan object from Get-TierModelMsaAcl containing ACL actions to execute.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER Config
    The TierModel configuration object containing GUID mappings and other settings.
    
    .OUTPUTS
    PSCustomObject with Applied, Skipped, Errors, DurationMs, and Converged status.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [Parameter(Mandatory)]
        [object]$Config
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "MsaAclExecutionStart" -Data @{
        TotalActions = @($Plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        DomainController = $DomainController
        WhatIf = $WhatIfPreference
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $applied = @()
        $skipped = @()
        $errors = @()
        $converged = $true
        
        $resolveAclGuid = {
            param([string]$Value)
            
            if ([string]::IsNullOrEmpty($Value)) {
                return $null
            }
            
            # AllObjectClasses is a special value meaning "all object types" (Guid::Empty)
            if ($Value -eq 'AllObjectClasses') {
                return ''
            }
            
            $parsedGuid = [Guid]::Empty
            if ([Guid]::TryParse($Value, [ref]$parsedGuid)) {
                return $parsedGuid.ToString()
            }
            
            $resolvedGuid = Resolve-TierModelGuid -Value $Value -Mappings $Config.guidMappings -DomainController $DomainController
            if ($null -eq $resolvedGuid) {
                throw "Failed to resolve GUID for '$Value'"
            }
            
            return $resolvedGuid
        }
        
        foreach ($action in $Plan.Actions) {
            if ($action.Action -eq 'CreateAcl') {
                try {
                    $aclData = $action.Data
                    $targetOUPath = $action.Path
                    $identityReference = $aclData.identityreference
                    
                    Write-TierModelLog -Level Info -Message "Applying MSA ACL delegation" -Data @{
                        TargetOUPath = $targetOUPath
                        IdentityReference = $identityReference
                        AccessControlType = $aclData.accesscontroltype
                        ActiveDirectoryRights = ($aclData.activedirectoryrights -join ', ')
                        ObjectType = $aclData.objecttype
                        Inheritance = $aclData.activeDirectorysecurityinheritance
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    if ($PSCmdlet.ShouldProcess("OU: $targetOUPath", "Apply MSA ACL delegation for $identityReference")) {
                        $de = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainController/$targetOUPath")
                        
                        $ntAccount = New-Object System.Security.Principal.NTAccount($identityReference)
                        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
                        
                        $adRights = 0 -as [System.DirectoryServices.ActiveDirectoryRights]
                        if ($aclData.activedirectoryrights -and $aclData.activedirectoryrights.Count -gt 0) {
                            foreach ($rightString in $aclData.activedirectoryrights) {
                                if (-not [string]::IsNullOrEmpty($rightString)) {
                                    try {
                                        $rightEnum = [System.DirectoryServices.ActiveDirectoryRights]::($rightString)
                                        $adRights = $adRights -bor $rightEnum
                                    } catch {
                                        Write-Host "  WARNING: Invalid ActiveDirectoryRight: $rightString" -ForegroundColor Yellow
                                    }
                                }
                            }
                        }
                        
                        $accessControlType = [System.Security.AccessControl.AccessControlType]::$($aclData.accesscontroltype)
                        $inheritance = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$($aclData.activeDirectorysecurityinheritance)
                        
                        $resolvedObjectType = & $resolveAclGuid $aclData.objecttype
                        $objectTypeGuid = if ([string]::IsNullOrEmpty($resolvedObjectType)) { [Guid]::Empty } else { [Guid]$resolvedObjectType }
                        
                        # GUID guard: prevent over-scoped ACE if resolution failed (but AllObjectClasses legitimately resolves to Empty)
                        if (-not [string]::IsNullOrEmpty($aclData.objecttype) -and $aclData.objecttype -ne 'AllObjectClasses' -and ($null -eq $resolvedObjectType -or $objectTypeGuid -eq [Guid]::Empty)) {
                            throw "Resolved objectType GUID for '$($aclData.objecttype)' is null, empty, or Guid.Empty. Aborting ACL application to prevent an over-scoped ACE."
                        }
                        
                        $inheritedObjectTypeGuid = [Guid]::Empty
                        if ($aclData.PSObject.Properties['inheritedObjectType'] -and -not [string]::IsNullOrEmpty($aclData.inheritedObjectType)) {
                            $resolvedInheritedObjectType = & $resolveAclGuid $aclData.inheritedObjectType
                            if ($null -eq $resolvedInheritedObjectType -or [string]::IsNullOrEmpty($resolvedInheritedObjectType)) {
                                throw "Resolved inheritedObjectType GUID for '$($aclData.inheritedObjectType)' is null or empty. Aborting ACL application to prevent an over-scoped ACE."
                            }
                            
                            $inheritedObjectTypeGuid = [Guid]$resolvedInheritedObjectType
                            if ($inheritedObjectTypeGuid -eq [Guid]::Empty) {
                                throw "Resolved inheritedObjectType GUID for '$($aclData.inheritedObjectType)' is Guid.Empty. Aborting ACL application to prevent an over-scoped ACE."
                            }
                        }
                        
                        if ($inheritedObjectTypeGuid -ne [Guid]::Empty) {
                            $accessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                                $sid,
                                $adRights,
                                $accessControlType,
                                $objectTypeGuid,
                                $inheritance,
                                $inheritedObjectTypeGuid
                            )
                        } else {
                            $accessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                                $sid,
                                $adRights,
                                $accessControlType,
                                $objectTypeGuid,
                                $inheritance
                            )
                        }
                        
                        $acl = $de.ObjectSecurity
                        $acl.AddAccessRule($accessRule)
                        $de.ObjectSecurity = $acl
                        $de.CommitChanges()
                        
                        Write-TierModelLog -Level Info -Message "MSA ACL delegation applied successfully" -Data @{
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            AccessRuleSID = $sid.Value
                            RightsApplied = $adRights.ToString()
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        $ouName = if ($targetOUPath -match "OU=([^,]+)") { $matches[1] } else { "Unknown OU" }
                        Write-Host "  ✅ Applied MSA ACL: $identityReference on $ouName" -ForegroundColor Green
                        
                        $applied += [PSCustomObject]@{
                            Action = 'CreateAcl'
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            ObjectType = $objectTypeGuid
                            InheritedObjectType = $inheritedObjectTypeGuid
                            RightsApplied = $adRights.ToString()
                            AccessRuleSID = $sid.Value
                        }
                    } else {
                        Write-Host "  [WhatIf] Would apply MSA ACL: $identityReference on $targetOUPath" -ForegroundColor DarkYellow
                        $skipped += [PSCustomObject]@{
                            Action = 'CreateAcl'
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            Reason = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }
                        }
                    }
                } catch {
                    Write-TierModelLog -Level Error -Message "Failed to apply MSA ACL delegation" -Data @{
                        TargetOUPath = $action.Path
                        IdentityReference = $action.Data.identityreference
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    Write-Host "  ERROR: Failed to apply MSA ACL for '$($action.Data.identityreference)' - $($_.Exception.Message)" -ForegroundColor Red
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'Execution'
                        Code = 'AclApplicationFailed'
                        Message = $_.Exception.Message
                        Context = @{
                            Action = $action.Action
                            TargetOUPath = $action.Path
                            IdentityReference = $action.Data.identityreference
                        }
                    }
                    $converged = $false
                }
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "MsaAclExecutionComplete" -Data @{
            AppliedActions = $applied.Count
            FailedActions = $errors.Count
            SkippedActions = $skipped.Count
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Applied = $applied
            Executed = $applied.Count
            Failed = $errors.Count
            Skipped = $skipped
            Errors = $errors
            DurationMs = $durationMs
            Converged = $converged
            CorrelationId = $CorrelationId
        }
    } catch {
        Write-TierModelLog -Level Error -Message "MSA ACL execution failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Applied = @()
            Executed = 0
            Failed = 1
            Skipped = @()
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'AclExecutionFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}
