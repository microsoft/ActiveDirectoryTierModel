# BUG-044 — the consolidated report body itemised one producer out of fifteen

- **Agent:** Rogue
- **Date:** 2026-09-05
- **Branch:** feature/enable-verbose-debug
- **Approved by:** Joel Platek (fix in v2.1.0)
- **Files:** `Audit-TierModel.ps1` only. No tests, specs, docs or CHANGELOG touched. Nothing staged, nothing committed.

## The defect

The `-FullDeployment` consolidated block built its per-entity evidence list additively:

```
DriftFindings wholesale  +  (Findings | Where { $_.Type -eq 'Drift' })
```

That second clause is a whitelist of a single string literal. An AST sweep of every object that
actually reaches `$auditResults` found that **nothing emits it any more** — BUG-042 removed the
last `Type='Drift'` label from `Test-TierModelOuAcl` earlier the same day. So the only entities
that reached the report body were the three producers that publish `DriftFindings` themselves
(OU, Group, User) plus OU ACL, which `Invoke-OuAclAudit` gives a `DriftFindings` projection.

Eleven entity types — GPO, ADMX, OU Canonical ACL, MSA ACL, gMSA ACL, dMSA ACL, WinLaps ACL,
WinLaps Decryptor, Domain Audit Rule, Auth Policies, Auth Silos — were counted into the header
and then dropped from the evidence. Present in `DriftCount`, absent from the artifact that is
supposed to justify it.

## Correcting the handoff's producer sweep

The sweep I inherited matched string-literal `Type = '...'` and left ten producers blank. I
determined what each actually does rather than inheriting either assumption. Three corrections:

1. **Six of the ten never reach the consolidated report at all.** `Test-TierModelGPO`,
   `Test-TierModelGPOContent`, `Test-TierModelGPOLink` and `Test-TierModelAuthSiloPrerequisite`
   are not referenced by `Audit-TierModel.ps1`. `Test-TierModelGPOLink`/`GPOContent` are called
   *inside* `Test-TierModelGPOAudit`, where their results are collapsed into `$result.Issues` and
   re-emitted as a single `Message` string — they never produce finding objects of their own.
   `Test-TierModelOuExists` returns an existence probe consumed by `Invoke-CanonicalAclAudit`, and
   `Test-TierModelPrerequisites` is a start-up gate whose result never enters `$auditResults`.
   None of these are affected; "blank" meant "not in the population", not "broken".
2. **Four of the ten are genuinely affected and are Status-shaped, not Type-less by accident.**
   `AuthPolicy` and `AuthSilo` emit `Status` of `Missing`/`Compliant`/`NonCompliant`;
   `WinLapsDecryptor` emits `Status` of `Error`/`Missing`/`Compliant`/`Mismatched`;
   `CanonicalAcl` findings are built inline in `Invoke-CanonicalAclAudit` and *do* carry
   `Type='Mismatch'` plus their own `ResourceType`.
3. **The `Admx` entry in the handoff conflated `ResourceType` with `Type`.** `Test-TierModelAdmx`
   emits `Type` of `Missing`/`Mismatch` (plus `Error` on wholesale failure); `ADMX`/`ADML` are
   its `ResourceType` values.

## Shape chosen: (b), the consumer — but routed through the existing normaliser

Not a widened `Where`-clause. The consolidated body now calls
`ConvertTo-TierModelDriftFinding`, which is **already** what `-GposOnly`, `-AdmxOnly` and all
eight `-Include*` standalone branches use. This is the BUG-042 principle applied again: one
projection with two consumers beats two projections kept in sync by discipline.

Reasons (a) was rejected: publishing a `DriftFindings` projection from each of eleven producers
is churn across eleven files for a defect that lives in one consumer, it would have created a
second projection of the same objects for every producer that already reaches the body, and it
would have left the standalone and consolidated paths still rendering through different code.

Reasons a naive widening was rejected: five producers emit `Type='Compliant'` and three emit
`Status='Compliant'`/`'Pass'`. "Everything non-Drift" would put compliant rows into the drift
body and make a clean estate report findings — trading a false green for a false red. The
normaliser already drops exactly those, by **exact** match, so `NonCompliant` is still drift.

A second, less obvious reason the normaliser was required rather than merely convenient: the
console block below interpolates `$_.Type`, `$_.Identifier` and `$_.Details`. Raw AuditRule,
AuthPolicy, AuthSilo and WinLapsDecryptor findings carry **neither** `Identifier` nor `Details`,
so passing them through unnormalised would throw under `Set-StrictMode -Version Latest` — a
report-time crash on a *drifted* run, which is the BUG-032 family defect.

## The double-count guard: `elseif`, not a second `+=`

`Invoke-OuAclAudit` publishes **both** `DriftFindings` and the raw `Findings` that projection was
built from. Normalising `Findings` unconditionally would itemise every OU ACL finding twice. The
branch is therefore `if/elseif`: a producer that publishes its own projection is authoritative
for its own drift.

The branch tests the property being **present**, not being non-empty. A compliant OU/Group/User
result publishes an *empty* `DriftFindings` and must stay empty rather than falling through to a
`Findings` property it does not have.

## Proof, not assertion

Control extracts the **shipping** normaliser and the **shipping** consolidated block out of
`Audit-TierModel.ps1` by AST extent (`FunctionDefinitionAst`, then the `$entityDriftFindings`
assignment plus the `IfStatementAst` that follows it) and executes them. Finding shapes come from
each producer's own hashtable key sets, also by AST. Nothing under test is retyped.

The BEFORE block could not be extracted from git — the whole block is an *addition* relative to
HEAD, since BUG-028 rewrote it earlier the same day and nothing is committed. Rather than run a
retyped copy and prove nothing, the BEFORE behaviour was **measured**: the only question that
decides its output is whether any finding carries the literal `Type='Drift'`, and that count was
measured against the scenario data directly.

| Scenario | Result |
|---|---|
| **A — fully compliant estate** (all 15 entity types, compliant rows taken from the producers' own AST literals) | body rows **BEFORE 0, AFTER 0**. Text renders the "No drift detected" branch, Json `driftFindings` `[]`, Html `Findings: 0`. **0/0/0 with an empty body holds.** |
| **B — drifted estate** (one real non-compliant shape per producer) | body rows **5 → 46**. Eleven entity types moved from 0 to non-zero; OU/Group/User/OU ACL unchanged at 1/1/1/2. |
| Findings carrying literal `Type='Drift'` | **0** — confirming the old filter was a whitelist of a literal nothing emits. |
| **C — OU ACL double-count guard** | 2 raw Findings, 2 published DriftFindings, **2** body rows. Itemised exactly once. |
| **D — StrictMode safety** | every emitted row interpolates `Type`/`ResourceType`/`Identifier`/`Details` without throwing. |

## Behaviour changes — for Joel, not shipped silently

No verdict, no count, no exit code and no NUnit attribute moves.

- Exit gate, compliance %, NUnit `failures=`, the Json `auditSummary` block and the log record all
  read `$auditSummary` / `$totalDrift`, which this change does not touch.
- The per-entity `Checked: / Drift: / Errors:` console line reads `Summary` only — unchanged.

Two artifact changes, both of which **are** the fix:

1. The **Text `=== FINDINGS ===` body** and the **Json `driftFindings` array** now itemise the
   eleven previously-dropped entity types. This is the defect being repaired.
2. The **Html `<p>Findings: N</p>`** count rises with the body, because it is `$driftFindings.Count` —
   the number of itemised rows, not a verdict. Flagged because it is a number in an artifact.

One console-only side effect worth naming: `Invoke-CanonicalAclAudit` prints its own findings
during Phase 1b (it takes no `-Silent`), so canonical drift now appears both there and in the
consolidated summary. Every other producer runs `-Silent`/`-SuppressSummary`. I judged restating
it correct — a consolidated summary that omits an entity type is the bug — but it is a visible
change and Joel should see it named.

## Over-fixing guard

Distinct behaviours changed: **one** — which findings reach the consolidated `-FullDeployment`
evidence body.

Confirmed unchanged: `-OuOnly`, `-GroupOnly`, `-UserOnly`, `-OuAclsOnly`, `-GposOnly`,
`-AdmxOnly` and the standalone `-Include*` path all still assign `$driftFindings` from their own
result exactly as before; the Text, Json, Html and NUnitXml renderers are byte-identical.

## GPO / WinLapsDecryptor arithmetic residual — documented, per Joel's ruling

Not fixed, by decision. `Test-TierModelGPOAudit` defines Drift as missing + mismatch + **errored**
audits, and `Test-TierModelWinLapsDecryptor` as Missing + Mismatched + **Errors**, so for those two
entity types `Missing + Mismatch` can legitimately be less than `Drift Findings` and the header
will not sum. Routing the remainder into `UnverifiedCount` — which means *read failures* — would
be the BUG-026 defect (a figure nothing verifies) wearing the costume of a fix.

Recorded in-code at both sites a future reader will hit, with the ruling and the date, so the
gap is not silently "corrected" later:
`Audit-TierModel.ps1` `-GposOnly` breakdown, and the standalone `$standaloneTotalMissing` block.
The errored objects are already reported honestly in `ErrorCount`. `DriftCount` is untouched
either way, so nothing depends on the gap.

## Broken tests

**None.** Unit 1573 total / 1572 passed / **1 failed**; Integration 318 / 318 / 0 — exactly the
stated baseline. The single failure is the known, pre-existing one and is unrelated to this
change: `tests\Unit.OuAclOperations.Tests.ps1:981`, "Test-TierModelOuAcl – extended coverage.ACE
mismatch.Sets Type='Drift' on the ACEProperties finding". It **encodes old-buggy behaviour** (the
label BUG-042 removed), it is Wolverine's to repair, and this change neither caused nor touched it.

## Status: LANDED (path A), complete and verified

Not backed out. BUG-044 was finished and both suites were run **before** the 20:30 deadline was
set, so there was no half-applied rewrite at risk of being committed. The tree is coherent: it is
the new behaviour throughout, with the old single-literal filter fully removed (the only remaining
occurrences of `-eq 'Drift'` in `Audit-TierModel.ps1` are inside explanatory comments at L1099 and
L2000).

**Next concrete edits — none required for BUG-044.** Two follow-ups belong to other people:

1. `tests\Unit.OuAclOperations.Tests.ps1:981` still encodes the BUG-042 label and is Wolverine's
   to repair. Not touched.
2. If anyone later wants the Phase 1b canonical console double-print suppressed, the change is to
   give `Invoke-CanonicalAclAudit` a `-Silent` switch matching its five siblings. Deliberately not
   done here — it is a separate behaviour from BUG-044 and would have been over-fixing.

**Verification re-run at 19:42 after the timestamp correction:** BOM `EF BB BF`, 0 parse errors,
Unit 1573 / 1572 / 1 (known failure only), Integration 318 / 318 / 0, repo root clean, nothing
staged, nothing committed.
