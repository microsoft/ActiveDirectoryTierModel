# Session Log: BUG-010 Lab Validation

**Date:** 2026-07-29  
**Agent:** Wolverine (Tester)  
**Bug:** BUG-010 (verify+retry loop in New-TierModelOu.ps1)  
**Lab:** TierLab-DC01 (tierlab.internal)  
**Duration:** 5 test runs (4x -OuOnly, 1x -FullDeployment)

## Summary

**Status:** ✅ PASS

The verify+retry fix in `New-TierModelOu.ps1` prevents silent no-ops on OU block-inheritance writes. The hard-stop gate in `Deploy-TierModel.ps1` prevents false-success propagation to Phase 2. All 10 OUs consistently showed gPOptions=1 (block inheritance enabled) across 4 clean -OuOnly restores, including the previously-failing "Tier 1 Server Staging" OU. Full deployment completed Phase 2 without hard-stop and achieved 100% audit compliance (31 OUs checked).

## Key Results

- TEST A (-OuOnly, 4 iterations): ✅ 10/10 OUs gPOptions=1, audit 0 failures every run
- TEST B (-FullDeployment, 1 run): ✅ Phase 2 cleared, 10 OUs gPOptions=1, audit 100% compliant
- Readback verification: ✅ Attempts=1 logged for every OU (code path confirmed active)
- Race condition (Attempts>1): ⚠️ Not observed (would need fault injection to trigger)

## Finding

Audit-TierModel.ps1 requires CWD=C:\TierModel (relative path issue). Not a BUG-010 regression; pre-existing operational gotcha.

## Recommendation

**Close BUG-010 as RESOLVED.** Inform team of Audit-TierModel.ps1 CWD requirement.
