# Decisions — Beast, 2026-09-07 13:05 — `known-bugs.md` reduced to an open-bugs-only work queue

**Agent:** Beast · **Requested by:** Joel Platek · **Branch:** `feature/enable-verbose-debug` (HEAD `6725ab3`)
**Files touched:** `.research\known-bugs.md`, `.research\known-bugs-archive.md` (new). Nothing staged, nothing committed. `CHANGELOG.md` not opened. `Audit-TierModel.ps1`, `modules\`, `tests\`, `specs\`, `docs\` untouched. Repo root unchanged at 13 files.

## The request

Joel: *"remove everything from known-bugs.md except the current bugs we have to fix. I dont want this file to keep a history. I want to be able to scroll quickly review and understand the bugs and how many we have."* Followed by: *"once that file is cleaned up I'll review while we start to squash all the remaining bugs."*

**The file's role changed: it is now the team's work queue, not a record.** That drove every decision below.

## D-1 — Preserve before prune, and archive the WHOLE file

`.research\` is in `.git/info/exclude:23`. **`known-bugs.md` has never been under version control** — no `git show`, no reflog, no recovery. Deletion is permanent, which puts this in a different risk class from pruning a tracked file.

The archive was therefore written and **verified** before a single line was cut, and it is a **complete copy**, not a selective one. **The selection step is where this kind of job loses something nobody notices for a month, and skipping it is free.**

| | Before | After |
|---|---:|---:|
| `known-bugs.md` | 127,736 bytes / 2,108 lines | **9,932 bytes / 183 lines** (−92%) |
| `known-bugs-archive.md` | — | **129,552 bytes / 2,139 lines** |

**Into the archive:** all 46 fixed-bug entries with causes, provenance, fixes and evidence; the 21 working rules; the "By design — do not re-file" rulings; the end-of-day restart cards; the release rule. Nothing deleted, corrected or re-ordered — it is a snapshot.

## D-2 — The archive's stated job is the v2.1.0 PR description

Per **D15**, the per-bug detail goes in the **PR description only** and must **NOT** be migrated into `CHANGELOG.md`. **That PR has not been written yet.** Had the fixed entries simply been deleted, the PR author's raw material would have gone with them. The archive header says this explicitly, so a future reader knows why the file exists and does not tidy it away.

## D-3 — Ordered by consequence, not by ID

A register is ordered by ID because it is a record; **a queue is ordered by consequence because someone works down it.** Joel will work top-down, so the order is the recommendation:

1. **BUG-049 — 🔴 CRITICAL.** `Drift: 0` printed above real itemised drift. Every other defect produced a wrong artifact or refused to run — both visible. This one **tells the operator the estate is clean when it is not**, on LAPS ACLs, MSA/gMSA/dMSA delegation, domain audit rules, auth policies and silos.
2. **BUG-048 — 🟠 Medium-High.** Labels lie: `[Error]` for a missing GPO, `[AuditRight]` for a missing SACL audit rule.
3. **BUG-047 — 🟡 Medium.** Exact-literal `'Missing'` colour match; everything else prints yellow, including `[Error]`.

## D-4 — Assignment stated at the top, because a count alone does not answer "does anything need me?"

**Open 3 · Unassigned 0 · all three with Rogue, in progress.** Joel asked to see plainly whether anything is open and unowned. Nothing is marked fixed that was not verified — all three carry 🔧 In progress.

## D-5 — Constraints carried forward, not just descriptions

Three things a reader of a pruned file cannot infer, kept deliberately:

- **BUG-048 and BUG-049 must land TOGETHER** (Trap A). WinLaps Decryptor's `Errors: 6` is the only correct counter in the audit, and it is correct **only because two faults cancel**. Relabel alone gives `Drift: 0, Errors: 0` above six red lines.
- **Trap B:** the `AuditRight` relabel must be conditional on `Status -eq 'Fail'` — the producer emits it on every pass and fail alike.
- **The BUG-047 ternary exists in four copies**; fixing the reported site leaves three.
- **Naming:** `-IncludeAuthPolicies` and `-IncludeAuditRules` **do not exist** (real gates: `-IncludeAuthSilos`, `-EnableAuditing`), so a sweep for those names returns a misleading zero.

## D-6 — Concern raised, instruction followed anyway

**Flagged for Joel, not second-guessed.** Archiving the **"By design — do not re-file"** section removes the only thing stopping the cancelled-deploy `exit 0` ruling and the GPO/WinLapsDecryptor drift-arithmetic ruling from being re-filed a third time; the **21 working rules** were live guidance rather than history. The instruction was unambiguous, so **both were archived as told and the cost was stated in the summary** — with a pointer to the archive in the new file's header so the trail is not lost. Joel decides whether either comes back.

## Constraints honoured

- Nothing staged, nothing committed. `.research\` only.
- `CHANGELOG.md` never opened; product code, `tests\`, `specs\`, `docs\` untouched.
- `Audit-TierModel.ps1` and `modules\` never opened — Rogue is mid-edit.
- CURRENT_DATETIME used verbatim: **2026-09-07T13:05:00+08:00**. Repo root still 13 files, zero strays.

## Note for Joel on tree state

The working tree is **not** clean, and neither change is a stray: `Audit-TierModel.ps1` is **Rogue's in-progress fix**, and `.squad/agents/beast/history.md` is **Beast's history append** from the 12:35 session, still uncommitted. Both `.research\` files are git-excluded and so never appear in `git status` at all. Nothing was staged.
