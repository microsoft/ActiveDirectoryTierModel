# Decision: Align the Domain Audit Rule producer to one-finding-per-object

Author: Rogue
Date: 2026-09-07
Branch: feature/enable-verbose-debug (uncommitted)
Requested by: Joel Platek via Beast. Joel ruled Option A.

## Context

After the audit reporting seam was repaired, thirteen of fourteen audit sections reconciled:
the number of finding lines printed under a section matched the section's Drift counter.
Domain Audit Rule did not. It printed `Drift: 1` over nine finding lines.

The section was internally consistent (402 = 410 - 8), so this was not the counter defect
resurfacing. It was a units mismatch: the counter reports drifted OBJECTS, the finding list
reported drifted RIGHTS.

## The question that was put, and why it was a false choice

The question was framed as "does the counter report objects or findings, both defensible".
It is not a free choice. The Overall Summary computes:

    compliancePercentage = ((totalChecked - totalDrift) / totalChecked) * 100

`totalChecked` counts objects. On the lab estate that is 403 objects. If Drift were switched
to count findings (410), compliance becomes (403 - 410) / 403 = **-1.74%**. A negative
compliance percentage is not a reading anyone can defend, so the counting unit is forced to
objects. Every one of the fourteen sections already counts objects; `Test-TierModelAuditRule`
sets `$totalChecked = 1` for the single domain root it examines.

That left only one direction: align the producer's findings layer to the counter, not the
counter to the findings.

## Decision (Option A, ruled by Joel)

`Test-TierModelAuditRule.ps1` no longer appends a per-right `AuditRight` row to `$findings`.
One drifted object produces one `MissingAuditRule` finding, matching every other producer.

Explicitly preserved:

- The per-right console output. The `Write-Host` per-right present/missing block is a separate
  statement from the findings append; it was left untouched and still prints one green or red
  line per configured right for the operator.
- The complete missing-rights list. It was already carried in `Details` on the
  `MissingAuditRule` summary row ("Missing rights: ..."), so no information is lost from
  the JSON or HTML artifacts - only duplication is removed.

## Measured outcome

| | Before | After |
|---|---|---|
| Printed finding lines (estate) | 410 | 402 |
| Drift counter | 402 | 402 |
| Headline | 402 DRIFT ITEMS | 402 DRIFT ITEMS |
| Compliance | 0.25% | 0.25% |
| Domain Audit Rule section | Drift 1 over 9 lines | Drift 1 over 1 line |

The predicted numbers held exactly. The headline did not move; only the reconciliation gap
closed. The section now reconciles on both readings at once.

## Artifact delta

The `Findings` collection on the Domain Audit Rule result loses nine per-right `AuditRight`
rows (eight of which were rendered; the ninth was a Pass row already dropped at render time by
the compliant-finding guard). The `MissingAuditRule` summary row survives with its `Details`
intact. Consumers filtering on `Type -eq 'AuditRight'` will now find none.

## Consequence for tests

`tests\Unit.AuditRuleOperations.Tests.ps1:464` asserts nine `AuditRight` findings and now gets
zero. That test encodes the behaviour this decision removes. It was not edited - `tests\` is
Wolverine's and he is actively working in it. He needs to retire or invert that assertion.

## Related: Invoke-OuAclAudit warning classification

`Invoke-OuAclAudit` projected every non-Compliant finding to `Type = 'Error'`, so a `Warning`
finding rendered as a red `[Error]`. Assessed before changing: the producer emits eight finding
types (Warning, Missing x3, Mismatch, Error x3). Only `Warning` was being remapped - genuine
`Error` findings already mapped to `Error` - so correcting it cannot suppress or hide a real
error state. It now routes through the shared `ConvertTo-TierModelDriftFinding` normaliser
instead of a hand-rolled projection, so it inherits the same severity colouring and label rules
as every other section. Observable delta: one advisory line moves from red `[Error]` to yellow
`[Warning]`.

## Open items referred upward

1. The `AuditRight` handling branch in `ConvertTo-TierModelDriftFinding` is now unexercised by
   any producer. It was deliberately kept as a defensive normaliser guard. Deleting a guard
   because today's producer stopped emitting the shape is how this class of bug recurs.
2. `OU ACL` with no `aclDelegations` configured renders `Checked: 0, Drift: 0, Errors: 0` with a
   single advisory finding. A scope with nothing to check reads as clean. This is structural and
   applies to every producer's empty-config path. Surfaced, not fixed - synthesising a fake error
   would be the wrong remedy.