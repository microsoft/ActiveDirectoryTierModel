# Tasks: Diagnostic Logging Switches (`-EnableVerbose` / `-EnableDebug`)

**Feature Branch**: `feature/enable-verbose-debug`
**Spec**: `specs/006-verbose-debug-logging/spec.md`
**Plan**: `specs/006-verbose-debug-logging/plan.md`
**Generated**: 2026-09-05 (retroactive)

---

## ⚠️ Status Honesty Note

This file was written **after** the implementation, so completed items are ticked from evidence read out of
the working tree on 2026-09-05, not from memory. Anything that could not be confirmed on disk is left
unticked, even where a conversation suggested otherwise.

**Sequencing deviation from Constitution II, accepted by Joel:** Pester tests for this feature are written
**after** lab validation, not before, because the behaviour to be asserted is the behaviour the lab measures.

**Current stopping line (updated 2026-09-08):** Suite measured green at **1,994 automated tests / 1,994 passing / 0 failed** after the T018 guard appeared, with **87.36%** coverage over the CI-scoped 82-file module population measured in the preceding full coverage run. T015 lab gate **passed** on 2026-09-05 (RUN 1, 50 rows, 0 FAIL), and Joel explicitly authorised treating lab-dependent acceptance as satisfied on 2026-09-08. **T017 is deferred to v2.1.1 by Joel's explicit ruling.** No verified-open v2.1.0 tasks remain; the only incomplete items are deferred.

---

## Phase 1: Design & POC — ✅ COMPLETE

- [x] T001 Lock design decisions D1–D8 with Joel: switch names (`-EnableVerbose` / `-EnableDebug`, chosen so
      the common parameters `-Verbose` / `-Debug` stay free), the `Debug\` subfolder, no retention, script +
      module scope preferences, the both-switches transcript gate, and the auto-enable-and-announce rule.
  - **Files**: `.research/verbose-vs-debug-design.md`, `.research/verbose-debug-implementation-plan.md` §0
  - **Satisfies**: D1, D2, D3, D5, D6, D8

- [x] T002 Lab/workstation POC round — the native `-Debug` **preference variable** versus the explicit
      `-Debug` **parameter**, plus preference restoration (POC-1), `-WhatIf` suppression (POC-2), nested
      transcripts (POC-3), `Debug\` path resolution (POC-6), `-Verbose:$false` sufficiency (POC-8), scoped
      preferences (POC-9) and transcript survival on Ctrl-C (POC-10).
  - **Files**: `.research/verbose-vs-debug-poc/`, `.research/debug-switch-poc/`
  - **Satisfies**: FR-010, FR-011, FR-013, FR-014, FR-015, FR-016, FR-017; spec findings M-1 … M-9

---

## Phase 2: `Deploy-TierModel.ps1` — ✅ COMPLETE

- [x] T003 Declare `-EnableVerbose` and `-EnableDebug` as a distinct `# --- Diagnostics ---` group after the
      existing logging trio.
  - **Files**: `Deploy-TierModel.ps1` (L239, L242)
  - **Satisfies**: FR-001, FR-002

- [x] T004 Diagnostics resolution: `$script:DiagnosticsEnabled`, D8 auto-enable of `-Logging` with the
      `$script:LoggingAutoEnabled` discriminator and the silent-default/no-prompt path, the announcement
      line, single absolutised log base, and `Debug\` folder creation with `-WhatIf:$false` and a `Test-Path`
      confirmation.
  - **Files**: `Deploy-TierModel.ps1` (L286–L310, L361, L370–L388)
  - **Satisfies**: FR-003, FR-004, FR-006, FR-007, FR-012, FR-013

- [x] T005 Raise `VerbosePreference` / `DebugPreference` **after** the module import, at script scope **and**
      module scope via `& $script:TierModelModule { … }`, never at global scope; announce which switches are
      active.
  - **Files**: `Deploy-TierModel.ps1` (L714–L728)
  - **Satisfies**: FR-014, FR-015, FR-016, FR-017

- [x] T006 Start the transcript only when **both** switches are present; `-WhatIf:$false`; confirm with
      `Test-Path` before setting `$script:TranscriptStarted`; print the blunt unredacted warning including
      the Ctrl-C caveat; warn and continue on failure.
  - **Files**: `Deploy-TierModel.ps1` (L743–L765)
  - **Satisfies**: FR-008, FR-009, FR-010, FR-012, FR-013

- [x] T007 Guarded `Stop-Transcript` (never unguarded — POC-3) and the copy-pasteable
      `-EnableVerbose -EnableDebug` re-run hint, suppressed when both switches are already on.
  - **Files**: `Deploy-TierModel.ps1` (L481–L511, L517–L562)
  - **Satisfies**: FR-011, FR-018

- [x] T008 Comment-based help for both switches, stating the auto-logging behaviour, the transcript gate and
      the unredacted warning — with no assertion of a cause for the customer incident.
  - **Files**: `Deploy-TierModel.ps1` (L140–L182)
  - **Satisfies**: FR-006, FR-008, FR-009

---

## Phase 3: `Audit-TierModel.ps1` — ✅ COMPLETE

- [x] T009 Add the `-Logging` switch to Audit (it had none), using Deploy's
      `"$OutputFileBase-MMddyy-HHmm.log"` convention, wired to `Initialize-TierModelLogging` at module scope
      so module-originated entries reach disk. Explicit `-Logging` without `-OutputFileBase` prompts, exactly
      as Deploy does.
  - **Files**: `Audit-TierModel.ps1`
  - **Satisfies**: FR-007, US-3

- [x] T010 Declare both diagnostics switches; diagnostics resolution, D8 auto-enable + announcement, and
      `Debug\` folder creation at parity with Deploy.
  - **Files**: `Audit-TierModel.ps1` (L213, L216, L534–L545, L604, L626–L644)
  - **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-006, FR-007

- [x] T011 Preference assignment after import at script + module scope; transcript start with the same
      `-WhatIf:$false` / `Test-Path` / warning treatment; guarded stop; re-run hint.
  - **Files**: `Audit-TierModel.ps1` (L693–L707, L721–L743, L414–L441, L447–L493)
  - **Satisfies**: FR-008 … FR-018

- [x] T012 Comment-based help for `-Logging`, `-EnableVerbose` and `-EnableDebug`.
  - **Files**: `Audit-TierModel.ps1` (L107–L137)
  - **Satisfies**: FR-006, FR-008, FR-009

---

## Phase 4: Bug Squash — ✅ COMPLETE (per the register)

- [x] T013 Squash the reliability improvements family found while building this feature. **Status and the exact
      fixed/outstanding split live in the register — read it there rather than trusting a count quoted
      anywhere else.**
  - **Files**: `.research/known-bugs.md` (authoritative register)
  - **Satisfies**: Joel's release rule — no release while known bugs remain unsquashed

---

## Phase 5: Test Harness Repair — ✅ COMPLETE

- [x] T014 Repair `tests/helpers/ADStubs.ps1`: give the 76 CI stubs `[CmdletBinding()]` and remove the hand-rolled
      `$ErrorAction` parameter that silently discarded the caller's value. Without this, error-handling tests
      cannot escalate in CI, and any `-Debug` or common parameter reaching a stub fails with
      "parameter not found".
  - **Files**: `tests/helpers/ADStubs.ps1`
  - **Satisfies**: prerequisite for every failure-path test in T017
  - **Evidence, read from the working tree 2026-09-06**: `tests/helpers/ADStubs.ps1` contains **76**
    `[CmdletBinding()]` occurrences and **zero** remaining `$ErrorAction` parameter declarations.

---

## ✅ JOEL'S GATE — LAB VALIDATION (RUN 2026-09-05: 50 ROWS, 0 FAIL)

- [x] T015 Execute the lab validation matrix on `TierLab-DC01`.
      **RUN 1 COMPLETE 2026-09-05 [17:08] — 50 rows, 0 FAIL (29 PASS, 21 PASS\*).** The headline assertion
      about a critical reliability improvement flipped 0/3 → 3/3. End state: 24 Tier OUs, 28 groups, 4 auth policies, 4 silos, 148 GPOs.
      Lab runs confirm the feature is lab-proven across `-OuOnly` / `-GroupOnly` / `-FullDeployment`, and
      `-FullDeployment` with every `-Include*` / `-Enable*`, on **both** entry scripts.
  - **Matrix**: `.research/verbose-debug-implementation-plan.md` §WI-19, plus the extended failure-path and
    apply-path rows in `.research/test-plan-verbose-debug-v2.md`
  - **Evidence**: `.research/lab-validation/LAB-RUN-PROGRESS.md` [16:36]–[17:08]. Note the file's own
    honesty: no raw run artefacts are retained under `.research/lab-validation/results/`.
  - **Satisfies**: FR-019, FR-020, and evidence for every FR above

  > ⚠️ **RE-VALIDATION CAVEAT — the report path has changed since this run.** Six reporting accuracy improvements
  > were fixed *after* RUN 1. The audit report path RUN 1 exercised is **not** the
  > code that exists today, and the changed path has **not** been lab-validated. This does not invalidate the
  > diagnostics-switch result — the switch machinery is upstream of reporting and was not touched — but a
  > confirmatory lab pass over the audit reporting path is outstanding. Tracked as **T027**.
  >
  > **RUN 2 (drift rows) did not produce a product verdict.** All six drifted rows failed with
  > *"fixture NOT staged"*; the root cause is a defect in the harness fixture (rename is refused by the
  > directory for `msDS-AuthNPolicy` / `msDS-AuthNPolicySilo` objects in the Configuration NC), **not** in the
  > product. Drift-path lab coverage therefore remains unproven. See `LAB-RUN-PROGRESS.md` §"RUN 2 / RUN 3".

---

## Phase 6: Post-Lab Work — ✅ COMPLETE (T015 passed; T016/T017 deferred)

- [x] 🟢 T026 Repair the one failing unit test. **Verified 2026-09-08** — suite is green at **1,994 automated tests / 1,994 passing / 0 failed** after the T018 guard appeared, where the 2026-09-06 report showed 1,572 passed / 1 failed. The red-suite blocker no longer exists.
  - **Files**: `tests/Unit.OuAclOperations.Tests.ps1` *(single-owner file; nobody else edits it)*
  - **Note**: under **D14** `tests/` is exempt from the comment-hygiene rule, so the surrounding `BUG-nnn` references in this file stay.
  - **Evidence**: `tests\Unit.OuAclOperations.Tests.ps1:980-1004` now asserts the producer-counted class
    relationally, explicitly rejects the old literal `Type='Drift'`, and reconciles `Mismatch`/`Missing`
    counts. Targeted run: `Unit.OuAclOperations.Tests.ps1` **103/103/0**. Full CI-scoped coverage run:
    **1,988/1,988/0**.
  - **Satisfies**: green suite — a release gate

- [x] 🔵 T027 Confirmatory lab pass over the **audit reporting path** after the reporting accuracy improvements.
      RUN 1 (2026-09-05) validated a report path that has since been changed by six reporting accuracy improvements.
      This is not a re-run of the full 50-row matrix — it is the reporting rows plus the standalone-scope and
      consolidated-report rows that the accuracy improvements touched.
  - **Files**: `.research/lab-validation/` *(harness — not this spec's to edit)*
  - **Basis**: **LAB-CONTINGENT CHECK-OFF.** Joel's 2026-09-08 instruction says to assume the lab passes at
    this point. No product-code file can prove this; the check mark is explicitly conditional on that
    owner-authorised lab assumption.
  - **Blocks**: Joel's confidence in the audit report, not the diagnostics feature itself

- [x] T018 CI static prohibition check: AST-scan `modules/TierModel/public/` and both entry scripts and fail
      the build on any AD/GPO invocation carrying a literal `-Debug`, and on any `@PSBoundParameters` splat
      into an AD/GPO call. **Independently required for v2.1.0** — it is not gated on T016 and T016's
      deferral does not defer it. If T016 is ever revived, T018 must already be in place first.
  - **Files**: `tests/`, `.github/workflows/ci.yml`
  - **Verification 2026-09-08**: `tests\Unit.DebugProhibition.Tests.ps1:1-132` parses
    `modules\TierModel\public`, `Deploy-TierModel.ps1`, and `Audit-TierModel.ps1` with the PowerShell AST,
    anti-vacuity-checks the scan, and asserts zero literal `-Debug` parameters and zero `@PSBoundParameters`
    splats on AD/GPO invocations. Targeted run: **6/6/0**. `.github\workflows\ci.yml:123-139` runs the whole
    `tests` tree, so this guard is CI-enforced once the test file is tracked.
  - **Satisfies**: FR-017

- [x] T019 Coverage review against the 80% gate once T017 lands.
  - **Depends on**: T017, T026
  - **Verification 2026-09-08**: full suite with CI coverage paths
    (`modules/TierModel/*.psm1`, `modules/TierModel/public/*.ps1`, `optional/Update-TierModelMembership.ps1`)
    passed **1,988/1,988/0** and measured **87.36%** command coverage (**14,606 / 16,719**), clearing the
    80% gate. After the tests-only T018 guard appeared, a full no-coverage suite run passed
    **1,994/1,994/0**. The CI gate itself is present in `.github\workflows\ci.yml:136-158`.
  - **Satisfies**: Constitution II

- [x] T020 Refresh the test counts in `README.md` and `docs/test-coverage.md`.
  - **Files**: `README.md`, `docs/test-coverage.md`
  - **Status**: ✅ **COMPLETED 2026-09-07** — counts, file totals, verdict and date all corrected per measured v2.1.0 results.
  - **What was measured**: v2.1.0 green suite, 32 automated `.ps1` files (25 Unit + 7 Integration), 1,980 automated tests (1,650 Unit + 330 Integration), plus 1 manual Excel workbook with 378 manual tests. Total: 33 files, 2,358 tests.
  - **Changes applied**:
    - `README.md:46` updated: "1,891 passing" → "1,980 passing", date "2026-09-02" → "2026-09-07"
    - `README.md:57` updated: "1,891 / 1,891 automated" → "1,980 / 1,980 automated", date "2026-09-02" → "2026-09-07"
    - `README.md:50-53` table rows: Unit (24 → 25 files, 1,573 → 1,650 tests), Integration (7 files unchanged, 318 → 330 tests), Manual (1 file, 378 tests unchanged), Total (32 → 33 files, 2,269 → 2,358 tests). Added "(Pester)" and "(Excel workbook)" labels to clarify automated vs manual distinction.
    - `docs/test-coverage.md:12` updated: date "2026-09-02" → "2026-09-07", count "1,891 total tests" → "1,980 automated tests"
    - `docs/test-coverage.md` Membership section: aggregate "1,783 → 1,891" → "1,783 → 1,980" with note "+89 other new tests in v2.1.0"
  - **About the 2026-09-06 assessment**: The original task analysis ("only verdict and date are stale; numbers are correct") was superseded by suite growth. By 2026-09-07 execution, the counts themselves had grown (1,650+330 vs 1,573+318) and file totals were incorrect (33 vs 32). The file-count error is worth understanding: the old "32 files" figure counted the Excel workbook (`tests\Manual.Integration.Tests.xlsx`, 60.7 KB) as a file, which coincidentally matched the count of `.ps1` containers (24+7). When Unit tests grew to 25 files, the total `.ps1` count became 32, and the coincidence broke — now correctly reported as 33 total (32 automated + 1 manual workbook). This breakdown was independently identified during a GitHub Copilot agent review.
  - **Verification**: All arithmetic asserts pass: 25+7=32, 1,650+330=1,980, 32+1=33, 1,980+378=2,358. Headline and table rows are now consistent.
  - **Sanity check 2026-09-08**: current `README.md:47,58` and `docs\test-coverage.md:12`
    have moved to **1,988** automated tests, but `docs\test-coverage.md:14` still carries a historical
    **1,980** aggregate note. If `tests\Unit.DebugProhibition.Tests.ps1` (T018, currently visible in the
    working tree) is accepted into the release, the published counts need another bump to **1,994** automated
    tests. Not touching docs here; recording the drift so nobody calls stale numbers green.
  - **Depends on**: T026 (suite was green before numbers were published)
  - **Satisfies**: docs accuracy

- [x] T021 `CHANGELOG.md` `[2.1.0]` section — **RE-SCOPED 2026-09-06 by D15.**
      **The planned migration of the 22 pending reliability improvements into `CHANGELOG.md` is
      CANCELLED — not deferred, not reduced. It is not happening.** Per-bug detail goes in the **pull
      request** instead.
      What remains is a **short `[2.1.0]` feature section** covering `-EnableVerbose` / `-EnableDebug`: the
      two switches, the `Debug\` subfolder, auto-enabled `-Logging` with its announcement, the both-switches
      transcript gate and the unredacted-transcript warning. A summary line acknowledging that this release
      also carries a bug-fix sweep is fine; **22 individual entries are not.**
      Pre-existing entries from earlier releases are **untouched** — they are shipped
      history.
      Must not assert a cause for the customer incident.
  - **Files**: `CHANGELOG.md`
  - **Owner**: **Joel or a documentation agent.** Not this feature's implementer, and explicitly not the
    agent that owns `docs/` on this branch — that agent is locked out of `CHANGELOG.md`. A failed v2.0.0 backfill
    (2026-09-03) is the reason the lock exists, and re-scoping the task
    does not lift it.
  - **Verification 2026-09-08**: **COMPLETED after rewrite.** `CHANGELOG.md:10-27`
    is a short 2.1.0 section. In that section, independent measurements found `BUG-\d+` = **0** and
    `filename.ps1:123`-style references = **0**. Required content is present: both switches and the
    preferences they raise (`$VerbosePreference` / `$DebugPreference`), naming rationale (`-Verbose` /
    `-Debug` remain unshadowed), auto-enabled `-Logging` plus on-screen announcement, `Debug\` subfolder,
    transcript only when both switches are supplied and not by either alone, and the unredacted-transcript
    warning. Cause/promise scan found **0** "root cause / reveal why" style claims. Normalised comparison
    confirmed `[Unreleased]` and `[2.0.0]`+ earlier sections are byte-equivalent to HEAD outside line-ending
    normalisation; diff hunks are confined to the old `[2.1.0]` span.
  - **Tests-line judgment**: acceptable, not blocking. "Added regression coverage for diagnostic logging
    behavior" says coverage was added, not that the full T017 diagnostics suite exists. Sharper wording would
    be "Added targeted regression coverage for diagnostics guardrails and the reliability/reporting sweep,"
    but the current line is not a false-green because T017's full transcript/preference coverage debt is
    explicitly deferred in this spec.
  - **Governed by**: **D15**

- [x] T022 `ci.yml` PSScriptAnalyzer scope change.
  - **Files**: `.github/workflows/ci.yml`
  - **Evidence**: `.github\workflows\ci.yml:62-67` now analyses three explicit targets —
    `modules/TierModel`, `Deploy-TierModel.ps1`, and `Audit-TierModel.ps1` — accumulating results per target
    before failing on a non-zero count at `.github\workflows\ci.yml:78-81`.

- [x] T023 Documentation pass — `docs/tiermodel-logging.md` and `docs/quick-deployment-guide.md`: the two
      switches, the composed escalation command, the `Debug\` folder, the absence of retention and why it
      differs from the membership script, the accepted console noise, and — prominently — the unredacted
      transcript warning. **No new file may be created under `docs/` without Joel's approval, because
      `docs/` publishes to GitHub Pages.** Must not assert a cause for the customer incident, and must not
      promise the switches will reveal why a GPO failed.
  - **Files**: `docs/tiermodel-logging.md`, `docs/quick-deployment-guide.md` *(existing files only)*
  - **Verification 2026-09-08**: **NOT COMPLETE.** `docs\tiermodel-logging.md:40-59` and
    `:99-134` cover the switches, `Debug\` folder and unredacted transcript warning, but the same page still
    states Audit "does NOT use the logging system" at `docs\tiermodel-logging.md:17-23` after T009 added
    `-Logging` to Audit. `docs\quick-deployment-guide.md` has **zero** matches for `EnableVerbose`,
    `EnableDebug`, `Debug\`, `unredacted`, `transcript`, or `diagnostic`.
  - **Status update 2026-09-08**: **IN PROGRESS, not deferred.** The
    `docs\quick-deployment-guide.md` repair and the `docs\detailed-deployment-guide.md` appendix
    work have separate owners. Leave unticked until both land and the docs are verified directly.
  - **Re-verification 2026-09-08**: the `docs\quick-deployment-guide.md` update now passes
    the six requested checks: `-EnableVerbose`/`-EnableDebug`, composed escalation command, `Debug\` folder,
    no retention plus contrast with `optional\Update-TierModelMembership.ps1`, accepted console noise, and a
    prominent unredacted-transcript warning. Measured counts in that file: `EnableVerbose` = **3**,
    `EnableDebug` = **3**, `Debug\` = **2**, `transcript` = **4**, `unredact` = **3**, literal `-Debug` =
    **0**. The `docs\detailed-deployment-guide.md:640-697` appendix also covers the same diagnostics
    model and includes an explicit "not a guaranteed root-cause tool" limit. Strict overclaim scan found no
    positive cause assertion or promise that the switches will reveal why a GPO failed. This pass left the
    task unticked because `docs\tiermodel-logging.md` still lacked the retention/membership-script contrast
    and still contradicted T009's added Audit `-Logging`.
  - **Final re-verification 2026-09-08**: **COMPLETED.** The
    `docs\tiermodel-logging.md` blocker is fixed. Measured false-claim count for
    `does NOT/does not use the logging system` is **0**. `docs\tiermodel-logging.md:5` now says `-Logging`
    is supported by both entry scripts; `:16-26` and `:92-94` distinguish Audit reports from Audit logs
    without claiming Audit is outside the logging system. The new `:144-169` retention section states
    Deploy/Audit have **no** log-file retention, contrasts that with
    `optional\Update-TierModelMembership.ps1`, and records the bounded membership retention axes:
    **7 days / 30 files / 200 MB**. Term counts in `tiermodel-logging.md`: `retention` = **3**,
    `7 days` = **2**, `Update-TierModelMembership` = **2**, `30 files` = **2**, `200 MB` = **2**.
    Re-reading `tiermodel-logging.md`, `quick-deployment-guide.md`, and `detailed-deployment-guide.md`
    found no positive cause assertion for the two-GPO incident and no promise that the switches will reveal
    why a GPO failed; the only matched root-cause line is the negative disclaimer at
    `docs\detailed-deployment-guide.md:697`.
  - **Satisfies**: spec "Docs to Update"

- [x] ✅ T024 **Comment hygiene sweep — remove bug numbers and bug history from product code.**
      Per **D13** (Joel, 2026-09-06: *"the only comment should be what this code is doing not that it is or was a bug"*), and applying to **all of Joel's repositories**, not just this one.
      **Status: ✅ COMPLETED 2026-09-07** — Final measurement: **91 product files (`.ps1`, `.psm1`, `.psd1`, excluding `tests\`, `.research\`, `.squad\`) → 0 bug-number references** across the full scope including `Audit-TierModel.ps1`, `modules/`, and `optional/`. This represents a remeasurement across a strictly larger file set than the 2026-09-06 estimate (86 files earlier today with narrower include pattern vs 91 files now with comprehensive scope), yielding the same answer: zero. **Final re-sweep due once the sweep finishes in `Audit-TierModel.ps1`** since a file mid-edit can regress, but measurement as of 2026-09-07T18:30 is zero.
      **The rule "keep the rule, drop the history":** where a comment encodes a live, non-obvious constraint, it survives as a **short present-tense statement of that constraint with no `BUG-nnn` and no story**. Everything purely historical is **deleted outright**, not reworded.
      **`tests/` is EXEMPT — see D14.** Bug-number references under `tests\` remain; in a test the bug number is often the only record of why a specific assertion exists.
  - **Files**: `Audit-TierModel.ps1`, `modules/`, `optional/` and related product scope *(completed)*
  - **Out of scope**: `tests/`, `specs/`, `.research/`, `CHANGELOG.md`, `.squad/`, PR bodies, commit
    messages — all of these are history by purpose; they are not touched by this task.
  - **Evidence**: 91 product files scanned (2026-09-07 18:30), 0 `BUG-\d+` matches. Prior estimate (2026-09-06) of 155 mentions / 36 files superseded by measured result.
  - **Satisfies**: D13, D14

- [x] T025 Release-readiness sweep: version numbers and stray files.
  - **Version — measured 2026-09-06, and it is largely already done:** `modules/TierModel/TierModel.psd1`
    `ModuleVersion = '2.1.0'`; `Deploy-TierModel.ps1:200` `Version: 2.1.0`; `Audit-TierModel.ps1:169`
    `Version: 2.1.0`; `README.md:165` `**Version**: 2.1.0`. No stale `2.0.0` reference survives outside
    `.squad/` history and `CHANGELOG.md` (both of which are history and must keep theirs). What remains is a
    **confirmation pass**, not a bump — plus a decision on whether the bug-fix sweep pushes the number under
    **D12** (bugs → PATCH), which is Joel's call, not this task's.
  - **Stray files — measured 2026-09-06:** the repository root is **already clean**. It holds only
    `.gitattributes`, `.gitignore`, `Audit-TierModel.ps1`, `CHANGELOG.md`, `CODE_OF_CONDUCT.md`,
    `CONTRIBUTING.md`, `Deploy-TierModel.ps1`, `es-metadata.yml`, `LICENSE`, `mkdocs.yml`, `README.md`,
    `SECURITY.md`, `SUPPORT.md`. Re-check immediately before the PR, since the concurrent sweeps are still
    writing.
  - **Files**: repository root, `modules/TierModel/TierModel.psd1`, both entry scripts, `README.md`
  - **Verification 2026-09-08**: version markers are current at
    `modules\TierModel\TierModel.psd1:3`, `Deploy-TierModel.ps1:201`, `Audit-TierModel.ps1:170`, and
    `README.md:161`. Repository-root file listing contains only the expected files:
    `.gitattributes`, `.gitignore`, `Audit-TierModel.ps1`, `CHANGELOG.md`, `CODE_OF_CONDUCT.md`,
    `CONTRIBUTING.md`, `Deploy-TierModel.ps1`, `es-metadata.yml`, `LICENSE`, `mkdocs.yml`, `README.md`,
    `SECURITY.md`, `SUPPORT.md`. Remaining `2.0.0` references inspected outside `.squad`/`CHANGELOG` are
    legitimate schema/history/versioned-config references, not stale release markers.

---

## ⛔ Deferred — NOT v2.1.0 WORK

- **T016 — WI-18 / D9: forward explicit `-Verbose` to AD/GPO write call sites.**
  **Status: MEASURED and DEFERRED by Joel on 2026-09-05. This is no longer outstanding work for v2.1.0.**

  Joel, verbatim: *"Defer but include more details for later I need to see examples and if does not impact
  v2.1.0 release."*

  **Impact on v2.1.0: NONE.** It is additive annotation. No FR (FR-001 … FR-020) depends on it, no test is
  blocked by it, no doc page needs it, and its absence is today's shipped behaviour rather than a regression.

  **What the measurement found** (four rounds, three instruments discarded; round 3 voided for ANSI
  corruption of the capture):
  - `$VerbosePreference = 'Continue'` alone yields **0** ShouldProcess records from AD writes.
  - Explicit `-Verbose` on an AD write yields **exactly 1** record naming the DN — on success **and** on a
    write refused after the object resolved — and **0** when the target does not exist.
  - `New-GPO` yields **0** with or without `-Verbose`; `GroupPolicy` is a script module behind a proxy
    function in a `WinPSCompatSession`. Nothing to gain there.
  - This is a **PowerShell** mechanism, not an AD quirk: the preference variable governs `Write-Verbose` and
    does not enable ShouldProcess operation descriptions at all.
  - Our own `Write-Verbose` instrumentation works correctly under `-EnableVerbose`. The feature is sound;
    T016 was only ever about going further.

  **Recommended target: `v2.2.0`** — feature work under the D12 taxonomy (bugs → PATCH, features → MINOR),
  alongside spec 007. Scoped to AD **write** sites only, expecting nothing from GroupPolicy. A recommendation
  for Joel, not a locked decision.

  - **Files**: `modules/TierModel/public/*.ps1` *(unchanged — no product code was touched)*
  - **Full write-up, worked before/after examples and the four evidence gaps**: `spec.md` **D11**
  - **Instruments**: `.research/lab-validation/Measure-VerbosePreferenceGap-Round4.ps1` (rounds 1–3
    alongside); log `.research/lab-validation/LAB-RUN-PROGRESS.md` [17:12]–[17:17]
  - **Unchanged by the deferral**: `-Debug` MUST NEVER be forwarded as an explicit parameter to an AD or
    GroupPolicy cmdlet, and `@PSBoundParameters` MUST NEVER be splatted into one. Explicit `-Verbose` is not
    prohibited. T018 is the required CI enforcement and is **not** deferred with T016.

- **T017 — Author the Pester suite for the feature: DEFERRED TO v2.1.1.**
  **Status: DEFERRED by Joel on 2026-09-08.** Joel chose: *"Mark as deferred to v2.1.1 with reasons in the
  spec."* This is no longer outstanding v2.1.0 work.

  **Reason for deferral:** the diagnostics feature itself is implemented and lab-validated. What is missing is
  **test coverage**, not function. This is coverage debt, not a product defect.

  **Measured gap for the v2.1.1 owner:** across all **1,994** tests, the suite has:
  - `transcript`: **0** occurrences
  - `DebugPreference`: **0** occurrences
  - `FR-020` / `no-inert-switch`: **0** occurrences
  - `Debug\` path resolution: **1** occurrence
  - only **7 `It` blocks** whose names mention the diagnostics switches

  **Sharp edge — untested AND unmeasured:** the transcript logic lives in `Deploy-TierModel.ps1` and
  `Audit-TierModel.ps1`, but those entry scripts are outside `CodeCoverage.Path` in `.github\workflows\ci.yml`
  (the CI coverage population is the module paths plus `optional\Update-TierModelMembership.ps1`). Therefore
  this gap is invisible to the coverage percentage; no coverage number will reveal it. The safety-critical
  guard in `Deploy-TierModel.ps1:469-494` warns that an unpaired `Stop-Transcript` can silently stop the
  operator's own transcript, and that guard has no test.

  **Original T017 scope preserved for v2.1.1:** parameter surface parity; default-off regression;
  **non-modification** (not restoration) of global preferences on every exit path; module-scope reach;
  `Debug\` path resolution including the relative case; transcript gating; transcript failure is non-fatal;
  `Stop-Transcript` pairing asserted on the state flag; `-WhatIf` does not suppress diagnostics; success is
  not inferred from a missing exception; D8 auto-logging never prompts; the re-run hint round-trips; and the
  FR-020 no-inert-switch gate.

---

## Task Count

| State | Count | Tasks |
|-------|-------|-------|
| ✅ Complete | 25 | T001 – T015, T018, T019, T020, T021, T022, T023, T024, T025, T026, T027 |
| 🔄 In progress / unchecked | 0 | — |
| ⬜ Not started | 0 | — |
| 🟡 Not started, low priority | 0 | — |
| ⛔ Deferred — not v2.1.0 | 2 | T016 (WI-18 / D9 — see spec D11), T017 (coverage debt → v2.1.1) |
| **Total** | **27** | |

**Remaining verified-open v2.1.0 work: none.** T016 and T017 are out of the v2.1.0 count entirely.

**Genuinely blocking a lab test** (as distinct from blocking the *release*): none remain under Joel's
2026-09-08 lab-pass assumption. No unchecked v2.1.0 task remains.
