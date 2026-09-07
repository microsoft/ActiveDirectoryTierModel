# SKILL: Silent Skip Detection in Plan-Execute Pipelines

## Pattern

When a planning function iterates over config items and uses `continue` / `return` to skip items that fail preconditions, the skipped items become invisible unless explicitly tracked and reported.

## Detection Checklist

1. **Find all `continue` / `return` inside `foreach` loops over config items.** For each one, verify:
   - Is there a `Write-Warning` or `Write-TierModelLog` BEFORE the skip? If not → silent skip.
   - Is there a counter (`$skippedCount++`) tracking the skip? If not → counter bug.

2. **Check summary calculations.** If the summary uses `Total - ActionsPlanned = Existing`, then skipped items inflate "Existing". The correct formula is `Total - ActionsPlanned - Skipped = Existing`.

3. **Check plan/execute function divergence.** If planning uses FunctionA (relaxed validation) but execution calls FunctionB (strict validation), items may appear in the plan but silently vanish during execution.

## Fix Template

```powershell
# BEFORE the continue/return:
Write-TierModelLog -Level Warning -Message "GPO skipped: precondition failed" -Data @{
    Name = $itemName
    Reason = "Group dependency not met"
    MissingDependency = $missingGroupName
}
$warnings += "GPO '$itemName' skipped: group dependency not met"
$skippedCount++
continue
```

## Applicability

Any plan-then-execute pipeline where:
- Config defines N items
- A planning loop filters items based on preconditions
- A summary reports "N total, X actions, Y existing"
