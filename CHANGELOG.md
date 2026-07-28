# Changelog

All notable changes to the TierModel project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **`-UserOnly` output now aligns with `-GroupOnly` (BUG-002)**: running `Deploy-TierModel.ps1 -UserOnly` against a domain without the Tier Model OUs/Groups now shows the same sections as every other scope parameter — `Analyzing User requirements...`, a `User Plan Summary`, and the specific `Dependency Errors:` list (each missing OU/Group) — with the `=== Deployment Plan ===` section showing only the generic "Resolve all dependency errors" line. Previously `-UserOnly` called `Invoke-UserDeployment -Silent`, which hid the summary and the dependency-error listing (only the generic resolve line appeared under an otherwise empty heading). The fix runs `Invoke-UserDeployment` non-Silent like `-GroupOnly`, while suppressing per-user "User exists" noise via `Get-TierModelUser -Silent` for parity with the Group path.
- **Windows LAPS FullDeployment planning no longer shows red "missing GPO" errors (BUG-005)**: during `-FullDeployment ... -IncludeWinLaps` preview (without `-ConfirmApply`) against an unprepared domain, a missing LAPS GPO is now silently non-blocking (the GPO is created by the earlier GPO phase). Instead of red `Required GPO ... does not exist` errors, the plan lists each LAPS GPO that will be configured as a yellow `■ Configure : <gpoName>` action, matching the format of the other planned actions. Only the 6 decryptor-configured GPOs are listed; the DC LAPS GPO retains the DSRM default (Domain Admins) by design and is not decryptor-configured in this phase. The standalone `-IncludeWinLaps` path keeps the strict GPO pre-existence requirement (earlier phases do not run there).
- **Pester version gate loosened to any 5.x, with side-by-side 6.x support (BUG-007)**: CI and `Test-TierModelPrerequisites` previously pinned Pester to the exact reference version (`5.7.1`), which blocked otherwise-valid 5.x releases from running or deploying. The gate now accepts any Pester **5.x** release (major-version match) while still blocking **6.x**, whose breaking changes (new mock engine / `Should-*` assertions) broke 44 test cases.
  - CI installs Pester with `-MinimumVersion 5.0.0 -MaximumVersion 5.99.99`; `config/dependencies.json` keeps `5.7.1` as the tested reference version.
  - `Test-TierModelPrerequisites` now accepts a supported 5.x release even when an unsupported newer major (e.g. 6.x) is installed **side-by-side** — this does not block deployment. It emits a non-blocking note that PowerShell auto-loads the highest version, so the 5.x line must be imported explicitly (`Import-Module Pester -MaximumVersion 5.99.99`). It fails only when no 5.x release is present.
  - `tests/Invoke-AllTests.ps1` now selects and explicitly imports the highest installed Pester 5.x so local/lab test runs use the supported version even when 6.x is installed alongside it.

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