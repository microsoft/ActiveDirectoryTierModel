function Test-TierModelCanonicalAcl {
    <#
    .SYNOPSIS
    Tests whether an Active Directory object's DACL is in canonical form.

    .DESCRIPTION
    Reads an AD object's security descriptor and determines whether the DACL is
    in canonical order (explicit Deny -> explicit Allow -> inherited Deny -> inherited Allow).
    When the DACL is not canonical, .NET's ObjectSecurity.AddAccessRule throws
    InvalidOperationException, blocking Tier Model OU ACL delegation.

    Returns a PSCustomObject with IsCanonical, DistinguishedName, and FirstOffendingPrincipal.

    Two parameter sets allow use with a live DC (ByServer) or with raw bytes (ByBytes) for
    Pester testing without an AD connection.

    .PARAMETER PreferredDc
    (ByServer) FQDN or hostname of the domain controller to query. Mandatory.

    .PARAMETER DistinguishedName
    Distinguished name of the AD object to check.
    ByServer default: domain root (from Get-ADDomain).
    ByBytes default: empty string used only for labeling.

    .PARAMETER SecurityDescriptorBytes
    (ByBytes) Raw ntSecurityDescriptor bytes. Allows unit testing without AD.

    .EXAMPLE
    Test-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com'

    .EXAMPLE
    Test-TierModelCanonicalAcl -SecurityDescriptorBytes $sdBytes -DistinguishedName 'DC=contoso,DC=com'

    .OUTPUTS
    [PSCustomObject] @{ IsCanonical = [bool]; DistinguishedName = [string]; FirstOffendingPrincipal = [string|null] }
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByServer')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByServer')]
        [string]$PreferredDc,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByServer')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByBytes')]
        [string]$DistinguishedName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByBytes')]
        [byte[]]$SecurityDescriptorBytes
    )

    $ErrorActionPreference = 'Stop'

    # --- Obtain SD bytes ---
    if ($PSCmdlet.ParameterSetName -eq 'ByServer') {
        if (-not $PSBoundParameters.ContainsKey('DistinguishedName') -or [string]::IsNullOrEmpty($DistinguishedName)) {
            $DistinguishedName = (Get-ADDomain -Server $PreferredDc).DistinguishedName
        }

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
            @('ntSecurityDescriptor')
        )
        [void]$req.Controls.Add($ctl)

        $sdBytes = ($conn.SendRequest($req)).Entries[0].Attributes['ntSecurityDescriptor'].GetValues([byte[]])[0]
    } else {
        $sdBytes = $SecurityDescriptorBytes
        if (-not $PSBoundParameters.ContainsKey('DistinguishedName')) {
            $DistinguishedName = ''
        }
    }

    # --- Parse descriptor and check canonicality ---
    # isContainer=$true, isDS=$true: required for AD objects with object-type ACEs
    $csd  = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $sdBytes, 0)
    $dacl = $csd.DiscretionaryAcl
    $isCanonical = [bool]$dacl.IsCanonical

    # --- First-offender scan ---
    # Canonical rank: explicit Deny=0, explicit Allow=1, inherited Deny=2, inherited Allow=3
    $firstOffendingPrincipal = $null

    if (-not $isCanonical) {
        $maxRankSeen = -1

        foreach ($ace in $dacl) {
            $q = $ace -as [System.Security.AccessControl.QualifiedAce]
            if ($null -eq $q) { continue }

            $isInherited = (([int]$ace.AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) -ne 0
            $isDeny      = $q.AceQualifier -eq [System.Security.AccessControl.AceQualifier]::AccessDenied

            $rank = if (-not $isInherited -and $isDeny)      { 0 }  # explicit Deny
                    elseif (-not $isInherited -and -not $isDeny) { 1 }  # explicit Allow
                    elseif ($isInherited -and $isDeny)       { 2 }  # inherited Deny
                    else                                     { 3 }  # inherited Allow

            if ($rank -lt $maxRankSeen) {
                # This ACE is out of order - it is the first offender
                $principal = try {
                    $q.SecurityIdentifier.Translate([System.Security.Principal.NTAccount]).Value
                } catch {
                    $q.SecurityIdentifier.Value
                }
                $firstOffendingPrincipal = $principal
                break
            }

            if ($rank -gt $maxRankSeen) {
                $maxRankSeen = $rank
            }
        }
    }

    return [PSCustomObject]@{
        IsCanonical             = $isCanonical
        DistinguishedName       = $DistinguishedName
        FirstOffendingPrincipal = $firstOffendingPrincipal
    }
}
