# wolverine -- History

## Session 2026-09-03 — Debug Capability Regression Risk Assessment

**Status:** COMPLETE
**Deliverable:** `.squad/decisions/inbox/wolverine-debug-regression-risk.md`

**Scope:** Read-only risk assessment — no test files written. Assessed the regression surface for adding `-Debug` / `[CmdletBinding()]` to `Deploy-TierModel.ps1`, `Audit-TierModel.ps1`, and `modules/TierModel/public/*.ps1`.

**Key findings:**
- All 80 public module functions already have `[CmdletBinding()]` — the "ensure CmdletBinding" part of the proposal is a no-op. Both Deploy and Audit scripts already have `[CmdletBinding()]` and already expose `-Debug`.
- **HIGH (hard break):** `Unit.ModuleManifest.Tests.ps1` lines 215–216 enforces exact count: `DeclaredFunctions.Count Should -Be ActualFunctions.Count`. Any new public function added without updating `FunctionsToExport` in `TierModel.psd1` instantly fails this test.
- **HIGH (hard break):** CI enforces 80% code coverage. New untested public functions will drop the percentage and fail the build.
- **MEDIUM (design constraint):** `tests/helpers/ADStubs.ps1` — all stubs use plain `param()` with no `[CmdletBinding()]`. If debug implementation forwards `-Debug` to AD cmdlets (via splat or explicit param), stubs throw binding errors. Solution: never forward `-Debug` to AD cmdlets.
- **LOW/MEDIUM:** `$DebugPreference = 'Inquire'` is a PS5.1 hazard only. CI runs PS7 where `-Debug` = `Continue`, no prompt. Safe in CI.
- **ZERO RISK:** Logging tests (`Unit.Logging.Tests.ps1`) use explicit `-LogPath`; no filename pattern assertions. All 304 `-ParameterFilter` usages check domain params, not common params.

**Baseline test count (from history):** 1,886 automated tests (1,572 unit, 314 integration) as of 2026-09-02 baseline.

**How to get a clean baseline:** `cd tests; .\Invoke-AllTests.ps1 -TestType Unit` — no AD/RSAT required, completes in ~2 minutes.

## Learnings

### 2026-09-03 — An unfaithful mock actively conceals production bugs

This is the headline lesson from unblocking four test-locked production bugs.

- **A mock that returns nothing where the real cmdlet returns an object is not "simple" — it is wrong,
  and it hides real defects.** `Grant-ADAuthenticationPolicySiloAccess`, `Set-ADAccountAuthenticationPolicySilo`
  and `Set-GPRegistryValue` were all mocked as `{ }`. Because the mock could never return anything, no
  production null/result check could ever be added, so a silent no-op AD/GPO write kept printing a green
  success tick. The tests were not merely failing to catch the bug — they were the reason the bug could
  not be fixed. Beast implemented three correct fixes, hit 4 failures, and had to revert.
- **Faithful means faithful to the real cmdlet's contract, not "returns something".** Both AD silo cmdlets
  emit *nothing* unless `-PassThru` is supplied; `Set-GPRegistryValue` emits the `Gpo` object by default.
  Blindly returning an object from the AD mocks polluted the function's output stream (production calls
  them without `| Out-Null`), turning `$result` into an array and breaking an unrelated test. The correct
  mock models *both* arms: no output without `-PassThru`, a realistic object with it.
- **A test whose comment contradicts its own mock is a latent blocker.** `Unit.GpoLinking.Tests.ps1`
  asserted an "enforcement mismatch" with config `enforced = 'No'` against a mock link whose `Enforced`
  was `$false` — the comment claimed the current state was "Yes/True". It only passed because of the very
  truthiness bug under repair (`'No' -ne $false` is True). Corrected to string `'Yes'`, which still asserts
  a genuine mismatch and additionally exercises the string-form config normalization path.

### 2026-09-03 — Pester 5.9 mock scoping facts (hard-won, verified empirically)

- `$PesterBoundParameters` **is** available inside a mock body (not just in `-ParameterFilter`). This is the
  reliable way to branch a mock on a switch such as `-PassThru`, since Pester 5.9 still does not inject
  named parameters into mock bodies.
- **But only for mocks registered with `Mock <cmd> -ModuleName <Mod>`.** A mock declared *inside*
  `InModuleScope <Mod> { Mock <cmd> {...} }` does **not** get `$PesterBoundParameters`, and under the
  module's StrictMode the reference throws *"The variable '$PesterBoundParameters' cannot be retrieved
  because it has not been set."* That exception is swallowed by the production try/catch and surfaces as a
  confusing downstream assertion failure (e.g. "Expected 'Set' to be found in collection Grant") rather
  than as an obvious mock error.
- The two registration styles also differ in `$script:` scope. A `$script:` variable written by a mock
  declared with `-ModuleName` is **not** the same variable read inside an `InModuleScope` block. Keep the
  initialisation, the mock and the assertions all in the same style or the counter silently reads `$null`.
- Diagnosing this class of failure: dump `$result.Errors` from the function under test. The real cause is
  almost always an exception thrown *inside the mock* and caught by production code.
- `Should -Contain` against an **empty** `List[string]` reports "collection $null" (an empty list pipes to
  nothing), which reads like an uninitialised variable but is not. Don't chase the wrong bug.

## Session 2026-09-02 -- Session Orchestration & Finalization

**Status:** COMPLETE
**Work:** Decisions archive processed, inbox merged, history records written

- Decisions.md: archived 12 entries (pre-2026-08-26), merged inbox "Dot-Source Pattern" decision
- decisions-archive.md: 12 archived entries appended, total 102,794 bytes
- Orchestration logs: written for Beast and Wolverine with session summary
- Session log: membership-tests-v2-release.md documenting full coordination
- History files updated with session notes
- .squad/ files staged for final commit

---

## Session 2026-09-02 -- Membership Reconciliation Unit Tests (Wolverine)

**Status:** COMPLETE
**Deliverable:** `tests/Unit.MembershipReconciliation.Tests.ps1` -- 107 tests, 107/107 pass

**What was built:**
- Dot-source seam pattern for standalone scripts (not modules): `if ($MyInvocation.InvocationName -eq '.') { return }` allows Pester to load functions without executing main.
- 107 mock-based unit tests covering: Resolve-ActiveSwitches (all 15 switches + mandatory order), Initialize-BuiltInExclusions + Test-IsBuiltInExcluded (case-insensitive HashSet), Test-IsCustomerExcluded (6 boundary cases), Resolve-OuDn/Resolve-GroupSam, Write-TmEvent (opt-in / no-throw contract), Initialize-Logging (pruning, filename pattern), Write-Log/Write-DebugLog (WhatIf immunity via -WhatIf:$false on Add-Content), Invoke-TierReconciliation (counter semantics, exclusion enforcement, WhatIf mode, ExcludeChildOuDn), Invoke-Tier2Operators / Invoke-Tier2Eud (operator-wins disambiguation).
- CI coverage wired: `optional/Update-TierModelMembership.ps1` added to `.github/workflows/ci.yml` CodeCoverage.Path. Measured coverage: **60.18%** (inline main-block and dispatch wrappers unreachable via dot-source).

**Key learnings:**
- `New-TestAdObj`: MUST use `$o.PSObject.Properties.Add([PSNoteProperty]::new(key, val))` NOT `Add-Member`. The real AD module registers an `ADEntityAdapter` for `Microsoft.ActiveDirectory.Management.ADObject` when imported. `Add-Member` goes through the adapter and throws "adapter may only be used for ADEntity". `PSObject.Properties.Add` bypasses the adapter entirely. CRITICAL: this applies even AFTER the real AD module loads during mock setup.
- Mock body `$Identity` not received without `param()` -- but even with explicit `param()` Pester 5.9 does NOT pass named params into mock bodies. Workaround: script-scope call counter ($script:T2GrpCall++) when two group-membership calls are made in fixed order.
- `$script:` variables defined outside BeforeAll (at Describe body level) run at DISCOVERY time and are NOT available at run time inside It blocks. Always use BeforeAll for test-data initialization.
- `Should -Throw '*pattern*'` is the correct Pester 5.x positional syntax. `-ExceptionMessage` is NOT a valid Pester 5 parameter (was Pester 4).
- Pester 5.x `It` test names with `<placeholder>` are treated as TestCase variable substitutions even without TestCases -- strict mode then throws "variable $name not set". Avoid `<...>` in test names unless TestCases are provided.
- EventLog::WriteEntry is a .NET static -- Pester 5.x cannot mock it. Write-TmEvent is tested for behavioral contract only (opt-in gate, no-throw, WhatIf detection).
- StrictMode 2.0 (set by the script at dot-source) throws for property access on plain .NET classes when the property doesn't exist as NoteProperty or CLR property. Fix: always add ALL required NoteProperties to test objects, including $null defaults for properties the code might access. PSCustomObject returns $null for missing props (no StrictMode error), but our ADObject stub (plain C# class) DOES throw. "Attribute absent" tests must become "attribute present but $null" to match production reality (Get-ADObject with -Properties always returns requested attrs).
- Fresh-session ADEntityAdapter timing: mock setup for `Get-ADGroup`, `Get-ADObject` etc. can trigger PowerShell auto-loading of the real ActiveDirectory module, which registers the ADEntityAdapter. Objects created AFTER this load fail with Add-Member. Solution: PSObject.Properties.Add before any mock is set up, or (simpler) always use PSObject.Properties.Add.
- Test "absent attribute" -> "attribute present but null": production reality is that `Get-ADObject -Properties adminDescription` ALWAYS returns the attribute, just with $null if unset. Tests must model production reality.

**NOT unit-testable (integration-covered by Joel lab UAT):**
- Exclusion parameter-pairing gate (-ExclusionAttribute without -ExclusionValue)
- -NoExclusions safety gate (mutually exclusive with -ExclusionAttribute)
- Invoke-Tier0/1/2 dispatch wrappers (call through to Invoke-TierReconciliation; covered indirectly)
- Invoke-BuiltInExclusionEnforcement (uses Get-ADUser; not part of Invoke-TierReconciliation)

**RECOMMENDATION FOR BEAST:** Extract the two inline main-block parameter gates into `Test-TmExclusionParams` to enable unit testing. Currently they're embedded in the `try {}` block and can only be reached by running the script's main execution path.

**Honest before/after test counts (measured in fresh sessions):**
- Unit tests: 23 files / 1,465 tests  =>  24 files / 1,572 tests (+107)
- Total automated: 1,779  =>  1,886 (+107)
- Script coverage: 60.18% (CI-measured, CodeCoverage.Path updated)
- README stated 22/1,469 (was already 1 file / 4 tests off from actual baseline)
- Verified both WITH ADStubs (CI path: 107/107) AND WITHOUT ADStubs (user's failure scenario: 107/107)

---

## Session 2026-09-02 -- Auth Silos Public Docs + v2 Migration (Storm)

Public-facing auth-silos operations guide revised with v2 migration appendix. No test impact (docs only).

---



**Status:** BLOCKED (awaiting Joel UAT completion)
**Trigger:** Once Beast confirms UAT complete, write comprehensive Pester test suite covering all 15 tier switches + optional flags.

**Test Coverage Needed:**
- Tier 0/1/2 Operator switches
- ServiceAcct / PawDevices / MemberServers / Staging switches  
- Tier 2 EUD vs Tier 2 Operators conflict resolution
- -All aggregates
- Exclusion attribute handling
- -EnableDebug and -EnableLogging output
- -WhatIf logging logic (v1.7.2): script-relative Logs/Debug folders, WHATIF preview lines, -WhatIf:$false on infra I/O
- PS 7.0+ requirement + 5.1 block

---

## Session 2026-08-27 — Auth Silo Coverage Gap-Fill

**Status:** ✅ COMPLETE — Auth silos test suite rewritten for create-once model

**Deliverables:** 1,783 tests passing (1,771→1,783), coverage raised from 90.16% → 90.9%

**Key Outcomes:**
- New-TierModelAuthSilo: 79.8% → 99.1%  
- Get-TierModelAuthSiloMembershipFd: 64.7% → 87.8%
- Set-TierModelAuthSiloMembership: 61.5% → 87.8%

**Design Changes Validated:**
- Removed memberAccountGroups (computer-only model)
- Removed exemptAccounts (pre-set built-in exclusions)
- Deferred SDDL (null at plan time, resolved at execute time)
- -OnlyForSilos filter validation

**Key Learning:** Outer catch blocks in membership functions are structurally unreachable — all inner operations are exception-safe by design (HashSet, List, comparisons don't throw). Documented as structural barrier.

---

## Archived Sessions  

Detailed coverage reports from 2026-08-15 and earlier archived to history-archive.md. Current focus: Update-TierModelMembership.ps1 Pester tests awaiting Beast UAT completion.

---

## Learnings — 2026-09-03 (session 2: gpoStatus + GPO link planner)

**A test whose own comment documents a bug is a bug report, not a specification.**
Three tests in `Unit.GpoLinking.Tests.ps1` and one in `Unit.GpoOperations.Tests.ps1`
contained comments explicitly narrating the defect they were pinning ("the function has
a StrictMode bug...", "Passes when actual flags also happen to be 0"). Each one had been
written to match observed output rather than intended behaviour. When a comment explains
*why the wrong answer is expected*, that is the signal to escalate, not to assert.

**The silent-default anti-pattern.** `default { 0 }` in the gpoStatus switch turned a
config typo into a green audit whenever the live GPO happened to be flags=0. There is no
runtime JSON-schema validation anywhere in this repo (`Test-TierModelConfig` is referenced
only from `tests\`, the hand-rolled validator never reads `enum`, and `Test-Json` appears
zero times), so nothing upstream catches the typo. Unknown enum values must fail loudly and
name both the offending value and the valid set — but must not `throw` in a way that aborts
the whole audit run.

**Empty-collection collapse hides the happy path.** `@() | Sort-Object {...}` returns `$null`,
and `$null.Count` throws under StrictMode. In the GPO link planner this meant the
*fully converged* case — the success outcome — surfaced as `GPOLinkPlanningFailed`, and a
genuine per-action failure was relabelled from `GPOLinkAnalysisFailed` to the outer
planning error, hiding which action actually broke. Always wrap pipeline results destined
for `.Count` in `@()`.

**Verify the mock that is actually in scope before "fixing" a test.** I changed
`enforced = 'No'` to `'Yes'` in "Should plan to update link when enforcement doesn't match"
after reading a `Get-GPInheritance` override that was declared *inside a different `It`*
(Pester 5 scopes it to that `It` alone). The Describe-level mock returns `Enforced = $true`,
so the original `'No'` was correct and my edit silently removed the mismatch. Reverted.
When several mocks share a cmdlet name in one file, confirm which one the failing test
actually resolves to.

**Test-isolation defect, not a production defect (EnvironmentSnapshot).**
`Unit.Prerequisites.Tests.ps1` writes fixtures to `[System.IO.Path]::GetTempPath()` under
FIXED names and deletes them in `AfterAll`. Two concurrent runs on the same machine delete
each other's fixtures mid-flight; `Test-TierModelPrerequisites.ps1` then early-returns with
`EnvironmentSnapshot = @{}` and every snapshot assertion reads `$null`. Reproduced
deterministically: concurrent run A 91/0, run B 85/6. Fix is unique fixture names per run
(PID or GUID), not a change to the production function. Left unfixed to avoid colliding
with Beast's concurrent BUG-011 work.
