# storm — History (Summarized)

## Session 2026-08-26 — v2.0.0 Appendix B: Auth Silos BREAKING CHANGE

**Status:** ✅ COMPLETE
**Content:** Appended ## Appendix B — Upgrading from v1.x.x to v2.0.0 to docs/auth-silos-operations-guide.md

### Key Decisions
- **Governing rule documented**: "Never replace or overwrite a GPO that is already in production"
- **Breaking change classification**: v2.0.0 modified link-enabled production GPOs; in-place edits are high risk
- **Sub-appendix structure (B.1–B.4) reserved** for future sessions:
  - B.1: New Tier 2 security groups + svc-t2euddomainjoin
  - B.2: New ACL delegation for Tier2EUDDomainJoin
  - B.3: Modified Tier 0 DCs Authentication Silo GPO
  - B.4: Modified Account Restrictions GPOs (7 total, Tier2EUDDomainJoin added)
- Note: Member-server Remote Credential Guard GPO changes flagged "still being finalized"

---

## Session 2026-08-24 (Pass 2) — Auth Silos Ops Guide Revision

**Status:** ✅ COMPLETE
**Scope:** Rubber-duck review + Joel's revision requirements incorporated

### Major Additions
- UAT test-case index (15 scenarios)
- All-tier scope table (4 silos, no 5th for general population)
- Tier 2 EUD walkthrough & domain-join scenarios
- Negative testing section (UAT-05/06/07)

### Critical Fixes
- Parameter correction: Set-ADAccountAuthenticationPolicySilo -Clear → -AuthenticationPolicySilo \
- RID-500 SID construction: (Get-ADDomain).DomainSID + "-500" pattern
- DSRM paragraph: removed false ntdsutil/AD DS startup claims
- RID-500 exemption: platform-exempt from silo check only; URA/account-state still apply
- Pre-enforcement gates (G1-G12): operationalized as pass/fail/STOP; G11 extended to business cycle; G3 adds SDDL SID verification
- Event ID refinements: 4719/5136/4820/4821 clarified; LDAP simple bind marked [Lab validation required]

---

## Session 2026-08-24 — Auth Silos Operations Guide Initial Authoring

**Status:** ✅ COMPLETE
**Deliverable:** docs/auth-silos-operations-guide.md (11 sections + mkdocs.yml nav entry)

### Sections Delivered
1. Overview + prerequisites
2. Silo structure (Origination Device Rule, SDDL, AND-vs-OR trap)
3. Scenario walkthroughs (T0 user/member server/PAW onboarding)
4. Audit→Enforced transition (12 pre-enforcement gates, enforcement, rollback, lockout recovery)
5. Maintenance + change control
6. Exemptions (RID-500, lifecycle, structural vs remediable)
7. Account/device lifecycle
8. Event IDs table + channel-enable
9. Troubleshooting (7 symptom→fix scenarios)
10. Limitations + layered model
11. Appendix A: build-from-scratch

### Key Decisions
- Correct Microsoft silo model only
- Origination Device Rule as organizing principle
- Kerberos armoring already deployed
- Event IDs 4820/4821 marked lab-validation-required
- Authentication Policy Failures channel enable documented as required first step
