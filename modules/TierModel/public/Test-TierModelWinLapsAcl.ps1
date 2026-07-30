function Test-TierModelWinLapsAcl {
    <#
    .SYNOPSIS
    Audit Windows LAPS DACL delegations against configuration.

    .DESCRIPTION
    Performs drift detection for Windows LAPS DACL delegations by verifying that
    Self-permission, Read-permission, and Reset-permission exist on each target OU
    with the correct principals. Supports multi-principal entries (e.g. EUD with two
    groups). Reports findings as Compliant, MissingAcl, or UnexpectedAcl.
    Uses only Windows LAPS (ms-LAPS-*) — never legacy.

    .PARAMETER Config
    TierModel configuration object containing winLapsDelegations definitions.

    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.

    .PARAMETER Silent
    Suppress all host output (for consolidated reporting).

    .PARAMETER SuppressSummary
    Suppress the summary section while still showing per-delegation status.

    .OUTPUTS
    PSCustomObject with TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, and Findings.

    .EXAMPLE
    $config = Get-TierModelConfig
    $audit = Test-TierModelWinLapsAcl -Config $config -DomainController 'DC01'
    $audit.Findings | Where-Object Type -eq 'MissingAcl'

    .EXAMPLE
    Test-TierModelWinLapsAcl -Config $config -DomainController 'DC01' -Silent
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

    Write-TierModelLog -Level Info -Message "WinLapsAclAuditStart" -Data @{
        DomainController = $DomainController
        Silent           = $Silent.IsPresent
        CorrelationId    = $CorrelationId
    } | Out-Null

    try {
        $totalChecked = 0
        $compliantCount = 0
        $missingCount = 0
        $mismatchCount = 0
        $errorCount = 0
        $findings = @()
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController

        if (-not ($Config.PSObject.Properties.Name -contains 'winLapsDelegations') -or -not $Config.winLapsDelegations) {
            Write-TierModelLog -Level Warning -Message "No Windows LAPS delegations found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null

            return [PSCustomObject]@{
                TotalChecked  = 0
                Compliant     = 0
                Missing       = 0
                Mismatched    = 0
                Errors        = 0
                Drift         = 0
                Findings      = @()
                DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }

        # Resolve NetBIOS domain name for principal matching
        $netBIOSDomain = $null
        try {
            $adDomain = Get-ADDomain -Server $DomainController -ErrorAction Stop
            $netBIOSDomain = $adDomain.NetBIOSName
        } catch {
            Write-TierModelLog -Level Warning -Message "Cannot resolve NetBIOS domain name" -Data @{
                Exception = $_.Exception.Message; CorrelationId = $CorrelationId
            } | Out-Null
        }

        # Pre-compute LAPS attribute schema GUIDs for SELF ACE detection (mirrors Get-TierModelWinLapsAcl planner).
        # When GUIDs cannot be resolved the filter falls back to any non-inherited SELF ACE, which is safe.
        $lapsSchemaGUIDs = @()
        try {
            $rootDSE  = Get-ADRootDSE -Server $DomainController -ErrorAction Stop
            $schemaDN = $rootDSE.schemaNamingContext
            $lapsAttrNames = @(
                'msLAPS-Password', 'msLAPS-EncryptedPassword', 'msLAPS-EncryptedPasswordHistory',
                'msLAPS-PasswordExpirationTime', 'msLAPS-EncryptedDSRMPassword', 'msLAPS-EncryptedDSRMPasswordHistory'
            )
            foreach ($attrName in $lapsAttrNames) {
                $attrObj = Get-ADObject -Filter "lDAPDisplayName -eq '$attrName'" -SearchBase $schemaDN `
                               -Server $DomainController -Properties schemaIDGUID -ErrorAction SilentlyContinue
                if ($attrObj -and $attrObj.schemaIDGUID) {
                    $lapsSchemaGUIDs += [Guid]::new($attrObj.schemaIDGUID)
                }
            }
        } catch { }

        if (-not $Silent) {
            Write-Host "Auditing Windows LAPS DACL delegations..." -ForegroundColor Cyan
        }

        foreach ($delegation in @($Config.winLapsDelegations)) {
            $totalChecked++
            $resolvedOuDn = Resolve-TierModelPlaceholder -Path $delegation.ouDn -DomainDN $domainDN
            $ouName = if ($resolvedOuDn -match '^OU=([^,]+)') { $matches[1] } else { $resolvedOuDn }
            $identifier = "LAPS → $ouName"

            if (-not $Silent) {
                Write-Host "Checking Windows LAPS Delegation: $identifier" -ForegroundColor Cyan
            }

            # Normalize readGroup/resetGroup to arrays
            $readGroupNames = @($delegation.readGroup)
            $resetGroupNames = @($delegation.resetGroup)

            # Resolve group sAMAccountNames for matching
            $readSamNames = @()
            foreach ($gName in $readGroupNames) {
                try {
                    $escapedName = $gName -replace "'", "''"
                    $adGroup = Get-ADGroup -Filter "Name -eq '$escapedName'" -Server $DomainController -Properties sAMAccountName -ErrorAction Stop
                    if ($adGroup) { $readSamNames += $adGroup.sAMAccountName }
                } catch { $readSamNames += $gName }
            }
            $resetSamNames = @()
            foreach ($gName in $resetGroupNames) {
                try {
                    $escapedName = $gName -replace "'", "''"
                    $adGroup = Get-ADGroup -Filter "Name -eq '$escapedName'" -Server $DomainController -Properties sAMAccountName -ErrorAction Stop
                    if ($adGroup) { $resetSamNames += $adGroup.sAMAccountName }
                } catch { $resetSamNames += $gName }
            }

            # Check OU exists
            try {
                Get-ADOrganizationalUnit -Identity $resolvedOuDn -Server $DomainController -ErrorAction Stop | Out-Null
            } catch {
                if (-not $Silent) {
                    Write-Host "    `u{274C} Target OU missing: $resolvedOuDn" -ForegroundColor Red
                }
                $findings += [PSCustomObject]@{
                    Type          = 'MissingAcl'
                    ResourceType  = 'LapsPermission'
                    Identifier    = $identifier
                    Property      = 'TargetOU'
                    ExpectedValue = $resolvedOuDn
                    ActualValue   = 'Not Found'
                    Details       = "Target OU '$resolvedOuDn' does not exist."
                }
                $missingCount++
                continue
            }

            # SELF detection: use Get-Acl (AD: provider) with non-inherited + LAPS GUID filter.
            # Find-LapsADExtendedRights does NOT surface the computer SELF-permission ACE in
            # ExtendedRightHolders — detecting it that way always returns false. This method
            # mirrors the proven idempotency logic in Get-TierModelWinLapsAcl.ps1 (planner).
            $selfOk = $false
            $readMissing = @()
            $resetMissing = @()
            $unexpectedHolders = @()
            $genericAllHolders = @()

            try {
                $ouAcl    = Get-Acl -Path "AD:$resolvedOuDn" -ErrorAction Stop
                $selfAces = @($ouAcl.Access | Where-Object {
                    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF' -and
                    -not $_.IsInherited -and
                    ($lapsSchemaGUIDs.Count -eq 0 -or $_.ObjectType -in $lapsSchemaGUIDs)
                })
                if ($selfAces.Count -ge 1) { $selfOk = $true }

                # BUG-009: Collect principals that hold GenericAll (full control) on the OU.
                # Their effective LAPS read is an artifact of the Tier Model's OU-management
                # delegation (audited separately by the OU ACL audit) - NOT an explicit LAPS
                # delegation - so they must not be flagged as unexpected LAPS holders here.
                $genericAllHolders = @($ouAcl.Access | Where-Object {
                    $_.PSObject.Properties['ActiveDirectoryRights'] -and
                    $_.PSObject.Properties['AccessControlType'] -and
                    "$($_.AccessControlType)" -eq 'Allow' -and
                    "$($_.ActiveDirectoryRights)" -match 'GenericAll'
                } | ForEach-Object { $_.IdentityReference.Value })
            } catch { }

            # Read/Reset detection: Find-LapsADExtendedRights correctly reports these holders
            try {
                $extendedRights = Find-LapsADExtendedRights -Identity $resolvedOuDn -ErrorAction SilentlyContinue
                if ($extendedRights) {
                    foreach ($right in @($extendedRights)) {
                        if ($right.PSObject.Properties['ExtendedRightHolders']) {
                            $holders = @($right.ExtendedRightHolders)
                            # Check each read principal is present
                            foreach ($sam in $readSamNames) {
                                $found = $false
                                foreach ($holder in $holders) {
                                    if ($holder -eq "$netBIOSDomain\$sam" -or $holder -like "*\$sam") {
                                        $found = $true
                                        break
                                    }
                                }
                                if (-not $found) { $readMissing += $sam }
                            }
                            # Check each reset principal is present
                            foreach ($sam in $resetSamNames) {
                                $found = $false
                                foreach ($holder in $holders) {
                                    if ($holder -eq "$netBIOSDomain\$sam" -or $holder -like "*\$sam") {
                                        $found = $true
                                        break
                                    }
                                }
                                if (-not $found) { $resetMissing += $sam }
                            }

                            # Detect unexpected principals holding LAPS read/reset rights (drift).
                            # Well-known/administrative principals are legitimately present and skipped.
                            foreach ($holder in $holders) {
                                if ($holder -eq 'NT AUTHORITY\SELF' -or
                                    $holder -eq 'NT AUTHORITY\SYSTEM' -or
                                    $holder -eq 'BUILTIN\Administrators' -or
                                    $holder -like '*\Domain Admins' -or
                                    $holder -like '*\Enterprise Admins' -or
                                    $holder -like '*\Administrators') {
                                    continue
                                }
                                # BUG-009: Skip principals whose LAPS access derives from a GenericAll
                                # (full control) grant on the OU. That is an OU-management delegation,
                                # out of scope for the LAPS-delegation audit and covered by the OU ACL audit.
                                $holderShort = ($holder -split '\\')[-1]
                                $viaGenericAll = $false
                                foreach ($ga in $genericAllHolders) {
                                    if ($holder -eq $ga -or (($ga -split '\\')[-1]) -eq $holderShort) {
                                        $viaGenericAll = $true
                                        break
                                    }
                                }
                                if ($viaGenericAll) { continue }
                                $isExpectedHolder = $false
                                foreach ($sam in @($readSamNames + $resetSamNames)) {
                                    if ($holder -eq "$netBIOSDomain\$sam" -or $holder -like "*\$sam") {
                                        $isExpectedHolder = $true
                                        break
                                    }
                                }
                                if (-not $isExpectedHolder -and $unexpectedHolders -notcontains $holder) {
                                    $unexpectedHolders += $holder
                                }
                            }
                        }
                    }
                }
            } catch {
                $findings += [PSCustomObject]@{
                    Type          = 'Error'
                    ResourceType  = 'LapsPermission'
                    Identifier    = $identifier
                    Property      = 'ExtendedRights'
                    ExpectedValue = 'Queryable'
                    ActualValue   = 'Failed'
                    Details       = $_.Exception.Message
                }
                $errorCount++
                continue
            }

            $missingPerms = @()
            if ($delegation.computerSelfPermission -and -not $selfOk) { $missingPerms += 'ComputerSelfPermission' }
            if ($readMissing.Count -gt 0) { $missingPerms += "ReadPasswordPermission($($readMissing -join ', '))" }
            if ($resetMissing.Count -gt 0) { $missingPerms += "ResetPasswordPermission($($resetMissing -join ', '))" }

            if ($missingPerms.Count -eq 0 -and $unexpectedHolders.Count -eq 0) {
                if (-not $Silent) {
                    Write-Host "    `u{2705} LAPS Delegation COMPLIANT" -ForegroundColor Green
                }
                $findings += [PSCustomObject]@{
                    Type          = 'Compliant'
                    ResourceType  = 'LapsPermission'
                    Identifier    = $identifier
                    Property      = 'Permissions'
                    ExpectedValue = 'Self + Read + Reset permissions present'
                    ActualValue   = 'Matched'
                    Details       = 'All Windows LAPS permissions match configuration.'
                }
                $compliantCount++
            } else {
                if ($missingPerms.Count -gt 0) {
                    if (-not $Silent) {
                        Write-Host "    `u{274C} Missing LAPS permissions: $($missingPerms -join ', ')" -ForegroundColor Red
                    }
                    $findings += [PSCustomObject]@{
                        Type          = 'MissingAcl'
                        ResourceType  = 'LapsPermission'
                        Identifier    = $identifier
                        Property      = 'Permissions'
                        ExpectedValue = 'Self + Read + Reset permissions present'
                        ActualValue   = "$($missingPerms.Count) permission(s) missing"
                        Details       = "Missing: $($missingPerms -join ', ')"
                    }
                    $missingCount++
                }
                if ($unexpectedHolders.Count -gt 0) {
                    if (-not $Silent) {
                        Write-Host "    `u{26A0}`u{FE0F} Unexpected LAPS ACEs detected: $($unexpectedHolders -join ', ')" -ForegroundColor Yellow
                    }
                    $findings += [PSCustomObject]@{
                        Type          = 'UnexpectedAcl'
                        ResourceType  = 'LapsPermission'
                        Identifier    = $identifier
                        Property      = 'Permissions'
                        ExpectedValue = 'Only configured Read/Reset principals present'
                        ActualValue   = "$($unexpectedHolders.Count) unexpected principal(s) found"
                        Details       = "Unexpected LAPS rights holders: $($unexpectedHolders -join ', ')"
                    }
                    $mismatchCount++
                }
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        if (-not $Silent -and -not $SuppressSummary) {
            Write-Host "`n=== Windows LAPS ACL Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total Checked: $totalChecked" -ForegroundColor White
            Write-Host "Compliant: $compliantCount" -ForegroundColor Green
            Write-Host "Missing: $missingCount" -ForegroundColor Red
            Write-Host "Mismatched: $mismatchCount" -ForegroundColor Yellow
            Write-Host "Errors: $errorCount" -ForegroundColor Red
        }

        Write-TierModelLog -Level Info -Message "WinLapsAclAuditComplete" -Data @{
            TotalChecked  = $totalChecked
            Compliant     = $compliantCount
            Missing       = $missingCount
            Mismatched    = $mismatchCount
            Errors        = $errorCount
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked  = $totalChecked
            Compliant     = $compliantCount
            Missing       = $missingCount
            Mismatched    = $mismatchCount
            Errors        = $errorCount
            Drift         = $missingCount + $mismatchCount
            Findings      = $findings
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        }
    } catch {
        Write-TierModelLog -Level Error -Message "Windows LAPS ACL audit failed" -Data @{
            Exception     = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked  = 0
            Compliant     = 0
            Missing       = 0
            Mismatched    = 0
            Errors        = 1
            Drift         = 0
            Findings      = @([PSCustomObject]@{
                Type          = 'Error'
                ResourceType  = 'LapsPermission'
                Identifier    = 'Windows LAPS ACL Audit'
                Property      = 'Execution'
                ExpectedValue = 'Audit should complete successfully'
                ActualValue   = 'Failed'
                Details       = $_.Exception.Message
            })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
