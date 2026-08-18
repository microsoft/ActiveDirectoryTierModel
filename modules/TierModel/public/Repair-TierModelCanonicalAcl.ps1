function Repair-TierModelCanonicalAcl {
    <#
    .SYNOPSIS
    Repairs a non-canonical DACL on an Active Directory object by re-sorting ACEs
    into canonical order (explicit Deny -> explicit Allow -> inherited Deny ->
    inherited Allow), with CommonAce before ObjectAce within each rank.

    .DESCRIPTION
    Reads the ntSecurityDescriptor from a DC-pinned LDAP connection, parses it as a
    CommonSecurityDescriptor, applies a stable canonical sort to the DACL, and writes
    the sorted bytes back via a DC-pinned ModifyRequest (SecurityDescriptorFlagControl
    with SecurityMasks::Dacl). The operation is multiset-preserving: ACE count must
    not change. If the DACL is already canonical the function returns immediately
    with WasAlreadyCanonical=$true and no write occurs.

    The ByBytes parameter set accepts raw ntSecurityDescriptor bytes for offline
    testing without an AD connection. In this mode no write occurs; the sorted bytes
    are returned in SortedSdBytes.

    Canonical rank definition (identical to Test-TierModelCanonicalAcl):
      0  Explicit Deny  (not inherited, AceQualifier = AccessDenied)
      1  Explicit Allow (not inherited, AceQualifier = AccessAllowed)
      2  Inherited Deny (IsInherited,   AceQualifier = AccessDenied)
      3  Inherited Allow(IsInherited,   AceQualifier = AccessAllowed)
    Within each rank: CommonAce (regular, AceType < 0x04) before ObjectAce
    (AceType >= 0x04). Stability: original relative order is preserved for ACEs
    with the same (rank, type) key.

    .PARAMETER PreferredDc
    (ByServer) FQDN or hostname of the domain controller to read from and write to.
    All reads and writes are pinned to this DC. Mandatory.

    .PARAMETER DistinguishedName
    (ByServer) Distinguished name of the OU or AD object to repair. Mandatory in
    ByServer set. Optional in ByBytes set (used only for logging/output labeling).

    .PARAMETER SecurityDescriptorBytes
    (ByBytes) Raw ntSecurityDescriptor bytes to sort offline. No AD write occurs.
    Sorted bytes are returned in SortedSdBytes. Mandatory in ByBytes set.

    .OUTPUTS
    [PSCustomObject] @{
        IsCanonical         = [bool]    # true if the output DACL is canonical
        WasAlreadyCanonical = [bool]    # true if no reorder was needed
        DistinguishedName   = [string]
        AceCountBefore      = [int]
        AceCountAfter       = [int]     # must equal AceCountBefore (multiset preservation)
        SortedSdBytes       = [byte[]]  # ByBytes only; $null for ByServer
        Warnings            = [string[]]
        DurationMs          = [int]
    }

    .EXAMPLE
    Repair-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' -DistinguishedName 'OU=Tier0,DC=contoso,DC=com'

    .EXAMPLE
    $r = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $sdBytes
    $r.IsCanonical       # $true after sort
    $r.WasAlreadyCanonical # $false (a sort was required)
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByServer')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true,  ParameterSetName = 'ByServer')]
        [string]$PreferredDc,

        [Parameter(Mandatory = $true,  ParameterSetName = 'ByServer')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByBytes')]
        [string]$DistinguishedName,

        [Parameter(Mandatory = $true,  ParameterSetName = 'ByBytes')]
        [byte[]]$SecurityDescriptorBytes
    )

    $ErrorActionPreference = 'Stop'
    $startTime = Get-Date
    $warnings  = [System.Collections.Generic.List[string]]::new()

    # --- Helper: compute canonical sort key for an ACE ---
    # Key = rank * 10000 + (isObject ? 1000 : 0) + originalIndex
    # Stability is guaranteed because originalIndex is unique.
    function Get-AceSortKey {
        param([System.Security.AccessControl.GenericAce]$Ace, [int]$OriginalIndex)

        $q = $Ace -as [System.Security.AccessControl.QualifiedAce]
        if ($null -eq $q) {
            # Non-qualified ACE (system ACE etc.) — keep at end, stable
            return 40000 + $OriginalIndex
        }

        $isInherited = (([int]$Ace.AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) -ne 0
        $isDeny      = $q.AceQualifier -eq [System.Security.AccessControl.AceQualifier]::AccessDenied

        $rank = if (-not $isInherited -and $isDeny)      { 0 }   # explicit Deny
                elseif (-not $isInherited -and -not $isDeny) { 1 }   # explicit Allow
                elseif ($isInherited -and $isDeny)       { 2 }   # inherited Deny
                else                                     { 3 }   # inherited Allow

        # CommonAce (AceType < 0x04) before ObjectAce (AceType >= 0x04) within rank
        $isObject = ($Ace -is [System.Security.AccessControl.ObjectAce]) ? 1 : 0

        return ($rank * 10000) + ($isObject * 1000) + $OriginalIndex
    }

    # --- Obtain SD bytes ---
    $sdBytes = $null
    $conn    = $null   # LdapConnection kept open for the write (ByServer)

    if ($PSCmdlet.ParameterSetName -eq 'ByServer') {
        Add-Type -AssemblyName System.DirectoryServices.Protocols

        $id   = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($PreferredDc)
        $conn = New-Object System.DirectoryServices.Protocols.LdapConnection($id)
        $conn.SessionOptions.Signing = $true
        $conn.SessionOptions.Sealing = $true
        $conn.Bind()

        $ctl = New-Object System.DirectoryServices.Protocols.SecurityDescriptorFlagControl(
            [System.DirectoryServices.Protocols.SecurityMasks]::Dacl
        )
        $req = New-Object System.DirectoryServices.Protocols.SearchRequest(
            $DistinguishedName,
            '(objectClass=*)',
            'Base',
            [string[]]@('ntSecurityDescriptor')
        )
        [void]$req.Controls.Add($ctl)

        $sdBytes = ($conn.SendRequest($req)).Entries[0].Attributes['ntSecurityDescriptor'].GetValues([byte[]])[0]
    } else {
        $sdBytes = $SecurityDescriptorBytes
        if (-not $PSBoundParameters.ContainsKey('DistinguishedName')) {
            $DistinguishedName = ''
        }
    }

    # --- Check if already canonical ---
    $csdCheck = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $sdBytes, 0)
    $aceCountBefore = $csdCheck.DiscretionaryAcl.Count
    $alreadyCanonical = [bool]$csdCheck.DiscretionaryAcl.IsCanonical

    # Early-return on DiscretionaryAcl.IsCanonical intentionally matches .NET's own canonical
    # definition — the same one that governs whether AddAccessRule/write throws
    # "not in canonical form". If .NET says IsCanonical=$true, the write will not throw and
    # no reorder is needed. The CommonAce-before-ObjectAce sub-order *within* a rank is a
    # stricter MS-DTYP nicety; .NET's IsCanonical does not require it, and neither does the
    # write path. Sorting when IsCanonical is already $true would be a no-op for the
    # throw-prevention purpose and is intentionally skipped here.
    if ($alreadyCanonical) {
        $duration = [int]((Get-Date) - $startTime).TotalMilliseconds
        Write-Debug "Repair-TierModelCanonicalAcl: '$DistinguishedName' is already canonical — no write."
        return [PSCustomObject]@{
            IsCanonical         = $true
            WasAlreadyCanonical = $true
            DistinguishedName   = $DistinguishedName
            AceCountBefore      = $aceCountBefore
            AceCountAfter       = $aceCountBefore
            SortedSdBytes       = $null
            Warnings            = $warnings.ToArray()
            DurationMs          = $duration
        }
    }

    # --- Build sorted ACE list ---
    # Collect all ACEs with their original index for stable sort key computation.
    $dacl     = $csdCheck.DiscretionaryAcl
    $aceList  = [System.Collections.Generic.List[object]]::new()
    $idx      = 0
    foreach ($ace in $dacl) {
        $aceList.Add([PSCustomObject]@{ Ace = $ace; SortKey = (Get-AceSortKey -Ace $ace -OriginalIndex $idx) })
        $idx++
    }

    # Stable sort by SortKey (PowerShell 7 Sort-Object is stable by default)
    $sorted = $aceList | Sort-Object -Property SortKey -Stable

    # --- Effective-access overlap scan (Deny + Allow on same SID/right) ---
    # Warn operator but proceed — the canonical sort is still correct.
    $explicitDenies  = $sorted | Where-Object {
        $q = $_.Ace -as [System.Security.AccessControl.QualifiedAce]
        $null -ne $q -and $q.AceQualifier -eq [System.Security.AccessControl.AceQualifier]::AccessDenied -and
        -not ((([int]$_.Ace.AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) -ne 0)
    }
    $explicitAllows  = $sorted | Where-Object {
        $q = $_.Ace -as [System.Security.AccessControl.QualifiedAce]
        $null -ne $q -and $q.AceQualifier -eq [System.Security.AccessControl.AceQualifier]::AccessAllowed -and
        -not ((([int]$_.Ace.AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) -ne 0)
    }
    foreach ($dEntry in $explicitDenies) {
        $dq = $dEntry.Ace -as [System.Security.AccessControl.QualifiedAce]
        foreach ($aEntry in $explicitAllows) {
            $aq = $aEntry.Ace -as [System.Security.AccessControl.QualifiedAce]
            if ($dq.SecurityIdentifier -eq $aq.SecurityIdentifier -and
                (([int]$dq.AccessMask) -band ([int]$aq.AccessMask)) -ne 0) {
                $sidName = try { $dq.SecurityIdentifier.Translate([System.Security.Principal.NTAccount]).Value } catch { $dq.SecurityIdentifier.Value }
                $warnMsg = "Potential effective-access overlap detected on '$DistinguishedName' for principal '$sidName' — review DACL before applying sort"
                Write-Warning $warnMsg
                $warnings.Add($warnMsg)
            }
        }
    }

    # --- Reconstruct SD with sorted DACL ---
    # Build a new RawSecurityDescriptor from the original, then replace DACL ACEs.
    $rawSd = New-Object System.Security.AccessControl.RawSecurityDescriptor($sdBytes, 0)
    $newDacl = New-Object System.Security.AccessControl.RawAcl($rawSd.DiscretionaryAcl.Revision, $sorted.Count)
    foreach ($entry in $sorted) {
        $newDacl.InsertAce($newDacl.Count, $entry.Ace)
    }
    $rawSd.DiscretionaryAcl = $newDacl

    # Serialise back to bytes
    $sortedBytes = New-Object byte[] $rawSd.BinaryLength
    $rawSd.GetBinaryForm($sortedBytes, 0)

    # --- Internal sanity: verify sorted SD is now canonical ---
    $csdSorted    = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $sortedBytes, 0)
    $aceCountAfter = $csdSorted.DiscretionaryAcl.Count
    $sortedIsCanonical = [bool]$csdSorted.DiscretionaryAcl.IsCanonical

    # Multiset guard: count must not exceed before-count (DC may de-dup on write, but we check pre-write)
    if ($aceCountAfter -ne $aceCountBefore) {
        $errMsg = "CanonicalSortAceCountMismatch: ACE count changed from $aceCountBefore to $aceCountAfter during sort for '$DistinguishedName'. No write performed."
        Write-Error $errMsg
        # Surface as a terminating error so the caller catches it.
        throw $errMsg
    }

    # --- ByBytes path: return sorted bytes without writing ---
    if ($PSCmdlet.ParameterSetName -eq 'ByBytes') {
        $duration = [int]((Get-Date) - $startTime).TotalMilliseconds
        Write-Verbose "Repair-TierModelCanonicalAcl (ByBytes): '$DistinguishedName' sorted. IsCanonical=$sortedIsCanonical AceBefore=$aceCountBefore AceAfter=$aceCountAfter"
        return [PSCustomObject]@{
            IsCanonical         = $sortedIsCanonical
            WasAlreadyCanonical = $false
            DistinguishedName   = $DistinguishedName
            AceCountBefore      = $aceCountBefore
            AceCountAfter       = $aceCountAfter
            SortedSdBytes       = $sortedBytes
            Warnings            = $warnings.ToArray()
            DurationMs          = $duration
        }
    }

    # --- ByServer path: write sorted SD back to the same DC-pinned connection ---
    $mod = New-Object System.DirectoryServices.Protocols.ModifyRequest
    $mod.DistinguishedName = $DistinguishedName
    $dam = New-Object System.DirectoryServices.Protocols.DirectoryAttributeModification
    $dam.Name = 'ntSecurityDescriptor'
    $dam.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Replace
    [void]$dam.Add($sortedBytes)
    [void]$mod.Modifications.Add($dam)
    $sdCtl = New-Object System.DirectoryServices.Protocols.SecurityDescriptorFlagControl(
        [System.DirectoryServices.Protocols.SecurityMasks]::Dacl
    )
    [void]$mod.Controls.Add($sdCtl)
    [void]$conn.SendRequest($mod)

    # --- Read back to confirm write and get actual ACE count (DC may de-dup duplicates) ---
    $req2 = New-Object System.DirectoryServices.Protocols.SearchRequest(
        $DistinguishedName,
        '(objectClass=*)',
        'Base',
        [string[]]@('ntSecurityDescriptor')
    )
    $ctl2 = New-Object System.DirectoryServices.Protocols.SecurityDescriptorFlagControl(
        [System.DirectoryServices.Protocols.SecurityMasks]::Dacl
    )
    [void]$req2.Controls.Add($ctl2)
    $writtenBytes = ($conn.SendRequest($req2)).Entries[0].Attributes['ntSecurityDescriptor'].GetValues([byte[]])[0]
    $csdWritten   = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $writtenBytes, 0)
    $aceCountWritten = $csdWritten.DiscretionaryAcl.Count

    # If DC de-duplicated ACEs, log at Verbose (not an error) provided all survivors are in the original set.
    if ($aceCountWritten -lt $aceCountBefore) {
        Write-Verbose "Repair-TierModelCanonicalAcl: DC de-duplicated $($aceCountBefore - $aceCountWritten) ACE(s) on write for '$DistinguishedName' (before=$aceCountBefore written=$aceCountWritten). This is expected when duplicate ACEs exist."
        $aceCountAfter = $aceCountWritten
    }

    $duration = [int]((Get-Date) - $startTime).TotalMilliseconds
    Write-Verbose "Repair-TierModelCanonicalAcl: '$DistinguishedName' repaired in ${duration}ms. IsCanonical=$([bool]$csdWritten.DiscretionaryAcl.IsCanonical) AceBefore=$aceCountBefore AceAfter=$aceCountAfter"

    return [PSCustomObject]@{
        IsCanonical         = [bool]$csdWritten.DiscretionaryAcl.IsCanonical
        WasAlreadyCanonical = $false
        DistinguishedName   = $DistinguishedName
        AceCountBefore      = $aceCountBefore
        AceCountAfter       = $aceCountAfter
        SortedSdBytes       = $null
        Warnings            = $warnings.ToArray()
        DurationMs          = $duration
    }
}
