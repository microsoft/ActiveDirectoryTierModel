# Decision — WI-18/D9 deferral and the release taxonomy (Storm, 2026-09-05)

Recorded in `specs/006-verbose-debug-logging/spec.md` as **D11** and **D12**, with pointers in
`plan.md` (locked-decisions table) and `tasks.md` (new "Deferred — NOT v2.1.0 WORK" section).

## D-number provenance

The `D`-series is one shared series originating in the decision table of
`.research/verbose-vs-debug-design.md`, which runs **D1 … D10** (D9 = forward `-Verbose` to AD/GPO
call sites; D10 = treat "false success" as a bug fix). Spec 006 quotes D1, D2, D3, D5, D6, D8 from
that same series. Highest ever assigned = D10, therefore **next free = D11**, and D12 follows.
Numbers are never reused. D9 was *not* reused for the deferral — D9 remains the original "do it"
decision; D11 is the ruling that supersedes it.

## D11 — WI-18 / D9 is MEASURED and DEFERRED

Joel, verbatim: *"Defer but include more details for later I need to see examples and if does not
impact v2.1.0 release."*

**Does it impact v2.1.0? NO.** Additive annotation of existing call sites. No FR (FR-001 … FR-020)
depends on it; no test, CI gate or doc page is blocked by it; its absence is the shipped status quo,
not a regression. T018 (the CI `-Debug` prohibition scan) was previously written as "must land
before T016" — that is a one-way dependency, so T018 stays in v2.1.0 and is **not** deferred with
T016.

Measured (four rounds, three instruments discarded; round 3 voided for ANSI corruption):

| Arm | Mechanism | Records naming the target |
|-----|-----------|---------------------------|
| L1 / L2 | preference only, `Write-Verbose` direct / in an advanced function | 1 / 1 |
| L3 / L4 | preference only, hand-written `ShouldProcess` / `New-Item` | 0 / 0 |
| AD1 | explicit `-Verbose`, `Set-ADOrganizationalUnit`, succeeds | 1 |
| AD2 / AD4 | preference only, success / post-resolution refusal | 0 / 0 |
| AD3 | explicit `-Verbose`, `Remove-ADOrganizationalUnit` refused **after** resolution | 1 |
| AD5 | explicit `-Verbose`, target DN **does not exist** | 0 |
| G1 / G2 | `New-GPO`, explicit `-Verbose` / preference only (round 1) | 0 / 0 |

Mechanism: `$VerbosePreference` governs `Write-Verbose` and does **not** enable ShouldProcess
operation descriptions. L3/L4 prove this is a PowerShell behaviour, not an AD quirk. Recorded as
spec finding **M-10**; spec **M-4** was partly falsified and is now annotated.

**Recommendation (Cyclops's, presented as a recommendation): scope to AD *write* sites only; expect
nothing from GroupPolicy.**

## D12 — Release taxonomy

Joel, verbatim: *"Since these are bugs they will most like be v2.1.1 and v2.1.2 type releases at the
end not a feature release level."*

- Bug fixes (BUG-nnn register) → **PATCH**: `v2.1.1`, `v2.1.2`
- New capability / new parameter surface → **MINOR**: `v2.2.0`
- Breaking change → **MAJOR**: `v3.0.0`

**Recommended target for WI-18: `v2.2.0`**, alongside spec 007's scope publish guard. WI-18 fixes no
defect and closes no BUG-nnn, so under D12 it is feature work and must not ride a `v2.1.x` patch.

Spec 007 is unaffected: its deferral rests on its own four preconditions and its `plan.md` stays a
deliberate stub with OQ-002 / OQ-003 open for Joel.

## Corrections to the brief I was given (evidence over summary)

1. **"That record only appears when the write is refused AFTER the object resolves" is too narrow.**
   AD1 shows the record on a **successful** write too. The correct statement is: present on success
   and on post-resolution refusal, absent only when the target does not resolve.
2. **The GroupPolicy zero is from round 1 (G1/G2), not round 4.** Round 4 has no GroupPolicy arm at
   all, and the GPO number was never re-measured after round 4 rehabilitated round 1's instrument.
   The structural facts (script module, proxy function, `WinPSCompatSession`) are independently
   checkable; the numeric `0` is reported, not re-proven.
3. **Round 4's own `$ladderOk` self-check declares the round VOID when `L3 = 0`** — which is exactly
   what was measured. The conclusions survive only because AD1/AD3 are an independent positive
   control that the script's boolean does not account for. The verdict is sound; the codified check
   is wrong and must be fixed before anyone re-runs it.
4. **No `New-AD*` cmdlet was ever measured, in any round.** Every AD arm used `Set-` or
   `Remove-ADOrganizationalUnit`. `New-AD*` is the product's largest write population and its
   ShouldProcess target-string shape is assumed, not measured.
5. **No raw measurement log is retained in-repo.** `.research/lab-validation/results/` is empty; the
   numbers come from Cyclops's run report and `LAB-RUN-PROGRESS.md`. Recorded as such rather than
   presented as reproducible-on-disk.
6. **Stale cross-reference fixed:** `plan.md` cited "T014" for the CI AST prohibition scan; that is
   **T018** in `tasks.md` (T014 is the ADStubs repair).
7. **"Our own `Write-Verbose` instrumentation works under `-EnableVerbose`" is not a round-4 result.**
   L1/L2 are bare-preference probes in a standalone script that never import TierModel and never run
   Deploy or Audit. They establish the mechanism only. The product-level evidence is the 50-row lab
   matrix (RUN 1, 0 FAIL) and round 1's module-scope arm A3.

## Durability note

Storing project conventions in agent memory has failed with *"repository was not found"*. The spec
files are the durable home for decisions — that is why D1 lives in `spec.md` and why D11/D12 do too.

## Constraints observed

Nothing staged, nothing committed. No file under `docs/` created or modified. Only
`specs/006-verbose-debug-logging/{spec,plan,tasks}.md` touched. No cause asserted for the original
customer incident — it remains formally CLOSED as UNKNOWN. The `-Debug` prohibition is restated in
D11 and remains unmissable in both the spec and the plan.
