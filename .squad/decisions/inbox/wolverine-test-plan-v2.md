# Decision Record — Test Plan v2 (BUG-026 → BUG-034) + two open questions answered

**Date:** 2026-09-05
**Author:** Wolverine (Tester)
**Branch:** `feature/enable-verbose-debug` — nothing committed, nothing staged
**Scope touched:** `.research\test-plan-verbose-debug-v2.md` (new),
`.research\test-plan-verbose-debug.md` (superseded banner only). **No test code written.**

---

## 1. Decisions

### 1.1 v2 supersedes v1 rather than replacing it
v1 is kept for provenance with a banner naming the three things in it that are now wrong. Deleting
it would erase the record of a withdrawn number, which is the part most worth keeping.

### 1.2 The BUG-019 population is **35 sites across 21 files**, AST-verified
Adopted over both the decision log's *37 across 28 module files* and my own v1 *70 across 22 files*.
Measured against the authoritative cmdlet surface (179 names from the real `ActiveDirectory` and
`GroupPolicy` modules), run twice — detached worktree at `04ab664` and the working tree.

Baseline 35 no-`ErrorAction` reads → working tree 1. Reads carrying `Stop` went 128 → 162. The two
deltas agree exactly (34), which is what makes the number trustworthy.

**I withdraw the 70/22 figure.** I could not reproduce it by any AST method and I tested the
obvious derivation (double-counting `Stop` + `catch` per site): the catch-clause delta is **+22**,
not +35, so that arithmetic fails. It was my number and it was wrong.

### 1.3 The `ADStubs` claim is confirmed for AD/GroupPolicy and **corrected** for LAPS
Confirmed: dot-sourced from `ci.yml` only; no test file loads it; all 5 stub groups are
`Get-Command`-guarded; AD/GP cmdlets resolve to the real modules here.

Corrected: the file defines **76** stub functions and dot-sourcing it on this RSAT machine defines
**4** — the legacy LAPS cmdlets, which RSAT does not supply. My "complete no-op on any RSAT machine"
was too strong. Corrected rather than defended.

The substantive half stands, and is stronger than "different code":

```
Stubbed Get-ADDomain … -ErrorAction Stop  -> did NOT throw, returned $null
Real    Get-ADDomain … -ErrorAction Stop  -> THREW ADServerDownException
```

**CI is structurally incapable of testing BUG-019.** An empty-bodied stub cannot represent a read
failure, so `-ErrorAction Stop` is unobservable there. Our 1573/318 is an RSAT-**present**
measurement; CI's identical-looking green measures **different code**. Every "proven by the green
suite" claim needs qualifying by environment — including two in `CHANGELOG.md`.

### 1.4 Script-internal functions get a second testing route: **AST extraction**
`Invoke-CanonicalAclAudit` and `ConvertTo-TierModelDriftFinding` live inside
`Audit-TierModel.ps1` and cannot be mocked. Beyond neutralising at the module-public boundary, they
can be parsed out of the **shipping file** by `FunctionDefinitionAst` name and dot-sourced into a
test session. Proven working — all 8 producer shapes were run through the live normaliser this way.

Accepted limitation: it tests the function in isolation, not its wiring. **Every AST-extracted unit
group must be paired with an Integration test proving the function is called.**

### 1.5 Fixture rule adopted for the six artifact-integrity defects
BUG-027, 028, 029, 030, 032, 034 share the shape *console right, saved artifact wrong*. (BUG-031 is
the mirror — log right, console wrong. BUG-026/033 are start-up defects.)

Every regression test in this family: **drifted fixture, more than one entity type, drift in the
EARLY types, LAST type clean, exact-integer assertions, and the artifact must NAME the object.**

Verified consolidated order:
`OU → Canonical ACL → Group → User → OU ACL → GPO → ADMX → MSA → gMSA → dMSA → WinLaps ACL →
WinLaps Decryptor → Audit Rule → Auth Policies → Auth Silos`

Three refinements found while verifying it:
- **"Last" is conditional.** Plain `-FullDeployment` ends at **ADMX**; only `-Include*` makes
  **Auth Silos** last. A fixture built for one is wrong for the other.
- **`WinLaps Decryptor` is behind `-IncludeWinLaps`,** not `-IncludeAuthSilos` — an auth-silo
  fixture misses one of BUG-034's three shapes.
- **BUG-028 and BUG-034 need opposite fixtures** (last type clean vs auth findings present). They
  cannot share a test.

### 1.6 Forecast: **+92** (Unit +44, Integration +48) → 1983
Revised from v1's +63. The increase is BUG-028→034, which postdate v1; BUG-019's own group came
*down* 31 → 27 now the population is exact. Confidence ±12.

---

## 2. Findings raised (reported, not fixed — I own no product code)

1. **🔴 The BUG-019 fix has one site still open:** `optional\Redirect-DefaultContainers.ps1` **L46
   `Get-ADDomain`**. Invisible three ways — CI ScriptAnalyzer scans `modules/TierModel` only; CI
   code coverage lists `optional/Update-TierModelMembership.ps1` but not this file; no test
   references it. Group 13's AST guard fails today for exactly this reason, which is the right
   way for a new control to arrive.
2. **`docs\known-bugs.md` marks BUG-034 🔴 Open; the code is fixed.** All three formerly-broken
   shapes now render correctly and the 33 correct sites are unchanged. Register is stale.
3. **CI cannot observe read failures at all** — §1.3. A permanent limit on what CI green means.
4. **CI's `Load AD/GPO Stubs` step is a no-op** — it is its own `run:` block, therefore its own
   pwsh process, and its functions die with it. Only the dot-source inside `Run Pester Tests`
   has effect. Harmless, but it reads as coverage that does not exist.
5. **CI ScriptAnalyzer and code coverage both exclude the two entry scripts.** This is why BUG-033
   survived — and `PSUseBOMForUnicodeEncodedFile` is *also* in the exclusion list, so the rule that
   would have caught it was disabled twice over.
6. **Deploy/Audit `Start-Transcript` asymmetry** (`-WhatIf:$false` on Deploy only) still
   unresolved. Blocks the Group 12 Audit mirror — a code question, not a test question.
7. **My v1 figure of 70 sites / 22 files is withdrawn.**

---

## 3. Method notes worth keeping

- **`Select-Object -First N` truncated my own analysis script** mid-run and prevented it writing its
  CSV — producing a "missing file" that looked like a bug. Register rule 8, committed by its author,
  within an hour of writing it up. Never truncate a pipeline whose side effects you need.
- **A detached worktree at the baseline commit** remains the clean way to measure a before/after
  population without touching the working tree. Removed and pruned; `git worktree list` shows only
  the main tree.
- **Verify the register, not just the code.** BUG-034 was fixed while still marked Open. Planning
  from the register alone would have produced tests for a defect that no longer exists.

---

## 4. Constraints honoured

`.research\` only — nothing under `tests\`, `modules\`, `docs\`, `.research\lab-validation\`, or
either entry script. No test code written; lab validation still precedes authoring. Nothing run
against the lab VM. Nothing committed or staged. Suites measured by path, never by `-Tag`. Temporary
worktree removed and pruned. Repo root confirmed clean of `*.log`. Analysis scripts kept in the
session workspace, not the repo.

---

## Addendum — v2.1 (2026-09-05)

Three additions requested after the v2 review. Planning only; no test code written.

### D-6 · ADStubs blindness — recommend **Option D**, a fourth option

Investigating the three offered options surfaced the actual cause, which none of them addressed.
All 76 stubs lack `[CmdletBinding()]` and 66 declare a hand-rolled `$ErrorAction` parameter that
captures `-ErrorAction Stop` into a local variable and discards it.

**This makes the gap worse than recorded.** It is not only *unmocked* calls that diverge: a
correctly written `Mock … { Write-Error }` BUG-019 regression test — the idiom this plan mandates —
**does not escalate in CI either**. All 27 Group 11 tests would have been authored against a
harness that cannot express the property they test.

Proven with four Pester cases: real cmdlet escalates; stub with hand-rolled `$ErrorAction` does
not; stub with `[CmdletBinding()]` does; unmocked stub returns `$null`.

**Decision sought:** adopt Option D — add `[CmdletBinding()]`, remove the hand-rolled
`$ErrorAction`. ~76 one-line edits in one test-helper file, no production change, no global test
state, no skipped tests. Rejected: (a) redundant with per-test mocks and introduces cross-test
state; (b) turns a vacuous green into a permanent red on runners where RSAT is not practical.
Adopt (c) for the residual only — unmocked calls, which no stub design can fix, handled by rule.

**Known cost:** `[CmdletBinding()]` makes each stub reject undeclared parameters it previously
absorbed. Expect one CI-wide red run and a stub-signature cleanup pass. That surfacing is a
benefit, but it must be budgeted rather than discovered.

**Blocks Group 11.** Sequenced as step 0.

### D-7 · `optional\` coverage — recommend closing all three holes

The untested, uncovered, unlinted file is **2.3 KB / 62 lines**; its sibling is already covered and
tested. A dedicated BUG-035 L46 test would duplicate TC-ENV-01's static guard, so the value lies in
the other two holes: add `optional/` to ScriptAnalyzer, add the file to `CodeCoverage.Path` (two
YAML lines), and add three behavioural tests. Recommend the YAML lands as a separate non-blocking
change, since linting a never-linted 95 KB sibling may produce a large backlog.

Two further defects found in that file while scoping: it has **no `Set-StrictMode`** (which is why
BUG-035's `$null` propagates into a malformed DN rather than throwing), and **`redirusr`/`redircmp`
exit codes are never checked**. Reported, not fixed.

### D-8 · Silent `catch` triage — 66 verified, but the population is 102

Re-measured by AST before adopting the brief's numbers. The 66 / 38 / 28 split and both named
concentrations reproduce **exactly**. Two amendments:

- **38 "with neither comment nor logging" overstates by 8** — those eight are documented in the
  `try` block rather than inside the `catch`. Genuinely undocumented: **30**.
- **66 is not the silent population.** A further 118 clauses contain statements but emit nothing;
  46 of those append to `$planErrors`/`$warnings` (the *correct* pattern, and not silent at all),
  leaving **72 lossy assignments**. Total genuinely silent: **102**.

Consequence for the lint question: un-excluding `PSAvoidUsingEmptyCatchBlock` would flag 66 and
**miss 72**, because they are not empty. Worth doing, but it buys about a third of the problem.

**The `AuthPolicy`(6)/`AuthSilo`(5) concentration is benign** and unrelated to BUG-034: it is the
`Set-StrictMode` idiom for probing a possibly-absent property. Recommend a code tidy-up to
`PSObject.Properties[...]`, not tests.

**Worth a test — 9, sampled by behaviour.** Headline: `Get-TierModelGpoFd.ps1` L204, where a failed
read is converted into a *planned deployment action* — every other case loses information, this one
invents it. Then `Test-TierModelPrerequisites.ps1` (22 silent clauses, the largest concentration,
in the component whose only job is to say whether it is safe to proceed), `Deploy-TierModel.ps1`
L782 (dMSA capability gate), and `Get-TierModelOuAcl` L220's `[Guid]::Empty` fallback, which
silently **widens an ACE's scope** — a security defect, not a reporting one.

In scope for this release because a silent `catch {}` is invisible **even under `-EnableDebug`** —
the one construct the branch's headline feature structurally cannot illuminate.

### D-9 · Forecast — +105, and the ±12 band is not being re-baselined

The BUG-026 → 034 estimate is **unchanged at +92 ±12**. The three additions are new scope and are
costed separately: Group 14 +3, Group 15 +9, TC-ENV-03 +1. New total **+105 → 1996, ±17**.
Deferring Group 15's P2 tier gives **+100 → 1991** — the plan's only scope lever.

### Self-correction recorded

§1.2 consequence 2 of the v2 plan claimed the `Write-Error` mock idiom "already achieves" CI/dev
parity. I asserted that without testing it. It is false. The claim is struck through **in place**
in the plan, next to where I made it, rather than silently replaced.

### D-10 · Late correction — BUG-035 was fixed while this addendum was being written

Rogue landed the `optional\Redirect-DefaultContainers.ps1` fix mid-revision. Re-verified against the
working tree before publishing: the read now carries `-ErrorAction Stop` in a `try`/`catch` that
rethrows with context, plus a guard rejecting an empty `DistinguishedName`. **The `-ErrorAction`
population is complete — zero open sites.**

Plan corrected in three places rather than left stale: §1.1 (finding now 🟢), TC-ENV-01 (no longer
"fails today" — its job is now to hold the population at zero), and Group 14 (reframed from
defect-hunt to **lock-in of a shipped fix**, which is the Group 7 pattern).

One consequence worth naming: **TC-035-01 cannot be a `Should -Throw` test.** The fix's second
guard also throws, so a reverted `-ErrorAction` still throws — just with a different message. Only
the message discriminates the two paths. This is the `Mock X { throw }` trap in a new costume, and
it would have produced a test that passes with the fix reverted.

Still open and verified after the fix: the script has **no `Set-StrictMode`**, and
`redirusr`/`redircmp` **exit codes are still unchecked**. Neither was in scope for BUG-035.

---

## Addendum — v2.2 (2026-09-05)

### D-11 · BUG-037 test repair — delivered, and it was a bug not a trade-off

`tests\Unit.GpoOperations.Tests.ps1` L2139 encoded the fabricated `LinkGPO` action as intended
behaviour. Repaired **in place**; Unit unchanged at 1573.

**Checked whether it was deliberate design rather than assuming.** It was not. The test and the
fabricating catch **entered in the same commit** (`f8270cd`, the initial codebase import); the only
rationale is an inline implementation note; there is no issue reference, ADR or decision record.
`docs\test-coverage.md` merely describes the behaviour. Independently verified Rogue's key
evidence: `-ErrorAction SilentlyContinue` was already on the read at `HEAD`, so the ordinary "not
linked" case arrives as an empty result handled inside the `try`, and only genuine terminating
failures reached the catch. **No decision needed from Joel.**

Assertion: `LinkGPO` count `-Be 0` **and** the specific warning. Count alone would pass against a
bare `catch {}`; the message is matched literally so the outer catch's warning cannot satisfy it.
The `throw` mock is deliberate and documented in the test — the `Write-Error` house rule targets
error *escalation*, and here the read is intentionally `SilentlyContinue`, so `Write-Error` would
never reach the catch under test.

Verified both directions: new test **fails against pre-fix `HEAD` code** (`Expected 0, but got 1`)
and passes against the fix, using a scratch copy of the tree — Rogue's working tree untouched.
Both siblings pass in **both** states, confirming TC-037-01 is the only thing pinning BUG-037.

Distinguishability confirmed: run against the sibling's scenario, the count assertion passes and
only the warning fails. **My first probe of this was vacuous** — a hand-rolled harness missing the
domain-DN mocks aborted planning before the code under test ran. Caught and redone. *A probe needs
its own fail-for-the-right-reason check, exactly like a test.*

**Two findings raised, not fixed:** nothing locks in the deliberate `SilentlyContinue` (switching
it to `Stop` keeps every test green while stopping link planning entirely — bigger than BUG-037);
and the surviving sibling asserts `-BeGreaterOrEqual 1` where an exact count is knowable.

### D-12 · BUG-036 / 037 / 038 folded into the plan

Groups 16 (BUG-037), 17 (BUG-038) and 18 (BUG-036) added. TC-CATCH-01 and TC-CATCH-08 retired as
obsolete — both became real defects within hours of being written down, which is an argument for
reading the remaining P2 entries rather than deferring them by default.

**BUG-038 fixture rule, measured not assumed:** `config\tiermodel-acls.json` has **105 ACE entries,
of which exactly 15 declare `inheritedObjectType`** (`BitLockerRecoveryObject` ×8, `User` ×6,
`Contact` ×1). The other **90 resolve to `[Guid]::Empty` legitimately**. So "never `Guid::Empty`"
is an invalid assertion — it would fail 90 correct delegations. The tests must separate *resolution
failure* from *by-design absence*, and must additionally prove the audit no longer applies the
fallback to its **own expectation** (the self-blinding), plus that remediation now follows
detection. Noted that MSA/gMSA/dMSA already carried the guard and matching tests at `HEAD` — reuse
their shape so the four families stay symmetrical.

**TC-035-01 confirmed as flagged:** Rogue is right that a bare `Should -Throw` passes with the fix
reverted, since both guards throw. Only the message discriminates. Already recorded in the plan.

### D-13 · Forecast — I am handing you a range, not a number

v2.2 arithmetic gives **+120 ±23**; the group table totals **+131**. The gap is Group 15's
re-tiering after losing TC-CATCH-01/08 to the two fixes. **Floor +120 → 2011, ceiling +131 → 2022.**
I would rather state an 11-test range I can defend than pick the tidier of two numbers. It converges
once Group 15 is re-tiered against the fixes.

Also flagged as unverified: Group 18 assumes **eight** producers, taken from the register rather
than measured. Register figures have been stale twice this session — measure before authoring.
