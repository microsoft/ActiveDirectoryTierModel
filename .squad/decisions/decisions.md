### 2026-08-14: Deploy-TierModel.ps1 comment-based help must stay in sync (Joel)

**By:** Joel Platek (via Copilot coordinator)

**Convention:** The comment-based help at the top of Deploy-TierModel.ps1 must document EVERY parameter with an accurate .PARAMETER block, and .DESCRIPTION/.EXAMPLE/.NOTES must reflect current behavior. When any parameter is added or its behavior changes (e.g. the audit-script edits), the help block must be updated in the same change. Help had drifted — missing .PARAMETER for -IncludeMsa/-IncludeGmsa/-IncludeDmsa/-IncludeWinLaps/-EnableAuditing/-AdmlLanguage and a stale .NOTES "Version: 2.0".

**Lab staging note:** .research/copilot-cli-hyperv-ad-lab/scripts/Restage-Lab.ps1 restores a NAMED checkpoint (default WinLapsSchema) + copies repo files to C:\TierModel on the DC WITHOUT deploying — use for manual-UAT staging.

---

### 2026-08-14: Audit rights validated per-right (granular output) — Beast

**Branch:** feature/domain-auditing | **Status:** Implemented

`Test-TierModelAuditRule` emits a per-right validation line for EVERY configured right in `domainAuditRule.rights`, modelled on `Test-TierModelGPOContent.ps1` URA validation:
```
        ✅ Right 'CreateChild' - present
        ❌ Right 'WriteDacl' - missing
```
Each right also produces a `{Type='AuditRight', Status='Pass'/'Fail'}` finding entry for downstream Sentinel tooling. `TotalChecked` stays 1 (rule count, not right count); `Drift` stays 0/1 (per-rule); `-Silent` suppresses all host output. Lab evidence (TierLab-DC01): ABSENT → all 9 ❌; PARTIAL (7-of-9) → 7 ✅ / 2 ❌; canonical + extra Failure ACE → all 9 ✅ COMPLIANT (ignored); restore → canonical converge idempotent.

---

### 2026-08-29: PowerShell 7.0+ requirement — block Windows PowerShell 5.1 — Beast

**Status:** APPROVED & IMPLEMENTED | **Commits:** 73b0521 (PS7 requirement + preflight guard)

Update-TierModelMembership.ps1 and all new tier-automation scripts target PowerShell 7.x exclusively. Rationale: (1) Windows PowerShell 5.1 is closed-source, unmaintained, end-of-life; (2) PS7 offers superior performance, security patching, and cross-platform foundation for future expansion. Preflight validation added: `#requires -Version 7.0` header + inline guard block for graceful user messaging. Breaks Windows PowerShell 5.1 execution; DCs and management hosts must run pwsh.exe or update Windows PowerShell policy via Group Policy or manual PS7 installation.

**Impact:** Storm (operational runbooks must document PS7 requirement); Wolverine (test matrix assumes PS 7.5.1+); Cyclops (no breaking change to Deploy-TierModel.ps1).

---

### 2026-08-29: Tier 2 Option X: Operator vs EUD disambiguated by group membership — Beast

**Status:** APPROVED & IMPLEMENTED | **Commits:** 9517474 (Tier 2 Operators/EUD Option X)

Single-valued policy for Tier 2 device operators. EUD status determined by membership in `Tier2LocalDeviceOperators`, NOT by OU location. Tier 2 Operator auth policy always wins in conflicts due to single-valued constraint; mandatory execution order: `-Tier2Operators` runs BEFORE `-Tier2Eud`. New user default (no Tier2LocalDeviceOperators membership) is treated as operator, with optional customer-curated pre-staging via group membership to override.

**Impact:** Wolverine (test matrix includes operator-wins conflict scenario); Storm (doc must clarify membership-driven device classification).

---

### 2026-08-29: Service account exclusion removes both policy AND group membership — Beast

**Status:** APPROVED & IMPLEMENTED | **Commits:** 71df4e1–eb23bfd (all tier switches)

Exclusion model for service accounts: (1) excluded OPERATOR/USER accounts remain in the operator group (URA still governs; only silo policy removed); (2) excluded SERVICE accounts are removed from BOTH the auth-policy assignment AND the service-accounts group. Rationale: deny-outside-tier URA/IPSec rules could break network connectivity for excluded service accounts if they remain group members. Operator/user exclusion is conservative—only policy is removed—allowing URA to govern inclusion.

**Impact:** Cyclops (exclusion attribute semantics); Storm (doc: deprovisioning scenarios, future group-membership removal scope).

---

### 2026-08-29: Update-TierModelMembership reconciliation script — optional DC-based automation — Beast

**Date:** 2026-08-27  
**Author:** Beast (Core Dev)  
**Status:** APPROVED & IMPLEMENTED  
**Commits:** 71df4e1 (Tier 0), 64306ce (Tier 1), 73b0521 (Tier 2), 9517474 (Tier 2 Ops/EUD), eb23bfd (-EnableDebug, -EnableLogging)  
**Plan:** `.research/auth-silos/Update-TierModelMembership.PLAN.md` (gitignored, local)

**Summary:** Unified reconciliation script to replace 6 legacy per-tier scripts. Keeps Tier Model auth policy coverage current via two mechanisms: (1) additive group membership for computers/accounts, (2) enforced auth policy assignment for accounts. 15 granular switches, config-driven DN resolution, customer-configurable exclusion attribute.

**Key Decisions:**
- Execution model: DC + local scheduled task + SYSTEM context. GPO/SYSVOL script-hijack risk does not apply to local scheduled tasks. Script-integrity hardening (ACL-locked local path + Authenticode code signing) is the real control. gMSA-on-management-host documented as optional alternative only.
- Group membership is additive-only in v1; policy assignment is enforced.
- msDS-AssignedAuthNPolicy is single-valued; Tier 2 Operator wins over EUD in conflicts.
- Tier2LocalDeviceOperators membership is NOT managed by this script—customer-curated. EUD status determined by group membership, not OU location.
- Targets PowerShell 7.x; blocks Windows PowerShell 5.1.

**Deferred:** -LogEventID until Joel supplies Sentinel-aligned event IDs/messages.

**Impact:** Storm (operational documentation); Wolverine (Pester tests pending post-UAT); Cyclops (create-once model confirmed compatible).
