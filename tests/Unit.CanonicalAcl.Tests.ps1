#Requires -Modules Pester
# Unit tests for Test-TierModelCanonicalAcl — ByBytes path only (no live AD required).
# Fixtures are built from well-known SIDs so the tests are fully offline and deterministic.

Describe "Test-TierModelCanonicalAcl — ByBytes path" -Tag 'Unit', 'CanonicalAcl' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'TierModel.psd1'
        Import-Module $ModulePath -Force

        # Build deterministic SD bytes from well-known SIDs.
        # Canonical rank order: explicit Deny=0, explicit Allow=1, inherited Deny=2, inherited Allow=3.
        # Non-canonical = an explicit Allow before an explicit Deny.
        function New-TestSdBytes {
            param(
                [switch]$NonCanonical,
                [switch]$MultiViolation
            )
            $owner = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'  # BUILTIN\Administrators
            $au    = [System.Security.Principal.SecurityIdentifier]'S-1-5-11'       # Authenticated Users
            $ev    = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'        # Everyone
            $sy    = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'       # SYSTEM

            $dacl = New-Object System.Security.AccessControl.RawAcl(
                [System.Security.AccessControl.GenericAcl]::AclRevision, 4)

            $allowAu = New-Object System.Security.AccessControl.CommonAce(
                [System.Security.AccessControl.AceFlags]::None,
                [System.Security.AccessControl.AceQualifier]::AccessAllowed,
                0x20094, $au, $false, $null)
            $denyEv = New-Object System.Security.AccessControl.CommonAce(
                [System.Security.AccessControl.AceFlags]::None,
                [System.Security.AccessControl.AceQualifier]::AccessDenied,
                0x20094, $ev, $false, $null)
            $allowSy = New-Object System.Security.AccessControl.CommonAce(
                [System.Security.AccessControl.AceFlags]::None,
                [System.Security.AccessControl.AceQualifier]::AccessAllowed,
                0x20094, $sy, $false, $null)
            $denySy = New-Object System.Security.AccessControl.CommonAce(
                [System.Security.AccessControl.AceFlags]::None,
                [System.Security.AccessControl.AceQualifier]::AccessDenied,
                0x20094, $sy, $false, $null)

            if ($MultiViolation) {
                # Allow(AU) -> Deny(Everyone) -> Allow(SYSTEM) -> Deny(SYSTEM)
                # Two violations: first offender = Everyone (rank drops 1->0)
                $dacl.InsertAce(0, $allowAu)
                $dacl.InsertAce(1, $denyEv)
                $dacl.InsertAce(2, $allowSy)
                $dacl.InsertAce(3, $denySy)
            } elseif ($NonCanonical) {
                # Allow(AU) -> Deny(Everyone): explicit Allow before explicit Deny = non-canonical
                $dacl.InsertAce(0, $allowAu)
                $dacl.InsertAce(1, $denyEv)
            } else {
                # Deny(Everyone) -> Allow(AU): canonical order
                $dacl.InsertAce(0, $denyEv)
                $dacl.InsertAce(1, $allowAu)
            }

            $sd = New-Object System.Security.AccessControl.RawSecurityDescriptor(
                [System.Security.AccessControl.ControlFlags]::DiscretionaryAclPresent,
                $owner, $owner, $null, $dacl)

            $b = New-Object byte[] $sd.BinaryLength
            $sd.GetBinaryForm($b, 0)
            return , $b
        }

        $script:CanonicalBytes    = New-TestSdBytes
        $script:NonCanonicalBytes = New-TestSdBytes -NonCanonical
        $script:MultiViolBytes    = New-TestSdBytes -MultiViolation
    }

    Context "Fixture self-consistency" {

        It "Canonical fixture is recognised as canonical by CommonSecurityDescriptor" {
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $script:CanonicalBytes, 0)
            $csd.DiscretionaryAcl.IsCanonical | Should -Be $true
        }

        It "NonCanonical fixture is recognised as non-canonical by CommonSecurityDescriptor" {
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $script:NonCanonicalBytes, 0)
            $csd.DiscretionaryAcl.IsCanonical | Should -Be $false
        }

        It "MultiViolation fixture is recognised as non-canonical by CommonSecurityDescriptor" {
            $csd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($true, $true, $script:MultiViolBytes, 0)
            $csd.DiscretionaryAcl.IsCanonical | Should -Be $false
        }
    }

    Context "Canonical DACL" {

        It "Returns IsCanonical = true" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes
            $result.IsCanonical | Should -Be $true
        }

        It "Returns FirstOffendingPrincipal = null when canonical" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes
            $result.FirstOffendingPrincipal | Should -BeNullOrEmpty
        }

        It "Echoes back DistinguishedName when provided" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes -DistinguishedName 'DC=test,DC=local'
            $result.DistinguishedName | Should -Be 'DC=test,DC=local'
        }

        It "Returns empty DistinguishedName when not provided" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes
            $result.DistinguishedName | Should -Be ''
        }
    }

    Context "Non-canonical DACL (Allow before Deny)" {

        It "Returns IsCanonical = false" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:NonCanonicalBytes
            $result.IsCanonical | Should -Be $false
        }

        It "Returns FirstOffendingPrincipal matching Everyone" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:NonCanonicalBytes
            $result.FirstOffendingPrincipal | Should -Match 'Everyone|S-1-1-0'
        }

        It "Echoes back DistinguishedName in ByBytes mode" {
            $dn = 'DC=contoso,DC=com'
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:NonCanonicalBytes -DistinguishedName $dn
            $result.DistinguishedName | Should -Be $dn
        }
    }

    Context "Multi-violation DACL — only first offender reported" {

        It "Returns IsCanonical = false" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolBytes
            $result.IsCanonical | Should -Be $false
        }

        It "Reports only the first offender (Everyone / S-1-1-0), not the later SYSTEM violation" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:MultiViolBytes
            $result.FirstOffendingPrincipal | Should -Match 'Everyone|S-1-1-0'
            $result.FirstOffendingPrincipal | Should -Not -Match 'SYSTEM|S-1-5-18'
        }
    }

    Context "Parameter-set: ByBytes does not require -PreferredDc" {

        It "Does not throw when called with only -SecurityDescriptorBytes" {
            { Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes } | Should -Not -Throw
        }

        It "Throws a parameter binding error when -SecurityDescriptorBytes is omitted from ByBytes call" {
            # Calling with a positional byte array actually binds to ByBytes; call with no params
            # to prove -PreferredDc is genuinely required for ByServer but not ByBytes.
            { Test-TierModelCanonicalAcl } | Should -Throw
        }
    }

    Context "ByServer path (LdapConnection mocked offline)" {

        BeforeAll {
            # Pre-load the assembly so offline creation of LdapDirectoryIdentifier /
            # SecurityDescriptorFlagControl / SearchRequest succeeds (LdapConnection is mocked).
            Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction SilentlyContinue

            # Real .NET class whose GetValues returns object[]{byte[]} without PowerShell's
            # pipeline-unrolling interfering (ScriptMethods unroll single-element arrays).
            if (-not ('FakeLdapAttr' -as [type])) {
                Add-Type @'
using System;
public class FakeLdapAttr {
    public byte[] Bytes;
    public FakeLdapAttr(byte[] bytes) { Bytes = bytes; }
    public object[] GetValues(Type t) { return new object[] { Bytes }; }
}
'@
            }
        }

        BeforeEach {
            Mock Get-ADDomain -ModuleName TierModel {
                return [PSCustomObject]@{ DistinguishedName = 'DC=contoso,DC=com' }
            }
            Mock New-Object -ModuleName TierModel `
                -ParameterFilter { $TypeName -eq 'System.DirectoryServices.Protocols.LdapConnection' } `
                -MockWith {
                    $conn = [PSCustomObject]@{ SessionOptions = [PSCustomObject]@{ Signing = $false; Sealing = $false } }
                    $conn | Add-Member -MemberType ScriptMethod -Name Bind -Value { }
                    $conn | Add-Member -MemberType ScriptMethod -Name SendRequest -Value {
                        param($r)
                        $attr  = [FakeLdapAttr]::new([byte[]]$global:_ByServerFixture)
                        $entry = [PSCustomObject]@{ Attributes = @{ 'ntSecurityDescriptor' = $attr } }
                        return [PSCustomObject]@{ Entries = @($entry) }
                    }
                    return $conn
                }
        }

        AfterEach {
            Remove-Variable -Name _ByServerFixture -Scope Global -ErrorAction SilentlyContinue
        }

        It "ByServer + non-canonical bytes -> IsCanonical false and FirstOffendingPrincipal set" {
            $global:_ByServerFixture = $script:NonCanonicalBytes
            $result = Test-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' -DistinguishedName 'DC=contoso,DC=com'
            $result.IsCanonical | Should -Be $false
            $result.FirstOffendingPrincipal | Should -Match 'Everyone|S-1-1-0'
        }

        It "ByServer + canonical bytes -> IsCanonical true and FirstOffendingPrincipal null" {
            $global:_ByServerFixture = $script:CanonicalBytes
            $result = Test-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' -DistinguishedName 'DC=contoso,DC=com'
            $result.IsCanonical | Should -Be $true
            $result.FirstOffendingPrincipal | Should -BeNullOrEmpty
        }

        It "ByServer with DN omitted -> invokes Get-ADDomain and uses its DN" {
            $global:_ByServerFixture = $script:NonCanonicalBytes
            $result = Test-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com'
            Should -Invoke Get-ADDomain -ModuleName TierModel -Times 1
            $result.DistinguishedName | Should -Be 'DC=contoso,DC=com'
        }

        It "ByServer with DN supplied -> does NOT invoke Get-ADDomain and echoes supplied DN" {
            $global:_ByServerFixture = $script:NonCanonicalBytes
            $result = Test-TierModelCanonicalAcl -PreferredDc 'dc01.contoso.com' -DistinguishedName 'OU=Tier0,DC=contoso,DC=com'
            Should -Invoke Get-ADDomain -ModuleName TierModel -Times 0
            $result.DistinguishedName | Should -Be 'OU=Tier0,DC=contoso,DC=com'
        }
    }

    Context "Return object structure" {

        It "Result has IsCanonical property" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes
            $result.PSObject.Properties.Name | Should -Contain 'IsCanonical'
        }

        It "Result has DistinguishedName property" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes
            $result.PSObject.Properties.Name | Should -Contain 'DistinguishedName'
        }

        It "Result has FirstOffendingPrincipal property" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes
            $result.PSObject.Properties.Name | Should -Contain 'FirstOffendingPrincipal'
        }

        It "IsCanonical is a boolean" {
            $result = Test-TierModelCanonicalAcl -SecurityDescriptorBytes $script:CanonicalBytes
            $result.IsCanonical | Should -BeOfType [bool]
        }
    }
}
