# Beast — History Archive

Archived on 2026-07-15T06-59-20Z. Summary of earlier session learnings archived for reference.

## Earlier Sessions

- Phase 16 Pester patterns (2025-07-18): Mock scope bleeding, shadow variables, Resolve-TierModelPlaceholder double-invocation
- MSA/gMSA/dMSA prep work (2026-05-29 through 2026-06-03): Precomputed optional plans, lab validation with KDS workaround
- Windows LAPS Wave-1 technical foundation (2026-07-13): Schema validation, LAPS cmdlets research, deployment patterns established
- Windows LAPS implementation T001–T012 (2026-07-14): Full cmdlet suite wired, 5 bugs found and fixed (StrictMode, display, group lookup, FD plan stale, SELF detection), lab runs 1–6 progression

## Key Learnings (Condensed)

- StrictMode trap: conditional variable initialization causes VariableIsUndefined in shared code paths — always resolve shared vars before any conditional branch
- LAPS ActionType ResourceType='LapsPermission' distinct from 'ACL' (gMSA/MSA/dMSA) — requires dedicated display branching
- SELF ACE detection: filter by IsInherited=False AND LAPS schema GUIDs; use Get-Acl "AD:" not nTSecurityDescriptor for reliable IsInherited flag in PS7
- FD plans must be regenerated at execution time if they contain late-resolved principals
- Group lookup by display name requires -Filter "Name -eq", not -Identity

## Windows LAPS Decryptor Integration (2026-07-15)

- ADPasswordEncryptionPrincipal GPO setting integrates proven Set-GPRegistryValue recipe
- Config shape: decryptorGroup (plain name), decryptorGpoName (explicit GPO name)
- Validation: 101 Pester tests pass, module imports v1.2.0 OK, parse clean
- 3 user decisions captured (per-tier isolation, root OU placement, placeholder convention)
- Lab NOT touched — ready for Joel's UAT

Status: READY FOR LAB VALIDATION — see decisions.md for details

## T013 Audit Integration + Bugfixes (2026-07-16)

**Status:** DELIVERED + LAB-VERIFIED — 379-check audit 100% compliant

**Summary:**
- New cmdlet: Test-TierModelWinLapsDecryptor (verifies ADPasswordEncryptionPrincipal on 6 non-DC LAPS GPOs)
- Integration: -IncludeWinLaps on Audit-TierModel.ps1; opt-in; both standalone + FullDeployment flows
- Module: v1.2.0, Test-TierModelWinLapsDecryptor added to FunctionsToExport

**Bugs Fixed (2 critical):**
- **Bug A (SELF false negatives):** Test-TierModelWinLapsAcl SELF detection now uses Get-Acl "AD:$ouDn" filtering for non-inherited LAPS ACEs (mirrors planner logic). All 7 OUs: 7/7 compliant post-deploy (was 0/7).
- **Bug B (StrictMode .Type/.Status):** Audit-TierModel.ps1 consolidated reporting guards property access with PSObject.Properties.Name checks before comparing. No more StrictMode errors.

**Lab Validation (Wolverine):**
- Standalone -IncludeWinLaps: 7 ACL (7/7 compliant), 6 decryptor (6/6 compliant), 0 drift
- Full -FullDeployment -IncludeWinLaps: 379 checks, 100% compliant, 0 drift, 0 errors
- Idempotency: 2nd run applied 0, Converged True
- Drift detection: Detected mismatched value, restored to compliant
- Opt-in confirmed: -FullDeployment without -IncludeWinLaps shows zero WinLaps content

**Key Patterns (for future):**
1. SELF detection: Get-Acl + non-inherited filter + LAPS GUID filter (Find-LapsADExtendedRights never returns SELF)
2. Mixed Findings: Guard property access under StrictMode; don't assume all Findings objects have same shape
3. Audit result envelope: { TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings, DurationMs, CorrelationId }
4. Decryptor findings shape: {GpoName, Expected, Actual, Status} (differs from ACL shape; wrapper tolerates this)
5. FullDeployment wrapper aggregation: Only uses Summary.* fields for consolidated totals
6. Opt-in gates: $IncludeWinLaps in $includeParameters; both audit blocks guarded by if ($IncludeWinLaps) inside if ($activeIncludeCount -gt 0)

**Handoff Status:** Ready for Joel's UAT gate. Feature complete + lab-verified. Next: T021 documentation updates.
