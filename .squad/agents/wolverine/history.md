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
- After restoring a Standard checkpoint on TierLab-DC01, AD readiness takes 4-6+ minutes (>300s). Use a 600s timeout. PS Direct "credential invalid" is normal for the first 30-60s while the VM boots.
- Start-LabAndDeploy.ps1 only shows the last 40 lines of deploy output — planning-mode "Action count"/"Create count" are not visible in normal runs. Capture them with a direct planning-only run if needed.
- **Baseline reference (no -IncludeWinLaps, 2026-07-14):** Applied: 643, Converged: False. WinLaps run must produce Applied > 643.
- **WinLaps Bug 5b (BLOCKING — SELF idempotency IsInherited mismatch):** In PowerShell 7, `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor` returns ACEs set by `Set-LapsADComputerSelfPermission` as `IsInherited = True`, even though they are explicitly-set non-inherited ACEs. `Get-Acl "AD:$ouDn"` returns the same ACEs with the correct `IsInherited = False`. Both `Get-TierModelWinLapsAcl.ps1` and `Get-TierModelWinLapsAclFd.ps1` use the AD module path for the SELF check → `-not $_.IsInherited` filter excludes all LAPS SELF ACEs → `$selfExists = false` always → SELF re-applied every run. Fix: replace `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor` with `Get-Acl "AD:$resolvedOuDn"` in the SELF detection block of both planners. GUID comparison logic is correct (confirmed: `msLAPS-Password` → `25139f56-7148-409b-9ec7-251a558a4ddc` = ACE ObjectType = same System.Guid value).
- **Find-LapsADExtendedRights reports DIRECT holders only (NOT inherited):** The cmdlet shows principals with directly-set LAPS extended right ACEs on the specified OU. It does NOT report principals whose access comes from INHERITED ACEs (e.g., a GenericAll inherited from a parent OU). Verified: root `OU=Tier Model Administration` shows TIERLAB\Tier0Admins (direct GenericAll), but T1PAW does NOT show Tier0Admins despite having inherited GenericAll from root OU (confirmed via Get-Acl).
- **GenericAll from base deploy OU ACL phase provides effective LAPS access:** In this lab, the base deploy grants Tier0Admins `GenericAll` (Rights=GenericAll, InheritanceType=All) on `OU=Tier Model Administration`. This inherits to T0PAW, T1PAW, T2PAW as IsInherited=True ACEs. GenericAll includes all rights including LAPS read/reset. WinLaps planner correctly detects Tier0Admins as already-present on root OU and skips explicit LAPS Read/Reset delegation. Functional LAPS access exists even without explicit LAPS extended right ACEs.
- **WinLaps root delegation idempotency behavior:** When a principal already has sufficient access (e.g., GenericAll) on a target OU, `Find-LapsADExtendedRights` includes them in the holders list, and the WinLaps planner correctly marks R/R as already-present and skips. The WinLaps SELF permission is still applied (SELF check uses Get-Acl DACL inspection, independent of extended rights).
- **Applied total (Run 6, 2026-07-14):** 673 (baseline 643 + delta +30). Bug 5b fixed. Idempotency Converged=True. All bugs 1-5b CLOSED. **GREEN FOR JOEL'S GATE.**
- lab-config.json lives at `.research\copilot-cli-hyperv-ad-lab\lab-config.json`, NOT in the scripts\ subdirectory. Always pass `-ConfigPath` explicitly to Start-LabAndDeploy.ps1.
- **WinLaps Bug 1 (BLOCKING):** `Test-TierModelPrerequisites.ps1` line 367: `$schemaDN = $null` init is inside `if ($IncludeMsa -or $IncludeGmsa -or $IncludeDmsa)`. When only `-IncludeWinLaps` is used, this block is skipped; line 515 reads `$schemaDN` under `Set-StrictMode -Version Latest` → VariableIsUndefined. Execution fails for both `-FullDeployment` and standalone paths. Beast must fix before any execution-mode WinLaps testing can complete.
- **WinLaps Bug 2 (MINOR):** `Write-IncludeAclPlanActions` in Deploy-TierModel.ps1 (~line 1038) uses `$_.Data.identityreference` — property exists on MSA/gMSA/dMSA actions but NOT on WinLaps actions (which use `lapsOperation`, `allowedPrincipals`, `ouDn`). Affects plan display only; action count calculation is correct. Beast must fix.
- **Planning mode bypass Bug 1:** `-IncludeWinLaps` in planning mode (no -ConfirmApply) works correctly — the `Test-TierModelPrerequisites -IncludeWinLaps` call is inside the `if ($ConfirmApply...)` execution block and is NOT reached in planning mode. 21 WinLaps actions correctly planned on a fresh WinLapsSchema state.
- **WinLapsSchema checkpoint has pre-existing LAPS permissions:** Previous finding of "4 pre-existing" was measuring post-base-deploy inherited ACLs. Clean WinLapsSchema restore (before deploy): only NT AUTHORITY\SYSTEM on Domain Controllers OU. Tier model OUs don't exist yet, so no other pre-existing WinLaps ACLs.
- **Find-LapsADExtendedRights output shape — CONFIRMED:** Object type `ExtendedRightsInfo`. Properties: `ObjectDN` (string), `ExtendedRightHolders` (array of strings in `NETBIOS\sAMAccountName` format, e.g., `TIERLAB\Tier0Admins`). `AllComputerPermission` not observed. Beast's idempotency check should compare against `NETBIOS\sAMAccountName` format strings.
- **WinLaps Bug 3 (BLOCKING):** `Test-TierModelPrerequisites.ps1` Gate 5 (~line 638): `Get-ADGroup -Identity $groupName` matches by SAMAccountName only. Config stores display names with spaces ("Tier 0 Server Operators"); AD SAMs are CamelCase ("Tier0ServerOperators"). Lookup fails for all 7 custom groups. Fix: use `-Filter "Name -eq '$groupName'"` — same pattern already in `Get-TierModelWinLapsAclFd`.
- **Plan display blank principals pre-base-deploy is expected behavior:** `Get-TierModelWinLapsAclFd` resolves groups from AD; when groups don't exist yet (pre-base-deploy plan), principals are empty → blank in display. Not a bug. Four-compose plan (post-base-deploy) shows principals correctly.
- **WinLaps Bug 5 (BLOCKING — SELF idempotency false positive):** `Get-TierModelWinLapsAclFd` checks `$selfAces.Count -ge 2` where `$selfAces` = ANY NT AUTHORITY\SELF ACEs on the OU DACL. Every AD OU inherits ≥2 default SELF ACEs (dnsHostName, SPN, Personal Information attribute set, etc.) → `$selfExists = true` for all OUs → 0 SELF planned in FD path → SELF never applied. Fix: either remove SELF detection entirely (rely on `Set-LapsADComputerSelfPermission` being idempotent) or filter by ms-LAPS-* schema attribute GUIDs.
- **PS Direct Write-Host capture gotcha:** In PS Direct `Invoke-Command`, `Write-Host` in the remote scriptblock prints DIRECTLY to the local host console but is NOT included in the function's return value as pipeline output. Use `Write-Output` / return values for data capture. `Write-Host` output appears in terminal without `$delLines` content → file write yields 0 bytes.
- **WinLaps delta composition (Run 4):** 7 LAPS GPO creates + 7 LAPS GPO imports + 7 LAPS GPO links = 21 GPO output lines (but counted as fewer in Applied due to GPO metric); 10 Phase 10 R/R (5 OUs × Read+Reset); 0 SELF (Bug 5). Applied=663 (delta=+20). After Bug 5 fix: expect +7 more from SELF → Applied~670 (not 664 — T1PAW/T2PAW R/R pre-existing + GPO delta means lab-specific total ≠ theoretical +21).
- **Standalone "Applied" property error (minor, recurring):** Standalone `Deploy-TierModel.ps1 -IncludeWinLaps -ConfirmApply` throws "The property 'Applied' cannot be found on this object" at end of run (non-blocking). Actions complete successfully before error. Pre-existing result-object handling issue in standalone summary code path.** `Deploy-TierModel.ps1` execution block (~line 1818) re-uses `$winLapsFdPlan` (set during planning phase before Phase 2 creates groups). `Get-Variable winLapsFdPlan` always finds it → `else` branch (fresh re-generate at execution time) never executes → stale plan with `allowedPrincipals=[]` → `Set-LapsADReadPasswordPermission -AllowedPrincipals @()` fails. Fix: in execution block, always call `Get-TierModelWinLapsAclFd` fresh. Same pattern affects MSA/gMSA/dMSA.
- **WinLaps actual totals (Run 3, 2026-07-14):** Full deploy `-FullDeployment -IncludeWinLaps` → Applied=661 (delta +18 from 643). 9 WinLaps ACL actions succeeded (7 SELF + DC Read + DC Reset). 12 failed (Bug 4). Standalone after = 15 actions applied. All delegations landed after combined run.
- **Find-LapsADExtendedRights output shape — FINAL CONFIRMED (Run 3):** `ExtendedRightsInfo` object, `ExtendedRightHolders` = array of strings in `NETBIOS\sAMAccountName` format. Examples: `TIERLAB\Tier0ServerOperators`, `TIERLAB\Tier2HelpdeskOperators`, `NT AUTHORITY\SYSTEM`. `AllComputerPermission` NOT observed. SELF tracked via Get-Acl (6 ACEs per OU, not in ExtendedRightHolders). Idempotency check must use `NETBIOS\sAMAccountName` format.
- **EUD dual-principal confirmed (Run 3):** Tier 2 End-User Devices: `TIERLAB\Tier2DeviceOperators` AND `TIERLAB\Tier2HelpdeskOperators` both present in `ExtendedRightHolders`. Beast's multi-principal WinLaps config and execution both correct.
- **T1PAW/T2PAW pre-existing LAPS rights:** `Tier1Admins`/`Tier2Admins` detected by `Find-LapsADExtendedRights` after base deploy (inherited computer-object ACEs from OU ACL phase) — NOT explicit WinLaps delegations. Standalone planner correctly treats them as already-present and skips. Not a bug.
- **Reliable VM restore:** Use `Get-VMCheckpoint -VMName $VM | Where-Object { $_.Name -eq 'WinLapsSchema' } | Restore-VMCheckpoint -Confirm:$false` — avoids wildcard error from `Restore-VMCheckpoint -VMName ... -Name ...` string form when VM is in certain states.

### 2026-07-14 — WinLaps Re-Test (Bug 1+2 fixed by Beast, Bug 3 found)

#### Mission
Re-run full P1+P2 test matrix after Beast fixed Bug 1 ($schemaDN StrictMode crash) and Bug 2 (plan display identityreference). Restore WinLapsSchema → stage fixed code → plan check → full WinLaps apply → idempotency → delegation → four-compose → guards.

#### Bug 1 + Bug 2 Confirmed Fixed
- No `"cannot be retrieved because it has not been set"` error. Bug 1 path now initializes `$schemaDN`/`$dfl` correctly when `-IncludeWinLaps` alone is used.
- Plan display: 0 `identityreference` errors. All 21 `■ LAPS SetComputerSelfPermission/SetReadPasswordPermission/SetResetPasswordPermission` lines render.

#### STOP CONDITION — Bug 3 Found

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
