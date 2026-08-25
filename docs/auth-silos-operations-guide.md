# Authentication Policy Silos — Operations Guide

> **⚠ DRAFT — Pending lab validation and automation**
>
> This guide documents the correct manual operator process for Authentication Policy Silos in a Tier Model environment. It is authored ahead of the automation build so that administrators can walk through the steps by hand in a lab. All PowerShell examples must be validated against your environment before use in production. Sections marked **\[Lab validation required\]** have not yet been confirmed in a customer environment.

---

## UAT Test-Case Index

Use this table as a lab checklist. Attempt each scenario in the order given; record pass/fail and any event IDs observed. Detail for each case is in the referenced section.

| ID | Scenario | Mode | Expected outcome | See |
|---|---|---|---|---|
| UAT-01 | Tier 0 admin logs on from approved Tier 0 PAW | Both | ✅ Allow | §3a |
| UAT-02 | Tier 1 admin logs on from approved Tier 1 PAW | Both | ✅ Allow | §3a, §2 scope table |
| UAT-03 | Local Device Admin logs on from their enrolled EUD | Both | ✅ Allow | §3d |
| UAT-04 | Tier 2 user reaches SharePoint hosted on a Tier 1 server | Enforce | ✅ Allow — silo only gates TGT source, not service-ticket issuance to a third party | §10 |
| UAT-05 | Tier 0 admin from a **non-tier-model** server (unapproved device) | Audit / Enforce | ⚠️ Event 305 / ❌ Deny (Event 105) | §3e, §9a |
| UAT-06 | Tier 0 admin from a **Tier 1 server** (cross-tier, unapproved for Tier 0) | Enforce | ❌ Deny (Event 105) | §9a |
| UAT-07 | Local Device Admin credentials used from a PAW or server (not their EUD) | Enforce | ❌ Deny (Event 105) | §9a |
| UAT-08 | New Tier 0 server joins domain; siloed admin logs on **before** approved-device-group add | Audit / Enforce | ⚠️ Event 305 / ❌ Deny | §3e |
| UAT-09 | Same device **after** approved-group add + replication + reboot | Enforce | ✅ Allow | §3e |
| UAT-10 | Automated Tier 1 build via `svc-t1srvdomainjoin`, silo in **Audit** | Audit | ✅ Domain join succeeds; Event 305 logged — informs exemption decision | §3e |
| UAT-11 | `svc-t1srvdomainjoin` siloed + enforced, build host **not** in approved-device group | Enforce | ❌ Join fails — proves exemption need | §3e |
| UAT-12 | `svc-t2euddomainjoin` (planned) — automated EUD provisioning | Audit | ✅ Join succeeds; Event 305 logged — same pattern as UAT-10 | §3e |
| UAT-13 | Audit → Enforce cutover, all G1–G12 gates passed | — | ✅ Gated flip with per-DC verification and fresh-TGT pilot test | §4 |
| UAT-14 | Exempt domain-join service account authenticates from non-approved device | Enforce | ✅ Allow; success events (4768/4624) logged; no 105 | §6 |
| UAT-15 | RID-500 break-glass — lockout recovery drill | Enforce | ✅ RID-500 authenticates; reverts enforcement; siloed admins recover | §4, §9 |

---

## Contents

1. [Overview — What Is an Authentication Policy Silo?](#1-overview)
2. [How the Tier Model Silo Set Is Structured](#2-silo-structure)
3. [Scenario Walkthroughs](#3-scenario-walkthroughs)
   - [3a. Onboard a new Tier 0 user](#3a-onboard-a-new-tier-0-user)
   - [3b. Onboard a new Tier 0 member server](#3b-onboard-a-new-tier-0-member-server)
   - [3c. Onboard a new Tier 0 PAW](#3c-onboard-a-new-tier-0-paw)
   - [3d. Onboard a Local Device Admin to the Tier 2 EUD silo](#3d-onboard-a-local-device-admin-tier-2-eud)
   - [3e. Domain-join scenarios — interactive and automated](#3e-domain-join-scenarios)
4. [Audit → Enforced Transition](#4-audit-to-enforced-transition)
5. [Daily Maintenance and Day-2 Operations](#5-daily-maintenance)
6. [Exclusions and Exemptions](#6-exclusions-and-exemptions)
7. [Lifecycle — Joiners, Movers, Leavers](#7-lifecycle)
8. [Event IDs and Monitoring](#8-event-ids-and-monitoring)
9. [Negative Testing — Prove Denials Work](#9a-negative-testing)
10. [Troubleshooting](#9-troubleshooting)
11. [Limitations — What Silos Do Not Protect](#10-limitations)
12. [Related Reading](#11-related-reading)

---

## 1. Overview

### Who this guide is for

This guide is for administrators who are comfortable with basic Active Directory tasks — creating users, working with groups, running PowerShell against AD — but have not worked with Authentication Policy Silos before.

No prior knowledge of SDDL, Kerberos conditional expressions, or Dynamic Access Control is assumed. Every term is explained when first used.

### What an Authentication Policy Silo is

When a Tier 0 administrator's credentials are stolen from a non-approved machine, the attacker can use those credentials from **any** device on the network. Standard Active Directory has no way to say "this account may only be used from these specific computers."

**Authentication Policy Silos** close that gap. Here is the precise guarantee, stated narrowly:

> Once effective enforcement and FAST/armoring prerequisites are proven on all relevant DCs and clients, **covered Kerberos AS (TGT) requests for the scoped account are denied when the source-device condition does not match**. The account cannot obtain a new TGT from a non-approved device.

This is a KDC-side control. It evaluates one decision point — the Kerberos AS exchange — and nothing else. It does **not** block every possible use of the credential. In particular: NTLM paths are not protected by this restriction; cached/offline sign-in is not affected; already-issued TGTs remain valid until they expire; LDAP simple bind is not evaluated by this mechanism \[Lab validation required\]; and Entra/cloud authentication never reaches a DC. See Section 11 for the full list.

**Authentication vs authorization vs use.** Silos restrict where a covered domain principal obtains a Kerberos ticket. They do **not** control logon type (interactive vs RDP vs service — that is the Account Restrictions GPO), local rights on the target host (that is local group/LAPS), or what the account can do in AD after logon (that is AD ACLs and RBAC). A successful silo-approved TGT does not mean the account was used safely — only that one covered authentication decision passed.

Here is how the pieces fit together:

| Object | What it is | Plain-language role |
|---|---|---|
| **Authentication Policy Silo** (`T0-Silo`) | An Active Directory object that groups your Tier 0 accounts (users, computers, service accounts) together and links them to policies | The container — "these accounts belong to this silo" |
| **Authentication Policy** (`T0-UserPolicy`) | An AD object that carries the actual restrictions: which devices the user may authenticate from, and how long their Kerberos ticket lasts | The rulebook — "from only these devices, for only this long" |
| **Approved-Device Group** (`T0-ApprovedDevices`) | An ordinary AD security group whose members are the computer accounts that are permitted to be authentication origin points | The allow list — "these machines are approved" |

The restriction is enforced by **Domain Controllers** at the moment a Kerberos AS exchange (ticket request) occurs. It is a DC-side control, not something installed on workstations.

### Prerequisites — confirm these before starting

The Tier Model already handles most of these. Your job is to **verify**, not create.

| Prerequisite | Minimum requirement | How to verify |
|---|---|---|
| Domain Functional Level | Windows Server 2012 R2 or later | `Get-ADDomain \| Select-Object DomainMode` |
| Kerberos armoring (FAST) — KDC side | GPO "KDC support for claims, compound authentication and Kerberos armoring" set to **Always provide claims** on the Domain Controllers OU | Open GPMC → domain → Domain Controllers OU → find the Tier 0 Account Restrictions GPO → Computer Config → Policies → Admin Templates → System → KDC |
| Kerberos armoring — client side | GPO "Kerberos client support for claims, compound authentication and Kerberos armoring" **Enabled** on PAW/jump-host OUs | Check the Account Restrictions GPO for your Tier 0 computer OU |
| PAW or jump-host devices | At least one hardened admin workstation that can be your first approved device | Confirm computer objects exist in the correct Tier 0 OU |
| Break-glass account | The built-in domain **Administrator** (RID-500) — never to be placed in any silo | Confirm it exists and has a known, secured password |
| Active Directory PowerShell module | Available on your management workstation | `Get-Module -Name ActiveDirectory -ListAvailable` |

> **Why Kerberos armoring matters:** `AllowedToAuthenticateFrom` (the device restriction) works by reading the computer identity from an "armored" Kerberos ticket request. Without armoring, the DC cannot see the device identity and the restriction cannot be evaluated. The Tier Model GPOs deploy this for you; you are confirming it is active.

---

## 2. Silo Structure

### All-tier scope — what gets siloed and what does not

The Tier Model deploys **four silos**. The general domain user and computer population is intentionally **not** siloed — silos are a privileged-accounts-only control.

| Silo | Member accounts (user + service) | Member computers | Approved origin devices (`Member of any`) |
|---|---|---|---|
| **Tier 0 Admin** (`T0-Silo`) | Tier 0 user accounts, Tier 0 service accounts | DCs, RODCs, Tier 0 servers, Tier 0 PAWs | DCs · RODCs · Tier 0 servers · Tier 0 PAWs |
| **Tier 1 Admin** (`T1-Silo`) | Tier 1 user accounts, Tier 1 service accounts | Tier 1 servers, Tier 1 PAWs | Tier 1 servers · Tier 1 PAWs |
| **Tier 2 Admin** (`T2-Silo`) | Tier 2 user accounts, Tier 2 service accounts | Tier 2 PAWs | Tier 2 PAWs |
| **Tier 2 EUD** (`T2-EUD-Silo`) | Local Device Admin accounts (EUD local-admin group) | Tier 2 EUD devices | Tier 2 EUD devices |

**Why there is no 5th silo for "everyone else":** Broad user-population siloing brings high scale, high device churn, privacy/telemetry noise, and weak proportionality of protection to cost. The general `Domain Users` / `Domain Computers` population is intentionally outside silo scope. The value of silos comes from the small, stable approved-device groups that privileged accounts require.

**Why the Tier 2 EUD silo exists:** Local Device Admins (the EUD local-admin accounts provisioned on end-user devices) are privileged on those devices and should be restricted to authenticate only from the devices they administer. This closes the "local admin credential reuse across EUDs" attack path.

### The objects and how they relate

A Tier 0 silo deployment creates the following objects. If you are working with an existing deployment, you can find these in Active Directory Administrative Center (ADAC) under **Authentication** → **Authentication Policies** and **Authentication Policy Silos**.

```
T0-Silo (Authentication Policy Silo)
  ├── UserAuthenticationPolicy  →  T0-UserPolicy
  ├── ComputerAuthenticationPolicy  →  (optional, Config B only)
  └── Permitted accounts  →  individual user/computer accounts

T0-UserPolicy (Authentication Policy)
  ├── UserAllowedToAuthenticateFrom  →  SDDL referencing T0-ApprovedDevices
  ├── UserTGTLifetimeMins  →  240 (4 hours, non-renewable)
  └── Enforce  →  false (audit) until you complete the gates in Section 4

T0-ApprovedDevices (Global or Universal Security Group)
  └── Members: PAW01$, PAW02$, (and any console-fallback machines)
```

### The Origination Device Rule

This rule tells you what goes in the approved-device group. The group must contain the computer from which the **Kerberos AS exchange** (the credential presentation that requests the TGT) occurs — which is **not always the machine the admin is aiming at**.

| How the admin connects | Which machine presents the TGT request | What goes in the group |
|---|---|---|
| Types credentials on a PAW (interactive logon) | The PAW | The PAW's computer account (`PAW01$`) |
| RDP to a DC with NLA enabled (default since Vista) | The **admin's workstation** — credentials are validated at the client before RDP connects | The **workstation's** computer account |
| Types credentials at a DC or server console (interactive, VMConnect basic mode) | The DC or server itself | The **DC/server's** computer account |
| PAM/privileged access broker initiates a session with vaulted credentials | The **broker server** | The **broker server's** computer account |

**Practical consequence:** If you use NLA for RDP administration (which you should), your PAWs go in the group — not the DCs and servers you manage. If you also need console fallback (VMConnect basic mode), the target VMs must also be in the group.

### The SDDL explained (read once; use the template)

The device restriction is expressed as a security descriptor string (SDDL). You do not need to write SDDL from scratch — the template below is correct for a single approved-device group. Read this section so you understand what the string means; then use the template.

```
O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of {SID(S-1-5-21-DOMAIN-GROUPRID)}))
```

Breaking it down:

| Part | Meaning |
|---|---|
| `O:SY` / `G:SY` | Owner and group = SYSTEM (standard for policy objects) |
| `XA` | Callback access-allowed ACE — the condition does the filtering |
| `OICI` | Inherit to child objects |
| `CR` | Control access right |
| `WD` | "World" (Everyone) — every AS request is evaluated; the condition below decides |
| `Member_of {SID(...)}` | The device presenting the TGT request must be a member of the named group |

> **⚠ Critical: AND vs OR logic**
>
> `Member_of {SID(A), SID(B)}` means the device must be in **both** groups — an AND condition. This is almost never what you want and will lock out anyone whose device is in only one group.
>
> If you have multiple approved-device groups (e.g., PAWs **and** jump servers), use:
> ```
> Member_of {SID(A)} || Member_of {SID(B)}
> ```
> In ADAC's condition builder, this is the **"Member of any"** option. If you leave it on **"Member of each"** (the default), you get AND logic. Change it to **"Member of any"** every time you add more than one group.

### Audit mode vs enforced mode

| Mode | What happens | When to use |
|---|---|---|
| **Audit** (`Enforce = $false`) | The DC evaluates the restriction, logs Event 305 if the device would have failed, but allows the authentication anyway | Start here. Always. Stay here until all pre-enforcement gates pass. |
| **Enforced** (`Enforce = $true`) | The DC denies the TGT request and logs Event 105 if the device fails the restriction | Only after all gates in Section 4 have passed |

**Audit mode blocks nothing.** A deployed silo in audit mode provides monitoring data but zero protection. Do not communicate to stakeholders that you have "deployed" a silo until it is enforced — or be explicit that it is in audit mode only.

---

## 3. Scenario Walkthroughs

These walkthroughs assume the silo, policy, and approved-device group **already exist** — a common day-2 situation. If you are building the infrastructure from scratch, complete the build sequence in Appendix A first, then return here.

In all examples, replace the following placeholders:

| Placeholder | Replace with |
|---|---|
| `CONTOSO` | Your domain NetBIOS name |
| `DC01`, `DC02` | Your domain controller names |
| `T0-Silo` | Your Tier 0 silo object name |
| `T0-UserPolicy` | Your Tier 0 user authentication policy name |
| `T0-ApprovedDevices` | Your approved-device group name |
| `t0-admin-newuser` | The sAMAccountName of the new account |
| `PAWNN` | The computer name (without `$`) of the new PAW or server |

---

### 3a. Onboard a New Tier 0 User

**What this does:** Registers a new Tier 0 administrator in the silo so that their account is protected by the `AllowedToAuthenticateFrom` restriction.

**Time required:** 5–10 minutes plus replication wait.

> **If this is a brownfield environment** (the customer scripts may have run previously), run the preflight in Step 0 below before proceeding. Existing direct-policy assignments can conflict with silo assignments in ways whose precedence is undocumented.

#### Step 0 — Brownfield preflight: check for existing assignments

```powershell
# Check BOTH assignment attributes before proceeding
Get-ADUser "t0-admin-newuser" `
    -Properties msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo
```

**What to look for:**

- Both attributes **empty:** clean — proceed to Step 1.
- `msDS-AssignedAuthNPolicy` is **set** (direct policy assignment): **STOP.** Do not assign a silo on top of a direct policy. The precedence between a direct policy and a silo assignment is undocumented \[Lab validation required\]. Treat this as a migration: document the existing direct assignment, plan a staged removal in coordination with the owner, and only assign the silo after the direct policy is cleared and verified.
- `msDS-AssignedAuthNPolicySilo` is **already set** to a different silo: **STOP.** An account can belong to only one silo. Remove the existing assignment first, then enroll in the new silo.

#### Step 1 — Confirm the account exists in the correct OU

Open Active Directory Users and Computers (ADUC). Verify the account is in your Tier 0 Users OU.

```powershell
# Verify account location
Get-ADUser -Identity "t0-admin-newuser" -Properties DistinguishedName |
    Select-Object SamAccountName, DistinguishedName
```

**Why:** The Tier Model's Account Restrictions GPOs apply based on OU placement. The account must be in the Tier 0 OU before the silo assignment is meaningful.

**Verify:** The `DistinguishedName` contains your Tier 0 Users OU path.

#### Step 2 — Confirm the user's PAW is already in the approved-device group

```powershell
# List current members of the approved-device group
Get-ADGroupMember -Identity "T0-ApprovedDevices" |
    Select-Object Name, objectClass
```

**Why:** If you assign the user to the silo before their PAW is in the device group, they will see Event 305 (audit) — or be locked out (enforce). Confirm the device is in the group **first**.

**Verify:** You see the PAW computer account (`PAWNN$`) in the output. If not, see **Section 3c** to add the PAW first.

#### Step 3 — Confirm device-group replication is complete on all DCs

```powershell
# Check group membership on each DC — run once per DC
Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC01" |
    Select-Object Name, objectClass

Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC02" |
    Select-Object Name, objectClass
```

**Why:** The DC that services the user's first TGT request may not be the same DC you just wrote to. If the group membership has not replicated, the new user's TGT request will appear to fail even if you did everything correctly.

**Verify:** Both DCs show the same members. If they differ, wait for AD replication (typically 15 seconds intrasite) or force with `repadmin /syncall DC01 /AdeP`.

> **⚠ Replication is load-bearing.** Do not proceed to Steps 4–5 until every relevant DC shows the correct group membership. Under audit mode, a replication gap shows up as spurious Event 305 events. Under enforced mode, it is a lockout.

#### Step 4 — Grant the account permission to join the silo

```powershell
# Grant silo access (this allows the account to be assigned to the silo)
Grant-ADAuthenticationPolicySiloAccess `
    -Identity "T0-Silo" `
    -Account "t0-admin-newuser"
```

**Why:** Before an account can be assigned to a silo, it must be on the silo's permitted-accounts list. This step is separate from assignment. Think of it as "add to the silo's guest list."

**Verify:**

```powershell
# Confirm the account appears in the silo's permitted accounts
Get-ADAuthenticationPolicySilo -Identity "T0-Silo" `
    -Properties msDS-AuthNPolicySiloMembers |
    Select-Object -ExpandProperty msDS-AuthNPolicySiloMembers
```

The user's Distinguished Name should appear in the output.

> **⚠ Common trap:** `Grant-ADAuthenticationPolicySiloAccess` only grants access — it does **not** assign the silo. If you skip this step and go directly to Step 5, the assignment will fail.

#### Step 5 — Assign the silo to the account

```powershell
# Assign the account to the silo
Set-ADAccountAuthenticationPolicySilo `
    -Identity "t0-admin-newuser" `
    -AuthenticationPolicySilo "T0-Silo"
```

**Why:** This writes the `msDS-AssignedAuthNPolicySilo` attribute on the user object, telling the DC which silo policies to apply when this account requests a TGT.

> **⚠ Critical: silo vs direct policy — do not mix**
>
> `Set-ADAccountAuthenticationPolicySilo` with `-AuthenticationPolicySilo` assigns the **silo** (correct).
>
> `Set-ADUser -AuthenticationPolicy` assigns a **direct policy** without a silo — this is a different mechanism with different (and undocumented) precedence behavior if both are set. Do **not** set both on the same account.

**Verify:**

```powershell
# Confirm the silo attribute is set on the user
Get-ADUser "t0-admin-newuser" `
    -Properties msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicySilo
```

The `msDS-AssignedAuthNPolicySilo` field should contain the Distinguished Name of `T0-Silo`.

#### Step 6 — (Separately-approved hardening) AccountNotDelegated

`AccountNotDelegated = $true` prevents the account from being used in Kerberos delegation chains. This is recommended for all Tier 0 accounts, but it takes effect **immediately and independently** of whether the silo is in audit or enforce mode. Do not include it as part of a silo-enrollment change window unless it has been separately reviewed for delegation-dependent workflows.

```powershell
# Apply only after separate review and approval for this account
Set-ADAccountControl -Identity "t0-admin-newuser" -AccountNotDelegated $true

# Verify
Get-ADUser "t0-admin-newuser" -Properties AccountNotDelegated |
    Select-Object SamAccountName, AccountNotDelegated
```

#### Step 7 — Verify audit events are flowing

Ask the new admin to attempt a normal logon from their PAW. Then check for audit events:

```powershell
# Check for silo-related events on each DC
# Run this on each DC or from a remote session targeting each DC
Get-WinEvent -LogName `
    "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" `
    -MaxEvents 50 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -like "*t0-admin-newuser*" }
```

**What to look for:**

- **No events (or Event 300-series with the correct device):** The admin authenticated from the approved device. 
- **Event 305 ("would-be-denied TGT"):** The admin authenticated from a device that is **not** in the approved-device group. Find out which device they used; add it if correct, or investigate if unexpected.

> **If the Authentication Policy Failures channel returns no results, the channel may be disabled.** See Section 8 for how to enable it.

**What breaks if you forget a step:**

| Skipped step | Symptom | Resolution |
|---|---|---|
| Step 2 (PAW not in device group) | Event 305 on every logon from the PAW (audit) or full lockout (enforced) | Add the PAW — see Section 3c |
| Step 3 (replication) | Intermittent Event 305 depending on which DC services the request | Wait for or force replication |
| Step 4 (grant access) | `Set-ADAccountAuthenticationPolicySilo` fails with an access error | Run Step 4 first |
| Step 5 (assignment) | User account not protected; no events generated | Run Step 5 |

---

### 3b. Onboard a New Tier 0 Member Server

**What this does:** Adds a new Tier 0 member server to the approved-device group so that administrators can log on to it interactively (console) if needed as a fallback, and so the server is tracked as part of the Tier 0 boundary.

> **When this is needed:** If your administrators connect to this server **only** via RDP with NLA or PowerShell remoting (the recommended approach), the server itself does **not** need to be in the approved-device group — because with NLA, the PAW is the origination device. Add the server to `T0-ApprovedDevices` only if:
> - Administrators may type credentials at the server's local logon screen (console or VMConnect basic mode), **or**
> - You are configuring `AllowedToAuthenticateTo` (Config B) and intend to enroll the server in the silo.

**Time required:** 5 minutes plus replication wait.

#### Step 1 — Confirm the computer account exists in the Tier 0 servers OU

```powershell
Get-ADComputer -Identity "NEWSRV01" -Properties DistinguishedName |
    Select-Object Name, DistinguishedName
```

**Verify:** The `DistinguishedName` shows the account is in your Tier 0 Servers OU.

#### Step 2 — Add the server to the approved-device group

```powershell
# Note the trailing $ — computer accounts in AD have a $ suffix
Add-ADGroupMember -Identity "T0-ApprovedDevices" -Members "NEWSRV01$"
```

**Why:** The SDDL expression `Member_of {SID(T0-ApprovedDevices)}` will now evaluate to true when someone presents a TGT request from this server.

**Verify:**

```powershell
Get-ADGroupMember -Identity "T0-ApprovedDevices" |
    Where-Object { $_.Name -eq "NEWSRV01" }
```

#### Step 3 — Verify replication on all DCs

```powershell
# Repeat for each DC
Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC01" |
    Select-Object Name, objectClass

Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC02" |
    Select-Object Name, objectClass
```

**Verify:** `NEWSRV01` appears on all DCs. Force replication if needed: `repadmin /syncall DC01 /AdeP`.

#### Step 4 — Confirm the Kerberos armoring GPO applies to the server

The server needs the client-side Kerberos armoring GPO so it can present armored TGT requests.

```powershell
# Run on the server itself (or via Invoke-Command)
Invoke-Command -ComputerName NEWSRV01 -ScriptBlock {
    gpresult /r /scope computer
}
```

Look for the Tier 0 Account Restrictions GPO (or whichever GPO carries Kerberos client armoring) in the Applied Computer GPOs list. If missing, check the OU placement and re-run `gpupdate /force` on the server, then reboot. **Kerberos armoring settings take effect at boot.**

#### Step 5 — Test using a console (local) logon

**Test transport matters.** This walkthrough adds the server for **console/interactive logon** — the path where the server's own Kerberos stack sends the AS request. To validate that origination device path, the test must use a local/interactive logon at the server, **not RDP with NLA** (which would put the Kerberos AS exchange back on the admin's PAW).

Use VMConnect basic session mode, physical console, or an out-of-band management console to log in interactively at the server. Check the DCs for Event 305 (audit) — you should see a successful logon event, and if the policy is in audit mode and the server is correctly enrolled, there should be no 305 for this server.

> **NLA/CredSSP RDP and second-hop delegation** are separate scenarios with additional considerations not fully covered in this guide \[Lab validation required\]. For remote-admin-only scenarios (where the server is a destination, not an origination device), see Section 2 (Origination Device Rule) — the server may not need to be in the approved-device group at all.

---

### 3c. Onboard a New Tier 0 PAW

**What this does:** Registers a new PAW as an approved origination device so that Tier 0 admins using it can obtain TGTs.

**Time required:** 10–15 minutes plus replication wait and reboot.

> **This is the most common day-2 operation.** Every time a new PAW is built or a PAW is rebuilt, it must be added to `T0-ApprovedDevices` before any Tier 0 account can authenticate from it.

#### Step 1 — Domain-join and OU placement

The PAW must be a domain-joined Windows machine with its computer account in the Tier 0 PAWs OU (or equivalent). Confirm:

```powershell
Get-ADComputer -Identity "PAW03" -Properties DistinguishedName |
    Select-Object Name, DistinguishedName
```

**Verify:** The OU path is the correct Tier 0 PAW OU, not the default `Computers` container.

#### Step 2 — Apply the Kerberos armoring GPO and reboot

The PAW must have the Kerberos client armoring GPO applied **and the machine rebooted** before the silo restriction can be satisfied. This GPO is already linked to your Tier 0 computer OUs by the Tier Model.

```powershell
# On the PAW
gpupdate /force
# Then reboot the PAW
Restart-Computer -ComputerName PAW03 -Force
```

**Why the reboot is required:** The Kerberos subsystem loads its configuration at startup. A `gpupdate` refreshes the policy files, but the armoring behavior is not active until the next boot.

> **⚠ If you add the PAW to the group before the GPO applies and the machine reboots, the DC may not be able to evaluate the device condition. The result depends on GPO state and whether "Fail unarmored authentication requests" is enabled. In audit mode this shows Event 305; in enforce mode this is a lockout.**

#### Step 3 — Add the PAW to the approved-device group

```powershell
Add-ADGroupMember -Identity "T0-ApprovedDevices" -Members "PAW03$"
```

#### Step 4 — Verify replication on all DCs

```powershell
Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC01" | Select-Object Name
Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC02" | Select-Object Name
```

**Verify:** `PAW03` appears on all DCs.

#### Step 5 — Confirm GPO application after reboot

```powershell
Invoke-Command -ComputerName PAW03 -ScriptBlock {
    gpresult /r /scope computer
}
```

Look for the Account Restrictions GPO (or the GPO carrying Kerberos client armoring) in the Applied Computer GPOs list.

#### Step 6 — Test an admin logon from the new PAW

Ask a Tier 0 admin to log on from PAW03 and open a PowerShell window. Then check the DCs for events:

```powershell
# Check on each DC
Get-WinEvent -LogName `
    "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" `
    -MaxEvents 20 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -like "*PAW03*" }
```

**What you want to see:** No events, or Event 305 is **absent** for this admin/PAW combination. Event 305 present means the device was not recognized as approved — recheck group membership and replication.

---

### 3d. Onboard a Local Device Admin to the Tier 2 EUD Silo

**What this does:** Registers a Local Device Admin account in the Tier 2 EUD silo so that the account can only obtain TGTs from the EUD devices it is authorized to administer. This closes the credential-reuse path where a compromised local admin credential could be used from any machine.

**When this applies:** Tier 2 EUD silo enrollment is for the dedicated local-admin accounts provisioned on end-user devices. Do not enroll general Tier 2 user accounts here — only accounts whose role is local device administration.

**Placeholders for this walkthrough:**

| Placeholder | Replace with |
|---|---|
| `T2-EUD-Silo` | Your Tier 2 EUD silo object name |
| `T2-EUD-UserPolicy` | Your Tier 2 EUD user authentication policy name |
| `T2-ApprovedEUDs` | Your Tier 2 EUD approved-device group name |
| `t2-localadmin-newuser` | The sAMAccountName of the Local Device Admin account |
| `EUD01` | The computer name (without `$`) of the EUD device |

#### Step 0 — Brownfield preflight

```powershell
Get-ADUser "t2-localadmin-newuser" `
    -Properties msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo
```

Both attributes must be empty before proceeding. See §3a Step 0 if either is set.

#### Step 1 — Confirm the EUD is in the approved-device group

```powershell
Get-ADGroupMember -Identity "T2-ApprovedEUDs" |
    Where-Object { $_.Name -eq "EUD01" }
```

If `EUD01$` is not present, add it:

```powershell
Add-ADGroupMember -Identity "T2-ApprovedEUDs" -Members "EUD01$"
```

Verify replication on all DCs before proceeding.

#### Step 2 — Grant silo access

```powershell
Grant-ADAuthenticationPolicySiloAccess `
    -Identity "T2-EUD-Silo" `
    -Account "t2-localadmin-newuser"
```

#### Step 3 — Assign the silo

```powershell
Set-ADAccountAuthenticationPolicySilo `
    -Identity "t2-localadmin-newuser" `
    -AuthenticationPolicySilo "T2-EUD-Silo"

# Verify
Get-ADUser "t2-localadmin-newuser" `
    -Properties msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicySilo
```

#### Step 4 — Test

From the target EUD (`EUD01`), log on interactively as the Local Device Admin account. Verify no Event 305 appears on the DCs. Then try to log on with the same account from a different device — in audit mode you should see Event 305; in enforce mode the logon is denied.

---

### 3e. Domain-Join Scenarios

Domain joining a device involves a TGT request from the machine that performs the join. If a domain-join service account is enrolled in a silo, the join host must be in the approved-device group. This section covers the standard patterns.

#### Scenario A — Interactive admin joins a fresh device

A Tier 0 or Tier 1 admin interactively joins a new device to the domain. This is the correct procedure when no automated provisioning pipeline is available.

**Step 1 — Join to the Staging OU.**
Configure the domain join to place the computer account in the appropriate Staging OU (e.g., `Tier0-PAW-Staging` or `Tier1-Server-Staging`), not directly in a production OU. Staging OUs do not have the Kerberos armoring GPO linked yet.

**Step 2 — Move to the production OU.**
After the join completes, move the computer account to the correct production OU in ADUC or with PowerShell:

```powershell
Move-ADObject `
    -Identity "CN=NEWPAW04,OU=Tier0-PAW-Staging,DC=CONTOSO,DC=COM" `
    -TargetPath "OU=Tier0-PAWs,DC=CONTOSO,DC=COM"
```

**Step 3 — Add to the approved-device group.**

```powershell
Add-ADGroupMember -Identity "T0-ApprovedDevices" -Members "NEWPAW04$"
```

Verify replication on all DCs.

**Step 4 — Reboot the device.**
The Kerberos armoring GPO (now linked via the production OU) takes effect at the next boot.

**Step 5 — Test.**
Only **after** Steps 2–4 and replication should a siloed admin attempt to log on from this device. In audit mode, logging on before the device is added shows Event 305 (UAT-08). After Steps 2–4, no 305 should appear (UAT-09).

> **The chicken-and-egg explained:** The device must be in the approved-device group **and** have the armoring GPO applied **before** a siloed admin can authenticate from it. Joining the domain is done by a separate non-siloed mechanism (see Scenario B/C below). The siloed admin is never the one joining; they log on after the device is fully prepared.

#### Scenario B — Automated join: existing `svc-pawdomainjoin` and `svc-t1srvdomainjoin`

The Tier Model includes two domain-join service accounts:

| Account | Scoped to | Delegation | Default state |
|---|---|---|---|
| `svc-pawdomainjoin` | PAW Staging OU | Create computer objects in Staging OU only | Disabled by default; enabled only during provisioning windows |
| `svc-t1srvdomainjoin` | Tier 1 Server Staging OU | Create computer objects in Staging OU only | Disabled by default; enabled only during provisioning windows |

These accounts authenticate from the build/orchestration host. Because the build host is often ephemeral and not in any production approved-device group, **these service accounts should be exempted from silos** — documented as structural exemptions with the compensating controls below.

**Why the exemption is correct, not lazy:**
- The domain-join happens before the device has GPO applied or is in the approved-device group — there is no approved device to originate from.
- The accounts have narrowly scoped delegation (Staging OU only) and are disabled except during provisioning.
- Enabling them only during provisioning windows limits the exposure window.

**Compensating controls for these exempt accounts:**

| Control | Description |
|---|---|
| Enabled/disabled lifecycle | Disabled except during active provisioning. Change-ticket required to enable. |
| OU-scoped delegation | Can only create objects in the designated Staging OU. |
| Staging OU | Computer objects land in a Staging OU where they receive no production GPOs until moved. |
| Enhanced monitoring | Alert on any use of these accounts outside provisioning windows. |
| Named owner | A specific operations owner responsible for the accounts and provisioning process. |

**UAT-10:** Run with silo in **audit** mode → join succeeds; Event 305 logged → informs exemption decision.
**UAT-11:** Silo in **enforce** mode + build host not in approved group → join fails immediately → proves exemption is needed.

#### Scenario C — Planned: `svc-t2euddomainjoin`

A `svc-t2euddomainjoin` service account for automated EUD provisioning is a planned configuration addition. It follows the same pattern as `svc-t1srvdomainjoin` but targets the Tier 2 EUD Staging OU with a `Tier2EUDDomainJoin` delegation group. **This is not yet implemented** — it is documented here as the planned design so that EUD provisioning automation has a defined target when the Tier 2 EUD silo is deployed.

**UAT-12:** Once implemented, test in audit mode — EUD join succeeds; Event 305 logged.

---

## 4. Audit → Enforced Transition

> **⚠ This section contains the highest-risk steps in this guide. Read it completely before executing any command.**
>
> **Enforcing a misconfigured silo can lock out every Tier 0 administrator simultaneously.** The built-in domain Administrator (RID-500) is platform-exempt from Authentication Policy evaluation and cannot be locked out by silos — but all other Tier 0 accounts can be. Treat this transition as a change window with a tested rollback plan.

### Pre-enforcement gates — all applicable gates must PASS before flipping Enforce = true

Work through every applicable gate. Mark each as **PASS**, **FAIL**, or **N/A with justification**. A single unresolved FAIL is a **STOP** — do not enforce.

| Gate | What to verify | Evidence required | Verdict |
|---|---|---|---|
| **G1 — Mechanics readiness** | DFL ≥ 2012 R2; using silo model (not direct-policy-only); no brownfield direct assignments remaining; policy-vs-silo Enforce composition confirmed \[Lab validation required\] | `Get-ADDomain \| Select-Object DomainMode`; review of §3a Step 0 preflight results | PASS / FAIL / STOP |
| **G2 — Correct SDDL** | OR vs AND logic verified; positive test from an approved device (no 305); negative test from a non-approved device (305 logged); peer review of SDDL string | Event 305 audit results from a deliberately non-approved device | PASS / FAIL / STOP |
| **G3 — Device group SID verified** | Export the policy SDDL; extract every SID embedded in `UserAllowedToAuthenticateFrom`; compare each SID to `(Get-ADGroup "T0-ApprovedDevices" -Properties SID).SID.Value`; they must match. A deleted-and-recreated group has a new SID while keeping the name — the SDDL silently matches nothing. | SDDL SID = group SID; exported membership per DC matches authoritative inventory | PASS / FAIL / STOP |
| **G4 — Independent recovery tested** | RID-500 break-glass can authenticate from a known emergency device and reach a writable DC; DSRM password is known, documented, and tested; OOB console access to at least one DC is confirmed | Written evidence of successful break-glass drill; DSRM password test record | PASS / FAIL / STOP |
| **G5 — Rollback runbook rehearsed** | Rollback steps (below) tested in lab; both policy AND silo Enforce reverted; per-DC convergence proven; authentication recovered | Lab rollback test evidence covering both objects | PASS / FAIL / STOP |
| **G6 — Replication health** | No replication errors on affected partitions or sites; all writable DCs and relevant RODCs are replicating | `repadmin /replsummary` — zero errors; `repadmin /showrepl` per DC | PASS / FAIL / STOP |
| **G7 — Observability** | Authentication Policy Failures channel **enabled and forwarding** on every DC; test event received in SIEM; audit subcategories and SACL coverage confirmed; ingestion and retention validated | Channel-enable verification from each DC; test 305 event visible in SIEM within expected latency | PASS / FAIL / STOP |
| **G8 — Effective permissions** | Only Tier 0-authorized identities can modify policies, silos, device groups, and prerequisite GPOs | AD ACL review covering the AuthN Policy configuration container, policy objects, silo objects, and device groups | PASS / FAIL / STOP |
| **G9 — Exemption register** | Every exempt account has: named owner, written justification, expiry date or permanent-structural classification, compensating controls, approval | Exemption log present and complete | PASS / FAIL / STOP |
| **G10 — Automation safety** *(applies only if automation writes to silo/device groups)* | Any automated writer is: single-writer or convergence-aware; delta-only; threshold-protected; signed/integrity-controlled; centrally logged; fail-safe on empty/partial results | Automation code review; test-harness zero-write evidence; threshold test | PASS / FAIL / N/A |
| **G11 — Representative audit coverage** | Audit period covers: normal working hours; maintenance windows; monthly/quarterly batch jobs; DR/patching/backup cycles; dormant service workflows; all in-scope NTLM-dependent paths inventoried (RADIUS/NPS, VPN, PTA, AD FS, LDAP simple-bind, RODC-served paths); effective FAST/DAC state confirmed per DC and per client type | Audit period spans the full business cycle; NTLM/LDAP-bind inventory complete and dispositioned | PASS / FAIL / STOP |
| **G12 — Cross-boundary topology** *(applies only if multiple domains or forest trusts exist)* | Same-forest domain pairs: group scope validated (Global groups cannot contain objects from other domains — use Universal for multi-domain device groups); per-domain DFL/DC OS confirmed; account-domain and resource-domain event locality lab-tested. Cross-forest: treated as outside silo coverage until lab-proven. | Per-domain-pair group-scope and event-locality evidence; cross-forest paths explicitly scoped out | PASS / FAIL / N/A |

> **On G11 — "at least one week" is not enough.** A week may miss monthly maintenance jobs, quarterly batch processes, DR drills, or services that only activate at end of quarter. Extend the audit period until every in-scope scheduled workflow has been observed at least once. Documenting the exact workflows covered is part of the evidence.
>
> **On G11 — NTLM and LDAP-bind inventory.** These paths generate **no Event 305** in audit mode. You must actively inventory them: check for RADIUS/NPS authentication (VPN, 802.1x), PTA agents, AD FS servers, applications using LDAP simple bind, and services that fall back to NTLM. For each: decide whether to exempt, migrate, or restrict separately. Do not assume a clean 305 audit window means these paths are safe to enforce.

### Enforce-state clarification — there are two `Enforce` flags

Both the **authentication policy** and the **authentication policy silo** have separate `Enforce` flags. The interaction between them when set differently is \[Lab validation required\] — do not assume one overrides the other.

**Safe practice:** Set and verify **both** flags consistently. The baseline is:
- `T0-UserPolicy.Enforce = $false` (audit) → `T0-UserPolicy.Enforce = $true` (enforced)
- `T0-Silo.Enforce = $false` (audit) → leave in audit mode for the initial rollout; only move to `$true` after lab-validating the combined behavior

During the transition described below, you are flipping the **policy** Enforce flag. Monitor and verify both. Roll back both if issues arise.

### The audit period

Before enforcing, run in audit mode for **at least one week** — ideally two weeks spanning a maintenance window. During this period:

1. Check Event 305 on all DCs daily.
2. Triage every 305 event: is this a legitimate admin device that is missing from the group, or is it expected noise?
3. Dispose of every 305 event: either fix the device membership, or document why it is expected.

```powershell
# Pull all 305 events from one DC — run against each DC
Get-WinEvent -LogName `
    "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" |
    Where-Object { $_.Id -eq 305 } |
    Select-Object TimeCreated, Message |
    Sort-Object TimeCreated
```

**A clean audit period means:** no undisposed Event 305 events. It does **not** mean enforcement is completely safe — NTLM paths and LDAP simple-bind paths do not generate 305 events. See Section 10 for what audit mode cannot see.

### Enforcing — step by step

Once all applicable gates pass:

**Step 1 — Export the current state as your rollback baseline:**

```powershell
# Export the policy SDDL and Enforce state
Get-ADAuthenticationPolicy -Identity "T0-UserPolicy" |
    Select-Object Name, UserAllowedToAuthenticateFrom, Enforce, UserTGTLifetimeMins |
    Export-Csv -Path ".\T0-Policy-PreEnforcement-$(Get-Date -Format yyyyMMdd).csv" -NoTypeInformation

# Export the silo state
Get-ADAuthenticationPolicySilo -Identity "T0-Silo" |
    Select-Object Name, Enforce, UserAuthenticationPolicy |
    Export-Csv -Path ".\T0-Silo-PreEnforcement-$(Get-Date -Format yyyyMMdd).csv" -NoTypeInformation

# Export device group membership
Get-ADGroupMember -Identity "T0-ApprovedDevices" |
    Export-Csv -Path ".\T0-ApprovedDevices-PreEnforcement-$(Get-Date -Format yyyyMMdd).csv" -NoTypeInformation
```

**Step 2 — Confirm the break-glass (RID-500) account is accessible:**

Construct the RID-500 SID from the domain SID — do not use wildcard matching on `objectSid`.

```powershell
# Build the RID-500 SID from the domain SID
$DomainSID = (Get-ADDomain -Server "DC01").DomainSID.Value
$RID500SID = "$DomainSID-500"

# Retrieve the built-in Administrator by its SID
$BuiltinAdmin = Get-ADUser -Identity $RID500SID `
    -Properties msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo
$BuiltinAdmin | Select-Object SamAccountName, msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo
```

Both silo-related attributes must be **empty**. If either is set:

```powershell
# Remove direct policy assignment if accidentally set
Set-ADUser -Identity $BuiltinAdmin.SamAccountName `
    -Clear msDS-AuthNPolicyBL

# Remove silo assignment if accidentally set
Set-ADAccountAuthenticationPolicySilo `
    -Identity $BuiltinAdmin.SamAccountName `
    -AuthenticationPolicySilo $null

# Verify both are cleared
Get-ADUser -Identity $RID500SID `
    -Properties msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo
```

> **Important:** RID-500 is exempt from Authentication Policy evaluation by the Windows platform — meaning it cannot be locked out by silo enforcement — but it is still subject to User Rights Assignment, account-state (disabled/locked), network reachability, firewall rules, and smartcard requirements. "RID-500 is exempt" means the Kerberos silo check does not apply; it does not mean the account can bypass every other access control.

**Step 3 — Record the current Enforce state of BOTH objects, then enable enforcement:**

```powershell
# Record before state — BOTH objects
Write-Host "=== BEFORE ENFORCEMENT ==="
Get-ADAuthenticationPolicy -Identity "T0-UserPolicy" -Server "DC01" |
    Select-Object Name, Enforce
Get-ADAuthenticationPolicySilo -Identity "T0-Silo" -Server "DC01" |
    Select-Object Name, Enforce

# Enable enforcement on the user authentication policy
# (Silo Enforce remains $false for initial rollout — review if flipping both)
Set-ADAuthenticationPolicy -Identity "T0-UserPolicy" -Enforce $true
```

> **⚠ Once this command runs, any Tier 0 account assigned to this policy whose authentication device is not in `T0-ApprovedDevices` will be denied a new TGT at their next Kerberos AS exchange.**
>
> Do **not** claim there is a "~240 minute window" before enforcement is felt. Existing TGTs may have lifetimes set by domain policy rather than the auth policy, and application sessions may outlive their TGT. Do not rely on a time window — verify with a controlled fresh-TGT test (Step 5 below).

**Step 4 — Immediately verify BOTH Enforce attributes on all DCs:**

```powershell
# Check on every writable DC
foreach ($dc in @("DC01", "DC02")) {
    Write-Host "=== $dc ==="
    Get-ADAuthenticationPolicy -Identity "T0-UserPolicy" -Server $dc |
        Select-Object Name, Enforce
    Get-ADAuthenticationPolicySilo -Identity "T0-Silo" -Server $dc |
        Select-Object Name, Enforce
}
```

All DCs must show `T0-UserPolicy.Enforce = True`. If any DC shows `False`, check replication: `repadmin /showrepl DC01`. Do not declare enforcement complete until all DCs converge.

**Step 5 — Verify using a dedicated pilot — force a genuinely fresh TGT:**

Do **not** use an existing session for this test — it may reuse a TGT that was obtained before enforcement. Use a dedicated pilot account or pilot device that has no cached tickets.

```powershell
# On the PILOT device (from an interactive logon or a fresh dedicated session):
# Purge all existing Kerberos tickets — ONLY in this pilot session
klist purge

# Then attempt an authentication that requires a new TGT:
# e.g., access a resource that triggers a Kerberos exchange
dir \\DC01\SYSVOL

# Capture what happened:
klist        # Should show a fresh TGT with the policy TGT lifetime
```

Simultaneously, maintain an **independent RID-500 session** (from a separate device) that you did NOT purge, so you can roll back immediately if the pilot test fails.

Check the DC for Event 105 — there must be none for the pilot account from the approved device. If 105 appears, roll back immediately.

**Step 6 — Monitor closely for the first 48 hours:**

Watch for Event 105 events on all DCs. Each one is real user impact — an account is being denied. Investigate each immediately.

### Rolling back enforcement

If something goes wrong, roll back **both** objects:

```powershell
# Disable enforcement on the policy
Set-ADAuthenticationPolicy -Identity "T0-UserPolicy" -Enforce $false

# If the silo Enforce was also enabled, disable it too
Set-ADAuthenticationPolicySilo -Identity "T0-Silo" -Enforce $false

# Verify BOTH on every DC
foreach ($dc in @("DC01", "DC02")) {
    Write-Host "=== $dc ==="
    Get-ADAuthenticationPolicy -Identity "T0-UserPolicy" -Server $dc |
        Select-Object Name, Enforce
    Get-ADAuthenticationPolicySilo -Identity "T0-Silo" -Server $dc |
        Select-Object Name, Enforce
}
```

**Rollback does not take effect instantly** — the change must replicate to every writable DC. Check each DC individually. Until all DCs show `Enforce = False`, some DCs may still be denying authentications.

After verifying rollback on all DCs, use a fresh-TGT test (see Step 5 above with `klist purge` on a pilot account) to confirm that a siloed admin can authenticate again. Then investigate the root cause before re-enforcing.

**If the rollback itself fails:** First confirm the write reached the DC (`Get-ADAuthenticationPolicy ... -Server <each DC>`). If one DC does not reflect the change, check replication (`repadmin /showrepl`) and force sync if needed: `repadmin /syncall DC01 /AdeP`.

> **If you cannot authenticate as any Tier 0 account and cannot reach a writable DC with RID-500:** DSRM is the last-resort option. Rebooting a DC into Directory Services Repair Mode brings up the DC with AD DS offline and local SAM authentication active — it is independent of Kerberos silo enforcement. This is a disruptive, last-resort procedure: the DC is offline for AD DS purposes during recovery, and the DSRM password must be known in advance. Use it only if all domain-authenticated recovery paths are exhausted. Perform attribute changes and recovery using `Active Directory Administrative Center` or `LDP` after restoring AD DS services, or restore from a known-good system-state backup if the configuration state cannot be safely repaired online.

---

## 5. Daily Maintenance and Day-2 Operations

### Daily

| Task | How | Why |
|---|---|---|
| Check Event 305/105 on all DCs | `Get-WinEvent` against Authentication Policy Failures channel on each DC | 305 = audit would-be-deny (review and triage); 105 = enforce deny (investigate immediately) |
| Review SIEM/forwarded events | Query your SIEM for Event IDs 105, 305 | Catch authentication-origin anomalies before they become incidents |

### Weekly

| Task | How | Why |
|---|---|---|
| Verify approved-device group membership is consistent on all DCs | `Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server DCxx` per DC | Replication issues or unauthorized adds/removes show up here |
| Review exemption register | Manual review of your exemption log | Exemptions accumulate; unowned or expired exemptions should be removed |
| Verify silo/policy Enforce state | Check **both** objects: `Get-ADAuthenticationPolicy -Identity "T0-UserPolicy" \| Select-Object Enforce` and `Get-ADAuthenticationPolicySilo -Identity "T0-Silo" \| Select-Object Enforce` | Accidental or malicious downgrade from enforced to audit on either object |

### Monthly

| Task | How | Why |
|---|---|---|
| Full membership reconciliation | Export device group and compare to authoritative device inventory | Decommissioned devices remain in the group (stale inclusion); new devices are not in the group (missed enrollment) |
| Review exemptions for expiry | Check your exemption log for entries past or near their expiry date | Expired exemptions become uncontrolled bypasses |
| Replication health check | `repadmin /replsummary` | Replication failures leave DCs with stale policy/group state |
| Verify Authentication Policy Failures channel is enabled on all DCs | See Section 8 | Channel can be disabled by GPO changes or accidents; silent when disabled |

### Change control requirements

Changes to the following objects require Tier 0 change control (two-person review, documented):

- `T0-UserPolicy` — any attribute change, especially `Enforce` and `UserAllowedToAuthenticateFrom`
- `T0-Silo` — permitted accounts, policy references, `Enforce`
- `T0-ApprovedDevices` — adds, removes, SID changes

> **Why the device group needs change control:** Adding a computer to `T0-ApprovedDevices` is functionally equivalent to relaxing the SDDL. An attacker who can add a computer account they control to this group has bypassed the silo without touching the policy.

---

## 6. Exclusions and Exemptions

### The break-glass account (built-in Administrator — RID-500)

The built-in domain Administrator account (the one whose Security Identifier ends in `-500`) is **permanently exempt** from Authentication Policy evaluation by the Windows platform. It is not possible to enforce silo restrictions against it.

**Required action:** Never assign RID-500 to any authentication policy silo or authentication policy. It is your recovery account. Confirm it has no assignments:

```powershell
# Build the RID-500 SID from the domain SID (reliable method)
$DomainSID = (Get-ADDomain -Server "DC01").DomainSID.Value
$RID500SID = "$DomainSID-500"

Get-ADUser -Identity $RID500SID `
    -Properties msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo
```

If either attribute is set (accidentally assigned):

```powershell
# Remove direct policy assignment
Set-ADUser -Identity $RID500SID -Clear msDS-AuthNPolicyBL

# Remove silo assignment — use -AuthenticationPolicySilo $null (not -Clear)
Set-ADAccountAuthenticationPolicySilo `
    -Identity $RID500SID `
    -AuthenticationPolicySilo $null

# Verify both are cleared
Get-ADUser -Identity $RID500SID `
    -Properties msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicy, msDS-AssignedAuthNPolicySilo
```

Monitor the built-in Administrator account more closely than regular accounts — it is exempt from silo enforcement by design and is therefore a high-value target. Note: the exemption means the Kerberos silo check does not apply; User Rights Assignment, account state, smartcard requirements, and network controls still apply.

### Exempting other accounts or devices

Sometimes a legitimate account or workflow cannot be enrolled in the silo. Common permanent reasons include:

- NTLM-only service workflows (RADIUS/NPS, some legacy applications) — see Section 10
- Non-domain-joined systems that will never be domain-joined
- Hardware management interfaces that use LDAP simple bind

**Every exemption must have:**

| Required element | Description |
|---|---|
| Named owner | A specific, named individual responsible for the exemption |
| Written justification | Why the account/device cannot satisfy the silo restriction (technical reason) |
| Expiry date | When the exemption expires and must be reviewed; use a hard-deny-by-default expiry for remediable conditions |
| Compensating controls | What additional monitoring or access controls apply to this exempt account/device |
| Approval | Documented approval from the risk owner |

**How to implement an account exemption:**

Simply do not enroll the account in the silo — do not run Steps 4–5 from Section 3a for that account. Document the exemption in your register.

> **⚠ Exemptions are bypasses by design.** An exempt Tier 0 account that is compromised can be used from any machine. Apply stronger monitoring to all exempt accounts: alert on logon from unexpected source devices, unusual hours, and privileged group use.

### Exemption lifecycle

| Stage | Action |
|---|---|
| **Request** | Technical owner submits justification with evidence of why enrollment is not possible |
| **Approval** | Risk owner (with both technical and risk competence) approves with explicit acceptance of residual risk |
| **Register** | Entry added to exemption log: account, owner, justification, compensating controls, expiry date |
| **Active monitoring** | Exempt account placed in heightened-monitoring tier |
| **Expiry** | At expiry: renew with fresh evidence (if still needed) or revoke exemption and enroll in silo |
| **Revocation** | If the underlying condition is resolved, remove from exemption register and complete silo enrollment |

---

## 7. Lifecycle — Joiners, Movers, Leavers

### Joiner — new Tier 0 administrator

1. Place account in the correct Tier 0 OU (prerequisite for Tier Model GPOs).
2. Run the brownfield preflight (§3a Step 0) to confirm no existing direct-policy or silo assignments.
3. Confirm the admin's PAW is in `T0-ApprovedDevices` and replicated on all DCs.
4. Grant silo access: `Grant-ADAuthenticationPolicySiloAccess`.
5. Assign silo: `Set-ADAccountAuthenticationPolicySilo`.
6. Verify audit events flowing correctly (§3a Step 7).
7. In a separately reviewed and approved hardening change: consider `AccountNotDelegated = $true` (§3a Step 6) — this takes effect immediately and is not audit-mode-only.

> **Device must be in the group before account is assigned.** If you assign the account first and add the device later, the admin will see Event 305 (audit) or be locked out (enforce) on their first logon attempt after enrollment.

### Joiner — new PAW or approved device

Complete Section 3c (Onboard a New Tier 0 PAW). The critical ordering is:

1. Domain-join and OU placement
2. GPO application + reboot (Kerberos armoring must be active)
3. Add to `T0-ApprovedDevices`
4. Verify replication on all DCs

### Mover — administrator changes role

| Direction | Required action |
|---|---|
| **Tier 1 → Tier 0** | Enroll in T0-Silo (Steps 4–5 of Section 3a); confirm T0 PAW in T0-ApprovedDevices; remove from T1-Silo if applicable |
| **Tier 0 → Tier 1** | Remove T0 silo assignment; enroll in T1-Silo if applicable; review device group membership; update exemption register if the account had exemptions |
| **Tier 0 → leaving privileged roles** | Remove silo assignment; disable account; update exemption register |

To remove a silo assignment (use `-AuthenticationPolicySilo $null`, not `-Clear`):

```powershell
# Remove silo assignment from a user
Set-ADAccountAuthenticationPolicySilo `
    -Identity "t0-admin-moving" `
    -AuthenticationPolicySilo $null

# Also revoke silo access (removes from permitted-accounts list)
Revoke-ADAuthenticationPolicySiloAccess `
    -Identity "T0-Silo" `
    -Account "t0-admin-moving"

# Verify both: assignment attribute and permitted-accounts list
Get-ADUser "t0-admin-moving" `
    -Properties msDS-AssignedAuthNPolicySilo |
    Select-Object SamAccountName, msDS-AssignedAuthNPolicySilo

Get-ADAuthenticationPolicySilo -Identity "T0-Silo" `
    -Properties msDS-AuthNPolicySiloMembers |
    Select-Object -ExpandProperty msDS-AuthNPolicySiloMembers
```

### Leaver — departing administrator

1. **Disable the account** (standard HR/IT offboarding).
2. **Remove the silo assignment and revoke silo access:**
   ```powershell
   # Remove assignment (-AuthenticationPolicySilo $null, not -Clear)
   Set-ADAccountAuthenticationPolicySilo `
       -Identity "t0-admin-leaving" `
       -AuthenticationPolicySilo $null

   # Revoke from permitted-accounts list
   Revoke-ADAuthenticationPolicySiloAccess `
       -Identity "T0-Silo" `
       -Account "t0-admin-leaving"

   # Verify both are cleared
   Get-ADUser "t0-admin-leaving" `
       -Properties msDS-AssignedAuthNPolicySilo |
       Select-Object SamAccountName, msDS-AssignedAuthNPolicySilo
   ```
3. **Do NOT automatically remove devices from `T0-ApprovedDevices`** — a PAW may be used by other administrators. Remove a device from the group only when it is being decommissioned or reassigned to a lower tier.
4. **Revoke any exemptions** the departing admin owned. Exemptions without an owner cannot be meaningfully reviewed.

### Device decommission

When a PAW or approved device is decommissioned or reassigned:

```powershell
# Remove the decommissioned computer from the approved-device group
Remove-ADGroupMember -Identity "T0-ApprovedDevices" -Members "OLDPAW01$" -Confirm:$false

# Verify removal on all DCs
Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC01" | Select-Object Name
```

Also disable or delete the computer account per your normal decommission procedure.

---

## 8. Event IDs and Monitoring

### Enable the Authentication Policy Failures channel (required — it is off by default)

The most important log channel is **disabled by default**. Enable it on every DC before you expect any audit data:

```powershell
# Run on each DC (or via Invoke-Command)
wevtutil set-log `
    "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" `
    /enabled:true /quiet

# Verify
wevtutil get-log `
    "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" |
    Select-String "Enabled"
```

> **⚠ If this channel is disabled, the absence of Event 305 events tells you nothing.** A disabled channel is indistinguishable from "no would-be-denials occurred." Confirm the channel is enabled on every DC before drawing any conclusions from a clean audit period.

### Event ID reference table

| Event ID | Channel | Mode | Meaning | Action |
|---|---|---|---|---|
| **305** | AuthenticationPolicyFailures-DomainController | Audit | Kerberos TGT would have been denied — the device failed `AllowedToAuthenticateFrom`. Authentication succeeded because policy is in audit mode. | Triage: is this an approved device not yet in the group, or an unexpected source? |
| **105** | AuthenticationPolicyFailures-DomainController | Enforce | Kerberos TGT was **denied**. The account could not obtain a TGT from the device. | Immediate investigation. Real user impact. |
| **306** | AuthenticationPolicyFailures-DomainController | Audit | Kerberos service ticket would have been denied — the requester failed `AllowedToAuthenticateTo` for a target. Authentication succeeded because policy is in audit mode. | Triage: relevant if `AllowedToAuthenticateTo` (Config B) is configured. |
| **106** | AuthenticationPolicyFailures-DomainController | Enforce | Kerberos service ticket was **denied** for a target protected by `AllowedToAuthenticateTo`. | Immediate investigation. |
| **101** | AuthenticationPolicyFailures-DomainController | Enforce | An NTLM authentication failed because an authentication policy with access-control restrictions was configured and NTLM cannot satisfy those restrictions. | Investigate NTLM-dependent workflow; see Section 9. |
| **4820** | Windows Security log | Enforce | Security log TGT-denied event — one third-party source (Ultimate Windows Security) has a captured sample showing account, silo name, policy name, TGT lifetime, device, service, client IP, and result code. **\[Lab validation required — field structure, audit subcategory prerequisite, and multi-OS reliability not confirmed by Microsoft documentation.\]** | Enable and test in lab before building SIEM rules. Do not treat as a documented equivalent of Event 105 until lab-confirmed. |
| **4821** | Windows Security log | Enforce | Security log service-ticket-denied event. **\[Lab validation required — existence inferred from event manifest only; no captured sample; not reproduced in any cited source.\]** | Do not build detection rules against this ID until lab-confirmed. |
| **5136** | Windows Security log | Both | An AD object attribute was modified — covers policy/silo changes when DS Access auditing and SACLs are configured. Requires Advanced Audit Policy "Directory Service Changes" enabled and a SACL on the relevant objects. Alert on: `msDS-AuthNPolicySiloEnforced`, `msDS-AuthNPolicyEnforced`, `msDS-AuthNPolicySiloMembers`. | Configure DS Change auditing and SACLs on policy/silo containers. |
| **5137** | Windows Security log | Both | An AD object was created — includes new policy or silo object creation. | Monitor for unexpected creation of auth-policy or silo objects. |
| **5141** | Windows Security log | Both | An AD object was deleted. | Alert on deletion of policy or silo objects. |
| **4728 / 4729** | Windows Security log | Both | Member added to / removed from a global security group. | Alert on changes to global approved-device groups (e.g., `T0-ApprovedDevices` if it is Global scope). |
| **4732 / 4733** | Windows Security log | Both | Member added to / removed from a local security group. | Alert if any approved-device group is domain-local scope. |
| **4756 / 4757** | Windows Security log | Both | Member added to / removed from a universal security group. | Alert on changes to universal approved-device groups (required for multi-domain environments). |
| **4719** | Windows Security log | Both | An **audit policy** was changed (category/subcategory setting changed on a DC). This does **not** directly detect the `AuthenticationPolicyFailures-DomainController` channel being disabled — application-channel state requires active polling (`wevtutil get-log`) or a canary-event approach. | Alert on audit-policy changes on DCs; separately poll channel state and SIEM ingestion health. |

### What to collect and where

| Source | What to forward | Priority |
|---|---|---|
| All domain controllers | `Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController` | Critical |
| All domain controllers | Windows Security log (5136, 4719, 4820) | High |
| PAWs and approved devices | Windows Security log (4624, 4648 for logon events) | Medium |

**Every relevant DC must forward these channels independently.** A single SIEM connection to one DC does not cover what other DCs are doing. In a multi-DC environment, a user may authenticate against any DC — the event only appears on the DC that serviced the request.

### Blind spots — what audit mode cannot see

| Path | Why it is invisible to 305/306 events | Compensating detection |
|---|---|---|
| NTLM authentication | No documented audit-mode equivalent of Event 305 for NTLM. NTLM failures appear as Event 101 (enforced) only. NTLM-dependent paths (RADIUS/NPS with MS-CHAPv2, some VPN, legacy services) will silently pass the audit period and fail immediately at enforcement. | Audit NTLM use with Event 4776 (NTLM credential validation); inventory NTLM paths before enforcement (G11). |
| LDAP simple bind | Whether authentication policy restrictions apply to LDAP simple bind is **\[Lab validation required\]** — it may bypass (coverage gap) or fail silently at enforcement with no prior 305 warning. Inventory all LDAP-bind-dependent apps before enforcing. | LDAP audit logging; LDAP channel binding; LDAPS enforcement; pre-enforcement LDAP-bind inventory. |
| Cached/offline sign-in | Cached credentials are validated locally, not by a DC. | Disable credential caching for Tier 0 accounts (Protected Users group); Credential Guard. |
| Already-issued tickets | TGTs issued before enforcement are not invalidated by enforcement. The TGT lifetime may be the domain default (longer than 240 minutes). Do not assume a fixed expiry window. | Use the fresh-TGT pilot test (§4 Step 5) to confirm enforcement. Do not wait for tickets to expire. |

---

## 9. Negative Testing — Prove Denials Work

Positive testing (the approved admin can log on from the approved PAW) is necessary but not sufficient. You must also prove that **unapproved devices are denied**. Do this during the audit period — when 305 events appear instead of actual lockouts — and again before enforcement.

**Test device:** Use a server that is NOT in any approved-device group. A non-tier-model server works well. A Tier 1 server is useful for cross-tier denial tests.

### UAT-05 — Tier 0 admin from an unapproved device

1. On the unapproved device, attempt an interactive logon or `klist get krbtgt` as the Tier 0 admin account.
2. In **audit** mode: the logon succeeds, but Event 305 appears on the DCs. Record which DC handled the AS request.
3. In **enforce** mode: the logon fails with a Kerberos error, and Event 105 appears on the DCs.

```powershell
# On each DC — check for 305 (audit) or 105 (enforce)
Get-WinEvent -LogName `
    "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" |
    Where-Object { $_.Id -in @(105, 305) } |
    Select-Object TimeCreated, Id, Message |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 10
```

**Pass criteria:** Event 305 or 105 appears with the correct account name and the unapproved device name. No 305/105 for an approved account from an approved device during the same period.

### UAT-06 — Cross-tier denial: Tier 0 admin from a Tier 1 server

1. Identify a Tier 1 server that is in the Tier 1 approved-device group but NOT in the Tier 0 approved-device group.
2. Attempt to log on as a Tier 0 admin from that Tier 1 server (interactive console logon — not NLA RDP, which would evaluate the admin's workstation).
3. In enforce mode: the logon fails; Event 105 appears.

This test proves the tier boundary is enforced — a Tier 0 credential cannot be used from a Tier 1 machine even if that machine is itself enrolled in a different silo.

### UAT-07 — Local Device Admin from non-EUD device

1. Attempt to log on as a Local Device Admin account from a PAW or server (not the enrolled EUD).
2. In enforce mode: the logon fails; Event 105 appears.

This test proves the Tier 2 EUD silo is working — local admin credentials cannot be reused cross-device.

### Recording test results

For each test, record:

| Field | Value |
|---|---|
| Test ID | UAT-05 / UAT-06 / UAT-07 |
| Account used | `t0-admin-xxx` |
| Device used | `UNAPPROVED-SRV01` |
| Mode | Audit / Enforce |
| DC that serviced request | `DC01` (from `klist` output or `nltest /dsgetdc:CONTOSO /kdc`) |
| Event observed | Event 305 (audit) or 105 (enforce) |
| Event timestamp | `2026-08-25T09:15:42` |
| Pass / Fail | Pass |

---

## 10. Troubleshooting

### Symptom: Admin cannot log on after silo enrollment

**Most likely cause:** The admin's device is not in `T0-ApprovedDevices`, or the group membership has not replicated.

```powershell
# Check which DC the client is authenticating against
nltest /dsgetdc:CONTOSO /kdc

# Check device group membership on that specific DC
Get-ADGroupMember -Identity "T0-ApprovedDevices" -Server "DC01" |
    Where-Object { $_.Name -like "PAWNAME*" }
```

If the device is missing: add it and force replication (`repadmin /syncall DC01 /AdeP`), then wait one minute and retry.

If the device is present but the admin still cannot log on: confirm the Kerberos armoring GPO is applied and the machine has been **rebooted** since the GPO applied. Run `gpresult /r` on the device and check Applied Computer GPOs.

---

### Symptom: Event 305 appearing unexpectedly

Event 305 fires when the DC evaluates an AS request from a device that is not in the approved-device group (in audit mode). The event message includes the account name, the device, and the policy/silo.

1. Identify the device name from the event.
2. Determine if it is a legitimate admin device that was missed — if so, add it.
3. If it is unexpected (e.g., a non-admin workstation), investigate how a Tier 0 credential ended up on that machine.

---

### Symptom: Event 101 — NTLM failure

An account with a silo/policy configured attempted NTLM authentication. The restriction cannot be applied to NTLM, so the attempt fails.

**This is a silent breakage risk.** NTLM paths do not generate Event 305 in audit mode — they generate Event 101 only in enforce mode. If you see Event 101 after enforcement, you have found an NTLM-dependent workflow that was invisible during the audit period.

**Resolution options:**
- Migrate the service/workflow to Kerberos.
- Use a separate, non-siloed service account for the NTLM workflow.
- Set `UserAllowedNTLMNetworkAuthentication = $true` on the policy if the NTLM path is essential — but note this weakens the policy's protection by explicitly permitting NTLM.

```powershell
# Check whether NTLM is explicitly allowed on the policy
Get-ADAuthenticationPolicy -Identity "T0-UserPolicy" |
    Select-Object Name, UserAllowedNTLMNetworkAuthentication
```

---

### Symptom: Enforcement reverted to audit unexpectedly

If your monitoring detects that a silo or policy has changed to `Enforce = false`:

1. Check Event 5136 on the DC that processed the write for who made the change.
2. Check the timestamp against planned changes and change records.
3. Re-enable enforcement only after verifying the cause. If an unauthorized actor made the change, treat it as a security incident.

---

### Symptom: All Tier 0 admins are locked out (Critical — lockout recovery runbook)

> **Use this runbook if no Tier 0 account can authenticate. Stay calm. You have options.**

**Step 1 — Try the built-in Administrator (RID-500).**

Construct the SID from the domain SID and authenticate with RID-500 from any machine you can reach.

```powershell
# Identify the built-in Administrator by constructing its SID
# (run from any machine with AD module, or find the account name in your documentation)
$DomainSID = (Get-ADDomain -Server "DC01").DomainSID.Value
$RID500SID = "$DomainSID-500"
$BuiltinAdmin = Get-ADUser -Identity $RID500SID
Write-Host "Break-glass account: $($BuiltinAdmin.SamAccountName)"
```

Log on as this account from any accessible machine. RID-500 is exempt from Authentication Policy evaluation by the platform — the Kerberos silo check is not applied to it. **However:** it is still subject to User Rights Assignment (confirm the account has "Allow log on locally" / "Allow log on through Remote Desktop Services" on the target DC), account state (must be enabled), and network/firewall reachability.

If RID-500 works, revert enforcement on both policy and silo:

```powershell
Set-ADAuthenticationPolicy -Identity "T0-UserPolicy" -Enforce $false
Set-ADAuthenticationPolicySilo -Identity "T0-Silo" -Enforce $false

# Verify on all DCs
foreach ($dc in @("DC01", "DC02")) {
    Get-ADAuthenticationPolicy -Identity "T0-UserPolicy" -Server $dc | Select-Object Name, Enforce
    Get-ADAuthenticationPolicySilo -Identity "T0-Silo" -Server $dc | Select-Object Name, Enforce
}
```

**Step 2 — If RID-500 cannot reach a writable DC, try DSRM (last resort).**

DSRM (Directory Services Repair Mode) boots a DC with AD DS services offline. Authentication uses the local SAM — it is independent of domain Kerberos and silo enforcement. This is disruptive (the DC is offline for AD services during recovery) and should only be used when all domain-authenticated paths are exhausted.

To use DSRM:
1. Reboot a DC into DSRM — requires the DSRM password (confirm this is documented before you need it).
2. Log on with the DSRM local Administrator credential at the console.
3. DSRM stabilises or restores AD DS itself — it is **not** a way to edit the authentication policy/silo objects (those are directory objects that require AD DS to be online). If the directory is intact and only the silo is misconfigured, do **not** attempt an offline repair: return to Step 1 and fix the objects online using the exempt RID-500 account and the standard `Set-ADAuthenticationPolicy` / `Set-ADAuthenticationPolicySilo` cmdlets.
4. Use DSRM only to restore from a known-good system-state backup when the directory configuration has been destructively corrupted or AD DS will not start.

**Step 3 — Identify and fix the root cause before re-enforcing.**

Common causes of total lockout:
- Empty or wrong-SID `T0-ApprovedDevices` group (check with G3 SID verification from §4)
- Wrong SDDL boolean logic (AND where OR was needed)
- Kerberos armoring GPO not applied on approved devices
- Group membership replication failure — verified per-DC but not per-originating-DC

After fixing, verify from every DC before re-enforcing. Run the fresh-TGT pilot test (§4 Step 5) before declaring recovery complete.

---

### Symptom: Inconsistent behavior — works from some DCs but not others

AD replication is the most common cause. The policy/group/silo state is consistent on one DC but not another.

```powershell
# Check replication status
repadmin /replsummary
repadmin /showrepl

# Force replication from DC01 to DC02
repadmin /syncall DC01 /AdeP
```

Verify the corrected state on all DCs individually before confirming resolution.

---

### Symptom: Admin works from PAW but not from jump server

Confirm which device is the actual origination device (apply the Origination Device Rule from Section 2). If the admin uses NLA/CredSSP for RDP to the jump server, their **PAW** is the origination device — the jump server does not need to be in the group. If they type credentials at the jump server's own logon screen, the **jump server** is the origination device and must be in `T0-ApprovedDevices`.

---

## 11. Limitations — What Silos Do Not Protect

Understanding what silos cannot do is as important as knowing what they can do.

| What you might want | Does the silo deliver it? | Why not, and what to use instead |
|---|---|---|
| Prevent credential use from any non-approved device | **Partial** — covers Kerberos AS exchange only | Does not cover: cached/offline sign-in, already-issued TGTs, NTLM paths, LDAP simple bind, cloud/Entra authentication |
| Block NTLM authentication | **Partial / \[Lab validation required\]** — Event 101 fires when a siloed account's NTLM authentication is blocked (enforced), but the NTLM-allow switch behavior and Windows Server 2016 DFL dependency are not fully documented. Protected Users group blocks NTLM for enrolled user accounts as a separate, complementary control. | Protected Users group for privileged human accounts; Group Policy NTLM restrictions (`Network Security: Restrict NTLM`). |
| Prevent LDAP simple-bind credential use | **\[Lab validation required\]** — may bypass silently or fail silently; behavior is not confirmed | LDAP channel binding; LDAPS enforcement; separate service account for LDAP-bound applications; network segmentation. |
| Restrict which servers an account can administer | **No** — silos restrict where a TGT is obtained, not what happens after logon | Use User Rights Assignment (deny logon rights), network segmentation, access control lists |
| Restrict logon type (interactive, RDP, service, batch) | **No** | Use User Rights Assignment (`Deny log on locally`, `Deny log on through Remote Desktop Services`, etc.) |
| Restrict which scheduled task or process the account runs | **No** | Use User Rights Assignment, Windows Defender Application Control (WDAC), Task Scheduler ACLs |
| Protect against lateral movement after a successful logon | **No** | Credential Guard, Local Administrator Password Solution (LAPS), network segmentation, least-privilege local admin |
| Block cloud/Entra authentication | **No** | Authentication Policy Silos are AD DS objects evaluated by domain controllers. Entra ID sign-ins, PRT issuance, OAuth tokens, and SaaS Conditional Access decisions are outside their reach. Use Microsoft Entra Conditional Access. |
| Protect non-domain-joined Linux or similar clients | **No** | Non-domain-joined systems have no AD computer account and cannot present the device identity needed to satisfy `AllowedToAuthenticateFrom`. Use separate credentials, network segmentation, and local PAM controls for Linux administration. |

### The layered model

Authentication Policy Silos are one layer in a defence-in-depth stack. They answer the narrow question: "May this domain principal obtain a Kerberos ticket from this device?" Other layers answer the remaining questions:

| Question | Control |
|---|---|
| "May this account log on to this server interactively or via RDP?" | User Rights Assignment |
| "What local groups and privileges does the account receive?" | Restricted Groups / LocalUsersAndGroups GPP; LAPS |
| "What network paths can reach this server?" | Windows Firewall, network segmentation |
| "What code can run in this account's context?" | WDAC / App Control for Business |
| "What can the account do in AD after logon?" | AD ACLs, role-based access control, Just Enough Administration (JEA) |
| "What Entra/cloud resources can the account reach?" | Microsoft Entra Conditional Access, Privileged Identity Management |

---

## Appendix A — Building the Silo Infrastructure from Scratch

Use this sequence if the silo, policy, and device group do not yet exist. Complete every step in order — each depends on the previous.

### Prerequisites check

```powershell
# Verify DFL
Get-ADDomain | Select-Object DomainMode

# Check for existing silo objects
Get-ADAuthenticationPolicySilo -Filter * | Select-Object Name
Get-ADAuthenticationPolicy -Filter * | Select-Object Name
```

### Step 1 — Create the approved-device group

```powershell
New-ADGroup `
    -Name "T0-ApprovedDevices" `
    -GroupScope Global `
    -GroupCategory Security `
    -Path "OU=Tier0Groups,DC=CONTOSO,DC=COM" `
    -Description "Devices approved as origination points for Tier 0 TGT requests"
```

### Step 2 — Populate the group and obtain the SID for SDDL

```powershell
# Add PAW computer accounts (note the trailing $)
Add-ADGroupMember -Identity "T0-ApprovedDevices" -Members "PAW01$","PAW02$"

# Obtain the group SID — you need this for the SDDL
$GroupSID = (Get-ADGroup "T0-ApprovedDevices").SID.Value
Write-Host "Group SID: $GroupSID"
# Example output: S-1-5-21-1234567890-1234567890-1234567890-1234
```

> **Copy the SID value.** You need it in the next step. Do not proceed until you have it.

### Step 3 — Create the user authentication policy

Replace `PASTE-YOUR-SID-HERE` with the SID from Step 2.

```powershell
$GroupSID = "PASTE-YOUR-SID-HERE"   # e.g. S-1-5-21-1234567890-1234567890-1234567890-1234

$SDDL = "O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of {SID($GroupSID)}))"

New-ADAuthenticationPolicy `
    -Name "T0-UserPolicy" `
    -UserTGTLifetimeMins 240 `
    -UserAllowedToAuthenticateFrom $SDDL `
    -Enforce $false `
    -ProtectedFromAccidentalDeletion $true `
    -Description "Tier 0 user authentication policy - audit mode"
```

> **240 minutes = 4 hours non-renewable TGT.** This aligns with Protected Users if you add that group later. The TGT is non-renewable — admins must re-authenticate after 4 hours.

### Step 4 — Create the silo

```powershell
New-ADAuthenticationPolicySilo `
    -Name "T0-Silo" `
    -UserAuthenticationPolicy "T0-UserPolicy" `
    -Enforce $false `
    -ProtectedFromAccidentalDeletion $true `
    -Description "Tier 0 authentication policy silo - audit mode"
```

### Step 5 — Verify replication before enrolling accounts

```powershell
# Verify group and policy/silo on all DCs
Get-ADGroup "T0-ApprovedDevices" -Server "DC01"
Get-ADGroup "T0-ApprovedDevices" -Server "DC02"
Get-ADAuthenticationPolicy "T0-UserPolicy" -Server "DC01"
Get-ADAuthenticationPolicySilo "T0-Silo" -Server "DC01"
```

### Step 6 — Enable the Authentication Policy Failures log channel on all DCs

```powershell
# Run on each DC
wevtutil set-log `
    "Microsoft-Windows-Authentication/AuthenticationPolicyFailures-DomainController" `
    /enabled:true /quiet
```

### Step 7 — Enroll accounts

For each Tier 0 user, follow Section 3a (Steps 4–7).

### Step 8 — Apply client GPO to PAWs and reboot

Confirm the Kerberos client armoring GPO is linked to the PAW OU and that all PAWs have received it and rebooted.

### Step 9 — Begin the audit period

Monitor Event 305 daily. See Section 4 (Audit → Enforced Transition) for when and how to flip to enforce mode.

---

## 12. Related Reading

- [Best Practices, Governance & AD Hardening](best-practices.md) — complementary controls including Protected Users, NTLM restrictions, and PAW guidance
- [GPO Management Guidance](gpo-management-guidance.md) — the Account Restrictions GPO that carries Kerberos armoring and Deny logon rights
- [Drift Detection](drift-detection-details.md) — how the Tier Model detects configuration drift
- [Sentinel Monitoring](sentinel-monitoring.md) — Security log event forwarding and collection
- Microsoft documentation: [Authentication Policies and Authentication Policy Silos](https://learn.microsoft.com/en-us/windows-server/security/credentials-protection-and-management/authentication-policies-and-authentication-policy-silos)
- Microsoft documentation: [Protected Users Security Group](https://learn.microsoft.com/en-us/windows-server/security/credentials-protection-and-management/protected-users-security-group)
- Microsoft documentation: [How to configure protected accounts](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/how-to-configure-protected-accounts)
