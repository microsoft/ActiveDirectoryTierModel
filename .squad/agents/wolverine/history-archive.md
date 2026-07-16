# Wolverine — History Archive

Archived on 2026-07-15T06-59-20Z. Detailed lab session notes archived for reference.

## Earlier Windows LAPS Lab Sessions (Runs 1–6)

- **Run 1 (2026-07-14)**: Bugs 1–2 found (StrictMode, plan display). Blocked by Bug 1; no WinLaps applied.
- **Run 2 (2026-07-14)**: Bugs 1–2 fix verified; Bug 3 found (Get-ADGroup -Identity). All 7 groups not found.
- **Run 3 (2026-07-14)**: Bugs 1–3 fixed; Bug 4 found (FD plan stale with empty principals). Full deploy: 661 applied (delta +18), 12 R/R actions failed.
- **Run 4 (2026-07-14)**: Bug 4 fixed; Bug 5 found (SELF detection false positive from inherited ACEs). Full deploy: 663 applied (delta +20); 7 SELF skipped (false positive).
- **Run 5 (2026-07-14 + diagnostics)**: Bug 5b root cause confirmed (IsInherited mismatch nTSecurityDescriptor vs Get-Acl in PS7). Full deploy: 677 applied (delta +34). Idempotency: 7 SELF re-applied (not fixed yet).
- **Run 6 (2026-07-14)**: Bug 5b fixed (Get-Acl "AD:" for SELF detection). Full deploy: 673 applied (delta +30 for root OU design change); Idempotency: Applied 0, Converged True ✅

## All 6 Bugs Found & Fixed

| Bug | Root Cause | Fixed By |
|-----|-----------|----------|
| 1 | StrictMode  undefined in WinLaps-only path | Add -or  to resolution condition |
| 2 | Plan display accesses missing identityreference | Branch on ResourceType='LapsPermission' |
| 3 | Group lookup via -Identity fails on display names with spaces | Use -Filter "Name -eq" |
| 4 | FD plan precomputed before Phase 2 groups created | Regenerate at execution time |
| 5 | SELF detection false positive from inherited domain ACEs | Filter by IsInherited=False + LAPS schema GUIDs |
| 5b | IsInherited mismatch nTSecurityDescriptor vs Get-Acl in PS7 | Use Get-Acl "AD:" for SELF detection |

## Lab Baseline & Reference

- **WinLapsSchema checkpoint**: 7 ms-LAPS-* attributes confirmed
- **Baseline (no WinLaps)**: Applied 643
- **Expected WinLaps delta**: +21 (7 OUs × 3 operations)
- **Final Run 6 totals**: Applied 673 (baseline 643, delta +30 for root OU design)

## T013 Audit Verification — Bugfix Re-Verify (2026-07-16)

**Mission:** Confirm Beast's 2 T013 bugfixes (SELF detection + StrictMode .Type/.Status) live in lab.

**Status:** ✅ PASS — Both bugs fixed, full audit 379 checks 100% compliant

**Test Results:**
- **Standalone -IncludeWinLaps:** ACL 7/7 compliant (Bug A fix), Decryptor 6/6 compliant, 0 drift, no errors
- **Full -FullDeployment -IncludeWinLaps:** 379 checks (OU 31, Group 26, User 2, ACL 101, GPO 146, ADMX 60, WinLaps ACL 7, Decryptor 6), 100% compliant, 0 drift, 0 errors
- **Idempotency:** 2nd run applied 0, Converged True
- **Opt-in:** -FullDeployment without -IncludeWinLaps shows zero WinLaps content
- **Drift detection:** Manually mismatched 1 decryptor → audit detected Mismatched → restored to compliant

**Decryptor Status (all 7 GPOs):**
| GPO | Expected | Actual | Status |
|-----|----------|--------|--------|
| Tier 0 PAWs | TIERLAB\Tier0Admins | TIERLAB\Tier0Admins | ✅ |
| Tier 0 Servers | TIERLAB\Tier0ServerOperators | TIERLAB\Tier0ServerOperators | ✅ |
| Tier 1 PAWs | TIERLAB\Tier1Admins | TIERLAB\Tier1Admins | ✅ |
| Tier 1 Servers | TIERLAB\Tier1ServerOperators | TIERLAB\Tier1ServerOperators | ✅ |
| Tier 2 PAWs | TIERLAB\Tier2Admins | TIERLAB\Tier2Admins | ✅ |
| Tier 2 EUD | TIERLAB\Tier2DeviceOperators | TIERLAB\Tier2DeviceOperators | ✅ |
| Tier 0 DCs | (skipped) | (not checked) | ✅ |

**Lab State:** TierLab-DC01 running, deployed, compliant, AD-ready for Joel's UAT

**Key Confirmation:**
- Bug A (SELF detection): Now uses Get-Acl "AD:$ouDn" filtering for non-inherited LAPS ACEs (mirrors planner). All 7 OUs correctly report 7/7 compliant post-deploy.
- Bug B (StrictMode .Type/.Status): Consolidated reporting guards property access before comparing. No more "property cannot be found" errors.
- New Test-TierModelWinLapsDecryptor: Works flawlessly end-to-end. Integration into Audit-TierModel.ps1 structurally correct.
- Opt-in behavior: Confirmed — feature requires explicit -IncludeWinLaps flag.

**Learnings:**
1. Get-Acl "AD:$dn" returns definitive IsInherited in PS7; Find-LapsADExtendedRights never surfaces SELF
2. Mixed Findings schemas require property-existence guards under StrictMode
3. Decryptor findings shape {GpoName, Expected, Actual, Status} differs from ACL but wrapper tolerates this
4. FullDeployment wrapper only uses Summary.* for aggregation; per-finding detail unnecessary for decryptor
5. Idempotency confirmed: Applied 0, Converged True on 2nd run after full deploy

**Next:** Joel's UAT gate. Feature complete, lab-verified, ready for end-to-end manual testing (Get-LapsADPassword -AsPlainText, prerequisites edge-cases)
- **Idempotency verification**: 2nd run = Applied 0, Converged True ✅

## Pre-existing LAPS Permissions (Checkpoint State)

- Tier 1 PAW Devices: Tier1Admins Read+Reset (set in WinLapsSchema checkpoint)
- Tier 2 PAW Devices: Tier2Admins Read+Reset (set in WinLapsSchema checkpoint)
- All other OUs: no LAPS delegations (fresh state)

## Key Pattern Learning

**Never use Get-ADOrganizationalUnit -Properties nTSecurityDescriptor for IsInherited checks in PS7.** Always use Get-Acl "AD:\" for correctly tracking directly-set ACEs.

Status: All 6 bugs closed; WinLaps planner stable; ready for decryptor GPO integration lab UAT
