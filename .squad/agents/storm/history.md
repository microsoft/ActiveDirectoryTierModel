# storm — History (Summarized)

## Session 2026-09-02 (Pass 4) — Auth Silos Ops Guide: Option 2 table corrections

**Status:** ✅ COMPLETE
**Line count:** 453 → 460

### Changes Made
- RDP column corrected to `—` for 4 GPOs whose baseline (`{84CF8070}` / `{22F75F61}`) does NOT
  contain the Credentials Delegation setting: `*- Tier 0/1/2 PAWs Account Restrictions` and
  `*- Tier Model Computer Quarantine Account Restrictions`. Verified against config/tiermodel-gpos.json by Joel.
- Added note under table explaining why PAWs/Quarantine differ (different GPO baseline, not the shared Account Restrictions baseline).
- Override-Deny template row: added footnote clarifying that "Batch · Net · RDS · Svc" is the combined set; each individual Override template adds Tier2EUDDomainJoin to its single named right only.

---

**Status:** ✅ COMPLETE
**Line count:** 422 → 453
**Scope:** Expanded Option 2 (manual GPO edit) in the migration appendix into a scannable
per-GPO checklist table.

### Changes Made
- Replaced Option 2 prose block with:
  - URA rights legend table (Net/Batch/Svc/Local/RDS symbols)
  - RDP setting path called out once at the top (applies to all rows)
  - Per-GPO table (13 rows): every Account Restrictions GPO × URA rights from scope table +
    RDP Credentials Delegation ✓
  - Staging GPOs (`*- Tier 0/1 Servers Staging`, `*- Tier Model PAW Staging`) marked — for URA
    (not in scope table) + ✓ for RDP setting
  - Template GPOs marked — for URA + ✓ for RDP setting
  - Separate explicit entry for `*- Tier 0 DCs Authentication Silo - Computer` (3 additions:
    KDC claims/armoring, RDP Credentials Delegation, GPP Registry item for audit channel)

### Unsure / Flagged for Cyclops
- Staging GPOs and template GPOs are NOT in the Deny-URA scope table; marked "—" for URA.
  Cyclops should confirm whether these GPOs also need Tier2EUDDomainJoin added to any deny rights.
- KDC setting full name used: "KDC support for claims, compound authentication and Kerberos
  armoring" — verify this is the exact ADMX display name for the policy.

---

**Status:** ✅ COMPLETE
**Starting line count:** 238 → **Final line count:** 422
**Scope:** Joel's review + new requirements incorporated. Joel's own edits preserved
("behavior", "(ADAC - dsac.exe)", "(Same for Tier 1)" headings, no quotes on TierModelExclude
in Example A, Example B changed to Tier 1).

### Changes Made

**Part 1 — IMPORTANT upgrade callout** added at the top (below intro, above "Who this is for"),
linking to `#appendix-upgrading-from-v1x-to-v200`.

**Part 2 — New section "Auth silos complement URA and Restricted Groups"** inserted after
"How the policies, silos, and devices are linked". Covers: Account Restrictions GPO gap-cover,
silos restrict WHERE not HOW (no logon-type restriction), why URA is still needed.

**Part 3 — Appendix: Upgrading from v1.x to v2.0.0** added before Related Reading. Includes:
- Breaking change callout
- What's new delta (new groups/SA, OU ACL, auth silos, modified GPOs)
- Tier2EUDDomainJoin deny-URA scope table
- Ordered migration steps (Group → User → OuAcls → AuthSilos → Gpos)
- Two GPO options (Option 1 = fresh redeploy recommended; Option 2 = manual edits)

**Part 4** — Related reading already in correct `.md` format; all 4 targets verified to exist.

**Part 5 — Factual corrections applied:**
1. Exclusion wording: "removes" → "clears policy / does not add; remove memberships manually"
2. Event 105: "account blocked" → "new Kerberos TGT denied from that device (not globally blocked)"
   Event 306/106: clarified as AllowedToAuthenticateTo (TGS TARGET), not expected from this deployment
3. NTLM: expanded to note no 305 equivalent + Event 101 under enforcement + RADIUS/NPS/VPN call-out
4. LDAP simple bind: hedged — behavior under enforcement not established here
5. adminDescription/Exchange: softened to "not normally used" + inventory recommendation
6. RID-500: replaced "must remain authenticatable" with Windows-always-exempts explanation + URA/account-state note
7. Scheduled task: added -LogonType ServiceAccount; DC description → "writable, Global-Catalog domain controller"
8. Example B: fixed T0-Hourly → T1-Hourly; added per-invocation exclusion-decision requirement; -JobId output condition noted
9. Enforcement checklist: added 2 prerequisite bullets (DFL ≥ WS2012R2 + positive control test)
10. Direct-vs-silo stacking: caution added inline in linkage section
11. "Only privileged accounts" paragraph: rewritten to distinguish computer enrollment (deploy time) vs user/SA direct policy (reconciliation script)

### Key Decisions
- Anchor `#appendix-upgrading-from-v1x-to-v200` (single hyphen) computed from Python-Markdown slugify rules
- Appendix placed BEFORE Related Reading per Joel's instruction
- Preserved all of Joel's manual edits verbatim

### Unsure / Flagged for Cyclops
- "Script preflight rejects RODCs and non-GC DCs" — stated as Joel-verified fact; not confirmed in the 220 lines of script read. Cyclops should verify the preflight check exists.
- Event 101 (NTLM under enforcement) — carried from Joel's correction; not independently verified against Microsoft docs.

---

## Session 2026-09-02 — Auth Silos Ops Guide: Full Public Rewrite

**Status:** ✅ COMPLETE
**Deliverable:** docs/auth-silos-operations-guide.md rewritten from ~1580 lines / 94 KB to 238 lines.
Filename preserved so mkdocs nav and inbound links continue to work.

### Sections Delivered (in order)
1. Title + one-paragraph intro
2. Who this is for and why
3. What gets deployed (8-object table, AUDIT mode callout)
4. How the policies, silos, and devices are linked
5. Check the event log for failed attempts (before you enforce)
6. Manual maintenance (Tier 0 user + computer, generalized to all tiers)
7. Automating maintenance with the reconciliation script (scheduling examples A/B/C, exclusions, logging)
8. Limitations
9. Related reading

### What Was Removed
- UAT Test-Case Index (15 scenarios)
- SDDL explained / deep SDDL walkthrough (mention only kept)
- Appendix A: Building Silo Infrastructure from Scratch
- Negative Testing / UAT-05/06/07 sections + recording-results tables
- Per-scenario command dumps (Scenarios 3a–3e with per-DC PowerShell blocks)
- Appendix B: Upgrading from v1.x to v2.0.0
- Exemption-lifecycle bureaucracy tables
- Pre-enforcement gates G1–G12 detail table (condensed to 5-step checklist)
- Scenario walkthroughs with long PowerShell sequences

### Key Decisions
- "8 objects" clarified upfront as 4 policies + 4 silos (not "8 silos")
- Object names preserved with exact `*- ` prefix
- TGT lifetimes and device group names grounded in config/tiermodel-authsilos.json
- Script facts grounded in optional/Update-TierModelMembership.ps1 lines 1–220
- adminDescription recommendation kept (Exchange-safe, always available)
- Docs cross-refs verified: best-practices.md, gpo-management-guidance.md, tiermodel-logging.md, sentinel-monitoring.md all confirmed to exist

### Unsure / Flagged for Cyclops Verification
- Event IDs 306/106 (TGS target restrictions) were in the original doc; included as a one-liner footnote row. If these are unconfirmed lab-only, Cyclops should remove them.
- LDAP simple bind as a blind spot was in the original doc marked [Lab validation required]; kept as a bullet under Blind Spots with no validation claim.

---

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
