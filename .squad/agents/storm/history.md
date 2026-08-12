# storm — History

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
