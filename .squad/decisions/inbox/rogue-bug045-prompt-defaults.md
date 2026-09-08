# Decision: prompt defaults for -OutputFileBase (BUG-045)

- **Author:** Rogue
- **Date:** 2026-09-07
- **Branch:** feature/enable-verbose-debug (uncommitted; Joel reviews and commits)
- **Requested by:** Joel Platek
- **Files:** `Deploy-TierModel.ps1`, `Audit-TierModel.ps1` (product code only; no tests touched)

## Decision

Pressing Enter at a `-OutputFileBase` prompt now resolves to a script-specific default instead of
throwing. Applied identically at all three prompt sites, re-derived from the AST before editing:

| Site | Trigger | Default |
|---|---|---|
| `Deploy-TierModel.ps1:307-313` | explicit `-Logging`, no base | `Deploy-TierModel` |
| `Audit-TierModel.ps1:529-535` | explicit `-Logging`, no base | `Audit-TierModel` |
| `Audit-TierModel.ps1:489-495` | `-OutputFormat`, no base | `Audit-TierModel` |

Shape at each site:

```powershell
# Empty input falls back to the default; an operator pressing Enter must not stop the run.
$defaultOutputFileBase = '<Deploy|Audit>-TierModel'
$OutputFileBase = Read-Host "Enter base filename for ... [$defaultOutputFileBase]"
if ([string]::IsNullOrWhiteSpace($OutputFileBase)) {
    $OutputFileBase = $defaultOutputFileBase
    Write-Host "Using default base filename for ...: $OutputFileBase" -ForegroundColor DarkGray
}
```

The two `throw "OutputFileBase cannot be empty ..."` statements are gone.

## Rationale for the specifics

- **Default shown in the prompt, not applied silently.** An operator who presses Enter can see what
  they are about to get before they press it.
- **Resolved value echoed once.** Puts the effective base name in the console and transcript, so a
  defaulted run is diagnosable after the fact.
- **`IsNullOrWhiteSpace` retained.** Whitespace-only input is still treated as empty; it now falls
  back rather than throwing.
- **Site 3 default matches site 2** (`Audit-TierModel`). It has no auto-enable equivalent to
  inherit from, and a single Audit-wide default is what an operator would predict.

## Explicitly NOT done

- **The two branches were NOT collapsed.** `if ($script:LoggingAutoEnabled) { silent default }
  else { prompt }` now ends in the same literal default in both arms and looks redundant. It is not.
  D8 requires that the auto-enabled path never even DISPLAY a prompt, so a diagnostics run stays
  copy-pasteable and runnable in a non-interactive host. Merging the arms would reintroduce a
  prompt on the diagnostics path — a silent regression the current test suite would not catch.
- **The Y/N confirmation gates at `Deploy-TierModel.ps1:795` and `:817` were not touched.**
  Cancel-exits-0 is Joel's by-design ruling.
- **No default added to the `-OutputFormat` parameter itself.** `-OutputFormat` with no value fails
  at PowerShell parameter binding before any script code runs; a param-block default cannot change
  that. Joel's "format" case is the prompt it triggers, which is site 3, and that is what was fixed.
- **No `BUG-` number written into code.** The one-line comment states the constraint in present
  tense with no number and no history.

## Documentation follow-through

Three comment-based help blocks stated the removed behaviour and were corrected: Deploy
`.PARAMETER OutputFileBase`, Audit `.PARAMETER OutputFileBase`, Audit `.PARAMETER Logging`
("an empty response is an error").

## Evidence

Harness outside the repo, six scenarios in child `pwsh` processes: dot-source
`tests/helpers/ADStubs.ps1`, replace `Read-Host` with a global function that records every prompt
string and returns empty, run the real entry script.

| Scenario | Prompts recorded | Log file | Hint replay |
|---|---|---|---|
| Deploy `-EnableVerbose` | **none** | `Deploy-TierModel-*.log` | `-OutputFileBase 'Deploy-TierModel'` |
| Deploy `-EnableDebug` | **none** | `Deploy-TierModel-*.log` | `-OutputFileBase 'Deploy-TierModel'` |
| Deploy `-Logging` | 1, `... [Deploy-TierModel]` | `Deploy-TierModel-*.log` | `-OutputFileBase 'Deploy-TierModel'` |
| Audit `-EnableVerbose` | **none** | `Audit-TierModel-*.log` | `-OutputFileBase 'Audit-TierModel'` |
| Audit `-Logging` | 1, `... [Audit-TierModel]` | `Audit-TierModel-*.log` | `-OutputFileBase 'Audit-TierModel'` |
| Audit `-OutputFormat Text` | 1, `... [Audit-TierModel]` | n/a (logging off) | `-OutputFileBase 'Audit-TierModel'` |

No scenario threw. NON-BLOCKING-3 holds: the diagnostics-hint replay emits the RESOLVED
`-OutputFileBase` in all six, so a copy-pasted re-run does not hit `Read-Host`.

Baselines: Unit **1608/1608/0**. Integration **316 passed / 2 failed of 318**. CI-shaped
(`ADStubs` dot-sourced, `Run.Path = "tests"`, one session) **1924 passed / 2 failed of 1926 across
32 test files**. Both entry scripts re-verified `EF BB BF` with 0 parse errors after the final
write. Nothing staged, nothing committed.

## Open items for Wolverine (tests are not mine to edit)

1. **`tests\Integration.Deploy.Tests.ps1:1822` and `:1832`** — "Should throw when OutputFileBase is
   empty string / is whitespace-only while Logging enabled", both asserting
   `*OutputFileBase cannot be empty*`. These **encode the old throw-on-empty behaviour** that Joel
   asked to remove. They did not catch a regression. Test totals are unchanged (318, 1926), so
   there is no collateral breakage. They need to be re-pointed at the new contract: prompt is
   shown, empty input resolves to the default, run continues.
2. **The D8 guarantee has zero test coverage.** `EnableVerbose` and `LoggingAutoEnabled` appear
   nowhere under `tests\`. The "auto-enable must never prompt" invariant is lab-confirmed and
   comment-documented but unenforced, which is exactly why the two-branch structure is easy to
   collapse by accident. A recorder-style test like the harness above would pin it.

## Correction to the brief

Product code is **not** at 0 `BUG-` references. Three pre-exist at HEAD and are untouched:
`modules\TierModel\TierModel.psm1:180`, `:210`, and a `BUG-001..011` mention inside the
`ReleaseNotes` string at `modules\TierModel\TierModel.psd1:102`. The two **entry scripts** are at 0
and remain at 0.
