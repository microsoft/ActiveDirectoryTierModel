# BUG-030 — `-AdmxOnly` and standalone `-Include*` reports always said "No drift detected"

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05T13:42:57+08:00
- **Requested by:** Joel Platek (fixing the fourth instance I reported under BUG-028)
- **Branch:** `feature/enable-verbose-debug` — HEAD `04ab664`, nothing committed, nothing staged
- **Files changed:** `Audit-TierModel.ps1` **only**
- **Status:** Implemented and verified. **A fifth defect found — reported, not fixed.**

---

## 1. The defect

`$driftFindings` was never assigned on the `-AdmxOnly` path, nor anywhere on the standalone
`-Include*` path. Both kept the empty initialiser at L646 all the way to report generation, so
every report on those two scopes read:

```
No drift detected - configuration matches AD state
```

regardless of what the console had just printed. Measured on the patched script with an ADMX
result carrying 4 findings: console `Total Drift: 4`, report `No drift detected`.

The fourth instance of the console-right/artifact-wrong pattern in this file.

---

## 2. Why it was left unwired in the first place — the reason matters

This was not a simple omission. The audit functions **do not agree on a finding shape**, and the
report interpolates `$_.Type`, `$_.ResourceType`, `$_.Identifier` and `$_.Details`:

| Source | Shape |
|---|---|
| OU / Group / User | `Type, ResourceType, Identifier, Details` — matches the report |
| `Test-TierModelAdmx` | `Type, ResourceType, **FileName**, **Message**` |
| standalone ACL audits | `Type, ResourceType, Identifier, **Property, ExpectedValue, ActualValue**` — **no `Details` at all** |

Under `Set-StrictMode -Version Latest`, handing the report a raw ADMX or standalone finding
**throws** on the missing property. So simply assigning `$driftFindings = $admxAudit.Findings`
would have swapped a silently-wrong report for a crashing one.

The standalone audits also emit `Type = 'Compliant'` findings, which are explicitly *not* drift
and must not appear in a drift report.

**Fix:** a single normaliser, `ConvertTo-TierModelDriftFinding`, that maps any finding onto the
shape the report renders — `Identifier` from `Identifier`/`FileName`/`GpoName`/`Name`, `Details`
from `Details`/`Message`/`Reason`, or synthesised from the `Property`/`Expected`/`Actual` triple
when no prose exists — and drops `Compliant` entries. Every property access is probed against
`PSObject.Properties.Name` first, so it is StrictMode-safe by construction.

Wired in at three places: the `-AdmxOnly` branch, a new `$standaloneFindings` accumulator fed by
**all 8** standalone sub-audits (MSA, gMSA, dMSA, WinLAPS ACL, WinLAPS decryptor, audit rule, auth
policies, auth silos), and the publish point next to the existing BUG-027 totals.

**The five single-entity `=` branches are untouched**, as required, and L646 is retained — it is
load-bearing, as proved under BUG-028.

---

## 3. ⚠️ FIFTH DEFECT FOUND — reporting immediately, not folding it in

While confirming the shape mismatch I checked the other branches for the same problem and found
one. Joel asked to be told at once.

**`-GposOnly` builds drift findings with no `ResourceType` property**, and the report interpolates
it. Determined empirically with the exact shape and the exact expression:

```
GPO-SHAPE   THREW -> The property 'ResourceType' cannot be found on this object.
OUACL-SHAPE OK    -> [Missing] ACL/X: Y
```

**This is a different and in one sense better failure mode than BUG-028/030** — it is *loud*. A
`-GposOnly` audit that finds any drift throws at report generation, so the operator gets no report
rather than a wrong one. But the outcome is still a lost artifact on a drifted domain, and a clean
`-GposOnly` run cannot reveal it because the branch only builds findings when there are findings.

The one-line fix is to add `ResourceType = 'GPO'` to that projection. **Not done** — outside the
scope Joel set for this pass, and he asked to know the true extent before returning to the lab.

**Running count of the console-right/artifact-wrong family in `Audit-TierModel.ps1`:**
BUG-027 (totals), BUG-028 (findings clobber), BUG-030 `-AdmxOnly`, BUG-030 standalone `-Include*`,
and now `-GposOnly`. The common root is that **each scope branch is responsible for populating the
shared reporting variables by hand, and nothing verifies that it did.**

---

## 4. Verification

### Control experiment

The two publish lines were stripped from a **repo-root** copy (confirmed to parse cleanly first).

| Assertion | Pre-fix control | Post-fix |
|---|---|---|
| ADMX: report is not "No drift detected" | **FAIL** | pass |
| ADMX: report contains all four markers | **FAIL** | pass |
| ADMX: Json `driftFindings.Count` = 4 | **FAIL — got 0** | pass |
| ADMX: Html `Findings: 4` | **FAIL** | pass |
| ADMX: a **clean** run still says "No drift detected" | pass | pass |
| Standalone: report lists both markers | **FAIL** | pass |
| Standalone: `Compliant` entry excluded | **FAIL** | pass |
| Standalone: Details synthesised from the triple | **FAIL** | pass |

The clean-run assertion passes in **both** columns deliberately — it is the guard against
over-fixing, and proves the change did not simply force findings to appear.

Control copy deleted immediately. Harness kept out of the repo, in the session workspace.

### Suites — by path, never by tag

| Suite | Result | Baseline | Delta |
|---|---|---|---|
| Unit | **1573 passed / 0 failed** | 1573 / 0 | none |
| Integration | **318 passed / 0 failed** | 318 / 0 | none |

Parse errors 0. HEAD `04ab664`, nothing staged, no stray files.

---

## 5. Scope compliance

`Audit-TierModel.ps1` only. `tests\`, `.research\lab-validation\`,
`Test-TierModelPrerequisites.ps1`, `TierModel.psm1` and `Deploy-TierModel.ps1` untouched for this
item. No commits. `Set-StrictMode -Version Latest` respected throughout — the normaliser exists
precisely because of it. No PowerShell 5.1 accommodation.

## 6. Open decision

**`-GposOnly` missing `ResourceType`** — one line, but it is a fifth instance and Joel wanted the
extent before deciding.
