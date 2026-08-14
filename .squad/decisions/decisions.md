### 2026-08-14: Deploy-TierModel.ps1 comment-based help must stay in sync (Joel)

**By:** Joel Platek (via Copilot coordinator)

**Convention:** The comment-based help at the top of Deploy-TierModel.ps1 must document EVERY parameter with an accurate .PARAMETER block, and .DESCRIPTION/.EXAMPLE/.NOTES must reflect current behavior. When any parameter is added or its behavior changes (e.g. the audit-script edits), the help block must be updated in the same change. Help had drifted — missing .PARAMETER for -IncludeMsa/-IncludeGmsa/-IncludeDmsa/-IncludeWinLaps/-EnableAuditing/-AdmlLanguage and a stale .NOTES "Version: 2.0".

**Lab staging note:** .research/copilot-cli-hyperv-ad-lab/scripts/Restage-Lab.ps1 restores a NAMED checkpoint (default WinLapsSchema) + copies repo files to C:\TierModel on the DC WITHOUT deploying — use for manual-UAT staging.
