# Decision Record — BUG-031 Integration test repair + CWD log litter

**Date:** 2026-09-05
**Author:** Wolverine (Tester)
**Branch:** `feature/enable-verbose-debug` (HEAD `04ab664`, nothing committed)
**Scope touched:** `tests\Integration.Audit.Tests.ps1`, `tests\Integration.Deploy.Tests.ps1` — `tests\` only.

---

## 1. Context

BUG-031 folds the canonical-ACL phase-throw count into `$totalErrors`, so a run whose Phase 1b
died can no longer render green. Three Integration tests mocked the six entity audit functions
but not the canonical-ACL phase, which throws against the non-existent test DC. They encoded the
old swallow-the-error behaviour and were stale, not regressed.

`Invoke-CanonicalAclAudit` is a function defined *inside* `Audit-TierModel.ps1` and the script is
invoked with `&`, so it is not resolvable to `Mock` from the test session. The phase is therefore
neutralised at its dependency boundary instead: `Get-ADDomain`, `Test-TierModelOuExists` and
`Test-TierModelCanonicalAcl` are all module-public and mockable.

## 2. Decision per test

### 2.1 `Full Deployment Audit > Full Audit Orchestration > Should calculate compliance percentage correctly`

- **Was wrong:** asserted `Compliance: 90%` while Phase 1b threw, giving
  `Total Errors: 1` and `Compliance: N/A (could not be determined)`.
- **Approach: neutralise the phase, and correct the arithmetic.** The test's subject is the
  compliance percentage calculation, not error handling; leaving the phase failing means it tests
  nothing it claims to.
- **Change:** added clean-read mocks for `Get-ADDomain` / `Test-TierModelOuExists` /
  `Test-TierModelCanonicalAcl`; replaced the single loose assertion with four exact-integer
  assertions — `Total Checked: 101`, `Total Drift: 10`, `Total Errors: 0`, `Compliance: 90.1%`.
- **Why 101 and 90.1%, not 100 and 90%:** with the phase running, the canonical-ACL audit
  legitimately contributes one checked object (the domain root; both Tier OUs report absent and
  are skipped). That is real product behaviour, so the expectation was corrected to match it
  rather than the mocks being bent to preserve a round number.

### 2.2 `Compliance Reporting > Compliance Status Display > Should show COMPLIANT status when no drift detected`

- **Was wrong:** failed on `Compliance: 100%` for the same reason (`Total Errors: 1`).
- **Approach: neutralise the phase.** Under BUG-031 a COMPLIANT verdict now legitimately
  *requires* every phase to have run — so the honest way to test the COMPLIANT display is to let
  the phase run and succeed.
- **Change:** same three mocks, plus assertion hardening (see §4) — the verdict match is now
  anchored to `Overall Audit Status: [^\r\n]*COMPLIANT`, and `Total Errors: 0` /
  `Total Checked: 33` / `Total Drift: 0` are asserted explicitly.

### 2.3 `Compliance Reporting > Compliance Status Display > Should show drift count when drift detected`

- **Was wrong:** failed on `10 DRIFT ITEMS`, because with `$totalErrors -gt 0` the verdict branch
  prints `COMPLIANCE COULD NOT BE FULLY DETERMINED` and the DRIFT ITEMS line is never emitted.
- **Approach: neutralise the phase.** The subject is the drift-count display; the error state
  suppresses that entire line, so the test could not reach its own subject.
- **Change:** same three mocks; kept `10 DRIFT ITEMS` / `Total Drift: 10` and added
  `Total Checked: 33` and `Total Errors: 0`.

**Not chosen for any of the three: "update the expectation to assert the phase error is counted."**
All three are compliance-*display* tests. Converting one into an error-accounting test would have
destroyed the only coverage of the display path it owns while producing a badly-named test. See
the gap raised in §5 instead.

## 3. Repo-root log litter (`tests\Integration.Deploy.Tests.ps1`)

The CWD-relative log path is the behaviour under test and must keep being tested, so **`-LogPath`
was deliberately not used** — that would have made the tests green while silently testing nothing.

Instead two helpers, `Enter-CwdSandbox` / `Exit-CwdSandbox`, were added to the file's top-level
`BeforeAll`. They create a throwaway `$env:TEMP\TierModel-Deploy-Cwd-*` directory, `Push-Location`
into it, and on exit `Pop-Location` (guarded by a pushed flag) with the directory removal in a
`finally`.

They are wired into `BeforeEach`/`AfterEach`, **never inline in an `It`**: an inline `Pop-Location`
is skipped when an assertion fails mid-test, which strands every subsequent test in the wrong
directory and cascades unrelated failures.

The brief named only L720–723, but a survey of all `-Logging`-without-`-LogPath` call sites found
**five** Describes doing this, not one:
`Logging Configuration`, `Logging Integration`, `Logging Edge Cases`, `Error Path Logging`,
`Coverage Gap Closing Round 2`. Fixing only the named one still left a `TestLog-*.log` in the root
— measured, not assumed. All five are now sandboxed.

## 4. Assertion hardening (an incidental but important finding)

At baseline, test 2.2's `$output | Should -Match 'COMPLIANT'` **passed even while the audit was
reporting `COMPLIANCE COULD NOT BE FULLY DETERMINED`**. `-Match` is case-insensitive, and the
failure output contains the sentence *"its compliance is UNKNOWN, not compliant."* The assertion
was matching the failure message. Only the sibling `Compliance: 100%` assertion caught the
problem.

House rule reinforced: an unanchored substring match on a status word is not a status assertion.
Anchor to the line that carries the verdict.

## 5. Gap raised, deliberately not closed here

Per Joel's sequencing (lab validation first, new test authoring second), this task was **repair
only**. Consequence: **no test now locks in BUG-031** — every test that previously exercised the
phase-throw path incidentally has had that path neutralised. A dedicated test asserting that a
thrown canonical-ACL phase yields `Total Errors: 1`, `COMPLIANCE COULD NOT BE FULLY DETERMINED`
and `Compliance: N/A` must be added in the authoring phase. Per the standing method rule it must
mock with `Write-Error`, not `throw`, wherever the property under test is error escalation.

## 6. Product defects found

None. The three failures were test defects exactly as predicted. BUG-031's behaviour was observed
directly and is correct: the phase error appears in `Total Errors`, forces the
`COMPLIANCE COULD NOT BE FULLY DETERMINED` verdict, and suppresses a misleading percentage.

## 7. Measurements (by path, never by `-Tag`)

| Suite | Before | After |
|---|---|---|
| Unit (`tests\Unit.*.Tests.ps1`) | 1573 / 1573 passed / 0 failed | **1573 / 1573 / 0** |
| Integration (`tests\Integration.*.Tests.ps1`) | 318 / 315 passed / 3 failed | **318 / 318 / 0** |
| `*.log` in repo root after full Integration run | 6+ per day | **0** |

Test count unchanged at 1891; no test was deleted, skipped or weakened. Each of the three was
confirmed failing for the intended reason before the change (the pre-edit file was replayed from
`HEAD` in a scratch copy) and passing after. No commits, no staging.
