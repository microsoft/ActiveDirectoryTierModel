# Test Tag Matrix

This document defines Pester tags used across all TierModel test suites.

## Test Scope Tags

| Tag | Purpose |
|-----|---------|
| Unit | Unit tests for individual functions and logic |
| Integration | Integration tests for full workflows and orchestration |

## Component Tags

| Tag | Purpose |
|-----|---------|
| OU | Organizational Unit operations and validation |
| User | User account operations and validation |
| Group | Security group operations and validation |
| GPO | Group Policy Object operations |
| GPOLink | Group Policy Object linking operations |
| GpoTemplates | GPO template (GptTmpl.inf) operations |
| ADMX | Administrative template import and validation |
| OuAcl | OU permissions and ACL operations |
| MsaAcl | Managed Service Account ACL delegation operations |
| GmsaAcl | Group Managed Service Account ACL delegation operations |
| DmsaAcl | Delegated Managed Service Account ACL delegation operations |
| WinLapsAcl | Windows LAPS ACL delegation operations |
| WinLapsDecryptor | Windows LAPS GPO decryptor (ADPasswordEncryptionPrincipal) operations |
| Resolution | Name resolution and placeholder expansion |
| Manifest | Module manifest validation |
| Module | Module loading and integration tests |
| Prereq | Prerequisite validation tests |

## Lifecycle/Phase Tags

| Tag | Purpose |
|-----|---------|
| Planning | Planning phase (Get-TierModel* cmdlets) |
| FullDeployment | Full deployment planning (*Fd cmdlets) |
| Execution | Execution phase (New-TierModel* cmdlets) |
| Audit | Audit and validation (Test-TierModel* cmdlets) |
| Validation | Configuration and state validation |
| Exists | Existence checks |
| Create | Object creation operations |
| Deployment | Deployment operations |
| Phase3 | Phase 3 components (Groups, ACLs) |

## Prerequisite-Specific Tags

| Tag | Purpose |
|-----|---------|
| DomainAdmin | Domain Admin membership validation |
| Version | PowerShell version validation |
| Elevation | Administrator elevation validation |
| Connectivity | Domain controller reachability |
| Dependencies | dependencies.json parsing and validation |
| Modules | External module version and presence checks |
| Domain | Domain/forest detection logic |
| MsaPrereq | MSA feature prerequisite checks |
| GmsaPrereq | gMSA feature prerequisite checks |
| DmsaPrereq | dMSA feature prerequisite checks |
| WinLapsPrereq | Windows LAPS feature prerequisite checks (schema, module, DFL) |

## Test Type Tags

| Tag | Purpose |
|-----|---------|
| Positive | Expected success path |
| Negative | Expected failure or error path |
| Structure | Object shape and snapshot structure validation |
| Content | GPO content and template validation |
| Apply | Mutating apply/convergence scenarios |

## Special Focus Tags

| Tag | Purpose |
|-----|---------|
| Drift | Drift detection tests |
| Convergence | Convergence and idempotency tests |
| Idempotency | Idempotency-specific validation |
| Performance | Performance benchmarking tests |
| ErrorHandling | Error handling and recovery tests |
| Compliance | Compliance reporting tests |
| Output | Output format and reporting tests |
| Scopes | Scope-specific operations |

## Resolution Tags

| Tag | Purpose |
|-----|---------|
| DomainDN | Domain DN resolution |
| Placeholder | Placeholder expansion |
| OuPath | OU path resolution |
| Guid | GUID resolution |
| DomainGuid | Domain-specific GUID resolution |

## Cmdlet-Specific Tags

| Tag | Purpose |
|-----|---------|
| NewTierModel | New-TierModel* cmdlet tests |
| SetTierModel | Set-TierModel* cmdlet tests |
| Plan | Planning operations |

## Usage Examples

```powershell
# Run only unit tests
Invoke-Pester -Tag Unit

# Run all OU-related tests
Invoke-Pester -Tag OU

# Run prerequisite domain admin negative tests
Invoke-Pester -Tag Prereq,DomainAdmin,Negative

# Run all audit tests
Invoke-Pester -Tag Audit

# Run GPO tests excluding integration
Invoke-Pester -Tag GPO -ExcludeTag Integration

# Run drift detection and convergence tests
Invoke-Pester -Tag Drift,Convergence

# Run only planning phase tests
Invoke-Pester -Tag Planning

# Run structure validation only
Invoke-Pester -Tag Structure
```

## Test Execution Scripts

- **Invoke-AllTests.ps1** - Runs complete test suite with coverage
- **Invoke-PrerequisiteTests.ps1** - Runs prerequisite-specific tests with coverage

## Test Files by Component

| Test File | Tags | Component |
|-----------|------|-----------|
| `Unit.WinLapsAclOperations.Tests.ps1` | Unit, WinLapsAcl, WinLapsDecryptor, WinLapsPrereq | Windows LAPS ACL delegation + GPO decryptor |
| `Integration.WinLapsDeployment.Tests.ps1` | Integration, WinLapsAcl, WinLapsDecryptor | Windows LAPS end-to-end deployment + idempotency |

For additional documentation, see:
- [Deployment Methodology](deployment-methodology.md) - Comprehensive testing strategy
- [CI/CD Integration](ci-cd.md) - Automated testing in pipelines
