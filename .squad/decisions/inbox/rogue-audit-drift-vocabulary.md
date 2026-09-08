# Decision record — Audit drift reporting: colour, labels, and the section/grand-total split

**Agent:** Rogue
**Date:** 2026-09-07
**Branch:** `feature/enable-verbose-debug` — HEAD `6725ab3` (NOT `04ab664`; see Discrepancies)
**Requested by:** Joel Platek
**Status:** Steps 1 and 2 complete and green. Step 3 complete but blocked on one Wolverine-owned test.
**Nothing staged. Nothing committed.**

---

## Baseline, confirmed before any edit

| Shape | Containers | Result |
|---|---|---|
| CI-shaped (`Invoke-AllTests.ps1`, one session, strict) | 32 | **1938 / 1938 / 0** |
| Unit by-path | 25 | **1608 / 1608 / 0** |
| Integration by-path | 7 | **330 / 330 / 0** |

Matches the expected pre-change state exactly. Wolverine's 12 tests are present and green.

---

## D-A. The colour rule is fixed by SEVERITY CLASS, not by a longer literal list

`$color = if ($_.Type -eq 'Missing') { 'Red' } else { 'Yellow' }` existed at **four** sites, not
one — `Invoke-OuAudit`, `Invoke-GroupAudit`, `Invoke-UserAudit` and the consolidated section loop.
All four now call a new `Get-TierModelFindingColor`.

Classification is by class, so a producer inventing a type name tomorrow is coloured sensibly:

* **Red** — undeterminable (`Error`, `Unverified`, `Failed`).
* **Red** — absent: any type *containing* `Missing`, plus `NotFound` / `Absent`. This is deliberately
  a substring test so the helper never needs to learn a producer's spelling.
* **Yellow** — present-but-wrong (`Mismatch`, `Unexpected`, `NonCompliant`, `Extra`, `Drift`, `Warning`).
* **Red** — **unknown types escalate, never demote.** Under-stating severity is the exact failure
  mode that produced this bug; an unrecognised name must not inherit the benign colour.

`[Error]` findings previously rendered **yellow** — worse than anything Joel reported.

## D-B. `AuditRight` → `MissingAuditRule`, derived from state (Trap B)

**Verdict on Trap B: the trap is real. `AuditRight` IS state-agnostic.**

Evidence — `Test-TierModelAuditRule.ps1:177`, a single hashtable emitted per right for **both**
outcomes:

```powershell
Type          = 'AuditRight'
ActualValue   = if ($rightPresent) { 'Present' } else { 'Missing' }
Status        = if ($rightPresent) { 'Pass' } else { 'Fail' }
```

A blanket relabel would therefore have marked a **passing** audit right as missing — re-introducing
precisely the bug the comment at `Audit-TierModel.ps1:345-346` records having fixed.

The relabel is placed in `ConvertTo-TierModelDriftFinding` (one normalisation point, shared by the
text/JSON/HTML consumers) **after** the compliant-drop guard, and is conditioned on the finding's
own state (`ActualValue -eq 'Missing'` or `Status -eq 'Fail'`). Named `MissingAuditRule`, not
`MissingAcl`: these are SACL audit rules, not DACL access rules, per Joel's ruling.

## D-C. Root cause 2 is NOT a producer-vocabulary problem — the reader is type-blind

**This overrules the diagnosis in the brief, and it makes the fix far smaller than feared.**

The brief attributed `Drift: 0` to four hard-coded key names missing a producer's spelling. That is
a real latent risk but it is **not** what Joel saw. The producers all publish `Drift`, `Missing` and
`Mismatched` correctly — AST-verified across all eight.

The actual defect: every standalone section builds `Summary = @{ ... }` — a **hashtable** — and the
section counter read it through `Get-SafePropertyValue`, which walks a dotted path using
`$current.PSObject.Properties.Name -contains $part`. A hashtable's `PSObject.Properties` are
`IsReadOnly, IsFixedSize, IsSynchronized, Keys, Values, SyncRoot, Count` — **never its keys.** The
walk fell out at the first segment and returned 0. Proven empirically under `Set-StrictMode -Version Latest`:

```
Summary is hashtable: True
PSObject prop names on Summary: IsReadOnly,IsFixedSize,IsSynchronized,Keys,Values,SyncRoot,Count
Get-SafePropertyValue Summary.Drift  = 0      <-- the bug
direct $r.Summary.Drift              = 2
```

`Checked:` was correct on the same line only because it used an explicit
`if ($result.Summary -is [hashtable])` branch. **The section counter and the grand total already
disagreed** — the grand total used the hashtable-aware `Test-SummaryKey`/`Get-SummaryCount` helpers
and was RIGHT; the section line was WRONG. No producer needed touching.

**Consequence: no producer resisted a shared vocabulary, because no producer needed to change.**
The "eight producers with no shared vocabulary" framing was the wrong model of this bug.

## D-D. Unification is one shared computation, not a key-name patch

Per Joel's ruling that this be fixed properly, the per-entity computation is extracted into two
functions — `Get-EntityDriftTotals` and `Get-EntityErrorTotal` — and **both the grand-total loop and
the section counter now call them.** They can no longer disagree, because there is only one of them.
This is the design Joel asked for, applied at the consumer where the defect actually lives.

## D-E. Error counting: `Max` of three sources, not `Max(a,b) + c`

Fixing D-C made a latent double-count **visible**: a failed audit rendered `Errors: 2` above a
single error line, because `Summary.Errors`, the top-level `Errors` collection and `Error`-typed
findings are three representations of one failure, and the code took `Max(a,b) + c`.

AST-verified: every standalone producer increments its error counter on the same line that appends
the Error finding, and OU/Group/User publish `DriftFindings` rather than `Findings` so the third
source is simply absent for them. `Max` of all three cannot double-count and cannot under-count
(`Test-TierModelAdmx` publishes `Errors = 0` alongside real Error findings and is still counted).

**This was mandatory, not scope creep:** shipping D-C without it would have regressed the section
error count from a correct 1 to an incorrect 2 — Trap A's shape.

## D-F. WinLaps Decryptor `Error` → `Missing`, scoped to ONE branch (overrules the brief)

**A blanket `Error`→`Missing` relabel would be seriously wrong and I did not do it.**

`Test-TierModelWinLapsDecryptor` emits six `Status='Error'` sites. Five are genuine
could-not-determine states: ambiguous multi-GPO match, `Get-GPO` throwing, group resolution failing,
domain resolution failing, and the outer catch. Relabelling those would report an **unreachable DC
as a clean-but-missing estate** — strictly worse than the `Drift: 0` bug this whole exercise exists
to kill, and it would suppress `COMPLIANCE COULD NOT BE FULLY DETERMINED`.

Only `L154` was changed: `Get-GPO -All` **succeeded** and the filter matched nothing. The GPO is
absent. That is a determinate finding, identical in kind to Auth Policy's `Missing`.

Because `$drift = $missingCount + $mismatchCount + $errorCount`, moving the row between counters
leaves Drift unchanged; only the Errors count and the label change — exactly the intent. The counter
follows automatically, so Trap A is satisfied.

---

## Before / after, every site Joel listed

Reproduced from his lab output through the real lifted functions:

| Section | Before | After |
|---|---|---|
| WinLaps ACL | `Drift: 0` · `[MissingAcl]` yellow | `Drift: 1` · `[MissingAcl]` **red** |
| MSA ACL | `Drift: 0` · `[MissingAcl]` yellow | `Drift: 2` · `[MissingAcl]` **red** |
| gMSA ACL | `Drift: 0` · `[Error]` yellow | `Errors: 1` · `[Error]` **red** |
| dMSA ACL | `Drift: 0` · `[MissingAcl]` yellow | `Drift: n` · `[MissingAcl]` **red** |
| WinLaps Decryptor | `Drift: 0` · `[Error]` | `Drift: 6` · `[Missing]` **red** |
| Domain Audit Rule | `Drift: 0` · `[AuditRight]` yellow | `Drift: 1` · `[MissingAuditRule]` **red** |
| Auth Policies | `Drift: 0` · `[Missing]` red | `Drift: 4` · `[Missing]` red |

**Reconciliation (the BUG-041 rule): `sum(section Drift) == grandTotalDrift` = 14/14 MATCH.
`sum(section Errors) == grandTotalErrors` = 1/1 MATCH.** They agree because they are now literally
the same code.

Note the Domain Audit Rule prints **10** finding lines against `Drift: 1`. That is correct, not a
new disagreement: the nine `[MissingAuditRule]` rows are the per-right breakdown of the single
missing rule, and the producer counts the rule once. The section counter counts *rules*, the list
itemises *rights*.

---

## Provenance — pre-existing, NOT introduced by this release

`git log -S` on `Audit-TierModel.ps1`:

* Colour rule → **`f8270cd` "Initial codebase for Active Directory Tier Model v1.0.0 (#3)"**
* `Get-SafePropertyValue $result 'Summary.Drift'` → **`f8270cd`**, same commit.
* `-IncludeMsa` family → `c2eb0b8` (MSA/gMSA/dMSA), `-IncludeWinLaps` → `e885eeb`.

**Joel's instinct was right about the trigger and wrong about the location.** Neither defect is new,
and neither came from the v2.1.0 diagnostics work (`23b5100`). Both were written when the only
producers were OU/Group/User, whose Types genuinely were `Missing`/`Mismatch` and whose Summaries
are reached differently. The later `-Include*` producers walked into a renderer and a reader that
pre-dated them. Latent since v1.0.0, exposed by the new flags.

---

## Blocked: one Wolverine-owned test encodes the old Step 3 behaviour

**`tests\Unit.WinLapsAclOperations.Tests.ps1:1210` — "GPO not found: Error status in findings,
Errors > 0"**, asserting at **:1217** `$result.Errors | Should -BeGreaterThan 0`, and at :1218 that
a finding with `Status -eq 'Error'` exists.

**Verdict: it encodes the old behaviour. It did NOT catch a regression.** It pins exactly the
mapping Joel ruled against. Not edited, and the fix was not bent to satisfy it. Wolverine owns it.

Attribution proven by reverting only Step 3 and re-running: **Unit 1608/1608/0.** The failure is
100% Step 3 and nothing else moved.

**Joel's options:** (a) have Wolverine invert the test to assert `Status='Missing'` and
`Missing > 0` while adding a sibling that pins the ambiguous/throw branches as still `Error`
— recommended; or (b) revert the single `Test-TierModelWinLapsDecryptor.ps1` hunk for a fully green
tree and land Step 3 with the test change together.

---

## Found, deliberately NOT fixed

`Audit-TierModel.ps1` `Invoke-OuAclAudit`:
`Type = if ($_.Type -eq 'Missing' -or $_.Type -eq 'Mismatch') { $_.Type } else { 'Error' }`
— the same exact-name defect shape. `Test-TierModelOuAcl` emits a `Type='Warning'` finding
(`:78`), which this relabels to `Error`, rendering it red as an error it is not. Label-only (the
error counter reads raw `Findings`), OU ACL is not in Joel's six, and there is no lab evidence.
**Surfaced rather than forced.** Joel's call.

---

## Discrepancies in the brief, for the record

1. **HEAD is `6725ab3`, not `04ab664`, and the tree was NOT "nothing committed".** Two commits landed
   after `04ab664`: `23b5100` (v2.1.0 verbose/debug diagnostics) and `6725ab3` (.squad records), both
   at 12:27–12:28 today. Provenance was checked against the real HEAD.
2. **`.squad/agents/beast/history.md` became modified during this session** — not by me. The tree was
   clean when I started. Beast appears to be working concurrently. Left untouched.

## Hygiene

Repo root **13 files, zero strays**. `Audit-TierModel.ps1` and `Deploy-TierModel.ps1` still
`EF BB BF`; `TierModel.psm1` still has no BOM; `Test-TierModelWinLapsDecryptor.ps1` still has no BOM.
0 parse errors on both edited files. Scratch lives outside the repo.

**`BUG-nnn` count: 1** — `modules\TierModel\TierModel.psd1:102`, unchanged, pending Joel's ruling.
*Enumeration rule: 2 root `*-TierModel.ps1` + all files under `modules\` + all files under
`optional\` = **86 files**.*
