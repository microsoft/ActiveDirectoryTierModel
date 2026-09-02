function Compare-TierModelAuthSddl {
    <#
    .SYNOPSIS
    Compare two AllowedToAuthenticateFrom SDDL strings for semantic equivalence,
    resolving SDDL domain-group aliases to full SIDs before comparison.

    .DESCRIPTION
    AD stores conditional-ACE SDDL using two-letter well-known aliases for some
    domain groups (e.g. DD for Domain Controllers / RID 516). When Deploy-TierModel
    writes a policy with a full SID (S-1-5-21-...-516) and then reads it back, AD may
    return the alias form (DD), causing a raw string comparison to report false drift
    even though the SDDL is semantically identical.

    This function resolves that by:
      1. Extracting the domain SID prefix from the DESIRED SDDL (which always contains
         full SIDs because Build-TierModelAuthSddl resolves groups via Resolve-TierModelPrincipalSid).
         Falls back to Get-ADDomain -Server $DomainController if no full domain SID is found.
      2. Expanding known SDDL domain aliases in BOTH SDDLs to full SIDs:
           DA = domainSID-512 (Domain Admins)
           DU = domainSID-513 (Domain Users)
           DG = domainSID-514 (Domain Guests)
           DC = domainSID-515 (Domain Computers)
           DD = domainSID-516 (Domain Controllers)
      3. Default (exact-match) mode: comparing the FULL SETS of expanded SIDs —
         order-insensitive, any difference in either direction is drift.
         RequireSubset mode: verifying every DESIRED SID is present in EXISTING —
         extra SIDs in EXISTING beyond DESIRED are allowed and returned in ExtraSids.
      4. Verifying the operator is Member_of_any (OR-logic) in both SDDLs; an
         AND-logic (Member_of_each) existing policy is always flagged as drift.

    Falls back to whitespace-normalized string comparison when the domain SID cannot
    be resolved.

    .PARAMETER DesiredSddl
    The SDDL string computed by Build-TierModelAuthSddl (always contains full SIDs).

    .PARAMETER ExistingSddl
    The SDDL string read back from Active Directory (may contain SDDL aliases).

    .PARAMETER DomainController
    Preferred domain controller. Used as a fallback when no full SID is found in
    DesiredSddl (unusual) to resolve the domain SID via Get-ADDomain.

    .PARAMETER RequireSubset
    When specified: pass if every DESIRED SID is present in EXISTING (subset/mandatory check).
    Extra SIDs in EXISTING beyond DESIRED are allowed and returned in ExtraSids.
    Used by audit cmdlets where customer-added extra device groups must not fail compliance.

    When omitted (default): exact-set equality — any difference in either direction fails.
    Used by the deploy planner (Get-TierModelAuthPolicyFd) for drift detection.

    .OUTPUTS
    PSCustomObject with:
      Equal     [bool]        — $true when comparison passes (exact or subset per mode).
      Reason    [string|null] — Human-readable description when Equal is $false; $null otherwise.
      ExtraSids [string[]]    — SIDs present in EXISTING but absent from DESIRED.
                                Always empty in exact-match mode. In RequireSubset mode, these
                                are the customer-added groups beyond config — allowed, informational.

    .EXAMPLE
    $result = Compare-TierModelAuthSddl `
        -DesiredSddl  'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(S-1-5-21-1-2-3-516)}))' `
        -ExistingSddl 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(DD)}))' `
        -DomainController 'DC01'
    $result.Equal   # $true — DD expands to S-1-5-21-1-2-3-516, sets are equal

    .EXAMPLE
    # Audit mode — subset check: extra groups in AD are allowed
    $result = Compare-TierModelAuthSddl -DesiredSddl $d -ExistingSddl $e -DomainController 'DC01' -RequireSubset
    if (-not $result.Equal) { Write-Host "Missing configured groups: $($result.Reason)" }
    if ($result.ExtraSids) { Write-Host "Extra (informational): $($result.ExtraSids -join ', ')" }

    .EXAMPLE
    $result = Compare-TierModelAuthSddl -DesiredSddl $desired -ExistingSddl $existing -DomainController 'DC01'
    if (-not $result.Equal) { Write-Host "Drift: $($result.Reason)" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DesiredSddl,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ExistingSddl,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [switch]$RequireSubset
    )

    # Trivially not equal when existing SDDL is absent (policy attribute not yet written)
    if ([string]::IsNullOrWhiteSpace($ExistingSddl)) {
        return [PSCustomObject]@{ Equal = $false; Reason = "Existing SDDL is null or empty"; ExtraSids = @() }
    }

    # ── Resolve domain SID for alias expansion ────────────────────────────────────────
    # Primary: extract from the desired SDDL, which always has full SIDs (S-1-5-21-...)
    # built by Build-TierModelAuthSddl via Resolve-TierModelPrincipalSid.
    # The domain SID is the prefix before the last RID component (S-1-5-21-{a}-{b}-{c}).
    $domainSid = $null
    $domainSidMatch = [regex]::Match($DesiredSddl, '(S-1-5-21(?:-\d+){3})-\d+')
    if ($domainSidMatch.Success) {
        $domainSid = $domainSidMatch.Groups[1].Value
    } else {
        # Fallback: query AD (uncommon — only when desired SDDL contains no domain SIDs)
        try {
            $domainSid = (Get-ADDomain -Server $DomainController -ErrorAction Stop).DomainSID.Value
        } catch {
            Write-TierModelLog -Level Warning -Message "Compare-TierModelAuthSddl: domain SID unresolvable — falling back to normalized string comparison" -Data @{
                Exception = $_.Exception.Message
            } | Out-Null
        }
    }

    # ── Build alias→full-SID map ──────────────────────────────────────────────────────
    # Only domain-relative aliases (two-letter, domain SID + RID) are relevant here.
    # Other well-known aliases (BA=S-1-5-32-544, WD=S-1-1-0, etc.) do not appear in
    # Member_of_any device-group conditions and are left unexpanded.
    $aliasMap = if ($domainSid) {
        @{
            'DA' = "$domainSid-512"   # Domain Admins
            'DU' = "$domainSid-513"   # Domain Users
            'DG' = "$domainSid-514"   # Domain Guests
            'DC' = "$domainSid-515"   # Domain Computers
            'DD' = "$domainSid-516"   # Domain Controllers
        }
    } else {
        @{}
    }

    # ── Fallback: whitespace-normalized string compare when alias map is unavailable ──
    if ($aliasMap.Count -eq 0) {
        $nd = ($DesiredSddl  -replace '\s+', '')
        $ne = ($ExistingSddl -replace '\s+', '')
        return [PSCustomObject]@{
            Equal     = ($nd -eq $ne)
            Reason    = if ($nd -eq $ne) { $null } else {
                "SDDL strings differ (alias expansion unavailable — domain SID not resolved; check DC connectivity)"
            }
            ExtraSids = @()
        }
    }

    # ── Verify OR-logic operator in both SDDLs ────────────────────────────────────────
    if ($DesiredSddl  -notmatch 'Member_of_any') {
        return [PSCustomObject]@{ Equal = $false; Reason = "Desired SDDL does not use Member_of_any (OR-logic)"; ExtraSids = @() }
    }
    if ($ExistingSddl -notmatch 'Member_of_any') {
        return [PSCustomObject]@{ Equal = $false; Reason = "Existing SDDL does not use Member_of_any (OR-logic) — possible AND-logic misconfiguration in AD"; ExtraSids = @() }
    }

    # ── Extract and expand SID tokens from both SDDLs ────────────────────────────────
    # Matches SID(alias_or_full_sid) tokens inside the condition block.
    # The ACE subject ;;;WD; is NOT wrapped in SID() and is not captured here.
    $sidPattern = 'SID\(([^)]+)\)'

    $desiredSids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($DesiredSddl, $sidPattern)) {
        $tok = $m.Groups[1].Value.Trim()
        $desiredSids.Add($(if ($aliasMap.ContainsKey($tok)) { $aliasMap[$tok] } else { $tok })) | Out-Null
    }

    $existingSids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($ExistingSddl, $sidPattern)) {
        $tok = $m.Groups[1].Value.Trim()
        $existingSids.Add($(if ($aliasMap.ContainsKey($tok)) { $aliasMap[$tok] } else { $tok })) | Out-Null
    }

    # ── Order-insensitive set comparison (exact or subset depending on mode) ─────────
    # Always compute extras so the caller has them regardless of mode.
    $missingFromExisting = @($desiredSids  | Where-Object { -not $existingSids.Contains($_) })
    $extraInExisting     = @($existingSids | Where-Object { -not $desiredSids.Contains($_) })

    if ($RequireSubset) {
        # SUBSET mode (used by audit): every DESIRED SID must be present in EXISTING.
        # Extra SIDs in EXISTING are allowed — customer may add their own device groups.
        if ($missingFromExisting.Count -gt 0) {
            return [PSCustomObject]@{
                Equal     = $false
                Reason    = "Configured device-group SIDs missing from existing: $($missingFromExisting -join ', ')"
                ExtraSids = [string[]]$extraInExisting
            }
        }
        return [PSCustomObject]@{ Equal = $true; Reason = $null; ExtraSids = [string[]]$extraInExisting }
    } else {
        # EXACT mode (used by deploy planner): both sets must be identical.
        if ($desiredSids.Count -ne $existingSids.Count) {
            return [PSCustomObject]@{
                Equal     = $false
                Reason    = "Device group count differs (desired: $($desiredSids.Count), existing: $($existingSids.Count))"
                ExtraSids = [string[]]$extraInExisting
            }
        }

        if ($missingFromExisting.Count -gt 0 -or $extraInExisting.Count -gt 0) {
            $parts = @()
            if ($missingFromExisting.Count -gt 0) { $parts += "in desired only: $($missingFromExisting -join ', ')" }
            if ($extraInExisting.Count     -gt 0) { $parts += "in existing only: $($extraInExisting -join ', ')" }
            return [PSCustomObject]@{ Equal = $false; Reason = "Device group SID sets differ — $($parts -join '; ')"; ExtraSids = [string[]]$extraInExisting }
        }

        return [PSCustomObject]@{ Equal = $true; Reason = $null; ExtraSids = @() }
    }
}
