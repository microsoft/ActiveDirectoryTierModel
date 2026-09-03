# beast -- History

## Recent Work (2026-09-02)

**Status:** Dot-source seam delivery complete; module v2.0.0 ready for release

### 2026-09-02 — Session Orchestration: Decisions Archived, v2.0.0 Prepared
- Dot-source guard committed in optional/Update-TierModelMembership.ps1 (no version bump — v1.7.2 unchanged)
- Wolverine's 107-test suite integrated; Membership script coverage 60.18%
- Module version bumped: 1.7.2 → 2.0.0 (Authentication Policy Silos release)
- PR #50 open (Closes #20) on feature/auth-silos; awaits merge to main
- Decisions archive: 12 old entries (pre-2026-08-26) archived; 1 inbox decision merged
- v2.0.0-rc1 tag pushed; v2.0.0 release tag to follow post-merge
- .squad files committed (no deliverable changes)

## Recent Work (2026-09-01)

**Status:** Latest fixes deployed and lab-validated

### 2026-09-01 — WhatIf-Safe Logging + Path Fix (v1.7.2)
- Fixed: -WhatIf flag now writes logs via -WhatIf:$false on infra I/O (New-Item, Add-Content, Remove-Item, Set-Content)
- Added: WHATIF preview lines at 9 change sites for preview-mode logging
- Moved: Logs/Debug folders from %ProgramData%\TierModel to $PSScriptRoot (script-relative)
- Lab validated on TierLab-DC01 by Coordinator — log file created, zero real changes in WhatIf mode
- Committed: a1ddffe (Joel Platek)

### 2026-09-01 — Milestone 8: -EnableEventLog Windows Event Log Support (v1.7.0)
- Added: Event log emission to Application log, Source 'TierModel'
- Added: -EnableEventLog switch (opt-in), -JobId parameter (correlation ID)
- Events: 1000 START (Information), 1001 COMPLETE (Information), 1009 ERROR (Error)
- All event writes are no-throw, best-effort — logging never blocks AD work
- Lab validation: awaiting Coordinator

## Archived Sessions

Work from 2026-08-24 and earlier has been archived to history-archive.md to maintain file size. See archive for:
- 2026-08-27: Design Plan for Update-TierModelMembership.ps1
- 2026-08-27: Amendment (Computer-Membership-Only model)
- 2026-08-29: Milestones 1-7 (comprehensive tier implementation)
- 2026-08-24: Format-TierModelDuration implementation
- 2026-08-14: -EnableAuditing implementation
- 2026-08-11: BUG-006 Canonical ACL gate

## Current Focus

Update-TierModelMembership.ps1 feature work ongoing. Lab validation in progress (Coordinator). Ready for Joel UAT upon Coordinator sign-off.

## Learnings

### 2026-09-03 — Debug/Logging Architecture Inventory

**⚠️ CORRECTION APPENDED (Scribe):** Initial claim "zero Write-TierModelLog -Level Debug call sites" was **INCORRECT**. Empirical audit by Coordinator confirmed **26 dormant Write-TierModelLog -Level Debug call sites** across 19 module files (concentrated in config/OU/group/GUID-resolution/ACL-planning and audit Test-* functions). This finding was corrected in the authoritative `.squad/decisions.md` section "CRITICAL VERIFIED FINDINGS — Finding 2" and recorded with explicit [CORRECTED FINDING] marker. Future sessions: reference the corrected finding, not this erroneous claim.

**Key findings from the `-Debug` feasibility inventory:**

- **`[CmdletBinding()]` coverage is nearly complete:** All 80 `modules/TierModel/public/*.ps1` functions and all 7 `TierModel.psm1` functions already have it. Both entry-point scripts have it (Deploy: `SupportsShouldProcess`, Audit: plain). The only gap is **15 script-internal helper functions** (8 in Deploy-TierModel.ps1, 7 in Audit-TierModel.ps1) that lack `[CmdletBinding()]`.

- **The reference implementation (`optional/Update-TierModelMembership.ps1`) deliberately avoids the `-Debug` common parameter.** It uses a custom `[switch]$EnableDebug` parameter and a private `Write-DebugLog` function that writes directly to `$PSScriptRoot\Debug\*.log` files. It never touches `$DebugPreference`. This is intentional — the automatic `-Debug` sets `$DebugPreference = 'Inquire'` which PROMPTS on every `Write-Debug` call.

- **`Write-TierModelLog` already has `Level = 'Debug'`** (routes to `Write-Debug $consoleMessage`), but there are only 4 `Write-Debug` calls anywhere in the codebase and zero `Write-TierModelLog -Level Debug` calls. The debug infrastructure in the logger is dormant.

- **Preference variable propagation:** `$DebugPreference = 'Continue'` set in Deploy/Audit scope DOES flow into module function calls (PowerShell inherits preference variables into child scopes including module calls). However, the default `-Debug` common parameter behavior sets it to `'Inquire'` (not `'Continue'`), so the fix pattern requires explicitly overriding to `'Continue'` after detecting `-Debug` was passed.

- **Silent `catch { }` blocks:** 1 in Deploy (line 320, intentional DFL probe), 25 in public module functions (all intentional — property access fallbacks in WinLaps, AuthPolicy, AuthSilo, Prerequisites). None are the root cause of "GPO deployment just stopped." The actual culprit is likely `$ErrorActionPreference = 'Stop'` propagating a deep exception that's reported via `Write-Host` but not visible when the console buffer scrolls.

- **Key file paths:**
  - Entry-point logging params: Deploy → `-Logging [switch]` + `-LogPath [string]`; Audit → `-LogPath [string]` only (no `-Logging` switch)
  - Log dir: `$PSScriptRoot\Logs\` (moved from `%ProgramData%\TierModel` in v1.7.2)
  - Membership debug dir: `$PSScriptRoot\Debug\` (beside the script)
  - Write-TierModelLog: `modules/TierModel/public/Write-TierModelLog.ps1`

- **Write-Verbose exists (41 calls in 6 files), Write-Debug scarce (4 calls in 2 files).** Running Deploy/Audit with `-Verbose` already surfaces more than most customers realize.

### 2026-09-02 — Dot-Source Test Seam for Pester (v1.7.2, no version bump)

**Pattern:** To make a monolithic PowerShell script unit-testable with Pester without altering runtime behaviour, insert a single guard immediately after the `# MAIN EXECUTION` banner and before the `try {` block:

```powershell
if ($MyInvocation.InvocationName -eq '.') { return }
```

**Why it works:**
- When Pester (or any caller) dot-sources the script (`. .\script.ps1`), PowerShell sets `$MyInvocation.InvocationName` to `'.'`, so the guard fires and `return` exits the script scope — functions defined above are loaded into the caller's scope but the main block never runs.
- When the script is invoked normally (`pwsh -File script.ps1` or `.\script.ps1`), `$MyInvocation.InvocationName` is the script path/name (never `'.'`), so the guard is a no-op and main runs as usual.
- `ScriptVersion` was intentionally left at `1.7.2` — this is a non-functional test seam with zero runtime impact.

**Verified (2026-09-02):**
- `ParseFile` → 0 syntax errors
- Byte scan → 0 non-ASCII bytes
- Dot-source in fresh `pwsh` session → `Resolve-ActiveSwitches`, `Test-IsCustomerExcluded`, `Write-TmEvent` all resolved; no PARAMETER ERROR / no main-execution output
- `-File` path unaffected (guard never fires)
