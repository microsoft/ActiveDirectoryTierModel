# 🏛️ Tier Model

Declarative PowerShell framework to deploy and audit an Active Directory Tier Model (OUs, Groups, Users, ACL Delegations, GPOs, ADMX) from a single version-controlled JSON configuration file. Supports idempotent re-runs, drift detection, and reproducible builds via pinned dependency versions.

> 🏗️ **Built with the Specify Framework** - Test-driven development ensuring quality and reliability

## 🎯 Goals
- 🔒 Safe, repeatable deployments (WhatIf planning + convergent apply)
- 📊 Drift auditing & reporting (hash provenance + structured findings)
- 🧩 Modular, test-first architecture (Pester enforced)
- 📦 Version governance for dependencies & configuration schema

## 📚 Documentation

To get started with TierModel, please refer to our comprehensive documentation:

### 🚀 Getting Started
- **[Quick Deployment Guide](docs/quick-deployment-guide.md)** - Fast-track deployment for experienced administrators
- **[Detailed Deployment Guide](docs/detailed-deployment-guide.md)** - Step-by-step deployment with explanations
- **[FAQ](docs/faq.md)** - Frequently asked questions covering upgrades, migration from previous versions, troubleshooting, and Sentinel integration

### 📖 Core Documentation
- **[Deployment Methodology](docs/deployment-methodology.md)** - Understanding the deployment approach
- **[Drift Detection Details](docs/drift-detection-details.md)** - Comprehensive drift auditing and remediation
- **[Tier Model Logging](docs/tiermodel-logging.md)** - Structured logging and diagnostics
- **[GPO Management Strategy](docs/gpo-management-strategy.md)** - Group Policy Object management
- **[ADMX Management](docs/admx-management.md)** - Administrative template handling
- **[Conditional Principals](docs/conditional-principals.md)** - Domain-specific principal resolution
- **[CI/CD Integration](docs/ci-cd.md)** - Pipeline integration and automation
- **[Test Tag Matrix](docs/test-tag-matrix.md)** - Pester test organization
- **[Test Coverage](docs/test-coverage.md)** - Comprehensive test coverage analysis and roadmap

### 🔧 Technical Specifications
- **[Feature Specification](specs/001-tier-model-module/spec.md)** - Complete requirements and user stories
- **[Implementation Plan](specs/001-tier-model-module/plan.md)** - Technical architecture and design decisions

## 🧪 Testing & Quality Assurance

**Current Test Status: ✅ ALL TESTS PASSING** *(Last run: March 6, 2026)*

| Test Suite | Test Files | Test Cases | Status | Coverage |
|------------|-----------|------------|--------|----------|
| **Unit Tests** | 12 files | 878 tests | ✅ 100% Pass | **91.3%** |
| **Integration Tests** | 6 files | 201 tests | ✅ 100% Pass | **100%** |
| **Manual Integration Tests** | 1 file | 265 tests | ✅ 100% Pass | **100%** |
| **Total** | **18 files** | **1,079 tests** | ✅ **All Passing** | **91.3%** |

### Test Coverage Highlights
- ✅ **46/46** production files have comprehensive test coverage
- ✅ **100%** of all automated 1,079 test cases passing
- ✅ **100%** of all manual 265 test cases passing
- ✅ **91.3%** overall line coverage (8,140 / 8,916 commands) — all files at 80%+
- ✅ `Get-TierModelConditionalGroupNames` — new function with full test coverage (6 unit tests)
- ✅ Mock-based testing (no Active Directory connectivity required)
- ✅ WhatIf support validation across all deployment operations

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
| Script | Purpose |
|--------|---------|
| `Deploy-TierModel.ps1` | 🚀 Deploy with scoped execution |
| `Audit-TierModel.ps1` | 📊 Audit and compliance checking |

## 🤝 Contributing

Contributions are welcome! Before submitting a pull request, you **must** ensure:

1. ✅ **All Pester tests pass** — the CI pipeline will reject any PR with failing tests
2. 🧪 **New or updated tests are included** — any new code or bug fix must include corresponding test cases to maintain or improve code coverage
3. 📊 **Code coverage stays at or above 80%** — the CI enforces a minimum coverage threshold; if your changes reduce coverage below 80%, add tests until coverage is restored
4. 📝 Documentation is updated for any new or changed functionality
5. 🎯 Code follows project conventions

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
git clone https://github.com/yourorg/TierModel.git
cd TierModel

# Run tests locally before submitting a PR
.\tests\Invoke-AllTests.ps1
```

## 📋 Prerequisites

- **PowerShell**: 7.0+
- **Elevation**: Administrator privileges required
- **Domain Admin**: Membership in Domain Admins group
- **Modules**: ActiveDirectory, GroupPolicy (see `config/dependencies.json`)

*For detailed prerequisite validation, run `Test-TierModelPrerequisites`*

## 🔗 Additional Resources

- ❓ [Frequently Asked Questions (FAQ)](docs/faq.md)
- 📦 [Dependencies Configuration](config/dependencies.json)
- 🗂️ [Configuration Schema](config/tiermodel.schema.json)
- 📜 [Changelog](CHANGELOG.md)

---

**Version**: 2.0.0 | **License**: MIT | **Status**: ✅ Production Ready

## 🚀 Releasing

This project uses **semantic versioning** (`MAJOR.MINOR.PATCH`) and tag-based releases.

| Bump | When | Example |
|------|------|---------|
| `PATCH` (2.0.**1**) | Bug fix, typo, doc correction | Fix broken ACL rule |
| `MINOR` (2.**1**.0) | New feature, backward-compatible | Add WinLAPS parameter |
| `MAJOR` (**3**.0.0) | Breaking change | Restructure config schema |

### Creating a release

1. Ensure all changes are merged to `main` and CI is green
2. Tag the release:
   ```bash
   git tag v2.1.0
   git push origin v2.1.0
   ```
3. The CI pipeline will automatically:
   - Run all tests and enforce code coverage (80% minimum)
   - Create a `TierModel-2.1.0.zip` release asset
   - Publish a GitHub Release with auto-generated release notes

You can also create a release from the GitHub UI: **Releases → Create a new release → enter the tag name** (e.g. `v2.1.0`).

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.