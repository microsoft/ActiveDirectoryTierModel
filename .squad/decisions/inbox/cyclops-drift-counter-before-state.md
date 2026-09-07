# Decision record — Audit drift-counter defect: pinned PRE-FIX baseline

**Agent:** Cyclops
**Date:** 2026-09-07
**Requested by:** Joel Platek
**Build measured:** commit `23b5100`, exported with `git archive` (NOT the working tree)
**Fixture:** `TierLab-DC01` @ checkpoint `WinLapsSchema`, undeployed estate
**Full evidence:** `C:\CyclopsStage\run-20260907-124147\FINDINGS-drift-counter-before-state.md`
**Raw logs:** `C:\CyclopsStage\run-20260907-124147\final\` (clean UTF-8) and `..\run-20260907-124147\`

---

## D1 — Staged with `git archive`, not a worktree, and not the working tree

**Decision:** `git archive 23b5100 | tar -x` into `C:\CyclopsStage\build-23b5100`.

**Proof:** 698/698 tracked blobs match the commit. Staged `Audit-TierModel.ps1` =
`825009aa9cd25886ca7609d028b2380aefa9f4c1`, identical to the commit blob. The repo working-tree
copy = `7dd376034557dc46dd977961aedf2d33344b8652`, already **+122/−4 lines**. Guest transfer
re-verified by SHA256 manifest, delta 0.

**Why it mattered:** this was not hypothetical. Rogue's fix was already partially written at the
moment the baseline was captured.

---

## D2 — The defect is SCOPE-CONDITIONAL. This changes the fix and its validation.

**Finding:** the defect does **not** reproduce on any standalone `-Include*` path. It reproduces
**only** on consolidated `-FullDeployment` runs.

All six standalone scopes reconcile exactly (`Drift` == findings printed) and use a different
renderer with **no `[Type]` labels at all**.

**Consequences — please treat as binding on the fix:**

1. The `[Type]`-labelled loop and its `Checked: N, Drift: N, Errors: N` line are reachable
   **only** from the consolidated path.
2. **A fix validated against `-IncludeWinLaps` validates nothing.** That path is already correct.
   Post-fix verification must run `-FullDeployment` and `-FullDeployment` + all includes.
3. Do not "fix" the standalone renderers. They are correct today.

---

## D3 — Section counters: 12 of 14 wrong, and core sections are affected

| Scope | Sections printing findings | Sections with wrong `Drift` |
|---|---|---|
| `-FullDeployment` | 6 | **4** (OU 31, Group 29, User 3, OU ACL 105) |
| `-FullDeployment` + all includes | 14 | **12** (only GPO and ADMX correct) |

**Wider than reported.** OU / Group / User / OU ACL need no `-Include*` switch: the defect is
reachable by `Audit-TierModel.ps1 -FullDeployment` with no other arguments.

Section `Drift` counters sum to **206** against a grand total of **374 / 402**. The two are
computed independently — which is why the grand total survived.

**`Total Checked` reconciles exactly** (375=375, 403=403). The `Checked` counter is sound and
should not be touched.

---

## D4 — Blast radius at the headline: real, but not the failure mode we feared

**The tool does NOT print a clean verdict over a list of drift.**

- `-FullDeployment` → `Overall Audit Status: ❌ 374 DRIFT ITEMS`, `Total Drift: 374` against
  374 findings printed. **Exact.**
- `-FullDeployment` + all includes → `Overall Audit Status: ⚠️ COMPLIANCE COULD NOT BE FULLY
  DETERMINED (12 error(s))`, `Total Drift: 402` against 410 printed.

**New, unpredicted defect — decryptor errors double-counted, and it hijacks the verdict.**
`Total Errors: 12` where section counters sum to 6. Bisected per switch:

| Scope | Total Errors |
|---|---|
| `-FullDeployment` | 0 |
| `-FullDeployment -IncludeMsa` | 0 |
| `-FullDeployment -EnableAuditing` | 0 |
| `-FullDeployment -IncludeWinLaps` | **12** |
| `-IncludeWinLaps` standalone | **6** |

`-IncludeWinLaps` is the sole contributor and its 6 decryptor errors are counted **exactly
twice**; `Total Checked` for the same switch rises by 13 (7+6), counted once. The double-count
is isolated to the error accumulator.

Because any non-zero error count flips the headline to "could not be determined", the effect is
to **suppress a 402-drift-item headline behind an indeterminate verdict**. Joel should be told
plainly: the tool is not claiming the estate is clean — it is claiming it cannot tell.

**Also:** `Total Drift` is 8 short in the all-includes scope (402 vs 410 printed), exactly the
`[AuditRight]` count. Domain Audit Rule contributes 1 drifted *object* to the grand total but
prints 9 finding *lines*. Recommend Rogue decide explicitly which unit the grand total reports
and state it, rather than letting the two disagree silently.

---

## D5 — Colour: confirmed, polarity inverted from the brief

| `[Type]` | Colour | Assessment |
|---|---|---|
| `[Missing]` | Red | reasonable |
| `[MissingAcl]` | Yellow | wrong |
| `[MissingAuditRule]` | Yellow | wrong |
| `[AuditRight]` | Yellow | wrong |
| `[Error]` | **Yellow** | **hard error rendered as a warning** |

The brief predicted the exact match on `'Missing'` would leave `Missing` yellow as well. Observed
the opposite: the exact match gets **Red**, everything else falls through to **Yellow**. The
user-visible consequence it predicted — `[Error]` rendering yellow — is **confirmed**.

The `Checked: N, Drift: N, Errors: N` line renders **Gray unconditionally**, at every value
including `Drift: 146` and `Errors: 6`.

Minor, standalone renderer only: colour is chosen per label not per value, so `Errors: 0` renders
Red and `Mismatched: 0` renders Yellow on a healthy section. Cosmetic; not urgent.

---

## D6 — Methodology decisions worth keeping

- **Colour cannot be captured by redirection.** `$PSStyle.OutputRendering='Ansi'` does not make
  `Write-Host -ForegroundColor` emit ANSI to a file (control: 0 ESC bytes in 128). A `Write-Host`
  proxy recording `ForegroundColor` and forwarding to `Microsoft.PowerShell.Utility\Write-Host`
  was required, and was validated against an 8-rung control ladder before any measurement was
  trusted. Product bytes were never modified.
- **Set `[Console]::OutputEncoding` in the PARENT**, not the child, or PS 5.1 destroys the `→`
  and `❌` glyphs in child `pwsh` output. This silently produced ~120 "unknown colour" rows in the
  first pass.
- **Two independent full runs reproduced every counter and finding count exactly.**

---

## D6a — Mapping onto the live register (BUG-047 / 048 / 049)

Read after measuring, so it cannot have biased the numbers. This baseline covers all three of
Rogue's in-flight IDs:

| ID | Scope | What this baseline pins |
|---|---|---|
| **BUG-047** colour | Medium | `[Error]`, `[MissingAcl]`, `[MissingAuditRule]`, `[AuditRight]` all **Yellow**; `[Missing]` **Red**; counter line **Gray** at every value. Polarity is inverted from the description in circulation. |
| **BUG-048** labels | Medium-High | Five distinct `[Type]` labels observed in the consolidated body; **zero** `[Type]` labels on any standalone path. |
| **BUG-049** drift counter | **CRITICAL** | 12 of 14 sections print `Drift: 0` over real findings; section counters sum 206 vs grand total 374/402. |

**Two additions the register does not appear to carry yet:**

1. **Scope-conditionality (affects BUG-048 and BUG-049).** Standalone `-Include*` is **correct**.
   Only the consolidated path is defective. Post-fix validation must use `-FullDeployment`.
2. **Doubled decryptor error count → hijacked headline verdict.** Not a colour or label issue and
   not obviously part of BUG-049's counter arithmetic. Recommend a **new ID**: `-IncludeWinLaps`
   contributes 6 decryptor errors that the consolidated grand total counts as 12, which flips
   `Overall Audit Status` to "COMPLIANCE COULD NOT BE FULLY DETERMINED" and suppresses a
   402-drift-item headline. Note `modules\TierModel\public\Test-TierModelWinLapsDecryptor.ps1`
   is under active edit by Rogue as of this writing — worth confirming with him whether this is
   already in hand before a new ID is issued.

---

## D7 — Lab state

No checkpoint created, deleted or renamed; DC01 still has exactly `DC-Promoted-Clean`,
`WinLapsSchema`, `AuthSilo-Lab`. Estate probes identical before and after — Audit performs no
writes, so Joel's reset fixture is intact. DC01 left **Running** on `WinLapsSchema` for the team.

`C:\TierModel` was **removed from the guest** after the runs: it held the `23b5100` build, and a
stale build at the canonical staging path is exactly the torn-build hazard this exercise existed
to avoid. Whoever validates Rogue's fix must stage it themselves.

Repo untouched — nothing staged, nothing committed, no files written into the repo other than
this record and the Cyclops history append. Repo root remains at 13 files.
