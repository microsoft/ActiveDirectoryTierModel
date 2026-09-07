# Decisions — Beast, 2026-09-07 15:36 — BUG-050/051/052 registered, BUG-047/048/049 closed

**Agent:** Beast · **Requested by:** Joel Platek · **Branch:** `feature/enable-verbose-debug`
**Files touched:** `.research\known-bugs.md`, `.research\known-bugs-archive.md`. Nothing staged, nothing committed. `CHANGELOG.md` not opened. No product code, `tests\`, `specs\` or `docs\` touched.

## Register movement

| | Before | After |
|---|---:|---:|
| Open | 3 — BUG-047, 048, 049 | **2 — BUG-050, BUG-052** |
| Unassigned | 0 | **2** |
| Next free ID | 050 | **053** |
| Closed today | 045, 046 | 045, 046, **047, 048, 049, 051** |

## D-1 — ID assignment

- **BUG-050** — user accounts created with no `UserPrincipalName`. **OPEN, unassigned.** Registration only, per Joel: *"Just put this in the known bugs for now and we will work on it later."*
- **BUG-051** — `Invoke-OuAclAudit` remapped `Warning` findings to `[Error]`. **Already FIXED by Rogue**; numbered for the record and archived immediately, since the live file holds open bugs only.
- **BUG-052** — a scope with nothing to check reports as clean. **OPEN, blocked on a ruling from Joel.**

## D-2 — "Unassigned: 2" was split, because the two are not the same kind of unassigned

All three previously-open bugs had an owner; neither new one does. That change (0 → 2) is what Joel reads this file for, so it leads the file. **But the two are not interchangeable:**

- **BUG-050 needs a person.** It is fully specified and can be picked up now.
- **BUG-052 needs a decision.** It cannot be worked until Joel rules, so assigning someone would just park them.

A bare "Unassigned: 2" implies two pickable tasks when only one is. Both the header sentence and the table say which is which.

## D-3 — Ordering: BUG-050 placed above BUG-052, with the reasoning published

Both are false-clean-adjacent — the family Joel prioritised — so the ordering needed an argument, not pattern-matching:

- **BUG-052 misleads someone who chose to configure nothing**; their own config is the cause and they have some reason to expect an empty result.
- **BUG-050 misleads everyone and breaks a real integration** (Entra ID Connect sync), *and* carries its own false-clean in part 2 — the audit cannot retrieve UPN, so pre-existing accounts stay non-compliant behind a clean report.
- BUG-052 is blocked on Joel regardless, so it cannot be worked first.

The reasoning is in the file so Joel can overrule it in one line.

## D-4 — Joel's "minor" assessment recorded, not flattened, and not silently overridden

He called BUG-050 *"a minor bug that wont impact anything."* The entry records that **his framing is correct for the tier model's own function** — the accounts are created, placed and grouped correctly, and every in-scope AD behaviour works — alongside the consequence **he named himself**: Entra ID Connect sync failures, which are not cosmetic for anyone running hybrid identity.

**Both readings are labelled and left for whoever picks it up to weigh.** Ordering it first while showing the reasoning is honest; quietly reordering around a principal's stated view is not.

## D-5 — Part 2 given equal billing: fixing the create path alone leaves a false-clean audit

Joel saw the create path (`New-TierModelUser.ps1` L87 hashtable → L110 `New-ADUser` splat). He did not see that **`Test-TierModelUser.ps1:107` fetches `-Properties DistinguishedName,Enabled,MemberOf` and does not retrieve UPN at all.**

**Consequence, stated explicitly in the entry: fix the create path alone and every pre-existing account remains silently non-compliant while the audit reports clean — the BUG-049 family.** The entry therefore requires **both paths to be fixed together**, the same coupling BUG-048/049 needed via Trap A. Part 3 (no UPN key in any of the 45 configs) makes it a **schema decision**, not a parameter addition.

## D-6 — Joel's fix ruling recorded to pre-empt the design debate

**Set the UPN from the domain's default suffix; if the forest has more than one, the customer adjusts manually afterwards.** Do not build multi-suffix selection logic — he has already decided the simple behaviour suffices.

## D-7 — Evidence carries its population (working rule 21)

Sweep of the **86-file product surface** (2 root + 82 `modules\` + 2 `optional\`) **plus 45 JSON configs**, case-insensitive `UserPrincipalName|\bUPN\b` via `ReadAllText` + `[regex]::Matches`: **0 hits in product code, 0 UPN keys in any config.** Quoted with its population, per the rule added this morning after a narrow-population "0" was wrong.

**Recorded as explicitly NOT affected:** `New-TierModelGroup.ps1` shares the `SamAccountName`-only shape, but **groups carry no UPN** (working rule 17 — record deliberate non-changes, or someone "fixes" them later).

## D-8 — Closures, and the caveat that must travel with BUG-047

BUG-047/048/049 archived as fixed with Cyclops's A/B evidence: sections printing `Drift: 0` over real findings **12 of 14 → 0 of 14**; section sums reconcile with the grand total (**374/374**, then **402/402**); **`Total Checked` unmoved**; verdict `⚠️ COMPLIANCE COULD NOT BE FULLY DETERMINED (12 error(s))` → `❌ 402 DRIFT ITEMS`. After Joel's Option A ruling, printed lines **410 → 402** with the counter unmoved at 402.

**`Total Checked` not moving is the load-bearing control** — it shows the counters were repaired without altering the population audited, which is what distinguishes this from a fix that merely makes numbers agree.

**⚠️ BUG-047's `[Error]` → red half is NOT lab-validated and cannot be.** Fixing the errors removed every `[Error]` finding from a healthy estate — an adjacent fix deleted the only fixture. Wolverine is covering it with a unit test mocking `Get-GPO` to throw. **This qualification is recorded in BOTH the live file's summary box and the archived entry**, because a caveat living in only one of two places is a caveat that gets dropped by whoever quotes the other.

## D-9 — BUG-051's value is the pre-fix assessment, not the fix

Rogue established **before touching it** that the producer emits eight finding types and **only `Warning`** was in the remapped set — genuine `Error` findings already mapped to `Error` — so the change **could not** suppress a real error state. He then routed the projection through the shared `ConvertTo-TierModelDriftFinding` normaliser rather than patching in place, keeping the vocabulary unified (the BUG-044 seam). Observable delta: one advisory line, red `[Error]` → yellow `[Warning]`.

**Establishing what a change cannot break before making it** is the transferable part; the delta is trivia.

## D-10 — BUG-052 left unfixed deliberately, and why the obvious fix is wrong

Rogue surfaced rather than fixed it. **Synthesising an error so the section stops looking clean would be a worse lie than the one it replaces** — it manufactures a failure state that does not exist, and it is the same species of "bend a counter so the output reads better" that Joel rejected in the by-design drift-arithmetic ruling.

**The real discriminator, recorded as the reason it needs a decision:** *"nothing was configured"* and *"nothing is wrong"* are different facts that currently render identically. The fix is to **distinguish them** — a `NOT CONFIGURED` / `SKIPPED` state distinct from both clean and failed. Whether that state exists, what it is called, and whether it affects the overall verdict or exit code are **Joel's calls**. It is structural and applies to **every producer's empty-config path**, not just OU ACL.

## Constraints honoured

- `.research\` only. Nothing staged, nothing committed. `CHANGELOG.md` never opened.
- Live file shape preserved exactly as Joel asked: **open count → open bugs by consequence → "By design — do not re-file"**. Live file is 11,063 bytes / 202 lines — still one scroll.
- **The "By design" section was carried across programmatically and asserted byte-identical** (`$new.Contains($original)` → True), not retyped. Nothing else in the live file moved.
- CURRENT_DATETIME used verbatim: **2026-09-07T15:36:32+08:00**. Repo root 13 files, no strays.
