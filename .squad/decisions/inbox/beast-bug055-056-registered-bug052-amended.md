# Decisions — Beast, 2026-09-07 17:05 — BUG-055 and BUG-056 registered; BUG-052 scope claim corrected

**Agent:** Beast · **Requested by:** Joel Platek via the coordinator · **Branch:** `feature/enable-verbose-debug`
**Files touched:** `.research\known-bugs.md`, `.squad\agents\beast\history.md`, this record. Nothing staged, nothing committed. Working tree not touched (Rogue live in `Audit-TierModel.ps1`). `CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\`.

## D-1 — The headline was corrected FIRST, before any entry was written

It said **2 open**; the true figure is **4**. Joel reads that line, and a register that under-reports its own open count is committing the defect it exists to catch. Now: **🔴 v2.1.0 — 4 OPEN BUGS. Two are NEW and UNASSIGNED.**

**The unassigned count is called out explicitly**, because "open" and "nobody is on it" are different facts and only one of them needs a person today.

## D-2 — BUG-055 registered as the highest-consequence open item

`Audit-TierModel.ps1:2381` — the **standalone** overall-status headline branches on **drift alone and ignores errors**. Lab-observed: `Overall Status: ✅ COMPLIANT` in **green**, `Total Errors: 2` in **red one line below**.

**This is Joel's complaint in its most literal form yet** — *"No point having a log file that says GREEN and MISSING.. that is dumb."*

> **It needs NO ruling from Joel.** The consolidated renderer already carries the guard at **`:1774`**, with a comment stating an errored run must never render green. **The standalone path never received it.** The rule is already decided, written and commented — it merely has to be applied consistently.

Recorded as **unassigned and immediately actionable**, since nothing blocks it.

## D-3 — BUG-056 registered; cross-referenced to the moment the team REFUSED to build it

`Test-TierModelGroup` and `Test-TierModelUser` render `All Groups/Users are compliant ✅` in **green when the directory is entirely unreachable**. The error is **captured and never rendered**.

**`Test-TierModelOu` already carries the remedy** — `UnverifiedCount`, commented *"an OU we could not read is not a pass."* Group and User never got it.

> **This is case (c) — "could not determine" reported as "clean" — the precise failure mode Rogue REFUSED to create** when he declined a blanket relabel on the WinLaps decryptor, on the grounds it would report an unreachable domain controller as a clean-but-missing estate. **He refused to introduce it there. It is already shipping here.**

Cross-referenced deliberately so the inconsistency is visible. **Unassigned, pending Rogue finishing BUG-054 — explicitly NOT marked assigned.**

## D-4 — BUG-052's registered scope claim was WRONG and is struck through, not deleted

**Registered as:** *"structural — every producer's empty-config path."* **Executed: wrong for 3 of 13.**

The sentence is **struck through in place with the correction beside it**, not removed.

> **A register that silently repairs its own wrong claims teaches nobody which kinds of claim to distrust.** This one was **reasoned from the code rather than executed** — that is the category of claim to distrust.

## D-5 — Population stated with every count (working rule 21)

**21 `Test-TierModel*` functions exist; 13 are config-driven scope producers; all 13 were executed on the empty case.**

| Denominator | Finding |
|---:|---|
| 13 / 13 | return `Checked=0, Drift=0` |
| 6 / 13 | print a **green compliant verdict** standalone |
| 7 / 13 | print nothing standalone, but their zeros surface in the consolidated renderer as `Checked: 0, Drift: 0, Errors: 0` — **typographically indistinguishable from a genuinely clean scope** |
| 3 / 13 | **fail correctly** — `organizationUnits`, `groups`, `users` hard-fail `Get-TierModelConfig` and abort the audit |

**The 6/7 split is the substantive correction:** both halves mislead, but in different renderers, so a fix must address both.

**Separate usability observation, NOT filed as a bug:** the abort error **names neither the file nor the section**. Recorded so it is not lost; **do not file without assessment.**

## D-6 — Zero-case arithmetic: executed, not argued. NOT a divide-by-zero.

**5 of 7** compliance sites guard `totalChecked -le 0` and print `N/A (could not be determined)` in red. **2 do not** — `:1116` (GPO) and `:2120` (ADMX) read `CompliancePercentage` from producers that `return 100`, giving a **silent 100% in green over `Total Checked: 0`**, lab-confirmed.

> **The defect is INCONSISTENCY, not absence** — the same shape as BUG-055 and BUG-056.

**The irony, recorded:** **GPO and ADMX were the only two sections CORRECT in the earlier drift-counter baseline, and they are the two WRONG here. Being right about one defect predicts nothing about the next.**

## D-7 — The constraint on any fix is recorded with the defect

**Case (b) — a scope configured but resolving to zero live objects — reports drift correctly today.**

> **A fix that collapses "nothing configured" with "configured but absent" would destroy a distinction the tool currently gets right.**

**A bug entry that describes only what is broken invites a fix that breaks what works.**

## D-8 — Stale sub-claims found and cleared inside the amended entry

Amending BUG-052's status left three statements the amendment had falsified: the heading still read *"CYCLOPS INVESTIGATING"*, the in-progress call-out still promised an option list, and the disproved *"every producer"* sentence sat in the body **contradicting the corrected population three paragraphs above it**. All corrected.

**Editing an entry's status is not editing the entry.** Sweep the whole section for statements the amendment just invalidated.

## Final state

| v2.1.0 | Status |
|---|---|
| **Open bugs in scope** | **4** |
| ↳ **BUG-055** | 🆕 unassigned — **needs no ruling**, correct behaviour already exists at `:1774` |
| ↳ **BUG-056** | 🆕 unassigned — pending Rogue finishing BUG-054 |
| ↳ BUG-054 | 🔧 in progress — Rogue |
| ↳ BUG-052 | 🔍 investigation complete — **awaiting Joel's behaviour ruling** |
| Deferred to a separate branch | 1 — BUG-050 |
| Closed not-a-defect | 1 — BUG-053 |
| **Next free ID** | **057** |

**Ordered by consequence:** BUG-055 and BUG-056 lead, because both print **green over errors the tool already detected**. Live file 21,257 bytes / 385 lines; **by-design section verified intact and last**.