# Authentication Policy Silos — Operations Guide

Authentication Policy Silos (AP Silos) are a Domain Controller-enforced control that restricts
where Kerberos TGTs can be issued. This guide covers what the Tier Model deploys, how to verify
behavior before enforcing, and how to keep the objects current as accounts and devices are created.

> **IMPORTANT — Upgrading from v1.x? Read this first.** Tier Model v2.0.0 is a breaking change for
> existing v1.x deployments: it adds new groups, a new service account, a new OU ACL delegation,
> the 8 authentication-silo objects, and modifies several already-deployed GPOs. Do not re-import
> or in-place-edit production GPOs that are already link enabled and in use. See
> [Appendix: Upgrading from v1.x to v2.0.0](#appendix-upgrading-from-v1x-to-v200) for the
> required, ordered migration steps.

## Who this is for and why

**Audience:** AD admins running the Tier Model who want to restrict where Tier 0 / 1 / 2 privileged
credentials can be used. No prior silo knowledge assumed.

**Why silos matter:** Standard AD lets a stolen privileged credential authenticate from any device.
Authentication Policy Silos give the KDC (Domain Controller) two levers:

- **Restrict TGT issuance** — the DC only issues a Kerberos TGT if the request originates from an
  approved device.
- **Shorten TGT lifetime** — limits how long a stolen TGT remains useful.

At deploy time, the Tier Model enrolls tier **computer** accounts into the silos. Privileged **user
and service accounts** receive a direct policy assignment via the reconciliation script; user/service
silo membership is an out-of-band operator task. The general Domain Users / Computers population is
intentionally **not** siloed.

---

## What gets deployed

The Tier Model deploys **8 objects: 4 Authentication Policies + 4 Authentication Policy Silos**.
Each silo is linked 1:1 to its policy. All 8 are created in **AUDIT mode** (`Enforce = false`) and
protected from accidental deletion.

| Tier | Authentication Policy | Authentication Policy Silo | TGT Lifetime |
|------|-----------------------|---------------------------|--------------|
| Tier 0 | `*- Tier 0 Authentication Policy` | `*- Tier 0 Authentication Silo` | 120 min (2 h) |
| Tier 1 | `*- Tier 1 Authentication Policy` | `*- Tier 1 Authentication Silo` | 240 min (4 h) |
| Tier 2 | `*- Tier 2 Authentication Policy` | `*- Tier 2 Authentication Silo` | 360 min (6 h) |
| Tier 2 EUD | `*- Tier 2 EUD Authentication Policy` | `*- Tier 2 EUD Authentication Silo` | Domain default (~10 h, not lowered) |

> The leading `*- ` is the real object name prefix — include it exactly when referencing these
> objects in PowerShell or Active Directory Admin Center (ADAC - dsac.exe).

All objects start in **AUDIT mode**: the DC logs would-be denials but does not block authentication
until you explicitly flip to enforced.

---

## How the policies, silos, and devices are linked

- **Policy ↔ Silo (1:1).** Each Authentication Policy Silo references exactly one Authentication
  Policy.
- **The silo governs computer membership.** The tier device groups (DCs, RODCs, member servers,
  PAWs, EUD devices) are enrolled in the silo at deploy time — these are the **approved origin
  devices**.
- **The policy carries the restriction.** It defines which devices an account may authenticate from
  (an SDDL condition the deploy module writes, using OR / "Member of any" logic) and the shortened
  TGT lifetime. You never author SDDL by hand.
- **Accounts receive the restriction** by having the tier's Authentication Policy directly assigned
  to them, or by being enrolled in the silo (an operator choice). The Tier Model does **not** manage
  user silo membership automatically — that is your task.
  > **Choose one model per account.** The reconciliation script continually assigns the policy
  > directly. If you instead enroll an account in a silo, first clear its direct
  > `msDS-AssignedAuthNPolicy` assignment and ensure automation will not re-add it. Do not stack
  > both without validating their combined precedence.
- **Approved-origin device group = the allow-list.** A device absent from the group causes a
  would-be denial for any tier account authenticating from it.
- **Audit vs. Enforce:**
  - **AUDIT** (`Enforce = false`): DC logs **Event 305** (would-be deny) — authentication proceeds.
  - **ENFORCE** (`Enforce = true`): DC logs **Event 105** — new Kerberos TGT denied from that
    device (the account is not globally blocked).
  - The silo's `Enforce` flag is the master switch for silo members. Set both silo and policy to
    `Enforce = true` for consistency.

---

## Auth silos complement URA and Restricted Groups

Authentication Policy Silos work alongside **User Rights Assignment (URA)** and **Restricted
Groups**, delivered by the Tier Model's Account Restrictions GPOs. They back each other up in a
defense-in-depth stack:

- **If the `*- Tier Model Account Restrictions` GPO** (linked at the domain root) somehow fails to
  apply to a given server or client endpoint, the auth silo still blocks that privileged account
  from obtaining a TGT from a non-approved origin device. One control covers the other's gap.
- **But silos restrict WHERE, not HOW.** A silo allows a service account to log on interactively
  and over RDP from an *approved* device — it does not constrain logon type.
- **That is why URA matters.** The Account Restrictions GPOs deny service accounts interactive and
  Remote Desktop logon (`Deny log on locally` / `Deny log on through Remote Desktop Services`) and
  constrain them to `Log on as a service` / batch. **Silo = origin device; URA = logon type. Use
  both.**

---

## Check the event log for failed attempts (before you enforce)

The audit channel is **on by default [*- Tier 0 DCs Authentication Silo - Computer]** when deploying the Tier Model GPOs, but Domain Controllers will require a reboot:

Query Event 305 (would-be deny) on each DC:

```powershell
Get-WinEvent -LogName "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" |
    Where-Object { $_.Id -eq 305 } |
    Select-Object TimeCreated, Message
```

**Triage every 305 before enforcing:**

- Device in scope but missing from the approved group → add it.
- Unexpected authentication source → investigate the path before enforcing.
- **Target:** zero undisposed 305s across all DCs = clean audit period.

| Event ID | Mode | Meaning |
|----------|------|---------|
| 305 | Audit | Would-be deny — auth allowed, logged only |
| 105 | Enforce | New Kerberos TGT denied from that device (account is not globally blocked) |
| 306 / 106 | Audit / Enforce | `AllowedToAuthenticateTo` (service-ticket TARGET) restrictions — this Tier Model sets only `AllowedToAuthenticateFrom`; 306/106 are **not** expected signals from this deployment |

**Blind spots — inventory these before enforcing:**

- **NTLM** — not evaluated against the Kerberos origin-device allow-list and has no Event 305
  audit equivalent. Under enforcement, NTLM that cannot satisfy the policy's access-control
  restrictions can be rejected and logged as **Event 101**. Inventory and test NTLM-dependent
  paths (RADIUS/NPS, legacy apps, VPN) separately before enforcing.
- **LDAP simple bind** — not covered by 305/306 auditing. Its behavior under enforced restrictions
  is not established here; it may bypass the restriction or fail with no prior audit warning.
  Inventory LDAP simple-bind apps before enforcing.
- **Cached / offline logon** — not covered.
- **Already-issued TGTs** — valid until expiry; enforcement only affects new TGT requests.

**Flipping to enforced (short checklist):**

1. Confirm the domain functional level is **≥ Windows Server 2012 R2** and that KDC claims /
   compound authentication / armoring is configured on all relevant DCs and supported on client
   paths.
2. Run a **positive control test** — from a supported but *non-approved* device, request a fresh
   TGT and confirm Event 305 is generated on the servicing DC and reaches monitoring. A
   nonfunctional or unassigned control also produces zero 305s, so a clean baseline alone is not
   proof the control is working.
3. Confirm zero undisposed 305s across all DCs over a representative audit period.
4. Verify break-glass (RID-500 built-in Administrator) is **not** enrolled in any silo.
5. Set the silo's `Enforce = true` — master switch for silo members.
6. Set the linked policy's `Enforce = true` as well.
7. Roll back = set both back to `false`. Do this in a change window with break-glass access tested
   beforehand.

---

## Manual maintenance

### When a new Tier 0 user (or service account) is created (Same for Tier 1)

- Place it in the correct Tier 0 OU:
  - Admin users → `OU=Tier 0 Accounts,OU=Tier 0,OU=Tier Model Administration`
  - Service accounts → `OU=Tier 0 Service Accounts,OU=Tier 0,OU=Tier Model Administration`
- Add to the correct group:
  - Admin users → `Tier0Operators`
  - Service accounts → `Tier0ServiceAccounts`
- Assign `*- Tier 0 Authentication Policy` to the account — this applies the origin-device
  restriction and the 2-hour TGT lifetime.
- **NEVER** assign a policy or silo to the break-glass built-in Administrator (RID-500). Windows
  always exempts RID-500 from Authentication Policy evaluation even if assigned — keep it
  unassigned as break-glass hygiene. It remains subject to account state, URA, smart-card, and
  network controls; test the full emergency-access path before enforcing.
- Mark any account that must be excluded (break-glass, special service accounts) with your exclusion
  attribute so automation skips it — see the script section below.

### When a new Tier 0 computer is created (Same for Tier 1)

- Move the computer account into the correct Tier 0 OU (PAW Devices, Member Servers, or Server
  Staging).
- Add the computer account (trailing `$`) to the matching device group:
  - PAWs → `Tier0PAWDevices`
  - Member servers → `Tier0MemberServers`
  This is what makes the machine an **approved origin device**.
- Confirm AD replication to all DCs before relying on the approval.

Apply the same pattern for Tier 1 and Tier 2 — substitute the tier-appropriate OUs, groups
(`Tier1Operators`, `Tier2Operators`, etc.), and policies.

All of the above can be automated — see the next section.

---

## Automating maintenance with the reconciliation script

`optional/Update-TierModelMembership.ps1` reconciles Tier Model group membership (ADDITIVE — never
removes) and assigns or clears the tier Authentication Policy on user and service accounts as they
are created. It **never** modifies policies, silos, or SDDL — those are create-once objects managed
by the deploy module. It runs as a local scheduled task on a **writable, Global-Catalog domain
controller** in SYSTEM context and **requires PowerShell 7 (`pwsh.exe`)** — Windows PowerShell 5.1
is explicitly blocked. The script preflight rejects RODCs and non-GC DCs.

> Run `Get-Help .\Update-TierModelMembership.ps1 -Full` for the complete parameter reference. Only
> the most important operational options are called out here.

### Scheduling examples

**Example A — Daily full reconciliation at 02:00**

```powershell
$action = New-ScheduledTaskAction `
    -Execute "C:\Program Files\PowerShell\7\pwsh.exe" `
    -Argument '-NoProfile -File "C:\TierModel\optional\Update-TierModelMembership.ps1" -All -ExclusionAttribute adminDescription -ExclusionValue TierModelExclude -EnableLogging -EnableEventLog -JobId Daily'

$trigger   = New-ScheduledTaskTrigger -Daily -At "02:00"
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "TierModel-Daily" `
    -Action $action -Trigger $trigger -Principal $principal -Force
```

**Example B — Split schedule (Tier 1 hourly, full daily catch-up)**

Every invocation must include the same exclusion decision (`-ExclusionAttribute`/`-ExclusionValue`
or `-NoExclusions`). Use `-AllTier1 -JobId T1-Hourly` for the Tier 1 task and `-All -JobId Daily`
for the daily full sweep (`-All` covers all tiers). `-JobId` only appears in output when
`-EnableLogging` or `-EnableEventLog` is also set — use it to correlate runs in your SIEM.

**Example C — Safe preview before the first real run**

```powershell
.\Update-TierModelMembership.ps1 -All `
    -ExclusionAttribute adminDescription -ExclusionValue "TierModelExclude" `
    -EnableLogging -WhatIf
```

`-WhatIf` shows exactly which users, computers, and service accounts **would** change — written to
the log file — without touching AD.

### Exclusions — required decision

> **The script refuses to run unless you make an explicit exclusion decision.**

Pass **either** `-ExclusionAttribute` + `-ExclusionValue` **or** `-NoExclusions`. This safety gate
prevents a forgotten exclusion from silently applying a policy to accounts that must stay out.

**Recommended:** `-ExclusionAttribute adminDescription -ExclusionValue "TierModelExclude"`

- `adminDescription` is a standard AD attribute, distinct from `description`, and is not normally
  used as an Exchange recipient field — which makes it a good exclusion marker even in Exchange
  environments. Before adopting it, inventory existing `adminDescription` values and confirm no
  Exchange or local automation writes it in your environment.
- Stamp `adminDescription = TierModelExclude` on break-glass accounts and any service account that
  must not be siloed. The script clears an assigned Authentication Policy from excluded accounts and
  does **not add** excluded service accounts to the tier service-account group. Group reconciliation
  is additive — it never removes an account already in a group; remove such memberships manually if
  required.

Only use `-NoExclusions` when you have verified there are genuinely no accounts to exclude — it
adds **everyone** in scope to the groups and policies.

### Logging

- `-EnableLogging` — writes a change log to a `Logs` subfolder beside the script (7-day retention).
- `-EnableEventLog` — writes START / COMPLETE / ERROR events to the Windows Application log
  (Source `TierModel`, Event IDs 1000 / 1001 / 1009).

See [Tier Model logging](https://microsoft.github.io/ActiveDirectoryTierModel/tiermodel-logging/) for log structure and retention details.

---

## Limitations

- AP Silos only restrict the **Kerberos AS (TGT) origin decision**. They do not block NTLM,
  LDAP simple bind, cached/offline logon, or Entra / cloud authentication paths.
- **Already-issued TGTs stay valid** until they expire — enforcement applies to new TGT requests
  only.
- Service tickets (TGS) from an already-issued TGT are not re-checked against the silo.
- Silos are **one layer**. Combine with Account Restrictions GPOs, LAPS, tiered OUs, and
  least-privilege role assignment.

---

## Appendix: Upgrading from v1.x to v2.0.0

> **BREAKING CHANGE.** v2.0.0 modifies GPOs that are already link-enabled in a v1.x environment
> and adds new AD objects. Never replace or in-place-overwrite a production GPO. Follow the ordered
> steps below; the GPO step offers a safe redeploy option and a manual option.

### What's new in v2.0.0 (the delta)

**New security groups and service account** (create these first):

| Object | Type | Scope | Purpose |
|--------|------|-------|---------|
| `Tier2EUDDevices` | Security group | Universal | Auth-silo device group — Tier 2 End-User Devices |
| `Tier2PAWDevices` | Security group | Universal | Auth-silo device group — Tier 2 PAWs |
| `Tier2EUDDomainJoin` | Security group | Global | Delegation group for domain-joining Tier 2 End-User Devices |
| `svc-t2euddomainjoin` | Service account | — | Tier 2 EUD domain-join account; created **disabled**; member of `Tier2EUDDomainJoin` |

**New OU ACL delegation:**

| Trustee | Target OU | Rights granted |
|---------|-----------|----------------|
| `Tier2EUDDomainJoin` | `OU=Tier 2 End-User Devices` | Create Computer objects; reset password; validated write to DNS host name; validated write to service principal name |

Note: delegation is on the End-User Devices OU directly — there is no separate Tier 2 EUD staging
OU. No new OUs are introduced in v2, so no OU deployment step is required.

**New authentication objects:** the 8 auth-silo objects (4 policies + 4 silos) described earlier in
this guide — all created in audit mode.

**Modified GPO — `*- Tier 0 DCs Authentication Silo - Computer`** (replaced):

| Setting | Where / effect |
|---------|---------------|
| KDC "Always provide claims" | Computer > Admin Templates > System > KDC — enables Kerberos armoring (FAST) claims |
| Remote host allows delegation of non-exportable credentials | Computer > Admin Templates > System > Credentials Delegation — Remote Credential Guard; enables admin RDP |
| Enable `AuthenticationPolicyFailures-DomainController` log channel | Computer > Preferences > Registry — sets `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController` `Enabled` (REG_DWORD) = 1 |

**Modified GPOs — Account Restrictions family** (re-deployed from an updated shared baseline):

Now add the **Remote host allows delegation of non-exportable credentials** setting (RDP / Remote
Credential Guard) and add `Tier2EUDDomainJoin` to the `SeDeny*` User Rights Assignment deny lists.
Affected GPOs:

- `*- Tier Model Account Restrictions` (domain root)
- `*- Tier 0 Servers Account Restrictions`
- `*- Tier 0 Servers Staging Account Restrictions`
- `*- Tier 1 Servers Account Restrictions`
- `*- Tier 1 Servers Staging Account Restrictions`
- `*- Tier 2 EUD Account Restrictions`
- `*- Tier Model PAW Staging Account Restrictions`
- `*- Tier Model Template ... URA - Computer` templates
- `*- Tier Model Template Tier 0/1 Servers Account Restrictions - Override - Deny *` templates

**`Tier2EUDDomainJoin` deny-URA scope** (varies by tier so the join account can still
network-join in its own tier):

| GPO | Deny rights added |
|-----|------------------|
| `*- Tier Model Account Restrictions` (domain root) | All 5 `SeDeny*` |
| `*- Tier 0 Servers Account Restrictions` | All 5 `SeDeny*` |
| `*- Tier 0 PAWs Account Restrictions` | All 5 `SeDeny*` |
| `*- Tier 1 Servers Account Restrictions` | All 5 `SeDeny*` |
| `*- Tier 1 PAWs Account Restrictions` | All 5 `SeDeny*` |
| `*- Tier Model Template Tier 0/1 Servers Account Restrictions - Override - Deny *` | Batch / Network / Remote Desktop / Service |
| `*- Tier 2 EUD Account Restrictions` | Batch + Service only (Network stays open to allow EUD domain-join) |
| `*- Tier 2 PAWs Account Restrictions` | Batch + Service only |
| `*- Tier Model Computer Quarantine Account Restrictions` | Interactive only |

The 5 `SeDeny*` rights = Deny access to this computer from the network, Deny log on as a batch
job, Deny log on as a service, Deny log on locally, Deny log on through Remote Desktop Services.

### Migration steps (in order)

**Step 1 — Add the new objects** (safe — brand-new objects, no conflict with v1.x). Run Audit
first to preview, then Deploy one scope at a time:

```
Audit-TierModel.ps1  -GroupOnly
Deploy-TierModel.ps1 -GroupOnly    # creates Tier2EUDDevices, Tier2PAWDevices, Tier2EUDDomainJoin

Deploy-TierModel.ps1 -UserOnly     # creates svc-t2euddomainjoin (disabled)

Deploy-TierModel.ps1 -OuAclsOnly   # adds Tier2EUDDomainJoin delegation on OU=Tier 2 End-User Devices
```

> Switch names are `-GroupOnly`, `-UserOnly`, `-OuAclsOnly`, `-GposOnly` — note `-OuAclsOnly` and
> `-GposOnly` (not "AclOnly" / "GpoOnly").

**Step 2 — Deploy the authentication silos:**

```
Deploy-TierModel.ps1 -IncludeAuthSilos
```

This creates the 8 objects in audit mode. The new device groups from Step 1 must exist first —
the command fails if they are missing.

**Step 3 — Update the GPOs** (the complex step). Two options:

**Option 1 — Redeploy the GPOs fresh (recommended):**

1. Rename the current (v1.x) GPOs and move them to the lowest link priority.
2. Run `Deploy-TierModel.ps1 -GposOnly` to deploy the updated GPOs alongside the renamed old ones.
   This has no functional impact if the GPOs were never manually edited (per Tier Model guidance
   they never should be).
3. Verify the new GPOs apply correctly and Group Policy Results show expected settings.
4. Delete the old renamed GPOs once verified.

The deploy script works cleanly as long as the old GPOs are renamed and at the lowest link
priority, so the new ones win precedence during cutover.

**Option 2 — Modify the existing GPOs manually (per-GPO checklist):**

Open each GPO in GPMC, make the changes below, then force-replicate and run `gpresult /h` to
verify the settings applied. Navigate using the paths at the top of each column.

**URA rights key** (Computer Config > Policies > Windows Settings > Security Settings >
User Rights Assignment — add `Tier2EUDDomainJoin` to each listed right):

| Symbol | Right |
|--------|-------|
| Net | Deny access to this computer from the network (`SeDenyNetworkLogonRight`) |
| Batch | Deny log on as a batch job (`SeDenyBatchLogonRight`) |
| Svc | Deny log on as a service (`SeDenyServiceLogonRight`) |
| Local | Deny log on locally (`SeDenyInteractiveLogonRight`) |
| RDS | Deny log on through Remote Desktop Services (`SeDenyRemoteInteractiveLogonRight`) |

**RDP setting** (rows marked ✓ below): Computer Config > Policies > Admin Templates > System >
Credentials Delegation > **"Remote host allows delegation of non-exportable credentials" = Enabled**
(registry: `HKLM\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowProtectedCreds = 1`)

| GPO | Add `Tier2EUDDomainJoin` to Deny-URA rights | Add RDP Credentials Delegation |
|-----|---------------------------------------------|-------------------------------|
| `*- Tier Model Account Restrictions` | Net · Batch · Svc · Local · RDS | ✓ |
| `*- Tier 0 Servers Account Restrictions` | Net · Batch · Svc · Local · RDS | ✓ |
| `*- Tier 0 Servers Staging Account Restrictions` | — | ✓ |
| `*- Tier 0 PAWs Account Restrictions` | Net · Batch · Svc · Local · RDS | — |
| `*- Tier 1 Servers Account Restrictions` | Net · Batch · Svc · Local · RDS | ✓ |
| `*- Tier 1 Servers Staging Account Restrictions` | — | ✓ |
| `*- Tier 1 PAWs Account Restrictions` | Net · Batch · Svc · Local · RDS | — |
| `*- Tier 2 EUD Account Restrictions` | Batch · Svc | ✓ |
| `*- Tier 2 PAWs Account Restrictions` | Batch · Svc | — |
| `*- Tier Model PAW Staging Account Restrictions` | — | ✓ |
| `*- Tier Model Computer Quarantine Account Restrictions` | Local | — |
| `*- Tier Model Template ... URA - Computer` templates | — | ✓ |
| `*- Tier Model Template Tier 0/1 Servers Account Restrictions - Override - Deny *` | Batch · Net · RDS · Svc ¹ | ✓ |

¹ This is the combined set across the eight Override templates. Each individual template (e.g.,
`...Override - Deny Batch`) adds `Tier2EUDDomainJoin` only to its single named right.

> The RDP credential-delegation setting applies to RDP destination hosts (servers/DCs) via the
> shared Account Restrictions baseline. The PAWs and Quarantine GPOs import a different baseline
> and do not receive it.

**`*- Tier 0 DCs Authentication Silo - Computer`** — three additions (this GPO only):

1. **KDC claims / armoring:** Computer Config > Policies > Admin Templates > System > KDC >
   "KDC support for claims, compound authentication and Kerberos armoring" = **Enabled**
2. **RDP / Remote Credential Guard:** Computer Config > Policies > Admin Templates > System >
   Credentials Delegation > "Remote host allows delegation of non-exportable credentials" = **Enabled**
3. **Enable audit log channel (Group Policy Preferences > Registry > New item):**
   - Hive: `HKEY_LOCAL_MACHINE`
   - Key: `SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController`
   - Value name: `Enabled` | Type: `REG_DWORD` | Data: `1`

> Whichever option you choose, never overwrite a production GPO in place — stage the change and
> verify before removing the old configuration.

---

## Related reading

- [Best practices](https://microsoft.github.io/ActiveDirectoryTierModel/best-practices/) — Tier Model design principles and hardening guidance.
- [GPO management guidance](https://microsoft.github.io/ActiveDirectoryTierModel/gpo-management-guidance/) — managing GPOs linked to tier OUs.
- [Tier Model logging](https://microsoft.github.io/ActiveDirectoryTierModel/tiermodel-logging/) — log locations, retention, and event sources.
- [Sentinel monitoring](https://microsoft.github.io/ActiveDirectoryTierModel/sentinel-monitoring/) — SIEM integration and alert rules.
