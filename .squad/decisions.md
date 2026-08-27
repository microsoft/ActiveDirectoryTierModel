# Squad Decisions

## Active Decisions (2026-08-25)

*Active decisions from the current retention window. Older entries are archived in decisions-archive.md.*

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

# Decision: Auth Silos Format-Duration Contract Locking

**Date:** 2026-08-24  
**Author:** Wolverine (Logan)  
**Branch:** feature/format-duration  
**Status:** ✅ DECIDED — Banker's rounding regression guards locked in

Unit tests for `Format-TierModelDuration` written AFTER lab validation of implementation. The trio of boundary values `90000 / 119999 / 120000` locks regressions that would occur if future refactors reach for `[int][TimeSpan]::TotalMinutes` (banker's rounding). Tests are not exploratory — they lock known-correct behavior proven in production. Integration wiring verified via discriminating DurationMs values (2254ms → '2s', 140000ms → '2m 20s').

---

# Decision: Beast Format-TierModelDuration Design Recommendation

**Date:** 2026-08-24  
**Author:** Beast (Dr. Hank McCoy)  
**Issue:** #34 — Format deployment duration in seconds/minutes instead of raw milliseconds  
**Status:** IMPLEMENTATION COMPLETE (2026-08-24) — awaiting Joel lab acceptance validation

Implementation delivers 4-tier public function with floor-based arithmetic (no banker's rounding). All 9 Write-Host call sites updated in Deploy-TierModel.ps1; 2 Write-TierModelLog sites kept raw. Function accepts `[double]` to handle both int and double DurationMs values. Critical fix for minute math: `[Math]::Floor` used instead of `[int]` cast to guarantee monotonic output (90000ms→1m 30s, not 2m 30s). Lab acceptance requires manual DC01 validation of three scenarios (seconds/milliseconds/minutes branches).

---

# Decision: Professor X Auth Silos Spec Scoping — All-Tier Four-Silo Model Final

**Date:** 2026-08-24  
**Author:** Professor X (Lead)  
**Branch:** feature/auth-silos  
**Spec:** specs/005-auth-silos/spec.md  
**Status:** ✅ ALL-TIER SCOPE APPROVED — Final scoping decisions locked

All four tiers in scope (Tier 0 Admin, Tier 1 Admin, Tier 2 Admin, Tier 2 EUD). No fifth silo for general population. CON-009 decision documents the scope table. Tier 2 explicitly included via four-silo model (Joel approval 2026-08-24). Structural exemptions for domain-join accounts (svc-pawdomainjoin / svc-t1srvdomainjoin / svc-t2euddomainjoin) documented as CON-010. Tier 2 EUD provisioning config (group / staging OU / delegated ACL / Account Restriction GPO) required as base-config prerequisite (Task T009). SDDL enforcement boundary explicitly documented: silos gate Kerberos TGT at AS exchange, distinct from URA logon rights and TGS service-ticket control.

---

# Decision: Storm Auth Silos Operations Guide Docs

**Date:** 2026-08-24  
**Author:** Storm (Documentation)  
**Branch:** feature/auth-silos  
**Status:** DRAFT — pending lab validation

Config A (user `AllowedToAuthenticateFrom` via single `T0-ApprovedDevices` group) is primary walkthrough; Config B (advanced service-ticket `AllowedToAuthenticateTo`) documented as optional, not walked through. Origination Device Rule taught as primary concept before PowerShell (correct mental model vs. misleading "add your PAW" framing). Event IDs 4820/4821 marked `[Lab validation required]` (undocumented, unconfirmed field structure). AuthenticationPolicyFailures-DomainController channel enable required as first step (channel off by default — silent readiness failure if omitted). RID-500 platform exemption documented explicitly. Account lifecycle vs device lifecycle separation documented in leaver procedure. UAT table with 15 test cases indexed by scenario/mode/expected outcome.

---

# Decision: Audit UNION Converge Ruling

**Date:** 2026-08-14  
**Author:** Joel Platek (via Copilot coordinator)  
**Feature:** `-EnableAuditing` (branch `feature/domain-auditing`)  
**Status:** ✅ VALIDATED — ready for production implementation

Canonical Everyone/Success/All ACE rights = **UNION of (existing managed-ACE rights) ∪ (canonical 9 rights)**. Preserve customer rights outside our 9 while GUARANTEEING our 9. Lab-validated converge mechanics: Read SACL; enumerate GetAuditRules() with foreach; compute union; if single managed ACE matches → no-op; else remove each managed ACE, add canonical union ACE, Set-Acl. Managed scope = SID=S-1-1-0, AuditFlags=Success, InheritanceType=All, non-inherited. All other ACEs untouched. Requires SeSecurityPrivilege. Bind read+write to one preferred DC. Two default Everyone/Success/All/WriteProperty ACEs absorbed into canonical ACE — no coverage loss.

---

# Decision: Domain-Root Audit SACL Spec

**Date:** 2026-08-14  
**Author:** Cyclops (Scott Summers)  
**Branch:** feature/domain-auditing  
**Status:** ✅ SPEC APPROVED — locked design, ready for implementation

SACL only (not DACL); avoid "delegation" language. Enumerate GetAuditRules() via foreach, not @(). Read-modify-write on same $acl object. No PurgeAuditRules (removes default SACLs outside managed scope). UNION target = existing managed rights ∪ canonical 9. Privilege check first; emit AUDITACL_PRIVILEGE_MISSING if SeSecurityPrivilege missing. Pester: all AC-* criteria + offline fixtures. Docs: remove Enable-TierModelAuditing.ps1 reference; state both SACL AND GPO required; note SACL replication delay. OI-001: retire optional/Enable-TierModelAuditing.ps1.

---

# Decision: -EnableAuditing Production Implementation (Build Discovery)

**Date:** 2026-08-14  
**Author:** Beast (Core Dev)  
**Branch:** feature/domain-auditing  
**Status:** DRAFT — discovery documented

Discovery 1: `Add-IncludeAclPhaseToDeploymentPlan` PSObject fragility — function checks `$Plan.Summary.PSObject.Properties.Name` which fails for @{} hashtable Summaries. Extended with `$Plan.Summary -is [hashtable] -and .ContainsKey('key')` as second-pass test. Recommendation: standardize all Summaries to [PSCustomObject] in separate refactoring PR. Discovery 2: UNION always includes WriteProperty on clean domain root (two default Everyone/Success/All/WriteProperty ACEs in managed scope). Idempotent and correct. Discovery 3: Double-Y confirm flow not testable non-interactively (Read-Host hangs over PowerShell Direct). Deferred to Joel's manual UAT.

---

# Decision: Pre-PR Cleanup Rulings

**Date:** 2026-08-14  
**Author:** Joel Platek (via Copilot coordinator)  
**Feature:** `-EnableAuditing` (branch `feature/domain-auditing`)  
**Status:** ✅ DECIDED

OI-001 RESOLVED — RETIRE `optional/Enable-TierModelAuditing.ps1` (delete, not archive; remove packaging/test references). Temp directory cleanup completed (repo-root `Temp\` held stale `TestGPO_Mock.inf`, now removed). Root cause: `Test-TierModelGPOContent.ps1` (~lines 76-86) writes `<GPOName>_Mock.inf` to `Temp\`, never cleans up. Not fixed in this PR (unrelated to auditing). Follow-up for Wolverine's test phase: add teardown/cleanup of `Temp\` mock artifacts to invoke-all/Pester harness.

---

# Decision: SACL Audit — Read API, Merge Behaviour, Converge Recipe

**Date:** 2026-08-14  
**Author:** Beast (Core Dev)  
**Status:** ✅ VALIDATED — empirical proof of merge/idempotency/no-clobber logic

Chosen API: `Get-Acl -Path "AD:<dn>" -Audit` / `Set-Acl -Path "AD:<dn>" -AclObject <obj>`. Privilege: SeSecurityPrivilege required. Key gotcha: GetAuditRules() returns AuthorizationRuleCollection — do NOT wrap with @() (wraps entire collection as 1 element). Enumerate via foreach. AddAuditRule behavior: MERGES rights into existing ACE when SID/AuditFlags/InheritanceType match (no duplicate). Converge recipe locked: read+modify same acl object; enumerate managed ACEs; remove all managed; add canonical union ACE; Set-Acl. Idempotency PASS (zero writes when canonical already exists). No-clobber PASS (unrelated ACEs untouched). Baseline default SACLs: 5 rules observed (2 identical Everyone/Success/All/WriteProperty defaults will be replaced by canonical ACE).

---

# Decision: -EnableAuditing Design Rulings (Joel)

**Date:** 2026-08-14  
**Author:** Joel Platek  
**Feature:** New `-EnableAuditing` deployment parameter (branch `feature/domain-auditing`)  
**Status:** ✅ APPROVED — 5 rulings locked

1. Cmdlet naming: Get-TierModelAuditRule, New-TierModelAuditRule, Test-TierModelAuditRule, Get-TierModelAuditRuleFd (audit-specific verbs; avoid *Acl/"delegation" language). 2. Partial-rights drift = MERGE (preserve existing rights, add only missing). Lab spike required BEFORE production code (COMPLETED — validated on DC). 3. Advanced Audit Policy dependency = doc only, no code check (GPO already deployed by default). 4. No rollback cmdlet for now (environment-specific; coverage via confirm-Y warning + output of added rights). 5. Audit script scope mirrors deployment (audit SACL only when `-EnableAuditing` passed, mirroring `-IncludeGmsa` pattern). Version 1.2.0→1.3.0 (additive minor). Sequence: spike → Joel review → production code → restore checkpoint → team tests → Joel UAT → fix audit script → Pester tests LAST.

---

# Decision: Move Pester Side-by-Side Advisory to EnvironmentSnapshot

**Date:** 2026-08-11  
**Author:** Beast (Dr. Hank McCoy)  
**Requested by:** Joel Platek  
**Status:** ✅ IMPLEMENTED — Canonical-ACL finalization batch (pending owner code review)

## Problem

`Test-TierModelPrerequisites.ps1` had a non-blocking advisory (Pester 5.x + 6.x side-by-side) writing into `$result.Remediation`. Because `Write-TierModelFailFast` renders the entire `Remediation` list whenever any prerequisite blocks, this orphaned advisory appeared in fail-fast output for unrelated failures (e.g. the canonical-ACL gate), confusing operators.

## Decision

Record the side-by-side advisory in `$result.EnvironmentSnapshot.PesterAdvisory` instead of `$result.Remediation`. `Valid` remains unchanged (non-blocking). Blocking branches (Pester not installed; no 5.x present) are untouched.

## Changes

| File | Change |
|------|--------|
| `modules/TierModel/public/Test-TierModelPrerequisites.ps1` | Third Pester `elseif` branch: replaced `$result.Remediation.Add(...)` with `$result.EnvironmentSnapshot.PesterAdvisory = ...`; updated branch comment. |
| `tests/Unit.Prerequisites.Tests.ps1` | Updated "side-by-side" test assertions from `$result.Remediation` to `$result.EnvironmentSnapshot.PesterAdvisory`; added negative assertion that advisory is NOT in Remediation; renamed test to "(non-blocking advisory in EnvironmentSnapshot)". |

## Validation

- Parse errors: 0 (both files)  
- Pester targeted run (`*side-by-side*`): **1 passed, 0 failed**  
- `Import-Module .\modules\TierModel\TierModel.psd1 -Force`: clean, v1.2.2  
- Safety grep across `tests/` for other consumers of the advisory in Remediation: none found.

---

# Cyclops Review — Non-Canonical Root ACL Pre-Flight Gate

**Reviewer:** Cyclops (Scott Summers)  
**Requested by:** Joel Platek  
**Date:** 2026-08-11T21:15:57+08:00  
**Branch:** `fix/bug-006-canonical-acl-check`  
**Verdict: ✅ APPROVE WITH NITS** — Canonical-ACL finalization batch (both nits fixed)

---

## Review Findings Summary (ABRIDGED)

This change is architecturally sound, correctly designed, and safe to ship. Two nits identified:

### Nit 1 — Exception catch path now emits Write-Warning (✅ FIXED)
`Test-TierModelPrerequisites.ps1` catch block now includes `Write-Warning "Canonical ACL check skipped: $($_.Exception.Message)"` for operator visibility.

### Nit 2 — Stale "pending sign-off" doc note removed (✅ FIXED)
`docs/canonical-acl.md` Symptom section: removed Note callout claiming "exact wording pending final sign-off". Message is finalized and tested.

---

## Full Verdict

**Security / Safety — PASS:** Detect-only confirmed (zero writes). Gate fails CLOSED. Partial-apply impossible (Valid=$false triggers exit before any AD mutation).

**Correctness — PASS:** Detection API correct. Rank scan logic correct. Returns proper PSCustomObject structure.

**Gate Placement — PASS:** Unconditional, after cheaper checks, guarded by AD module check. Both callers (Deploy/Audit) respect `.Valid=$false`.

**Pester Advisory Change — PASS:** Blocking branches untouched; non-blocking advisory correctly isolated to EnvironmentSnapshot.

**Tests — PASS:** 22 new tests (18 ByBytes offline + 4 gate integration). 1,457/1,457 suite all green. Zero regressions. ByServer live-LDAP limitation accepted.

**Standards — PASS:** Module conventions, verb, export order, help docs all consistent.

**Docs Accuracy — PASS:** Numbers internally consistent. BUG-006 label not leaked to public docs. Guidance technically sound.

**APPROVE WITH NITS (now APPROVED: both nits fixed in finalization batch).**

---

# Test Report: Canonical ACL Gate — Unit Tests (Pester 5.x)

**Date:** 2026-08-11T20:46:31+08:00  
**Author:** Wolverine (Logan)  
**Requested by:** Joel Platek  
**Branch:** fix/bug-006-canonical-acl-check  
**Status:** ✅ DELIVERED — Canonical-ACL finalization batch

---

## Deliverables

### New file: `tests/Unit.CanonicalAcl.Tests.ps1`
18 tests covering `Test-TierModelCanonicalAcl` via the ByBytes path (fully offline).  
Contexts: Fixture self-consistency (3), Canonical DACL (4), Non-canonical DACL (3), Multi-violation (2), Parameter-set (2), Return object structure (4).

### Appended to: `tests/Unit.Prerequisites.Tests.ps1`
4 gate tests in new `Context "Canonical ACL gate"` inside the Extended Coverage Describe:
- Non-canonical + named principal → Valid=$false, correct errors + remediation, RootAclCanonical=$false
- Non-canonical + null principal → fallback error message
- Canonical → no error added, RootAclCanonical=$true
- Exception → RootAclCheckError set, no hard-fail

**Total new tests: 22** (18 + 4)

---

## Full Suite Results — Pester 5.9.0

| Metric | Value |
|--------|-------|
| TOTAL  | 1457  |
| PASS   | 1457  |
| FAIL   | 0     |
| SKIP   | 0     |

**Module-scope coverage:** 91.13%  
**Per-file coverage:**
- `Test-TierModelCanonicalAcl.ps1`: 58.93% (ByServer branch offline-untestable)
- `Test-TierModelPrerequisites.ps1`: 85.03%

**ZERO regressions. ZERO failures caused by our changes. ✅**

---

# Decision: Repro snippet for BUG-006 lives only in the doc

**Date:** 2026-08-11  
**Author:** Storm  
**Status:** ✅ DECIDED — Canonical-ACL finalization batch

## Context

BUG-006 (non-canonical domain-root ACL) required a diagnostic PowerShell snippet. Snippet is reproduced in `docs/canonical-acl.md` as a fenced code block and NOT shipped as a standalone script file.

## Rationale

- Keeping it embedded in the doc lives next to its explanation, context, and caveats.
- Does not imply it is a supported product cmdlet (it is a one-off diagnostic aid).
- Research/lab original remains in `.research/` for Beast/Wolverine reference.

---

# Cyclops Inbox: Architecture Note — Domain-Root Audit SACL Spec (2026-08-14)

**By:** Cyclops (Scott Summers)  
**Date:** 2026-08-14T16:54:43+08:00  
**Branch:** `feature/domain-auditing`  
**Source:** `.squad/decisions/inbox/cyclops-audit-spec.md`

Spec authored and ready. No new design decisions — documents locked design from earlier decisions. Key implementation signals:

- SACL only, not DACL; avoid "delegation" language
- Enumerate `GetAuditRules()` with `foreach`, not `@()`
- Read-modify-write on same `$acl` object
- No `PurgeAuditRules` (removes default SACLs outside managed scope)
- UNION target = existing managed rights ∪ canonical 9
- Privilege check first; emit `AUDITACL_PRIVILEGE_MISSING` on missing `SeSecurityPrivilege`
- Pester: all AC-* criteria + offline fixtures
- Docs: remove Enable-TierModelAuditing.ps1 reference; state both SACL AND GPO required; note SACL replication delay
- OI-001 decision: retire optional/Enable-TierModelAuditing.ps1

---

# Beast Inbox: Build Discovery — -EnableAuditing Production Implementation (2026-08-14)

**Author:** Beast (Core Dev)  
**Branch:** `feature/domain-auditing`  
**Status:** Draft for Joel review  
**Source:** `.squad/decisions/inbox/beast-audit-build.md`

## Discovery 1: `Add-IncludeAclPhaseToDeploymentPlan` PSObject fragility

Existing function checks `$Plan.Summary.PSObject.Properties.Name -contains 'key'`, which fails for `@{...}` hashtable Summaries. Extended function to check `$Plan.Summary -is [hashtable] -and .ContainsKey('key')` as second-pass test, plus extended `ConfigureAuditRule` fallback action counting.

**Recommendation:** Future cmdlets use `[PSCustomObject]` (not `@{}`) for Summary objects, or add their action type to fallback filter. **Owner decision:** standardize all Summaries to `[PSCustomObject]`? Beast recommends yes, but in a separate refactoring PR, not now.

## Discovery 2: UNION always includes WriteProperty on clean domain root

Clean `DC-Promoted-Clean` baseline has two default `Everyone/Success/All/WriteProperty` ACEs in managed scope. UNION target includes these, producing the canonical 9. Idempotent and correct. **No action.**

## Discovery 3: Double-Y confirm flow not testable non-interactively

The `-EnableAuditing -ConfirmApply` gate uses `Read-Host`, which hangs over PowerShell Direct. **Deferred to Joel's manual UAT.** Code is correct; just not automatable.

---

# Coordinator Inbox: Audit UNION Converge Ruling (2026-08-14)

**By:** Joel Platek (via Copilot coordinator)  
**Feature:** `-EnableAuditing` (branch `feature/domain-auditing`)  
**Source:** `.squad/decisions/inbox/coordinator-audit-union-ruling.md`

Canonical Everyone/Success/All ACE rights = **UNION of (any existing managed-ACE rights) ∪ (canonical 9 rights)**. Preserve customer rights outside our 9 while GUARANTEEING our 9. Do NOT overwrite to "exactly 9".

**Managed scope:** SID=S-1-1-0, AuditFlags=Success, InheritanceType=All, non-inherited. Everything else untouched (no-clobber, proven in lab spike).

**Converge mechanics (lab-validated):**
1. Read SACL via `Get-Acl -Audit`
2. Enumerate `GetAuditRules()` with `foreach` (not `@()`)
3. Compute union target
4. If single managed ACE already equals union → no-op
5. Else: `RemoveAuditRuleSpecific` each managed ACE (same `$acl` object), then `AddAuditRule` canonical union ACE
6. `Set-Acl`

Requires `SeSecurityPrivilege`. Bind read+write to one preferred DC (SACL replicates). Note: two default `Everyone/Success/All/WriteProperty` ACEs are absorbed into canonical ACE — no coverage loss.

---

# Coordinator Inbox: Pre-PR Cleanup Rulings (2026-08-14)

**By:** Joel Platek (via Copilot coordinator)  
**Feature:** `-EnableAuditing` (branch `feature/domain-auditing`)  
**Source:** `.squad/decisions/inbox/coordinator-pre-pr-cleanup.md`

**OI-001 RESOLVED — RETIRE `optional/Enable-TierModelAuditing.ps1`**

Delete entirely before final PR (not archive). Remove packaging/test references. Storm updates docs separately. File is fully superseded by `-EnableAuditing` / new AuditRule cmdlets.

**Temp directory cleanup — completed this session**

Repo-root `Temp\` held stale `TestGPO_Mock.inf` (gitignored). Removed.

**ROOT CAUSE:** `modules/TierModel/public/Test-TierModelGPOContent.ps1` (~lines 76-86) writes `<GPOName>_Mock.inf` into `Temp\` and never cleans up. **Not fixed in this PR** (unrelated to auditing, no existing-cmdlet changes in this branch).

**Follow-up for Wolverine's test phase:** Add teardown/cleanup of `Temp\` mock artifacts to invoke-all/Pester harness so runs leave clean tree.

---

# Design Decision: SACL Audit — Read API, Merge Behaviour, Converge Recipe

**Date:** 2026-08-14  
**Author:** Beast (Core Dev)  
**Status:** VALIDATED — ready for Joel's go/no-go on production implementation  
**Spike script:** `.research/copilot-cli-hyperv-ad-lab/scripts/audit-spike/Invoke-AuditSpikeRepro.ps1`

---

## Context

Planning `-EnableAuditing` deployment parameter that writes a SACL audit ACE to the domain root to feed Microsoft Sentinel. The existing `optional/Enable-TierModelAuditing.ps1` was identified as having a re-run bug (stacks duplicate ACEs). Before writing production code, Joel required empirical proof of the merge/idempotency/no-clobber logic.

---

## Decision 1: SACL Read/Write API

**Chosen:** `Get-Acl -Path "AD:<dn>" -Audit` / `Set-Acl -Path "AD:<dn>" -AclObject <obj>`

**Rejected:** `DirectoryEntry.Options.SecurityMasks` — property not available on this OS/PS combination.

**Requirement:** `Import-Module ActiveDirectory` must precede the call to make the `AD:` PSDrive available.

**Privilege:** `SeSecurityPrivilege` is required. Production code must surface a clear error if not present. In deployment context the caller runs as Domain Admin which holds this privilege.

**Key gotcha:** `GetAuditRules()` returns `AuthorizationRuleCollection` — NOT a PowerShell array. Wrapping with `@()` produces a 1-element array containing the whole collection. Must enumerate via `foreach ($r in $collection)` or pipeline.

---

## Decision 2: AddAuditRule merge vs duplicate

**Empirical result: AddAuditRule MERGES rights** into an existing ACE when SID / AuditFlags / InheritanceType match. It does NOT create a duplicate ACE.

**Caveat:** The clean domain root already has TWO identical `Everyone/Success/All/WriteProperty` ACEs (default Windows SACLs). When those two managed ACEs are present, AddAuditRule merges into one of them, leaving the second unchanged. Result: count stays the same but state remains multi-ACE. A naïve "did count increase?" merge check is therefore unreliable.

**Implication for production code:** Cannot rely on AddAuditRule alone to converge to a single canonical ACE. Must use the recipe below.

---

## Decision 3: Converge recipe (validated)

```powershell
# Read and modify via the SAME acl object (cross-object RemoveAuditRuleSpecific silently no-ops)
$acl = Get-Acl -Path "AD:$domainDN" -Audit

# Enumerate managed ACEs from this acl object
$managedAces = [System.Collections.Generic.List[...]]::new()
foreach ($r in $acl.GetAuditRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
    if ($r.IdentityReference.Value -eq 'S-1-1-0' -and
        $r.AuditFlags -eq [AuditFlags]::Success -and
        $r.InheritanceType -eq [ActiveDirectorySecurityInheritance]::All -and
        -not $r.IsInherited) { $managedAces.Add($r) }
}

# Check if already complete: exactly 1 ACE with all 9 rights
$presentInt = [int]0
foreach ($a in $managedAces) { $presentInt = $presentInt -bor [int]$a.ActiveDirectoryRights }
$alreadyDone = ($managedAces.Count -eq 1) -and ((([int]$targetRights) -band (-bnot $presentInt)) -eq 0)
if ($alreadyDone) { return }   # idempotent — no write

# Converge: remove old managed ACEs, add canonical
foreach ($a in $managedAces) { $acl.RemoveAuditRuleSpecific($a) }
$acl.AddAuditRule(<canonical-9-right-rule>)
Set-Acl -Path "AD:$domainDN" -AclObject $acl
```

**Why not PurgeAuditRules(SID)?** It removes ALL ACEs for Everyone, including the default `Everyone/Success/None/WriteProperty,WriteDacl,WriteOwner` ACE (Inherit=None) which is not ours to touch.

---

## Decision 4: Scope of converge — managed ACE definition

Managed = `SID=S-1-1-0, AuditFlags=Success, InheritanceType=All, IsInherited=false`.

Everything else is left untouched:
- Other SIDs (e.g. S-1-5-32-544 Administrators)
- Other AuditFlags (e.g. Failure)
- Inherit=None ACEs (default domain-root SACLs)
- IsInherited=true ACEs

---

## Decision 5: Baseline default SACLs on clean domain root

5 default rules observed on `DC=tierlab,DC=internal` (DC-Promoted-Clean checkpoint):

| SID | AuditFlags | Inheritance | Rights |
|-----|-----------|-------------|--------|
| S-1-1-0 | Success | None | WriteProperty, WriteDacl, WriteOwner |
| S-1-5-32-544 | Success | None | ExtendedRight |
| Domain-SID-513 | Success | None | ExtendedRight |
| S-1-1-0 | Success | All | WriteProperty |
| S-1-1-0 | Success | All | WriteProperty *(duplicate)* |

**Note:** The two identical `Everyone/Success/All/WriteProperty` ACEs are a Windows default artefact. The converge recipe will replace both with the single canonical ACE (all 9 rights). This is a beneficial side effect — it cleans up the pre-existing duplication.

**Production question for Joel:** Is it acceptable to replace these two default `Everyone/Success/All/WriteProperty` ACEs with our canonical ACE? The canonical ACE is a superset (it includes WriteProperty plus 8 more rights), so Sentinel coverage is extended, not reduced. Joel should confirm before we ship.

---

## Decision 6: Idempotency and no-clobber — confirmed

- **Idempotency PASS:** When the canonical ACE already exists (1 ACE, all 9 rights), converge detects "already up to date" and performs zero writes.
- **No-clobber PASS:** `Everyone/Failure/All/ReadProperty` ACE seeded alongside the canonical ACE; survived the converge untouched. Converge is scoped to `AuditFlags=Success` only.

---

## Decision 7: Planning output data shape — confirmed available

The planning layer can report:
- `Status`: ABSENT / PARTIAL / COMPLETE / MULTI-ACE
- `ExistingRights` (N/9 count) — which of the 9 target rights are present
- `MissingRights` (N/9 count) — which are absent
- `WillAdd` — what will be written on the next converge run
- `TotalSaclRules` — total explicit non-inherited rules on domain root

This maps cleanly to the deployment "yellow = to-create, green = already exists, total counts" convention.

---

## Multi-DC Note

Lab is single-DC; this was not tested. In production:
- Bind SACL reads and writes to one preferred DC by FQDN.
- The SACL replicates to other DCs via normal AD replication (USN-based).
- Do not write to multiple DCs in the same operation — risk of conflict/collision.

---

### 2026-08-14: -EnableAuditing design rulings (from Joel / @VAsHachiRoku)

**By:** Joel Platek (via Copilot coordinator)
**Feature:** New `-EnableAuditing` deployment parameter (branch `feature/domain-auditing`)

**Decisions:**
1. **Cmdlet naming approved:** `Get-TierModelAuditRule`, `New-TierModelAuditRule`, `Test-TierModelAuditRule`, `Get-TierModelAuditRuleFd` (audit-specific verbs/counts; avoid `*Acl`/"delegation" language since this is a SACL, not a DACL).
2. **Partial-rights drift = MERGE.** When an audit ACE already exists on the domain root, add only the MISSING rights and preserve existing rights. Do NOT nuke/replace unrelated customer audit ACEs. **Must be validated in the lab with a throwaway spike script BEFORE writing production code** (seed an existing partial Everyone/Success ACE, run merge logic, confirm output + idempotency).
3. **Advanced Audit Policy dependency = doc only, no code check.** The DC advanced-audit GPO is already deployed and linked by default. `docs/sentinel-monitoring.md` must state that BOTH the auditing SACL (via `-EnableAuditing`) AND the GPO (configured + link enabled — link is on by default) are required for monitoring to function.
4. **No rollback/disable cmdlet for now.** Rollback is environment-specific (can't reliably know which of the added rights/ACEs to remove). Coverage is the `-EnableAuditing` confirm-Y warning + showing which ACL rights we add at deploy time. Operators own their own rollback.
5. **Audit script scope mirrors deployment.** `Audit-TierModel.ps1` checks auditing ONLY when `-EnableAuditing` is passed (same as `-IncludeGmsa` gating gMSA audit). What you deploy is what you audit.

**Sequence:** lab spike to prove merge logic + output → Joel reviews/confirms spike results if needed → write production code → restore `WinLapsSchema` checkpoint → team tests code → Joel does manual lab deployment UAT → fix audit script → Pester tests LAST.

**Version:** manifest bump 1.2.0 → 1.3.0 (additive minor feature).

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

