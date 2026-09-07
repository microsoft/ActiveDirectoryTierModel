# Decisions — Beast, 2026-09-07 16:05 — BUG-050 deferred to v2.1.1; BUG-053 registered unassessed

**Agent:** Beast · **Requested by:** Joel Platek · **Branch:** `feature/enable-verbose-debug`
**Files touched:** `.research\known-bugs.md`, `.research\known-bugs-archive.md`. Nothing staged, nothing committed. `CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\` touched. `.squad/skills/` deliberately not touched (see D-7).

## D-1 — BUG-050 deferred to v2.1.1 and marked OUT OF SCOPE for v2.1.0

**Joel's ruling, verbatim:** *"the UPN bug will not be part of logging that will be a v2.1.1 release. This is something outside of all the logging and debug work we are doing, so the team shouldnt touch this at this time."*

**Kept in the live file, not archived** — archiving implies closed and it is not. It sits **last**, so the natural reading order never reaches it while looking for work.

## D-2 — The v2.1.0 count was re-derived, because the brief's pre-computed number went stale

The brief computed the v2.1.0-actionable count as **zero** (BUG-050 deferred, BUG-052 blocked). **Registering BUG-053 in the same pass invalidated that arithmetic** — triaging an unassessed item is work a person can pick up. Rather than transcribe a number that had gone stale between being written and being applied, it was broken out:

| For v2.1.0 | Count | Which |
|---|---:|---|
| **Ready to fix — needs a person** | **0** | — |
| Blocked on Joel's ruling | 1 | BUG-052 |
| Open but **unassessed** | 1 | BUG-053 |
| **Deferred out of the release** | 1 | BUG-050 |
| Total entries in file | 3 | |

**"Ready to fix: 0" is the number Joel wants, and it survives the addition.** "Open: 3" would misrepresent the release. Stated at the top: **the release is blocked on two decisions from Joel, not on engineering capacity.**

**"Actionable" had to be defined before it could be counted** — blocked-on-a-decision, unassessed and deferred are three different not-actionable states that collapse into a misleading total.

## D-3 — Do-not-touch made unmissable in FOUR independent places

The ruling's purpose is that nobody picks it up **by accident**, so one banner is insufficient — a reader scanning only headings, only the summary table, or only the entry must each hit it:

1. Header table row: **"Deferred to v2.1.1 — DO NOT TOUCH"**.
2. **The `##` heading itself** carries 🛑 DEFERRED TO v2.1.1 — DO NOT TOUCH. *(Added after checking the heading-only outline and finding it silent — the outline is how this file is scanned.)*
3. A full-width `#` banner above the entry.
4. A blockquote with **⛔ THE TEAM MUST NOT WORK ON THIS BUG**, Joel's verbatim ruling, and an explicit instruction to stop reading and go back up.

## D-4 — The release taxonomy recorded, so the deferral is not re-litigated

| Change | Goes to |
|---|---|
| Bugs | **v2.1.1 / v2.1.2 patch** |
| Features | v2.2.0 minor |
| **A defect introduced *by* v2.1.0** | **must be fixed *in* v2.1.0** |

The UPN defect is **pre-existing and unrelated to the `-EnableVerbose`/`-EnableDebug` work**, so it misses the third rule and lands in the patch bucket. **A deferral without its reasoning is a deferral that gets reversed** the moment someone notices an open bug at release time.

## D-5 — The ordering argument kept visible and explicitly overtaken

Beast argued BUG-050 above BUG-052 on consequence at 15:36; the coordinator agreed and **it has not been withdrawn**. Joel ruled on **scope**. Recorded in the entry rather than silently re-sorted:

> **Consequence decides what to fix first; scope decides which release fixes it.** A defect can be genuinely more consequential *and* correctly deferred.

The entry states BUG-050 now sits last **because it is out of scope, not because the severity argument was lost**. A register that quietly reorders itself teaches nothing; one that shows "argued X, ruled Y, here is why" is worth reading.

## D-6 — BUG-053 registered with NO severity, deliberately

**ADMX `default { 'Gray' }` at two render sites left unconverted by the BUG-047 fix.** It has the *shape* of the BUG-047 family — and shape is exactly what this register has been wrong about before.

**The `default` arm may be dead code.** If every ADMX finding type is explicitly handled above it, nothing reaches it and there is no defect, only a tidiness question. **Assigning a severity now would be a number nobody can defend.**

Triage script written into the entry: (1) enumerate the types the producer actually emits — **from the producer, not the render site**; (2) establish whether the `default` arm is reachable at all; (3) if reachable, decide whether Gray is wrong for those types — it may be correct for informational findings; (4) **only then** assign severity and decide v2.1.0 inclusion. Cross-referenced to the shared colour classifier from the BUG-047 fix: **do not build a third colour path.**

## D-7 — Candidate working rule 22 flagged, NOT added — scope discipline applied to my own work

Test 464's retirement (`Should -Be 9` replaced by reconciliation invariants; control F1 re-adds the ruled-out rows and fails 2 tests **without the test knowing the number 9**) is the assertion-side twin of working rule 19:

> **A literal encodes today's answer; an invariant encodes the relationship that makes any answer correct.** Rule 19 covers a *filter* matching a literal that stops being emitted, silently becoming a deny-all. This is the *assertion* case — and unlike rule 19's, it fails loudly first and then invites someone to "fix" it by editing the number (working rule 9).

Recorded in the archive and **flagged for Joel's approval. `.squad/skills/verification-discipline/SKILL.md` was NOT edited — this session was scoped `.research\` only.** Consistency check: it would be incoherent to enforce BUG-050's scope ruling in one section and breach my own scope in another.

## D-8 — BUG-047 caveat amended precisely: narrowed, not withdrawn

Three distinct claims; **only the first changed.**

| Claim | Before | After |
|---|---|---|
| Is it validated? | No | **Yes — by unit test** |
| Is it lab-validated? | No | **Still no** |
| Can it ever be lab-validated? | (implicit) | **No — by construction** |

Fixing BUG-049's errors removed every `[Error]` finding from a healthy estate, so **no future lab run can close this**. Wolverine's three tests run the **real** `Test-TierModelWinLapsDecryptor` with `Get-GPO` mocked to throw at `:181`, through the **real** normaliser and colour classifier — not a re-implementation. Controls: **E1** (`Error`→Yellow) → **6 failures**; **E2** (relabel that branch) → **4**.

**Standing instruction retained in both copies:** say *"unit-test validated; not lab-validatable, by construction."* **A caveat that gets "updated" into deletion is how a half-true green survives.**

## D-9 — Suite state recorded

**CI-shaped 1980 / 1980 / 0 across 32 containers; coverage 87.36% against a gate of 80 (PASS).** By path: Unit **1650/1650/0**, Integration **330/330/0** — and **1650 + 330 = 1980 exactly**, so **no container or StrictMode divergence between local and CI shape.** That closes the CI-vs-local gap for this work, which mattered because this register already documents what happens when the two shapes differ silently.

## Items still awaiting Joel — do not lose these

1. **BUG-052** — empty scope reads clean. Needs his ruling on whether a `NOT CONFIGURED` / `SKIPPED` state exists, what it is called, and whether it affects the verdict or exit code.
2. **BUG-053** — needs triage first, then a scope decision on whether it ships in v2.1.0.
3. **Candidate working rule 22** (literals vs invariants) — approval to add it to the skill.

## Constraints honoured

- `.research\` only. Nothing staged, nothing committed. `CHANGELOG.md` never opened.
- Live file shape unchanged: **open count → open bugs → "By design — do not re-file"**. 14,952 bytes — still one scroll.
- **"By design" carried across programmatically and asserted byte-identical** (`Contains` → True), not retyped.
- CURRENT_DATETIME used verbatim: **2026-09-07T16:05:00+08:00**. Repo root 13 files, no strays.
