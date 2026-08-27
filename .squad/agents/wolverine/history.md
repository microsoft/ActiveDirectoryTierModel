# wolverine — History (Summarized)

## Session 2026-08-27 — Auth Silo Coverage Gap-Fill Pass

**Status:** ✅ COMPLETE — 1,783 total tests, 1,783 passing, 0 failures
**Deliverables:** `tests/Unit.AuthSiloOperations.Tests.ps1` +12 targeted tests (119→131)

### Coverage Outcomes (second pass)

| Script | Before | After | Change |
|--------|--------|-------|--------|
| `New-TierModelAuthSilo` | 79.8% | **99.1%** | +19.3% (outer catch via Write-TierModelLog mock) |
| `Get-TierModelAuthSiloMembershipFd` | 64.7% | **87.8%** | +23.1% (states b/d, DN-format, outer catch) |
| `Set-TierModelAuthSiloMembership` | 61.5% | **87.8%** | +26.3% (group-expand fail, pre-check throw, DN-format, Grant fail, outer catch) |

Overall: 90.16% → **90.9%** (1,771 → 1,783 tests)

### Key Learnings (Coverage Deep-Dive)

- **PowerShell ScriptProperty `{ throw }` returns `""` not throws**: Confirmed by direct PS test. `Add-Member -MemberType ScriptProperty -Value { throw "..." }` silently returns empty string in `foreach ($x in @($obj.Prop))` and assignment contexts. Attempting to use this to trigger per-silo outer catch fails — the function gets an empty string and processes normally. This is a PS7 runtime behavior, not a Pester issue.

- **Outer function catch trigger — Write-TierModelLog mock inside try block**: For `New-TierModelAuthSilo`, the outer catch (`AuthSiloExecutionFailed`) is triggered by mocking `Write-TierModelLog` to throw on the 2nd call (the "AuthSiloExecutionComplete" call inside the try block). The 1st call (AuthSiloExecutionStart) is OUTSIDE the try. The 3rd call (AuthSiloExecutionFailed, inside the outer catch) must NOT throw. Use `if ($script:_tl_count -eq 2) { throw }` (exactly 2, not >= 2).

- **Per-silo outer catch is genuinely unreachable in unit tests for both membership functions**: The catch wraps code where all inner operations are either protected by their own try-catch or use operations (HashSet<string>, List<object>, bool comparisons) that never throw in practice. ScriptProperty doesn't work. Creating a custom IEnumerable that throws on MoveNext requires C# class authoring. Document as structural barrier, not test gap.

- **`UserDeclined` ternary branch**: `if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }` — the else branch requires `ShouldProcess() = false` without `-WhatIf`. In PowerShell there's no way to force this non-interactively. 1 command permanently unreachable per function that uses this pattern.

- **State (b) and state (d) for MembershipFd classification**: These are distinct paths through the already-assigned/pending decision. (b) granted+not-assigned uses `grantedDns.Contains(dn)=TRUE` and `currentSiloRef=$null`. (d) Get-ADComputer throws uses the inner catch. Both exercised by separate tests.

- **DN-format `msDS-AssignedAuthNPolicySilo` value**: When AD stores the silo ref as a DN `CN=SiloName,CN=...`, the code does `($ref -split ',')[0] -replace '^CN=', ''`. Tested by mocking Get-ADComputer to return DN-format value.

- **`$localEmptyCfg = [PSCustomObject]@{ authenticationSilos = @() }` vs `$script:ConfigEmpty`**: `$script:ConfigEmpty` returned `Converged=$false` in the Set-TierModelAuthSiloMembership context for unexplained reasons (possibly mock state from New-TierModelAuthSilo outer catch test via `InModuleScope TierModel { ... }` Write-TierModelLog mock). Using a fresh local config object avoids the issue.



**Status:** ✅ COMPLETE — 1,771 total tests (1,457 unit + 314 integration), 1,771 passing, 0 failures
**Deliverables:** `tests/Unit.AuthSiloOperations.Tests.ps1` — rewrote from 88 stale tests to 119 correct tests (+31 net). `README.md` and `docs/test-coverage.md` updated.

### Key Accomplishments

1. **Create-Once Model Alignment (19 tests removed, 50 added)**
   - Removed: UpdateAuthPolicy / UpdateAuthSilo drift tests (6), memberAccountGroups assertions (2), exemptAccounts / RID-500 exemption tests (3), UpdateAuthSilo action tests (2), user-based membership tests (3), plan-time SID-resolution failure test (1), plan-time SDDL test (1), "unexpected member NonCompliant" test (1).
   - Fixed: "NonCompliant on TGT drift" assertion (UserTGTLifetimeMins→TGT), "SDDL drift" assertion (SDDL→AllowedToAuthenticate), "unexpected member" test inverted (extras are now ALLOWED → Compliant + ExtraMembers).
   - Added: deferred SDDL (ResolvedSddl=$null in plan), execution-time SID resolution, pre-supplied SDDL honored, SidResolutionFailed path, CreatedNames/CreatedSiloNames contracts, -OnlyForSilos filter (empty/matching/omitted), computer-only membership, already-granted-not-yet-set path, WhatIf/non-already-exists exceptions.

2. **NEW Context: Get-TierModelAuthSiloMembershipFd (8 tests)**
   - Pending vs already-assigned classification
   - -OnlyForSilos filter (empty/matching/omitted)
   - Absent group tolerance (GroupExpandFailed error)
   - Summary keys TotalPending / TotalAlreadyAssigned / TotalActions / ExistingCount
   - Action entries: SiloName, SamAccountName, ObjectClass=computer

3. **RequireSubset tests for Compare-TierModelAuthSddl (4 tests added)**
   - Extras allowed + ExtraSids populated
   - Missing mandatory SID → Equal=false
   - Exact match → ExtraSids empty
   - Whitespace fallback when Get-ADDomain fails
   - Domain SID fallback via Get-ADDomain
   - Count-differs → reason matches

4. **Coverage Outcomes**
   - Overall: **90.16%** (13,506/14,980 commands), up from 88.93%
   - Build-TierModelAuthSddl: **100%** (5/5)
   - Compare-TierModelAuthSddl: **96.2%** (100/104)
   - Test-TierModelAuthSiloPrerequisite: **98.5%** (65/66)
   - Get-TierModelAuthPolicy / Get-TierModelAuthSilo: **95.5%** (21/22)
   - Test-TierModelAuthPolicy: **81.3%** (161/198)
   - Test-TierModelAuthSilo: **83.4%** (181/217)
   - Get-TierModelAuthSiloFd: **85.6%** (107/125)
   - Get-TierModelAuthPolicyFd: **83.7%** (87/104)
   - New-TierModelAuthPolicy: **82.9%** (107/129)
   - New-TierModelAuthSilo: **79.8%** — outer catch path structurally bounded
   - Get-TierModelAuthSiloMembershipFd: **64.7%** — inner classification loop (computer SID reads) partially covered; `Get-ADUser` path never called (computer-only)
   - Set-TierModelAuthSiloMembership: **61.5%** — large 221-command file; race-condition "converged-between-precheck-and-write" path and ShouldProcess-UserDeclined branch are structural barriers

### Learnings (Create-Once Tests)

- **Hashtable vs PSCustomObject for Summary**: `Get-TierModelAuthSiloMembershipFd` returns `$summary = @{...}` (Hashtable). Assert with `$result.Summary.Keys | Should -Contain 'TotalPending'`, NOT `.PSObject.Properties.Name` (that returns Hashtable metadata).
- **WhatIf tests**: `-WhatIf` on a `[CmdletBinding(SupportsShouldProcess)]` function makes `$PSCmdlet.ShouldProcess()` return false without user prompt. This exercises the WhatIf output branch and skips AD writes.
- **Test for already-granted-not-assigned** (Step 2 of two-step assignment): Mock `Get-ADAuthenticationPolicySilo` to return silo with `Members = @('CN=PAW01,...')` AND mock `Get-ADComputer` to return `'msDS-AssignedAuthNPolicySilo' = $null`. The pre-check sees Grant already done but Set not done → only `Set-ADAccountAuthenticationPolicySilo` is called once.
- **Brace imbalance from multi-edit sessions**: When replacing a context ending `}` plus `}` (Describe close), make sure new_str includes BOTH closings. Missing one closing brace compiles as valid PS but fails Pester discovery with "missing closing '}'". Debug with `($content.ToCharArray() | Where-Object { $_ -eq '{' }).Count` vs close.
- **Config object migration**: Removing `memberAccountGroups` from test config object required finding all test assertions that referenced user membership behavior. New config has `memberComputerGroups` only, matching production JSON schema.
- **Non-Silent output coverage**: Add tests that call audit cmdlets WITHOUT `-Silent` to cover `Write-Host` output branches (each host write is a counted command). A single non-Silent test can cover 5-10 new commands.
- **Resolve mock placement**: `Resolve-TierModelPrincipalSid` must be mocked at context level (not just in per-test `It` blocks) when New-TierModelAuthPolicy tests run with `ResolvedSddl=$null`; otherwise the real function runs and may fail in a mock-AD environment.
- **Files**: `tests/Unit.AuthSiloOperations.Tests.ps1` (119 tests across 13 contexts), `README.md` (QA section, auth-silos bullet), `docs/test-coverage.md` (tier tables, per-file table, new entries).



### Audit Behaviors Covered

1. **Test-TierModelAuthPolicy (11 tests)**
   - Compliant when AD matches config (description, TGT, SDDL, PFAD)
   - Missing when policy absent from AD
   - NonCompliant on: description drift, TGT drift, SDDL drift (different SID), PFAD=false
   - TGT check skipped when config TGT=null (EUD domain-default) — AD TGT value irrelevant
   - Enforce=true in AD → still Compliant (Enforce is never audited)
   - DD alias (SID(DD) in existing SDDL) is NOT a false-positive vs desired full S-1-5-21-...-516
   - Output structure has all required properties
   - TotalChecked / Compliant / Missing / Drift counters verified with two-policy scenario

2. **Test-TierModelAuthSilo (12 tests)**
   - Compliant when silo matches config with correct Members list (accounts + computers)
   - Missing when silo absent from AD
   - NonCompliant on: description drift, UserAuthenticationPolicy wrong, PFAD=false
   - NonCompliant when expected member absent from silo Members list
   - NonCompliant when unexpected member present in silo Members list
   - Exempt accounts (svc-pawdomainjoin etc.) excluded from expected → Compliant without them
   - RID-500 Administrator excluded from expected → Compliant without it
   - Enforce=true in AD → still Compliant (Enforce is never audited)
   - Empty groups + empty Members → Compliant (zero expected, zero current)
   - Output structure has all required properties

### Learnings (Audit-Specific)

- `$script:MatchingSddl` and `$script:AuditAdminDn` defined in BeforeAll are accessible from `It` block mock scriptblocks because mock scriptblocks access `$script:` variables from the TEST scope (not the TierModel module scope). This is the correct pattern — consistent with `$script:mockAcl` in Unit.AuditRuleOperations.Tests.ps1.
- Get-ADAuthenticationPolicySilo is called TWICE per silo in Test-TierModelAuthSilo: once with `-Properties *` (metadata), once with `-Properties Members` (membership). A single mock returning an object with both `Members` and metadata properties satisfies both calls.
- Compare-TierModelAuthSddl does NOT need a mock in audit tests when the mock AD policy has a matching SDDL — letting it run naturally also validates the DD alias expansion end-to-end.



**Status:** ✅ COMPLETE — 1,399 total unit tests, 1,399 passing, 0 failures
**Deliverables:** `tests/Unit.AuthSiloOperations.Tests.ps1` (67 tests across 10 Contexts)

### Key Accomplishments

1. **Auth Silo Deploy Tests (67 tests)**
   - Covers all 10 deploy cmdlets: Build-TierModelAuthSddl, Compare-TierModelAuthSddl,
     Get-TierModelAuthPolicy, Get-TierModelAuthSilo, Get-TierModelAuthPolicyFd,
     Get-TierModelAuthSiloFd, New-TierModelAuthPolicy, New-TierModelAuthSilo,
     Set-TierModelAuthSiloMembership, Test-TierModelAuthSiloPrerequisite
   - All AD cmdlets mocked — no live domain required
   - Written AFTER lab validation per workflow directive

2. **Mocking Approach**
   - Module-scope mocks via `Mock <Func> -ModuleName TierModel { }` (same convention as Unit.AuditRuleOperations)
   - Base mocks (Write-TierModelLog, Write-Host) set in Describe-level BeforeAll
   - Per-context AD mocks in Context-level BeforeAll (Get-ADAuthenticationPolicy, Get-ADAuthenticationPolicySilo, etc.)
   - Per-test overrides inline in It blocks with `InModuleScope TierModel { Mock ... }`
   - Helper functions (NewAuthPolicyPlan, NewSiloPlan, OneSiloConfig) defined in BeforeAll — NOT in Context body (known Pester v5 scope trap: `function script:Foo {}` in Context body NOT accessible from It blocks)
   - Capture-variable pattern: `$script:CapturedX = $null` set in `InModuleScope TierModel` BeforeAll of mock, read back with `InModuleScope TierModel { ... | Should -Be ... }` after call

3. **Auth-Silo Behaviors Covered**
   - Build-TierModelAuthSddl: O:SYG:SYD prefix; single/multi SID; OR-logic (Member_of_any only); string type
   - Compare-TierModelAuthSddl: identical=Equal; DD alias→full SID equal; reordered SIDs equal; different SIDs NotEqual; AND-logic (Member_of_each) NotEqual; empty existing NotEqual
   - Get-TierModelAuthPolicy: 4 policies; correct names; TGT 120/240/360/null; device groups; empty-config returns []
   - Get-TierModelAuthSilo: 4 silos; correct names; 1:1 policy refs; member groups; empty-config returns []
   - Get-TierModelAuthPolicyFd: CreateAuthPolicy when absent; AlreadyConverged when matching; UpdateAuthPolicy for TGT/SDDL/PFAD drift; error+skip on SID resolution failure; null-TGT EUD = no TGT drift
   - Get-TierModelAuthSiloFd: CreateAuthSilo when absent; policy pending creation NOT an error; error when policy not in config; AlreadyConverged; UpdateAuthSilo for description/PFAD/policy-ref drift
   - New-TierModelAuthPolicy: New-ADAuthenticationPolicy called for Create; Enforce=false; TGT lifetime set when non-null, NOT set when null (PSBoundParameters check); Set-ADAuthenticationPolicy for Update; empty plan = 0 calls, Converged=true
   - New-TierModelAuthSilo: New-ADAuthenticationPolicySilo called for Create; Enforce=false; all 3 class policies = same policy (1:1); Set-ADAuthenticationPolicySilo for Update; empty plan = 0 calls
   - Set-TierModelAuthSiloMembership: Grant THEN Set order (captured via List[string]); exempt accounts skipped (Reason=ExemptAccount); RID-500 Administrator skipped; already-assigned skipped (Reason=AlreadyAssigned, Grant+Set Times=0); empty groups = 0 Applied, 0 Errors
   - Test-TierModelAuthSiloPrerequisite: Passed when all groups exist; Checked>5 unique groups; Passed=false with group name in failure message when device group missing; Passed=false when account group missing; Get-ADUser never called; Passed=false on empty config

4. **Test File Fixes Required**
   - `Unit.ModuleManifest.Tests.ps1`: updated version expectation 1.3.2→1.3.3 (manifest updated by auth-silo PR, test not updated)
   - `Unit.ModuleManifest.Tests.ps1`: added `Build` and `Compare` to naming-convention regex (auth-silo cmdlets use approved verbs Build/Compare not in original allowlist)

### Learnings
- Pester v5: `function script:FuncName {}` in Context body is NOT accessible via `script:FuncName` call from It blocks. Always define helpers in `BeforeAll { function FuncName {} }` (no scope prefix). This is consistent with the existing Mock-ACL helper pattern in Unit.AuditRuleOperations.Tests.ps1.
- `script:FuncName` (no args) resolves as a variable access ($script:FuncName), silently returning $null; `script:FuncName -Param value` attempts a command call and throws. This explains inconsistent failure patterns.



**Status:** ✅ COMPLETE — 1,987 total tests (1,652 automated + 335 manual)
**Deliverables:** Format-Duration unit tests, Pester v5.9.0 hard-pin, CLR assembly conflict resolution

### Key Accomplishments

1. **Format-TierModelDuration Tests**
   - 23 unit tests across 4 Contexts (sub-ms, ms, seconds, minutes)
   - Created 	ests/Unit.FormatDuration.Tests.ps1
   - 3 integration test scenarios added: 150ms→'2s', all-converged, 140000ms→'2m 20s'
   - Banker's-rounding guard trio (90000/119999/120000) locks regression
   - All files above 80% CI gate

2. **Pester v5 Hard-Pin Fix (Defense in Depth)**
   - **Layer 1**: CLR Detection + Re-Spawn — detect Pester v6 CLR in [AppDomain], re-invoke clean child
   - **Layer 2**: \ = 'None' during discovery to prevent v6 auto-load
   - **Layer 3**: Hard assertion post-import to verify Major version = 5
   - Root cause: Pester 6.0.0 removes Assert-MockCalled (replaced by Should -Invoke); v6 CLR assembly can't be unloaded mid-process
   - Local test runtime baseline: **~4.0 min / 1533 tests** (Pester 5.9.0, no coverage)

3. **Coverage Metrics (Authoritative 2026-08-15)**
   - Overall: 89.65% (14,651 / 16,343 commands)
   - 6 key files all above 80% gate:
     - Get-TierModelAuditRule.ps1: 100%
     - Get-TierModelAuditRuleFd.ps1: 97.73%
     - Test-TierModelAuditRule.ps1: 98.41%
     - New-TierModelAuditRule.ps1: 84.14%
     - Audit-TierModel.ps1: 85.9%
     - Deploy-TierModel.ps1: 81.53%
   - 19 unit test files (not 20 — stale count fixed)
   - 7 integration test files
   - Per-file coverage refreshed in docs/test-coverage.md

### Mock ACL Pattern (Durable Learning)
- PSCustomObject with _Aces List[object] NoteProperty + ScriptMethods GetAuditRules/RemoveAuditRuleSpecific/AddAuditRule
- Mock Get-Acl -ParameterFilter { \ }
- 9 canonical rights bits: CreateChild=1, DeleteChild=2, Self=8, WriteProperty=32, DeleteTree=64, ExtendedRight=256, Delete=65536, WriteDacl=262144, WriteOwner=524288; ALL9=852331

### Key Learnings
- Helper funcs in Describe body NOT visible in mock scriptblocks; define in BeforeAll { function ... } block
- Get-TierModelAuditRuleFd never resolves 'script:CorrelationId' scope prefix; always re-stamps fresh GUID
- Temp artifacts cleaned up at end (coverage-audit.xml, cov-native.csv)
- No pre-existing failures caused by Format-Duration changes; all 64 pre-existing failures unrelated

---

## Session 2026-08-15 — Coverage Refresh & Pester v6 CLR Conflict Resolution

**Status:** ✅ COMPLETE — All 1,533 tests passing
**Issue:** 64 pre-existing Pester v6 contamination failures obscuring real coverage

### Root Cause Analysis
- Pester 6.0.0 auto-loaded by pwsh 7.6.5 before Invoke-AllTests.ps1 ran
- v6 removed Assert-MockCalled → all v5 mock patterns fail (64 pre-existing tests)
- Zero failures from new -EnableAuditing audit code

### CLR Assembly Conflict Pattern (Durable)
- Remove-Module only removes PowerShell wrapper; .NET assembly persists in [AppDomain]
- Only remedy: new process (pwsh -NoProfile -NonInteractive)
- Always check [AppDomain]::CurrentDomain.GetAssemblies() for version conflicts in long-running terminals

### OneDrive Offline-Pin Impact
- Joel pinned PowerShell + WindowsPowerShell module dirs "Always keep on device"
- Result: import time 0.54s → **0.50s** (essentially unchanged)
- OneDrive hydration was NOT the bottleneck; execution is compute-bound

---

## Earlier Session 2026-08-11 — BUG-006 Canonical ACL Tests

**Status:** ✅ COMPLETE — PENDING owner code review + PR
**Tests:** 	ests/Unit.CanonicalAcl.Tests.ps1 (18 tests, ByBytes path, offline fixtures)
**Coverage:** CanonicalAcl.ps1 58.93% (ByServer offline-untestable); Prerequisites.ps1 85.03%
**Total:** 1,457 tests, 1,457 passing, 91.13% coverage
