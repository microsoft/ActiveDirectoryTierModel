function Test-TierModelOuAcl {
    <#
    .SYNOPSIS
    Audit TierModel OU ACL delegations against configuration.
    
    .DESCRIPTION
    Validates that OU ACL delegations in Active Directory match the TierModel configuration.
    Performs comprehensive property-by-property validation including:
    - Target OU existence
    - Identity/Group existence  
    - ACL readability
    - Access Control Type matching
    - Inheritance settings
    - Object Type GUID
    - Active Directory Rights
    Reports detailed compliance status and identifies specific drift from configuration.
    
    .PARAMETER Config
    TierModel configuration object containing ACL delegation definitions to validate against.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER Silent
    Suppress console output and return only the results object.
    
    .EXAMPLE
    Test-TierModelOuAcl -Config $config -DomainController "DC01"
    
    .EXAMPLE
    $auditResults = Test-TierModelOuAcl -Config $config -DomainController "DC01" -Silent
    
    .OUTPUTS
    PSCustomObject with audit results including compliance status and detailed drift findings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$Silent
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "OuAclAuditStart" -Data @{
        DomainController = $DomainController
        Silent = $Silent.IsPresent
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Initialize audit results
        $totalAcls = 0
        $compliantCount = 0
        $missingCount = 0
        $mismatchCount = 0
        $errorCount = 0
        $findings = @()
        
        # Resolve domain DN for placeholder replacement
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        
        # Check aclDelegations if they exist in config
        if (-not $Config.PSObject.Properties['aclDelegations'] -or -not $Config.aclDelegations) {
            Write-TierModelLog -Level Warning -Message "No aclDelegations found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            
            if (-not $Silent) {
                Write-Host "No OU ACL delegations found in configuration" -ForegroundColor Yellow
            }
            
            $findings += [PSCustomObject]@{
                Type = 'Warning'
                ResourceType = 'Config'
                Identifier = 'aclDelegations'
                Property = 'Existence'
                ExpectedValue = 'aclDelegations section should exist'
                ActualValue = 'No aclDelegations found'
                Details = 'Configuration does not contain aclDelegations section'
            }
        } else {
            if (-not $Silent) {
                Write-Host "Auditing OU ACL delegations..." -ForegroundColor Cyan
            }
        
            # Audit each ACL delegation
            foreach ($acl in $Config.aclDelegations) {
                $totalAcls++
                
                try {
                    # Replace placeholders in target OU path
                    $targetOUPath = Resolve-TierModelPlaceholder -Path $acl.targetOUPath -DomainDN $domainDN
                    $identityReference = $acl.identityreference
                    
                    Write-Host "Checking ACL Delegation: $identityReference → $targetOUPath" -ForegroundColor Cyan
                    
                    # Step 1: Check if target OU exists
                    try {
                        Get-ADOrganizationalUnit -Identity $targetOUPath -Server $DomainController -ErrorAction Stop | Out-Null
                        Write-Host "    ✅ Target OU exists" -ForegroundColor Green
                    } catch {
                        Write-Host "    ❌ Target OU missing" -ForegroundColor Red
                        
                        $findings += [PSCustomObject]@{
                            Type = 'Drift'
                            ResourceType = 'ACL'
                            Identifier = "$identityReference → $($acl.targetOUPath)"
                            Property = 'TargetOU'
                            ExpectedValue = $targetOUPath
                            ActualValue = 'Not Found'
                            Details = "Target OU '$targetOUPath' for ACL delegation does not exist"
                        }
                        $missingCount++
                        continue
                    }
                    
                    # Step 2: Check if identity/group exists
                    $resolvedIdentity = $null
                    try {
                        # Try as group first
                        try {
                            $groupObject = Get-ADGroup -Identity $identityReference -Server $DomainController -ErrorAction Stop
                            $resolvedIdentity = $groupObject.SamAccountName
                            Write-Host "    ✅ Identity '$identityReference' exists (Group)" -ForegroundColor Green
                        } catch {
                            # Try as user
                            try {
                                $userObject = Get-ADUser -Identity $identityReference -Server $DomainController -ErrorAction Stop
                                $resolvedIdentity = $userObject.SamAccountName
                                Write-Host "    ✅ Identity '$identityReference' exists (User)" -ForegroundColor Green
                            } catch {
                                # Identity not found
                                Write-Host "    ❌ Identity '$identityReference' not found" -ForegroundColor Red
                                
                                $findings += [PSCustomObject]@{
                                    Type = 'Drift'
                                    ResourceType = 'ACL'
                                    Identifier = "$identityReference → $($acl.targetOUPath)"
                                    Property = 'Identity'
                                    ExpectedValue = $identityReference
                                    ActualValue = 'Not Found'
                                    Details = "Identity '$identityReference' for ACL delegation does not exist in Active Directory"
                                }
                                $missingCount++
                                continue
                            }
                        }
                    } catch {
                        Write-Host "    ⚠️ Identity check failed: $($_.Exception.Message)" -ForegroundColor Yellow
                        continue
                    }
                    
                    # Step 3: Get current ACL on the OU
                    $currentAcl = $null
                    try {
                        $currentAcl = Get-Acl -Path "AD:\$targetOUPath" -ErrorAction Stop
                        Write-Host "    ✅ OU ACL readable" -ForegroundColor Green
                    } catch {
                        Write-Host "    ❌ Cannot read OU ACL" -ForegroundColor Red
                        
                        $findings += [PSCustomObject]@{
                            Type = 'Error'
                            ResourceType = 'ACL'
                            Identifier = "$identityReference → $($acl.targetOUPath)"
                            Property = 'ACLAccess'
                            ExpectedValue = 'Readable'
                            ActualValue = 'Access Denied'
                            Details = "Cannot read ACL for OU '$targetOUPath': $($_.Exception.Message)"
                        }
                        $errorCount++
                        continue
                    }
                    
                    # Step 4: Parse expected values from configuration
                    $expectedAccessControlType = [System.Security.AccessControl.AccessControlType]::$($acl.accesscontroltype)
                    $expectedInheritance = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$($acl.activeDirectorysecurityinheritance)
                    
                    # Step 4a: Resolve objecttype (convert friendly names to GUIDs if needed)
                    $resolvedObjectType = $acl.objecttype
                    if (-not [string]::IsNullOrEmpty($acl.objecttype)) {
                        try {
                            # Try to resolve using GUID mappings if it's not already a valid GUID
                            if (-not [System.Guid]::TryParse($acl.objecttype, [ref][System.Guid]::Empty)) {
                                $resolvedObjectType = Resolve-TierModelGuid -Value $acl.objecttype -Mappings $Config.guidMappings -DomainController $DomainController
                                if ($null -ne $resolvedObjectType) {
                                    if (-not [string]::IsNullOrEmpty($resolvedObjectType)) {
                                        Write-Verbose "Resolved objecttype '$($acl.objecttype)' to GUID: $resolvedObjectType"
                                    } else {
                                        Write-Verbose "Resolved objecttype '$($acl.objecttype)' to empty GUID (all object types)"
                                    }
                                } else {
                                    Write-Warning "Could not resolve objecttype '$($acl.objecttype)' to GUID. Using original value."
                                    $resolvedObjectType = $acl.objecttype
                                }
                            }
                        } catch {
                            Write-Warning "Error resolving objecttype '$($acl.objecttype)': $($_.Exception.Message). Using original value."
                            $resolvedObjectType = $acl.objecttype
                        }
                    }
                    
                    $expectedObjectType = if ([string]::IsNullOrEmpty($resolvedObjectType)) { [Guid]::Empty } else { [Guid]$resolvedObjectType }
                    
                    # Parse expected rights
                    $expectedRights = 0 -as [System.DirectoryServices.ActiveDirectoryRights]
                    if ($acl.activedirectoryrights -and $acl.activedirectoryrights.Count -gt 0) {
                        foreach ($rightString in $acl.activedirectoryrights) {
                            if (-not [string]::IsNullOrEmpty($rightString)) {
                                try {
                                    $rightEnum = [System.DirectoryServices.ActiveDirectoryRights]::($rightString)
                                    $expectedRights = $expectedRights -bor $rightEnum
                                } catch {
                                    if (-not $Silent) {
                                        Write-Host "    ⚠️ Invalid right: $rightString" -ForegroundColor Yellow
                                    }
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
                    
                    # Step 5: Find matching ACE in current ACL
                    $matchingAces = $currentAcl.Access | Where-Object {
                        # Check identity reference (handle domain prefix variations)
                        $_.IdentityReference.Value -like "*\$identityReference" -or 
                        $_.IdentityReference.Value -eq $identityReference -or
                        $_.IdentityReference.Value -like "*$resolvedIdentity"
                    }
                    
                    if (-not $matchingAces) {
                        if (-not $Silent) {
                            Write-Host "    ❌ No ACE found for identity '$identityReference'" -ForegroundColor Red
                        }
                        
                        $findings += [PSCustomObject]@{
                            Type = 'Drift'
                            ResourceType = 'ACL'
                            Identifier = "$identityReference → $($acl.targetOUPath)"
                            Property = 'ACE'
                            ExpectedValue = "ACE for '$identityReference'"
                            ActualValue = 'Missing'
                            Details = "No Access Control Entry found for '$identityReference' on '$targetOUPath'"
                        }
                        $missingCount++
                        continue
                    }
                    
                    # Step 6: Find the specific ACE that matches all expected properties
                    $compliantAce = $null
                    $aceDetails = @()
                    
                    # Look for an ACE that matches ALL expected properties
                    foreach ($ace in $matchingAces) {
                        $accessControlMatches = ($ace.AccessControlType -eq $expectedAccessControlType)
                        $inheritanceMatches = ($ace.InheritanceType -eq $expectedInheritance)
                        $objectTypeMatches = ($ace.ObjectType -eq $expectedObjectType)
                        $rightsMatch = ($ace.ActiveDirectoryRights -band $expectedRights) -eq $expectedRights
                        
                        # Check inherited object type GUID if present
                        $inheritedObjectTypeMatches = if ($inheritedObjectTypeGuid -ne [Guid]::Empty) {
                            $ace.InheritedObjectType -eq $inheritedObjectTypeGuid
                        } else {
                            $ace.InheritedObjectType -eq [Guid]::Empty -or $null -eq $ace.InheritedObjectType
                        }
                        
                        if ($accessControlMatches -and $inheritanceMatches -and $objectTypeMatches -and $rightsMatch -and $inheritedObjectTypeMatches) {
                            $compliantAce = $ace
                            break
                        }
                    }
                    
                    if ($compliantAce) {
                        # Found exact match - report success for each property
                        if (-not $Silent) {
                            Write-Host "    ✅ Access Control Type: $($compliantAce.AccessControlType)" -ForegroundColor Green
                            Write-Host "    ✅ Inheritance: $($compliantAce.InheritanceType)" -ForegroundColor Green
                            Write-Host "    ✅ Object Type: $($compliantAce.ObjectType)" -ForegroundColor Green
                            Write-Host "    ✅ Rights: $($compliantAce.ActiveDirectoryRights) (includes required $expectedRights)" -ForegroundColor Green
                        }
                        $aceCompliant = $true
                    } else {
                        # No exact match found - report what we expected vs what we found
                        if (-not $Silent) {
                            Write-Host "    ❌ No ACE found with exact match for all properties" -ForegroundColor Red
                            Write-Host "      Expected: AccessType=$expectedAccessControlType, Rights=$expectedRights, Inheritance=$expectedInheritance, ObjectType=$expectedObjectType" -ForegroundColor Yellow
                            Write-Host "      Available ACEs for this identity:" -ForegroundColor Yellow
                            foreach ($ace in $matchingAces) {
                                Write-Host "        - AccessType=$($ace.AccessControlType), Rights=$($ace.ActiveDirectoryRights), Inheritance=$($ace.InheritanceType), ObjectType=$($ace.ObjectType)" -ForegroundColor Gray
                            }
                        }
                        $aceCompliant = $false
                        $aceDetails += "No ACE found matching all required properties"
                    }
                    
                    # Report final result for this ACL delegation
                    if ($aceCompliant) {
                        Write-Host "    ✅ ACL Delegation COMPLIANT" -ForegroundColor Green
                        $compliantCount++
                    } else {
                        Write-Host "    ❌ ACL Delegation DRIFT DETECTED" -ForegroundColor Red
                        
                        $findings += [PSCustomObject]@{
                            Type = 'Drift'
                            ResourceType = 'ACL'
                            Identifier = "$identityReference → $($acl.targetOUPath)"
                            Property = 'ACEProperties'
                            ExpectedValue = "AccessType: $expectedAccessControlType, Rights: $expectedRights, Inheritance: $expectedInheritance, ObjectType: $expectedObjectType"
                            ActualValue = $aceDetails -join '; '
                            Details = "ACL delegation properties don't match configuration: $($aceDetails -join '; ')"
                        }
                        $mismatchCount++
                    }
                    
                } catch {
                    Write-TierModelLog -Level Error -Message "ACL audit failed for delegation" -Data @{
                        IdentityReference = $acl.identityreference
                        TargetOUPath = $targetOUPath
                        OriginalPath = $acl.targetOUPath
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    if (-not $Silent) {
                        Write-Host "    ❌ Audit error: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    
                    $findings += [PSCustomObject]@{
                        Type = 'Error'
                        ResourceType = 'ACL'
                        Identifier = "$($acl.identityreference) → $($acl.targetOUPath)"
                        Property = 'Audit'
                        ExpectedValue = 'Successful audit'
                        ActualValue = 'Failed'
                        Details = "Failed to audit ACL delegation: $($_.Exception.Message)"
                    }
                    $errorCount++
                }
            }
        }
        
        # Calculate compliance percentage
        $compliancePercentage = if ($totalAcls -gt 0) {
            [math]::Round(($compliantCount / $totalAcls) * 100, 2)
        } else {
            100
        }
        
        # Display audit summary
        if (-not $Silent) {
            Write-Host "`n=== OU ACL Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total OU ACL Delegations Checked: $totalAcls" -ForegroundColor White
            if ($missingCount -eq 0) {
                Write-Host "Missing OU ACL Delegations: 0 ✅" -ForegroundColor Green
            } else {
                Write-Host "Missing OU ACL Delegations: $missingCount ❌" -ForegroundColor Red
            }
            if ($mismatchCount -eq 0) {
                Write-Host "Configuration Mismatches: 0 ✅" -ForegroundColor Green
            } else {
                Write-Host "Configuration Mismatches: $mismatchCount ❌" -ForegroundColor Red
            }
            if ($missingCount -eq 0 -and $mismatchCount -eq 0 -and $errorCount -eq 0) {
                Write-Host "Overall Status: All OU ACL Delegations are compliant ✅" -ForegroundColor Green
            } else {
                Write-Host "Overall Status: $($missingCount + $mismatchCount + $errorCount) issues found ❌" -ForegroundColor Red
            }
        }
        
        # Summary output
        if (-not $Silent) {
            Write-Host "" # Blank line for spacing
            Write-Host "OU ACL Audit Summary:" -ForegroundColor White
            Write-Host "  Total Checked: $totalAcls" -ForegroundColor Gray
            Write-Host "  Missing: $missingCount" -ForegroundColor Red
            Write-Host "  Mismatched: $mismatchCount" -ForegroundColor Yellow
            Write-Host "  Total Drift: $($missingCount + $mismatchCount)" -ForegroundColor $(if (($missingCount + $mismatchCount) -eq 0) { 'Green' } else { 'Red' })
            Write-Host "  Compliance: $compliancePercentage%" -ForegroundColor $(if ($compliancePercentage -ge 90) { 'Green' } elseif ($compliancePercentage -ge 70) { 'Yellow' } else { 'Red' })
            Write-Host "" # Blank line for spacing
            
            # Show drift findings if any
            if ($findings.Count -gt 0) {
                Write-Host "Audit Findings:" -ForegroundColor Yellow
                $findings | ForEach-Object {
                    $color = switch ($_.Type) {
                        'Error' { 'Red' }
                        'Drift' { 'Yellow' }
                        'Warning' { 'Gray' }
                        default { 'White' }
                    }
                    Write-Host "  [$($_.Type)] $($_.Identifier) - $($_.Property): $($_.Details)" -ForegroundColor $color
                }
            } else {
                Write-Host "  ✅ All OU ACL delegations match configuration expectations." -ForegroundColor Green
            }
            Write-Host "" # Blank line before script completion message
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "OuAclAuditComplete" -Data @{
            TotalAcls = $totalAcls
            Compliant = $compliantCount
            Missing = $missingCount
            Mismatched = $mismatchCount
            Errors = $errorCount
            CompliancePercentage = $compliancePercentage
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Summary = @{
                TotalAcls = $totalAcls
                Compliant = $compliantCount
                Missing = $missingCount
                Mismatched = $mismatchCount
                Errors = $errorCount
                CompliancePercentage = $compliancePercentage
            }
            Findings = $findings
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "OU ACL audit failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            Summary = @{
                TotalAcls = 0
                Compliant = 0
                Missing = 0
                Mismatched = 0
                Errors = 1
                CompliancePercentage = 0
            }
            Findings = @([PSCustomObject]@{
                Type = 'Error'
                ResourceType = 'ACL'
                Identifier = 'OU ACL Audit'
                Property = 'Execution'
                ExpectedValue = 'Audit should complete successfully'
                ActualValue = 'Audit failed'
                Details = $_.Exception.Message
            })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}