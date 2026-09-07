# Decision: Test Strategy for `feature/enable-verbose-debug` — and the RSAT-conditional baseline

**Date:** 2026-09-05
**Author:** Wolverine (Testing)
**Status:** Proposed — items 1 and 2 need a team call before test work starts
**Related artifact:** `.research\test-plan-verbose-debug.md`

## Context

Joel asked for a test *plan* — not tests — for the `feature/enable-verbose-debug` branch
(BUG-019, BUG-026, BUG-027, plus the `-EnableVerbose`/`-EnableDebug` switches). Sequence is
deliberate: lab first, tests second. Writing tests before lab sign-off was a mistake in a prior
session.

While measuring baselines I found the Integration suite is **not** green on this branch on an
RSAT-equipped machine. That is the material finding and it drives most of what follows.

## Decisions Made

### 1. ⚠️ The Integration baseline is 315/3 on RSAT machines, and the production code is correct

Measured: Integration **315 passed / 3 failed** on the branch. Control: `Integration.Audit.Tests.ps1`
at clean `04ab664` in a temporary detached worktree, same machine, same session — **69/0**. The
three failures are branch-introduced, not environmental.

All three are in `tests\Integration.Audit.Tests.ps1` and expect `Compliance: 90%`,
`Compliance: 100%` and `10 DRIFT ITEMS`. None of them mocks `Get-ADDomain`, so the canonical ACL
phase reaches the real cmdlet, which cannot contact `testdc.contoso.local`. Before BUG-019 that
failure was swallowed and the run scored `Compliance: 96%, Total Errors: 0`. With BUG-019 it is
correctly surfaced as `⚠️ COMPLIANCE COULD NOT BE FULLY DETERMINED (1 error(s))`.

**Decision: do not change production code. The three tests are stale** — they encode the old
swallow-the-error behaviour, which is precisely what BUG-019 and BLOCKING-2 exist to eliminate.
They will be repaired in the follow-up test task, plus a new test locking in the correct verdict.

**Action for reviewers:** three red Integration tests on this branch are **expected and correct**.
Do not revert BUG-019 to make them green.

### 2. "Green suite" claims are RSAT-conditional and must be qualified

The 318/0 figure is an **RSAT-absent** measurement. `tests\helpers\ADStubs.ps1` is dot-sourced
only from `.github\workflows\ci.yml` (L101, L108); no test file loads it, and every block is
guarded by `if (-not (Get-Command Get-ADDomain ...))`, so it is a no-op wherever RSAT exists.
CI and developer machines therefore run different code, and CI is structurally blind to
read-failure defects because the stubs return `$null` without erroring.

**Decision:** qualify the figure by environment wherever it is quoted (README, `docs\test-coverage.md`,
CHANGELOG). Existing claims of the form "proven by the green suite — Unit 1573/0, Integration
318/0" — including the BUG-015 justification in `CHANGELOG.md` — are weaker than they read.

**Recommended follow-up (out of scope for this branch, needs its own task):** load the stubs from
the test files rather than only from CI, so both environments run the same code. This divergence
has now demonstrably produced a false green that survived until BUG-019 exposed it.

### 3. `ADStubs.ps1` will NOT gain a throwing mode

The brief proposed an opt-in "make stubs throw" mechanism to cover BUG-019's catch blocks.
**Rejected as the wrong tool.** Pester's `Mock` replaces the command outright, so the stub body
is never reached by any test that mocks what it wants to fail; and the stubs are a no-op on RSAT
machines anyway. Coverage needs per-test mocks, not a helper change.

A design is documented in §3.3 of the plan should the team disagree, with the constraints it
would have to meet (default-inert, `WriteError` default mode, both stub copies patched,
unconditional `AfterEach` cleanup, 1573/318 provably unchanged before use). My estimate is
low-hundreds of first-run failures needing individual triage — weeks of work, orthogonal to this
branch.

### 4. House rule: `Write-Error`, not `throw`, when testing `-ErrorAction Stop` fixes

A `throw` inside a Pester mock is terminating regardless of what the call site says, so
`Should -Throw` passes identically before and after a BUG-019 fix. Such tests are decoration.

**Rule:** mock with `Write-Error` (non-terminating). It only becomes terminating if the call site
passes `-ErrorAction Stop` — the exact property under test. Where the consequence is observable,
assert the consequence (poisoned cache, `$null` reaching a comparison), not the throw.
**Reviewers should reject any BUG-019 test whose only assertion is `Should -Throw`.**

### 5. House rule: BUG-027-class tests require a drifted fixture and exact-integer assertions

A stale `DriftCount = 0` is indistinguishable from a correct `0`, so a compliant-fixture test for
BUG-027 passes with the bug fully reverted — worse than no test, because it looks like coverage.
Same for BLOCKING-2's `UnverifiedCount`.

**Rule:** non-zero drift, non-zero checked, and **exact** expected integers — never
`-BeGreaterThan 0`, which sails past partial-sum bugs. Assert on outputs (report body, JUnit XML,
log record, exit code), never on the intermediate locals in the consolidated block.

### 6. The stray-log test is fixed by relocating the CWD, not by adding `-LogPath`

`tests\Integration.Deploy.Tests.ps1` L720–L728 writes `TestLog-*.log` into the repository root.
Adding `-LogPath` would delete the behaviour under test. Fix is `Push-Location`/`Pop-Location` to
a temp directory via `BeforeEach`/`AfterEach` (never inline in the `It` — an exception would
leave every later test running from the wrong directory).

Two stray logs were removed from the repo root during this session; a fresh one appeared from my
own baseline run, confirming the defect reproduces.

### 7. Scope explicitly excluded from automated testing

The lab is stronger evidence for: verbose/debug record emission counts, transcript contents and
the UNREDACTED banner, `Start-Transcript` no-opping under `-WhatIf`, and deployment idempotency.
`-Debug` forwarded to a real AD cmdlet is covered **statically** instead — an AST guard asserting
no `-Debug`/`-Verbose` reaches any `AD`/`GP` cmdlet across both scripts and all public functions.
One test, permanent, covers files not yet written.

## Forecast

+32 Unit / +31 Integration = **+63**, taking the automated total **1891 → 1954** (±10).
Unit baseline re-confirmed at **1573/0** this session.

README and `docs\test-coverage.md` should **not** be updated until the tests actually land.

## Open Questions for the Team

1. **Deploy and Audit diagnostics have diverged.** `Deploy-TierModel.ps1` L690 passes
   `-WhatIf:$false` to `Start-Transcript`; `Audit-TierModel.ps1` L576 does not. Mirrored tests
   will surface this as an asymmetric failure. This is a code question for Beast/Rogue, not a
   test question — I own no production code.
2. Does the team accept a **representative sample** (one test per distinct catch *behaviour*, per
   file, across the 8 densest files) rather than one test per each of the ~70 `-ErrorAction Stop`
   sites? I believe per-site testing would produce mostly-identical tests with poor value density.

## Files Changed

- `.research\test-plan-verbose-debug.md` — new (plan only)
- `.squad\agents\wolverine\history.md` — Learnings appended
- Repository root — two stray `TestLog-*.log` artifacts deleted

No file under `tests\` was created or modified. No production code touched. Nothing committed.
