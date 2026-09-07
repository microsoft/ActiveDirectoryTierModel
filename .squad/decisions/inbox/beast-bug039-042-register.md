# Decisions — bug register update for BUG-039 … BUG-043

**Author:** Beast · **Date:** 2026-09-05 · **Branch:** `feature/enable-verbose-debug`
**Scope of change:** `.research\known-bugs.md` only. Nothing staged, nothing committed.
`CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\` touched.

## D1 — BUG-039/040/041 recorded as FIXED; register now reads 2 open, 41 of 43 IDs closed

All three were verified in the working tree before recording, not taken on report:

- BUG-039 — `Audit-TierModel.ps1:2493` now ends `-join [Environment]::NewLine`. Confirmed.
- BUG-040 — five `Identifier` sites in `Test-TierModelOuAcl.ps1` switched from `$acl.targetOUPath`
  to the resolved `$targetOUPath` (confirmed by diff: exactly five `-`/`+` pairs).
- BUG-041 — the global `$totalDrift = $totalMissing + $totalMismatched` override is **deleted**
  (present at `04ab664:1128`, absent now, tombstoned in a comment). `Test-SummaryKey` and
  `Get-SummaryCount` added as pure additions at `:1654`/`:1660`; no `Get-SafePropertyValue` call
  site changed.

All three are **pre-existing**, verified by reading `04ab664`, not by recollection. None was caused
by the `-EnableVerbose`/`-EnableDebug` work.

## D2 — BUG-041's re-classification is recorded as the headline, not the fix

Rogue's correction is recorded as authoritative over the original "instance eight of the
hand-populated-reporting-variable family" framing. Three consequences are written into the register:

1. Console and artifact render the **same** variables, so both were wrong **and agreed**. The
   screen-versus-file comparison that caught the previous seven would have passed this clean.
2. It is **not** in a scope-branch publish step, so the **spec 007 publish guard would not catch
   it**. Storm/whoever owns 007 should not count BUG-041 as covered scope.
3. Severity is above BUG-039/040: `$auditSummary.DriftCount` feeds the NUnit `failures=` attribute
   at `Audit-TierModel.ps1:2513`. It **under-reports** (a compliant estate still reports 0, guarded)
   but it is CI-consequential.

## D3 — NEW WORKING RULE 14, and it is genuinely new

"Two outputs agreeing proves only that they share a source." Existing rule 1 ("verify against the
artifact, not the console") detects a *disagreement* between two renderings and is structurally
incapable of detecting a shared-source error. Rule 14 adds an **intra-artifact reconciliation**
check: does the summary header reconcile against the body printed beneath it? Rules 15–17 added
alongside (self-contradicting finding object localises to the producer; a moved test count is
evidence against the diagnosis; record deliberate non-changes).

## D4 — NEW OPEN DEFECT: BUG-043, found while verifying BUG-042

`-OuAclsOnly` (`:2097-2100`), `-GposOnly` (`:2136-2139`) and the standalone `-Include*` path
(`:2406-2407`) publish `$auditSummary.DriftCount` and **never** `MissingCount`/`MismatchCount`, so
the saved report renders `Drift Findings: 8 / - Missing: 0 / - Mismatch: 0` over a body of 8
findings. Pre-existing (same shape at `04ab664:1359-1391`). `-OuOnly`/`-GroupOnly`/`-UserOnly`
publish all four correctly; `-AdmxOnly` sets `MismatchCount = Drift`, which is at least
self-consistent.

**This is the "instance eight" that BUG-041 was mistaken for** — same symptom class, and unlike
BUG-041 it **is** in a scope-branch publish step, so it is squarely in spec 007's target set.
Severity Medium: `DriftCount` itself is correct, so CI and the NUnit `failures=` attribute are
unaffected; the damage is that the artifact contradicts itself and is unusable as evidence.
Left unfixed — product code is out of scope for a register update.

**Consequence: next free ID is 044, not 043.**

## D5 — Cancelled deploy exits 0: recorded as BY DESIGN, no bug number

`Deploy-TierModel.ps1:818` and `:840`, both `Read-Host … -ne 'Y'` → `exit 0`. Both verified.
Joel ruled it intended (the deploy script is never run non-interactively). Recorded in a new
**"By design — do not re-file"** section with his rationale verbatim, plus the trigger: Cyclops's
wrapper answered `YES` where the gate demands exactly `Y`, so it cancelled and then reported
success from the exit code. The lesson is recorded against the **wrapper**, not the script.
The ruling carries an explicit expiry: if a `-Force`/`-NonInteractive` path is ever added, revisit.

## D6 — The "Next free ID" line no longer matches `BUG-\d{3}`

It now reads **"Next free ID: 044"** with no prefix, plus a note explaining why and instructing
future editors not to restore it. This was the cause of the coordinator's false "17 pending
CHANGELOG migrations" against a true 16. A `BUG-\d{3}` census of the file now returns exactly the
43 real IDs. Pending-migration count is now **19** (BUG-019, BUG-024…BUG-038, BUG-039…BUG-041) —
still a separate task, still not mine.

## D7 — BUG-042 severity read for Joel: scope flags change the narrative, not the verdict

Filed as OPEN, **Low**. Verified: drift total, compliance %, NUnit `failures=` and exit code are
**identical** under `-OuAclsOnly` and `-FullDeployment` (both resolve to `Missing + Mismatched`,
because `Test-TierModelOuAcl` publishes no `Drift` key and BUG-041's per-result derive branch
handles it). What differs is the report body: `Type` reads `Missing`/`Mismatch` under `-OuAclsOnly`
and `Drift` under `-FullDeployment`, and — the sharper edge — `Error` findings such as an
**unreadable OU ACL**, plus the missing-`aclDelegations` `Warning`, appear in the `-OuAclsOnly`
body but are filtered out of the `-FullDeployment` body (which keeps only `Type -eq 'Drift'`).
They still reach `ErrorCount`, so they are not invisible, but they are not itemised.
Recommended fix direction: move the derivation into the producer, or teach the consolidator the
same mapping. **Do not** simply widen the consolidator's filter — that changes behaviour for all
eight producers.

## D8 — Not filed, recorded for triage only

`Test-TierModelOuAcl.ps1:165` — the identity-check catch does `continue` with no finding and no
counter increment, so an ACL that could not be verified silently leaves the body. It lowers
compliance % (it counts in `$totalAcls` but never as compliant), so it does not fake green. It
belongs to the existing 102-site lossy-catch triage population, not to a new bug number.
