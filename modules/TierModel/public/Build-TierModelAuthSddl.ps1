function Build-TierModelAuthSddl {
    <#
    .SYNOPSIS
    Build the AllowedToAuthenticateFrom SDDL string for an AD Authentication Policy.

    .DESCRIPTION
    Constructs the msDS-UserAllowedToAuthenticateFrom SDDL string that restricts Kerberos
    TGT issuance to accounts authenticating from devices in at least one of the specified
    groups. Uses OR-logic (Member_of_any) so a device belonging to ANY listed group satisfies
    the condition.

    SDDL format: O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(sid1), SID(sid2), ...}))
      - O:SY / G:SY — Owner and Group: NT AUTHORITY\SYSTEM
      - XA           — Access Allowed Callback ACE type
      - OICI         — ObjectInherit | ContainerInherit flags
      - CR           — ControlAccess right (Kerberos TGT issuance)
      - WD           — World (Everyone) — the account subject being evaluated
      - Member_of_any — OR-logic: device must be a member of ANY listed group

    AND-logic (Member_of_each / && between groups) is the documented lockout failure mode:
    it requires a device to be simultaneously a member of every listed group, which is never
    true for a "set of approved device types" policy and causes all TGT requests to be denied.
    This function always emits OR-logic and must never be changed to AND.

    .PARAMETER DeviceSids
    One or more SID strings (S-1-5-...) representing the approved device security groups.
    At least one SID is required.

    .OUTPUTS
    string — SDDL value for msDS-UserAllowedToAuthenticateFrom.

    .EXAMPLE
    $sddl = Build-TierModelAuthSddl -DeviceSids @('S-1-5-21-111-222-333-1234', 'S-1-5-21-111-222-333-1235')
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DeviceSids
    )

    # Build SID token list: SID(s-1-5-...), SID(s-1-5-...), ...
    $sidTokens = $DeviceSids | ForEach-Object { "SID($_)" }
    $sidList = $sidTokens -join ', '

    # OR-logic conditional ACE. Member_of_any means: the device's SID list intersects
    # with the listed groups — i.e. device ∈ (group1 ∪ group2 ∪ ...).
    return "O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {$sidList}))"
}
