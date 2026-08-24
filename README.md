# 🏛️ Tier Model

Declarative PowerShell framework to deploy and audit an Active Directory Tier Model (OUs, Groups, Users, ACL Delegations, GPOs, ADMX, MSA/gMSA/dMSA Permissions, Windows LAPS Permissions) from a single version-controlled JSON configuration file. Supports idempotent re-runs, drift detection, and reproducible builds via pinned dependency versions.

> 🏗️ **Built with the Specify Framework** - Test-driven development ensuring quality and reliability

## 🎯 Goals
- 🔒 Safe, repeatable deployments (WhatIf planning + convergent apply)
- 📊 Drift auditing & reporting (hash provenance + structured findings)
- 🧩 Modular, test-first architecture (Pester enforced)
- 📦 Version governance for dependencies & configuration schema

## 📚 Documentation

> 📖 **Full documentation**: [GitHub Pages - Active Directory Tier Model](https://microsoft.github.io/ActiveDirectoryTierModel)

To get started with TierModel, please refer to our comprehensive documentation:

### 🚀 Getting Started
- **[Quick Deployment Guide](https://microsoft.github.io/ActiveDirectoryTierModel/quick-deployment-guide/)** - Fast-track deployment for experienced administrators
- **[Detailed Deployment Guide](https://microsoft.github.io/ActiveDirectoryTierModel/detailed-deployment-guide/)** - Step-by-step deployment with explanations
- **[FAQ](https://microsoft.github.io/ActiveDirectoryTierModel/faq/)** - Frequently asked questions covering upgrades, migration from previous versions, troubleshooting, and Sentinel integration

### 📖 Core Documentation
- **[Deployment Methodology](https://microsoft.github.io/ActiveDirectoryTierModel/deployment-methodology/)** - Understanding the deployment approach
- **[Drift Detection Details](https://microsoft.github.io/ActiveDirectoryTierModel/drift-detection-details/)** - Comprehensive drift auditing and remediation
- **[Tier Model Logging](https://microsoft.github.io/ActiveDirectoryTierModel/tiermodel-logging/)** - Structured logging and diagnostics
- **[GPO Management Strategy](https://microsoft.github.io/ActiveDirectoryTierModel/gpo-management-strategy/)** - Group Policy Object management
- **[GPO Management Guidance](https://microsoft.github.io/ActiveDirectoryTierModel/gpo-management-guidance/)** - Best practices, baseline selection, the SOE override model, firewall lockdown, and upgrade lifecycle
- **[Best Practices & Hardening](https://microsoft.github.io/ActiveDirectoryTierModel/best-practices/)** - Governance rules (group manager tiering) and post-deployment AD hardening guidance
- **[ADMX Management](https://microsoft.github.io/ActiveDirectoryTierModel/admx-management/)** - Administrative template handling
- **[Conditional Principals](https://microsoft.github.io/ActiveDirectoryTierModel/conditional-principals/)** - Domain-specific principal resolution
- **[CI/CD Integration](https://microsoft.github.io/ActiveDirectoryTierModel/ci-cd/)** - Pipeline integration and automation
- **[Test Tag Matrix](https://microsoft.github.io/ActiveDirectoryTierModel/test-tag-matrix/)** - Pester test organization
- **[Test Coverage](https://microsoft.github.io/ActiveDirectoryTierModel/test-coverage/)** - Comprehensive test coverage analysis and roadmap
- **[Language Support](https://microsoft.github.io/ActiveDirectoryTierModel/language-support/)** - Supported languages (English only today) and the localization roadmap
- **[Sentinel Monitoring](https://microsoft.github.io/ActiveDirectoryTierModel/sentinel-monitoring/)** - Out-of-the-box Microsoft Sentinel monitoring for a deployed Tier Model (Content Hub solution)

### 🔧 Technical Specifications
- **[Feature Specification](specs/001-tier-model-module/spec.md)** - Complete requirements and user stories
- **[Implementation Plan](specs/001-tier-model-module/plan.md)** - Technical architecture and design decisions

## 🧪 Testing & Quality Assurance

**Current Test Status: ✅ 1,652 passing / 0 failures (100%)** *(Last run: 2026-08-24)*

| Test Suite | Test Files | Test Cases | Status | Coverage |
|------------|-----------|------------|--------|----------|
| **Unit Tests** | 22 files | 1,338 tests | ✅ All pass | **88.93%** |
| **Integration Tests** | 7 files | 314 tests | ✅ All pass | **88.93%** |
| **Manual Integration Tests** | 1 file | 335 tests | ✅ 100% Pass | **N/A** |
| **Total** | **29 files** | **1,987 tests** | ✅ **100% passing** | **88.93%** |

### Test Coverage Highlights
- ✅ **71/71** production files have comprehensive test coverage
- ✅ **1,652 / 1,652** automated test cases passing — 0 failures (Pester 5.9.0, 2026-08-24)
- ✅ **88.93%** overall Pester-measured command coverage (all files above 80% CI gate)
- ✅ **New canonical-ACL resilience (#41):** OU deploy uses a phased verify-and-remediate loop — after each disable-inheritance write, `New-TierModelOu` reads back the DACL and auto-sorts if non-canonical (via `Repair-TierModelCanonicalAcl`); lab-validated at 7/7 OUs corrected per deploy under an inherited-Deny condition. New public cmdlet `Repair-TierModelCanonicalAcl` (**95.40%** coverage) available for standalone use. `Audit-TierModel.ps1` now reports Case 1 (non-canonical domain root, deployment blocker) and Case 2 (non-canonical Tier OU, pre-fix artifact) as structured drift findings.
- ✅ **New in v1.3.0:** `-EnableAuditing` domain audit rule (SACL) support — 4 new cmdlets (`Get-TierModelAuditRule` **100%**, `Get-TierModelAuditRuleFd` **97.73%**, `Test-TierModelAuditRule` **98.41%**, `New-TierModelAuditRule` **84.14%**) covered by `Unit.AuditRuleOperations.Tests.ps1` (47 unit tests) plus `-EnableAuditing` integration tests in Audit and Deploy orchestrators; `Audit-TierModel.ps1` **77.16%**, `Deploy-TierModel.ps1` **81.53%**
- ✅ Mock-based testing (no Active Directory connectivity required)

### Running Tests
```powershell
# Run all tests
.\tests\Invoke-AllTests.ps1

# Run unit tests only
.\tests\Invoke-AllTests.ps1 -TestType Unit

# Run integration tests only
.\tests\Invoke-AllTests.ps1 -TestType Integration

# Show only failures (useful for large test runs)
.\tests\Invoke-AllTests.ps1 -FailedOnly

# Run with detailed output
.\tests\Invoke-AllTests.ps1 -Detailed
```

### Deployment Scripts
| Script | Purpose | Optional Features |
|--------|---------|-------------------|
| `Deploy-TierModel.ps1` | 🚀 Deploy with scoped execution | `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` (Managed Service Account ACL delegation), `-IncludeWinLaps` (Windows LAPS ACL delegation + GPO decryptor) |
| `Audit-TierModel.ps1` | 📊 Audit and compliance checking | `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` (Managed Service Account ACL audit), `-IncludeWinLaps` (Windows LAPS ACL + decryptor audit) |

## 🤝 Contributing

Contributions are welcome — but this is a **security-sensitive** project, so we follow an
**issue-first** process. Please read **[CONTRIBUTING.md](CONTRIBUTING.md)** before opening a
pull request.

**The process, in short:**

1. 🗣️ **Open an issue first** describing the problem or proposal — for *any* change (feature, fix, refactor, config, or docs).
2. 🧭 **Discuss and get maintainer agreement** on scope and approach **before writing code**.
3. 🔀 **Then open a focused PR** that links the agreed issue and implements only what was agreed.

> ⚠️ **Pull requests without a linked, pre-agreed issue will be closed.** Unsolicited new
> parameters, alternate deployment topologies, relaxed security validation, or
> bundled / reformat-heavy changes are rejected on sight — not to be unwelcoming, but
> because unreviewed changes to a tiering-security tool can silently weaken tier
> boundaries. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the full rationale.

When your PR is ready, it must also satisfy:

1. ✅ **All Pester tests pass** — the CI pipeline will reject any PR with failing tests
2. 🧪 **New or updated tests are included** — any new code or bug fix must include corresponding test cases to maintain or improve code coverage
3. 📊 **Code coverage stays at or above 80%** — the CI enforces a minimum coverage threshold; if your changes reduce coverage below 80%, add tests until coverage is restored
4. 📝 Documentation is updated for any new or changed functionality
5. 🎯 Code follows project conventions and keeps the diff focused (no unrelated reformatting)

> **Note:** The packaging step will not produce a release artifact unless all tests pass and coverage meets the minimum threshold.

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

### Development Setup
```powershell
# Clone repository
git clone https://github.com/microsoft/ActiveDirectoryTierModel.git
cd ActiveDirectoryTierModel

# Run tests locally before submitting a PR
.\tests\Invoke-AllTests.ps1
```

## 📋 Prerequisites

- **PowerShell**: 7.0+
- **Elevation**: Administrator privileges required
- **Domain Admin**: Membership in Domain Admins group
- **Modules**: ActiveDirectory, GroupPolicy (see `config/dependencies.json`)
- **Language**: English (`en-US`) only — both the **host OS** (the machine you run the scripts from) and **Active Directory** must be English (see [Language Support](https://microsoft.github.io/ActiveDirectoryTierModel/language-support/))

*For detailed prerequisite validation, run `Test-TierModelPrerequisites`*

## 📊 Monitoring

Out-of-the-box Microsoft Sentinel monitoring for a deployed Tier Model is available as a solution in the **Azure Content Hub**. The solution covers Tier Model–specific detection and triage — no custom playbooks or watchlists required. The only hard requirement is that every Domain Controller's Security event logs must be flowing into the Sentinel workspace; any DC not onboarded is a blind spot.

- 📖 [Sentinel Monitoring Guide](https://microsoft.github.io/ActiveDirectoryTierModel/sentinel-monitoring/)
- 🔗 [Content Hub solution source (Azure/Azure-Sentinel)](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Microsoft%20Active%20Directory%20Tier%20Model)

## 🔗 Additional Resources

- ❓ [Frequently Asked Questions (FAQ)](https://microsoft.github.io/ActiveDirectoryTierModel/faq/)
- 📦 [Dependencies Configuration](config/dependencies.json)
- 🗂️ [Configuration Schema](config/tiermodel.schema.json)
- 📜 [Changelog](CHANGELOG.md)

---

**Version**: 1.2.3 | **License**: MIT | **Status**: ✅ Production Ready

## 🚀 Releasing

This project uses **semantic versioning** (`MAJOR.MINOR.PATCH`) and tag-based releases.

| Bump | When | Example |
|------|------|---------|
| `PATCH` (1.0.**1**) | Bug fix, typo, doc correction | Fix broken ACL rule |
| `MINOR` (1.**1**.0) | New feature, backward-compatible | Add WinLAPS parameter |
| `MAJOR` (**2**.0.0) | Breaking change | Restructure config schema |

### Creating a release

1. Ensure all changes are merged to `main` and CI is green
2. Tag the release:
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```
3. The CI pipeline will automatically:
   - Run all tests and enforce code coverage (80% minimum)
   - Create a `TierModel-1.1.0.zip` release asset
   - Publish a GitHub Release with auto-generated release notes

You can also create a release from the GitHub UI: **Releases → Create a new release → enter the tag name** (e.g. `v1.1.0`).

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.