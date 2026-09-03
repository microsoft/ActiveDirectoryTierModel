# storm — History (Summarized)

## Session 2026-09-03 — Documentation Scope: Adding `-Debug` to Deploy/Audit Scripts

**Status:** ✅ READ-ONLY SCOPING INVENTORY COMPLETE (NO MODIFICATIONS)
**Date:** 2026-09-03T13:59:39.519+08:00
**Requested by:** Joel Platek
**Trigger:** Team scoping to add `-Debug` (debug log file) capability to `Deploy-TierModel.ps1` and `Audit-TierModel.ps1`, using `optional\Update-TierModelMembership.ps1` v1.7.2 as reference.

### Inventory Summary

#### Current State — Existing Logging Parameters
1. **Deploy-TierModel.ps1**: 
   - `.PARAMETER Logging` (switch, enable structured logging)
   - `.PARAMETER LogPath` (directory, where logs written)
   - `.PARAMETER OutputFileBase` (filename prefix without timestamp/extension)
   - 3 `.EXAMPLE` blocks showing `-Logging` usage

2. **Audit-TierModel.ps1**:
   - `.PARAMETER LogPath` (directory, where reports written)
   - `.PARAMETER OutputFormat` (enum: Text, Json, Html, NUnitXml)
   - `.PARAMETER OutputFileBase` (filename prefix)
   - 6 `.EXAMPLE` blocks (none show logging/output params yet)
   - Note: Audit uses **separate purpose** (reports, not logs) — different from Deploy

3. **Update-TierModelMembership.ps1** (reference — v1.7.2):
   - `.PARAMETER EnableDebug` (switch, not `-Debug`)
   - Creates `Debug\` subfolder beside script (separate from logs)
   - Filename pattern: `Update-TierModelMembership.debug.<timestamp>.<CorrelationId>.log`
   - Bounded retention: 7-day age + max 30 files + 200 MB total
   - Free-space precheck: 50 MB minimum before write
   - **FAIL-FAST**: aborts before ANY AD changes if debug file cannot be created
   - Correlation ID in both debug filename AND logging entries (for cross-referencing)
   - No `.EXAMPLE` entries demonstrate `-EnableDebug` usage
   - Help text: "deep per-decision troubleshooting dump to a Debug subfolder…"

#### Documentation Surface (What WOULD Change)

**SCRIPT COMMENT-BASED HELP (user-facing):**
| File | Content | Work |
|------|---------|------|
| `Deploy-TierModel.ps1` | `.PARAMETER -Debug` help block | Add 8–12 lines matching Membership template (directory location, retention policy, fail-fast behavior, free-space check) |
| `Deploy-TierModel.ps1` | `.EXAMPLE` blocks | Add 1–2 new examples showing `-Debug` flag combined with other parameters (e.g., `-FullDeployment -Debug`, `-OuOnly -Debug -Logging`) |
| `Audit-TierModel.ps1` | `.PARAMETER -Debug` help block | Add 8–12 lines (same template as Deploy) |
| `Audit-TierModel.ps1` | `.EXAMPLE` blocks | Add 1–2 new examples (e.g., `-FullDeployment -Debug`, `-GposOnly -Debug`) |

**PRIMARY DOCUMENTATION (docs/ folder):**
| File | Section | Work | Rough Size |
|------|---------|------|-----------|
| `docs/tiermodel-logging.md` | New top-level section after "Overview" | Add "Deployment Debug vs. Logging" (clarify `-Debug` separate from `-Logging`; filename pattern; when to use; fail-fast behavior) | 1–2 paragraphs |
| `docs/tiermodel-logging.md` | New subsection "Debug Features" under Features | Document bounded retention (age/count/size), free-space precheck, fail-fast guarantee, correlation ID cross-ref with logs | 1 section (~8–10 lines) |
| `docs/tiermodel-logging.md` | "Usage" → new "Enabling Debug in Deployment" | Add examples: `-FullDeployment -Debug`, `-OuOnly -Debug`, output file location | 1 code block + 3–5 lines |
| `docs/tiermodel-logging.md` | "Security Features" (existing) | Add note: debug files contain sensitive object DNs but never credentials (same redaction as logs) | 2–3 lines |
| `docs/tiermodel-logging.md` | "Troubleshooting" → new "Debug Log Analysis" subsection | How to read debug logs, correlation ID matching with `-Logging` output, timestamp format | 1 subsection (~6–8 lines) |
| `docs/quick-deployment-guide.md` | Section "Optional: Enable Logging" | Rename to "Optional: Enable Logging and Debug"; add `-Debug` example; clarify mutual compatibility | Expand ~8–10 lines |
| `docs/quick-deployment-guide.md` | "Troubleshooting" section | Add new "Debug Logs" bullet: location, when to use, how to share with support | 3–4 lines |

**CHANGELOG & VERSION DOCS:**
| File | Content | Work |
|------|---------|------|
| `CHANGELOG.md` | Unreleased → Added | New entry: "**Debug Logging**: Optional per-decision troubleshooting via `-Debug` in Deploy-TierModel.ps1 and Audit-TierModel.ps1, mirrors optional/Update-TierModelMembership.ps1 v1.7.2 implementation with bounded retention and fail-fast file-creation guarantee." | ~2–3 lines |
| `mkdocs.yml` | Nav (if separate page created) | No change needed (tiermodel-logging.md already in nav) |

**POTENTIAL FUTURE (if team expands debug scope):**
- New `docs/troubleshooting.md` page (does not currently exist) — would house "Run with -Debug to troubleshoot" guidance and log analysis patterns. **Not in scoping yet** — captured here as forward reference only.

#### Key Decisions Needed (NOT decided in this scoping)

1. **Parameter name**: Will Deploy/Audit use `-Debug` (shorter) or `-EnableDebug` (consistent with Membership)? 
   - **Impact**: Changes parameter reference throughout docs/help.
   
2. **Debug folder location**: Separate `Debug\` subfolder (like Membership) or mixed with `-LogPath`?
   - **Impact**: Affects "Usage" examples and file-location guidance in docs.
   
3. **File naming pattern**: Will Deploy/Audit follow `Deploy-TierModel.debug.<timestamp>.<CorrelationId>.log` or simpler pattern?
   - **Impact**: Changes documentation examples and troubleshooting walkthrough.

4. **Correlation ID**: Will Deploy/Audit embed the same CorrelationId in both debug AND `-Logging` output (like Membership)?
   - **Impact**: Affects "Security Features" and "Troubleshooting" docs (cross-referencing guidance).

5. **Audit's `-Debug` semantic**: For Audit, is `-Debug` per-module/per-check, or script-wide?
   - **Impact**: Changes examples and "Usage" documentation.

#### What WILL NOT Change (Joel's note: respect existing figures)

- Manual Integration/UAT test counts in README and test-coverage docs — **left untouched**.
- Test coverage percentages are author-maintained from Excel — **no automated changes**.

### Learnings

1. **Reference implementation proven solid**: Update-TierModelMembership.ps1 v1.7.2 shows bounded retention + fail-fast works in production; can safely mirror for Deploy/Audit.

2. **No existing troubleshooting page**: Docs currently have **no dedicated troubleshooting guide**. The "-Debug" feature would benefit from a future `docs/troubleshooting.md` stub linking to debug log analysis, but that's out of scope here.

3. **Audit vs. Deploy logging model differs**: Audit uses `-OutputFormat` (reports, not logs); Deploy uses `-Logging` (logs). Adding `-Debug` to both is consistent but the OUTPUT PURPOSE is different — Audit reports are compliance/drift findings; Deploy logs are operational records. Debug logs are diagnostic for **both**.

4. **Documentation already primed for debug**: `docs/tiermodel-logging.md` has sections for "Troubleshooting", "Log Analysis", "Security Features" — adding debug guidance is additive, not a restructure.

---

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
