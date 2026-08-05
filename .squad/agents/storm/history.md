# storm — History

## Session 2026-08-05 — GPO Management Guidance Page (Revision Pass)

Revision pass on `docs/gpo-management-guidance.md` applying all owner peer-review corrections (2026-08-05T16:09:55+08:00):

- **§1 Overview & Philosophy:** Rewrote to establish Account Restrictions GPO at link order 1 (highest, enabled day one) as the model's foundation. SOE at link order 2, overrides baselines but NOT Account Restrictions. Four-home model corrected throughout.
- **§2 Golden Rules:** Added "never put Deny URAs or RG definitions in the SOE." Updated SHF name example to `CIS v3.0.0`. Changed "unpredictable" baseline reasoning to performance rationale. Made third-party config delivery prescriptive (via GPO, never local).
- **§3 Precedence Table:** Corrected inverted table — Account Restrictions = order 1 (enabled), SOE = order 2 (disabled), SHF = 3, MS SCT = 4, feature GPOs 5–12 with accurate enabled/disabled states. Added new subsections: "User Rights Assignments Are Not Cumulative" (replace-not-merge; why overrides work) and "GPO Configuration Halves — Why We Disable One Half per GPO" (UserSettingsDisabled performance, loopback guidance).
- **§4 Post-Deployment:** Added explicit "Enable the SOE link" step. Added firewall audit-mode step before enabling baseline. Added explicit statement that SOE does not override Account Restrictions.
- **§5 Choosing Your Security Baseline:** Added requirement for vendor-provided importable GPO (CIS provides one behind membership). Added "if you don't import, you can't claim the framework" guidance and auditor disclosure note. Fixed dual-baseline rationale from "unpredictable" to "performance/processing cost." Added application-specific override path at child OU level.
- **§7 SOE:** Added explicit statement that SOE is at priority 2 and does not override Account Restrictions at priority 1.
- **§8 Review GPOs table:** Fixed first row — separated BitLocker (disk encryption) from Windows LAPS (local admin password). Added AV exclusions note (child-OU Security GPO). Added free/built-in callout (MDE requires license). Made third-party alternative column prescriptive throughout.
- **§9 Enforced GPOs:** Removed false "Default Domain Policy is the common example" claim. Corrected framing: Tier Model blocks inheritance; only Enforced GPOs can still reach it. Added concrete "Group Policy Inheritance tab" verification step.
- **§11 Naming:** Updated child-OU GPO naming from "URA - Computer" suffix to "Security" convention (e.g., `T1-Payroll-Web Security`).
- **§12 Deny Model:** Fixed Denied To column — each right denies the full set of Tier Model AD groups + relevant local accounts. Override 1: removed "only when vendor doesn't support gMSA" clause; corrected gMSA guidance (gMSA still needs Allow rights, doesn't eliminate URA rules). Added duplicate/rename/link-below-Security procedure. Override 2: corrected CLIUSR explanation — template removes `NT AUTHORITY\Local account` (all local accounts), not CLIUSR by name.
- **§13 Template GPOs Reference:** Added User Config disabled callout. Fixed Override-Deny-Network row (removes all local accounts, not CLIUSR by name). Renamed all template usage descriptions from "URA" to "Security." Added link-order guidance (Security GPO = priority 1, overrides below).
- **§14 Firewall:** Added prerequisite first step (Windows Firewall must be enabled + block mode before exporting policy). Fixed attacker double-negative sentence to plain affirmative statement.
- **§15 Governance:** Updated "URA GPO" → "Security GPO."
- **§16 Worked Example:** Renamed all child-OU GPOs from "URA - Computer" to "Security" convention. Fixed Starting Point description (Account Restrictions at order 1, enabled). Corrected Step 5 (Override Deny Network): explained NT AUTHORITY\Local account is what's removed, not CLIUSR by name; Override links at priority 2 below Security GPO at priority 1. Updated Step 6 firewall to verify block mode first. Updated image placeholder description to show corrected layer order.
- **§17 Upgrade Lifecycle:** Fixed CIS example version `CIS Mar2027` → `CIS v3.0.0` (or date-based label such as `Nov26`).

`mkdocs build --strict` — ✅ exit code 0, zero warnings. `site/` deleted.



**Files created/modified:**
- `docs/gpo-management-guidance.md` (new)
- `mkdocs.yml` (nav entry added after GPO Management Strategy)
- `docs/index.md` (Component Management bullet added)
- `README.md` (Core Documentation bullet added)

## Learnings

- **2026-08-05 — GPO Guidance page:** `docs/gpo-management-guidance.md` is the operational best-practices companion to `docs/gpo-management-strategy.md` (which covers JSON mechanics/schema). Key rules encoded in the page:
  - Root Tier Model OU GPOs = vendor layer, untouchable. SOE GPO = only root GPO the operator populates.
  - Pick exactly ONE security baseline (MS SCT or SHF). Never enable both simultaneously.
  - The Windows Server 2025 MS SCT baseline GPO applies correctly to all prior OS versions (2016/2019/2022). Do not create per-OS baselines and do not use WMI filters.
  - Five Deny logon rights are owned by the root Account Restrictions GPO. Allow rights are owned by the child-OU app-role GPO. Two sanctioned overrides: built-in Administrators for service/batch (prefer gMSA), and CLIUSR for Windows Failover Cluster network deny.
  - Windows Firewall "no local merge" = only GPO rules evaluated; local rules ignored even if created by a local admin.
  - Baseline upgrade lifecycle: replace-with-new → pilot scoped to test servers → expand to Authenticated Users → delete old GPO. Never edit a live production root GPO in place.
  - Diagrams left as text placeholders under `images/gpo/` for the user to create: `gpo-layer-precedence.png`, `firewall-no-local-merge.png`, `payroll-example-gpo-layers.png`.
  - The page is the authoritative public answer to per-OS-baseline requests, WMI-filter proposals, and requests to modify provided GPOs.

**Status:** ✅ SHIPPED — All tasks complete, committed, ready for Joel's UAT + release.

The Windows LAPS feature (T001–T021) is now complete and committed to feature/windows-laps branch:
- Beast (T001–T013): Implementation + audit cmdlet ✅
- Wolverine (T014–T020): Test suite (113 tests, 90.92% coverage, 1401/1401 green) ✅
- Storm (T021): Documentation (8 files, README metrics) ✅

Orchestration logs: 2026-07-16T09-34-10Z-wolverine.md and 2026-07-16T09-34-10Z-storm.md  
Session log: 2026-07-16T09-34-10Z-winlaps-feature-complete.md

Next gate: Joel's manual UAT, then PR merge, v1.2.0 release.

---

## Sessions

**2026-07-28T16:53+08:00 — BUG-003 / OQ-4 dMSA Functional Level Resolution:** Beast confirmed dMSA requires ONLY DFL=Windows2025Domain for same-domain deployments; FFL 2025 NOT required. No FFL check needed in dMSA documentation. See `.squad/decisions.md` OQ-4 resolution.

### Session 2025-07-18 — Phase 16 Documentation Updates

Updated all documentation files for Phase 16 MSA/gMSA/dMSA feature rollout:
- Updated `docs/test-tag-matrix.md`: Added MsaAcl, GmsaAcl, DmsaAcl component tags; added MsaPrereq, GmsaPrereq, DmsaPrereq prerequisite tags
- Updated `docs/detailed-deployment-guide.md`: Added Steps 7-9 for MSA/gMSA/dMSA ACL deployments (Plan → Deploy → Audit substeps); updated Component Dependencies section
- Updated `docs/deployment-methodology.md`: Added MSA/gMSA/dMSA to Deployment Order of Precedence (steps 7-9); updated Information Messages and Warning Messages to include MSA/gMSA/dMSA
- Updated `docs/drift-detection-details.md`: Added scoped audit examples for `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`; added MSA/gMSA/dMSA drift interpretation table entries; added MSA/gMSA/dMSA component-specific details with Test-TierModel* cmdlet references
- Updated `docs/cmdlet-architecture.md`: Added Phase 7-9 sections documenting 12 new cmdlets (4 per type: Get-TierModel*Acl, Get-TierModel*AclFd, New-TierModel*Acl, Test-TierModel*Acl); documented ACL model (two ACEs per delegation on object class)
- Updated `docs/test-coverage.md`: Added 12 new cmdlets to coverage table marked "⏳ Pending" with estimated line counts (~240, ~195, ~159, ~318 lines per pattern); updated total file count to 58; updated pending re-measure note with Phase 16 details
- Updated `README.md`: Updated project description to include "MSA/gMSA/dMSA Permissions"; updated test file counts (15 unit tests, 21 total test files); updated Test Coverage Highlights with 58 production files; added optional features table to Deployment Scripts section showing `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` switches

## Session 2026-08-05 — Sentinel Monitoring Documentation

Authored the Microsoft Sentinel monitoring guide for the Tier Model Content Hub solution.

**Files created/modified:**
- `docs/sentinel-monitoring.md` — new guide (two-part: philosophy + step-by-step install with 26 screenshots)
- `docs/images/sentinel/` — 26 screenshots copied from user's Downloads
- `mkdocs.yml` — added `Sentinel Monitoring: sentinel-monitoring.md` nav entry; added `validation.links.not_found: ignore` to allow image asset links under strict mode
- `docs/index.md` — added `## Monitoring` section with bullet linking the new page
- `README.md` — added `## 📊 Monitoring` section before `## 🔗 Additional Resources`; added bullet in Core Documentation list

**Build result:** `mkdocs build --strict` passes clean, 0 warnings.

## Learnings

- Parameter naming convention: Follow PowerShell PascalCase convention consistently. `-IncludeGmsa` is more readable and maintainable than mixed-case `-IncludeGMSA`.
- Rights model clarity: Explicit statement of the two-ACE pattern (scoped CreateChild/DeleteChild + GenericAll on descendants) prevents implementation ambiguity and supports auditability.
- Edge cases matter: Operational concerns (Protected Users, KDS provisioning) must be documented alongside functional requirements to set correct expectations for operations teams.
- 2026-05-29T10:10:00Z — Spec documentation merged and archived by Scribe. All parameter fixes, edge cases, and rights model clarifications preserved in decisions registry.
- **2025-07-18 — Documentation consistency:** MSA/gMSA/dMSA features marked as "Optional" requiring explicit `-Include*` switches throughout all docs; all 7 documentation files updated in a single coordinated pass; test coverage file marked as "Pending re-measure" to signal to team that measurements will shift when tests are run

## Pending: Windows LAPS Decryptor Configuration Documentation (T021)

**2026-07-16 NOTE (Scribe):** T013 Windows LAPS audit feature is COMPLETE + LAB-VERIFIED. Both deploy and audit are now committed (feature code in 4fcdfa3). 

**Documentation needed for T021:**
- Decryptor GPO configuration step within `-IncludeWinLaps` audit flow (new Test-TierModelWinLapsDecryptor cmdlet, drift detection, GPO registry value validation)
- Audit examples: `-IncludeWinLaps` standalone + FullDeployment modes, opt-in behavior
- Known limitation: Tier 0 Admins cannot decrypt Tier 1/2 PAW passwords (separate ADPasswordEncryptionPrincipal principals required)
- Design decisions: per-tier isolation, root OU ACL placement, decryptorGroup display-name format
- Prerequisites for audit: schema, LAPS module, DFL ≥2016, all 7 LAPS GPOs must exist

**T013 Summary:** 379-check full audit verified live (OU 31, Group 26, User 2, ACL 101, GPO 146, ADMX 60, WinLaps ACL 7, Decryptor 6), 100% compliant, 0 drift. Opt-in via -IncludeWinLaps. Ready for Joel's UAT. T021 docs will add -IncludeWinLaps examples and decryptor audit methodology.

---

### Session 2026-07-16 — T021 Windows LAPS Documentation

Wrote all T021 documentation for the Windows LAPS feature (module v1.2.0):

**Files changed:**
- `README.md` — Updated description, version (1.1.0→1.2.0), test counts (Unit: 17/1,122, Integration: 7/279, Manual: 331, Total: 25/1,732), production files (58→63), coverage (91.6%→90.92%), scripts table (+`-IncludeWinLaps`)
- `docs/detailed-deployment-guide.md` — Added Step 10 (WinLaps standalone + full deployment), prerequisites table, schema hard-stop callout, decryptor note, tier isolation note; updated Component Dependencies
- `docs/deployment-methodology.md` — Added Phase 10 to Deployment Order; updated INFO/WARN messages; added WinLaps rows to Object Validation Matrix; added 8 new function contracts; added WinLaps test files to test file list
- `docs/cmdlet-architecture.md` — Added Phase 10 section with all 5 cmdlets (roles, params, delegation model table, tier isolation note)
- `docs/test-coverage.md` — Updated header/totals (63 files, 90.92%); added 5 WinLaps cmdlets to tier tables, detailed rows, and Public Functions section; updated Coverage Summary table (47 public functions)
- `docs/drift-detection-details.md` — Added `-IncludeWinLaps` to full + scoped audit examples; added LapsPermission and LapsDecryptor to drift interpretation table; added Windows LAPS ACL Delegations component-specific details section; updated Notes
- `docs/test-tag-matrix.md` — Added WinLapsAcl, WinLapsDecryptor component tags; WinLapsPrereq prerequisite tag; added WinLaps test files table
- `docs/faq.md` — Updated version to v1.2.0; updated FullDeployment vs switches answer to mention optional features; added new Windows LAPS FAQ section (8 Q&As)
- `docs/quick-deployment-guide.md` — Added optional features callout box to Step 2

**Test counts used:**
- Unit: 17 files, 1,122 tests (Pester confirmed 2026-07-16)
- Integration: 7 files, 279 tests (Pester confirmed 2026-07-16)
- Manual: 1 file, 331 tests (Joel's xlsx tracker — kept as-is per instructions)
- Total: 25 files, 1,732 tests

## Learnings

- Parameter naming convention: Follow PowerShell PascalCase convention consistently. `-IncludeGmsa` is more readable and maintainable than mixed-case `-IncludeGMSA`.
- Rights model clarity: Explicit statement of the two-ACE pattern (scoped CreateChild/DeleteChild + GenericAll on descendants) prevents implementation ambiguity and supports auditability.
- Edge cases matter: Operational concerns (Protected Users, KDS provisioning) must be documented alongside functional requirements to set correct expectations for operations teams.
- 2026-05-29T10:10:00Z — Spec documentation merged and archived by Scribe. All parameter fixes, edge cases, and rights model clarifications preserved in decisions registry.
- **2025-07-18 — Documentation consistency:** MSA/gMSA/dMSA features marked as "Optional" requiring explicit `-Include*` switches throughout all docs; all 7 documentation files updated in a single coordinated pass; test coverage file marked as "Pending re-measure" to signal to team that measurements will shift when tests are run
- **2026-07-16 — WinLaps documentation:** Windows LAPS feature is Windows LAPS ONLY (never legacy ms-Mcs-AdmPwd*); schema prerequisite is a hard stop (tool never extends schema); decryptor is per-tier (single principal per GPO, CNG-DPAPI enforcement); DC OU has no decryptor (DSRM uses Domain Admins); audit is always OPT-IN via -IncludeWinLaps
- **2026-08-05 — Sentinel monitoring doc:** Lives at `docs/sentinel-monitoring.md`, screenshots at `docs/images/sentinel/` (26 files). Doc principles: never include rule/workbook counts (they change); never duplicate KQL — link to Azure/Azure-Sentinel source; keep doc focused on philosophy, prerequisites, click-through enablement, and links. Recommended install order: install from Content Hub → enable analytic rules (one at a time) → deploy automation rules (ARM template, same region/RG as workspace) → save workbook. The `(TMxxx.1)` tag in rule names links analytic rules, automation rules, and workbook — renaming breaks everything.
- **2026-08-05T11:24:14+08:00 — Exclude screenshots that show rule/workbook counts:** The solution-details "content included" screenshot (`02-solution-details-02.png`) was intentionally removed because it displayed rule/workbook counts that would require re-shooting whenever counts change. Consistent with the no-counts guardrail: if an image would make the doc lie when counts change, don't include it. A screenshot copied from Downloads had a leading space in its filename (` 01-contenthub-search.png`). MkDocs 1.6.x strict mode correctly caught this as a broken image link. The correct fix is to rename the asset (use `-LiteralPath` in PowerShell to handle the space literally). Never add `validation.links.not_found: ignore` to mkdocs.yml to paper over a broken link — that hides real problems. Keep strict link validation ON at all times.