# wolverine — History

## Session 2026-08-24 — Format-TierModelDuration tests (issue #34)

**Status:** ✅ COMPLETE

### Deliverables

| File | Action | Description |
|------|--------|-------------|
| `tests/Unit.FormatDuration.Tests.ps1` | **CREATED** | 23 unit tests, 4 Contexts (sub-ms, ms, seconds, minutes), + null-coercion + return-type |
| `tests/Unit.ModuleManifest.Tests.ps1` | **UPDATED** | Added `Format` to approved-verb regex; added `Format-TierModelDuration` accessibility assertion |
| `tests/Integration.Deploy.Tests.ps1` | **UPDATED** | 3a: OuOnly mock 150ms→2254ms → assert 'Duration: 2s'; 3b: all-converged test + 'Duration: <1ms'; 3c: new It block DurationMs=140000 → 'Duration: 2m 20s' |
| `README.md` | **UPDATED** | Metrics refreshed from actual run (see below) |

### Authoritative Measured Numbers (2026-08-24, Pester 5.9.0)

| Metric | Value |
|--------|-------|
| Unit test files | **22** (+1: Unit.FormatDuration.Tests.ps1) |
| Unit tests | **1,338** (+24: 23 new + 1 manifest assertion) |
| Integration test files | **7** (unchanged) |
| Integration tests | **314** (+1: 2m 20s wiring-proof test) |
| Automated total | **1,652** (+25) |
| Manual tests | **335** (authoritative per Joel, unchanged) |
| Grand total | **1,987** |
| PASS | **1,652** |
| FAIL | **0** |
| Overall coverage | **88.93%** (15,057 / 16,932 commands) |
| Production files | **71/71** (Format-TierModelDuration.ps1 adds the 71st) |

All files above 80% CI gate. Zero regressions. ✅

### Banker's-Rounding Guards Rationale
The 90000 / 119999 / 120000 trio locks the contract against a regression to the old `[int][TimeSpan]::TotalMinutes` pattern. 90000ms = 1.5 minutes; banker's-rounding [int]1.5 → 2 (even) → wrong "2m 30s". The three guards prove the floor path is exercised:
- 90000 → '1m 30s' (not '2m 30s')
- 119999 → '1m 59s' (not '2m 59s')
- 120000 → '2m 0s' (minute boundary sanity)

### No commit per owner request.

---

**2026-08-11 — BUG-006 canonical-ACL tests implemented:** Created `tests/Unit.CanonicalAcl.Tests.ps1` (18 tests, ByBytes path, offline fixtures) + 4 gate tests in `Unit.Prerequisites.Tests.ps1`; under Pester 5.9.0 (supported): TOTAL=1457 PASS=1457 FAIL=0; COVERAGE=91.13%; CanonicalAcl.ps1 33/56=58.93% (ByServer branch offline-untestable), Prerequisites.ps1 409/481=85.03%. Reviewed APPROVE. FINALIZATION COMPLETE: PENDING owner code review + PR. No commit (per owner request).

## Session 2026-08-15 (afternoon) — Coverage Refresh @ 100% Pass Rate

**Status:** ✅ COMPLETE

### Authoritative Measured Numbers (2026-08-15, Pester 5.9.0)

| Metric | Value |
|--------|-------|
| Unit tests | **1,220** (19 Unit.*.Tests.ps1 files) |
| Integration tests | **313** (7 Integration.*.Tests.ps1 files) |
| Automated total | **1,533** (1,220 + 313 = 1,533 ✅ confirmed) |
| Manual tests | **335** (authoritative per Joel) |
| Grand total | **1,868** (1,533 + 335) |
| Overall coverage | **89.65%** (14,651 / 16,343 commands — JaCoCo INSTRUCTION) |

### Per-File Coverage (6 key files)
| File | Covered | Total | % |
|------|---------|-------|---|
| Get-TierModelAuditRule.ps1 | 145 | 145 | **100%** |
| Get-TierModelAuditRuleFd.ps1 | 43 | 44 | **97.73%** |
| Test-TierModelAuditRule.ps1 | 186 | 189 | **98.41%** |
| New-TierModelAuditRule.ps1 | 122 | 145 | **84.14%** |
| Audit-TierModel.ps1 | 847 | 986 | **85.9%** |
| Deploy-TierModel.ps1 | 1854 | 2274 | **81.53%** |

All 6 files above 80% CI gate. No files below gate. ✅

### Key Facts
- Overall went from 85.96% → **89.65%** because the 64 pre-existing failures (v6 contamination) were suppressing coverage of dMSA/gMSA/MSA/GPOContent/CanonicalAcl code paths. Green suite = real coverage.
- Test file count: 19 Unit (not 20 — README had a stale "20 files" count).
- README was showing "~1,220" and "~313" estimates — replaced with exact numbers.
- Temp\ = absent (CLEAN) after all runs.

### Docs Updated
- `README.md`: Status line ⚠️→✅, test table exact counts, coverage 85.96%→89.65%, file count 20→19, per-cmdlet percentages refreshed.
- `docs/test-coverage.md`: Last measured date 2026-08-14→2026-08-15, overall 85.96%→89.65%, per-file rows updated for 6 key files.
- `docs/test-tag-matrix.md`: Already correct (AuditRule entries present), no changes needed.

### No commit per owner request. No test files edited.



**Problem:** Joel reported ~66 suite failures. Runner used dynamic "highest 5.x" logic → selected 5.9.0 correctly. Direct investigation confirmed 5.9.0 yields **TOTAL=1533 PASS=1533 FAIL=0**. Root cause of Joel's failures was Pester v6 leaking in on a prior run (same pattern as 2026-08-14 correction pass: 64 pre-existing failures attributed to v6 `Assert-MockCalled` removal). The dynamic "highest 5.x" logic itself was not the bug today, but Joel's directive is to hard-pin so future 5.x minor installs cannot silently take over.

**Fix:** `tests/Invoke-AllTests.ps1` — replaced dynamic highest-5.x selection with explicit `$KnownGoodPesterVersion = '5.9.0'` pin. Logic: exact version match first; if absent, fall back to highest 5.x with a loud warning; if no 5.x at all, hard error. Updated side-by-side warning message to say "incompatible with this test suite. Using pinned 5.9.0."

**Proof:** Runner prints `📋 Pester Version: 5.9.0`, `WARNING: Pester 6.0.0 is installed side-by-side; 6.x has breaking changes incompatible with this test suite. Using pinned 5.9.0.` Final count: **TOTAL=1533 PASS=1533 FAIL=0 SKIP=0**. Temp\ directory: False (clean after run).

**No commit per owner request. File edited: tests/Invoke-AllTests.ps1 ONLY.**

## Session 2026-08-15 — Pester v5 Pin — Deeper Fix (v2, afternoon)

**New problem discovered:** The morning fix handled Pester v6 as a PowerShell module but NOT as a .NET CLR assembly. Under pwsh 7.6.5, once any Pester 6.x command runs in a terminal session (or is triggered by auto-load), the Pester v6 CLR assembly locks into the AppDomain. Subsequent `Import-Module Pester -RequiredVersion 5.9.0 -Force` throws `"Assembly with same name is already loaded"` — this is the "busted terminal" Joel described. The morning `$KnownGoodPesterVersion` pin was insufficient for this scenario.

**Root cause of Joel's 66 failures:** Pester 6.0.0 auto-loaded by pwsh 7.6.5 (updated 2026-08-14) before `Invoke-AllTests.ps1` ran. v6 removed `Assert-MockCalled` and redesigned the mock engine — all pre-existing tests using v5 mock patterns fail. Zero failures from new auditing code.

**Fix (defence in depth — 3 layers added to Invoke-AllTests.ps1):**
1. **CLR Detection + Re-Spawn:** Check `[System.AppDomain]::CurrentDomain.GetAssemblies()` for Pester version ≥ 6. If found, re-invoke `pwsh -NoProfile -NonInteractive -File <self> @args` and `exit $LASTEXITCODE`. Clean child process has no pre-loaded Pester assembly. `-NoProfile` prevents profile from re-triggering v6 auto-load.
2. **`$PSModuleAutoLoadingPreference = 'None'`** during discovery/import — prevents implicit auto-load of highest-installed version (v6). Restored after import so test code can auto-load other modules.
3. **Hard post-import assertion:** `if ($loadedPester.Version.Major -ne 5) { throw "FATAL..." }` — aborts with clear message if layers 1+2 somehow fail.

**Adversarial proof:**
- Pre-loaded Pester 6.0.0 CLR in calling pwsh session → `Invoke-AllTests.ps1` → detected v6 CLR → re-spawned clean child → `📋 Pester Version: 5.9.0 / Major confirmed: 5` → **TOTAL=1533 PASS=1533 FAIL=0** in 3.33 min.
- Temp\ = False (clean).

**Key learning — CLR assembly vs PowerShell module:** `Remove-Module` only removes the PowerShell module wrapper. The .NET assembly (`Add-Type` or `Assembly.LoadFrom`) remains in the AppDomain for the process lifetime. The only remedy is a new process. Always check `[AppDomain]::CurrentDomain.GetAssemblies()` for version conflicts when mixing module versions in long-running terminals.

**OneDrive offline-pin (2026-08-15 follow-up):** Joel pinned PowerShell + WindowsPowerShell module dirs "Always keep on device." Result: import time went 0.54s → **0.50s** — essentially unchanged. OneDrive hydration was NEVER the bottleneck. The test execution itself is compute-bound (mocked AD/ACL calls, WinLAPS ~200s). Joel's reported "~20 min" local run was almost certainly a v6-contaminated run where failures and retry/output overhead ballooned the clock, OR a run with code coverage enabled. Post-fix (Pester 5.9.0, no coverage) the authoritative measured local runtime is **~4.0 minutes** (3.95–4.09 min across multiple Measure-Command runs).

**Authoritative local runtime going forward:**
- Baseline today: **~4.0 min / 1533 tests** (Pester 5.9.0, no coverage, post-OneDrive-pin)
- Expected growth: ~13s per 100 new tests
- At 2000 tests: ~4.9 min | At 3000 tests: ~6.9 min
- CI < 8 min includes JaCoCo coverage collection — local without coverage will always be faster.

**No commit per owner request. File edited: tests/Invoke-AllTests.ps1 ONLY.**

## Learnings

**2026-07-28 — BUG-008 & BUG-004 Lab Validation (this session):**

### Lab Config Facts
- Checkpoints actually on TierLab-DC01 (as of 2026-07-28): `DC-Promoted-Clean`, `WinLapsSchema`. No `WinLapsSchema-Ready` — that was created during BUG-002/005 session and is gone.
- `lab-config.json` lives in `.research/copilot-cli-hyperv-ad-lab/` (parent of `scripts/`), NOT inside `scripts/`. Pass `-ConfigPath` explicitly to helper scripts.
- WinLaps audit (Test-TierModelWinLapsAcl) is slow — each of the 7 delegations calls `Find-LapsADExtendedRights` which takes ~1 min per OU. Full audit: 8–10 min. Always use `-File` mode (not `-Command {}`); the former streams output; the latter buffers until completion.
- The `run-winlaps-audit.ps1` wrapper `Set-Location C:\TierModel; & .\Audit-TierModel.ps1 -PreferredDc DC01 -IncludeWinLaps` works reliably when executed via `& $pwsh -File`.

### Exact Function Signatures (re-confirmed on guest)
- `Test-TierModelWinLapsAcl -Config <object> -DomainController <string> [-Silent] [-SuppressSummary]`
- `Get-TierModelConfig` (no params) — loads from module-relative config
- `Audit-TierModel.ps1 -PreferredDc DC01 -IncludeWinLaps` (standalone WinLaps audit mode, no scope param needed)

### Pre-existing WinLapsSchema Checkpoint State (important: known false-positive pattern)
- After deploying TierModel on WinLapsSchema checkpoint, `Test-TierModelWinLapsAcl` reports `UnexpectedAcl` for:
  - `TIERLAB\Tier0Admins` on `OU=Tier 0 Member Servers` — root cause: `Tier0Admins` has a **GenericAll** ACE (non-inherited) on that OU from OU delegation. `Find-LapsADExtendedRights` expands GenericAll → effective LAPS rights holder. Config only expects Tier0ServerOperators there.
  - `TIERLAB\Tier1Admins` on `OU=Tier 1 Member Servers` — same root cause (GenericAll OU delegation ACE).
- These are NOT inherited from domain root or parent OUs — they are direct GenericAll ACEs set as part of the Tier Model's OU de

## Session 2026-08-14 — Beast Batch Complete + Pending Pester Tests (2026-08-14T18:49:54+08:00)

**Beast batch status (as of 2026-08-14T18:49:54+08:00):** ✅ COMPLETE
- Audit-TierModel.ps1 header/label cleanup (PSScriptAnalyzer clean, staged on DC01)
- Test-TierModelAuditRule.ps1 granular per-right output (lab-validated 3 scenarios, PSScriptAnalyzer clean, staged on DC01)
- Decisions merged; orchestration log written; inbox cleared

**Pending tasks (post-UAT + post-Storm docs):**
- Implement full Pester test suite for audit-script wiring (follow Phase 16 conventions)
- Fix Temp\ teardown in test cleanup blocks to ensure no temp files persist
- Integration testing timeline coordination with Storm + Beast

**BLOCKED ON:** Storm docs + Joel's manual UAT sign-off before final PR
[truncated summary]

## Session 2026-02-27 — v1.3.0 -EnableAuditing Pester Suite Complete

**Status:** ✅ COMPLETE — 1,533 automated tests / 0 failed. Overall docs-scope coverage 89.65% (was 88.74%).

### Deliverables
- Created `tests/Unit.AuditRuleOperations.Tests.ps1` (47 unit tests) covering all 4 new cmdlets + Get-TierModelConfig audit segment:
  - Get-TierModelAuditRule: ABSENT / PARTIAL / MULTI-ACE / already-converged / empty-config / error paths (SeSecurityPrivilegeDenied, SaclReadFailed, AuditRulePlanningFailed)
  - New-TierModelAuditRule: apply / idempotent (AlreadyConverged) / WhatIf / privilege throw / non-ConfigureAuditRule skip
  - Test-TierModelAuditRule: COMPLIANT / PARTIAL / ABSENT / MULTI-ACE / granular per-right findings / SACL-read-error / missing-config
  - Get-TierModelAuditRuleFd: delegation + re-stamp CorrelationId + AuditRuleFdPlanningFailed
  - Get-TierModelConfig: audit file present / absent / malformed-parse-warned
- Extended `tests/Integration.Audit.Tests.ps1` (+15 tests, tag AuditRule): standalone -EnableAuditing, scope-combination errors, FullDeployment consolidated report, COMPLIANT/DRIFT rows, combined -Include*+-EnableAuditing coverage, audit-failure catch paths, output-file generation.
- Extended `tests/Integration.Deploy.Tests.ps1` (+10 tests, tag AuditRule): -EnableAuditing scope validation, planning-mode (no event-log Y gate), apply-mode Y gate, FullDeployment Phase 11 Get-TierModelAuditRuleFd wiring.
- Fixed Temp\ teardown leak: added AfterAll cleanup (removing repo-root Temp\*_Mock.inf) to both Test-TierModelGPOContent Describe blocks in `tests/Unit.GpoOperations.Tests.ps1`.
- Version-drift fix: Integration.Module.Tests.ps1 + Unit.ModuleManifest.Tests.ps1 asserted 1.2.3 while manifest is 1.3.0 → updated to 1.3.0.

### Coverage (real, native command-count methodology)
- Get-TierModelAuditRule.ps1: 100% (145/145)
- Get-TierModelAuditRuleFd.ps1: 97.73% (43/44)
- Test-TierModelAuditRule.ps1: 98.41% (186/189)
- New-TierModelAuditRule.ps1: 84.14% (122/145)  [JaCoCo LINE 93.8%]
- Get-TierModelConfig.ps1: 94.87% (audit segment now exercised)
- Audit-TierModel.ps1: 73.1% → 85.9% (847/986) — GOAL >80% MET
- Deploy-TierModel.ps1: 81.53% (kept >81%)

### Key learnings (durable)
- **PIN PESTER 5.9.0** before every run: `Remove-Module Pester -Force -EA SilentlyContinue; Import-Module Pester -RequiredVersion 5.9.0 -Force`. Env has Pester 6.0.0 which auto-loads and breaks Assert-MockCalled/Should. Invoke-AllTests.ps1 pins it automatically.
- **Mock ACL pattern**: PSCustomObject with `_Aces` List[object] NoteProperty + ScriptMethods GetAuditRules/RemoveAuditRuleSpecific/AddAuditRule referencing `$this._Aces` (avoids GetNewClosure scope issues). Mock Get-Acl -ParameterFilter { $Audit }.
- **Helper funcs defined in a Describe body are NOT visible inside mock scriptblocks** when running scripts via `& $path`. Define them inside a `BeforeAll { function ... }` block.
- **9 canonical rights bits**: CreateChild=1, DeleteChild=2, Self=8, WriteProperty=32, DeleteTree=64, ExtendedRight=256, Delete=65536, WriteDacl=262144, WriteOwner=524288; ALL9=852331.
- **Get-TierModelAuditRuleFd quirk**: its `Get-Variable -Name 'script:CorrelationId'` never resolves (scope prefix in name), so Fd always re-stamps a fresh GUID — assert a valid GUID, not a specific value.
- Coverage doc uses **native Pester command counts** (not JaCoCo LINE); totals differ. Use native methodology to keep the All Files table self-consistent.
- Temp artifacts coverage-audit.xml / cov-native.csv are scratch — cleaned up at end.

## Session 2026-08-14 — v1.3.0 Pester Suite + Correction Pass (2026-08-14T20:xx+08:00)

**Correction of sub-agent's fabricated coverage numbers.** Re-ran actual Pester+JaCoCo and updated docs to real measurements.

### REAL measured numbers (JaCoCo XML + Pester command count, 2026-08-14)
- **Get-TierModelAuditRule.ps1: 100%** (106/106)
- **Get-TierModelAuditRuleFd.ps1: 100%** (28/28)
- **Test-TierModelAuditRule.ps1: 98.12%** (157/160)
- **New-TierModelAuditRule.ps1: 93.91%** (108/115)
- **Audit-TierModel.ps1: 88.19%** (605/686) — recovered from 73.1%, above 80% gate ✓
- **Deploy-TierModel.ps1: 85.14%** (1301/1528) — above 80% gate ✓
- **Get-TierModelConfig.ps1: 100%** (92/92) — audit segment fully covered
- **Overall Pester: 85.96%** (16,529 commands, 68 files)
- **Total tests: 1,533** (1,469 passing / 64 pre-existing failures unrelated to -EnableAuditing)

### Key correction: Do NOT use Assert-MockCalled with Pester v6
- Env runs **Pester v6.0.0** (not v5). `Assert-MockCalled` is removed in v6 — use `Should -Invoke` instead.
- The sub-agent's tests had 5 failures due to `Assert-MockCalled`. Fixed by replacing all with `Should -Invoke Set-Acl -ModuleName TierModel -Times N`.
- `Should -Invoke` with `-ModuleName` works exactly as `Assert-MockCalled` did.

### Pre-existing failures (64 total, NOT caused by -EnableAuditing)
- `Unit.GpoOperations.Tests.ps1`: 9 failures (Test-Path mock filter doesn't match Temp path)
- `Unit.DmsaAclOperations.Tests.ps1`: ~4 failures (type resolution issue)
- `Unit.GmsaAclOperations.Tests.ps1`: ~7 failures (same type resolution issue)
- `Unit.MsaAclOperations.Tests.ps1`: ~5 failures (same)
- `Unit.OuAclOperations.Tests.ps1`: ~15 failures (same pattern)
- `Unit.CanonicalAcl.Tests.ps1`: 4 failures (ByServer path offline)
- `Integration.WinLapsDeployment.Tests.ps1`: 1 failure (mock count mismatch)

### Narrative docs NOT touched (Storm's domain)
- docs/detailed-deployment-guide.md, docs/sentinel-monitoring.md, docs/faq.md, docs/index.md, docs/quick-deployment-guide.md — reverted sub-agent's unauthorized edits.

### Temp\ cleanup fix
Added `AfterAll` blocks to `tests/Unit.GpoOperations.Tests.ps1` to remove `Temp\*_Mock.inf` artifacts. Pre-existing GPO content test failures remain (Test-Path mock filter issue is separate).
