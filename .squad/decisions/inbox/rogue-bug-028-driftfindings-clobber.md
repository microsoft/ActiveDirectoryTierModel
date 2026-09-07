# BUG-028 — `$driftFindings` clobbered inside the per-entity loop

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05T13:34:26+08:00
- **Requested by:** Joel Platek
- **Branch:** `feature/enable-verbose-debug` — HEAD `04ab664`, nothing committed, nothing staged
- **Files changed:** `Audit-TierModel.ps1` **only**
- **Status:** Implemented and verified. Two items escalated for decision.

---

## 1. The defect as reported, and as found

Joel's report was correct in mechanism and **understated in severity**.

`$driftFindings = @()` sat *inside* `foreach ($result in $auditResults)`, immediately after the
per-entity `Write-Host "${entityType}:"`. Every iteration reset it. Three consumers read it after
the loop:

| Consumer | What it renders |
|---|---|
| Text report — FINDINGS section | the itemised drift list |
| Json report — `driftFindings` | the machine-readable drift list |
| Html report — `Findings: N` | the headline count |

Joel expected the report to contain **the last entity type's** findings. In practice it is worse
than that: the last entity type on the consolidated path is **ADMX**, and in the common case ADMX
has no drift. So the report does not merely under-report — it renders

```
No drift detected - configuration matches AD state
```

for a run whose console printed every finding. My pre-fix control measured the Json
`driftFindings` array at **0 elements** against 5 findings on the console. Not "only the last
entity type": **nothing at all**, unless the final phase happened to drift.

This is the same signature as BUG-027: console right, persisted artifact wrong, no error raised,
exit code unchanged.

### Confirmation of Joel's field anecdote

Joel removed groups from the DENY URA to exercise drift detection and read the result off the
console. Groups is not the last entity type, so the report he would have sent to Microsoft would
have contained **no findings section at all**. The anecdote is not a near miss; it is a hit.

---

## 2. Fix — accumulation (task 1)

The per-entity list and the report list are now two different variables.

- `$consolidatedDriftFindings = @()` declared **before** the loop (L1641).
- The in-loop list renamed to `$entityDriftFindings` (L1754). The console block reads it, so the
  per-entity display is byte-for-byte unchanged.
- `$consolidatedDriftFindings += $entityDriftFindings` inside the loop (L1772).
- `$driftFindings = $consolidatedDriftFindings` after the loop (L1792), alongside the BUG-027
  total assignments.

**The five single-entity branches are untouched.** They assign `$driftFindings` with `=` from
their own single result and were always correct. Verified by search after editing — L1824
(`$ouResult`), L1861 (`$groupResult`), L1876 (`$userResult`), L1892 (`$ouAclResult`), L1923
(`$gpoResult`) are unchanged. Only one scope branch can ever run (`$activeScopeCount -gt 1` is
rejected at parameter validation), so there is no interaction between them and the new
accumulator.

---

## 3. Fix — `$driftCount -gt 0` (task 2)

Joel's hypothesis was that `Get-SafePropertyValue $result 'DriftFindings'` returns a *collection*
and that `$collection -gt 0` is a filtering comparison. **I tested it rather than reasoned about
it, and the hypothesis is wrong — but a real defect is present anyway.**

`Get-SafePropertyValue` explicitly returns `$current.Count` for `[array]` and
`[System.Collections.ICollection]`, so `$driftCount` genuinely is an integer. Empirical results
across three shapes:

| `DriftFindings` shape | outer guard | helper returns | `-gt 0` | outcome |
|---|---|---|---|---|
| array of 2 | True | `2` | True | kept |
| array of 1 | True | `1` | True | kept |
| **bare single object (not array-wrapped)** | **True** | **0** | **False** | **SILENTLY DROPPED** |

A value that is neither an array nor an `ICollection` falls through to `try { [int]$current }
catch { return 0 }`. Casting a `PSCustomObject` to `[int]` throws, so the helper returns `0`, the
`-gt 0` test fails, and a finding that passed the outer truthiness guard is discarded.

The secondary test was also **redundant** — `if (... -and $result.DriftFindings)` already
establishes non-emptiness.

**Fix applied:** the secondary test is deleted and the append is array-wrapped:

```powershell
$entityDriftFindings += @($result.DriftFindings)
```

`@()` normalises the scalar case so `.Count` is meaningful downstream. The `$driftFromFindings`
append is wrapped identically.

**Is the bare-object shape reachable today?** No, in shipped module code. `Test-TierModelOu`,
`Test-TierModelGroup`, `Test-TierModelUser` and `TierModel.psm1:654` all build `$driftFindings =
@()` then `+=`, which yields `[object[]]` even for one element. I also chased down
`Test-TierModelUser.ps1:275`, `DriftFindings = $driftFindings.Count` — an **integer** under a
`DriftFindings` key, which would have been a live instance. It is confined to the
`Write-TierModelLog -Data` payload; the returned result object is built at L277–283 with
`DriftFindings = $driftFindings`. **Harmless.** So this was a latent robustness hole, not an
active data-loss bug — but it is one line of code away from becoming one, and a regression test
now covers it.

---

## 4. Fix — console vs log `Total Errors` (task 3), **scope narrowed, please read**

The divergence is real. `$auditSummary.ErrorCount++` at L1226 counts a phase that **threw** (the
canonical-ACL catch, NON-BLOCKING-5). A phase that threw never lands in `$auditResults`, so
`$totalErrors` — accumulated from results — structurally cannot see it. Console said `0`, log said
`1`.

**I first implemented the obvious fix and it was too wide.** Folding `$auditSummary.ErrorCount`
into `$totalErrors` before the verdict also feeds TRUE-FINAL-2 and the compliance guard, which is
arguably *more* correct — but it changed the headline verdict and broke **three Integration
tests**, taking the suite from 318/0 to **315/3**:

- `Full Deployment Audit.Full Audit Orchestration.Should calculate compliance percentage correctly`
- `Compliance Reporting.Compliance Status Display.Should show COMPLIANT status when no drift detected`
- `Compliance Reporting.Compliance Status Display.Should show drift count when drift detected`

Cause: those three mock the six entity functions but **not** `Invoke-CanonicalAclAudit`, which
therefore throws against the test's unreachable DC and sets `ErrorCount = 1`. Under the wide fix
the verdict became `COMPLIANCE COULD NOT BE FULLY DETERMINED` and compliance became `N/A`.

I am not permitted to touch `tests\`, and Joel scoped task 3 as a "small, contained change" to the
**console line**. So I narrowed it: the console renders a separate `$displayErrors` (L1611, L1627)
and `$totalErrors` is left alone, so the verdict and compliance behave exactly as before. The log
keeps `$auditSummary.ErrorCount += $totalErrors`, which yields the same combined number.
**Console and log now agree**, baseline restored to 318/0.

### ESCALATION 1 — should a thrown phase block a green verdict?

The narrow fix leaves a run that can print `Overall Audit Status: ✅ COMPLIANT` alongside
`Total Errors: 1`. That is internally inconsistent, and the NON-BLOCKING-5 comment in the code
states the opposite intent outright: *"A phase that did not run is not a phase that passed."*

I believe the wide fix is the correct product behaviour and that the three Integration tests are
asserting the old, wrong behaviour. But that is a call for Joel and Wolverine, not for me in a
pass scoped to `Audit-TierModel.ps1`. **The cost is exactly three tests, named above.** Say the
word and I will implement the wide version; Wolverine updates those three.

---

## 5. `$driftFindings = @()` at L646 (task 4) — **load-bearing, proved, not deleted**

Proved empirically rather than argued. I copied the script to the repo root, replaced L646 with a
comment, and ran `-AdmxOnly` through a mocked harness:

```
THREW: The variable '$driftFindings' cannot be retrieved because it has not been set.
```

Under `Set-StrictMode -Version Latest` the report generator dies without it. **Retained.** The
control copy was deleted immediately.

---

## 6. ⚠️ FOURTH INSTANCE OF THE PATTERN — reported, not fixed

Joel asked to be told immediately if a fourth console-right/artifact-wrong instance appeared. It
did, and it fell out of the L646 proof above.

**`$driftFindings` is never assigned on the `-AdmxOnly` path, nor on the standalone `-Include*`
path.** Both keep the L646 empty initialiser all the way to report generation. Measured on the
real, fully-patched script with an ADMX mock carrying 4 drift findings:

```
Total Checked: 15
No drift detected - configuration matches AD state
```

The console printed the drift. The report denies it exists. Same failure mode as BUG-028, two
more scopes, still live after this pass. This is the reason L646 is load-bearing — it is masking
the omission rather than serving a legitimate empty case.

**Not fixed in this pass** — per instruction, reported first. It is a small fix (assign
`$driftFindings` from the ADMX/standalone results the way the other five branches do) and I can
do it on Joel's word.

---

## 7. Verification

### Control experiment (the point of the exercise)

A single-entity fixture passes while broken, so the fixture carries drift in **two** entity types
(OU ×2, Group ×1) with a **clean final entity type** (ADMX), which is the realistic shape.

Pre-fix control: my own fix stripped by regex from a **repo-root** copy (it must live in the repo
root or `$PSScriptRoot` fails to find `Modules\` and the control fails for the wrong reason).

| Assertion | Pre-fix control | Post-fix |
|---|---|---|
| Console shows OU + Group markers | pass | pass |
| Text report has no `No drift detected` | **FAIL** | pass |
| Text report has all 3 markers across 2 entity types | **FAIL** | pass |
| Json `driftFindings.Count` = 3 | **FAIL — got 0** | pass |
| Html `Findings: 3` | **FAIL** | pass |
| Bare un-wrapped finding survives | **FAIL** | pass |
| Console `Total Errors: 1` = log `"ErrorCount":1` | n/a | pass |

Harness total **9/9** post-fix (5 BUG-027 regression + 4 BUG-028). Control copy deleted.
Harness kept out of the repo, in the session workspace.

### Suites — run by path, never by tag

| Suite | Result | Baseline | Delta |
|---|---|---|---|
| Unit | **1573 passed / 0 failed** | 1573 / 0 | none |
| Integration | **318 passed / 0 failed** | 318 / 0 | none |

Parse errors: **0**. HEAD still `04ab664`, nothing staged, no stray files in the working tree.

---

## 8. Scope compliance

`Audit-TierModel.ps1` is the only file changed. `tests\`, `.research\lab-validation\`,
`Test-TierModelPrerequisites.ps1`, `TierModel.psm1` and `Deploy-TierModel.ps1` untouched. No
commits. No PowerShell 5.1 accommodation. No `[System.IO.Path]::GetFullPath()`. No `-Debug`
forwarded to any AD or GroupPolicy cmdlet.

## 9. Open decisions for Joel

1. **Verdict on a thrown phase** — narrow (current, 318/0) or wide (correct, costs 3 named tests).
2. **Fourth instance** — `-AdmxOnly` and standalone `-Include*` reports always read
   "No drift detected". Fix now or schedule.
