# Decision record — audit counter & T018b test resolution

**Agent:** Wolverine (tests)
**Date:** 2026-09-07
**Requested by:** Joel Platek
**Base:** HEAD `6725ab3`, Rogue's audit-reporting fix uncommitted in the working tree
**Scope touched:** `tests\Unit.WinLapsAclOperations.Tests.ps1`, `tests\Unit.AuditReporting.Tests.ps1`
**Nothing committed, nothing staged, no product file changed.**

---

## D1 — T018b: the test was wrong, the product is right

**Verdict: uphold Rogue's change. The old assertion encoded a defect.**

Reached independently, on four pieces of evidence:

1. **Determinacy.** `Get-GPO -All` *succeeded*; the `-like` filter matched nothing. That is a
   determinate statement about the estate — the decryptor GPO is absent. `Status = 'Error'`
   everywhere else in this report means *compliance could not be established*, and it is what
   drives the "COMPLIANCE COULD NOT BE FULLY DETERMINED" banner. Reporting a determinate absence
   as an inability to determine is a false claim about the audit's own reach.
2. **Sibling parity, verified in source rather than assumed.**
   `Test-TierModelAuthPolicy.ps1` L104-110 reports a policy that is not in the directory as
   `Status = 'Missing'` and increments `$missingCount`. Same situation, same vocabulary. The
   decryptor was the outlier.
3. **The producer's own documented contract.** `Test-TierModelWinLapsDecryptor`'s comment-based
   help says "Reports each result as Compliant, Missing, or Mismatched." The old branch reported
   a fourth thing the contract does not name.
4. **Drift is unaffected.** `$drift = $missingCount + $mismatchCount + $errorCount`, so moving the
   row between two counters leaves the section total at 1. Only the label and the *error* count
   change, which is the whole intent.

**Rogue's refusal to relabel the other five sites was correct and is now enforced, not merely
documented.** An `Error -> Missing` blanket pass would report an unreachable domain controller as
a clean-but-absent estate — strictly worse than the bug being killed.

## D2 — both halves of T018b are covered, and the AST ratchet is the half that earns its keep

Three tests replace one:

| Test | Guards |
|---|---|
| `GPO resolved but nothing matched: Missing status, and Errors stays at 0` | the new behaviour, with exact integers (`Missing=1, Errors=0, Drift=1`) rather than `-BeGreaterThan 0` |
| `Determinate absence and could-not-determine states are classified apart, in one table` | the two classes **against each other** across five branches — fails on a collapse in *either* direction |
| `Keeps five could-not-determine construction sites and two absence sites in the shipping producer` | an AST census of `Status = '...'` hashtable literals: 5 Error / 2 Missing / 1 Mismatched / 1 Compliant |

The AST ratchet is not redundant. The fifth Error site is the **outer catch**, which is not
reachable from any mock because every inner failure is already handled. Control C3 relabelled it
`'Error' -> 'Unverified'` and **only** the ratchet failed — 87/88 otherwise green. Without it, that
branch could be deleted or relabelled and nothing in a 1,962-test suite would move.

## D3 — the reduced-bug assertion is on the shared readers, not on `Get-SafePropertyValue`

**This departs from the brief, deliberately.** The brief asked for one assertion that
`Get-SafePropertyValue` agrees for a hashtable and a PSCustomObject. **It does not, and Rogue did
not make it.** Measured directly against the shipping helper:

```
Get-SafePropertyValue <pscustom Summary> 'Summary.Drift'  -> 5
Get-SafePropertyValue <hashtable Summary> 'Summary.Drift' -> 0
```

He routed the drift and error reads *around* it via `Get-SummaryCount`/`Test-SummaryKey` instead
of teaching it to read a dictionary. That is the smaller blast radius and I am not proposing it be
changed — `Get-SafePropertyValue` still has five live callers doing entity-type detection off
`Summary.Total*`, and widening it would touch all of them (skill rule 10).

So the "two must agree" assertion is written against **the readers the report actually uses** —
`Get-EntityDriftTotals` and `Get-EntityErrorTotal` — which is where the requirement really lives.
The type-blindness is then pinned by three separate things:

* a test naming the **mechanism** as a fact about PowerShell (`@{Drift=6}.PSObject.Properties.Name`
  contains `Keys` and `Count`, never `Drift`) — that assertion cannot rot;
* one explicitly-labelled test documenting the **live limitation** of `Get-SafePropertyValue`, with
  an instruction saying it is the line to delete if the helper is ever made dictionary-aware;
* an **AST ratchet** proving no drift or error count is read through a dotted `Summary.*` path.
  Population stated: all 7 `Get-SafePropertyValue` call sites; the survivors are 5 × `Summary.Total*`
  entity-type detection and 2 × top-level `'Errors'`, none of which is a count off a hashtable.

## D4 — reconciliation is asserted as numbers *and* as a single definition

A section total and a grand total computed from one shared function agree tautologically. Skill
rule 14 says two agreeing outputs prove only a shared source — so the assertion that carries the
weight is the **call-site ratchet**: `Get-EntityDriftTotals` and `Get-EntityErrorTotal` are each
called **exactly twice**, once per loop, with no third copy. The numeric half uses a drifted
8-section estate built from the nine real `Summary = @{...}` wrap sites, and reproduces Rogue's
measurements exactly: **drift 14, missing 8, mismatched 5, errors 1**.

## D5 — an error is counted once, and Cyclops's estate-scale shape is a named test

`Summary.Errors`, the top-level `Errors` collection and `Status='Error'` findings are three
renderings of one failure. `Max(Max(a,b),c)` is asserted against four shapes: one error in all
three representations -> 1; **six decryptor errors -> 6, not 12** (Cyclops's `Total Errors: 12` over
sections summing to 6); findings-only with the count left at 0 (Test-TierModelAdmx) -> still counted;
count-only with no findings -> still counted.

## D6 — colour is asserted by class, and Cyclops's yellow `[Error]` is confirmed by control

Control R3 restored the original `if ($_.Type -eq 'Missing') { 'Red' } else { 'Yellow' }` rule.
`Get-TierModelFindingColor 'Error'` returned **Yellow** under it. Cyclops's report is correct and is
now a test: undeterminable -> Red, missing-family (`Missing`/`MissingAcl`/`MissingAuditRule`/
`NotFound`/`Absent`) -> Red, present-but-wrong -> Yellow, **unknown -> Red** (escalate, never demote).
Plus a ratchet: 4 classifier call sites and **0** surviving `-eq 'Missing'` colour literals.

## D7 — observation, NOT acted on: a latent dead comparison in the entity-type fallback

`Audit-TierModel.ps1` L1918-1922 read
`elseif (Get-SafePropertyValue $result 'Summary.TotalOUs' -gt 0) { "OU" }`. `Get-SafePropertyValue`
is a plain function with two positional parameters, so `-gt` and `0` land in `$args` and are
discarded — the branch tests the raw return value for truthiness, not `> 0`. Behaviourally
equivalent today (any non-zero count is truthy), so it is latent, not live. It also only executes
when `EntityType` is absent, which no wrapped producer allows. **Pre-existing, outside Rogue's
change and outside `tests\`. Reported, not fixed, and not asserted either way** so a future correction
does not have to fight a test.

## D8 — my four CI-parity recommendations remain open and unacted

Unchanged and still awaiting Joel's ruling: (1) make local runs CI-shaped by default;
(2) `Set-StrictMode` in every test file or none; (3) a stub-fidelity meta-test; (4) pin the CI Pester
version. Nothing in this session depends on any of them.

---

## Counts

| Run | Before | After | Delta |
|---|---:|---:|---:|
| By-path Unit (25 files) | 1608 / 1608 / 0 | **1632 / 1632 / 0** | +24 |
| By-path Integration (7 files) | 330 / 330 / 0 | **330 / 330 / 0** | 0 |
| CI-shaped (32 containers) | 1938 / 1937 / **1 failed** | **1962 / 1962 / 0** | +24, −1 failure |
| Coverage gate (80%, `exit 1`) | 87.37% PASS | 87.37% PASS | 0 |

+24 = 2 net new in `Unit.WinLapsAclOperations.Tests.ps1` (1 replaced by 3) and 22 new in
`Unit.AuditReporting.Tests.ps1`. By-path Unit + Integration = 1632 + 330 = 1962, exactly the
CI-shaped figure, so nothing is discovered in one shape and not the other. Coverage is flat because
`Audit-TierModel.ps1` is not in the CI `CodeCoverage.Path` list — the new tests raise assurance on a
file the gate has never measured.

## Control-proofs — six, each restoring the product byte-identically

| # | Deliberate break | Failed | Right reason |
|---|---|---:|---|
| C1 | decryptor absence back to `Status='Error'` / `$errorCount++` | 3 | new behaviour, class table, AST census 5→6 |
| C2 | ambiguous-match branch relabelled `Missing` (blanket collapse) | 3 | class table, AST census 5→4, pre-existing multi-GPO test |
| C3 | outer catch relabelled `'Unverified'` | **1** | **AST census only — nothing else can see this branch** |
| R1 | drift read routed back through `Get-SafePropertyValue` | 4 | agreement 3→0, reconcile 8→0, ratchet 7→12 offenders |
| R2 | `Max(a,b) + c` double-count restored | 4 | 1→2 and 6→12 |
| R3 | original `-eq 'Missing'` colour rule restored | 4 | `Error` rendered **Yellow**, missing-family Yellow, no escalation |

Restoration verified by file hash after every control; `git status` shows the two product files with
Rogue's original diff stats (`18/2` and `149/65`) and no other change.

---

## Addendum — after Joel's in-flight update and Rogue's mid-session landing

### D9. `[Error]` red is now covered directly, because nothing else can cover it

Cyclops's lab A/B left **zero `[Error]` findings across all eight scopes**: the only producer
emitting `Error` in that estate was the exact branch Rogue relabelled to a missing-state. The colour
fix for `[Error]` is therefore real but unexercised outside a unit test.

Added, as standalone tests rather than as a by-product of the missing-family assertion:

- `[Error]` -> Red, with an explicit `Should -Not -Be 'Yellow'` and case variants.
- A chain test: producer-shaped `Status='Error'` -> `ConvertTo-TierModelDriftFinding` -> `Type='Error'`
  -> `Get-TierModelFindingColor` -> the rendered `[Error]` marker. This is the path an operator sees.
- The other could-not-determine synonyms, kept in their own test so that collapsing them does not
  silently take `[Error]` with it.

Control R4 isolated `Error`->Yellow only: **3 failures**, the two `[Error]` tests plus the estate
colour test, with the missing-family and other-undeterminable tests still green. That is the proof
the guard is specific to `Error` and not riding on its neighbours.

### D10. Two render sites were never converted to the classifier

`Get-TierModelFindingColor` has 4 call sites, but the report colours findings at **6** places. The
GPO audit findings (~L1200) and ADMX audit findings (~L2221) keep their own inline
`switch ($_.Type)` maps.

`Error` is correctly `Red` at both, so there is no live severity bug there — but the maps end in
`default { 'Gray' }`, which means ADMX's own `ADMX`/`ADML` types render **Gray**. That is the same
class of severity demotion the classifier was created to remove. **Reported, not fixed, not asserted
either way** — converting them is Rogue's call, not mine.

The census test asserts the honest numbers (4 delegating, 6 total, 0 legacy `-eq 'Missing'`
literals), and a separate test pins `Error->Red` and `Missing->Red` at the two unconverted maps.
Control R5 broke `'Error' { 'Red' }` in the first unconverted map only: **1 failure**, that test.

### D11. OU ACL findings: an Error must not be manufactured

Rogue's mid-session `Invoke-OuAclAudit` rewrite replaced

```
Type = if ($_.Type -eq 'Missing' -or $_.Type -eq 'Mismatch') { $_.Type } else { 'Error' }
```

with the shared normaliser. The old form was an exact-literal whitelist of two that collapsed
**everything else** to `Error` — inventing an error the audit never encountered. This removes yet
another `[Error]` source from the lab, so like D9 it can only be covered by unit test.

Three tests added: a non-Missing/non-Mismatch finding keeps its own type and yields no `Error`
(and renders Yellow, not Red); a genuine `Error` still arrives as `Error` in Red; and a source
ratchet that the collapse expression is gone and the projection goes through the normaliser.

### D12. `[AuditRight]` — deliberately left unruled, and it is the suite's only failure

Rogue also removed the per-right `Type='AuditRight'` findings emission from
`Test-TierModelAuditRule.ps1`, making those rows console-only.

Census over the enumerated 86-file product surface: **0 producers** of `Type='AuditRight'` remain;
**1 consumer survives**, `if ($findingType -eq 'AuditRight')` inside `ConvertTo-TierModelDriftFinding`.
That is rule 19's exact shape — a consumer whose population has silently fallen to zero. It is
currently harmless (the branch is a passthrough, not a filter), but it is now dead code.

Supporting evidence for Joel's ruling: **no exported artifact consumes `Findings`**. There is no
`Export-Csv`/`Export-Clixml` of findings anywhere in `Audit-TierModel.ps1`; findings are
console-rendered. So the removal loses no machine-readable output, which supports Rogue's stated
rationale (one drifted object, one finding, so the section's finding count agrees with its Drift
counter).

**This breaks the pre-existing test `Emits one granular AuditRight finding per configured right`
(`Unit.AuditRuleOperations.Tests.ps1:458`), which asserts exactly 9 granular findings with per-right
Pass/Fail.** It is the same shape as T018b: a test encoding behaviour the product has deliberately
changed. Joel explicitly reserved this ruling pending Rogue's confirmation, so **I have not touched
it in either direction** — relaxing it would pin absence, and it is not mine to pin. It is the
single remaining failure in the suite and it is correctly attributed to an un-ruled product change,
not to my work.

### D13. `Unit.Prerequisites.Tests.ps1` was not safe to run twice at once

A CI-shaped run mid-session reported **33 failures**. None were mine — all 33 were in
`TierModel Prerequisites Tests`, and the messages were `Dependencies file not found`. A clean
re-run with nothing else running gave **1970 / 1969 / 1**. The 33 were an artifact of another
agent's `pwsh` running the suite concurrently on this shared box.

Cause: that file built fixture paths as fixed names directly in the **shared system temp root** —
`valid-dependencies.json`, `invalid-dependencies.json`, `ext-prereq-full.json`,
`ext-prereq-pester.json`, `test-deps-missing.json`. Two simultaneous runs share those paths and the
first to finish deletes the fixtures the other is still reading.

Population check across `tests\`: 16 temp-path constructions, **14 already unique** (`Get-Random` /
`New-Guid`). `Unit.Prerequisites.Tests.ps1` was the sole outlier, at two `BeforeAll` sites.

Fixed both to a per-run GUID directory, with `AfterAll` removing only that directory.

**This is a discretionary fix inside `tests\`, which I own, and Joel can back it out cleanly** — it
is three hunks in one file and changes no assertion. Note it does **not** affect real CI, which runs
a single process; it protects this team's shared-box workflow, and it cost a full investigation
cycle today.

Control (concurrent pairs, 3 runs each):

| State | Failures across 3 concurrent pairs |
|---|---|
| Original shared temp root | 13, 4, 6 — always the second job to finish |
| After fixing site 1 only | still failing on `ext-prereq-full.json` — **the fix was incomplete and the probe caught it** |
| After fixing both sites | 1, 0, 0 |

The first attempt looked *worse* than the control (2 failures vs 0) because the race is timing
dependent and a single pair is not a measurement. Capturing failure **names** rather than counts is
what identified the missed second site. A count alone would have sent me to tune the fixture.

Residual: one lower-frequency race remains (`Should report RSAT-AD remediation when ActiveDirectory
module is missing`, ~1 pair in 6). It is not fixture-related — it looks like module-import/
`Get-Module -ListAvailable` contention between the two processes. **Reported, not chased.**

---

## Addendum 2 — label question answered, and what the tree says

### D14. Rogue's three-state `AuditRight` table is correct. I verified it, then pinned it.

Read directly from `ConvertTo-TierModelDriftFinding` and reproduced with the lifted function:

| `AuditRight` state | Result | Colour |
|---|---|---|
| `Status='Pass'`, `ActualValue='Present'` | dropped, zero rendered | n/a |
| `Status='Fail'` or `ActualValue='Missing'` | `MissingAuditRule` | Red |
| any third state (e.g. `Status='Warn'`, `ActualValue='Inherited'`) | stays `AuditRight` | Red |

Two genuinely independent guards, as Joel described: the Pass/Compliant/OK/Success/True status
guard at `:349`, and the state-conditioned relabel at `:361`. Five tests added, and **the pinned
claim is "never appears for a Pass or Fail row", never "never appears"**.

Reproduced Rogue's harness arithmetic exactly: feeding the 9 configured rights plus the summary row
gives **10 emitted -> 9 rendered**, all `MissingAuditRule`, all Red. That corroborates the lab
observation of 9 lines before and after.

Controls: **E3** (relabel made unconditional) -> 3 failures including the third-state test; **E4**
(Pass guard deleted) -> 4 failures including the Pass-drop test. Neither control fails the other's
test, which is what proves the two guards are pinned separately rather than one riding on the other.

### D15. The `[Error]` fixture, taken end to end through the real producer

Rather than a hand-written finding shape, the new tests run the **real**
`Test-TierModelWinLapsDecryptor` with `Get-GPO` mocked to throw, then carry its actual output through
the **real** normaliser and colour classifier lifted from the shipping report. A synthetic shape can
drift away from what the producer emits; this cannot.

Three tests: GPO query failure -> red `[Error]`; ambiguous multi-GPO match -> red `[Error]`, not an
absence; and the absence branch -> `Missing`, in the same file so that collapsing the branches in
**either** direction fails something.

This is the two-for-one Joel identified: the same tests prove `[Error]` renders red *and* pin
Rogue's refusal to relabel the five could-not-determine sites.

Controls: **E1** (`Error` forced to Yellow) -> 6 failures, spanning both files; **E2** (the
`Get-GPO`-throw branch relabelled `Error`->`Missing`, the edit a maintainer would actually make) ->
4 failures, including the new end-to-end test.

### D16. Correction to the brief: the producer change is NOT merely under consideration

Joel wrote that a change to `Test-TierModelAuditRule.ps1` dropping the per-right rows "is not
approved yet and Rogue has made no edits."

**The edit is in the working tree and has been throughout this session** — blob `f35a24b`, 21 lines
changed, removing the entire `Type='AuditRight'` emission block. Measured against the tree:

- `AuditRight` emit sites in the producer: **0**.
- Consequently the 10-emitted/9-rendered arithmetic is reachable only with the edit reverted. With
  the edit in place the producer emits **one** finding for this drift, so the section renders
  **1** `[MissingAuditRule]` line, not 9.
- It is the **sole failing test in the whole suite**: `Unit.AuditRuleOperations.Tests.ps1:458`,
  which asserts 9 granular findings.

On the merits the change is defensible, and two facts support it: no exported artifact consumes
`Findings` (no `Export-Csv`/`Export-Clixml` anywhere), and the per-right detail is **not** lost —
the summary row's `Details` carries `Missing rights: <list>`. But it is unapproved, it changes
rendered output 9 lines -> 1, and it should be ruled on explicitly rather than shipped by accident.

**I have not touched that test in either direction.** Relaxing it would pin absence; it is not mine
to pin, and it correctly encodes an unresolved question.

### D17. No new brittle literals on that producer

Per Joel's heads-up, the new tests assert **reconciliation and classification**, not finding counts
on `Test-TierModelAuditRule`. Every new assertion is expressed against the normaliser and the colour
classifier using explicit finding shapes, so it survives whichever way the producer question is
ruled. The one count-shaped assertion (`Should -Be 2` in the two-guards test) counts rows of a
literal fixture defined in the test itself, not producer output.

---

## Addendum 3 — Option A landed; the producer test retired and replaced

### D18. `Unit.AuditRuleOperations.Tests.ps1` — retired one literal, added three guards

The failing test asserted `$rightFindings.Count | Should -Be 9` against the per-right `AuditRight`
rows that Joel ruled out of the findings collection. It encoded the old behaviour, so it goes — but
it was **the only thing pinning that producer's finding shape**, so deleting it bare would have left
the next change to move finding counts with a green suite.

Replaced with three tests, none of them a producer-count literal:

1. **`One finding per counted object`** — `Compliant + Drift + Errors == Findings.Count`, plus the
   single finding being `MissingAuditRule` and its `Details` still carrying `Missing rights: ...`
   (the detail the removed rows used to carry).
2. **`Reconciles in all three verdict states`** — compliant and drifted each produce exactly one
   finding, so the invariant cannot be satisfied by a producer that simply emits nothing.
3. **`Keeps the per-right console output`** — the ruling removed the rows from *findings* only. The
   operator-facing per-right console output is a separate surface that was explicitly kept, and
   after retiring the old test **nothing else pinned it**.

This is strictly stronger than what it replaces: the literal `9` only caught a change to that one
count, whereas the reconciliation catches **any** re-multiplication of per-object findings.

Controls, with the producer restored byte-identically and `diff --stat` unchanged either side:

| # | Deliberate break | Failed | Which |
|---|---|---:|---|
| F1 | per-right rows re-added to `$findings` (the ruled-out regression) | **2** | both reconciliation tests |
| F2 | per-right console output deleted | **1** | the console pin only |

F1 is the important one: it is the exact edit the retired test existed to catch, and the replacement
catches it without knowing the number 9.

### D19. The `AuditRight` normaliser branch is now guarded only by unit tests

With Option A landed, **no producer emits `Type='AuditRight'`**. Rogue kept the normaliser branch
deliberately — deleting a defensive guard because today's producer stopped emitting the shape is how
this class of bug returns — and I agree. The five tests in
`Context 'AuditRight is relabelled from its own state, not rewritten wholesale'` are therefore the
only things that reach it. That is now stated in the Context header, so a future reader does not
delete them as redundant.

The `ProducerDriftShapes` exemplar at the top of the same file has been relabelled from
`Test-TierModelAuditRule (Right)` to `AuditRight shape (normaliser branch, no live producer)`, with
a comment saying plainly that it is **not** producer coverage. It still passes legitimately because
it exercises the normaliser directly, but the old name implied a producer that no longer exists.

### D20. Final state

| Run | Session start | Final | Delta |
|---|---|---|---|
| By-path Unit | 1608 | **1650 / 1650 / 0** | +42 |
| By-path Integration | 330 | **330 / 330 / 0** | 0 |
| CI-shaped, 32 containers | 1938 / 1937 / **1** | **1980 / 1980 / 0** | +42, **zero failures** |
| Coverage, gate 80 `exit 1` | 87.37% | **87.36% PASS** | -12 statements |

1650 + 330 = 1980 exactly, so containers and StrictMode did not diverge.

**Fourteen deliberate product breaks across the session** — C1-C3, R1-R5, E1-E4, F1-F2 — each failing
for its intended reason, each restored and verified. Plus three concurrency trials for D13.

---

## Addendum 4 - unreachable-directory test inversion (2026-09-07 18:05)

**D21. `Unit.GroupOperations.Tests.ps1:622` inverted. Cyclops upheld.**
Old: `\.DriftFindings | Should -BeNullOrEmpty` when `Get-ADGroup` throws a non-identity exception.
New: exactly one `Type='Error'` finding, `Identifier='Tier0Admins/ReadFailure'`, `MissingCount=0`,
`UnverifiedCount=1`, `DriftCount > 0`.
*Why the new value is correct:* the pre-fix producer added a warning and continued, and `\` summed
only missing+mismatch. Warnings do not feed the compliance verdict. So a group whose state was unknown was
counted nowhere and the section printed "All Groups are compliant". The old assertion pinned that. It is
asserted as `Error` and explicitly **not** `Missing` because the group may exist - we failed to ask.
Both pre-existing WARNING assertions in that `It` still pass; Cyclops's change is additive as claimed.

**D22. Gap found: Cyclops's identical User-producer fix had no test at all.** Zero hits in
`Unit.UserOperations.Tests.ps1` for the read-failure path. Added Context "User Read Failure Handling"
(2 tests): per-user Error findings reconciled against `UnverifiedCount`, and
`DriftCount == Missing + Mismatch + Unverified`. Expressed as reconciliation against config count, not literals.

**D23. Control-proof, six breaks, all red for the intended reason, all restored byte-identically:**
G1/U1 `Type='Error'` -> `'Missing'` (1 / 2 failed); G2/U2 drop `+ \` from the drift total
(1 / 2); G3/U3 remove `\++` (1 / 2). `restored=True` on all six against pre-mutation SHA256.

**D24. Observation for Joel, not acted on.** The User producer's outer catch previously returned hardcoded
`DriftFindings = @()` and an all-zero Summary; Cyclops now returns the real values. That hardcoded-zero shape
is the same defect class as the `Missing: 0` Rogue is fixing in Admx. Worth a sweep for other hardcoded
literal summaries in outer catches.

**Counts:** `Unit.GroupOperations` 49/49/0 (unchanged; one assertion rewritten in place).
`Unit.UserOperations` 50 -> **52/52/0** (+2). Expected suite total **1982**, up from the 1980 baseline.
Full CI-shaped run still **held** pending Rogue.
