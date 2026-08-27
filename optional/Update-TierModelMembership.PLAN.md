# Design Plan: Update-TierModelMembership.ps1

> **Status:** DRAFT — Awaiting Joel review before any code is written  
> **Author:** Beast (Core Dev)  
> **Date:** 2026-08-27  
> **Location:** `optional/Update-TierModelMembership.ps1`  
> **Target:** Windows PowerShell 5.1 + ActiveDirectory module (must NOT assume PS7)

---

## 1. Purpose & Scope

A scheduled reconciliation script that keeps the Tier Model's Authentication Policy coverage current as machines join the domain and accounts are created. The script is **additive for group membership** and **enforcing for policy assignment** — it never rewrites SDDL or modifies Authentication Policies/Silos (those are create-once via the deploy module).

### Two Mechanisms

| Mechanism | What it does | Why it works |
|-----------|-------------|--------------|
| **Computers + Accounts → GROUP membership** | Adds objects from Tier OUs into the correct Tier groups | The Authentication Policy SDDL (`UserAllowedToAuthenticateFrom`) references device groups by SID. Keeping group membership current is what covers new devices. The SDDL is never rewritten. |
| **Accounts → AUTH POLICY assignment** | Assigns `msDS-AssignedAuthNPolicy` directly on user/service accounts | New accounts need the tier's Authentication Policy so they are governed. This is direct policy assignment via `Set-ADUser -AuthenticationPolicy` / `Set-ADObject`, **NOT** silo membership (silos govern computers only in the create-once model). |

### What This Script Does NOT Do

- Never edits SDDL on any Authentication Policy
- Never modifies Authentication Policy or Silo objects
- Never creates or deletes AD objects
- Never manages silo membership (`msDS-AuthNPolicySiloMembers`)
- Does NOT deprovision objects that left a Tier OU (v1 — flagged as future)
- Does NOT manage Tier2LocalDeviceOperators group membership (customer-curated)

---

## 2. Config-Driven DN Resolution

All OU paths, group names, policy names, and exclusion accounts are derived from config files. Nothing is hardcoded. The `{{DOMAIN_DN}}` token is resolved at runtime via `(Get-ADDomain).DistinguishedName`.

### Source Config Files

| File | Provides |
|------|----------|
| `config/tiermodel-ous.json` | OU names and parent paths |
| `config/tiermodel-groups.json` | Group `samAccountName` values and OU locations |
| `config/tiermodel-authsilos.json` | Authentication Policy names (4 policies) |
| `config/tiermodel-users.json` | Built-in exclusion accounts (3 domain-join svc accounts) |

### OU-to-DN Mapping (from `tiermodel-ous.json`)

The OU structure is **non-uniform** — Accounts/Service Accounts/PAW Devices are under `OU=Tier Model Administration`, while Member Servers and End-User Devices are at the domain root.

#### Tier 0

| Logical Name | Full DN |
|-------------|---------|
| Tier 0 Accounts | `OU=Tier 0 Accounts,OU=Tier 0,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 0 Service Accounts | `OU=Tier 0 Service Accounts,OU=Tier 0,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 0 PAW Devices | `OU=Tier 0 PAW Devices,OU=Tier 0,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 0 Member Servers | `OU=Tier 0 Member Servers,{{DOMAIN_DN}}` ← domain root |
| Tier 0 Server Staging | `OU=Tier 0 Server Staging,OU=Tier 0 Member Servers,{{DOMAIN_DN}}` |

#### Tier 1

| Logical Name | Full DN |
|-------------|---------|
| Tier 1 Accounts | `OU=Tier 1 Accounts,OU=Tier 1,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 1 Service Accounts | `OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 1 PAW Devices | `OU=Tier 1 PAW Devices,OU=Tier 1,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 1 Member Servers | `OU=Tier 1 Member Servers,{{DOMAIN_DN}}` ← domain root |
| Tier 1 Server Staging | `OU=Tier 1 Server Staging,OU=Tier 1 Member Servers,{{DOMAIN_DN}}` |

#### Tier 2

| Logical Name | Full DN |
|-------------|---------|
| Tier 2 Accounts | `OU=Tier 2 Accounts,OU=Tier 2,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 2 Service Accounts | `OU=Tier 2 Service Accounts,OU=Tier 2,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 2 PAW Devices | `OU=Tier 2 PAW Devices,OU=Tier 2,OU=Tier Model Administration,{{DOMAIN_DN}}` |
| Tier 2 End-User Devices | `OU=Tier 2 End-User Devices,{{DOMAIN_DN}}` ← domain root |
| Disabled End-User Devices | `OU=Disabled End-User Devices,OU=Tier 2 End-User Devices,{{DOMAIN_DN}}` ← excluded child |

> **Note:** `OU=Tier 2 End-User Accounts,{{DOMAIN_DN}}` at the domain root is for non-admin end users — it is NOT in scope for this script. Tier 2 admin/operator accounts live in `OU=Tier 2 Accounts,OU=Tier 2,OU=Tier Model Administration,...`.

### Group Mapping (from `tiermodel-groups.json`)

| samAccountName | Scope | Category | Path |
|---------------|-------|----------|------|
| `Tier0Operators` | Global | Security | `OU=Tier 0 Groups,OU=Tier 0,OU=Tier Model Administration,...` |
| `Tier0ServiceAccounts` | Global | Security | `OU=Tier 0 Groups,...` |
| `Tier0MemberServers` | Universal | Security | `OU=Tier 0 Groups,...` |
| `Tier0PAWDevices` | Universal | Security | `OU=Tier 0 Groups,...` |
| `Tier1Operators` | Global | Security | `OU=Tier 1 Groups,...` |
| `Tier1ServiceAccounts` | Global | Security | `OU=Tier 1 Groups,...` |
| `Tier1MemberServers` | Universal | Security | `OU=Tier 1 Groups,...` |
| `Tier1PAWDevices` | Universal | Security | `OU=Tier 1 Groups,...` |
| `Tier2Operators` | Global | Security | `OU=Tier 2 Groups,...` |
| `Tier2ServiceAccounts` | Global | Security | `OU=Tier 2 Groups,...` |
| `Tier2PAWDevices` | Universal | Security | `OU=Tier 2 Groups,...` |
| `Tier2EUDDevices` | Universal | Security | `OU=Tier 2 Groups,...` |
| `Tier2LocalDeviceOperators` | Global | Security | `OU=Tier 2 Groups,...` |

### Authentication Policy Mapping (from `tiermodel-authsilos.json`)

| Policy Name | Assigned To |
|------------|-------------|
| `*- Tier 0 Authentication Policy` | Tier 0 operators + service accounts |
| `*- Tier 1 Authentication Policy` | Tier 1 operators + service accounts |
| `*- Tier 2 Authentication Policy` | Tier 2 operators + service accounts |
| `*- Tier 2 EUD Authentication Policy` | Tier 2 LocalDeviceOperators (EUD users) |

### Built-In Exclusion Accounts (from `tiermodel-users.json`)

| samAccountName | OU | memberOf | Purpose |
|---------------|-----|----------|---------|
| `svc-pawdomainjoin` | `OU=Tier 0 Service Accounts,...` | `PAWDomainJoin` | PAW staging domain join |
| `svc-t1srvdomainjoin` | `OU=Tier 1 Service Accounts,...` | `Tier1ServerDomainJoin` | Tier 1 server staging domain join |
| `svc-t2euddomainjoin` | `OU=Tier 2 Service Accounts,...` | `Tier2EUDDomainJoin` | Tier 2 EUD domain join |

These three accounts require NTLM for domain-join operations. They must **NEVER** receive an Authentication Policy assignment. The script's first step ensures/confirms this every run and **removes** any policy that is somehow assigned to them.

---

## 3. Parameter Design

### Switch Hierarchy

```
-All (DEFAULT)
├── -AllTier0
│   ├── -Tier0Operators
│   ├── -Tier0ServiceActt
│   ├── -Tier0PawDevices
│   ├── -Tier0MemberServers
│   └── -Tier0Staging
├── -AllTier1
│   ├── -Tier1Operators
│   ├── -Tier1ServiceActt
│   ├── -Tier1PawDevices
│   ├── -Tier1MemberServers
│   └── -Tier1Staging
└── -AllTier2
    ├── -Tier2Operators
    ├── -Tier2Eud
    ├── -Tier2ServiceActt
    ├── -Tier2PawDevices
    └── -Tier2EudDevices
```

### Parameter Declaration

```
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # --- Tier-level aggregates ---
    [switch]$All,              # DEFAULT if no switches specified
    [switch]$AllTier0,
    [switch]$AllTier1,
    [switch]$AllTier2,

    # --- Tier 0 granular ---
    [switch]$Tier0Operators,
    [switch]$Tier0ServiceActt,
    [switch]$Tier0PawDevices,
    [switch]$Tier0MemberServers,
    [switch]$Tier0Staging,

    # --- Tier 1 granular ---
    [switch]$Tier1Operators,
    [switch]$Tier1ServiceActt,
    [switch]$Tier1PawDevices,
    [switch]$Tier1MemberServers,
    [switch]$Tier1Staging,

    # --- Tier 2 granular ---
    [switch]$Tier2Operators,
    [switch]$Tier2Eud,
    [switch]$Tier2ServiceActt,
    [switch]$Tier2PawDevices,
    [switch]$Tier2EudDevices,

    # --- Exclusion ---
    [string]$ExclusionAttribute,     # Optional: AD attribute to check
    [string]$ExclusionValue,         # Mandatory iff ExclusionAttribute present

    # --- Dry-run ---
    [switch]$ReportOnly              # Alias for -WhatIf with structured output
)
```

### Parameter Resolution Logic

1. If NO switch is specified → treat as `-All` (all 15 granular switches active).
2. `-All` activates `-AllTier0 + -AllTier1 + -AllTier2`.
3. `-AllTier0` activates all 5 Tier 0 granular switches; same for Tier 1 and Tier 2.
4. Individual switches can be combined freely: e.g., `-Tier0Operators -Tier1MemberServers`.
5. `-ExclusionValue` is validated as mandatory when `-ExclusionAttribute` is present (use `ValidateScript` or explicit early check — not `ParameterSetName`, because parameter sets don't compose well with 15+ switches).
6. `-ReportOnly` sets `$WhatIfPreference = $true` and enables structured summary output.

### Scheduling Examples

```powershell
# Daily full reconciliation
.\Update-TierModelMembership.ps1 -All

# Hourly Tier 1 member servers only
.\Update-TierModelMembership.ps1 -Tier1MemberServers

# Daily Tier 0 with customer exclusion
.\Update-TierModelMembership.ps1 -AllTier0 -ExclusionAttribute extensionAttribute15 -ExclusionValue "TierExclude"

# Dry run — see what would change
.\Update-TierModelMembership.ps1 -All -ReportOnly
```

---

## 4. Per-Switch Semantics

### 4.1 Tier 0/1 Operators (`-Tier0Operators`, `-Tier1Operators`)

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate ALL user objects (recursive, all child OUs) in `Tier X Accounts` OU | — |
| 2 | Add each user to `TierXOperators` group (if not already member) | **NO** — all tier users are operators |
| 3 | Assign `*- Tier X Authentication Policy` to each user (via `Set-ADUser -AuthenticationPolicy`) | **YES** — skip excluded users; remove policy from excluded users who have it |

### 4.2 Tier 0/1 Service Accounts (`-Tier0ServiceActt`, `-Tier1ServiceActt`)

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate ALL user + MSA + gMSA + dMSA objects (recursive) in `Tier X Service Accounts` OU | — |
| 2 | Add each to `TierXServiceAccounts` group | **YES** — skip excluded objects |
| 3 | Assign `*- Tier X Authentication Policy` to each | **YES** — skip excluded; remove policy from excluded who have it |

**Object class filter:** `Get-ADObject -LDAPFilter '(|(objectClass=user)(objectClass=msDS-GroupManagedServiceAccount)(objectClass=msDS-DelegatedManagedServiceAccount))' -SearchBase <OU> -SearchScope Subtree`

> **Design note:** Do NOT use `Get-ADServiceAccount` — it may fail on domains without the DFL/KDS key for gMSA/dMSA. Use `Get-ADObject` with LDAP filter and trap any errors gracefully. The `objectClass=user` filter also captures standard MSA objects (standalone managed service accounts inherit from `user`).

### 4.3 Tier 0/1 PAW Devices (`-Tier0PawDevices`, `-Tier1PawDevices`)

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate ALL computer objects (recursive) in `Tier X PAW Devices` OU | — |
| 2 | Add each to `TierXPAWDevices` group | **NO** — exclusions never apply to computers |

No policy assignment for computers (policies are assigned via device group SDDL, not direct assignment).

### 4.4 Tier 0/1 Member Servers (`-Tier0MemberServers`, `-Tier1MemberServers`)

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate ALL computer objects (recursive) in `Tier X Member Servers` OU, **EXCLUDING** the `Tier X Server Staging` child OU | — |
| 2 | Add each to `TierXMemberServers` group | **NO** |

**OU exclusion technique:** Use `-SearchBase` on the parent OU with `-SearchScope Subtree`, then filter results where `DistinguishedName` does NOT end with the Staging OU DN. Alternatively, enumerate all immediate child OUs, skip the Staging OU, and recurse each remaining child separately. The former (post-filter) is simpler and more reliable.

### 4.5 Tier 0/1 Staging (`-Tier0Staging`, `-Tier1Staging`)

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate ALL computer objects in `Tier X Server Staging` OU (direct children only — staging is flat) | — |
| 2 | Add each to `TierXMemberServers` group (same target group as `-TierXMemberServers`) | **NO** |

### 4.6 Tier 2 Operators (`-Tier2Operators`)

This is the most complex switch due to the EUD/Operator split.

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate ALL user objects (recursive) in `Tier 2 Accounts` OU | — |
| 2 | Read current membership of `Tier2LocalDeviceOperators` group (cache as HashSet) | — |
| 3 | For each user: if user is in `Tier2LocalDeviceOperators` → **SKIP** (they are EUD, handled by `-Tier2Eud`) | — |
| 4 | Add remaining users to `Tier2Operators` group | **NO** — all non-EUD tier users are operators |
| 5 | Assign `*- Tier 2 Authentication Policy` to each operator | **YES** — skip excluded; remove policy from excluded who have it |

**Conflict rule:** If a user is in BOTH `Tier2Operators` AND `Tier2LocalDeviceOperators` (customer misconfig), treat as Tier2Operator — the Tier 2 policy wins. Rationale: a user in Tier2Operators can't be an EUD local admin anyway because both URA and the silo would block them. Better to have *some* policy than none.

### 4.7 Tier 2 EUD (`-Tier2Eud`)

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate members of `Tier2LocalDeviceOperators` group | — |
| 2 | For each member: if user is ALSO in `Tier2Operators` → **SKIP** (operator wins; single-valued `msDS-AssignedAuthNPolicy`) | — |
| 3 | Assign `*- Tier 2 EUD Authentication Policy` to each remaining LDO member | **YES** — skip excluded; remove policy from excluded who have it |

> **Key:** `-Tier2Eud` does NOT add users to any group. It only assigns the EUD policy to existing `Tier2LocalDeviceOperators` members. LDO membership is customer-curated.

### 4.8 Tier 2 Service Accounts (`-Tier2ServiceActt`)

Same pattern as Tier 0/1 Service Accounts, targeting `Tier 2 Service Accounts` OU → `Tier2ServiceAccounts` group + `*- Tier 2 Authentication Policy`.

### 4.9 Tier 2 PAW Devices (`-Tier2PawDevices`)

Same pattern as Tier 0/1 PAW Devices, targeting `Tier 2 PAW Devices` OU → `Tier2PAWDevices` group.

### 4.10 Tier 2 EUD Devices (`-Tier2EudDevices`)

| Step | Action | Exclusion Applies? |
|------|--------|--------------------|
| 1 | Enumerate ALL computer objects (recursive) in `Tier 2 End-User Devices` OU, **EXCLUDING** the `Disabled End-User Devices` child OU | — |
| 2 | Add each to `Tier2EUDDevices` group | **NO** |

**OU exclusion:** Same technique as Member Servers — post-filter to exclude `OU=Disabled End-User Devices,...` DNs.

---

## 5. Tier 2 Operator-vs-EUD Truth Table

Because `msDS-AssignedAuthNPolicy` is **single-valued** (one policy per account), the script must deterministically resolve which policy wins.

| In Tier2Operators? | In Tier2LocalDeviceOperators? | Policy Assigned | Switch Owner | Rationale |
|---|---|---|---|---|
| No | No | `*- Tier 2 Authentication Policy` | `-Tier2Operators` adds to Operators, assigns policy | New user defaults to operator |
| Yes | No | `*- Tier 2 Authentication Policy` | `-Tier2Operators` assigns policy | Standard operator |
| No | Yes | `*- Tier 2 EUD Authentication Policy` | `-Tier2Eud` assigns EUD policy | Standard EUD local admin |
| Yes | Yes | `*- Tier 2 Authentication Policy` | `-Tier2Operators` assigns; `-Tier2Eud` skips | Operator wins (misconfig) |

**Execution order dependency:** When `-All` or `-AllTier2` runs both `-Tier2Operators` and `-Tier2Eud`, the order must be:
1. `-Tier2Operators` first — adds new users to Tier2Operators, assigns Tier 2 policy
2. `-Tier2Eud` second — checks Tier2Operators membership (now current), assigns EUD policy only to non-operators

This ordering is **mandatory** and must be documented in the script's execution flow.

---

## 6. Exclusion Model

### 6.1 Built-In Exclusions (Always Active)

The three domain-join service accounts are **ALWAYS** excluded from Authentication Policy assignment, regardless of whether `-ExclusionAttribute` is provided.

**Identification:** By `sAMAccountName` from `config/tiermodel-users.json`:
- `svc-pawdomainjoin`
- `svc-t1srvdomainjoin`
- `svc-t2euddomainjoin`

**Enforcement (Step 0 — runs FIRST every execution):**
1. Look up each account by `sAMAccountName`.
2. Read `msDS-AssignedAuthNPolicy`.
3. If any policy is assigned → **REMOVE IT** (clear `msDS-AssignedAuthNPolicy`).
4. Log the remediation action.

> **OPEN QUESTION (OQ-2):** Should the script also stamp the customer exclusion marker (e.g., `extensionAttribute15 = "TierExclude"`) on these accounts as a belt-and-suspenders measure? Pro: a second exclusion path catches edge cases. Con: modifying an attribute the customer controls may surprise them. **Recommend:** Do not stamp — the built-in check by `sAMAccountName` is authoritative and the marker is for customer-defined exclusions only.

### 6.2 Customer Exclusions (Optional)

When `-ExclusionAttribute` and `-ExclusionValue` are provided:

| Context | Exclusion applies? |
|---------|-------------------|
| Policy assignment (all account types) | **YES** — skip assignment; remove policy if present |
| ServiceAccounts group membership | **YES** — skip group add |
| Operators group membership | **NO** — all tier users must be in the operator group |
| Computer group membership | **NO** — exclusions never apply to computers |

**Check:** `(Get-ADObject).Properties[$ExclusionAttribute] -eq $ExclusionValue`

### 6.3 Enforcement: Remove Policy from Excluded Objects

To honor "confirm still excluded each run," the script must:
1. For every object where exclusion applies to policy assignment:
   - If the object has `msDS-AssignedAuthNPolicy` set to a Tier Model policy → **CLEAR IT**.
   - Log: `"Removed policy '<PolicyName>' from excluded object '<sAMAccountName>'"`.
2. This ensures that if an admin manually assigns a policy to an excluded object, the next run cleans it up.

### 6.4 Group Membership: Additive-Only in v1

- The script **adds** objects to groups but does **not remove** them.
- If an excluded service account is already in a group, it stays. Removal is a v2 feature.
- Deprovisioning (objects that left a Tier OU) is **out of scope** for v1.

> **OPEN QUESTION (OQ-3):** Joel to confirm: additive-only for groups in v1, enforced for policy assignment? The existing legacy scripts (`Update-Tier0MemberServers.ps1`) DO remove non-OU computers from groups. Should this script follow that precedent or stay additive-only?

---

## 7. Execution Flow

```
┌──────────────────────────────────────────────────────────────┐
│ PHASE 0: VALIDATION                                         │
│  1. Validate config files exist and parse correctly          │
│  2. Resolve {{DOMAIN_DN}} → actual domain DN                │
│  3. Validate domain reachability (Get-ADDomain)              │
│  4. Validate all referenced OUs exist in AD                  │
│  5. Validate all referenced groups exist in AD               │
│  6. Validate all referenced Authentication Policies exist    │
│  7. Validate ExclusionAttribute/ExclusionValue params        │
│  8. If ANY validation fails → ABORT (no partial execution)   │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE 1: BUILT-IN EXCLUSION ENFORCEMENT                     │
│  For each of the 3 domain-join svc accounts:                │
│    - Read msDS-AssignedAuthNPolicy                          │
│    - If policy assigned → REMOVE (clear attribute)          │
│    - Log action                                              │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE 2: RECONCILIATION (per active switch)                 │
│  Execution order (mandatory when multiple switches):        │
│    1. Tier0Operators                                        │
│    2. Tier0ServiceActt                                      │
│    3. Tier0PawDevices                                       │
│    4. Tier0MemberServers                                    │
│    5. Tier0Staging                                          │
│    6. Tier1Operators                                        │
│    7. Tier1ServiceActt                                      │
│    8. Tier1PawDevices                                       │
│    9. Tier1MemberServers                                    │
│   10. Tier1Staging                                          │
│   11. Tier2Operators    ← MUST run before Tier2Eud          │
│   12. Tier2Eud          ← checks Tier2Operators membership  │
│   13. Tier2ServiceActt                                      │
│   14. Tier2PawDevices                                       │
│   15. Tier2EudDevices                                       │
│                                                              │
│  Per switch:                                                 │
│    a. Enumerate source OU (with exclusion filters)          │
│    b. Read current group membership (cache as HashSet)      │
│    c. Add missing objects to group (if switch does groups)   │
│    d. Assign policy to non-excluded objects                  │
│    e. Remove policy from excluded objects that have it       │
│    f. Accumulate per-switch counters                         │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE 3: SUMMARY                                            │
│  Per-switch and aggregate counters:                         │
│    Scanned / Added-to-group / Policy-assigned /             │
│    Excluded / Policy-removed / Errors / Already-current     │
│  Write to log file + console + optional Event Log           │
└──────────────────────────────────────────────────────────────┘
```

### Idempotency Guarantees

| Scenario | Behavior |
|----------|----------|
| Empty groups + no policy assignments → run | Converges: all objects added, all policies assigned |
| Re-run immediately after | Zero changes: all objects already in groups, all policies already assigned |
| Add 5 new objects to OU → run | Exactly 5 added to group, 5 policies assigned |
| Mark 2 objects as excluded → run | 2 policies removed, groups unchanged (additive-only v1) |

### Performance Optimization

- Cache group membership as `HashSet<string>` (DN, case-insensitive) at switch start — avoids per-object `Get-ADGroupMember` calls.
- Cache `Tier2LocalDeviceOperators` and `Tier2Operators` membership once for Tier 2 switches.
- Use single `Get-ADObject` query per OU with LDAP filter (not per-object queries).
- Batch `Add-ADGroupMember` where possible (the cmdlet accepts arrays).
- Read `msDS-AssignedAuthNPolicy` in the initial object query (`-Properties msDS-AssignedAuthNPolicy`) to avoid a second round-trip.

---

## 8. Execution & Security Model

### DECIDED: Local Scheduled Task on DC, SYSTEM Context (Recommended)

The recommended execution model is a **local scheduled task on a Domain Controller** running as `NT AUTHORITY\SYSTEM`.

#### Why DC + SYSTEM Is Safe and Correct

The script-hijack risk that applies to GPO scripts does **NOT** apply to local scheduled tasks:

- **GPO startup/shutdown/logon scripts** live on SYSVOL/NETLOGON — readable by all authenticated users and editable if the share/object ACL is misconfigured, even without rights on the GPO itself. That is the real hijack vector.
- **A local scheduled-task script** on the DC's local disk has none of that exposure. The script is not on a share, not replicated, and not accessible to non-admin principals.
- **If an attacker already has a local/interactive session on a DC, the domain is already fully compromised.** A local script adds zero marginal risk in that scenario.
- **SYSTEM context is the cleanest identity choice.** On a DC, SYSTEM is effectively the Domain Controller computer account (Domain Admin equivalent). This is *cleaner* than creating a dedicated service account and placing it into Domain Admins / Builtin Administrators / Enterprise Admins, or managing a separate password lifecycle. No managed/non-expiring password. No service account sprawl.

#### Primary Model: DC + Local Scheduled Task + SYSTEM

| Aspect | Detail |
|--------|--------|
| Run on | Domain Controller |
| Identity | `NT AUTHORITY\SYSTEM` |
| Script location | Local disk path on the DC (e.g., `C:\TierModel\Scripts\`) — **NOT** SYSVOL, NETLOGON, or any network share |
| AD module | Always available on DCs (RSAT-AD-PowerShell is a DC role feature) |
| Connectivity | Localhost — no cross-server authentication needed |

#### Script-Integrity Hardening (CRITICAL)

The security of a local scheduled task is the **integrity of the script file itself**. These controls are mandatory:

1. **Protected local path with tight NTFS ACL:**
   - Script directory ACL: `SYSTEM` (Full Control) + `BUILTIN\Administrators` (Full Control) — no other principals.
   - Remove inherited permissions from the script directory.
   - No broad write access (no `Authenticated Users`, no `Domain Users`, no `Everyone`).

2. **Authenticode code-signing (recommended):**
   - Sign the script with a code-signing certificate trusted on the DC.
   - Set execution policy to `AllSigned` on the DC (or at minimum, configure the scheduled task action to run `powershell.exe -ExecutionPolicy AllSigned -File <path>`).
   - Any unauthorized modification breaks the signature → script refuses to execute.

3. **Never store on SYSVOL or NETLOGON:**
   - SYSVOL is replicated to all DCs and writable by Domain Admins — a broader attack surface than a single DC's local disk.
   - NETLOGON is a SYSVOL child share — same exposure.

4. **Scheduled task configuration:**
   - "Run whether user is logged on or not"
   - "Run with highest privileges"
   - "Do not store password" (SYSTEM does not need one)
   - Trigger: daily/hourly as appropriate for the customer's change rate

5. **Transcript logging:**
   - Enable PowerShell transcript logging for the scheduled task for forensic audit trail.

#### Alternative: Off-DC Execution (Optional, Not Recommended)

For organizations that specifically want the reconciliation automation off the DCs:

| Aspect | Detail |
|--------|--------|
| Run on | Tier 0 management server or PAW |
| Identity | Dedicated gMSA (e.g., `gMSA-TierReconcile$`) — **never** a plain password-based service account |
| Delegation required | `Write Member` on the 13 Tier groups; `Write msDS-AssignedAuthNPolicy` on accounts in the 6 Accounts/Service Accounts OUs; `Read` on all Tier OUs |
| Trade-offs | Requires gMSA creation + delegation setup; cross-server authentication; management host must be Tier 0; same script-integrity hardening applies on the management host |

> **Note:** If running off-DC, the identity must be the management host's computer account (`YOURHOST$`) or a gMSA. Never use a plain service account with a stored/non-expiring password for cross-server Tier 0 automation.

---

## 9. Error Handling & Fail-Safety

### Hard Failures (Abort Entire Run)

- Config file missing or unparseable
- `{{DOMAIN_DN}}` resolution fails
- Domain not reachable (`Get-ADDomain` fails)
- Any referenced OU / group / Authentication Policy does not exist in AD
- `ActiveDirectory` module not available

### Soft Failures (Log + Continue)

- Individual object fails to add to group (e.g., replication lag, transient error)
- Individual policy assignment fails
- Individual object query fails

### Fail-Safe Rules

1. **Never touch objects outside Tier Model OUs.** All operations are scoped by `-SearchBase` to specific OUs.
2. **Never mass-remove on transient AD errors.** Group membership is additive-only. Policy removal is per-object, not bulk.
3. **Validate before act.** Every OU, group, and policy is validated in Phase 0 before any modifications.
4. **Per-object try/catch.** Individual object failures do not abort the switch or the run.
5. **Counters track errors.** The summary reports error counts so operators can investigate.

---

## 10. Logging

### File Logging

- Path: `$env:LOCALAPPDATA\Update-TierModelMembership.log` (follows existing script pattern)
- Format: `<ISO8601>, [<Severity>], <Message>`
- Rotation: rename to `.sav` when exceeding 1 MB (matches existing pattern)
- Severities: `Error`, `Warning`, `Information`, `Debug`

### Console Output

- `-WhatIf` / `-ReportOnly`: prefixed with `[WhatIf] Would ...` for each action
- Normal run: per-switch progress + final summary table

### Summary Output (per run)

```
╔══════════════════════════════════════════════════════════════╗
║ Update-TierModelMembership — Run Summary                    ║
╠══════════════════════════════════════════════════════════════╣
║ Switch              Scanned  Added  Policy  Excl  Removed  ║
║ Tier0Operators          12      3       3     0       0    ║
║ Tier0ServiceActt        14      2       2     2       1    ║
║ Tier0PawDevices          8      1       —     —       —    ║
║ Tier0MemberServers      10      0       —     —       —    ║
║ ...                                                        ║
║ TOTAL                  134     12      18     4       2    ║
╠══════════════════════════════════════════════════════════════╣
║ Built-in exclusions enforced: 3 (0 policies removed)       ║
║ Errors: 0                                                   ║
║ Duration: 4s                                                ║
╚══════════════════════════════════════════════════════════════╝
```

### Optional: Windows Event Log

Write summary to `Application` log with source `TierModelReconciliation` (or use existing `Application` source per legacy pattern). One event per run: EventID 1000 (success) or 1001 (errors occurred). Per-object events are excessive and should remain file-only.

---

## 11. Lab Test Matrix

### Test Environment Setup

- **ExclusionAttribute:** `extensionAttribute15` (recommended lab default — no Exchange schema dependency; available on all AD schemas since Windows Server 2000)
- **ExclusionValue:** `TierExclude`
- **Note:** In production, customers may choose any existing AD attribute (e.g., `department`, `info`, `seeAlso`, `extensionAttribute1-15`, or any custom schema extension). The script does NOT assume Exchange schema is present.

### Test Data Population

#### Tier 0/1 (symmetric — test both identically)

| OU | Object Type | Count | Excluded | Notes |
|----|------------|-------|----------|-------|
| Tier X Accounts | user | 10 | 0 | All become operators; all get policy |
| Tier X Service Accounts | user | 10 | 2 | 2 have `extensionAttribute15=TierExclude` |
| Tier X Service Accounts | msDS-GroupManagedServiceAccount | 10 | 2 | 2 excluded |
| Tier X Service Accounts | msDS-DelegatedManagedServiceAccount | 10 | 2 | 2 excluded (requires Windows Server 2025 DFL) |
| Tier X Service Accounts | managedServiceAccount (MSA) | 10 | 2 | 2 excluded; MSA objectClass inherits from `user` |
| Tier X PAW Devices | computer | 10 | — | No exclusions for computers |
| Tier X Member Servers | computer | 10 | — | EXCLUDE Staging child OU |
| Tier X Server Staging | computer | 5 | — | Go into TierXMemberServers group |

#### Tier 2

| OU / Group | Object Type | Count | Excluded | Notes |
|-----------|------------|-------|----------|-------|
| Tier 2 Accounts | user — already in Tier2Operators | 10 | 0 | Should get Tier 2 policy, stay in group |
| Tier 2 Accounts | user — already in Tier2LocalDeviceOperators | 10 | 0 | Should get EUD policy; NOT added to Operators |
| Tier 2 Accounts | user — in NO group | 10 | 2 | 8 should become Operators + get Tier 2 policy; 2 excluded skip policy |
| Tier 2 Accounts | user — in BOTH Operators + LDO | 2 | 0 | Conflict test: should get Tier 2 policy (operator wins) |
| Tier 2 Service Accounts | user | 10 | 2 | Same as Tier 0/1 pattern |
| Tier 2 Service Accounts | gMSA | 10 | 2 | Same pattern |
| Tier 2 Service Accounts | dMSA | 10 | 2 | Same pattern |
| Tier 2 Service Accounts | MSA | 10 | 2 | Same pattern |
| Tier 2 PAW Devices | computer | 10 | — | No exclusions |
| Tier 2 End-User Devices | computer | 10 | — | EXCLUDE Disabled End-User Devices child OU |
| Disabled End-User Devices | computer | 3 | — | Must NOT appear in Tier2EUDDevices group |

#### Built-In Exclusion Objects

| Account | OU | Test |
|---------|-----|------|
| `svc-pawdomainjoin` | Tier 0 Service Accounts | Never gets policy; if manually assigned → script removes it |
| `svc-t1srvdomainjoin` | Tier 1 Service Accounts | Same |
| `svc-t2euddomainjoin` | Tier 2 Service Accounts | Same |

### Test Scenarios & Expected End-States

#### Scenario 1: Initial Convergence (empty → populated)

**Precondition:** All 13 Tier groups are empty. No accounts have `msDS-AssignedAuthNPolicy` set.

**Run:** `.\Update-TierModelMembership.ps1 -All -ExclusionAttribute extensionAttribute15 -ExclusionValue TierExclude`

**Expected End-State — Tier 0 (Tier 1 identical):**

| Group | Expected Members | Count |
|-------|-----------------|-------|
| `Tier0Operators` | All 10 Tier 0 Accounts users | 10 |
| `Tier0ServiceAccounts` | 10 users + 10 MSA + 10 gMSA + 10 dMSA − 8 excluded = 32 | 32 |
| `Tier0MemberServers` | 10 Member Servers computers + 5 Staging computers = 15 | 15 |
| `Tier0PAWDevices` | 10 PAW computers | 10 |

| Policy Assignment | Count |
|-------------------|-------|
| `*- Tier 0 Authentication Policy` assigned | 10 operators + 32 non-excluded service accounts = 42 |
| Excluded service accounts (no policy) | 8 (2 user + 2 MSA + 2 gMSA + 2 dMSA) |
| Built-in excluded (no policy) | 1 (`svc-pawdomainjoin`) |

**Expected End-State — Tier 2:**

| Group | Expected Members | Count |
|-------|-----------------|-------|
| `Tier2Operators` | 10 already-in + 8 new (10 no-group minus 2 excluded) + 2 conflict = 20 | 20 |
| `Tier2ServiceAccounts` | 32 (same pattern as Tier 0) | 32 |
| `Tier2PAWDevices` | 10 | 10 |
| `Tier2EUDDevices` | 10 (excluding Disabled OU) | 10 |
| `Tier2LocalDeviceOperators` | 10 (UNCHANGED — script does not manage this group) | 10 |

| Policy Assignment | Count |
|-------------------|-------|
| `*- Tier 2 Authentication Policy` | 20 operators + 32 service accounts = 52 |
| `*- Tier 2 EUD Authentication Policy` | 10 LDO members − 2 conflict (also in Operators) = 8 |
| Excluded (no policy) | 2 operator-excluded + 8 svc-excluded + 1 built-in = 11 |

**Verification Commands:**
```powershell
# Group membership count
(Get-ADGroupMember -Identity 'Tier0Operators').Count  # → 10
(Get-ADGroupMember -Identity 'Tier0ServiceAccounts').Count  # → 32

# Policy assignment check
Get-ADUser -SearchBase '<Tier0AccountsOU>' -Filter * -Properties msDS-AssignedAuthNPolicy |
    Where-Object { $_.'msDS-AssignedAuthNPolicy' } | Measure-Object  # → 10

# Exclusion check
Get-ADUser -Identity 'svc-pawdomainjoin' -Properties msDS-AssignedAuthNPolicy |
    Select-Object msDS-AssignedAuthNPolicy  # → empty/null

# Tier 2 conflict check
Get-ADUser -Identity '<conflict-user>' -Properties msDS-AssignedAuthNPolicy |
    Select-Object msDS-AssignedAuthNPolicy  # → *- Tier 2 Authentication Policy (not EUD)
```

#### Scenario 2: Idempotency (re-run → zero changes)

**Precondition:** Scenario 1 completed successfully.

**Run:** Same command as Scenario 1.

**Expected:** Summary shows `Added: 0`, `Policy-assigned: 0`, `Removed: 0`, `Errors: 0` for every switch. Console output indicates "already current" for all objects.

**Verification:** Compare group membership counts and policy assignments — identical to Scenario 1.

#### Scenario 3: Incremental Addition (5 new objects)

**Precondition:** Scenario 2 completed (stable state).

**Action:** Create 5 new objects per OU per type:
- 5 new users in each Tier X Accounts OU
- 5 new users + 5 gMSA in each Tier X Service Accounts OU
- 5 new computers in each PAW/MemberServers/EUD OU

**Run:** Same command.

**Expected:**
- Tier 0 Operators: 10 → 15 (+5)
- Tier 0 Service Accounts: 32 → 42 (+10: 5 users + 5 gMSA)
- Tier 0 PAW Devices: 10 → 15 (+5)
- Tier 0 Member Servers: 15 → 20 (+5)
- Tier 2 EUD Devices: 10 → 15 (+5)
- Summary shows exactly the expected additions per switch.

#### Scenario 4: Built-In Exclusion Remediation

**Precondition:** Stable state.

**Action:** Manually assign a policy to `svc-pawdomainjoin`:
```powershell
Set-ADUser -Identity 'svc-pawdomainjoin' -AuthenticationPolicy '*- Tier 0 Authentication Policy'
```

**Run:** Same command.

**Expected:** Phase 1 detects the assignment and removes it. Log: `"Removed policy '*- Tier 0 Authentication Policy' from built-in excluded account 'svc-pawdomainjoin'"`. `svc-pawdomainjoin` has no policy after the run.

#### Scenario 5: Customer Exclusion Enforcement

**Precondition:** Stable state.

**Action:** Mark a previously-assigned Tier 0 service account as excluded:
```powershell
Set-ADUser -Identity 'svc-test01' -Replace @{extensionAttribute15 = 'TierExclude'}
```

**Run:** Same command.

**Expected:** `svc-test01`'s `msDS-AssignedAuthNPolicy` is cleared. `svc-test01` remains in `Tier0ServiceAccounts` group (additive-only v1). Summary shows `Excluded: +1`, `Removed: +1` for `Tier0ServiceActt`.

#### Scenario 6: Tier 2 Operator/EUD Split

**Precondition:** Clean Tier 2 state.

**Test matrix (per-user outcomes):**

| User | Tier2Operators? | Tier2LDO? | Excluded? | Expected Group Add | Expected Policy |
|------|----------------|-----------|-----------|-------------------|----------------|
| u01 | No | No | No | → Tier2Operators | `*- Tier 2 Authentication Policy` |
| u02 | No | No | Yes | → Tier2Operators (excl doesn't apply to groups) | NONE (excluded) |
| u03 | Yes | No | No | Already in | `*- Tier 2 Authentication Policy` |
| u04 | No | Yes | No | NOT added to Operators | `*- Tier 2 EUD Authentication Policy` |
| u05 | No | Yes | Yes | NOT added to Operators | NONE (excluded) |
| u06 | Yes | Yes | No | Already in Operators | `*- Tier 2 Authentication Policy` (operator wins) |
| u07 | Yes | Yes | Yes | Already in Operators | NONE (excluded from policy only) |

#### Scenario 7: Single-Switch Scheduling

**Run:** `.\Update-TierModelMembership.ps1 -Tier1MemberServers`

**Expected:** Only Tier 1 Member Servers OU is scanned. Only `Tier1MemberServers` group is touched. No other tiers/groups/policies are affected. Built-in exclusion enforcement (Phase 1) still runs (always runs).

#### Scenario 8: OU Exclusion (Staging / Disabled)

**Precondition:** 3 computers in `Tier 0 Server Staging` OU. 3 computers in `Disabled End-User Devices` OU.

**Run with -Tier0MemberServers:** Staging computers must NOT appear in results. 

**Run with -Tier0Staging:** ONLY Staging computers appear.

**Run with -Tier2EudDevices:** Disabled End-User Devices computers must NOT appear.

**Verification:**
```powershell
# After -Tier0MemberServers:
Get-ADGroupMember 'Tier0MemberServers' | Where-Object {
    $_.DistinguishedName -like '*Staging*'
}  # → empty (staging excluded)

# After -Tier0Staging:
Get-ADGroupMember 'Tier0MemberServers' | Where-Object {
    $_.DistinguishedName -like '*Staging*'
}  # → 3 staging computers now present
```

---

## 12. Considerations & Design Decisions

### C1: PowerShell Version Compatibility

Target Windows PowerShell 5.1. Do NOT use:
- `??` (null-coalescing)
- `??=` (null-coalescing assignment)
- `?.` (null-conditional)
- Ternary operator `? :`
- `ForEach-Object -Parallel`
- Classes with constructors (use `[PSCustomObject]` instead)
- `$PSStyle` (PS7 only)

DO use: `[System.Collections.Generic.HashSet[string]]`, `Import-Module ActiveDirectory`, `$PSCmdlet.ShouldProcess()`.

### C2: dMSA Object Class Availability

`msDS-DelegatedManagedServiceAccount` requires Windows Server 2025 DFL. The LDAP filter includes it, but the script must not fail if no dMSA objects exist (the filter simply returns zero results). Test matrix includes dMSA to validate graceful handling on pre-2025 DFLs.

### C3: Config Loading Strategy

The script should use a lightweight config loader (not the full module's `Get-TierModelConfig`). It reads 4 JSON files directly, resolves `{{DOMAIN_DN}}`, and builds a lookup table. This avoids a dependency on the TierModel module being installed (the script lives in `optional/` and may run standalone).

### C4: Relationship to Existing Legacy Scripts

The `optional/TierModel-AuthSilos/` directory contains 6 legacy per-tier scripts. `Update-TierModelMembership.ps1` is designed to **replace** all of them with a single unified script. The legacy scripts should be marked as deprecated once this script is validated. The plan does NOT delete them — that is a separate PR.

### C5: WhatIf / ReportOnly Behavior

`-WhatIf` (inherited from `SupportsShouldProcess`) and `-ReportOnly` both produce read-only output. `-ReportOnly` additionally outputs a structured `[PSCustomObject]` summary suitable for pipeline consumption (e.g., export to CSV for scheduled-task monitoring).

---

## 13. Open Questions

### OQ-1: Tier 2 New-User Default — Operator or LocalDeviceOperator?

**Context:** Joel's test-matrix line mentions "create 10 users that should get added to Tier 2 local device operators." However, by the switch semantics defined above, a brand-new user in the Tier 2 Accounts OU with no group membership would default to **Tier2Operators** (not Tier2LocalDeviceOperators), because `-Tier2Operators` adds all non-LDO users to the Operators group.

The script **cannot guess** a human's EUD-vs-admin intent for a new user.

**Options:**
- **(A) Default to Operators** (current design): new Tier 2 users become operators unless the customer pre-stages them into `Tier2LocalDeviceOperators`. This is safer — operator policy is more restrictive than EUD.
- **(B) Require pre-staging:** The customer must add users to `Tier2LocalDeviceOperators` before the script runs, or they become operators by default.
- **(C) Separate marker attribute:** Add a second attribute check (e.g., `extensionAttribute14 = "EUD"`) to designate EUD intent. Adds complexity.

**Recommendation:** Option A/B (they are equivalent). Document that `Tier2LocalDeviceOperators` membership is a prerequisite for EUD policy assignment. The script logs a warning for new users defaulting to Operators.

**Joel must clarify** his test-matrix intent: does "should get added to Tier 2 local device operators" mean the TEST SETUP pre-stages them, or the SCRIPT should add them?

### OQ-2: Stamp Exclusion Marker on Built-In Accounts?

**Question:** Should the script write `extensionAttribute15 = "TierExclude"` (or whatever the customer chose) on the 3 domain-join accounts as a defense-in-depth measure?

**Recommendation:** No. See §6.1 rationale. The `sAMAccountName`-based check is authoritative and the marker is for customer-defined exclusions only. Let Joel confirm.

### OQ-3: Group Membership — Additive-Only or Enforce?

**Question:** Should the script remove objects from groups when they no longer belong (e.g., a computer moved out of the OU but is still in the group)?

**Context:** The legacy `Update-Tier0MemberServers.ps1` DOES remove non-OU computers from groups. The new script defaults to additive-only in v1 for safety.

**Recommendation:** Additive-only for v1. Add removal as a `-EnforceGroupMembership` switch in v2 with a separate `-WhatIf` pass. Joel to confirm.

### OQ-4: Tier 0/1 Staging SearchScope

**Question:** Should `-TierXStaging` use `-SearchScope OneLevel` (flat — staging OU has no children) or `-SearchScope Subtree` (recursive — future-proof if someone creates sub-OUs)?

**Recommendation:** `Subtree` for consistency with all other switches. The Staging OU config has no children today, but Subtree is safe and forward-compatible.

### OQ-5: Protected Users Group

**Question:** The legacy `Update-Tier0AuthSiloUsers.ps1` adds Tier 0 users to the Protected Users group and marks them as "sensitive and cannot be delegated." Should this script replicate that behavior?

**Recommendation:** Out of scope for v1. Protected Users membership and `AccountNotDelegated` are separate security controls with their own operational implications. They should be a separate optional feature, not bundled into group/policy reconciliation. Joel to confirm.

### OQ-6: Multi-Domain Forest Support

**Question:** The legacy scripts have a `-MultiDomainForest` switch. Should this script support multi-domain forests?

**Recommendation:** Single-domain only for v1. Multi-domain adds significant complexity (cross-domain group membership, GC queries, per-domain policy resolution). Document as a v2 feature. Joel to confirm.

### Decided (No Longer Open)

- **Execution Security Model:** DECIDED — Local scheduled task on DC, SYSTEM context. See §8. GPO/SYSVOL script-hijack risk does not apply to local scheduled tasks; script-integrity hardening (ACL + code signing) is the real control.

---

## 14. File Dependencies

```
optional/
├── Update-TierModelMembership.ps1          ← THE NEW SCRIPT
└── TierModel-AuthSilos/
    ├── Update-Tier0AuthSiloUsers.ps1       ← LEGACY (to be deprecated)
    ├── Update-Tier0MemberServers.ps1       ← LEGACY
    ├── Update-Tier0PAWDevices.ps1          ← LEGACY
    ├── Update-Tier1AuthSiloUsers.ps1       ← LEGACY
    ├── Update-Tier1MemberServers.ps1       ← LEGACY
    ├── Update-Tier1PAWDevices.ps1          ← LEGACY
    ├── Deploy-TierModelAuthSilo.ps1
    ├── ScheduleTask-GPO/
    └── ScheduleTask-Local/

config/
├── tiermodel-ous.json                      ← OU paths
├── tiermodel-groups.json                   ← Group definitions
├── tiermodel-authsilos.json                ← Policy names
└── tiermodel-users.json                    ← Built-in exclusion accounts
```

---

*End of design plan. No code to be written until Joel approves this plan and resolves the open questions.*


---

## 15. Rubber-Duck Review Findings (2026-08-27, Gemini) — fold into plan before coding

### Critical (fix in plan before coding)
1. **Tier 2 truth-table contradiction (§4.6 vs §5).** §4.6 Step 3 skips any user in Tier2LocalDeviceOperators, but §5 row 4 (user in BOTH groups) requires -Tier2Operators to ASSIGN. As written, a both-groups user is skipped by both switches and gets NO policy. FIX: §4.6 Step 3 = skip only if "in LDO AND NOT already in Tier2Operators." Then the both-groups user correctly receives the Tier 2 (operator) policy per the truth table.
2. **Built-in exclusion flap in enumeration (§6.1 vs §4.2).** Phase 0 clears the policy from the 3 domain-join accounts, but the Service Accounts enumeration only checks the customer ExclusionAttribute, so it will re-assign the Tier policy to a built-in account living in a Service Accounts OU, and Phase 0 removes it next run -> flap every run. FIX: enumeration phases MUST filter the 3 built-in sAMAccountNames before any group/policy action (built-in exclusion applies everywhere, not just Phase 0).

### High (lifecycle / idempotency)
3. **Additive-only demotion hole (OQ-3).** An account/computer moved OUT of a Tier OU keeps its group membership + policy forever (privilege never revoked). v1 minimum: enumerate each TierX group and WARN on members whose DN is no longer under the Tier X OU.
4. **Disabled EUD devices never leave the group.** Excluding the Disabled OU from enumeration only blocks new adds; additive-only means a device moved to Disabled stays in Tier2EUDDevices. Decide: accept in v1, or make the Disabled OU an explicit removal exception.
5. **CLI-param exclusions cause flapping.** If -ExclusionAttribute/-ExclusionValue are CLI params, any run/scheduled task that omits them re-assigns policies to excluded accounts and the next correct run removes them -> flap. RECOMMEND: move exclusion attribute/value into JSON config so every run shares one exclusion state. (Design change from CLI switches - Joel decides.)

### Medium
6. **Break-glass bypass.** Excluding an operator strips the policy but keeps them in TierXOperators, so they can administer the tier without PAW/silo enforcement. Confirm this is intended break-glass behavior; if not, policy exclusion should also skip the operator group.
7. **DN child-OU matching fragility.** Use a -like "*OU=Tier 0 Server Staging,*" wildcard for child-OU exclusion, not a strict DN-suffix string match (AD DN spacing can vary).

### Open-question validation
Duck agreed with all 6 recommendations: OQ-1 default-to-Operator (fail-secure), OQ-2 no marker stamp, OQ-3 additive-only-with-warnings, OQ-4 Subtree, OQ-5 Protected Users out of scope, OQ-6 single-domain v1.

### New decisions to add to Open Questions
- OQ-7: exclusion attribute/value in JSON config vs CLI params (flapping risk - finding #5).
- OQ-8: break-glass - operator-group-without-policy intended? (finding #6).
- OQ-3 expanded: additive-only + demotion warnings + Disabled-EUD removal exception (findings #3, #4).
