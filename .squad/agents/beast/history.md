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

---

**Earlier history archived to history-archive.md (2026-07-28).**

**Essential Patterns (for future work):**
1. **StrictMode scoping:** Shared variables resolve BEFORE conditionals, not inside branches.
2. **ResourceType in display:** Branch on `$_.ResourceType -eq 'LapsPermission'` to render lapsOperation/allowedPrincipals.
3. **ACE IsInherited (PS7):** Use `Get-Acl "AD:<dn>"`, not nTSecurityDescriptor; filt
[truncated summary]
