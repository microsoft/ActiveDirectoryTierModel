# Decision: D13 comment strip — TierModel.psm1 survivors

- **Author:** Rogue
- **Date:** 2026-09-07T12:20:00+08:00
- **Branch:** feature/enable-verbose-debug (uncommitted; Joel reviews and commits)
- **File changed:** `modules\TierModel\TierModel.psm1` only

## Decision

Applied D13 "keep the rule, drop the history" to the two surviving `BUG-023` comments.

| Line | Before | After |
|---|---|---|
| 180 | `# BUG-023: Load schema for FromConfig so validation is not silently skipped.` | `# Load schema for FromConfig so validation is not silently skipped.` |
| 210 | `# Schema validation — runs for both FromPath and FromConfig (BUG-023 fix)` | `# Schema validation — runs for both FromPath and FromConfig` |

Read in context first, as instructed. Neither required an authored rewrite: both were already
present-tense statements of a live constraint whose only offence was the number. `:180` still names
the constraint that matters (without it, the `FromConfig` path skips schema validation silently),
and the following line — untouched — explains why the path is resolved locally rather than taken
from `$SchemaPath`. `:210` still states what the block does for both parameter sets. No stubs.

## Not done

`modules\TierModel\TierModel.psd1:102` left untouched. It is the manifest's `ReleaseNotes` string:
shipped metadata surfaced by `Find-Module`/`Get-Module`, i.e. changelog-shaped release
documentation rather than a code comment. Joel's ruling is pending and was not pre-empted in either
direction.

## Why these two survived the 2026-09-06 strip pass

Not a miss inside the searched set — an enumeration that never included the file.

- `TierModel.psm1` was **unmodified in the working tree** before this turn, so the pass never wrote
  to it.
- The repo holds 80 `modules\TierModel\public\*.ps1` + 2 root entry scripts + 2 `optional\`
  scripts = **84**, which is exactly the "parse check across 84 files" recorded in that pass's
  notes. The correct scope is **86** — the missing two are the root module `.psm1` and the manifest
  `.psd1`.
- The 36 files the pass edited decompose as 32 public cmdlets + 2 entry scripts + 2 optional.

**The root module and the manifest were outside the enumeration by construction, so both the strip
and its verification were blind to them.** The pass itself was sound; its population was not.

Nothing else in that pass depended on the enumeration — the 139 edit ops were each AST-validated
against Comment tokens per range, independent of how the file list was built. The only other
measurement through the same lens was the parse check, same 84 files.

**Process change:** report the file COUNT and the enumeration rule next to any "0", not the 0
alone. "84 files, 0 hits" is falsifiable on sight against the repo's real 86; a bare "0" is not.
A population defined by file shape (`public\*.ps1` plus scripts) silently excludes the
structurally unusual members — a root module and a manifest — which are precisely the files no
other sweep is looking at either.

## Verification

- AST tokens at both edited lines are `Comment` (+ `NewLine`) only — no executable code in range.
- `git diff` on the file: exactly 2 insertions, 2 deletions, both comment lines.
- Size 43168 → 43145 = 23 bytes, matching `"BUG-023: "` (9) + `" (BUG-023 fix)"` (14) exactly.
- **`TierModel.psm1` carries NO BOM** (unlike the two entry scripts) and still carries none:
  first bytes `53 65 74`. Em dash on `:210` still `E2 80 94`. 0 parse errors.
- **Wider-scope sweep** — root `*-TierModel.ps1` + `modules\` + `optional\`, all
  `.ps1`/`.psm1`/`.psd1`, **86 files: 1 `BUG-` reference**, `modules\TierModel\TierModel.psd1:102`.
- **CI-shaped suite: 1924 passed / 2 failed of 1926** — unchanged, the same two Integration.Deploy
  tests invalidated by the BUG-045 fix and now owned by Wolverine.
- `Deploy-TierModel.ps1` and `Audit-TierModel.ps1` untouched this turn, both still `EF BB BF`.
  `tests\` untouched. Nothing staged, nothing committed, no scratch in the repo.
