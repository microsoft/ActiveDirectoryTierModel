function New-TierModelOuAcl {
    <#
    .SYNOPSIS
    Execute TierModel OU ACL delegation deployment plan.
    
    .DESCRIPTION
    Applies OU ACL delegations in Active Directory based on the deployment plan generated
    by Get-TierModelOuAcl. Handles ACL creation with proper rights assignment, inheritance,
    and principal resolution.
    
    .PARAMETER Plan
    Deployment plan object from Get-TierModelOuAcl containing ACL actions to execute.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER Config
    The TierModel configuration object containing GUID mappings and other settings.
    
    .EXAMPLE
    $plan = Get-TierModelOuAcl -Config $config -DomainController "DC01"
    New-TierModelOuAcl -Plan $plan -DomainController "DC01" -Config $config
    
    .OUTPUTS
    PSCustomObject with execution results including success/failure counts and details.
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
    
    Write-TierModelLog -Level Info -Message "OuAclExecutionStart" -Data @{
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
            if ($action.Action -eq 'CreateAcl') {
                try {
                    $aclData = $action.Data
                    $targetOUPath = $action.Path
                    $identityReference = $aclData.identityreference
                    
                    Write-TierModelLog -Level Info -Message "Applying ACL delegation" -Data @{
                        TargetOUPath = $targetOUPath
                        IdentityReference = $identityReference
                        AccessControlType = $aclData.accesscontroltype
                        ActiveDirectoryRights = ($aclData.activedirectoryrights -join ', ')
                        ObjectType = $aclData.objecttype
                        Inheritance = $aclData.activeDirectorysecurityinheritance
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    if ($PSCmdlet.ShouldProcess("OU: $targetOUPath", "Apply ACL delegation for $identityReference")) {
                        
                        # Bind to the OU via LDAP (like original working code)
                        $de = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$targetOUPath")
                        
                        # Resolve NTAccount -> SID (recommended for stable matching)
                        $ntAccount = New-Object System.Security.Principal.NTAccount($identityReference)
                        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
                        
                        # Parse Active Directory Rights - handle array format safely
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
                        
                        # Parse Access Control Type
                        $accessControlType = [System.Security.AccessControl.AccessControlType]::$($aclData.accesscontroltype)
                        
                        # Parse Inheritance
                        $inheritance = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$($aclData.activeDirectorysecurityinheritance)
                        
                        # Parse Object Type GUID (resolve friendly names to GUIDs if needed)
                        $resolvedObjectType = $aclData.objecttype
                        if (-not [string]::IsNullOrEmpty($aclData.objecttype)) {
                            try {
                                # Try to resolve using GUID mappings if it's not already a valid GUID
                                if (-not [System.Guid]::TryParse($aclData.objecttype, [ref][System.Guid]::Empty)) {
                                    $resolvedObjectType = Resolve-TierModelGuid -Value $aclData.objecttype -Mappings $Config.guidMappings -DomainController $DomainController
                                    if ($null -ne $resolvedObjectType) {
                                        if (-not [string]::IsNullOrEmpty($resolvedObjectType)) {
                                            Write-Verbose "Resolved objecttype '$($aclData.objecttype)' to GUID: $resolvedObjectType"
                                        } else {
                                            Write-Verbose "Resolved objecttype '$($aclData.objecttype)' to empty GUID (all object types)"
                                        }
                                    } else {
                                        Write-Warning "Could not resolve objecttype '$($aclData.objecttype)' to GUID. Using original value."
                                        $resolvedObjectType = $aclData.objecttype
                                    }
                                }
                            } catch {
                                Write-Warning "Error resolving objecttype '$($aclData.objecttype)': $($_.Exception.Message). Using original value."
                                $resolvedObjectType = $aclData.objecttype
                            }
                        }
                        
                        $objectTypeGuid = if ([string]::IsNullOrEmpty($resolvedObjectType)) { [Guid]::Empty } else { [Guid]$resolvedObjectType }
                        
                        # Handle inherited object type if specified
                        $inheritedObjectTypeGuid = [Guid]::Empty
                        if ($aclData.PSObject.Properties['inheritedObjectType'] -and -not [string]::IsNullOrEmpty($aclData.inheritedObjectType)) {
                            try {
                                # Try to resolve using GUID mappings if it's not already a valid GUID
                                if (-not [System.Guid]::TryParse($aclData.inheritedObjectType, [ref][System.Guid]::Empty)) {
                                    $resolvedInheritedObjectType = Resolve-TierModelGuid -Value $aclData.inheritedObjectType -Mappings $Config.guidMappings -DomainController $DomainController
                                    if ($null -ne $resolvedInheritedObjectType -and -not [string]::IsNullOrEmpty($resolvedInheritedObjectType)) {
                                        $inheritedObjectTypeGuid = [Guid]$resolvedInheritedObjectType
                                        Write-Verbose "Resolved inheritedObjectType '$($aclData.inheritedObjectType)' to GUID: $resolvedInheritedObjectType"
                                    }
                                } else {
                                    $inheritedObjectTypeGuid = [Guid]$aclData.inheritedObjectType
                                }
                            } catch {
                                Write-Warning "Error resolving inheritedObjectType '$($aclData.inheritedObjectType)': $($_.Exception.Message). Using empty GUID."
                                $inheritedObjectTypeGuid = [Guid]::Empty
                            }
                        }
                        
                        # Build the access rule with or without inherited object type
                        if ($inheritedObjectTypeGuid -ne [Guid]::Empty) {
                            # Use 6-parameter constructor for inherited object type
                            $accessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                                $sid,
                                $adRights,
                                $accessControlType,
                                $objectTypeGuid,
                                $inheritance,
                                $inheritedObjectTypeGuid
                            )
                        } else {
                            # Use 5-parameter constructor (original behavior)
                            $accessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                                $sid,
                                $adRights,
                                $accessControlType,
                                $objectTypeGuid,
                                $inheritance
                            )
                        }
                        
                        # Apply the rule (use AddAccessRule instead of SetAccessRule)
                        $acl = $de.ObjectSecurity
                        $acl.AddAccessRule($accessRule)
                        $de.ObjectSecurity = $acl
                        $de.CommitChanges()
                        
                        Write-TierModelLog -Level Info -Message "ACL delegation applied successfully" -Data @{
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            AccessRuleSID = $sid.Value
                            RightsApplied = $adRights.ToString()
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        # Extract just the OU name from the full DN for readable output
                        $ouName = if ($targetOUPath -match "OU=([^,]+)") { $matches[1] } else { "Unknown OU" }
                        Write-Host "  ✅ Applied ACL: $identityReference on $ouName" -ForegroundColor Green
                        $executed++
                    } else {
                        Write-Host "  [WhatIf] Would apply ACL: $identityReference on $targetOUPath" -ForegroundColor DarkYellow
                        $skipped++
                    }
                    
                } catch {
                    Write-TierModelLog -Level Error -Message "Failed to apply ACL delegation" -Data @{
                        TargetOUPath = $action.Path
                        IdentityReference = $action.Data.identityreference
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    Write-Host "  ERROR: Failed to apply ACL for '$($action.Data.identityreference)' - $($_.Exception.Message)" -ForegroundColor Red
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
                    $failed++
                    $converged = $false
                }
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "OuAclExecutionComplete" -Data @{
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
        Write-TierModelLog -Level Error -Message "OU ACL execution failed" -Data @{
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
                Code = 'AclExecutionFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            DurationMs = 0
            Converged = $false
            CorrelationId = $CorrelationId
        }
    }
}