function Get-TierModelDmsaAcl {
    <#
    .SYNOPSIS
    Analyze TierModel dMSA ACL delegation requirements and generate deployment plan.
    
    .DESCRIPTION
    Examines delegated managed service account ACL delegation configuration and current
    Active Directory OU ACL state to generate a deployment plan. Validates target OUs
    and delegation groups exist before evaluating ACL state, and dynamically resolves
    the domain-specific dMSA class GUID.
    
    .PARAMETER Config
    TierModel configuration object containing dMSA ACL delegation definitions.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER IncludeDetails
    Include detailed analysis in the planning output for troubleshooting.
    
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
    
    Write-TierModelLog -Level Info -Message "DmsaAclPlanningStart" -Data @{
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $actions = @()
        $planErrors = @()
        $warnings = @()
        
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        if (-not ($Config.PSObject.Properties.Name -contains 'dmsaAclDelegations') -or
            -not $Config.dmsaAclDelegations -or
            $Config.dmsaAclDelegations.Count -eq 0) {
            
            Write-TierModelLog -Level Warning -Message "No dMSA ACL delegations found in configuration" -Data @{
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
        
        $delegations = @($Config.dmsaAclDelegations)
        $dmsaGuid = Resolve-DomainSpecificGuid -AttributeName 'msDS-DelegatedManagedServiceAccount' -SchemaObjectClass 'classSchema' -DomainController $DomainController
        $parsedDmsaGuid = [Guid]::Empty
        if ([string]::IsNullOrEmpty([string]$dmsaGuid) -or -not [Guid]::TryParse([string]$dmsaGuid, [ref]$parsedDmsaGuid) -or $parsedDmsaGuid -eq [Guid]::Empty) {
            throw "Failed to resolve domain-specific GUID for 'msDS-DelegatedManagedServiceAccount'."
        }
        
        Write-TierModelLog -Level Info -Message "Analyzing dMSA ACL delegations" -Data @{
            TotalAclsInConfig = $delegations.Count
            ResolvedDmsaGuid = $dmsaGuid
            CorrelationId = $CorrelationId
        } | Out-Null
        
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
            
            if ($Value -eq 'msDS-DelegatedManagedServiceAccount') {
                return $dmsaGuid
            }
            
            $resolvedGuid = Resolve-TierModelGuid -Value $Value -Mappings $Config.guidMappings -DomainController $DomainController
            if ($null -eq $resolvedGuid) {
                throw "Failed to resolve GUID for '$Value'"
            }
            
            return $resolvedGuid
        }
        
        $uniqueOUs = $delegations | ForEach-Object {
            Resolve-TierModelPlaceholder -Path $_.targetOUPath -DomainDN $domainDN
        } | Select-Object -Unique
        
        foreach ($ouPath in $uniqueOUs) {
            try {
                Get-ADOrganizationalUnit -Identity $ouPath -Server $DomainController -ErrorAction Stop | Out-Null
            } catch {
                $planErrors += @{
                    Timestamp = Get-Date
                    Category = 'Validation'
                    Code = 'TargetOUNotFound'
                    Message = "Target OU not found: '$ouPath'. Use -OusOnly to deploy the OUs, or use -FullDeployment -IncludeDmsa."
                    Context = @{ TargetOUPath = $ouPath }
                }
            }
        }
        
        $uniqueGroups = $delegations | ForEach-Object { $_.identityreference } | Select-Object -Unique
        foreach ($group in $uniqueGroups) {
            try {
                Get-ADGroup -Identity $group -Server $DomainController -ErrorAction Stop | Out-Null
            } catch {
                $planErrors += @{
                    Timestamp = Get-Date
                    Category = 'Validation'
                    Code = 'SecurityPrincipalNotFound'
                    Message = "Delegation group '$group' not found. Use -GroupsOnly to deploy the Groups, or use -FullDeployment -IncludeDmsa."
                    Context = @{ IdentityReference = $group }
                }
            }
        }
        
        if ($planErrors.Count -gt 0) {
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
                    ConfiguredAcls = $delegations.Count
                    ExistingAcls = 0
                    ValidationErrors = $planErrors.Count
                }
                Errors = $planErrors
                Warnings = @("One or more prerequisites are missing. Deploy the Tier Model OUs and Groups first.")
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }
        
        foreach ($acl in $delegations) {
            try {
                $targetOUPath = Resolve-TierModelPlaceholder -Path $acl.targetOUPath -DomainDN $domainDN
                $resolvedObjectType = & $resolveAclGuid $acl.objecttype
                $identityReference = $acl.identityreference
                $objectTypeGuid = if ([string]::IsNullOrEmpty($resolvedObjectType)) {
                    [Guid]::Empty
                } else {
                    [Guid]$resolvedObjectType
                }
                
                $existingAcl = $null
                $needsApplication = $true
                
                try {
                    $currentAcl = Get-Acl -Path "AD:\$targetOUPath" -ErrorAction Stop
                    
                    $expectedAccessControlType = [System.Security.AccessControl.AccessControlType]::$($acl.accesscontroltype)
                    $expectedInheritance = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$($acl.activeDirectorysecurityinheritance)
                    
                    $expectedRights = 0 -as [System.DirectoryServices.ActiveDirectoryRights]
                    if ($acl.activedirectoryrights -and $acl.activedirectoryrights.Count -gt 0) {
                        foreach ($rightString in $acl.activedirectoryrights) {
                            if (-not [string]::IsNullOrEmpty($rightString)) {
                                try {
                                    $rightEnum = [System.DirectoryServices.ActiveDirectoryRights]::($rightString)
                                    $expectedRights = $expectedRights -bor $rightEnum
                                } catch {
                                }
                            }
                        }
                    }
                    
                    $inheritedObjectTypeGuid = [Guid]::Empty
                    if ($acl.PSObject.Properties['inheritedObjectType'] -and -not [string]::IsNullOrEmpty($acl.inheritedObjectType)) {
                        $resolvedInheritedObjectType = & $resolveAclGuid $acl.inheritedObjectType
                        if ($null -ne $resolvedInheritedObjectType -and -not [string]::IsNullOrEmpty($resolvedInheritedObjectType)) {
                            $inheritedObjectTypeGuid = [Guid]$resolvedInheritedObjectType
                        }
                    }
                    
                    $existingAcl = $currentAcl.Access | Where-Object {
                        try {
                            $identityMatches = $_.IdentityReference.Value -like "*\$identityReference" -or
                                             $_.IdentityReference.Value -eq $identityReference
                            $accessControlMatches = $_.AccessControlType -eq $expectedAccessControlType
                            $objectTypeMatches = $_.ObjectType -eq $objectTypeGuid
                            $inheritanceMatches = $_.InheritanceType -eq $expectedInheritance
                            $rightsMatches = $_.ActiveDirectoryRights -eq $expectedRights
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
                        Write-TierModelLog -Level Info -Message "dMSA ACL delegation already exists with exact match" -Data @{
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            ObjectType = $resolvedObjectType
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
                
                if ($needsApplication) {
                    $actionData = @{}
                    foreach ($property in $acl.PSObject.Properties) {
                        $actionData[$property.Name] = $property.Value
                    }
                    if (-not [string]::IsNullOrEmpty($resolvedObjectType)) {
                        $actionData['objecttype'] = $resolvedObjectType
                    }
                    if ($acl.PSObject.Properties['inheritedObjectType']) {
                        $actionData['inheritedObjectType'] = if ($inheritedObjectTypeGuid -ne [Guid]::Empty) {
                            $inheritedObjectTypeGuid.ToString()
                        } else {
                            $acl.inheritedObjectType
                        }
                    }
                    
                    $actions += [PSCustomObject]@{
                        Action = 'CreateAcl'
                        ResourceType = 'ACL'
                        Name = "ACL Delegation: $identityReference on $targetOUPath"
                        Path = $targetOUPath
                        Data = [PSCustomObject]$actionData
                        Dependencies = @()
                        RiskLevel = 'Low'
                        Validation = @{
                            TargetOUExists = $true
                            PrincipalResolvable = $true
                        }
                    }
                    
                    Write-TierModelLog -Level Info -Message "dMSA ACL delegation needs application" -Data @{
                        AclId = if ($acl.PSObject.Properties.Name -contains 'id') { $acl.id } else { "$($acl.identityreference)-$($acl.targetOUPath)" }
                        TargetOUPath = $targetOUPath
                        IdentityReference = $identityReference
                        AccessControlType = $acl.accesscontroltype
                        ResolvedDmsaGuid = $dmsaGuid
                        CorrelationId = $CorrelationId
                    } | Out-Null
                }
            } catch {
                $planErrors += @{
                    Timestamp = Get-Date
                    Category = 'Processing'
                    Code = 'AclAnalysisFailed'
                    Message = "Failed to analyze dMSA ACL delegation: $($_.Exception.Message)"
                    Context = @{
                        IdentityReference = $acl.identityreference
                        TargetOUPath = $acl.targetOUPath
                    }
                }
            }
        }
        
        $createActions = @($actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        $lowRiskActions = @($actions | Where-Object { $_.RiskLevel -eq 'Low' }).Count
        
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
                ConfiguredAcls = $delegations.Count
                ExistingAcls = $delegations.Count - $createActions
                ValidationErrors = $planErrors.Count
            }
            Warnings = $warnings
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
        
        Write-TierModelLog -Level Info -Message "DmsaAclPlanningComplete" -Data @{
            TotalActions = $actions.Count
            CreateActions = $createActions
            ValidationErrors = $planErrors.Count
            DurationMs = $result.DurationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $result
    } catch {
        Write-TierModelLog -Level Error -Message "dMSA ACL planning failed" -Data @{
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
