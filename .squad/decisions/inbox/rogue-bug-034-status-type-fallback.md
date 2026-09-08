# BUG-034 — `Status` as the second reporting convention in the drift normaliser

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05
- **Status:** Implemented, awaiting review
- **Scope:** `Audit-TierModel.ps1` only (`ConvertTo-TierModelDriftFinding`)
- **Branch state:** uncommitted; HEAD `04ab664`

## Problem

The normaliser assumed one finding convention (`Type` / `Identifier` / `Details`). The codebase
has **two**. Four producers express the verdict in `Status` and name the object in a
producer-specific key:

| Producer | Shape | Sites |
|---|---|---|
| `Test-TierModelAuthPolicy` | `PolicyName, Status, Issues, EnforceState, ExtraDeviceGroups` | 3 |
| `Test-TierModelAuthSilo` | `SiloName, Status, Issues, EnforceState, ExtraMembers` | 3 |
| `Test-TierModelWinLapsDecryptor` | `GpoName, Expected, Actual, Status` | 9 |
| `Test-TierModelAuditRule` (1 of 5 shapes) | `Type='AuditRight', …, ExpectedValue, ActualValue, Status` | 1 |

Result before the fix — console names the object, the report does not:

```
AuthPolicy       -> [Drift] Unknown/Unknown: No further detail reported.
AuthSilo         -> [Drift] Unknown/Unknown: No further detail reported.
WinLapsDecryptor -> [Drift] Unknown/LAPS-Decrypt: No further detail reported.
```

## A further defect found while fixing this — reported to Joel before acting

`Test-TierModelAuditRule.ps1` L177 appends a finding **unconditionally** inside
`foreach ($right in $ruleConfig.rights)`, with `Type='AuditRight'` and `Status='Pass'`/`'Fail'`.
The normaliser dropped only the literal `Type -eq 'Compliant'`, so **every PASSING audit right
was rendered into the drift FINDINGS section**:

```
[AuditRight] DomainAuditRule/DomainRoot → DC=…: Property=…; Expected=Present; Actual=Present
```

This is the *inverse* of the family we have been chasing — the artifact claims drift where the
console prints `✅ present`. On a fully compliant domain with `-IncludeAuditing`, the report
listed every configured right as a finding. Like BUG-034 itself this is **exposure created by
the BUG-030 wiring, not a regression**: before that work `$driftFindings` was never assigned on
this path, so nothing was reported at all. The `Status` compliant-drop below fixes it.

## Design — and a correction to my own proposal

I had intended to prefer `Status` over `Type` when `Type` was not a "recognised drift class".
**Extracting the real literals by AST killed that idea**: the healthy producers use
`MissingAcl`, `UnexpectedAcl`, `MissingAuditRule`, `AuditRight` — a whitelist would have
mis-classified values it simply had not heard of. The shipped rule is therefore strictly
narrower and safer:

1. **`Type` always wins when present and truthy** — unchanged from before.
2. **`Status` is consulted only when `Type` is absent.** This is what makes every Type-bearing
   shape byte-identical.
3. **Compliant-drop by either convention**: `Type -eq 'Compliant'`, or `Status` exactly in
   `Pass, Compliant, OK, Success, True`. Matched **exactly, never by wildcard** — `NonCompliant`
   must not be read as compliant.
4. Identifier keys extended with `PolicyName`, `SiloName`.
5. `Issues` joined with `'; '`, checked **after** `Details`/`Message`/`Reason` so their
   precedence is untouched.
6. `Expected`/`Actual` added via `elseif` **after** `ExpectedValue`/`ActualValue`, so shapes
   carrying the latter render exactly as before.

## Verification — the acceptance bar was the shapes NOT being fixed

Harness: `Bug034.Shapes.ps1`. Key sets **and hard-coded literals** are extracted by AST from the
shipping producers, and the normaliser is loaded by `FunctionDefinitionAst` from the shipping
script — no retyped copies on either side. 110 rows across 9 producers.

```
before rows: 110 ; after rows: 110
IDENTICAL rows: 79
CHANGED   rows: 31
```

**All 79 unchanged rows** are the Type-bearing shapes: `MsaAcl`, `GmsaAcl`, `DmsaAcl`,
`WinLapsAcl`, `Admx`, and the four good `AuditRule` shapes. `Details` still wins over the
`Property/Expected/Actual` triple.

**All 31 changed rows** are the four broken shapes, and every one improves:

```
AuditRule  Status=Pass         [AuditRight] …Actual=Present     -> <DROPPED>
AuthPolicy Status=Compliant    [Drift] Unknown/Unknown: …       -> <DROPPED>
AuthPolicy Status=Missing      [Drift] Unknown/Unknown: …       -> [Missing] Unknown/Tier0-Policy: Not found in Active Directory
AuthSilo   Status=NonCompliant [Drift] Unknown/Unknown: …       -> [NonCompliant] Unknown/Tier0-Silo: issue-one; issue-two
WinLaps    Status=Compliant    [Drift] Unknown/LAPS-Decrypt: …  -> <DROPPED>
WinLaps    Status=Error        [Drift] Unknown/LAPS-Decrypt: …  -> [Error] Unknown/LAPS-Decrypt: Expected=GPO must exist; Actual=No matching GPO
```

- Parse errors **0**; UTF-8 BOM re-verified present after the edit (BUG-033 standing check).
- Unit **1573 / 1573 / 0**; Integration **318 / 318 / 0** — green, matching Wolverine's repaired
  baseline. No test needed changing.

## Known remaining gap — reported, NOT actioned

The three `Status`-convention producers still render `ResourceType = Unknown`
(`[Missing] Unknown/Tier0-Policy: …`). Type, Identifier and Details are now all correct, so this
is the last cosmetic edge. The cause is structural: the standalone path aggregates all eight
producers into one `$standaloneFindings` array and normalises **once**, so a single
`-DefaultResourceType` cannot distinguish them. Fixing it means normalising per producer at each
of the 8 append sites. That is outside the scope Joel set, so I have not done it. It is a
~8-line mechanical change if wanted.
