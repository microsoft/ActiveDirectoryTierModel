# Decision — the bug register lives ONLY in `.research\known-bugs.md`

**Author:** Beast (Core Dev)
**Date:** 2026-09-05
**Branch:** `feature/enable-verbose-debug`
**Requested by:** Joel Platek

## Decision

`.research\known-bugs.md` is the single authoritative defect register. `docs\known-bugs.md` has been
**deleted**. The register must never be duplicated into `docs\`.

**Rationale (Joel, verbatim):** *"The Known bugs shouldnt be under docs it is under .research please
merge with the existing. New docs must have my approval as this will go publich on github pages and
I dont need this info there."*

`docs\` is **not** git-ignored and publishes to GitHub Pages. `.research\` is git-ignored
(`.git/info/exclude:23`). Internal defect detail — unfixed security findings, CI blind spots,
customer-incident context — must not be published.

**Any new file under `docs\` now requires Joel's personal approval.**

## Register structure (follow this)

Organised by **status**, per the file's own numbering convention:

1. **Open Bugs** — currently none.
2. **Fixed on this branch — pending migration to `CHANGELOG.md`** — BUG-019 and BUG-024..BUG-038.
   These are to be **MOVED, not copied**, into `CHANGELOG.md` under `[2.1.0]` at release-prep time,
   and then **deleted** from the register. Each entry carries enough detail that the CHANGELOG
   author does not have to re-derive anything.
3. **Outstanding work — not numbered defects** — the catch-block triage and the CI
   test-infrastructure gap.

**Next free ID: `BUG-039`.** IDs are never reused.

## Findings the team should know

**1. Three bugs were carried as open after being fixed.** BUG-034, BUG-037 and BUG-038 are all fixed
in the working tree, verified against source on 2026-09-05. **There are now zero open numbered
defects** — 20 of 20 fixed, not the 18-of-20 previously assumed. Re-verify a bug's status against
source before quoting it; the register goes stale faster than the code.

**2. BUG-019 and BUG-035 verified closed by independent AST sweep.** Product code (entry scripts,
`modules\`, `optional\`) contains **zero** AD/GroupPolicy reads without an explicit `-ErrorAction`:
243 `Stop` / 78 `SilentlyContinue` / 0 none. The 102 remaining bare call sites in the repo are all
under `.research\` in PoC and lab scripts, which are not shipped.

**3. The empty-catch figures reconcile — they were two different populations, both correct.**

| Measure | Count |
|---|---:|
| Syntactically empty `catch {}` (what PSScriptAnalyzer sees) | **66** |
| — of which rationale is documented (28 in-catch + 8 in the enclosing `try`) | 36 |
| — **undocumented** | **30** |
| `catch` clauses whose statements emit nothing (analyzer is blind to these) | **118** |
| — of which correctly append to `$planErrors` / `$warnings` | 46 |
| — **lossy** | **72** |
| **Real information-loss population (30 + 72)** | **102** |

**Un-excluding `PSAvoidUsingEmptyCatchBlock` flags 66 and misses 72 — roughly a third of the real
problem is invisible to the rule.** Turning it on is worth doing; do not mistake a clean rule run
for a clean codebase.

**4. The `Test-TierModelAuthPolicy` (6) / `Test-TierModelAuthSilo` (5) cluster is BENIGN.** All 11
are `try { $x = $obj.Prop } catch {}` — the StrictMode optional-attribute probing idiom, where
`$null` is the correct handled answer. They must **not** be triaged as swallowed failures. The
earlier framing that grouped them with the worst offenders was true about the count and misleading
about the risk.

**5. The original customer incident (two GPOs silently failing) is formally CLOSED as UNKNOWN.** No
sentence in the register asserts a cause for it, and any that did have been neutralised. Several
recorded defects share its *shape* — a failure with no visible signal — and fixing them removes the
blindness that made it un-diagnosable. That is a statement about diagnosability, not causation.

## New working rules added to the register

- **Rule 11 — `-ErrorAction Stop` is necessary, never sufficient.** A successful read returning a
  blank value is not an error and no error-action setting can see it. Pair every hardened read with
  an explicit value guard. Proven by BUG-035 and again by BUG-038's resolver.
- **Rule 12 — state the population before quoting a count.** The empty-catch figure was reported
  wrong twice because "66" and "102" measure different sets. A number without its population is not
  evidence.
- **Rule 13 — a defect register goes stale faster than the code.** Re-verify status against source.

## Open items for others

- **`CHANGELOG.md` migration (release-prep owner):** move BUG-019 and BUG-024..BUG-038 into
  `[2.1.0]`, then delete them from `.research\known-bugs.md`.
- **Test infra (Wolverine):** `tests\ADStubs.ps1` stubs cannot represent a read failure — a stubbed
  `Get-ADDomain … -ErrorAction Stop` returns `$null` without throwing, so CI is structurally blind
  to the entire BUG-019 class even with perfect tests.
- **BUG-031 regression test is owed** and must use `Write-Error` (non-terminating), not `throw`.
- **CI (decision needed):** extending ScriptAnalyzer to the two entry scripts is **free — 0
  findings**. `optional\` being unlinted is one of the three reasons BUG-035 survived.
