# FR-007 Provenance Correction

**Date**: 2026-09-07T11:50:00+08:00  
**Agent**: Storm  
**Issue**: False provenance claim in FR-007 — claimed `-Logging` prompt was pre-existing on both Deploy and Audit, but Audit's implementation is new to this release.

## Independent Verification

Using PowerShell `[System.IO.File]::ReadAllText` + `[regex]::Matches` with `IgnoreCase` (not `Select-String`):

### Audit-TierModel.ps1 at 04ab664 (head commit)
- Logging switch occurrences: **0**
- Read-Host occurrences: 1 (the `-OutputFormat` prompt only)
- Parameter declaration check: **0** `-Logging` parameter found

### Audit-TierModel.ps1 in working tree (feature/enable-verbose-debug)
- Logging switch occurrences: **1**
- Read-Host occurrences: 4
- Parameter declaration check: **1** `-Logging` parameter found
- File size: 135,283 bytes (vs 80,252 in 04ab664)

### Deploy-TierModel.ps1 at 04ab664
- Logging switch occurrences: 0 (parameter exists; checked via parameter declaration regex)
- Parameter declaration check: **1** `-Logging` parameter found
- Lines 233-236 show explicit prompt code (existing shipped behavior):
  ```
  if ($Logging -and -not $OutputFileBase) {
      $OutputFileBase = Read-Host "Enter base filename for logs (timestamp and extension will be added automatically)"
      if ([string]::IsNullOrWhiteSpace($OutputFileBase)) {
          throw "OutputFileBase cannot be empty when Logging is enabled"
  ```

## Conclusion

- **Deploy**: `-Logging` prompt IS pre-existing shipped behavior at 04ab664 (confirmed)
- **Audit**: `-Logging` parameter and prompt are **NEW in this release** (confirmed absent at 04ab664, present in working tree)

## Corrections Made

### 1. spec.md FR-007 (lines 125-129)

**Before:**
```
- **FR-007**: **The prompt rule.** An *explicit* `-Logging` without `-OutputFileBase` MUST prompt (existing
  shipped behaviour, preserved unchanged, on both scripts). An *auto-enabled* `-Logging` MUST NEVER prompt —
  it takes a silent default — because a diagnostics re-run has to remain copy-pasteable and runnable in a
  non-interactive host. The two paths MUST be distinguished by an explicit flag, not inferred.
```

**After:**
```
- **FR-007**: **The prompt rule.** An *explicit* `-Logging` without `-OutputFileBase` MUST prompt. On Deploy,
  this is existing shipped behaviour, preserved unchanged; on Audit, the `-Logging` switch and its prompt
  behaviour are new in this release. An *auto-enabled* `-Logging` MUST NEVER prompt — it takes a silent
  default — because a diagnostics re-run has to remain copy-pasteable and runnable in a non-interactive host.
  The two paths MUST be distinguished by an explicit flag, not inferred.
```

### 2. plan.md table row (line 149)

**Before:**
```
| Operator passed `-Logging` | **Prompt** (`Read-Host`), throw on empty — pre-existing shipped behaviour, preserved |
```

**After:**
```
| Operator passed `-Logging` | **Prompt** (`Read-Host`), throw on empty — on Deploy this is pre-existing shipped behaviour, preserved; on Audit, new in this release |
```

## Files Searched for Similar Claims

Searched all files in specs/006-verbose-debug-logging for:
- "preserved unchanged.*both scripts" or "both scripts.*preserved unchanged"
- "Logging.*preserve" or "preserve.*Logging"
- "shipped|preserved|unchanged|both scripts"

Results: Only the two instances above contained the false claim; now corrected.

## Notes on Beast's Observation

Beast's note about the diagnostic trap was correct: searching 04ab664:Audit for the throw statement *does* find a match (from `-OutputFormat` site at line 236 in Deploy), making it read like the `-Logging` site is pre-existing. Only searching for "Logging" as the feature name directly revealed the absence. This has been corrected.

## No Other Files Modified

- Did NOT touch Deploy-TierModel.ps1 (Rogue is actively editing)
- Did NOT touch Audit-TierModel.ps1 (Rogue is actively editing)
- Did NOT touch CHANGELOG.md (locked out)
- Did NOT touch .research/known-bugs.md (Beast owns it)
- Did NOT create any new files under docs/ (requires Joel's approval)
