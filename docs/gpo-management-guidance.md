# GPO Management Guidance & Best Practices

This page defines the operational rules for managing Group Policy Objects within the Active Directory Tier Model. It is prescriptive by design. The goal is a black-and-white model that eliminates grey custom configurations, keeps in-place upgrades working, and keeps the audit script accurate.

**This page covers operational practice.** For the JSON schema used to declare GPOs (modes, `importPath`, `gpoStatus`, URA/RG properties), see [GPO Management Strategy](gpo-management-strategy.md).

---

## Contents

1. [Overview & Philosophy](#1-overview-philosophy)
2. [The Golden Rules](#2-the-golden-rules)
3. [The GPO Layers & Precedence](#3-the-gpo-layers-precedence)
4. [Post-Deployment Configuration](#4-post-deployment-configuration)
5. [Choosing Your Security Baseline](#5-choosing-your-security-baseline)
6. [Windows Version Support](#6-windows-version-support)
7. [The SOE — Your Environment's Override Surface](#7-the-soe-your-environments-override-surface)
8. [Review Every Provided GPO — Use It or Leave It Unlinked](#8-review-every-provided-gpo-use-it-or-leave-it-unlinked)
9. [OU Design: Inheritance & Enforcement](#9-ou-design-inheritance-enforcement)
10. [Extending With Child OUs](#10-extending-with-child-ous)
11. [Migrating Applications In — Naming Convention](#11-migrating-applications-in-naming-convention)
12. [The Deny Model (User Rights)](#12-the-deny-model-user-rights)
13. [Template GPOs Reference](#13-template-gpos-reference)
14. [Windows Firewall Deep-Dive](#14-windows-firewall-deep-dive)
15. [Governance — Checks & Balances](#15-governance-checks-balances)
16. [Worked Example — Payroll (Web + DB)](#16-worked-example-payroll-web-db)
17. [Ongoing Maintenance & In-Place Upgrades](#17-ongoing-maintenance-in-place-upgrades)
18. [Related Reading](#18-related-reading)

---

## 1. Overview & Philosophy

The Tier Model GPO set is a **vendor layer**. It is designed, tested, and version-controlled as a unit. When you deploy the Tier Model, the root Tier Model OU GPOs arrive pre-configured. They are not a starting point for customization — they are the finished product for their intended purpose.

This distinction matters for two reasons:

- **In-place upgrades.** When a new version of the Tier Model ships, it replaces root-level GPOs cleanly because those GPOs have not been modified. If you have altered them, an upgrade becomes a diff exercise and a maintenance burden you own forever.
- **Audit accuracy.** The [Drift Detection](drift-detection-details.md) audit script validates that the expected GPOs are present, linked in the correct order, and configured correctly. Reordering, renaming, or modifying a provided root-level GPO will produce drift findings that cannot be auto-remediated.

The **SOE GPO** (`*- Tier <N> Servers SOE - Computer`) is your designated override surface. Every customer-specific setting belongs there. The SOE is created empty and linked at the highest priority within each root Tier Model OU so that its settings win over everything beneath it in link order. Your job is to put settings *into* the SOE — never to edit the other root GPOs.

The model eliminates grey configurations by giving every setting a single, correct home:

- Settings that apply to all servers of a given tier → SOE.
- Settings that apply to a specific application role → child-OU app-role GPO.
- Deny logon rights for the tier → root Account Restrictions GPO (hands off).
- Allow logon rights for an application role → child-OU app-role GPO.

If a setting does not fit one of these four homes, the question to ask is whether it belongs in the tier at all.

---

## 2. The Golden Rules

**Do:**

- Override in the SOE. The SOE is the only root-level GPO you add settings to.
- Build your application-specific configuration in child-OU GPOs.
- Pick exactly ONE security baseline — either the Microsoft SCT baseline or an SHF (CIS/NIST). Enable one, leave the other unlinked.
- Enable GPO links deliberately, after testing. Most root GPOs ship link-disabled for this reason.
- Remediate any Enforced GPOs at the root of the domain *before* deploying the Tier Model.
- Rename the SHF GPO to record the provider and version (e.g., `*- Tier 1 Servers SHF CIS Nov2026 - Computer`) so future versions can be introduced and swapped without ambiguity.
- Use gMSA accounts for services wherever the vendor supports them.

**Never:**

- Add, remove, or reorder GPO links at the root of a Tier Model OU.
- Edit a provided root-level GPO directly. It is the vendor product.
- Link-enable both the Microsoft SCT baseline and an SHF baseline simultaneously. The overlap is enormous and the interaction is unpredictable.
- Use GPO Enforcement on any link within the Tier Model OUs.
- Use Block Inheritance on child OUs you create (it signals poor OU design — if you need to isolate a child OU, the correct answer is a different OU location or a more specific link).
- Add WMI filters to apply a GPO to one Windows version only.
- Create version-specific baselines (one for 2019, one for 2022, one for 2025). The Server 2025 baseline covers all.

---

## 3. The GPO Layers & Precedence

Group Policy applies from the outermost OU inward. Within an OU, a lower link-order number wins (link order 1 is highest precedence). The Tier Model uses this deliberately.

### Root Tier Model OU GPOs (the vendor layer)

These GPOs are linked directly on the root Tier Model OU (e.g., `OU=Tier 1 Member Servers`). They define the security posture for every server in that tier. Their link order is fixed and meaningful:

| Priority | GPO | Purpose |
|----------|-----|---------|
| 1 (highest) | `*- Tier <N> Servers SOE - Computer` | Your override surface. Empty by default. |
| 2 | `*- Tier <N> Servers SHF [Provider] [Version] - Computer` | Industry-framework baseline slot (CIS, NIST, etc.). Ships unlinked. |
| 3 | `*- Tier <N> Servers MSFT Windows Server 2025 - Member Server` | Microsoft SCT baseline. Ships unlinked. |
| 4+ | Defender AV, BitLocker, Windows LAPS, MDE Group Tag, Edge, IE11 | Feature GPOs. Mix of link-enabled and link-disabled. |
| Last | `*- Tier <N> Servers Account Restrictions` | Five Deny logon rights. Ships link-enabled. |

Because the SOE is at priority 1, any setting you put in the SOE overrides the same setting in the baseline GPOs below it. This is the mechanism that lets you selectively override one or two settings from a baseline without forking the baseline itself.

### Child-OU App-Role GPOs (your layer)

GPOs linked on a child OU (e.g., `OU=T1-Payroll-Web,OU=Tier 1 Member Servers`) are processed *before* the parent-OU GPOs, because Group Policy inheritance flows from outermost to innermost and innermost wins. A setting configured in a child-OU GPO therefore overrides the same setting from any root Tier Model OU GPO.

This is how the five Deny logon rights are overridden for specific scenarios (see [Section 12](#12-the-deny-model-user-rights)): the root Account Restrictions GPO sets the Deny, and a child-OU Override GPO removes a specific group from that Deny.

> **🖼️ Image placeholder — suggested file `images/gpo/gpo-layer-precedence.png`**
>
> *What this diagram should show:* A simplified OU tree with `Tier 1 Member Servers` at the root and `T1-Payroll-Web` and `T1-Payroll-DB` as child OUs. Arrows or shading indicate the GPO processing order (child OUs first, then parent), with annotations showing which GPOs link at each level and which direction wins. Label the root as "vendor layer (do not modify)" and the child OUs as "your layer."

### Link-Enabled vs. Link-Disabled Defaults

The Tier Model ships GPOs in one of two states to enforce a deliberate review before you accept a potentially impactful setting:

**Ships link-DISABLED (review and enable after testing):**
- Security baseline GPOs (SOE, SHF, Microsoft SCT)
- Defender Antivirus
- BitLocker
- Windows LAPS
- MDE Group Tag
- Firewall Restrictions

**Ships link-ENABLED (active from deployment):**
- Advanced Audit
- PowerShell Audit
- Edge, IE11
- Account Restrictions (the five Deny GPO)
- PAW device GPOs (secure day one; AppLocker ships in Audit mode before Enforce)

The rationale: audit and logging are safe to enable immediately and should be on by default. Firewall and baseline GPOs can cause outages if applied to servers that have not been tested — so they require a deliberate decision to enable.

---

## 4. Post-Deployment Configuration

After deploying the Tier Model, perform these steps before considering deployment complete:

1. **Review which link-disabled GPOs apply to your environment.** Decide whether to use the Microsoft SCT baseline or an SHF baseline (not both — see [Section 5](#5-choosing-your-security-baseline)). Enable the one you choose.
2. **Populate the SOE GPO.** At minimum, add your local Administrator and Guest account rename settings. Add Windows Update configuration if you manage updates via Group Policy.
3. **Review the feature GPOs** (Defender AV, BitLocker, Windows LAPS, MDE Group Tag, Edge). For each, make the use-it-or-leave-it decision described in [Section 8](#8-review-every-provided-gpo-use-it-or-leave-it-unlinked).
4. **Test before enabling firewall GPOs.** Enabling the firewall baseline on servers that currently run with the Windows Firewall disabled can cause an immediate outage. See [Section 14](#14-windows-firewall-deep-dive).

This is the complete post-deployment checklist. Every other customization belongs in child-OU app-role GPOs, created as applications are migrated into the tier.

---

## 5. Choosing Your Security Baseline

You have two slots and you enable exactly one:

**Option A — Microsoft Security Compliance Toolkit (SCT) baseline**

The `*- Tier <N> Servers MSFT Windows Server 2025 - Member Server` GPO ships ready to link-enable. It is the Microsoft-recommended baseline for member servers. If your organization does not have a mandated industry framework, this is the correct choice. Link-enable it and move on.

**Option B — Security Hardening Framework (SHF): CIS or NIST**

If your organization requires CIS Benchmarks, NIST 800-53, or a similar framework, use the SHF slot:

1. Download the framework vendor's GPO backup.
2. Import it into the `*- Tier <N> Servers SHF [Provider] [Version] - Computer` GPO using `Import-GPO`.
3. Rename the GPO by replacing `[Provider]` and `[Version]` with the specific framework and version (e.g., `CIS Nov2026`). The full name becomes `*- Tier 1 Servers SHF CIS Nov2026 - Computer`. This naming convention is the version-control mechanism — when a newer CIS version ships, you create a new GPO with the new version in the name and retire the old one without ambiguity.
4. Leave the Microsoft SCT baseline link-disabled.

**The most important rule:** do not enable both. The settings overlap heavily. Running two baselines simultaneously produces unpredictable results depending on which GPO wins for each setting, and your effective configuration becomes impossible to reason about.

**Never modify a provided vendor baseline.** If your application or environment requires a baseline setting to be different, override that setting in the SOE. The SOE is at higher link priority and wins. The baseline remains unmodified and can be replaced cleanly when a new version ships.

**Never duplicate a setting across GPOs.** If Windows Update is configured in the SOE and also in the baseline, the SOE wins — but the duplicate makes it harder to understand your effective configuration and harder to audit. Set each setting in one place.

---

## 6. Windows Version Support

The `*- Tier <N> Servers MSFT Windows Server 2025 - Member Server` GPO applies correctly to servers running Windows Server 2016, 2019, 2022, and 2025. The settings it contains are supported on all of those operating system versions.

**Do not create separate baselines for each Windows Server version.** A GPO named `*- Tier 1 Servers MSFT Windows Server 2022 - Member Server` alongside the 2025 GPO, linked simultaneously, duplicates settings, creates precedence ambiguity, and adds a maintenance burden. The 2025 baseline is sufficient for all supported versions.

**Do not add WMI filters to apply a GPO only to a specific OS version.** WMI filters add processing overhead, complicate troubleshooting, and address a problem that does not exist here. A single baseline GPO applied to all servers in the tier is correct, intentional, and supported.

If a specific setting is needed only on a subset of servers (for example, a feature that exists on 2025 but not on 2019), that is a child-OU concern handled by placing those servers in their own child OU and applying the setting there.

---

## 7. The SOE — Your Environment's Override Surface

The Standard Operating Environment GPO (`*- Tier <N> Servers SOE - Computer`) is the one root-level GPO that you are expected to populate. It is created empty and linked at the highest priority, so its settings override anything below it.

**Settings that belong in the SOE:**

- Local account renames: rename the built-in Administrator account and Guest account to your organization's standard names.
- Windows Update configuration (WSUS server, update schedules, deferral policies).
- Any setting your chosen baseline includes that you need to override for your environment.
- Any security or configuration setting your environment requires that is not covered by the chosen baseline.
- Inbound firewall rules needed on every server in the tier (e.g., a backup agent's listening port that every server requires).

**Settings that do not belong in the SOE:**

- Application-specific configuration (put it in a child-OU app-role GPO).
- Deny logon rights (those belong in the root Account Restrictions GPO, which you do not edit).
- Allow logon rights for a specific application (those belong in the child-OU app-role GPO).

---

## 8. Review Every Provided GPO — Use It or Leave It Unlinked

For each optional capability GPO, make a binary decision: use the provided GPO, or leave it unlinked and manage the capability yourself. The table below captures each decision.

| Capability | Provided GPO | If you use an alternative |
|---|---|---|
| **Disk encryption** | Windows LAPS GPO controls the recovery password. BitLocker GPO enforces encryption. Link-enable both if using BitLocker. | If a third-party disk encryption solution manages this, leave the BitLocker GPO unlinked. Put any required configuration in the SOE. |
| **Host firewall** | Firewall Restrictions GPO. Link-enable to enforce Windows Firewall rules centrally. | If a third-party host firewall agent is used, leave the Windows Firewall Restrictions GPO unlinked. **Do not disable the Windows Firewall.** Leave it running in audit mode (see [Section 14](#14-windows-firewall-deep-dive)). |
| **EDR / XDR** | MDE Group Tag GPO. Link-enable if servers are onboarded to Microsoft Defender for Endpoint. | If not using MDE, leave the tag GPO unlinked. Your EDR agent's configuration goes in the SOE or a child-OU GPO. |
| **Web browser** | Edge GPO. Edge is installed on every supported Windows Server version. Recommend link-enabling. | If Chrome or Firefox policies are required, add them to the SOE (or a child-OU GPO for specific servers). Edge and a third-party browser policy can coexist. |
| **Antivirus** | Defender Antivirus GPO. Link-enable if using Microsoft Defender Antivirus. | If a third-party AV agent manages protection, leave the Defender AV GPO unlinked. Configuration for the third-party agent goes in the SOE. |
| **Local admin password** | Windows LAPS GPO. Link-enable if using Windows LAPS to manage the built-in Administrator password. | If a separate password management solution manages the built-in Administrator account, leave the Windows LAPS GPO unlinked. |

The guiding principle: the Tier Model provides these GPOs so you do not have to build them. Use them when they match your tooling. Leave them unlinked when they do not — but always have a replacement in the SOE or a child-OU GPO, not an ungoverned local configuration.

---

## 9. OU Design: Inheritance & Enforcement

### Block Inheritance

Block Inheritance on an OU prevents GPOs from parent OUs from flowing into it. Within the Tier Model, Block Inheritance is used intentionally at Tier Model root OUs to isolate them from domain-level GPOs. You should not replicate this in the OUs you create beneath the Tier Model.

If you feel the need to block inheritance on a child OU, the correct diagnosis is usually one of:
- A setting in a root Tier Model GPO needs to be overridden — use the SOE or the Override template GPOs.
- A setting from a domain-level GPO is interfering — remediate the domain-level GPO instead of blocking inheritance (see the Enforced GPOs note below).

The only partial exception: you **may** block inheritance at the Domain Controllers OU to prevent domain-level GPOs from affecting domain controllers. This is operationally sound, but it is a production change with consequences — test it carefully. The Tier Model does not configure this by default because it is environment-specific.

### GPO Enforcement

An Enforced GPO link cannot be overridden by Block Inheritance or by a higher-priority link. Within the Tier Model, Enforcement is never used. If you Enforce a GPO on a Tier Model OU or its children, you create a layer that overrides the SOE and potentially the security baseline — breaking the precedence model this documentation describes.

Never enforce a GPO within the Tier Model OU structure.

### Enforced GPOs at the Root of the Domain

This is the most critical pre-deployment check. Any GPO that is link-Enforced at the root of the domain (`Default Domain Policy` is the common example, but it can be any GPO) bleeds down through every OU, including the Tier Model OUs, and cannot be blocked. If such a GPO conflicts with a Tier Model GPO setting, the Enforced GPO wins — regardless of where it sits in link order.

**Before deploying the Tier Model, audit domain-level Enforced GPOs and remediate them.** Options:

1. Remove the Enforcement flag from the domain-level GPO link. This is the correct fix when Enforcement was applied as a shortcut rather than by design.
2. Move settings that must apply to the whole domain into the domain-level GPO without Enforcement, relying on inheritance.
3. Explicitly exclude the Tier Model OUs if the domain-level GPO's settings are not compatible with the Tier Model.

Do not proceed with Tier Model deployment while Enforced domain-level GPOs conflict with the Tier Model. The audit script will report drift that is not fixable without resolving the Enforcement conflict.

---

## 10. Extending With Child OUs

The root Tier Model OUs are the vendor layer: you do not modify the GPO structure there. All customer-specific, application-specific, or environment-specific configuration is built in child OUs beneath the root.

Child OUs serve several organizational purposes:

- **Application isolation:** Group all servers for a given application under a single child OU (e.g., `T1-Payroll`), and sub-OUs by role if needed (`T1-Payroll-Web`, `T1-Payroll-DB`).
- **Compliance or regional separation:** If a subset of servers must meet different compliance requirements (e.g., PCI-in-scope servers), place them in their own child OU and link the applicable additional GPOs there.
- **Simplified GPOs:** Rather than a single large SOE GPO that conditionally applies different settings, use separate child-OU GPOs that apply cleanly to the exact servers that need them. A Google Chrome policy GPO linked at a child OU is easier to audit and modify than a policy buried in a shared SOE.

The one rule when extending: do not replicate settings from root Tier Model GPOs in your child-OU GPOs. If you are duplicating a setting, you are either overriding it (in which case, use the Override templates) or adding unnecessary complexity.

---

## 11. Migrating Applications In — Naming Convention

When creating child OUs for application workloads, use the naming convention:

```
T#-<App>-<Role>
```

Examples:

- `T1-Payroll-Web` — Tier 1, Payroll application, web servers
- `T1-Payroll-DB` — Tier 1, Payroll application, database servers
- `T0-PKI-CA` — Tier 0, PKI application, certificate authority servers
- `T2-FileShare-FS` — Tier 2, file share application, file servers

Optionally, group application roles under a parent OU:

```
OU=T1-Payroll
    OU=T1-Payroll-Web
    OU=T1-Payroll-DB
```

Or place both roles directly under the tier root:

```
OU=T1-Payroll-Web, OU=Tier 1 Member Servers
OU=T1-Payroll-DB,  OU=Tier 1 Member Servers
```

Both structures work. Use the parent-OU grouping when you have several roles for one application and want them visually grouped in Active Directory Users and Computers. Use the flat structure for simpler applications.

GPO names at child OUs should follow the same `T#-<App>-<Role>` prefix to keep them associated with their OU. For example: `T1-Payroll-Web URA - Computer`, `T1-Payroll-DB Firewall - Computer`.

---

## 12. The Deny Model (User Rights)

The Tier Model enforces five "Deny" logon rights at the root Tier Model OU via the `*- Tier <N> Servers Account Restrictions` GPO:

| Right | Denied To |
|---|---|
| Deny log on locally | Accounts that should not have interactive access at the tier |
| Deny log on as a service | Built-in Administrators group (local) |
| Deny log on as a batch job | Built-in Administrators group (local) |
| Deny access to this computer from the network | Local accounts |
| Deny log on through Remote Desktop Services | Accounts that should not have RDP access at the tier |

The root Account Restrictions GPO defines the Deny side. **You do not modify this GPO.** The Tier Model owns the Deny.

Your child-OU app-role GPO owns the corresponding **Allow** logon rights. For example, a web server role GPO grants "Log on as a service" to the IIS application pool service account, and "Allow log on through Remote Desktop Services" to the Tier 1 local admins group.

### Sanctioned Override 1: Built-in Administrators Running Services

The root GPO denies `Log on as a service` and `Log on as a batch job` to the local Administrators group. This prevents the common misconfiguration of running services or scheduled tasks as a local administrator account — a significant lateral movement risk.

Override this Deny only when a vendor explicitly requires a member of the local Administrators group to run a service or scheduled task, and only when the vendor does not support gMSA accounts. In that case, link one of the Override template GPOs (`*- Tier Model Template Tier <N> Servers Account Restrictions - Override - Deny Service` or `- Override - Deny Batch`) at the specific child OU for that application. This removes the built-in Administrators group from the Deny right for servers in that OU only.

Always prefer a gMSA when the vendor supports it. A gMSA eliminates this override entirely because the service account is not a member of the local Administrators group.

### Sanctioned Override 2: Windows Failover Cluster CLIUSR

The root GPO denies network access to all local accounts. This is correct for the vast majority of workloads. Windows Failover Clustering uses a special local account named `CLIUSR` that requires network access between cluster nodes to function. Without it, cluster heartbeat and resource failover break.

If you are deploying Windows Failover Cluster nodes in the tier, link the `*- Tier Model Template Tier <N> Servers Account Restrictions - Override - Deny Network` template GPO at the child OU for those cluster nodes. This template removes `CLIUSR` from the "Deny access to this computer from the network" right. Apply it only to the cluster nodes' child OU — never to the tier root or to non-cluster servers.

These are the **only two sanctioned overrides** of the Deny rights. Any other override requires a security review and must be documented.

---

## 13. Template GPOs Reference

The Tier Model ships the following template GPOs in `config/tiermodel-gpos.json`. Duplicate the relevant template GPO, rename it to your application-role naming convention, and link it at your child OU.

| Template GPO | Purpose | How to use |
|---|---|---|
| `*- Tier Model Template Security Baseline - Computer` | Default Allow policy applied at each child OU. The Restricted Group sets the members of the local Administrators group. | Duplicate per child OU. Usually the only change is adding your `Tier <N> <App> Local Admins` group to the builtin Administrators Restricted Group. |
| `*- Tier Model Template IIS URA - Computer` | User Rights Assignment starting point for IIS web server roles. | Duplicate per child OU. Review and add your IIS application pool service accounts and the `Tier <N> <App> Local Admins` Restricted Group. |
| `*- Tier Model Template SQL URA - Computer` | User Rights Assignment starting point for SQL Server roles. | Duplicate per child OU. Review and add your SQL service accounts (prefer gMSA). Add the `Tier <N> <App> Local Admins` Restricted Group. |
| `*- Tier Model Template IIS and SQL URA - Computer` | Combined IIS and SQL URA starting point. Included for environments where a single server runs both roles (common in test/dev). | IIS and SQL on the same server is not a security best practice. Use this template in test environments only. Prefer the separate IIS and SQL templates in production. |
| `*- Tier Model Template Firewall Audit - Computer` | Windows Firewall GPO starting point for an application role. | Duplicate per child OU, rename to role naming convention. Export the server's Windows Firewall policy, import into the GPO. Set "no local merge" so only GPO rules apply. Enable the GPO. See [Section 14](#14-windows-firewall-deep-dive). |
| `*- Tier Model Template Tier <N> Servers Account Restrictions - Override - Deny Batch` | Removes the built-in Administrators group from "Deny log on as a batch job." | Link at the specific child OU where a vendor service/scheduled task requires local admin membership. Use sparingly. |
| `*- Tier Model Template Tier <N> Servers Account Restrictions - Override - Deny Network` | Removes local accounts (specifically `CLIUSR`) from "Deny access to this computer from the network." | Link at cluster node child OUs only. The template already removes `CLIUSR` — do not add other local accounts unless you have a documented security justification. |
| `*- Tier Model Template Tier <N> Servers Account Restrictions - Override - Deny Remote Desktop` | Removes a group from "Deny log on through Remote Desktop Services." | Use only when a specific account requires RDP that the root deny explicitly blocks. |
| `*- Tier Model Template Tier <N> Servers Account Restrictions - Override - Deny Service` | Removes the built-in Administrators group from "Deny log on as a service." | Same guidance as the Deny Batch override. Prefer gMSA over this override. |

**Important note on Override templates:** The Override template GPOs ship with the built-in Administrators group and local accounts already removed from the applicable Deny right. Your starting point is a clean slate — do not add groups back unless you are intentionally expanding the exception. Edit the template to remove only the specific principals that require the exception for this application role.

---

## 14. Windows Firewall Deep-Dive

### Baseline Behavior

The Microsoft SCT baseline and all major SHF baselines (CIS, NIST) configure the Windows Firewall in **Block mode** — all inbound connections are denied unless explicitly permitted by a rule. If you are deploying the baseline to servers that currently run with the Windows Firewall disabled, enabling the baseline will break connectivity to those servers. Test first. Proceed slowly.

### Central Management Model

The Tier Model centrally manages the Windows Firewall through Group Policy. Each app-role GPO at a child OU controls the firewall rules for the servers in that role. This means:

- Rules needed on every server in the tier → SOE GPO.
- Rules needed on all web servers → child-OU web role GPO.
- Rules needed on all SQL servers → child-OU SQL role GPO.
- Rules unique to one application → that application's child-OU GPO.

### Building a Firewall GPO for an Application Role

1. Stand up one server for the application role and confirm it is operating normally.
2. Export the Windows Firewall policy from that server using `netsh advfirewall export`.
3. Import the exported policy into the Firewall Audit template GPO you duplicated for this role.
4. Enable the "Firewall: Do not allow users to manage the Windows Firewall" setting and set "Apply local firewall rules" to **No** (this is the "no local merge" configuration).
5. Set all three firewall profiles (Domain, Private, Public) to **Enabled** and **Audit** mode (log dropped packets but do not block yet).
6. Monitor the event log for blocked connections. Add rules for any legitimate traffic that is being dropped.
7. When no legitimate traffic is being dropped, switch the profiles from Audit to **Block**.

### "No Local Merge" — What It Means in Practice

When "Apply local firewall rules" is set to No, the Windows Firewall evaluates only rules delivered by Group Policy. Rules created locally — by a local administrator, by an installer, or by any other process — are present in the firewall's local store but are not evaluated.

This has one important security implication worth stating plainly: an attacker who has compromised a server and wants to prevent their malware's outbound traffic from being blocked by a local firewall rule cannot do so. Any rule they create locally is ignored. The only way to change the effective firewall policy is to change the GPO — which requires requesting a rule change through the AD team, the same process as requesting a port to be opened on a network firewall.

Even when a third-party host firewall agent is deployed, keep the Windows Firewall enabled in audit mode. Audit mode logs dropped packets even when no blocking occurs. This provides a record of traffic that would have been blocked, which is valuable for forensics and for verifying that a future Block transition would not break legitimate traffic.

> **🖼️ Image placeholder — suggested file `images/gpo/firewall-no-local-merge.png`**
>
> *What this diagram should show:* A two-column illustration showing the effective firewall rule evaluation flow. Left column: "no local merge OFF" — GPO rules and local rules both evaluated, local rules can be added by any local admin. Right column: "no local merge ON" — only GPO rules evaluated; local rules stored but silently ignored. Annotate with the implication: firewall changes must go through the AD team and the child-OU GPO.

---

## 15. Governance — Checks & Balances

A server owner or local administrator cannot self-modify the security controls that the Tier Model enforces. This is intentional.

- **Local Administrators membership** is controlled by the Restricted Group setting in the child-OU app-role GPO. A local administrator cannot add themselves or others to the Administrators group in a way that survives a Group Policy refresh. Changes to local Administrators membership must be requested to the AD team, who updates the `T#-<App>-<Role>` GPO if the request is valid.

- **User Rights Assignments** are set by the root Account Restrictions GPO and the child-OU URA GPO. A local administrator cannot grant themselves "Log on as a service" or remove themselves from a Deny right. The Group Policy refresh restores the GPO-defined configuration within the refresh interval.

- **Windows Firewall rules** (when "no local merge" is enabled) cannot be modified by local administrators in a way that affects the active ruleset. Rule changes must go through the AD team and the child-OU firewall GPO.

This model aligns with zero-trust principles: each host has its own trust boundary enforced by Group Policy, and the AD team is the authority for changes to that boundary. Server owners and application teams request changes; the AD team validates and implements them.

---

## 16. Worked Example — Payroll (Web + DB)

This example walks through building the complete GPO configuration for a two-tier Payroll application in Tier 1.

**Starting point:** Tier 1 Member Servers root OU, with all root Tier Model GPOs in place. Security baseline (MS SCT or SHF) is chosen and link-enabled in the SOE. Account Restrictions (Deny) GPO is link-enabled.

**Step 1 — Create child OUs**

Create `OU=T1-Payroll-Web,OU=Tier 1 Member Servers` and `OU=T1-Payroll-DB,OU=Tier 1 Member Servers`.

**Step 2 — Create the local admins group**

Create the AD security group `Tier 1 Payroll Local Admins` in the appropriate Tier 1 groups OU. Create this group *before* creating the GPOs that reference it. The GPO's Restricted Group setting resolves the group at policy application time, but creating it first ensures the reference is valid from the start.

**Step 3 — Web server GPO**

Duplicate `*- Tier Model Template IIS URA - Computer`. Rename the copy to `T1-Payroll-Web URA - Computer`. Link it to `T1-Payroll-Web` at link order 1. In the Restricted Group for builtin Administrators, add `Tier 1 Payroll Local Admins`.

**Step 4 — Database server GPO**

Duplicate `*- Tier Model Template SQL URA - Computer`. Rename the copy to `T1-Payroll-DB URA - Computer`. Link it to `T1-Payroll-DB` at link order 1. In the Restricted Group for builtin Administrators, add `Tier 1 Payroll Local Admins`. Add your SQL service account gMSA to the "Log on as a service" URA.

**Step 5 — Cluster node override (if Payroll DB uses Windows Failover Cluster)**

If the Payroll DB servers are Windows Failover Cluster nodes, duplicate `*- Tier Model Template Tier 1 Servers Account Restrictions - Override - Deny Network`. Rename the copy to `T1-Payroll-DB Override Deny Network - Computer`. Link it to `T1-Payroll-DB` at link order 2 (below the URA GPO at priority 1). This allows the cluster's `CLIUSR` local account to access the network for cluster heartbeat and resource failover.

**Step 6 — Firewall GPOs**

For each child OU:

1. Duplicate `*- Tier Model Template Firewall Audit - Computer`.
2. Rename: `T1-Payroll-Web Firewall - Computer` and `T1-Payroll-DB Firewall - Computer`.
3. Export the Windows Firewall policy from a representative server for each role.
4. Import the exported policy into the respective GPO.
5. Enable "no local merge" (set "Apply local firewall rules" to No on all three profiles).
6. Set all three profiles to Enabled + Audit mode.
7. Link each GPO to its respective child OU and enable the link.
8. Monitor for dropped legitimate traffic over several days, then transition to Block mode.

> **🖼️ Image placeholder — suggested file `images/gpo/payroll-example-gpo-layers.png`**
>
> *What this diagram should show:* A stacked-layer diagram for the `T1-Payroll-DB` OU. From top (applied last, lowest effective priority) to bottom (applied first, highest effective priority): root Tier 1 Member Servers GPOs (SOE at top, Account Restrictions Deny at bottom), then the T1-Payroll-DB child-OU GPOs above them in processing order (URA at priority 1, Override Deny Network at priority 2, Firewall at priority 3). Annotate which settings each layer controls and indicate the "innermost wins" direction.*

**Result:** The Payroll Web servers accept IIS traffic with local admins managed by Restricted Group. The Payroll DB servers accept SQL traffic and allow cluster heartbeat. Both sets of servers have centrally-managed firewall rules. The AD team controls all of these settings — no server owner can self-modify them.

---

## 17. Ongoing Maintenance & In-Place Upgrades

### The Baseline GPO Upgrade Lifecycle

When a new version of a security baseline ships — a new Microsoft SCT release, a new annual CIS Benchmark, or a NIST revision — the upgrade process is:

1. **Create the new GPO.** Import the new baseline into a new GPO using the SHF naming convention with the updated version, for example: `*- Tier 1 Servers SHF CIS Mar2027 - Computer`. Do not modify the existing in-production GPO.
2. **Link at high priority, link-disabled.** Link the new GPO at the root Tier Model OU at a higher link priority than the current production baseline, but leave the link disabled.
3. **Scope to a pilot group.** In the GPO's Security Filtering, replace "Authenticated Users" with a security group containing a small set of test servers. Enable the link. The new baseline applies only to the pilot servers.
4. **Test.** Verify no services break, no connectivity issues emerge, and the pilot servers behave correctly under the new baseline. Address any conflicts in the SOE.
5. **Expand scope.** Change Security Filtering back to Authenticated Users. The new baseline now applies to all servers in the tier.
6. **Remove the old GPO.** Delete the link to the previous baseline GPO, then delete the GPO itself. The naming convention means there is no ambiguity about which GPO is current.

This is why baselines are version-controlled by name and never edited in place. A baseline GPO that is live in production has been tested against known-good behavior. Editing it in place changes the behavior of production servers without a controlled rollout. The replace-with-new approach gives you a pilot, a rollback path (re-enable the old GPO link), and a clean record of what changed and when.

### What Must Never Change at the Root Level

Once a root Tier Model GPO is deployed to production, it is immutable — with one exception. **The SOE GPO may be updated** because it is your configuration surface. All other root Tier Model GPOs — the Account Restrictions GPO, the baseline GPO, the feature GPOs — are either replaced wholesale (as described above) or left untouched between versions.

If you find yourself wanting to edit a root GPO that is not the SOE, the correct action is one of:
- Add the required setting to the SOE (for overrides).
- Use a child-OU Override template GPO (for Deny right exceptions).
- File a request with the Tier Model project if you believe the root GPO itself has an error.

Touching root GPOs breaks the in-place upgrade path: the next Tier Model version cannot cleanly replace a GPO you have modified. It also breaks the audit script, which validates exact expected configurations. The result is permanent manual maintenance — the model's primary cost is imposed on operators who modify root GPOs.

### Child-OU App-Role GPOs — Legitimate Change

Child-OU app-role GPOs are your environment's configuration and may legitimately change to support new requirements. A new application version that opens additional firewall ports, a gMSA rotation, a new service account — these changes go into the `T#-<App>-<Role>` GPO for the affected application role. This is expected and supported.

The distinction: root = vendor/immutable; child = yours/changeable.

---

## 18. Related Reading

- **[GPO Management Strategy](gpo-management-strategy.md)** — The JSON schema and mechanics for declaring GPOs in the Tier Model: modes (`create`, `createAndImport`, `createImportAndConfigure`), `importPath`, `gpoStatus`, and URA/RG properties. Read this if you need to understand how the deployment tool processes GPO declarations.
- **[Detailed Deployment Guide](detailed-deployment-guide.md)** — Step-by-step deployment walkthrough including the post-deployment checklist.
- **[Deployment Methodology](deployment-methodology.md)** — The overall deployment approach, idempotency principles, and validation framework.
- **[Drift Detection Details](drift-detection-details.md)** — How the audit script detects and reports GPO drift, and how to interpret findings. Drift findings that cannot be auto-remediated are typically caused by manual modifications to root Tier Model GPOs.

**Common questions this page answers:**

- *Do I need separate baseline GPOs for Windows Server 2019 and 2022?* No. See [Section 6](#6-windows-version-support).
- *Should I add WMI filters so the baseline applies only to specific OS versions?* No. See [Section 6](#6-windows-version-support).
- *Can I modify the provided Microsoft SCT or CIS baseline GPO?* No. Override in the SOE. See [Section 5](#5-choosing-your-security-baseline).
- *Why should I never use GPO Enforcement within the Tier Model?* See [Section 9](#9-ou-design-inheritance-enforcement).
- *Where do I put settings that apply to my whole tier?* The SOE. See [Section 7](#7-the-soe-your-environments-override-surface).
