# Decision: Rogue — BUG-026, Audit fails to start from any foreign working directory

**Date:** 2026-09-05
**Author:** Rogue (Core Dev)
**Status:** **DECIDED — option (a), final for v2.1.0** (Joel, 2026-09-05). Implemented in code and
verified on disk by Joel; staged to the DC. Options (b) and (c) are **rejected**, see
"Decision on the module default" below. This record was corrected on 2026-09-05 — an earlier
revision claimed `New-TierModel` / `Set-TierModel` were publicly exported. **They are not.**
**Branch:** `feature/enable-verbose-debug`
**Requested by:** Joel Platek

## Context

Cyclops's 41-row lab matrix split perfectly clean: 22/22 Deploy PASS, 19/19 Audit FAIL, every
Audit row failing in ~1 second. The harness runs each row from a scratch `_procwd` directory.

Root cause, verified on disk and reproduced empirically:

- `modules\TierModel\public\Test-TierModelPrerequisites.ps1:50` declares
  `[string]$DependenciesPath = 'config/dependencies.json'` — a **CWD-relative** default.
  L99 `Test-Path`s it; L115 records `Dependencies file not found at: config/dependencies.json`.
- `Deploy-TierModel.ps1` overrides it with an absolute `$PSScriptRoot`-based path at **both**
  call sites (L817, L2600). This was already fixed once, as BUG-008 (see CHANGELOG line 176).
- `Audit-TierModel.ps1` overrode it at **neither** call site.

Consequence: `Audit-TierModel.ps1` could not start unless the operator happened to be `cd`'d into
the install directory. Pre-existing, not a regression from the verbose/debug work — but it defeats
the purpose of that work, whose entire operator story is "re-run Audit with `-EnableVerbose
-EnableDebug` for diagnostics".

## Decision — Option (a), implemented

Both Audit call sites now mirror Deploy's proven pattern, passing an absolute path:

```powershell
DependenciesPath = (Join-Path $PSScriptRoot 'config\dependencies.json')
```

- **L601** (primary prerequisite gate) — added as an explicit parameter on the existing direct
  invocation, alongside `-SkipRootCanonicalCheck`.
- **L1971-L1974** (`-Include*` standalone path) — `$prereqSplat` reshaped from a one-line hashtable
  to a multi-line one carrying `PreferredDc` and `DependenciesPath`; the subsequent conditional
  `$prereqSplat['Include*']` assignments are untouched.

Both carry a two-line comment naming BUG-026 so the next reader does not "simplify" it away.

`Deploy-TierModel.ps1` and `Test-TierModelPrerequisites.ps1` were **not** modified. `tests\` and
`.research\lab-validation\` were **not** touched. Nothing committed.

`[System.IO.Path]::GetFullPath()` was not used — it is banned in this repo for exactly this defect
class (it resolves against .NET's process CWD, which does not track PowerShell's location).

## Verification

| Check | Result |
|---|---|
| `Parser::ParseFile` on `Audit-TierModel.ps1` | **0 errors** |
| AST re-derivation of both call sites | both bind `DependenciesPath`; splat carries the key |
| **Control** — `Test-TierModelPrerequisites -PreferredDc ... -SkipRootCanonicalCheck` (default path) from a scratch `$env:TEMP` dir | `Dependencies file not found at: config/dependencies.json` — bug reproduced |
| **Fix** — `Audit-TierModel.ps1 -PreferredDc nonexistent.dc.local -OuOnly` run from a scratch `$env:TEMP` dir | deps gate **gone**; run proceeds to genuine DC-connectivity errors and the diagnostics hint |
| Unit suite, by path (`tests\Unit.*.Tests.ps1`) | **1573 passed / 0 failed / 0 skipped** — baseline matched |
| Integration suite, by path (`tests\Integration.*.Tests.ps1`) | **318 passed / 0 failed / 0 skipped** — baseline matched |

Neither suite number moved. Neither suite exercises this defect: the Integration Audit tests
`Mock Test-TierModelPrerequisites` wholesale, so the real parameter binding is never reached, and
Pester runs from the repo root where the CWD-relative default happens to resolve. **A green suite
proves nothing here — the scratch-directory control run is the real evidence.**

## OPEN — the module default itself (Joel to decide)

Full caller inventory of `Test-TierModelPrerequisites` across the repo:

### Shipped, non-test invocations: **6**

| # | Site | Passes `DependenciesPath`? |
|---|---|---|
| 1 | `Deploy-TierModel.ps1:817` (`$prereqSplat`) | ✅ absolute, `$PSScriptRoot` |
| 2 | `Deploy-TierModel.ps1:2600` (`$prereqSplat`) | ✅ absolute, `$PSScriptRoot` |
| 3 | `Audit-TierModel.ps1:601` | ✅ **now** absolute (was relying on the default) |
| 4 | `Audit-TierModel.ps1:1980` (`$prereqSplat`) | ✅ **now** absolute (was relying on the default) |
| 5 | `modules\TierModel\TierModel.psm1:694`, in **`New-TierModel`** | ⚠️ passes the parameter, but its **own** `$DependenciesPath` default at L678 is the identical CWD-relative literal `'config/dependencies.json'` |
| 6 | `modules\TierModel\TierModel.psm1:794`, in **`Set-TierModel`** | ⚠️ same — own default at L778 is the same CWD-relative literal |

**Sites 5 and 6 are internal-only.** They *look* compliant in a grep, but they merely launder the
same CWD-relative default one layer up.

> **CORRECTION (2026-09-05).** An earlier revision of this record claimed `New-TierModel` and
> `Set-TierModel` are "publicly exported (`TierModel.psd1`), so any customer calling them from a
> foreign working directory hits BUG-026 too." **That claim was false and I withdraw it.** It came
> from a substring match: `TierModel.psd1` contains `New-TierModelGpo`, `New-TierModelOu` and
> fourteen other prefixed names that *contain* the string `New-TierModel`, and I read those as
> hits for the bare name. Joel caught it. Verified three ways since:
>
> 1. Exact-match search of `TierModel.psd1` for `'New-TierModel'` / `'Set-TierModel'` as
>    standalone quoted list entries → **0 hits**.
> 2. **0** occurrences of `Export-ModuleMember` anywhere in `TierModel.psm1`, so the manifest's
>    explicit `FunctionsToExport` list is authoritative.
> 3. Runtime, the settling evidence — `Import-Module .\modules\TierModel\TierModel.psd1 -PassThru`
>    in a clean session: **83 exported**, `'New-TierModel' exported? False`,
>    `'Set-TierModel' exported? False`. Matches Joel's independent run exactly.
>
> **Consequence: the customer-impact argument for option (b) is void.** No customer can reach
> these two functions. The only customer-reachable path was Audit, which option (a) has fixed.

### Test invocations: **87** — 86 pass `DependenciesPath`, **1** does not

- `tests\Integration.TierModel.Tests.ps1:28` — `Test-TierModelPrerequisites -PreferredDc $testDc`,
  deliberately exercising the default. This is the single test that a mandatory-parameter change
  would break outright.
- All 86 others (`tests\Unit.Prerequisites.Tests.ps1`, the rest of `Integration.TierModel`) pass an
  explicit temp-file path and are indifferent to the default.
- The ~60 `Mock Test-TierModelPrerequisites` lines in `Integration.Audit.Tests.ps1`,
  `Integration.Deploy.Tests.ps1` and `Unit.TierModelModule.Tests.ps1` replace the command entirely
  and are unaffected by any signature change.

### Comment-based help examples: **2**, both in `Test-TierModelPrerequisites.ps1`

- L29 — relies on the default.
- L37 — passes a relative `"custom/deps.json"`, which models the very trap we are closing.

### Docs: **0 invocations**

`docs\canonical-acl.md:263`, `docs\language-support.md:47`,
`docs\quick-deployment-guide.md:129` and the `docs\test-coverage.md` references are all prose
mentions, not runnable examples. `optional\` has **no** callers. The one `.research\` caller
(`bug006\Invoke-GateValidation.ps1:9`) already passes an absolute path.

## Decision on the module default — (a) stands, (b) and (c) rejected

Joel's call, 2026-09-05, and I agree with it now that my export claim is retracted:

- **(b) rejected.** `Test-TierModelPrerequisites` *is* exported. Making one of its parameters
  mandatory is a breaking signature change, and v2.1.0 is a minor release under the SemVer this
  repo explicitly follows. Breaking a public function to defend two unreachable internal callers
  is a bad trade. My earlier recommendation of (b) rested entirely on the false export claim.
- **(c) rejected.** `modules\TierModel\` walking upward to a repo-root `config\` is a guess about
  deployed layout; a plausible-but-wrong path is worse than a loud failure.
- **(a) final.** The two Audit call sites now pass an absolute `$PSScriptRoot` path, matching
  Deploy. The module default is left alone.

## Follow-up finding — are the two wrappers reachable at all?

Joel asked whether `New-TierModel` / `Set-TierModel` are called from anywhere, using exact command
names rather than substrings. Swept the whole repo (`modules\`, `tests\`, `optional\`, `docs\`,
both root scripts, `specs\`) two ways: a word-boundary regex `(?<![-\w])(New|Set)-TierModel(?![-\w])`
across `.ps1/.psm1/.psd1/.md/.json/.yml`, and an AST pass over every `.ps1/.psm1` matching
`CommandAst.GetCommandName()` **exactly**. The AST pass is the authoritative one: it counts command
position only, so `New-TierModelOu` and the `New-TierModel*` wildcards in prose cannot register.

**Result: 22 invocations, all in tests, all of one file.**

| Location | Count | Notes |
|---|---|---|
| `tests\Unit.TierModelModule.Tests.ps1` L886–L1021 | 10 | `New-TierModel`, via `InModuleScope` (the file's own header comments at L11–L12 label both "private — via InModuleScope") |
| `tests\Unit.TierModelModule.Tests.ps1` L1049–L1196 | 12 | `Set-TierModel`, same mechanism |
| **Everywhere else** | **0** | `Deploy-TierModel.ps1`, `Audit-TierModel.ps1`, `modules\`, `optional\`, `docs\`, `specs\` — no invocation of either |

Also checked for indirect reachability that a command-name sweep would miss —
`Invoke-Expression`, `& 'New-TierModel'`, `Get-Command 'New-TierModel'` — **0 hits repo-wide**.
`tests\Integration.Convergence.Tests.ps1:106` is a stale comment (`# Mock Set-TierModel to avoid
actual execution`) with no corresponding `Mock` or call; the test below it exercises
`Get-TierModelPlan` instead.

**So: zero production callers. The only thing that executes these functions is the test file that
exists to cover them.** `docs\test-coverage.md:801-802` already documents both as "(private)".

### One more signal Joel should weigh: `Set-TierModel` is broken by construction

`TierModel.psm1:868`, inside `Set-TierModel`, calls `Invoke-TierModelPlan -Plan $plan`. That
function is **defined nowhere in the repo** — the AST sweep finds exactly one occurrence of the
name, and it is that call site. `docs\test-coverage.md:254` records the same thing as coverage
hard-limit (6): *"the function is called but never defined anywhere in the module, making this
branch permanently unreachable."* `Set-TierModel`'s apply path would throw `CommandNotFoundException`
if it were ever reached. A function whose execution path cannot complete, which nothing calls, is
dead code — not a latent bug worth patching.

### Blast radius if Joel chooses deletion — **report only, nothing edited**

- **`Unit.ModuleManifest.Tests.ps1` is not at risk.** Joel flagged that it builds expectations from
  the `public\` folder listing (`$script:PublicPath` at L8, `Get-ChildItem -Filter '*.ps1'` at
  L191). Both functions live in `TierModel.psm1`, **not** in `public\` — a filter of that folder
  for these two basenames returns **0**. Deleting them cannot move the manifest test's expectations.
- **What would have to move with them:** the two `Describe` blocks in
  `tests\Unit.TierModelModule.Tests.ps1` (roughly L866–L1210, 22 invocations) plus its header
  comments at L11–L12 — Wolverine's file, so his call and his sequencing.
- **Coverage docs** would need `docs\test-coverage.md` L254 hard-limit (6), L801–802 and L816
  updated — Scribe's.
- Suite deltas would need re-baselining afterwards, since those Describe blocks contribute to the
  Unit 1573.

**I have edited nothing.** Deletion touches the module surface and is Joel's sign-off.

## Follow-ups

- Joel to decide on deleting `New-TierModel` / `Set-TierModel` (and the now-orphaned
  `Invoke-TierModelPlan` call). If yes, sequence the `tests\` edit with Wolverine and the
  `docs\test-coverage.md` edit with Scribe.
- `CHANGELOG.md` entry for BUG-026 not written — Scribe owns it. Option (a) is now final, so the
  wording can be settled: Audit's two prerequisite call sites now resolve
  `config\dependencies.json` from `$PSScriptRoot`, matching the BUG-008 fix in Deploy.
