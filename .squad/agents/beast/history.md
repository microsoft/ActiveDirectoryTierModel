# beast — History (Archived Summary)

## 2026-08-27 — Amendment: Computer-Membership-Only + Remove exemptAccounts

**Status:** ✅ COMPLETE — 6 files changed; ready for lab validation

### Scope Reduction: Silos govern computers, not accounts

Tier admin account groups are always empty on a TM deploy. Auditing/assigning user silo membership is a no-op and adds complexity for no operational benefit. Removed entirely.

**Config (`tiermodel-authsilos.json`):**
- Removed top-level `exemptAccounts` block (3 domain-join service accounts + RID-500 well-known-account entry)
- Removed `memberAccountGroups` array from ALL 4 silos
- Updated `comment` fields to remove VPN-exclusion/account rationale text
- Updated top-level comment to state computer-only scope

**Deploy (`Set-TierModelAuthSiloMembership`, `Get-TierModelAuthSiloMembershipFd`):**
- Removed entire exemption setup (configuredExempts, RID-500 resolution, exemptSet HashSet, ExemptAccounts log)
- Removed account-group expansion loop (`foreach memberAccountGroups`)
- Removed exemptSet.Contains check from computer-group expansion
- `$allPrincipals = @($accountsToAssign) + @($computersToAssign)` → `@($computersToAssign)`
- Membership summary: removed "N exempt-skipped" → just "N assigned, N already-assigned"
- `TotalExempt` removed from MembershipFd Summary

**Audit (`Test-TierModelAuthSilo`, `Test-TierModelAuthSiloPrerequisite`):**
- Removed exemption setup block from Test-TierModelAuthSilo (no exemptSet)
- Removed memberAccountGroups expansion loop; computer-only membership subset check retained
- Check 5 comment: "Computer membership (subset check — computer groups only)"
- Test-TierModelAuthSiloPrerequisite: removed `foreach ($silo.memberAccountGroups)` section

**Config loading (`Get-TierModelConfig`):**
- Removed `authSilosExemptAccounts` property from config object

### Final per-silo config shape
```json
{
  "name": "*- Tier 0 Admins Authentication Silo",
  "description": "...",
  "policy": "*- Tier 0 Admins Authentication Policy",
  "memberComputerGroups": ["Domain Controllers", "Read-only Domain Controllers", "Tier0MemberServers", "Tier0PAWDevices"],
  "enforce": false,
  "protectedFromAccidentalDeletion": true,
  "comment": "..."
}
```

No `memberAccountGroups`. No `exemptAccounts`.

---



**Status:** ✅ COMPLETE — 9 files changed; ready for lab validation

### Create-Once / Never-Modify Deploy Model

**Rule**: Authentication Policies and Silos are created ONCE by deploy. If an object already exists in AD, deploy leaves it completely untouched regardless of any property difference. No drift detection, no update actions, ever. Modifications to existing objects are an out-of-band operation.

**Changes:**
- `Get-TierModelAuthPolicyFd`: removed all drift detection (SID resolution, SDDL comparison, PFAD check, TGT check, Enforce check). Now: exists in AD → AlreadyExists; not in AD → resolve SIDs + build SDDL → CreateAuthPolicy.
- `Get-TierModelAuthSiloFd`: same. Removed UpdateAuthSilo. Now: exists → AlreadyExists; not in AD → CreateAuthSilo.
- `New-TierModelAuthPolicy`: removed all UpdateAuthPolicy handling. Create-only. Returns `CreatedNames [string[]]`.
- `New-TierModelAuthSilo`: removed all UpdateAuthSilo handling. Create-only. Returns `CreatedSiloNames [string[]]`.

### Create-Once Membership Model

Silo membership is assigned ONLY for silos created in this run. Silos that already existed are never touched by membership assignment.

**Changes:**
- `New-TierModelAuthSilo`: returns `CreatedSiloNames` — the names of silos actually created.
- `Set-TierModelAuthSiloMembership`: added `[string[]]$OnlyForSilos` — when bound, only processes silos in the list (empty list = process nothing; unbound = process all for backwards compat).
- `Get-TierModelAuthSiloMembershipFd`: same `-OnlyForSilos` parameter for plan-mode pending count.
- Deploy wiring: pass `$authSiloResult.CreatedSiloNames` to `-OnlyForSilos`; fully converged runs show 0 membership pending.

### Green-Only Deploy Output (`-ConfirmApply`)
- `✅ Created Authentication Policy: *- Tier 0 Admins Authentication Policy`
- `✅ Created Authentication Policy Silo: *- Tier 0 Admins Authentication Silo`
- `✅ Assigned DC01$ (computer) to silo: *- Tier 0 Admins Authentication Silo`
- `✅ Already deployed — nothing to create` (when all objects already exist)
- Yellow/Red = real problem only. No "X to create, Y to update, Z converged" yellow lines.

### Plan Mode Output (no `-ConfirmApply`)
- `  Auth Policies: all 4 already deployed` (Green) OR `  Auth Policies: 2 to create` (Cyan)
- `  Auth Silos:    all 4 already deployed` (Green) OR `  Auth Silos:    3 to create` (Cyan)
- `  Membership:    0 pending (all silos already deployed)` (Gray) OR `  Membership:    will assign for N new silo(s)` (Cyan)

### Audit Console Cleanup
- `Write-TierModelLog -Level Warning` → `Write-TierModelLog -Level Info` for audit NonCompliant events. Structured log still written to file; `Write-Warning` no longer called → no "WARNING: [timestamp]..." console spam.
- Per-issue display: `❌ NonCompliant — {concise reason}` (one line per issue, Red) instead of `❌ NonCompliant` + multi-line yellow dump.
- SDDL issues name the group, not the SID: `AllowedToAuthenticateFrom: missing required device group: Tier0PAWDevices`
- Silo policy link: `UserAuthenticationPolicy not linked to config policy '...' (not linked)` 
- Added `ℹ️  Enforce state: {state}` below ❌ lines (informational, DarkGray).
- Added `sidToGroupName` map in Test-TierModelAuthPolicy so missing SIDs show as group names.

---



**Status:** ✅ FIXED — 3 files changed + 1 new cmdlet; ready for lab validation

### New Cmdlet: `Get-TierModelAuthSiloMembershipFd`

Read-only membership planner. Builds the exemption set, expands member groups, then for each
expected principal reads:
1. `grantedDns` (silo Members list via `msDS-AuthNPolicySiloMembers`) — Grant step done?
2. `msDS-AssignedAuthNPolicySilo` on the account — Set step done?

A principal is `ALREADY-ASSIGNED` only if BOTH are satisfied; otherwise it is `PENDING`.

Returns `{ Actions (pending only), Summary { TotalPending, TotalAlreadyAssigned, TotalExempt, TotalActions, ExistingCount }, Warnings, Errors, DurationMs }`.

### Fixed: `Set-TierModelAuthSiloMembership` — ShouldProcess ordering

The read-only already-assigned pre-check (`$alreadyGranted` + `$preCheckSiloName` → `$alreadyAssigned`) now runs BEFORE `$PSCmdlet.ShouldProcess()`. Effect:
- **WhatIf mode**: converged principals skip entirely (`continue`); only truly pending principals print `[WhatIf] Would assign`, so WhatIf output is accurate
- **Execution mode**: converged principals skip with `continue` (no ShouldProcess overhead); pending principals go to ShouldProcess → Grant → Set as before
- **Eliminates the redundant inner AD read** in step 2 — `$preCheckSiloName` is reused from the pre-check, saving one `Get-ADUser/Computer` per already-assigned principal

### Fixed: Deploy-TierModel.ps1 plan-mode membership line

Both plan-mode blocks (FullDeployment planning, standalone planning) now call `Get-TierModelAuthSiloMembershipFd` instead of printing a static silo count:
```
# Converged:
  Membership:    0 pending (all assigned)          ← Gray

# Work pending:
  Membership:    3 pending assignment(s)            ← Yellow
```
The pending count is also added to `$deploymentPlan.TotalActions` / `$standaloneDeploymentPlan.TotalActions`, making `Action count: N` in the plan summary consistent: a fully converged re-run shows `Action count: 0`.

### `$alreadyAssigned` logic (matches both cmdlets)
```
$alreadyGranted  = silo's Members list contains account DN
$currentSiloName = msDS-AssignedAuthNPolicySilo → normalize DN to name
$alreadyAssigned = $alreadyGranted AND ($currentSiloName -eq $siloName)
```

---



**Status:** ✅ FIXED — 3 files changed; ready for lab re-validation

### Rule 1: Enforce State — Always Informational, Never Pass/Fail

Both `Test-TierModelAuthPolicy` and `Test-TierModelAuthSilo` now:
- READ the Enforce attribute and expose it as `EnforceState` in every Findings entry: `'audit mode'`, `'ENFORCED'`, or `'unknown'`
- NEVER add it to `$issues` (the array that drives NonCompliant)
- A policy/silo with `Enforce=$true` is **Compliant exactly like** `Enforce=$false`
- The per-object display line now shows `(enforce: <state>)` regardless of pass/fail

### Rule 2: Mandatory-Subset Check (configured ⊆ actual)

**SDDL device groups** (`Test-TierModelAuthPolicy`):
- Uses `Compare-TierModelAuthSddl -RequireSubset` instead of exact-match
- Every CONFIGURED device-group SID must be present → NonCompliant if any are missing
- Extra SIDs in AD beyond config (customer-added custom groups) → allowed, `ExtraDeviceGroups` in Findings (informational display with ℹ️)
- Deploy planner (`Get-TierModelAuthPolicyFd`) still uses exact-match (no `-RequireSubset`) — deploy behavior UNCHANGED

**Silo membership** (`Test-TierModelAuthSilo`):
- Every CONFIGURED member (from group expansion minus exempts) must be in silo Members → NonCompliant if absent (`"Missing from silo Members: <sam> (<dn>)"`)
- Extra members in silo beyond config → allowed, `ExtraMembers` in Findings (informational display with ℹ️), NEVER counted as NonCompliant
- Removed: `$issues += "Unexpected member in silo (not in config groups): ..."` — this exact failure is gone

### `Compare-TierModelAuthSddl` API Change

Added `[switch]$RequireSubset` parameter. All return paths now include `ExtraSids [string[]]`:
- **Default (exact mode)**: sets must be identical; `ExtraSids = @()`
- **RequireSubset mode**: desired ⊆ existing; `ExtraSids = [string[]]` of extras in existing-but-not-desired (informational)

Callers that omit `-RequireSubset` (including `Get-TierModelAuthPolicyFd`) are **unaffected** — exact-match behavior preserved.

### Findings Shape After Refinements

**Test-TierModelAuthPolicy Findings entry:**
```
{ PolicyName, Status, Issues, EnforceState, ExtraDeviceGroups }
```

**Test-TierModelAuthSilo Findings entry:**
```
{ SiloName, Status, Issues, EnforceState, ExtraMembers }
```

### Definitive Compliant / NonCompliant Criteria

**Test-TierModelAuthPolicy** — NonCompliant when:
- Policy absent from AD → `Missing`
- Description differs
- UserTGTLifetimeMins differs (when config is non-null)
- Any CONFIGURED device-group SID absent from AllowedToAuthenticateFrom (`-RequireSubset`)
- ProtectedFromAccidentalDeletion ≠ true

Informational only (never NonCompliant): Enforce state; extra device groups beyond config.

**Test-TierModelAuthSilo** — NonCompliant when:
- Silo absent from AD → `Missing`
- Description differs
- Any of User/Computer/ServiceAuthenticationPolicy link differs
- ProtectedFromAccidentalDeletion ≠ true
- Any CONFIGURED member (account or computer, minus exempts) absent from silo Members

Informational only (never NonCompliant): Enforce state; extra silo members beyond config.

---



**Status:** ✅ IMPLEMENTATION COMPLETE — Deploy + Audit cmdlet sets, 8 public functions, config, lab-ready

### Auth Silos Deployment (2026-08-27)

**8 Public Cmdlets:**
- Get-TierModelAuthPolicy / Get-TierModelAuthPolicyFd — Load and plan auth policies
- Get-TierModelAuthSilo / Get-TierModelAuthSiloFd — Load and plan auth silos
- New-TierModelAuthPolicy — Idempotent create/update (Enforce=$false, PFAD=$true)
- New-TierModelAuthSilo — Idempotent create/update (1:1 policy per silo; all 3 classes same policy)
- Set-TierModelAuthSiloMembership — Idempotent membership (recursive expansion, exemptions, pre-checks)
- Test-TierModelAuthSiloPrerequisite — Dependency gate (group existence)

**Public Helper:**
- Build-TierModelAuthSddl — Constructs Member_of_any (OR-logic) SDDL; never AND-logic

**Key Invariants:**
- SDDL OR-logic: Member_of_any prevents lockout; AND-logic is documented failure mode
- Policies before silos (execution order enforced in Deploy-TierModel)
- Grant then Set for membership (both idempotent via pre-checks)
- RID-500 exemption resolved at runtime for renamed administrator accounts

**Deploy-TierModel Integration:**
- Param: -IncludeAuthSilos (after -IncludeWinLaps)
- Standalone: 3-step execution (policies → silos → membership)
- FullDeployment: Phase 12 planning; policies → silos → membership after audit
- Module v1.3.3, FunctionsToExport updated

**Config:** config/tiermodel-authsilos.json — 4 policies + 4 silos (1:1 mapping), group names resolved at runtime

### Auth Silos Audit (2026-08-27)

**2 Public Audit Cmdlets:**
- Test-TierModelAuthPolicy — Verify policy compliance (existence, Description, TGT lifetime, SDDL via Compare-TierModelAuthSddl, PFAD)
- Test-TierModelAuthSilo — Verify silo compliance (existence, policy links, PFAD, membership validation)

**Return Shape:** TotalChecked / Compliant / Missing / NonCompliant / Errors / Drift / Findings array (consistent with Test-TierModelWinLapsAcl)

**Hard Rule:** Enforce is intentionally NOT checked — audit mode is default; enforcement is a separate lifecycle step

**Audit-TierModel Integration:**
- -IncludeAuthSilos param after -IncludeWinLaps
- Standalone block + FullDeployment results (EntityType: 'Auth Policies' / 'Auth Silos')
- Membership comparison: config-expected vs silo's msDS-AuthNPolicySiloMembers (recursive expansion minus exempts + RID-500)

### SDDL Alias Fix (2026-08-26)

**Bug:** Domain Controllers group (RID 516) stored as SID, read back as SID(DD) alias → false drift on every re-run (Tier 0 only)

**Fix:** New public cmdlet Compare-TierModelAuthSddl
- Extracts domain SID from desired SDDL
- Expands DA/DU/DG/DC/DD aliases to full SIDs in both SDDLs
- Set-based comparison (order-insensitive, case-insensitive)
- Returns { Equal: bool, Reason: string }

**Applied to:** Get-TierModelAuthPolicyFd drift detection

### Silo Policy Dependency Fix (2026-08-25)

**Bug:** First deploy errored on silo planning (policies not yet in AD) → deployment blocked

**Fix:**
1. Get-TierModelAuthSiloFd now validates policy reference against **config**, not AD
2. Deploy-TierModel.ps1 restructured: policies created first (AD), then silos planned+created
3. Error handling: policy not in config = real error; policy pending creation = proceeds

**Invariant:** Policies must exist in AD before silos are created (non-negotiable)

### Config Finalization (2026-08-27)

**Naming Convention:** All 8 objects use *-  prefix (mirrors GPO convention)
- Tier 0/1/2 Admins: policies + silos
- Tier 2 EUD: policy + silo

**TGT Lifetimes:** Tier 0 (120m), Tier 1 (240m), Tier 2 Admin (360m), Tier 2 EUD (null/domain default)

**Group Scope:** Admins + Operators + ServiceAccounts per tier; Tier 2 EUD = LocalDeviceOperators only

**Open Items:** VPN account group inclusion (pending confirmation)

---

## 2026-08-24 — Format-TierModelDuration Implementation

**Status:** ✅ COMPLETE — Public function, 9 Write-Host sites updated, 12/12 smoke tests pass

**Function:** Format-TierModelDuration.ps1
- 4-tier format: <1ms / Xms / Xs / Xm Ys
- Floor-based arithmetic (no banker's rounding: 90000→1m 30s, not 2m 30s)
- Accepts both [int] and [double] DurationMs

**Integration:** Updated 9 Write-Host console sites in Deploy-TierModel.ps1; left 2 log sites raw

**Module v1.3.0, added to FunctionsToExport**

**Regression Guards:** 90000/119999/120000 boundary values locked

---

## 2026-08-14 — -EnableAuditing Implementation

**Status:** ✅ DELIVERED — 4 audit cmdlets, config/schema, deploy integration, lab-validated

**Cmdlets:** Get-TierModelAuditRule, New-TierModelAuditRule, Test-TierModelAuditRule, Get-TierModelAuditRuleFd

**Config:** tiermodel-audit.json — 9-right SACL list, domain DN templating

**SACL Pattern (Validated):**
- Get-Acl -Path "AD:<dn>" -Audit (requires SeSecurityPrivilege)
- UNION converge: remove managed ACEs, add canonical 9-right ACE, Set-Acl
- Idempotency: already-converged = zero writes
- No-clobber: non-Success AuditFlags left untouched

---

## 2026-08-11 — BUG-006 Canonical ACL Pre-flight Gate

**Status:** ✅ COMPLETE — Test-TierModelCanonicalAcl, 18 tests, lab-validated

**Technique:** System.DirectoryServices.Protocols + CommonSecurityDescriptor parsing
- Check .DiscretionaryAcl.IsCanonical (CommonAcl only)
- Two parameter sets: ByServer (live AD), ByBytes (Pester-friendly)

**Integration:** Pre-flight gate in Test-TierModelPrerequisites (WinLaps block); both Deploy/Audit hard-stop on non-canonical state

---

## Essential Technical Patterns

**SDDL Semantics:** Member_of_any (OR) prevents lockout; Member_of_each (AND) = documented failure

**Idempotency:** Always check-before-act; .Count wrapping for empty sets (@() prevents StrictMode errors)

**Type Handling:** Mixed int/double require explicit casting

**SACL Converge:** Remove managed → add canonical → write same object; zero writes when converged

**Exemptions:** RID-500 resolved at runtime; configured accounts in HashSet (case-insensitive skip)

**CLR Conflicts:** Process-lifetime persistence; spawn clean child process to resolve

**Hashtable vs PSObject:** .ContainsKey() for hashtables; .Properties.Name for objects

**Two-Step Binding:** Grant-ADAuthenticationPolicySiloAccess + Set-ADAccountAuthenticationPolicySilo (both idempotent)

---

**Latest Decision:** Beast-AuthSilos-Deploy (2026-08-27) — 8-object model, SDDL design, key implementation decisions documented

**Next:** Lab validation of 8 open items; config review (Joel); module code deployment to test environment
