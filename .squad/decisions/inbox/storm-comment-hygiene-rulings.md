# Decisions — comment hygiene, test exemption, changelog scope (D13 / D14 / D15)

**Recorded by:** Storm
**Date:** 2026-09-06
**Requested by:** Joel Platek
**Branch:** `feature/enable-verbose-debug` (HEAD `04ab664` — nothing staged, nothing committed)
**Durable home:** `specs/006-verbose-debug-logging/spec.md` (full text) and `plan.md` (decision table).
This inbox file is a pointer, not the authority.

---

## D-number allocation and its proof

The `D`-series is **one shared series**, not per-document.

| Where | Range | Checked |
|---|---|---|
| `.research/verbose-vs-debug-design.md` — origin decision table | **D1 … D10** | Re-read 2026-09-06; still ends at D10 |
| `specs/006-verbose-debug-logging/spec.md` | **D11, D12** (allocated 2026-09-05) | present |
| Everywhere else in the repository | none | searched every `.md` for a `D`-number citation |

Highest in use anywhere = **D12** → next free = **D13**. Allocated **D13, D14, D15**. Numbers are never
reused; D9 in particular stays as the original "do it" ruling with D11 superseding it.

---

## D13 — No bug numbers or bug history in code comments. ALL of Joel's repositories.

Joel, verbatim: *"I dont like you putting all these comments about BUG-029 numbers inline comments in our
code once its been fixed we should remove it... Github and git and committing keeps track of these changes
along with branch and pull request. I dont want all these huge comment blocks in the code the only comment
should be what this code is doing not that it is or was a bug."*

Asked explicitly whether repo-scoped or global, Joel chose **all his repositories**. This is a standing
authoring convention, not a one-off cleanup.

**"Keep the rule, drop the history."** Where a comment encodes a **live, non-obvious constraint**, it
survives as a short **present-tense** statement of that constraint with **no bug number and no story**.
Everything purely historical is **deleted outright**, not reworded.

Does not reach: `tests/` (D14), `specs/`, `.research/`, `CHANGELOG.md`, `.squad/`, PR bodies, commit
messages — those are history by purpose.

**Execution:** Rogue, on product code, **155 mentions across 36 files**. Tracked as `tasks.md` **T024**.

## D14 — `tests/` is EXEMPT from D13.

The ~30 `BUG-nnn` references under `tests\` stay. In a test the bug number is frequently the only record of
why a specific assertion exists; strip it and the next reader deletes the assertion as arbitrary, and the
defect returns. The exemption is narrow — it does not license bug-history prose in product code, and a test
comment should still be one line where one line will do.

## D15 — Bug detail goes in the PULL REQUEST, not `CHANGELOG.md`. The 22-bug migration is CANCELLED.

Joel, verbatim: *"We dont need to detail docoument the bugs like we did its stuff that can go in the PR
later."* Asked how to record the 22 pending bugs (BUG-019 + BUG-024 … BUG-044) for v2.1.0, he chose
**"PR only — do not migrate the 22 bugs into CHANGELOG at all."**

- Migration of the 22 bugs → **cancelled**, not deferred.
- A `[2.1.0]` section in `CHANGELOG.md` → **still required**, describing the **feature**
  (`-EnableVerbose` / `-EnableDebug`) only. Short section.
- Pre-existing `BUG-001` … `BUG-023` entries → **untouched**; they are shipped history.
- `.research/known-bugs.md` → **untouched and still authoritative**. D15 moves bug detail out of the
  *changelog*, not out of the project.
- **Owner of the `[2.1.0]` feature section: Joel or the Scribe.** Explicitly **not Storm** — Storm is locked
  out of `CHANGELOG.md`, and re-scoping the task does not lift that lock.

## Cross-reference (not a new decision)

Joel's 2026-09-05 ruling that the **GPO / WinLapsDecryptor drift-arithmetic residual** is documented and not
fixed is recorded by Beast in `.research/known-bugs.md` under *"By design — do not re-file"*. Spec 006 now
cross-references it; the entry is deliberately **not** duplicated.

---

## Files changed by Storm for this

- `specs/006-verbose-debug-logging/spec.md` — D13/D14/D15 + cross-reference; heading and provenance note
  updated to `D11 … D15`; `Status:` line updated to lab-validated; `Docs to Update` CHANGELOG bullet
  re-scoped.
- `specs/006-verbose-debug-logging/plan.md` — three rows added to the locked-decisions table.
- `specs/006-verbose-debug-logging/tasks.md` — T014 and T015 closed against on-disk evidence; T021
  re-scoped under D15; T024 (comment hygiene), T025 (version/stray sweep), T026 (failing test), T027
  (report-path re-validation) added; counts corrected 23 → 27.

Nothing staged, nothing committed. No product code, no `tests/`, no `docs/`, no `CHANGELOG.md`,
no `.research/` touched.
