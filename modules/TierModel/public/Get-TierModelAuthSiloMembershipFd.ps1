function Get-TierModelAuthSiloMembershipFd {
    <#
    .SYNOPSIS
    Build a read-only membership plan for Authentication Policy Silos (Full Deployment variant).

    .DESCRIPTION
    For each silo defined in tiermodel-authsilos.json, expands memberAccountGroups and
    memberComputerGroups (minus exemptAccounts including the RID-500 built-in Administrator)
    and classifies each expected principal as PENDING or ALREADY-ASSIGNED by reading the
    principal's msDS-AssignedAuthNPolicySilo attribute AND verifying the silo's Members list.

    A principal is ALREADY-ASSIGNED only when BOTH conditions hold:
      1. The principal's DN is in the silo's msDS-AuthNPolicySiloMembers list (Grant done).
      2. The principal's msDS-AssignedAuthNPolicySilo points to this silo (Set done).

    If either condition is not met the principal is PENDING — Set-TierModelAuthSiloMembership
    would perform at least one write for it.

    This function is read-only. It makes no changes to Active Directory.

    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig. Must include authenticationSilos
    and authSilosExemptAccounts from tiermodel-authsilos.json.

    .PARAMETER DomainController
    Preferred domain controller for all AD queries.

    .OUTPUTS
    PSCustomObject with:
      Actions      — one entry per PENDING principal ({ Action, SiloName, SamAccountName, ObjectClass })
      Summary      — { TotalPending, TotalAlreadyAssigned, TotalActions, ExistingCount }
      Warnings     — non-fatal messages
      Errors       — planning failures
      DurationMs   — elapsed time
      CorrelationId

    .EXAMPLE
    $config = Get-TierModelConfig
    $plan   = Get-TierModelAuthSiloMembershipFd -Config $config -DomainController 'DC01'
    if ($plan.Summary.TotalPending -eq 0) { "All members already assigned" }

    .EXAMPLE
    $plan.Actions | Select-Object SiloName, SamAccountName, ObjectClass
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController,

        # When specified, only count pending membership for silos in this list.
        # Pass $authSiloFdPlan.Actions.Name (CreateAuthSilo names) to implement
        # the create-once membership model: silos already in AD have 0 pending.
        # Omit to compute pending for all silos (direct-invocation / audit mode).
        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$OnlyForSilos
    )

    $CorrelationId = if (Get-Variable -Name 'script:CorrelationId' -ErrorAction SilentlyContinue) { $script:CorrelationId } else { [System.Guid]::NewGuid().ToString() }
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuthSiloMembershipFdPlanStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
    } | Out-Null

    $actions      = @()
    $warnings     = @()
    $errors       = @()
    $totalPending  = 0
    $totalAssigned = 0

    try {
        $silos = Get-TierModelAuthSilo -Config $Config
        if ($silos.Count -eq 0) {
            $warnings += "No silos in configuration — nothing to plan for membership"
        }

        foreach ($silo in $silos) {
            $siloName = $silo.name

            # Apply OnlyForSilos filter
            if ($PSBoundParameters.ContainsKey('OnlyForSilos')) {
                $filterSet = [System.Collections.Generic.HashSet[string]]::new(
                    [string[]]($OnlyForSilos ?? @()),
                    [System.StringComparer]::OrdinalIgnoreCase
                )
                if ($filterSet.Count -eq 0 -or -not $filterSet.Contains($siloName)) { continue }
            }

            try {
                # Get silo Members list for the Grant-step idempotency check
                $grantedDns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                try {
                    $adSilo = Get-ADAuthenticationPolicySilo -Identity $siloName -Properties Members -Server $DomainController -ErrorAction Stop
                    foreach ($dn in @($adSilo.Members | Where-Object { $_ })) { $grantedDns.Add($dn) | Out-Null }
                } catch {
                    $warnings += "Silo '$siloName' not found in AD — membership plan will show all as pending"
                }

                # Expand computer groups only (user/account membership is out of TM scope)
                $expectedPrincipals = [System.Collections.Generic.List[object]]::new()
                foreach ($groupName in @($silo.memberComputerGroups)) {
                    try {
                        $members = @(Get-ADGroupMember -Identity $groupName -Recursive -Server $DomainController -ErrorAction Stop |
                            Where-Object { $_.objectClass -eq 'computer' })
                        foreach ($m in $members) { $expectedPrincipals.Add($m) }
                    } catch {
                        $errors += @{
                            Timestamp = Get-Date; Category = 'External'; Code = 'GroupExpandFailed'
                            Message   = "Cannot expand computer group '$groupName': $($_.Exception.Message)"
                            Context   = @{ SiloName = $siloName; GroupName = $groupName; CorrelationId = $CorrelationId }
                        }
                    }
                }

                # Classify each expected computer: PENDING or ALREADY-ASSIGNED
                foreach ($principal in $expectedPrincipals) {
                    $sam         = $principal.SamAccountName
                    $dn          = $principal.DistinguishedName
                    $objectClass = $principal.objectClass   # always 'computer'

                    $alreadyGranted  = $grantedDns.Contains($dn)
                    $currentSiloRef  = $null
                    try {
                        $acct = if ($objectClass -eq 'computer') {
                            Get-ADComputer -Identity $sam -Properties 'msDS-AssignedAuthNPolicySilo' -Server $DomainController -ErrorAction Stop
                        } else {
                            Get-ADUser -Identity $sam -Properties 'msDS-AssignedAuthNPolicySilo' -Server $DomainController -ErrorAction Stop
                        }
                        $currentSiloRef = $acct.'msDS-AssignedAuthNPolicySilo'
                    } catch {
                        Write-TierModelLog -Level Warning -Message "AuthSiloMembershipFdReadFailed" -Data @{
                            SiloName = $siloName; SamAccountName = $sam; Exception = $_.Exception.Message; CorrelationId = $CorrelationId
                        } | Out-Null
                        # Treat as pending if we cannot read the property (safer to over-report)
                    }

                    $currentSiloName = if ($currentSiloRef -match '^CN=') {
                        ($currentSiloRef -split ',')[0] -replace '^CN=', ''
                    } else { "$currentSiloRef" }

                    $fullyAssigned = $alreadyGranted -and ($currentSiloName -eq $siloName)

                    if ($fullyAssigned) {
                        $totalAssigned++
                    } else {
                        $totalPending++
                        $actions += [PSCustomObject]@{
                            Action         = 'AssignMembership'
                            SiloName       = $siloName
                            SamAccountName = $sam
                            ObjectClass    = $objectClass
                            DistinguishedName = $dn
                        }
                    }
                }
            } catch {
                $errors += @{
                    Timestamp = Get-Date; Category = 'Execution'; Code = 'AuthSiloMembershipFdSiloFailed'
                    Message   = "Failed to plan membership for silo '$siloName': $($_.Exception.Message)"
                    Context   = @{ SiloName = $siloName; CorrelationId = $CorrelationId }
                }
                Write-TierModelLog -Level Error -Message "AuthSiloMembershipFdSiloFailed" -Data @{
                    SiloName = $siloName; Exception = $_.Exception.Message; CorrelationId = $CorrelationId
                } | Out-Null
            }
        }

        $summary = @{
            TotalPending         = $totalPending
            TotalAlreadyAssigned = $totalAssigned
            TotalActions         = $totalPending
            ExistingCount        = $totalAssigned
        }

        Write-TierModelLog -Level Info -Message "AuthSiloMembershipFdPlanComplete" -Data @{
            TotalPending    = $totalPending
            TotalAssigned   = $totalAssigned
            ErrorCount      = $errors.Count
            CorrelationId   = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions       = $actions
            Summary       = $summary
            Warnings      = $warnings
            Errors        = $errors
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }

    } catch {
        Write-TierModelLog -Level Error -Message "AuthSiloMembershipFdPlanFailed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            Actions    = @()
            Summary    = @{ TotalPending = 0; TotalAlreadyAssigned = 0; TotalActions = 0; ExistingCount = 0 }
            Warnings   = $warnings
            Errors     = @(@{ Timestamp = Get-Date; Category = 'Critical'; Code = 'AuthSiloMembershipFdPlanFailed'
                               Message = $_.Exception.Message; Context = @{ CorrelationId = $CorrelationId } })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
