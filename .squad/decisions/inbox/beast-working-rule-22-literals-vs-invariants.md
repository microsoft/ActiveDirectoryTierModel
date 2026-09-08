# Decisions — Beast, 2026-09-07 16:35 — Working rule 22 added (literals vs invariants)

**Agent:** Beast · **Requested by:** Joel Platek (standing ruling) via the coordinator (scope extension) · **Branch:** `feature/enable-verbose-debug`
**Files touched:** `.squad/skills/verification-discipline/SKILL.md`, `.squad/agents/beast/history.md`, this record. Nothing staged, nothing committed. `CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\` touched. `.research\known-bugs.md` NOT modified (verified unchanged at 14,899 bytes).

## D-1 — Rule 22 added under a standing ruling, not a new decision

Joel had already ruled that working rules belong in `.squad/skills/`. Adding rule 22 therefore needed **no fresh ruling from Joel — only a scope extension from the coordinator**, because the preceding brief was scoped `.research\` only. Recorded so nobody later reads this as an unapproved edit to a Joel-owned artifact.

## D-2 — The rule, as written

> **A literal encodes today's answer; an invariant encodes the relationship that makes any answer correct.**

Rule 19 is the production-side of this problem (a string literal in a filter that silently becomes a deny-all). **Rule 22 is the assertion side.**

**Evidence it is grounded in, not the aphorism:**

| | Old | New |
|---|---|---|
| Test 464 asserted | `Should -Be 9` | `Compliant + Drift + Errors == Findings.Count`, all three verdict states reconciling |
| Catches re-multiplication | at one config size | at **any** config size |
| Survives a legitimate ruling | **no — died with it** | yes |
| Rewritten when the system changes | every time | **only when the system is wrong** |

When Joel ruled the per-right rows out of `$findings`, the literal `9` became wrong and **the test died with the behaviour it was pinning.** Wolverine's control **F1** proved the replacement strictly stronger: re-adding the ruled-out per-right rows **fails 2 tests without any test knowing the number 9**.

## D-3 — The counter-case is IN the rule, deliberately

**"Literals are bad" would be a worse rule than the one it replaced.** So the rule carries its own limit: **literals are correct when the number IS the specification, not a consequence of it.** Joel's ruling that a `Pass` row renders **zero** lines is a *decree* — nothing derives it, it is the requirement itself, and pinning it exactly as `0` is how a violation of the ruling gets detected.

**The discriminator is derived vs decreed**, and it generalises beyond tests. Derived numbers are consequences of a computation and belong in an invariant. Decreed numbers are the specification and belong in a literal. Closing line kept because it is the operative part: *if you cannot say which one you are looking at, you do not yet understand what the test is for.*

## D-4 — Four stale references updated; this is substantive, not housekeeping

Frontmatter description (21→22 rules), Patterns preamble, one Context routing bullet, one Anti-Patterns pointer.

**Rationale:** agents load `.squad/skills/` at spawn, so **a rule nobody can route to is a rule nobody applies.** That was the whole argument for promoting these from a document to a skill. Appending rule 22 and leaving the routing stale would have produced a file that is technically 22 rules and **functionally 21** — the failure mode of a reference document is unreachability, not wrongness. This is the same defect shape as BUG-044, which shipped because rule 19 existed but was not in anyone's hands.

## D-5 — Contiguity asserted as an invariant, not a literal

The count was **not** eyeballed. Every `^\d+\. \*\*` heading was extracted from the Patterns section and the sequence set-compared against `1..22`: **22 found, 22 distinct, exact, no gaps, no duplicates, no extras.**

**This is rule 22 applied to rule 22's own file.** The rule count is *derived* from the rule list, so pinning it by eye is exactly the failure the rule describes — and it had already failed once, when a brief cited 20 against an actual 21. Rules 1–21 confirmed byte-identical afterwards via `.Contains()` on anchors in rules 1, 19 and 21 (including rule 21's 86-file table). Nothing renumbered, nothing reworded.

## D-6 — No rule has been superseded

Re-checked on the earlier promotion and again here: none of rules 1–21 has been contradicted by later work. Rule 22 **extends** rule 19 across the production/assertion boundary; it does not replace it. Both stay.

## D-7 — Scope was held twice and the resolution is now standing policy

I declined to write my own `history.md` on the previous turn because the brief said "nothing else". The coordinator's ruling: **asking is the correct resolution, not excessive literalism** — the failure mode that matters is an agent widening its own scope *quietly*.

**Standing clarification, recorded for future briefs:** an agent's own `history.md` and a decision record for work just completed are **always in scope unless explicitly excluded**. They are the record of the work, not new work.

## Open items carried forward (unchanged by this session)

1. **BUG-052** — empty scope reads clean. Blocked on Joel's ruling (is there a `NOT CONFIGURED`/`SKIPPED` state, what is it called, does it affect verdict and exit code).
2. **BUG-053** — ADMX `default { 'Gray' }`. **Unassessed, no severity assigned.** Triage from the producer first; the arm may be dead code. Rogue triaging read-only.
3. **BUG-050** — UPN. Deferred to v2.1.1, **do not touch during v2.1.0.**
4. **`git add -f` still required** for `.squad/skills/verification-discipline/SKILL.md` and everything else new under `.squad/` — `.git/info/exclude:9` hides new `.squad` paths from `git status`. Joel has ruled this happens later; not actioned here.

**v2.1.0 ready-to-fix count: 0.** Next free bug ID: **054**.