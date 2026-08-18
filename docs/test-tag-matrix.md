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
| AuditRule | Domain audit rule (SACL) configuration and drift detection |
| CanonicalAcl | DACL canonical-order detection and remediation |
| Repair | Canonical DACL re-sort (Repair-TierModelCanonicalAcl) |
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
| CanonicalAclPrereq | Non-canonical root ACL gate + -SkipRootCanonicalCheck path |

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
| `Unit.AuditRuleOperations.Tests.ps1` | Unit, AuditRule | Domain audit rule (SACL) plan/apply/drift cmdlets + config segment |
| `Integration.Audit.Tests.ps1` (AuditRule) | Integration, Audit, AuditRule | `-EnableAuditing` standalone/FullDeployment/combined audit paths |
| `Integration.Deploy.Tests.ps1` (AuditRule) | Integration, Deploy, AuditRule | `-EnableAuditing` scope validation + Phase 11 deployment paths |
| `Unit.CanonicalAclRepair.Tests.ps1` | Unit, CanonicalAcl, Repair | `Repair-TierModelCanonicalAcl` ByBytes offline: return shape; all-four-ranks sort; CommonAce-before-ObjectAce sub-order; already-canonical (WasAlreadyCanonical=true, null SortedSdBytes); multiset preservation (AceCount invariant, SID identity); stability (equal-rank relative order preserved); idempotency (double-repair = canonical on second call); Deny/Allow overlap warning; DistinguishedName passthrough; multiple-violation 5-ACE; SortedSdBytes roundtrip; ByServer mocked (non-canonical write, already-canonical no-write, AceCountBefore, DN echo); parameter-set validation |
| `Unit.CanonicalAclAudit.Tests.ps1` | Unit, CanonicalAcl, Audit | `Invoke-CanonicalAclAudit` (extracted from `Audit-TierModel.ps1`): Case 1 domain-root non-canonical (Mismatched/Drift counters, Case1 finding, LogCode AuditNonCanonicalAclDomainRoot, ResourceType DomainRoot, Identifier=DN, Details mentions domain root + canonical-acl.md, TotalChecked=1); Case 2 Tier-OU non-canonical (Mismatched/Drift, Case2 finding, LogCode AuditNonCanonicalAclTierOu, ResourceType TierModelOU, Details mentions OU name + New-TierModelOu.ps1); all-canonical (Drift=0, no findings, TotalChecked=Compliant, Missing=0); counts mix (Compliant/Mismatched/Errors correct, Drift=Mismatched invariant); exception on root (Errors=1, Mismatched=0); exception on OU (Errors=1 continues); absent-OU skip (canonical check not called for absent OUs, TotalChecked=1); return shape (all required fields, CorrelationId is GUID, DurationMs ≥ 0) |

For additional documentation, see:
- [Deployment Methodology](deployment-methodology.md) - Comprehensive testing strategy
- [CI/CD Integration](ci-cd.md) - Automated testing in pipelines
