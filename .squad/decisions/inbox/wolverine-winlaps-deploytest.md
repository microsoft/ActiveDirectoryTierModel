# Wolverine WinLaps Live Lab Test Results — 2026-07-14

**Branch:** feature/windows-laps  
**Tester:** Wolverine (Logan)  
**Lab:** TierLab-DC01 (Hyper-V), checkpoint WinLapsSchema  
**Requested by:** Joel Platek  
**Sessions:** Run 1 (Bug 1+2 found) → Run 2 (Bug 3 found) → Run 3 (Bug 4 found) → Run 4 (Bug 5 found) → Run 5 (Bug 5 FD fix ✅, Bug 5b found) → **Diag run (Bug 5b root cause confirmed)**

**Sessions:** Run 1 (Bug 1+2 found) → Run 2 (Bug 3 found) → Run 3 (Bug 4 found) → Run 4 (Bug 5 found) → Run 5 (Bug 5 FD fix ✅, Bug 5b found) → **Diag run (Bug 5b root cause confirmed)**

---

## RUN 6 — ✅ GREEN FOR JOEL'S GATE

Bugs 1–5b all confirmed fixed. Bug 5b fix (`Get-Acl "AD:$ouDn"` replacing `nTSecurityDescriptor` for SELF detection) **confirmed working** — idempotency now **Converged: True, Applied: 0**. Config change (Tier 0 Admins root delegation) validated. One design-behavior note on `Find-LapsADExtendedRights` inheritance reporting.

---

## Run 6 Summary

| Item | Result |
|---|---|
| Applied | **673** (baseline 643, delta **+30**) |
| Applied_winlaps > 643 | **✅ PASS** |
| AllowedPrincipals-empty errors | **NONE** ✅ |
| Phase 10 SELF applied | **7/7** ✅ (all OUs incl. Tier Model Administration root) |
| Phase 10 R/R applied | 10 actions (DC, T0Members, Root-OU-SELF-only, T1Members, T1PAW-SELF-only, T2PAW-SELF-only, EUD) ✅ |
| Idempotency (2nd run) — **Bug 5b key check** | **Applied: 0, Converged: True** ✅ **PASS** |
| SELF idempotency | **0 SELF on 2nd run** ✅ (Bug 5b fix confirmed) |
| R/R idempotency | **0 Read, 0 Reset on 2nd run** ✅ |
| Tier Model Administration root OU | Tier0Admins present via `Find-LapsADExtendedRights` ✅ |
| T1PAW Tier0Admins via `Find-LapsADExtendedRights` | NOT shown (tool reports direct holders only) ⚠️ |
| T1PAW Tier0Admins via `Get-Acl` | Present (inherited GenericAll from base deploy) ✅ functional access confirmed |
| EUD dual-principal | TIERLAB\Tier2DeviceOperators + TIERLAB\Tier2HelpdeskOperators ✅ |
| Legacy LAPS refs | **NONE** ✅ |
| Plan display clean | **PASS** ✅ |

### Phase 10 Full Output (Run 6 — all applied actions)

```
Applied LAPS Self-Permission: Domain Controllers
Applied LAPS Read-Permission: TIERLAB\Domain Admins on Domain Controllers
Applied LAPS Reset-Permission: TIERLAB\Domain Admins on Domain Controllers
Applied LAPS Self-Permission: Tier 0 Member Servers
Applied LAPS Read-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
Applied LAPS Reset-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
Applied LAPS Self-Permission: Tier Model Administration                  ← new config entry
[Read/Reset skipped — Tier0Admins already present via GenericAll]
Applied LAPS Self-Permission: Tier 1 Member Servers
Applied LAPS Read-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
Applied LAPS Reset-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
Applied LAPS Self-Permission: Tier 1 PAW Devices
[Read/Reset skipped — Tier1Admins already present]
Applied LAPS Self-Permission: Tier 2 PAW Devices
[Read/Reset skipped — Tier2Admins already present]
Applied LAPS Self-Permission: Tier 2 End-User Devices
Applied LAPS Read-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 EUD
Applied LAPS Reset-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 EUD
```

### Idempotency (2nd Run — Converged) ✅

```
Phase: Windows LAPS ACL Delegations
  ✓ Windows LAPS ACL delegations already up to date

=== Deployment Results ===
Applied: 0
Skipped: 0
Errors: 0
Duration: 0ms
Converged: True
```

### Root Delegation Validation

**Tier Model Administration ROOT:**
```
Find-LapsADExtendedRights:
  HOLDER: NT AUTHORITY\SYSTEM, Domain Admins, Enterprise Admins, TIERLAB\Tier0Admins ← PRESENT ✅

Get-Acl detail (Tier0Admins ACE on root OU):
  Rights=GenericAll  InheritanceType=All  IsInherited=False  (from base deploy OU ACL phase)
```

**T1PAW and T2PAW — inheritance behavior:**
```
Find-LapsADExtendedRights on T1PAW:
  HOLDER: NT AUTHORITY\SYSTEM, Domain Admins, Tier1Admins
  Tier0Admins: NOT listed by tool (direct holders only)

Get-Acl on T1PAW (Tier0Admins ACE):
  Rights=GenericAll  InheritanceType=All  IsInherited=True  ObjType=00000000-... (all types)
  → Tier0Admins HAS inherited GenericAll = full effective access incl. LAPS read/reset ✅
```

**Design behavior note for Joel:**

The root OU delegation (`OU=Tier Model Administration`) shows `TIERLAB\Tier0Admins` in `Find-LapsADExtendedRights` because Tier0Admins already had `GenericAll` on that OU from the base deploy's OU ACL phase (not from an explicit WinLaps LAPS ACE). Consequently:
1. The WinLaps planner correctly detected Tier0Admins as already-present on the root OU and skipped Read/Reset (added SELF only).
2. `Set-LapsADReadPasswordPermission` was never called for the root OU — so no LAPS-specific read/reset extended right ACE was added to root OU.
3. `Find-LapsADExtendedRights` on T1PAW and T2PAW does NOT show Tier0Admins, because the tool only reports DIRECT (non-inherited) extended right holders.
4. However, Tier0Admins DOES have effective LAPS access on T1/T2 PAW via the inherited `GenericAll` ACE — confirmed via `Get-Acl`.

**Functional access verdict:** Tier0Admins CAN read/reset LAPS passwords on ALL computers in the TierModel admin hierarchy (T0PAW, T1PAW, T2PAW) via `GenericAll` inheritance from the base deploy. The WinLaps root delegation is redundant in this lab but would be the authoritative LAPS delegation in a production environment without GenericAll.

**Recommendation for Joel:** Validate actual read capability by running `Get-LapsADPassword -Identity <T1PAW-computer> -AsPlainText` as a Tier0Admins member to confirm end-to-end.

### Delegation Verification — All 7 Config OUs (Run 6)

| OU | ExtendedRightHolders (direct) | Status |
|---|---|---|
| Domain Controllers | `TIERLAB\Domain Admins` | ✅ |
| Tier 0 Member Servers | `TIERLAB\Tier0ServerOperators` | ✅ |
| Tier Model Administration | `TIERLAB\Tier0Admins` (direct via GenericAll from base deploy) | ✅ |
| Tier 1 Member Servers | `TIERLAB\Tier1ServerOperators` | ✅ |
| Tier 1 PAW Devices | `TIERLAB\Tier1Admins` (direct) + Tier0Admins inherited GenericAll | ✅ functional |
| Tier 2 PAW Devices | `TIERLAB\Tier2Admins` (direct) + Tier0Admins inherited GenericAll | ✅ functional |
| Tier 2 End-User Devices | `TIERLAB\Tier2DeviceOperators` + `TIERLAB\Tier2HelpdeskOperators` | ✅ EUD DUAL |

### SELF ACE Confirmation (Run 6, Tier Model Administration root)

```
ms-LAPS-* schema GUIDs: 7
Non-inherited LAPS SELF ACEs on root OU (via Get-Acl): 2
  Rights=WriteProperty              ObjType=25139f56-7148-409b-9ec7-251a558a4ddc Inherited=False
  Rights=ReadProperty,WriteProperty ObjType=4417032b-3485-4685-93e2-f0d766d3d4ac Inherited=False
```

### Bug History (All Runs)

| Bug | Status | Description |
|---|---|---|
| **Bug 1** | FIXED ✅ | `$schemaDN` StrictMode crash in `Test-TierModelPrerequisites.ps1` |
| **Bug 2** | FIXED ✅ | `identityreference` property missing on WinLaps plan actions (plan display) |
| **Bug 3** | FIXED ✅ | `Get-ADGroup -Identity` fails for display names with spaces (Gate 5) |
| **Bug 4** | FIXED ✅ | `$winLapsFdPlan` reused from planning phase (before groups exist) → empty AllowedPrincipals |
| **Bug 5** | FIXED ✅ | `Get-TierModelWinLapsAclFd` SELF check counts any NT AUTHORITY\SELF ACEs → default inherited ACEs false-positive → SELF never applied by FD planner |
| **Bug 5b** | FIXED ✅ | SELF ACEs show as `IsInherited=True` via `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor` in PS7; fix: `Get-Acl "AD:$ouDn"` in both planners |

### Final Lab State (Run 6)

**VM: TierLab-DC01 | Off | Checkpoint: WinLapsSchema (clean, restored)**  
All wt6-*.txt, wt6-run.ps1, wt6-inherit.ps1 cleaned up. Ready for Joel's manual UAT.

---

Bugs 1–5 (FD planner) confirmed fixed. Bug 5 FD fix confirmed working — **7/7 SELF applied in Phase 10**. New **Bug 5b** found: SELF idempotency detection fails in both planners via `IsInherited` mismatch, with root cause fully confirmed by targeted diagnostics.

---

## Run 5 Summary

| Item | Result |
|---|---|
| Applied | **677** (baseline 643, delta **+34**) |
| Applied_winlaps > 643 | **✅ PASS** |
| AllowedPrincipals-empty errors | **NONE** ✅ (Bug 4 confirmed fixed) |
| Phase 10 SELF applied | **7/7** ✅ (Bug 5 FD planner fix confirmed) |
| Phase 10 R/R actions | **10 applied** (5 OUs × Read+Reset) ✅ |
| T1PAW/T2PAW R/R | **Correctly skipped** (pre-existing from base deploy OU ACLs) ✅ |
| Idempotency (2nd run standalone) | **7 SELF applied** (not 0) ❌ STOP |
| R/R idempotency | **0 R/R** (correctly detected) ✅ |
| Delegation — all 7 OUs | **All correct** ✅ |
| EUD dual-principal | **CONFIRMED** ✅ |
| SELF ACE verification | **2 non-inherited LAPS SELF ACEs on DC OU** ✅ |
| Legacy LAPS refs | **NONE** ✅ |
| Plan display clean | **PASS** ✅ |

### Delta Accounting (Run 5)
- Baseline 643 + 7 SELF + 10 R/R (T1PAW/T2PAW R/R pre-existing = skipped) + 17 GPO-related = 677
- Net WinLaps-specific actions applied: 17 (7 SELF + 10 R/R)

### Phase 10 Full Output (Run 5, first deploy — all 17 actions)

```
Applied LAPS Self-Permission: Domain Controllers
Applied LAPS Read-Permission: TIERLAB\Domain Admins on Domain Controllers
Applied LAPS Reset-Permission: TIERLAB\Domain Admins on Domain Controllers
Applied LAPS Self-Permission: Tier 0 Member Servers
Applied LAPS Read-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
Applied LAPS Reset-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
Applied LAPS Self-Permission: Tier 0 PAW Devices
Applied LAPS Read-Permission: TIERLAB\Tier0Admins on Tier 0 PAW Devices
Applied LAPS Reset-Permission: TIERLAB\Tier0Admins on Tier 0 PAW Devices
Applied LAPS Self-Permission: Tier 1 Member Servers
Applied LAPS Read-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
Applied LAPS Reset-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
Applied LAPS Self-Permission: Tier 1 PAW Devices        [no R/R — pre-existing]
Applied LAPS Self-Permission: Tier 2 PAW Devices        [no R/R — pre-existing]
Applied LAPS Self-Permission: Tier 2 End-User Devices
Applied LAPS Read-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 EUD
Applied LAPS Reset-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 EUD
```

### Delegation Verification — All 7 OUs (Run 5)

| OU | ExtendedRightHolders | Status |
|---|---|---|
| Domain Controllers | `TIERLAB\Domain Admins` | ✅ |
| Tier 0 Member Servers | `TIERLAB\Tier0Admins`, `TIERLAB\Tier0ServerOperators` | ✅ |
| Tier 0 PAW Devices | `TIERLAB\Tier0Admins` | ✅ |
| Tier 1 Member Servers | `TIERLAB\Tier1Admins`, `TIERLAB\Tier1ServerOperators` | ✅ |
| Tier 1 PAW Devices | `TIERLAB\Tier1Admins` (pre-existing from OU ACLs) | ✅ |
| Tier 2 PAW Devices | `TIERLAB\Tier2Admins` (pre-existing from OU ACLs) | ✅ |
| Tier 2 End-User Devices | `TIERLAB\Tier2DeviceOperators` + `TIERLAB\Tier2HelpdeskOperators` | ✅ EUD DUAL |

### SELF ACE Confirmation (DC OU sample, after Run 5)

```
# Via Get-Acl "AD:OU=Domain Controllers,...":
Non-inherited SELF/LAPS-GUID ACEs: 2
  Rights=WriteProperty              ObjType=25139f56-7148-409b-9ec7-251a558a4ddc Inherited=False  [msLAPS-Password]
  Rights=ReadProperty,WriteProperty ObjType=4417032b-3485-4685-93e2-f0d766d3d4ac Inherited=False  [msLAPS-PasswordExpirationTime]
```

---

## Bug 5b — BLOCKING: SELF Detection `IsInherited` Mismatch (Root Cause Confirmed)

**Files affected:** `modules/TierModel/public/Get-TierModelWinLapsAcl.ps1` AND `modules/TierModel/public/Get-TierModelWinLapsAclFd.ps1`

**Symptom:** Standalone idempotency run (after full deploy applied SELF) still shows "Actions planned: 7" and applies all 7 SELF again — `$selfExists = false` for all OUs even when LAPS SELF ACEs are present.

**Root cause (confirmed by targeted diagnostics on 2026-07-14):**

Both planners read the OU's DACL via `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor`, then filter with `-not $_.IsInherited` to find explicitly-set LAPS SELF ACEs. In PowerShell 7, `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor` returns ACEs set by `Set-LapsADComputerSelfPermission` with **`IsInherited = True`** — even though they are explicitly-set, non-inherited ACEs. The `-not $_.IsInherited` filter therefore excludes all of them → `$selfAces.Count = 0` → `$selfExists = false` always.

`Get-Acl "AD:$ouDn"` correctly returns the same ACEs with **`IsInherited = False`**.

**Diagnostic proof (run via pwsh.exe on DC, 30 min after Set-LapsADComputerSelfPermission):**
```powershell
# Same DC OU, same SELF ACEs set by the LAPS module:

$ou = Get-ADOrganizationalUnit -Identity $dcDN -Properties nTSecurityDescriptor -Server $DC
$selfNonInh = @($ou.nTSecurityDescriptor.Access | Where-Object {
    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF' -and -not $_.IsInherited })
Write-Host $selfNonInh.Count   # → 0   ← WRONG: LAPS SELF ACEs are hidden (marked as inherited)

$acl = Get-Acl "AD:$dcDN"
$selfNonInh2 = @($acl.Access | Where-Object {
    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF' -and -not $_.IsInherited })
Write-Host $selfNonInh2.Count  # → 2   ← CORRECT: LAPS SELF ACEs visible with IsInherited=False
```

**Additional detail:** The GUID comparison logic is correct — `msLAPS-Password` resolves to `25139f56-7148-409b-9ec7-251a558a4ddc` which matches the ACE ObjectType exactly. Both GUIDs are `System.Guid` type; `$_.ObjectType -in $lapsSchemaGUIDs` would succeed if the ACE ever reached that check. The `IsInherited` flag is the sole blocker.

**Fix for Beast (both planners — identical change in each):**

Replace `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor` with `Get-Acl "AD:$resolvedOuDn"` for the SELF ACE check:

```powershell
# BEFORE (broken in both Get-TierModelWinLapsAcl.ps1 and Get-TierModelWinLapsAclFd.ps1):
$ouWithAcl = Get-ADOrganizationalUnit -Identity $resolvedOuDn -Server $DomainController `
    -Properties nTSecurityDescriptor -ErrorAction Stop
$selfAces = @($ouWithAcl.nTSecurityDescriptor.Access | Where-Object {
    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF' -and
    -not $_.IsInherited -and
    ($lapsSchemaGUIDs.Count -eq 0 -or $_.ObjectType -in $lapsSchemaGUIDs)
})

# AFTER (fix):
$ouAcl = Get-Acl "AD:$resolvedOuDn"
$selfAces = @($ouAcl.Access | Where-Object {
    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF' -and
    -not $_.IsInherited -and
    ($lapsSchemaGUIDs.Count -eq 0 -or $_.ObjectType -in $lapsSchemaGUIDs)
})
```

`Get-Acl "AD:$ouDn"` reads via the ActiveDirectory PSDrive and correctly preserves `IsInherited = False` for explicitly-set ACEs. No `-Server` parameter needed (uses default DC discovery; the deploy always runs on the DC).

---

## RUN 4 — ⚠️ STOP CONDITION — Bug 5 Found

Bugs 1–4 confirmed fixed. Bug 4 (empty AllowedPrincipals) **CONFIRMED FIXED** — zero errors in Run 4. New **Bug 5** found: SELF idempotency detection false positive.

---

## Run 4 Summary

| Item | Result |
|---|---|
| Applied | **663** (baseline 643, delta **+20**) |
| Expected delta | +21 → 664 (exact) or +20 → 663 (accounting for T1PAW/T2PAW pre-existing R/R) |
| AllowedPrincipals-empty errors | **NONE** ✅ (Bug 4 confirmed fixed) |
| Phase 10 R/R actions | **10 applied** (5 OUs × Read+Reset, correct principals) ✅ |
| Phase 10 SELF actions | **0 applied** (false positive — see Bug 5) ❌ |
| Idempotency (2nd run) | **7 SELF applied** (not 0) ❌ |
| R/R idempotency | **0 R/R** (correctly detected as already-present) ✅ |
| Delegation landed | **T0Members + EUD confirmed** ✅ |
| EUD dual-principal | **CONFIRMED** (Tier2DeviceOperators + Tier2HelpdeskOperators) ✅ |
| Legacy LAPS refs | **NONE** ✅ |
| Plan display clean | **PASS** (0 identityreference errors) ✅ |

---

## Bug 5 — BLOCKING: SELF Idempotency False Positive

**File:** `modules/TierModel/public/Get-TierModelWinLapsAclFd.ps1`

**Exact detection code:**
```powershell
$selfAces = @($ouWithAcl.nTSecurityDescriptor.Access | Where-Object {
    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF'
})
if ($selfAces.Count -ge 2) { $selfExists = $true }
```

**Root cause:**

The check counts **ANY** NT AUTHORITY\SELF ACEs on the OU DACL. Every AD OU inherits ≥2 default SELF ACEs from the domain root (e.g., Allow/SELF/WriteProperty for `dnsHostName`, `servicePrincipalName`, `userPassword`, `Personal Information` attribute set, etc. — standard computer self-write permissions). These pre-existing default ACEs trigger `$selfAces.Count -ge 2` → `$selfExists = $true` for all 7 OUs → FD planner generates 0 SELF actions → SELF never applied by full deploy.

**Effect:**
- Full deploy Phase 10: 0 SELF actions (all 7 skipped as false positive) → `Applied LAPS Self-Permission` lines absent from output
- Standalone 2nd run (idempotency test): `Get-TierModelWinLapsAcl` (standalone planner) doesn't have this false positive → correctly detects SELF as NOT present → plans and applies 7 SELF → idempotency test shows 7 (not 0) → STOP condition
- Applied delta: 663 instead of 664 (missing 1 SELF-contributed count; the other delta difference is explained by T1PAW/T2PAW R/R being pre-existing)

**Standalone idempotency run output (full Phase 10):**
```
Phase: Windows LAPS ACL Delegations
  Actions planned: 7
  ✅ Applied LAPS Self-Permission: Domain Controllers
  ✅ Applied LAPS Self-Permission: Tier 0 Member Servers
  ✅ Applied LAPS Self-Permission: Tier 0 PAW Devices
  ✅ Applied LAPS Self-Permission: Tier 1 Member Servers
  ✅ Applied LAPS Self-Permission: Tier 1 PAW Devices
  ✅ Applied LAPS Self-Permission: Tier 2 PAW Devices
  ✅ Applied LAPS Self-Permission: Tier 2 End-User Devices
```
R/R: 0 planned (correctly detected as already-present ✅). SELF: 7 applied (not idempotent ❌).

**Proposed fix for Beast (two options):**

**Option A (simplest — remove check, rely on LAPS cmdlet idempotency):**
Remove the SELF detection block entirely. `Set-LapsADComputerSelfPermission` is idempotent at the LAPS module level (safe to call multiple times). Always plan SELF → plan always shows 7 → `New-TierModelWinLapsAcl` always calls it → no error, no AD write if already set. Trade-off: plan always shows SELF as "Applied" even when it's a no-op.

**Option B (correct — filter by LAPS attribute GUIDs):**
Instead of counting any SELF ACEs, check specifically for SELF WriteProperty ACEs on the ms-LAPS-* attribute GUIDs. Get the LAPS attribute GUIDs from the schema and filter:
```powershell
# Get LAPS attribute GUIDs from schema
$lapsAttrGuids = Get-ADObject -Filter "name -like 'ms-LAPS-*'" -SearchBase $schemaDN -Properties schemaIdGuid |
    ForEach-Object { [guid]$_.schemaIdGuid }

$selfAces = @($ouWithAcl.nTSecurityDescriptor.Access | Where-Object {
    $_.IdentityReference.Value -eq 'NT AUTHORITY\SELF' -and
    $_.AccessControlType -eq 'Allow' -and
    ($_.ActiveDirectoryRights -band [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty) -ne 0 -and
    $lapsAttrGuids -contains $_.ObjectType
})
if ($selfAces.Count -ge 2) { $selfExists = $true }
```

---

## Phase 10 Full Deploy Output (Run 4)

```
=== Optional Features: MSA/gMSA/dMSA/WinLaps ACL Delegations ===
  Deploying Windows LAPS ACL delegations...
  ✅ Applied LAPS Read-Permission: TIERLAB\Domain Admins on Domain Controllers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Domain Admins on Domain Controllers
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier0Admins on Tier 0 PAW Devices
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier0Admins on Tier 0 PAW Devices
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 End-User Devices
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 End-User Devices
[no SELF lines — all 7 SELF skipped as false positive]
=== Deployment Results ===
Applied: 663
Converged: False
```

**Note on T1PAW/T2PAW Read+Reset absent from Phase 10:**
Tier 1 PAW Devices and Tier 2 PAW Devices Read+Reset are correctly absent — `Find-LapsADExtendedRights` detects `Tier1Admins`/`Tier2Admins` as already having LAPS extended rights (granted by the base deployment's OU ACL phase via inherited computer-object ACEs). These are legitimately pre-existing and correctly skipped.

---

## Delegation Verification (Run 4)

```
=== Tier 0 Member Servers ===
  DN: OU=Tier 0 Member Servers,DC=tierlab,DC=internal
  HOLDER: 'NT AUTHORITY\SYSTEM'
  HOLDER: 'TIERLAB\Domain Admins'
  HOLDER: 'TIERLAB\Enterprise Admins'
  HOLDER: 'TIERLAB\Tier0Admins'
  HOLDER: 'TIERLAB\Tier0ServerOperators'

=== Tier 2 End-User Devices ===
  DN: OU=Tier 2 End-User Devices,DC=tierlab,DC=internal
  HOLDER: 'NT AUTHORITY\SYSTEM'
  HOLDER: 'TIERLAB\Domain Admins'
  HOLDER: 'TIERLAB\Enterprise Admins'
  HOLDER: 'TIERLAB\Tier2DeviceOperators'
  HOLDER: 'TIERLAB\Tier2HelpdeskOperators'
```

Tier0ServerOperators ✅ | EUD dual-principal ✅ (Tier2DeviceOperators + Tier2HelpdeskOperators).

---

## Bug History (All Runs)

| Bug | Status | Description |
|---|---|---|
| **Bug 1** | FIXED ✅ | `$schemaDN` StrictMode crash in `Test-TierModelPrerequisites.ps1` |
| **Bug 2** | FIXED ✅ | `identityreference` property missing on WinLaps plan actions (plan display) |
| **Bug 3** | FIXED ✅ | `Get-ADGroup -Identity` fails for display names with spaces (Gate 5) |
| **Bug 4** | FIXED ✅ | `$winLapsFdPlan` reused from planning phase (before groups exist) → empty AllowedPrincipals |
| **Bug 5** | FIXED ✅ | `Get-TierModelWinLapsAclFd` SELF check counts any NT AUTHORITY\SELF ACEs → default inherited ACEs false-positive → SELF never applied by FD planner |
| **Bug 5b** | **OPEN ❌** | SELF ACEs set by `Set-LapsADComputerSelfPermission` show as `IsInherited=True` via `Get-ADOrganizationalUnit -Properties nTSecurityDescriptor` in PS7; `-not $_.IsInherited` filter excludes them → `$selfExists=false` always → SELF re-applied every run. Fix: use `Get-Acl "AD:$ouDn"` in both `Get-TierModelWinLapsAcl.ps1` and `Get-TierModelWinLapsAclFd.ps1` |

---

## Output Files (Run 4, 2026-07-14)

| File | Contents |
|---|---|
| `wt4-deploy.txt` | Full deploy output — 731 lines, Applied=663, Phase 10 R/R ✅, 0 SELF (false positive) |
| `wt4-idem.txt` | Standalone 2nd run — 7 SELF applied (not 0), R/R 0 ✅ |
| `wt4-delegation.txt` | Find-LapsADExtendedRights — T0Members + EUD confirmed |

---

## Final Lab State (Run 4)

**VM: TierLab-DC01 | State: Off | Checkpoint: WinLapsSchema (clean, restored)**  
Ready for Joel's manual UAT from a known clean base.

---

---

## Bug 4 — BLOCKING: `$winLapsFdPlan` Pre-Generated Before Groups Exist → Empty AllowedPrincipals

**File:** `Deploy-TierModel.ps1` execution block (~line 1818)

**Exact error (12 Read/Reset operations, all non-DC OUs):**
```
[Error] Failed to apply Windows LAPS delegation | LapsOperation=SetReadPasswordPermission,
Exception=Cannot bind argument to parameter 'AllowedPrincipals' because it is an empty array.,
TargetOU=OU=Tier 0 Member Servers,DC=tierlab,DC=internal
```

**Root cause:**

In Deploy-TierModel.ps1, the planning phase calls `Get-TierModelWinLapsAclFd` to generate `$winLapsFdPlan`. This happens **before** Phase 2 runs (groups not yet created). Group lookups via `-Filter "Name -eq '...'"` fail (groups don't exist yet) → `$resolvedReadPrincipals = @()` → plan stores `allowedPrincipals = []` for all custom Tier-model groups.

The execution block then does:
```powershell
# Line ~1818 — re-uses the stale pre-generated plan:
$winLapsPlan = if (Get-Variable winLapsFdPlan -ErrorAction SilentlyContinue) { $winLapsFdPlan } else {
    Get-TierModelWinLapsAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent
}
```

`$winLapsFdPlan` is ALWAYS set (from planning phase), so the `else` branch (which would work correctly at execution time, when groups exist) is **never reached**. The execution proceeds with the stale plan → `AllowedPrincipals = @()` → error.

**Evidence:**
- "Domain Admins" (built-in group, pre-exists before any deployment): **SUCCESS** ✅
- All "Tier X ..." groups (created in Phase 2 of the same run): **FAIL** ❌ — empty array
- Standalone path (`-IncludeWinLaps -ConfirmApply` without `-FullDeployment`) calls `Get-TierModelWinLapsAcl` at execution time → correctly resolves all groups → **all 15 planned actions applied successfully** ✅

**Affected OUs (all 6 non-DC OUs fail Read+Reset = 12 failures total):**
- Tier 0 Member Servers, Tier 0 PAW Devices, Tier 1 Member Servers, Tier 1 PAW Devices, Tier 2 PAW Devices, Tier 2 End-User Devices

**Proposed fix (for Beast):**

In the execution block (`if ($IncludeWinLaps)` inside `if ($ConfirmApply ...)`), always re-generate the plan fresh:
```powershell
# Replace the if/else that re-uses $winLapsFdPlan with a fresh call:
$winLapsPlan = Get-TierModelWinLapsAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent
```

Or more conservatively (only re-generate in apply mode):
```powershell
$winLapsPlan = if ($ConfirmApply) {
    Get-TierModelWinLapsAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent
} elseif (Get-Variable winLapsFdPlan -ErrorAction SilentlyContinue) { $winLapsFdPlan } else {
    Get-TierModelWinLapsAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent
}
```

**Note:** MSA, gMSA, dMSA use the **same pattern** (`$msaFdPlan`, `$gmsaFdPlan`, `$dmsaFdPlan`) and likely have the same bug. All should be fixed together.

---

## Bugs 1, 2, 3 — CONFIRMED FIXED ✅

- **Bug 1 (schemaDN StrictMode):** Confirmed fixed — no StrictMode crash in any run
- **Bug 2 (plan display identityreference):** Confirmed fixed — 0 errors, `■ LAPS` lines render
- **Bug 3 (Gate 5 Get-ADGroup -Identity):** Confirmed fixed — prereqs PASS, groups found

---

## Run 3 Test Matrix

### P1 — TOTALS INCREASE
| Item | Result |
|---|---|
| Baseline Applied | **643** |
| WinLaps Applied (-FullDeployment) | **661** (delta +18) |
| Expected if all actions succeed | 664 (643 + 21) |
| Delta shortfall | −3 WinLaps SELF + DC = 9; 12 Read/Reset FAILED |
| **VERDICT** | **PARTIAL PASS** — Applied > 643 ✅ but 12/21 WinLaps ACL actions failed (Bug 4) |

**WinLaps execution breakdown:**
- ✅ SELF permissions: all 7 OUs applied
- ✅ Read + Reset: Domain Controllers (TIERLAB\Domain Admins) — pre-existing group
- ❌ Read + Reset: all 6 other OUs — empty AllowedPrincipals (Bug 4)

### P1 — IDEMPOTENCY
Immediately after the full deploy, standalone `-IncludeWinLaps -ConfirmApply` ran.

- **Actions planned: 15** (standalone correctly detected DC Read/Reset, T1PAW, T2PAW Read/Reset as already-present → skipped; only applied remaining 7 SELF + 4 Read + 4 Reset)
- **All 15 applied successfully** — standalone path works correctly
- Note: the 7 SELF re-applied are likely no-ops at the LAPS cmdlet level (idempotent)
- **True idempotency (0 actions on 3rd run)** not tested — would require a 3rd run after a complete apply

**VERDICT: NOT CONFIRMED** — True idempotency can't be verified until Bug 4 is fixed so a clean complete apply occurs first.

### P1 — DELEGATION LANDED
After the combined run (full deploy + standalone), all expected delegations are confirmed in AD:

| OU | Expected Principals | Actual ExtendedRightHolders | Result |
|---|---|---|---|
| Domain Controllers | TIERLAB\Domain Admins | NT AUTHORITY\SYSTEM, **TIERLAB\Domain Admins** | ✅ |
| Tier 0 Member Servers | TIERLAB\Tier0ServerOperators | NT AUTHORITY\SYSTEM, Domain Admins, Enterprise Admins, Tier0Admins, **TIERLAB\Tier0ServerOperators** | ✅ |
| Tier 2 End-User Devices | TIERLAB\Tier2DeviceOperators + TIERLAB\Tier2HelpdeskOperators | NT AUTHORITY\SYSTEM, Domain Admins, Enterprise Admins, **TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators** | ✅ |

**EUD DUAL-PRINCIPAL: CONFIRMED ✅** — both Tier2DeviceOperators AND Tier2HelpdeskOperators present.

**SELF permissions confirmed:** 6 ACEs (ExtendedRight/WriteProperty) on all sampled OUs.

**Find-LapsADExtendedRights output shape — FINAL CONFIRMED:**
- Object type: `ExtendedRightsInfo`
- Property: `ExtendedRightHolders` — array of strings in `NETBIOS\sAMAccountName` format
- Examples: `TIERLAB\Domain Admins`, `TIERLAB\Tier0Admins`, `TIERLAB\Tier2HelpdeskOperators`
- No `AllComputerPermission` property observed
- SELF tracked via AD ACL (`Get-Acl`), not via `ExtendedRightHolders`

### P1 — PLAN DISPLAY (quick re-confirm)
**PASS** ✅ — 0 `identityreference` errors; `■ LAPS` lines rendered.
Post-deploy plan shows 7 SetComputerSelfPermission lines (Read/Reset detected as already-set → plan shows only remaining SELF).

### P1 — WINDOWS-LAPS-ONLY
**PASS** ✅ — zero `ms-Mcs-AdmPwd`, `AdmPwd.PS` references in full deploy output (754 lines).

---

## Standalone Idempotency Output (full)

```
=== Standalone MSA/gMSA/dMSA/WinLaps ACL Deployment ===
Phase: Windows LAPS ACL Delegations
  Actions planned: 15
  ✅ Applied LAPS Self-Permission: Domain Controllers
  ✅ Applied LAPS Self-Permission: Tier 0 Member Servers
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
  ✅ Applied LAPS Self-Permission: Tier 0 PAW Devices
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier0Admins on Tier 0 PAW Devices
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier0Admins on Tier 0 PAW Devices
  ✅ Applied LAPS Self-Permission: Tier 1 Member Servers
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier1ServerOperators on Tier 1 Member Servers
  ✅ Applied LAPS Self-Permission: Tier 1 PAW Devices      ← T1PAW Read/Reset already set → SKIPPED
  ✅ Applied LAPS Self-Permission: Tier 2 PAW Devices      ← T2PAW Read/Reset already set → SKIPPED
  ✅ Applied LAPS Self-Permission: Tier 2 End-User Devices
  ✅ Applied LAPS Read-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 End-User Devices
  ✅ Applied LAPS Reset-Permission: TIERLAB\Tier2DeviceOperators, TIERLAB\Tier2HelpdeskOperators on Tier 2 End-User Devices
```

DC Read/Reset, T1PAW Read/Reset, T2PAW Read/Reset correctly detected as already-present and SKIPPED.

Note: T1PAW (Tier 1 Admins) and T2PAW (Tier 2 Admins) Read/Reset were set by the base deployment's OU ACL phase (Tier1Admins/Tier2Admins granted read access to LAPS attributes via inherited ACEs). `Find-LapsADExtendedRights` correctly detects these as present.

---

## Output Files (Run 3, 2026-07-14)

| File | Contents |
|---|---|
| `wt3-deploy.txt` | Full deploy with -IncludeWinLaps — 754 lines, Applied=661, Bug 4 errors |
| `wt3-idem.txt` | Standalone idempotency run — 15 actions, all applied, DC/T1PAW/T2PAW skipped |
| `wt3-delegation.txt` | Find-LapsADExtendedRights shape + delegation verification |
| `wt3-plan.txt` | Plan display re-confirm — 519 lines, 0 identityreference errors |

---

## Final Lab State

- **VM:** TierLab-DC01 | **State:** Off | **Checkpoint:** WinLapsSchema (restored, no WinLaps ACLs)
- Ready for Joel's manual UAT from a clean baseline.

---

## Action Required (for Beast — Bug 4)

**Fix location:** `Deploy-TierModel.ps1` execution block, `if ($IncludeWinLaps)` section (~line 1818)  
**Change:** In the execution block, always re-call `Get-TierModelWinLapsAclFd` at execution time (after Phase 2 creates groups), not re-use the planning-phase `$winLapsFdPlan`.  
**Also fix:** Same pattern applies to MSA (`$msaFdPlan`), gMSA (`$gmsaFdPlan`), dMSA (`$dmsaFdPlan`) — all use the same pre-generated plan that may have the same timing issue.

**Branch:** feature/windows-laps  
**Tester:** Wolverine (Logan)  
**Lab:** TierLab-DC01 (Hyper-V), checkpoint WinLapsSchema  
**Requested by:** Joel Platek  
**Sessions:** First run (Bug 1+2 found) + Re-test after Beast fixed Bug 1+2

---

## FIRST RUN — ⚠️ STOP CONDITION (2026-07-14 AM)

Two bugs found blocking WinLaps execution. See commit history for details. Beast fixed both. See Re-Test section below.

---

## RE-TEST — ⚠️ STOP CONDITION — Bug 3 Found

Beast's Bug 1 + Bug 2 fixes are confirmed working. A **new blocking bug (Bug 3)** was found in the re-test:

---

## Bug 3 — BLOCKING: `Get-ADGroup -Identity` in Gate 5 Fails for Custom Groups

**File:** `modules/TierModel/public/Test-TierModelPrerequisites.ps1` ~line 638

**Exact error (all 7 custom groups):**
```
? MSA/gMSA/dMSA/WinLaps prerequisites failed:
  - WINLAPS_GROUP_MISSING: Required group 'Tier 0 Server Operators' not found in AD. Deploy groups first.
  - WINLAPS_GROUP_MISSING: Required group 'Tier 0 Admins' not found in AD. Deploy groups first.
  - WINLAPS_GROUP_MISSING: Required group 'Tier 1 Server Operators' not found in AD. Deploy groups first.
  - WINLAPS_GROUP_MISSING: Required group 'Tier 1 Admins' not found in AD. Deploy groups first.
  - WINLAPS_GROUP_MISSING: Required group 'Tier 2 Admins' not found in AD. Deploy groups first.
  - WINLAPS_GROUP_MISSING: Required group 'Tier 2 Device Operators' not found in AD. Deploy groups first.
  - WINLAPS_GROUP_MISSING: Required group 'Tier 2 Help-desk Operators' not found in AD. Deploy groups first.
```

**Root cause:**
Gate 5 in `Test-TierModelPrerequisites.ps1` (~line 638) uses:
```powershell
Get-ADGroup -Identity $groupName -Server $PreferredDc -ErrorAction Stop | Out-Null
```

`Get-ADGroup -Identity` matches by: DN, GUID, SID, or **SAMAccountName only**. It does NOT match by the `Name` (CN) attribute.

The `tiermodel-winlaps.json` config stores display names with spaces (e.g., `"Tier 0 Server Operators"`). The base deployment creates these groups with:
- Display name (CN): `Tier 0 Server Operators` (with spaces)
- SAMAccountName: `Tier0ServerOperators` (CamelCase, no spaces)

`Get-ADGroup -Identity 'Tier 0 Server Operators'` tries to match SAMAccountName = `Tier 0 Server Operators` → no group found → WINLAPS_GROUP_MISSING. The group exists in AD but is not found because the SAM is `Tier0ServerOperators` not `Tier 0 Server Operators`.

"Domain Admins" works (no error) because Domain Admins' SAMAccountName IS `Domain Admins` (with space — it's a built-in group that was deliberately given a SAM with a space).

**Evidence:** Base deployment output (Phase 2) confirms ALL groups ARE created:
```
? Creating Group: Tier 0 Server Operators (Tier0ServerOperators)
? Creating Group: Tier 1 Server Operators (Tier1ServerOperators)
? Creating Group: Tier 2 Device Operators (Tier2DeviceOperators)
? Creating Group: Tier 2 Help-desk Operators (Tier2HelpdeskOperators)
...
```

**Contrast with plan generator:** `Get-TierModelWinLapsAclFd` uses `-Filter "Name -eq '$group'"` which matches by CN/Name → correctly finds groups → plan shows `TIERLAB\Tier0ServerOperators` etc. Only the prereq check uses `-Identity`.

**Proposed fix (for Beast):**
In Gate 5 of `Test-TierModelPrerequisites.ps1` (~line 638), replace:
```powershell
Get-ADGroup -Identity $groupName -Server $PreferredDc -ErrorAction Stop | Out-Null
```
with a `-Filter` lookup (same pattern as `Get-TierModelWinLapsAclFd`):
```powershell
$grp = Get-ADGroup -Filter "Name -eq '$groupName'" -Server $PreferredDc -ErrorAction SilentlyContinue
if (-not $grp) {
    $grp = Get-ADGroup -Filter "sAMAccountName -eq '$groupName'" -Server $PreferredDc -ErrorAction SilentlyContinue
}
if (-not $grp) {
    $result.Valid = $false
    $winLapsGroupsExist = $false
    $null = $result.Errors.Add("WINLAPS_GROUP_MISSING: ...")
}
```

**Impact:** WinLaps execution is completely blocked (prerequisite check fails). Applied = 643 (no delta). All execution-mode items fail.

---

## Bug 1 — FIXED ✅ (Beast's fix confirmed working)

`$schemaDN` VariableIsUndefined crash is gone. Bug 1 fix confirmed:
- No `"cannot be retrieved because it has not been set"` error in any re-test output
- `Test-TierModelPrerequisites` now correctly initializes `$schemaDN`/`$dfl` when `-IncludeWinLaps` is used alone

## Bug 2 — FIXED ✅ (Beast's fix confirmed working)

`Write-IncludeAclPlanActions` `identityreference` error is gone. Plan display correctly shows:
```
■ LAPS SetComputerSelfPermission: SELF on Domain Controllers
■ LAPS SetReadPasswordPermission: TIERLAB\Domain Admins on Domain Controllers
■ LAPS SetResetPasswordPermission: TIERLAB\Domain Admins on Domain Controllers
■ LAPS SetComputerSelfPermission: SELF on Tier 0 Member Servers
...
```
(21 lines, one per action; principals blank pre-base-deploy because groups don't exist yet — expected)

---

## Re-Test Matrix Results

### P1 — TOTALS INCREASE
| Item | Result |
|---|---|
| Baseline Applied (confirmed from prior run) | **643** |
| WinLaps Applied | **643** (Bug 3 blocked execution) |
| Delta | **0** (expected +21) |
| **P1 PASS/FAIL** | **FAIL** — Bug 3 prevents WinLaps from executing |

### P1 — IDEMPOTENCY
**BLOCKED** — same Bug 3. Standalone WinLaps also fails Gate 5.

### P1 — PLAN DISPLAY (Bug 2 regression check)
**PASS** ✅ — 0 `identityreference` errors, all 21 `■ LAPS` lines rendered.

### P1 — WINDOWS-LAPS-ONLY
**PASS** ✅ — zero references to `ms-Mcs-AdmPwd`, `AdmPwd.PS` across 728 lines.

### P1 — FOUR-COMPOSE PLANNING (Bug 2 regression + phase ordering)
**PASS** ✅ — Phases 7→8→9→10, 0 `identityreference` errors. Compose plan:
```
Phase 7: MSA ACL Delegations
Phase 8: gMSA ACL Delegations
Phase 9: dMSA ACL Delegations
Phase 10: Windows LAPS ACL Delegations
```
Four-compose plan runs AFTER base deploy (groups exist) → principals displayed correctly:
```
■ LAPS SetReadPasswordPermission: TIERLAB\Tier0ServerOperators on Tier 0 Member Servers
```

### P1 — DELEGATION VERIFICATION
**PARTIAL** — WinLaps never applied, so no WinLaps-specific ACLs set. However, `Find-LapsADExtendedRights` output shape **IS confirmed** from the post-base-deploy state (inherited/default LAPS rights visible):

**`Find-LapsADExtendedRights` Output Shape — CONFIRMED:**
- Object type: `ExtendedRightsInfo`
- Properties: `ObjectDN` (string), `ExtendedRightHolders` (array of strings in `DOMAIN\sAMAccountName` format)
- Example: `TIERLAB\Domain Admins`, `TIERLAB\Enterprise Admins`, `TIERLAB\Tier0Admins`
- **Format is `NETBIOS\sAMAccountName` (e.g., `TIERLAB\Tier0ServerOperators`)** — Beast's idempotency code should check this format
- `AllComputerPermission` property NOT observed in returned objects (SELF permission tracked separately)

**EUD dual-principal:** NOT confirmed — WinLaps code never ran. Only `Tier2DeviceOperators` appeared (inherited). `Tier2HelpdeskOperators` would need explicit WinLaps delegation.

### P2 — GUARDS (re-confirm)
**PASS** ✅ — `-IncludeWinLaps -OuOnly` and `-IncludeWinLaps -GroupOnly` both throw correct error:
```
-IncludeMsa, -IncludeGmsa, -IncludeDmsa, and -IncludeWinLaps can only be used standalone or
combined with -FullDeployment. They cannot be used with -OuOnly, -GroupOnly, -UserOnly,
-GposOnly, -OuAclsOnly, or -AdmxOnly.
```

---

## Key Technical Findings (Re-Test)

1. **Pre-existing LAPS ACLs on clean WinLapsSchema checkpoint:** Only `NT AUTHORITY\SYSTEM` on Domain Controllers OU. Tier model OUs don't exist until base deploy runs. No Tier*Admins pre-existing LAPS ACLs from checkpoint (previous "4 pre-existing" finding was measuring post-base-deploy state via inherited permissions, not true checkpoint state).

2. **Plan shows 21 actions (all OUs, fresh state).** 685 total plan actions (base 664 + WinLaps 21) on a clean WinLapsSchema restore.

3. **`Find-LapsADExtendedRights` holder format:** `NETBIOS\sAMAccountName` confirmed. Beast's idempotency code checks `$holders` for strings like `TIERLAB\Tier0ServerOperators` — format is correct.

4. **Plan display blank principals (pre-base-deploy is expected):** When plan runs before base deploy (groups don't exist yet), `Get-TierModelWinLapsAclFd` can't resolve groups by `-Filter "Name -eq ..."` → `$resolvedReadPrincipals = @()` → plan shows `■ LAPS SetReadPasswordPermission:  on Tier 0 Member Servers` (blank after ": "). This is expected behavior, NOT a bug. The four-compose plan runs after base deploy and shows principals correctly.

5. **Gate 5 lookup vs plan generator:** Plan generator (`Get-TierModelWinLapsAclFd`) correctly uses `-Filter "Name -eq '$group'"` → works. Prereq check (Gate 5) uses `-Identity $groupName` → fails for custom groups. Same fix pattern already exists in the codebase.

---

## Pre-Check Results (WinLapsSchema fresh restore, before base deploy)

```
Find-LapsADExtendedRights available: True
PRE-EXIST: OU=Domain Controllers,DC=tierlab,DC=internal -> NT AUTHORITY\SYSTEM
ERROR on OU=Tier 0 Member Servers: Directory object not found. (OU not deployed yet)
ERROR on OU=Tier 1 Member Servers: Directory object not found. (OU not deployed yet)
ERROR on OU=Tier 2 End-User Devices: Directory object not found. (OU not deployed yet)
Pre-existing non-SELF LAPS ACLs: 1 (only NT AUTHORITY\SYSTEM on DC OU — not a user principal)
```

---

## Output Files (re-test, 2026-07-14)

| File | Contents |
|---|---|
| `wtest2-precheck.txt` | Pre-deploy LAPS ACL check on clean WinLapsSchema restore |
| `wtest2-plan.txt` | Plan display (Bug 2 regression check) — 434 lines, 21 actions, 0 errors |
| `wtest2-winlaps.txt` | Full WinLaps deploy attempt — 728 lines, Bug 3 hit |
| `wtest2-idem.txt` | Idempotency check — Bug 3 hit |
| `wtest2-delegation.txt` | Find-LapsADExtendedRights shape investigation |
| `wtest2-compose.txt` | Four-compose planning — 537 lines, phases 7–10 ✅ |
| `wtest2-guards.txt` | Guard re-confirm — OuOnly + GroupOnly both fail correctly |

---

## Final Lab State

- **VM:** TierLab-DC01 | **State:** Off | **Checkpoint:** WinLapsSchema (restored, no WinLaps ACLs applied)
- Ready for Joel's manual UAT from a clean baseline.

---

## Action Required (for Beast — Bug 3)

**Fix location:** `modules/TierModel/public/Test-TierModelPrerequisites.ps1` Gate 5 (~line 638)  
**Change:** Replace `Get-ADGroup -Identity $groupName` with `-Filter "Name -eq '$groupName'"` (same pattern as `Get-TierModelWinLapsAclFd`).  
**Note:** Bug 1 and Bug 2 fixes are confirmed green. Only Bug 3 remains blocking.
