# Decisions — Beast, 2026-09-07 12:35 — audit drift-counter register update

**Agent:** Beast · **Requested by:** Joel Platek · **Branch:** `feature/enable-verbose-debug` (HEAD `04ab664`, nothing committed)
**File touched:** `.research\known-bugs.md` **only**. Nothing staged, nothing committed. `CHANGELOG.md` not opened. Repo root unchanged at 13 files. No scratch file created inside the repo.

## Register movement

| | Before | After |
|---|---:|---:|
| Total IDs issued | 46 | **49** |
| Fixed | 44 | **46** |
| Open (unfixed, unowned) | 2 | **0** |
| In progress (Rogue) | 0 | **3** (047, 048, 049) |
| Next free ID | 047 | **050** |
| Fixed but not yet in `CHANGELOG.md` | 22 | **24** (BUG-019 + BUG-024…046) |

## D-1 — BUG-045 and BUG-046 recorded as FIXED, with the decision named

Rogue's fix verified independently on the filesystem, not accepted from a self-report (working rule 13): all three prompt sites default instead of throwing, show the default in the prompt (`... [Deploy-TierModel]`), and echo the resolved value. Zero residual `cannot be empty when` in either entry script; UTF-8 BOM `EF BB BF` intact on both (BUG-033 regression guard).

BUG-046's whole reason for existing as a separate ID was that its fix required a decision. **Recorded: Joel chose `Audit-TierModel`, on 2026-09-07.** That was the stated precondition for ever folding it into BUG-045.

**Also recorded as method, not status:** Rogue proved the D8 never-prompt guarantee by replacing `Read-Host` with a recorder of prompts *requested* and running the real scripts in child processes — 0 prompts on `-EnableVerbose`/`-EnableDebug`, exactly 1 each on explicit `-Logging`/`-OutputFormat` with Enter accepted and no throw.

## D-2 — The coverage gap is recorded as the headline lesson of BUG-045

`EnableVerbose` = 0, `EnableDebug` = 0, `LoggingAutoEnabled` = 0 across every `.ps1` under `tests\` before today — confirmed independently by Beast with `ReadAllText` + `[regex]::Matches`. **A 1,926-test suite at 87.37% coverage contained no reference to the feature the release is named for.** Coverage measures lines executed, not behaviours asserted. Closed by Wolverine: 12 tests, CI-shaped suite now **1938/1938/0**, and the anti-collapse guard control-proved by making the maintainer's plausible edit (`if ($script:LoggingAutoEnabled)` → `if ($false)`) — 6 tests fail, where previously that edit failed nothing.

## D-3 — Joel's one "colour bug" was split into THREE IDs (Beast's call)

Principle carried over from this morning's 045/046 split: **a free repair and a decision must not share a status flag.** Practical test applied — **do the parts fail independently?** All three do; fixing any one leaves the other two live.

| ID | Why separate | Severity |
|---|---|---|
| **BUG-047** colour | Free, unconditional, no ruling needed, moves no number | Medium |
| **BUG-048** labels | Needed Joel's ruling; booby-trapped in two directions | Medium-High |
| **BUG-049** drift counter | Different defect class; changes audit numbers and verdicts | **CRITICAL** |

## D-4 — BUG-049 rated CRITICAL, the highest in the register

Argued, not asserted: every other defect here produced a **wrong artifact** or **refused to run** — both visible, both inviting a second look. This one prints `Drift: 0` above real itemised drift on LAPS ACLs, MSA/gMSA/dMSA delegation, domain audit rules, auth policies and silos. **It tells the operator the estate is clean when it is not**, on exactly the surfaces the Tier Model exists to protect.

Cause: `Audit-TierModel.ps1:1884` sums four hard-coded key names; `Get-SafePropertyValue` (`:1632`) collapses an absent property to zero, so **a missing key and a clean estate render identically**. The totals loop near `:1714` uses a different key set again, so sections and grand totals can legitimately disagree. Fourth appearance of the BUG-039/040/041 shape.

*(Statement about severity only. Asserts no connection to the original two-GPO customer incident, which is formally CLOSED as UNKNOWN.)*

## D-5 — Joel's rulings recorded verbatim in the register

1. `[AuditRight]` → **`[MissingAuditRule]`**, explicitly **not** `MissingAcl` — these are SACL audit rules, not DACL ACLs.
2. Fix the counter **now, properly**, by **unifying the producer vocabulary**, not by patching key names into the whitelist (working rule 19 at design level).
3. **Accepted in advance:** audit numbers will change and Overall Audit Status may flip from clean to non-compliant on estates that currently look fine. Recorded explicitly so nobody backs the change out when the first green estate turns red.

## D-6 — Trap B upgraded from a warning to a proof

At `04ab664:modules/TierModel/public/Test-TierModelAuditRule.ps1:177-185`, the producer emits `Type = 'AuditRight'` **once per right, on every pass and every fail alike** — the verdict is carried in `Status`, never in `Type`. A blanket rename is therefore **guaranteed**, not merely liable, to label passing audit rights as missing. **The relabel must be conditional on `Status -eq 'Fail'`.** This also explains Joel's 9-finding Domain Audit Rule section.

Two implementer notes recorded alongside: the `AuditRight` object has **no `Details`** property while its `MissingAuditRule` sibling does, and the renderer interpolates `$($_.Details)` — working rule 18's exact failure mode, at report time, on a drifted run. And the Trap B comment at `:345-346` is **not** pre-existing (`AuditRight` appears 0× in that file at `04ab664`), so its presence is not evidence the guard is battle-tested here.

## D-7 — Trap A recorded as a general hazard: a compensating pair

`$entityErrors` (`:1890`) counts findings whose `Type` is literally `Error`. **WinLaps Decryptor's `Errors: 6` is the only correct counter in the entire audit — and it is correct only because two faults cancel.** Relabelling `Error` → `Missing` alone yields `Drift: 0, Errors: 0` above six red lines. **BUG-048 and BUG-049 must land together, or BUG-048 must not land at all.** Fixing half of a compensating pair is a regression.

## D-8 — Provenance: all three are PRE-EXISTING at `04ab664`

Joel called the `-Include*` parameters "recent". They are not. Evidence, not recollection — baseline extracted with `git show 04ab664:Audit-TierModel.ps1` to a path **outside the repo** (Rogue is mid-edit; a live read risks a torn view), read with `ReadAllText` + `[regex]::Matches`, never `Select-String`:

- All six switches (`-IncludeMsa/-IncludeGmsa/-IncludeDmsa/-IncludeWinLaps/-IncludeAuthSilos/-EnableAuditing`) in the `param()` block, with their combination-validation rules.
- All eight audited section `Type` literals present.
- The mis-colouring ternary present **4×** (L377, L438, L499, L1273) — fixing only the site Joel hit leaves three copies behind.
- The four-key drift sum verbatim at L1234-1237; `$entityErrors` at L1239-1250.
- The grand-totals loop at L1100-1103 using a **different** key set (no `DriftCount`) — **the divergence itself is pre-existing.**

**Naming trap, recorded because it would otherwise cost someone an hour:** there is **no `-IncludeAuthPolicies` and no `-IncludeAuditRules`.** Auth Policies *and* Silos are gated by `-IncludeAuthSilos`; Domain Audit Rule by `-EnableAuditing`. Both plausible names return **zero**, and taking those zeros at face value would have produced exactly the wrong provenance answer.

The feature-introduced set is unchanged: **BUG-024, BUG-025, BUG-045 (Audit site only).**

## D-9 — Working rule 21 added, attributed to Beast's error

> **When you report a ZERO or an ABSENCE, state the population and the enumeration rule beside it.**

Rule 12 says a count needs its population; 21 is the sharper case, because **a zero looks identical whether the enumeration was right or wrong — a wrong population hides its own error perfectly.**

The false "0 BUG- references in product code" was **Beast's**, asserted in Rogue's brief from a check scoped only to the two entry scripts. **Rogue caught it.** Recorded that way round deliberately: a rule about honest enumeration that misattributes its own origin undercuts itself.

**The reusable fact, verified by direct enumeration — the product surface is 86 files:** 2 root `*-TierModel.ps1` + 82 under `modules\` (80 `public\*.ps1` + `TierModel.psm1` + `TierModel.psd1`) + 2 under `optional\`. The failed sweep enumerated by **file shape** and got **84**, structurally blind to `TierModel.psm1`/`TierModel.psd1` — which is exactly where the two surviving violations were. **"84 files, 0 hits" is falsifiable on sight against a repo with 86. A bare "0" is not.**

## Constraints honoured

- Nothing staged, nothing committed. Only `.research\known-bugs.md` edited.
- `CHANGELOG.md` never opened. `tests\`, `specs\`, `docs\` and all product code untouched.
- **`Audit-TierModel.ps1` never opened** — Rogue is mid-edit; every line number quoted came from Joel's report or the `04ab664` baseline.
- Restart card at the top of the register brought current: counts, provenance note, a new step 0, and a SUPERSEDED marker on the stale 1573/1572/1 suite baseline.
- "By design — do not re-file" section left intact (cancelled-deploy `exit 0`; GPO/WinLapsDecryptor breakdown not summing).
- Original two-GPO customer incident left formally **CLOSED as UNKNOWN**; no cause asserted anywhere.
- CURRENT_DATETIME used verbatim: **2026-09-07T12:35:00+08:00**. Repo root still 13 files.

## Open for Joel

The standing strategic question is now **sharper, not answered**. The open count is back to zero for the first time since 2026-09-05 — and the same audit reporting seam produced three more defects this afternoon, one of them the most severe in the register. Applied literally, *"don't release unless we squash all known bugs that we find"* has still not terminated on this seam. **Whether to freeze scope for v2.1.0 and open a dedicated reporting-path pass remains Joel's call. Nobody should act as though it is decided.**
