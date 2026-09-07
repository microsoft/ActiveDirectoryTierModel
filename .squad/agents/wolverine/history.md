# wolverine -- History



## Session -04 — Scribe Orchestration & Verification

**Status:** COMPLETE — Orchestration logs written, no new test work this session.

This session's focus: Scribe documentation of the config-validation wire-in session (BUG-020..023). Wolverine's prior fixture repairs for BUG-023 (test count held at 101, no assertions weakened) were verified shipped in commit c973611 with full unit suite passing (1,573/0).

**Key outcomes:**
- BUG-023 fixture repair (prior session): Confirmed stable in c973611
- Unit test suite: 1,573/0 passing
- Integration suite: 318/0 passing
- Lab validation: TierLab-DC01 deployment succeeded

---



## Learnings

### Session — 2026-09-05 — Test plan for `feature/enable-verbose-debug` (BUG-019 / 026 / 027)

**Deliverable:** `.research\test-plan-verbose-debug.md`. PLAN ONLY — no test code written, by
explicit instruction from Joel. Writing tests before the lab signs off was a mistake made in a
previous session; the sequence is lab first, tests second.

**1. `Mock X { throw }` does NOT prove an `-ErrorAction Stop` fix.** A `throw` inside a Pester
mock is terminating whether or not the production call site says `-ErrorAction Stop`. So
"assert it throws" passes identically before and after the fix. ~70 worthless tests were one
careless decision away. **House rule going forward: mock with `Write-Error` (non-terminating)
for these.** It only becomes terminating if the call site passes `-ErrorAction Stop` — which is
exactly the property under test. Where the consequence is observable, assert the downstream
consequence (poisoned cache, `$null` reaching a comparison), not the throw.

**2. `tests\helpers\ADStubs.ps1` is a CI-only shim, and I had the wrong mental model of it.**
It is dot-sourced *only* from `.github\workflows\ci.yml` (L101, L108). No test file loads it.
Every block is guarded by `if (-not (Get-Command Get-ADDomain ...))`, so on any RSAT machine it
is a complete no-op. And its bodies are bypassed entirely the moment a test calls `Mock`.
Making the stubs throw is therefore *not* the route to covering catch blocks — per-test mocks
are, and they need no helper change.

**3. That divergence has already produced a false green — I caught it live.** Integration on
this branch is **315/3** on an RSAT machine, versus **69/0** for `Integration.Audit.Tests.ps1`
at clean `04ab664` (verified with a temporary detached `git worktree` — a clean, non-destructive
way to get a true baseline without touching the working tree; worth remembering). Root cause:
three tests never mock `Get-ADDomain`, so in CI the `$null`-returning stub lets the canonical
ACL phase "succeed", while on RSAT the real cmdlet fails. BUG-019's `-ErrorAction Stop` now
surfaces that failure honestly as `COMPLIANCE COULD NOT BE FULLY DETERMINED`. **The code is
right; the three tests encode the old swallow-the-error behaviour and are stale.** Repair them
and add a test that locks in the new verdict.

**Corollary I should have internalised sooner: "proven by the green suite" is an
RSAT-absent claim.** It needs qualifying every time it is written, including in CHANGELOG
entries that already lean on it.

**4. A test for a "wrong answer that looks right" bug must use a fixture where wrong and right
differ.** BUG-027 (stale `$auditSummary` zeros) is invisible on a compliant estate — a stale
`DriftCount = 0` and a correct `0` are identical. Any BUG-027 test on a clean fixture is *worse
than no test*: it passes with the bug fully reverted while looking like coverage. Same logic for
BLOCKING-2's `UnverifiedCount`. Assert **exact integers**, never `-BeGreaterThan 0` — a
"non-zero" assertion sails past partial-sum bugs.

**5. Two independent causes of a false green need defeating together.** BUG-026 was missed
because (a) every Integration Audit test mocks `Test-TierModelPrerequisites` away, *and* (b)
`Invoke-AllTests.ps1` L90 `Push-Location $scriptRoot` means the broken CWD-relative path happens
to resolve. Fixing either alone still passes with the bug reintroduced. Ask "how many reasons is
this green?", not "is there a reason".

**6. `Push-Location` belongs in `BeforeEach`/`AfterEach`, never inline in an `It`.** If the `It`
throws mid-body an inline `Pop-Location` never runs and every subsequent test executes from the
wrong directory — cascading failures that look like a catastrophic regression. Same rule for any
opt-in global test state: unconditional cleanup in `AfterEach`.

**7. Some things genuinely should not be unit-tested, and saying so is part of the job.**
The `-EnableVerbose`/`-EnableDebug` host behaviours — `Start-Transcript` silently no-opping under
`-WhatIf`, nested transcripts being harmless, module-scope preference resolution, `-Debug`
throwing a null-reference when forwarded to a real AD cmdlet — cannot be faithfully reproduced in
Pester. The lab is the stronger evidence. What *can* be tested is our **defence** against them
(confirm transcript creation with `Test-Path`, never infer success from no-exception) and a
**static AST guard** asserting no `-Debug`/`-Verbose` is ever passed to an `AD`/`GP` cmdlet — one
test, permanent, covering files not yet written. Highest leverage item in the whole plan.

**8. Verify the brief.** Every line number I was given had drifted, the ~33-sites figure was
actually 70 across 22 files, and the central premise about ADStubs was wrong. Four of the five
corrections made the plan better. Also: some BUG-019 sites keep `SilentlyContinue`
*deliberately* (`Get-TierModelGroup` et al., where "does not exist" drives the create plan) — a
test asserting those throw would encode the opposite of the design.

**Forecast:** +32 Unit / +31 Integration = **+63**, taking the automated total 1891 → **1954**
(±10). Unit baseline re-confirmed at 1573/0.

### Session — 2026-09-05 — BUG-031 test repair + repo-root log litter (repair only)

**Scope: `tests\` only.** Three stale Integration tests repaired, CWD log litter stopped.
Unit **1573/1573/0**, Integration **318/318/0**, both measured by path. No commits, no staging.

**9. A script-internal function cannot be mocked from the test session.**
`Invoke-CanonicalAclAudit` lives inside `Audit-TierModel.ps1` and the script is invoked with `&`,
so `Mock -CommandName Invoke-CanonicalAclAudit` has nothing to bind to. The route is to neutralise
the phase at its **dependency boundary** — here `Get-ADDomain`, `Test-TierModelOuExists` and
`Test-TierModelCanonicalAcl`, all module-public and mockable. Worth checking *where a function is
defined* before planning to mock it; it changes the whole shape of the fix.

**10. When a fix changes real totals, correct the expectation — do not bend the fixture.**
With Phase 1b actually running, the canonical-ACL audit legitimately contributes one checked
object (the domain root). Total Checked moved 100 -> 101 and compliance 90% -> 90.1%. The
temptation was to drop the OU mock to 99 so the round number survived. That would have encoded a
lie. Assert the real numbers and comment where the extra object comes from.

**11. `Should -Match 'COMPLIANT'` passed while the audit said COMPLIANCE COULD NOT BE FULLY
DETERMINED.** `-Match` is case-insensitive and the failure output contains *"its compliance is
UNKNOWN, not compliant."* The assertion was matching the failure message. It survived only because
a sibling assertion on `Compliance: 100%` did the real work. **An unanchored substring match on a
status word is not a status assertion** — anchor to the verdict line
(`Overall Audit Status: [^\r\n]*COMPLIANT`). This is the same family of defect as `Should -Throw`
proving nothing: the assertion is satisfied by states it was written to reject.

**12. The named line was never the whole problem.** The brief pointed at L720–723 of
`Integration.Deploy.Tests.ps1`. Fixing only that one still dropped a `TestLog-*.log` in the repo
root — measured, not assumed. A survey of `-Logging` without `-LogPath` found **five** Describes
doing it. Always re-run the observable symptom rather than declaring victory over the cited line.

**13. `Push-Location` sandbox, confirmed as the right shape.** Helpers in the top-level
`BeforeAll` (`Enter-CwdSandbox`/`Exit-CwdSandbox`), called from `BeforeEach`/`AfterEach`, with a
pushed-flag guard and directory removal in `finally`. Never `-LogPath` — the CWD-relative path is
the behaviour under test, and `-LogPath` would have made the tests green while testing nothing.
This is learning #6 from the previous session applied, and it held up.

**14. Replaying the pre-edit file from `HEAD` into a scratch copy is a cheap, safe way to prove
"fails for the intended reason".** `git show HEAD:tests/... > tests\ZZBaseline.*.Tests.ps1`, run
filtered, delete. Both remaining tests were confirmed failing on `Total Errors: 1` from the phase
throw — the intended cause — not on some incidental difference. Same spirit as the detached
worktree trick, at lower cost.

**15. Repair-only leaves a coverage hole, and saying so is the job.** Every test that incidentally
exercised the BUG-031 phase-throw path has now had that path neutralised, so **nothing currently
locks in BUG-031**. Flagged for the authoring phase rather than smuggled in against Joel's
sequencing. Must be written with `Write-Error`, not `throw`.

**No product defects found.** The three failures were test defects exactly as forecast, and
BUG-031's behaviour was observed directly and is correct.

### Session — 2026-09-05 — Test plan v2 (BUG-026..034) + two open questions answered

**PLAN ONLY**, `.research\` only. No test code. Forecast revised +63 -> **+92** (1891 -> 1983).

**16. I withdrew my own number, and that is the point.** v1's "70 `-ErrorAction` sites across 22
files" is not reproducible by any AST method. The verified population at `04ab664` is **35 reads
across 21 files**; 34 are fixed, **1 remains**. I tested the obvious derivation (double-counting
`Stop` + `catch` per site) and it fails — the catch delta is +22, not +35. I had written in v1 that
"grep produced a wildly inflated count" about someone else's figure. It applied to mine too. Check
your own numbers with the same instrument you use on other people's.

**17. Measure a before/after population against the baseline commit, not against intuition.**
Detached worktree at `04ab664` + identical AST script against both trees. The reconciliation is what
makes it trustworthy: 35 - 1 = 34 = 162 - 128. Two independent deltas agreeing beats one confident
count.

**18. Use the authoritative cmdlet list, not a name regex.** My first census used
`^(Get|Set|...)-(AD|GP)` and caught `Get-GpoActionsForConfig` — an internal helper — because
`-match` is case-insensitive, so `Get-Gpo…` satisfies `Get-GP`. `Get-Command -Module ActiveDirectory,
GroupPolicy` gives 179 real names and zero false positives. Same failure family as the
case-insensitive `Should -Match 'COMPLIANT'`.

**19. `Select-Object -First N` killed my own script before it flushed its CSV.** I wrote register
rule 8 about exactly this and then committed it within the hour, on my own analysis tooling rather
than a child process. The "file not found" that followed looked like a bug in the script. If a
pipeline has side effects you need, never truncate it.

**20. My ADStubs claim was right in substance and wrong as stated — corrected, not defended.**
"Complete no-op on any RSAT machine" is false: the file defines **76** stubs and **4** legacy LAPS
ones still get defined, because RSAT does not ship them. AD/GroupPolicy — the part that matters — is
genuinely inert. Report the correction as prominently as the confirmation.

**21. The real finding underneath it is bigger than "CI runs different code".** A stubbed
`Get-ADDomain … -ErrorAction Stop` **returns `$null` and does not throw**; the real cmdlet throws
`ADServerDownException`. An empty-bodied stub cannot *represent* a read failure, so **CI is
structurally incapable of testing BUG-019** — it would be blind with perfect tests. Our 1573/318 is
an RSAT-**present** measurement of *different code* than CI's identical-looking green.

**22. Script-internal functions have a second route: AST extraction.** `Mock` cannot bind to
`ConvertTo-TierModelDriftFinding` or `Invoke-CanonicalAclAudit`. But parsing the **shipping file**,
finding the `FunctionDefinitionAst` *by name*, and dot-sourcing `Extent.Text` tests the real source,
survives line drift, and needs no product change. It tests isolation, not wiring — so always pair it
with one Integration test proving the function is actually called.

**23. Verify the register, not only the code.** `known-bugs.md` marks BUG-034 🔴 Open; I ran all 8
real producer shapes through the shipping normaliser and it is **fixed**. Planning from the register
would have produced tests for a defect that no longer exists.

**24. "Last entity type" is conditional, and the fixture rule depends on it.** Plain
`-FullDeployment` ends at **ADMX**; `-Include*` makes **Auth Silos** last. Broken code keeps only the
last entity's findings, so a fixture must drift the EARLY types and leave the LAST clean — which
means the same fixture is wrong for the other scope. Also: `WinLaps Decryptor` sits behind
`-IncludeWinLaps`, not `-IncludeAuthSilos`; and BUG-028 (last type clean) and BUG-034 (auth findings
present) need **opposite** fixtures and cannot share a test.

**25. A new control should arrive failing.** The proposed AST guard "every AD/GP read carries an
explicit `-ErrorAction`" fails today on `optional\Redirect-DefaultContainers.ps1` L46 — a file that
is unanalysed (ScriptAnalyzer scans `modules/TierModel` only), uncovered (absent from
`CodeCoverage.Path`) and untested. That is the ideal debut for a guard: it earns trust by catching
something real before anyone has to believe it.

---

## 2026-09-05 — Plan v2.1: ADStubs root cause, `optional\` scope, silent-catch triage

**26. A stub is not a fake cmdlet unless it is an *advanced function*.** I had proved an
empty-bodied stub returns `$null` and concluded CI was blind only to *unmocked* calls. Wrong, and I
had asserted it in a plan without testing it. All 76 `ADStubs.ps1` functions lack
`[CmdletBinding()]`, and 66 declare a hand-rolled `$ErrorAction` parameter — which captures
`-ErrorAction Stop` into an ordinary local variable and throws it away. So even a correctly written
`Mock … { Write-Error }` regression test does **not** escalate in CI. The harness cannot express
the property the test exists to check. Lesson: when mocking is the foundation of a plan, test the
*harness* before costing 27 tests on top of it.

**27. Finding the cause turned three bad options into one cheap one.** Asked to pick among
throwing stubs / fail-CI-loudly / accept-the-gap, the right answer was a fourth option that only
appeared after I stopped evaluating options and went one level deeper. Adding `[CmdletBinding()]`
fixes it: mocked calls escalate correctly, unmocked calls still return `$null` harmlessly. Verified
both directions. When every available option is unattractive, that is usually a signal the cause
has not been found yet.

**28. State the cost that bites you later, not just the cost to do the work.** `[CmdletBinding()]`
makes each stub reject undeclared parameters it used to absorb silently, so the honest cost is "76
one-line edits **plus one CI-wide red run and a signature cleanup**". A recommendation that hides
its second-order cost gets adopted and then resented.

**29. Verify the brief's numbers even when the brief is right.** Joel's 66 / 38 / 28 catch split
reproduced *exactly* by AST, as did both named concentrations. But the same sweep found two things
the numbers did not say: 8 of the 38 are documented in the `try` rather than the `catch` (so 30, not
38, are undocumented), and there are 118 *further* clauses that have statements but emit nothing.
Agreeing with a number is not the same as understanding the population it describes.

**30. My own "silent" classifier was too literal, and I caught it by reading the bodies.** I first
counted 118 "emits nothing" clauses as silent. Reading them showed 46 append to
`$planErrors`/`$warnings` — surfaced in the plan object and the report, and a *better* pattern than
logging. Real silent total: 102, not 184. I nearly shipped a 78 % overstatement by trusting a regex
over the code. Always sample the bodies before quoting a population.

**31. The lint rule would have missed two thirds of it.** `PSAvoidUsingEmptyCatchBlock` flags the
66 empty bodies and none of the 72 lossy assignments, because those are not empty. Worth
un-excluding, but "turn the rule back on" is not the fix it sounds like. A ratchet test pinned to a
measured baseline covers what the linter cannot express.

**32. A concentration is not automatically a smell.** `Test-TierModelAuthPolicy`(6) and
`AuthSilo`(5) looked damning — the same producers behind BUG-034. Reading them, they are all
`try { $x = $obj.Prop } catch {}`, the `Set-StrictMode -Version Latest` idiom for a possibly-absent
property. Benign, and unrelated to BUG-034. If I had reported "the BUG-034 producers are also the
worst catch offenders" it would have been true, suggestive, and completely misleading.

**33. Rank by what the silence *causes*, not by how silent it is.** Most swallowed reads lose
information. `Get-TierModelGpoFd.ps1` L204 — *"if we can't check built-in container links, assume
linking is needed"* — **invents** a deployment action from a failed read. And
`Get-TierModelOuAcl.ps1` L220 falls back to `[Guid]::Empty`, i.e. "all object types", so a swallowed
lookup *widens an ACE's scope*. Those two outrank thirty tidier ones.

**34. Measure the directory before accepting "we have no coverage there".** `optional\` sounded
like an unbounded liability. It is two files; one is already covered and tested; the uncovered one
is 2.3 KB. That turned a scoping debate into two YAML lines and three tests. It also showed a
dedicated BUG-035 test would merely duplicate the AST guard I had already planned — the value was
in the *other* two holes, not the one I was pointed at.

**35. Don't re-baseline a forecast you are being held to.** +92 ±12 was for BUG-026 → 034. Three
new scopes arrived afterwards. The honest presentation keeps +92 ±12 intact, adds +13 on separate
lines, and states the new total and widened band explicitly — plus which tier can be cut to get
back down. Quietly reporting "+105 ±17" would have looked like the same estimate drifting.

**36. Strike through a wrong claim where you made it.** My false §1.2 assertion is struck through
in place in the plan with a pointer to §1.3, not deleted and replaced. A reader who remembers the
old claim needs to find its correction at the location they remember.

**37. Re-verify the code under a live teammate before you publish a claim about it.** Rogue fixed
BUG-035 while I was writing the section recommending tests for it. Had I trusted my read from the
start of the session, I would have shipped a plan describing a defect that no longer existed and a
guard test asserted to "fail today" that in fact passes. The re-check cost one command. The
correction it forced changed three sections and, more usefully, reclassified Group 14 from
defect-hunt to lock-in — which *raises* its priority, since an untested fix is exactly the state
this plan exists to eliminate.

**38. A fix can create a new false-assertion trap.** Rogue's BUG-035 fix throws on a failed read
*and* throws on an empty `DistinguishedName`. So a `Should -Throw` test passes with the
`-ErrorAction` reverted — the fallback guard catches it and throws anyway. Only the exception
*message* separates the two paths. Same family as `Mock X { throw }`: the assertion is satisfied by
something other than the property under test. Defensive depth in the product narrows what a test is
allowed to assert, and it is worth checking for the moment a fix adds a second guard.

**39. Ask whether a test was designed or merely codified — the answer is in the commit graph.**
Before rewriting a test that encoded a defect, I checked whether the "fallback" was a deliberate
safety trade-off. `git log -S` put the test and the fabricating catch in the *same* initial-import
commit, with no issue reference and only an implementation note for rationale. That turns "should
Joel decide?" into "no decision needed" — and it took one command. A test written *with* the code
in a bulk drop is evidence of codification; a test written later, alone, in response to a scenario,
is evidence of design.

**40. Verify the fixer's evidence independently, even when you agree with the conclusion.** Rogue's
case rested on `-ErrorAction SilentlyContinue` already being on the read, so only genuine failures
reached the catch. If he had *added* it as part of the fix, the reasoning would have been circular.
`git show HEAD:` settled it in one command. Agreeing with a conclusion is not the same as having
checked its premise.

**41. A house rule applied without its reason becomes a bug.** My own rule says mock with
`Write-Error`, never `throw`. Here the read is deliberately `SilentlyContinue`, so `Write-Error` is
swallowed and never reaches the catch under test — applying the rule would have produced a test
that exercises nothing. The rule targets error *escalation*; this test's property is *reaching the
catch at all*. I wrote the exception into the test as a comment, because the next reader will
otherwise "fix" it to comply.

**42. My verification probe was vacuous and I nearly believed it.** To prove two sibling tests were
not interchangeable, I hand-rolled a minimal Pester harness — and omitted the domain-DN mocks the
real file's `BeforeAll` supplies. Planning aborted with "Failed to resolve domain DN" *before the
code under test ran*. Count was trivially 0, `Write-Warning` trivially uncalled, and the probe
"confirmed" my expectation without executing a single relevant line. The output only gave it away
because an unexpected error line appeared. **A probe needs its own fail-for-the-right-reason check,
exactly like a test.** Redone by copying the real harness and swapping only the mock.

**43. Run the fixed test against the *old* code, not just the new.** The old test failing against
the new code proves nothing about the new test. Copying `modules\` and `tests\` to scratch and
reverting one file via `git show HEAD:` gave a real pre-fix run — and it also revealed that both
sibling tests pass in *both* states, i.e. they are blind to the defect and the repaired test is the
sole thing pinning it. That fact would have been invisible from the green suite.

**44. Measure the config before writing a fixture rule.** For BUG-038 the obvious assertion is
"`inheritedObjectType` must never be `Guid::Empty`". Counting the config killed it: **15 of 105**
entries declare the attribute, so 90 resolve to `Guid::Empty` legitimately and that assertion would
fail 90 correct delegations. The real rule is to separate *resolution failure* from *by-design
absence* — which is only visible once you count.

**45. When two derivations disagree, publish the range.** My v2.2 group table totals +131; the
incremental arithmetic gives +120. I could not reconcile them without work I had not done, so I
reported floor and ceiling and named the cause. Picking the tidier number would have been a guess
wearing a point estimate's clothes — and I have already watched one of my own unverified figures
(70/22) die this session.

**46. The file I had been reporting on for a whole session was at a different path.** My brief,
and my own earlier findings, said `tests\ADStubs.ps1`. It does not exist. The real file is
`tests\helpers\ADStubs.ps1`. The counts I had reported (76 stubs, 0 with `[CmdletBinding()]`, 66
with a hand-rolled `$ErrorAction`) verified exactly against it, so the measurement was sound and
only the path in the write-up was wrong -- but a teammate acting on my report would have opened
nothing. Re-resolve the path, not just the numbers.

**47. Guarded stubs mean the local suite never touches them.** Every block in `ADStubs.ps1` is
wrapped in `if (-not (Get-Command <cmdlet> ...))`. This box has RSAT, so `ActiveDirectory`,
`GroupPolicy` and `LAPS` are real and **74 of 76 stubs never define locally**; only the two
`AdmPwd.PS` stubs do. The 1573-green Unit suite was binding against real cmdlets that have always
honoured `-ErrorAction`. So the defect was unreachable locally and the green suite was not
merely blind to it -- it was never even in the room.

**48. I wrote a vacuous probe again, and PROBE-0 is why I caught it.** My first before/after probe
reported "BEFORE already throws", which would have killed the whole work item as a non-issue. The
cause was #47: `Get-ADGroup` resolved to the real cmdlet. What saved it was the discipline from
learning #42 -- I added a test asserting the thing under test is what I think it is
(`(Get-Command Get-ADGroup).CommandType -eq 'Function'`). **Every probe needs an
am-I-even-measuring-the-right-object assertion, and it must be a separate failing-visible test,
not a comment.** The tell was PROBE-2 printing `ErrorActionParameterType=ActionPreference` on a
stub that supposedly had a hand-rolled `[object]` one. Read the diagnostic output even when the
test passes -- especially when it passes.

**49. To exercise guarded stubs, force the guards open in a scratch copy -- selectively.** I
generated a modified `ADStubs.ps1` replacing `if (-not (Get-Command X ...))` with `if ($true)`,
but only for the four groups genuinely absent in CI. I deliberately left the `Get-Acl` guard
closed, because `Get-Acl` ships with PowerShell and is present in CI too -- forcing it would have
been unfaithful *and* would have shadowed the real `Get-Acl` with a stub that returns `$null`.
Faithfulness of a simulation is a per-guard judgement, not a global switch.

**50. Two stubs are dead code in every environment.** `Get-Acl` / `Set-Acl` are guarded on a
cmdlet that always exists. They cannot execute locally or in CI. Flagged for Joel rather than
deleted -- removing them is a different decision than the one I was sanctioned to make.

**51. My own confident failure forecast was simply wrong, and controls proved it.** I predicted a
CI-wide red run: advanced functions reject undeclared named arguments where simple functions
absorb them. Actual result under a CI-faithful run: Integration 318/318/0, Unit 1570/1573, and
**zero** `parameter cannot be found` errors. **Parameters I had to add during triage: 0.** The
three Unit failures were not mine -- they reproduced identically in *two* controls (original stubs
forced open; and scratch copy with stubs unforced), which pins them to path-dependence in
`Unit.AdmxImport.Tests.ps1` when run from a scratch location. Without those controls I would have
spent the session "triaging" three failures I did not cause, and would probably have "fixed" a
stub to make them go away. **Run the control before you triage, not after the fix stops working.**

**52. Why the forecast was wrong is more useful than the fact that it was.** The stub signatures
already matched their call sites -- the original author did that part right. The only common
parameter the product passes to AD/GPO cmdlets is `-ErrorAction`, which is exactly the one
`[CmdletBinding()]` now supplies for real. The hand-rolled parameter was not covering for a
signature mismatch; it was purely the thing breaking escalation. That means Option D was a
narrower change than I had priced it as, and the "budget for a red run" caveat can be dropped
from future proposals of the same shape.

**53. Check that a fix does not just invert a broken behaviour.** Before the change,
`-ErrorAction SilentlyContinue` also failed: the probe printed `Write-Error: stub-failure-boom`
to the host because the preference was captured into a variable and dropped. After, `Stop` throws
*and* `SilentlyContinue` genuinely suppresses. I asserted both directions. A fix that made `Stop`
throw but left `SilentlyContinue` noisy would have passed a one-sided proof.

**54. A plain `$Confirm` parameter is fine on an advanced function -- verify, do not assume.**
Seven stubs declare `$Confirm`. I expected `[CmdletBinding()]` to collide with it. It does not:
`-Confirm` only becomes a reserved common parameter under `SupportsShouldProcess`. Confirmed by
`Get-Command` metadata *and* a runtime bind, because metadata alone would not have caught a
binder-level rejection.


---

## Session 2026-09-06 — CI parity (Joel: "run them the same way github PR will")

**55. Pester 5 shares one session state across every container, so `Set-StrictMode` set at
FILE scope leaks into every file discovered after it.** Seven of our 32 test files set
`Set-StrictMode -Version Latest` at file scope. CI uses `Run.Path = "tests"` (one session, all
32 files) and `Integration.Audit.Tests.ps1` is alphabetically first, so CI runs the whole suite
strict. We run locally BY PATH in two separate processes, and in the Unit run the first setter
sits at position 24 of 25 — so locally almost nothing is strict. That single difference produced
64 green-local / red-CI failures. Proven with a 4-file minimal repro in a fresh process:
STRICT=off -> 0 fail, STRICT=on -> 64 fail. **If you are chasing a local/CI gap in a Pester 5
repo, check file-scope StrictMode before anything else.**

**56. `Mock Foo { return $null }` is NOT the same as `Mock Foo { }`.** `return $null` writes a
literal `$null` to the output stream. If the product does not suppress that call's output, the
caller's `$result` becomes a 2-element array `@($null, <real result>)`. Non-strict member
enumeration silently skips the `$null`, so `$result.Executed` works *by accident*; under
StrictMode it throws. Stub a void cmdlet with an empty scriptblock. There are ~38 instances of
`{ return $null }` across tests/ — most are legitimate (the product is checking for a null
return); only the ones standing in for genuinely void cmdlets are wrong. Do not blanket-fix.

**57. `$x = 0` followed by `$script:x++` inside a mock body are two different variables.**
Without StrictMode the `$script:` one starts undefined and increments from `$null`, so the test
passes and nobody notices. With StrictMode every mocked call throws, the product's catch
swallows it, and the assertion reads "expected 1, got 0" — which looks like a product bug and is
not. Found exactly 2 in the repo with a scan for local `= 0` initialisers whose name also appears
as `$script:`. That scan is worth re-running after anyone adds counter-based mocks.

**58. "This property should be absent" cannot be written as `$obj.Prop | Should -BeNullOrEmpty`
under StrictMode.** Use `$obj.PSObject.Properties.Name | Should -Not -Contain 'Prop'`. Same for
`($x | Where-Object {...}).Count` when the filter can match nothing — wrap in `@()`.

**59. `Mock` binds parameters against the MOCKED command's metadata, so a stub with a narrower
signature than the real cmdlet turns a valid product call into a CI-only failure.** Our stubs
lacked `Confirm` on `New-ADGroup`/`Add-ADGroupMember` and `Confirm`+`ChangePasswordAtLogon` on
`New-ADUser`. Locally (RSAT present) the guards keep the stubs undefined and mocks bind against
the real cmdlets, so everything passes. In CI the binding fails, the product's catch swallows it,
and 13 tests report "expected 1 call, got 0". **The failure mode is indistinguishable from a
product bug at the assertion.** Always check the stub signature against the actual call site
before blaming the product.

**60. How to simulate "no RSAT" faithfully — two ways that are WRONG.** (a) Forcing the
`Get-Command` guards open while the real ActiveDirectory module is still importable: the real
module and the in-memory stub module coexist, which never happens on a runner. (b) Removing
`C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules` from `PSModulePath`: that also removes ~96
inbox modules windows-latest *does* have, and manufactured 80 bogus `Unit.Prerequisites`
failures. **The right way:** mirror the inbox module directory with directory junctions
(`mklink /J`, no admin needed), omit only `ActiveDirectory`, point `PSModulePath` at the mirror,
and leave `ADStubs.ps1` completely untouched so its own guards decide. Always print an
environment assertion (`AD=0 LAPS=1 GroupPolicy=1 Pester=present`) before trusting the run —
attempt (b) would have been caught instantly by that one line. See `norsat3.ps1`.

**61. A simulation that produces MORE failures is not automatically a better simulation.**
Attempt (b) above gave 97 failures vs the eventual true answer of 13. I nearly triaged 80
`Unit.Prerequisites` failures that were entirely my own artefact. The tell was the shape: 80
failures in one file, all in a file whose whole job is checking module availability, right after
I removed a pile of modules. **When a probe changes the environment, suspect the probe first.**

**62. Prove a harness change is behaviour-neutral, do not argue it.** For the
`Mock { return $null }` -> `Mock { }` change I ran the file both ways in fresh processes and
compared pass counts AND product warning counts (153/153 and 4/5 warnings, identical). Reasoning
said it was neutral; the A/B is what I would actually show Joel.

**63. `Unit.AdmxImport.Tests.ps1` path-dependence: RULED NOT a CI risk.** Copied the entire
working tree to `%TEMP%\adtm-pathtest`, set cwd there, ran the file: 27/27. It references only
`$PSScriptRoot`. The 3 failures I flagged in a previous session came from a *partial* scratch
copy missing repo fixtures — not from the absolute path. My earlier flag was a false alarm
caused by my own incomplete copy.

**64. The "378-test Manual Integration Tests file" is `Manual.Integration.Tests.xlsx` — an Excel
workbook.** Pester discovers `*.Tests.ps1` only, so CI has never run it and never will. README's
"32 test files" counts the xlsx. Confirmed by enumerating `$result.Containers` from the real
CI-shaped run. Do not re-investigate this.

**65. CI has a coverage gate nobody mentioned.** 80% threshold with `exit 1`. Currently 87.37%
(14579/16686) — passing, but it is a fourth way CI can go red that is invisible locally unless
you enable `CodeCoverage` in your reproduction. My `ci-run.ps1` now reports it explicitly.

**66. Final state this session.** Local by-path Unit 1608/1608/0, Integration 318/318/0;
CI-shaped 1926/1926/0 (both with and without RSAT); lint 0 issues; security 0 Errors; coverage
gate PASS. 36 tests added (35 new in `Unit.AuditReporting.Tests.ps1` + 1 rewritten in
`Unit.OuAclOperations.Tests.ps1`). Zero product files changed.
---

## 2026-09-07 — D8 / FR-007 never-prompt coverage + empty-prompt contract re-point

**Scope: `tests\` only.** 2 tests re-pointed, 12 tests net added. Unit by-path **1608/1608/0**,
Integration by-path **330/330/0**, CI-shaped **1938/1938/0** (32 containers). No commits, no
staging, no product file touched.

**67. A `$script:` assignment made inside a Pester mock body is NOT visible to the `It` that
reads it back.** My first prompt-recorder wrote `$script:SeenBasePrompt = $Prompt` inside
`Mock Read-Host` and the `It` read `$null` — and `Should -BeLike` against `$null` fails loudly,
which is the only reason I caught it. Had the assertion been `Should -Not -Match` or a `-Times 0`
style check it would have passed vacuously forever. The route that works is a **closure**:
`$prompts = [List[string]]::new()` in the `It`, then
`Mock Read-Host { param($Prompt) $prompts.Add($Prompt); ... }.GetNewClosure()`. Mutating a
captured object needs no scope resolution at all. This is the same family as learning #42 — a
probe that "confirms" an expectation without executing the relevant line.

**68. The prompt RECORDER is strictly stronger than `Should -Invoke Read-Host -Times 0`.**
Rogue's technique, and it earns its keep twice: it proves the prompt was never *reached* rather
than that a canned answer was consumed, and when the guarantee breaks the failure message names
the prompt string that appeared. A `-Times 0` assertion tells you a count and nothing else.

**69. The log file never lands on disk in Deploy's integration harness, because
`Write-TierModelLog` is mocked.** My first re-pointed test asserted
`Get-ChildItem -Filter 'Deploy-TierModel-*.log'` in the CWD sandbox and got 0 — while the console
plainly printed `Log file saved: ...\Deploy-TierModel-090726-1206.log`. The observable that
actually exists is the **console echo** (`Logging enabled: <path>`), captured with `6>&1`.
Before asserting on an artifact, check whether the harness mocks away the thing that creates it.

**70. Two branches ending in the same literal are only distinguishable by a side effect.** D8's
explicit-`-Logging` and diagnostics-auto-enabled paths both now resolve to `Deploy-TierModel`.
No output assertion can tell them apart. The **only** observable is whether a prompt happened, so
the anti-collapse test asserts the two prompt counts *against each other* (0 vs 1) in a single
`It`, not each in isolation. Control-proved: collapsing the branches fails 3 Deploy tests and 3
Audit tests.

**71. Keeping the whitespace case was not defensive padding — it is the only test that fails
under an `IsNullOrEmpty` regression.** Control-prove R4 changed exactly
`IsNullOrWhiteSpace` -> `IsNullOrEmpty` in Deploy: the empty-string test stayed **green**, the
whitespace-only test **failed alone**. Anyone arguing the two cases are redundant has the
equivalence backwards — they are equivalent *because of* `IsNullOrWhiteSpace`, which is precisely
what is under test.

**72. Control-prove with eight separate single-property reverts, not one big one.** R1 collapse
Deploy / R2 collapse Audit / R3 restore the throw / R4 IsNullOrEmpty / R5 drop `[default]` from
the prompt text / R6+R7 delete the NON-BLOCKING-3 resolved-base block / R8 restore the Audit
`-OutputFormat` throw. Each failed *only* the tests it should and left the rest green. A revert
that knocks over more tests than expected is a sign the tests are coupled, not a stronger proof —
my own rule, and it held.

**73. The diagnostics hint is not reachable from a successful run.** Deploy prints it only when
`$script:DeploymentBlocked`; Audit only when drift or errors are non-zero. My first hint test used
`Mock New-TierModelOu { throw }` under `-FullDeployment -ConfirmApply` and never reached the tail
at all. `Mock Get-TierModelConfig { throw }` (site L916) is the cheap reachable one, and it fires
*after* the prompt block has resolved `-OutputFileBase` — which is exactly the state
NON-BLOCKING-3 is about. Audit's tail hint is reachable for free because the standard OU mock
returns `DriftCount = 1`.

**74. Coverage of the headline feature went from literally zero to enforced.**
`EnableVerbose` / `EnableDebug` / `LoggingAutoEnabled` appeared **0 times** in `tests\` before
this session. That a 1,926-test suite at 87 % coverage could carry a release's flagship feature
with no test at all is the strongest argument I have seen for "measure the feature, not the
percentage".

**No product defects found.** Rogue's three prompt sites, the D8 seam and the NON-BLOCKING-3
replay all behave exactly as documented; every failure I produced was one I injected.
