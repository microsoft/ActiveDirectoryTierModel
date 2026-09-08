# Decisions — Beast, 2026-09-07 12:40 — by-design rulings stay live; 21 working rules promoted to a skill

**Agent:** Beast · **Requested by:** Joel Platek · **Branch:** `feature/enable-verbose-debug` (HEAD `6725ab3`)
**Files touched:** `.research\known-bugs.md`, `.squad\skills\verification-discipline\SKILL.md` (new). Nothing staged, nothing committed. `CHANGELOG.md` not opened. `Audit-TierModel.ps1` and `modules\` never opened — Rogue is mid-edit.

Refinement of the 13:05 prune, reversing two of its archive decisions on Joel's ruling.

## D-1 — "By design — do not re-file" stays in the LIVE file

Joel: *"yes by defautl do not file, archive is fine for now."* Restored to `.research\known-bugs.md`, trimmed from ~95 lines of narrative to **the two rulings and the reason each is not a bug**.

**Both rulings kept verbatim**, including Joel's own words on the deploy exit code — a ruling paraphrased is a ruling re-litigated. Three things deliberately retained:

- **The discriminator**, which is the line that actually prevents the re-file: *BUG-041/043 were a breakdown that was **wrong or missing**; this is a breakdown that is **right and incomplete by definition**, because Drift for these two producers has a third component.*
- **The expiry condition** on the exit-code ruling — it holds only while deploys stay interactive; a `-Force`/`-NonInteractive` switch or an unattended service account voids it. A ruling with an unstated premise outlives its premise.
- **The wrong-fix warning** — routing the difference into `UnverifiedCount` (which means *read failures*) to make a header reconcile is "the BUG-026 defect wearing the costume of a fix".

**Live file is now: open count → 3 open bugs (ordered by consequence) → by design. Nothing else.** 13,796 bytes / 254 lines.

## D-2 — The working rules became a skill, not an archive entry

**Path: `.squad/skills/verification-discipline/SKILL.md`** — 15,952 bytes.

**Name chosen to read as technique, not bug history.** The rules are about *how to know a claim about code is true*: proving absence and zeros, designing checks that can fail, verifying artifacts over consoles, reading a moved number as evidence.

Follows `.squad/templates/skill.md` exactly — frontmatter (`name`, `description`, `domain`, `confidence`, `source`) plus **Context / Patterns / Examples / Anti-Patterns**. The rules occupy **Patterns** untouched; Examples expands the three whose stories are most often needed in full (14, 16, 19); Anti-Patterns are terse derived pointers **explicitly marked as derived, with the rules stated as authoritative where the two differ**.

## D-3 — There are 21 rules, not 20 — and all 21 moved

Joel's instruction said 20. **His count was one edition stale:** rule 21 (*state the population and the enumeration rule beside any zero*) was added earlier the same day. All **21** moved. Reported rather than quietly moving 20, which would have orphaned the newest and least-embedded rule in an archive nobody reads.

**Verbatim transfer verified mechanically, not by eye.** The rules block was extracted to a scratch file outside the repo, inserted by variable, then asserted: `$skill.Contains($original)` → **True**, with rule numbers **1-21 all present** and none renumbered, merged or reworded. "Verbatim" is a factual claim and deserves a check that could fail — rule 21 applied to my own work.

## D-4 — Confidence: **high**

Joel's read, and I agree — but set on my own evidence rather than deferred:

1. Earned from ~46 real, shipped defects, not from theory.
2. Several were **independently re-derived by different agents**, which is weak replication but real.
3. **Rules 14, 16 and 19 each went on to find *further* bugs after being written.** This is the actual argument: a rule that has made a **novel prediction** is in a different class from one that merely describes what already happened.

Honest limits, so the level is defensible rather than promotional: they are drawn from **one codebase, one language, one team**, and the PowerShell/Pester specifics in rules 3 and 5 will not transfer verbatim. The *techniques* generalise; some examples do not.

## D-5 — Nothing superseded, checked deliberately

The instruction was *"if any rule has been superseded or contradicted by later work, say so — do not silently drop it."* Checked: **no rule has been falsified.**

The one relationship worth naming is **rule 1 ↔ rule 14**: rule 14 records that rule 1's technique (console vs artifact) *stopped working* once both outputs were rendered from the same variables. That is a **limit, not a contradiction** — and rule 1 already carries it in its own text ("this only detects a *disagreement*. See rule 14"). Both stay, unaltered.

## ⚠️ D-6 — CORRECTION FOR JOEL: the new skill is INVISIBLE to git

**Joel predicted the skill file would show in `git status` as new work. It does not.**

- `.git/info/exclude:9` excludes `.squad/`, and `git check-ignore -v` confirms it matches `.squad/skills/verification-discipline/SKILL.md`.
- The 131 existing `.squad` files are versioned only because they were **already tracked** before that rule mattered. **Exclude never affects tracked paths** — the half of the rule Joel had right. **It does fully hide new ones** — the half that bites here.

**Consequence: the skill sits in exactly the unprotected position `known-bugs.md` was in** — no history, no recovery, absent from `git status`, and it will be silently missed by any "commit everything that changed" pass. **It needs `git add -f` to be versioned.**

**I did not run it.** Staging is Joel's, and unstaged-and-flagged beats staged-and-unmentioned.

## Constraints honoured

- Nothing staged, nothing committed. `CHANGELOG.md` never opened. Product code, `tests\`, `specs\`, `docs\` untouched.
- `Audit-TierModel.ps1` and `modules\` never opened — Rogue mid-edit.
- CURRENT_DATETIME used verbatim: **2026-09-07T12:40:00+08:00**. Repo root still 13 files, zero strays; scratch file cleaned up outside the repo.

## Tree state for Joel

`git status` shows three modified files, none of them stray: **`Audit-TierModel.ps1`** and **`modules/TierModel/public/Test-TierModelWinLapsDecryptor.ps1`** are Rogue's in-progress fix; **`.squad/agents/beast/history.md`** is Beast's uncommitted history appends. The two `.research\` files and the new skill are all git-excluded and appear nowhere.
