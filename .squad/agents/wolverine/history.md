# wolverine — History

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
- These are NOT inherited from domain root or parent OUs — they are direct GenericAll ACEs set as part of the Tier Model's OU delegation (Tier0Admins manages T0 Member Servers).
- **This is a potential false positive in the BUG-004 fix**: GenericAll OU delegations legitimately imply LAPS read access but are not the same as explicit LAPS read grants. Flagged for Beast to evaluate whether GenericAll holders should be excluded from UnexpectedAcl reporting.
- Mismatched count on clean WinLapsSchema post-deploy: **2** (these two OUs). Does not represent injected drift.

### BUG-008 Validation
- **PASS**. Both `prereqSplat` hashtables at Deploy-TierModel.ps1 L1773 and L2338 now include `DependenciesPath = (Join-Path $PSScriptRoot 'config\dependencies.json')`.
- RUN A (cwd=C:\): `"Validating prerequisites... Prerequisites validation passed."` — NO "Dependencies file not found" error.
- RUN B (cwd=C:\TierModel): identical prereq success.
- Script ended cleanly with `"Use -ConfirmApply to execute the deployment plan"` / `"Deploy script completed."` (expected — preview mode, no -ConfirmApply).

### BUG-004 Validation
- **PASS**. `Test-TierModelWinLapsAcl` now emits `Type='UnexpectedAcl'` / `ResourceType='LapsPermission'` when unexpected principals hold LAPS rights.
- Injection: `New-ADGroup ZZZ-WolverineDrift` + `Set-LapsADReadPasswordPermission -Identity <T1PawDN> -AllowedPrincipals TIERLAB\ZZZ-WolverineDrift`.
- Re-audit: `⚠️ Unexpected LAPS ACEs detected: TIERLAB\ZZZ-WolverineDrift` on `LAPS → Tier 1 PAW Devices`. Mismatched went 2→3.
- Finding object confirmed: `Type=UnexpectedAcl, ResourceType=LapsPermission, Details="Unexpected LAPS rights holders: TIERLAB\ZZZ-WolverineDrift"`.
- Control: Domain Admins, Enterprise Admins, SYSTEM, SELF, Administrators all pass `NOT flagged as UnexpectedAcl`.
- Cleanup: removed 5 LAPS ACEs via `Get-Acl/RemoveAccessRule/Set-Acl` on AD: drive. T1 PAW Devices returned COMPLIANT. Group deleted. Final Mismatched=2 (pre-existing only).
- `Set-LapsADReadPasswordPermission` has no removal flag — must use direct ACL manipulation via AD: provider to remove LAPS ACEs.

**Beast needed?** No. Both fixes validated without code-level blockers. One design observation raised (GenericAll false positive) for Beast's review — does not block the fix.
**2026-07-28 — UI Bugs BUG-002 & BUG-005 Full Campaign Verdict:**
- BUG-002: ✅ RESOLVED — Deploy-TierModel.ps1 L2022–2048 UserOnly block now emits 4 specific ❌ dependency errors; apply correctly blocked on dirty deps; zero AD writes on failure. Wolverine T1–T4: glyph+label proof (❌ = Red foreground). Cyclops corroboration: L2022–2048 error-accumulation gate and L638–645 prerequisites check match observed behavior.
- BUG-005: ✅ RESOLVED — Get-TierModelWinLapsAclFd.ps1 L196–202 planner correctly routes missing GPO to warnings (not errors) for FD scope; Deploy-TierModel.ps1 L1638–1642 preview gate allows plan to proceed (gate is if .Errors, not .Warnings); Phase 10 apply executes after Phase 5 GPO creation. Wolverine T5–T9: FD preview shows 7× yellow ⚠ (not red ❌); standalone -IncludeWinLaps shows 19× red ❌ (scope boundary). Cyclops corroboration: three-layer source confirmation (planner routing, preview gate, apply path regenerates fresh plan at execution time).
- Regressions: NONE — sibling scopes (GroupOnly, GposOnly, audit) all healthy; no contamination observed.
- Ancillary: BUG-006 candidate identified (pre-existing Test-TierModelPrerequisites relative-path default 'config/dependencies.json' fails unless CWD = C:\TierModel when called from FD+IncludeWinLaps or standalone -Include* blocks without explicit -DependenciesPath). Workaround: pwsh -WorkingDirectory 'C:\TierModel'. Severity: MEDIUM (real operational hazard, trivial fix = add Join-Path  to both callsites L1778 & L2353).
- Lab state: TierLab-DC01 fully deployed (31 OUs, 26 groups, 2 users, 146 GPOs, 7 LAPS GPOs), running, checkpoint WinLapsSchema-Ready created.
- Cyclops final verdict: APPROVE — both bugs safe to merge; no blockers.

### Lab Validation: UI Bugs BUG-002 & BUG-005 (2026-07-28)

**Deploy-Preview Validation Workflow on Hyper-V AD Lab:**
- Transport: PowerShell Direct via `New-PSSession -VMName TierLab-DC01 -Credential $cred` (VMBus, no network needed).
- Each PS Direct session runs WinPS 5.1 — always spawn `C:\Program Files\PowerShell\7\pwsh.exe` as a child process to run the TierModel module (requires PS7).
- Session state does NOT persist between separate PS tool calls; create and use sessions within a single invocation.
- Copy working tree host→guest with `Copy-Item -ToSession` then verify with SHA256 hash comparison; guest disk state persists between calls.
- Prerequisites gate: `Test-TierModelPrerequisites` picks the highest available Pester version (`Sort-Object Version -Descending | Select-Object -First 1`). Lab VM had Pester 6.0.0 installed; had to remove 6.0.0 & 5.9.0 from guest so 5.7.1 wins — deploy prereq then passed.

**⚠-vs-❌ Glyph/Label Technique for Proving Color Across Redirected Output:**
- ANSI color codes are stripped when PS output is captured/redirected. Color is provable only via the GLYPH+LABEL combo in source: `⚠` is emitted with `-ForegroundColor Yellow`; `❌` is emitted with `-ForegroundColor Red`.
- Set `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` in the WinPS 5.1 PS Direct session before spawning the child pwsh.exe so ⚠/❌ Unicode glyphs are captured faithfully (not mojibake).
- Save transcript to guest file with `-Encoding utf8`; read back with `Get-Content -Encoding UTF8`.
- In BUG-005: 7× `⚠ LAPS GPO ... not found - assuming it will be created by the GPO phase` confirmed Yellow-warning behavior. Zero `❌` LAPS errors confirmed Red-error was suppressed/removed.
- In BUG-002: 4× `❌ Required group/OU ... does not exist - create X first` confirmed the specific per-dependency errors are now emitted (were previously suppressed by the `-Silent` call).

**PASS/FAIL Outcomes:**
- **BUG-002 (UserOnly dependency errors) — PASS** (commit 32b748f, 2026-07-28): specific ❌ dependency items appear.
- **BUG-005 (WinLaps preview GPO warning) — PASS** (commit 32b748f, 2026-07-28): Phase 10 emits ⚠ not ❌ for missing GPOs.

---

**Older history archived to history-archive.md (2026-07-28).**

**Status:** ✅ FIXED — LOCAL only, no commit. Requested by Joel Platek.

**Bug:** `tests\Invoke-AllTests.ps1 -FailedOnly` hung in an interactive console at the WinLaps test.  
Root cause: two tests in `tests\Unit.WinLapsAclOperations.Tests.ps1` (lines 309–315) invoked  
`Get-TierModelWinLapsAcl` with a missing mandatory param inside `Should -Throw`. In CI (non-interactive),  
PowerShell throws → test passes. In an interactive host, PowerShell prompts → hangs forever.

**Fix:** Replaced both invocation-based tests with command-metadata tests that check  
`[System.Management.Automation.ParameterAttribute].Mandatory` directly — zero cmdlet invocation,  
no host can ever prompt, same semantic guarantee. Pattern used:
```powershell
$attr = (Get-Command Get-TierModelWinLapsAcl).Parameters['Config'].Attributes |
        Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
($attr.Mandatory -contains $true) | Should -BeTrue
```

**Sibling scan:** All other WinLaps cmdlet calls in the 3 WinLaps test files supply all mandatory params. No other anti-patterns found in WinLaps files. Non-WinLaps `Should -Throw` calls in existing test files all supply mandatory params and test business logic (not missing-param detection) — no changes needed.

**Verification:** Full suite 1401/0 (PASS/FAIL). `Invoke-AllTests.ps1 -FailedOnly` completed exit 0, no prompts.

---

## FEATURE COMPLETE: Windows LAPS T001–T021 (2026-07-16)

**Status:** ✅ SHIPPED — All tasks complete, committed, ready for Joel's UAT + release.

The Windows LAPS feature (T001–T021) is now complete and committed to feature/windows-laps branch:
- Beast (T001–T013): Implementation + audit cmdlet ✅
- Wolverine (T014–T020): Test suite (113 tests, 90.92% coverage, 1401/1401 green) ✅
- Storm (T021): Documentation (8 files, README metrics) ✅

Orchestration logs: 2026-07-16T09-34-10Z-wolverine.md and 2026-07-16T09-34-10Z-storm.md  
Session log: 2026-07-16T09-34-10Z-winlaps-feature-complete.md

Next gate: Joel's manual UAT, then PR merge, v1.2.0 release.

---

## Current: T014–T020 Follow-up Items — DONE (1401/1401 passing, 90.92%+ coverage)

**Status:** All 7 tasks (T014–T020) complete + follow-up items complete. Full test suite 1401 pass / 0 fail / 0 skip. No regressions. Overall coverage 90.92%+ (above 80% CI floor).

### 2026-07-16 — Follow-up: Version-Test Fixes + BUG-004 + Full-Green Confirmation

**Items completed:**
1. **Fixed 2 stale version-test assertions** (`1.1.0` → `1.2.0`):
   - `tests/Unit.ModuleManifest.Tests.ps1` line 41-42: updated both test title `'Has current version 1.2.0'` and assertion `Should -Be '1.2.0'`
   - `tests/Integration.Module.Tests.ps1` line ~35: `Should -Be '1.2.0'`
   - These were pre-existing failures caused by the intentional 1.2.0 bump; now resolved.

2. **UnexpectedAcl investigation + BUG-004:**
   - `Test-TierModelMsaAcl.ps1` line 343: ✅ emits `Type = 'UnexpectedAcl'` in code
   - `Test-TierModelGmsaAcl.ps1` line 343: ✅ emits `Type = 'UnexpectedAcl'` in code
   - `Test-TierModelDmsaAcl.ps1` line 353: ✅ emits `Type = 'UnexpectedAcl'` in code
   - `Test-TierModelWinLapsAcl.ps1` line 10: ❌ only in `.DESCRIPTION` doc-comment — code never emits it
   - **BUG-004 added** to `.research/known-bugs.md` — WinLaps-specific gap; MSA/gMSA/dMSA are correct.

3. **Full suite re-run:** 1401 pass / 0 fail / 0 skip — ✅ 100% green, no regressions.

---

## Previous: T014–T020 WinLaps Pester Tests — DONE (1399/1401 passing, 90.92% coverage)

**Status:** All 7 tasks (T014–T020) complete. Full test suite 1399 pass / 2 fail (pre-existing module version failures, NOT mine). Overall coverage 90.92% (above 80% CI floor). No regressions.

## Learnings

### 2026-07-16 — T014–T020 WinLaps Pester Tests (Deferred Unit/Integration Suite)

**Mission:** Author the full Windows LAPS unit and integration test suite (T014–T020) after Joel's manual UAT. All unit tests: mocked only, no live AD, CI-compatible.

#### Files Created/Modified
- **tests/helpers/ADStubs.ps1** — Added stubs: `Get-ADComputer` (AD block), `Get-GPRegistryValue`/`Set-GPRegistryValue` (GroupPolicy block), new LAPS block (`Find-LapsADExtendedRights`, `Set-LapsADComputerSelfPermission`, `Set-LapsADReadPasswordPermission`, `Set-LapsADResetPasswordPermission`) with in-memory LAPS module registration
- **tests/Unit.Prerequisites.Tests.ps1** — Added `Context "WinLaps Prerequisites (-IncludeWinLaps)"` block (T014, 12 tests)
- **tests/Unit.WinLapsAclOperations.Tests.ps1** — NEW file (T015–T018, T020, 84 tests)
- **tests/Integration.WinLapsDeployment.Tests.ps1** — NEW file (T019, 17 tests)

#### Final Coverage
| File | Commands | Covered | Missed | % |
|------|----------|---------|--------|---|
| Get-TierModelWinLapsAcl.ps1 | 546 | 506 | 40 | 92.7% |
| New-TierModelWinLapsAcl.ps1 | 187 | 162 | 25 | 86.6% |
| Get-TierModelWinLapsAclFd.ps1 | 462 | 404 | 58 | 87.4% |
| Test-TierModelWinLapsAcl.ps1 | 219 | 189 | 30 | 86.3% |
| Test-TierModelWinLapsDecryptor.ps1 | 207 | 169 | 38 | 81.6% |
| Test-TierModelPrerequisites.ps1 | 383 | 277 | 106 | 72.3% |
| **Overall Module** | 12,305 | 11,184 | 1,121 | **90.92%** |

#### Critical WinLaps Testing Knowledge

**`EnvironmentSnapshot` is a hashtable, NOT a PSCustomObject.** In Test-TierModelPrerequisites.ps1, the result's `EnvironmentSnapshot` field is initialized with `@{}`. Use `.ContainsKey('WinLapsSchemaPresent')` — NOT `.PSObject.Properties.Name -contains 'WinLapsSchemaPresent'`.

**`Find-LapsADExtendedRights` returning `$null` ≠ "permission missing".** Both planners/auditors check `if ($extendedRights)` before processing holders. When the mock returns `$null`, the code skips all read/reset checks entirely (no miss detected → result appears Compliant). To test "permission missing": mock to return `[PSCustomObject]@{ ExtendedRightHolders = @("SomeOtherGroup") }` — holders present but NOT the expected group.

**Doc-string comments trigger invariant false positives.** WinLaps cmdlets contain `<# ... never legacy (ms-Mcs-AdmPwd*, AdmPwd.PS) ... #>` in help text. Regex `'AdmPwd\.PS'` matches these. T020 invariant tests must filter out comment lines (lines starting with `#`) or check only for `Import-Module.*AdmPwd` / actual cmdlet invocation patterns.

**`Get-TierModelWinLapsAclFd` has no top-level `Converged` property.** Unlike the standalone planner, the FD variant returns `{Actions, Summary, Analysis, Errors, Warnings, DurationMs, CorrelationId}` — no `Converged`. Tests must not assert `.Converged` on FD results.

**Gate ordering in `Get-TierModelWinLapsAcl`.** Gates 1-3 (schema, LAPS module, DFL) return early. OU/group validation, Gate 4a (GPO, only if `$Config.gpos` present), Gate 4b (DC exclusion) all accumulate errors. Single final early-return if errors > 0 after Gate 4b.

**Outer `catch` blocks (catastrophic handlers) are unreachable via mocking.** All 5 cmdlets have a top-level `try { ... } catch { ... }` wrapping the entire function body. These handlers only trigger when an unexpected exception escapes ALL inner try/catch blocks. Cannot be exercised through mocking without modifying production code. Constitutes the primary source of the coverage gap (<100%).

**`Test-TierModelWinLapsDecryptor` Drift = Missing + Mismatched + Errors.** Unlike `Test-TierModelWinLapsAcl` where Drift = Missing + Mismatched only, the Decryptor audit includes `$errorCount` in drift.

**In-memory LAPS module stub is critical.** `Test-TierModelPrerequisites` does `Import-Module LAPS -EA Stop`, `Get-Module LAPS`, then `Get-Command $cmd -Module LAPS`. All three must succeed without real RSAT. ADStubs.ps1 now registers a `New-Module` in-memory LAPS module that exports all 3 required cmdlets.

**T019 tests at cmdlet level, not Deploy-TierModel.ps1.** Deploy-TierModel.ps1 is not in the CI coverage path (`modules/TierModel/*.psm1` + `public/*.ps1` only). Integration tests validate plan+apply pipeline directly via `Get-TierModelWinLapsAcl → New-TierModelWinLapsAcl` + real config JSON structure verification.

**Pre-existing module version failures.** `Integration.Module.Tests.ps1` and `Unit.ModuleManifest.Tests.ps1` expect module version `1.1.0` but actual is `1.2.0`. These are NOT from WinLaps work — need Beast to update version expectations or bump manifest.


**Mission:** Confirm Beast's fixes for the two bugs found in the 6-step smoke test.

**Result:** ✅ BOTH FIXED — zero regressions.

| Test | Bug A (SELF detection) | Bug B (.Type error) | Overall |
|------|------------------------|---------------------|---------|
| Standalone -IncludeWinLaps | ✅ ACL 7/7 COMPLIANT (was 0/7) | ✅ No error | ✅ 0 drift |
| Full -FullDeployment -IncludeWinLaps | ✅ ACL 7/7 COMPLIANT | ✅ No error | ✅ 379 checked, 100% compliant, 0 drift, 0 errors |

**Full audit breakdown:** OU 31, Group 26, User 2, OU ACL 101, GPO 146, ADMX 60, WinLaps ACL 7, WinLaps Decryptor 6 = 379 total. All zero drift.

**Lab state:** VM TierLab-DC01 running, deployed, compliant, AD-ready for Joel.

### 2026-07-16 — T013 WinLaps Audit Smoke Test (6-Step E2E)

**Mission:** Verify Beast's new WinLaps audit integration (T013) end-to-end against live lab — both Test-TierModelWinLapsAcl and NEW Test-TierModelWinLapsDecryptor, opt-in behavior, empty-box resilience, and drift detection.

**Result:** CONDITIONAL PASS — Decryptor audit (NEW code) is PERFECT. Two bugs found (1 new T013, 1 pre-existing).

#### Step Results

| Step | Description | Result |
|------|-------------|--------|
| 1 | Audit Joel's current deployed state | ✅ Ran clean. Decryptor 6/6 compliant. ACL: 7 missing SELF (INFORMATIONAL — pre-existing detection bug) |
| 2 | Empty-box "all missing" (WinLapsSchema, no tier model) | ✅ No crash. 7 ACL missing (6 OUs don't exist + DC missing perms). 6 decryptor "No GPO found" errors. Graceful handling. |
| 3 | Fresh deploy -FullDeployment -IncludeWinLaps | ✅ Applied: 681, Errors: 0. All 6 decryptors configured correctly. |
| 4a | Standalone -IncludeWinLaps audit | ⚠️ Decryptor 6/6 compliant. ACL: 7 missing SELF (Bug A — pre-existing). |
| 4b | Full -FullDeployment -IncludeWinLaps audit | ⚠️ Both sections present. Decryptor 6/6 compliant. Bug B found (line 787 .Type error). |
| 4c | Negative: -FullDeployment (no -IncludeWinLaps) | ✅ ZERO WinLaps/LAPS content in output. Opt-in confirmed. |
| 5 | Drift detection + restore | ✅ Correctly detected 1 MISMATCHED (Tier 0 PAWs: expected Tier0Admins, actual Domain Admins). Restored to 6/6 compliant. |
| 6 | Final state | ✅ VM running, AD responding, deployed + decryptors compliant. |

#### Decryptor Compliant Table (Steps 4a/5-restored)

| GPO | ADPasswordEncryptionPrincipal | Status |
|-----|-------------------------------|--------|
| *- Tier 0 PAWs Windows LAPS - Computer | TIERLAB\Tier0Admins | ✅ Compliant |
| *- Tier 0 Servers Windows LAPS - Computer | TIERLAB\Tier0ServerOperators | ✅ Compliant |
| *- Tier 1 PAWs Windows LAPS - Computer | TIERLAB\Tier1Admins | ✅ Compliant |
| *- Tier 1 Servers Windows LAPS - Computer | TIERLAB\Tier1ServerOperators | ✅ Compliant |
| *- Tier 2 PAWs Windows LAPS - Computer | TIERLAB\Tier2Admins | ✅ Compliant |
| *- Tier 2 EUD Windows LAPS - Computer | TIERLAB\Tier2DeviceOperators | ✅ Compliant |
| *- Tier 0 DCs Windows LAPS - Computer | (skipped — DC OU) | ✅ Correct |

#### Bugs Found

**Bug A (PRE-EXISTING, not T013):** `Test-TierModelWinLapsAcl` SELF detection uses `Find-LapsADExtendedRights` which does NOT include `NT AUTHORITY\SELF` in its `ExtendedRightHolders` output. The deploy planners correctly use `Get-Acl "AD:$ouDn"` (Bug 5b fix). The audit function was never updated. All 7 OUs falsely report ComputerSelfPermission as missing even though SELF was applied by deploy.
- **File:** `modules/TierModel/public/Test-TierModelWinLapsAcl.ps1` line 163
- **Repro:** Deploy -FullDeployment -IncludeWinLaps, then audit -IncludeWinLaps → 7 missing SELF
- **Fix:** Use `Get-Acl "AD:$ouDn"` to check for NT AUTHORITY\SELF ACEs with LAPS GUIDs, same as the deploy planners

**Bug B (NEW, T013):** `Audit-TierModel.ps1` line 787 accesses `.Type` on WinLaps Decryptor findings but those objects use `.Status` instead. The ACL audit findings have `.Type`; the decryptor findings have `.Status` (GpoName, Expected, Actual, Status). Non-terminating — audit continues and completes — but pollutes output with error text.
- **File:** `Audit-TierModel.ps1` line 787
- **Error text:** `The property 'Type' cannot be found on this object. Verify that the property exists.`
- **Repro:** Run `.\Audit-TierModel.ps1 -PreferredDc DC01 -FullDeployment -IncludeWinLaps`
- **Fix:** Guard the `.Type` filter with a property existence check, or normalize decryptor findings to include `.Type`

#### Lab State
- **VM:** TierLab-DC01 RUNNING, deployed + decryptors compliant, AD responding
- **Ready for Joel's UAT immediately**

### 2026-07-15 — Full Deploy Decryptor E2E Test (Run 8)

**Mission:** Prove the new ConfigureLapsDecryptor code actually edits 6 non-DC LAPS GPOs during a -FullDeployment -IncludeWinLaps run on a clean WinLapsSchema baseline.

**Result:** ✅ PASS — all 6 decryptor GPO registry values independently verified via Get-GPRegistryValue.

**Key Findings:**
- **Grand Total Applied:** 681 (baseline without WinLaps: 643; delta: +38)
- **WinLaps Phase Actions:** 7 SELF + 6 Read + 6 Reset + 6 ConfigureLapsDecryptor = 25 actions fired
- **Decryptor delta from Run 6 (no decryptor code):** 681 - 673 = +8 (6 decryptors + 2 additional R/R from EUD config simplification)
- **Idempotency:** Applied 0, Converged True — decryptors NOT re-written on 2nd run ✅
- **No errors:** Zero terminating errors, zero "property cannot be found" crashes, zero "cannot bind" failures
- **DC GPO correctly left alone:** ADPasswordEncryptionPrincipal NOT SET on DC DSRM GPO ✅
- **ADPasswordEncryptionEnabled preserved:** Still = 1 on all 6 GPOs (decryptor write did NOT clobber enable flag) ✅

**GPO Verification Table (all 7):**
| GPO | ADPasswordEncryptionPrincipal | Expected | Verdict |
|-----|-------------------------------|----------|---------|
| *- Tier 0 PAWs Windows LAPS - Computer | TIERLAB\Tier0Admins | TIERLAB\Tier0Admins | PASS |
| *- Tier 0 Servers Windows LAPS - Computer | TIERLAB\Tier0ServerOperators | TIERLAB\Tier0ServerOperators | PASS |
| *- Tier 1 PAWs Windows LAPS - Computer | TIERLAB\Tier1Admins | TIERLAB\Tier1Admins | PASS |
| *- Tier 1 Servers Windows LAPS - Computer | TIERLAB\Tier1ServerOperators | TIERLAB\Tier1ServerOperators | PASS |
| *- Tier 2 PAWs Windows LAPS - Computer | TIERLAB\Tier2Admins | TIERLAB\Tier2Admins | PASS |
| *- Tier 2 EUD Windows LAPS - Computer | TIERLAB\Tier2DeviceOperators | TIERLAB\Tier2DeviceOperators | PASS |
| *- Tier 0 DCs Windows LAPS - Computer | (NOT SET) | (NOT SET) | PASS |

**Lab Config Note:** lab-config.json is at `.research/copilot-cli-hyperv-ad-lab/lab-config.json` (not in the scripts/ subdirectory). Password: LabPass123!.

**Lab State:** VM restored to WinLapsSchema, AD responding, clean for Joel.

### Windows LAPS — All Bugs Fixed

| Bug | Issue | Fix |
|-----|-------|-----|
| 1 | $schemaDN undefined in WinLaps path | Add -or $IncludeWinLaps to init |
| 2 | Plan display missing identityreference | Branch on ResourceType='LapsPermission' |
| 3 | Groups not found (display names have spaces) | Use -Filter "Name -eq" |
| 4 | FD plan precomputed before groups exist | Regenerate at execution time |
| 5 | SELF false positive from inherited ACEs | Filter IsInherited=False + LAPS GUIDs |
| 5b | IsInherited mismatch PS7 (Get-ADOrganizationalUnit vs Get-Acl) | Use Get-Acl "AD:$ouDn" |

### Run 6 (Final) ✅

- Applied: 673 (baseline 643, +30 for root OU design)
- Idempotency: Converged True, Applied 0 on 2nd run ✅
- All 7 OUs delegated with correct principals
- EUD dual-principal verified (Tier2DeviceOperators + Tier2HelpdeskOperators)

### Run 7 (Standalone Bug Fix) ✅

- Verified fix for `.Applied cannot be found` crash
- 21 delegations applied, all lines printed, Converged: True
- Fix: Set-LapsAD* calls now end with `| Out-Null`

### Key Learning

Use Get-Acl "AD:$dn" not Get-ADOrganizationalUnit.nTSecurityDescriptor for IsInherited checks in PS7.

See history-archive.md for detailed Runs 1–7 notes. See .squad/decisions.md for ConfigureGPO integration details.

**Bug 3 (BLOCKING):** `Test-TierModelPrerequisites.ps1` Gate 5 (~line 638): `Get-ADGroup -Identity $groupName` matches by SAMAccountName only. Config stores display names with spaces ("Tier 0 Server Operators"); AD group SAMs are CamelCase without spaces ("Tier0ServerOperators"). Lookup fails for ALL 7 custom groups. "Domain Admins" works only because its SAM has a space (built-in group). **Fix:** use `-Filter "Name -eq '$groupName'"` — same pattern already used by `Get-TierModelWinLapsAclFd`. All groups ARE created in Phase 2 of base deploy; only the prereq check can't find them.

Error: `WINLAPS_GROUP_MISSING: Required group 'Tier 0 Server Operators' not found in AD. Deploy groups first.` (all 7 groups, same error)

#### Find-LapsADExtendedRights Output Shape — CONFIRMED
- Object type: `ExtendedRightsInfo`
- Properties: `ObjectDN` (string), `ExtendedRightHolders` (array of strings)
- **Format: `NETBIOS\sAMAccountName`** (e.g., `TIERLAB\Domain Admins`, `TIERLAB\Enterprise Admins`, `TIERLAB\Tier0Admins`)
- `AllComputerPermission` property NOT observed
- Note: inherited/default LAPS rights (Domain Admins, Enterprise Admins, NT AUTHORITY\SYSTEM) appear on all OUs after LAPS schema extended; tier-specific groups (e.g., Tier0Admins on Tier 0 Member Servers) appear via inherited computer-object read ACEs from base deploy OU ACL phase

#### Pre-existing LAPS ACLs — Corrected Finding
- Clean WinLapsSchema restore (before any deploy): only `NT AUTHORITY\SYSTEM` on Domain Controllers OU. Tier model OUs don't exist yet.
- Previous "4 pre-existing" finding was measuring POST-base-deploy inherited ACLs, not checkpoint state.
- After base deploy: Tier0Admins, Tier1Admins, Tier2DeviceOperators appear in `Find-LapsADExtendedRights` results for their respective OUs via inherited computer-read ACEs — not from WinLaps explicit delegation.

#### Test Results Summary
- **WinLaps Applied: 643** ❌ (Bug 3 blocked execution; delta = 0)
- **Bug 2 plan display: PASS** ✅ (21 `■ LAPS` lines, 0 errors)
- **Four-compose phases: PASS** ✅ (7→8→9→10 confirmed, Bug 2 regression clean)
- **Legacy LAPS refs: NONE** ✅ (0 ms-Mcs-AdmPwd / AdmPwd.PS across 728 lines)
- **Guards: PASS** ✅ (-OuOnly + -GroupOnly both throw correct error)
- **EUD dual-principal: BLOCKED** (WinLaps never applied)
- **Idempotency: BLOCKED** (same Bug 3)
- **Delegation verification: PARTIAL** — Find-LapsADExtendedRights shape confirmed; explicit WinLaps ACLs not landed

#### Plan Display Blank Principals (expected, not a bug)
When `-IncludeWinLaps` plan runs BEFORE base deploy (groups not yet in AD), `Get-TierModelWinLapsAclFd` resolves groups with `-Filter "Name -eq ..."` → groups not found → `allowedPrincipals = @()` → display shows `■ LAPS SetReadPasswordPermission:  on Tier 0 Member Servers` (blank). Expected. Four-compose plan (after base deploy) shows principals correctly: `TIERLAB\Tier0ServerOperators`.

#### Final Lab State
- **VM: Off, restored to WinLapsSchema** (no WinLaps ACLs applied)
- Output files: `wtest2-precheck.txt`, `wtest2-plan.txt`, `wtest2-winlaps.txt`, `wtest2-idem.txt`, `wtest2-delegation.txt`, `wtest2-compose.txt`, `wtest2-guards.txt`

### 2026-07-14 — WinLaps FINAL Run #6 (Bug 5b fixed, Root Delegation config change — GREEN)

#### Mission
Combined final re-test: Bug 5b fix (`Get-Acl "AD:$ouDn"` for SELF detection) + config change (Tier 0 Admins entry moved from `OU=Tier 0 PAW Devices` to `OU=Tier Model Administration` root). Expected: Applied > 643, idempotency Converged=True (all 3 types: Self/Read/Reset = 0).

#### Bug 5b Confirmed Fixed ✅
Idempotency 2nd run: **Applied: 0, Skipped: 0, Errors: 0, Converged: True**. `Windows LAPS ACL delegations already up to date`. SELF, READ, RESET all 0. Bug 5b is CLOSED. All bugs 1–5b now CLOSED.

#### Totals
- **Applied = 673** (baseline 643, delta **+30**)

#### Phase 10 (7 SELF applied, R/R as expected)
- 7/7 SELF applied including "Tier Model Administration" (new config entry) ✅
- Root OU Read/Reset: skipped (Tier0Admins already present via GenericAll from base deploy) ✅
- T1PAW/T2PAW Read/Reset: skipped (Tier1/2Admins already present) ✅
- DC, T0Members, T1Members, EUD: Read+Reset applied with correct principals ✅

#### Root Delegation Design Behavior
- Root OU (`OU=Tier Model Administration`): Tier0Admins already has `GenericAll` from base deploy's OU ACL phase
- WinLaps planner correctly detects this via `Find-LapsADExtendedRights` → skips explicit LAPS Read/Reset, adds SELF only
- `Find-LapsADExtendedRights` on T1PAW/T2PAW: does NOT show Tier0Admins (tool reports DIRECT holders only, not inherited)
- `Get-Acl` on T1PAW: Tier0Admins HAS inherited GenericAll (IsInherited=True) — functional access confirmed
- Tier0Admins can effectively read/reset LAPS on all PAW tiers via GenericAll inheritance

#### Delegation All 7 OUs ✅
All configured OUs have correct principals confirmed.

#### Final Lab State (Run 6)
- **VM: Off, restored to WinLapsSchema** (clean)
- All wt6-*.txt, wt6-*.ps1 cleaned up

### 2026-07-14 — WinLaps Re-Test #5 + Bug 5b Root Cause Diagnostic

#### Mission
Final re-test after Beast fixed Bug 5 (FD planner SELF false positive — now uses non-inherited + LAPS GUID filter). Expected: 7 SELF + 14 R/R = 21 WinLaps actions, Applied ≈ 664, then 0 on idempotency.

#### Bug 5 (FD Planner) Confirmed Fixed ✅
Phase 10 shows **7/7 Applied LAPS Self-Permission** lines. All OUs: SELF applied correctly. Bug 5 is CLOSED.

#### Totals
- **Applied = 677** (baseline 643, delta **+34**)
- 7 SELF + 10 R/R (T1PAW/T2PAW skipped as pre-existing) = 17 WinLaps ACL actions
- GPO-related actions (7 creates + 7 imports + links) account for the remaining delta

#### STOP CONDITION — Bug 5b: SELF Idempotency Still Fails

**Idempotency run (standalone, immediately after full deploy): 7 SELF applied again (not 0).**  
R/R: 0 planned/applied ✅ (correct — R/R idempotency via `Find-LapsADExtendedRights` works).

#### Bug 5b Root Cause Investigation (Same Session)

Ran targeted diagnostics on the VM to identify why `$selfExists = false` after SELF is applied:

1. **GUID comparison is correct.** `msLAPS-Password` → `25139f56-7148-409b-9ec7-251a558a4ddc`. ACE ObjectType = same GUID. Both `System.Guid`. `$_.ObjectType -in $lapsSchemaGUIDs` would succeed if the ACE reached that check.

2. **IdentityReference format is correct.** `$_.IdentityReference.Value -eq 'NT AUTHORITY\SELF'` matches via both `Get-ADOrganizationalUnit` and `Get-Acl` methods.

3. **Root cause confirmed: `IsInherited` flag mismatch.** In PowerShell 7, `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor` returns ACEs set by `Set-LapsADComputerSelfPermission` with `IsInherited = True`. Beast's `-not $_.IsInherited` filter excludes them. `Get-Acl "AD:$ouDn"` correctly returns the same ACEs with `IsInherited = False`.

```
# Via Get-ADOrganizationalUnit (PS7):  non-inherited SELF ACEs = 0  ← WRONG
# Via Get-Acl "AD:$dcDN"        (PS7):  non-inherited SELF ACEs = 2  ← CORRECT
```

This affects BOTH `Get-TierModelWinLapsAcl.ps1` (standalone) and `Get-TierModelWinLapsAclFd.ps1` (FD).

#### Delegation — All 7 OUs Confirmed ✅
All 7 OUs verified via `Find-LapsADExtendedRights`. All holders present. EUD dual-principal confirmed (Tier2DeviceOperators + Tier2HelpdeskOperators). T1PAW/T2PAW holders (Tier1Admins/Tier2Admins) confirmed present — correctly pre-existing from base deploy OU ACLs.

#### Final Lab State (Run 5 + Diag)
- **VM: Off, restored to WinLapsSchema** (clean — all temp files removed)
- wt5-run.ps1, wt5-*.txt all cleaned up

### 2026-07-14 — WinLaps Re-Test #4 (Bug 4 fixed, Bug 5 found)

#### Mission
Final re-test after Beast fixed Bug 4 (execution block re-generates FD plan fresh at apply time) and added SELF idempotency detection. Expected: Applied=664 (643+21), idempotency=0.

#### Bug 4 Confirmed Fixed ✅
Zero "AllowedPrincipals empty array" errors. Phase 10 applied Read+Reset for all 5 non-pre-existing OUs with correct principals. Bug 4 is **CLOSED**.

#### STOP CONDITION — Bug 5: SELF Detection False Positive

**Applied=663 (delta=+20, not +21). Phase 10: 0 SELF actions applied (all 7 skipped). Idempotency 2nd run: 7 SELF applied (not 0).**

**Bug 5 root cause:** `Get-TierModelWinLapsAclFd` SELF detection:
```powershell
$selfAces = @($ouWithAcl.nTSecurityDescriptor.Access | Where-Object {
    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF'
})
if ($selfAces.Count -ge 2) { $selfExists = $true }
```
Counts ANY NT AUTHORITY\SELF ACE. Every AD OU inherits ≥2 default SELF ACEs (computer self-write for dnsHostName, SPN, Personal Information, etc.) → `$selfExists = $true` for all 7 OUs → 0 SELF planned in FD path → SELF never applied by full deploy.

**Impact:**
- FD path: 0 SELF applied (silently skipped as false positive)
- Standalone path's idempotency run: correctly detects SELF as NOT present (standalone planner doesn't have false positive) → applies 7 SELF
- True idempotency not achieved: 2nd run = 7 SELF (not 0)

**Fix for Beast (Option A — simplest):** Remove the SELF detection block from `Get-TierModelWinLapsAclFd`. `Set-LapsADComputerSelfPermission` is idempotent at the LAPS module level — always plan/call it, no AD write if already set.  
**Fix for Beast (Option B — precise):** Filter `$selfAces` by ObjectType matching ms-LAPS-* schema attribute GUIDs, not any SELF ACE.

#### Phase 10 Full Deploy Results
- Domain Controllers: Read + Reset applied (TIERLAB\Domain Admins) ✅
- Tier 0 Member Servers: Read + Reset applied (TIERLAB\Tier0ServerOperators) ✅
- Tier 0 PAW Devices: Read + Reset applied (TIERLAB\Tier0Admins) ✅
- Tier 1 Member Servers: Read + Reset applied (TIERLAB\Tier1ServerOperators) ✅
- Tier 1 PAW Devices: Read + Reset SKIPPED (pre-existing, correct) ✅
- Tier 2 PAW Devices: Read + Reset SKIPPED (pre-existing, correct) ✅
- Tier 2 End-User Devices: Read + Reset applied (TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators) ✅
- ALL SELF: 0 applied (Bug 5 false positive) ❌

#### Idempotency Run
- Actions planned: 7 (all SELF)
- All 7 SELF applied (SELF was NOT set by full deploy due to Bug 5)
- R/R: 0 planned/applied (correctly detected as already-present) ✅
- Error at end: "The property 'Applied' cannot be found on this object" — pre-existing minor standalone result-object issue, non-blocking

#### Delegation Verification ✅
- Tier 0 Member Servers: TIERLAB\Tier0ServerOperators ✅
- Tier 2 End-User Devices: TIERLAB\Tier2DeviceOperators + TIERLAB\Tier2HelpdeskOperators ✅ (EUD DUAL-PRINCIPAL)

#### Final Lab State (Run 4)
- **VM: Off, restored to WinLapsSchema** (clean)
- Output files: wt4-deploy.txt, wt4-idem.txt, wt4-delegation.txt (retained for Joel)
- wt4-run.ps1, wt3-*.txt cleaned up

### 2026-07-14 — WinLaps Re-Test #3 (Bugs 1+2+3 fixed, Bug 4 found)

#### Mission
Run decisive execution test: Restore WinLapsSchema → full deploy with -IncludeWinLaps → assert Applied > 643 → idempotency → delegation spot-check. Bugs 1, 2, 3 confirmed fixed. Bug 4 found (BLOCKING for full deploy path).

#### Bugs 1, 2, 3 Confirmed Fixed ✅
- Bug 1 (schemaDN StrictMode): no VariableIsUndefined — `$schemaDN` now initialized in WinLaps path
- Bug 2 (plan display identityreference): 0 errors; `■ LAPS` lines render correctly with lapsOperation/ouName/allowedPrincipals
- Bug 3 (Gate 5 Get-ADGroup -Identity): prereq check passes; all 7 custom groups found via `-Filter "Name -eq '...'"`

#### STOP CONDITION — Bug 4 Found

**Bug 4 (BLOCKING for `-FullDeployment -IncludeWinLaps`):** `Get-TierModelWinLapsAclFd` called in planning phase before Phase 2 creates Tier model groups. `$winLapsFdPlan` stored with `allowedPrincipals = []` for all custom groups. Execution block re-uses this stale plan → `New-TierModelWinLapsAcl` calls `Set-LapsADReadPasswordPermission -AllowedPrincipals @()` → error.

**Error text:** `Cannot bind argument to parameter 'AllowedPrincipals' because it is an empty array.`  
**Affected:** 12 actions (6 non-DC OUs × Read + Reset)  
**Unaffected:** Domain Admins (built-in, pre-existing), 7 SELF permissions (no AllowedPrincipals param), 2 DC Read/Reset (Domain Admins resolves at plan time)

**Root cause code location (`Deploy-TierModel.ps1` ~line 1818):**
```powershell
$winLapsPlan = if (Get-Variable winLapsFdPlan -ErrorAction SilentlyContinue) { $winLapsFdPlan } else {
    Get-TierModelWinLapsAclFd ...  # ← never reached; $winLapsFdPlan always set from planning phase
}
```
`$winLapsFdPlan` is always set (planning phase runs first, groups not yet created) → `else` branch (fresh re-generate, works at execution time) never executes.

**Fix:** In the execution block (`if ($IncludeWinLaps)` inside `if ($ConfirmApply)`), always call `Get-TierModelWinLapsAclFd` fresh instead of re-using the pre-generated plan. Same pattern affects MSA/gMSA/dMSA.

#### T1PAW and T2PAW Pre-Existing LAPS Rights Clarified
`Find-LapsADExtendedRights` on Tier 1 PAW Devices and Tier 2 PAW Devices detects `Tier1Admins`/`Tier2Admins` as already holding extended LAPS rights — these are set by the base deploy's OU ACL phase via inherited computer-object ACEs. The standalone planner correctly counts them as already-present and skips them. This is NOT a WinLaps ACL delegation — it's a by-product of base deploy OU ACL management.

#### Totals
- **Applied = 661** (baseline 643 + delta **+18**)
- 7 SELF + DC Read + DC Reset = 9 WinLaps ACL actions applied by full deploy
- 12 Read/Reset failed (Bug 4)
- Delta vs expected (+21): missing 3 actions (T0PAW Read/Reset already pre-exist; actual gap is 12 failures − 9 pre-existing = 3 net shortfall)
- **Applied > 643 ✅** (core requirement met; exact expectation depends on pre-existing state)

#### Standalone Ran Successfully After Full Deploy
After full deploy (with 12 failed actions), standalone `-IncludeWinLaps -ConfirmApply` applied 15 remaining actions:
- Correctly SKIPPED: DC Read/Reset, T1PAW Read/Reset, T2PAW Read/Reset (detected as already-present)
- Applied: T0Members, T0PAW, T1Members, EUD (Read + Reset) = 8 actions; 7 SELF = 15 total

After combined run, all expected delegations confirmed in AD via `Find-LapsADExtendedRights`.

#### Delegation Verification ✅
- Domain Controllers: `TIERLAB\Domain Admins` ✅
- Tier 0 Member Servers: `TIERLAB\Tier0ServerOperators` ✅
- Tier 2 End-User Devices: `TIERLAB\Tier2DeviceOperators` + `TIERLAB\Tier2HelpdeskOperators` ✅ **EUD DUAL-PRINCIPAL CONFIRMED**
- SELF permissions: 6 ACEs per OU (ExtendedRight/WriteProperty) confirmed via Get-Acl

#### Find-LapsADExtendedRights Output Shape — FINAL CONFIRMED
- Object type: `ExtendedRightsInfo`
- `ExtendedRightHolders`: array of strings in `NETBIOS\sAMAccountName` format
- Example values: `TIERLAB\Domain Admins`, `TIERLAB\Enterprise Admins`, `NT AUTHORITY\SYSTEM`, `TIERLAB\Tier0ServerOperators`, `TIERLAB\Tier2HelpdeskOperators`
- `AllComputerPermission` NOT observed (SELF tracked separately via Get-Acl)
- Beast's idempotency check must compare against `NETBIOS\sAMAccountName` format (e.g., `TIERLAB\Tier0ServerOperators` not `Tier0ServerOperators`)

#### Idempotency Status
- **True idempotency (2nd run = 0 new actions) NOT confirmed** — cannot be verified until Bug 4 fixed and a clean complete full deploy runs first
- Read/Reset idempotency detection in standalone path: WORKS (correctly skips already-present)
- SELF idempotency: standalone always plans SELF; `Set-LapsADComputerSelfPermission` likely no-op at LAPS level when already set

#### Final Lab State (Run 3)
- **VM: Off, restored to WinLapsSchema** ✅ (confirmed via `(Get-VM TierLab-DC01).State = Off` and `Restore-VMCheckpoint` via checkpoint object)
- Output files retained for Joel's reference: `wt3-deploy.txt`, `wt3-idem.txt`, `wt3-delegation.txt`, `wt3-plan.txt`
- `wt3-run.ps1`, `wtest2-*.txt` cleaned up

### 2026-07-13 — WinLaps Lab Access + Test Strategy (feature/windows-laps)

#### Lab Access Procedure
- **Requires**: Elevated (Administrator) PowerShell on the Hyper-V host
- **VM**: `TierLab-DC01` — confirmed present (State: Off, Status: Operating normally)
- **Baseline checkpoint**: `DC-Promoted-Clean` (Standard, 2026-07-13 18:11)
- **WinLaps checkpoint**: `WinLapsSchema` (Standard, 2026-07-13 18:19, child of DC-Promoted-Clean)
  - Schema already extended by user; use this as the WinLaps retest baseline
  - Do NOT use DC-Promoted-Clean for WinLaps tests (schema not yet extended there)
- **Rollback to WinLapsSchema**:
  ```powershell
  Stop-VM -Name 'TierLab-DC01' -TurnOff -Force
  Restore-VMCheckpoint -VMName 'TierLab-DC01' -Name 'WinLapsSchema' -Confirm:$false
  Start-VM -Name 'TierLab-DC01'
  ```
- **Deploy with WinLaps**: `Start-LabAndDeploy.ps1 -AdditionalParams @('-IncludeWinLaps')`
- **Full clean reset**: `Reset-Lab.ps1` (restores to DC-Promoted-Clean)
- **Known issue**: NTDS StartPending after Standard checkpoint restore — handled automatically by Start-LabAndDeploy.ps1 and Reset-Lab.ps1
- **PS Direct access**: Requires `Invoke-Command -VMName 'TierLab-DC01' -Credential $cred`; credentials in lab-config.json; sessions do NOT persist across tool calls

#### How Totals Are Measured
- **Planning mode** (no -ConfirmApply): `Deploy-TierModel.ps1` prints `=== Deployment Plan ===` with lines:
  - `Action count: N` — `$deploymentPlan.TotalActions`
  - `Create count: N` — `$deploymentPlan.CreateCount`
- **Apply mode** (-ConfirmApply): prints `=== Deployment Results ===` with lines:
  - `Applied: N` — `$totalApplied` (sum of .Applied.Count + .Executed across all phase results)
  - `Converged: True/False`
- For unit tests: assert on `$plan.Summary.TotalActions` / `$plan.Summary.CreateActions` directly
- For integration totals test: capture stdout, grep for `^Action count: (\d+)` or `^Applied: (\d+)`
- TOTALS assertion: capture baseline (no -IncludeWinLaps), restore WinLapsSchema, run with -IncludeWinLaps → Applied count must be strictly greater

#### Test Plan Outline
- **19 tests total**: 15 unit + 4 integration
- **Files**: `tests/Unit.WinLapsDeployment.Tests.ps1`, `tests/Integration.WinLapsDeployment.Tests.ps1`
- **Key tests**: Schema hard stop (T01), OUs missing (T03), groups missing (T04), no legacy ms-Mcs-AdmPwd* (T06), idempotency (T07/T10/T18), WhatIf no writes (T08), totals increase (T16/T17), WinLaps after MSA/gMSA/dMSA (T14/T19)
- Full test plan written to `specs/003-win-laps/test-strategy.md`

#### Wave-2 Orchestration (2026-07-13T11:34:25Z)

- WinLaps specification phase consolidated by Scribe orchestration session
- All Wave-1 lab verification + test strategy findings merged into decisions.md (8 inbox files consolidated)
- Orchestration log created: .squad/orchestration-log/2026-07-13T11-34-25-UTC-wolverine.md
- Spec APPROVED by Professor X (9/9 constitution pass, test-first requirement verified)
- Lab harness ready for Phase 1 implementation: restore to WinLapsSchema checkpoint, run T001–T019 test stubs
- Awaiting Scribe handoff to begin Phase 1 test authoring

### 2026-07-14 — WinLaps Pre-Deployment Baseline + Lab Prep (feature/windows-laps)

#### Mission
Restore lab to WinLapsSchema checkpoint, confirm schema, run baseline deployment (no WinLaps), capture reference totals, restore clean state for WinLaps comparison test.

#### Schema Confirmation ✅
- Restored VM from WinLapsSchema checkpoint; confirmed 7 msLAPS- attributes present in schema NC
- Attributes: msLAPS-Password, msLAPS-EncryptedPassword, msLAPS-EncryptedPasswordHistory, msLAPS-EncryptedDSRMPassword, msLAPS-EncryptedDSRMPasswordHistory, msLAPS-CurrentPasswordVersion, msLAPS-PasswordExpirationTime
- WinLapsSchema checkpoint is confirmed schema-extended — safe baseline for WinLaps testing

#### Baseline Deployment Results (no -IncludeWinLaps)
- Script: `Start-LabAndDeploy.ps1 -ConfigPath <lab-config.json>` → `-FullDeployment -ConfirmApply`
- **Applied: 643** | Skipped: 4 | Errors: 0 | Duration: ~46.5s | **Converged: False**
- Planning "Action count"/"Create count" not captured (Start-LabAndDeploy.ps1 shows only last 40 output lines; planning section scrolls off)
- **Reference total for WinLaps comparison: Applied must be STRICTLY GREATER than 643**
- Expected delta: +21 (7 OUs × 3 per Beast's action model — verify against actual once T001–T012 land)

#### AD Readiness Note
- After WinLapsSchema standard checkpoint restore, AD readiness took >300s (PS Direct showed "credential invalid" for first ~60s, then NTDS Running but AD cmdlets not ready for ~3-5 more minutes)
- Use 600s timeout (already default in Start-LabAndDeploy.ps1)
- PS Direct connectivity confirmed via `Invoke-Command -VMName 'TierLab-DC01' -Credential $cred` — the 300s loop timed out before AD cmdlets were ready, but a retry immediately after confirmed AD was up

#### Final Lab State
- **VM: Off, restored to WinLapsSchema checkpoint** (clean, pre-baseline state)
- Inbox note written: `.squad/decisions/inbox/wolverine-winlaps-baseline.md`
- All PS sessions removed (no stray connections left open)

### 2026-07-14 — WinLaps Live Lab Test (feature/windows-laps)

#### Mission
Run full P1+P2 test matrix against Beast's T001–T012 implementation. Restore WinLapsSchema → run baseline (no WinLaps) → restore → run with -IncludeWinLaps → idempotency → delegation check → guards → 4-compose.

#### STOP CONDITION — Two Bugs Found

**Bug 1 (BLOCKING):** `$schemaDN` VariableIsUndefined in `Test-TierModelPrerequisites.ps1`
- Error: `Unexpected error during prerequisites check: The variable '$schemaDN' cannot be retrieved because it has not been set.`
- Root cause: `$schemaDN = $null` (line 367) is inside `if ($IncludeMsa -or $IncludeGmsa -or $IncludeDmsa)`. When ONLY `-IncludeWinLaps` is passed, that block is skipped. Line 515 then reads `$schemaDN` under `Set-StrictMode -Version Latest` → VariableIsUndefined.
- Affects: both `-FullDeployment -ConfirmApply -IncludeWinLaps` AND standalone `-IncludeWinLaps -ConfirmApply`.
- Planning mode is unaffected (execution-only code path).
- Fix location: `modules/TierModel/public/Test-TierModelPrerequisites.ps1` lines 366–367.

**Bug 2 (MINOR):** `Write-IncludeAclPlanActions` accesses `$_.Data.identityreference` which doesn't exist on WinLaps action objects (WinLaps uses `lapsOperation`, `allowedPrincipals`, `ouDn`). Only affects plan display output; action COUNT is correct.
- Fix location: `Deploy-TierModel.ps1`, function `Write-IncludeAclPlanActions` (~line 1038).

#### Test Results Summary
- **Baseline Applied: 643** ✅ (matches pre-code reference)
- **WinLaps Applied: 643** ❌ (Bug 1 blocked execution; delta = 0)
- **Legacy LAPS refs: NONE** ✅ (ms-Mcs-AdmPwd / AdmPwd.PS absent across 722 lines)
- **Guard -OuOnly: PASS** ✅ — error thrown correctly
- **Guard -GroupOnly: PASS** ✅ — error thrown correctly
- **Planning mode (Guard3): PASS** ✅ — 21 WinLaps actions planned on clean state
- **Four-compose planning: PASS** ✅ — phases 7→8→9→10 in order, no crash (Bug 2 display error in plan output but non-blocking)
- **Idempotency: BLOCKED** — same Bug 1

#### Find-LapsADExtendedRights Output Shape (partial)
- Could NOT run delegation verification (WinLaps never applied due to Bug 1)
- FD planning code (`Get-TierModelWinLapsAclFd`) confirmed that `Find-LapsADExtendedRights` returns objects with `ExtendedRightHolders` (plural) property containing string values — detected 4 pre-existing permissions from the WinLapsSchema checkpoint: Tier 1/2 PAW Devices had `readGroup` + `resetGroup` already set.
- Full output shape (property names, DOM\sam vs sam format) remains unconfirmed until WinLaps is actually applied.

#### WinLaps Planning Delta (fresh vs deployed state)
- On a fresh WinLapsSchema restore (OUs not yet deployed): `Get-TierModelWinLapsAclFd` plans **21 actions** (FD mode skips OU existence check, plans all)
- After base deploy with 4 pre-existing LAPS permissions in checkpoint: `Get-TierModelWinLapsAclFd` plans **17 actions** (correctly detects 4 existing via `Find-LapsADExtendedRights`)
- Pre-existing permissions: `Tier 1 Admins` read+reset on Tier 1 PAW Devices; `Tier 2 Admins` read+reset on Tier 2 PAW Devices — these are in the WinLapsSchema checkpoint

#### Final Lab State
- **VM: Off, restored to WinLapsSchema** (no WinLaps ACLs applied)
- Output files written to repo root: `wtest-base.txt`, `wtest-winlaps.txt`, `wtest-plan-winlaps.txt`, `wtest-idem.txt`, `wtest-guard1.txt`, `wtest-guard2.txt`, `wtest-compose.txt`
- Inbox written: `.squad/decisions/inbox/wolverine-winlaps-deploytest.md`

### 2026-07-15 — WinLaps Standalone Bug Fix Verification (Run 7)

#### Mission
Verify fix for standalone `-IncludeWinLaps -ConfirmApply` crash: `"The property 'Applied' cannot be found on this object."` Root cause: `New-TierModelWinLapsAcl` returned an ARRAY (21 stray cmdlet output objects + result object) instead of a single result object; Deploy-TierModel.ps1 accessed `$winLapsResult.Applied` under `Set-StrictMode -Version Latest` → VariableIsUndefined error. Fix: all three `Set-LapsAD*Permission` calls now end with `| Out-Null`.

#### Sequence Executed
1. `Restore-VMCheckpoint -VMName 'TierLab-DC01' -Name 'WinLapsSchema'` + `Start-VM`
2. Waited for AD readiness (PS Direct credential-invalid first ~60s, then NTDS Running, AD cmdlets ready ~120–180s)
3. Copied current repo to `C:\TierModel` on DC via PS Direct (398 files)
4. **Verified** `New-TierModelWinLapsAcl.ps1` on DC: all three `| Out-Null` confirmed present
5. Ran (a) `-OuOnly -ConfirmApply` → (b) `-GroupOnly -ConfirmApply` → (c) `-IncludeWinLaps -ConfirmApply`
6. Cleaned up run-a/b/c.ps1 temp scripts; removed PS sessions

#### Fix Verification ✅

**New-TierModelWinLapsAcl.ps1 on DC — `| Out-Null` confirmed:**
- `Set-LapsADComputerSelfPermission ... -ErrorAction Stop | Out-Null` ✅
- `Set-LapsADReadPasswordPermission ... -ErrorAction Stop | Out-Null` ✅
- `Set-LapsADResetPasswordPermission ... -ErrorAction Stop | Out-Null` ✅

#### Run (a) — OuOnly ✅
- 31 OUs created, no errors, Action count: 31, Converged: False (expected on first run)

#### Run (b) — GroupOnly ✅
- 26 groups created, no errors, Action count: 26, Converged: False (expected on first run)

#### Run (c) — IncludeWinLaps Standalone ✅ GREEN

**No `.Applied cannot be found` error** — FIX CONFIRMED.

Full output tail (from first Applied line through end of run):
```
Phase: Windows LAPS ACL Delegations
  Actions planned: 21
  ✅ Applied LAPS Self-Permission: Domain Controllers
  ✅ Applied LAPS Read-Permission: TIERLAB\Domain Admins on Domain Controllers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Domain Admins on Domain Controllers
  ✅ Applied LAPS Self-Permission: Tier 0 Member Servers
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
  ✅ Applied LAPS Self-Permission: Tier Model Administration
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier0Admins on Tier Model Administration
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier0Admins on Tier Model Administration
  ✅ Applied LAPS Self-Permission: Tier 1 Member Servers
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
  ✅ Applied LAPS Self-Permission: Tier 1 PAW Devices
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier1Admins on Tier 1 PAW Devices
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier1Admins on Tier 1 PAW Devices
  ✅ Applied LAPS Self-Permission: Tier 2 PAW Devices
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier2Admins on Tier 2 PAW Devices
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier2Admins on Tier 2 PAW Devices
  ✅ Applied LAPS Self-Permission: Tier 2 End-User Devices
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 End-User Devices
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 End-User Devices

=== Deployment Results ===
Applied: 21
Skipped: 0
Errors: 0
Duration: 11286.825ms
Converged: True

Deploy script completed.
```

**Key metrics:**
- Applied: **21** (all 7 OUs × 3 operations) ✅
- Errors: **0** ✅
- Converged: **True** (all operations succeeded, no errors) ✅
- `.Applied cannot be found` error: **ABSENT** ✅
- `=== Deployment Results ===` summary: **PRESENT** ✅

**All 21 delegations confirmed correct:**
- 7 SELF permissions (all OUs) ✅
- DC: Domain Admins Read + Reset ✅
- T0 Members: Tier0ServerOperators Read + Reset ✅
- Tier Model Administration (root): Tier0Admins Read + Reset ✅
- T1 Members: Tier1ServerOperators Read + Reset ✅
- T1 PAW: Tier1Admins Read + Reset ✅ (T1/T2 PAW now applied fresh — WinLapsSchema checkpoint did NOT pre-set them in this run)
- T2 PAW: Tier2Admins Read + Reset ✅
- EUD: Tier2DeviceOperators + Tier2HelpdeskOperators Read + Reset ✅ (dual-principal)

**Note on T1PAW/T2PAW behavior vs Run 6:** Previous Run 6 (full deploy before WinLaps) saw T1PAW/T2PAW Read/Reset skipped (pre-existing via GenericAll inherited from base deploy). This Run 7 standalone path (OuOnly + GroupOnly only, no full ACL phase) does NOT set the GenericAll inheritance, so WinLaps planner correctly applies Read+Reset fresh for all 7 OUs = 21 total. This is the expected standalone behavior.

#### Second Issue — None Found
Scrutinized full output (55 lines). No second error, no terminating error, no anomalous warnings. The standalone path prints "TierModel module loaded successfully." and "Prerequisites validation passed." twice (once at script start, once inside the standalone branch) — this is existing cosmetic behavior, not a new bug. No other anomalies detected.

#### Final Lab State
- **VM: RUNNING**, post-run (c) state: OUs created, Groups created, WinLaps ACLs applied
- Temp scripts (run-a/b/c.ps1) on DC: removed ✅
- PS sessions: all closed ✅
- To roll back to clean WinLapsSchema for fresh testing:
  ```powershell
  Stop-VM -Name 'TierLab-DC01' -TurnOff -Force -ErrorAction SilentlyContinue
  Restore-VMCheckpoint -VMName 'TierLab-DC01' -Name 'WinLapsSchema' -Confirm:$false
  Start-VM -Name 'TierLab-DC01'
  ```
- Inbox written: `.squad/decisions/inbox/wolverine-winlaps-applied-fix.md`

---

### Full Destructive Validation Campaign: BUG-002 + BUG-005 (2026-07-28)

**Branch:** fix/ui-bugs-002-005 @ 32b748f | **Requested by:** Joel Platek | **Full latitude granted**

#### Checkpoint / Baseline Strategy
- Starting state: `WinLapsSchema`-derived, fix tree already in `C:\TierModel`, Pester 5.7.1 only (no 5.9.0/6.0.0), AD clean, LAPS schema present.
- Created `WinLapsSchema-Ready` checkpoint at start of campaign. This snapshot has: fix tree deployed, Pester fixed, LAPS schema, clean AD. Used as the fast-iteration baseline for all destructive tests.
- Restored to `WinLapsSchema-Ready` before T4, T5/T6 (T6 inherited T5 state — clean), and T7 (with KDS root key re-added after each restore).
- KDS root key added (`Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))`) for T7 to enable gMSA/dMSA. Not needed for T1-T6.
- Preserved checkpoints: `DC-Promoted-Clean`, `WinLapsSchema`, `WinLapsSchema-Ready` (new, permanent).

#### Key Techniques
- **Stdin pipe for -ConfirmApply:** Script uses `Read-Host` for confirmation. Bypass in non-interactive session: `'Y' | & $pwsh -File ...`. Discovered when T2 first attempt returned "Deployment cancelled by user."
- **-WorkingDirectory for standalone prereq:** Both the "Optional Features" block inside FullDeployment+Include* and the standalone -Include* path call `Test-TierModelPrerequisites` without `-DependenciesPath`, defaulting to relative `config/dependencies.json`. Works only when process cwd = `C:\TierModel`. Fix: use `pwsh -WorkingDirectory 'C:\TierModel' -File ...`. **This is a pre-existing bug separate from BUG-002/005** — logged as a finding.
- **UTF-8 glyph capture:** `[Console]::OutputEncoding=[Text.Encoding]::UTF8` in the PS-Direct WinPS session before spawning pwsh child. Save transcript with `-Encoding utf8`; read with `Get-Content -Encoding UTF8`.
- **⚠ vs ❌ proof:** ANSI stripped in redirect. Proof via glyph+label: `⚠` = yellow warning (not blocking), `❌` = red error (blocking). In T5: 7× `⚠ LAPS GPO ... not found - assuming it will be created by the GPO phase`. In T6: 19× `❌` including 7 GPO-specific.

#### Test Results

**T1 [preview, clean] -UserOnly → PASS**
- 4× `❌` specific errors: PAWDomainJoin/Tier1ServerDomainJoin groups + Tier 0/1 Service Accounts OUs
- "Resolve all dependency errors before proceeding with User deployment" generic line present
- BUG-002 fix confirmed: specific per-dependency ❌ items visible (vs prior empty/generic)

**T2 [apply, clean] -UserOnly -ConfirmApply → PASS**
- Same 4× specific ❌ items shown after `Y` stdin confirmation
- Deployment proceeded past confirmation (`Proceeding with deployment execution...`) but stopped safely
- AD query: zero non-builtin user accounts created

**T3 [deps satisfied] OuOnly → GroupOnly → UserOnly → PASS**
- T3a OuOnly -ConfirmApply: 31 OUs created (✅)
- T3b GroupOnly -ConfirmApply: 26 groups created (✅)
- T3c UserOnly preview: 0 dependency errors, plan shows 4 actions (2 create + 2 update)
- T3d UserOnly -ConfirmApply: `svc-pawdomainjoin` + `svc-t1srvdomainjoin` created in correct OUs (AD query confirmed)

**T4 [parity] GroupOnly + GposOnly previews → PASS**
- GroupOnly: 3× `❌ Target OU ... does not exist - create OUs first`
- GposOnly: 40× `❌` (26 missing groups + 14 missing OUs)
- Sibling behavior unchanged by BUG-002 fix — no regression

**T5 [FD preview, clean+LAPS] FullDeployment+Includes preview → PASS**
- Phase 10: 7× `⚠ LAPS GPO ... not found - assuming it will be created by the GPO phase during FullDeployment.`
- 21 ACL actions planned
- Zero `❌` LAPS errors; "Windows LAPS planning errors" gate not triggered
- BUG-005 fix confirmed: ⚠ yellow warning path working

**T6 [standalone strict, clean+LAPS] -IncludeWinLaps alone → PASS**
- 19× `❌` errors: 7 missing OUs + 6 missing groups + 7 GPO errors (`Required GPO ... does not exist - create GPOs first`)
- Zero `⚠` yellow "will be created" leak
- Scope boundary confirmed: fix is restricted to FD planner (Get-TierModelWinLapsAclFd); standalone path (Get-TierModelWinLapsAcl) stays strict

**T7 [FD apply, clean+LAPS] FullDeployment+All+ConfirmApply → PASS**
- Workaround needed: `pwsh -WorkingDirectory C:\TierModel` for Optional Features prereq
- All 7 LAPS GPOs created (✅ Created GPO + Imported settings + Created GPO link per GPO)
- All 21 LAPS ACL delegations applied (7 SELF permissions + 6 Read-Permission + 5 Reset-Permission + OU decryptors)
- MSA + gMSA + dMSA ACL delegations also applied (KDS key pre-seeded)
- Applied: 705, Skipped: 4, Errors: 0

**T8 [FD preview after apply] Verify warnings conditional → PASS**
- Phase 10: 7× `✅ GPO Exists` + 6× `✅ LAPS Decryptor Exists`
- `✅ Windows LAPS ACL delegations already up to date`
- Zero `⚠` warnings — warning is genuinely conditional on absence, not unconditional noise

**T9 [audit] Full audit with IncludeWinLaps → PASS**
- Overall Status: ✅ COMPLIANT
- Total Checked: 379, Missing: 0, Drift: 0, Errors: 0, Compliance: 100%
- WinLaps ACL: 7 checked, 0 drift | WinLaps Decryptor: 6 checked, 0 drift
- All ADPasswordEncryptionPrincipal settings correct per GPO

#### Pre-Existing Bug Found (Separate from BUG-002/005)
`Test-TierModelPrerequisites` default `DependenciesPath = 'config/dependencies.json'` is relative. Both the Optional Features block in FD+Include* and the standalone -Include* block call it without an explicit path. Fails unless `$PWD = C:\TierModel`. Non-standalone paths use `Join-Path $PSScriptRoot 'config\dependencies.json'` (correct). Workaround: `pwsh -WorkingDirectory 'C:\TierModel'`.

#### Verdict
- **BUG-002: RESOLVED** — specific ❌ dependency errors shown in both preview and apply paths; safe blockage confirmed; fix vanishes when deps satisfied; no regression in siblings.
- **BUG-005: RESOLVED** — FD preview shows ⚠ yellow (not ❌ red); FD apply proceeds and LAPS ACLs applied; standalone path remains strict (scope boundary intact); warning conditional (disappears post-deploy); audit 100% compliant.
- **No regressions** in GroupOnly, GposOnly, or any other path.

#### Final Lab State
- VM: RUNNING, AD: responsive, domain: tierlab.internal
- Fully deployed Tier Model: 31 OUs, 26 groups, 2 users, 101 OU ACLs, 146 GPOs (incl. 7 LAPS GPOs), 60 ADMX files, all LAPS ACLs + decryptors applied, MSA/gMSA/dMSA ACLs applied
- KDS root key present (b816352d)
- Checkpoints: DC-Promoted-Clean (root), WinLapsSchema (LAPS schema), WinLapsSchema-Ready (fast-iteration baseline with fix tree + Pester fixed)

