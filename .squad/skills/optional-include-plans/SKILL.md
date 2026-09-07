---
name: "optional-include-plans"
description: "How to fold optional deployment phases into a shared planning and apply pipeline"
domain: "deployment"
confidence: "high"
source: "manual"
---

## Context
Use this pattern when a deployment script has optional phases that can run standalone or alongside a larger full-deployment orchestration. The planner must show optional actions in the same summary users rely on before they approve `-ConfirmApply`.

## Patterns
- Precompute optional plans before printing the aggregate deployment summary.
- Add optional action counts into the same `Create/Update/Link/Configure/AlreadyExist` totals used by the main plan.
- Store the optional plan objects and reuse them during execution instead of re-planning later.
- Render each optional ACL action with the same user-facing format as the comparable core phase so standalone and full-deployment UX stay consistent.

## Examples
- `Deploy-TierModel.ps1` now calls `Get-TierModelMsaAclFd`, `Get-TierModelGmsaAclFd`, and `Get-TierModelDmsaAclFd` before the full deployment summary and reuses those plans during optional execution.
- `Write-IncludeAclPlanActions` and `Add-IncludeAclPhaseToDeploymentPlan` centralize the include-phase display and counting logic.

## Anti-Patterns
- Planning optional phases only after the summary has already been printed.
- Re-planning optional phases during apply with different functions or different assumptions.
- Showing aggregate counts without listing the underlying optional actions users are expected to approve.
