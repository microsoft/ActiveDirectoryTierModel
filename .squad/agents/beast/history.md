# beast -- History

## Session 2026-09-04 — Config Validation Wire-In & Scribe Orchestration

**Status:** Scribe logs recorded; prior session work (BUG-020/021/022/023) completed by team

This session's focus: Scribe orchestration and decision archival for the config-validation wire-in session. Beast's prior work (CHANGELOG entries for BUG-020, BUG-021, early BUG-023 tracking) was verified shipped in commit c973611. BUG-022 CHANGELOG correction was flagged as incomplete by Beast but later recovered and completed by Cyclops.

**Key lesson:** Agent self-reports of completion are not sufficient evidence. Cyclops independently verified line numbers and corrected the CHANGELOG entry that Beast reported as done but which never persisted to disk.

---

## Recent Work (2026-09-04)

**Status:** BUG-016 complete — gpoStatus reduced to 4 real values, deploy fails loudly on bad value

### 2026-09-04 — BUG-016: Remove Invented gpoStatus Values, Deploy Fail-Loud

**Branch:** `fix/gpo-silent-skip-and-false-success`  
**Files changed:** `modules/TierModel/public/New-TierModelGpo.ps1`, `modules/TierModel/public/Test-TierModelGPO.ps1`

**What was done:**
- **Deploy side (New-TierModelGpo.ps1 ~L167-205):** Removed `AllEnabled` and `BothSettingsDisabled` from the `switch` lookup. Removed the silent `default { 0 }`. Added an explicit pre-validation block (before the inner `try`) that throws for any unrecognized value — the throw propagates to the **outer** catch (per-GPO failure accounting: red ERROR console line, `$failed++`, `$converged = $false`) not the inner catch (which is warning-only and counts the GPO as executed). Error message names the GPO, the bad value, and lists all 4 valid values.
- **Audit side (Test-TierModelGPO.ps1 ~L166-189):** Reduced `$validGpoStatus` ordered hashtable from 6 entries to 4. Updated the comment to document the AD-flags-vs-enum-ordinal trap. Removed dead `BothSettingsDisabled` reference from the `GPO Enabled State` advisory string comparison.
- **Both sides:** Comments updated to state these are AD `flags` attribute values (not .NET GpoStatus enum ordinals), to record the empirically verified mapping from Joel's 2026-09-04 lab run, and to explain why the BUG-016 removals were made.
- **Flags values:** Unchanged. AllSettingsEnabled=0, UserSettingsDisabled=1, ComputerSettingsDisabled=2, AllSettingsDisabled=3 (AD flags attribute, not enum ordinals).
- **PSScriptAnalyzer:** 0 errors, 0 new warnings. Pre-existing Write-Host and BOM warnings unchanged.
- **Unit tests:** 1567 passed / 6 failed. All 6 failures are expected (tests encode old wrong behaviour). Wolverine report produced (see below).

**Wolverine test report (6 expected failures to fix):**

| File | Line | Test name | Why it fails | Required new expectation |
|---|---|---|---|---|
| Unit.GpoOperations.Tests.ps1 | 494 | "Should validate GPO status configuration" | Uses `gpoStatus = "AllEnabled"` (invented value; now unrecognized → Fail, not Pass) | Change `gpoStatus` to `"AllSettingsEnabled"` and keep `Status = 'Pass'` |
| Unit.GpoOperations.Tests.ps1 | 1736 | "Should call Set-ADObject when mode is 'create' and gpoStatus is AllEnabled" | `"AllEnabled"` is now invalid → pre-validation throws → Set-ADObject never called | Change `gpoStatus` to `"AllSettingsEnabled"`; test should pass with `Executed = 1` and `Set-ADObject` called once with `flags = 0` |
| Unit.GpoOperations.Tests.ps1 | 1767 | "Should pass flag=3 for BothSettingsDisabled" | `"BothSettingsDisabled"` is now invalid → pre-validation throws → Set-ADObject never called | Change `gpoStatus` to `"AllSettingsDisabled"` and expect `flags = 3` |
| Unit.GpoOperations.Tests.ps1 | 1777 | "Should default to flag=0 for unrecognized gpoStatus value" | The silent default is gone; unrecognized value now throws → GPO counted as `Failed = 1`, not `Executed = 1` | Rewrite: assert `result.Failed -eq 1`, `result.Executed -eq 0`, `result.Converged -eq $false`, and that error message matches the GPO name + bad value |
| Unit.GpoOperations.Tests.ps1 | 1803 | "Should log a warning and still mark GPO as executed when Set-ADObject throws" | Uses `gpoStatus = "AllEnabled"` (now invalid) → pre-validation throws before Set-ADObject is even mocked → GPO is Failed, not Executed | Change `gpoStatus` to `"AllSettingsEnabled"` (or any valid value) so the mock is reached; the original non-fatal-ADObject-throw behaviour still applies |
| Unit.GpoOperations.Tests.ps1 | 2533 | "Passes status check for BothSettingsDisabled (flags=3)" | `"BothSettingsDisabled"` removed from `$validGpoStatus` → `$expectedFlags` is `$null` → status check Fails, not Passes | Change `gpoStatus` to `"AllSettingsDisabled"` (flags=3, same value) |

## Recent Work (2026-09-02)

**Status:** Dot-source seam delivery complete; module v2.0.0 ready for release

### 2026-09-02 — Session Orchestration: Decisions Archived, v2.0.0 Prepared
- Dot-source guard committed in optional/Update-TierModelMembership.ps1 (no version bump — v1.7.2 unchanged)
- Wolverine's 107-test suite integrated; Membership script coverage 60.18%
- Module version bumped: 1.7.2 → 2.0.0 (Authentication Policy Silos release)
- PR #50 open (Closes #20) on feature/auth-silos; awaits merge to main
- Decisions archive: 12 old entries (pre-2026-08-26) archived; 1 inbox decision merged
- v2.0.0-rc1 tag pushed; v2.0.0 release tag to follow post-merge
- .squad files committed (no deliverable changes)


---

## Session 2026-09-05 — Known-bugs register merge (docs\ duplicate folded into .research\)

**Task:** Merge the coordinator's `docs\known-bugs.md` (30 KB, BUG-019..038) into the authoritative,
git-ignored `.research\known-bugs.md`, then delete the duplicate. `docs\` publishes to GitHub Pages
and Joel requires personal approval for any new file there.

**Headline finding — the register was stale on three bugs.** I did not trust the source file's own
status column; I verified each against source. BUG-034, BUG-037 and BUG-038 were all carried as
open/contradictory but are **fixed in the working tree**:
- BUG-034: `Audit-TierModel.ps1` L350-400 normaliser already honours `PolicyName`, `SiloName`,
  `Issues` and `Status`-as-Type-fallback, with compliant verdicts matched exactly (not by wildcard).
- BUG-037: `Get-TierModelGpoFd.ps1` L220-230 catch now records + warns and plans NO action, instead
  of fabricating a `Risk = High` LinkGPO.
- BUG-038: all four sites carry `$inheritedObjectTypeUnresolved` and fail closed; the write path
  now throws rather than warning-and-proceeding.

Result: **0 open numbered defects**, 16 fixed-but-not-yet-in-CHANGELOG (BUG-019 + BUG-024..038).
The coordinator's assumed "18 fixed of 20" was wrong; it is 20 of 20.

**Independent AST verification of BUG-019/BUG-035.** Whole-repo AST sweep (excl. `tests\`): product
code has ZERO AD/GroupPolicy reads without explicit `-ErrorAction` (243 Stop / 78 SilentlyContinue
/ 0 none). All 102 remaining bare sites are `.research\` PoC and lab scripts — not shipped.

**Reconciled the empty-catch numbers that had been wrong twice.** My AST sweep of entry scripts +
modules reproduces the ORIGINAL 66/28/38 exactly, so Wolverine's "102 not 66" is not a correction of
the same measure — it is a DIFFERENT population. They reconcile perfectly:
- 66 syntactically-empty `catch {}` = 36 documented (28 in-catch + 8 in the enclosing try) + 30 undocumented
- 118 catch clauses whose statements emit nothing = 46 that append to `$planErrors`/`$warnings` + **72 lossy**
- 30 + 72 = **102** = the real information-loss population
My sweep independently lands on 72 (109 emitting-nothing minus 37 appending) — same answer via a
cruder emit-regex. Net: un-excluding `PSAvoidUsingEmptyCatchBlock` flags 66 and MISSES 72.

**Confirmed the AuthPolicy(6)/AuthSilo(5) cluster is BENIGN.** Read all 11: every one is
`try { $x = $obj.Prop } catch {}` — the StrictMode optional-attribute probing idiom, where `$null`
is the correct handled answer. Listing them as a "notable concentration" of silent failures was
true-about-the-count but misleading-about-the-risk. Corrected in the merged file.

**Lessons:**
1. **A defect register goes stale faster than the code.** Three of twenty entries were wrong. Never
   quote a bug's status without re-verifying it against source.
2. **State the population before quoting a count.** "66" and "102" were both correct and both
   describe different sets. A number without its population is not evidence — this cost the team two
   rounds of confusion.
3. **A source file can contradict itself.** `docs\known-bugs.md` marked BUG-034 fixed in its summary
   table while filing it under `## Open defects` saying "It must still be closed". The table was
   right; the section heading was stale. Derive status from the code, not from either.
4. **`-ErrorAction Stop` is necessary, never sufficient** (BUG-035, BUG-038). A successful read
   returning a blank value is not an error and no error-action setting can see it. Every hardened
   read needs a value guard too. This is now working rule 11.

**Constraints honoured:** nothing staged or committed; `CHANGELOG.md` never opened for writing (read
only, to confirm it contains BUG-001..018 + BUG-020..023); no new file under `docs\`; did not touch
`specs\`, `docs\design-scope-publish-guard.md` (Storm) or `tests\ADStubs.ps1` (Wolverine); every
assertion of a cause for the original two-GPO customer incident neutralised — the merged file now
states the root cause is formally CLOSED as UNKNOWN and explicitly distinguishes "same shape" from
"established cause".

---

## Session 2026-09-05 (evening) — Register update: BUG-039..041 fixed, BUG-042/043 open

**Task:** Record three lab-found, Rogue-fixed defects, one new open defect, one by-design ruling,
and repair the "Next free ID" bookkeeping line in `.research\known-bugs.md`.

**Result: 2 open (BUG-042, BUG-043), 41 fixed, next free ID 044.** The coordinator briefed "next
free 043"; verifying BUG-042's severity turned up a fourth defect, so 043 was consumed.

**I verified every claim rather than trusting the brief, and every one held**, including provenance:
BUG-039/040/041 are all present at `04ab664`, so none is feature-introduced. Confirmed
`Audit-TierModel.ps1:2493` `-join [Environment]::NewLine`; five `Identifier` diff pairs in
`Test-TierModelOuAcl.ps1`; the `$totalDrift` override deleted (present at `04ab664:1128`);
`Test-SummaryKey`/`Get-SummaryCount` as pure additions at `:1654`/`:1660`; `Deploy-TierModel.ps1`
`:818`/`:840` both `exit 0`. The brief's "three MSA-family sites left on the raw path" was right but
under-specified: they are in three *sibling* files (`Test-TierModelMsaAcl.ps1:129`,
`Gmsa:129`, `Dmsa:139`), not in `Test-TierModelOuAcl.ps1` — a grep of the fixed file alone makes the
fix look complete when four deliberate exceptions exist. Recorded with file+line.

**NEW DEFECT — BUG-043, found by applying the very insight the task asked me to evaluate.** Rule 14
says compare a summary against the body *within one artifact*. Doing that to the scope branches:
`-OuAclsOnly`, `-GposOnly` and the standalone `-Include*` path publish `DriftCount` but never
`MissingCount`/`MismatchCount`, so a saved report reads `Drift 8 / Missing 0 / Mismatch 0` over 8
findings. Pre-existing. This **is** the "instance eight" BUG-041 was mistaken for, and unlike
BUG-041 it sits in a scope-branch publish step — so spec 007's guard aims at it correctly.

**Lessons:**
1. **Rule 1 has a blind spot and it took a real defect to expose it.** "Verify the artifact, not the
   console" only detects a *disagreement*. When both renderings read the same variables they fail
   together and agree. BUG-041 was invisible to seven-defects-worth of established technique.
   Intra-artifact reconciliation (does the header sum to the body?) is now rule 14 — and it paid for
   itself within the hour by finding BUG-043.
2. **A self-contradicting object localises the fault to the producer** (rule 15). Rogue's BUG-040
   proof — resolved DN in `ExpectedValue`/`Details`, placeholder in `Identifier`, same object — is
   the cheapest possible discriminator between "upstream resolution failed" and "one construction
   site read the wrong variable", and it prevented a second expansion pass that would have hidden a
   real fault had one existed.
3. **A moved test count is evidence about the diagnosis, not a fixture to adjust** (rule 16).
   Rogue's first BUG-041 fix went 318→316; the regression *was* the proof that key-renaming had only
   changed which producer family got discarded.
4. **Deliberate non-changes must be written down next to the changes** (rule 17). Four raw-path
   sites kept on purpose, and an override deleted rather than widened, both read as incomplete work.
5. **Bookkeeping must not be shaped like data.** "Next free ID is BUG-039" matched a `BUG-\d{3}`
   sweep and inflated the pending-migration count to 17 against a true 16. Reworded to "Next free
   ID: 044" with no prefix; a census now returns exactly the 43 real IDs.
6. **Severity is not uniform across a batch found in one run.** Cyclops's "rendering, not loss"
   verdict was correct for BUG-039/040 and wrong for BUG-041, which feeds the NUnit `failures=`
   attribute. Three defects surfacing together says nothing about their shared impact — and here
   they even shared a *producer* (the same 8 OU-ACL objects), which is exactly the coincidence that
   makes a batch look homogeneous when it is not.

**Constraints honoured:** nothing staged or committed; `CHANGELOG.md` never opened; only
`.research\known-bugs.md` edited; no product code, `tests\`, `specs\`, `docs\` touched; no cause
asserted for the two-GPO customer incident; test suites not re-run; temp files removed.

---

## Session 2026-09-05 (end of day) — BUG-044 recorded, register closed to 0 open, restart card written

**Task:** End-of-day register pass before Joel's 21:00 commit. Record Rogue's landed BUG-044 fix,
Joel's ruling on the GPO/WinLapsDecryptor arithmetic residual, the known bug-encoding test failure,
and write a cold-start "Where we are" section. Sole file edited: `.research\known-bugs.md`.

**Result: 44 total IDs, 44 fixed, 0 OPEN, next free ID 045.** Pending CHANGELOG migration rose from
19 to 22 entries (BUG-019 + BUG-024..044).

**I re-verified status against source rather than trusting the brief or Rogue's self-report
(working rule 13), and all three flips held:**
- BUG-042 fixed — zero surviving `Type = 'Drift'` literals in `Audit-TierModel.ps1` or the module;
  the only `-eq 'Drift'` text left is explanatory comments at `:1099` and `:2000`.
- BUG-043 fixed — all three offending branches now publish the breakdown: `-OuAclsOnly` `:2188-2189`,
  `-GposOnly` `:2237-2238` (both reads StrictMode-guarded), standalone `-Include*` `:2575-2576`.
- BUG-044 fixed — consolidated body routed through `ConvertTo-TierModelDriftFinding` with an
  `if/elseif` double-count guard.

**Nothing in Rogue's decision record contradicted the coordinator's summary.** Every headline
checked out against the record and against source. Two things his record supplied that the summary
did not: the `Admx` sweep row conflated `ResourceType` with `Type`, and the Phase 1b
`Invoke-CanonicalAclAudit` console double-print is a real, deliberate, visible side effect that
needed naming for Joel.

**Timestamp sweep: no forward-dated stamps found.** Scanned all of `.squad\` and `.research\` for
`2026-09-05` times after 20:05 and for any `2026-09-06`+ date. Latest stamp anywhere is 19:42
(Rogue's post-correction verification re-run). The drift the coordinator described had already been
corrected before I arrived. Nothing to fix.

**Lessons — three new working rules earned, now rules 18/19/20 in the register:**
1. **Rule 19 is the one I would have missed.** BUG-044 was *created* by BUG-042 several hours
   earlier — removing the last producer of a string literal turned a downstream whitelist into a
   silent deny-all, and **nothing failed**. A filter matching nothing raises no error and returns a
   confident, empty, wrong answer. When deleting a label/key/value, grep every **consumer** and
   prove each still has a population.
2. **Rule 20 is a correction to my own work.** My producer sweep matched string-literal
   `Type = '...'` and reported ten producers BLANK. Six were *not in the report population at all*;
   four were genuinely affected and merely `Status`-shaped. **A sweep reports what it can match, not
   what is true** — rule 12 (state the population) applied to code instead of counts. I recorded the
   six/four split explicitly in the register precisely so nobody re-derives it.
3. **Rule 18 — StrictMode.** Three bites in one day (BUG-032, BUG-043's 318→316, BUG-044). The
   failure always lands at report time on a **drifted** run: the run that most needs an artifact is
   the one that produces none. A nice-to-have must never be able to take the report down.
4. **A by-design item needs its DISCRIMINATOR written down, not just its ruling.** The GPO/
   WinLapsDecryptor header that does not sum looks identical to BUG-041 and BUG-043 — both real,
   both same shape, both same file, same day. I recorded the one-line test that separates them:
   *those were a breakdown WRONG or MISSING; this is a breakdown RIGHT and INCOMPLETE BY
   DEFINITION.* A ruling without a discriminator still costs the next person a triage cycle.
5. **Zero open is a statement about knowledge, not about health.** Six defects came out of one seam
   today, three from inspection alone. I wrote that caveat directly under the zero so the number
   cannot be quoted as "the seam is clean", and left the freeze-scope question explicitly as Joel's.

**Constraints honoured:** nothing staged, nothing committed (`git diff --cached` empty);
`CHANGELOG.md` never opened; only `.research\known-bugs.md` edited; no product code, `tests\`,
`specs\` or `docs\` touched; test suites NOT re-run (baseline quoted from Rogue's 19:42
verification); no cause asserted for the two-GPO customer incident; no scratch files created; repo
root holds only its 13 legitimate tracked files, and the only untracked paths are Storm's two spec
folders.

---

## Session 2026-09-07 (morning) — BUG-045 / BUG-046 registered from Joel's live lab; provenance brief overruled

**Task:** Register (NOT fix) the empty-answer-at-the-filename-prompt defect Joel hit in the lab.
Sole file edited: `.research\known-bugs.md`. Decision record:
`.squad\decisions\inbox\beast-bug045-empty-prompt.md`.

**Result: 46 total IDs, 44 fixed, 2 OPEN (BUG-045, BUG-046), next free ID 047.** Pending CHANGELOG
migration unchanged at 22 — open defects do not belong in the fixed-pending section.

**HEADLINE — I overruled the coordinator's provenance verdict, and the evidence is unambiguous.**
The brief asserted all three sites are pre-existing and none caused by the `-EnableVerbose` /
`-EnableDebug` work. Two of three hold. The third does not:
- Deploy `-Logging` (Joel's actual repro) — **pre-existing**, `04ab664:233-236`; the diff shows the
  throw line changing **indentation only** as it moved into the new `else`.
- Audit `-OutputFormat` — **pre-existing**, `04ab664:221-224` verbatim.
- Audit `-Logging` — **FEATURE-INTRODUCED.** `Audit-TierModel.ps1` at `04ab664` contains **zero
  occurrences of the string `Logging`**. No switch, no prompt, no throw. The entire block is a `+`
  addition. This release did not reveal that instance — it **wrote** it, porting Deploy's bad shape
  across alongside the good D8 branch.

Knock-on: the restart card's *"Only BUG-024 and BUG-025 are feature-introduced"* was stale and was
corrected in place. Feature-introduced set is now BUG-024, BUG-025, BUG-045 (Audit site only).

**Judgement calls made:**
- **Sites 1+2 = one ID (BUG-045); site 3 = its own ID (BUG-046).** Not because site 3 is a different
  failure mode — it is the same one — but because **its fix is not free**. Sites 1/2 fall back to a
  default that already exists two lines away and was already approved under D8. Site 3 has no
  auto-enable branch, so no default has ever been chosen and somebody must decide one. A free repair
  and a design decision must not share a status flag.
- **Mixed provenance recorded PER SITE inside BUG-045**, not flattened to one word for the column's
  convenience. Flagged in the entry so it is not later "tidied".
- **Severity High** for BUG-045: hard stop rather than degradation; trigger is the single most
  likely operator action in existence (Enter at an unlabelled prompt); invocation is documented and
  reasonable. Not Critical — fails loudly before any AD change, one-parameter workaround, cannot
  corrupt an estate or produce a false verdict.

**Lessons — new working rules:**
1. **"Pre-existing" is a property of a SITE, not of a defect.** A defect with N sites can have N
   different provenances. Answering the question once for the bug is how a release quietly takes
   credit for not causing something it half-caused. This is the sharpest version yet of rule 12
   (state the population before quoting a count) — applied to provenance instead of counts.
2. **`git show <sha>:<file> | grep <symptom>` is not enough; grep the FEATURE NAME too.** Searching
   `04ab664:Audit-TierModel.ps1` for the throw string returned the `-OutputFormat` hit and looked
   like a clean confirmation. Only searching for `Logging` *at all* — and getting **zero** hits —
   exposed that the whole parameter was new. **An absent feature returns a plausible partial match
   from its sibling.** Always establish that the feature existed before concluding its bug did.
3. **Correct code adjacent to broken code is the strongest possible fix instruction — and the
   strongest possible trap.** The D8 auto-enable branch already does the right thing three lines
   above the throw. That makes the fix nearly free, and makes "just merge the two branches, they
   share a default now" nearly irresistible — which would destroy FR-007's explicit-vs-auto
   distinction and the lab-proven 28/28 never-prompt guarantee. **Recording the fix without
   recording the merge prohibition would have been worse than recording neither.**
4. **A spec can be wrong about history.** FR-007 calls the explicit prompt *"existing shipped
   behaviour, preserved unchanged, on both scripts"*. For Audit there was no existing behaviour to
   preserve. Passed to Storm; `specs\` is not mine to edit.
5. **Register a defect the operator has NOT hit yet, prominently.** BUG-046 is invisible until the
   first `-OutputFormat` run without a base name. The cost of registering it now is one heading; the
   cost of a customer finding it is the incident this whole project exists because of.

**Constraints honoured:** nothing staged, nothing committed (`git diff --cached` empty); no product
code touched (`Deploy-TierModel.ps1`, `Audit-TierModel.ps1`, `modules\`, `optional\` read-only);
`tests\`, `specs\`, `docs\` untouched; `CHANGELOG.md` never opened (locked out); no test suites run —
Joel is live in this tree; no scratch files created; BUG numbers confined to
`.research\known-bugs.md` (documentation, not code — nothing stripped); no cause asserted for the
two-GPO customer incident; repo root verified at its 13 legitimate tracked files, zero strays.

---

## Session 2026-09-07 (12:35) — Register: BUG-045/046 closed, BUG-047/048/049 opened, working rule 21

**Task:** Three register jobs in `.research\known-bugs.md` (my file alone). Nothing staged, nothing
committed, `CHANGELOG.md` never opened, root unchanged at 13 files, no scratch file inside the repo.

**Totals: 46 IDs / 44 fixed / 2 open / next free 047  →  49 IDs / 46 fixed / 0 open / 3 in progress
/ next free 050.** Fixed-but-not-yet-in-CHANGELOG 22 → 24.

### Job 1 — BUG-045/046 closed as FIXED

Recorded Rogue's fix at all three prompt sites (default + default shown in prompt + resolved value
echoed), my own verification (zero residual `cannot be empty when`, BOM `EF BB BF` intact on both
scripts), and BUG-046's design decision **named with its decider** — Joel chose `Audit-TierModel` —
because "record who chose the default" was the stated precondition for ever folding it into 045.

Two things recorded prominently because they are method, not status:
- **Rogue proved the D8 never-prompt guarantee instead of asserting it** — replaced `Read-Host` with
  a recorder of prompts *requested*, ran the real scripts in child processes. That inverts the
  observation: "was the prompt reached?" not "did the run finish?". 0 prompts on
  `-EnableVerbose`/`-EnableDebug`; exactly 1 each on explicit `-Logging`/`-OutputFormat`, Enter
  accepted, no throw. Both halves of the spec evidenced by one instrument.
- **THE REAL LESSON: the feature the release is named for had ZERO test coverage.** I confirmed
  independently — `EnableVerbose`=0, `EnableDebug`=0, `LoggingAutoEnabled`=0 across every `.ps1`
  under `tests\`. 1,926 tests at 87.37% coverage, not one naming the feature. **Coverage measures
  lines executed, not behaviours asserted; a high figure over a suite that never names your feature
  says nothing about your feature.** Wolverine closed it (12 tests, 1938/1938/0) and control-proved
  the guard by making the maintainer's plausible edit (`if ($script:LoggingAutoEnabled)` →
  `if ($false)`): 6 tests fail. That edit previously failed nothing.

### Job 2 — the ID split, and what the "colour bug" actually was

**I split it three ways.** Same principle as 045/046 and it held up: a free repair and a decision
must not share a status flag, because a flag reads as one fact about one unit of work. The practical
test for whether a split is real — **do they fail independently?** — passes: fixing any one leaves
the other two live.

- **BUG-047 colour** — free, unconditional, no ruling, changes no number.
- **BUG-048 labels** — needed Joel's ruling (`MissingAuditRule`, *not* `MissingAcl`: SACL audit
  rules are not DACL ACLs) and is booby-trapped both ways.
- **BUG-049 counter** — different class, different severity, changes audit verdicts.

**BUG-049 is the most severe entry in the register and I argued it rather than asserting it.** Every
other defect here produced a wrong artifact or refused to run — both *visible*. This one says
`Drift: 0` above real, itemised drift on LAPS ACLs, MSA/gMSA/dMSA delegation, domain audit rules,
auth policies and silos: **it tells the operator the estate is clean when it is not**, on exactly the
surfaces the Tier Model protects. Cause: `:1884` sums four hard-coded key names and
`Get-SafePropertyValue` (`:1632`) collapses absent to zero, so **a missing key and a clean estate
render identically**; the totals loop near `:1714` uses a different key set again. Fourth appearance
of the BUG-039/040/041 shape — exact-name matching across producers with no shared vocabulary.

**I upgraded Trap B from a warning into a proof.** At
`04ab664:modules/.../Test-TierModelAuditRule.ps1:177-185` the producer emits `Type='AuditRight'`
**once per right, pass and fail alike** — the verdict lives in `Status`, never in `Type`. So a
blanket rename is not *risky*, it is **guaranteed** to mark passing rights as missing; the relabel
must be conditional on `Status -eq 'Fail'`. That also explains Joel's 9-finding section. Bonus for
the implementer: the `AuditRight` object has **no `Details`** while its `MissingAuditRule` sibling
does, and the renderer interpolates `$($_.Details)` — working rule 18's exact failure mode, at
report time, on a drifted run.

Trap A recorded as the general hazard it is: **WinLaps Decryptor's `Errors: 6` is the only correct
counter in the audit, and it is correct only because two faults cancel.** Fix half of a compensating
pair and you regress.

### Provenance — Joel called the `-Include*` parameters "recent". They are not.

All three defects **PRE-EXIST `04ab664`**, evidenced not recalled. Method: extracted
`git show 04ab664:Audit-TierModel.ps1` to a path **outside the repo** (Rogue is mid-edit; a live read
can return a torn view), then `ReadAllText` + `[regex]::Matches`.

- All six switches in the `param()` block; all eight section `Type` literals present.
- The mis-colouring ternary present **4×** (L377/438/499/1273) — fixing only the one Joel hit leaves
  three copies.
- The four-key drift sum verbatim at L1234-1237; `$entityErrors` at L1239-1250; and the totals loop
  at L1100-1103 using a **different** key set — **the divergence itself is pre-existing.**

**The trap I walked into and out of:** `-IncludeAuthPolicies` and `-IncludeAuditRules` both return
**zero** — because **they do not exist under those names**. Auth Policies *and* Silos are gated by
`-IncludeAuthSilos`; audit rules by `-EnableAuditing`. Taking those zeros at face value would have
produced exactly the wrong provenance answer. My own absent-feature warning, met head-on.

One genuinely new thing found: the Trap B comment at `Audit-TierModel.ps1:345-346` is **not**
pre-existing (`AuditRight` appears 0× in that file at `04ab664`). The producer is old; the warning
about it is new — so don't read the comment as evidence the guard is battle-tested here.

### Job 3 — working rule 21, attributed correctly

**"When you report a ZERO or an ABSENCE, state the population and the enumeration rule beside it."**
Rule 12 says a count needs its population; 21 is the sharper case — **a zero looks identical whether
your enumeration was right or wrong, so a wrong population hides its own error perfectly.**

The false "0 BUG- references in product code" was **mine**, asserted in Rogue's brief from a check
scoped only to the two entry scripts. **Rogue caught it.** I recorded it that way round deliberately:
a rule about honest enumeration that misattributes its own origin undercuts itself. The enumeration
that produced the wrong zero was by **file shape** (cmdlet-style `public\*.ps1` + root + optional =
**84**), structurally blind to `TierModel.psm1`/`TierModel.psd1` — which is where the two surviving
violations were.

**Reusable fact, verified by direct enumeration and now in the file: the product surface is 86** —
2 root `*-TierModel.ps1` + 82 under `modules\` (80 `public\*.ps1` + `.psm1` + `.psd1`) + 2 under
`optional\`. **"84 files, 0 hits" is falsifiable on sight against a repo with 86. A bare "0" is not.**

### Lessons for me

1. **A split is real only if the parts fail independently.** That test is cheaper and more honest
   than arguing about severity, and it justified three IDs where Joel reported one bug.
2. **Upgrade a trap from a warning to a proof whenever the producer is readable.** "Could mark
   passing findings as missing" is advice a hurried implementer discounts; "emits on every pass, the
   verdict is in `Status`" is a constraint they cannot.
3. **A compensating pair is a landmine dressed as a working feature.** The only correct counter in
   the audit was correct by accident. Look for cancelling faults wherever one number is right and its
   neighbours are wrong.
4. **When a file is being edited by someone else, git is the safe reader.** `git show <commit>:<path>`
   to a scratch path outside the repo gave me a stable baseline and left no stray file behind.
5. **My zero was wrong because my population was unstated.** I asserted it, Rogue disproved it. Rule
   21 exists because I earned it, and it is written with my name on the error.

---

## Session 2026-09-07 (13:05) — known-bugs.md reduced to an open-bugs-only work queue

**Joel:** *"remove everything from known-bugs.md except the current bugs we have to fix. I dont want
this file to keep a history."* It is about to become the team's **work queue**, not a record — he
reads it and works from it while we squash the rest of v2.1.0.

**Preserve first, then prune.** `.research\` is in `.git/info/exclude:23`, so `known-bugs.md` has
**never** been under version control: no `git show`, no reflog, no recovery. Deleting from it is
permanent. So the archive was written and **verified** before a single line was cut, and it is a
**full copy** of the file rather than a selective one — selecting what to keep is exactly where
this kind of job loses something nobody notices for a month.

- **`.research\known-bugs-archive.md` — 129,552 bytes, 2,139 lines.** All 46 fixed bugs with causes,
  provenance, fixes and evidence; the 21 working rules; the "By design — do not re-file" rulings;
  the restart cards; the release rule.
- **`.research\known-bugs.md` — 9,932 bytes, 183 lines.** Count at the top, three open bugs, nothing
  else. **127,736 → 9,932 bytes, a 92% cut.**

**The archive's header states its concrete job:** it is the raw material for the v2.1.0 **PR
description**. Per D15 the per-bug detail goes in the PR and **not** into `CHANGELOG.md`, and that
PR has not been written yet — so if the fixed entries had simply been deleted, the PR's source
material would have gone with them. That is the specific loss the safeguard prevented.

**Ordering — consequence, not ID order.** BUG-049 first (says `Drift: 0` over real drift — tells the
operator the estate is clean when it is not), then BUG-048 (labels), then BUG-047 (colour). Joel
works top-down, so the order *is* the recommendation.

**Stated at the top, because he asked what still needs someone:** open **3**, unassigned **0**, all
three with Rogue. A count is only useful next to the answer to "does anything need me?".

**Carried forward the three things a reader of a pruned file cannot infer:** that BUG-048 and
BUG-049 must land **together** (Trap A — WinLaps Decryptor's `Errors: 6` is the only correct counter
in the audit and is correct only because two faults cancel); that the BUG-047 ternary exists in
**four** copies, so fixing the reported site leaves three; and that `-IncludeAuthPolicies` /
`-IncludeAuditRules` **do not exist** (the real gates are `-IncludeAuthSilos` and `-EnableAuditing`),
so a sweep for those names returns a misleading zero.

**Flagged to Joel rather than second-guessed.** Cutting the "By design — do not re-file" section
removes the only thing stopping the cancelled-deploy `exit 0` and the GPO/WinLapsDecryptor drift
arithmetic being re-filed a third time, and the working rules were live guidance. **The instruction
was clear, so both were archived as told and the concern was raised in the summary** — a one-line
pointer to the archive is in the new file's header so the trail is not lost.

### Lessons

1. **"No git history" changes the risk class of a delete.** For a tracked file, pruning is reversible
   and an archive is bureaucracy. For this one it is the only copy. **Check whether a file is
   tracked before you decide how careful to be** — the answer changes the job.
2. **Archive the whole file, not the parts you judge worth keeping.** The selection step is where the
   loss happens, and it is free to skip.
3. **A work queue is a different artifact from a register**, and the difference is ordering and
   assignment, not length. A register is ordered by ID because it is a record; a queue is ordered by
   consequence because someone works down it.
4. **When you prune, carry forward the constraints, not just the descriptions.** "These two must land
   together" is invisible in a per-bug summary and is the sort of thing that gets rediscovered by
   shipping a regression.
5. **Raise a concern and comply anyway.** Joel's instruction was unambiguous; the right move was to
   do it, say what it costs, and let him decide — not to hedge by half-keeping the sections.

---

## Session 2026-09-07 (12:40) — Refinement: by-design rulings stay live, 21 working rules promoted to a skill

Joel ruled on the two items I flagged at 13:05. Both reversals of my archive-everything pass.

**1. "By design — do not re-file" restored to the LIVE `known-bugs.md`**, trimmed from ~95 lines of
narrative to the two rulings and the reason each is not a bug. **Both of Joel's rulings kept
verbatim**, including his own words on the deploy exit code — a ruling paraphrased is a ruling
re-litigated. Kept the discriminator sentence, because that is the line that actually prevents the
re-file: *BUG-041/043 were a breakdown that was wrong or missing; this is a breakdown that is right
and incomplete by definition.* Also kept the expiry condition on the exit-code ruling (a `-Force` /
`-NonInteractive` switch would void it), since a ruling with an unstated premise outlives its
premise. Live file structure is now: **count → 3 open bugs → by design.**

**2. The working rules became `.squad/skills/verification-discipline/SKILL.md`** — 15,952 bytes,
following `.squad/templates/skill.md` exactly (Context / Patterns / Examples / Anti-Patterns +
frontmatter with `confidence`). Named for the technique, not the history.

**There are 21 rules, not 20.** Joel's instruction said 20; I added rule 21 (state the population
and enumeration rule beside any zero) earlier the same day, so his count was one edition stale. **I
moved all 21 and said so rather than quietly moving 20 and leaving one behind** — which would have
orphaned the newest and least-embedded rule in an archive nobody reads.

**Transfer was mechanical, not retyped.** I extracted the rules block to a scratch file outside the
repo, inserted it by variable, then asserted `$skill.Contains($orig)` → **True**, with all numbers
1-21 present. "Verbatim" is a claim like any other and deserves a check that could fail; retyping
21 rules and eyeballing them is exactly how a citation goes missing.

**Confidence: high** — Joel's read, and I agree, but I set it on my own evidence rather than
deferring: ~46 real defects, several rules independently re-derived by different agents, and rules
14, 16 and 19 each went on to find *further* bugs after being written. That last point is the real
argument — a rule that has made a novel prediction is in a different class from one that merely
describes what happened.

**Nothing is superseded.** I checked specifically, because "say so, do not silently drop" was the
instruction. Rule 1 is *limited* by rule 14 — but rule 1 already carries that limit in its own text
("this only detects a disagreement, see rule 14"), which is a refinement, not a contradiction. No
rule has been falsified.

### ⚠️ The finding Joel needs and did not expect

**He predicted the new skill would show in `git status` as new work. It does not.**
`.git/info/exclude:9` excludes `.squad/`, and `git check-ignore` confirms it matches
`.squad/skills/verification-discipline/SKILL.md`. The 131 existing `.squad` files are versioned only
because they were **already tracked** before that rule applied — exclude never affects tracked
paths, which is the half of the rule he had right; it does fully hide **new** ones, which is the
half that bites here.

**Consequence: the skill is in exactly the same unprotected position as `known-bugs.md` was** — no
history, no recovery, invisible to `git status`, and it will be silently missed by any "commit
everything that changed" pass. It needs `git add -f` to be versioned. I did not run it: staging is
his, and unstaged-and-flagged beats staged-and-unmentioned.

### Lessons

1. **When an instruction's count disagrees with the artifact, the artifact is newer.** "20 rules"
   was true this morning. Report the discrepancy and act on the artifact.
2. **Verify a verbatim copy with a containment assertion.** "Verbatim" is a factual claim; make it
   falsifiable (rule 21 applied to my own work).
3. **A ruling must be stored with its premise and its expiry.** The exit-code ruling is only sound
   while deploys stay interactive; unstated, that premise silently expires.
4. **`.gitignore` semantics differ for tracked vs untracked paths, and the difference is invisible
   until it costs you a file.** Existing files staying versioned does **not** imply new siblings
   will be. Always `git check-ignore` a new file in an excluded tree.
5. **Storage location determines whether guidance is used.** These rules existed for days and BUG-044
   still shipped, because rule 19 was in a file nobody had open. `.squad/skills/` is read at spawn —
   the move is the fix, not the filing.

---

## Session 2026-09-07 (15:36) — BUG-050/051/052 registered; 047/048/049 closed out

**Three new IDs, three closures, live queue back to 2 open.**

| | Before | After |
|---|---:|---:|
| Open | 3 (047, 048, 049) | **2** (050, 052) |
| Unassigned | 0 | **2** — and that is the number Joel needs |
| Next free ID | 050 | **053** |

**ID assignment:** BUG-050 = Joel's missing UPN (open, unassigned); BUG-051 = the `Warning`→`[Error]`
remap in `Invoke-OuAclAudit` (already fixed, numbered for the record); BUG-052 = empty scope reads as
clean (open, blocked on Joel's ruling).

**The count went 0 unassigned → 2 unassigned.** All three previously-open bugs had an owner; neither
new one does. That is the fact Joel actually reads this file for, so it is in the first sentence, and
I split it: **BUG-050 needs a person; BUG-052 needs a ruling and cannot be worked until it gets one.**
"Unassigned: 2" alone would have implied two pickable tasks when only one is.

### Ordering — I put BUG-050 above BUG-052, against the pull of the false-clean family

Both are false-clean-adjacent, which is the family Joel prioritised, so this needed an actual
argument rather than pattern-matching:

- **BUG-052 misleads someone who chose to configure nothing.** The operator's own config is the cause;
  they have some reason to expect an empty result.
- **BUG-050 misleads everyone and breaks a real integration.** Entra ID Connect sync failures are a
  named operational break, and its part 2 carries its own false-clean: the audit cannot retrieve UPN
  at all, so every pre-existing account is non-compliant behind a clean report.
- BUG-052 is blocked on Joel anyway, so it cannot be worked first regardless.

Recorded the reasoning in the file so he can overrule it in one line.

### Where I went beyond the brief

**I did not flatten Joel's "minor... wont impact anything" into either a downgrade or a silent
override.** Both readings are in the entry, labelled, with the note that his framing is *correct for
the tier model's own function* — the accounts work in AD; it is the Entra boundary that breaks. Then
ordered it first anyway, with the reasoning visible. Recording a principal's assessment and
disagreeing with its weighting in the open is honest; quietly reordering around it is not.

**Gave part 2 (audit cannot see UPN) equal billing, as the coordinator asked, and said why in the
file:** fixing the create path alone leaves a false-clean audit — the BUG-049 family. So the entry
states **both paths must be fixed together**, the same coupling BUG-048/049 needed via Trap A. That
constraint is invisible from Joel's report and is exactly what gets lost when a bug is filed from the
symptom.

**Kept the "not affected" line.** `New-TierModelGroup.ps1` has the identical `SamAccountName`-only
shape but groups carry no UPN. Working rule 17 — record deliberate non-changes, or someone "fixes"
them later.

### The caveat I refused to let get rounded off

BUG-047/048/049 are closed with Cyclops's A/B numbers (12 of 14 → 0 of 14; 374/374, 402/402;
`Total Checked` unmoved; verdict flipped). **But BUG-047's `[Error]` → red half is not lab-validated
and cannot be** — fixing the errors deleted the only fixture that could have shown it. That
qualification is in the live file's summary box *and* attached to the archived entry, because a
caveat that lives in only one of the two places is a caveat that will be dropped by whoever quotes
the other. **`Total Checked` not moving is the load-bearing control** in that validation — it shows
the counters were repaired without changing the population audited — so I called it out rather than
letting it read as one more green number.

**BUG-051's value is Rogue's pre-fix assessment, not the fix.** He established that only `Warning` was
in the remapped set — of eight emitted types — so the change **could not** suppress a real error
state, *before* touching it. Establishing what a change cannot break beforehand beats making it and
hoping the suite notices. That is what I archived; the one-line delta is trivia by comparison.

### Lessons

1. **"Unassigned: N" is not enough — split blocked-on-a-person from blocked-on-a-decision.** They look
   identical in a count and are opposite in what they need from the reader.
2. **When a principal calls a bug minor and the evidence disagrees, publish both and order on the
   evidence.** The alternative — silently reordering — costs the trust that makes the register useful.
3. **A caveat must be attached to every copy of the claim it qualifies.** Split the claim from its
   caveat across two files and the caveat is gone.
4. **File the bug, not the symptom.** Joel reported a create-path defect; the audit-path half is what
   makes fixing it correctly non-obvious, and it would not have appeared in an entry written straight
   from his words.

---

## Session 2026-09-07 (16:05) — BUG-050 deferred to v2.1.1, BUG-053 registered unassessed, suite green

**The headline number changed shape, and that was the real work.** The brief pre-computed the
v2.1.0-actionable count as **zero** (BUG-050 deferred, BUG-052 blocked on Joel). **Registering
BUG-053 in the same pass invalidated that arithmetic** — triaging an unassessed item is work a person
can pick up. Rather than adopt a number that had gone stale between being written and being applied,
I broke it out:

| For v2.1.0 | Count |
|---|---:|
| **Ready to fix — needs a person** | **0** |
| Blocked on Joel's ruling | 1 (BUG-052) |
| Open but **unassessed** | 1 (BUG-053) |
| **Deferred out of the release** | 1 (BUG-050) |

"Ready to fix: 0" is the number Joel wants and it survives the addition; "open: 3" would have
misrepresented the release. **The release is blocked on two decisions from him, not on engineering
capacity** — that is the file's first line now. This is working rule 12/21 applied to a status
report rather than to a grep: a count is only meaningful with its population, and "actionable" needed
defining before it could be counted.

### Making the do-not-touch unmissable — four independent places

Joel's point was that nobody should be able to pick BUG-050 up **by accident**, so one banner was not
enough. A scanner reading only headings, only the summary table, or only the entry all hit it:

1. Header table row — **"Deferred to v2.1.1 — DO NOT TOUCH"**.
2. The `##` heading itself carries **🛑 DEFERRED TO v2.1.1 — DO NOT TOUCH** (added after I checked the
   heading-only outline and found it silent — the outline is how this file is scanned).
3. A full-width `#` banner above the entry.
4. A blockquote with **⛔ THE TEAM MUST NOT WORK ON THIS BUG**, Joel's verbatim ruling, and a literal
   instruction to stop reading and go back up.

It is also placed **last**, so the natural reading order never reaches it while looking for work.

### Recorded the taxonomy, because "why" is what stops re-litigation

Bugs → v2.1.1/v2.1.2; features → v2.2.0; **a defect introduced *by* v2.1.0 must be fixed *in*
v2.1.0.** UPN is pre-existing and unrelated to the logging work, so it misses the third rule and lands
in the patch bucket. Without that table, the next person to notice an open bug at release time
re-opens the question. **A deferral without its reasoning is a deferral that gets reversed.**

### My ordering argument: kept visible, explicitly overtaken

I argued BUG-050 above BUG-052 on consequence; that was agreed and has **not** been withdrawn. Joel
ruled on **scope**. I wrote the distinction into the file rather than silently re-sorting:
**consequence decides what to fix first; scope decides which release fixes it.** A defect can be more
consequential *and* correctly deferred. The entry says so, and says it now sits last because it is out
of scope, **not** because the argument was lost.

### BUG-053 registered with NO severity — deliberately

It has the *shape* of BUG-047 (colour/severity demotion), and shape is exactly what this register has
been wrong about before. **The `default { 'Gray' }` arm may be dead code**: if every ADMX finding type
is explicitly handled above it, nothing reaches it and there is no defect. So I registered it so it
cannot be lost, wrote a four-step triage script (enumerate the types **from the producer**, not from
the render site; establish reachability; only then decide if Gray is wrong; only then assign
severity), and **refused to assign a severity I could not defend.** Being told not to invent one is
the same discipline as not inventing a population for a zero.

### Amended the BUG-047 caveat precisely — narrowed, not withdrawn

Three claims, only one changed. **Was** "not validated"; **now** "validated by unit test, still not
lab-validated, and **cannot ever be** lab-validated" — because fixing BUG-049 deleted the only fixture,
so no future lab run closes it. Recorded Wolverine's controls (E1 → 6 failures, E2 → 4) and that the
tests exercise the **real** producer, normaliser and classifier rather than a re-implementation. Kept
in both copies. **A caveat that gets "updated" into deletion is how a half-true green survives.**

### Flagged rather than acted: candidate working rule 22

Test 464's retirement — `Should -Be 9` replaced by reconciliation invariants, proved strictly stronger
by control F1 (re-adding ruled-out rows fails 2 tests **without the test knowing the number 9**) — is
the assertion-side twin of rule 19. **A literal encodes today's answer; an invariant encodes the
relationship that makes any answer correct.** I recorded it in the archive and flagged it as a
candidate rule, but **did not touch the skill file: this session was scoped `.research\` only.** In
scope terms that is the same discipline I was applying to BUG-050 three sections earlier — noticing
that consistency was the check that stopped me.

### Lessons

1. **A pre-computed number in a brief can go stale inside the same task that applies it.** Re-derive
   the count after your own edits; do not transcribe it.
2. **"Actionable" needs defining before it can be counted.** Blocked-on-a-decision, unassessed, and
   deferred are three different not-actionable states and collapse into a misleading total.
3. **An instruction to make something unmissable is a claim to test, not a banner to write.** I
   checked the heading-only outline, found it silent, and fixed it — the outline is how this file is
   actually scanned.
4. **Narrow a caveat; never let "amend" become "delete".** State which of the claims changed and which
   did not.
5. **Scope discipline applies to your own good ideas.** The rule-22 candidate was worth adding and
   still out of bounds.


## Session 2026-09-07 (16:20) — Working rule 22 added to the verification-discipline skill

**Requested by:** Joel Platek via the coordinator, under Joel's standing ruling that working rules
live in `.squad/skills/`. No fresh decision from Joel was needed — only a scope extension from the
coordinator, because my prior brief had been `.research\` only.
**Files touched:** `.squad/skills/verification-discipline/SKILL.md` (15,953 → 19,483 bytes), then
this file and one decision record under a second scope extension. Nothing staged, nothing committed.

### The rule

**22 — a literal encodes today's answer; an invariant encodes the relationship that makes any answer
correct.** Rule 19 is the production-side of the same problem (a string literal in a filter that
stops matching); 22 is the assertion side. Grounded in the retirement of test 464: it asserted
`Should -Be 9`, and when Joel ruled the per-right rows out of `$findings` the literal became wrong —
**the test died with the behaviour it was pinning.** It could not survive a legitimate change to the
very thing it existed to guard. The replacement asserts reconciliation
(`Compliant + Drift + Errors == Findings.Count`, all three verdict states reconciling), and
Wolverine's control **F1 proved it strictly stronger: re-adding the ruled-out rows fails 2 tests
without any test knowing the number 9.**

### Lessons

1. **The file now practises what it documents — and that was rule 22 applied to rule 22's own file.**
   I did not assert "22 rules" by eye. I extracted every `^\d+\. \*\*` heading from the Patterns
   section and set-compared the sequence against `1..22`. **That check exists because the count had
   already been asserted wrong once** — the brief said 20 when there were 21. The count is *derived*
   from the rule list, so pinning it by eye is exactly the failure rule 22 describes; asserting the
   sequence relationship is the invariant form. The coordinator then independently re-derived the
   same check rather than take my word, which is rule 14 working as intended.

2. **The four stale-reference updates were the substantive part, not housekeeping.** Frontmatter
   description (21→22), Patterns preamble, one Context routing bullet, one Anti-Patterns pointer.
   **A rule nobody can route to is a rule nobody applies** — which was the entire argument for making
   these a skill rather than a document, since agents load skills at spawn. Appending rule 22 and
   leaving the routing stale would have produced a file that is technically 22 rules and
   functionally 21. The failure mode of a reference document is not wrongness, it is unreachability.

3. **The reusable discriminator is derived vs decreed, and it generalises past tests.** Pin decrees
   exactly; assert relationships for anything derived. I put the counter-case in the rule itself so
   it cannot be applied blindly — Joel's ruling that a `Pass` row renders **zero** lines is a decree,
   nothing derives it, and pinning it as `0` is precisely how you detect the ruling being violated.
   "Literals are bad" would have been a worse rule than the one it replaced. Closing line, which is
   the part likely to change behaviour: **if you cannot say which one you are looking at, you do not
   yet understand what the test is for.**

4. **Holding scope twice was right, and asking was the correct resolution — not excessive
   literalism.** I declined to write this history file on the previous turn because the brief said
   "nothing else", on the same turn the coordinator had praised the scope instinct. The failure mode
   that matters is an agent widening its own scope quietly; asking costs one round-trip and makes the
   widening visible. **Standing clarification now recorded: my own `history.md` and a decision record
   for work just completed are ALWAYS in scope unless explicitly excluded** — they are the record of
   the work, not new work. That resolves the ambiguity without weakening the rule.

5. **`.squad/` edits are invisible to `git status`** (`.git/info/exclude:9`), so "I changed it" cannot
   be confirmed the usual way. Verify by reading the file back off disk — the same discipline as
   rule 1 (verify against the artifact, not the console). Both this file and the skill file need
   `git add -f`; Joel has ruled that happens later and it is not mine to do.

### State at handoff

Skill file: **22 rules, contiguous 1–22, verified mechanically**, rules 1–21 byte-identical (spot-
checked anchors in 1, 19, 21 including rule 21's 86-file table). No BOM, matching
`.squad\templates\skill.md`. Live `.research\known-bugs.md` untouched at 14,899 bytes: BUG-052
(blocked on Joel), BUG-053 (unassessed, no severity), BUG-050 (deferred v2.1.1, do-not-touch), then
the by-design section. **Ready to fix for v2.1.0: 0.** Next free ID **054**. Root at 13 files.
Nothing staged, nothing committed.

## Session 2026-09-07 (16:50) — BUG-053 closed NOT-A-DEFECT, BUG-054 registered

**Files touched:** `.research\known-bugs.md` (14,899 → 16,020 bytes), `.research\known-bugs-archive.md`
(138,247 → 142,853), this file, one decision record. Nothing staged, nothing committed; working tree
untouched (Joel lab testing, suite green 1980/1980/0).

### Lessons

1. **"Same shape" is a search heuristic, never a finding.** BUG-053 was registered because it
   resembled BUG-047 — a `default { 'Gray' }` arm that could demote severity. Rogue triaged it by
   **execution** and both arms proved **structurally unreachable**: ADMX driven through all four
   outcome paths emits only `{Missing, Mismatch, Error}`, all handled above the `default`; GPO, the
   real candidate because its producer has its own `default { 'Unknown' }` at `:426` and `'Unknown'`
   is absent from the render switch, was executed over **1,296 combinations** and `'Unknown'` never
   survives — the `if/elseif/else` at `:355-369` has an unguarded `else`, and `:371` is the only site
   appending to `$auditResults` (AST-verified, two assignments). **BUG-047's arm was reached every
   run; this one is reached never. Same shape, opposite consequence.** Third time in one session that
   reasoning from resemblance would have produced a wrong answer.

2. **Refusing to assign a severity I could not defend was vindicated within 45 minutes.** I
   registered BUG-053 at 16:05 with **no severity**, explicitly because shape is not proof. Had I
   inherited BUG-047's severity from the resemblance, the register would have carried a
   defensible-looking number for **a defect that does not exist**. The discipline that pays here is
   the same one as not inventing a population for a zero (rule 21): *an unearned number is worse than
   an admitted gap.*

3. **Correct the description, do not just stamp the status.** The entry said "two ADMX render sites".
   It was **one ADMX site (`:2209-2214`) and one GPO site (`:1193-1198`)**. Wolverine's underlying
   observation was sound; his *characterisation* was wrong, and it would have sent whoever picked it
   up hunting a second ADMX site that does not exist. **The observation being right and the label
   being wrong are different failures** — a closure that fixes only the status leaves the bad label
   in the archive as the permanent record.

4. **A residual tidiness item needs its caveat attached or it becomes the next bug.** Two lines could
   route to `Get-TierModelFindingColor`; zero-risk *only because the arm is dead*. Recorded with the
   sentence that makes it safe: **the shared classifier escalates unknown types to Red rather than
   demoting to Gray**, so the swap is not behaviour-preserving *in principle* — only here, only for
   now. A "trivial cleanup" without that sentence is how a behaviour change ships unnoticed.

5. **Calibrating a severity DOWN takes as much evidence as calibrating one up.** BUG-054 is the same
   family as BUG-049 (a counter printed over findings that contradict it) but **materially less
   severe for a checkable reason: ADMX folds missing files into the Mismatched bucket, so total drift
   and compliance % stay correct and the estate does not read falsely clean.** I put that in the
   entry as a warning against reading it as a second BUG-049. **Inflating it would have been the
   easier and more dramatic call, and would have misdirected the release.**

6. **Closing one entry does not license re-sorting the file.** BUG-054 took BUG-053's position
   (second, above BUG-050) exactly as instructed; BUG-052 stayed first. I also caught and fixed a
   stale cross-reference the closure would otherwise have left behind — the header still advertised
   **21** working rules after I added rule 22 this afternoon. **Same failure mode as the four stale
   references in the skill file: the entry is right and the pointer to it has rotted.**

### State at handoff

Live file order: **BUG-052** (blocked on Joel) → **BUG-054** (blocked on Joel) → **BUG-050**
(deferred v2.1.1, do-not-touch) → by-design section, verified intact. **Ready to fix for v2.1.0: 0.**
Next free ID **055**. Root 13 files, nothing staged.

## Session 2026-09-07 (16:22) — v2.1.0 re-scoped to logging only; register split; three bugs deferred

**Files touched:** `.research\known-bugs.md` (16,020 → 6,393 bytes), **new** `.research\deferred-bugs.md`
(13,226 bytes), this file, one decision record. Nothing staged, nothing committed; working tree
untouched (Joel lab testing, suite green 1980/1980/0).

**The ruling:** Joel scoped v2.1.0 to logging / `-EnableVerbose` / `-EnableDebug` bugs **only**;
everything else goes to a separate branch, later. His test is impact — *is it causing issues with
deployments?* BUG-054 and BUG-050 named explicitly; BUG-052 deferred on the coordinator's inference.

### Lessons

1. **I split the file, and the constraint told me which half to sacrifice.** The brief said the live
   file must stay one scroll, and that **if it got long the deferred section moves out — never gets
   truncated**. Three full entries were 9,596 bytes against a 3,555-byte by-design section, so
   inlining them was never going to fit. **Having the priority stated in advance turned a judgement
   call into a lookup.** Live file is now 113 lines; full detail is intact in `deferred-bugs.md`.

2. **A deferred bug needs a home that is not the archive.** The archive means *closed*, and dropping
   three open defects into it would have laundered "out of scope" into "resolved". The new file says
   so explicitly at its tail. **The branch these are deferred to does not exist yet** — that is the
   whole reason the file has to exist and has to be findable from the live register.

3. **Never launder your own inference as the customer's ruling.** Joel named the ADMX and UPN bugs;
   the coordinator applied the same logic to BUG-052 himself and **instructed me to mark it as his
   inference, not Joel's words**. I did, in **both** files, in a call-out box, with the reversal cost
   stated ("costs one sentence"). This is the same discipline as recording attribution correctly in
   rule 21 and correcting Wolverine's label on BUG-053: **who said a thing is part of the finding.**
   A register that attributes an inference to the person with authority makes the inference
   unchallengeable, which is exactly backwards.

4. **A "zero" is only the headline if it is the honest zero.** The top line now reads **v2.1.0 has
   zero open bugs and a green suite** — but the same table shows **3 deferred, not fixed, not
   closed**, and the word *deferred* is never left to imply *done*. Rule 21 again: the zero is
   trustworthy only because its population is beside it.

5. **My own verification produced a false negative and I nearly reported it.** Checking that BUG-050's
   evidence survived the move, `.Contains('86-file product surface')` returned **False** — because
   the phrase **wraps across a line break** in the markdown. The text was intact. **A substring check
   against wrapped prose is unsound**; match on a short unwrapped fragment or normalise whitespace
   first. I caught it by re-checking rather than reporting the miss, but it would have been a
   confident, wrong claim of data loss — the mirror image of a confident, wrong zero.

### State at handoff

`known-bugs.md`: headline (0 open, green suite) → deferred summary table pointing at
`deferred-bugs.md` → by-design section, **verified byte-identical and at the tail**.
`deferred-bugs.md`: BUG-050 → BUG-052 → BUG-054, ordered by consequence (scope no longer separates
them), full reproduction detail retained. **In scope for v2.1.0: 0.** Next free ID **055**.

## Session 2026-09-07 (16:35) — REVERSAL: BUG-052/054 back in scope; scope test corrected

**Files touched:** `.research\known-bugs.md` (6,393 → 13,177 bytes), `.research\deferred-bugs.md`
(13,226 → 7,284, now BUG-050 only), `.research\known-bugs-archive.md` (repair only), this file, one
decision record. Nothing staged, nothing committed; working tree untouched (Rogue in
`Audit-TierModel.ps1`/`Test-TierModelAdmx.ps1`, Storm in `docs\`/`specs\`, Cyclops reading).

**The reversal:** BUG-052 and BUG-054 were deferred out of v2.1.0 at 16:22 and returned at 16:35.
**A coordinator error, not a change of mind by Joel** — recorded that way at the coordinator's own
instruction.

### Lessons

1. **The scope test is a PROPERTY, not a LABEL — and I should have noticed the axis was wrong.**
   The 16:22 deferral asked *"is it ADMX / is it logging-related?"* Joel's actual test is
   ***"does it make the tool lie?"*** — *"the output should be accurate meaning the reports, colors,
   text, etc. No point having a log file that says GREEN and MISSING.. that is dumb."* **That is a
   near-verbatim description of BUG-054**, which prints `Missing ADMX Files: 0 ✅` in green at
   `Test-TierModelAdmx.ps1:233`. Joel dismissed "that ADMX thing" **without realising it was the case
   he was describing** — the category name hid the property from its own owner. I had that entry's
   full text in front of me and matched it against the category too. **Category is a label; accuracy
   is a property. Labels are what you file under; properties are what you decide on.**

2. **Vindication is not the point, but the mechanism is: the inference call-out was overturned in
   under an hour.** At 16:22 I recorded BUG-052's deferral as **the coordinator's inference**, by
   name, subject to Joel's correction — over his own authority, because he told me to. **Had it been
   written as Joel's ruling, reversing it would have meant contradicting the customer rather than
   correcting a colleague.** I completed the round trip in the file rather than deleting it: the
   inference was *made, flagged, and overturned*, and that sequence is the strongest argument in the
   register for precise attribution. **Delete the history and the practice loses its evidence.**

3. **Fix the false headline BEFORE anything else.** The file still said "✅ v2.1.0 HAS ZERO OPEN
   BUGS". Joel reads that line. **A stale headline is worse than no headline** — it is the register
   committing the exact defect the register exists to catch (BUG-049: reporting clean when it is
   not). I corrected it as the first write of the session, before touching a single entry.

4. **I shipped three real defects into my own files and caught them only by checking. Own that.**
   (a) The `@'...'@` here-string trap bit me **again** — three literal `''` artifacts in
   `deferred-bugs.md` and one in the archive, written last session. My verification that session
   checked `history.md` and the decision record for `''` **but not the file I had just created** —
   the population of my own check was too narrow, which is rule 21 turned on myself.
   (b) A splice produced `---## By design` with no line break, silently removing the heading.
   (c) I introduced **bare-LF line endings** into three files in a repo that is otherwise pure CRLF.
   All repaired; content proved identical across the normalisation by comparing line-ending-normalised
   before/after. **Sweep every file you touched, not the ones you remember touching.**

5. **Two of my own verification checks returned confident false results this session.**
   `.Contains('**`+"`"+`Test-TierModelAdmx.ps1:235`+"`"+`...')` failed because **backticks are escapes in a
   double-quoted PowerShell string** and silently vanished; `(?m)^---$` counted **0** separators in a
   CRLF file because `$` will not match before `\r`. **Both were false negatives that looked like
   findings.** Yesterday's wrapped-prose `.Contains` miss was the same species. The rule I keep
   re-learning: **when a check reports "not found", suspect the check before believing the absence** —
   a search tool that is subtly wrong is indistinguishable from a true zero.

### State at handoff

**In scope for v2.1.0: 2, both in progress, neither blocked on a person** — BUG-054 (Rogue, fixing)
and BUG-052 (Cyclops, **investigating only**; Joel rules before any repair). Deferred: **1**
(BUG-050, full detail retained in `deferred-bugs.md`, deferred on three independent grounds).
Closed not-a-defect: BUG-053. Next free ID **055**. By-design section content verified unchanged and
at the tail. Root 13 files, nothing staged.

**Flagged, not actioned (coordinator will scope it when the tree is quiet):** the wrapped-prose and
false-negative verification gotchas belong in
`.squad/skills/verification-discipline/SKILL.md`, not only here.

## Session 2026-09-07 (17:05) — BUG-055 and BUG-056 registered; BUG-052's scope claim corrected

**Files touched:** `.research\known-bugs.md` (13,177 → 21,257 bytes), this file, one decision record.
Nothing staged, nothing committed; working tree untouched (Rogue live in `Audit-TierModel.ps1`).

**Cyclops was sent to investigate BUG-052 and found two defects nobody predicted, both worse than the
one he was sent for.** Registered as BUG-055 (green `✅ COMPLIANT` printed above `Total Errors: 2`)
and BUG-056 (unreachable directory renders `All Users/Groups compliant ✅`). Next free ID **057**.

### Lessons

1. **"Was this applied to EVERY site?" is now the default question, not an afterthought.** BUG-055,
   BUG-056 and half of the amended BUG-052 are **all the same shape: a rule that exists, is correct,
   is commented, and was applied unevenly.** BUG-055 — the errors-suppress-green guard lives at
   `:1774` with a comment saying an errored run must never render green; the standalone path at
   `:2381` never got it. BUG-056 — `Test-TierModelOu` carries `UnverifiedCount` and the comment *"an
   OU we could not read is not a pass"*; Group and User never got it. BUG-052's arithmetic — **5 of 7**
   compliance sites guard `totalChecked -le 0`; GPO `:1116` and ADMX `:2120` do not. **That is the
   fourth, fifth and sixth instance of this shape in one register.** The defect is *inconsistency*,
   not absence — which means **finding the correct implementation is the START of the search, not the
   end of it.**

2. **An investigation's most valuable output can be the correction to its own premise.** BUG-052 was
   registered as *"structural — every producer's empty-config path."* Executed: **wrong for 3 of 13**.
   `organizationUnits`, `groups` and `users` hard-fail `Get-TierModelConfig` and abort the audit —
   they **fail closed and loudly**, which is correct. I **struck the original claim through rather
   than deleting it**, with the corrected denominator beside it. **A register that silently repairs
   its own wrong claims teaches nobody which kinds of claim to distrust** — and this one was wrong in
   the specific way that matters: it was reasoned from the code rather than executed.

3. **State the denominator or the count is unfalsifiable — rule 21, and this entry is now the model
   for it.** Every BUG-052 figure carries `/13`, with the population defined up front: **21
   `Test-TierModel*` functions, of which 13 are config-driven scope producers, all 13 executed.**
   "6 print green, 7 print nothing" is checkable on sight; "most producers" is not.

4. **Being right about one defect predicts nothing about the next — recorded as the entry's irony.**
   **GPO and ADMX were the only two sections CORRECT in the earlier drift-counter baseline, and they
   are the two WRONG in the zero-case arithmetic.** Reputational reasoning about code areas is
   worthless; only execution counts.

5. **Record the constraint on the fix, not just the defect.** BUG-052 case (b) — a scope configured
   but resolving to zero live objects — **reports drift correctly today.** The obvious fix collapses
   "nothing configured" with "configured but absent" and **would destroy a distinction the tool
   currently gets right.** A bug entry that describes only what is broken invites a fix that breaks
   what works.

6. **Cross-reference a defect to the moment the team refused to create it.** BUG-056 is case (c),
   *"could not determine" reported as "clean"* — **the exact failure mode Rogue refused to introduce**
   when he declined a blanket relabel on the WinLaps decryptor, on the grounds it would report an
   unreachable DC as a clean-but-missing estate. **He refused to build it there; it was already
   shipping here.** Linking the two makes the inconsistency impossible to miss and shows the team's
   own judgement was right before the evidence arrived.

7. **Stale sub-claims survive a status edit.** After amending BUG-052 I found the heading still said
   *"CYCLOPS INVESTIGATING"*, the in-progress call-out still told people an option list was coming,
   and the disproved *"every producer"* sentence still sat in the body **contradicting the corrected
   population three paragraphs above it.** I only caught them by re-reading the rendered section.
   **Editing an entry's status is not editing the entry** — sweep the whole section for statements
   the amendment just falsified.

### State at handoff

**Open for v2.1.0: 4** — **BUG-055** (unassigned, needs **no ruling**: correct behaviour already
exists at `:1774`), **BUG-056** (unassigned, pending Rogue), **BUG-054** (Rogue, in progress),
**BUG-052** (investigation complete, awaiting Joel's ruling). **Deferred: 1** (BUG-050). Closed
not-a-defect: BUG-053. **Next free ID 057.** Ordered by consequence: the two new false-clean defects
lead, because both print green over errors the tool already detected. By-design section verified
intact and last. Root 13 files, nothing staged.

## 2026-09-07 17:45 - Working rule 23, BUG-057, SKILL.md normalisation

Three jobs, all in lane. `.research\` + `.squad\` only. Committed nothing, staged nothing. Four
agents live in the product tree (Rogue, Cyclops, Storm, Wolverine) - stayed out of all of it.

**Job 2 first, because the headline was stale.** Standing practice: the count at the top is the line
Joel reads, and a stale headline is worse than no headline. Corrected 4 -> 5 open before writing the
BUG-057 body, not after.

**BUG-057** - `tests\Unit.ModuleManifest.Tests.ps1:399`, test "Release notes mention current version"
asserts `Should -Match '1\.1\.0'` while `ModuleVersion` is 2.1.0. Green only because `1.1.0:`
survives among historical entries. Classified explicitly as the same class as BUG-054/055/056 - a
green signal that does not mean what it appears to mean - except in the harness. Recorded that a
false green in a test is worse than a red, because a red gets looked at. Also flagged it as a rule-22
violation: a literal where a derived invariant belongs, which is exactly why it went stale silently.
Recorded the content gap (no `2.1.0` ReleaseNotes entry; present: 2.0.0, 1.3.3, 1.3.0, 1.2.3, 1.2.2,
1.2.1, 1.2.0, 1.1.0, 1.0.0) and the sequenced fix: notes first (Joel-or-Scribe only, pairs with the
outstanding `CHANGELOG.md [2.1.0]`), assertion repointed at `ModuleVersion` second. Wolverine's
instruction not to touch the assertion meanwhile is recorded as standing, with the reason.

**Job 1 - working rule 23.** Six instances of one shape is a pattern: a rule that exists, is correct,
is commented, and was applied unevenly. Wrote it as a four-row table with file:line so it is
checkable rather than folklore. Included the corollary (a producer fix is not finished until every
render site is checked - BUG-054 survived a release exactly this way, while `CHANGELOG.md:25` called
that fix "the highest-leverage fix on this branch") and the diagnostic value (the correct
implementation is the cheapest oracle - you diff against a decision already made, and where it
carries a comment, that comment is the specification).

Updated the four cross-references as always: frontmatter description, Patterns preamble, a Context
routing bullet, an Anti-Patterns pointer (two, in fact - rule 23 earns a stop-early one and a
producer/render one). **Contiguity verified by set-comparing extracted `^\d+\. \*\*` headings against
`1..23`, not by eye** - `Compare-Object` returned nothing.

**Job 3 - line endings and the gotcha.** SKILL.md was 151 CRLF / 114 LF from an earlier append.
Normalised by collapsing everything to LF and re-expanding uniformly, which is content-preserving by
construction rather than by inspection. 19,483 B -> 23,832 B, CRLF 316 / LF 0.

Added three verification gotchas to Anti-Patterns, the first being the one I hit for a third time
**in this very run**: `.Contains` against a phrase that wrapped a line break reported the
`Test-TierModelOu` comment missing when it was present. Caught it before reporting - that is the
behaviour the rule teaches, so it is written as "match a short unwrapped fragment or normalise
whitespace first". Bundled the other two long-standing traps while I was there: backticks and `$`
vanishing inside double-quoted PowerShell search strings, and `(?m)^...$` returning a confident zero
on CRLF text.

**Self-check on this run:** swept for `''` here-string artifacts (0), bare LF in `.research\` (0),
and caught one splice defect of my own - `---` running straight into the `## Deferred` heading with
no blank line, which would have swallowed the heading in render. Fixed before reporting.

Register left at 24,886 B / 450 lines, 5 open, next free ID 058. Deferred file untouched, still
BUG-050 only.

## 2026-09-07 17:25 - Timestamp drift note, and closing the false-clean sweep

Two jobs, `.research\` + `.squad\` only. Committed nothing, staged nothing. Changed no existing
timestamp. Rogue, Storm and Wolverine all live in the product tree - stayed out.

**Job 1 - the session's times drifted and Joel ruled "leave the stamps, add a note".** The
coordinator issued CURRENT_DATETIME values by feel rather than reading the clock; by the end they ran
about 75 minutes ahead of real elapsed time, and they had already been written into files as fact.

Wrote a short limitation note directly under the register's "Last updated" line - the exact point a
reader meets a timestamp and might act on it. It says the drift happened, that the values were
**supplied and not measured**, that **dates are correct and only times are affected**, and that
**file mtimes on disk are authoritative where ordering matters**. Named the affected files
(`specs\006-verbose-debug-logging\tasks.md` T024, `spec.md`, agent histories).

Written as a limitation of the record, not an apology, and **attributed to nobody** - Storm and I
wrote what we were given, and the coordinator was explicit that the fault was his. That instruction
was right and I followed it exactly: a register that blames the writer for the supplier's error
teaches the wrong lesson.

One artefact I left deliberately rather than smoothing over: this note is stamped 17:25, which reads
*earlier* than the register's "Last updated 17:45" immediately above it. I flagged that inline
("which is why that reads later than this") instead of quietly adjusting either. The inconsistency
**is** the evidence.

**Rule candidate flagged, not self-approved.** The coordinator's formulation is strong - *a timestamp
is a measurement and must be read, never composed* - and it is the third instance today of a document
asserting something that did not happen that way. But he phrased it conditionally ("if a rule comes
out of it"), where rules 22 and 23 each came with an explicit instruction to add. **So I recorded it
as the rule-24 candidate in the decision record and left SKILL.md alone.** Same discipline as the
BUG-052 inference call-out: do not launder a maybe into a ruling. It costs him one sentence to say
yes.

**Job 2 - closed the literal false-clean line of inquiry.** No seventh instance. Recorded it in the
live register under an explicit DO-NOT-RE-OPEN heading, because the entire value of a null result is
that nobody re-derives it in three weeks.

Stated the population beside every count as instructed: **81 files** (80 public + `TierModel.psm1`),
**33 error-returns zeroing a count across 27 files at HEAD**, 32/26 present state, **false-clean 0**.
Corrected the brief's assumption that `modules\TierModel\internal\` exists - it does not - and
checked every `.research\` file for a repeat of that claim before reporting: zero hits, so nothing to
amend.

Gave most of the space to **why the zero is trustworthy**, which is the actual finding: a 12-mutation
battery caught 12/12. A sweep that finds nothing is worth nothing until shown able to find something.
Recorded both times Cyclops caught his own instrument (filter under-reporting by half; generator at
fault for 11/12, not the sweep) as **suspect the instrument, including the instrument that tests the
instrument**. Also recorded, at his request, that the coordinator's own narrow regex was **right by
luck** and would have missed all 33 sites - working rule 19's shape arriving as a false negative.

Captured the BUG-052 precedent: `Test-TierModelAuthSiloPrerequisite.ps1:83` already returns
`Passed=$false` for an empty scope, so Option 1 is the rule this code already follows - a rule 23
instance, and useful ammunition when Joel rules.

**Self-check:** hit the wrapped-bold trap again - my anchor `**Two of the four report a FALSE
CLEAN**` missed because the bold spans the whole sentence, not the fragment. Inspected the raw line
and char codes rather than guessing, then anchored on unformatted text. Also caught the `---`
run-together against `## Deferred` for the second time - my appended blocks end with a separator and
the anchor follows immediately. Worth remembering as a habit: **check `---\r\n#` after every splice**,
not just when I remember.

Register: 29,895 B / 535 lines, by-design verified still last heading. **5 open, next free ID 058 -
unchanged; neither job registered or closed a bug.**
