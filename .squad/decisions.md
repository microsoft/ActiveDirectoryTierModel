# Squad Decisions

## Active Decisions (2026-09-02)

*Active decisions from the current retention window. Older entries are archived in decisions-archive.md.*

---

# Decision: Module Version Bump — v2.0.0 Authentication Policy Silos Release

**Date:** 2026-09-02
**Author:** Coordinator (Squad)
**Status:** Decided — implemented, PR #50 awaits merge

## Context

Feature branch `feature/auth-silos` ships the authentication-silos deploy subsystem, a major feature addition to TierModel. Module version must be bumped from 1.x to reflect the breaking changes and new public cmdlets introduced by this feature.

## Decisions Made

### 1. Version 2.0.0 marks the Authentication Policy Silos release

- **Previous version:** 1.7.2
- **New version:** 2.0.0 (released as v2.0.0-rc1 tag)
- **Breaking change:** `-IncludeAuthSilos` parameter structure changed; create-once model (no update actions)
- **New cmdlets:** `Get-TierModelAuthSiloMembershipFd`, `New-TierModelAuthSilo`, `Set-TierModelAuthSiloMembership`, `Test-TierModelAuthSilo`
- **Schema change:** `memberAccountGroups`, `exemptAccounts` fields removed from silo objects

### 2. Module manifest updated

- `modules/TierModel/TierModel.psd1`: ModuleVersion = '2.0.0'
- Release notes file updated with feature summary and breaking changes
- Version-assertion tests: `Unit.ModuleManifest.Tests.ps1` and `Integration.Module.Tests.ps1` updated to expect v2.0.0

### 3. Test counts and coverage updated

- Integration tests: 314 → 318 (+4 new auth-silo integration tests)
- Automated total: 1890 tests, all passing
- Membership script coverage: 60.18% (CI-measured; accepted for optional scheduled script)
- Aggregate project coverage: ≥80% (maintained)

### 4. v2.0.0 tag and release procedure

- v2.0.0-rc1 tag pushed to feature branch for early validation
- After PR #50 merges to main: push v2.0.0 tag to main to trigger GitHub release workflow
- Release notes auto-generated from CHANGELOG and commit messages

## Files Changed

- `modules/TierModel/TierModel.psd1` — ModuleVersion bumped
- `Unit.ModuleManifest.Tests.ps1` — version assertion updated
- `Integration.Module.Tests.ps1` — version assertion updated
- `README.md` — test count totals updated
- `docs/test-coverage.md` — coverage percentages and dates updated

## Related Decisions

- Wolverine: Dot-Source Pattern for Standalone Script Unit Tests (2026-09-02)
- Coverage acceptance for optional/Update-TierModelMembership.ps1 (60.18%)

---

# Decision: Dot-Source Pattern for Standalone Script Unit Tests

**Date:** 2026-09-02
**Author:** Wolverine (Testing)
**Status:** Proposed -- pending Cyclops review

## Context

`optional/Update-TierModelMembership.ps1` is a standalone scheduled-task script (~2270 lines,
PowerShell 7). It is NOT a module cmdlet, so `InModuleScope` does NOT apply. Beast added a
dot-source seam near the `# MAIN EXECUTION` banner:

```powershell
if ($MyInvocation.InvocationName -eq '.') { return }
```

This guard means dot-sourcing loads all helper functions without running the main block.

## Decisions Made

### 1. Dot-source test seam for standalone scripts

When `$MyInvocation.InvocationName -eq '.'`, the script returns early. All functions defined
above the guard are loaded in the caller's scope. This is the correct pattern for any standalone
`.ps1` script that needs unit testing via Pester. NOT a module -- do not use InModuleScope.

Dot-source in BeforeAll:
```powershell
. "$PSScriptRoot\..\optional\Update-TierModelMembership.ps1"
```

### 2. ADObject creation: New-Object + Add-Member NoteProperty

On RSAT-enabled machines, `Microsoft.ActiveDirectory.Management.ADObject` is the REAL type
from the AD module. It does NOT support `$obj[$key] = $value` indexer or `.Add()` from
PowerShell. The correct pattern:

```powershell
$obj = New-Object 'Microsoft.ActiveDirectory.Management.ADObject'
$obj | Add-Member -NotePropertyName 'sAMAccountName' -NotePropertyValue 'user1' -Force
$obj | Add-Member -NotePropertyName 'msDS-AssignedAuthNPolicy' -NotePropertyValue $null -Force
```

NoteProperties are found by dot-notation (`$obj.sAMAccountName`) and satisfy the
`[Microsoft.ActiveDirectory.Management.ADObject]` parameter type constraint.

For CI without RSAT: define a minimal stub type using Add-Type before dot-sourcing:
```powershell
if (-not ('Microsoft.ActiveDirectory.Management.ADObject' -as [type])) {
    Add-Type -TypeDefinition 'namespace Microsoft.ActiveDirectory.Management { public class ADObject {} }'
}
```

### 3. Mock body parameters in Pester 5.9 are NOT auto-injected

In Pester 5.9.0, mock body scriptblocks do NOT receive the mocked function's bound parameters
as named variables, even with explicit `param()`. The ParameterFilter DOES see bound params,
but the body does NOT receive them this way.

**Workaround for mocks that must distinguish calls by parameter value:**
Use a script-scope call counter when calls are made in a known fixed order:

```powershell
$script:GrpCall = 0
BeforeEach { $script:GrpCall = 0 }
Mock Get-ADGroupMember {
    $script:GrpCall++
    if ($script:GrpCall % 2 -eq 1) { @(...first-call-result...) }
    else                            { @(...second-call-result...) }
}
```

This is robust when the mocked function is always called in the same order within the SUT.

### 4. Variables defined at Describe-body level run at DISCOVERY time

In Pester 5.x, code at the Describe block level (outside BeforeAll/It/etc.) runs during the
DISCOVERY phase. Variables set there (even with `$script:`) are NOT available during the RUN
phase inside It blocks. Always initialize shared test data inside `BeforeAll`.

Exception: `-TestCases @(...)` expressions are evaluated at discovery time. Arrays used in
TestCases MUST be defined outside BeforeAll (directly in Describe/Context body) or hardcoded.

### 5. Should -Throw syntax in Pester 5.x

Correct:
```powershell
{ code } | Should -Throw '*CONFIG ERROR*'   # positional ExpectedMessage (glob)
```

WRONG (Pester 4 syntax -- NOT supported in Pester 5):
```powershell
{ code } | Should -Throw -ExceptionMessage '*CONFIG ERROR*'
```

### 6. Angle brackets in It names trigger variable lookup

In Pester 5.x, `<placeholder>` in an It name is treated as a TestCase variable substitution
even when no TestCases are provided. With `Set-StrictMode -Version 2`, this throws
"variable '$placeholder' cannot be retrieved." Avoid `<...>` in It names unless TestCases
are provided.

### 7. .NET static methods are not mockable in Pester 5

`[System.Diagnostics.EventLog]::WriteEntry` cannot be mocked with Pester 5.x.
`Write-TmEvent` is tested for behavioral contract only:
- Opt-in gate (`$EnableEventLog` and `$script:EventLogReady`)
- No-throw guarantee (try/catch in function)
- WhatIf detection (`$WhatIfPreference` affects `$runMode` field)

The exact pipe-delimited message format is a lab-validated integration concern.

### 8. Inline main-block parameter gates are not unit-testable

The exclusion parameter-pairing check and `-NoExclusions` safety gate live inline in the
`try {}` block after `if ($MyInvocation.InvocationName -eq '.') { return }`. Dot-sourcing
returns before these lines, so they cannot be reached by unit tests.

**Recommendation for Beast:** Extract into `Test-TmExclusionParams` private function so they
can be unit-tested independently. Until then, these gates are integration-covered by Joel's
lab UAT.

## Files Changed

- `tests/Unit.MembershipReconciliation.Tests.ps1` -- new (107 tests)
- `.github/workflows/ci.yml` -- CodeCoverage.Path extended to include the script
- `README.md` -- test counts and coverage updated
- `docs/test-coverage.md` -- script added to per-file table, Last measured updated
- `.squad/agents/wolverine/history.md` -- session entry prepended

## Coverage

Script added to CI coverage path. Estimated ~74% (exact figure pending CI run).
Functions NOT covered by unit tests (integration-only):
- `Assert-Preflight` (requires live DC)
- `Import-TierModelConfig` (requires config JSON files)
- `Initialize-TmEventLog` (requires event log registry write)
- `Initialize-Debug` (deep filesystem setup)
- `Invoke-BuiltInExclusionEnforcement` (uses Get-ADUser, separate from reconciliation)
- `Invoke-Tier0/1/2*` dispatch wrappers (thin wrappers; covered transitively)
- Inline exclusion parameter gate (requires main block execution)

## Additional Technical Decision: ADEntityAdapter Workaround

**CRITICAL for future AD-object tests in standalone scripts:**

`New-Object 'Microsoft.ActiveDirectory.Management.ADObject' | Add-Member` FAILS after the real
ActiveDirectory module is imported into the session. The module registers `ADEntityAdapter` for
all ADObject instances. `Add-Member` calls `GetProperty` on the adapter which throws.

**The fix:** Use `$o.PSObject.Properties.Add([PSNoteProperty]::new(key, val))`.
PSObject.Properties.Add writes directly to the PSObject wrapper, bypassing the type adapter.
Property access `$o.propertyName` finds the NoteProperty via ETS. Works before and after
real AD module load.

Timing: Mock setup for AD cmdlets can trigger PowerShell auto-loading of the real AD module.
Objects created before mock setup (in BeforeAll) may work; objects created in later Context
BeforeAlls may fail. PSObject.Properties.Add removes this timing sensitivity.

"Attribute absent" tests are unrealistic: In production, Get-ADObject -Properties attr always
returns the attribute (null if unset). StrictMode 2.0 throws on real ADObject for absent props.
Replace with "attribute present but null" tests.

**Measured coverage: 60.18%** (CI-measured, CodeCoverage.Path updated in ci.yml).

---

# Decision: Auth Silos Ops Guide — Public Rewrite Structure

**Date:** 2026-09-02
**Author:** Storm (DevRel & Documentation)
**Status:** Proposed — pending Joel review

## Context

`docs/auth-silos-operations-guide.md` grew to ~1580 lines as a combined lab/UAT operations manual
across three authoring sessions. Joel requested a short, public-facing rewrite targeting 180–280
lines — same filename, bullet-heavy, no SDDL, no UAT detail, no lab/build appendices.

## Decisions Made

### 1. "8 objects" clarified immediately as 4 + 4

The intro to "What gets deployed" leads with: **"8 objects: 4 Authentication Policies +
4 Authentication Policy Silos."** This prevents the common reader mistake of calling each silo
a separate policy or of expecting 8 silos.

### 2. SDDL reduced to one sentence

Per Joel's explicit instruction: no SDDL strings, no breakdown table. One sentence in "How
the policies and devices are linked" says the deploy module builds the SDDL using OR / "Member
of any" logic — the operator never authors SDDL by hand.

### 3. Enforce flip condensed to 5-step checklist

The 12-gate pre-enforcement gate table was replaced with a 5-step plain-English checklist.
Joel's instruction: "keep this to a few bullets — no giant gate table."

### 4. adminDescription for exclusions called out prominently

Joel specifically flagged this: `adminDescription` is the recommended exclusion attribute because
Exchange does not touch it (Exchange uses `description`). This is called out in a prominent block
under "Exclusions — required decision."

### 5. Appendix B (v1.x → v2.0.0 upgrade) removed from this doc

Joel: "drop it — it's release-notes material." The content still exists in git history. If a
migration guide is needed later it should live in CHANGELOG or a dedicated upgrade doc.

### 6. Scheduling examples grounded in script's actual parameters

Parameters used in examples (`-All`, `-AllTier0`, `-ExclusionAttribute`, `-ExclusionValue`,
`-EnableLogging`, `-EnableEventLog`, `-JobId`, `-WhatIf`) verified against script source
lines 1–220. `-NoProfile` added to all pwsh.exe invocations as best practice.

## Files Changed

- `docs/auth-silos-operations-guide.md` — full overwrite (238 lines)
- `.squad/agents/storm/history.md` — session entry prepended

## Items for Cyclops Verification

- Event IDs 306/106 (TGS service-ticket target restrictions): carried forward from original doc.
  If these were lab-validation-required in the original, Cyclops should remove the table row.
- LDAP simple bind blind spot: original doc marked this [Lab validation required]. Kept as a
  bullet with no validation claim.

---

---

# Decision: Auth Silos Ops Guide — v2 Migration Appendix

**Date:** 2026-09-02
**Author:** Storm (DevRel & Documentation)
**Status:** Proposed — pending Joel review

## Context

Auth silos ops guide revision round 2. Joel added new requirements including a v1.x → v2.0.0
migration appendix, a URA/Restricted-Groups complementary-controls section, factual corrections,
and an IMPORTANT callout at the top.

## Decisions Made

### 1. Migration appendix placed BEFORE Related Reading

Joel specified "before Related Reading." The appendix is long (~130 lines) but self-contained.
Keeping it inside the same file (rather than a separate migration doc) ensures inbound links
from the IMPORTANT callout work and the upgrade procedure is discoverable at the doc that a
v2 admin will be reading anyway.

### 2. Two GPO options (not one)

The appendix offers two paths for the GPO update step:
- **Option 1 (recommended):** rename old GPOs → deploy new ones fresh → verify → delete old.
  Safe because the deploy script is idempotent and the old GPOs continue to apply during cutover
  (lowest link priority buys time to verify).
- **Option 2 (manual):** hand-edit existing GPOs with exact settings. For admins who cannot or
  will not redeploy GPOs.

The governing rule "never overwrite a production GPO in place" is restated in both options.

### 3. Ordered migration steps (Group → User → OuAcls → AuthSilos → Gpos)

This order is required, not advisory:
1. Groups must exist before AuthSilos (deploy fails if device groups are missing).
2. Users (service account) can be created any time after groups, but placing it in Step 1 keeps
   the new-object phase together.
3. OuAcls is harmless at any point but logically belongs with the new-object phase.
4. AuthSilos requires the new device groups from Step 1 — fails if missing.
5. Gpos is last because it carries the most operational risk (live GPO changes).

### 4. Anchor computed as single-hyphen `#appendix-upgrading-from-v1x-to-v200`

Python-Markdown / MkDocs default slugify:
- Lowercase
- Remove non-alphanumeric chars except spaces and hyphens (strips `:` and `.`)
- Spaces → hyphens
- Result for "Appendix: Upgrading from v1.x to v2.0.0": `appendix-upgrading-from-v1x-to-v200`

The task prompt showed a double-hyphen example `#appendix--upgrading-from-v1x-to-v200`; single
hyphen is the correct Python-Markdown output and was used. If the MkDocs build produces a
different anchor, update the IMPORTANT callout link.

### 5. "Auth silos complement URA and Restricted Groups" section added near top

Joel's requirement: silos restrict WHERE (origin device), URA restricts HOW (logon type). Both
are required; they cover each other's gaps. Section placed immediately after the linkage section
so readers who understand the linkage immediately understand why URA is still needed.

### 6. Factual corrections from Joel applied (Part 5)

All 11 corrections applied. Two items remain flagged for Cyclops verification:
- "Script preflight rejects RODCs and non-GC DCs" — stated as Joel-verified; not confirmed
  independently in the 220 script lines read.
- Event 101 (NTLM under enforcement) — Joel's correction; not independently verified.

## Files Changed

- `docs/auth-silos-operations-guide.md` — revised (238 → 422 lines)
- `.squad/agents/storm/history.md` — session entry prepended

---

---

# Decision: Auth Silo Test Realignment — Create-Once Model

**Date:** 2026-08-27  
**Author:** Wolverine (Tester)  
**Status:** Implemented

---

## Context

Commit 244ab52 on `feature/auth-silos` shipped a major behavioral change to the `-IncludeAuthSilos` deploy pipeline:

- **Create-once model**: existing policies/silos are never modified by deploy. No drift/update actions.
- **Deferred SDDL**: plan actions carry `ResolvedSddl = $null`; SID resolution and SDDL construction happen at execution time in `New-TierModelAuthPolicy`.
- **User membership removed**: `memberAccountGroups`, `exemptAccounts`, RID-500 exemption all gone. Silos govern computers only (`memberComputerGroups`).
- **New cmdlet**: `Get-TierModelAuthSiloMembershipFd` — read-only planner with `-OnlyForSilos` filter.

The existing `Unit.AuthSiloOperations.Tests.ps1` (88 tests) was written against the old model and had **18 failures** against the new code.

---

## Decision: Test-code alignment (not production-code change)

Per Joel's standing directive: tests must match the already-validated, committed production code. Where tests disagreed with working code, the tests were wrong.

**Key alignments:**

1. **Planner `ResolvedSddl`**: changed assertion from `Should -Match 'Member_of_any'` to `Should -BeNullOrEmpty` — SDDL is deferred at plan time in the create-once model.
2. **UpdateAuthPolicy / UpdateAuthSilo tests**: removed entirely — these actions do not exist in the create-once planner.
3. **memberAccountGroups / exemptAccounts**: removed from test config object and all related assertions. Production schema no longer has these fields.
4. **Test-TierModelAuthSilo "unexpected member"**: inverted — extra members beyond config are now ALLOWED (informational), not NonCompliant.
5. **Test-TierModelAuthPolicy assertions**: fixed issue message patterns (TGT drift: `'TGT'` not `'UserTGTLifetimeMins'`; SDDL drift: `'AllowedToAuthenticate'` not `'SDDL'`).

---

## Coverage Decisions

Three auth-silo files are below 80% with structural barriers:

| File | Coverage | Barrier |
|------|----------|---------|
| `Set-TierModelAuthSiloMembership.ps1` | 61.5% | 221-command file; ShouldProcess-UserDeclined branch, race-condition "converged-between-precheck-and-write" path, outer catch require interactive confirmation or live-AD |
| `Get-TierModelAuthSiloMembershipFd.ps1` | 64.7% | Inner loop reads `msDS-AssignedAuthNPolicySilo` via `Get-ADComputer`; `Get-ADUser` path never called (computer-only model by design) |
| `New-TierModelAuthSilo.ps1` | 79.8% | Outer catastrophic catch block (requires making `Get-Date` or similar fail); structurally equivalent to `Import-TierModelGpo.ps1` which is also exempted |

**Ruling**: Apply same precedent as `Audit-TierModel.ps1` (77.16%) and `Test-TierModelCanonicalAcl.ps1` (92.86% ByServer-exempt). These files are exempt from the per-file 80% gate for the bounded structural paths. All deployment-critical cmdlets are above 80%.

---

## Update: Coverage Gap-Fill (2026-08-27, second pass)

After the initial rewrite, three files remained below 85%. A targeted second pass brought all auth-silo files to 85%+:

| Script | Before | After |
|--------|--------|-------|
| `New-TierModelAuthSilo` | 79.8% | **99.1%** |
| `Get-TierModelAuthSiloMembershipFd` | 64.7% | **87.8%** |
| `Set-TierModelAuthSiloMembership` | 61.5% | **87.8%** |

**Confirmed unreachable paths (per-silo outer catch):** PowerShell ScriptProperty `{ throw }` returns `""` rather than propagating, confirmed by direct test. The per-silo outer catch (`AuthSiloMembershipFdSiloFailed`, `AuthSiloMembershipSiloFailed`) requires code inside the silo-level try but outside all inner try-catch blocks to throw. All such code paths (HashSet<string> ops, bool expressions, string formatting) are highly robust and won't throw in practice. This catch exists as a defensive safety net only, not for ordinary error scenarios.

**New-TierModelAuthSilo 99.1%:** Only 1 command permanently unreachable: the `'UserDeclined'` branch of `if ($WhatIfPreference) { 'WhatIf' } else { 'UserDeclined' }` — requires interactive ShouldProcess decline.

**Final suite: 1,783 tests, 0 failures, 90.9% overall coverage.**

---

---

# Decision: Authentication Policy Silo Config Schema and 8-Object Model

**Date:** 2026-08-27
**Author:** Beast (Core Developer)
**Branch:** `feature/auth-silos`
**Status:** DRAFT — pending Joel review

---

## Context

The `-IncludeAuthSilos` feature requires a config file defining the Authentication Policy and Authentication Policy Silo objects to be created in AD. This decision records the schema and the 8-object model chosen for `config/tiermodel-authsilos.json`.

---

## Decision

### File and schema

- **File:** `config/tiermodel-authsilos.json`
- **Header fields:** `schemaVersion: "1.0.0"` and `comment` (matching the convention in `tiermodel-winlaps.json`)
- **Top-level arrays:** `authenticationPolicies` (4 objects) and `authenticationSilos` (4 objects)
- **Top-level `exemptAccounts` block:** documents the three structurally exempt domain-join service accounts explicitly, making the invariant visible to the deploy module and reviewers without duplicating their base-config definitions

### 8-object model: 4 policies + 4 silos, 1:1

Each silo references exactly one Authentication Policy. The mapping is:

| Silo | Policy | TGT lifetime |
|---|---|---|
| Tier 0 Admins Authentication Silo | Tier 0 Admins Authentication Policy | 120 min |
| Tier 1 Admins Authentication Silo | Tier 1 Admins Authentication Policy | 240 min |
| Tier 2 Admins Authentication Silo | Tier 2 Admins Authentication Policy | 360 min |
| Tier 2 EUD Authentication Silo | Tier 2 EUD Authentication Policy | null (domain default) |

### SDDL resolved at runtime

The `allowedToAuthenticateFromDeviceGroups` field in each policy object is an array of group samaccountnames (or display names for built-in groups). The deploy module resolves each name to a SID at runtime and constructs the `AllowedToAuthenticateFrom` SDDL using `Member_of_any` (OR logic). SDDL is never authored in the config file.

**Rationale:** Authoring raw SIDs in the config couples the file to a specific domain. Authoring SDDL strings directly increases the risk of introducing AND logic (`Member_of_each`), which is the documented lockout failure mode — it requires a device to simultaneously belong to all listed device groups. `Member_of_any` (OR) is the only semantically correct operator when multiple device groups represent alternate approved device sets.

### Audit-mode default

All eight objects are created with `enforce: false` and `protectedFromAccidentalDeletion: true`. Enforcement is a separate lifecycle step gated on a pre-enforcement safety checklist (see spec 005). The config cannot trigger enforcement; that requires an explicit operator action.

### Domain-join exemption invariant

The three domain-join service accounts (`svc-pawdomainjoin`, `svc-t1srvdomainjoin`, `svc-t2euddomainjoin`) are structurally exempt from all silo membership. They belong to `*DomainJoin` security groups, not `*ServiceAccounts` or `*Admins` groups, so group-scoped silo membership naturally excludes them. The `exemptAccounts` block makes this invariant explicit in the config file. Each account must be recorded in the exemption register with compensating controls.

---

## Rationale for config-only draft (no module code)

The config is authored first so Joel can review and confirm object names, TGT lifetimes, device group assignments, and account group scope before any PowerShell module code is written. Naming conventions and group membership decisions in the config directly determine the module's Grant/Assign logic and cannot be changed cheaply after the module is coded.

---

## Open questions for Joel

1. **Object naming convention** — `"Tier N Admins Authentication Policy"` / `"Tier N Admins Authentication Silo"` — acceptable?
2. **Tier 0 built-in group names** — `"Domain Controllers"` and `"Read-only Domain Controllers"` — correct built-in group display names for the target domain?
3. **Tier 2 EUD `userTGTLifetimeMinutes: null`** — domain default TGT lifetime (typically 10 hours) acceptable for EUD local device operators?
4. **`memberAccountGroups` scope per silo** — should Operators groups (Tier0Operators, Tier0ServerOperators, Tier1Operators, Tier1ServerOperators, Tier2Operators, Tier2DeviceOperators, etc.) also be silo account members, or is the Admins + ServiceAccounts scope correct?


---

---

# Decision: Auth Silos Deploy Cmdlet Set and Integration

**Date:** 2026-08-27
**Author:** Beast (Core Developer)
**Branch:** feature/auth-silos
**Status:** IMPLEMENTATION COMPLETE — awaiting lab validation

---

## Context

This decision documents the cmdlet set and integration choices made when implementing the deploy side of `-IncludeAuthSilos` (audit-mode object creation). The Pester test phase follows lab validation per Joel's directive.

---

## Cmdlet Set

### Public cmdlets (modules/TierModel/public/)

| Cmdlet | Responsibility |
|---|---|
| `Get-TierModelAuthPolicy` | Load raw `authenticationPolicies` array from `config.authenticationPolicies` (populated from tiermodel-authsilos.json). Returns desired-state objects; no AD queries. |
| `Get-TierModelAuthPolicyFd` | Fully-resolved planning: resolve device group names → SIDs via `Resolve-TierModelPrincipalSid`, build SDDL via `Build-TierModelAuthSddl`, query AD for existing policy state, emit `CreateAuthPolicy`/`UpdateAuthPolicy` actions. Returns plan object with `Actions/Summary/Errors`. |
| `Get-TierModelAuthSilo` | Load raw `authenticationSilos` array from config. No AD queries. |
| `Get-TierModelAuthSiloFd` | Fully-resolved planning: validate referenced policy exists in AD, check silo existence, detect drift on Description/policy links/Enforce/PFAD. Emit `CreateAuthSilo`/`UpdateAuthSilo` actions. |
| `New-TierModelAuthPolicy` | Idempotent Create or Update. `New-ADAuthenticationPolicy` for create; `Set-ADAuthenticationPolicy` + `Set-ADObject` for update. Always: `Enforce = $false`, `ProtectedFromAccidentalDeletion = $true`. `UserTGTLifetimeMins` omitted when config value is null (domain default). |
| `New-TierModelAuthSilo` | Idempotent Create or Update. Sets `UserAuthenticationPolicy`, `ComputerAuthenticationPolicy`, `ServiceAuthenticationPolicy` all to the same policy (1:1 design). `Enforce = $false`, `PFAD = $true`. |
| `Set-TierModelAuthSiloMembership` | Expands `memberAccountGroups`+`memberComputerGroups` recursively; skips exempt accounts (3 configured + RID-500 resolved at runtime); two-step `Grant-ADAuthenticationPolicySiloAccess` then `Set-ADAccountAuthenticationPolicySilo` per account; idempotent via pre-check before each step. |
| `Test-TierModelAuthSiloPrerequisite` | Dependency gate: collects all unique group names from `allowedToAuthenticateFromDeviceGroups`, `memberComputerGroups`, `memberAccountGroups`; calls `Get-ADGroup` for each; returns `Passed/Failures/Checked`. Does NOT check individual accounts or GPOs. |

### Private helper (modules/TierModel/internal/)

| Function | Role |
|---|---|
| `Build-TierModelAuthSddl` | Builds `O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(s1), ...}))`. OR-logic ONLY; never AND. |

---

## Key Design Decisions

### 1. Plan-based API (consistent with WinLaps/Audit pattern)

`Get-TierModelAuthPolicyFd` and `Get-TierModelAuthSiloFd` return plan objects with `Actions` arrays, consumed by `New-TierModelAuthPolicy` and `New-TierModelAuthSilo`. This mirrors `Get-TierModelWinLapsAclFd` / `New-TierModelWinLapsAcl`.

`Set-TierModelAuthSiloMembership` takes Config directly (no separate plan) because group membership must be re-evaluated at execution time on every run for idempotency.

### 2. SDDL — OR-logic invariant

`Build-TierModelAuthSddl` always emits `Member_of_any` (OR). AND-logic (`Member_of_each`) is the documented lockout failure mode: it requires a device to simultaneously be in every listed group, which is never true for a "set of approved device types" policy. This is non-negotiable and documented in the private helper's comment block.

### 3. 1:1 policy-to-silo, same policy for all three account classes

Each silo sets `-UserAuthenticationPolicy`, `-ComputerAuthenticationPolicy`, and `-ServiceAuthenticationPolicy` to the same policy name. The tier model has a 1:1 silo-to-policy mapping and no separate per-class policies. Setting all three classes to the same policy ensures complete coverage without requiring a more complex multi-policy design.

### 4. Audit mode — never enforce

All `New-ADAuthenticationPolicy` and `New-ADAuthenticationPolicySilo` calls use `Enforce = $false` (via hashtable splatting). Enforcement is a separate lifecycle step gated on a pre-enforcement safety checklist and is explicitly out of scope. Drift detection in the Fd planners checks `Enforce` and emits `UpdateAuthPolicy`/`UpdateAuthSilo` if it has been accidentally set to true (to re-audit-mode the object).

### 5. ProtectedFromAccidentalDeletion = $true on all objects

Policies and silos are created with `ProtectedFromAccidentalDeletion = $true`. If drift is detected on this property, `Set-ADObject -ProtectedFromAccidentalDeletion $true` is called separately (the `Set-ADAuthentication*` cmdlets do not expose this parameter).

### 6. Grant-then-Set membership order

Always in order: `Grant-ADAuthenticationPolicySiloAccess` first, then `Set-ADAccountAuthenticationPolicySilo`. Idempotency via:
- Grant: check account DN against silo's `Members` list before calling
- Set: check `msDS-AssignedAuthNPolicySilo` on the account before calling

### 7. RID-500 exemption resolved at runtime

The built-in Administrator account is commonly renamed. The function resolves `<DomainSID>-500` at runtime to get the current `SamAccountName`, then adds it to the exemption HashSet. Failure to resolve (DC unreachable) logs a warning but does not halt (the account won't appear in any managed group anyway).

### 8. Deploy-TierModel.ps1 integration

- Standalone mode: prerequisite gate (fail fast), then plan+display, then (if `-ConfirmApply`) execute policies → silos → membership
- FullDeployment planning: Phase 12, manually increments `TotalActions/CreateCount/UpdateCount/AlreadyExistCount` (does not use `Add-IncludeAclPhaseToDeploymentPlan` because that helper is tuned for ACL/SACL action types)
- FullDeployment execution: inside the optional features block after audit; all three results (`authPolicyExecResult`, `authSiloExecResult`, `authMembershipExecResult`) added to `$allResults` for consolidated reporting

### 9. Get-TierModelConfig optional file

`tiermodel-authsilos.json` added to `$optionalFiles` in `Get-TierModelConfig`. Absent file → `authenticationPolicies`, `authenticationSilos`, `authSilosExemptAccounts` are all `$null` on the config object. All auth silo cmdlets handle `$null` gracefully (return empty arrays / empty plans).

---

## Open Items for Lab Validation

1. **Enforce parameter behavior**: Verify `Enforce = $false` in hashtable splatting has identical behavior to `-Enforce:$false` direct named param with `New-ADAuthenticationPolicy`.
2. **SDDL round-trip**: Verify that `Get-ADAuthenticationPolicy -Properties *` returns `UserAllowedToAuthenticateFrom` in the same SDDL format as was written (whitespace normalization may be needed; current comparison normalizes whitespace).
3. **TGT lifetime property name**: Verify whether `Get-ADAuthenticationPolicy` returns `UserTGTLifetimeMins` as a direct property or only `msDS-UserTGTLifetime` (100-ns intervals). Both fallbacks are implemented.
4. **Silo policy property names**: Verify whether `Get-ADAuthenticationPolicySilo` returns `UserAuthenticationPolicy` / `ComputerAuthenticationPolicy` / `ServiceAuthenticationPolicy` as friendly names or DNs — drift detection normalizes DN→name but this needs lab confirmation.
5. **Empty groups**: Confirm that `Get-ADGroupMember -Recursive` on an empty group returns an empty array (not an error) on Server 2022/2025.
6. **Grant idempotency**: Verify `Grant-ADAuthenticationPolicySiloAccess` does not throw if the account is already in the silo's Members list (the pre-check guards against this but verify error behavior if the check races).

---

### 2026-08-27T11:24:19+08:00: User directive — code-first, tests-after (no TDD)

**By:** Joel Platek (via Copilot)

**What:** For the auth-silos work and generally on this project: write the code and validate it **in the lab first**; only **after** it is working do we write the test cases (Pester) against the working code. Do NOT write test cases first. Sequence: Deploy code → lab-validate → Deploy tests → then Audit code → lab-validate → Audit tests.

**Wolverine, note:** writing test cases first was a mistake last time. Author tests only against code that has already been lab-validated as working.

**Why:** User request — captured for team memory; Wolverine must be informed before any test authoring.

---

### 2026-08-27T11:55:00+08:00: User directive — module placement + confirm drastic changes

**By:** Joel Platek (via Copilot)

**What:** All TierModel PowerShell module functions/helpers MUST live under `modules/TierModel/public/`. Do NOT place new functions under `modules/TierModel/internal/`. When a structural or placement choice is drastically different from existing convention, CONFIRM the placement with Joel BEFORE proceeding (do not silently deviate).

**Applies to:** Beast and all agents authoring module code; and the coordinator (must flag drastic deviations for confirmation).

**Context:** `Build-TierModelAuthSddl.ps1` was initially placed under `internal/`; it has been moved to `public/` and added to `FunctionsToExport`.

**Why:** User request — captured for team memory.

---

# Decision: Storm v2.0.0 Appendix B — Auth Silos BREAKING CHANGE Documentation

**Date:** 2026-08-26  
**Author:** Storm (Documentation)  
**Branch:** `feature/auth-silos`  
**Status:** DRAFT — working tree only, no commit

## Decision

`docs/auth-silos-operations-guide.md` has been extended with `## Appendix B — Upgrading from v1.x.x to v2.0.0` documenting the complete v2.0.0 delta and the breaking change posture for existing deployments.

## Key Rulings

1. **Breaking change classification confirmed.** Version 2.0.0 modified several link-enabled production GPOs (new settings + new `SeDeny*` deny entries). This is a breaking change for v1.x.x deployments; an upgrade path must be explicitly planned.

2. **Governing rule documented prominently:** "Never replace or overwrite a GPO that is already in production." This rule is stated in a blockquote callout at the top of Appendix B and must not be contradicted anywhere in the guide.

3. **Sub-appendix structure (B.1–B.4) is reserved.** Each sub-section is currently a stub. Full remediation procedures are to be added per-topic in future sessions. The structure must not be renamed or reordered — other team members and future sessions will slot content into B.1–B.4 by name.

4. **v2.0.0 delta inventory locked** (from task spec and `config/tiermodel-gpos.json`):
   - New groups: `Tier2EUDDevices` (Universal), `Tier2PAWDevices` (Universal), `Tier2EUDDomainJoin` (Global)
   - New service account: `svc-t2euddomainjoin` (disabled; member of `Tier2EUDDomainJoin`)
   - New ACL: `Tier2EUDDomainJoin` → OU=Tier 2 End-User Devices (standard domain-join set; no staging OU)
   - Modified GPO: `*- Tier 0 DCs Authentication Silo - Computer` (KDC claims, client armoring, Remote Credential Guard, event-log channel)
   - Modified GPOs: all Tier 0/1 Account Restrictions (root + servers/PAWs + Override templates) — `Tier2EUDDomainJoin` added to `SeDeny*`

5. **Member-server Remote Credential Guard GPO flagged "still being finalized."** This content is excluded from the current appendix and must be added before the appendix is considered complete.

---
