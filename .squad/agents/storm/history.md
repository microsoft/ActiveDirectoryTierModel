# storm — History

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
