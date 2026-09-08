# Decision record — D8 / FR-007 never-prompt coverage

**Agent:** wolverine
**Date:** 2026-09-07
**Branch:** `feature/enable-verbose-debug` (HEAD `04ab664`, nothing committed)
**Requested by:** Joel Platek
**Scope touched:** `tests\Integration.Deploy.Tests.ps1`, `tests\Integration.Audit.Tests.ps1` only.
No product file, no `modules\`, nothing staged, nothing committed.

---

## D-A — The two `Should -Throw` tests were re-pointed, not deleted

`Integration.Deploy.Tests.ps1` asserted `*OutputFileBase cannot be empty*` for empty-string and
whitespace-only replies. That contract was removed on Joel's instruction ("hitting enter shouldn't
get errors or stop script"). Both tests encoded the *old* contract and neither had ever caught a
regression.

**Decision:** re-point both at the new contract (empty and whitespace-only both succeed and resolve
to `Deploy-TierModel`), and keep them as two separate cases.

**Rationale, demonstrated not asserted:** control-prove R4 changed only
`[string]::IsNullOrWhiteSpace` -> `[string]::IsNullOrEmpty` in `Deploy-TierModel.ps1`. The
empty-string test stayed green; the whitespace-only test failed **alone**. The two inputs are
equivalent *because of* `IsNullOrWhiteSpace` — which is the property under test — so deleting either
case removes the only detector for that regression class.

A third test was added asserting the prompt string carries the default (`... [Deploy-TierModel]`),
so an operator can see what Enter accepts. Net: 2 tests -> 3.

## D-B — The D8 never-prompt guarantee is now enforced by a comparison, not by two isolated checks

Both D8 branches now end in the same literal default, so no output assertion can distinguish them.
The **only** observable difference is whether a prompt occurred.

**Decision:** each script gets an "anti-collapse" test that runs the same scope twice — once with
explicit `-Logging`, once with a diagnostics switch — and asserts the prompt counts **against each
other** (1 vs 0) inside a single `It`, with `Should -Not -Be` making the non-interchangeability
explicit.

**Demonstrated:** replacing `if ($script:LoggingAutoEnabled)` with `if ($false)` — the exact edit a
maintainer would make when the branches "look redundant" — fails **3 Deploy** and **3 Audit** tests.
Before this session it failed nothing.

## D-C — Prompt recorders by closure, never `$script:`

**Decision (house rule, generalises beyond this feature):** a Pester mock that must report what it
saw uses a collection captured by `.GetNewClosure()`. A `$script:` assignment made inside a mock
body is **not** visible to the `It` that reads it back — verified: the naive version asserted
against `$null`. Any recorder-style mock written with `$script:` should be treated as suspect.

## D-D — Console echo is the observable, not the log file

`Write-TierModelLog` is mocked in the Deploy integration harness, so no log file ever reaches disk
there. Assertions on the resolved `-OutputFileBase` use the script's own echo
(`Logging enabled: <path>`) captured with `6>&1`, matched against
`Deploy-TierModel-\d{6}-\d{4}\.log`.

## D-E — Container count and file placement

**Decision:** the new tests were appended to the two existing Integration files rather than put in a
new `Integration.Diagnostics.Tests.ps1`. This reuses two large, proven mock harnesses and keeps the
CI container count at **32**, so no CI wiring assumption changes. Cost: both files grow.

---

## Control-proofs performed

Each revert was applied to a **scratch copy of the repository outside the tree**
(`%TEMP%\wolv\scratch`), one property at a time, product files restored from pristine between runs.
Scratch deleted afterwards.

| # | Reverted property | Expected to fail | Result |
|---|---|---|---|
| R1 | Deploy: collapse the D8 branches (always prompt) | 3 Deploy D8 tests | 3 failed, 2 passed — as intended |
| R2 | Audit: collapse the D8 branches | 3 Audit D8 tests | 3 failed, 3 passed — as intended |
| R3 | Deploy: restore `throw "OutputFileBase cannot be empty..."` | all 3 Logging Edge Cases | 3 failed |
| R4 | Deploy: `IsNullOrWhiteSpace` -> `IsNullOrEmpty` | whitespace case **only** | 1 failed, 2 passed |
| R5 | Deploy: drop `[$defaultOutputFileBase]` from the prompt text | prompt-text test only | 1 failed, 2 passed |
| R6 | Deploy: delete the NON-BLOCKING-3 resolved-base block | hint replay test only | 1 failed, 4 passed |
| R7 | Audit: delete the NON-BLOCKING-3 resolved-base block | both Audit hint tests | 2 failed, 4 passed |
| R8 | Audit: restore the `-OutputFormat` empty throw | OutputFormat prompt test only | 1 failed, 5 passed |

Every revert failed exactly the tests it should and no others.

---

## Run shapes (all after the change)

| Shape | Discovered | Passed | Failed | Containers |
|---|---|---|---|---|
| Unit, by path | 1608 | 1608 | 0 | 25 |
| Integration, by path | 330 | 330 | 0 | 7 |
| **CI-shaped** (`ADStubs.ps1` dot-sourced, `$config.Run.Path = "tests"`, one session) | **1938** | **1938** | **0** | **32** |

Baseline before the change: Unit 1608/1608/0, Integration 318/316/2, CI-shaped 1926/1924/2.
Net **+12** tests, **-2** failures. The CI shape runs the whole suite under
`Set-StrictMode -Version Latest` (inherited from the alphabetically-first
`Integration.Audit.Tests.ps1`); all new tests were verified in that shape, not only by path.

---

## Open items for Joel

- The four earlier CI recommendations remain **unruled and unactioned**. This work materially
  strengthens the case for adding `[CmdletBinding()]` to `tests\helpers\ADStubs.ps1`: the new D8
  tests mock `Read-Host`, not an AD cmdlet, so they are unaffected by the stub-fidelity gap — but
  that is exactly the point. The gap is now the *only* remaining reason a CI green differs from a
  local green in this area.
- No product change is requested or implied. Rogue's three prompt sites, the `LoggingAutoEnabled`
  seam and the NON-BLOCKING-3 replay all behave exactly as their comments describe.
