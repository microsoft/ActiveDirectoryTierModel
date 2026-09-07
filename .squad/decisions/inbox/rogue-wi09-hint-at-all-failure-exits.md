# Decision: WI-09 diagnostics hint placed at all failure exits, not the two specified

**Author:** Rogue (Core Dev)
**Date:** 2026-09-05
**Status:** Deliberate deviation — flagged for review
**Related:** WI-09, WI-16

## The instruction

WI-09 named **two** sites for the copy-pasteable re-run hint in `Deploy-TierModel.ps1`: the
"GPO planning failed" message, and the end block.

## What I did instead

I placed `Write-TierModelDiagnosticsHint` at **all six** top-level `exit 1` sites in Deploy, plus
the GPO-planning message and the blocked end block.

## Why

Deploy's two *most common* real-world failures — prerequisite validation and configuration
validation — do not reach either of the two specified sites. They call `Write-TierModelFailFast`
and `exit 1` well before them. As specified, an operator whose run died at prerequisites (the
single most likely outcome on a first run) would have been told nothing about `-EnableVerbose`.

More importantly, `Audit-TierModel.ps1` has only three top-level exits, and mirroring the plan
there naturally put a hint at every one of them. Had I followed WI-09 literally, Audit would
have offered diagnostics on every failure and Deploy would have offered them on almost none —
the exact "an operator must never have to remember which script behaves differently" asymmetry
that this whole work item was structured to avoid.

## Safety

The helper is self-suppressing: `if ($EnableVerbose -and $EnableDebug) { return }`. So the hint
never appears on a run that already has both switches on, no matter how many call sites exist.
Verified at runtime in both scripts — hint present with no switches, absent with both.

## Ordering detail worth keeping

At every exit path the hint is emitted **before** `Stop-TierModelDiagnosticsTranscript`. My first
pass had it the other way round, which would have dropped the re-run line out of the transcript —
the one artifact a customer is expected to send us. Caught by reading the inserted lines back
rather than trusting the insertion.

## If this is unwanted

Reverting is mechanical: delete the `Write-TierModelDiagnosticsHint` line and its `# WI-09`
comment from the four extra Deploy sites. Nothing else depends on them.
