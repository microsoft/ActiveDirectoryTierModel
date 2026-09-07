# Jean — History

## Learnings

### 2026-09-03 — CHANGELOG v2.0.0 + v2.1.0 authoring (branch `fix/gpo-silent-skip-and-false-success`)

Context: a previous agent fabricated the v2.0.0 section (non-existent cmdlets, non-existent
files, a bogus "Exchange 2019" reference). I re-authored it from evidence only.

- **Cite-a-file-or-omit works.** Every cmdlet named in the new v2.0.0 section was confirmed
  against `git diff --name-status v1.3.3 v2.0.0` AND against the live filesystem glob
  `modules\TierModel\public\*Auth*.ps1`. Both agree: exactly 13 new public cmdlets. The
  `FunctionsToExport` diff in `TierModel.psd1` was used as a third cross-check.
- **Do not trust `ReleaseNotes` in the `.psd1` as ground truth.** The v2.0.0 `ReleaseNotes`
  string attributes the auth-silo cmdlets to "1.3.3", which is wrong — the v1.3.3 tag does not
  contain them. Version-history prose inside the manifest has drifted; only the git diff and
  the filesystem are authoritative.
- **Config key names differ from the obvious guess.** `config/tiermodel-authsilos.json` uses
  `authenticationSilos`, not `authenticationPolicySilos`. Enumerate `PSObject.Properties.Name`
  before asserting anything about a config file.
- **A docstring can reference a config key that does not exist.**
  `Get-TierModelAuthSiloMembershipFd.ps1` mentions `authSilosExemptAccounts from
  tiermodel-authsilos.json`, but that key is absent from the shipped config. I therefore
  described the exemptions as *runtime* behaviour (the three `svc-*domainjoin` accounts mapped
  in `optional/Update-TierModelMembership.ps1`, plus RID-500) and did NOT claim they are
  config-driven. Comments are documentation, not evidence.
- **`Select-String -SimpleMatch` is unreliable in this repo.** Used
  `[System.IO.File]::ReadAllText($absolutePath)` + `[regex]::Matches` throughout, with full
  absolute paths. It never failed.
- **Investigating the diff surfaced real work the brief had not listed.** The branch also adds
  `SkippedGpos` / `SkippedGpoSummary` attribution in `Get-TierModelGpo.ps1` (the "silent skip"
  in the branch name), an ADMX central-store overwrite advisory, the removal of the dead
  `internal/` loader in `TierModel.psm1`, and a premature green ✅ in `New-TierModelUser.ps1`.
  Reading the whole `git diff --stat HEAD` before writing is worth the tokens.
- **The write-verification fix is wider than the two files named in the brief.**
  `Get-TierModelWriteFailureDetail` is used in 8 cmdlets. Grepping for the helper found the
  true blast radius; naming only the two given files would have understated it.
- **Honesty about the schema enum held up.** Verified `Test-Json` has zero occurrences repo-wide
  and `Test-TierModelConfig` is referenced only from `tests/` plus its own definition in the
  `.psm1`. Documented the enum as editor/IntelliSense-only, as instructed.
- **Quantified claims are cheap to verify and worth it.** `config/tiermodel-gpos.json`:
  0 occurrences of `"enforced"`, 146 GPO entries. Both counted directly.

Nothing was staged or committed. Working-tree edit to `CHANGELOG.md` only.

### 2026-09-03 (follow-up) — bug-ID cross-referencing with Cyclops

- **Tag bug IDs even when the bullet is already accurate.** My ADMX bullet was correct but
  Cyclops's review of `.research\known-bugs.md` was the trigger to confirm the `(BUG-012)` tag
  was present and to add his verified line citations (`Copy-TierModelAdmx.ps1:74–99`,
  `Get-TierModelAdmx.ps1:119–122` and `:180–183`). Traceability between the bug register and
  the CHANGELOG only works if the ID appears in both.
- **Do not attach an OPEN bug's ID to a bullet describing a FIX.** Cyclops supplied BUG-015 and
  BUG-016 for cross-referencing; both are still open, so tagging my fixed bullets with them
  would have read as "fixed in 2.1.0" and been wrong. I verified each on disk first:
  - BUG-015 — `tests/helpers/ADStubs.ps1:94` and `:106` still declare `Set-GPRegistryValue`
    with an empty body. My test fix touched only the *local* mock in
    `Integration.WinLapsDeployment.Tests.ps1`, a different file. Recorded as an explicit
    "this corrects the local mock only; the shared stubs remain open as BUG-015" note.
  - BUG-016 — `New-TierModelGpo.ps1:178` still has `default { 0 }`. Recorded as a stated
    remaining asymmetry, open by owner decision, explicitly "not addressed in this release".
  Naming what is still open next to what was fixed is more useful to Joel than a clean-looking
  entry, and it stops a future reader assuming the whole class of defect is closed.

