function Get-TierModelOuAcl {
    <#
    .SYNOPSIS
    Analyze TierModel OU ACL delegation requirements and generate deployment plan.
    
    .DESCRIPTION
    Examines the TierModel configuration and current Active Directory OU ACL state
    to generate a deployment plan for ACL delegations. Validates target OUs exist,
    resolves security principals, and determines which ACL entries need to be applied.
    
    .PARAMETER Config
    TierModel configuration object containing ACL delegation definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER IncludeDetails
    Include detailed analysis in the planning output for troubleshooting.
    
    .EXAMPLE
    $plan = Get-TierModelOuAcl -Config $config -DomainController "DC01"
    
    .EXAMPLE
    $plan = Get-TierModelOuAcl -Config $config -DomainController "DC01" -IncludeDetails
    
    .OUTPUTS
    PSCustomObject with deployment plan including actions, summary, and analysis details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$IncludeDetails
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "OuAclPlanningStart" -Data @{
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
        
        Write-TierModelLog -Level Info -Message "Analyzing ACL delegations" -Data @{
            TotalAclsInConfig = $Config.aclDelegations.Count
            CorrelationId = $CorrelationId
        } | Out-Null
        
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
                
                # Validate target OU exists
                $targetOUExists = $false
                try {
                    Get-ADOrganizationalUnit -Identity $targetOUPath -Server $DomainController -ErrorAction Stop | Out-Null
                    $targetOUExists = $true
                } catch {
                    # Extract just the OU name for cleaner error messages
                    $ouName = if ($targetOUPath -match '^OU=([^,]+)') { $matches[1] } else { $targetOUPath }
                    $planErrors += @{
                        Timestamp = Get-Date
                        Category = 'Validation'
                        Code = 'TargetOUNotFound'
                        Message = "Target OU '$ouName' does not exist - create OUs first"
                        Context = @{
                            AclId = if ($acl.PSObject.Properties.Name -contains 'id') { $acl.id } else { "$($acl.identityreference)-$($acl.targetOUPath)" }
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                        }
                    }
                }
                
                # Validate security principal (Group) exists
                $principalExists = $false
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
                        $planErrors += @{
                            Timestamp = Get-Date
                            Category = 'Validation'
                            Code = 'SecurityPrincipalNotFound'
                            Message = "Security principal '$identityReference' does not exist - create Groups first"
                            Context = @{
                                AclId = if ($acl.PSObject.Properties.Name -contains 'id') { $acl.id } else { "$($acl.identityreference)-$($acl.targetOUPath)" }
                                TargetOUPath = $targetOUPath
                                IdentityReference = $identityReference
                            }
                        }
                    }
                }
                
                # Only proceed to ACL checking if both OU and principal exist
                if (-not $targetOUExists -or -not $principalExists) {
                    continue
                }
                
                # Check if ACL already exists
                $existingAcl = $null
                $needsApplication = $true
                
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
                        Write-TierModelLog -Level Info -Message "ACL delegation already exists with exact match" -Data @{
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            ObjectType = $acl.objecttype
                            Rights = ($acl.activedirectoryrights -join ', ')
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    }
                } catch {
                    $planErrors += @{
                        Timestamp = Get-Date
                        Category = 'AccessCheck'
                        Code = 'AclReadFailed'
                        Message = "Could not read existing ACL for OU '$targetOUPath': $($_.Exception.Message)"
                        Context = @{
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                        }
                    }
                    continue
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
                            PrincipalResolvable = $true  # We'll validate this during execution
                        }
                    }
                    
                    Write-TierModelLog -Level Info -Message "ACL delegation needs application" -Data @{
                        AclId = if ($acl.PSObject.Properties.Name -contains 'id') { $acl.id } else { "$($acl.identityreference)-$($acl.targetOUPath)" }
                        TargetOUPath = $targetOUPath
                        IdentityReference = $identityReference
                        AccessControlType = $acl.accesscontroltype
                        CorrelationId = $CorrelationId
                    } | Out-Null
                }
                
            } catch {
                $planErrors += @{
                    Timestamp = Get-Date
                    Category = 'Processing'
                    Code = 'AclAnalysisFailed'
                    Message = "Failed to analyze ACL delegation: $($_.Exception.Message)"
                    Context = @{
                        IdentityReference = $acl.identityreference
                        TargetOUPath = $acl.targetOUPath
                    }
                }
            }
        }
        
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
                RiskAssessment = @{
                    LowRisk = $lowRiskActions
                    MediumRisk = 0
                    HighRisk = 0
                }
            }
            Analysis = @{
                ConfiguredAcls = $Config.aclDelegations.Count
                ExistingAcls = $Config.aclDelegations.Count - $createActions
                ValidationErrors = $planErrors.Count
            }
            Warnings = $warnings
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
        
        Write-TierModelLog -Level Info -Message "OuAclPlanningComplete" -Data @{
            TotalActions = $actions.Count
            CreateActions = $createActions
            ValidationErrors = $planErrors.Count
            DurationMs = $result.DurationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $result
        
    } catch {
        Write-TierModelLog -Level Error -Message "OU ACL planning failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Actions = @()
            Summary = @{
                TotalActions = 0
                CreateActions = 0
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
                Code = 'PlanningFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            Warnings = @()
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}