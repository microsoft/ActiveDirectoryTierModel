# Decisions — Beast, 2026-09-07 16:50 — BUG-053 closed NOT-A-DEFECT; BUG-054 registered

**Agent:** Beast · **Requested by:** Joel Platek via the coordinator · **Branch:** `feature/enable-verbose-debug`
**Files touched:** `.research\known-bugs.md`, `.research\known-bugs-archive.md`, `.squad\agents\beast\history.md`, this record. Nothing staged, nothing committed. Working tree not touched (Joel lab testing; suite green 1980/1980/0). `CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\`.

## D-1 — BUG-053 closed as NOT A DEFECT, on execution evidence

Rogue triaged by **executing the real producer bodies**, not by reading them. Both `default { 'Gray' }` arms are **structurally unreachable**; nothing has ever rendered Gray.

| Site | Method | Emitted / reachable types | Reachable set |
|---|---|---|---|
| ADMX `Audit-TierModel.ps1:2209-2214` | real `Test-TierModelAdmx` body, dependencies shadowed, all four outcome paths | `{Missing, Mismatch, Error}` — all handled above the `default` | **empty** |
| GPO `Audit-TierModel.ps1:1193-1198` | `:344-370` + `:420-428` lifted verbatim, **1,296 combinations** | `OverallStatus` ∈ `{Pass, Error, Fail}`; `'Unknown'` never survives | **empty** |

The GPO site was **a real candidate, not a hypothetical**: its producer has its own `default { 'Unknown' }` at `:426`, and `'Unknown'` is absent from the render switch. It is unreachable because the `if/elseif/else` at `:355-369` has an **unguarded `else`**, and `:371` is the **only** site appending to `$auditResults` (AST-verified: two assignments total).

**Closed after 45 minutes open. That is the correct outcome, not a wasted entry** — registering it is what caused it to be triaged.

## D-2 — Correction carried with the closure: only ONE of the two sites is ADMX

The entry was registered as "two ADMX render sites". **`:1193-1198` renders GPO findings inside `Invoke-GpoAudit` and has nothing to do with ADMX.**

**Wolverine's underlying observation was sound; his characterisation was not.** Recorded as an explicit correction rather than silently overwritten, because a wrong label left in the archive is the permanent record, and it would have sent whoever picked this up hunting for a second ADMX site that does not exist. **The observation being right and the label being wrong are different failures.**

## D-3 — Why the BUG-047 resemblance was superficial — the durable lesson

> **BUG-047's arm was REACHED EVERY RUN. This one is reached NEVER. Same shape, opposite consequence.**

Stated prominently in both the archive closure and the live file so **nobody re-files it on sight**. The question is not *"does a weak `default` arm exist"* — it does — but ***"can anything reach it"***.

**Third time this session that reasoning from resemblance would have produced a wrong answer.** Shape is a search heuristic; it is never a finding.

## D-4 — Registering BUG-053 with NO severity was vindicated

It was registered at 16:05 with severity deliberately withheld, on the grounds that shape is not proof. **Had BUG-047's severity been inherited from the resemblance, the register would have carried a defensible-looking number for a defect that does not exist.** Same discipline as never quoting a zero without its population (rule 21).

## D-5 — Residual tidiness item recorded, NOT promoted to a bug

Two lines could route to `Get-TierModelFindingColor`. **Zero-risk precisely because the arm is dead. Bundle into the next change touching the file; do not schedule; do not file as a bug.**

**Caveat that must travel with it:** the shared classifier **escalates unknown types to Red rather than demoting to Gray**, so the swap is **not behaviour-preserving in principle** — only here, only while no unknown type exists. Without that sentence a "trivial cleanup" ships a behaviour change.

## D-6 — BUG-054 registered, severity calibrated DOWN deliberately

Four **string literals**, not computed values: `Audit-TierModel.ps1:1168` and `:2195`, `Test-TierModelAdmx.ps1:233` and `:235`. Reachable and proven so — Rogue's executed Missing scenario returned **60 `[Missing]` findings** with `Missing: 0` printed above them; the GPO producer computes a real `Summary.MissingGpos` that the console **ignores in favour of the literal**. `Test-TierModelAdmx.ps1:235` is the worst line: it is the **drift** branch, printing `Missing ADMX Files: 0 ❌` — **a red failure marker beside a zero**.

**It is the BUG-049 family but materially less severe, and the entry says so explicitly:** ADMX folds missing files into the Mismatched bucket, so **total drift and compliance % remain correct and the estate does not read falsely clean.** The harm is misclassification *within* the summary, not a suppressed total.

**Inflating this would have been the easier call and would have misdirected the release.** Calibrating a severity **down** requires as much evidence as raising one.

## D-7 — Scope: in for v2.1.0 PENDING Joel's ruling. Not decided here.

It is a reporting defect in exactly the area this release improves, which is Joel's stated bar — **but he has not ruled, and the register does not decide for him.** Queued **above** BUG-053's old position as instructed; BUG-052 remains first.

## D-8 — Stale cross-reference caught and fixed

The header still advertised **21** working rules after rule 22 was added earlier today. Corrected to 22. **Same failure mode as the four stale references in the skill file: the content is right and the pointer to it has rotted.**

## Recount

| For v2.1.0 | Count | Which |
|---|---:|---|
| **Ready to fix — needs a person** | **0** | — |
| Blocked on Joel's ruling | **2** | BUG-052, BUG-054 |
| Open but unassessed | **0** | BUG-053 closed |
| **Deferred to v2.1.1 — DO NOT TOUCH** | **1** | BUG-050 |
| Total open entries | 3 | |
| **Next free ID** | **055** | |

Live file order: **BUG-052 → BUG-054 → BUG-050 → "By design — do not re-file"** (verified intact). Closed detail lives only in `.research\known-bugs-archive.md`, which is git-excluded with no version history — **do not delete it**; it is the raw material for the v2.1.0 PR description.