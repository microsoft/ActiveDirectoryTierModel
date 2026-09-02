function Set-TierModelAuthSiloMembership {
    <#
    .SYNOPSIS
    Assign computer membership to AD Authentication Policy Silos (create-once model).

    .DESCRIPTION
    For each silo defined in tiermodel-authsilos.json, expands memberComputerGroups to
    their individual computer objects, then assigns each to the silo using the mandatory
    two-step sequence:
      1. Grant-ADAuthenticationPolicySiloAccess  — adds the computer to the silo access list
      2. Set-ADAccountAuthenticationPolicySilo   — stamps the silo reference on the computer

    COMPUTER MEMBERSHIP ONLY: The Tier Model does not manage user/account silo membership.
    Tier admin account groups are always empty on a fresh TM deploy; account siloing is an
    out-of-band operator task performed after accounts are created and hardened.

    Membership is create-once: use -OnlyForSilos to restrict processing to newly created
    silos (pass CreatedSiloNames from New-TierModelAuthSilo). Omit -OnlyForSilos to process
    all silos (direct invocation / backwards compat).

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig. Must contain authenticationSilos.

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .PARAMETER OnlyForSilos
    When specified, only process silos whose names are in this list. Pass the CreatedSiloNames
    from New-TierModelAuthSilo for create-once behaviour. Empty array = process nothing.
    Omit entirely to process ALL silos.

    .OUTPUTS
    PSCustomObject with Applied, Skipped, Errors, DurationMs, Converged, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    Set-TierModelAuthSiloMembership -Config $config -DomainController 'DC01'

    .EXAMPLE
    # Create-once: only assign membership for newly created silos
    $siloResult = New-TierModelAuthSilo -Plan $plan -DomainController 'DC01'
    Set-TierModelAuthSiloMembership -Config $config -DomainController 'DC01' -OnlyForSilos $siloResult.CreatedSiloNames

    .EXAMPLE
    Set-TierModelAuthSiloMembership -Config $config -DomainController 'DC01' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController,

        # When specified, only process silos whose names are in this list.
        # Pass the CreatedSiloNames from New-TierModelAuthSilo to implement the
        # create-once membership model (only assign membership for newly created silos).
        # Pass an empty array to process no silos.
        # Omit entirely to process ALL silos (backwards-compat / direct invocation).
        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$OnlyForSilos
    )

    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuthSiloMembershipStart" -Data @{
        DomainController = $DomainController
        WhatIf           = $WhatIfPreference
        CorrelationId    = $CorrelationId
    } | Out-Null

    $applied   = @()
    $skipped   = @()
    $errors    = @()
    $converged = $true

    try {
        $silos = Get-TierModelAuthSilo -Config $Config
        if ($silos.Count -eq 0) {
            Write-TierModelLog -Level Warning -Message "No authentication silos in config — nothing to assign" -Data @{ CorrelationId = $CorrelationId } | Out-Null
        }

        # ── Process each silo ──────────────────────────────────────────────────────────
        foreach ($silo in $silos) {
            $siloName = $silo.name

            # -OnlyForSilos filter: skip silos not in the caller-specified list.
            # When -OnlyForSilos is bound (even as empty array), restrict to that list;
            # when omitted ($null), process all silos.
            if ($PSBoundParameters.ContainsKey('OnlyForSilos')) {
                $filterSet = [System.Collections.Generic.HashSet[string]]::new(
                    [string[]]($OnlyForSilos ?? @()),
                    [System.StringComparer]::OrdinalIgnoreCase
                )
                if ($filterSet.Count -eq 0 -or -not $filterSet.Contains($siloName)) {
                    continue   # not in the create-once target list; skip
                }
            }

            try {
                Write-TierModelLog -Level Info -Message "AuthSiloMembershipProcessSilo" -Data @{
                    SiloName      = $siloName
                    CorrelationId = $CorrelationId
                } | Out-Null

                # Verify the silo exists in AD before attempting grants
                try {
                    $adSilo = Get-ADAuthenticationPolicySilo -Identity $siloName -Properties Members -Server $DomainController -ErrorAction Stop
                } catch {
                    $errors += @{
                        Timestamp = Get-Date; Category = 'External'; Code = 'AuthSiloNotFound'
                        Message   = "Silo '$siloName' not found in AD — run New-TierModelAuthSilo first. Detail: $($_.Exception.Message)"
                        Context   = @{ SiloName = $siloName; CorrelationId = $CorrelationId }
                    }
                    $converged = $false
                    continue
                }

                # Current granted-access member DNs (used for idempotency check on Grant step)
                $grantedDns = [System.Collections.Generic.HashSet[string]]::new(
                    [string[]]@($adSilo.Members | Where-Object { $_ }),
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                # ── Expand member computer groups (computer membership only) ──────────
                $computersToAssign = [System.Collections.Generic.List[object]]::new()
                foreach ($groupName in @($silo.memberComputerGroups)) {
                    try {
                        $members = @(Get-ADGroupMember -Identity $groupName -Recursive -Server $DomainController -ErrorAction Stop |
                            Where-Object { $_.objectClass -eq 'computer' })
                        foreach ($member in $members) {
                            $computersToAssign.Add($member)
                        }
                    } catch {
                        $errors += @{
                            Timestamp = Get-Date; Category = 'External'; Code = 'GroupExpandFailed'
                            Message   = "Failed to expand computer group '$groupName' for silo '$siloName': $($_.Exception.Message)"
                            Context   = @{ SiloName = $siloName; GroupName = $groupName; CorrelationId = $CorrelationId }
                        }
                        $converged = $false
                    }
                }

                # ── Assign computers (Grant then Set — mandatory two-step order) ─────────
                $allPrincipals = @($computersToAssign)
                foreach ($principal in $allPrincipals) {
                    $sam         = $principal.SamAccountName
                    $dn          = $principal.DistinguishedName
                    $objectClass = $principal.objectClass

                    # ── Read-only already-assigned pre-check (runs before ShouldProcess) ──
                    # Placed here so WhatIf mode correctly categorises converged vs pending
                    # instead of showing every principal as "would assign".
                    $alreadyGranted    = $grantedDns.Contains($dn)
                    $preCheckSiloRef   = $null
                    try {
                        $preCheckAcct = if ($objectClass -eq 'computer') {
                            Get-ADComputer -Identity $sam -Properties 'msDS-AssignedAuthNPolicySilo' -Server $DomainController -ErrorAction Stop
                        } else {
                            Get-ADUser -Identity $sam -Properties 'msDS-AssignedAuthNPolicySilo' -Server $DomainController -ErrorAction Stop
                        }
                        $preCheckSiloRef = $preCheckAcct.'msDS-AssignedAuthNPolicySilo'
                    } catch {
                        # If the read fails, treat as pending (safer than silently skipping)
                        Write-TierModelLog -Level Warning -Message "AuthSiloMembershipPreCheckFailed" -Data @{
                            SiloName = $siloName; SamAccountName = $sam; Exception = $_.Exception.Message; CorrelationId = $CorrelationId
                        } | Out-Null
                    }
                    $preCheckSiloName = if ($preCheckSiloRef -match '^CN=') {
                        ($preCheckSiloRef -split ',')[0] -replace '^CN=', ''
                    } else { "$preCheckSiloRef" }
                    $alreadyAssigned  = $alreadyGranted -and ($preCheckSiloName -eq $siloName)

                    if ($alreadyAssigned) {
                        # Fully converged — skip without ShouldProcess (no side effects at all)
                        $skipped += [PSCustomObject]@{
                            Action         = 'AssignSiloMembership'
                            SiloName       = $siloName
                            SamAccountName = $sam
                            ObjectClass    = $objectClass
                            Reason         = 'AlreadyAssigned'
                        }
                        Write-Host "  ℹ️  Already assigned: $sam → $siloName" -ForegroundColor DarkGray
                        continue
                    }

                    # Not yet converged — call ShouldProcess for the actual writes
                    if ($PSCmdlet.ShouldProcess("$sam → silo '$siloName'", "Grant-ADAuthenticationPolicySiloAccess then Set-ADAccountAuthenticationPolicySilo")) {
                        try {
                            $changed = $false

                            # Step 1: Grant — use pre-check result to skip redundant Members read
                            if (-not $alreadyGranted) {
                                Grant-ADAuthenticationPolicySiloAccess -Identity $siloName -Account $sam `
                                    -Server $DomainController -Confirm:$false -ErrorAction Stop
                                $grantedDns.Add($dn) | Out-Null
                                $changed = $true
                                Write-TierModelLog -Level Debug -Message "AuthSiloAccessGranted" -Data @{
                                    SiloName = $siloName; SamAccountName = $sam; CorrelationId = $CorrelationId
                                } | Out-Null
                            }

                            # Step 2: Set — use pre-check result to skip redundant account read
                            if ($preCheckSiloName -ne $siloName) {
                                Set-ADAccountAuthenticationPolicySilo -Identity $sam `
                                    -AuthenticationPolicySilo $siloName `
                                    -Server $DomainController -Confirm:$false -ErrorAction Stop
                                $changed = $true
                                Write-TierModelLog -Level Debug -Message "AuthSiloAccountAssigned" -Data @{
                                    SiloName = $siloName; SamAccountName = $sam; CorrelationId = $CorrelationId
                                } | Out-Null
                            }

                            if ($changed) {
                                $applied += [PSCustomObject]@{
                                    Action         = 'AssignSiloMembership'
                                    SiloName       = $siloName
                                    SamAccountName = $sam
                                    ObjectClass    = $objectClass
                                }
                                Write-Host "  ✅ Assigned $sam ($objectClass) to silo: $siloName" -ForegroundColor Green
                            } else {
                                # Converged between pre-check and write (race-condition safety net)
                                $skipped += [PSCustomObject]@{
                                    Action         = 'AssignSiloMembership'
                                    SiloName       = $siloName
                                    SamAccountName = $sam
                                    ObjectClass    = $objectClass
                                    Reason         = 'AlreadyAssigned'
                                }
                                Write-Host "  ℹ️  Already assigned: $sam → $siloName" -ForegroundColor DarkGray
                            }
                        } catch {
                            Write-Host "  ERROR: Failed to assign '$sam' to silo '$siloName' — $($_.Exception.Message)" -ForegroundColor Red
                            Write-TierModelLog -Level Error -Message "AuthSiloMembershipAssignFailed" -Data @{
                                SiloName       = $siloName
                                SamAccountName = $sam
                                Exception      = $_.Exception.Message
                                CorrelationId  = $CorrelationId
                            } | Out-Null
                            $errors += @{
                                Timestamp = Get-Date; Category = 'Execution'; Code = 'AssignSiloMembershipFailed'
                                Message   = "Failed to assign '$sam' to silo '$siloName': $($_.Exception.Message)"
                                Context   = @{ SiloName = $siloName; SamAccountName = $sam; CorrelationId = $CorrelationId }
                            }
                            $converged = $false
                        }
                    } else {
                        # WhatIf or UserDeclined — principal is known PENDING (not already-assigned)
                        Write-Host "  [WhatIf] Would assign '$sam' ($objectClass) to silo '$siloName'" -ForegroundColor DarkYellow
                        $skipped += [PSCustomObject]@{
                            Action         = 'AssignSiloMembership'
                            SiloName       = $siloName
                            SamAccountName = $sam
                            Reason         = if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }
                        }
                    }
                }
            } catch {
                $errors += @{
                    Timestamp = Get-Date; Category = 'Execution'; Code = 'AuthSiloMembershipSiloFailed'
                    Message   = "Failed to process silo '$siloName': $($_.Exception.Message)"
                    Context   = @{ SiloName = $siloName; CorrelationId = $CorrelationId }
                }
                Write-TierModelLog -Level Error -Message "AuthSiloMembershipSiloFailed" -Data @{
                    SiloName = $siloName; Exception = $_.Exception.Message; CorrelationId = $CorrelationId
                } | Out-Null
                $converged = $false
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        # One-line membership summary so Applied/Skipped totals are fully explained
        $assignedCount = @($applied | Where-Object { $_.Action -eq 'AssignSiloMembership' }).Count
        $alreadyCount  = @($skipped | Where-Object { $_.Reason -eq 'AlreadyAssigned'      }).Count
        Write-Host "  Membership: $assignedCount assigned, $alreadyCount already-assigned" `
            -ForegroundColor $(if ($errors.Count -gt 0) { 'Yellow' } elseif ($assignedCount -gt 0) { 'Green' } else { 'Gray' })

        Write-TierModelLog -Level Info -Message "AuthSiloMembershipComplete" -Data @{
            AppliedCount = $applied.Count
            SkippedCount = $skipped.Count
            ErrorCount   = $errors.Count
            DurationMs   = $durationMs
            Converged    = $converged
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied       = $applied
            Skipped       = $skipped
            Errors        = $errors
            DurationMs    = $durationMs
            Converged     = $converged
            CorrelationId = $CorrelationId
        }

    } catch {
        Write-TierModelLog -Level Error -Message "AuthSiloMembershipFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Applied = @(); Skipped = @()
            Errors  = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthSiloMembershipFailed'
                           Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            DurationMs = ((Get-Date) - $startTime).TotalMilliseconds
            Converged  = $false
            CorrelationId = $CorrelationId
        }
    }
}
