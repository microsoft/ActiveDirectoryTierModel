# wolverine -- History

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
