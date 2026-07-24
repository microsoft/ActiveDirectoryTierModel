function Get-TierModelWinLapsAcl {
    <#
    .SYNOPSIS
    Analyze Windows LAPS DACL delegation requirements and generate deployment plan.

    .DESCRIPTION
    Examines Windows LAPS delegation configuration and current Active Directory state
    to generate a deployment plan. Validates target OUs, read/reset groups, schema
    presence, LAPS module availability, and DFL level. For each configured delegation
    entry, produces 3 CreateAcl actions: Self-permission, Read-permission, Reset-permission.
    Resolves group names to NetBIOS\sAMAccountName format for -AllowedPrincipals.
    Uses only Windows LAPS (ms-LAPS-*) — never legacy (ms-Mcs-AdmPwd*, AdmPwd.PS).

    .PARAMETER Config
    TierModel configuration object containing winLapsDelegations definitions.

    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.

    .PARAMETER IncludeDetails
    Include detailed analysis in the planning output for troubleshooting.

    .OUTPUTS
    PSCustomObject with deployment plan including Actions, Summary, Warnings, Errors, and Converged.

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelWinLapsAcl -Config $config -DomainController 'DC01'

    .EXAMPLE
    $plan = Get-TierModelWinLapsAcl -Config $config -DomainController 'DC01' -IncludeDetails
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

    Write-TierModelLog -Level Info -Message "WinLapsAclPlanningStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    try {
        $actions = @()
        $planErrors = @()
        $warnings = @()

        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController

        # Check for winLapsDelegations in config
        if (-not ($Config.PSObject.Properties.Name -contains 'winLapsDelegations') -or
            -not $Config.winLapsDelegations -or
            $Config.winLapsDelegations.Count -eq 0) {

            Write-TierModelLog -Level Warning -Message "No Windows LAPS delegations found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null

            return [PSCustomObject]@{
                Actions    = $actions
                Summary    = @{
                    TotalActions  = 0
                    CreateActions = 0
                    ExistingCount = 0
                    RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 }
                }
                Analysis   = @{ ConfiguredDelegations = 0; ExistingPermissions = 0; ValidationErrors = 0 }
                Errors     = $planErrors
                Warnings   = $warnings
                Converged  = $true
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }

        $delegations = @($Config.winLapsDelegations)

        Write-TierModelLog -Level Info -Message "Analyzing Windows LAPS delegations" -Data @{
            TotalDelegationsInConfig = $delegations.Count
            CorrelationId = $CorrelationId
        } | Out-Null

        # Defensive Gate 1-3 re-checks (schema, module, DFL)
        # Gate 1: Schema check
        try {
            $rootDSE = Get-ADRootDSE -Server $DomainController -ErrorAction Stop
            $schemaDN = $rootDSE.schemaNamingContext
            $lapsAttr = Get-ADObject -Filter "lDAPDisplayName -eq 'msLAPS-Password'" -SearchBase $schemaDN -Server $DomainController -ErrorAction SilentlyContinue
            if (-not $lapsAttr) {
                $planErrors += @{
                    Timestamp = Get-Date
                    Category  = 'Validation'
                    Code      = 'WINLAPS_SCHEMA_MISSING'
                    Message   = 'The current Domain does not contain the Windows LAPS schema extensions, please follow Microsoft Doc guidance on how to extend the schema, then re-attempt the Tier Model Windows LAPS deployment.'
                    Context   = @{}
                }
                return [PSCustomObject]@{
                    Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                    Analysis = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = 1 }
                    Errors = $planErrors; Warnings = @(); Converged = $false
                    DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
                }
            }
        } catch {
            $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_SCHEMA_MISSING'; Message = "Could not verify the Windows LAPS schema extensions on the domain: $($_.Exception.Message). Confirm connectivity to the domain controller, then re-attempt the Tier Model Windows LAPS deployment."; Context = @{} }
            return [PSCustomObject]@{
                Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                Analysis = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = 1 }
                Errors = $planErrors; Warnings = @(); Converged = $false
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
            }
        }

        # Gate 2: LAPS module
        try {
            Import-Module LAPS -ErrorAction Stop -Verbose:$false
        } catch {
            $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_MODULE_MISSING'; Message = "LAPS PowerShell module not available: $($_.Exception.Message)"; Context = @{} }
            return [PSCustomObject]@{
                Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                Analysis = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = 1 }
                Errors = $planErrors; Warnings = @(); Converged = $false
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
            }
        }

        # Gate 3: DFL
        try {
            $adDomain = Get-ADDomain -Server $DomainController -ErrorAction Stop
            $dfl = $adDomain.DomainMode
            $netBIOSDomain = $adDomain.NetBIOSName
            $validDfl = @('Windows2016Domain', 'Windows2025Domain')
            if ($dfl -notin $validDfl) {
                $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'WINLAPS_DFL_INSUFFICIENT'; Message = "DFL '$dfl' is below Windows2016Domain. LAPS encryption requires DFL >= 2016."; Context = @{} }
                return [PSCustomObject]@{
                    Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                    Analysis = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = 1 }
                    Errors = $planErrors; Warnings = @(); Converged = $false
                    DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
                }
            }
        } catch {
            $warnings += "Could not verify DFL: $($_.Exception.Message)"
            $netBIOSDomain = $null
        }

        # Resolve NetBIOS domain name if not yet available
        if (-not $netBIOSDomain) {
            try {
                $adDomain = Get-ADDomain -Server $DomainController -ErrorAction Stop
                $netBIOSDomain = $adDomain.NetBIOSName
            } catch {
                $planErrors += @{ Timestamp = Get-Date; Category = 'Validation'; Code = 'DOMAIN_RESOLUTION_FAILED'; Message = "Cannot resolve NetBIOS domain name: $($_.Exception.Message)"; Context = @{} }
                return [PSCustomObject]@{
                    Actions = @(); Summary = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                    Analysis = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = 1 }
                    Errors = $planErrors; Warnings = @(); Converged = $false
                    DurationMs = ((Get-Date) - $startTime).TotalMilliseconds; CorrelationId = $CorrelationId
                }
            }
        }

        # Validate target OUs
        $uniqueOUs = $delegations | ForEach-Object {
            Resolve-TierModelPlaceholder -Path $_.ouDn -DomainDN $domainDN
        } | Select-Object -Unique

        foreach ($ouPath in $uniqueOUs) {
            try {
                Get-ADOrganizationalUnit -Identity $ouPath -Server $DomainController -ErrorAction Stop | Out-Null
            } catch {
                $ouName = $ouPath
                if ($ouPath -match '^OU=([^,]+)') { $ouName = $matches[1] }
                elseif ($ouPath -match '^CN=([^,]+)') { $ouName = $matches[1] }
                $planErrors += @{
                    Timestamp = Get-Date
                    Category  = 'Validation'
                    Code      = 'TargetOUNotFound'
                    Message   = "Target OU '$ouName' does not exist - create OUs first"
                    Context   = @{ TargetOUPath = $ouPath }
                }
            }
        }

        # Validate groups and resolve sAMAccountName for NetBIOS\sam format
        $groupResolution = @{} # friendly name → "NETBIOS\sAMAccountName"
        $allGroupNames = @()
        foreach ($delegation in $delegations) {
            $allGroupNames += @($delegation.readGroup)
            $allGroupNames += @($delegation.resetGroup)
            # Include decryptorGroup in resolution
            if ($delegation.PSObject.Properties['decryptorGroup'] -and $delegation.decryptorGroup) {
                $allGroupNames += @($delegation.decryptorGroup)
            }
        }
        $uniqueGroups = @($allGroupNames | Select-Object -Unique)

        foreach ($group in $uniqueGroups) {
            try {
                $adGroup = $null

                # Well-known groups (e.g. "Domain Admins") first via fixed SID/RID —
                # their display names are localized in non-English ADs
                $wellKnownSid = $null
                try {
                    $wellKnownSid = Get-WellKnownSid -Principal $group
                    if (-not $wellKnownSid) {
                        $wellKnownSid = Get-WellKnownDomainRidSid -Principal $group -DomainController $DomainController
                    }
                } catch { $wellKnownSid = $null }
                if ($wellKnownSid) {
                    try {
                        $adGroup = Get-ADGroup -Identity $wellKnownSid -Server $DomainController -Properties sAMAccountName -ErrorAction Stop
                    } catch { $adGroup = $null }
                }

                if (-not $adGroup) {
                    $escapedName = $group -replace "'", "''"
                    $adGroup = Get-ADGroup -Filter "Name -eq '$escapedName'" -Server $DomainController -Properties sAMAccountName -ErrorAction Stop
                }
                if ($adGroup) {
                    $groupResolution[$group] = "$netBIOSDomain\$($adGroup.sAMAccountName)"
                } else {
                    $planErrors += @{
                        Timestamp = Get-Date
                        Category  = 'Validation'
                        Code      = 'RequiredGroupNotFound'
                        Message   = "Required group '$group' does not exist - create Groups first"
                        Context   = @{ GroupName = $group }
                    }
                }
            } catch {
                $planErrors += @{
                    Timestamp = Get-Date
                    Category  = 'Validation'
                    Code      = 'RequiredGroupNotFound'
                    Message   = "Required group '$group' does not exist - create Groups first"
                    Context   = @{ GroupName = $group }
                }
            }
        }

        # Gate 4a: Validate LAPS GPOs exist (required for decryptor configuration)
        # Extract all LAPS GPO names from the GPO config (tiermodel-gpos.json)
        $requiredLapsGpoNames = @()
        if ($Config.PSObject.Properties['gpos'] -and $Config.gpos) {
            foreach ($ouKey in $Config.gpos.PSObject.Properties.Name) {
                $ouGpoData = $Config.gpos.$ouKey
                foreach ($gpoArray in @('ImportOnlyGpo', 'PostConfigureGpo')) {
                    if ($ouGpoData.PSObject.Properties[$gpoArray] -and $ouGpoData.$gpoArray) {
                        foreach ($gpo in $ouGpoData.$gpoArray) {
                            if ($gpo.name -like '*Windows LAPS*') {
                                $requiredLapsGpoNames += $gpo.name
                            }
                        }
                    }
                }
            }
        }
        $requiredLapsGpoNames = @($requiredLapsGpoNames | Select-Object -Unique)

        if ($requiredLapsGpoNames.Count -gt 0) {
            foreach ($gpoName in $requiredLapsGpoNames) {
                try {
                    $existingGpo = Get-GPO -Name $gpoName -Server $DomainController -ErrorAction Stop
                } catch {
                    $planErrors += @{
                        Timestamp = Get-Date
                        Category  = 'Validation'
                        Code      = 'RequiredGpoNotFound'
                        Message   = "Required GPO '$gpoName' does not exist - create GPOs first"
                        Context   = @{ GpoName = $gpoName }
                    }
                }
            }
        }

        # Gate 4b: DC exclusion check
        foreach ($delegation in $delegations) {
            $resolvedOuDn = Resolve-TierModelPlaceholder -Path $delegation.ouDn -DomainDN $domainDN
            $isDcOu = if ($delegation.PSObject.Properties['isDomainControllerOu']) { $delegation.isDomainControllerOu } else { $false }
            if (-not $isDcOu) {
                try {
                    $dcObjects = Get-ADComputer -Filter { PrimaryGroupID -eq 516 } -SearchBase $resolvedOuDn -Server $DomainController -ErrorAction SilentlyContinue
                    if ($dcObjects) {
                        $planErrors += @{
                            Timestamp = Get-Date
                            Category  = 'Validation'
                            Code      = 'WINLAPS_DC_SCOPE_REJECTED'
                            Message   = "OU '$resolvedOuDn' contains Domain Controller objects. Set isDomainControllerOu=true to opt in."
                            Context   = @{ TargetOUPath = $resolvedOuDn }
                        }
                    }
                } catch { }
            }
        }

        if ($planErrors.Count -gt 0) {
            return [PSCustomObject]@{
                Actions    = @()
                Summary    = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
                Analysis   = @{ ConfiguredDelegations = $delegations.Count; ExistingPermissions = 0; ValidationErrors = $planErrors.Count }
                Errors     = $planErrors
                Warnings   = @("One or more prerequisites are missing. Deploy the Tier Model OUs and Groups first.")
                Converged  = $false
                DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
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

        # For each delegation, detect existing state and plan 3 actions (Self + Read + Reset)
        $existingCount = 0
        foreach ($delegation in $delegations) {
            $resolvedOuDn = Resolve-TierModelPlaceholder -Path $delegation.ouDn -DomainDN $domainDN
            $ouName = if ($resolvedOuDn -match '^OU=([^,]+)') { $matches[1] } else { $resolvedOuDn }

            # Normalize readGroup/resetGroup to arrays and resolve to NetBIOS\sam
            $readGroupNames = @($delegation.readGroup)
            $resetGroupNames = @($delegation.resetGroup)
            $resolvedReadPrincipals = @($readGroupNames | ForEach-Object { $groupResolution[$_] } | Where-Object { $_ })
            $resolvedResetPrincipals = @($resetGroupNames | ForEach-Object { $groupResolution[$_] } | Where-Object { $_ })

            # Detect existing SELF permission via OU DACL inspection
            # LAPS SELF ACEs are NON-INHERITED (directly set on OU); default SELF ACEs are inherited
            $selfExists = $false
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

            # Detect existing Read/Reset permissions via Find-LapsADExtendedRights
            $readExists = $false
            $resetExists = $false

            try {
                $extendedRights = Find-LapsADExtendedRights -Identity $resolvedOuDn -ErrorAction SilentlyContinue
                if ($extendedRights) {
                    foreach ($right in @($extendedRights)) {
                        if ($right.PSObject.Properties['ExtendedRightHolders']) {
                            $holders = @($right.ExtendedRightHolders)
                            # Check if all configured read principals are present
                            $allReadPresent = $true
                            foreach ($principal in $resolvedReadPrincipals) {
                                $found = $false
                                foreach ($holder in $holders) {
                                    if ($holder -eq $principal -or $holder -like "*\$($principal.Split('\')[-1])") {
                                        $found = $true
                                        break
                                    }
                                }
                                if (-not $found) { $allReadPresent = $false; break }
                            }
                            if ($allReadPresent -and $resolvedReadPrincipals.Count -gt 0) { $readExists = $true }

                            # Check if all configured reset principals are present
                            $allResetPresent = $true
                            foreach ($principal in $resolvedResetPrincipals) {
                                $found = $false
                                foreach ($holder in $holders) {
                                    if ($holder -eq $principal -or $holder -like "*\$($principal.Split('\')[-1])") {
                                        $found = $true
                                        break
                                    }
                                }
                                if (-not $found) { $allResetPresent = $false; break }
                            }
                            if ($allResetPresent -and $resolvedResetPrincipals.Count -gt 0) { $resetExists = $true }
                        }
                    }
                }
            } catch {
                # Cannot detect — plan all actions
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
                    Validation   = @{ TargetOUExists = $true; PrincipalResolvable = $true }
                }
            } elseif ($delegation.computerSelfPermission -and $selfExists) {
                $existingCount++
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
                    Validation   = @{ TargetOUExists = $true; PrincipalResolvable = $true }
                }
            } else {
                $existingCount++
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
                    Validation   = @{ TargetOUExists = $true; PrincipalResolvable = $true }
                }
            } else {
                $existingCount++
            }
        }

        # Plan LAPS Decryptor GPO configuration (for entries with decryptorGroup)
        foreach ($delegation in $delegations) {
            $isDcOu = if ($delegation.PSObject.Properties['isDomainControllerOu']) { $delegation.isDomainControllerOu } else { $false }
            if ($isDcOu) { continue }
            if (-not ($delegation.PSObject.Properties['decryptorGroup'] -and $delegation.decryptorGroup)) { continue }
            if (-not ($delegation.PSObject.Properties['decryptorGpoName'] -and $delegation.decryptorGpoName)) { continue }

            $decryptorGroupName = $delegation.decryptorGroup
            $gpoName = $delegation.decryptorGpoName
            $resolvedDecryptor = $groupResolution[$decryptorGroupName]
            if (-not $resolvedDecryptor) { continue }

            # Check if decryptor already set correctly on the GPO
            $decryptorExists = $false
            try {
                $lapsKey = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
                $regValues = Get-GPRegistryValue -Name $gpoName -Key $lapsKey -Server $DomainController -ErrorAction Stop
                $currentPrincipal = $regValues | Where-Object { $_.ValueName -eq 'ADPasswordEncryptionPrincipal' }
                if ($currentPrincipal -and $currentPrincipal.Value -eq $resolvedDecryptor) {
                    $decryptorExists = $true
                }
            } catch { }

            if (-not $decryptorExists) {
                $actions += [PSCustomObject]@{
                    Action       = 'ConfigureLapsDecryptor'
                    ResourceType = 'LapsDecryptor'
                    Name         = "LAPS Decryptor: $resolvedDecryptor on $gpoName"
                    Path         = $gpoName
                    Data         = [PSCustomObject]@{
                        lapsOperation   = 'SetDecryptorPrincipal'
                        gpoName         = $gpoName
                        decryptorValue  = $resolvedDecryptor
                        decryptorGroup  = $decryptorGroupName
                    }
                    Dependencies = @()
                    RiskLevel    = 'Low'
                    Validation   = @{ GpoExists = $true; PrincipalResolvable = $true }
                }
            } else {
                $existingCount++
            }
        }

        $createActions = @($actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count
        $configureActions = @($actions | Where-Object { $_.Action -eq 'ConfigureLapsDecryptor' }).Count
        $lowRiskActions = @($actions | Where-Object { $_.RiskLevel -eq 'Low' }).Count
        $converged = ($actions.Count -eq 0)

        $result = [PSCustomObject]@{
            Actions       = $actions
            Summary       = @{
                TotalActions      = $actions.Count
                CreateActions     = $createActions
                ConfigureActions  = $configureActions
                ExistingCount     = $existingCount
                RiskAssessment    = @{ LowRisk = $lowRiskActions; MediumRisk = 0; HighRisk = 0 }
            }
            Analysis      = @{
                ConfiguredDelegations = $delegations.Count
                ExistingPermissions   = $existingCount
                ValidationErrors      = $planErrors.Count
            }
            Errors        = $planErrors
            Warnings      = $warnings
            Converged     = $converged
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }

        Write-TierModelLog -Level Info -Message "WinLapsAclPlanningComplete" -Data @{
            TotalActions     = $actions.Count
            CreateActions    = $createActions
            ExistingCount    = $existingCount
            Converged        = $converged
            DurationMs       = $result.DurationMs
            CorrelationId    = $CorrelationId
        } | Out-Null

        return $result
    } catch {
        Write-TierModelLog -Level Error -Message "Windows LAPS ACL planning failed" -Data @{
            Exception     = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalActions = 0; CreateActions = 0; ExistingCount = 0; RiskAssessment = @{ LowRisk = 0; MediumRisk = 0; HighRisk = 0 } }
            Analysis   = @{ ConfiguredDelegations = 0; ExistingPermissions = 0; ValidationErrors = 1 }
            Errors     = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'PlanningFailed'; Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            Warnings   = @()
            Converged  = $false
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
