function Get-TierModelGmsaAclFd {
    <#
    .SYNOPSIS
    Analyze TierModel gMSA ACL delegation requirements and generate deployment plan (Full Deployment variant).
    
    .DESCRIPTION
    Examines group managed service account ACL delegation configuration and current
    Active Directory OU ACL state to generate a deployment plan for full deployment scenarios.
    This variant uses lighter validation and assumes prerequisite OUs and groups are created
    by earlier phases.
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
    
    Write-TierModelLog -Level Info -Message "GmsaAclFdPlanningStart" -Data @{
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $actions = @()
        $planErrors = @()
        $warnings = @()
        $existingAclCount = 0
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        if (-not ($Config.PSObject.Properties.Name -contains 'gmsaAclDelegations') -or
            -not $Config.gmsaAclDelegations -or
            $Config.gmsaAclDelegations.Count -eq 0) {
            
            Write-TierModelLog -Level Warning -Message "No gMSA ACL delegations found in configuration" -Data @{
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
                    ValidationErrors = 0
                }
                Errors = @()
                Warnings = @()
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }
        
        $delegations = @($Config.gmsaAclDelegations)
        
        Write-TierModelLog -Level Info -Message "Analyzing gMSA ACL delegations (Full Deployment)" -Data @{
            TotalAclsInConfig = $delegations.Count
            ServiceAccountClass = 'msDS-GroupManagedServiceAccount'
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
            
            $resolvedGuid = Resolve-TierModelGuid -Value $Value -Mappings $Config.guidMappings -DomainController $DomainController
            if ($null -eq $resolvedGuid) {
                throw "Failed to resolve GUID for '$Value'"
            }
            
            return $resolvedGuid
        }
        
        foreach ($acl in $delegations) {
            try {
                $targetOUPath = Resolve-TierModelPlaceholder -Path $acl.targetOUPath -DomainDN $domainDN
                $resolvedObjectType = & $resolveAclGuid $acl.objecttype
                $identityReference = $acl.identityreference
                $objectTypeGuid = if ([string]::IsNullOrEmpty($resolvedObjectType)) { [Guid]::Empty } else { [Guid]$resolvedObjectType }
                $inheritedObjectTypeGuid = [Guid]::Empty
                
                if ($acl.PSObject.Properties['inheritedObjectType'] -and -not [string]::IsNullOrEmpty($acl.inheritedObjectType)) {
                    $resolvedInheritedObjectType = & $resolveAclGuid $acl.inheritedObjectType
                    if ($null -ne $resolvedInheritedObjectType -and -not [string]::IsNullOrEmpty($resolvedInheritedObjectType)) {
                        $inheritedObjectTypeGuid = [Guid]$resolvedInheritedObjectType
                    }
                }
                
                $targetOUExists = $false
                $principalExists = $false
                
                try {
                    Get-ADOrganizationalUnit -Identity $targetOUPath -Server $DomainController -ErrorAction Stop | Out-Null
                    $targetOUExists = $true
                } catch {
                }
                
                try {
                    Get-ADGroup -Identity $identityReference -Server $DomainController -ErrorAction Stop | Out-Null
                    $principalExists = $true
                } catch {
                    try {
                        Get-ADUser -Identity $identityReference -Server $DomainController -ErrorAction Stop | Out-Null
                        $principalExists = $true
                    } catch {
                    }
                }
                
                $needsApplication = $true
                if ($targetOUExists -and $principalExists) {
                    try {
                        $currentAcl = Get-Acl -Path "AD:\$targetOUPath" -ErrorAction Stop
                        $expectedAccessControlType = [System.Security.AccessControl.AccessControlType]::$($acl.accesscontroltype)
                        $expectedInheritance = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$($acl.activeDirectorysecurityinheritance)
                        $expectedRights = 0 -as [System.DirectoryServices.ActiveDirectoryRights]
                        
                        foreach ($rightString in @($acl.activedirectoryrights)) {
                            if (-not [string]::IsNullOrEmpty($rightString)) {
                                try {
                                    $expectedRights = $expectedRights -bor [System.DirectoryServices.ActiveDirectoryRights]::($rightString)
                                } catch {
                                }
                            }
                        }
                        
                        $existingAcl = $currentAcl.Access | Where-Object {
                            try {
                                $identityMatches = $_.IdentityReference.Value -like "*\$identityReference" -or $_.IdentityReference.Value -eq $identityReference
                                $accessControlMatches = $_.AccessControlType -eq $expectedAccessControlType
                                $objectTypeMatches = $_.ObjectType -eq $objectTypeGuid
                                $inheritanceMatches = $_.InheritanceType -eq $expectedInheritance
                                $rightsMatches = $_.ActiveDirectoryRights -eq $expectedRights
                                $inheritedObjectTypeMatches = if ($inheritedObjectTypeGuid -ne [Guid]::Empty) {
                                    $_.InheritedObjectType -eq $inheritedObjectTypeGuid
                                } else {
                                    $_.InheritedObjectType -eq [Guid]::Empty -or $null -eq $_.InheritedObjectType
                                }
                                
                                $identityMatches -and $accessControlMatches -and $objectTypeMatches -and $inheritanceMatches -and $rightsMatches -and $inheritedObjectTypeMatches
                            } catch {
                                $false
                            }
                        }
                        
                        if ($existingAcl) {
                            $needsApplication = $false
                            $existingAclCount++
                            
                            if (-not $Silent) {
                                $ouName = if ($targetOUPath -match '^OU=([^,]+)') { $matches[1] } else { $targetOUPath }
                                Write-Host "  ✅ gMSA ACL Exists: $identityReference -> $ouName" -ForegroundColor Green
                            }
                            
                            Write-TierModelLog -Level Info -Message "gMSA ACL delegation already exists with exact match (Fd)" -Data @{
                                TargetOUPath = $targetOUPath
                                IdentityReference = $identityReference
                                ObjectType = $resolvedObjectType
                                Rights = ($acl.activedirectoryrights -join ', ')
                                CorrelationId = $CorrelationId
                            } | Out-Null
                        }
                    } catch {
                        Write-TierModelLog -Level Debug -Message "Could not read gMSA ACL, will plan create action" -Data @{
                            TargetOUPath = $targetOUPath
                            IdentityReference = $identityReference
                            Exception = $_.Exception.Message
                            CorrelationId = $CorrelationId
                        } | Out-Null
                    }
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
                            TargetOUExists = $targetOUExists
                            PrincipalResolvable = $principalExists
                        }
                    }
                    
                    Write-TierModelLog -Level Info -Message "gMSA ACL delegation needs application (Fd)" -Data @{
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
                    Code = 'GmsaAclFdAnalysisFailed'
                    Message = "Failed to analyze gMSA ACL delegation (Fd): $($_.Exception.Message)"
                    Context = @{
                        IdentityReference = $acl.identityreference
                        TargetOUPath = $acl.targetOUPath
                    }
                }
            }
        }
        
        $createActions = @($actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        $lowRiskActions = @($actions | Where-Object { $_.RiskLevel -eq 'Low' }).Count
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        $result = [PSCustomObject]@{
            Actions = $actions
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
                ConfiguredAcls = $delegations.Count
                ExistingAcls = $existingAclCount
                ValidationErrors = $planErrors.Count
            }
            Errors = $planErrors
            Warnings = $warnings
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        }
        
        Write-TierModelLog -Level Info -Message "GmsaAclFdPlanningComplete" -Data @{
            TotalActions = $actions.Count
            CreateActions = $createActions
            ExistingAcls = $existingAclCount
            ValidationErrors = $planErrors.Count
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $result
    } catch {
        Write-TierModelLog -Level Error -Message "gMSA ACL Fd planning failed" -Data @{
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
                Code = 'GmsaAclFdPlanningFailed'
                Message = $_.Exception.Message
                Context = @{ CorrelationId = $CorrelationId }
            })
            Warnings = @()
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
