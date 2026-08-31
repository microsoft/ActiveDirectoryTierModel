# Changelog

All notable changes to the TierModel project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.3] - 2026-08-31

### Fixed
- **Domain Admin prerequisite false-fails under the PowerShell 7 Windows PowerShell compatibility shim (issue #47)**: when `Test-TierModelPrerequisites` ran under PowerShell 7 with an RSAT ActiveDirectory module that is not Core-native (for example on a Windows Server 2016 host, or any host whose AD module edition forces the fallback), PowerShell loaded the module through the Windows PowerShell compatibility shim (WinPSCompatSession) and returned **deserialized** objects — SIDs came back as strings, so the `Get-ADGroupMember | Where-Object { $_.SID -eq $currentUser.User }` membership check compared a deserialized SID against a live `SecurityIdentifier` and never matched. The prerequisite reported *"Domain Admin membership required for deployment operations"* even for a genuine Domain Admin. The ActiveDirectory module is now imported with `-SkipEditionCheck` so PowerShell 7 loads it in-process (native objects, no deserialization), and a fail-fast guard detects the compatibility-shim condition (domain SID returned as a string) and stops with clear remediation — preventing a silent broken deployment in which SID resolution would have written empty principals into URA and GPO restricted-groups policy. Lab-validated: full `-FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa -IncludeWinLaps -EnableAuditing` deploy (707 actions, 0 errors, all SIDs resolving) followed by a full audit (418 checks, COMPLIANT, 0 drift).

## [1.3.2] - 2026-08-24

### Added
- **Human-readable deployment duration output (issue #34)**: `Deploy-TierModel.ps1` console duration lines now render in a four-tier format — `<1ms` (sub-millisecond/zero), `Xms` (1–999 ms), `Xs` (1–59 s), `Xm Ys` (60 s+) — instead of raw milliseconds. A multi-minute full deployment now displays e.g. `Duration: 4m 23s`; a single-OU idempotent run displays e.g. `Duration: 350ms`; a zero-duration no-op displays `Duration: <1ms` (never zero). All tiers use `Math.Floor`; the minute tier uses explicit floor-based integer arithmetic to avoid `[int][TimeSpan]::TotalMinutes` banker's rounding.
- **`Format-TierModelDuration` public cmdlet** (`modules/TierModel/public/Format-TierModelDuration.ps1`): the formatting primitive backing the above change. Accepts `[double]$Milliseconds`; unit-testable in isolation.
- **Best Practices, Governance & AD Hardening documentation page (issue #33)**: new `docs/best-practices.md` covering AD tier model governance, hardening recommendations, and operational best practices; added to mkdocs nav and linked from README.

### Changed
- **Canonical ACL overlap remediation now prints a green `REMEDIATED:` status line per OU** instead of a yellow `WARNING`; the overlap detail (DN + principal) is retained in the result's `Warnings` for audit (`Repair-TierModelCanonicalAcl.ps1`).

## [1.3.1] - 2026-08-18

### Fixed
- **OU deployment failure on domains with an inherited Deny ACE above the Tier OUs (issue #41)**: `New-TierModelOu` threw `"This access control list is not in canonical form and therefore cannot be modified"` when disabling security inheritance on a Tier OU promoted the inherited Deny to an explicit copy and wrote it back below existing explicit Allow entries — producing a non-canonical DACL. The fix rewrites OU creation as a **phased flow**: Phase 2 disables inheritance via a DC-pinned `System.DirectoryServices.Protocols` write, then immediately reads the DACL back and checks canonical order. If the DACL is non-canonical (which it is on essentially every disable-inheritance OU under an inherited-Deny condition), the new `Repair-TierModelCanonicalAcl` primitive re-sorts it before Phase 3 (accidental-deletion protection) runs. This verify-and-remediate step is the load-bearing fix — not a backstop. Lab validation: remediation fired on all disable-inheritance OUs under the Deny condition; deployment completed clean with all OUs canonical; zero remediations when no inherited Deny is present.
- **`-FullDeployment` now hard-stops before the Groups phase on any OU error** (previously only inheritance-verification errors triggered the stop).

### Added
- **`Repair-TierModelCanonicalAcl` public cmdlet**: canonical DACL re-sort primitive. Permission-neutral — reorders ACEs into canonical form (explicit Deny → explicit Allow → inherited Deny → inherited Allow) without adding, removing, or modifying any ACE. ACE count before and after is identical. Sort is stable. Supports live DC writes (`-PreferredDc`, `-DistinguishedName`) and offline byte-level sorting (`-SecurityDescriptorBytes`). Also available to operators for manual remediation of a non-canonical domain root or ad-hoc OU repairs.
- **Canonical-ACL audit in `Audit-TierModel.ps1`** (read-only; included in `-OuOnly` and `-FullDeployment`): checks the domain root and each Tier OU for canonical DACL order and surfaces structured drift findings:
  - **Case 1** (`AuditNonCanonicalAclDomainRoot`) — domain root is non-canonical; this is the pre-flight blocker. Operator resolves manually (ADUC Reorder or `Repair-TierModelCanonicalAcl`) before deploying.
  - **Case 2** (`AuditNonCanonicalAclTierOu`) — a Tier OU is non-canonical; indicates a failed or pre-fix deployment. Operator deletes the OU and redeploys.
- **Deploy INFO line**: `Deploy-TierModel.ps1` now reports a non-interrupting summary at the end of the OU-creation phase: `Canonical remediation: N OU DACL(s) auto-corrected during disable-inheritance.` (`N = 0` when no inherited Deny is present; `N > 0` — typically equal to the number of disable-inheritance OUs — when one is present).
- **`-SkipRootCanonicalCheck` switch on `Test-TierModelPrerequisites`**: lets `Audit-TierModel.ps1` report a non-canonical domain root as a Case 1 audit finding instead of halting. `Deploy-TierModel.ps1` does not pass this switch, so the domain-root pre-flight gate remains fatal for deployments.

### Changed
- Module version 1.3.0 → **1.3.1** (+1 exported cmdlet: `Repair-TierModelCanonicalAcl`).

### Tests
- New `tests/Unit.CanonicalAclRepair.Tests.ps1` (`Repair-TierModelCanonicalAcl` — ByBytes offline: return shape, all-four-rank sort, CommonAce-before-ObjectAce sub-order, already-canonical, multiset-preservation, stability, idempotency, Deny/Allow overlap warning, DistinguishedName passthrough, multiple-violation, roundtrip; ByServer mocked offline) and `tests/Unit.CanonicalAclAudit.Tests.ps1` (`Invoke-CanonicalAclAudit` — Case 1, Case 2, all-canonical, mix/error/exception/skip paths, return shape). Additions to `tests/Unit.Prerequisites.Tests.ps1` (+5: `-SkipRootCanonicalCheck` gate), `tests/Unit.OuOperations.Tests.ps1` (Phase 2 verify-and-remediate path), and `tests/Integration.Deploy.Tests.ps1` (canonical-remediation INFO line, N=0/N>0 scenarios). Full suite: **1,627 automated tests passing** under Pester 5.x; aggregate command coverage **≈89%** (`Repair-TierModelCanonicalAcl.ps1` 95.4%, `New-TierModelOu.ps1` 84.9%; live-LDAP ByServer paths exempt per existing team precedent).

## [1.3.0] - 2026-08-17

### Added
- **`-EnableAuditing` deployment parameter** on `Deploy-TierModel.ps1` (issue #38). Configures an Active Directory **domain-root object-auditing SACL** (trustee Everyone/S-1-1-0, Success, All-inheritance, 9 rights) that feeds the Microsoft Sentinel Tier Model monitoring solution. Runs standalone (`Deploy-TierModel.ps1 -EnableAuditing -ConfirmApply`) or with `-FullDeployment -EnableAuditing`. Mutually exclusive with the `-*Only` switches. Requires `SeSecurityPrivilege`.
- Four new module cmdlets (exported from TierModel 1.3.0): `Get-TierModelAuditRule` (planner), `New-TierModelAuditRule` (applier, idempotent UNION-converge — preserves out-of-scope ACEs), `Test-TierModelAuditRule` (drift detection with granular per-right PASS/FAIL), `Get-TierModelAuditRuleFd` (FullDeployment wrapper).
- New config `config/tiermodel-audit.json` (domain-root audit rule) + `domainAuditRule` schema segment in `config/tiermodel.schema.json`.
- **Second confirmation gate:** when `-EnableAuditing` is combined with `-ConfirmApply`, an auditing-impact warning + 'Y' prompt is shown FIRST (event-log volume acknowledgement), then the standard deployment 'Y'.
- `-EnableAuditing` support in `Audit-TierModel.ps1` (mirrors the deployment scope) with granular per-right ✅/❌ output aligned to the GPO URA validation model.
- Documentation: new "Step 11: Configure Domain-Root Auditing" in the Detailed Deployment Guide; Sentinel Monitoring guide updated to document the two-part requirement (the `-EnableAuditing` SACL AND the default-linked `*- Tier 0 DCs Advanced Audit Policy - Computer` GPO).

### Changed
- Module version 1.2.3 → **1.3.0** (+4 exported cmdlets).
- Test runner `tests/Invoke-AllTests.ps1` now hard-pins execution to Pester 5.x and blocks Pester 6.x from binding (6.x has breaking changes not yet supported).

### Removed
- Deleted the legacy standalone `optional/Enable-TierModelAuditing.ps1` — its functionality is now built into `Deploy-TierModel.ps1 -EnableAuditing`.

### Tests
- New `tests/Unit.AuditRuleOperations.Tests.ps1` (47 unit tests) plus `-EnableAuditing` integration coverage in the Audit and Deploy suites. Full suite: **1,533 automated tests passing** under Pester 5.x; overall command coverage **89.65%** (new audit cmdlets 84–100%; `Audit-TierModel.ps1` 85.9%, `Deploy-TierModel.ps1` 81.53%).

## [1.2.3] - 2026-08-12

### Added
- **Non-canonical root ACL pre-flight check** (`Test-TierModelCanonicalAcl`) and a `Test-TierModelPrerequisites` gate that hard-stop Deploy and Audit (all modes, zero objects) with a friendly message when the domain root DACL is not in canonical form. Detect-only — never rewrites ACLs.
- **New documentation page:** Canonical ACLs (`docs/canonical-acl.md`) — explains the condition, the ADUC Reorder fix, effective-permission impact, DC backup guidance, and when to open a Microsoft support case.

### Changed
- The non-blocking Pester 6.x side-by-side advisory now records to `EnvironmentSnapshot.PesterAdvisory` instead of `Remediation`, so it no longer appears in unrelated Deploy/Audit fail-fast output.

### Tests
- Added 26 unit tests (`Unit.CanonicalAcl.Tests.ps1` + canonical-ACL gate tests in `Unit.Prerequisites.Tests.ps1`). Full suite: 1,461 automated tests passing under Pester 5.x; docs-scope coverage 88.74%.

## [1.2.2] - 2026-07-31

### Added
- **English-language enforcement (#23)**: `Test-TierModelPrerequisites` now fails fast — before any deployment or audit change — when the environment is not English (`en-US`). Two unconditional checks run up front and are inherited by both `Deploy-TierModel.ps1` and `Audit-TierModel.ps1`:
  - **Host operating system** — reads the local machine's static `InstallLanguage` LCID (`HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language`) and requires an English variant (primary language `0x09`, e.g. en-US/en-GB). Runs after the elevation check and **before** the Pester/module checks, and returns immediately on a non-English host so the operator is never asked to install modules on an unsupported OS.
  - **Active Directory** — resolves three well-known groups by SID (Domain Admins `<DomainSID>-512`, Server Operators `S-1-5-32-549`, Account Operators `S-1-5-32-548`) and requires each directory `Name` to be its English value. Child-domain safe (no Enterprise/Schema Admins); names are read from AD (never client-side SID translation, which the local OS would localize into a false pass). A confirmed localized name always fails closed even if another well-known group cannot be resolved.
  - Both checks emit friendly `Errors`/`Remediation` and record diagnostics in `EnvironmentSnapshot` (`HostInstallLanguage`, `HostOsEnglish`, `AdLanguageEnglish`, `AdLanguageMismatches`, …).
- **Documentation**: new `docs/language-support.md` documenting the English-only requirement, the 18 fully-localized Windows Server languages that are detected and stopped, and a future community-localization roadmap. Prerequisite notes added to the README, the quick/detailed deployment guides, and the FAQ.

### Notes
- No configuration changes are required and English (`en-US`) deployments and audits are unaffected (full suite: **1,435** automated tests passing; module scope ~91% coverage). Non-English environments are a documented, unsupported scenario — see `docs/language-support.md`.

## [1.2.1] - 2026-07-30

### Fixed
- **OU and GPO ACLs now bind to the preferred DC (BUG-001)**: `New-TierModelOuAcl` bound to the target OU with a serverless path (`[ADSI]"LDAP://$targetOUPath"`), which connects to a random DC — in multi-DC environments successive ACL delegations could land on different DCs, causing replication-dependent inconsistency. It now binds via `"LDAP://$DomainController/$targetOUPath"` (the `-PreferredDc` passed through the pipeline), matching the MSA/gMSA/dMSA ACL cmdlets. The same serverless-bind pattern in `New-TierModelGpo` (the GPO Deny-Apply ACL / GPC bind) was fixed to `"LDAP://$DomainController/CN={...}"` so every ACL — OU and GPO — targets the same DC.
- **`-UserOnly` output now aligns with `-GroupOnly` (BUG-002)**: running `Deploy-TierModel.ps1 -UserOnly` against a domain without the Tier Model OUs/Groups now shows the same sections as every other scope parameter — `Analyzing User requirements...`, a `User Plan Summary`, and the specific `Dependency Errors:` list (each missing OU/Group) — with the `=== Deployment Plan ===` section showing only the generic "Resolve all dependency errors" line. Previously `-UserOnly` called `Invoke-UserDeployment -Silent`, which hid the summary and the dependency-error listing (only the generic resolve line appeared under an otherwise empty heading). The fix runs `Invoke-UserDeployment` non-Silent like `-GroupOnly`, while suppressing per-user "User exists" noise via `Get-TierModelUser -Silent` for parity with the Group path.
- **Windows LAPS FullDeployment planning no longer shows red "missing GPO" errors (BUG-005)**: during `-FullDeployment ... -IncludeWinLaps` preview (without `-ConfirmApply`) against an unprepared domain, a missing LAPS GPO is now silently non-blocking (the GPO is created by the earlier GPO phase). Instead of red `Required GPO ... does not exist` errors, the plan lists each LAPS GPO that will be configured as a yellow `■ Configure : <gpoName>` action, matching the format of the other planned actions. Only the 6 decryptor-configured GPOs are listed; the DC LAPS GPO retains the DSRM default (Domain Admins) by design and is not decryptor-configured in this phase. The FD planner's group resolution was also fixed so that, against an unprepared domain (where `Get-ADGroup -Filter` returns no match without throwing), the `Create ACL` principals and the decryptor `Configure` actions render with best-effort estimated names instead of being blank/omitted (resolved for real at apply time). The standalone `-IncludeWinLaps` path keeps the strict GPO pre-existence requirement (earlier phases do not run there).
- **Pester version gate loosened to any 5.x, with side-by-side 6.x support (BUG-007)**: CI and `Test-TierModelPrerequisites` previously pinned Pester to the exact reference version (`5.7.1`), which blocked otherwise-valid 5.x releases from running or deploying. The gate now accepts any Pester **5.x** release (major-version match) while still blocking **6.x**, whose breaking changes (new mock engine / `Should-*` assertions) broke 44 test cases.
  - CI installs Pester with `-MinimumVersion 5.0.0 -MaximumVersion 5.99.99`; `config/dependencies.json` keeps `5.7.1` as the tested reference version.
  - `Test-TierModelPrerequisites` now accepts a supported 5.x release even when an unsupported newer major (e.g. 6.x) is installed **side-by-side** — this does not block deployment. It emits a non-blocking note that PowerShell auto-loads the highest version, so the 5.x line must be imported explicitly (`Import-Module Pester -MaximumVersion 5.99.99`). It fails only when no 5.x release is present.
  - `tests/Invoke-AllTests.ps1` now selects and explicitly imports the highest installed Pester 5.x so local/lab test runs use the supported version even when 6.x is installed alongside it.
- **dMSA/gMSA/Windows LAPS prerequisites now fail fast, before any deployment phase (BUG-003)**: previously `-FullDeployment -IncludeDmsa` on a domain below Domain Functional Level 2025 ran the entire standard deployment and only surfaced the dMSA requirement as a confusing `attribute 'msDS-DelegatedManagedServiceAccount' not found in schema` planner error at Phase 9. A dMSA DFL critical pre-flight gate now fails fast with a clean message right after module load, and the `-Include*` switches are routed through the up-front `Test-TierModelPrerequisites` call so gMSA (KDS root key), Windows LAPS (schema), and dMSA prerequisites all block before any phase in both `-FullDeployment` and standalone modes. The dMSA DFL message is friendly (no redundant schema-version error), and the DFL-only check is confirmed correct for the single-domain Tier Model (Forest FL 2025 is required only for cross-domain/cross-forest dMSA, which the Tier Model never performs).
- **Windows LAPS audit now detects unexpected (extra) LAPS delegations (BUG-004)**: `Test-TierModelWinLapsAcl` documented an `UnexpectedAcl` finding but never emitted one — it only verified that the configured Read/Reset principals were present, never that extra principals were absent. It now flags any LAPS extended-right holder that is not a configured Read/Reset group and not a well-known/admin principal as `UnexpectedAcl` (yellow ⚠️, counted as drift), mirroring the MSA/gMSA/dMSA audits.
- **`-Include*` prerequisite checks resolve `config/dependencies.json` from any working directory (BUG-008)**: the `$prereqSplat` hashtables for the MSA/gMSA/dMSA/WinLaps prerequisite checks omitted `DependenciesPath`, so `Test-TierModelPrerequisites` fell back to its cwd-relative default and failed with "Dependencies file not found" when the script was launched by absolute path from a different directory. Both splats now pass an absolute `$PSScriptRoot`-based `DependenciesPath`, matching the primary prerequisite call.
- **Consistent fail-fast prerequisite messages across Deploy and Audit**: a shared `Write-TierModelFailFast` helper renders every up-front gate (PowerShell version, dMSA DFL, and the general prerequisite failure) identically — indented message with no `Prerequisites not met:` header and no `ERROR:` prefix, a blank-line-separated `Remediation steps:` block, and the closing `Deploy script completed.` / `Audit script completed.` line. Duplicated resolution text was removed from the Windows LAPS schema errors, every previously-bare dMSA prerequisite error gained a remediation step, and `Audit-TierModel.ps1` gained a matching PowerShell-version gate.
- **OU "Block GPO Inheritance" is now verified and retried during deployment (BUG-010)**: creating an OU with `blockGpoInheritance` (or `disableInheritance`) previously called `Set-GPInheritance -IsBlocked Yes` (or `Set-Acl` protection) once and reported success as long as the call did not throw — but the change intermittently did not persist (a silent no-op, ~10% per OU on a fast run), leaving a tier boundary unblocked while the deployment still reported success. `New-TierModelOu` now reads back `Get-GPInheritance` (and the ACL's `AreAccessRulesProtected`) on the same DC and retries up to 4 times with backoff until the setting is verified; if it still cannot be confirmed it records a human-readable error ("Block GPO Inheritance flag was not set for OU 'X'…") instead of a false success. In `-FullDeployment`, an unverified OU inheritance setting hard-stops the run before the Groups phase so a tier boundary is never silently left open. The logic remains create-only — existing/live OUs are never modified (remediate drift via change control and confirm with the audit script).
- **Windows LAPS audit no longer false-flags tier admins that hold OU full control (BUG-009)**: `Test-TierModelWinLapsAcl`'s `UnexpectedAcl` detection (added in BUG-004) uses `Find-LapsADExtendedRights`, which resolves a principal's *effective* LAPS read — including access granted implicitly by `GenericAll` (full control). Because the Tier Model's own OU-management delegation grants tier admin groups (e.g. `Tier0Admins`/`Tier1Admins`) `GenericAll` on their Member-Server OUs, every audit flagged them as unexpected LAPS readers even though they hold no *explicit* ms-LAPS delegation. The audit now collects the OU's `GenericAll` (Allow) holders from the same DACL it already reads for SELF detection and excludes them from the unexpected-holder check, so a genuinely unexpected *explicit* LAPS reader is still flagged while `GenericAll`-derived effective access is not. Full-control drift remains covered separately by the OU ACL audit. (Lab-validated: the two recurring `Tier0Admins`/`Tier1Admins` warnings are gone and an injected explicit LAPS holder is still detected.)
- **Clean deployment no longer reports phantom "Skipped" items (BUG-011)**: a brand-new `-FullDeployment … -ConfirmApply` reported `Skipped: 4` despite creating everything with zero real skips. The User and OuAcl result objects built their `Applied`/`Skipped` arrays with `@(1..$executionResult.Skipped | ForEach-Object {…})`; when the count is `0`, PowerShell's `1..0` is a **descending** range (`{1, 0}`, two elements), so each of those two phases emitted 2 phantom "Skipped" entries → `Skipped: 4`. All four `1..$n` ranges (the User and OuAcl `Applied` and `Skipped` builders) are now guarded with `if ($n -gt 0)` so a zero count yields an empty array; real applied/skipped counts are unchanged.

## [1.2.0] - 2026-07-17

### Added

#### Windows LAPS Support
- **Windows LAPS ACL Cmdlets**: `Get-TierModelWinLapsAcl`, `Get-TierModelWinLapsAclFd`, `New-TierModelWinLapsAcl`, and `Test-TierModelWinLapsAcl` for deploying and auditing Windows LAPS DACL delegations (Self / Read / Reset permissions per target OU)
- **Windows LAPS Decryptor Audit**: `Test-TierModelWinLapsDecryptor` verifies the `ADPasswordEncryptionPrincipal` GPO registry policy on each non-DC LAPS GPO
- **`-IncludeWinLaps` switch**: added to `Deploy-TierModel.ps1` (standalone and full-deployment Phase 10, after MSA/gMSA/dMSA) and `Audit-TierModel.ps1` (opt-in ACL + decryptor drift detection)
- **Configuration**: `config/tiermodel-winlaps.json` defining 7 LAPS ACL delegations plus per-OU decryptor group mapping
- **GPO Decryptor Configuration**: deployment configures the authorized password decryptor (`ADPasswordEncryptionPrincipal`) on the 6 non-DC LAPS GPOs so the correct tier group can decrypt managed passwords (Domain Controllers retain the DSRM default of Domain Admins)
- **Prerequisite Validation**: extended `Test-TierModelPrerequisites` with the Windows LAPS schema hard-stop and the OU / group / LAPS-GPO dependency checks
- **Windows LAPS only**: uses `ms-LAPS-*` attributes exclusively — never legacy Microsoft LAPS (`ms-Mcs-AdmPwd*` / `AdmPwd.PS`)

### Changed
- Removed the superseded manual `optional/Deploy-WindowsLaps.ps1` (functionality replaced by `Deploy-TierModel.ps1 -IncludeWinLaps`)

### Tests
- Added `tests/Unit.WinLapsAclOperations.Tests.ps1` and `tests/Integration.WinLapsDeployment.Tests.ps1` (113 new tests) and extended prerequisite/manifest tests; added AD/GPO/LAPS stubs so the suite runs in CI without a domain controller
- Full suite: 1,401 automated tests passing; 90.92% module code coverage

### Documentation
- Documented `-IncludeWinLaps` across `README.md` and `docs/` (detailed deployment guide, deployment methodology, cmdlet architecture, drift detection, FAQ, test coverage, test tag matrix), matching the existing MSA/gMSA/dMSA "Optional Feature" pattern

## [1.1.0] - 2026-06-30

### Added

#### Managed Service Account (MSA/gMSA/dMSA) ACL Support
- **gMSA ACL Cmdlets**: `Get-TierModelGmsaAcl`, `Get-TierModelGmsaAclFd`, `New-TierModelGmsaAcl`, and `Test-TierModelGmsaAcl` for deploying and auditing Group Managed Service Account ACLs
- **dMSA ACL Cmdlets**: `Get-TierModelDmsaAcl`, `Get-TierModelDmsaAclFd`, `New-TierModelDmsaAcl`, and `Test-TierModelDmsaAcl` for Delegated Managed Service Account ACLs
- **MSA ACL Cmdlets**: `Get-TierModelMsaAcl`, `Get-TierModelMsaAclFd`, `New-TierModelMsaAcl`, and `Test-TierModelMsaAcl` for standalone Managed Service Account ACLs
- **Configuration**: `config/tiermodel-gmsa.json`, `config/tiermodel-dmsa.json`, and `config/tiermodel-msa.json` for MSA tier model ACL definitions
- **Prerequisite Validation**: Extended `Test-TierModelPrerequisites` with MSA-related checks
- **Domain GUID Resolution**: Enhanced `Resolve-DomainSpecificGuid` to support MSA schema/extended-rights GUIDs

### Tests
- Added unit test suites for MSA, gMSA, and dMSA ACL operations and updated prerequisite/manifest tests
- Added integration tests for MSA deploy and audit workflows

## [1.0.0] - 2026-02-27

### Added

#### Deployment & Audit Scripts
- **Deploy-TierModel.ps1**: Modular deployment script with component-specific switches (-OuOnly, -GroupOnly, -UserOnly, -GposOnly, -OuAclsOnly, -AdmxOnly, -FullDeployment)
- **Audit-TierModel.ps1**: Comprehensive drift detection and compliance auditing with multiple output formats (Text, Json, Html, NUnitXml)
- **Component-Specific Cmdlets**: Dedicated Test-TierModel* cmdlets for each component type (Ou, Group, User, OuAcl, Gpo, Admx)
- **Scoped Operations**: Run deployments and audits for specific components or full deployment with consolidated reporting

#### Structured Logging System
- **Write-TierModelLog**: Structured logging with correlation ID tracking, security redaction, and JSON output
- **Deployment Logging**: Optional logging via -Logging switch in Deploy-TierModel.ps1
- **Security Redaction**: Automatic redaction of passwords, secrets, tokens, and credentials in log output
- **Correlation Tracking**: Track related operations across multiple function calls with unique correlation IDs

#### Prerequisite Validation
- **Comprehensive Checks**: PowerShell version (5.1, 7.0+), admin elevation, Domain Admin membership, DC reachability
- **Dependency Management**: Automated module dependency checking with structured remediation guidance
- **Integration**: Built into Deploy-TierModel.ps1 and Audit-TierModel.ps1 scripts

#### Drift Detection & Compliance
- **Multi-Resource Detection**: OUs, Groups, Users, GPOs, ACLs, and ADMX templates
- **Finding Types**: Missing resources, configuration mismatches, extra protections, hash mismatches
- **Multiple Report Formats**: Text, JSON, HTML, and NUnit XML for CI/CD integration
- **Severity Classification**: High, Medium, Low priority for remediation planning

#### GPO Management
- **Flexible Configuration**: ImportOnlyGpo (baseline templates) and PostConfigureGpo (with User Rights and Restricted Groups)
- **Three Deployment Modes**: create (placeholder), createAndImport (from backup), createImportAndConfigure (full settings)
- **Security Filtering**: denyApplyGroupPolicy support for Domain Controllers and Read-only Domain Controllers
- **Principals Management**: Resolvable groups, forest-root principals, conditional groups, and literal SID strings
- **Hash Verification**: MD5 hash validation for ADMX template integrity

#### Documentation
- **Quick Deployment Guide**: Fast-track instructions for experienced administrators
- **Detailed Deployment Guide**: Step-by-step walkthrough for comprehensive deployments
- **Drift Detection Details**: Complete guide to auditing and compliance checking
- **Cmdlet Architecture**: Documentation of modular design for testability and maintainability
- **GPO Management Strategy**: Group Policy configuration and deployment patterns
- **Test Tag Matrix**: Comprehensive test organization and execution strategies
- **Conditional Principals**: Managing dynamic group resolution and forest-specific principals

### Enhanced Features

#### Configuration Management
- **Segmented JSON Structure**: Separate files for OUs, Groups, Users, GPOs, ACLs, ADMX, metadata
- **JSON Schema Validation**: tiermodel.schema.json for configuration validation
- **Hash Verification**: Configuration provenance with Get-TierModelConfigHash
- **GUID Mappings**: Centralized GUID resolution for ACL and GPO rights

#### Testing Framework
- **19 Test Files**: Unit and integration tests covering all components
- **Comprehensive Tags**: 60+ Pester tags for granular test execution
- **Component Coverage**: Dedicated tests for OUs, Groups, Users, GPOs, Links, ACLs, ADMX, Resolution, Logging
- **Test Scripts**: Invoke-AllTests.ps1 and Invoke-PrerequisiteTests.ps1 for test execution

#### CI/CD Pipelines
- **GitHub Actions**: Multi-stage workflow with linting, testing (PS 5.1 & 7.4), security analysis, packaging
- **Azure DevOps**: Comprehensive pipeline with test matrix, code coverage, and artifact publishing
- **Security Scanning**: PSScriptAnalyzer integration with fail-on-critical-issues
- **Scheduled Drift Detection**: Daily automated compliance monitoring

### Technical Improvements

#### Module Architecture
- **Cmdlet Separation**: Dedicated *Fd variants for full deployment validation logic
- **Modular Design**: Test-TierModel* cmdlets for individual component validation
- **WhatIf Support**: ShouldProcess implementation across all state-changing operations
- **Error Handling**: Structured error reporting with remediation guidance

#### Code Quality
- **PSScriptAnalyzer**: Comprehensive linting with security rule enforcement
- **Pester 5.x**: Modern test framework with code coverage reporting
- **Multi-Platform**: PowerShell 5.1 and 7.x compatibility
- **Security Analysis**: Automated credential and PII detection

### Breaking Changes

#### Configuration Format
- **Segmented Structure**: Migration from single-file to multi-file JSON configuration
  - Previous: Single monolithic JSON file
  - Current: Separate files for each component type in config/ directory
- **GPO Structure**: Changed from flat gpos array to per-OU ImportOnlyGpo/PostConfigureGpo structure
- **Schema Requirement**: All configurations must validate against tiermodel.schema.json

#### Function Changes
- Removed `Test-TierModelDrift` function - use `Audit-TierModel.ps1` script instead
- Renamed test cmdlets from Test-TierModel* to component-specific variants
- Updated logging function signatures (backward compatible via defaults)

#### Deployment Process
- Enhanced prerequisite validation may block deployments that previously succeeded
- Configuration file location changed to config/ directory structure
- ADMX deployment now config-driven (no external path parameters)

### Security Enhancements
- Automatic credential redaction in all log output
- Security rule enforcement in CI pipelines
- GPO rights delegation with least-privilege patterns
- Fail-fast validation for security-critical prerequisites
- MD5 hash verification for template integrity

### Fixed
- Corrected GPO JSON structure documentation (ImportOnlyGpo/PostConfigureGpo)
- Fixed restrictedGroups structure (emptyGroups and membershipGroups arrays)
- Corrected principals object structure with proper array types
- Updated all documentation to reflect actual implementation
- Removed outdated GPO permissions validation documentation

### Removed
- Legacy single-file configuration support (use migration guide)
- Example functions that were never implemented
- Confusing documentation references
- Outdated cmdlet references in CI/CD pipelines

---

**For detailed implementation specifications, see the documentation in `docs/`.**