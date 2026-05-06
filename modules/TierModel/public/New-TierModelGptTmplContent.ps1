function New-TierModelGptTmplContent {
    <#
    .SYNOPSIS
    Generate GptTmpl.inf content for GPO security templates.
    
    .DESCRIPTION
    Creates formatted GptTmpl.inf content from GPO configuration data,
    including User Rights Assignments and Restricted Groups with proper
    SID resolution and formatting. Uses the exact working logic from Deploy-TierModel.ps1.
    
    .PARAMETER GPOData
    GPO configuration data containing userRightsAssignments and restrictedGroups.
    
    .PARAMETER CorrelationId
    Optional correlation ID for logging and tracking.
    
    .PARAMETER StrictMode
    If specified, throws errors instead of warnings when SID resolution fails.
    
    .EXAMPLE
    $content = New-TierModelGptTmplContent -GPOData $gpoConfig
    
    .EXAMPLE
    $content = New-TierModelGptTmplContent -GPOData $gpoConfig -StrictMode
    
    .OUTPUTS
    String containing formatted GptTmpl.inf content ready for file output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$GPOData,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),
        
        [switch]$StrictMode
    )
    
    Write-TierModelLog -Level Info -Message "Generating GptTmpl.inf content" -Data @{
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        # Start with template header (exact format from working code)
        $gptTmplContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
"@
        
        # Process User Rights Assignments (exact logic from Deploy-TierModel.ps1)
        if ($GPOData.PSObject.Properties['userRightsAssignments'] -and $GPOData.userRightsAssignments) {
            
            foreach ($ura in $GPOData.userRightsAssignments) {
                $allPrincipals = @()
                $rightsToProcess = @()
                
                # Handle two different URA formats:
                # Format 1: "rights" (array) + "principalGroups" 
                # Format 2: "right" (single) + "principals"
                
                if ($ura.PSObject.Properties['rights'] -and $ura.rights) {
                    # Original format
                    $rightsToProcess = $ura.rights
                    $principalsObj = $ura.principalGroups
                    
                    # Add always include groups
                    if ($principalsObj.PSObject.Properties['alwaysInclude'] -and $principalsObj.alwaysInclude) {
                        $allPrincipals += $principalsObj.alwaysInclude
                    }
                    
                    # Add forest root only groups
                    if ($principalsObj.PSObject.Properties['forestRootOnly'] -and $principalsObj.forestRootOnly) {
                        $allPrincipals += $principalsObj.forestRootOnly
                    }
                    
                    # Add conditional groups (evaluated against AD — groups not found are skipped)
                    if ($principalsObj.PSObject.Properties['conditionalGroups'] -and $principalsObj.conditionalGroups) {
                        foreach ($conditionalGroup in $principalsObj.conditionalGroups) {
                            if ($conditionalGroup.PSObject.Properties['names'] -and $conditionalGroup.names) {
                                $resolvedNames = @(Get-TierModelConditionalGroupNames -ConditionalGroup $conditionalGroup -DomainController $DomainController -CorrelationId $CorrelationId)
                                if ($resolvedNames.Count -gt 0) { $allPrincipals += $resolvedNames }
                            }
                        }
                    }
                    
                    # Add literal strings
                    if ($principalsObj.PSObject.Properties['literalStrings'] -and $principalsObj.literalStrings) {
                        $allPrincipals += $principalsObj.literalStrings
                    }
                    
                } elseif ($ura.PSObject.Properties['right'] -and $ura.right) {
                    # New format
                    $rightsToProcess = @($ura.right)
                    $principalsObj = $ura.principals
                    
                    # Add resolvable groups
                    if ($principalsObj.PSObject.Properties['resolvableGroups'] -and $principalsObj.resolvableGroups) {
                        $allPrincipals += $principalsObj.resolvableGroups
                    }
                    
                    # Add forest root only groups
                    if ($principalsObj.PSObject.Properties['forestRootOnly'] -and $principalsObj.forestRootOnly) {
                        $allPrincipals += $principalsObj.forestRootOnly
                    }
                    
                    # Add conditional groups (evaluated against AD — groups not found are skipped)
                    if ($principalsObj.PSObject.Properties['conditionalGroups'] -and $principalsObj.conditionalGroups) {
                        foreach ($conditionalGroup in $principalsObj.conditionalGroups) {
                            if ($conditionalGroup.PSObject.Properties['names'] -and $conditionalGroup.names) {
                                $resolvedNames = @(Get-TierModelConditionalGroupNames -ConditionalGroup $conditionalGroup -DomainController $DomainController -CorrelationId $CorrelationId)
                                if ($resolvedNames.Count -gt 0) { $allPrincipals += $resolvedNames }
                            }
                        }
                    }
                    
                    # Add literal strings
                    if ($principalsObj.PSObject.Properties['literalStrings'] -and $principalsObj.literalStrings) {
                        $allPrincipals += $principalsObj.literalStrings
                    }
                }
                
                if ($rightsToProcess.Count -eq 0) {
                    continue
                }
                
                # Separate resolvable groups from literal strings (exact working logic)
                $resolvableGroups = @()
                $literalStrings = @()
                
                # Collect resolvable groups and literal strings separately
                if ($ura.PSObject.Properties['rights'] -and $ura.rights) {
                    # Original format
                    if ($ura.principalGroups.PSObject.Properties['alwaysInclude'] -and $ura.principalGroups.alwaysInclude) {
                        $resolvableGroups += $ura.principalGroups.alwaysInclude
                    }
                    if ($ura.principalGroups.PSObject.Properties['forestRootOnly'] -and $ura.principalGroups.forestRootOnly) {
                        $resolvableGroups += $ura.principalGroups.forestRootOnly
                    }
                    if ($ura.principalGroups.PSObject.Properties['conditionalGroups'] -and $ura.principalGroups.conditionalGroups) {
                        foreach ($conditionalGroup in $ura.principalGroups.conditionalGroups) {
                            if ($conditionalGroup.PSObject.Properties['names'] -and $conditionalGroup.names) {
                                $resolvedNames = @(Get-TierModelConditionalGroupNames -ConditionalGroup $conditionalGroup -DomainController $DomainController -CorrelationId $CorrelationId)
                                if ($resolvedNames.Count -gt 0) { $resolvableGroups += $resolvedNames }
                            }
                        }
                    }
                    if ($ura.principalGroups.PSObject.Properties['literalStrings'] -and $ura.principalGroups.literalStrings) {
                        $literalStrings += $ura.principalGroups.literalStrings
                    }
                } elseif ($ura.PSObject.Properties['right'] -and $ura.right) {
                    # New format
                    if ($ura.principals.PSObject.Properties['resolvableGroups'] -and $ura.principals.resolvableGroups) {
                        $resolvableGroups += $ura.principals.resolvableGroups
                    }
                    if ($ura.principals.PSObject.Properties['forestRootOnly'] -and $ura.principals.forestRootOnly) {
                        $resolvableGroups += $ura.principals.forestRootOnly
                    }
                    if ($ura.principals.PSObject.Properties['conditionalGroups'] -and $ura.principals.conditionalGroups) {
                        foreach ($conditionalGroup in $ura.principals.conditionalGroups) {
                            if ($conditionalGroup.PSObject.Properties['names'] -and $conditionalGroup.names) {
                                $resolvedNames = @(Get-TierModelConditionalGroupNames -ConditionalGroup $conditionalGroup -DomainController $DomainController -CorrelationId $CorrelationId)
                                if ($resolvedNames.Count -gt 0) { $resolvableGroups += $resolvedNames }
                            }
                        }
                    }
                    if ($ura.principals.PSObject.Properties['literalStrings'] -and $ura.principals.literalStrings) {
                        $literalStrings += $ura.principals.literalStrings
                    }
                }
                
                # Convert resolvable groups to SIDs using proper TierModel SID resolution
                $principalSids = @()
                foreach ($principal in $resolvableGroups) {
                    try {
                        # Use TierModel SID resolution that handles Administrator account properly
                        $sidResult = Resolve-TierModelPrincipalSid -Principal $principal -DomainController $DomainController -CorrelationId $CorrelationId
                        if ($sidResult.Success) {
                            $principalSids += "*$($sidResult.Sid)"
                        } else {
                            throw "SID resolution failed: $($sidResult.Error)"
                        }
                    } catch {
                        # If SID resolution fails, skip this principal with a warning
                        if ($StrictMode) {
                            throw "Could not resolve SID for principal: $principal. $($_.Exception.Message)"
                        } else {
                            Write-Host "    WARNING: Could not resolve SID for principal: $principal. Skipping in URA." -ForegroundColor Yellow
                        }
                    }
                }
                
                # Add literal strings directly (no SID resolution needed)
                $principalSids += $literalStrings
                
                # Generate URA entries for each right
                foreach ($right in $rightsToProcess) {
                    $sidList = $principalSids -join ","
                    $gptTmplContent += "`n$right = $sidList"
                }
            }
        }
        
        # Process Restricted Groups if present (exact working logic)
        $gptTmplContent += "`n[Group Membership]"
        if ($GPOData.PSObject.Properties['restrictedGroups'] -and $GPOData.restrictedGroups) {
            # Process emptyGroups
            if ($GPOData.restrictedGroups.PSObject.Properties['emptyGroups'] -and $GPOData.restrictedGroups.emptyGroups) {
                foreach ($emptyGroup in $GPOData.restrictedGroups.emptyGroups) {
                    $gptTmplContent += "`n$emptyGroup="
                }
            }
            
            # Process membershipGroups
            if ($GPOData.restrictedGroups.PSObject.Properties['membershipGroups'] -and $GPOData.restrictedGroups.membershipGroups) {
                foreach ($membershipGroup in $GPOData.restrictedGroups.membershipGroups) {
                    if ($membershipGroup.PSObject.Properties['groupSidOrName'] -and $membershipGroup.PSObject.Properties['memberGroups']) {
                        $groupName = $membershipGroup.groupSidOrName
                        
                        # Resolve member group names to SIDs using proper TierModel SID resolution
                        $memberSids = @()
                        foreach ($member in $membershipGroup.memberGroups) {
                            try {
                                # Use TierModel SID resolution that handles Administrator account properly
                                $sidResult = Resolve-TierModelPrincipalSid -Principal $member -DomainController $DomainController -CorrelationId $CorrelationId
                                if ($sidResult.Success) {
                                    $memberSids += "*$($sidResult.Sid)"
                                } else {
                                    throw "SID resolution failed: $($sidResult.Error)"
                                }
                            } catch {
                                # If SID resolution fails, skip this member with a warning
                                if ($StrictMode) {
                                    throw "Could not resolve SID for RG member: $member in group $groupName. $($_.Exception.Message)"
                                } else {
                                    Write-Host "    WARNING: Could not resolve SID for RG member: $member. Skipping in group $groupName." -ForegroundColor Yellow
                                }
                            }
                        }
                        
                        $members = $memberSids -join ","
                        $gptTmplContent += "`n$groupName=$members"
                    }
                }
            }
        }
        
        Write-TierModelLog -Level Info -Message "GptTmpl.inf content generated successfully" -Data @{
            CorrelationId = $CorrelationId
            ContentLength = $gptTmplContent.Length
        } | Out-Null
        
        return $gptTmplContent
        
    } catch {
        Write-TierModelLog -Level Error -Message "Failed to generate GptTmpl.inf content" -Data @{
            CorrelationId = $CorrelationId
            Exception = $_.Exception.Message
        } | Out-Null
        
        throw "Failed to generate GptTmpl.inf content: $($_.Exception.Message)"
    }
}