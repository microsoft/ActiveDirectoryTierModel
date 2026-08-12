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

