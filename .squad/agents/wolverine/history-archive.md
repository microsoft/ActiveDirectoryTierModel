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
- **Idempotency verification**: 2nd run = Applied 0, Converged True ✅

## Pre-existing LAPS Permissions (Checkpoint State)

- Tier 1 PAW Devices: Tier1Admins Read+Reset (set in WinLapsSchema checkpoint)
- Tier 2 PAW Devices: Tier2Admins Read+Reset (set in WinLapsSchema checkpoint)
- All other OUs: no LAPS delegations (fresh state)

## Key Pattern Learning

**Never use Get-ADOrganizationalUnit -Properties nTSecurityDescriptor for IsInherited checks in PS7.** Always use Get-Acl "AD:\" for correctly tracking directly-set ACEs.

Status: All 6 bugs closed; WinLaps planner stable; ready for decryptor GPO integration lab UAT
