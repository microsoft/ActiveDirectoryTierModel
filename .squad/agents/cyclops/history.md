# cyclops — History

## Sessions

### 2026-06-30 (v2.1.0 Release Prep)
- Added PSUseDeclaredVarsMoreThanAssignments to ScriptAnalyzer excludeRules in .github/workflows/ci.yml
- Reviewed and validated v2.1.0 release decision (minor bump for optional gMSA/dMSA/MSA ACL support)
- Confirmed cmdlet files remain untouched (user directive enforced throughout)
- Discovered: Get-TierModel*Acl cmdlets call Resolve-TierModelPlaceholder twice per delegation (line 114 + line 172)
- Validated test pattern compliance: -Scope It without -Exactly Count for per-delegation assertions
- Coordinated with Wolverine on mock scope fixes
- CI fully green, 1292/1292 tests passing

## Learnings
- 2026-06-30T12:17:50+08:00 — Test shadow variables (existence-check vars for scope assertions) require ScriptAnalyzer rule exclusion; they are intentionally not dereferenced in the script body
- 2026-06-30T12:17:50+08:00 — Double invocation patterns require "at least N" assertions (-Scope It without -Exactly Count) rather than exact counts
- 2026-05-29T18:03:29.139+08:00 — The gMSA/dMSA feature plan is now locked to existing OU delegation patterns, self-contained cmdlets, optional ACL config segments loaded through `Get-TierModelConfig`, and read-only KDS validation via remoting to the preferred domain controller.
- 2026-05-29T10:10:00Z — Architectural decisions documented in Scribe merge. Plan review complete with 11 decisions captured.

