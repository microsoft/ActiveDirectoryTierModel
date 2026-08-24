# Best Practices, Governance & AD Hardening

This is a living, prescriptive best-practices reference for operating an Active Directory environment built on the Tier Model. Some items are Tier-Model-specific rules; others are general AD guidance that applies with or without the Tier Model.

**Deploying the Tier Model is not the finish line.** The Tier Model protects specific things — tier isolation of privileged credentials, OU structure, GPO configuration, and delegation controls — but Active Directory has many other areas that still require hardening after deployment. This page is the operational companion to the deployment guides for what comes next.

---

## Contents

1. [Part 1 — General AD Guidance](#part-1-general-ad-guidance)
   - [Group Management & Delegation](#group-management-delegation)
2. [Part 2 — AD Hardening Guidance](#part-2-ad-hardening-guidance)
   - [Patch & Vulnerability Management](#patch-vulnerability-management)
   - [Authentication Relay Attacks (NTLM)](#authentication-relay-attacks-ntlm)
   - [Kerberoasting & Service Accounts](#kerberoasting-service-accounts)
   - [Privileged Access & PAWs](#privileged-access-paws)
   - [Legacy Protocols & Attack Surface Reduction](#legacy-protocols-attack-surface-reduction)
   - [Monitoring & Detection](#monitoring-detection)
3. [Related Reading](#related-reading)

---

## Part 1 — General AD Guidance

### Group Management & Delegation

Active Directory groups — especially privileged and administrative groups — require governed ownership: a named, accountable account that manages membership. The `managedBy` attribute and the **"Manager can update membership list"** delegation provide exactly that.

**What it is.** Every AD group exposes a **Managed By** tab in Active Directory Users and Computers (ADUC). Setting the `managedBy` attribute to a specific admin account designates that account as the group's responsible owner. Enabling **"Manager can update membership list"** on that same tab adds a single Access Control Entry (ACE) to the group: write access to the `member` attribute, scoped only to that designated account.

The scope of the delegation is intentionally narrow. The manager can add and remove group members. They cannot rename the group, change its scope or type, modify its description, or perform any other group management operation. `managedBy` is a governance designation; `member` write is the operational delegation.

**Why it matters.** A named group manager creates separation of duties without expanding permanent privilege. An operations team manages membership for an admin group without being Domain Admins. A role owner curates their own group. A Just-in-Time workflow checks users in and out without any standing elevated access. This is an operational governance improvement that layers on top of the Tier Model without changing its architecture — no deployment script changes, no new Tier Model concepts.

> **Golden Rule: The `managedBy` account for a Tier N group must be a Tier N admin account.**
>
> Same tier, always. Never up. Never down. Never untiered.

**Why this rule is non-negotiable.** Credential exposure must match the sensitivity of the resource being managed.

- **Using a Tier 0 account to manage a Tier 1 or Tier 2 group** means checking out a Tier 0 credential to perform lower-tier work. That is not least privilege and not Just Enough Access (JEA). The Tier 0 credential is now in contact with the Tier 1 boundary, and any system it touches carries Tier 0 risk.
- **Using an untiered (non-Tier-Model) account** as the manager of any tiered group crosses a tier boundary. A cross-tier `managedBy` relationship is a control path an attacker can traverse from the untiered estate into the tier.
- **The correct assignment is same-tier, always:** Tier 0 group → Tier 0 admin account; Tier 1 group → Tier 1 admin account; Tier 2 group → Tier 2 admin account.

**Worked examples:**

| Group | Correct manager | Wrong: cross-tier | Wrong: untiered |
|---|---|---|---|
| `T0-Admins` | Tier 0 admin account | — | Any non-Tier-Model account — breaks tier isolation |
| `T1-ServerAdmins` | Tier 1 admin account | Tier 0 account — credential over-exposure, not JEA | Standard user / service account — tier boundary break |
| `T2-WorkstationAdmins` | Tier 2 admin account | Tier 0 or Tier 1 account — over-exposure | Standard user / service account — tier boundary break |

**Pairing with a PAW.** The manager account is most effective when restricted to log on only from a Privileged Access Workstation at the same tier. The tier's Account Restrictions GPO already enforces this for Tier Model accounts; ensure the manager account is placed in the correct Tier OU so the same Deny logon policy applies.

**Relationship to Just-in-Time.** The `managedBy` delegation complements JIT but does not require it. With JIT, the manager account triggers membership changes on demand without standing access. Without JIT, it creates a named, governed owner for each group — already a significant improvement over ad hoc Domain Admin membership edits.

---

*More general AD guidance is planned — Fine-Grained Password Policies for admin accounts, service account governance, OU delegation patterns. Suggestions welcome via GitHub issues.*

---

## Part 2 — AD Hardening Guidance

Even with the Tier Model deployed, AD hardening remains the operator's responsibility. The Tier Model establishes privileged access segmentation, OU structure, and delegation controls — it is a foundation, not a complete hardening programme. The items below are a starting checklist, not an exhaustive treatment; the authoritative how-to lives in the linked Microsoft guidance.

### Patch & Vulnerability Management

Unpatched AD DS components on domain controllers and member servers are among the most reliable attacker entry points in any enterprise. Prioritize Critical and Important CVEs against LDAP, Kerberos, Netlogon, and the Windows kernel. Domain controllers should reach patched state within days of a critical release — not weeks. No security control compensates for a known-unpatched remote code execution vulnerability on a DC.

### Authentication Relay Attacks (NTLM)

NTLM relay attacks — including coercion techniques such as PetitPotam — allow an attacker with limited initial access to impersonate domain accounts, including Domain Admins, against DC-exposed services. Enable LDAP signing and channel binding, and Extended Protection for Authentication (EPA) on IIS and Exchange endpoints. Plan a migration away from NTLM toward Kerberos across the environment. See the 2025 AD DS threat guidance in [Related Reading](#related-reading) for current prescriptive mitigation steps.

### Kerberoasting & Service Accounts

Service accounts with registered SPNs are offline-crackable via Kerberoasting — no elevated privilege required for the ticket request, and the traffic is indistinguishable from normal Kerberos use. Prefer **group Managed Service Accounts (gMSA)** or, where the domain functional level supports it, **delegated Managed Service Accounts (dMSA)** — both use system-managed, automatically-rotating passwords that are practically uncrackable offline. For legacy accounts that cannot yet migrate, enforce long (25+ character) random passwords and audit all SPN registrations.

### Privileged Access & PAWs

The Tier Model's containment guarantees are only as strong as the endpoints from which admin credentials are entered. A Privileged Access Workstation at the correct tier — hardened, network-segmented, dedicated to admin tasks only — prevents credential theft via keyloggers, clipboard capture, and lateral movement through compromised desktops. The Tier Model's Account Restrictions GPO and Deny logon framework are designed to enforce PAW use. See [GPO Management Guidance](gpo-management-guidance.md) for how the deny model is structured.

### Legacy Protocols & Attack Surface Reduction

Every unnecessary protocol is an attack surface. Audit and disable SMBv1, LLMNR, NetBIOS over TCP/IP, NTLMv1, and weak Kerberos cipher suites (RC4, DES). Disable the Print Spooler service on domain controllers — this removes both PrintNightmare exploitation and NTLM coercion vectors. The Tier Model's baseline GPO set covers many of these controls; confirm your chosen baseline is link-enabled.

### Monitoring & Detection

Hardening without visibility is incomplete. The Tier Model ships a [Microsoft Sentinel monitoring solution](sentinel-monitoring.md) for Tier-Model-specific detections — but Sentinel does not replace a full AD monitoring strategy. Confirm that Advanced Audit Policy and PowerShell audit logging GPOs are enabled on domain controllers (both ship enabled in the Tier Model). Every DC whose Security event log does not reach your SIEM is a blind spot, not partial coverage.

---

## Related Reading

**Microsoft authoritative guidance:**

- Microsoft Learn — **[Best practices for securing Active Directory](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/best-practices-for-securing-active-directory)** — the primary Microsoft reference for AD security architecture and practices.
- Windows Server Blog (Dec 2025) — **[Microsoft's guidance to help mitigate critical threats to Active Directory Domain Services in 2025](https://www.microsoft.com/en-us/windows-server/blog/2025/12/09/microsofts-guidance-to-help-mitigate-critical-threats-to-active-directory-domain-services-in-2025/)** — six critical threat categories with specific mitigations: NTLM relay, Kerberoasting, legacy protocols, patch hygiene, and more.
- Microsoft Tech Community — **[AD Hardening / AD Security series (Core Infrastructure and Security Blog)](https://techcommunity.microsoft.com/tag/adhardening?nodeid=board%3Acoreinfrastructureandsecurityblog)** — ongoing guidance from Microsoft field and product teams.

**Within this documentation:**

- **[GPO Management Guidance](gpo-management-guidance.md)** — Operational rules for the Tier Model GPO set, including the Account Restrictions GPO, baseline selection, and the SOE override surface.
- **[Canonical ACLs](canonical-acl.md)** — OU delegation and ACL correctness; background for understanding what the Tier Model protects at the OU level.
- **[Sentinel Monitoring](sentinel-monitoring.md)** — Out-of-the-box Microsoft Sentinel monitoring for a deployed Tier Model.

---

*This page began as a community best-practice request — [issue #33](https://github.com/microsoft/ActiveDirectoryTierModel/issues/33). Further best-practice contributions are welcome; open a GitHub issue with your suggestion.*
