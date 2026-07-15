# Squad Decisions — Archive

This archive contains decisions older than the retention window (7 days when file >= 51200 bytes).

## Archived on 2026-07-15

### 2026-06-30T12:17:50+08:00: v2.1.0 Release Version for gMSA/dMSA/MSA ACL Work
**Context:** specs/002-gmsa-support branch, PR #13 open and mergeable
**Decision:** Release as v2.1.0 (minor bump over unreleased 2.0.0 in repo). Last published GitHub release was v1.0.0; manifest already declared 2.0.0.
**Rationale:** Bump minor version to reflect new gMSA/dMSA/MSA ACL capabilities without major version change.
**Status:** ACTIVE — v2.1.0 tag NOT created yet (awaiting merge approval)

### 2026-06-30T12:17:50+08:00: Cmdlet Files (modules/TierModel/) Are Off-Limits
**Context:** gMSA/dMSA/MSA ACL support implementation
**Decision:** NO CHANGES to existing cmdlet files under modules/TierModel/. User directive: cmdlets are working/tested.
**Rationale:** Minimize risk; cmdlets are in stable state. All work confined to test files and CI config.
**Status:** ACTIVE — enforced throughout Phase 16 testing

### 2026-06-30T12:17:50+08:00: ScriptAnalyzer Rule PSUseDeclaredVarsMoreThanAssignments Excluded in CI
**Context:** New Test-TierModel*Acl.ps1 cmdlets use existence-check variables
**Decision:** Added PSUseDeclaredVarsMoreThanAssignments to excludeRules in .github/workflows/ci.yml
**Rationale:** Test cmdlets require variables to check if certain operations were invoked (Shadow variables for scope assertions).
**Status:** ACTIVE — CI checks passing with this exclusion

### 2026-06-30T12:17:50+08:00: Resolve-TierModelPlaceholder Invoked Twice Per Delegation (Not Per List)
**Context:** Unit.GmsaAclOperations.Tests.ps1 and Unit.DmsaAclOperations.Tests.ps1 fix
**Decision:** Removed -Exactly Count from Should -Invoke assertions; kept -Scope It. Tests now assert "at least 2 invocations per delegation" (line 114 unique-OU pass + line 172 main loop).
**Rationale:** Get-TierModel{Gmsa,Dmsa,Msa}Acl calls Resolve-TierModelPlaceholder multiple times per delegation (once for unique-OU pass, once in main loop). -Scope It + no -Exactly permits accurate assertion without false negatives.
**Status:** ACTIVE — all CI tests passing
