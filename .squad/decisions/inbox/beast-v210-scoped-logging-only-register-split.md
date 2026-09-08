# Decisions — Beast, 2026-09-07 16:22 — v2.1.0 scoped to logging only; register split; BUG-050/052/054 deferred

**Agent:** Beast · **Requested by:** Joel Platek via the coordinator · **Branch:** `feature/enable-verbose-debug`
**Files touched:** `.research\known-bugs.md`, **new** `.research\deferred-bugs.md`, `.squad\agents\beast\history.md`, this record. Nothing staged, nothing committed. Working tree not touched (Joel lab testing; suite green 1980/1980/0). `CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\`.

## D-1 — v2.1.0 is now scoped to logging / verbose / debug bugs ONLY

**Joel, 2026-09-07T16:22, verbatim:**

> *"If its not logging related liek that ADMX thing and the UPN those need to go to a different branch and fix later on. I want to focus solely on bugs related to our new logging verbose and debugging problems."*

> *"Those other two are not causing issues with deployments."*

**His test is impact: is it causing issues with deployments?** For all three deferred bugs the answer is no — deployments complete and the tier model functions. What they damage is **reporting accuracy**, and for BUG-050 **downstream Entra ID Connect sync**.

## D-2 — BUG-054 re-scoped OUT of v2.1.0; the previous instruction is withdrawn, not quietly dropped

Thirty minutes earlier BUG-054 was registered as *"in scope for v2.1.0 pending Joel's ruling"*. **He ruled, and it went the other way.** The entry now carries an explicit withdrawal line rather than a silent edit, so a reader who saw the earlier state is not left wondering which is current.

## D-3 — ⚠️ BUG-052 is deferred on the COORDINATOR'S INFERENCE, not on Joel's ruling

**Joel did not name BUG-052.** The coordinator applied the same ruling by inference: it is an audit-reporting edge case, not logging-related, not causing deployment issues, so it meets Joel's stated test the same way BUG-054 does.

**Marked as an inference in BOTH files**, in a call-out box, attributed to the coordinator, and flagged **subject to Joel's correction** with the reversal cost stated ("costs one sentence").

> **The reasoning is explicitly NOT attributed to Joel.** A register that launders an inference as a ruling makes it unchallengeable — which is exactly backwards, since an inference is the thing that most needs challenging. Same discipline as correcting attribution in rule 21 and correcting Wolverine's label on BUG-053: **who said a thing is part of the finding.**

Also still true and unchanged by the deferral: BUG-052 needs a **product decision** (does a `NOT CONFIGURED` / `SKIPPED` state exist, what is it called, does it affect verdict and exit code), not a repair.

## D-4 — BUG-050 now has TWO independent deferral reasons, both recorded

| When | Ground |
|---|---|
| 2026-09-07 16:05 | **Release taxonomy** — pre-existing defect, unrelated to v2.1.0, so it lands in the patch bucket |
| 2026-09-07 16:22 | **Impact** — *"not causing issues with deployments"* |

Recorded separately rather than merged: **two independent reasons is stronger evidence than one, and if either is later overturned the other still stands.**

## D-5 — THE FILE WAS SPLIT. New file: `.research\deferred-bugs.md` (13,226 bytes, 238 lines)

**The call, and why:** three full entries totalled **9,596 bytes** against a **3,555-byte** by-design section. Keeping them inline could not coexist with "one scroll". The brief pre-stated the priority — **if it gets long, the deferred section moves out, it does NOT get truncated** — which turned a judgement call into a lookup.

**Full reproduction detail retained, nothing thinned.** Verified present after the move: `New-TierModelUser.ps1` L87/L110, `Test-TierModelUser.ps1:107`, the 86-file/45-config sweep evidence, `aclDelegations`, all four BUG-054 sites including `Test-TierModelAdmx.ps1:235`, `Summary.MissingGpos`, and the 60-`[Missing]`-findings proof.

**Ordered by consequence, highest first: BUG-050 → BUG-052 → BUG-054.** Scope no longer separates them — all three are equally out of v2.1.0 — so damage is the only useful ordering left. This is consistent with the consequence argument published at 15:36 and never withdrawn.

## D-6 — Deferred is NOT archived, and the file says so

**They were deliberately NOT put in `.research\known-bugs-archive.md`.** That file is for **closed** entries; archiving implies resolved. These are open, deferred, and waiting for a branch **that does not exist yet** — which is precisely the failure mode this file guards against.

## D-7 — The headline Joel asked for, with its population beside it

Top of the live file: **"✅ v2.1.0 HAS ZERO OPEN BUGS AND A GREEN SUITE."** The same table immediately shows **3 deferred — not fixed, not closed** and **1 closed as not-a-defect**. **The zero is trustworthy only because what is excluded from it is stated beside it** (working rule 21).

## Final state

| v2.1.0 | Count |
|---|---:|
| **Open bugs in scope for v2.1.0** | **0** |
| Deferred to a separate branch (not fixed, not closed) | 3 — BUG-050, BUG-052, BUG-054 |
| Closed not-a-defect | 1 — BUG-053 |
| **Next free ID** | **055** |

`known-bugs.md` (6,393 bytes, 113 lines): headline → deferred summary table → **by-design section, verified byte-identical and at the tail**. `.research\` is git-excluded — **neither `deferred-bugs.md` nor the archive has version history. Do not delete either.**