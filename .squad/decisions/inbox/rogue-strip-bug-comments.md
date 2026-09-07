# Strip BUG-nnn comments from product code

**By:** Rogue
**When:** 2026-09-06T09:05..10:15+08:00
**Branch:** feature/enable-verbose-debug (HEAD 04ab664)
**Requested by:** Joel Platek, via Copilot directive
`.squad/decisions/inbox/copilot-directive-20260905-2022.md`
**Status:** DONE — nothing staged, nothing committed. Joel reviews and commits.

---

## The ruling being executed

Joel, twice: inline `BUG-nnn` references and bug-history comment blocks must not survive the fix.
*"The only comment should be what this code is doing, not that it is or was a bug."* Git, GitHub,
branches and PRs already carry that history. Standing preference across **all** his repositories.

Scope: product code only — `Audit-TierModel.ps1`, `Deploy-TierModel.ps1`,
`modules\TierModel\**\*.ps1`, `optional\*.ps1`. `tests\**` explicitly excluded by Joel's ruling
(*"the bug number is often the only record of why an assertion exists"*).

---

## Result

| Measure | Before | After |
|---|---|---|
| `BUG-nnn` comment tokens, product code | 155 | **0** |
| `BUG-nnn` mentions, product code (any context) | 156 | **0** |
| Product files affected | 36 | 0 |
| `tests\**` BUG-nnn mentions | 54 | **54 (untouched)** |
| Unit | 1573 / 1572 / 1 | **1573 / 1572 / 1** |
| Integration | 318 / 318 / 0 | **318 / 318 / 0** |

139 edit operations: **38 blocks deleted outright** (228 comment lines), **60 single-line number
strips** (text otherwise unchanged), **41 authored rewrites**.

Net: 635 comment/blank lines removed, 227 comment lines added.

---

## How each comment was classified

Three populations, not two. The brief assumed two (pure history → delete; live constraint →
rewrite) and predicted "about six" rewrites. The evidence showed a third, much larger population,
and this is the main judgement call in the pass:

1. **Pure history → DELETED.** Anything narrating what used to be broken, what an earlier version
   did, or how the bug was found. Every multi-line story block. Includes ~25 `-ErrorAction Stop`
   justification blocks of the form *"previously a failed read was non-terminating, so $x became
   $null…"*. Deleted without replacement: nobody is going to "fix" an explicit `-ErrorAction Stop`
   back to nothing, so the comment protects nothing. It is pure narration of the fix.

2. **Already present-tense guidance, only the number offends → NUMBER STRIPPED (60 sites).** The
   dominant example is the 26 `# BUG-019: SilentlyContinue is INTENTIONAL here. … Do not change to
   Stop.` comments. These are three-line, present-tense statements of a deliberate choice that a
   maintainer would otherwise "improve" into a defect. Removing the `BUG-019: ` prefix satisfies
   Joel's rule exactly — what survives says only what the code is doing and why. Deleting them
   outright would have removed live engineering guidance he never asked to lose.

3. **Live constraint embedded in a history block → REWRITTEN (41 sites).** Short present-tense
   statement of the constraint, no bug number, no history.

**Test applied when torn:** *would deleting this comment plausibly cause a future maintainer to
write a defect?* If no → delete. This is stricter than "is it interesting", and it is why the
`-ErrorAction Stop` blocks went and the `SilentlyContinue` ones stayed.

---

## Where I overruled the brief

- **"About six rewrites" was too low; the answer is 41.** Reported honestly rather than trimmed to
  fit the number. Of the 41, roughly a dozen are mechanical shortenings of already present-tense
  text (e.g. `# Exactly 4 real .NET GpoStatus members.`). The substantive preserved constraints are
  the `SilentlyContinue`/`Stop` choices, the four `Guid.Empty` fail-closed sites, the four
  BLOCKING-1 "no not-found heuristic" sites, the three `-WhatIf:$false` log-apparatus sites, the
  `$OFS`/`-join` site, the `'='` vs `'+='` ErrorCount site, the "do not recompute drift globally"
  site, and the two GPO/WinLapsDecryptor arithmetic residuals Joel personally ruled on. Full
  before/after for all 41 is in the session artifact `rewrites-before-after.md`.

- **The named sibling raw-path sites do not exist as comments.** The brief listed four deliberate
  raw-path `Identifier` sites: `Test-TierModelOuAcl.ps1` plus `Test-TierModelMsaAcl.ps1:129`,
  `Test-TierModelGmsaAcl.ps1:129`, `Test-TierModelDmsaAcl.ps1:139`. The three MSA/gMSA/dMSA files
  contain **no `BUG-` comments at all** — those catch blocks are entirely uncommented. Nothing to
  strip. I did **not** add new comments there: Joel's directive is toward less commentary, and
  adding some would have been out of scope. Only the `Test-TierModelOuAcl.ps1` site was rewritten.

- **`tests\` holds 54 `BUG-nnn` mentions, not 30.** Eight files. Untouched either way; the four
  modified test files in `git status` are yesterday's work, present before this pass began.

- **The requested verification could not be run as specified.** The brief asked for `git diff`
  restricted to product code to contain only comment/blank removals. That check is impossible here:
  all 36 product files already carried **uncommitted** BUG-039..044 work, so `git diff` against
  HEAD (04ab664) shows yesterday's changes too — 1822 added / 231 removed lines, mostly not mine.
  See the verification section for what I did instead.

- **`.squad/agents/rogue/charter.md` does not exist.** Only `history.md` is present. Every other
  agent directory is likewise charter-less. Flagging rather than inventing one.

---

## Verification

**1. Pre-edit safety (AST, on the pre-pass files).** All 139 target ranges were proved to contain
only `Comment` tokens or blank lines, with no overlaps. This caught a real defect before it landed:
one range (`Resolve-TierModelPrincipalSid.ps1` L473..L489) spanned three lines of executable code
including a `Get-ADObject` call. Split into two ops. A naive line-based strip would have deleted it.

**2. Coverage.** All 155 census tokens fall inside an op range. The single reported exception is the
comment-based-help block in `Audit-TierModel.ps1`, where only the `.DESCRIPTION` sub-range was
replaced — deliberate.

**3. Reconstructed baseline + round-trip.** Because `git diff` was contaminated, the pre-pass state
of all 36 files was reconstructed from the AST context dump, with **0 unrecovered lines**. Proof
the reconstruction is faithful: re-applying the 139 ops to it reproduces the current working tree
**byte-for-byte in all 36 files** (0 mismatches).

**4. Diff-shape proof (pre-pass baseline → working tree).**
```
lines REMOVED: 635      lines ADDED: 227
REMOVED lines that are NOT a comment or blank : 0
ADDED   lines that are NOT a comment or blank : 0
ADDED   lines containing 'BUG-'               : 0
```

**5. Independent AST cross-check.** Non-comment token streams compared either side: **identical in
all 36 files.** The first run of this check reported 26 files "changed" and contradicted the
line-based proof; the cause was `NewLine` tokens (removing comment lines removes newlines).
Excluding `NewLine`, 0 differences. The contradiction was chased rather than the favourable result
accepted.

**6. Parse + BOM.** 84 product files parse with 0 errors. `Audit-TierModel.ps1` and
`Deploy-TierModel.ps1` both re-verified at `EF BB BF` after the final write.

**7. Suites, run once each by path.** Unit 1573 / 1572 / 1; Integration 318 / 318 / 0. Exactly the
expected baseline. The single failure is the known `Unit.OuAclOperations.Tests.ps1:981`
("Sets Type='Drift' on the ACEProperties finding") — Wolverine's to repair, not touched here.

---

## Open item for Joel

The 41 rewrites are the reviewable surface. If Joel wants the number closer to six, the population
to cut is category 2 above — the 26 `SilentlyContinue … Do not change to Stop` comments and the
similar short constraint notes. I kept them because deleting them removes the only in-code warning
protecting a deliberate choice, and because with the number gone they already comply with his rule.
That is a judgement he can reverse cheaply; the deletions cannot be reversed cheaply.

Related: BUG-019 + BUG-024..044 are still pending migration into `CHANGELOG.md` under `[2.1.0]`.
That migration is now the *only* home for the history stripped out here.
