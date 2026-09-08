# BUG-032 — `-GposOnly` drift findings carry no `ResourceType`; the report throws

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05
- **Status:** Implemented, awaiting review
- **Scope:** `Audit-TierModel.ps1` only
- **Branch state:** uncommitted; HEAD `04ab664`

## Problem

The `-GposOnly` branch projected its findings as:

```powershell
[PSCustomObject]@{
    Type       = $_.Type
    Identifier = $_.GpoName
    Details    = $_.Message
}
```

with **no `ResourceType`** key. The Text report renders each finding with:

```powershell
"[$($_.Type)] $($_.ResourceType)/$($_.Identifier): $($_.Details)"
```

Under `Set-StrictMode -Version Latest`, reading a property that does not exist on a
`PSCustomObject` **throws**. So a `-GposOnly` audit that found any drift threw during report
generation and produced **no report at all**.

This is the fifth instance of the console-right/artifact-wrong family, but with a different
failure mode: **loud rather than silently wrong**. The outcome for the operator is arguably
worse — a drifted domain yields no artifact whatsoever.

**A clean run cannot reveal it.** The projection only executes when there are findings, so
every green `-GposOnly` run passes straight through.

## Change

Added `ResourceType` to the projection, defaulting to `'GPO'` but preserving a
source-supplied value if one is ever present:

```powershell
ResourceType = if ($_.PSObject.Properties.Name -contains 'ResourceType' -and $_.ResourceType) { $_.ResourceType } else { 'GPO' }
```

The membership test is deliberate: `$_.ResourceType` alone would itself throw under
StrictMode when absent, which is the very defect being fixed. The `-contains` guard is
evaluated first and short-circuits.

## Verification — control experiment

Tested the report's **exact** interpolation expression against the exact object shapes,
in isolation, under `Set-StrictMode -Version Latest`:

```
PRE-FIX  : THREW -> The property 'ResourceType' cannot be found on this object. Verify that the property exists.
POST-FIX : OK -> [Missing] GPO/Tier0-GPO: GPO not found
GUARD    : preserved ResourceType = GPO-LINK (expect GPO-LINK)
```

The GUARD row is the over-fixing check: a source object that already carries a
`ResourceType` keeps it rather than being flattened to `'GPO'`.

- Parse errors: **0**.
- Unit **1573/0**; Integration **315/3** (the three expected BUG-031 failures only).

## Notes for review

This was found by tracing the BUG-030 work, not by any test. The pattern — a scope branch
hand-building the shared reporting shape and omitting a key the report requires — is the
same missing invariant covered in the separate scope-publish-guard design note.
