# beast — History

## Current: Windows LAPS Implementation Complete (2026-07-16)

**Status:** ✅ SHIPPED — All T001–T021 tasks complete, committed to feature/windows-laps branch, ready for Joel's UAT + release.

**Implementation Summary:**
- T001–T013: Implementation + audit cmdlet (5 new public functions, config, decryptor integration)
- T014–T020: Test suite (113 new Pester tests, 90.92% coverage, 1401/1401 green)
- T021: Documentation (8 files, README metrics updated to v1.2.0)

**Latest Fixes (2026-07-16):**
1. **SELF ACE Detection (Bug A):** Replaced `Find-LapsADExtendedRights` SELF check with `Get-Acl "AD:$ouDn"` filtering for non-inherited LAPS ACEs. SELF now correctly detected on all 7 OUs post-deploy.
2. **Mixed Findings Shapes (Bug B):** Consolidated audit reporting now guards `.Type` / `.Status` property access with `PSObject.Properties.Name` checks to work with both WinLaps ACL and Decryptor findings shapes.

**Essential Patterns for Future Work:**
- SELF ACE detection: Use `Get-Acl "AD:$ouDn"` + non-inherited filter + LAPS GUID filter (never `Find-LapsADExtendedRights` for SELF)
- Pre-compute LAPS schema GUIDs once before loop, not inside it
- Mixed audit findings: Guard property access with `$_.PSObject.Properties.Name -contains 'Type'`
- Decryptor audit pattern: Get-GPO → Get-GPRegistryValue ADPasswordEncryptionPrincipal → compare -ieq expected value
- Opt-in enforcement: WinLaps audit gated by `if ($IncludeWinLaps)` inside optional feature block

**Next Phase:** Joel's manual UAT, then PR merge, v1.2.0 release.

## Learnings: BUG-006 Canonical-ACL Pre-flight Gate (2026-08-11)

**Function:** `Test-TierModelCanonicalAcl`
**File:** `modules/TierModel/public/Test-TierModelCanonicalAcl.ps1`
**Exported in:** `modules/TierModel/TierModel.psd1` (alphabetical, before Test-TierModelPrerequisites)
**Wired into:** `modules/TierModel/public/Test-TierModelPrerequisites.ps1` (after WinLaps block, before ArrayLists conversion)

**Detection technique:**
- Use `System.DirectoryServices.Protocols` (S.DS.P) for DACL-only read from AD — NOT `Get-Acl` or `DirectoryEntry.Options` (unreliable for this use case).
- Parse bytes via `CommonSecurityDescriptor($true, $true, $sdBytes, 0)` — `isContainer=$true, isDS=$true` is mandatory for AD objects; `isDS=$false` mis-parses object-type ACEs and gives wrong results.
- `RawSecurityDescriptor`/`RawAcl` have NO `IsCanonical` property — must use `CommonSecurityDescriptor.DiscretionaryAcl.IsCanonical` (CommonAcl exposes it).
- Cast enum operands to `[int]` before `-band` (PS 5.1 throws otherwise; defensive for PS 7+ too).
- Two parameter sets: `ByServer` (live AD) and `ByBytes` (Pester-friendly, no AD required).

**Insertion point in Test-TierModelPrerequisites:**
- Between the `$result.EnvironmentSnapshot.LapsModulePresent = $lapsModulePresent` / `}` block close and the `# Convert ArrayLists` comment.
- Guarded with `if (Get-Module ActiveDirectory ...)` mirroring existing AD-language check pattern.
- On exception: sets `RootAclCheckError` snapshot field only — does NOT hard-fail (DC reachability already gated).

**Audit also hard-stops:** Both `Deploy-TierModel.ps1` and `Audit-TierModel.ps1` call `Test-TierModelPrerequisites` and fail-fast on `.Valid=$false`. Placing the gate in the shared prerequisites means Audit also hard-stops on a non-canonical root domain DACL. This is intentional and accepted.

**STATUS (2026-08-11 end-of-session):** Gate + doc lab-validated. Beast implementation complete. Pending owner code review. No commit (per owner request).

---

**Earlier history archived to history-archive.md (2026-07-28).**

**Essential Patterns (for future work):**
1. **StrictMode scoping:** Shared variables resolve BEFORE conditionals, not inside branches.
2. **ResourceType in display:** Branch on `$_.ResourceType -eq 'LapsPermission'` to render lapsOperation/allowedPrincipals.
3. **ACE IsInherited (PS7):** Use `Get-Acl "AD:<dn>"`, not nTSecurityDescriptor; filt
[truncated summary]

- 2026-08-11T20:14:44+08:00 | Moved non-blocking Pester side-by-side advisory from `\.Remediation` to `\.EnvironmentSnapshot.PesterAdvisory` in `Test-TierModelPrerequisites.ps1`; updated coupled test in `Unit.Prerequisites.Tests.ps1`; 1 Pester test passed, 0 failed.

- 2026-08-11T21:23:45+08:00 | FINALIZATION COMPLETE: Canonical-ACL gate + tests + docs reviewed APPROVE, nits fixed (Write-Warning in catch block, doc disclaimer removed). All 1,457 tests passing (91.13% coverage). PENDING owner code review + PR tomorrow. No commit (per owner request).
