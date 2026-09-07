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
