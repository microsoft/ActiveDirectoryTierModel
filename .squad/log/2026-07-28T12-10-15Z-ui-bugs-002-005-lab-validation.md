# Session Log: UI Bugs BUG-002 + BUG-005 Hyper-V Lab Validation

**Date:** 2026-07-28  
**Requested by:** Joel Platek  
**Objective:** Validate UI bug fixes on live Hyper-V AD lab before merge to main

---

## Summary

Two UI bug fixes on branch fix/ui-bugs-002-005 (commit 32b748f) were validated on live Hyper-V lab (TierLab-DC01, checkpoint WinLapsSchema):

| Bug | Description | Status |
|-----|-------------|--------|
| BUG-002 | `-UserOnly` preview now shows specific per-dependency ❌ error messages | ✅ PASS |
| BUG-005 | `-FullDeployment -IncludeWinLaps` Phase 10 shows ⚠ warnings (not ❌ errors) | ✅ PASS |

**Review Verdict:** Cyclops reviewed source code and confirmed both fixes are sound. ✅ APPROVED.

---

## Lab Validation Detail

### Wolverine (Tester)
- Deployed 399-file working tree to guest C:\TierModel
- Ran BUG-002 scenario: `-UserOnly` preview
  - **Output:** Specific ❌ messages under `Dependency Errors:` header ✓
  - 4× error lines naming missing Groups/OUs ✓
  - Resolve message ✓
- Ran BUG-005 scenario: `-FullDeployment -IncludeWinLaps -IncludeMsa -IncludeGmsa -IncludeDmsa` preview
  - **Output:** 7× yellow ⚠ "GPO not found" warnings ✓
  - `Actions planned: 21` ✓
  - Zero red ❌ planning errors ✓
- Resolved Pester version gate (installed 5.7.1, removed 6.0.0/5.9.0) to clear prerequisite validation

### Cyclops (Architect & Reviewer)
- Reviewed Deploy-TierModel.ps1 lines 2034–2044 (BUG-002 render)
- Reviewed Deploy-TierModel.ps1 lines 1638–1650 (BUG-005 render)
- Reviewed Get-TierModelWinLapsAclFd.ps1 line ~201 (warning vs error classification)
- Confirmed glyph-to-color rendering is hardcoded (sound)
- Confirmed Pester swap has zero impact on deployment logic (test-runner tool only)
- **Verdict:** ✅ APPROVED — Both fixes safe to merge

---

## Lab State After Validation

- VM TierLab-DC01: **Running** (checkpoint clean, not reset, not applied)
- No `-ConfirmApply` used; both runs PREVIEW/PLANNING only
- Zero AD changes made to lab
- Ready for next UAT phase

---

## Next Steps

- Merge fix/ui-bugs-002-005 to main
- Update version/release notes if needed
- Joel's additional UAT (if required)
