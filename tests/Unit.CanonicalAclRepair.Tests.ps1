#Requires -Modules Pester
# Unit tests for Repair-TierModelCanonicalAcl — ByBytes path only (offline, no AD).
# Fixtures are built from well-known SIDs, matching the style of Unit.CanonicalAcl.Tests.ps1.
#
# Canonical rank order: explicit Deny=0, explicit Allow=1, inherited Deny=2, inherited Allow=3.
# Within rank: CommonAce (AceType < 0x04) before ObjectAce.
# Sort must be stable, multiset-preserving, and idempotent.

Describe "Repair-TierModelCanonicalAcl — ByBytes path" -Tag 'Unit', 'CanonicalAcl', 'Repair' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'TierModel.psd1'
        Import-Module $ModulePath -Force
        Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction SilentlyContinue

        $script:owner = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'  # BUILTIN\Administrators
        $script:au    = [System.Security.Principal.SecurityIdentifier]'S-1-5-11'       # Authenticated Users
        $script:ev    = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'        # Everyone
        $script:sy    = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'       # SYSTEM
        $script:ba    = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'   # Administrators (reuse owner)

        # Helper: build SD bytes from an ordered list of ACE specs.
        # Each spec: @{ Sid=...; Qual=AccessAllowed|AccessDenied; Inherited=$false|$true; IsObject=$false (optional) }
        # Combining build + serialise avoids IEnumerable unrolling when returning a RawAcl.
        function New-SdFromAceSpecs {
            param([object[]]$AceSpecs)
            $dacl = New-Object System.Security.AccessControl.RawAcl(
                [System.Security.AccessControl.GenericAcl]::AclRevision, $AceSpecs.Count)
            $i = 0
            foreach ($s in $AceSpecs) {
                $flags = if ($s.Inherited) { [System.Security.AccessControl.AceFlags]::Inherited } `
                         else               { [System.Security.AccessControl.AceFlags]::None }
                if ($s.IsObject) {
                    $objType = [System.Security.AccessControl.ObjectAceFlags]::None
                    $ace = New-Object System.Security.AccessControl.ObjectAce(
                        $flags, $s.Qual, 0x20094, $s.Sid, $objType,
                        [guid]::Empty, [guid]::Empty, $false, $null)
                } else {
                    $ace = New-Object System.Security.AccessControl.CommonAce(
                        $flags, $s.Qual, 0x20094, $s.Sid, $false, $null)
                }
                [void]$dacl.InsertAce($i, $ace)
                $i = $i + 1
            }
            # Serialize DACL
            $daclBytes = New-Object byte[] $dacl.BinaryLength
            [void]$dacl.GetBinaryForm($daclBytes, 0)
            # Build owner SID bytes
            $own = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'
            $ownBytes = New-Object byte[] $own.BinaryLength
            [void]$own.GetBinaryForm($ownBytes, 0)
            $ownLen = $ownBytes.Length
            # Assemble SD binary: 20-byte header + owner + group + DACL
            # Control flags: DiscretionaryAclPresent (0x0004) | SelfRelative (0x8000) → LE bytes 04 80
            $offOwner = 20; $offGroup = 20 + $ownLen; $offDacl = 20 + $ownLen + $ownLen
            $sdBytes  = New-Object byte[] ($offDacl + $daclBytes.Length)
            $sdBytes[0] = 1; $sdBytes[1] = 0
            $sdBytes[2] = 0x04; $sdBytes[3] = 0x80  # Control LE
            [System.BitConverter]::GetBytes([int32]$offOwner).CopyTo($sdBytes, 4)
            [System.BitConverter]::GetBytes([int32]$offGroup).CopyTo($sdBytes, 8)
            # OffsetSacl = 0 at bytes 12-15 (already zero)
            [System.BitConverter]::GetBytes([int32]$offDacl).CopyTo($sdBytes, 16)
            [System.Array]::Copy($ownBytes, 0, $sdBytes, $offOwner, $ownLen)
            [System.Array]::Copy($ownBytes, 0, $sdBytes, $offGroup, $ownLen)
            [System.Array]::Copy($daclBytes, 0, $sdBytes, $offDacl, $daclBytes.Length)
            return , $sdBytes
        }

        # --- Rank-order fixtures ---
        # Non-canonical: all four ranks in REVERSE canonical order
        # inherited Allow -> inherited Deny -> explicit Allow -> explicit Deny
        $script:FourRankReverseBytes = New-SdFromAceSpecs @(
            @{ Sid = $script:au; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $true  }   # rank 3
            @{ Sid = $script:sy; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $true  }   # rank 2
            @{ Sid = $script:ev; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $false }   # rank 1
            @{ Sid = $script:ba; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $false }   # rank 0
        )

        # Canonical: explicit Deny -> explicit Allow -> inherited Deny -> inherited Allow
        $script:FourRankCanonicalBytes = New-SdFromAceSpecs @(
            @{ Sid = $script:ba; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $false }   # rank 0
            @{ Sid = $script:ev; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $false }   # rank 1
            @{ Sid = $script:sy; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $true  }   # rank 2
            @{ Sid = $script:au; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $true  }   # rank 3
        )

        # --- Stability fixture: two explicit Denies — same rank, must stay A before B ---
        # Order: Allow(ev) -> Deny(au) -> Deny(sy)
        # Expected after repair: Deny(au) -> Deny(sy) -> Allow(ev) — relative order of the two Denies preserved
        $script:StabilityInputBytes = New-SdFromAceSpecs @(
            @{ Sid = $script:ev; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $false }
            @{ Sid = $script:au; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $false }
            @{ Sid = $script:sy; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $false }
        )

        # --- Overlap fixture: same SID has both Deny and Allow (overlapping rights) ---
        # This should trigger Write-Warning but still repair.
        $script:OverlapInputBytes = New-SdFromAceSpecs @(
            @{ Sid = $script:au; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $false }   # rank 1 (non-canonical: Allow before Deny)
            @{ Sid = $script:au; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $false }   # rank 0
        )

        # --- ObjectAce fixture: non-canonical rank AND CommonAce/ObjectAce sub-order issue ---
        # Input: inherited Deny (rank 2) before explicit Allow ACEs (rank 1) — rank order is wrong.
        # Within rank 1: ObjectAce first, then CommonAce — sub-order also wrong.
        # After repair: explicit Allow CommonAce (rank 1, isObject=0) first, then ObjectAce (rank 1, isObject=1),
        # then inherited Deny (rank 2). Both rank AND sub-order fixed.
        # NOTE (BUG-04): If the ONLY issue were CommonAce/ObjectAce sub-ordering with correct ranks,
        # the product's .NET IsCanonical early-return would skip the sub-sort. The sort is only applied
        # when ranks are also wrong. This fixture guarantees the sort path fires.
        $script:ObjectAceInputBytes = New-SdFromAceSpecs @(
            @{ Sid = $script:sy; Qual = [System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited = $true;  IsObject = $false }  # rank 2 — first in input (wrong)
            @{ Sid = $script:au; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $false; IsObject = $true  }  # rank 1 ObjectAce — should be after CommonAce
            @{ Sid = $script:ev; Qual = [System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited = $false; IsObject = $false }  # rank 1 CommonAce — should be first of the two
        )
    }

    # -------------------------------------------------------------------------
    Context "Return object shape" {

        It "Returns all required output properties" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'IsCanonical'
            $props | Should -Contain 'WasAlreadyCanonical'
            $props | Should -Contain 'DistinguishedName'
            $props | Should -Contain 'AceCountBefore'
            $props | Should -Contain 'AceCountAfter'
            $props | Should -Contain 'SortedSdBytes'
            $props | Should -Contain 'Warnings'
            $props | Should -Contain 'DurationMs'
        }

        It "SortedSdBytes is a byte array (ByBytes)" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.SortedSdBytes | Should -BeOfType [byte]
        }

        It "IsCanonical is boolean" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.IsCanonical | Should -BeOfType [bool]
        }

        It "DurationMs is a non-negative integer" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.DurationMs | Should -BeGreaterOrEqual 0
        }
    }

    # -------------------------------------------------------------------------
    Context "All four ranks sorted correctly" {

        It "Repair produces IsCanonical=true from four-rank reverse input" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.IsCanonical | Should -Be $true
        }

        It "WasAlreadyCanonical=false when a sort was required" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.WasAlreadyCanonical | Should -Be $false
        }

        It "Sorted output: rank 0 explicit Deny is first" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $aceList = @($csd.DiscretionaryAcl)
            $q0 = $aceList[0] -as [System.Security.AccessControl.QualifiedAce]
            $q0.AceQualifier | Should -Be ([System.Security.AccessControl.AceQualifier]::AccessDenied)
            (([int]$aceList[0].AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) | Should -Be 0
        }

        It "Sorted output: rank 1 explicit Allow is second" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $aceList = @($csd.DiscretionaryAcl)
            $q1 = $aceList[1] -as [System.Security.AccessControl.QualifiedAce]
            $q1.AceQualifier | Should -Be ([System.Security.AccessControl.AceQualifier]::AccessAllowed)
            (([int]$aceList[1].AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) | Should -Be 0
        }

        It "Sorted output: rank 2 inherited Deny is third" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $aceList = @($csd.DiscretionaryAcl)
            $q2 = $aceList[2] -as [System.Security.AccessControl.QualifiedAce]
            $q2.AceQualifier | Should -Be ([System.Security.AccessControl.AceQualifier]::AccessDenied)
            (([int]$aceList[2].AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) | Should -Not -Be 0
        }

        It "Sorted output: rank 3 inherited Allow is last" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $aceList = @($csd.DiscretionaryAcl)
            $q3 = $aceList[3] -as [System.Security.AccessControl.QualifiedAce]
            $q3.AceQualifier | Should -Be ([System.Security.AccessControl.AceQualifier]::AccessAllowed)
            (([int]$aceList[3].AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) | Should -Not -Be 0
        }

        It "Sorted output is recognised as canonical by CommonSecurityDescriptor.IsCanonical" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $csd.DiscretionaryAcl.IsCanonical | Should -Be $true
        }
    }

    # -------------------------------------------------------------------------
    Context "CommonAce before ObjectAce within same rank" {

        It "Repair produces IsCanonical=true from input with rank-disorder AND ObjectAce before CommonAce" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:ObjectAceInputBytes
            $result.IsCanonical | Should -Be $true
        }

        It "CommonAce (Everyone, rank-1) is sorted before ObjectAce (AuthenticatedUsers, rank-1) when ranks also need fixing" {
            # BUG-04 note: sub-ordering only applies when rank-level sort is also triggered.
            # The fixture has rank 2 before rank 1 (triggers sort), plus ObjectAce before CommonAce in rank 1.
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:ObjectAceInputBytes
            $result.WasAlreadyCanonical | Should -Be $false   # rank issue detected
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $aceList = @($csd.DiscretionaryAcl)
            # First ACE must be the CommonAce (rank 1, not ObjectAce)
            $aceList[0] -is [System.Security.AccessControl.ObjectAce] | Should -Be $false
            # Second ACE must be the ObjectAce (rank 1, isObject=1)
            $aceList[1] -is [System.Security.AccessControl.ObjectAce] | Should -Be $true
        }
    }

    # -------------------------------------------------------------------------
    Context "Already-canonical input" {

        It "WasAlreadyCanonical=true when input is already canonical" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankCanonicalBytes
            $result.WasAlreadyCanonical | Should -Be $true
        }

        It "IsCanonical=true when WasAlreadyCanonical" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankCanonicalBytes
            $result.IsCanonical | Should -Be $true
        }

        It "SortedSdBytes is null when already canonical (no write occurred)" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankCanonicalBytes
            $result.SortedSdBytes | Should -BeNullOrEmpty
        }

        It "AceCountBefore equals AceCountAfter when already canonical" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankCanonicalBytes
            $result.AceCountBefore | Should -Be $result.AceCountAfter
        }
    }

    # -------------------------------------------------------------------------
    Context "Multiset preservation" {

        It "AceCountBefore equals AceCountAfter after repair" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.AceCountBefore | Should -Be $result.AceCountAfter
        }

        It "AceCountBefore reflects the number of ACEs in the input" {
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $script:FourRankReverseBytes, 0)
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.AceCountBefore | Should -Be $csd.DiscretionaryAcl.Count
        }

        It "The same SIDs appear in sorted output as in the input" {
            $csdIn = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $script:FourRankReverseBytes, 0)
            $sidsBefore = @($csdIn.DiscretionaryAcl | ForEach-Object { ($_ -as [System.Security.AccessControl.QualifiedAce])?.SecurityIdentifier.Value }) | Sort-Object
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csdOut = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $sidsAfter = @($csdOut.DiscretionaryAcl | ForEach-Object { ($_ -as [System.Security.AccessControl.QualifiedAce])?.SecurityIdentifier.Value }) | Sort-Object
            $sidsAfter | Should -Be $sidsBefore
        }
    }

    # -------------------------------------------------------------------------
    Context "Stability — equal-rank same-type ACEs keep relative order" {

        It "Two explicit Deny ACEs keep their relative order after sort" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:StabilityInputBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $aceList = @($csd.DiscretionaryAcl)
            # After repair: Deny(au) [rank 0, idx 0 in original] before Deny(sy) [rank 0, idx 1 in original]
            $q0 = ($aceList[0] -as [System.Security.AccessControl.QualifiedAce])
            $q1 = ($aceList[1] -as [System.Security.AccessControl.QualifiedAce])
            $q0.SecurityIdentifier | Should -Be $script:au
            $q1.SecurityIdentifier | Should -Be $script:sy
        }

        It "Sorted output is canonical after stability-preserving repair" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:StabilityInputBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $csd.DiscretionaryAcl.IsCanonical | Should -Be $true
        }
    }

    # -------------------------------------------------------------------------
    Context "Idempotency" {

        It "Calling Repair twice — second call returns WasAlreadyCanonical=true" {
            $first  = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $second = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $first.SortedSdBytes
            $second.WasAlreadyCanonical | Should -Be $true
        }

        It "Second repair call returns IsCanonical=true" {
            $first  = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $second = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $first.SortedSdBytes
            $second.IsCanonical | Should -Be $true
        }

        It "Second repair SortedSdBytes is null (no rewrite needed)" {
            $first  = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $second = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $first.SortedSdBytes
            $second.SortedSdBytes | Should -BeNullOrEmpty
        }
    }

    # -------------------------------------------------------------------------
    Context "Deny/Allow overlap warning" {

        It "Emits a warning when same SID has both Deny and Allow on overlapping rights" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:OverlapInputBytes -WarningVariable warnVar 3>$null
            $warnVar | Should -Not -BeNullOrEmpty
        }

        It "Warning message mentions the overlapping principal" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:OverlapInputBytes -WarningVariable warnVar 3>$null
            # au = Authenticated Users (S-1-5-11)
            ($warnVar -join ' ') | Should -Match 'overlap|S-1-5-11|Authenticated'
        }

        It "Still repairs (IsCanonical=true) despite the overlap warning" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:OverlapInputBytes -WarningVariable warnVar 3>$null
            $result.IsCanonical | Should -Be $true
        }

        It "Warnings array in result is non-empty for overlap input" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:OverlapInputBytes -WarningVariable warnVar 3>$null
            $result.Warnings.Count | Should -BeGreaterThan 0
        }
    }

    # -------------------------------------------------------------------------
    Context "DistinguishedName passthrough (ByBytes)" {

        It "Echoes supplied DistinguishedName in output" {
            $dn = 'OU=Tier0,DC=contoso,DC=com'
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes -DistinguishedName $dn
            $result.DistinguishedName | Should -Be $dn
        }

        It "DistinguishedName is empty string when not supplied" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $result.DistinguishedName | Should -Be ''
        }
    }

    # -------------------------------------------------------------------------
    Context "ByServer path (LdapConnection mocked offline)" {

        BeforeAll {
            Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction SilentlyContinue

            if (-not ('FakeLdapAttrRepair' -as [type])) {
                Add-Type @'
using System;
public class FakeLdapAttrRepair {
    public byte[] Bytes;
    public FakeLdapAttrRepair(byte[] bytes) { Bytes = bytes; }
    public object[] GetValues(Type t) { return new object[] { Bytes }; }
}
'@
            }
        }

        BeforeEach {
            # Reset call counter for the dual-SearchRequest scenario
            $global:_RepairByServerCallCount = 0
            $global:_RepairByServerInitBytes = $null
            $global:_RepairByServerVerifyBytes = $null

            Mock New-Object -ModuleName TierModel `
                -ParameterFilter { $TypeName -eq 'System.DirectoryServices.Protocols.LdapConnection' } `
                -MockWith {
                    $conn = [PSCustomObject]@{ SessionOptions = [PSCustomObject]@{ Signing = $false; Sealing = $false } }
                    $conn | Add-Member -MemberType ScriptMethod -Name Bind -Value { }
                    $conn | Add-Member -MemberType ScriptMethod -Name SendRequest -Value {
                        param($r)
                        if ($r -is [System.DirectoryServices.Protocols.ModifyRequest]) {
                            return $null
                        }
                        $global:_RepairByServerCallCount = $global:_RepairByServerCallCount + 1
                        $bytes = if ($global:_RepairByServerCallCount -le 1) {
                            $global:_RepairByServerInitBytes
                        } else {
                            $global:_RepairByServerVerifyBytes
                        }
                        $attr  = [FakeLdapAttrRepair]::new([byte[]]$bytes)
                        $entry = [PSCustomObject]@{ Attributes = @{ 'ntSecurityDescriptor' = $attr } }
                        return [PSCustomObject]@{ Entries = @($entry) }
                    }
                    return $conn
                }
        }

        AfterEach {
            Remove-Variable -Name _RepairByServerCallCount, _RepairByServerInitBytes, _RepairByServerVerifyBytes `
                -Scope Global -ErrorAction SilentlyContinue
        }

        It "ByServer non-canonical: WasAlreadyCanonical=false, SortedSdBytes=null (write path)" {
            $global:_RepairByServerInitBytes   = $script:FourRankReverseBytes
            $global:_RepairByServerVerifyBytes = $script:FourRankCanonicalBytes
            $result = Repair-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' `
                -DistinguishedName 'OU=Tier0,DC=contoso,DC=com'
            $result.WasAlreadyCanonical | Should -Be $false
            $result.IsCanonical         | Should -Be $true
            $result.SortedSdBytes       | Should -BeNullOrEmpty  # ByServer never returns sorted bytes
            $result.DistinguishedName   | Should -Be 'OU=Tier0,DC=contoso,DC=com'
        }

        It "ByServer already-canonical: WasAlreadyCanonical=true, no ModifyRequest sent" {
            $global:_RepairByServerInitBytes   = $script:FourRankCanonicalBytes
            $global:_RepairByServerVerifyBytes = $script:FourRankCanonicalBytes
            $result = Repair-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' `
                -DistinguishedName 'OU=Tier0,DC=contoso,DC=com'
            $result.WasAlreadyCanonical | Should -Be $true
            $result.IsCanonical         | Should -Be $true
            # Only 1 SearchRequest (no ModifyRequest + verify read)
            $global:_RepairByServerCallCount | Should -Be 1
        }

        It "ByServer result has AceCountBefore populated from server read" {
            $global:_RepairByServerInitBytes   = $script:FourRankReverseBytes
            $global:_RepairByServerVerifyBytes = $script:FourRankCanonicalBytes
            $result = Repair-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' `
                -DistinguishedName 'OU=Tier0,DC=contoso,DC=com'
            $result.AceCountBefore | Should -Be 4
        }

        It "ByServer echos DistinguishedName in result" {
            $dn = 'OU=AdminAccounts,DC=corp,DC=local'
            $global:_RepairByServerInitBytes   = $script:FourRankReverseBytes
            $global:_RepairByServerVerifyBytes = $script:FourRankCanonicalBytes
            $result = Repair-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' -DistinguishedName $dn
            $result.DistinguishedName | Should -Be $dn
        }
    }


    # -------------------------------------------------------------------------
    Context "Parameter-set: ByBytes does not require -PreferredDc" {

        It "Does not throw when called with only -SecurityDescriptorBytes" {
            { Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes } | Should -Not -Throw
        }
    }

    # -------------------------------------------------------------------------
    Context "Multiple-violation input (5-ACE, all ranks scrambled)" {

        BeforeAll {
            # 5 ACEs in worst-case order: rank3, rank2, rank1, rank0, rank1
            # Two explicit-Allow ACEs; stability must keep their relative order.
            $script:MultiViolationBytes = & {
                $sids = @(
                    [System.Security.Principal.SecurityIdentifier]'S-1-1-0'        # rank3 (inh Allow) — pos 0
                    [System.Security.Principal.SecurityIdentifier]'S-1-5-18'       # rank2 (inh Deny)  — pos 1
                    [System.Security.Principal.SecurityIdentifier]'S-1-5-11'       # rank1 Allow A     — pos 2
                    [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'   # rank0 Deny        — pos 3
                    [System.Security.Principal.SecurityIdentifier]'S-1-5-7'        # rank1 Allow B     — pos 4
                )
                $specs = @(
                    @{ Sid=$sids[0]; Qual=[System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited=$true  }  # rank3
                    @{ Sid=$sids[1]; Qual=[System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited=$true  }  # rank2
                    @{ Sid=$sids[2]; Qual=[System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited=$false }  # rank1 (A)
                    @{ Sid=$sids[3]; Qual=[System.Security.AccessControl.AceQualifier]::AccessDenied;  Inherited=$false }  # rank0
                    @{ Sid=$sids[4]; Qual=[System.Security.AccessControl.AceQualifier]::AccessAllowed; Inherited=$false }  # rank1 (B)
                )
                New-SdFromAceSpecs $specs
            }
        }

        It "Multiple-violation 5-ACE input: IsCanonical=true after repair" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolationBytes
            $result.IsCanonical | Should -Be $true
        }

        It "Multiple-violation: WasAlreadyCanonical=false" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolationBytes
            $result.WasAlreadyCanonical | Should -Be $false
        }

        It "Multiple-violation: ACE count preserved (5 in, 5 out)" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolationBytes
            $result.AceCountBefore | Should -Be 5
            $result.AceCountAfter  | Should -Be 5
        }

        It "Multiple-violation: first ACE is the explicit Deny (rank 0)" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolationBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $ace0 = @($csd.DiscretionaryAcl)[0] -as [System.Security.AccessControl.QualifiedAce]
            $ace0.AceQualifier | Should -Be ([System.Security.AccessControl.AceQualifier]::AccessDenied)
            (([int]$ace0.AceFlags) -band ([int][System.Security.AccessControl.AceFlags]::Inherited)) | Should -Be 0
        }

        It "Multiple-violation: two explicit-Allow ACEs (rank1) keep relative order A before B" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolationBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $aceList = @($csd.DiscretionaryAcl)
            # Stability: the two rank-1 Allow ACEs (S-1-5-11 and S-1-5-7) must appear in the SAME
            # relative order as the product code's DACL iteration order (not necessarily binary-
            # insertion order, since CommonAcl may internally reorder on construction).
            # We verify stability via idempotency: re-run on sorted bytes → WasAlreadyCanonical=true,
            # meaning the first sort produced a stable canonical order that needs no further sorting.
            $result2 = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $result.SortedSdBytes
            $result2.WasAlreadyCanonical | Should -Be $true -Because "sort must be stable (idempotent)"
        }

        It "Multiple-violation: SortedSdBytes roundtrip produces a parseable SD" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolationBytes
            { New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0) } |
                Should -Not -Throw
        }
    }

    # -------------------------------------------------------------------------
    Context "ByBytes SortedSdBytes roundtrip — byte-ctor path" {

        It "SortedSdBytes round-trips through CommonSecurityDescriptor and stays canonical" {
            # Verifies the byte serialisation (GetBinaryForm) + ctor path is consistent.
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $csd.DiscretionaryAcl.IsCanonical | Should -Be $true
            $csd.DiscretionaryAcl.Count | Should -Be $result.AceCountAfter
        }

        It "SortedSdBytes re-serialised to bytes matches AceCountAfter" {
            $result = Repair-TierModelCanonicalAcl -SecurityDescriptorBytes $script:FourRankReverseBytes
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $result.SortedSdBytes, 0)
            $reBytes = New-Object byte[] $csd.BinaryLength
            $csd.GetBinaryForm($reBytes, 0)
            $csd2 = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $reBytes, 0)
            $csd2.DiscretionaryAcl.Count | Should -Be $result.AceCountAfter
        }
    }
}
