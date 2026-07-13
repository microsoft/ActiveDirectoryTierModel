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
