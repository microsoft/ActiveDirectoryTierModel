# Normaliser routing — the "cheap exception" from the scope-publish-guard design

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05
- **Status:** Implemented (one of two), **second one declined with evidence**
- **Scope:** `Audit-TierModel.ps1` only
- **Related:** `rogue-scope-publish-guard-design.md` (full guard deferred to v2.2.0)

Joel accepted my proposal to route the two remaining hand-built findings projections through
the existing `ConvertTo-TierModelDriftFinding` normaliser. I did **one** of them. The second is
not equivalent, and forcing it would have changed behaviour. Detail below.

## Change 1 — `-GposOnly` routed through the normaliser (done)

Added an optional parameter to the normaliser:

```powershell
[string]$DefaultResourceType = 'Unknown'
```

used in place of the previously hard-coded `'Unknown'` fallback. The default keeps every
existing caller (`-AdmxOnly`, the standalone `-Include*` path) behaviourally unchanged.

The `-GposOnly` branch is now one line:

```powershell
$driftFindings = @($gpoResult.Findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'GPO')
```

This is provably equivalent because `Test-TierModelGPOAudit` emits exactly
`Type` / `GpoName` / `Message` (verified at its single finding-construction site, L441), and the
normaliser already maps `GpoName`→`Identifier` and `Message`→`Details`.

**Equivalence control.** I extracted the *shipping* normaliser from the file by AST (rather than
retyping it) and rendered both shapes through the report's literal interpolation:

```
count new=3 old=3
rendered output identical to previous hand-built shape: True
  [Missing] GPO/Tier0-Baseline: GPO not found in domain
  [Mismatch] GPO/Tier1-Baseline: Link enforced mismatch
  [Error] GPO/Tier2-Baseline: Access denied
```

Regression control on the new parameter:

```
existing caller (no -DefaultResourceType): ResourceType='Unknown'   <- unchanged
with override:                             ResourceType='ADMX'
compliant still dropped:                   True                     <- unchanged
```

## Change 2 — `-OuOnly` + canonical ACL: **declined, comment added instead**

I did not route this one, and I want to be explicit that this is a deviation from what was
asked.

**Reason 1 — it carries a Type derivation the normaliser cannot express.**
`Test-TierModelOuAcl` emits `Type` of `'Drift'`, `'Error'` or `'Warning'`. The branch
re-classifies `'Drift'` into `'Missing'` vs `'Mismatch'` by inspecting `ActualValue`/`Details`,
and maps everything else to `'Error'`. The normaliser preserves the raw `Type`. Routing it would
silently change every OU-ACL finding label in the report — including surfacing `'Warning'`
findings (the `aclDelegations`-missing config shape at L79) as `Warning` rather than `Error`.

**Reason 2 — there is no latent StrictMode hazard here to close.** This was the actual
justification for the exception, and it does not apply. I checked all 8 finding-construction
sites in `Test-TierModelOuAcl.ps1` (L79, L111, L142, L168, L258, L325, L350, L463): **every one**
emits `Type`, `ResourceType`, `Identifier`, `ExpectedValue`, `ActualValue` and `Details`. The
producer is uniform, so none of the unguarded reads in this projection can throw. Unlike
`-GposOnly`, this shape was never missing a key.

I added a comment at the site recording both findings, so a future reader does not "fix" it into
a regression.

## Net effect

`-GposOnly` was the **last** hand-built findings shape that could omit a report-required key.
The remaining hand-built projection is provably complete against its producer. That closes the
specific hole BUG-032 came through without adding a helper, a sentinel, or new control flow —
i.e. without pre-empting the v2.2.0 guard decision.

## Verification

- Parse errors: **0** (PS 7), **0** (real PS 5.1, with the BUG-033 BOM in place).
- Unit **1573/1573/0**; Integration **318 total / 315 passed / 3 failed** — the same three
  BUG-031 tests and no others.
