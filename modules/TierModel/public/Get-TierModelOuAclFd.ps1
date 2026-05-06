function Get-TierModelOuAclFd {
    <#
    .SYNOPSIS
    Analyze TierModel OU ACL delegation requirements and generate deployment plan (Full Deployment variant).
    
    .DESCRIPTION
    Examines the TierModel configuration and current Active Directory OU ACL state
    to generate a deployment plan for ACL delegations for full deployment scenarios.
    This variant uses lighter validation - assumes OUs and Groups will be created by earlier phases.
    
    .PARAMETER Config
    TierModel configuration object containing ACL delegation definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER IncludeDetails
    Include detailed analysis in the planning output for troubleshooting.
    
    .EXAMPLE
    $plan = Get-TierModelOuAclFd -Config $config -DomainController "DC01"
    
    .EXAMPLE
    $plan = Get-TierModelOuAclFd -Config $config -DomainController "DC01" -IncludeDetails
    
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
    
    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "OuAclFdPlanningStart" -Data @{
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Initialize plan structure
        $actions = @()
        $planErrors = @()
        $warnings = @()
        
        # Get domain DN for placeholder replacement
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        # Check if ACL delegations are configured
        if (-not $Config.PSObject.Properties.Name -contains 'aclDelegations' -or 
            -not $Config.aclDelegations -or 
            $Config.aclDelegations.Count -eq 0) {
            
            Write-TierModelLog -Level Warning -Message "No ACL delegations found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            
            return [PSCustomObject]@{
                Actions = $actions
                Summary = @{
                    TotalActions = 0
                    CreateActions = 0
                    ExistingCount = 0
                    RiskAssessment = @{
                        LowRisk = 0
                        MediumRisk = 0
                        HighRisk = 0
                    }
                }
                Analysis = @{
                    ConfiguredAcls = 0
                    ExistingAcls = 0
                    ValidationErrors = 0
                }
                Errors = $planErrors
                Warnings = $warnings
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }
        
        Write-TierModelLog -Level Info -Message "Analyzing ACL delegations (Full Deployment)" -Data @{
            TotalAclsInConfig = $Config.aclDelegations.Count
            CorrelationId = $CorrelationId
        } | Out-Null
        
        $existingAclCount = 0
        
        # Process each ACL delegation
        foreach ($acl in $Config.aclDelegations) {
            try {
                # Replace placeholders in target OU path
                $targetOUPath = Resolve-TierModelPlaceholder -Path $acl.targetOUPath -DomainDN $domainDN
                
                # Resolve GUID mapping for object type (convert friendly names to GUIDs)
                $resolvedObjectType = if ($Config.PSObject.Properties.Name -contains 'guidMappings' -and $Config.guidMappings -and -not [string]::IsNullOrEmpty($acl.objecttype)) {
                    try {
                        Resolve-TierModelGuid -Value $acl.objecttype -Mappings $Config.guidMappings -DomainController $DomainController
                    } catch {
                        Write-TierModelLog -Level Warning -Message "GUID resolution failed, using original value" -Data @{
                            OriginalValue = $acl.objecttype
                            Error = $_.Exception.Message
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        $acl.objecttype  # Fallback to original value
                    }
                } else {
                    $acl.objecttype  # No GUID mappings available or empty objecttype, use original
                }
                
                $identityReference = $acl.identityreference
                $objectTypeGuid = if ([string]::IsNullOrEmpty($resolvedObjectType)) { 
                    [Guid]::Empty 
                } else { 
                    [Guid]$resolvedObjectType 
                }
                
                # Full Deployment variant: Check OU and Group existence but don't fail if missing
                # Assume Phase 1 creates OUs and Phase 2 creates Groups
                $targetOUExists = $false
                $principalExists = $false
                
                # Check if target OU exists (for ACL validation only)
                try {
                    Get-ADOrganizationalUnit -Identity $targetOUPath -Server $DomainController -ErrorAction Stop | Out-Null
                    $targetOUExists = $true
                } catch {
                    # OU doesn't exist - will be created in Phase 1
                }
                
                # Check if security principal exists (for ACL validation only)
                try {
                    # Try to resolve the identity reference as a group first
                    Get-ADGroup -Identity $identityReference -Server $DomainController -ErrorAction Stop | Out-Null
                    $principalExists = $true
                } catch {
                    # If not a group, try as a user or other principal
                    try {
                        Get-ADUser -Identity $identityReference -Server $DomainController -ErrorAction Stop | Out-Null
                        $principalExists = $true
                    } catch {
                        # Principal doesn't exist - will be created in Phase 2
                    }
                }
                
                # Check for existing ACLs to avoid duplicate creation
                $existingAcl = $null
                $needsApplication = $true
                
                # Check if ACL already exists (enabled for proper deployment planning)
                if ($targetOUExists -and $principalExists) {  # Only check if both OU and principal exist
                    try {
                        $currentAcl = Get-Acl -Path "AD:\$targetOUPath" -ErrorAction Stop
                        
                        # Convert string values to proper enum types for comparison
                        $expectedAccessControlType = [System.Security.AccessControl.AccessControlType]::$($acl.accesscontroltype)
                        $expectedInheritance = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$($acl.activeDirectorysecurityinheritance)
                        
                        # Parse expected rights to match exactly
                        $expectedRights = 0 -as [System.DirectoryServices.ActiveDirectoryRights]
                        if ($acl.activedirectoryrights -and $acl.activedirectoryrights.Count -gt 0) {
                            foreach ($rightString in $acl.activedirectoryrights) {
                                if (-not [string]::IsNullOrEmpty($rightString)) {
                                    try {
                                        $rightEnum = [System.DirectoryServices.ActiveDirectoryRights]::($rightString)
                                        $expectedRights = $expectedRights -bor $rightEnum
                                    } catch {
                                        # Invalid right - skip
                                    }
                                }
                            }
                        }
                        
                        # Resolve inheritedObjectType if present
                        $inheritedObjectTypeGuid = [Guid]::Empty
                        if ($acl.PSObject.Properties['inheritedObjectType'] -and -not [string]::IsNullOrEmpty($acl.inheritedObjectType)) {
                            try {
                                if (-not [System.Guid]::TryParse($acl.inheritedObjectType, [ref][System.Guid]::Empty)) {
                                    $resolvedInheritedObjectType = Resolve-TierModelGuid -Value $acl.inheritedObjectType -Mappings $Config.guidMappings -DomainController $DomainController
                                    if ($null -ne $resolvedInheritedObjectType -and -not [string]::IsNullOrEmpty($resolvedInheritedObjectType)) {
                                        $inheritedObjectTypeGuid = [Guid]$resolvedInheritedObjectType
                                    }
                                } else {
                                    $inheritedObjectTypeGuid = [Guid]$acl.inheritedObjectType
                                }
                            } catch {
                                $inheritedObjectTypeGuid = [Guid]::Empty
                            }
                        }
                        
                        $existingAcl = $currentAcl.Access | Where-Object {
                            try {
                                # Check identity reference (handle domain prefix)
                                $identityMatches = $_.IdentityReference.Value -like "*\$identityReference" -or 
                                                 $_.IdentityReference.Value -eq $identityReference
                                
                                # Check access control type
                                $accessControlMatches = $_.AccessControlType -eq $expectedAccessControlType
                                
                                # Check object type GUID
                                $objectTypeMatches = $_.ObjectType -eq $objectTypeGuid
                                
                                # Check inheritance type
                                $inheritanceMatches = $_.InheritanceType -eq $expectedInheritance
                                
                                # Check Active Directory Rights (exact match)
                                $rightsMatches = $_.ActiveDirectoryRights -eq $expectedRights
                                
                                # Check inherited object type GUID if present
                                $inheritedObjectTypeMatches = if ($inheritedObjectTypeGuid -ne [Guid]::Empty) {
                                    $_.InheritedObjectType -eq $inheritedObjectTypeGuid
                                } else {
                                    $_.InheritedObjectType -eq [Guid]::Empty -or $null -eq $_.InheritedObjectType
                                }
                                
                                return ($identityMatches -and $accessControlMatches -and $objectTypeMatches -and $inheritanceMatches -and $rightsMatches -and $inheritedObjectTypeMatches)
                            } catch {
                                return $false
                            }
                        }
                        
                        if ($existingAcl) {
                            $needsApplication = $false
                            $existingAclCount++
                            
                            # Show green check for existing ACL
                            $ouName = if ($targetOUPath -match '^OU=([^,]+)') { $matches[1] } else { $targetOUPath }
                            if (-not $Silent) {
                                Write-Host "  ✅ OU ACL Exists: $identityReference -> $ouName ($($acl.objecttype))" -ForegroundColor Green
                            }
                            
                            Write-TierModelLog -Level Info -Message "ACL delegation already exists with exact match (Fd)" -Data @{
                                TargetOUPath = $targetOUPath
                                IdentityReference = $identityReference
                                ObjectType = $acl.objecttype
                                Rights = ($acl.activedirectoryrights -join ', ')
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        }
                    } catch {
                        # Could not read ACL - assume it needs to be applied
                        Write-TierModelLog -Level Debug -Message "Could not read ACL, will attempt to apply" -Data @{
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            Exception = $_.Exception.Message
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    }
                }
                
                # Create action if ACL needs to be applied
                if ($needsApplication) {
                    $actions += [PSCustomObject]@{
                        Action = 'CreateAcl'
                        ResourceType = 'ACL'
                        Name = "ACL Delegation: $identityReference on $targetOUPath"
                        Path = $targetOUPath
                        Data = $acl
                        Dependencies = @()  # ACLs depend on OUs existing
                        RiskLevel = 'Low'   # ACL modifications are generally low risk
                        Validation = @{
                            TargetOUExists = $targetOUExists
                            PrincipalResolvable = $principalExists
                        }
                    }
                    
                    Write-TierModelLog -Level Info -Message "ACL delegation needs application (Fd)" -Data @{
                        AclId = if ($acl.PSObject.Properties.Name -contains 'id') { $acl.id } else { "$($acl.identityreference)-$($acl.targetOUPath)" }
                        TargetOUPath = $targetOUPath
                        IdentityReference = $identityReference
                        AccessControlType = $acl.accesscontroltype
                        TargetOUExists = $targetOUExists
                        PrincipalExists = $principalExists
                        CorrelationId = $CorrelationId
                    } | Out-Null
                }
                
            } catch {
                $planErrors += @{
                    Timestamp = Get-Date
                    Category = 'Processing'
                    Code = 'AclFdAnalysisFailed'
                    Message = "Failed to analyze ACL delegation (Fd): $($_.Exception.Message)"
                    Context = @{
                        IdentityReference = $acl.identityreference
                        TargetOUPath = $acl.targetOUPath
                    }
                }
            }
        }
        
        # No display logic in Full Deployment variant - handled by Deploy script
        
        # Calculate summary
        $createActions = @($actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        $lowRiskActions = @($actions | Where-Object { $_.RiskLevel -eq 'Low' }).Count
        
        # Build result
        $result = [PSCustomObject]@{
            Actions = $actions
            Errors = $planErrors
            Summary = @{
                TotalActions = $actions.Count
                CreateActions = $createActions
                ExistingCount = $existingAclCount
                RiskAssessment = @{
                    LowRisk = $lowRiskActions
                    MediumRisk = 0
                    HighRisk = 0
                }
            }
            Analysis = @{
                ConfiguredAcls = $Config.aclDelegations.Count
                ExistingAcls = $existingAclCount
                ValidationErrors = $planErrors.Count
            }
            Warnings = $warnings
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
        
        Write-TierModelLog -Level Info -Message "OuAclFdPlanningComplete" -Data @{
            TotalActions = $actions.Count
            CreateActions = $createActions
            ExistingAcls = $existingAclCount
            ValidationErrors = $planErrors.Count
            DurationMs = $result.DurationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $result
        
    } catch {
        Write-TierModelLog -Level Error -Message "OU ACL Fd planning failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = @()
            Summary = @{
                TotalActions = 0
                CreateActions = 0
                ExistingCount = 0
                RiskAssessment = @{
                    LowRisk = 0
                    MediumRisk = 0
                    HighRisk = 0
                }
            }
            Analysis = @{
                ConfiguredAcls = 0
                ExistingAcls = 0
                ValidationErrors = 1
            }
            Errors = @(@{
                Timestamp = Get-Date
                Category = 'Critical'
                Code = 'PlanningFdFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            Warnings = @()
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}