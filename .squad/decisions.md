# Squad Decisions

## Active Decisions (2026-08-11)

*Active decisions from the current retention window. Older entries are archived in decisions-archive.md.*

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

