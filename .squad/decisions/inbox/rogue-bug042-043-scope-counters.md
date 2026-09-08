# BUG-042 / BUG-043 — scope-dependent finding labels and unpublished drift breakdowns

Owner: Rogue
Date: 2026-09-05
Branch: feature/enable-verbose-debug
Files changed: `Audit-TierModel.ps1`, `modules\TierModel\public\Test-TierModelOuAcl.ps1`
Nothing staged, nothing committed.

Result: **Unit 1573 total / 1572 passed / 1 failed**, **Integration 318 / 318 / 0**.
The single Unit failure is a test that asserts the defective label — see "Test that encodes
the bug" below. Baseline was Unit 1573/1573/0, Integration 318/318/0, re-measured on this
branch before any edit.

Both bugs are **PRE-EXISTING at `04ab664`**. Neither was introduced by the logging feature.

---

## 1. Beast's producer-vs-consolidator call on BUG-042 — I agree with the instinct, and the
##    recommendation as written is necessary but NOT sufficient

Beast recommended fixing BUG-042 in the producer rather than by widening the consolidator's
filter. The instinct is right and it is the same instinct that made the BUG-040 fix correct:
the information was already present at the producer and was being thrown away, then guessed at
downstream. But taken literally the recommendation cannot work, and I want that on the record
because acting on it as stated would have shipped a regression.

`Test-TierModelOuAcl` emitted a generic `Type='Drift'`. The consolidated `-FullDeployment` body
selects findings with `Findings | Where-Object { $_.Type -eq 'Drift' }`. So if the producer
alone is changed to emit precise labels, **that filter matches nothing and OU ACL drift
disappears from the `-FullDeployment` report body entirely** — strictly worse than the bug.
Producer and consumer had to move together.

The deeper point: the producer was not independently wrong. It was **bent to fit a broken
consumer**. `Type='Drift'` exists because the consolidator only accepts `'Drift'`.

### What I measured that changes the severity picture

**(a) The `-OuAclsOnly` label was itself wrong for two of the four drift sites.**
Beast's framing was "the label reads Missing/Mismatch one way and Drift the other", implying
`-OuAclsOnly` was the correct rendering. It was not. The branch re-derived the class by
substring-matching the English prose in `Details`:

```
if ($_.ActualValue -eq 'Missing' -or $_.Details -like "*missing*" -or $_.Details -like "*No Access Control Entry*")
```

Run against the producer's four real Drift shapes (verbatim expression, real literals):

| producer site | counter incremented | rendered by `-OuAclsOnly` | correct? |
|---|---|---|---|
| L121 target OU does not exist | `$missingCount++` | `[Mismatch]` | **WRONG** |
| L152 identity does not exist  | `$missingCount++` | `[Mismatch]` | **WRONG** |
| L280 no ACE for identity      | `$missingCount++` | `[Missing]`  | correct |
| L355 ACE properties differ    | `$mismatchCount++`| `[Mismatch]` | correct |

Both wrong sites say "does not exist" rather than "missing", so the substring test missed them.
This means a drifted `-OuAclsOnly` report already **contradicted its own header** — "Missing: 2"
above two rows labelled `[Mismatch]` — before any cross-scope comparison. That is the BUG-041
intra-artifact reconciliation rule firing inside BUG-042's own footprint. Consequence for the
fix: "make `-FullDeployment` match `-OuAclsOnly`" would have propagated a wrong label.

**(b) The consolidator's filter is far more broken than BUG-042 describes — filed as BUG-044.**
`Type -eq 'Drift'` is effectively a whitelist of one producer. AST scan of every producer whose
findings reach the consolidated `Findings` branch:

| producer | Types it emits | survives `-eq 'Drift'` |
|---|---|---|
| Test-TierModelOuAcl | Drift, Error, Warning | yes |
| Test-TierModelGPOAudit | Missing, Mismatch, Error, Unknown | **no** |
| Test-TierModelAdmx | Missing, Mismatch, ADMX, ADML, Error | **no** |
| Test-TierModelMsaAcl / Gmsa / Dmsa / WinLapsAcl | MissingAcl, UnexpectedAcl, Compliant, Error | **no** |
| Test-TierModelAuditRule | MissingAuditRule, AuditRight, Compliant, Error | **no** |
| Test-TierModelWinLapsDecryptor / AuthPolicy / AuthSilo / CanonicalAcl | Status-shaped, no Type | **no** |

Eleven of twelve producers are dropped from the `-FullDeployment` console itemisation and
report body. This is the BUG-030 defect class ("findings on screen, zero in the report") at
scale. **I did not fix it** — repairing it changes the report body of every `-FullDeployment`
run for eleven producers, which is a behaviour change Joel must approve. Filed as BUG-044 below.

### The fix I actually shipped for BUG-042 — one projection, two consumers

Rather than widen the shared filter (Beast's warning holds — widening it to accept
`Missing`/`Mismatch` would silently admit GPO and ADMX findings too, i.e. an unapproved partial
BUG-044 fix), I made the OU ACL path conform to the **reference implementation Joel named**.
`Invoke-OuAudit`, `Invoke-GroupAudit` and `Invoke-UserAudit` publish a `DriftFindings` property,
and the consolidated loop takes that property **wholesale, unfiltered**. `Invoke-OuAclAudit`
now does the same:

1. `Test-TierModelOuAcl` emits the class it already counts — `Type='Missing'` at the three
   `$missingCount++` sites, `Type='Mismatch'` at the `$mismatchCount++` site. `Error` and
   `Warning` unchanged. No guessing anywhere.
2. `Invoke-OuAclAudit` builds the Type/ResourceType/Identifier/Details projection **once** and
   publishes it as `DriftFindings`.
3. `-OuAclsOnly` consumes `$ouAclResult.DriftFindings`; its bespoke substring derivation is
   deleted.
4. The consolidated path picks the same array up wholesale. **The shared filter is untouched.**

The two scopes now read the same objects, so they cannot disagree by construction. Verified
against the shipping `Invoke-OuAclAudit` extracted by AST:

```
-OuAclsOnly body        : [Missing] A  [Missing] B  [Mismatch] C  [Error] D
-FullDeployment body    : [Missing] A  [Missing] B  [Mismatch] C  [Error] D
IDENTICAL LABELS        : True
NO DOUBLE-COUNT         : True   (no product finding says 'Drift' any more, so the surviving
                                  `Type -eq 'Drift'` arm adds nothing on top of DriftFindings)
Unreadable ACL in BOTH  : True   (Beast's symptom 2, closed)
```

Both symptoms close: the cross-scope label disagreement, and the unreadable OU ACL that was
itemised under `-OuAclsOnly` but filtered out of the `-FullDeployment` body.

Deliberately **not** changed: the `Warning` -> `Error` mapping the `-OuAclsOnly` branch has
always applied to non-drift findings. It is pre-existing, it is arguably wrong (the L78
"no aclDelegations in config" finding increments no counter and is not an error), and changing
it would move output beyond BUG-042. Recorded, not touched.

---

## 2. BUG-043 — does fixing it change any verdict, count, exit code or NUnit attribute?

**No. Confirmed by inspection and by test.** This is a pure publish of numbers the branches
already had.

At all three sites `DriftCount` is assigned by the **identical expression** before and after.
All nine `$auditSummary.DriftCount` assignments in the file were diffed and are unchanged:

```
L2048 = $totalDrift                                        L2116 = $userResult.Summary.DriftCount
L2064 = $ouResult.Summary.DriftCount                       L2131 = ($ouAclResult.Summary.Missing + .Mismatched)
L2081 += $canonicalResult.Drift                            L2162 = $gpoResult.Summary.Drift
L2101 = $groupResult.Summary.DriftCount                    L2210 = [int]$admxAudit.Summary.Drift
                                                           L2508 = $standaloneTotalDrift
```

Downstream consumers, all verified untouched:
* exit gate `if ($auditSummary.DriftCount -gt 0 -or $auditSummary.ErrorCount -gt 0)` — unchanged
* NUnitXml `failures="$($auditSummary.DriftCount)"` — unchanged
* compliance % — derives from DriftCount/TotalChecked — unchanged
* Html `Findings: $($driftFindings.Count)` — unchanged
* the completion log record (TotalChecked/DriftCount/ErrorCount/UnverifiedCount) — unchanged

The **only** difference is the Text report's `- Missing:` / `- Mismatch:` lines and the
corresponding fields in the Json `auditSummary`. That is exactly the damage BUG-043 describes.

### The three sites

* **`-OuAclsOnly`** — publishes `Summary.Missing` / `Summary.Mismatched`. The branch already
  *computes* DriftCount from these two fields one line above, so it reconciles exactly.
* **`-GposOnly`** — publishes `Summary.MissingGpos` / `Summary.ConfigurationMismatches`, the
  producer's own mutually-exclusive failure buckets. Not derived by subtraction.
* **standalone `-Include*`** — accumulates `$standaloneTotalMissing` / `$standaloneTotalMismatched`
  in step with `$standaloneTotalDrift` at all eight producer sites. Seven of the eight define
  their own `Drift` as exactly `Missing + Mismatched|NonCompliant` (AST-verified), so this
  reconciles rather than approximates. AuthPolicy and AuthSilo name the bucket `NonCompliant`.

Measured on the standalone path:
```
BEFORE -> Drift Findings: 9 / Missing: 0 / Mismatch: 0   (above a body of 9 findings)
AFTER  -> Drift Findings: 9 / Missing: 5 / Mismatch: 4   RECONCILES: True
compliant estate -> 0 / 0 / 0                            stays 0: True
```

### Two known residuals, recorded rather than papered over — FOR JOEL'S DECISION

Two producers define `Drift` to include an **error** component that the Missing/Mismatch
buckets do not name:

* `Test-TierModelGPOAudit`: `Drift = $totalFailed` = missing + mismatch + GPOs whose audit errored.
* `Test-TierModelWinLapsDecryptor`: `Drift = Missing + Mismatched + Errors`.

So when those producers error, `Missing + Mismatch` is legitimately **less** than
`Drift Findings` by that error count:

```
Drift Findings: 11 / Missing: 6 / Mismatch: 4 / Errors: 1   -> gap of 1 == that error count
```

I did **not** close this gap. Routing the remainder into `UnverifiedCount` would have been
defensible (the consolidated path already models drift as `Missing + Mismatched + Unverified`),
but `UnverifiedCount` is a published counter meaning "read failures", and pushing a GPO audit
error into it is a semantic change to a real number — the BUG-026 family defect of writing a
figure nothing verifies. The honest breakdown is a strict improvement on `0 / 0`, and the
residual is a smaller, separate question. **Joel: this needs a ruling.** Neither producer
publishes its drift-error component as a named Summary key today, so closing it cleanly would
require adding one.

---

## 3. A defect in my own first cut, caught by the suite — worth recording

My first `-GposOnly` edit read `$gpoResult.Summary.MissingGpos` directly. Integration went
**318 -> 316** with `The property 'MissingGpos' cannot be found on this object`.

That was **not** a fixture problem and I did not treat it as one. Both keys are optional across
the Summary shapes that branch must accept, and under `Set-StrictMode -Version Latest` an
unguarded read **aborts the entire branch** — which is precisely BUG-032, already documented a
few lines away in this same file: a StrictMode throw at report time meant a *drifted* run
produced no report at all. I had reintroduced the exact defect class the surrounding comments
warn about, in a release about silent failures.

Both reads are now presence-guarded and Integration is back to 318/318/0.

**Rule, restated:** a breakdown is a nice-to-have; it must never be able to take the report
down. And: when the suite moves, the suite is the measurement.

---

## 4. Test that encodes the bug — NOT edited (tests/ is out of my scope)

```
tests\Unit.OuAclOperations.Tests.ps1:981
  It "Sets Type='Drift' on the ACEProperties finding" {
      ($result.Findings | Where-Object { $_.Property -eq 'ACEProperties' })[0].Type | Should -Be 'Drift'
  }
```

This asserts the generic label BUG-042 exists to remove. Reported straight rather than worked
around. Suggested replacement — note it should assert the label **agrees with the counter the
producer incremented**, otherwise it re-encodes a free-floating string:

```powershell
It "Labels the ACEProperties finding with the class it counted ('Mismatch')" {
    $result = Test-TierModelOuAcl -Config $script:CfgMismatch -DomainController $script:DC -Silent
    $f = @($result.Findings | Where-Object { $_.Property -eq 'ACEProperties' })
    $f[0].Type | Should -Be 'Mismatch'
    # the label must reconcile with the counter, not merely be a fixed string
    @($result.Findings | Where-Object { $_.Type -eq 'Mismatch' }).Count |
        Should -Be $result.Summary.Mismatched
}
```

The sibling test at L973 ("Records ACEProperties drift...") keys on `Property`, not `Type`, and
still passes — correctly.

---

## 5. NEW: BUG-044 — consolidated body filter drops 11 of 12 producers (NOT FIXED, needs approval)

`Audit-TierModel.ps1`, consolidated per-entity loop:

```powershell
$driftFromFindings = $result.Findings | Where-Object {
    ($_.PSObject.Properties.Name -contains 'Type') -and $_.Type -eq 'Drift'
}
```

No producer except `Test-TierModelOuAcl` ever emitted `Type='Drift'` (and after BUG-042 none
does). Every GPO, ADMX, MSA, gMSA, dMSA, WinLaps ACL, WinLaps Decryptor, Domain Audit Rule,
Auth Policy, Auth Silo and Canonical ACL finding is silently dropped from the `-FullDeployment`
console itemisation and report body. Counts are unaffected — `DriftCount`, compliance, exit
code and `failures=` all derive from Summary counters, not from this list — so this is an
**evidence** defect, the same class as BUG-028/BUG-030 and the same class this release exists
to eliminate.

Severity: medium-high on evidence quality, nil on CI.

Recommended fix (**not applied**): give the remaining producers the same treatment BUG-042 gave
the OU ACL path — publish a `DriftFindings` projection per producer/wrapper rather than widening
the shared filter, so the drift-class decision stays with the code that counted it. Widening the
filter instead would newly admit `Compliant`-typed rows from four producers, which is the
inverse defect fixed under BUG-034.

**Why I stopped:** applying this changes the report body of every `-FullDeployment` run for
eleven producers. Joel's instruction was to flag behaviour changes, not make them.

---

## 6. Out of scope, confirmed untouched

* `Test-TierModelOuAcl.ps1` identity-check `continue` that swallows a failure — left alone, per
  brief. It belongs to the 102-site lossy-catch triage population.
* The four deliberate raw-path `Identifier` sites from BUG-040 (`Test-TierModelOuAcl` outer
  catch, `Test-TierModelMsaAcl:129`, `Test-TierModelGmsaAcl:129`, `Test-TierModelDmsaAcl:139`) —
  not touched, not tidied.
* `-OuOnly` / `-GroupOnly` / `-UserOnly` publish blocks — byte-identical, verified by sweep.
* Json / Html / NUnitXml renderers — byte-identical, verified by sweep.
* `tests\`, `specs\`, `docs\`, `.research\`, `CHANGELOG.md` — not touched.
* The original two-GPO customer incident remains formally CLOSED as UNKNOWN. No cause asserted.

## 7. Over-fixing guard

**Three distinct behaviours changed**, all in the reporting layer, none in a verdict:

1. `Test-TierModelOuAcl` finding labels: generic `Drift` -> the class already counted
   (`Missing` x3 sites, `Mismatch` x1). Fixes two provably wrong labels.
2. OU ACL findings reach both scopes through one shared `DriftFindings` projection, so the two
   scopes render identically and the unreadable-ACL finding is itemised in both.
3. `MissingCount` / `MismatchCount` published at the three scope branches that published only
   `DriftCount`.

Confirmed **not** altered: `-OuOnly`/`-GroupOnly`/`-UserOnly`; the Json, Html and NUnitXml
renderers; all nine `DriftCount` assignments; the exit-code gate; the completion log record.
A compliant estate still reports `0 / 0 / 0` with an empty body on both the OU ACL path and the
standalone path — the fix under-reports rather than manufacturing a false green.

UTF-8 BOM on `Audit-TierModel.ps1` verified `EF BB BF` after every write. Both edited files
parse with 0 errors. `Test-TierModelOuAcl.ps1` correctly has no BOM — BUG-033 applied BOMs to
the two entry scripts only, confirmed against `HEAD`.
