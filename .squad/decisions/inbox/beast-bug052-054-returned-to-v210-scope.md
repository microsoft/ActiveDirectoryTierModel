# Decisions — Beast, 2026-09-07 16:35 — REVERSAL: BUG-052 and BUG-054 returned to v2.1.0 scope

**Agent:** Beast · **Requested by:** Joel Platek via the coordinator · **Branch:** `feature/enable-verbose-debug`
**Files touched:** `.research\known-bugs.md`, `.research\deferred-bugs.md`, `.research\known-bugs-archive.md` (repair only), `.squad\agents\beast\history.md`, this record. Nothing staged, nothing committed. Working tree not touched. `CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\`.

## D-1 — The 16:22 deferral was a COORDINATOR ERROR, not a change of mind by Joel

Recorded that way at the coordinator's own instruction. **Joel clarified a principle; the 16:22 scoping had been made against the wrong axis.**

> **Joel, 2026-09-07 16:35, verbatim:**
>
> > *"I want anything related to logging fixed and the output should be accurate meaning the reports, colors, text, etc. **No point having a log file that says GREEN and MISSING.. that is dumb the log must be accurate too.**"*

**That is a near-verbatim description of BUG-054.** `Test-TierModelAdmx.ps1:233` prints `"Missing ADMX Files: 0 ✅"` in **green**. Joel had sent "that ADMX thing" away an hour earlier **without realising it was the case he was describing**. Once the two lines were put in front of him he confirmed both bugs return.

## D-2 — THE LESSON: the scope test is OUTPUT ACCURACY, not bug category

| Wrong axis (used at 16:22) | Right axis (Joel's actual test) |
|---|---|
| *"Is it ADMX / is it logging-related?"* | **"Does it make the tool lie?"** |

**Category is a label; accuracy is a property.** BUG-054 was filed under "ADMX" and dismissed on the label, while the property — a green ✅ beside a false zero — was exactly what Joel was asking to have fixed. **The category name hid the property from the person who owned it.**

**Recorded in the live register, not just here**, because it is the rule that prevents the next mis-scope.

## D-3 — BUG-050 stays deferred, and it passes the CORRECTED test too

**It is not an output defect at all — it is deployment correctness, a wrong object being created.** Joel was explicit and unprompted. It is now deferred on **three independent grounds**: release taxonomy (16:05), deployment impact (16:22), and output-accuracy scope (16:35). **Full detail retained in `deferred-bugs.md`; nothing thinned.**

## D-4 — Statuses set precisely: in progress ≠ being repaired

| Bug | Status | Who |
|---|---|---|
| **BUG-054** | 🔧 **IN SCOPE, being fixed now** | Rogue — the four sites |
| **BUG-052** | 🔍 **IN SCOPE, INVESTIGATION ONLY — not a repair** | Cyclops, read-only, producing ranked options |

**BUG-052 carries an explicit call-out that investigation is not repair**, with Joel's chosen process verbatim — *"team investigates and recommends, then I rule"* — and the instruction that **nothing may be marked fixed before he rules.** An option list must not be mistaken for a fix.

## D-5 — The inference call-out was overturned within the hour. The round trip is COMPLETED, not deleted.

At 16:22 BUG-052's deferral was recorded as **the coordinator's inference**, attributed to him by name and flagged subject to Joel's correction — **over his own authority, at his instruction.**

> **Had it been written up as Joel's ruling, reversing it would have meant contradicting the customer instead of correcting a colleague.**

The live register now shows the full sequence — **inference made → flagged as an inference → overturned** — rather than quietly deleting the deferral. **That sequence is the strongest evidence in the register for why attribution is recorded precisely, and it only exists because the history was completed rather than erased.**

## D-6 — The false headline was fixed FIRST, before any entry was touched

The file still read *"✅ v2.1.0 HAS ZERO OPEN BUGS"*. **Joel reads that line.** A stale headline is the register committing the exact defect it exists to catch — **reporting clean when it is not, the BUG-049 family.** Corrected as the first write of the session.

## D-7 — Three defects found in my OWN prior output, and repaired

| Defect | Detail |
|---|---|
| `''` here-string artifacts | **3** in `deferred-bugs.md`, **1** in the archive — the `@'...'@` trap, where `''` is not an escape. Last session's `''` sweep checked `history.md` and the decision record **but not the file just created** — **too narrow a population, rule 21 turned on myself.** |
| `---## By design` | A splice removed the line break, silently killing the heading. |
| Bare-LF line endings | Introduced into 3 files in an otherwise pure-CRLF repo. Normalised; **content proved identical** by comparing line-ending-normalised before/after. |

`test-plan-verbose-debug-v2.md` also has bare-LF but is **not mine — left untouched.**

## D-8 — Two of my own checks returned confident FALSE results

- `.Contains()` on a string containing **backticks inside a double-quoted PowerShell string** — the backticks are escapes and vanished silently.
- `(?m)^---$` counted **0** separators in a CRLF file, because `$` does not match before `\r`.

**Both were false negatives that looked like findings** — the same species as the wrapped-prose miss recorded earlier. **When a check reports "not found", suspect the check before believing the absence.** Flagged for the skill file; **not actioned** — the coordinator will scope that when the tree is quiet.

## Final state

| v2.1.0 | Count |
|---|---:|
| **Open bugs in scope for v2.1.0** | **2** — both in progress, neither blocked on a person |
| ↳ BUG-054 | Rogue, fixing now |
| ↳ BUG-052 | Cyclops, investigating (Joel rules before any repair) |
| Deferred to a separate branch | 1 — BUG-050 |
| Closed not-a-defect | 1 — BUG-053 |
| **Next free ID** | **055** |

Live file (13,177 bytes, 236 lines): headline → scope-reversal record → BUG-054 → BUG-052 → deferred pointer → **by-design section, content verified unchanged and at the tail**. `.research\` is git-excluded — **`deferred-bugs.md` and the archive have no version history. Do not delete either.**