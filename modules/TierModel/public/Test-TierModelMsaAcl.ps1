function Test-TierModelMsaAcl {
    <#
    .SYNOPSIS
    Audit TierModel MSA ACL delegations against configuration.
    
    .DESCRIPTION
    Performs drift detection for standalone managed service account ACL delegations by
    validating that the expected ACEs exist on each target OU in Active Directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$Silent,
        
        [switch]$SuppressSummary
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "MsaAclAuditStart" -Data @{
        DomainController = $DomainController
        Silent = $Silent.IsPresent
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $totalAcls = 0
        $compliantCount = 0
        $missingCount = 0
        $mismatchCount = 0
        $errorCount = 0
        $findings = @()
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        if (-not ($Config.PSObject.Properties.Name -contains 'msaAclDelegations') -or -not $Config.msaAclDelegations) {
            Write-TierModelLog -Level Warning -Message "No MSA ACL delegations found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            
            return [PSCustomObject]@{
                TotalChecked = 0
                Compliant = 0
                Missing = 0
                Mismatched = 0
                Errors = 0
                Drift = 0
                Findings = @()
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }
        
        if (-not $Silent) {
            Write-Host "Auditing MSA ACL delegations..." -ForegroundColor Cyan
        }
        
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
        
        $testIdentityMatch = {
            param([string]$ActualIdentity, [string]$ExpectedIdentity)
            $ActualIdentity -eq $ExpectedIdentity -or $ActualIdentity -like "*\$ExpectedIdentity"
        }
        
        $testAceMatch = {
            param($Ace, $ExpectedAce)
            
            $identityMatches = & $testIdentityMatch $Ace.IdentityReference.Value $ExpectedAce.IdentityReference
            $accessControlMatches = $Ace.AccessControlType -eq $ExpectedAce.AccessControlType
            $objectTypeMatches = $Ace.ObjectType -eq $ExpectedAce.ObjectType
            $inheritanceMatches = $Ace.InheritanceType -eq $ExpectedAce.InheritanceType
            $rightsMatches = $Ace.ActiveDirectoryRights -eq $ExpectedAce.ActiveDirectoryRights
            $inheritedObjectTypeMatches = if ($ExpectedAce.InheritedObjectType -ne [Guid]::Empty) {
                $Ace.InheritedObjectType -eq $ExpectedAce.InheritedObjectType
            } else {
                $Ace.InheritedObjectType -eq [Guid]::Empty -or $null -eq $Ace.InheritedObjectType
            }
            
            $identityMatches -and $accessControlMatches -and $objectTypeMatches -and $inheritanceMatches -and $rightsMatches -and $inheritedObjectTypeMatches
        }
        
        $delegationGroups = @{}
        foreach ($acl in @($Config.msaAclDelegations)) {
            try {
                $targetOUPath = Resolve-TierModelPlaceholder -Path $acl.targetOUPath -DomainDN $domainDN
                $key = "$targetOUPath||$($acl.identityreference)"
                
                if (-not $delegationGroups.ContainsKey($key)) {
                    $delegationGroups[$key] = [ordered]@{
                        TargetOUPath = $targetOUPath
                        IdentityReference = $acl.identityreference
                        Entries = @()
                    }
                }
                
                $delegationGroups[$key].Entries += $acl
            } catch {
                $findings += [PSCustomObject]@{
                    Type = 'Error'
                    ResourceType = 'ACL'
                    Identifier = "$($acl.identityreference) → $($acl.targetOUPath)"
                    Property = 'Config'
                    ExpectedValue = 'Resolvable target OU path'
                    ActualValue = 'Resolution failed'
                    Details = $_.Exception.Message
                }
                $errorCount++
            }
        }
        
        $serviceAccountGuid = [Guid](& $resolveAclGuid 'msDS-ManagedServiceAccount')
        
        foreach ($group in $delegationGroups.Values) {
            $totalAcls++
            $targetOUPath = $group.TargetOUPath
            $identityReference = $group.IdentityReference
            $identifier = "$identityReference → $targetOUPath"
            
            if (-not $Silent) {
                Write-Host "Checking MSA ACL Delegation: $identifier" -ForegroundColor Cyan
            }
            
            # Step 1: Check if target OU exists
            try {
                Get-ADOrganizationalUnit -Identity $targetOUPath -Server $DomainController -ErrorAction Stop | Out-Null
                if (-not $Silent) {
                    Write-Host "    ✅ Target OU exists" -ForegroundColor Green
                }
            } catch {
                if (-not $Silent) {
                    Write-Host "    ❌ Target OU missing" -ForegroundColor Red
                }
                
                $findings += [PSCustomObject]@{
                    Type = 'MissingAcl'
                    ResourceType = 'ACL'
                    Identifier = $identifier
                    Property = 'TargetOU'
                    ExpectedValue = $targetOUPath
                    ActualValue = 'Not Found'
                    Details = "Target OU '$targetOUPath' does not exist."
                }
                $missingCount++
                continue
            }
            
            # Step 2: Check if identity/group exists
            try {
                $null = Get-ADGroup -Identity $identityReference -Server $DomainController -ErrorAction Stop
                if (-not $Silent) {
                    Write-Host "    ✅ Identity '$identityReference' exists (Group)" -ForegroundColor Green
                }
            } catch {
                try {
                    $null = Get-ADUser -Identity $identityReference -Server $DomainController -ErrorAction Stop
                    if (-not $Silent) {
                        Write-Host "    ✅ Identity '$identityReference' exists (User)" -ForegroundColor Green
                    }
                } catch {
                    if (-not $Silent) {
                        Write-Host "    ❌ Identity '$identityReference' not found" -ForegroundColor Red
                    }
                    
                    $findings += [PSCustomObject]@{
                        Type = 'MissingAcl'
                        ResourceType = 'ACL'
                        Identifier = $identifier
                        Property = 'Identity'
                        ExpectedValue = $identityReference
                        ActualValue = 'Not Found'
                        Details = "Identity '$identityReference' does not exist in Active Directory."
                    }
                    $missingCount++
                    continue
                }
            }
            
            # Step 3: Read OU ACL
            try {
                $currentAcl = Get-Acl -Path "AD:\$targetOUPath" -ErrorAction Stop
                if (-not $Silent) {
                    Write-Host "    ✅ OU ACL readable" -ForegroundColor Green
                }
            } catch {
                if (-not $Silent) {
                    Write-Host "    ❌ Cannot read OU ACL" -ForegroundColor Red
                }
                
                $findings += [PSCustomObject]@{
                    Type = 'Error'
                    ResourceType = 'ACL'
                    Identifier = $identifier
                    Property = 'ACLAccess'
                    ExpectedValue = 'Readable'
                    ActualValue = 'Failed'
                    Details = $_.Exception.Message
                }
                $errorCount++
                continue
            }
            
            $expectedEntries = @()
            foreach ($acl in @($group.Entries)) {
                $resolvedObjectType = & $resolveAclGuid $acl.objecttype
                $objectTypeGuid = if ([string]::IsNullOrEmpty($resolvedObjectType)) { [Guid]::Empty } else { [Guid]$resolvedObjectType }
                $expectedRights = 0 -as [System.DirectoryServices.ActiveDirectoryRights]
                
                foreach ($rightString in @($acl.activedirectoryrights)) {
                    if (-not [string]::IsNullOrEmpty($rightString)) {
                        $expectedRights = $expectedRights -bor [System.DirectoryServices.ActiveDirectoryRights]::($rightString)
                    }
                }
                
                $inheritedObjectTypeGuid = [Guid]::Empty
                if ($acl.PSObject.Properties['inheritedObjectType'] -and -not [string]::IsNullOrEmpty($acl.inheritedObjectType)) {
                    $resolvedInheritedObjectType = & $resolveAclGuid $acl.inheritedObjectType
                    if (-not [string]::IsNullOrEmpty($resolvedInheritedObjectType)) {
                        $inheritedObjectTypeGuid = [Guid]$resolvedInheritedObjectType
                    }
                }
                
                $expectedEntries += [PSCustomObject]@{
                    IdentityReference = $identityReference
                    AccessControlType = [System.Security.AccessControl.AccessControlType]::$($acl.accesscontroltype)
                    ObjectType = $objectTypeGuid
                    InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$($acl.activeDirectorysecurityinheritance)
                    ActiveDirectoryRights = $expectedRights
                    InheritedObjectType = $inheritedObjectTypeGuid
                    Source = $acl.comment
                }
            }
            
            $missingExpected = @()
            foreach ($expectedAce in $expectedEntries) {
                $matchedAce = $null
                foreach ($ace in $currentAcl.Access) {
                    if (& $testAceMatch $ace $expectedAce) {
                        $matchedAce = $ace
                        break
                    }
                }
                
                if (-not $matchedAce) {
                    $missingExpected += $expectedAce
                }
            }
            
            $relevantAces = @()
            foreach ($ace in $currentAcl.Access) {
                if (& $testIdentityMatch $ace.IdentityReference.Value $identityReference) {
                    if ($ace.ObjectType -eq $serviceAccountGuid -or $ace.InheritedObjectType -eq $serviceAccountGuid) {
                        $relevantAces += $ace
                    }
                }
            }
            
            $unexpectedAces = @()
            foreach ($ace in $relevantAces) {
                $isExpected = $false
                foreach ($expectedAce in $expectedEntries) {
                    if (& $testAceMatch $ace $expectedAce) {
                        $isExpected = $true
                        break
                    }
                }
                
                if (-not $isExpected) {
                    $unexpectedAces += $ace
                }
            }
            
            if ($missingExpected.Count -eq 0 -and $unexpectedAces.Count -eq 0) {
                if (-not $Silent) {
                    Write-Host "    ✅ ACL Delegation COMPLIANT" -ForegroundColor Green
                }
                
                $findings += [PSCustomObject]@{
                    Type = 'Compliant'
                    ResourceType = 'ACL'
                    Identifier = $identifier
                    Property = 'ACEs'
                    ExpectedValue = 'Both expected MSA ACEs present'
                    ActualValue = 'Matched'
                    Details = 'Create/DeleteChild and descendant GenericAll ACEs match configuration.'
                }
                $compliantCount++
                continue
            }
            
            if ($missingExpected.Count -gt 0) {
                if (-not $Silent) {
                    Write-Host "    ❌ Missing expected ACEs" -ForegroundColor Red
                }
                
                $findings += [PSCustomObject]@{
                    Type = 'MissingAcl'
                    ResourceType = 'ACL'
                    Identifier = $identifier
                    Property = 'ACEs'
                    ExpectedValue = 'Both expected MSA ACEs present'
                    ActualValue = "$($missingExpected.Count) expected ACE(s) missing"
                    Details = (($missingExpected | ForEach-Object {
                        "AccessType=$($_.AccessControlType); Rights=$($_.ActiveDirectoryRights); Inheritance=$($_.InheritanceType); ObjectType=$($_.ObjectType); InheritedObjectType=$($_.InheritedObjectType)"
                    }) -join ' | ')
                }
                $missingCount++
            }
            
            if ($unexpectedAces.Count -gt 0) {
                if (-not $Silent) {
                    Write-Host "    ⚠️ Unexpected ACEs detected" -ForegroundColor Yellow
                }
                
                $findings += [PSCustomObject]@{
                    Type = 'UnexpectedAcl'
                    ResourceType = 'ACL'
                    Identifier = $identifier
                    Property = 'ACEs'
                    ExpectedValue = 'Only configured MSA ACEs present'
                    ActualValue = "$($unexpectedAces.Count) unexpected ACE(s) found"
                    Details = (($unexpectedAces | ForEach-Object {
                        "Identity=$($_.IdentityReference.Value); AccessType=$($_.AccessControlType); Rights=$($_.ActiveDirectoryRights); Inheritance=$($_.InheritanceType); ObjectType=$($_.ObjectType); InheritedObjectType=$($_.InheritedObjectType)"
                    }) -join ' | ')
                }
                $mismatchCount++
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        if (-not $Silent -and -not $SuppressSummary) {
            Write-Host "`n=== MSA ACL Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total Checked: $totalAcls" -ForegroundColor White
            Write-Host "Compliant: $compliantCount" -ForegroundColor Green
            Write-Host "Missing: $missingCount" -ForegroundColor Red
            Write-Host "Mismatched: $mismatchCount" -ForegroundColor Yellow
            Write-Host "Errors: $errorCount" -ForegroundColor Red
        }
        
        Write-TierModelLog -Level Info -Message "MsaAclAuditComplete" -Data @{
            TotalChecked = $totalAcls
            Compliant = $compliantCount
            Missing = $missingCount
            Mismatched = $mismatchCount
            Errors = $errorCount
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            TotalChecked = $totalAcls
            Compliant = $compliantCount
            Missing = $missingCount
            Mismatched = $mismatchCount
            Errors = $errorCount
            Drift = $missingCount + $mismatchCount
            Findings = $findings
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        }
    } catch {
        Write-TierModelLog -Level Error -Message "MSA ACL audit failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            TotalChecked = 0
            Compliant = 0
            Missing = 0
            Mismatched = 0
            Errors = 1
            Drift = 0
            Findings = @([PSCustomObject]@{
                Type = 'Error'
                ResourceType = 'ACL'
                Identifier = 'MSA ACL Audit'
                Property = 'Execution'
                ExpectedValue = 'Audit should complete successfully'
                ActualValue = 'Failed'
                Details = $_.Exception.Message
            })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
