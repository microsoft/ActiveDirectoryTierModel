# Session Log: Auth Silo Lab Setup Deployment

**Date:** 2026-08-25T11:40:00Z (UTC)  
**Author:** Beast (Dr. Hank McCoy) / Copilot Coordinator  
**Status:** ✅ COMPLETE — Lab baseline ready for Joel UAT

---

## What Was Deployed

### Device Groups (2)
- **Tier2PAWDevices** — Universal group in OU=Tier 2 Groups; designated approved origination device for Tier 2 Admin silo
- **Tier2EUDDevices** — Universal group in OU=Tier 2 Groups; designated approved origination device for Tier 2 EUD silo

### Test Accounts (17)
Distributed across 5 organizational units, pre-assigned to appropriate tier groups:
- **Tier 0:** 2 admin accounts
- **Tier 1:** 3 admin accounts  
- **Tier 2 Admin:** 4 admin accounts (from SAW devices)
- **Tier 2 EUD Local Admin:** 4 local device admin accounts (from Tier 2 EUD devices)
- **General Users:** 4 regular domain user accounts (not siloed)

### Authentication Policies (4) — All Enforce=$false (Audit Mode)
1. **T0-UserPolicy** — Tier 0 admin authentication policy; UserTGTLifetimeMins=240
2. **T1-UserPolicy** — Tier 1 admin authentication policy; UserTGTLifetimeMins=240
3. **T2Admin-UserPolicy** — Tier 2 admin authentication policy; UserTGTLifetimeMins=240
4. **T2EUD-UserPolicy** — Tier 2 EUD device admin authentication policy; UserTGTLifetimeMins=240

### Authentication Policy Silos (4) — All Enforce=$false (Audit Mode)
1. **T0-Silo** — Assigned policy T0-UserPolicy; contains Tier 0 admin accounts
2. **T1-Silo** — Assigned policy T1-UserPolicy; contains Tier 1 admin accounts
3. **T2Admin-Silo** — Assigned policy T2Admin-UserPolicy; contains Tier 2 admin accounts
4. **T2EUD-Silo** — Assigned policy T2EUD-UserPolicy; contains Tier 2 EUD device admin accounts

### Account Assignment (17 total)
Each account was processed through two-step assignment:
1. **Grant-ADAuthenticationPolicySiloAccess** — Added account to silo's permitted-accounts list (`msDS-AuthNPolicySiloGrantedAccounts`)
2. **Set-ADAccountAuthenticationPolicySilo** — Bound account to silo policy (`msDS-AssignedAuthNPolicySilo`)

Result: Both silo forward-link (`msDS-AuthNPolicySiloMembers`) and account back-link (`msDS-AssignedAuthNPolicySilo`) populated and validated.

---

## Lab Environment

**Domain:** tierlab.internal  
**DC:** TierLab-DC01  
**Baseline Checkpoint:** DC-Promoted-Clean (restored before deployment)  
**Lab Helper Script:** `.research/copilot-cli-hyperv-ad-lab/scripts/auth-silos/Setup-AuthSiloLab.ps1`

---

## Specification and Bug References

**Ties to:**
- **Spec 005** — Authentication Silos feature (`specs/005-auth-silos/spec.md`)
  - All-tier four-silo model implemented (CON-009 decision)
  - Silo enforcement boundary documented (CON-002 decision)
  - Tier 2 included (Decision 8 approved)
  - RID-500 structural exclusion in code (CON-005)
  - FAST/DAC GPO validation gated (CON-008)

- **BUG-008** — Not explicitly filed but relates to authentication policy silos design validation and lab-readiness requirements for `-IncludeAuthSilos` implementation

---

## Operational Status

**Lab is AUDIT-MODE READY for Joel's checkpoint:**
- ✅ Four silos created and assigned; no accounts locked out (Enforce=$false)
- ✅ Audit events flowing to AuthenticationPolicyFailures-DomainController channel
- ✅ No enforcement gate active — safe to restore checkpoint and iterate
- ✅ Script is fully idempotent (re-run safe)
- ✅ All cmdlet syntax gotchas documented in Beast history (auth-silo cmdlet parameters, `-Enforce` switch colon syntax, property constraints, two-step assignment, SID normalization)

**Ready for:**
1. **Joel's Checkpoint Review** — Current state can be saved as checkpoint for regression testing
2. **Manual UAT Walkthrough** — Joel can test authentication flows, event collection, silo policy scoping
3. **Code Phase Entry** — Implementation team can reference auth-silo cmdlet patterns and lab validation in code reviews
4. **Enforcement Gate Validation** — Pre-enforcement gate criteria (G1–G12) can be systematically tested before flipping Enforce=$true in production

---

## Next Steps (Joel's Decision)

1. Restore `DC-Promoted-Clean` checkpoint; take new checkpoint `auth-silo-audit-baseline`
2. Manual UAT of 15 test scenarios (reference: `.squad/decisions.md` storm-auth-silos-ops-guide; UAT table)
3. Document any cmdlet behavior observations or events not matching spec
4. Clear for implementation team to begin `-IncludeAuthSilos` production code phase
5. (Later) Enforcement flip and enforcement gate validation in separate gate-validation session

---

## Lab Technical Notes

- **SDDL OR-logic validated:** `Member_of_any` syntax confirmed working (NOT `&&` between device groups)
- **TGT lifetime restriction:** Not applied in audit mode (Enforce=$false); only takes effect at enforcement
- **Idempotency patterns:** HashSet-based tracking prevents double-assignment and duplicate grants
- **Lab password:** `LabP@ss2026!Silo` (14 chars, mixed case, digit, special; satisfies AD complexity)
- **Cmdlet gotchas documented:** All parameter colon-syntax, property constraints, two-step assignment sequence, and SID normalization behaviors recorded for code phase reference

---

**DEPLOYMENT VALIDATION: PASS**  
**LAB AUDIT-BASELINE CHECKPOINT: READY FOR EXPORT**
