# Decision: Design scope lives under `specs/`, not `docs/` — plus specs 006 and 007

**Author:** Storm (DevRel & Documentation)
**Date:** 2026-09-05
**Branch:** `feature/enable-verbose-debug`
**Requested by:** Joel Platek

---

## Decision 1 — `docs/` is a governed publishing surface; design scope goes under `specs/`

`docs/` publishes to GitHub Pages. Joel's ruling: **"New docs must have my approval as this will go public
on github pages and I dont need this info there."**

- No new file may be created under `docs/` without Joel's personal approval.
- Design proposals, scoping arguments and open-question registers belong in a numbered `specs/NNN-*/`
  folder, alongside `spec.md` / `plan.md` / `tasks.md`.
- `docs/design-scope-publish-guard.md` was relocated to `specs/007-scope-publish-guard/spec.md` and deleted.

## Decision 2 — A feature gets its numbered spec folder, retroactively if we skipped the step

`specs/006-verbose-debug-logging/` was created after the fact for the `-EnableVerbose` / `-EnableDebug`
feature. Retroactive specs are marked as such at the top and are written **from evidence on disk**, not from
memory. Completed tasks are ticked only where the code was read and confirmed.

## Decision 3 — Scope publish guard is DEFERRED to v2.2.0, and the reason must be stated accurately

Joel deferred it. The correct rationale is **not** "it is rare":

- Six defects (BUG-027/028/030/032/034/036) shared one root cause — every scope branch populates the shared
  reporting variables by hand and nothing verifies that it did; console right, saved artifact silently wrong.
- **All six are individually fixed**, so no v2.1.0 user is exposed.
- The guard is regression insurance against a future seventh instance. Its value is entirely prospective,
  which is why deferring costs a v2.1.0 user nothing.

`specs/007-scope-publish-guard/plan.md` is a deliberate stub: nobody has scoped the work, and two open
questions (throw vs log-loudly; branch 5 `-OuAclOnly` normalisation vs `-PreNormalised` escape hatch) must be
answered by Joel first.

---

## Corrections others should carry forward

1. **Line-number anchors for the diagnostics feature (measured 2026-09-05):**
   - `Deploy-TierModel.ps1` — switches L239/L242; auto-logging + prompt rule L286–L310; announcement L361;
     `Debug\` folder L370–L388; preferences **L714–L728**; transcript **L743–L765**; guarded stop L481–L511;
     re-run hint L517–L562.
   - `Audit-TierModel.ps1` — switches L213/L216; auto-logging L534–L545; announcement L604; `Debug\`
     L626–L644; preferences **L693–L707**; transcript **L721–L743**; guarded stop L414–L441; hint L447–L493.
   - The previously circulated ranges (Deploy L716–722 / L736–762, Audit L695–701 / L719–725) are stale.
2. **WI-18 / decision D9 is NOT implemented.** A scan of `modules/TierModel/public/` found **zero** AD or
   GPO invocations carrying an explicit `-Verbose`. It remains gated on POC-5 / lab evidence. It is listed as
   not-started in `specs/006-verbose-debug-logging/tasks.md`, not as complete.
3. **The stub harness path is `tests/helpers/ADStubs.ps1`**, not `tests/ADStubs.ps1`.
4. **The "49 rows / 57 rows" lab-matrix figure could not be found anywhere in `.research/`.** The matrix is
   described in `specs/006-*/tasks.md` by its sources (`.research/verbose-debug-implementation-plan.md`
   §WI-19 — 21 rows — plus `.research/test-plan-verbose-debug-v2.md`) and by its state: **built, not run**.
5. **The publish-guard source document counts SIX instances**, not seven, and argues about preventing
   "instance seven". `specs/007-*/spec.md` preserves the document's own arithmetic and flags that the
   register at `.research/known-bugs.md` is authoritative if a seventh has since been identified.

## Standing constraint recorded for everyone

The customer incident that motivated the diagnostics feature is **formally closed with an UNKNOWN cause**.
No spec, plan, task, code comment, help text, doc page or commit message may assert or imply a cause — and
nothing may promise the switches will reveal why a GPO failed (`New-GPO -Verbose` yields zero records).
