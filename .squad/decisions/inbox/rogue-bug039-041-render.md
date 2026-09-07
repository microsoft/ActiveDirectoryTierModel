# BUG-039 / BUG-040 / BUG-041 — the Audit report rendering path

- **Owner:** Rogue
- **Requested by:** Joel Platek
- **Branch:** `feature/enable-verbose-debug`
- **Date:** 2026-09-05T18:40+08:00
- **Files changed:** `Audit-TierModel.ps1`, `modules\TierModel\public\Test-TierModelOuAcl.ps1`
- **Nothing staged, nothing committed.**

---

## Summary of verdicts

| Bug | Root cause | Where fixed | Data loss? |
|---|---|---|---|
| BUG-039 | `$OFS` array flattening inside an expandable string | render site (correct place) | No — pure rendering |
| BUG-040 | Producer re-read the RAW config value for one field | **producer**, not render site | No — cosmetic, but self-contradictory |
| BUG-041 | A global override that discards drift components | aggregation loop | **YES — the headline count was wrong** |

---

## BUG-039 — every finding on one physical line

### Root cause

The findings list is emitted from a subexpression inside a here-string:

```powershell
$(... else { $driftFindings | ForEach-Object { "[$($_.Type)] ..." } })
```

A subexpression that yields an **array** inside an expandable string is flattened using
`$OFS`, which defaults to a **single space**. So N findings become one physical line joined
by spaces. This is a language semantic, not a loop bug — the pipeline produced 11 correct
strings and the string interpolation glued them together.

Reproduced exactly before touching anything: 11 findings, **1 newline**, everything on one line.

### Fix

One line. Join explicitly:

```powershell
($driftFindings | ForEach-Object { "[$($_.Type)] $($_.ResourceType)/$($_.Identifier): $($_.Details)" }) -join [Environment]::NewLine
```

### Before / after (rendered from the shipping here-string, 11 findings)

BEFORE — `chars=1699 newlines=16`, FINDINGS block is one line:

```
=== FINDINGS ===
[Missing] OU/Tier0-Servers: OU does not exist [Mismatch] Group/T0-Admins/GroupScope: Expected Global, found Universal [Mismatch] User/svc-t0/Location: Wrong OU [Drift] ACL/T0-Admins-1 -> OU=Tier 0 Servers,DC=tierlab,DC=local: No Access Control Entry found for 'T0-Admins-1' on 'OU=Tier 0 Servers,DC=tierlab,DC=local' [Drift] ACL/T0-Admins-2 -> OU=Tier 0 Servers,DC=tierlab,DC=local: No Access Control Entry found for 'T0-Admins-2' on 'OU=Tier 0 Servers,DC=tierlab,DC=local' [Drift] ACL/T0-Admins-3 -> ...
```

AFTER — `chars=1753 newlines=28`, one finding per line:

```
=== FINDINGS ===
[Missing] OU/Tier0-Servers: OU does not exist
[Mismatch] Group/T0-Admins/GroupScope: Expected Global, found Universal
[Mismatch] User/svc-t0/Location: Wrong OU
[Drift] ACL/T0-Admins-1 -> OU=Tier 0 Servers,DC=tierlab,DC=local: No Access Control Entry found for 'T0-Admins-1' on 'OU=Tier 0 Servers,DC=tierlab,DC=local'
[Drift] ACL/T0-Admins-2 -> OU=Tier 0 Servers,DC=tierlab,DC=local: No Access Control Entry found for 'T0-Admins-2' on 'OU=Tier 0 Servers,DC=tierlab,DC=local'
...
[Drift] ACL/T0-Admins-8 -> OU=Tier 0 Servers,DC=tierlab,DC=local: No Access Control Entry found for 'T0-Admins-8' on 'OU=Tier 0 Servers,DC=tierlab,DC=local'
```

Only the `Text` renderer was affected. `Json` goes through `ConvertTo-Json`, `Html` and
`NUnitXml` emit counts only. **Not** changed.

---

## BUG-040 — `{{DOMAIN_DN}}` leaking into identifiers

### Root cause — this is a PRODUCER omission, NOT an upstream resolution failure

Joel asked specifically whether resolution failed upstream. **It did not.** `$domainDN` and
`Resolve-TierModelPlaceholder` were correct throughout. The evidence is inside the finding
objects themselves: in every affected finding the `ExpectedValue` and `Details` fields carry
the **fully resolved** DN while only `Identifier` carries the placeholder. A single finding
object contradicted itself. A resolution failure cannot produce that — it would corrupt all
three fields together, which is exactly the shape of the earlier incident documented at
`Get-TierModelGpo.ps1:99`.

`Test-TierModelOuAcl.ps1` resolves once at the top of the loop:

```powershell
$targetOUPath = Resolve-TierModelPlaceholder -Path $acl.targetOUPath -DomainDN $domainDN
```

…and then **five** finding sites built their `Identifier` from the raw `$($acl.targetOUPath)`
instead of the resolved local. Stale-source read, one field, one file.

I did **not** add a second expansion pass at the render site. That would have been papering
over, and would also have been wrong: the render site has no `$domainDN` in scope and would
have had to re-resolve, re-introducing exactly the fragility the BUG-019 comments warn about.

### Fix

Five `Identifier` fields in `Test-TierModelOuAcl.ps1` now use the resolved `$targetOUPath`
(properties `TargetOU`, `Identity`, `ACLAccess`, `ACE`, `ACEProperties`).

### What I deliberately did NOT change

- **`Test-TierModelOuAcl.ps1` outer catch (`Property = 'Audit'`).** If the resolve itself is
  what threw, `$targetOUPath` still holds the **previous loop iteration's** value. A silently
  wrong identifier is worse than a visible placeholder. Left raw, and commented.
- **`Test-TierModelMsaAcl` / `GmsaAcl` / `DmsaAcl` (one site each).** These sit in the
  **resolution-failure catch**, where reporting the unresolvable config value is the correct
  behaviour. Changing them would have been over-fixing.

---

## BUG-041 — the summary counters contradicted the body

### Is this instance eight of the BUG-026 family? **Partly — and Joel's framing needs correcting.**

It shares the family's *root architectural cause*: **reporting numbers are maintained by hand
against a key list, and nothing verifies the result.** In that sense, yes.

But two things in the brief do not survive contact with the evidence:

1. **It is NOT "console right, saved artifact wrong."** The consolidated console Overall
   Summary prints the *same* `$totalMissing` / `$totalMismatched` / `$totalDrift` variables the
   report reads. Console and artifact were **equally wrong and agreed with each other**. What
   they contradicted was the *per-entity* console block and the findings body. That matters:
   the previous seven were caught by comparing console to artifact, and that method would
   **not** have caught this one.

2. **It is not a scope-branch publish bug.** BUG-027/028/030/032/034/036 all live in the
   *publish* step of a scope branch. This one lives in the **aggregation loop** that runs
   before any branch. The scope-publish guard proposed under specs/007 would not have caught it.

### Root cause — TWO defects, and the second is the real one

**(a) Two Summary key conventions, only one of them read.**
`Test-TierModelOu/Group/User` publish `MissingCount`/`MismatchCount`; every other producer
publishes `Missing`/`Mismatched`. `$totalDrift` already read **both** spellings of its own key.
`$totalMissing`/`$totalMismatched` read only the short spelling, so OU/Group/User drift was
dropped from the breakdown.

**(b) A global override that is unconditionally lossy — this is the real root cause.**

```powershell
if ($totalMissing -gt 0 -or $totalMismatched -gt 0 -or $totalUnverified -gt 0) {
    $totalDrift = $totalMissing + $totalMismatched + $totalUnverified
}
```

This is an **overwrite**. `TRUE-FINAL-1` already carried a comment warning that any component
not named in the formula is discarded. The lab run proved that warning true.

It cannot be repaired by widening the formula, because the producers fall into two **disjoint**
families (AST-verified across every `Test-TierModel*` Summary literal):

| Family | Publishes | Consequence |
|---|---|---|
| `Test-TierModelOuAcl` (all 3 Summary shapes) | `Missing`/`Mismatched`, **no drift total at all** | plain accumulation misses it — *this is why the override exists* |
| `Test-TierModelGPOAudit`, `Test-TierModelAdmx` | a `Drift` total, **no Missing/Mismatched** | the override misses **them** |
| `Test-TierModelOu/Group/User` | both, `*Count` spelling | dropped by (a) |
| MSA/gMSA/dMSA/LAPS/AuditRule/AuthPolicy/AuthSilo | both, short spelling | fine |

Whichever way that single formula is written, one family is discarded. In the lab run the
correctly accumulated `Drift = 11` was computed and then **overwritten with 8**.

### I overruled my own first fix

My first attempt fixed only (a) — read both key spellings. It was clean, symmetric with
`$totalDrift`, and made the lab arithmetic reconcile. **It was wrong.** It took Integration
from 318/318 to 316/318, and the two failures were not noise: they asserted
`Total Drift: 5` and `Total Drift: 10`, and my change produced 3 and 8 by feeding the override
a *newly larger* Missing/Mismatch pair while still discarding the GPO/ADMX drift totals. Fixing
(a) alone changes *which* family gets dropped; it does not stop the dropping.

The failing tests are what exposed it. I did not adjust them.

### Fix

Per-**result** accumulation, replacing the global override:

- honour a producer's **own** drift total when it publishes one (`Drift`, else `DriftCount`);
- derive `Missing + Mismatched + Unverified` **only** for producers that publish no total;
- accumulate the Missing/Mismatch/Unverified breakdown reading **both** key spellings;
- **delete** the global override entirely.

A single global formula cannot express a per-producer choice — same lesson as BUG-036, where
a parameter could not express the problem and the call site had to move.

Two small helpers were added, `Test-SummaryKey` and `Get-SummaryCount`, because presence must
be distinguishable from a zero value: *"publishes no drift total"* and *"publishes a drift
total of 0"* need opposite treatment, and `Get-SafePropertyValue` collapses both to `0`.

`TRUE-FINAL-1`'s original concern — that an unreadable OU must not vanish from the headline —
is preserved: `Test-TierModelOu` already folds `$unverifiedCount` into its own `DriftCount`
(`Test-TierModelOu.ps1:346`), so the producer's total carries it. Verified by guard below.

### Result

| | Drift | Missing | Mismatch | body findings |
|---|---|---|---|---|
| lab, before | 8 | 8 | 0 | 11 |
| after fix | **11** | 9 | 2 | 11 |

Headline now equals the body count, and the breakdown sums to the headline.

---

## Challenging the brief

**Cyclops's assessment — "the multi-entity content itself survives correctly; this is rendering,
not loss" — is correct for BUG-039 and BUG-040 and WRONG for BUG-041.**

BUG-039 and BUG-040 lose nothing: 11 findings in, 11 findings out, all text present, only the
line breaks and one identifier field wrong. Genuinely lower severity than the BUG-026 family.

**BUG-041 is real numeric loss and should be rated with the BUG-026 family, not below it.** The
headline `Drift Findings` count was **8 when the true answer was 11**. Three real drift items
were absent from the number an operator reads first, and from the NUnit XML `failures=`
attribute that a CI gate keys on. A compliant estate still reports 0 (guarded), so this does
not manufacture a false green — but it does **under-report** drift, and a run with drift only
in the OU/Group/User family plus GPO could under-report substantially. I would not ship it.

Two further corrections to the framing, both above: BUG-041 is **not** "console right, artifact
wrong" (both were wrong and agreed), and it is **not** in the scope-branch publish step, so the
specs/007 publish guard would not have caught it.

**A note on the "8 identifiers" and "8 Missing" coincidence.** These are the same 8 objects.
They are the `Test-TierModelOuAcl` findings: counted in the summary as `Missing`, rendered in
the body as `[Drift]`, and carrying the leaked placeholder. All three defects converged on one
producer, which is why one lab run surfaced all three at once.

## Left deliberately unfixed — BUG-042 candidate

`Test-TierModelOuAcl` emits `Type = 'Drift'`. The `-OuAclsOnly` branch re-classifies that into
`Missing`/`Mismatch`; the consolidated `-FullDeployment` path does not. So the same finding
renders `[Missing]` in one scope and `[Drift]` in another, and the summary calls it "Missing"
while the body calls it "Drift". The arithmetic now reconciles either way, so this is a
**labelling** inconsistency, not a counting one. Fixing it means touching a type derivation
across two scopes and was outside the three bugs I was given. **Recommend BUG-042.**

## Over-fixing guard

**Three distinct behaviours changed.**

1. Text-report FINDINGS list joins with newlines (BUG-039).
2. Five `Identifier` fields report the resolved OU path (BUG-040).
3. Consolidated drift/missing/mismatch totals accumulate per-result instead of via a global
   override (BUG-041).

Plus two pure-addition helpers with no behaviour of their own.

**Confirmed unchanged:** the Json/Html/NUnitXml renderers; the compliant-estate result (0
stays 0, guarded); the unverified-only result (1 stays 1, guarded); every producer's own
counts; the three MSA-family raw-path catch identifiers; the `Test-TierModelOuAcl` outer-catch
identifier; all test files, `tests\helpers\ADStubs.ps1`, `specs\`, `docs\`, `.research\`.

**No claim is made anywhere about the cause of the original two-GPO customer incident.**

## Verification

- `Audit-TierModel.ps1` UTF-8 BOM `EF BB BF` verified present after **every** write, including
  the final one. Both files parse with 0 errors. `Test-TierModelOuAcl.ps1` had no BOM at HEAD
  and still has none.
- Line numbers re-derived by AST immediately before editing; all anchors were unique text.
- **Unit: 1573 passed / 1573 / 0 failed.** Matches baseline exactly.
- **Integration: 318 passed / 318 / 0 failed.** Matches baseline exactly. The two failures
  produced by my first (incomplete) fix are gone, and they went green because the corrected
  code produces the numbers those tests always expected — not because I touched them.
- Scratch probes deleted; repo root clean.
