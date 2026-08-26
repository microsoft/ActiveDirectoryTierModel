# storm — History

## Session 2026-08-26 — v2.0.0 Appendix B: Auth Silos BREAKING CHANGE (2026-08-26T19:47:50+08:00)

**Requested by:** Joel Platek (@VAsHachiRoku)
**Branch:** `feature/auth-silos`

**Task completed:**

Appended `## Appendix B — Upgrading from v1.x.x to v2.0.0` to `docs/auth-silos-operations-guide.md` (after the Related Reading section, end of file).

**New content delivered:**
- BREAKING CHANGE callout: v2.0.0 modified link-enabled production GPOs; in-place edits/re-imports are high risk
- Governing rule prominently stated: **never replace or overwrite a GPO that is already in production**
- v2.0.0 delta in four scannable sub-sections:
  - **B.1** — New Tier 2 security groups (`Tier2EUDDevices`, `Tier2PAWDevices`, `Tier2EUDDomainJoin`) and service account (`svc-t2euddomainjoin`)
  - **B.2** — New ACL delegation: `Tier2EUDDomainJoin` on OU=Tier 2 End-User Devices (standard domain-join set; no staging OU)
  - **B.3** — Modified GPO `*- Tier 0 DCs Authentication Silo - Computer` (KDC claims/armoring, client armoring, Remote Credential Guard, event-log channel via GPP registry)
  - **B.4** — Modified Account Restrictions GPOs (×7: domain-root + Tier 0/1 Servers/PAWs + all Override templates) — `Tier2EUDDomainJoin` added to `SeDeny*` deny lists
- "Still being finalized" note for member-server Remote Credential Guard GPO changes
- Each sub-section is a placeholder — full remediation procedures to be slotted in per-topic

**Status:** ✅ COMPLETE — working tree only, no commit.

---

## Session 2026-08-24 (Pass 2) — Auth Silos Ops Guide Revision (2026-08-24T20:20:38+08:00)

**Requested by:** Joel Platek (@VAsHachiRoku)
**Branch:** `feature/auth-silos`

**Revision pass on `docs/auth-silos-operations-guide.md` based on rubber-duck review and Joel's revision requirements.**

**New content added:**
- UAT test-case index table (15 scenarios) at the very top of the document, after the draft banner
- All-tier scope table in §2 (four silos: T0 Admin, T1 Admin, T2 Admin, T2 EUD; rationale for no 5th silo for general population)
- §3d — Tier 2 EUD silo walkthrough (onboard Local Device Admin)
- §3e — Domain-join scenarios: interactive admin (Staging OU → production → group → reboot), automated service accounts (`svc-pawdomainjoin`, `svc-t1srvdomainjoin` as structural exemptions with compensating controls), and planned `svc-t2euddomainjoin`
- §9 Negative Testing section (UAT-05/06/07 with recording template)
- Design clarifications woven into §1: narrow Kerberos-AS guarantee, authentication ≠ authorization ≠ use

**Critical fixes:**
- `Set-ADAccountAuthenticationPolicySilo -Clear` → `-AuthenticationPolicySilo $null` (invalid parameter removed)
- `Get-ADUser -Filter { objectSid -like "*-500" }` → SID constructed from `(Get-ADDomain -Server <DC>).DomainSID + "-500"`
- DSRM paragraph: removed false "ntdsutil reverses Enforce" and "manually start AD DS" claims; described accurately as disruptive last-resort
- RID-500 exemption corrected: platform-exempt from Kerberos silo check only; URA/account-state/network/firewall still apply
- Removed false "~240-minute window" claim; replaced with fresh-TGT pilot test using `klist purge` in dedicated pilot session
- Brownfield preflight (Step 0) added to §3a: check both `msDS-AssignedAuthNPolicy` and `msDS-AssignedAuthNPolicySilo` before assignment; treat existing direct assignment as migration STOP
- Pre-enforcement gates: all G1-G12 operationalized as pass/fail/STOP rows; G11 extended to full business cycle coverage + NTLM/LDAP-bind inventory; G3 adds SDDL SID verification
- Enforce composition: documents both policy Enforce AND silo Enforce; marks mixed-mode precedence as [Lab validation required]; verifies both on every DC during cutover and rollback

**Should-fixes applied:**
- 4719: corrected to "audit-policy changes" (not "channel disabled"); added channel-state polling note
- 5136: added companion events 4728/4729, 4732/4733, 4756/4757, 5137/5141
- 4820: narrowed from "equivalent" to "reported by third-party; field structure unconfirmed"; [Lab validation required]
- 4821: removed "equivalent" wording; existence is inferred only
- LDAP simple bind: changed from "bypasses" (presented as fact) to [Lab validation required] throughout
- §3b Step 5: specified console/local logon as test transport (not RDP/NLA); NLA/delegation marked [Lab validation required]
- Opening promise: softened to narrow Kerberos AS exchange statement
- AccountNotDelegated: moved to separately-approved hardening step
- Unassignment: added `Revoke-ADAuthenticationPolicySiloAccess` + verify both attributes in movers/leavers

**Status:** ✅ COMPLETE — working tree only, no commit.

---

## Session 2026-08-24 — Auth Silos Operations Guide (2026-08-24T19:22:09+08:00)

**Requested by:** Joel Platek (@VAsHachiRoku)
**Branch:** `feature/auth-silos`

**Task completed:**

Created `docs/auth-silos-operations-guide.md` — a draft operations guide for Authentication Policy Silos. Added nav entry in `mkdocs.yml` after "Best Practices & Hardening."

**Sections delivered:**
1. Overview: plain-language explanation of silos, prerequisites checklist, confirmation that Kerberos armoring is already deployed by the Tier Model.
2. Silo structure: object inventory, Origination Device Rule, SDDL explained, AND-vs-OR trap documented.
3. Scenario walkthroughs: onboard new Tier 0 user / new member server / new PAW — all with step-by-step instructions, WHY and HOW TO VERIFY for each step, and "what breaks if you skip" tables.
4. Audit → Enforced transition with 12 pre-enforcement gates, enforcement procedure, rollback runbook, and total-lockout recovery runbook.
5. Daily/weekly/monthly maintenance including change-control requirements.
6. Exemptions: RID-500 permanent exemption, lifecycle, structural vs remediable distinction.
7. Lifecycle: joiner/mover/leaver for accounts and devices; account-vs-device lifecycle separation.
8. Event IDs table (105, 305, 106, 306, 101, 4820, 4821, 5136, 4719); channel-enable command; blind spots.
9. Troubleshooting: 7 symptom→cause→fix scenarios including total lockout recovery runbook.
10. Limitations table; layered model for complementary controls.
11. Appendix A: build-from-scratch sequence.

**Key decisions:**
- Correct Microsoft silo model only; `source-material/` scripts approach explicitly excluded.
- AND-vs-OR SDDL trap highlighted prominently; "Member of any" ADAC setting called out.
- Origination Device Rule as organizing principle for device group membership.
- Kerberos armoring as already-deployed (verify, don't create).
- Event IDs 4820/4821 marked lab-validation-required.
- Authentication Policy Failures channel enable documented as required first step.

**Status:** ✅ COMPLETE — files in working tree, no commit.

---

## Session 2026-08-17 — CHANGELOG v1.3.0 Release Notes (2026-08-17T10:22:31+08:00)

**Requested by:** Joel Platek (@VAsHachiRoku)

**Context:** Feature branch `feature/domain-auditing` is ready for v1.3.0 release documentation. Commits 6d6ad8e + dbda98b contain the -EnableAuditing parameter, four new audit rule cmdlets, config files, documentation, and comprehensive test coverage.

**Task completed:**

1. **CHANGELOG.md — New `## [1.3.0] - 2026-08-17` entry** inserted directly below `## [Unreleased]` (empty) and above `## [1.2.3]`, matching the exact "Keep a Changelog" format and voice of existing entries.

   **Subsections documented:**
   - **Added:** `-EnableAuditing` parameter on Deploy-TierModel.ps1 (issue #38); four new cmdlets (Get/New/Test-TierModelAuditRule, Get-TierModelAuditRuleFd); config files (tiermodel-audit.json + schema); second confirmation gate with auditing-impact warning; Audit-TierModel.ps1 -EnableAuditing support; documentation (Step 11 in detailed deployment guide, Sentinel monitoring updates).
   - **Changed:** Module version 1.2.3 → 1.3.0 (+4 exported cmdlets); Pester 5.x hard-pin, 6.x block in test runner.
   - **Removed:** Legacy `optional/Enable-TierModelAuditing.ps1` (functionality now built into -EnableAuditing).
   - **Tests:** New Unit.AuditRuleOperations.Tests.ps1 (47 tests); 1,533 total tests passing under Pester 5.x; 89.65% command coverage (audit cmdlets 84–100%, Audit-TierModel 85.9%, Deploy-TierModel 81.53%).

2. **Verification:** `Select-String -Path CHANGELOG.md -Pattern '## \[1.3.0\]'` returned exactly one match at line 10, positioned between [Unreleased] (line 9) and [1.2.3] (line 42).

**Status:** ✅ COMPLETE — CHANGELOG.md ready for v1.3.0 release. No commits made (per owner direction).

---

## Session 2026-08-15 — Domain-Auditing Feature Documentation Rebuild (2026-08-15T14:29:48+08:00)

**Requested by:** Joel Platek (@VAsHachiRoku)

**Context:** Documentation updates from Session 2026-08-14 were lost in a `git reset` after a PowerShell terminal crash. This session rebuilds both docs from the stored history notes (which were approved by Joel). The feature branch `feature/domain-auditing` (module v1.3.0) is committed at 6d6ad8e.

**Tasks completed:**

1. **docs/sentinel-monitoring.md** — Rebuilt "Before you begin" bullet (lines 29–40, formerly 29–39):
   - **Removed:** Stale broken link to deleted `optional/Enable-TierModelAuditing.ps1` script
   - **Removed:** "Coming in a future release" placeholder note (feature has shipped in v1.3.0)
   - **Added:** Clear two-part monitoring prerequisite documentation:
     - Part 1: Domain-root SACL audit rule via `Deploy-TierModel.ps1 -EnableAuditing -ConfirmApply` (NEW in v1.3.0; selects what to audit: Everyone, Success, All-inheritance, 9 rights)
     - Part 2: DC Advanced Audit Policy GPO (`*- Tier 0 DCs Advanced Audit Policy - Computer`; pre-deployed, linked by default; enables event generation)
   - **Kept:** Event-log sizing/rollover warning (still valid and important)
   - **Added:** Explicit replication-delay note (15 minutes for SACL convergence)
   - Tone and structure consistent with existing page

2. **docs/detailed-deployment-guide.md** — Rebuilt Step 11 section (new, inserted after Windows LAPS section, before "After completing all deployment steps"):
   - **Step 11 title:** "Configure Domain-Root Auditing (Optional)"
   - **Step 11.1:** Plan audit SACL deployment (no writes, no prompts; shows Phase 11 action and ACE details)
   - **Step 11.2:** Deploy audit SACL with `-ConfirmApply` (explains two-Y sequence: auditing-impact Y FIRST, then standard deploy Y SECOND)
   - **Step 11.3:** Audit compliance with `Audit-TierModel.ps1 -EnableAuditing` (granular per-right ✅/❌ output)
   - **Composition:** `-FullDeployment -EnableAuditing` (clean, documented)
   - **Mutual exclusion:** Explained `-EnableAuditing` incompatibility with `-*Only` switches
   - **Prerequisites:** SeSecurityPrivilege, preferred DC binding, Tier Model pre-deployed
   - **Cross-link:** Sentinel monitoring prerequisite reminder with link to sentinel-monitoring.md
   - **Idempotency note:** Re-runs skip converged domain root, exit cleanly
   - Matches existing guide structure, heading levels, markdown style

3. **Verified absence of deleted-script references:**
   - Grep of both updated docs for `Enable-TierModelAuditing`: **ZERO matches** ✅
   - No broken links remain
   - All content is current and accurate to v1.3.0

**Status:** ✅ COMPLETE — Documentation fully rebuilt from approved Session 2026-08-14 notes. No code changes. No commits (per owner direction). Ready for owner verification.

---

## Session 2026-08-14 — Domain-Auditing Feature Documentation (2026-08-14T19:09:17+08:00)

**Requested by:** Joel Platek (@VAsHachiRoku)

**Context:** Feature branch `feature/domain-auditing` (module v1.3.0) introduces the new `-EnableAuditing` deployment parameter and three new cmdlets (`Get-/New-/Test-TierModelAuditRule`), fully replacing the deleted `optional/Enable-TierModelAuditing.ps1` script.

**Tasks completed:**

1. **docs/sentinel-monitoring.md** — Removed all references to the now-deleted `optional/Enable-TierModelAuditing.ps1` script. Replaced with updated prerequisites section documenting:
   - `Deploy-TierModel.ps1 -EnableAuditing -ConfirmApply` as the new way to enable domain-root SACL auditing
   - Two-part relationship: SACL audit rule (domain root, Everyone, 9 rights, Success) + DC Advanced Audit Policy GPO (`*- Tier 0 DCs Advanced Audit Policy - Computer`, linked by default)
   - Note that both MUST be in place for Sentinel monitoring to function
   - SACL replication delay (allow 15 minutes for convergence)
   - Brief warning about event-log sizing and collection

2. **docs/detailed-deployment-guide.md** — Added comprehensive Step 11 section covering domain-root auditing configuration:
   - Step 11.1: Plan audit SACL deployment (what gets reviewed, no prompts, no writes)
   - Step 11.2: Deploy audit SACL with `-ConfirmApply` (explains the two-prompt sequence: audit-specific Y gate THEN standard deploy Y gate)
   - Step 11.3: Audit audit SACL compliance (`-EnableAuditing` on Audit-TierModel.ps1)
   - Composition with `-FullDeployment`
   - Prerequisites: SeSecurityPrivilege, preferred DC binding, mutual exclusion with `-*Only`
   - Sentinel monitoring prerequisite reminder (GPO + SACL)
   - Matches existing guide structure/tone

3. **Verified absence of stale references** — Grepped entire `docs/` folder; confirmed no remaining references to `Enable-TierModelAuditing` or `optional/Enable-TierModelAuditing.ps1` (aside from removed instances). Files checked: all `.md` files in `docs/`.

**Status:** ✅ COMPLETE — All documentation updates done. No code changes. No commits (per owner direction). Ready for owner review.

**Learnings:**

- **Two-part monitoring prerequisite:** The new audit feature is tightly coupled to the pre-existing DC Advanced Audit Policy GPO. Both pieces must be active simultaneously — SACL selects what to audit, GPO enables event generation. Clearly documenting this relationship prevents operator confusion about why monitoring doesn't work if only one piece is in place.
- **Confirmation UX complexity:** The new `-EnableAuditing -ConfirmApply` flow shows TWO distinct prompts in sequence (audit-specific warning first, then standard deployment confirmation). This is important to document so operators understand why they see two Y prompts and what each means.
- **Replication timing:** Added explicit guidance that SACL changes replicate via normal AD replication and operators should allow 15 minutes for convergence. This prevents premature "auditing not working" escalations.
- **Script retirement signal:** Removing the old standalone script reference entirely (not archiving) sends a clear signal that the feature is now built-in. No partial migrations or legacy paths.

---

## Session 2026-08-11 — Canonical ACL doc (BUG-006)

**Requested by:** Joel Platek (@VAsHachiRoku)

**Context:** Feature branch `feature/domain-auditing` (module v1.3.0) introduces the new `-EnableAuditing` deployment parameter and three new cmdlets (`Get-/New-/Test-TierModelAuditRule`), fully replacing the deleted `optional/Enable-TierModelAuditing.ps1` script.

**Tasks completed:**

1. **docs/sentinel-monitoring.md** — Removed all references to the now-deleted `optional/Enable-TierModelAuditing.ps1` script. Replaced with updated prerequisites section documenting:
   - `Deploy-TierModel.ps1 -EnableAuditing -ConfirmApply` as the new way to enable domain-root SACL auditing
   - Two-part relationship: SACL audit rule (domain root, Everyone, 9 rights, Success) + DC Advanced Audit Policy GPO (`*- Tier 0 DCs Advanced Audit Policy - Computer`, linked by default)
   - Note that both MUST be in place for Sentinel monitoring to function
   - SACL replication delay (allow 15 minutes for convergence)
   - Brief warning about event-log sizing and collection

2. **docs/detailed-deployment-guide.md** — Added comprehensive Step 11 section covering domain-root auditing configuration:
   - Step 11.1: Plan audit SACL deployment (what gets reviewed, no prompts, no writes)
   - Step 11.2: Deploy audit SACL with `-ConfirmApply` (explains the two-prompt sequence: audit-specific Y gate THEN standard deploy Y gate)
   - Step 11.3: Audit audit SACL compliance (`-EnableAuditing` on Audit-TierModel.ps1)
   - Composition with `-FullDeployment`
   - Prerequisites: SeSecurityPrivilege, preferred DC binding, mutual exclusion with `-*Only`
   - Sentinel monitoring prerequisite reminder (GPO + SACL)
   - Matches existing guide structure/tone

3. **Verified absence of stale references** — Grepped entire `docs/` folder; confirmed no remaining references to `Enable-TierModelAuditing` or `optional/Enable-TierModelAuditing.ps1` (aside from removed instances). Files checked: all `.md` files in `docs/`.

**Status:** ✅ COMPLETE — All documentation updates done. No code changes. No commits (per owner direction). Ready for owner review.

**Learnings:**

- **Two-part monitoring prerequisite:** The new audit feature is tightly coupled to the pre-existing DC Advanced Audit Policy GPO. Both pieces must be active simultaneously — SACL selects what to audit, GPO enables event generation. Clearly documenting this relationship prevents operator confusion about why monitoring doesn't work if only one piece is in place.
- **Confirmation UX complexity:** The new `-EnableAuditing -ConfirmApply` flow shows TWO distinct prompts in sequence (audit-specific warning first, then standard deployment confirmation). This is important to document so operators understand why they see two Y prompts and what each means.
- **Replication timing:** Added explicit guidance that SACL changes replicate via normal AD replication and operators should allow 15 minutes for convergence. This prevents premature "auditing not working" escalations.
- **Script retirement signal:** Removing the old standalone script reference entirely (not archiving) sends a clear signal that the feature is now built-in. No partial migrations or legacy paths.

---

## Session 2026-08-11 — Canonical ACL doc (BUG-006)

Created `docs/canonical-acl.md` and updated `mkdocs.yml` nav. Lab-validated with Beast's gate implementation. Finalization complete: reviewed APPROVE (nits fixed: Write-Warning in catch block, doc disclaimer removed). PENDING owner code review + PR. No commit (per owner request).

## Session 2026-08-12 — Test metrics update (+4 ByServer unit tests)

Updated published test numbers in README.md, docs/test-coverage.md, and CHANGELOG.md: 1,457 → 1,461 automated tests; 1,788 → 1,792 total; 88.69% → 88.74% docs-scope coverage; 22 → 26 new unit tests this workstream; Test-TierModelCanonicalAcl.ps1 promoted from 🔴 78.57% to 🟡 92.86% (52/4/56) and moved to correct ascending-sort position in per-file table. All three files grep-clean of old values. No commit (per owner request). Requested by Joel Platek.

### Learnings

- **Key file paths:**
  - New doc: `docs/canonical-acl.md`
  - Diagnostic script (source only, NOT shipped): `.research/copilot-cli-hyperv-ad-lab/scripts/bug006/Invoke-OuAclCanonicalRepro.ps1`
  - Nav updated in: `mkdocs.yml`
- **Canonical ACL order rule:** Explicit Deny → Explicit Allow → Inherited Deny → Inherited Allow. Non-canonical = an explicit Deny appearing *after* (below) an explicit Allow.
- **BUG-006 mechanism:** `.NET AddAccessRule` throws `System.InvalidOperationException: "This access control list is not in canonical form and therefore cannot be modified."` when targeting an object with a non-canonical DACL. The domain root's non-canonical ACL propagates to child OUs via inheritance, blocking the Tier Model's OU delegation step.
- **Repro snippet lives ONLY in the doc** — `Invoke-OuAclCanonicalRepro.ps1` is reproduced verbatim inside `docs/canonical-acl.md` as a fenced code block. It is **not** shipped as a script file in the repo.
- **Fix path:** ADUC → Advanced Features → domain root Properties → Security tab → Reorder button. Must review/remove unwanted Allow ACEs **before** reordering (reorder activates previously-ineffective Allows). Back up DCs before touching.
- **Realistic example principals used:** `CONTOSO\APAC_HelpDesk` (Allow) and `CONTOSO\Global_HelpDesk` (Deny) on `DC=contoso,DC=com`.

**STATUS (2026-08-11 end-of-session):** Doc + Beast's gate implementation lab-validated. Pending owner code review. No commit (per owner request).

## Session 2026-08-14 — Beast Batch Complete + Pending Audit Docs (2026-08-14T18:49:54+08:00)

**Beast batch status (as of 2026-08-14T18:49:54+08:00):** ✅ COMPLETE
- Header/label cleanup in Audit-TierModel.ps1 (PSScriptAnalyzer clean, staged on DC01)
- Granular per-right audit output in Test-TierModelAuditRule.ps1 (PSScriptAnalyzer clean, lab-validated 3 scenarios, staged on DC01)
- Orchestration log written; decisions merged; inbox cleared

**Pending tasks (post-UAT):**
- Update `docs/sentinel-monitoring.md`: remove old script refs, document -EnableAuditing requirement, note DC advanced-audit-policy GPO/link dependency + SACL replication delay
- Update `README.md` and `CHANGELOG.md` with audit feature release notes
- Update `docs/faq.md` with audit troubleshooting
- Coordinate with Wolverine on Pester test timing

**BLOCKED ON:** Joel's manual UAT (interactive `-EnableAuditing -ConfirmApply` double-Y flow + visual review of granular output) sign-off before final PR

## Session 2026-08-05 — GPO Management Guidance Page (Revision Pass)

Revision pass on `docs/gpo-management-guidance.md` applying all owner peer-review corrections (2026-08-05T16:09:55+08:00):

- **§1 Overview & Philosophy:** Rewrote to establish Account Restrictions GPO at link order 1 (highest, enabled day one) as the model's foundation. SOE at link order 2, overrides baselines but NOT Account Restrictions. Four-home model corrected throughout.
- **§2 Golden Rules:** Added "never put Deny URAs or RG definitions in the SOE." Updated SHF name example to `CIS v3.0.0`. Changed "unpredictable" baseline reasoning to performance rationale. Made third-party config delivery prescriptive (via GPO, never local).
- **§3 Precedence Table:** Corrected inverted table — Account Restrictions = order 1 (enabled), SOE = order 2 (disabled), SHF = 3, MS SCT = 4, feature GPOs 5–12 with accurate enabled/disabled states. Added new subsections: "User Rights Assignments Are Not Cumulative" (replace-not-merge; why overrides work) and "GPO Configuration Halves — Why We Disable One Half per GPO" (UserSettingsDisabled performance, loopback guidance).
- **§4 Post-Deployment:** Added explicit "Enable the SOE link" step. Added firewall audit-mode step before enabling baseline. Added explicit statement that SOE does not override Account Restrictions.
- **§5 Choosing Your Security Baseline:** Added requirement for vendor-provided importable GPO (CIS provides one behind membership). Added "if you don't import, you can't claim the framework" guidance and auditor disclosure note. Fixed dual-baseline rationale from "unpredictable" to "performance/processing cost." Added application-specific override path at child OU level.
- **§7 SOE:** Added explicit statement that SOE is at priority 2 and does not override Account Restrictions at priority 1.
- **§8 Review GPOs table:** Fixed first row — separated BitLocker (disk encryption) from Windows LAPS (local admin password). Adde
[truncated summary]

---

## Learnings

### Key file paths
- `docs/auth-silos-operations-guide.md` — the Auth Silos Operations Guide; all appendices live at the end, after `## 12. Related Reading`
- `config/tiermodel-gpos.json` — authoritative source for exact GPO names (use `*-` prefix convention; e.g. `*- Tier Model Account Restrictions`, `*- Tier 0 DCs Authentication Silo - Computer`)
- `.squad/decisions/inbox/` — drop team-relevant decisions here for Scribe to merge

### Document conventions (auth-silos-operations-guide.md)
- Heading style: `## Appendix X — Title`; sub-sections: `### X.N — Title`
- Tables: `|---|---|` (no padding); code-formatted GPO/group/account names with backticks
- Voice: authoritative, direct, second-person ("you"); American English
- Asterisk in GPO names inside headings: escape as `\*-`; inside table cells: use backtick code formatting
- Warning/info callouts: `> **⚠ ...**` blockquote style

### v2.0.0 appendix decision (2026-08-26)
- Appendix B documents the v2.0.0 delta as a BREAKING CHANGE for v1.x.x deployments
- Governing rule: never replace or overwrite a production GPO
- Sub-sections B.1–B.4 are placeholder stubs; full remediation procedures to be slotted in per-topic in future sessions
- GPO names confirmed from `config/tiermodel-gpos.json`: root `*- Tier Model Account Restrictions`; tier GPOs `*- Tier 0/1 Servers/PAWs Account Restrictions`; templates `*- Tier Model Template Tier 0/1 Servers Account Restrictions - Override - Deny *`
