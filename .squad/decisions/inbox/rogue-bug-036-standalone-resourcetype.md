# BUG-036 — Standalone `-Include*` findings render `ResourceType = Unknown`

**Author:** Rogue (Core Developer)
**Date:** 2026-09-05
**Files:** `Audit-TierModel.ps1` only
**Status:** Implemented, verified, uncommitted

## Problem

After BUG-030/034 the standalone `-Include*` path published findings correctly typed and
identified, but three of the eight producers rendered `Unknown/<name>` as the resource:

- `Test-TierModelWinLapsDecryptor` (7 append sites)
- `Test-TierModelAuthPolicy` (3 append sites)
- `Test-TierModelAuthSilo` (3 append sites)

`Unknown/` in a drift report is the useless output this release exists to prevent.

## Root cause — structural, not a typo

The standalone path aggregates all eight producers into a single `$standaloneFindings` array
and normalised it **once**, at the tail. `ConvertTo-TierModelDriftFinding -DefaultResourceType`
can therefore only ever carry one value for eight different resource classes, so the three
producers that emit no `ResourceType` of their own could not be served at all.

## Fix

Moved normalisation from the single tail call to the **eight append sites**, each supplying its
own `-DefaultResourceType`. The tail became a plain assignment (`@($standaloneFindings)`) so
findings are not normalised twice.

| Producer | `-DefaultResourceType` | Emits own `ResourceType`? |
|---|---|---|
| `Test-TierModelMsaAcl` | `ACL` | yes (`ACL`) — default never consulted |
| `Test-TierModelGmsaAcl` | `ACL` | yes (`ACL`) — default never consulted |
| `Test-TierModelDmsaAcl` | `ACL` | yes (`ACL`) — default never consulted |
| `Test-TierModelWinLapsAcl` | `LapsPermission` | yes — default never consulted |
| `Test-TierModelAuditRule` | `DomainAuditRule` | yes — default never consulted |
| `Test-TierModelWinLapsDecryptor` | `LapsDecryptor` | **no** |
| `Test-TierModelAuthPolicy` | `AuthPolicy` | **no** |
| `Test-TierModelAuthSilo` | `AuthSilo` | **no** |

Values follow existing house style (singular PascalCase), extracted from the producers'
hard-coded literals rather than invented: `ACL`, `LapsPermission`, `DomainAuditRule`.

The normaliser was **not** modified. It already prefers a finding's own `ResourceType` and
consults the default only when absent, which is what makes the five correct producers immune.

## Acceptance measurement

Harness `Bug036.ResourceType.ps1` AST-extracts append shapes from all eight producers, loads
`ConvertTo-TierModelDriftFinding` out of the shipping script by `FunctionDefinitionAst`, and
renders through the report's exact interpolation.

**43 real append rows: 33 byte-identical, 10 changed.** All 10 changes are the `ResourceType`
token alone, confined to the three producers that emit none. No `Unknown/` survives.

### Method note — appends vs initialisers

The reviewer's independent audit initially disagreed with my figures because its extraction
treated **result-object initialisers** as findings. They are not. A hashtable literal counts as
a finding only when its enclosing assignment is a `+=` onto the findings collection.

Excluded, verified by AST: the `TotalChecked/Compliant/Missing/...` result objects (~26 across
the eight files), the per-item `$result` objects in the GPO/ADMX producers, the parameter-log
hashtables (`DomainController/Silent/CorrelationId`), and the ACE-shape objects. Including any
of these defines a population that does not exist and manufactures false "changed" rows.

## Verification

- Parse errors: `Audit-TierModel.ps1` = 0 (PS 7 and real 5.1)
- UTF-8 BOM re-verified present after the edit (BUG-033 standing rule)
- Unit **1573/1573/0**, Integration **318/318/0**, both by path

## Residual

`-OuAclOnly` is still not routed through the normaliser. That remains deliberate and is
documented in-code: it carries a `Type` derivation the normaliser cannot express, and all eight
of its construction sites already emit all six fields, so no StrictMode hazard exists.
