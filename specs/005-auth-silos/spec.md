# Feature Specification: Authentication Policy Silos (`-IncludeAuthSilos`)

**Feature Branch**: `feature/auth-silos`
**Created**: 2026-08-24
**Updated**: 2026-08-24 — four-silo model (all tiers), silo enforcement boundary, domain-join exemptions, Tier 2 EUD config addition, UAT acceptance matrix
**Status**: Draft (scoping) — Detailed FRs, cmdlet contracts, and acceptance criteria are deferred to the design phase after an ops-guide walkthrough with Joel. This spec captures scope, constraints, the correct AD object model, prerequisites, user scenarios, high-level requirements, and open questions.

> **Scoping note**: This is a scoping-phase specification. It frames what this feature must do, what the correct AD object model is, what the four-silo structure is, what the audit-first lifecycle looks like, and what the critical safety invariants are. Final detailed functional requirements and implementation specifics are a subsequent deliverable.

---

## Overview

Authentication Policy Silos (`-IncludeAuthSilos`) extends the Tier Model deployment to create AD DS Authentication Policy Silo objects across all four administrative tiers — Tier 0 Admin, Tier 1 Admin, Tier 2 Admin, and Tier 2 EUD — constraining where privileged accounts can obtain Kerberos TGTs to pre-approved administrative workstations and servers. The general Domain Users and Domain Computers population is intentionally not siloed. Silos are deployed in **audit mode first**; enforcement is a separate lifecycle step gated on a pre-enforcement safety checklist. The feature integrates with `Deploy-TierModel.ps1` and `Audit-TierModel.ps1` via an `-IncludeAuthSilos` switch, mirroring the pattern established by `-EnableAuditing` (spec 004) and `-IncludeWinLaps` (spec 003).

---

## The Four-Silo Model

The deployment creates **four authentication policy silos** — one per administrative tier/scope. This is the complete and fixed set; there is no fifth silo.

| Silo | Member accounts (user + service) | Member computers | Approved origin devices — `AllowedToAuthenticateFrom` ("member of any") |
|---|---|---|---|
| **Tier 0 Admin** | Tier 0 Accounts + Tier 0 Service Accounts | DCs, RODCs, Tier 0 Servers, Tier 0 PAWs | DCs · RODCs · Tier 0 Servers · Tier 0 PAWs |
| **Tier 1 Admin** | Tier 1 Accounts + Tier 1 Service Accounts | Tier 1 Servers, Tier 1 PAWs | Tier 1 Servers · Tier 1 PAWs |
| **Tier 2 Admin** | Tier 2 Accounts + Tier 2 Service Accounts | Tier 2 PAWs | Tier 2 PAWs |
| **Tier 2 EUD** | Local Device Admins (the existing group granting local admin on end-user devices) | Tier 2 EUD devices | Tier 2 EUD devices |

> **Privileged-accounts-only scope**: General Domain Users and Domain Computers are **intentionally not siloed**. Enforcing Kerberos Armoring (FAST) at every corporate endpoint is operationally impractical, the breakage risk at scale is unacceptable, and the proportionality is poor for non-administrative accounts. Any request to add a general-user or Domain Computers silo is explicitly out of scope.

### Silo Enforcement Boundary — What Silos Do and Do Not Control

Authentication Policy Silos gate **Kerberos TGT issuance at the domain controller AS exchange** based on the source device. They are **distinct** from two other control planes that must not be conflated:

| Control plane | What it restricts | How it is configured |
|---|---|---|
| **Silo `AllowedToAuthenticateFrom`** | Which device may obtain a covered TGT (AS exchange) | Auth Policy object SDDL — this feature |
| **URA logon rights** | Which logon types are permitted on a host (interactive, batch, service, network, RDP) | Account Restriction GPOs — **pre-existing Tier Model GPOs, not this feature** |
| **Silo `AllowedToAuthenticateTo`** | Who may obtain a service ticket to a target account/SPN (TGS exchange) | Auth Policy object SDDL — configured per computer/service policy |

An admin who passes the silo's `AllowedToAuthenticateFrom` check (TGT issued) may still be denied by URA, or denied a service ticket by `AllowedToAuthenticateTo`. These are independent control planes. This spec addresses only authentication policy silo deployment; URA and existing GPO configurations are unchanged by `-IncludeAuthSilos`.

---

## Domain-Join Service Account Exemptions

Three domain-join service accounts are **structurally exempt** from silo membership. They authenticate from ephemeral build and orchestration hosts that are not enrolled in any approved Tier device group; siloing them would break automated device provisioning.

| Account | Silo scope | Exempt reason | Compensating controls |
|---|---|---|---|
| `svc-pawdomainjoin` | Tier 0 Admin silo (PAW provisioning) | Authenticates from Autopilot/MDT/build hosts outside managed PAW device sets | Disabled by default; enabled only during provisioning window; create-computer rights scoped to PAW Staging OU only; all use monitored |
| `svc-t1srvdomainjoin` | Tier 1 Admin silo | Authenticates from orchestration/build systems outside Tier 1 managed device sets | Disabled by default; enabled only during provisioning window; create-computer rights scoped to Tier 1 Server Staging OU only; all use monitored |
| `svc-t2euddomainjoin` | Tier 2 EUD silo | Authenticates from EUD imaging/MDM hosts outside Tier 2 EUD managed device sets | Disabled by default; enabled only during provisioning window; create-computer rights scoped to Tier 2 EUD Staging OU only; all use monitored |

These are **structural exemptions** (permanent technical incompatibility), not time-bounded governance exemptions. They must be documented in the exemption register with compensating controls but are not candidates for eventual enforcement.

> **Note on `svc-t2euddomainjoin`**: This account, its associated group, and the Tier 2 EUD Staging OU **do not currently exist** in the Tier Model. Their creation is a prerequisite for deploying the Tier 2 EUD silo. See the section below.

---

## Required New Config Addition — Tier 2 EUD Provisioning

The Tier Model does not currently have a domain-join service account or staging OU for Tier 2 EUD devices. To mirror the pattern established for PAW Staging and Tier 1 Server Staging, the following additions are required before the Tier 2 EUD silo can be deployed. These are additions to the Tier Model's base config, not one-off manual steps.

| Item | Description | Config area affected |
|---|---|---|
| `svc-t2euddomainjoin` service account | Domain-join service account for Tier 2 EUD devices; disabled by default | `tiermodel-users.json` (or equivalent users config) |
| `Tier2EUDDomainJoin` security group | Group scoping the domain-join delegation rights for Tier 2 EUD; `svc-t2euddomainjoin` is the only member | `tiermodel-groups.json` (or equivalent groups config) |
| `Tier 2 EUD Staging` OU | Staging OU for EUD computer objects prior to GPO assignment and Tier 2 EUD group enrollment | `tiermodel-ous.json` (or equivalent OUs config) |
| Delegated create-computer rights | Grant `Tier2EUDDomainJoin` group create-computer/delete-computer rights scoped to `Tier 2 EUD Staging` OU — mirrors the Tier 1 Server Staging ACL pattern | `tiermodel-acls.json` (or equivalent ACLs config) |
| Account Restriction GPO for Tier 2 EUD | Deny interactive and RDP logon for `svc-t2euddomainjoin`; Kerberos Armoring enabled; mirrors Tier 1 and PAW account-restriction GPO patterns | Tier 2 EUD Account Restriction GPO config |

`svc-t2euddomainjoin` is then added to the exemption register as a structural exempt account for the Tier 2 EUD silo, with the same disabled-by-default + provisioning-window pattern as the other domain-join accounts.

---

> **Important**: The customer's existing scripts under `source-material/TierModel-AuthSilos/` are **frozen evidence** of current state with documented defects. They must not be modified, run, or used as a reference implementation. Correct behavior is derived from Microsoft primary documentation; the existing scripts are evidence of what the current approach does, not how this feature should be built.

Authentication policies and Authentication Policy Silos are **two distinct AD DS object classes**:

| Object class | AD class | Role |
|---|---|---|
| Authentication Policy | `msDS-AuthNPolicies` | Defines per-account-class settings: TGT lifetime, `AllowedToAuthenticateFrom` (source restriction), `AllowedToAuthenticateTo` (service-ticket restriction), and `Enforce` state |
| Authentication Policy Silo | `msDS-AuthNPolicySilo` | Groups user, computer, and service accounts; references per-class policies for silo members; carries its own `Enforce` state |

The implementation **must** create real silo objects and link them to per-class policies. Per-tier, three policies are required — one each for user accounts, computer accounts, and service/managed service accounts — referenced by the silo object.

The customer's existing scripts assign authentication policies directly to accounts and **never create silo objects**. This means no silo grouping, no silo membership governance, and no silo-level claims. This is the primary structural defect in the existing scripts and must not be replicated.

### SDDL Boolean Logic — A Critical Invariant

`AllowedToAuthenticateFrom` conditions restrict which devices can satisfy the source-device check during Kerberos TGT issuance. When multiple approved device groups exist (e.g., PAWs and management servers), the SDDL **must** use OR logic:

```
# Correct — either approved group satisfies the condition
Member_of_any {SID(Tier0PAWDevices), SID(Tier0MgmtServers)}
```

Using AND logic (`&&`, or ADAC "Member of each") between approved device groups requires a device to be a member of **all** listed groups simultaneously. For a "these are the allowed device sets" intent, AND is wrong — it denies any admin whose device is only in one of the groups. This is the documented lockout failure mode present in the customer's existing scripts and the most likely cause of a self-inflicted enforcement outage.

### Account Lifecycle for Silo Membership

Assigning an account to a silo requires two steps, in order:

1. **Grant silo access** (`Grant-ADAuthenticationPolicySiloAccess`): grants permission for the account to join the silo.
2. **Assign silo membership** (`Set-ADAccountAuthenticationPolicySilo`): assigns the account to the silo, binding it to the silo's per-class policies.

Both steps are required. A permission grant without an assignment provides no protection; an assignment without prior grant is blocked by AD.

---

## Audit-First Lifecycle

Audit mode is **not a safe enforcement preview** for all authentication paths. Clean audit means only "no logged Kerberos would-be-denies during a healthy observation window." NTLM-dependent paths, LDAP simple-bind traffic, and non-Kerberos authentication paths produce no 305/306 audit events. A quiet audit log does not prove enforcement is safe for those paths.

The three-stage lifecycle is:

| Stage | Trigger | What happens | Authentication protected? |
|---|---|---|---|
| **1. Deploy (audit mode)** | `-IncludeAuthSilos -ConfirmApply` | Create silo and policy objects; grant/assign accounts; all objects `Enforce = false` | ❌ No — audit events only |
| **2. Observation and gate validation** | Normal operations; `Audit-TierModel.ps1 -IncludeAuthSilos` | 305/306 would-be-deny events observed; drift detected; pre-enforcement gates G1–G12 assessed | ❌ No — not protective |
| **3. Enforcement flip** | Separate, manually-invoked operation (details deferred — see Open Questions) | `Enforce = true` on policies/silos; G1–G12 gates verified before execution; audit record produced | ✅ Yes — actual denial |

**Enforcement flip is never part of the `-IncludeAuthSilos` deployment flow.** It is a separate, explicitly-invoked operation requiring gate verification and operator acknowledgement.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Deploy Authentication Policy Silos in Audit Mode (Priority: P1)

Administrator runs `Deploy-TierModel.ps1 -PreferredDc DC01 -IncludeAuthSilos -ConfirmApply` to create all four Authentication Policy Silo objects (Tier 0 Admin, Tier 1 Admin, Tier 2 Admin, Tier 2 EUD) and their associated per-class Authentication Policies, with all silo-scoped accounts granted and assigned. All objects are deployed in audit mode (`Enforce = false`). Kerberos 305/306 would-be-deny events begin flowing to the SIEM for observation; no authentication is blocked.

**Clarifications Applied**:
- Four silo objects are created — one per tier/scope (Tier 0 Admin, Tier 1 Admin, Tier 2 Admin, Tier 2 EUD). No fifth silo.
- Real `msDS-AuthNPolicySilo` objects are created for each configured silo — not direct policy assignment only.
- Per-silo, three authentication policies are created (user, computer, service/MSA) and referenced by the silo object.
- `AllowedToAuthenticateFrom` SDDL uses OR logic for device groups.
- All created objects have `Enforce = false`. No code path in deployment may set `Enforce = true`.
- Tier device groups (PAWs, management servers, EUD devices) must pre-exist and be populated. The code validates group existence and non-emptiness before any AD write.
- The Tier 2 EUD Staging OU, `svc-t2euddomainjoin`, and `Tier2EUDDomainJoin` group must exist before the Tier 2 EUD silo can be deployed (see "Required New Config Addition" section).
- Domain-join service accounts (`svc-pawdomainjoin`, `svc-t1srvdomainjoin`, `svc-t2euddomainjoin`) are exempt from silo membership — not assigned to any silo.
- Kerberos Armoring (FAST) GPOs are pre-existing in the Tier Model. The code validates their presence; it does not create or modify them.
- The built-in domain Administrator (RID-500) is structurally excluded from silo membership — by SID suffix match, not by account name.
- Without `-ConfirmApply`, the invocation produces a plan showing what would be created; zero AD writes occur.

**Acceptance Scenarios** *(high-level — detailed criteria deferred to design phase)*:
1. **Given** all four Tier device groups exist and are populated, FAST GPOs confirmed active, DFL requirements met, Tier 2 EUD config additions present, **When** running `-IncludeAuthSilos` without `-ConfirmApply`, **Then** a plan listing four silo objects, policy objects, and account assignments to create is displayed; zero AD writes occur.
2. **Given** prerequisites confirmed, **When** running `-IncludeAuthSilos -ConfirmApply`, **Then** four silo objects, policies, grants, and assignments are created with `Enforce = false`; a second dry run reports 0 actions (`Converged = True`).
3. **Given** silo objects already exist and match desired state, **When** running `-IncludeAuthSilos`, **Then** the plan reports 0 actions (`Converged = True`); no writes occur (idempotent).
4. **Given** a Tier device group is empty or missing, **When** running `-IncludeAuthSilos`, **Then** the system halts with `AUTHSILO_DEVICE_GROUP_EMPTY` before any AD writes; no partial state is created.
5. **Given** Kerberos Armoring GPO validation fails, **When** running `-IncludeAuthSilos`, **Then** the system halts with `AUTHSILO_FAST_PREREQ_MISSING`; no writes occur.
6. **Given** an account in the configured scope has already been assigned to a silo matching desired state, **When** running `-IncludeAuthSilos`, **Then** that account is not re-processed; the delta-only contract holds.
7. **Given** `svc-t2euddomainjoin` (or any other domain-join exempt account) is in a silo's account scope query, **When** running `-IncludeAuthSilos`, **Then** that account is skipped — not granted or assigned to any silo; it appears in the plan as exempted.

---

### User Story 2 — Audit Current Authentication Policy Silo State (Priority: P1)

Security engineer runs `Audit-TierModel.ps1 -PreferredDc DC01 -IncludeAuthSilos` to verify that silo objects, per-class policies, account assignments, and device groups match the desired state defined by the Tier Model configuration. Without `-IncludeAuthSilos`, silo state is not checked or reported.

**Clarifications Applied**:
- This is a read-only operation. Zero AD writes occur.
- Audit checks: silo object existence and settings, policy `Enforce` state, account assignment completeness (desired vs. actual), device group non-emptiness, and configuration drift from baseline.
- Mirrors the `-IncludeGmsa` gating pattern established in prior specs.

**Acceptance Scenarios**:
1. **Given** silos are deployed and match desired state, **When** running `Audit-TierModel.ps1 -IncludeAuthSilos`, **Then** the report shows all silos, policies, and assignments as converged; no drift detected.
2. **Given** an account was removed from silo assignment outside the deployment flow, **When** running the audit, **Then** the report flags the missing assignment as drift.
3. **Given** a policy's `Enforce` flag was set to `true` outside the deployment flow (unexpected enforcement), **When** running the audit, **Then** the report flags the unexpected enforcement state as drift.
4. **Given** an `Enforce` flag was reverted to `false` after prior enforcement (enforcement regression), **When** running the audit, **Then** the report flags the enforcement regression as drift.
5. **Given** `Audit-TierModel.ps1` is run **without** `-IncludeAuthSilos`, **Then** silo state is not checked and does not appear in the report.

---

### User Story 3 — Enforce Authentication Policy Silos (Future — Gated) (Priority: P2)

> **Status: Deferred.** The enforcement flip operation's exact form, UX, and gate verification mechanism will be finalized after the ops-guide walkthrough. This user story captures the intended shape and the non-negotiable pre-conditions only.

After satisfying all applicable pre-enforcement safety gates (G1–G12), an authorized operator runs a separate enforcement flip operation to promote silo policies from audit (`Enforce = false`) to enforced (`Enforce = true`). Authentication events change from would-be-deny (305/306) to actual denial (105/106) for non-compliant requests.

**Design shape (intent — implementation details deferred to Open Questions OQ-002/OQ-006)**:
- Enforcement flip is a separate, explicitly-invoked operation. It is never triggered by `-IncludeAuthSilos`.
- The operation verifies gate state before executing (device groups non-empty, replication healthy, recovery path validated as working — not merely documented).
- An explicit operator acknowledgement parameter is required (not just absence of a WhatIf flag).
- The operation produces an audit record: who flipped, when, from which host, and with what justification.
- Scope may be per-tier (Tier 0 before Tier 1) or all-tiers; exact scope is deferred.

**Pre-enforcement safety gates — all must pass before enforcement proceeds**:

| Gate | What must be true | Stop condition |
|---|---|---|
| G1 — SDDL correctness | `AllowedToAuthenticateFrom` conditions tested: approved device authenticates successfully; non-approved device is denied | Enforcement stop |
| G2 — Account assignment completeness | All intended accounts assigned; no unintended accounts in scope; stale assignments removed | Enforcement stop |
| G3 — Approved-device group population | Device groups are non-empty, contain correct SIDs, and changes have replicated to all DCs | Enforcement stop |
| G4 — Independent recovery path | At least one recovery path works without authenticating as a silo-restricted Tier 0 account; path has been tested end-to-end, not just documented | Enforcement stop |
| G5 — Rollback runbook exercised | Revert steps, convergence timeline, per-DC validation, and auth outcome tests executed in lab or pilot | Enforcement stop |
| G6 — Replication health | No blocking replication failures for affected partitions on any DC | Enforcement stop until fixed or scoped |
| G7 — Observability proven | DC event channels enabled, centralized, retained; 305/306 collection validated across all in-scope DCs | Audit-only may proceed; enforcement stop without confirmed collection |
| G8 — Effective permissions inventoried | Effective modify paths over policies/silos/feeder groups/GPOs/automation/logging are Tier 0-contained | Enforcement stop; unmanaged degradation risk |
| G9 — Exemption register complete | Every exempt account has named owner, reason, expiry or re-evaluation trigger, and compensating controls | Enforcement stop for broad rollout |
| G10 — Automation safety | Any writer is single-writer, delta-only, threshold-protected, signed, centrally logged, and fail-safe on empty/partial queries | Disable automation or keep report-only |
| G11 — Representative audit window | Audit period covers maintenance windows, infrequent scheduled jobs, and business-cycle peaks | Do not claim audit supports enforcement without coverage |
| G12 — Cross-boundary topology | For any in-scope account/resource domain pairs, per-domain coverage and recovery ownership is confirmed | Enforcement stop for those paths |

---

## Test Acceptance Matrix (UAT-01–UAT-15)

> These scenarios are the required validation set before the feature is considered operationally ready. The ops guide provides the detailed step-by-step walkthrough; this table names the scenarios and their expected outcomes in both audit and enforced modes. All destructive scenarios (UAT-12, UAT-14) must be run in the lab only.

| ID | Scenario | Audit mode expected | Enforced mode expected | Notes |
|---|---|---|---|---|
| UAT-01 | **Approved device — Tier 0 Admin**: Tier 0 admin account authenticates from a Tier 0 PAW in the `Tier0PAWDevices` group | 305 event generated (would-be-deny does not fire because device IS approved) — no event; TGT issued | TGT issued; no 105 event | Baseline positive test; confirms SDDL OR logic is correct for approved devices |
| UAT-02 | **Approved device — Tier 1 Admin**: Tier 1 admin account authenticates from a Tier 1 PAW | TGT issued normally | TGT issued normally | Baseline positive — Tier 1 PAW in approved group |
| UAT-03 | **Approved device — Tier 2 Admin**: Tier 2 admin account authenticates from a Tier 2 PAW | TGT issued normally | TGT issued normally | Baseline positive — Tier 2 PAW in approved group |
| UAT-04 | **Approved device — Tier 2 EUD**: Local Device Admin account authenticates from a Tier 2 EUD device in the approved group | TGT issued normally | TGT issued normally | Baseline positive — EUD device in approved group |
| UAT-05 | **Non-Tier-Model server deny**: Tier 0 admin account attempts authentication from a standard member server not in any approved Tier device group | 305 would-be-deny event generated | 105 TGT denial; authentication fails | Critical negative test; confirms silo restricts non-approved hosts |
| UAT-06 | **Cross-tier deny — Tier 1 device vs Tier 0 account**: Tier 0 admin account attempts authentication from a Tier 1 PAW (in `Tier1PAWDevices` but not in any Tier 0 approved group) | 305 event generated | 105 denial | Cross-tier isolation test; Tier 1 device must not unlock Tier 0 accounts |
| UAT-07 | **Cross-tier deny — EUD vs Tier 1 account**: Tier 1 admin account attempts authentication from a Tier 2 EUD device | 305 event generated | 105 denial | EUD devices must not be able to obtain Tier 1 TGTs |
| UAT-08 | **New device onboarding — device not yet enrolled**: PAW newly imaged but not yet added to `Tier0PAWDevices` group; Tier 0 admin attempts authentication | 305 event generated | 105 denial (device group not updated yet) | Tests sequencing: device MUST be in approved group before admin can authenticate from it |
| UAT-09 | **New device onboarding — approved-group add + TGT refresh**: After adding the new PAW to `Tier0PAWDevices` and allowing replication, Tier 0 admin obtains a new TGT | No 305 event; TGT issued (in audit); confirm group membership visible on all DCs | TGT issued after replication; new Kerberos exchange | Tests the full new-device onboarding sequence: join domain → add to approved group → replicate → new TGT |
| UAT-10 | **Automated domain-join — `svc-t1srvdomainjoin` (audit mode)**: Enable the account during provisioning window; domain-join a Tier 1 server via automation | 305 event generated for the `svc-t1srvdomainjoin` Kerberos exchange (it is exempt — no silo applied, but test whether any event fires) OR no event because account is not in any silo | TGT issued — exempt account is not restricted by silo | Confirm exemption: exempt accounts pass through; no 305/105 for accounts not assigned to any silo |
| UAT-11 | **Automated domain-join — `svc-t2euddomainjoin`**: Once config additions are deployed, enable account; domain-join a Tier 2 EUD device | Same as UAT-10: no silo restriction applies | TGT issued — exempt account | Validates Tier 2 EUD provisioning end-to-end |
| UAT-12 | **Audit → enforce gate**: Attempt to flip a silo to `Enforce = true` without passing G1–G12 gate checklist (in lab: attempt enforcement when device group is empty) | N/A | Enforcement attempt rejected / operator gate not passed | Tests that enforcement cannot proceed without gate verification; requires enforcement-flip implementation |
| UAT-13 | **Structural exemption — `svc-pawdomainjoin`**: With Tier 0 Admin silo in enforced mode, enable `svc-pawdomainjoin` during a provisioning window; domain-join a PAW | N/A (exempt) | TGT issued; domain join succeeds | Validates that exempt account is not blocked even when the silo is enforced |
| UAT-14 | **RID-500 recovery path**: With all non-exempt Tier 0 admins blocked (misconfigured SDDL with no approved devices in enforce mode), authenticate to DC console as RID-500; revert enforcement | N/A | RID-500 authenticates from DC console (platform-exempt); reverts `Enforce` to `false`; Tier 0 admins recover on next TGT | Lab-only destructive test; validates recovery invariant SI-01; RID-500 is the always-available recovery path |
| UAT-15 | **Second-run idempotency**: Deploy all four silos in audit mode; immediately re-run `-IncludeAuthSilos` | Plan shows 0 actions, `Converged = True`; zero AD writes | N/A | Validates FR-007 (idempotency) and delta-only contract |

> **Reference**: The ops guide provides the detailed per-scenario walkthrough, including prerequisite setup, exact commands, expected event IDs, and pass/fail criteria. This table names the scenarios; the ops guide is the authoritative test execution reference.

---

## Edge Cases

- **Empty approved-device group**: An empty Tier device group means no device can satisfy the `AllowedToAuthenticateFrom` condition. If enforced, every siloed account would be denied. The system must halt with `AUTHSILO_DEVICE_GROUP_EMPTY` before any AD write when a configured device group is empty.
- **SDDL AND-logic lockout**: Using `&&` between device groups requires simultaneous membership in all listed groups. This denies any account whose device is in only one of the allowed groups — a lockout risk present in the existing customer scripts. OR logic (`Member_of_any`) is the only correct semantics for "these are the allowed device sets."
- **RID-500 structural exclusion**: The built-in domain Administrator is platform-exempt from authentication policy evaluation even when assigned to a silo. The code excludes it by SID suffix (`-500$`), not by `sAMAccountName` (which can be renamed). This exclusion is non-configurable.
- **NTLM and non-Kerberos paths produce no audit events**: RADIUS/NPS MS-CHAPv2, LDAP simple bind, PTA credential validation, cached credentials, and non-domain-joined host authentication produce no Kerberos 305/306 would-be-deny events. A clean audit window is not proof of enforcement safety for these paths.
- **Protected Users interaction**: Protected Users membership applies restrictions immediately (NTLM block, 4-hour TGT lifetime, no credential caching) and is not an audit-first control. Protected Users management is outside the scope of this feature; its interaction with silo TGT lifetime settings requires validation before enforcement.
- **Domain-join account exemptions**: `svc-pawdomainjoin`, `svc-t1srvdomainjoin`, and `svc-t2euddomainjoin` must never appear in any silo's granted or assigned account set. If these accounts appear in an OU or group query populating silo scope, the code must explicitly skip them. Their exemption is structural, not configurable.
- **Tier 2 EUD config additions prerequisite**: The Tier 2 EUD silo cannot be deployed until `svc-t2euddomainjoin`, `Tier2EUDDomainJoin`, and `Tier 2 EUD Staging` OU exist in the Tier Model. If any of these are missing, the system must halt with a descriptive error; no partial Tier 2 EUD silo state may be created.
- **Enforcement regression** (`Enforce` reverted to `false` post-enforcement): Protection is silently removed without a service outage. This must be detected as drift by `Audit-TierModel.ps1 -IncludeAuthSilos`.
- **Delta-only mandatory**: Writing the full account membership set on every reconciliation run generates false-positive group-modification alerts. Only accounts where desired state differs from actual state may be added or removed.
- **Replication inconsistency**: Policy, silo, or group changes may reach some DCs before others. Post-write verification must cover multiple DCs; reading from the write-target DC alone does not prove global convergence.
- **Audit parking**: A silo deployed in audit mode but never progressed to enforcement provides partial Kerberos telemetry but zero authentication protection. Deployment output must label audit-mode state as "audit-only / not protective."
- **Authoritative restore / forest recovery**: If a forest or partition restore predates the silo enforcement state, enforcement can silently revert. The control-plane state of silos must be explicitly verified after any authoritative restore.

---

## Prerequisites

| Prerequisite | Current state | Validation approach |
|---|---|---|
| Windows Server 2012 R2 Domain Functional Level (minimum) | Must be satisfied in the target environment | Check DFL via `Get-ADDomain`; halt with `AUTHSILO_DFL_INSUFFICIENT` if not met |
| Kerberos Armoring (FAST) and Dynamic Access Control (DAC) GPOs active on all domain controllers | **Pre-existing** — the Tier Model already deploys this via Account Restriction GPOs per tier and the domain root GPO | Validate GPO linkage and settings are enforced on all DCs; do NOT create or modify GPOs |
| Tier device groups (PAWs, management servers per tier) exist and are populated | Operator responsibility before running `-IncludeAuthSilos` | Validate group existence and non-emptiness; halt with `AUTHSILO_DEVICE_GROUP_EMPTY` if empty |
| AD PowerShell module (`ActiveDirectory`) | Must be present on the management host | Check module availability; halt with `AUTHSILO_MODULE_MISSING` if absent |
| Sufficient AD permissions | Caller must hold rights to create `msDS-AuthNPolicies` and `msDS-AuthNPolicySilo` objects in the AuthN Policy Configuration container | Check for `AUTHSILO_PERMISSION_MISSING`; domain admin holds required rights |
| Target accounts catalogued | Accounts scoped to each silo must be resolvable from configuration | Validate all accounts resolve before any write; fail with per-account errors if unresolvable |

> **FAST/DAC prerequisite note**: The Tier Model already deploys KDC support for claims, compound authentication, and Kerberos armoring via Account Restriction GPOs for each tier and the domain-root GPO. The code validates that these settings are active; it does not create or re-link any GPO. If a GPO setting is found missing, the error directs the operator to the Tier Model GPO documentation.

---

## Constraints

These constraints are non-negotiable and must shape every design and implementation decision for this feature.

| ID | Constraint | Consequence if violated |
|---|---|---|
| CON-001 | The implementation must create `msDS-AuthNPolicySilo` silo objects AND `msDS-AuthNPolicies` policy objects. Direct policy assignment to accounts without silo objects is not the target model. | Code without silo objects does not implement this feature correctly and forfeits silo grouping and governance. |
| CON-002 | `AllowedToAuthenticateFrom` SDDL must use OR logic (`Member_of_any`) for device groups. AND logic (`&&`) between approved device group SIDs is prohibited. | AND logic denies any account whose device is in only one approved group — a lockout failure mode documented in A4-W01. |
| CON-003 | All silo and policy objects created by `-IncludeAuthSilos` must have `Enforce = false`. No code path in deployment may set `Enforce = true`. | Deployment-triggered enforcement bypasses the pre-enforcement gate checklist. |
| CON-004 | The enforcement flip is a separate, manually-invoked operation. It must never be triggered by `-IncludeAuthSilos` or by any automated/scheduled path. | Automated enforcement is an uncontrolled Tier 0 state change. |
| CON-005 | The built-in domain Administrator (RID-500) is structurally excluded from silo membership by SID suffix match (`-500$`), not by `sAMAccountName`. This exclusion is not configurable. | RID-500 is platform-exempt from authentication policy evaluation; assigning it creates the appearance of protection without providing it. |
| CON-006 | Any reconciliation automation for silo membership must be delta-only, threshold-protected against mass changes, fail-safe on empty/partial queries, centrally logged with delta counts and run IDs, and run as a single writer. Running on every DC via GPO-delivered scheduled task is explicitly prohibited. | The existing scripts' pattern is a Tier 0 control-plane attack surface generating constant false-positive alerts. |
| CON-007 | Source-material scripts under `source-material/TierModel-AuthSilos/` are frozen evidence. They must not be modified, run, or used as a reference implementation. | Those scripts have 4 Critical and 19 Major defects; using them recreates known failure modes. |
| CON-008 | Kerberos Armoring (FAST) and DAC GPOs are pre-existing. The deployment code validates their presence; it does not create, modify, or link any GPO. | GPO management is outside the scope of this feature. |
| CON-009 | There are exactly four silos: Tier 0 Admin, Tier 1 Admin, Tier 2 Admin, Tier 2 EUD. No fifth silo may be created. General Domain Users and Domain Computers are intentionally not siloed. | A fifth silo would extend enforcement to populations where it is impractical, disproportionate, and likely to cause unacceptable breakage at scale. |
| CON-010 | Domain-join service accounts (`svc-pawdomainjoin`, `svc-t1srvdomainjoin`, `svc-t2euddomainjoin`) are structurally exempt from silo membership. The code must explicitly exclude them by SID regardless of OU or group membership. This exclusion is non-configurable. | These accounts authenticate from ephemeral build hosts outside any approved Tier device set; siloing them breaks automated device provisioning. |
| CON-011 | The Tier 0 Admin silo's `AllowedToAuthenticateFrom` device set MUST include **both** the built-in `Domain Controllers` (RID 516) **and** `Read-only Domain Controllers` (RID 521) groups. | RODC computer accounts are members of `Read-only Domain Controllers`, not `Domain Controllers`. A DC-only condition denies Tier 0 authentication originating from or via an RODC — an RODC branch-site outage. For multi-domain forests, also consider `Enterprise Read-Only Domain Controllers` (RID 498). |

---

## High-Level Functional Requirements

> **Note**: These are scoping-level requirements. Detailed FRs with cmdlet contracts, configuration schema, and acceptance criteria (AC-* table) will be completed in a subsequent design phase after the ops-guide walkthrough.

- **FR-001**: System MUST support `-IncludeAuthSilos` as a switch parameter on `Deploy-TierModel.ps1`, usable standalone and with `-FullDeployment`.
- **FR-002**: System MUST support `-IncludeAuthSilos` as a switch parameter on `Audit-TierModel.ps1`. Without `-IncludeAuthSilos`, silo state MUST NOT be checked or reported.
- **FR-003**: When `-IncludeAuthSilos` is specified on deployment, the system MUST create `msDS-AuthNPolicySilo` silo objects and `msDS-AuthNPolicies` policy objects (one per account class: user, computer, service) for each configured tier. Creating policy objects without silo objects is insufficient.
- **FR-004**: All silo and policy objects created by deployment MUST have `Enforce = false`. No code path in the `-IncludeAuthSilos` deployment flow may set `Enforce = true`.
- **FR-005**: `AllowedToAuthenticateFrom` SDDL MUST use OR logic (`Member_of_any`) for device groups. AND logic (`&&`) between device group SIDs is prohibited.
- **FR-006**: Prior to any AD write, the system MUST validate all prerequisites: (a) DFL ≥ Windows Server 2012 R2, (b) FAST/Kerberos Armoring GPOs confirmed active on DCs, (c) configured Tier device groups exist and are non-empty, (d) target accounts are resolvable, (e) required AD module present. Failure of any check MUST halt with a stable error code; no AD writes may occur.
- **FR-007**: System MUST be idempotent — a second run against already-converged state reports 0 actions (`Converged = True`) and makes zero AD writes.
- **FR-008**: Account assignment MUST be delta-only: only accounts where desired state differs from actual state are granted access to or assigned membership in a silo. Writing the full membership set unconditionally is prohibited.
- **FR-009**: The built-in domain Administrator (RID-500) MUST be structurally excluded from silo membership by SID suffix match. This exclusion is non-configurable.
- **FR-010**: System MUST support plan/dry-run mode without `-ConfirmApply` — zero AD writes; plan output shows what would be created or changed.
- **FR-011**: System MUST NOT allow `-IncludeAuthSilos` combined with any `-*Only` parameter. Valid combinations: standalone or with `-FullDeployment` only.
- **FR-012**: Deployment output for audit-mode deployments MUST clearly label the deployment state as **audit-only / not protective**. No output, log, or report may imply that an audit-mode silo provides enforcement protection.
- **FR-013**: `Audit-TierModel.ps1 -IncludeAuthSilos` MUST detect all drift conditions: changed policy settings, unexpected or regressed `Enforce` state, missing or extra account assignments, empty device groups, and silo or policy object deletion or modification.
- **FR-014**: Any reconciliation automation (if introduced) MUST be delta-only, threshold-protected with separate add/remove thresholds, fail-safe on empty or partial source queries, centrally logged with run ID and delta counts, and single-writer. Detailed implementation requirements are deferred.
- **FR-015**: System MUST log all operations with `Write-TierModelLog` including CorrelationId, Level, Message, and Data. No credential or sensitive data may be logged.

### Key Entities

| Entity | Definition |
|---|---|
| **Authentication Policy Silo** | An AD DS object (`msDS-AuthNPolicySilo`) grouping user, computer, and service accounts and referencing per-class authentication policies for silo members. Carries its own `Enforce` state. |
| **Authentication Policy** | An AD DS object (`msDS-AuthNPolicies`) defining per-account-class settings: TGT lifetime, `AllowedToAuthenticateFrom`, `AllowedToAuthenticateTo`, optional NTLM switches, and `Enforce` state. |
| **Tier Device Group** | An AD security group whose members are approved admin workstations (PAWs) or management servers for a given tier. Used as SID references in `AllowedToAuthenticateFrom` SDDL conditions. |
| **Silo Permitted Account** | An account granted access to join a silo via `Grant-ADAuthenticationPolicySiloAccess`. Permission to join is distinct from silo membership. |
| **Silo Assignment** | An account linked to a silo (and thereby to the silo's per-class policies) via `Set-ADAccountAuthenticationPolicySilo`. Requires prior permission grant. |
| **Pre-enforcement Gates** | Twelve safety checks (G1–G12) that must be satisfied before any silo policy is promoted from audit to enforced. Enforcement is a stop condition until all applicable gates pass. |
| **RID-500 Account** | The built-in domain Administrator, platform-exempt from authentication policy evaluation. Excluded from silo membership by code invariant (SID suffix match). |
| **Audit Mode** | `Enforce = false`. The DC evaluates conditions to generate would-be-deny events (305/306) but does not apply the restriction. Audit mode is not protective. |
| **Enforced Mode** | `Enforce = true`. Non-compliant Kerberos requests are denied and generate events 105/106. |
| **Delta** | The difference between desired silo membership state and actual silo membership state: accounts to add, accounts to remove, and accounts already converged. |

---

## Out of Scope

| Item | Reason |
|---|---|
| Enforcement flip implementation | Deferred to design phase after ops-guide walkthrough (OQ-002/OQ-006) |
| General Domain Users / Domain Computers siloing | Intentionally not siloed — see CON-009 and the privileged-accounts-only scope constraint |
| Cross-forest silo coverage | Not documented by Microsoft as supported; treat as out of scope until lab-validated |
| Protected Users group management | A separate identity-hardening control not part of this feature |
| User Rights Assignment (URA) configuration | A complementary control managed via existing Account Restriction GPOs; unchanged by this feature |
| Exemption automation | Detailed exemption lifecycle management beyond the three documented structural exemptions is a deferred design decision (OQ-003) |
| Service-account (gMSA) silo scope in wave 1 | gMSA-in-silo behavior requires lab validation; deferred to design phase (OQ-004) |
| SIEM alert rules and monitoring configuration | Owned by the operator/SOC team |
| Rollback cmdlet | Revert to audit by toggling `Enforce`; no dedicated rollback cmdlet required |
| Source-material script modification | Scripts are frozen evidence; must not be modified or run |
| Scheduled reconciliation automation | Deploy-time only in the first wave; scheduled automation is a future design decision |

---

## Open Questions / Deferred

Items marked **RESOLVED** were settled by Joel's approval of the four-silo model. Remaining items are deferred to the design phase after the ops-guide walkthrough.

| ID | Question | Status | Impact |
|---|---|---|---|
| OQ-001 | **Converge recipe for account assignment**: Exact delta reconciliation pattern for silo grants and assignments — add-only, full-delta, or report-only? SID normalization approach? | **Open** — deferred to design phase | Drives FR-008 detailed implementation |
| OQ-002 | **Enforcement flip UX**: What does the enforcement flip operation look like? Single cmdlet with acknowledgement? Per-silo scope or all-silos? Two-phase confirmation? | **Open** — deferred to design phase | Drives User Story 3 implementation |
| OQ-003 | **Exemption model beyond domain-join accounts**: How are time-bounded exemptions (other than the three structural ones) tracked — AD attribute, config file, or external register? Who can grant? How is expiry enforced? | **Partially resolved** — three structural domain-join exemptions are documented (CON-010, "Domain-Join Service Account Exemptions" section). Governance model for additional exemptions is deferred. | Drives exemption data structure |
| OQ-004 | **Service account (gMSA) silos in wave 1**: Are gMSA accounts in scope for the first implementation wave, or deferred? | **Open** — deferred to design phase; gMSA-in-silo behavior requires lab validation | Drives per-class policy scope |
| OQ-005 | **Tier 2 handling** | **RESOLVED** — four-silo model approved: Tier 2 Admin silo + Tier 2 EUD silo both in scope; see "The Four-Silo Model" section | N/A |
| OQ-006 | **Pre-enforcement gate verification mechanism**: What does the code do when checking gates — report-only, blocking validation, or operator-attested checklist? | **Open** — deferred to design phase | Drives enforcement flip design |
| OQ-007 | **Configuration schema shape**: Is the configuration per-silo JSON? What are the naming conventions and placeholder patterns? | **Open** — deferred to design phase | Drives config file design |
| OQ-008 | **SDDL generation strategy**: Is `AllowedToAuthenticateFrom` SDDL computed at runtime from resolved group SIDs, or authored in config? | **Open** — deferred to design phase | Drives policy creation and validation implementation |
| OQ-009 | **Lab validation requirements**: Which UAT scenarios must pass before audit-mode deployment is considered ready? Before enforcement is permitted? | **Open** — UAT-01–15 scenarios are named; pass/fail criteria are in the ops guide | Drives test strategy and lab runbook |
| OQ-010 | **Wave structure**: Does the first wave ship deployment-only, or deployment and auditing together? | **Open** — deferred to Joel decision | Drives task phasing and version bump timing |
| OQ-011 | **Silo vs Policy `Enforce` precedence for silo members** — the audit→enforce master switch. | **RESOLVED (lab-validated 2026-08-26, WS2025).** For a silo-assigned account the **Silo's `Enforce` flag is the master switch** and governs BOTH the `AllowedToAuthenticateFrom` device restriction AND the TGT lifetime. **Silo=Audit** → non-approved device allowed + **305** would-be-deny + domain-default TGT (e.g. 10h, renewable). **Silo=Enforce** → non-approved device **DENIED (105)** + policy TGT (e.g. 4h, non-renewable). The referenced **Policy's own `Enforce` flag has NO independent effect on silo members** (Policy=Enforce while Silo=Audit → still allowed + 10h TGT). A/B/C/D matrix captured in the ops guide. | **Guidance:** enforce the **Silo** at minimum to actually block logins and apply the short TGT; enforce **both** (recommended) for a consistent/supported config and to also govern any direct-assignment (non-silo) accounts. Trap: enforcing only the Policy object with the Silo in audit blocks nothing. Also resolves TGT-lifetime-in-audit (research VAL-A1-08): TGT lifetime tracks the **Silo** flag. |
| OQ-012 | **gMSA-in-silo behavior**: Do group managed service accounts function correctly when assigned to an auth policy silo? | **Open** — requires lab validation (AS-Q-22 from research) | Determines whether gMSA accounts can be included in wave 1 service policies |
| OQ-013 | **RDP (NLA/CredSSP) to Tier 0 targets denied while interactive logon succeeds**: Lab-observed 2026-08-25 — with Tier 0 enforced, `t0-admin1` (Domain Admin) logs on **interactively** to DC01 and TIERLAB-SERVER (both approved origins: `Domain Controllers` / `Tier0MemberServers`), but **RDP** to either is **denied — event 105, blank Device Name**. **Root cause identified 2026-08-26 (lab):** the RDP-NLA target requests the delegated user's TGT *from itself*, so the **target machine's own client Kerberos armoring must be active** — and it is NOT effective on DC01/TIERLAB-SERVER (KDC `CbacAndArmorLevel` blank in `HKLM\SYSTEM\CurrentControlSet\Services\Kdc`; no domain GPO delivers armoring; bits present look local/manual). Confirmed via 105 events showing `Client Address` = the TARGET (.11 server, .20 client) with blank Device Name. This is the documented target-side armoring requirement (research BRK-17), NOT a fundamental silo/RDP incompatibility. | **Root-caused; fix pending.** Fix: client Kerberos armoring GPO (`EnableCbacAndArmor`) must be linked to and effective on **every** tier computer OU — **Domain Controllers OU + Member Servers OUs + PAW OUs** — plus KDC "Always provide claims" on the DC OU, then **reboot every machine**. Re-test in AUDIT first (305 should vanish once target armoring is active), then enforce. | **Blocks enforcement** for admins who RDP to Tier 0 servers/DCs — a core Tier 0 admin path. The Tier Model must link the client-armoring GPO to ALL tier computer OUs (incl. Domain Controllers), not just workstation OUs. |

---

## Dependencies

- Spec 001 (Tier Model AD Deployment & Audit Module) — base infrastructure required.
- Spec 004 (`-EnableAuditing`) — establishes the `-IncludeX` switch pattern and audit lifecycle conventions that this spec extends.
- Active Directory PowerShell module and Windows Server 2012 R2+ DFL.
- Kerberos Armoring (FAST) GPOs — pre-existing in the Tier Model; this feature validates, not creates.
- Tier device groups (all four tiers + EUD) pre-populated by the operator; this feature validates group existence and non-emptiness.
- **Tier 2 EUD config additions** — `svc-t2euddomainjoin` service account, `Tier2EUDDomainJoin` group, `Tier 2 EUD Staging` OU, delegated create-computer rights, and Account Restriction GPO must be added to the Tier Model base config before the Tier 2 EUD silo can be deployed (see "Required New Config Addition" section).

---

## Assumptions

- Deployment context runs as Domain Admin with sufficient AD rights to create and modify `msDS-AuthNPolicies` and `msDS-AuthNPolicySilo` objects.
- Tier device groups (PAWs, management servers, EUD devices per tier) are operator-maintained and pre-populated before `-IncludeAuthSilos` is invoked.
- The single-domain topology is the initial target; multi-domain support may extend the design but is not required for the first wave.
- Lab environment (`TierLab-DC01`, `tierlab.internal`) is available for validation.
- The existing Tier Model GPOs already include Kerberos Armoring settings; no new GPO must be created for this feature beyond the Tier 2 EUD Account Restriction GPO required by the new config addition.

---

## Version

| Item | Change |
|---|---|
| Module manifest (`TierModel.psd1`) | Version bump TBD — pending wave structure decision (OQ-010) |
