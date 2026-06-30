# wolverine — History

## Sessions

### 2026-06-30 (v2.1.0 Release Prep)
- Ran full Invoke-AllTests.ps1 suite: 1292 tests passed / 0 failed ✅
- Fixed Unit.GmsaAclOperations.Tests.ps1 mock scope issue (added -Scope It to assertions)
- Fixed Unit.DmsaAclOperations.Tests.ps1 mock scope consistency
- Discovered: Get-TierModel*Acl cmdlets call Resolve-TierModelPlaceholder twice per delegation (not once per list)
- Coordinated test fix with Coordinator (removed -Exactly Count, kept -Scope It for per-delegation assertions)
- All tests passing, CI fully green

## Learnings
- Mock scope bleeding in Pester 5.7.1 requires careful placement of mocks and use of -Scope It flags
- Shadow variables (existence-check vars) used in test assertions are intentionally not dereferenced in script body
- Double invocation of Resolve-TierModelPlaceholder per delegation must be tested with "at least N" semantics, not exact counts
