### 2026-08-14: Deploy-TierModel.ps1 comment-based help must stay in sync (Joel)

**By:** Joel Platek (via Copilot coordinator)

**Convention:** The comment-based help at the top of Deploy-TierModel.ps1 must document EVERY parameter with an accurate .PARAMETER block, and .DESCRIPTION/.EXAMPLE/.NOTES must reflect current behavior. When any parameter is added or its behavior changes (e.g. the audit-script edits), the help block must be updated in the same change. Help had drifted — missing .PARAMETER for -IncludeMsa/-IncludeGmsa/-IncludeDmsa/-IncludeWinLaps/-EnableAuditing/-AdmlLanguage and a stale .NOTES "Version: 2.0".

**Lab staging note:** .research/copilot-cli-hyperv-ad-lab/scripts/Restage-Lab.ps1 restores a NAMED checkpoint (default WinLapsSchema) + copies repo files to C:\TierModel on the DC WITHOUT deploying — use for manual-UAT staging.

---

### 2026-08-14: Audit rights validated per-right (granular output) — Beast

**Branch:** feature/domain-auditing | **Status:** Implemented

`Test-TierModelAuditRule` emits a per-right validation line for EVERY configured right in `domainAuditRule.rights`, modelled on `Test-TierModelGPOContent.ps1` URA validation:
```
        ✅ Right 'CreateChild' - present
        ❌ Right 'WriteDacl' - missing
```
Each right also produces a `{Type='AuditRight', Status='Pass'/'Fail'}` finding entry for downstream Sentinel tooling. `TotalChecked` stays 1 (rule count, not right count); `Drift` stays 0/1 (per-rule); `-Silent` suppresses all host output. Lab evidence (TierLab-DC01): ABSENT → all 9 ❌; PARTIAL (7-of-9) → 7 ✅ / 2 ❌; canonical + extra Failure ACE → all 9 ✅ COMPLIANT (ignored); restore → canonical converge idempotent.
