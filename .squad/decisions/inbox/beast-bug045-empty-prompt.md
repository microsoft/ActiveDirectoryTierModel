# Decision record — BUG-045 / BUG-046 registration (empty answer at the `-OutputFileBase` prompt)

**Agent:** Beast
**Date:** 2026-09-07 ~11:40 (+08:00)
**Branch:** `feature/enable-verbose-debug` — HEAD `04ab664`
**Requested by:** Joel Platek, from a live lab session
**Scope:** Registration only. **No product code touched. Nothing staged. Nothing committed.**
**Sole file edited:** `.research\known-bugs.md`

---

## Outcome

Two IDs registered, both **OPEN**:

| ID | Site(s) | Provenance | Severity |
|----|---------|-----------|----------|
| **BUG-045** | `Deploy-TierModel.ps1:305-310` (Joel's repro) and `Audit-TierModel.ps1:524-528` | **MIXED** — Deploy pre-existing, **Audit feature-introduced** | **High** |
| **BUG-046** | `Audit-TierModel.ps1:487-491` (`-OutputFormat`) | Pre-existing | **Medium-High** |

Register totals moved **44 IDs / 44 fixed / 0 open / next free 045** →
**46 IDs / 44 fixed / 2 open / next free 047**.
Pending-CHANGELOG migration count is **unchanged at 22** — BUG-045/046 are open, not fixed, so
they do not belong in that section.

---

## Decision 1 — three sites, two IDs (not one, not three)

**Sites 1 and 2 are ONE defect (BUG-045).** Identical condition, identical prompt, identical throw
string, and — decisively — **identical fix**: fall back to the default already present in the
sibling `if` branch. Splitting them invites one being fixed and the other left, which is exactly how
the shape spread from Deploy into Audit in the first place.

**The `-OutputFormat` site is a SEPARATE ID (BUG-046).** Not because it is a different failure
mode — it is the same one — but because **its fix is not free**. BUG-045's fix copies a value that
already exists two lines away and was already approved under D8. BUG-046 has **no auto-enable
branch and therefore no default has ever been chosen**, so fixing it requires a product decision.
A free fix and a fix needing a design call must not sit behind one status flag.

I did not drop the `-OutputFormat` site, and I flagged it prominently: **Joel has not hit it yet.
He will, the first time he asks for a report file without a base name.**

## Decision 2 — mixed provenance is recorded per-site rather than flattened

The register's provenance column is normally one word per ID. BUG-045 cannot honour that. Rather
than force a split for a bookkeeping column's convenience, or flatten two different answers into
one wrong word, provenance is recorded **per site** inside the entry. Noted explicitly in the entry
so it is not "tidied up" later.

---

## PROVENANCE VERDICT — the brief was half wrong, and Joel needs the correction

The brief's reading was that all three sites are pre-existing and none is caused by the
`-EnableVerbose`/`-EnableDebug` work. **I verified with `git show 04ab664:<file>` as instructed and
that is true for two of the three sites and false for the third.**

**Site 1 — `Deploy-TierModel.ps1` `-Logging` — PRE-EXISTING. Confirmed.**
`git show 04ab664:Deploy-TierModel.ps1` → `L196: [switch]$Logging,` / `L233: if ($Logging -and -not
$OutputFileBase) {` / `L234: Read-Host` / `L236: throw "OutputFileBase cannot be empty when Logging
is enabled"`. `git diff 04ab664 -- Deploy-TierModel.ps1` shows the throw line changing
**indentation only** (it moved into the new `else`). **Joel's own repro is not his release's fault.**

**Site 3 — `Audit-TierModel.ps1` `-OutputFormat` — PRE-EXISTING. Confirmed.**
`git show 04ab664:Audit-TierModel.ps1` → `L221-224`, verbatim including the throw string.

**Site 2 — `Audit-TierModel.ps1` `-Logging` — FEATURE-INTRODUCED. This contradicts the brief.**
At `04ab664`, `Audit-TierModel.ps1` contains **zero occurrences of the string `Logging`**. There was
no `-Logging` switch, no prompt, no throw. The whole block is a `+` addition:

```
git diff 04ab664 -- Audit-TierModel.ps1
+    [switch]$Logging,
+        $OutputFileBase = Read-Host "Enter base filename for logs (...)"
+            throw "OutputFileBase cannot be empty when Logging is enabled"
```

**Plainly stated for Joel:** the bug you hit is older than your release. But the *identical* bug now
sitting in Audit is **new code this release wrote**, by porting Deploy's bad shape across alongside
the good D8 branch. The release did not merely reveal that instance — it created it, and it is the
release's to own.

**Knock-on correction made in the register:** the restart card asserted *"Only BUG-024 and BUG-025
in this entire register are feature-introduced."* That is now stale and was corrected in place. The
feature-introduced set is **BUG-024, BUG-025, and BUG-045 (Audit site only)**.

---

## SEVERITY READ — High for BUG-045, Medium-High for BUG-046

**High**, which is higher than the blast radius alone would suggest:

1. **Hard stop, not degradation.** The run aborts before doing any work. Every other defect in the
   register (BUG-039…044) produced a *wrong artifact*; this produces *no run at all*.
2. **The trigger is the single most likely operator action that exists.** A prompt with no stated
   default invites Enter. This is not an edge case — it is the default path through the prompt.
3. **The invocation is documented and reasonable.** `-Logging` with no base name is precisely what
   an operator types when they want a log and do not care what it is called.
4. **It is a diagnosability defect, which is this release's entire subject.** The operator asking
   for a log file is the operator who already suspects something is wrong. Refusing to run is the
   worst available response to that request.

**Not Critical:** it fails loudly and early, before any AD change; the workaround is one parameter;
and it cannot corrupt an estate, lose findings, or produce a false verdict — which is what separates
it from BUG-038 and BUG-044.

BUG-046 is rated one notch lower **only** because it has not been observed in the lab, not because
the failure is any softer. Note the trap: if BUG-045 is fixed and BUG-046 is not, two prompts ~35
lines apart in the same file will behave differently.

---

## GUARD RAILS recorded for whoever fixes this

- **The prompt is NOT the bug and must not be removed.** `specs\006-verbose-debug-logging\spec.md`
  **FR-007** mandates it for the explicit path. The defect is solely what happens **after an empty
  answer**.
- **Do not collapse the two branches into one.** `$script:LoggingAutoEnabled` is load-bearing;
  FR-007 requires the two paths be *"distinguished by an explicit flag, not inferred"*. Once both
  branches share a default value the temptation to merge them is obvious — and it would destroy the
  D8 guarantee.
- **The auto-enabled never-prompt behaviour is lab-proven 28/28 and must not regress.**
- **The correct fix is a fallback, not a throw:** on empty/whitespace input use the same default the
  auto-enabled branch uses (`'Deploy-TierModel'` / `'Audit-TierModel'`), and echo which name was
  chosen. BUG-046 has no such default and needs Joel to pick one.

## Observation passed to Storm — NOT acted on (specs\ is not mine)

FR-007 says the explicit prompt is *"existing shipped behaviour, preserved unchanged, **on both
scripts**"*. That is inaccurate for Audit: Audit had no `-Logging` at `04ab664`, so there was no
existing Audit behaviour to preserve. The Audit prompt is **new**, not preserved. Storm's call.

---

## Constraints honoured

- Nothing staged, nothing committed (`git diff --cached --name-only` empty).
- **No product code touched** — `Deploy-TierModel.ps1`, `Audit-TierModel.ps1`, `modules\`,
  `optional\` all read-only.
- `tests\`, `specs\`, `docs\` untouched. **`CHANGELOG.md` never opened** (locked out).
- No test suites run; no scratch files created anywhere in the repo; Joel's lab tree undisturbed.
- BUG numbers appear only in `.research\known-bugs.md` — documentation, not code. The
  no-BUG-numbers-in-code rule is unaffected and nothing was stripped.
- No cause asserted for the original two-GPO customer incident; it remains formally CLOSED as
  UNKNOWN.
- Repo root verified: 13 legitimate tracked files, zero strays.
