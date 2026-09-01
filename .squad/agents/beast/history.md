# beast -- History

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
