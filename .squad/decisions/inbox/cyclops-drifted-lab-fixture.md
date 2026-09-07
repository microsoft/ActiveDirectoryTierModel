# Decision: a drifted lab fixture, because a clean domain cannot fail

- **Author:** Cyclops (lab/validation engineer)
- **Date:** 2026-09-05
- **Requested by:** Joel Platek
- **Branch:** `feature/enable-verbose-debug` (nothing committed or staged)
- **Scope touched:** `.research\lab-validation\` only

---

## Context

Sixteen defects found; fifteen fixed. Six share one shape:

> The console shows the operator correct information. The log, report or XML — the artifacts
> sent to Microsoft — are silently wrong or empty. Nothing throws, nothing is red, exit codes
> are unaffected.

BUG-027, BUG-028, BUG-030, BUG-032, BUG-034 and the reporting half of BUG-031 are all of this
family.

**A clean, compliant domain cannot detect any of them.** A stale `DriftCount = 0` is
indistinguishable from a correct `0`. `No drift detected - configuration matches AD state` is
the *correct* output on a clean domain and the *symptom* on a drifted one. The 42-row matrix
runs against a clean domain, so it would have passed while all six were live.

This is not closable by asserting harder. It needs a different domain state.

## Decision

Add an opt-in, mutating, reversible drifted-lab fixture and seven rows that assert the report
agrees with the console.

1. **`New-LabDriftFixture.ps1`** — 9 components, 3 profiles (`Clean` / `Drifted` /
   `DriftedAdmx`), idempotent and reversible. Every component is a rename, an attribute flip, a
   DACL swap or a GPO registry-value change; **nothing is created or deleted**. Pre-drift values
   are snapshotted to `state\lab-drift-fixture-state.json`. Names come from `config\`, never
   from literals.
2. **Seven rows `X1`–`X6b`** behind `-IncludeDriftRows`, one per scope (a product constraint:
   `$activeScopeCount -gt 1` is rejected).
3. **`proof\Prove-DriftRowAssertions.ps1`** — 54/54, every assertion watched failing first
   against a broken stub and passing against a fixed one.

## The ordering trap, and why it is asserted rather than assumed

The consolidated audit walks
`OU(1) → Canonical ACL(2) → Group(3) → User(4) → OU ACL(5) → GPO(6) → ADMX(7) → … → AuthPolicy(14) → AuthSilo(15)`
and broken code keeps only the **last** entity's findings.

Therefore the drift must be **early** and the **last consolidated type (ADMX) must be clean**.
Drift a late type and a broken build still publishes something — the row passes *while broken*.
That is exactly why a `-FullDeployment` DENY-URA removal test passed against BUG-028, and why a
single-entity fixture is worse than none: it produces a green tick that means nothing.

Both invariants are checked twice: offline by `-Action Plan` (exit 2 if violated) and during the
run by the `Last consolidated type (ADMX) is clean` check.

`Drifted` profile, verified offline:

```
  Drifted objects            : 9
  Consolidated entity types  : 4 (OU, OU ACL, Group, GPO)
  Last consolidated (ADMX)   : CLEAN - a clobber leaves the report EMPTY
  CAPABLE OF FAILING: 4 early entity types drifted, last type clean.
```

## Two defects in the supplied fixture brief

Both found by reading the product rather than the feature description.

1. **"Groups: 2 members" would have produced zero findings.**
   `Test-TierModelGroup.ps1` compares existence, OU location, `GroupScope` and `GroupCategory`
   — **not membership**. Row 1 would have had exactly one drifted entity type and would have
   been incapable of failing, in precisely the way it exists to prevent. Substituted a
   **GroupScope flip (Global → Universal)** on two tier groups.
2. **Row 1 needs ADMX clean; row 3 needs ADMX missing.** Both correct, but not simultaneously.
   Resolved with three profiles and by ordering rows so the fixture converges three times.

This is the second and third time a brief has specified drift the product does not measure. The
standing rule: derive the fixture from what the audit actually compares.

## Observed failures — the evidence

| Row | Broken-stub result | Fixed-stub result |
|---|---|---|
| X1 | `[FAIL] Report FINDINGS non-empty — REPORT SAYS "No drift detected"` | `[PASS] 6 finding line(s)` |
| X1 | `[FAIL] Console findings reached the report — MISSING from report: Tier 0 Server Staging, Tier 0 Admins/GroupScope, Tier 1 Admins/GroupScope, Tier 0/UnexpectedAce, Tier 1/UnexpectedAce, Tier 1 Member Server Baseline` | `[PASS] all 6 present` |
| X1 | `[FAIL] FINDINGS span more than one entity type — report carries 0:` | `[PASS] report carries 4: OU, Group, OU ACL, GPO` |
| X2 | `[FAIL] Report file exists — no path announced` | `[PASS]` report written |
| X3 | `[FAIL] Report matches console drift — 0 finding line(s) + "No drift detected"` | `[PASS] 1 finding line(s)` |
| X4 | `[FAIL] Report matches console drift — 0 finding line(s) + "No drift detected"` | `[PASS] 1 finding line(s)` |
| X5 | `[FAIL] Canonical ACL phase did not throw — PHASE THREW` / `[FAIL] No false "could not be determined" verdict — UNDETERMINED` | `[PASS] phase completed` / `[PASS] determined` |
| X6a | `[FAIL] Report names the drifted objects — 0/2 named; NOT named: Tier 2 Authentication Policy, Tier 2 Authentication Silo` (while `Report FINDINGS non-empty` PASSED with `2 finding line(s)`) | `[PASS] 2/2 named in the report`; verdict token `Missing` |
| X6b | `[FAIL] Report names the drifted objects — 0/1 named; NOT named: Tier 2 PAWs Windows LAPS - Computer` (while both weaker checks PASSED) | `[PASS] 1/1 named in the report`; verdict token `Mismatched` |
| verdict token | `[FAIL] Findings carry a real verdict type — 2 target line(s); verdict token(s): Drift` (isolated via the `typeregress` stub, where naming still PASSES) | `[PASS] verdict token(s): Missing` |

Throughout, X1's `Last consolidated type (ADMX) is clean` reads `[PASS] ADMX Drift: 0` — the
ordering precondition held *while the row failed*, which is what makes the failure meaningful.

## The proof script nearly lied, and how it was caught

The first run reported 42 failures. All read `CHECK NOT EMITTED: '<name>' absent from row
X1-full-multi` — the checks had **never run**. `Add-DriftReportChecks` was throwing on parameter
binding (`[string[]]` marked `Mandatory` rejects empty-string elements; console output is full
of blank lines).

Written as plain booleans, all 42 would have read "FAIL" and looked like a successful
watch-it-fail-first. Two things prevented that:

- the **parse-before-trust** gate proved the stubs were sound, so the fault had to be mine
  (adopted after a fix was nearly shipped this morning on a control that failed for a parse
  error rather than the defect); and
- `Assert-Check` distinguishes **absent** from **failed**.

**New standing rule: a proof harness must report an absent assertion differently from a failed
one.** An assertion that did not run is the most dangerous outcome available, because it is
indistinguishable from one that failed correctly.

Three further `Set-StrictMode` faults were found the same way (`.Count`/`.Sum` on unrolled
pipeline output and on an empty `Measure-Object`). One was on the **Clean** convergence path,
which every revert takes — it would have thrown at the end of every drift-enabled run.

## Vacuity controls

Nothing here may pass over an empty population.

| Control | Requirement |
|---|---|
| Fixture staged nothing (product FIXED, domain clean) | checks FAIL — an unstaged domain is a clean domain |
| Only ONE entity type drifted | BUG-028 detector FAILS with `PRECONDITION NOT MET`, blaming the **fixture** |
| LAST type (ADMX) dirty | ordering precondition FAILS |
| No drift rows in scope | matrix aggregates read `NOT COVERED`, never green |
| Fixture script missing | run aborts rather than running rows against a clean domain |
| Expected-name list empty | naming check FAILS — it does not pass because "all zero needles were found" |

Console `Total Drift: 0` on a drifted scope is a FAIL, not a silent pass. Zero console findings
makes the console/report comparison FAIL, not pass.

### The empty-name control immediately caught a live vacuity hole in the harness

`-ExpectedNames $(if (...) { $d.Names } else { @() })` yields *nothing* when the list is empty,
so PowerShell bound `$null` to the `[string[]]` parameter. `@($null)` has `Count = 1`, and
`$line -like "*$null*"` is `$line -like "**"` — which matches every line. The naming check
reported **`1/1 named in the report` while asserting nothing at all**: the console-right /
artifact-wrong defect family, reproduced inside the detector built to catch it. Fixed at both
ends (bind through a local; strip null/blank needles before counting).

The very next run, the now-working guard caught a second one: `tiermodel-winlaps.json` is
heterogeneous — only the Domain Controllers delegation carries `isDomainControllerOu` — so
`-not $_.isDomainControllerOu` threw under `Set-StrictMode` on every other entry. **Do not
filter heterogeneous JSON config on property truthiness**; test `PSObject.Properties[$name]` for
presence and select on a property whose absence is itself meaningful (`decryptorGpoName`).

## Rows 6a and 6b: watched failing pre-fix, now expected to PASS

I **did** observe both rows failing against pre-fix product code, while BUG-034 was still open.
That observation is the control. **No product code was reverted to reproduce it** — the pre-fix
rendering is retained as a *stub* inside the proof script, so the failure stays reproducible
without touching the product.

BUG-034's scope was wider than first briefed: **three** producers, **not reachable from the same
switch**.

| Producer | Shape emitted | Switch |
|---|---|---|
| `Test-TierModelAuthPolicy` | `PolicyName, Status, Issues, EnforceState` | `-IncludeAuthSilos` |
| `Test-TierModelAuthSilo` | `SiloName, Status, Issues, EnforceState` | `-IncludeAuthSilos` |
| `Test-TierModelWinLapsDecryptor` | `GpoName, Expected, Actual, Status` | `-IncludeWinLaps` |

A single `-IncludeAuthSilos` row would have covered two of three and **looked complete**. Row
count must follow the *producer inventory*, not the bug count, whenever the defect is a shape
mismatch.

### Asserting against a fix that is still moving

Rogue had a `ResourceType` follow-up in flight while these assertions were being written. The
rule adopted: **assert the part of the shape that carried the information loss; observe the
rest.**

| | Asserted? |
|---|---|
| Identifier of a `FINDINGS` line names the drifted object | **yes**, read from the *parsed* Identifier field, not by searching report text |
| Verdict token comes from `Status` rather than the generic `Drift` placeholder | **yes** |
| Resource type | **no — INFO only**, because its owner is still changing it |
| `FINDINGS` merely non-empty | not sufficient, and never was |

No expected value in these rows contains the token `Unknown`, and no assertion matches a whole
rendered line.

**The hard-coding guard.** In the fixed-product stub the `-IncludeAuthSilos` findings carry the
*old* resource type while the `-IncludeWinLaps` finding carries the *new* one, and both rows must
pass. Reintroducing a resource-type assertion turns one of them red immediately. A comment saying
"do not assert this" would not have survived; a failing test will.

**A new assertion must fail on its own reason.** Against the pre-fix stub the verdict-token check
fails — but so does the naming check, so the verdict failure could be a passenger. A `typeregress`
stub was added that names the object correctly and *only* collapses the verdict: the verdict check
fails there and the naming check passes, which isolates them.

**Why not a non-empty check.** All three producers emitted a finding even while broken. On the
decryptor, `FINDINGS non-empty` and `report matches console total` **both passed throughout the
outage**; two proof assertions record that, so the row cannot be simplified back without a red
test.

`Test-TierModelAuditRule` (one of five construction sites substitutes `Status` for `Details`)
was deliberately given **no row**: it degrades gracefully via the `Property/Expected/Actual`
triple, so it is lossy, not broken.

The WinLaps drift is a **registry value**, not a rename: the producer resolves its GPO by
display-name pattern, so a rename would yield a "no matching GPO" error finding instead of the
`Mismatched` finding whose rendering is under test. Relatedly, the leading `*- ` in config is a
**literal** for auth policies (`Get-ADAuthenticationPolicy -Identity`) and a genuine **wildcard**
for the decryptor (`Where-Object DisplayName -like`); asserting on the name's distinctive tail
is the only form correct under both.

## Row 5 exists because of an unmeasured risk in a shipped fix

BUG-031 folds canonical-ACL phase throws into the verdict. **Every observation of that phase so
far had an unreachable DC — nobody has watched it succeed.** If it throws benignly against a
healthy reachable DC, every clean domain now reports `COMPLIANCE COULD NOT BE FULLY DETERMINED`:
a false alarm on the happy path, and the change most likely to make an operator stop reading the
output. Row 5 asserts the phase was reached, did not throw, and produced no undetermined
verdict. The verdict line itself is INFO — an unapplied lab legitimately holds drift.

## Honest limitations

- **`OuAce` is not proven capable of failing.** A non-canonical DACL cannot be forced through
  the managed API (.NET re-orders Deny before Allow), so whether two extra explicit ACEs surface
  as OU ACL findings, Canonical ACL findings, or neither is unobserved against the real product.
  Treated as upside: X1's multi-entity guarantee rests on `OuRename` (1) and `GroupScope` (3).
- The literal `*- ` prefix on policy/silo/GPO names may or may not be substituted at deployment.
  Every lookup tries exact, then wildcard, and **throws** on a miss rather than returning `$null`.
- `Rename-ADObject` against `ProtectedFromAccidentalDeletion` objects is assumed to work
  (protection denies Delete/DeleteTree, not rename). Untested; a failure surfaces as a staging
  FAIL, not a silent skip.

## Status

Built and dry-validated only. **The full matrix has not been run** — Joel schedules the final
run. Inventory is 49 rows with `-IncludeDriftRows`, 57 with failure and apply paths added.
BUG-034 has landed, so **all seven drift rows are now expected to pass**; a failure on X6a or
X6b is a regression in the `Status`-as-`Type` fallback or in the identifier keys, and is to be
reported as a finding rather than softened.

Regression: all five proof scripts green (54 + 26 + 17 + 14 + 7).
