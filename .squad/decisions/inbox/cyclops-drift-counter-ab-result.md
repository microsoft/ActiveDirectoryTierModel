# Decision record — Audit drift-counter fix: A/B lab result (BEFORE vs AFTER)

**Agent:** Cyclops
**Date:** 2026-09-07
**Requested by:** Joel Platek
**BEFORE:** commit `23b5100` (baseline captured earlier today)
**AFTER:** working-tree snapshot 2026-09-07T13:18:45+08:00, HEAD `6725ab3`, fix **uncommitted**
**Fixture:** `TierLab-DC01` @ `WinLapsSchema`, undeployed estate — identical to the BEFORE run
**Evidence:** `C:\CyclopsStage\run-20260907-124147\FINDINGS-drift-counter-AB-result.md`
**Logs:** `C:\CyclopsStage\run-20260907-124147\after\` (AFTER), `...\final\` (BEFORE control)

---

## D1 — Snapshot method and proof of A/B isolation

Working tree snapshotted as the **first action**; live files re-hashed afterwards and confirmed
unchanged (Rogue idle throughout).

| File | SHA256 | git blob |
|---|---|---|
| `Audit-TierModel.ps1` | `97710A2E…3B38EA77` | `2b396eb6898007e82f415ddbae8dacfc02246236` |
| `Test-TierModelWinLapsDecryptor.ps1` | `4DE0DD33…6893304B` | `78e67a33d9e291290685844061185d7ea3d756c6` |

`git diff --name-only 23b5100 6725ab3` returns **only four `.squad/agents/*/history.md` files** —
zero product delta. AFTER image built as `23b5100` + those two files; SHA256 comparison of the two
698-file builds gives a delta of **exactly 2**. The A/B therefore isolates Rogue's fix and nothing
else.

---

## D2 — VERDICT: the fix works. Recommend acceptance.

| Measurement | BEFORE | Expected | **OBSERVED** | |
|---|---|---|---|---|
| Sections `Drift: 0` over findings | 12 of 14 | 0 | **1 of 14** | see D3 |
| Plain `-FullDeployment` | 4 of 6 broken | all correct | **all 6 correct** | MET |
| Section sum vs grand total | 206 vs 374/402 | reconcile | **374/374, 402/402** | MET |
| `Total Errors` vs sections | 12 vs 6 | 6 vs 6 | **0 vs 0** | see D4 |
| Overall verdict | "COULD NOT BE DETERMINED" | states drift | **`❌ 402 DRIFT ITEMS`** | MET |
| **`Total Checked`** | reconciled | **must not move** | **375→375, 403→403** | **MET** |
| Colour, missing-family | mixed | all red | **all red** | MET |
| Colour, `[Error]` | yellow | red | **UNVERIFIABLE** | see D5 |

Reproducibility confirmed: full scope run twice, all 15 section rows identical.

**Headline strings, verbatim — Joel should see these before retesting:**

    BEFORE   Overall Audit Status: ⚠️  COMPLIANCE COULD NOT BE FULLY DETERMINED (12 error(s))
             Total Checked: 403 / Total Drift: 402 / Total Errors: 12
             Compliance: N/A (could not be determined)

    AFTER    Overall Audit Status: ❌ 402 DRIFT ITEMS
             Total Checked: 403 / Total Drift: 402 / Total Errors: 0
             Compliance: 0.25%

Two user-visible headline changes, not one: the status string **and** `Compliance` moving from
`N/A (could not be determined)` to `0.25%`. The second was not in the predicted set.

**Corroboration, not agreement:** Rogue's type-blindness diagnosis says `Checked:` survived only
because of an explicit `-is [hashtable]` branch. My BEFORE run independently recorded
`Total Checked` reconciling perfectly while every other counter collapsed. His cause predicts my
symptom, measured before I knew the cause.

---

## D3 — Domain Audit Rule: a units ruling is needed, not a bug fix

`Checked: 1, Drift: 1, Errors: 0` above **9** printed finding lines — one object audited, one
drifted object reported, nine lines rendered (8 per-right + 1 summary).

**Now internally consistent**: section says 1, grand total counts 1, `402 = 410 − 8`. Rogue's
"two shared functions, cannot disagree by construction" holds. This is not a surviving instance of
the original defect.

**Requested ruling:** does the `Drift` counter report drifted **objects** or drifted **findings**?
Whichever Joel picks, the output should state it. Until then, the printed-vs-counter reconciliation
check flags this row on every run — a permanent false alarm for any future audit-reconciliation
pass, including Storm's.

---

## D4 — `Total Errors` 12 → 0 (not → 6): accepted, with the reason recorded

The 6 decryptor findings were **reclassified** `Error` → `Missing`, so no errors remained to
count. The prediction assumed they would survive de-duplication.

    BEFORE: [Error]   … Expected=GPO must exist; Actual=No matching GPO   (Yellow)
    AFTER:  [Missing] … Expected=GPO must exist; Actual=No matching GPO   (Red)

**Confirms Rogue's account.** He relabelled only the `Get-GPO`-succeeded-and-matched-nothing site;
in this fixture all six decryptor findings come from that one site, so all six move together. The
old `12` was `6` counted twice and both copies are reclassified. Sections still agree with the
grand total, which is the invariant that matters.

---

## D5 — `[Error]` colour is UNVERIFIED. Do not mark BUG-047 lab-validated.

**Zero `[Error]` findings across all eight AFTER scopes.** The only producer in this estate was
relabelled by D4, so the predicted `[Error]` → red change is **unexercised**. A fix was made
untestable by an adjacent fix.

Probed the unreachable-DC state cheaply and non-mutatingly (`-PreferredDc NOSUCHDC99`):

    Cannot reach PreferredDc 'NOSUCHDC99' on LDAP port 389.
    exit code 1

**An unreachable DC is hard-stopped at the prerequisite gate and never reaches the decryptor.**
So the disaster Rogue guarded against cannot occur through `-PreferredDc`.

**Stated limit of that evidence:** it rules out only the connectivity-at-startup shape. A DC lost
**mid-run**, or `Get-GPO` failing on **permissions** rather than reachability, still reaches the
five `Status='Error'` sites he deliberately left alone. **His refusal was correct and should
stand.** It is simply already defended one layer up for the commonest case.

**Recommendation:** BUG-047 needs a unit test or a purpose-built fixture for the `[Error]` colour
path before it is called lab-validated. I did not manufacture one, per instruction.

---

## D6 — Unpredicted: finding labels are now section-uniform

    BEFORE  Domain Audit Rule:  [AuditRight] x8  +  [MissingAuditRule] x1
    AFTER   Domain Audit Rule:  [MissingAuditRule] x9

**All 14 sections now render exactly one distinct `[Type]` label.** Before the fix at least one
rendered two. `[AuditRight]` has disappeared from the product's output entirely.

Message bodies are **unchanged** (`Property=CreateChild; Expected=Present; Actual=Missing`), so no
detail is lost. What is lost is the label's ability to distinguish "one specific right missing"
from "the whole rule missing" at a glance.

Plausibly deliberate BUG-048 normalisation — **flagged, not credited**, because it was outside the
predicted set. **Rogue to confirm intent.** If labels are now derived per-section rather than
per-finding, that caps what a label can ever express and belongs in the record explicitly.

---

## D7 — No regression on the standalone paths

Five of six standalone scopes byte-identical BEFORE vs AFTER. Only `-IncludeWinLaps` moved, and
only via the D4 reclassification:

    BEFORE  Total Checked: 13   Total Drift: 13   Total Errors: 6
    AFTER   Total Checked: 13   Total Drift: 13   Total Errors: 0

`Total Checked` and `Total Drift` unmoved. Note for the record: "no producer needed touching"
applies to the **counter** fix; the **decryptor relabel** did touch a producer, which is why the
standalone renderer moved at all. Both statements are true and describe different changes.

---

## D8 — Lab state

DC01 **Running** on `WinLapsSchema`. **No checkpoint created, deleted or renamed — still three.**
Estate identical before and after (`TierOUs=0 TierGroups=0 AuthPol=0 Silos=0 GPOs=2`); Audit
performs no writes, fixture intact for the team.

`C:\TierModel` **removed from the guest**. It held the AFTER **uncommitted, unreviewed** build —
the mirror image of last run's stale-build hazard. Anyone auditing that DC would have silently
been exercising Rogue's in-flight fix. Next user must stage deliberately and record which build.

Repo untouched: root at 13 files, nothing staged, nothing committed, HEAD still `6725ab3`.
