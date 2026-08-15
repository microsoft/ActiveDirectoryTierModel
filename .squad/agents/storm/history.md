# storm — History

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
