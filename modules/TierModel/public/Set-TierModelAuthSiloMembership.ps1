function Set-TierModelAuthSiloMembership {
    <#
    .SYNOPSIS
    Idempotently assign account and computer membership to AD Authentication Policy Silos.

    .DESCRIPTION
    For each silo defined in tiermodel-authsilos.json, expands the memberAccountGroups and
    memberComputerGroups to their individual member accounts and computers, then assigns
    each to the silo using the mandatory two-step sequence:
      1. Grant-ADAuthenticationPolicySiloAccess  — adds the account to the silo's access list
      2. Set-ADAccountAuthenticationPolicySilo   — stamps the silo reference on the account

    Both steps are always performed in order; omitting either step leaves membership incomplete.
    Each step is idempotent: accounts already in the desired state are detected and skipped.

    EXEMPTIONS — the following accounts are NEVER assigned to any silo:
      - Configured domain-join service accounts (from authSilosExemptAccounts.samaccountnames
        in tiermodel-authsilos.json): svc-pawdomainjoin, svc-t1srvdomainjoin, svc-t2euddomainjoin.
        These authenticate from ephemeral provisioning hosts outside any approved device group.
      - The built-in domain Administrator account identified by RID-500 (<DomainSID>-500),
        resolved at runtime to handle renamed Administrator accounts. This account must remain
        unsiloed as an emergency break-glass path that survives a silo misconfiguration or
        enforced-silo lockout.

    Groups are enumerated recursively (-Recursive). Empty groups result in zero assignments —
    safe and expected during phased rollouts before group membership is populated.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig. Must contain authenticationSilos
    and authSilosExemptAccounts (populated from tiermodel-authsilos.json).

    .PARAMETER DomainController
    Preferred domain controller for all AD operations.

    .OUTPUTS
    PSCustomObject with Applied, Skipped, Errors, DurationMs, Converged, CorrelationId.

    .EXAMPLE
    $config = Get-TierModelConfig
    Set-TierModelAuthSiloMembership -Config $config -DomainController 'DC01'

    .EXAMPLE
    Set-TierModelAuthSiloMembership -Config $config -DomainController 'DC01' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController
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

        # ── Build the runtime exemption set ──────────────────────────────────────────────
        # Configured domain-join service accounts (permanent structural exemptions)
        $configuredExempts = @()
        if ($Config.PSObject.Properties['authSilosExemptAccounts'] -and $Config.authSilosExemptAccounts) {
            $configuredExempts = @($Config.authSilosExemptAccounts.samaccountnames)
        }

        # Resolve RID-500 (built-in Administrator) by SID — handles renamed accounts
        $rid500SamName = $null
        try {
            $domainSid    = (Get-ADDomain -Server $DomainController -ErrorAction Stop).DomainSID.Value
            $adminSid     = "$domainSid-500"
            $adminAccount = Get-ADUser -Identity $adminSid -Server $DomainController -ErrorAction Stop
            $rid500SamName = $adminAccount.SamAccountName
            Write-TierModelLog -Level Debug -Message "RID500Resolved" -Data @{
                Sid           = $adminSid
                SamAccountName = $rid500SamName
                CorrelationId = $CorrelationId
            } | Out-Null
        } catch {
            Write-TierModelLog -Level Warning -Message "Failed to resolve RID-500 Administrator account — proceeding without RID-500 exemption (check DC connectivity)" -Data @{
                Exception     = $_.Exception.Message
                CorrelationId = $CorrelationId
            } | Out-Null
        }

        $exemptSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $configuredExempts) { $exemptSet.Add($name) | Out-Null }
        if ($null -ne $rid500SamName) { $exemptSet.Add($rid500SamName) | Out-Null }

        Write-TierModelLog -Level Info -Message "AuthSiloMembershipExemptSet" -Data @{
            ExemptAccounts = [string[]]$exemptSet
            CorrelationId  = $CorrelationId
        } | Out-Null

        # ── Process each silo ──────────────────────────────────────────────────────────
        foreach ($silo in $silos) {
            $siloName = $silo.name

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

                # ── Expand member account groups ───────────────────────────────────────
                $accountsToAssign = [System.Collections.Generic.List[object]]::new()
                foreach ($groupName in @($silo.memberAccountGroups)) {
                    try {
                        $members = @(Get-ADGroupMember -Identity $groupName -Recursive -Server $DomainController -ErrorAction Stop |
                            Where-Object { $_.objectClass -eq 'user' })
                        foreach ($member in $members) {
                            if (-not $exemptSet.Contains($member.SamAccountName)) {
                                $accountsToAssign.Add($member)
                            } else {
                                $skipped += [PSCustomObject]@{
                                    Action = 'SkipExemptAccount'
                                    SiloName = $siloName
                                    SamAccountName = $member.SamAccountName
                                    Reason = 'ExemptAccount'
                                }
                                Write-TierModelLog -Level Info -Message "AuthSiloMembershipSkipExempt" -Data @{
                                    SiloName       = $siloName
                                    SamAccountName = $member.SamAccountName
                                    CorrelationId  = $CorrelationId
                                } | Out-Null
                            }
                        }
                    } catch {
                        $errors += @{
                            Timestamp = Get-Date; Category = 'External'; Code = 'GroupExpandFailed'
                            Message   = "Failed to expand account group '$groupName' for silo '$siloName': $($_.Exception.Message)"
                            Context   = @{ SiloName = $siloName; GroupName = $groupName; CorrelationId = $CorrelationId }
                        }
                        $converged = $false
                    }
                }

                # ── Expand member computer groups ──────────────────────────────────────
                $computersToAssign = [System.Collections.Generic.List[object]]::new()
                foreach ($groupName in @($silo.memberComputerGroups)) {
                    try {
                        $members = @(Get-ADGroupMember -Identity $groupName -Recursive -Server $DomainController -ErrorAction Stop |
                            Where-Object { $_.objectClass -eq 'computer' })
                        foreach ($member in $members) {
                            # Apply the same exemption check to computers (future-proofs against
                            # built-in computer objects that may appear in these groups)
                            if (-not $exemptSet.Contains($member.SamAccountName)) {
                                $computersToAssign.Add($member)
                            } else {
                                $skipped += [PSCustomObject]@{
                                    Action = 'SkipExemptComputer'
                                    SiloName = $siloName
                                    SamAccountName = $member.SamAccountName
                                    Reason = 'ExemptAccount'
                                }
                            }
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

                # ── Assign accounts (Grant then Set — mandatory two-step order) ─────────
                $allPrincipals = @($accountsToAssign) + @($computersToAssign)
                foreach ($principal in $allPrincipals) {
                    $sam = $principal.SamAccountName
                    $dn  = $principal.DistinguishedName

                    if ($PSCmdlet.ShouldProcess("$sam → silo '$siloName'", "Grant-ADAuthenticationPolicySiloAccess then Set-ADAccountAuthenticationPolicySilo")) {
                        try {
                            $changed = $false
                            # Step 1: Grant-ADAuthenticationPolicySiloAccess
                            # Idempotency: only grant if the account DN is not already in the silo's Members list
                            if (-not $grantedDns.Contains($dn)) {
                                Grant-ADAuthenticationPolicySiloAccess -Identity $siloName -Account $sam `
                                    -Server $DomainController -Confirm:$false -ErrorAction Stop
                                $grantedDns.Add($dn) | Out-Null
                                $changed = $true
                                Write-TierModelLog -Level Debug -Message "AuthSiloAccessGranted" -Data @{
                                    SiloName = $siloName; SamAccountName = $sam; CorrelationId = $CorrelationId
                                } | Out-Null
                            }

                            # Step 2: Set-ADAccountAuthenticationPolicySilo
                            # Idempotency: only set if account's assigned silo DN differs from this silo
                            $objectClass = $principal.objectClass
                            $currentSiloRef = $null
                            if ($objectClass -eq 'computer') {
                                $acct = Get-ADComputer -Identity $sam -Properties 'msDS-AssignedAuthNPolicySilo' -Server $DomainController -ErrorAction Stop
                            } else {
                                $acct = Get-ADUser -Identity $sam -Properties 'msDS-AssignedAuthNPolicySilo' -Server $DomainController -ErrorAction Stop
                            }
                            $currentSiloRef = $acct.'msDS-AssignedAuthNPolicySilo'

                            # Resolve the current assigned silo name from its DN (if set)
                            $currentSiloName = if ($currentSiloRef -match '^CN=') {
                                ($currentSiloRef -split ',')[0] -replace '^CN=', ''
                            } else { "$currentSiloRef" }

                            if ($currentSiloName -ne $siloName) {
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
                            } else {
                                $skipped += [PSCustomObject]@{
                                    Action         = 'AssignSiloMembership'
                                    SiloName       = $siloName
                                    SamAccountName = $sam
                                    ObjectClass    = $objectClass
                                    Reason         = 'AlreadyAssigned'
                                }
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
                        Write-Host "  [WhatIf] Would assign '$sam' to silo '$siloName'" -ForegroundColor DarkYellow
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
