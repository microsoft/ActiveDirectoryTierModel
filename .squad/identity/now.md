---
updated_at: 2026-05-29T07:54:52.154Z
focus_area: Initial setup
active_issues: []
---

# What We're Focused On

Getting started. Updated by coordinator at session start.

- 2026-08-04: Focus = Sentinel monitoring docs. Branch feature/sentinel-monitoring-docs; removed optional/TIerModel-Sentinel (commit 5e9bdd5, local/unpushed). Next: write docs/sentinel-monitoring.md with 25 screenshots + mkdocs/README wiring; reference optional/Enable-TierModelAuditing.ps1 as audit prereq; open+link issue before PR; PIM up (VAsHachiRoku) before push.

## 2026-08-06 (tomorrow) - GPO Management Guidance, next iteration
Branch: feature/gpo-management-guidance (doc-revision committed, NOT pushed). Preview via mkdocs serve.
REMINDERS FOR JOEL (he explicitly asked to be reminded):
1. BEAST REMINDER - Account Restrictions is THE foundation (root link order 1, enabled day one, the single most important GPO). RESTRUCTURE the doc to introduce Account Restrictions MUCH EARLIER (currently first detailed in section 12). Bring its importance up front.
2. ADD A NEW SECTION NEAR THE END - Default Domain Policy & Default Domain Controller Policy cleanup: removing non-default settings; move custom settings out to baselines/SOE; never modify DDP/DDCP except the password policy (ties to DSRM recovery guidance).
Still-held for owner decision (Beast gap suggestions): allow-side rights; domain-root '*- Tier Model Account Restrictions' GPO; gPOptions=1 mechanism; virtual accounts (NT SERVICE\).

- 2026-08-06 EOD: GPO guidance + Sentinel docs COMMITTED (eab18ac) on feature/gpo-management-guidance; NOT pushed. User could not PIM today -> PIM tomorrow. Then run: push branch; gh issue create (files/issue-docs-monitoring-gpo.md); gh pr create --base main Closes #<issue> (files/PR-body-docs-monitoring-gpo.md). Combined PR = Sentinel monitoring + GPO guidance. Active gh acct VAsHachiRoku.

- 2026-08-11: Focus = BUG-006 canonical-ACL pre-flight. Branch feature: fix/bug-006-canonical-acl-check (commit 176d443 removed Migrate-LegacyTierModel.ps1). Agreed: HARD fail-fast (0 objects, all modes), check ONLY domain-root DACL, place near END of Test-TierModelPrerequisites, detect-only never rewrite. De-risked locally: detection = CommonSecurityDescriptor.DiscretionaryAcl.IsCanonical (no live AD for unit tests); repro = pure-PowerShell RawAcl (no VBS). NEXT SESSION: Joel restarts VSC as ADMIN -> dispatch Beast+Wolverine to reproduce in lab (TierLab-DC01, checkpoint+rollback) so Joel SEES the bug, THEN discuss in-product check + friendly error message + new GitHub remediation page (Storm). Full plan: .squad/decisions/inbox/coordinator-bug006-canonical-acl-plan.md
