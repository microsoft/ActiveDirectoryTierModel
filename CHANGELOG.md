# Changelog

All notable changes to the TierModel project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-06-30

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

## [2.0.0] - 2026-02-27

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

## [1.0.0] - Initial Release

### Added
- Basic Active Directory Tier Model framework
- Organizational Unit management
- Security Group operations
- User account management
- Group Policy Object support
- Configuration-driven deployment
- JSON schema validation
- Pester test framework

---

**For detailed implementation specifications, see the documentation in `docs/`.**