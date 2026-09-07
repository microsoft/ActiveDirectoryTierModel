---
name: "verification-discipline"
description: "How to know a claim about code is actually true: proving absence and zeros, designing checks that can fail, verifying artifacts rather than consoles, and reading a moved number as evidence instead of noise. 23 rules, each earned from a specific shipped defect."
domain: "verification, testing, debugging, code-review"
confidence: "high"
source: "earned"
---

## Context

Apply this skill whenever you are about to **assert that something is true about a codebase** —
that a bug is fixed, that a pattern does not occur, that a count is N, that a test proves what its
name says, or that a feature is or is not present.

It exists because the ActiveDirectoryTierModel project produced ~46 real defects in which the
*checking* failed, not the coding. Green suites, clean greps, agreeing outputs and confident zeros
were all wrong at least once. Every rule below is the residue of one of those failures.

**Use it at these moments specifically:**

- Before reporting a **zero, an absence, or a count** (rules 5, 12, 20, 21).
- Before trusting a **passing test** as evidence (rules 3, 6, 7).
- Before believing a **console message, a status field, or a register entry** (rules 1, 4, 13, 14).
- When a fix **moves a number you did not expect it to move** (rules 9, 16).
- Before you **pin a number in an assertion**, or rewrite one a legitimate change has broken
  (rules 9, 22).
- When you are about to **widen a shared code path, delete a literal, or rename a key** (rules 10,
  15, 17, 18, 19).
- The moment you **find the correct implementation of something** — that is the start of the search,
  not the end (rule 23).
- When a read succeeds but returns something blank or surprising (rule 11).

**Cheapest possible use:** before you write "0", "none", "all", "verified" or "fixed" in a report,
find the rule that governs that word and satisfy it.

## Patterns

The 23 rules, reproduced **verbatim** from the project defect register. Numbering is preserved and
must not be changed — several rules are cited by number elsewhere, and the defect IDs inside them
are the evidence that makes each rule believable. Read the citations; they are the valuable part.

1. **Verify against the artifact, not the console.** Every defect in the 026–030 family looks
   perfect on screen. **Limit: this only detects a *disagreement*. See rule 14.**
2. **A green run proves nothing about a drift-counting bug.** Use a drifted fixture with more than
   one entity type.
3. **`Mock X { throw }` proves nothing about `-ErrorAction Stop`.** It throws whether or not the fix
   is present. Mock with `Write-Error` — non-terminating, so it escalates *only* if the call site
   requests `Stop`. Reject any BUG-019 test whose only assertion is `Should -Throw`.
4. **Never infer success from the absence of an exception.** Confirm with `Test-Path` or equivalent.
5. **Count call sites with the AST**, never with grep or regex.
6. **Watch a new assertion fail before trusting it.** A check only ever observed passing is not
   evidence. Confirm it fails for the **intended reason** — a control that fails for the wrong
   reason (a parse error, say) is worse than no control, because it manufactures false confidence.
7. **Beware assertions satisfied by the state they were written to reject.** A
   `Should -Match 'COMPLIANT'` passed for months against output reading *"its compliance is UNKNOWN,
   **not compliant**"* — `-Match` is case-insensitive and the failure text contained the word.
   Anchor on the verdict line, not a substring.
8. **Never truncate a live pipeline you are measuring.** `Select-Object -First N` can kill a child
   process before it flushes, producing a phantom "no output" result. This nearly caused a
   non-existent product defect to be reported.
9. **Fix the fixture, not the assertion.** When a repaired test yields an awkward number, assert the
   awkward number. Tuning a mock to restore a round figure encodes a lie.
10. **The acceptance bar for a shared code path is the sites you are *not* changing.** Widening a
    normaliser to repair 3 shapes risks silently altering the 33 that were already correct — prove
    byte-identical output for those first.
11. **`-ErrorAction Stop` is necessary, never sufficient.** A successful read returning a blank
    value is not an error and no error-action setting can see it. Pair every hardened read with an
    explicit value guard (BUG-035, BUG-038).
12. **State the population before quoting a count.** The empty-catch figure was wrong twice because
    "66" and "102" measure different things. A number without its population is not evidence.
13. **A defect register goes stale faster than the code.** BUG-034, BUG-037 and BUG-038 were all
    carried as open after they had been fixed. Re-verify status against source before quoting it.
14. **Two outputs agreeing proves only that they share a source, not that either is right.** Rule 1
    catches a console/artifact *disagreement*; where both are rendered from the same variables, they
    fail together and agree while doing it. BUG-041 was found only by counting the findings in the
    body and comparing that count against the header **within a single artifact** — an internal
    consistency check, not a cross-output one. **Add that check to the standard sweep:** for every
    report, does the summary reconcile against the body it sits above? Seven earlier defects were
    caught by rule 1; it would have passed BUG-041, and BUG-043 was found by applying rule 14
    directly.
15. **A finding object that contradicts itself localises the bug to the producer.** BUG-040: only
    `Identifier` carried the placeholder while `ExpectedValue` and `Details` on the *same object*
    carried the resolved DN. A genuine upstream resolution failure corrupts every field together, so
    per-field disagreement is proof the upstream value was fine and a single construction site is at
    fault. Use this before adding any second normalisation/expansion pass — a second pass over
    already-correct data hides the real fault instead of fixing it.
16. **When a fix moves a test count, the diagnosis is wrong until proven otherwise.** Rogue's first
    BUG-041 fix took Integration 318→316. The regression was the evidence that key-renaming had only
    changed *which* producer family was being discarded. Read a moved count as information about the
    diagnosis, never as a fixture to be adjusted (see rule 9).
17. **Record deliberate non-changes next to the changes.** BUG-040 left four sites on the raw path on
    purpose; the BUG-041 override was deleted rather than widened. Both look like incomplete work to
    the next reader. An un-recorded deliberate omission gets "fixed" by someone else later.
18. **Under `Set-StrictMode -Version Latest`, widening what reaches a renderer widens what can crash
    it.** Bitten three times on 2026-09-05 alone: BUG-032 (`ResourceType` interpolation), BUG-043
    (an unguarded `MissingGpos` read that took Integration 318→316), BUG-044 (raw `AuditRule`,
    `AuthPolicy`, `AuthSilo` and `WinLapsDecryptor` findings carry neither `Identifier` nor
    `Details`). The failure always lands at **report time on a DRIFTED run** — the run that most
    needs an artifact is the one that produces none. So: before letting a new finding shape reach a
    renderer, either normalise it to a guaranteed shape or guard every property read. **A
    nice-to-have must never be able to take the report down.**
19. **A whitelist filtered on a string literal silently becomes a deny-all when the literal stops
    being emitted.** BUG-044 was created, not by an edit to the consolidated body, but by BUG-042
    removing the last producer of `Type='Drift'` several hours earlier — and nothing failed. When
    you delete a label, value or key, grep for every **consumer** that matches it and prove each
    still has a population. A filter that matches nothing raises no error and produces a confident,
    empty, wrong answer.
20. **Distinguish "blank" from "not applicable" before quoting a producer sweep.** Ten producers
    read as BLANK in a `Type = '...'` literal sweep. Six were **not in the report population at
    all**; four were genuinely affected and merely `Status`-shaped. A sweep reports what it can
    match, not what is true — this is rule 12 (state the population) applied to code rather than
    counts.
21. **When you report a ZERO or an ABSENCE, state the population and the enumeration rule beside
    it.** Rule 12 says a count needs its population; this is the sharper case, because **a zero is
    the one result that looks identical whether your enumeration was right or wrong**. A wrong
    population hides its own error perfectly.

    Earned on 2026-09-07 and paid for twice. The comment-strip pass reported *"0 BUG- references in
    product code"*. It was wrong. It had enumerated by **file shape** — cmdlet-style
    `modules\TierModel\public\*.ps1` plus the root scripts plus `optional\` — which comes to **84**
    files and is **structurally blind to `TierModel.psm1` and `TierModel.psd1`**, because those are
    neither cmdlet-style module files nor root scripts. Two violations survived undetected in
    `TierModel.psm1` and were only caught by a later, wider sweep.

    **The reusable fact — record it, do not re-derive it. The product surface is 86 files:**

    | Population | Count |
    |---|---:|
    | Root `*-TierModel.ps1` (`Deploy-TierModel.ps1`, `Audit-TierModel.ps1`) | 2 |
    | Under `modules\` (**80** `public\*.ps1` + `TierModel.psm1` + `TierModel.psd1`) | 82 |
    | Under `optional\` | 2 |
    | **TOTAL product surface** | **86** |

    Verified by direct enumeration on 2026-09-07. **`TierModel.psm1` and `TierModel.psd1` are the
    two files every shape-based sweep drops.** Any sweep that reports 84 has already lost them.

    **"84 files, 0 hits" is falsifiable on sight against a repo with 86. A bare "0" is not.** That
    is the entire rule: the population is what makes a zero *checkable by the reader*, and an
    unfalsifiable zero is not evidence, it is a claim.

    **Attribution, stated correctly.** The false "0" was **Beast's**, asserted in Rogue's brief from
    a check that had in fact been scoped only to the two entry scripts. **Rogue caught it.** It is
    recorded this way round deliberately: a rule about honest enumeration that misattributes its own
    origin would undercut itself, and the person who finds the error is not the person who made it.

    Corollary — **an absence must be searched for by the feature's own name.** A sibling code path
    will happily return a plausible partial match and let you conclude a feature exists when it does
    not, or vice versa. Use `[IO.File]::ReadAllText` + `[regex]::Matches` for any absence claim,
    never `Select-String`, whose per-line, pipeline-shaped output can silently drop matches on files
    it cannot read cleanly. Both halves of this rule were exercised again the same afternoon on
    BUG-049's provenance: `-IncludeAuthPolicies` and `-IncludeAuditRules` return **zero** because
    **they do not exist under those names** — the features are gated by `-IncludeAuthSilos` and
    `-EnableAuditing` and are fully pre-existing. A zero taken at face value there would have
    produced exactly the wrong provenance answer.

22. **A literal encodes today's answer; an invariant encodes the relationship that makes any answer
    correct.** Rule 19 is the production-side of this problem — a string literal in a filter that
    stops matching. This is the assertion side. Before you pin a number in a test, ask whether that
    number is **decreed** or **derived**. Pin decreed numbers exactly. Never pin a derived one:
    assert the relationship it falls out of instead.

    Earned on 2026-09-07, from the retirement of test 464. It asserted `Should -Be 9`. When Joel
    ruled the per-right rows out of `$findings`, the literal `9` became wrong — and **the test died
    with the behaviour it was pinning.** It could not survive a legitimate change to the very thing
    it existed to guard. That is the tell: a test you must rewrite every time the system changes
    legitimately is not protecting the system, it is charging rent on it.

    **The replacement asserts reconciliation, not arithmetic:** `Compliant + Drift + Errors ==
    Findings.Count`, plus the requirement that all three verdict states reconcile.

    **It is strictly stronger, and that was proved rather than argued.** Wolverine's control F1
    re-added the ruled-out per-right rows — the exact regression the old test existed to catch —
    and **2 tests failed without any test knowing the number 9.** So the invariant caught everything
    the literal caught, while surviving the ruling that killed the literal.

    | | `Should -Be 9` | `Compliant + Drift + Errors == Count` |
    |---|---|---|
    | Catches re-multiplication | at one config size | **at any config size** |
    | Survives a legitimate ruling | **no — dies with it** | yes |
    | Must be rewritten when the system changes | every time | **only when the system is wrong** |

    That last row is the whole rule. **A literal breaks when the system changes; an invariant breaks
    when the system is wrong.** Only one of those is a signal.

    **Counter-case — do not apply this blindly. Literals are correct when the number IS the
    specification, not a consequence of it.** Joel's ruling that a `Pass` row renders **zero** lines
    is a decree: nothing derives it, it is the requirement itself, and it should be pinned exactly
    as `0`. Pinning it is how you detect the ruling being violated. The test is not "is it a number"
    but **"is this number derived, or decreed?"** Derived numbers are consequences of a computation
    and belong in an invariant. Decreed numbers are the specification and belong in a literal. If
    you cannot say which one you are looking at, you do not yet understand what the test is for.

23. **Finding the correct implementation of a rule is the START of the search, not the end.** When
    you find a guard, a comment, or a remedy that is *right*, the next question is never "good, that
    is handled" — it is **"where else should this be, and is it?"** In this codebase the answer has
    been *"somewhere it isn't"* **six times**.

    **The six, with sites, so this is checkable rather than folklore:**

    | The rule, where it IS correct | Where it is MISSING | Bug |
    |---|---|---|
    | `Audit-TierModel.ps1:1774` — errors must never render green, with a comment saying so | `Audit-TierModel.ps1:2381` (standalone headline) | BUG-055 |
    | `Test-TierModelOu` — `UnverifiedCount`, commented *"an OU we could not read is not a pass"* | `Test-TierModelGroup`, `Test-TierModelUser` | BUG-056 |
    | **5 of 7** compliance sites guard `totalChecked -le 0` | `Audit-TierModel.ps1:1116` (GPO), `:2120` (ADMX) | BUG-052 |
    | `Test-TierModelGPOAudit.ps1:438-462` — real-count fix | `Audit-TierModel.ps1:1168` — the render site the same fix missed | BUG-054 |

    **The defect is INCONSISTENCY, not absence.** Nobody failed to decide these; somebody failed to
    apply a decision everywhere. That is a different search, and grep for the *symptom* will not find
    it — you have to grep for the *rule* and enumerate the sites that should carry it.

    **Corollary, and it is the practical half — a fix that repairs a producer is NOT FINISHED until
    every render site of that producer has been checked.** BUG-054 survived a release for exactly
    this reason: the producer was fixed and the display was not. Worse, **`CHANGELOG.md:25` called
    that fix *"the highest-leverage fix on this branch"* while half of it was still outstanding.** A
    confident changelog entry is not evidence that a fix is complete.

    **Why this is the cheapest oracle you will ever get.** The correct implementation **tells you what
    right looks like.** You are no longer guessing at intent, arguing about desired behaviour, or
    waiting on a ruling — **you are diffing against a decision the team has already made and written
    down.** When the correct version carries a comment explaining itself, as `:1774` and
    `Test-TierModelOu` both do, that comment is the specification. Use it.

## Examples

The rules above carry their own worked examples inline; these are the three whose stories are most
often needed in full, cited by the rule that owns them.

**Rule 14 — why a technique that worked seven times stopped working.** Rule 1 ("verify against the
artifact, not the console") caught seven defects. It then *passed* BUG-041, because the console and
the saved report were rendered from the **same variables** — they failed together and agreed while
doing it. The replacement check is internal, not cross-output: **count the findings in the body and
compare that count against the header, within a single artifact.** Applying it directly then found
BUG-043. A verification technique can have a blind spot that only shows up after a long run of
successes.

**Rule 16 — a moved test count as diagnostic information.** A fix for BUG-041 took the Integration
suite from 318 passing to 316. The two failures were not fixture damage to be repaired: they were
the evidence that the diagnosis was wrong — the "fix" had only changed *which* producer family was
being silently discarded. Reading the regression as information, rather than adjusting the tests to
restore the count, is what located the real fault.

**Rule 19 — a whitelist that became a deny-all with no error.** BUG-044 (the consolidated report
itemised 4 producers out of 15) was not caused by any edit to the reporting code. It was caused by
BUG-042's fix removing the last producer that emitted `Type='Drift'` several hours earlier. The
downstream filter matched that literal, its population silently fell to zero, **nothing failed**,
and the report became confidently empty. When you delete a label, value or key, grep for every
**consumer** of it and prove each still has a population.

## Anti-Patterns

Short restatements of what to avoid. **These are derived pointers, not rules — the authoritative
wording is in Patterns above, and it governs where the two differ.**

- **Reporting a bare `0`.** Without its population and enumeration rule, a zero is unfalsifiable and
  is a claim, not evidence (rules 12, 21).
- **Enumerating a codebase by file shape.** Shape-based sweeps drop the files that do not fit the
  shape, and those are exactly where things hide (rule 21).
- **Using `Select-String` to prove an absence.** Use `[IO.File]::ReadAllText` + `[regex]::Matches`
  (rule 21). And count call sites with the **AST**, never with grep (rule 5).
- **Searching for a feature by a plausible name instead of its real one.** A sibling code path
  returns a convincing partial match, and a nonexistent parameter name returns a convincing zero
  (rule 21).
- **Citing a green suite as proof of a counting or drift fix.** Use a drifted fixture with more than
  one entity type (rule 2).
- **Shipping an assertion you have only ever watched pass.** Break the code deliberately and confirm
  the check fails **for the intended reason** (rule 6).
- **`Mock X { throw }` to test `-ErrorAction Stop`.** It passes whether or not the fix exists; mock
  with `Write-Error` instead (rule 3).
- **Adjusting a fixture to restore a round number** after a fix moved it (rules 9, 16).
- **Pinning a derived number as a literal.** If the number is a consequence of a computation, assert
  the relationship instead — a literal dies with the behaviour it pins the moment that behaviour
  legitimately changes. Decreed numbers are the exception and should be pinned exactly (rule 22).
- **Quoting a defect register's status field** without re-verifying it against source (rule 13).
- **Treating two agreeing outputs as corroboration** when they share a source (rule 14).
- **Adding a second normalisation pass** over data that a single producer corrupted (rule 15).
- **Extending an exact-literal whitelist by one more `-or`** instead of matching the class (rule 19).
- **Letting a nice-to-have finding shape reach a renderer unguarded** under `Set-StrictMode` — it
  fails at report time, on the drifted run that most needed the report (rule 18).
- **Leaving a deliberate non-change unrecorded.** It looks like incomplete work and someone "fixes"
  it later (rule 17).
- **Stopping when you find the code that gets it right.** Enumerate every site that should carry the
  same rule and check each one; the defect is usually inconsistency, not absence (rule 23).
- **Calling a producer fix "done" without checking its render sites** (rule 23).
- **Using `.Contains()` on a phrase that wraps a line break** in prose or markdown — it reports
  "missing" for text that is present. Match a short unwrapped fragment, or normalise whitespace with
  `-replace '\s+',' '` first (rule 21).
- **Putting backticks or `$` inside a double-quoted PowerShell search string.** Both are escapes and
  vanish silently, so the search looks clean and finds nothing. Use single quotes for literals.
- **Trusting `(?m)^...$` on CRLF text.** `$` will not match before `\r`, so line-anchored counts come
  back as a confident zero. Use `\r?$`.

## Provenance and maintenance

- **Source:** `.research\known-bugs.md` on the ActiveDirectoryTierModel v2.1.0 diagnostics release,
  promoted here 2026-09-07 12:40 on Joel Platek's ruling. The full defect register those rules came
  from is preserved at `.research\known-bugs-archive.md` (git-excluded, no version history — do not
  delete it).
- **Why a skill and not a document:** agents read `.squad/skills/` at spawn, so these get **applied**
  rather than merely stored. Previously they were used only when someone remembered to paste them
  into a brief — which is how BUG-044 shipped, since **rule 19 describes that exact failure** and
  nobody had it in hand at the time.
- **Adding a rule:** append with the next number, cite the specific defect that produced it, and do
  not renumber or reword the existing ones.
- **Rule 22 added 2026-09-07 16:20**, on the coordinator's scope extension under Joel's standing
  ruling that working rules live here. Source: the retirement of test 464 and Wolverine's control
  F1. Rules 1–21 were re-verified byte-identical at the time of the append; only the rule count in
  the description, the Patterns preamble, one Context routing bullet and one Anti-Patterns pointer
  were updated to match.
- **Rule 23 added 2026-09-07 17:45**, on the coordinator's ruling that six instances of one defect
  shape make a pattern, not an observation. Source: BUG-052, BUG-054, BUG-055, BUG-056 and the two
  earlier producer/render splits. Rules 1-22 were re-verified byte-identical at the time of the
  append; contiguity 1-23 was confirmed by set-comparing the extracted headings against `1..23`
  rather than by eye. Three verification gotchas were added to Anti-Patterns in the same pass.
- **Line endings normalised to CRLF 2026-09-07 17:45.** The file had been left mixed (151 CRLF / 114
  LF) by an earlier append. Normalisation collapsed all endings to LF and re-expanded uniformly, so
  it is content-preserving by construction; the file is now CRLF-only, 0 bare LF. Keep it that way -
  a mixed file makes `.Contains` anchors fail unpredictably against multi-line search strings.