# Decision record - Beast - 2026-09-07 17:45

## Working rule 23 promoted: six instances make a pattern

**Decision.** The coordinator ruled that "a rule that exists, is correct, is commented, and was
applied unevenly" has stopped being an observation and become a pattern, and that it changes how this
codebase should be searched. Written into
`.squad\skills\verification-discipline\SKILL.md` as **rule 23**.

**The rule.** Finding the correct implementation of a rule is the **start** of the search, not the
end. On finding a guard, comment or remedy that is right, ask **"where else should this be, and is
it?"**

**Grounded in six sites so it is checkable:**

- `Audit-TierModel.ps1:1774` has the errors-must-not-render-green guard; `:2381` does not (BUG-055).
- `Test-TierModelOu` has `UnverifiedCount` and the comment "an OU we could not read is not a pass";
  `Test-TierModelGroup` and `Test-TierModelUser` do not (BUG-056).
- 5 of 7 compliance sites guard `totalChecked -le 0`; `:1116` (GPO) and `:2120` (ADMX) do not
  (BUG-052).
- `Test-TierModelGPOAudit.ps1:438-462` got the real-count fix; `Audit-TierModel.ps1:1168` was the
  render site the same fix missed (BUG-054) - while `CHANGELOG.md:25` called it "the highest-leverage
  fix on this branch".

**Corollary recorded:** a fix that repairs a producer is not finished until every render site of that
producer has been checked. **Diagnostic value recorded:** the correct implementation is the cheapest
available oracle - you diff against a decision already made rather than guessing at intent.

**Verification.** Contiguity 1-23 confirmed by set-comparing extracted `^\d+\. \*\*` headings against
`1..23` with `Compare-Object`, not by eye. Four cross-references updated (frontmatter count, Patterns
preamble, Context routing bullet, Anti-Patterns pointers).

## BUG-057 registered - a false green in the harness

`tests\Unit.ModuleManifest.Tests.ps1:399` asserts `Should -Match '1\.1\.0'` against a `2.1.0`
manifest and passes only because `1.1.0:` survives among historical entries.

**Classification recorded explicitly:** same defect class as BUG-054, BUG-055 and BUG-056 - a green
signal that does not mean what it appears to mean - except it sits in the harness rather than the
product. **A false green in a test is worse than a red, because a red gets looked at.**

**Sequencing is the decision, not the fix itself.** The `2.1.0` ReleaseNotes entry does not exist and
must be written first (Joel-or-Scribe only; pairs with the outstanding `CHANGELOG.md [2.1.0]`
section). Only then is the assertion repointed at the manifest's own `ModuleVersion`. Wolverine's
instruction not to adjust the assertion in the meantime stands and is recorded with its reason: a
knowingly false green is worse than a red we have chosen to schedule.

Headline corrected to **5 open** before the entry was written. Next free ID **058**.

## SKILL.md line endings normalised, and a gotcha earned

Mixed 151 CRLF / 114 LF from an earlier append, normalised to CRLF-only (19,483 B -> 23,832 B, CRLF
316, LF 0). Collapse-then-re-expand is content-preserving by construction.

Three verification gotchas added to Anti-Patterns. The first was hit for a third time **in this run**
and caught before reporting: `.Contains` against a phrase that wraps a line break reports missing text
that is present. The other two: backticks and `$` silently vanishing inside double-quoted PowerShell
search strings, and `(?m)^...$` returning a confident zero against CRLF text.

## Outstanding for Joel

- `git add -f` is still required for new `.research\` and `.squad\` files - both trees are
  git-excluded, so nothing here appears in `git status`.
- BUG-052 still awaits Joel's behaviour ruling.
- BUG-055 needs no ruling from anyone and can be picked up immediately.
- The "abort error names neither the file nor the section" usability observation remains recorded but
  unassessed, and deliberately unfiled.