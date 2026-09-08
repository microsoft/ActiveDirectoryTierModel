# Feature Specification: Diagnostic Logging Switches (`-EnableVerbose` / `-EnableDebug`)

**Feature Branch**: `feature/enable-verbose-debug`
**Created**: 2026-09-05 (authored retroactively — implementation preceded the spec folder)
**Status**: Implemented and **lab-validated** — RUN 1 on 2026-09-05, 50 rows, 0 FAIL
(`.research/lab-validation/LAB-RUN-PROGRESS.md`). Six audit reporting accuracy improvements landed after
that run, so the **audit report path** has changed and is pending a confirmatory pass (`tasks.md` T027).
**Input**: Locked design decisions D1–D8 (Joel-approved), the POC results recorded in
`.research/verbose-debug-implementation-plan.md` §1b/§1c, and `.research/verbose-vs-debug-design.md`.
This spec documents a finalized and already-implemented design — no new design decisions are introduced here.

> **Retroactive spec notice**: the `-EnableVerbose` / `-EnableDebug` work was built before its numbered
> spec folder existed. This document, `plan.md` and `tasks.md` were written after the fact from the code on
> disk and the research record. Where this spec cites a line number, that number was read from the working
> tree on 2026-09-05 and is stated as evidence, not as a design instruction.

---

## ⛔ HARD PRODUCTION PROHIBITION

> **Never forward `-Debug` as an explicit parameter to an `ActiveDirectory` or `GroupPolicy` cmdlet.**
>
> Lab-proven to throw `Object reference not set to an instance of an object` in a non-interactive host.
> The same prohibition covers `@PSBoundParameters` splats into an AD/GPO call, because a splat can carry
> `-Debug` in silently.
>
> Setting the **preference variable** (`$DebugPreference = 'Continue'`) is safe, and is what the
> implementation does. Explicit `-Verbose` on an AD/GPO cmdlet is **not** prohibited.
>
> This matters more than any other line in this spec: a `-Debug` NRE fires precisely when the operator has
> turned diagnostics on because something is already broken.

---

## Motivation

A customer reported two GPOs failing to create, with no error surfaced and no logs to inspect.

**The root-cause investigation for that incident is FORMALLY CLOSED and the cause is UNKNOWN.**
No statement in this spec, in `plan.md`, in `tasks.md`, in code comments, in help text or in a commit
message may assert or imply a cause.

The purpose of this feature is stated only as: **when something goes wrong, the operator re-runs with
diagnostics and gets something useful to send to Microsoft.** It is an observability feature. It makes no
promise about revealing why any particular GPO operation failed.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator re-runs a failed deployment with diagnostics (Priority: P1)
An administrator whose deployment produced an unhelpful result re-runs
`Deploy-TierModel.ps1 -PreferredDc DC01 -OuOnly -EnableVerbose` and obtains verbose output on the console
and a log file on disk, without having remembered to pass `-Logging`.

**Acceptance Scenarios**:
1. **Given** a run with `-EnableVerbose` and no `-Logging`, **When** the script starts, **Then** `-Logging`
   is enabled automatically, the console announces that it was, and a log file is written.
2. **Given** the same run and no `-OutputFileBase`, **Then** the base name defaults silently to the script
   name — **no `Read-Host` prompt occurs**.
3. **Given** a run with neither diagnostics switch, **Then** behaviour is identical to the pre-feature
   script: no `Debug\` folder, no transcript, no log file that would not otherwise have existed.

### User Story 2 — Operator captures a full session to send to Microsoft (Priority: P1)
An administrator runs
`Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -EnableVerbose -EnableDebug -LogPath C:\Logs`
and obtains verbose output, debug output, and an unredacted transcript of the console session in a `Debug\`
subfolder, together with an on-screen warning that the transcript is unredacted.

**Acceptance Scenarios**:
1. **Given** both switches, **Then** a transcript is started in `<LogPath>\Debug\` and its path is printed.
2. **Given** only one switch, **Then** no transcript is started.
3. **Given** a transcript was started, **Then** the console carries an explicit unredacted-content warning.
4. **Given** `Start-Transcript` fails or is suppressed, **Then** the script warns and continues; the run is
   never aborted for a diagnostics failure.

### User Story 3 — Audit parity (Priority: P1)
A security engineer runs `Audit-TierModel.ps1 -PreferredDc DC01 -GposOnly -EnableVerbose -EnableDebug` and
gets the same diagnostics contract as Deploy: auto-enabled logging, a `Debug\` folder, and a transcript.

**Acceptance Scenarios**:
1. **Given** the same switch combination on either script, **Then** the observable diagnostics behaviour is
   the same — folder location, transcript gating, announcement, prompt behaviour.
2. **Given** `Audit-TierModel.ps1 -Logging` **without** `-OutputFileBase`, **Then** the operator is prompted,
   exactly as on Deploy — explicit `-Logging` retains its shipped prompting behaviour.

### Edge Cases
- `-EnableVerbose` alone → verbose output, log file, **no** transcript.
- `-EnableDebug` alone → debug output, log file, **no** transcript.
- Both switches under `-WhatIf` (Deploy only) → the log directory, the `Debug\` folder and the transcript
  must all be created for real. They record the preview; they are not part of the change being previewed.
- `Start-Transcript` under `-WhatIf` → throws nothing and creates nothing (POC-2). Success must be confirmed
  with `Test-Path`, never inferred from the absence of an exception.
- An operator's own outer transcript is already running → a nested `Start-Transcript` is harmless (POC-3);
  an **unpaired `Stop-Transcript` is not** — it silently stops the operator's transcript.
- Read-only or unavailable `-LogPath` → warn, continue, no transcript.
- Relative `-LogPath` invoked from a directory other than the repo root → the log file and `Debug\` must
  share a parent directory (POC-6).
- Ctrl-C mid-run → global preference variables are never touched, because they are never written; an open
  transcript keeps capturing until the console exits, and the operator is warned of this on screen.
- Console output under `-EnableDebug` is noisy. **Accepted by Joel.** No console-cleanliness machinery.

---

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: Both entry scripts MUST expose `-EnableVerbose` and `-EnableDebug` as `[switch]` parameters.
  **(D1)** The names are deliberately chosen so the PowerShell common parameters `-Verbose` and `-Debug`
  remain free and unshadowed.
- **FR-002**: The two switches MUST compose: either alone, or both together.
- **FR-003**: Diagnostic artefacts MUST be written to a **`Debug\` subfolder** of the resolved log
  directory, kept separate from normal logs. **(D2)**
- **FR-004**: The `Debug\` folder and the log file MUST be derived from a single absolutised base path so a
  relative `-LogPath` cannot separate them. `GetUnresolvedProviderPathFromPSPath` is the required idiom;
  `Resolve-Path`/`Convert-Path` throw on a not-yet-existing path and `[System.IO.Path]::GetFullPath()` is
  **banned** — it resolves against the .NET process current directory, which does not track PowerShell's
  location. **(POC-6)**
- **FR-005**: There MUST be **no retention or rotation policy** for Deploy or Audit diagnostics. **(D3)**
  Deploy and Audit are run once to confirm things. This deliberately differs from
  `optional/Update-TierModelMembership.ps1`, which runs as a scheduled task and keeps 7 days — that script
  is out of scope and is not modified.
- **FR-006**: Either switch MUST auto-enable `-Logging`, and MUST **announce** on the console that it did
  so. **(D8)** The switches never prompt.
- **FR-007**: **The prompt rule.** An *explicit* `-Logging` without `-OutputFileBase` MUST prompt. On Deploy,
  this is existing shipped behaviour, preserved unchanged; on Audit, the `-Logging` switch and its prompt
  behaviour are new in this release. An *auto-enabled* `-Logging` MUST NEVER prompt — it takes a silent
  default — because a diagnostics re-run has to remain copy-pasteable and runnable in a non-interactive host.
  The two paths MUST be distinguished by an explicit flag, not inferred.
- **FR-008**: A transcript MUST be started **only when BOTH switches are supplied**. **(D6)**
  `-EnableVerbose` alone is the routine "show me more" case and must not produce an unredacted console
  capture; requiring both makes the transcript a deliberate act.
- **FR-009**: The transcript is **unredacted** and MUST carry a blunt on-screen warning to that effect,
  including the instruction to review it for host names, account names and other environment detail before
  sharing it, and a statement that a Ctrl-C leaves it open and capturing.
- **FR-010**: Transcript success MUST be confirmed with `Test-Path` and recorded in a state flag. Success
  MUST NOT be inferred from the absence of an exception. **(POC-2)**
- **FR-011**: `Stop-Transcript` MUST NEVER be called unguarded. It MUST be called only when the state flag
  from FR-010 records a confirmed start. **(POC-3)** An unpaired stop succeeds silently against the
  *operator's* transcript.
- **FR-012**: Diagnostics MUST be best-effort. A failure to create the log directory, the `Debug\` folder or
  the transcript MUST warn and continue. It MUST NEVER abort a deployment or an audit.
- **FR-013**: Under `-WhatIf` (Deploy is `SupportsShouldProcess`; Audit is not), the diagnostics apparatus
  MUST be created for real, using per-call `-WhatIf:$false`. **(POC-2)**
- **FR-014**: Preference variables MUST be raised **after** the TierModel module import, at **script scope
  and module scope**, and **never at global scope**. **(POC-8, POC-9)** Ordering is load-bearing:
  `-Verbose:$false` on the import does not suppress the module body's own `Write-Verbose` records; only
  importing first, while `VerbosePreference` is still `SilentlyContinue`, reaches zero. Script scope alone
  reaches module functions with zero records — the module-scope assignment is genuinely required.
- **FR-015**: `-Verbose:$false` MUST remain on the module import. It is what covers the bare
  `ActiveDirectory`/`GroupPolicy` imports that run after preferences go live, which ordering alone cannot
  protect.
- **FR-016**: Global preference variables MUST NOT be modified at all — not modified and restored,
  **not modified**. Because nothing global is written, no `try/finally` restore and no `$Original*Preference`
  capture exists, and Ctrl-C cannot leak state into the operator's session. The module-scope value persists
  for the session, but both scripts `Import-Module -Force` at startup, so it self-heals between runs.
- **FR-017**: `-Debug` MUST NEVER be forwarded as an explicit parameter to an AD or GroupPolicy cmdlet, and
  `@PSBoundParameters` MUST NEVER be splatted into an AD or GroupPolicy call. See the hard prohibition above.
- **FR-018**: On failure paths, the scripts MUST print a copy-pasteable re-run line that adds
  `-EnableVerbose -EnableDebug` to the operator's original invocation. The hint MUST be suppressed when both
  switches are already present, and the emitted string MUST round-trip as a valid invocation.
- **FR-019**: A run with **neither** switch MUST be indistinguishable from the pre-feature behaviour. This is
  the regression contract that protects every existing user.
- **FR-020**: A diagnostics switch MUST NOT be inert. Both switches on both scripts must produce observable
  effects (preference reach, `Debug\` folder, transcript). A silently no-op diagnostics switch is worse than
  an absent one: it fires when something is already broken and reports "diagnostics showed nothing" instead
  of "diagnostics never ran".

### Key Entities
- **DiagnosticsEnabled**: `-EnableVerbose -or -EnableDebug`. Gates auto-logging, the `Debug\` folder and the
  preference assignment.
- **LoggingAutoEnabled**: the flag that distinguishes explicit `-Logging` (prompts) from auto-enabled
  `-Logging` (never prompts). FR-007 depends entirely on this distinction being explicit.
- **DebugFolderPath**: `<resolved log directory>\Debug`, or `$null` when it could not be created.
- **TranscriptStarted**: load-bearing boolean, set **only** after `Test-Path` confirms the transcript file
  exists. It is the sole guard on `Stop-Transcript`.

---

## Lab-Measured Findings That Justify the Design

These were measured, not assumed. They constrain what the feature can honestly promise.

| # | Finding | Consequence |
|---|---------|-------------|
| M-1 | `ActiveDirectory` is a **Manifest** module, loaded in-process. | Preference variables can reach it. |
| M-2 | `GroupPolicy` is a **Script** module whose `Get-*` commands are **proxy functions executing in a remote WinPSCompat PowerShell 5.1 runspace**. | Diagnostic streams raised in our runspace do not automatically follow the call into theirs. |
| M-3 | **No AD or GPO cmdlet emits a Debug record at all.** | `-EnableDebug`'s value comes from *our own* `Write-Debug` / `-Level Debug` sites, not from the platform modules. The feature must not promise platform debug detail. |
| M-4 | ~~Explicit `-Verbose` on an AD **write** yields exactly **1** record naming the target DN, even when the operation fails.~~ **PARTLY FALSIFIED 2026-09-05 — see D11.** The record appears on a successful write and on a write refused *after* the target resolved. It does **not** appear when the target does not exist. | Still the most useful diagnostic AD offers, but it is silent on absence. Scope claims accordingly. |
| M-5 | `New-GPO -Verbose` yields **ZERO** records. | GPO creation produces no verbose evidence. Stated here so nobody promises otherwise. Provenance and re-measurement caveat in D11. |
| M-10 | `$VerbosePreference = 'Continue'` alone yields **ZERO** ShouldProcess records — from AD cmdlets, from a hand-written `SupportsShouldProcess` function, and from `New-Item` alike. The preference variable governs `Write-Verbose`; it does **not** enable ShouldProcess operation descriptions. | This is a PowerShell mechanism, not an AD quirk. It is the whole reason WI-18 exists as separate work rather than falling out of `-EnableVerbose`. **(D11)** |
| M-6 | Explicit `-Debug` on AD/GPO cmdlets throws NRE in a non-interactive host. | FR-017, the hard prohibition. |
| M-7 | POC-2: under `-WhatIf`, `Start-Transcript` throws nothing and creates no file. | FR-010, FR-013. |
| M-8 | POC-3: a nested `Start-Transcript` is harmless; an **unpaired `Stop-Transcript` is not**. | FR-011. |
| M-9 | POC-8 / POC-9: `-Verbose:$false` alone is insufficient; script scope alone reaches module functions with 0 records. | FR-014, FR-015. |

---

## Implementation Evidence (read from the working tree, 2026-09-05)

| Concern | `Deploy-TierModel.ps1` | `Audit-TierModel.ps1` |
|---|---|---|
| Switch declarations | L239 (`$EnableVerbose`), L242 (`$EnableDebug`) | L213, L216 |
| Auto-enable `-Logging` + prompt rule | L286–L310 | L534–L545 |
| Auto-enable announcement | L361 | L604 |
| `Debug\` folder creation | L370–L388 | L626–L644 |
| Preference assignment (script + module scope, post-import) | L714–L728 | L693–L707 |
| Transcript start, `-WhatIf:$false`, `Test-Path` confirmation, unredacted warning | L743–L765 | L721–L743 |
| Guarded `Stop-Transcript` | L481–L511 | L414–L441 |
| Copy-pasteable re-run hint | L517–L562 | L447–L493 |

Both files carry a **UTF-8 BOM** that must survive any future edit.

---

## Post-Implementation Decisions — D11 … D15

> **On the D-number.** The `D`-series is a single shared series originating in the decision table of
> `.research/verbose-vs-debug-design.md`, which runs **D1 … D10** (`D9` = forward `-Verbose` to AD/GPO call
> sites; `D10` = treat "false success" as a bug fix). This spec and `plan.md` quote D1, D2, D3, D5, D6 and
> D8 from that same series. The highest number ever assigned in the origin document is **D10**; D11 and D12
> were allocated here on 2026-09-05. Re-verified on **2026-09-06** by re-reading the origin decision table
> (`D1 … D10`, no additions) and searching every `.md` in the repository for a `D`-number citation: the
> highest in use anywhere is **D12**, so the next free number is **D13**. D13, D14 and D15 are allocated
> below. Numbers are never reused. These decisions are recorded here, in the spec, because attempts to store
> project conventions in agent memory have failed with *"repository was not found"* — **the spec files are
> the durable home for decisions.** That is also why D1 lives in `spec.md` rather than in memory.

---

### D11 — WI-18 / D9 (`-Verbose` on AD/GPO call sites) is **MEASURED and DEFERRED**. It does not ship in v2.1.0.

**Joel's ruling, verbatim:** *"Defer but include more details for later I need to see examples and if does not
impact v2.1.0 release."*

**Impact on v2.1.0: NONE.** WI-18 is purely additive annotation of existing call sites. No FR in this spec
depends on it — FR-001 … FR-020 are all satisfied by the switch machinery, which is implemented, and whose own
`Write-Verbose` instrumentation is exercised by the 50-row lab matrix (RUN 1, 0 FAIL). *(Precision: the round-4
ladder arms L1/L2 measure a bare preference variable in a standalone probe, not the `-EnableVerbose` switch
reaching the TierModel module. They establish the mechanism; the product-level claim rests on the lab matrix
and on round 1's module-scope arm A3, not on L1/L2.)* No test, no CI gate and no documentation page is blocked
by WI-18's absence. Deferring it removes nothing that exists today: the product emits **zero** target-naming
verbose records from AD/GPO call sites now, and will continue to, which is the status quo rather than a
regression. **Deferring WI-18 does not impact the v2.1.0 release.**

#### What was actually measured

Instruments: `.research/lab-validation/Measure-VerbosePreferenceGap.ps1` (round 1) and
`-Round2/-Round3/-Round4.ps1`. **Three instruments were discarded before one was trusted** — round 2 voided
round 1's preference arms on an untested assumption; round 3 was voided outright because it matched
`^VERBOSE: ` against pwsh 7 console output that `$PSStyle` had already wrapped in ANSI, and so read `0` for an
arm round 1 had proven to be `1`. Round 4 is the instrument of record for the **AD** arms.

Round 4 first proves the capture in both directions, then measures:

| Arm | Mechanism | Records naming the target |
|-----|-----------|---------------------------|
| L1 | preference only, `Write-Verbose` directly | **1** |
| L2 | preference only, `Write-Verbose` inside an advanced function | **1** |
| L3 | preference only, hand-written `$PSCmdlet.ShouldProcess` | **0** |
| L4 | preference only, `New-Item` | **0** |
| AD1 | explicit `-Verbose`, `Set-ADOrganizationalUnit`, write **succeeds** | **1** |
| AD2 | preference only, same write | **0** |
| AD3 | explicit `-Verbose`, `Remove-ADOrganizationalUnit` **refused after the object resolved** | **1** |
| AD4 | preference only, same refusal | **0** |
| AD5 | explicit `-Verbose`, `Set-ADOrganizationalUnit` on a **DN that does not exist** | **0** |
| G1 / G2 | `New-GPO`, explicit `-Verbose` / preference only (round 1) | **0** / **0** |

The two records that were captured, verbatim:

```text
VERBOSE: Performing the operation "Set" on target "OU=CyclopsR4Ok,DC=tierlab,DC=internal".
VERBOSE: Performing the operation "Remove" on target "OU=CyclopsR4Protected,DC=tierlab,DC=internal".
```

#### The mechanism, stated plainly because it is counter-intuitive

`$VerbosePreference = 'Continue'` governs **`Write-Verbose`**. It does **not** enable ShouldProcess operation
descriptions (`Performing the operation "X" on target "Y"`). Only an explicit `-Verbose` on the call does
that. L3 and L4 prove this is a **PowerShell** behaviour and not an Active Directory quirk: a hand-written
`SupportsShouldProcess` function and `New-Item` behave exactly as the AD cmdlets do. This is recorded as M-10.

#### The caveat that decides the value

The DN-naming record covers **success and post-resolution refusal** (permission, constraint, protection). It
is **silent when the target object does not exist** (AD5) — which is the commonest audit and drift case. So
the annotation buys evidence about *refused writes on objects that are there*, and nothing about *absence*.

#### Before / after — what the change would look like

Representative call site, `modules/TierModel/public/New-TierModelOu.ps1` L181 (the `@newOuParams` splat is a
purpose-built hashtable, **not** `@PSBoundParameters`, and is therefore permitted):

```powershell
# BEFORE (today, all 216 AD/GPO call sites)
$newOU = New-ADOrganizationalUnit @newOuParams -ErrorAction Stop

# AFTER (WI-18 as proposed — gated so a non-diagnostic run is unchanged, FR-019)
$newOU = New-ADOrganizationalUnit @newOuParams -ErrorAction Stop -Verbose:($VerbosePreference -eq 'Continue')
```

The observable difference in an `-EnableVerbose` log, using the shapes actually measured:

```text
# BEFORE — the operator gets our own instrumentation only; nothing names the directory object
VERBOSE: [New-TierModelOu] Creating OU 'Tier0-Servers'
<error text, no target DN from the platform>

# AFTER — a refused write on an object that resolves gains one platform record naming the DN
VERBOSE: [New-TierModelOu] Creating OU 'Tier0-Servers'
VERBOSE: Performing the operation "Set" on target "OU=Tier0-Servers,DC=contoso,DC=com".
<error text>

# AFTER — but a target that does not exist still yields nothing extra. This is the limit of the change.
VERBOSE: [New-TierModelOu] Creating OU 'Tier0-Servers'
<error text, still no target DN>

# AFTER — GroupPolicy gains nothing at all, in any case
VERBOSE: [New-TierModelGpo] Creating GPO 'Tier 0 - Restricted Logon'
<error text, no platform record>
```

#### Recommendation (Cyclops's, presented as a recommendation and **not** as settled)

Scope WI-18 to **AD write call sites only** (`New-AD*`, `Set-AD*`, `Remove-AD*`, `Add-`/`Remove-ADGroupMember`)
and expect **nothing** from `GroupPolicy`. Read call sites gain nothing measurable and would only add noise.

#### Evidence gaps a future implementer must close before building this

1. **No `New-AD*` cmdlet was ever measured.** Every AD arm in every round used `Set-` or
   `Remove-ADOrganizationalUnit`. `New-AD*` is the largest write population in the product and its
   ShouldProcess target-string shape is **assumed**, not measured. Measure one before touching 17 files.
2. **The GroupPolicy zero comes from round 1 (G1/G2), not round 4**, and was never re-measured after round 4
   rehabilitated round 1's instrument. The *structural* facts behind it — `GroupPolicy` is
   `ModuleType = Script`, `New-GPO` is a proxy `Function`, a `WinPSCompatSession` is present — are
   independently checkable and are not in doubt. The numeric `0` is reported, not re-proven.
3. **No raw measurement log is retained in the repository.** `.research/lab-validation/results/` is empty;
   the numbers above come from Cyclops's run report and `LAB-RUN-PROGRESS.md`. Re-running round 4 costs
   minutes and should be done before the work is scheduled.
4. **Round 4's own `$ladderOk` self-check declares the round VOID when `L3 = 0`**, which is what was measured.
   The conclusions above survive that only because AD1/AD3 are an independent positive control the script's
   boolean does not account for — the capture demonstrably *can* see a ShouldProcess record. The verdict is
   sound; the script's codified self-check is not. Fix the check before re-running it.

6. **The "our own instrumentation works" claim is not sourced from round 4.** L1/L2 are bare-preference
   probes in a standalone script; they never import TierModel and never run Deploy or Audit. The product-level
   evidence is the 50-row lab matrix (RUN 1, 0 FAIL) plus round 1's module-scope arm A3. Cite those, not L1/L2.



`-Debug` MUST NEVER be forwarded as an explicit parameter to an AD or GroupPolicy cmdlet, and
`@PSBoundParameters` MUST NEVER be splatted into one. See the hard prohibition at the top of this spec and
FR-017. WI-18 is about `-Verbose` only. Explicit `-Verbose` is **not** prohibited; explicit `-Debug` throws
`Object reference not set to an instance of an object` in a non-interactive host — precisely when the operator
has turned diagnostics on because something is already broken.

**Nothing in D11 asserts, or may be read as asserting, a cause for the original customer incident. That
investigation is closed and the cause is UNKNOWN.**

---

### D12 — Release taxonomy: bug fixes are PATCH releases, features are MINOR releases

**Joel's ruling, verbatim:** *"Since these are bugs they will most like be v2.1.1 and v2.1.2 type releases at
the end not a feature release level."*

| Work | Release level | Example |
|------|---------------|---------|
| Bug fixes | **PATCH** — `v2.1.1`, `v2.1.2` | Reliability and accuracy improvements in flight |
| New capability / new parameter surface | **MINOR** — `v2.2.0` | The scope publish guard (spec 007) |
| Breaking change | **MAJOR** — `v3.0.0` | none queued |

This is a durable project convention, not a one-off. It applies to every queued item, and it is recorded in a
spec file rather than in agent memory for the reason given at the top of this section.

**Recommended target for WI-18: `v2.2.0`, alongside spec 007.** WI-18 adds a new diagnostic capability to
existing call sites and fixes no defect, changes no incorrect behaviour. Under D12 that makes it feature
work, so it belongs in a MINOR release and must not be smuggled into a `v2.1.x` patch.
Pairing it with the scope publish guard also means the two remaining deferred items share one release train
rather than fragmenting the roadmap. This is a recommendation for Joel; the number is not locked.

**No effect on spec 007.** The scope publish guard's deferral rests on its own four preconditions
(`specs/007-scope-publish-guard/plan.md`), none of which involve WI-18. `plan.md` there remains a deliberate
stub with OQ-002 and OQ-003 open for Joel; nothing in D11 or D12 unblocks it or changes what it must answer.

---

### D13 — No bug numbers and no bug history in code comments. **Applies to all of Joel's repositories.**

**Joel's ruling, verbatim:** *"I dont like you putting all these comments about [BUG-nnn] numbers inline
comments in our code once its been fixed we should remove it... Github and git and committing keeps track of
these changes along with branch and pull request. I dont want all these huge comment blocks in the code the
only comment should be what this code is doing not that it is or was a bug."*

**Scope.** Joel was asked explicitly whether this was repo-scoped or global and chose **all his
repositories**. It is therefore a standing authoring convention, not a one-off cleanup of this branch.

**The rule.** A comment may describe **what the code does** and **what live constraint it must respect**. It
may not describe what the code *was*, what broke, when it broke, or which ticket recorded it. Git, the branch
and the pull request already hold that history, and they hold it better than a comment can.

**The approved nuance — "keep the rule, drop the history."** Some comments carry a genuine, non-obvious
constraint that a future editor would otherwise violate. Those survive as a **short, present-tense statement
of the constraint** with **no `BUG-nnn` and no narrative**. Everything purely historical is deleted outright,
not reworded.

| Before | After |
|---|---|
| `# Constraint issue: this used to raise a false alarm when the set was empty because the count was computed before the filter ran.` | `# Count after filtering; an empty set is not a finding.` |
| `# Legacy condition: Write-TierModelFailFast previously exited without logging, so failed runs left no record.` | *(deleted — the code now logs, which is self-evident)* |

**What this rule does NOT reach:**

- **`tests/` — exempt. See D14.**
- Specs, `.research/`, `CHANGELOG.md`, `.squad/` records, PR bodies and commit messages. These are history
  by purpose; the ruling is about *code*.

**Execution status at the time of writing:** Rogue is applying D13 to product code on this branch —
**155 mentions across 36 files**. That sweep is Rogue's; no other agent edits product code for it. Tracked as
task **T024** in `tasks.md`.

---

### D14 — `tests/` is EXEMPT from D13. Bug numbers stay in test files.

**Joel's ruling.** Bug-number references under `tests\` remain.

**Rationale, and it is a real one:** in a test file the bug number is frequently the *only* record of why a
specific assertion exists. An assertion that looks arbitrary — a particular label, a particular count, a
particular ordering — is protected from "tidying" by the reference that explains it. Strip the number and the
next person deletes the assertion as noise, and the defect returns.

This exemption is **narrow**: it covers files under `tests/`. It does not license bug-history prose in
product code that merely happens to be test-adjacent, and it does not license the "huge comment blocks" Joel
objected to. A test comment should still be one line where one line will do.

---

### D15 — Bug detail belongs in the pull request, NOT in `CHANGELOG.md`. The 22-bug migration is CANCELLED.

**Joel's ruling, verbatim:** *"We dont need to detail docoument the bugs like we did its stuff that can go in
the PR later."*

Asked specifically how the 22 pending reliability improvements for v2.1.0 should be recorded, he
chose **"PR only — do not migrate them into `CHANGELOG.md` at all."**

**Consequences, stated plainly:**

| Item | Disposition |
|---|---|
| Migrating the 22 pending reliability improvements into `CHANGELOG.md` | **CANCELLED.** Not deferred, not reduced — it is not happening. |
| A `[2.1.0]` section in `CHANGELOG.md` | **STILL REQUIRED**, but it describes the **feature** (`-EnableVerbose` / `-EnableDebug`) only. It is now a short section. |
| Pre-existing bug-history entries in `CHANGELOG.md` from earlier releases | **UNTOUCHED.** They are shipped history; removing them would rewrite a published record. D15 governs what goes in from here, not what has already gone out. |
| The bug register `.research/known-bugs.md` | **UNTOUCHED and still authoritative.** D15 moves bug detail out of the *changelog*, not out of the project. |
| Per-bug detail for v2.1.0 | Goes in the **pull request body**. |

**Who writes the `[2.1.0]` feature section:** it remains **Joel's or the Scribe's**, exactly as `tasks.md`
T021 already stated — but it is now a materially smaller job than the migration it replaces. See the
re-scoped T021.

---

### Cross-reference — the GPO / WinLapsDecryptor drift-arithmetic residual (Joel's 2026-09-05 ruling)

Joel ruled that the drift-count arithmetic residual affecting the GPO and WinLapsDecryptor entity types is
**documented, not fixed**. It carries no BUG number by decision.

**It is recorded in full by Beast in `.research/known-bugs.md`, under *"By design — do not re-file"*, as
*"GPO / WinLapsDecryptor drift arithmetic does not sum"*. That entry is the authority; it is deliberately not
duplicated here.** It is cross-referenced from this spec only because a reader of 006 arriving at the
audit reporting changes will otherwise re-discover the drift-count arithmetic residual and try to "correct" it.
Do not.

---

### D16 — Audit Reporting Improvements — v2.1.0

**Joel's ruling, 2026-09-07:** *"the Audit should be fixed because its returning colors and this in theory is related to logging and accuraccy of the audit."*

The audit report path received **four accuracy improvements** in v2.1.0, shipped as behaviour changes in the `-EnableVerbose` / `-EnableDebug` branch. These are observable changes to report output; they fix no code defect but they improve the semantic accuracy of audit findings.

#### 1. Missing-family findings render red, not yellow

**Before:** Several finding types (`MissingAcl`, `MissingAuditRule` and others) fell through an exact-literal match in the old label map and rendered **yellow** — meaning "drift" — when they should have rendered **red** — meaning "missing" (absent, not merely different).

**After:** Missing-family findings now render **red** consistently across all entity types, correctly distinguishing absence (red) from drift (yellow).

#### 2. `[AuditRight]` rows relabelled `[MissingAuditRule]` — for Pass and Fail rows only

**Before:** All `[AuditRight]` labels were uniform across the report.

**After:** `[AuditRight]` rows are relabelled **`[MissingAuditRule]`** **only when reporting Pass or Fail audit-rule findings**. Rows reporting any third state — for example, "rule exists but with wrong properties" — still render `[AuditRight]`. This distinction reflects the actual audit result: a pass or fail on audit rules means the rule is present or absent, not just misconfigured. **State the accuracy of the actual audit result, not a generic label.**

#### 3. WinLaps decryptor: `[Error]` became `[Missing]` on one specific error path only

**Before:** All decryptor errors rendered `[Error]`.

**After:** On the specific path where `Get-GPO` succeeded but matched **no GPO** (the GPO does not exist in the domain), the finding now renders **`[Missing]` only**. **Five other error paths remain `[Error]`**, because they mean "could not determine whether it exists" — a domain controller is unreachable, the query threw an exception, or similar. Relabelling those as `[Missing]` would report an unreachable infrastructure problem as a clean, missing-and-acceptable estate — a lie. **The distinction is essential: [Missing] means "we looked and it is not there"; [Error] means "we could not look".**

#### 4. Drift counters derived from shared functions — per-section and grand total aligned

**Before:** Drift counter logic was duplicated across reporting loops, creating opportunities for disagreement between the per-section counters and the grand total.

**After:** Per-section drift counters and the grand total are now computed by calling **shared functions** from both reporting loops. They cannot disagree because they share the same implementation. **Drift counts objects, not findings** — a single object may appear in multiple findings, but is counted once. The compliance percentage depends on this distinction.

---



A bug family discovered while building this feature is being squashed on this branch. The authoritative
register is `.research/known-bugs.md` — refer to it for status and per-bug detail rather than to any count
quoted elsewhere.

Joel's release rule, verbatim:

> "I basically do not want to release unless we squash all known bugs that we find. We are not in a rush or
> timeline for this release if it takes 1 hour, 1 day, or 1 week we are good to go!"

---

## Out of Scope

- Any statement of cause for the original customer incident. **Closed and unknown.**
- Console-output cleanliness or a unified output sink. Withdrawn; noise is accepted.
- Retention or rotation for Deploy/Audit diagnostics (FR-005).
- `optional/Update-TierModelMembership.ps1` — different lifecycle, left alone.
- The scope publish guard — relocated to `specs/007-scope-publish-guard/` and deferred to v2.2.0.
- **WI-18 / D9 — forwarding explicit `-Verbose` to AD/GPO call sites. Measured and deferred; see D11.**
  It is not part of v2.1.0 and nothing in v2.1.0 depends on it. Recommended target `v2.2.0` under D12.

---

## Docs to Update *(pending Joel's approval — `docs/` publishes to GitHub Pages)*

- `docs/tiermodel-logging.md` — the two switches, the composed escalation command, the `Debug\` folder, the
  absence of retention and why it differs from the membership script, the accepted console noise, and —
  prominently — that transcripts are unredacted and must be reviewed before being sent to anyone.
- `docs/quick-deployment-guide.md` — the escalation command.
- `README.md` / `docs/test-coverage.md` — test count refresh once the new tests land.
- `CHANGELOG.md` — a `[2.1.0]` entry describing the **feature only** (`-EnableVerbose` / `-EnableDebug`).
  **The 22-bug migration is cancelled — see D15.** Bug detail goes in the pull request. Still
  **owned by Joel/Scribe, not by this feature's implementer.**

**Must not say**: anything asserting a cause for the customer incident, and anything promising the switches
will reveal why a GPO failed (see M-3 and M-5).
