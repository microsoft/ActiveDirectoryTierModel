function Get-TierModelWinLapsAclFd {
    <#
    .SYNOPSIS
    Analyze Windows LAPS DACL delegation requirements for full deployment mode.

    .DESCRIPTION
    Examines Windows LAPS delegation configuration and current Active Directory state
    to generate a deployment plan for full deployment scenarios. Uses lighter validation
    than Get-TierModelWinLapsAcl — assumes OUs and groups will exist from earlier
    deployment phases. Schema, module, DFL, and DC-exclusion checks still mandatory.
    Resolves group names to NetBIOS\sAMAccountName format for -AllowedPrincipals.
    Uses only Windows LAPS (ms-LAPS-*) — never legacy (ms-Mcs-AdmPwd*, AdmPwd.PS).

    .PARAMETER Config
    TierModel configuration object containing winLapsDelegations definitions.

    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.

    .PARAMETER IncludeDetails
    Include detailed analysis in the planning output for troubleshooting.

    .PARAMETER Silent
    Suppress host output for consolidated reporting.

    .OUTPUTS
    PSCustomObject with deployment plan including Actions, Summary, Errors, and analysis.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelWinLapsAclFd -Config $config -DomainController 'DC01' -Silent

    .EXAMPLE
    $plan = Get-TierModelWinLapsAclFd -Config $config -DomainController 'DC01' -IncludeDetails
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

    Write-TierModelLog -Level Info -Message "WinLapsAclFdPlanningStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    try {
        $actions = @()
        $planErrors = @()
        $warnings = @()
        $existingCount = 0
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController

        if (-not ($Config.PSObject.Properties.Name -contains 'winLapsDelegations') -or
            -not $Config.winLapsDelegations -or
            $Config.winLapsDelegations.Count -eq 0) {

            Write-TierModelLog -Level Warning -Message "No Windows LAPS delegations found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null

            return [PSCustomObject]@{
                Actions    = @()
                Summary    = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                Analysis   = @{ ConfiguredDelegations = 0; ExistingPermissions = 0; ValidationErrors = 0 }
                Errors     = @()
                Warnings   = @()
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }

        $delegations = @($Config.winLapsDelegations)

        Write-TierModelLog -Level Info -Message "Analyzing Windows LAPS delegations (Full Deployment)" -Data @{
            TotalDelegationsInConfig = $delegations.Count
            CorrelationId = $CorrelationId
        } | Out-Null

        # Defensive checks: schema, module, DFL
        $netBIOSDomain = $null
        try {
            $rootDSE = Get-ADRootDSE -Server $DomainController -ErrorAction Stop
            $schemaDN = $rootDSE.schemaNamingContext
            $lapsAttr = Get-ADObject -Filter "lDAPDisplayName -eq 'msLAPS-Password'" -SearchBase $schemaDN -Server $DomainController -ErrorAction SilentlyContinue
            if (-not $lapsAttr) {
                $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_SCHEMA_MISSING'; Message = 'Windows LAPS schema attributes not found.'; Context = @{} }
            }
        } catch {
            $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_SCHEMA_MISSING'; Message = "Schema query failed: $($_.Exception.Message)"; Context = @{} }
        }

        try {
            Import-Module LAPS -ErrorAction Stop -Verbose:$false
        } catch {
            $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_MODULE_MISSING'; Message = "LAPS module not available: $($_.Exception.Message)"; Context = @{} }
        }

        try {
            $adDomain = Get-ADDomain -Server $DomainController -ErrorAction Stop
            $dfl = $adDomain.DomainMode
            $netBIOSDomain = $adDomain.NetBIOSName
            $validDfl = @('Windows2016Domain', 'Windows2025Domain')
            if ($dfl -notin $validDfl) {
                $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_DFL_INSUFFICIENT'; Message = "DFL '$dfl' below Windows2016Domain."; Context = @{} }
            }
        } catch {
            $warnings += "Could not verify DFL: $($_.Exception.Message)"
        }

        if ($planErrors.Count -gt 0) {
            return [PSCustomObject]@{
                Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                Analysis = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = $planErrors.Count }
                Errors = $planErrors; Warnings = $warnings
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
            }
        }

        # Resolve NetBIOS domain name if not yet available
        if (-not $netBIOSDomain) {
            try {
                $adDomain = Get-ADDomain -Server $DomainController -ErrorAction Stop
                $netBIOSDomain = $adDomain.NetBIOSName
            } catch {
                $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'DOMAIN_RESOLUTION_FAILED'; Message = "Cannot resolve NetBIOS domain: $($_.Exception.Message)"; Context = @{} }
                return [PSCustomObject]@{
                    Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                    Analysis = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = 1 }
                    Errors = $planErrors; Warnings = $warnings
                    DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
                }
            }
        }

        # Resolve all group names to NetBIOS\sAMAccountName
        $groupResolution = @{}
        $allGroupNames = @()
        foreach ($delegation in $delegations) {
            $allGroupNames += @($delegation.readGroup)
            $allGroupNames += @($delegation.resetGroup)
        }
        $uniqueGroups = @($allGroupNames | Select-Object -Unique)
        foreach ($group in $uniqueGroups) {
            try {
                $escapedName = $group -replace "'", "''"
                $adGroup = Get-ADGroup -Filter "Name -eq '$escapedName'" -Server $DomainController -Properties sAMAccountName -ErrorAction Stop
                if ($adGroup) {
                    $groupResolution[$group] = "$netBIOSDomain\$($adGroup.sAMAccountName)"
                }
            } catch {
                # In FD mode, groups may not exist yet (created by earlier phases); use best-effort
                $groupResolution[$group] = "$netBIOSDomain\$($group -replace ' ','')"
                $warnings += "Group '$group' not found — using estimated sAMAccountName for plan."
            }
        }

        # Resolve ms-LAPS attribute schemaIDGUIDs for precise SELF idempotency detection
        $lapsSchemaGUIDs = @()
        try {
            $lapsAttrNames = @('msLAPS-Password', 'msLAPS-EncryptedPassword', 'msLAPS-EncryptedPasswordHistory', 'msLAPS-PasswordExpirationTime', 'msLAPS-EncryptedDSRMPassword', 'msLAPS-EncryptedDSRMPasswordHistory')
            foreach ($attrName in $lapsAttrNames) {
                $attrObj = Get-ADObject -Filter "lDAPDisplayName -eq '$attrName'" -SearchBase $schemaDN -Server $DomainController -Properties schemaIDGUID -ErrorAction SilentlyContinue
                if ($attrObj -and $attrObj.schemaIDGUID) {
                    $lapsSchemaGUIDs += [Guid]::new($attrObj.schemaIDGUID)
                }
            }
        } catch { }

        # For each delegation, check existing state and plan actions
        foreach ($delegation in $delegations) {
            $resolvedOuDn = Resolve-TierModelPlaceholder -Path $delegation.ouDn -DomainDN $domainDN
            $ouName = if ($resolvedOuDn -match '^OU=([^,]+)') { $matches[1] } else { $resolvedOuDn }

            # Normalize readGroup/resetGroup to arrays and resolve
            $readGroupNames = @($delegation.readGroup)
            $resetGroupNames = @($delegation.resetGroup)
            $resolvedReadPrincipals = @($readGroupNames | ForEach-Object { $groupResolution[$_] } | Where-Object { $_ })
            $resolvedResetPrincipals = @($resetGroupNames | ForEach-Object { $groupResolution[$_] } | Where-Object { $_ })

            # Light validation: check if OU exists (non-blocking in FD mode)
            $ouExists = $false
            try {
                Get-ADOrganizationalUnit -Identity $resolvedOuDn -Server $DomainController -ErrorAction Stop | Out-Null
                $ouExists = $true
            } catch { }

            # DC exclusion check (still mandatory)
            $isDcOu = if ($delegation.PSObject.Properties['isDomainControllerOu']) { $delegation.isDomainControllerOu } else { $false }
            if (-not $isDcOu -and $ouExists) {
                try {
                    $dcObjects = Get-ADComputer -Filter { PrimaryGroupID -eq 516 } -SearchBase $resolvedOuDn -Server $DomainController -ErrorAction SilentlyContinue
                    if ($dcObjects) {
                        $planErrors += @{
                            Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_DC_SCOPE_REJECTED'
                            Message = "OU '$resolvedOuDn' contains DC objects. Set isDomainControllerOu=true to opt in."
                            Context = @{ TargetOUPath = $resolvedOuDn }
                        }
                        continue
                    }
                } catch { }
            }

            # Detect existing permissions
            $selfExists = $false
            $readExists = $false
            $resetExists = $false

            if ($ouExists) {
                # Detect SELF via non-inherited ACEs with ms-LAPS ObjectType GUIDs
                # (inherited SELF ACEs exist by default on all OUs — must exclude them)
                try {
                    # Use Get-Acl on the AD: provider for reliable IsInherited values
                    # (Get-ADOrganizationalUnit -Properties nTSecurityDescriptor can misreport IsInherited=True in PS7)
                    # Note: if strict multi-DC targeting is needed, use [ADSI]"LDAP://$DomainController/$dn" + .ObjectSecurity
                    $ouAcl = Get-Acl -Path "AD:$resolvedOuDn" -ErrorAction Stop
                    $selfAces = @($ouAcl.Access | Where-Object {
                        $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF' -and
                        -not $_.IsInherited -and
                        ($lapsSchemaGUIDs.Count -eq 0 -or $_.ObjectType -in $lapsSchemaGUIDs)
                    })
                    if ($selfAces.Count -ge 1) { $selfExists = $true }
                } catch { }

                # Detect Read/Reset via Find-LapsADExtendedRights
                try {
                    $extendedRights = Find-LapsADExtendedRights -Identity $resolvedOuDn -ErrorAction SilentlyContinue
                    if ($extendedRights) {
                        foreach ($right in @($extendedRights)) {
                            if ($right.PSObject.Properties['ExtendedRightHolders']) {
                                $holders = @($right.ExtendedRightHolders)
                                # Check all read principals present
                                $allReadPresent = $true
                                foreach ($principal in $resolvedReadPrincipals) {
                                    $found = $false
                                    foreach ($holder in $holders) {
                                        if ($holder -eq $principal -or $holder -like "*\$($principal.Split('\')[-1])") {
                                            $found = $true; break
                                        }
                                    }
                                    if (-not $found) { $allReadPresent = $false; break }
                                }
                                if ($allReadPresent -and $resolvedReadPrincipals.Count -gt 0) { $readExists = $true }

                                # Check all reset principals present
                                $allResetPresent = $true
                                foreach ($principal in $resolvedResetPrincipals) {
                                    $found = $false
                                    foreach ($holder in $holders) {
                                        if ($holder -eq $principal -or $holder -like "*\$($principal.Split('\')[-1])") {
                                            $found = $true; break
                                        }
                                    }
                                    if (-not $found) { $allResetPresent = $false; break }
                                }
                                if ($allResetPresent -and $resolvedResetPrincipals.Count -gt 0) { $resetExists = $true }
                            }
                        }
                    }
                } catch { }
            }

            # Plan Self permission
            if ($delegation.computerSelfPermission -and -not $selfExists) {
                $actions += [PSCustomObject]@{
                    Action       = 'CreateAcl'
                    ResourceType = 'LapsPermission'
                    Name         = "LAPS Self-Permission: $ouName"
                    Path         = $resolvedOuDn
                    Data         = [PSCustomObject]@{
                        lapsOperation          = 'SetComputerSelfPermission'
                        ouDn                   = $resolvedOuDn
                        computerSelfPermission = $true
                    }
                    Dependencies = @()
                    RiskLevel    = 'Low'
                    Validation   = @{ TargetOUExists = $ouExists; PrincipalResolvable = $true }
                }
            } elseif ($delegation.computerSelfPermission -and $selfExists) {
                $existingCount++
                if (-not $Silent) {
                    Write-Host "  `u{2705} LAPS Self-Permission Exists: $ouName" -ForegroundColor Green
                }
            }

            # Plan Read permission (single call with all principals as array)
            if (-not $readExists) {
                $actions += [PSCustomObject]@{
                    Action       = 'CreateAcl'
                    ResourceType = 'LapsPermission'
                    Name         = "LAPS Read-Permission: $($readGroupNames -join ', ') on $ouName"
                    Path         = $resolvedOuDn
                    Data         = [PSCustomObject]@{
                        lapsOperation     = 'SetReadPasswordPermission'
                        ouDn              = $resolvedOuDn
                        allowedPrincipals = $resolvedReadPrincipals
                    }
                    Dependencies = @()
                    RiskLevel    = 'Low'
                    Validation   = @{ TargetOUExists = $ouExists; PrincipalResolvable = $true }
                }
            } else {
                $existingCount++
                if (-not $Silent) {
                    Write-Host "  `u{2705} LAPS Read-Permission Exists: $($readGroupNames -join ', ') -> $ouName" -ForegroundColor Green
                }
            }

            # Plan Reset permission (single call with all principals as array)
            if (-not $resetExists) {
                $actions += [PSCustomObject]@{
                    Action       = 'CreateAcl'
                    ResourceType = 'LapsPermission'
                    Name         = "LAPS Reset-Permission: $($resetGroupNames -join ', ') on $ouName"
                    Path         = $resolvedOuDn
                    Data         = [PSCustomObject]@{
                        lapsOperation     = 'SetResetPasswordPermission'
                        ouDn              = $resolvedOuDn
                        allowedPrincipals = $resolvedResetPrincipals
                    }
                    Dependencies = @()
                    RiskLevel    = 'Low'
                    Validation   = @{ TargetOUExists = $ouExists; PrincipalResolvable = $true }
                }
            } else {
                $existingCount++
                if (-not $Silent) {
                    Write-Host "  `u{2705} LAPS Reset-Permission Exists: $($resetGroupNames -join ', ') -> $ouName" -ForegroundColor Green
                }
            }
        }

        $createActions = @($actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        $lowRiskActions = @($actions | Where-Object { $_.RiskLevel -eq 'Low' }).Count
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        $result = [PSCustomObject]@{
            Actions    = $actions
            Summary    = @{
                TotalActions   = $actions.Count
                CreateActions  = $createActions
                ExistingCount  = $existingCount
                RiskAssessment = @{ LowRisk = $lowRiskActions; MediumRisk = 0; HighRisk = 0 }
            }
            Analysis   = @{
                ConfiguredDelegations = $delegations.Count
                ExistingPermissions   = $existingCount
                ValidationErrors      = $planErrors.Count
            }
            Errors     = $planErrors
            Warnings   = $warnings
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        }

        Write-TierModelLog -Level Info -Message "WinLapsAclFdPlanningComplete" -Data @{
            TotalActions  = $actions.Count
            CreateActions = $createActions
            ExistingCount = $existingCount
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null

        return $result
    } catch {
        Write-TierModelLog -Level Error -Message "Windows LAPS ACL Fd planning failed" -Data @{
            Exception     = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
            Analysis = @{ ConfiguredDelegations = 0; ExistingPermissions = 0; ValidationErrors = 1 }
            Errors = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'WinLapsAclFdPlanningFailed'; Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            Warnings = @()
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
        }
    }
}
