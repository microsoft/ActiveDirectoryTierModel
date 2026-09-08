# professor-x — History

## FEATURE COMPLETE: Windows LAPS T001–T021 (2026-07-16)

**Status:** ✅ SHIPPED — All tasks complete, committed, ready for Joel's UAT + release.

The Windows LAPS feature (T001–T021) is now complete and committed to feature/windows-laps branch:
- Beast (T001–T013): Implementation + audit cmdlet ✅
- Wolverine (T014–T020): Test suite (113 tests, 90.92% coverage, 1401/1401 green) ✅
- Storm (T021): Documentation (8 files, README metrics) ✅

Spec review (Professor-X T008): APPROVED — feature spec meets all Constitution requirements and security invariants.

Orchestration logs: 2026-07-16T09-34-10Z-wolverine.md and 2026-07-16T09-34-10Z-storm.md  
Session log: 2026-07-16T09-34-10Z-winlaps-feature-complete.md

Next gate: Joel's manual UAT, then PR merge, v1.2.0 release.

---

## 2026-08-24: Spec 005 Updated — All-Tier Four-Silo Model

**Update**: Applied Joel's approved all-tier model to `specs/005-auth-silos/`.

### Changes Made

**spec.md**: Header updated with revision date. Overview updated to all four tiers. Four new sections added:
- **The Four-Silo Model** — scope table with Tier 0 Admin / Tier 1 Admin / Tier 2 Admin / Tier 2 EUD silos, approved-origin-device column, no-fifth-silo constraint, privileged-accounts-only scope
- **Silo Enforcement Boundary** — explicit distinction: silos gate TGT source-device (AS exchange) only; URA logon rights (existing GPOs) and TGS service-ticket control are independent planes; do not conflate
- **Domain-Join Service Account Exemptions** — svc-pawdomainjoin + svc-t1srvdomainjoin (existing) + svc-t2euddomainjoin (new/required); structural exemptions with compensating controls
- **Required New Config Addition — Tier 2 EUD Provisioning** — svc-t2euddomainjoin + Tier2EUDDomainJoin group + Tier 2 EUD Staging OU + delegated create-computer rights + Account Restriction GPO

User Story 1 updated to all four silos, domain-join exemption clarification added (scenario 7). New section **Test Acceptance Matrix (UAT-01–UAT-15)** added. Edge Cases expanded (+2: domain-join exemption, Tier 2 EUD prereq). Constraints extended to CON-009 (no fifth silo; privileged-only) and CON-010 (domain-join structural exemptions). Out of Scope: "Tier 2 silo deployment" removed; "General Domain Users/Computers siloing" added as out of scope by design. Open Questions: OQ-005 marked RESOLVED; OQ-003 partially resolved; OQ-011/OQ-012 added.

**plan.md**: AD Object Model shows all four silos + structural exemptions table. New Files section expanded with Tier 2 EUD config additions table. Risk Register extended to R10.

**tasks.md**: T009 added for Tier 2 EUD base-config additions. Lab validation tasks expanded: T021 (negative/cross-tier), T022 (new-device onboarding), T023 (domain-join exempt accounts), T024 (gate check + RID-500 recovery), T025 (G1–G12 full gate checklist). Review/release tasks renumbered T026–T028.

**checklists/requirements.md**: All sections updated to reflect four-silo model; OQ-005 checked as RESOLVED; CON-009/010 added to Security & Safety; UAT matrix referenced in Tasks.md Completeness.

### Decisions Made in This Update

1. **Four-silo model is final**: Tier 0 Admin / Tier 1 Admin / Tier 2 Admin / Tier 2 EUD. No fifth silo. (CON-009)
2. **Privileged-accounts-only**: General Domain Users/Computers intentionally not siloed. (CON-009)
3. **Silo enforcement boundary clarified**: TGT source-device (AS exchange) only; URA and TGS are separate, independent control planes.
4. **Domain-join exemptions are structural**: svc-pawdomainjoin, svc-t1srvdomainjoin, svc-t2euddomainjoin are permanently exempt (not time-bounded). (CON-010)
5. **Tier 2 EUD provisioning is a required config addition**: svc-t2euddomainjoin + Tier2EUDDomainJoin + Tier 2 EUD Staging OU must be added to base Tier Model config before Tier 2 EUD silo can deploy.

---

## 2026-08-24: Spec 005 Authored — Authentication Policy Silos (`-IncludeAuthSilos`)

**Deliverables**: `specs/005-auth-silos/spec.md`, `plan.md`, `tasks.md`, `checklists/requirements.md`
**Status**: Draft (scoping) — ops-guide walkthrough with Joel is next step (T001)

### Scoping Decisions Made

1. **Full silo model required (CON-001)**: Real `msDS-AuthNPolicySilo` objects + per-class `msDS-AuthNPolicies` policies. Direct policy assignment without silo objects is not the target model. Customer scripts are frozen evidence only.
2. **OR logic required in AllowedToAuthenticateFrom SDDL (CON-002)**: `&&` (AND) between device groups is prohibited. The customer scripts' AND logic is the documented lockout failure mode.
3. **Audit-first as three-stage lifecycle (CON-003/004)**: All objects created with `Enforce = false`. Enforcement flip is a separate, manually-invoked operation — never triggered by `-IncludeAuthSilos`.
4. **RID-500 structural exclusion (CON-005)**: Non-configurable; by SID suffix match (`-500$`), not by `sAMAccountName`.
5. **FAST/DAC GPO validation only (CON-008)**: Pre-existing in Tier Model. Code validates; does not create or modify GPOs.
6. **Switch naming**: `-IncludeAuthSilos` — consistent with `-IncludeWinLaps`, `-IncludeGmsa` optional-feature pattern.
7. **Tier scope**: Tier 0 + Tier 1 in scope; Tier 2 is explicit out-of-scope for initial implementation.

### Deferred / Open

OQ-001 through OQ-010 (converge recipe, enforcement flip UX, exemption model, gMSA scope, Tier 2, gate verification, config shape, SDDL generation, lab validation requirements, wave structure) — all deferred to ops-guide walkthrough session (T001).

### Learnings

- The audit→enforce lifecycle is first-class, not a flag. Spec 005 establishes it as three distinct stages with twelve pre-enforcement gates. Future specs that involve Tier boundary controls should reference this structure.
- The customer script review (A4: 4 Critical, 19 Major) is a direct design input. The two most important defects to prohibit in code are: (1) no silo objects created, (2) AND logic in SDDL between device groups. Both are now structural constraints in CON-001 and CON-002.
- Pre-enforcement gates (G1–G12) are a reusable checklist pattern for any AD control that deploys in audit-then-enforce lifecycle. Consider referencing this pattern in future control-plane features.

---

## 2026-07-13: Spec Review — 003-win-laps

**Verdict:** APPROVED (with 2 minor non-blocking items)

Reviewed `specs/003-win-laps/` (spec.md, plan.md, tasks.md, checklists/requirements.md) against:
- Constitution v1.3.0 (all 9 principles)
- 002-gmsa-support baseline (structure parity)
- Source findings (Beast, Cyclops, Wolverine inbox documents)
- Joel's 10 explicit requirements

## Learnings

- 003 correctly implements Constitution II (test-first) unlike 002 which deviated. This is the RIGHT approach going forward — test-first is non-negotiable per constitution.
- Self-contained design pattern (baseline works without modifying existing cmdlets, with OQ-flagged optional integration) is a strong architecture choice for new features. Reduces blast radius and gives Joel explicit control over scope creep.
- The 002→003 size ratio (~60%) is proportional to cmdlet count (3 vs 12) — do NOT flag feature specs as "too thin" when scope is genuinely narrower.
- Documentation tasks (README/docs updates) should be explicitly tasked in every spec's tasks.md. 002 had T037; 003 missed this. Flag in future reviews.
- "Files to Modify (Existing)" summary table is valuable for Joel's review — recommend it as standard structure for all plan.md files.
- ADR-0001 (Windows LAPS only invariant) with 3-layer enforcement is a strong security architecture pattern worth replicating for future exclusion invariants.

## 2026-07-13: Wave-2 Orchestration Complete

**Orchestration session log created**: `.squad/orchestration-log/2026-07-13T11-34-25-UTC-professor-x.md`

Review final verdict: APPROVED. All agent findings consolidated into decisions.md. Spec-Kit ready for implementation wave handoff. 6 open decisions routed to Joel; 2 already resolved (OQ-WL-05, OQ-WL-06). Team transition from Wave-2 specification to implementation waves now underway.

Recommendation: This level of structured wave coordination (research → architecture → specification → approval → implementation) should be documented as a process pattern for future multi-agent features. Cyclops + Professor X review cycle is effective.


## Learnings

## 2026-09-03: Verbose vs Debug — Joel's challenge, and what the lab actually showed

Joel asked whether we had confused Verbose and Debug and whether we should ship both.
He was right that we missed the distinction. The lab work that followed found something
bigger than the naming question, and it changed the shape of the feature.

**The three findings that matter:**

1. **GroupPolicy cmdlets emit ZERO verbose and ZERO debug records under PS7** — in all
   four preference modes AND with explicit `-Verbose`/`-Debug`. They load as proxy
   *functions* through the WinPSCompatSession shim (`ModuleType=Script`,
   `CommandType=Function`), and neither stream survives that boundary. The customer's
   failure was in the GPO path. A debug switch would have printed nothing new there.
2. **The information was always available on the error stream.** The GPO cmdlets produce
   excellent, specific errors ("The command cannot be completed because a X GPO already
   exists", "There is no GPO named X ... linked to ..."). Our code discards them in
   **66 empty `catch {}` blocks** (AST-verified across `modules/TierModel/public`).
   That is the customer's bug — a catch-block bug, not a logging bug.
3. **`Write-TierModelLog` without `-LogPath` writes to no file at all.**
   `$script:LoggingEnabled` is initialised `$false` in TierModel.psm1 and is never
   assigned `$true` anywhere in the repo. The 26 "dormant" module Debug sites would
   have emitted console-only. The previously-assumed Phase 1 design did not produce a
   log file.

**Corrections to facts the team had marked as verified** (recording these because
over-claiming has already cost us credibility with Joel once):

- "PS7 `-Debug` sets Continue, no prompt hazard" — **wrong for AD cmdlets in a
  non-interactive host.** Explicit `-Debug` on `New-ADOrganizationalUnit` / `New-ADGroup`
  throws `Object reference not set to an instance of an object`. Every time. Note the
  nuance: `$global:DebugPreference='Continue'` is safe; the explicit parameter is not.
  This kills "Mode C" as a production option.
- "Mode B == Mode C, 46 records, 0 differences" — **true only for our own module
  functions.** `$global:VerbosePreference` does NOT reach AD binary cmdlets (0 records),
  though it does reach our advanced functions (1 record). Capturing AD narration requires
  forwarding `-Verbose` to all 31 AD/GPO call sites. Real work, not a free switch.
- "`4>&1` does not capture the debug stream" was written up as a PS 7.6.5 quirk. It is
  not a quirk — stream 4 is verbose, stream 5 is debug. Somebody nearly designed around
  a phantom bug.

**Solved the hard part — "everything in the file, console clean":**
A unified sink. `*>&1` into a `ForEach-Object` that writes every record to the file and
selectively re-emits to console. Verified working: console showed only Write-Host UX +
one clean error line; file contained host lines, script verbose/debug, module Info/Debug,
the AD cmdlet's own target-DN narration, the error message, and the error category /
FullyQualifiedErrorId / target object — all interleaved in true chronological order.

Dead ends worth remembering: `*>>` blanks the console (Write-Host is stream 6 and gets
captured); `4>>f 5>>f` fails with a file-lock error because two redirection operators
open two exclusive handles on one file; `5>&4` is a parser error because PowerShell only
merges into stream 1.

**Recommendation made:** one switch, not two. Joel's need is "shit's not working, give me
everything" — forcing an operator to choose a PowerShell stream during an incident just
creates a way to pick wrong and then triage a half-capture. Kept `-EnableDebug` as the
name (discoverability beats accuracy; it is the word the customer used) and flagged the
mild inaccuracy openly rather than quietly.

**Upheld the Start-Transcript rejection, with better reasons than before.** A transcript
only captures what reaches the host, so it needs preferences set to Continue, which
floods the console — precisely what Joel does not want. Transcript and clean console are
mutually exclusive. It also loses error category and FQID.

**Process learning — the one I want to carry forward:** the team spent a full review cycle
designing a switch without ever asking whether the code paths it would illuminate were
instrumented at all. They were not: the GPO write path has zero Debug sites and 66 catch
blocks that destroy the exception before any logger sees it. I sequenced the plan so the
catch-block fix lands in Phase 2, *before* the switch in Phase 3 — if Joel stops after
Phase 2 the customer's bug is fixed and we have shipped real value; had we built the
switch first and stopped, we would have shipped nothing. **Ask "is there anything to log?"
before designing the thing that turns logging on.**

Lab hygiene: 5 OUs, 5 groups, 5 GPOs created under OU=POC-VD and all removed (verified 0
remaining). VM left running, no checkpoint created, restored or deleted. Confirmed the DC
is 192.168.100.10 — the 192.168.1.2 in decisions/0001-remote-management-architecture.md is
stale and should be corrected.

## 2026-09-03 (later): Requirements changed — and the lab found the actual bug

Joel withdrew the console-cleanliness requirement ("debugging isnt meant to be clean"),
corrected me that Start-Transcript was never rejected, and signalled two composing
switches. He then asked the question that mattered most: are we missing something with
the GPO path — would -EnableVerbose/-EnableDebug actually show the full error?

**The answer was no, and finding out why produced the most valuable result of the session.**

**The bug:** GroupPolicy cmdlet failures are NON-TERMINATING. `New-TierModelGpo.ps1`
L72/L74 calls `New-GPO` with no `-ErrorAction Stop`. So the catch block never fires,
`$newGPO` is `$null`, and execution falls straight through to
`Write-Host "✅ Created GPO: $gpoName"` and `$executed++`. **We print a green tick for a
GPO that does not exist**, and report `Failed = 0`, `Converged = $true`. Proven in the
lab with a disk-based module replicating the exact production shape. The branch was
already named `fix/gpo-silent-skip-and-false-success` — the name was more accurate than
anyone realised.

**The compounding defect:** `Deploy-TierModel.ps1` L206 sets
`$ErrorActionPreference = 'Stop'`, and it does NOT propagate into module functions.
Module-scope measured `Continue` in every case. Same module-boundary behaviour we'd
already proven for `$DebugPreference` and `$VerbosePreference` — but nobody had thought
to check whether it applied to the *error* preference, where it matters most. Lesson:
when you establish that one preference variable doesn't cross a boundary, immediately
check the others.

**The audit:** 40 catch blocks in the GPO write path. 9 empty, 8 that never read the
exception, 23 message-only, and **zero** that preserve FullyQualifiedErrorId,
CategoryInfo, InnerException or ScriptStackTrace. Module-wide, 66 empty catches across
24 files. Plus `Deploy-TierModel.ps1` L1284 tells the operator "GPO planning failed -
check logs for details" when module-level logging never writes to a file at all.

**A trap for whoever implements the fix:** the WinPSCompat shim flattens exceptions to
`RemoteException` with `InnerException` always `<none>`. A remediation that dutifully
logs `InnerException` would capture nothing. The useful fields are
`FullyQualifiedErrorId` (`GpoWithNameAlreadyExists,…NewGpoCommand`) and `CategoryInfo`.
Worth stating explicitly in the handoff or it will be got wrong.

**On changing my mind:** I recommended one switch in v1 and Joel indicated two. I
withdrew my recommendation rather than defending it — because the facts changed. Once
console-cleanliness was dropped and transcript was on the table, the two switches map
to genuinely different mechanisms (verbose = preference + `-Verbose` forwarding to 31 AD
call sites; debug = preference + our instrumentation), and Joel's both-on case is the
documented escalation path. My original objection ("don't make an operator choose under
pressure") I preserved as a concrete refinement instead: print a copy-pasteable
both-switches-on command in the failure message. Keep the useful part of a rejected
argument rather than discarding it wholesale.

**On Joel's transcript proposal:** verified it works — captured host, verbose, debug,
warnings, output, module-boundary records, AD target-DN narration and the non-terminating
GPO error, in both non-interactive and remoting hosts. Endorsed it, and reported four
flaws rather than quietly engineering around them: ~60 lines of module-import verbose
noise burying the signal (fix: import first, set preferences after), transcript
double-writing errors, **transcript bypassing our secret redaction** (a real concern for
a Tier 0 tool whose diagnostic files customers will email us), and artefact overlap with
`-Logging`.

**The process learning, sharper than this morning's:** I sequenced the plan so
`-ErrorAction Stop` (2–3 h) and catch enrichment (6–8 h) land in Phases 1–2, with the
switches at Phase 4. W1+W2+W3 is ~9–13 hours and fixes the reported incident; everything
else is enhancement. We spent an entire prior review cycle designing a switch to
illuminate code paths that destroy their evidence before any stream can carry it. **Ask
"is there anything left to log?" before designing the thing that turns logging on** — and
when a customer reports a silent failure, suspect the error handling before the logging.

**Honest limit:** I proved the mechanism but cannot attribute the customer's exact
message. The ranking in the design is reasoned likelihood, not attribution. Their console
scrollback or log file would settle it in minutes and I recommended asking for it rather
than guessing.

Lab: 4 POC rounds, all objects removed (POC OUs = 0, POC GPOs = 0), VM left running, no
checkpoint touched.

---

## 2026-09-03 — Logging revival (W3), and three of my own claims refuted

### ⛔ Corrections to my own prior analysis — carry these forward, do NOT re-assert the originals

My `.research\verbose-vs-debug-design.md` was adversarially reviewed. Three
load-bearing claims were refuted by direct measurement and independently
re-verified. I confirmed all three against the production tree myself:

1. **"`$ErrorActionPreference` does not cross the module boundary" — FALSE.**
   `modules\TierModel\TierModel.psm1` **L2** is `$ErrorActionPreference = 'Stop'`.
   Module scope **is** `Stop`. My lab replica module omitted the `.psm1` header, so
   I measured my own scaffold and reported it as production behaviour.
2. **"`Set-StrictMode` / malformed-DN downstream" — FALSE.** `TierModel.psm1`
   **L1** is `Set-StrictMode -Version Latest`. `$null.Id` therefore **throws**, is
   caught, and surfaces as a warning. No malformed DN is ever sent to AD.
3. **My redaction argument was oversold.** `Write-TierModelLog` L63-70 replaces
   only **exact top-level keys** `Password/Secret/Token/Key/Credential`. Nested
   hashtables, `AdminPassword`-style names, and the free-text `Message` field are
   never touched. My recommendation (warn about transcripts, isolate them) still
   stands, but the "redacted JSON vs. raw transcript" contrast I used to justify it
   is false — today's JSON log is **already** not a trustworthy redacted artefact.

**The genuinely correct mechanism for the false-success bug:** under PowerShell 7
with the WinPSCompat shim, AD/GroupPolicy load as **script proxy functions** using
`$PSCmdlet.WriteError()`, which does not honour the caller's `Stop` preference.
Same trigger as BUG-013. It does not occur under Windows PowerShell 5.1.

**Lesson, and it is the expensive one:** *a replica is only evidence if it
replicates the thing that matters.* I built a disk-based module to get away from
in-memory artefacts — correct instinct — but I never diffed my scaffold's header
against `TierModel.psm1`. The first two lines of the real file were exactly the
two lines that decided the answer. **Before trusting a lab result about scope or
preference, diff the harness against the production file it stands in for**, and
prefer measuring the real module wherever it can be loaded at all.

Second lesson: **quantify with a number you produced.** My 9-13 h estimate was
counted sites times an assumed uniform cost. The reviewer put it at 20-30 h and I
agree; I corrected the document rather than defending it. Drivers I had ignored:
40 catch blocks each needing individual domain judgement, the 80% coverage gate
applying to every new branch, and `ADStubs.ps1` never throwing — so every new
failure path needs new mocking built before it can be tested.

### Finding B fixed — module file logging was completely dead

Re-measured the blast radius myself rather than taking the reviewer's numbers:
**454** production `Write-TierModelLog` call-lines (reviewer said 455 — the
variance is the 24th Deploy site, which sits inside the `-Logging` guard and
passes no `-LogPath`; not a disagreement). **430** are inside `modules\` and
**none** of them passes `-LogPath`. Exactly **23** pass it, all in
`Deploy-TierModel.ps1`. So **431 (95%)** could never reach disk, including all
**107** module-level `-Level Error` lines. `Audit-TierModel.ps1` had **0** call
sites and produced no log records at all.

Two independent breaks, which matters: `$script:LoggingEnabled = $false` (psm1
L11) *and* `$script:DefaultLogPath = $null` (L12). Flipping the flag alone would
have fixed nothing — `if ($logFile)` would still have skipped the write. **When a
feature is gated on more than one variable, check every one before declaring the
fix; the first one you find is not necessarily the only one broken.**

**Chose Option 1 (module-scope initialisation) over Option 2 (thread `-LogPath`
through ~70 functions).** One internal helper plus two call-outs fixes 431 sites;
Option 2 would have meant ~431 edits in a Tier 0 tool on a branch three other
agents were editing live, and would have pushed a diagnostics concern into the
signature of ~70 domain functions — the same class of defect as the bug itself.
The reviewer's warning about drifting into doing *both* was the real risk, so I
added **zero** new `-LogPath` arguments and left Beast's 23 exactly as written.
`$LogPath` still wins inside `Write-TierModelLog`, both resolve to the same file,
no duplication.

Constraint that shaped the design: `tests\Unit.ModuleManifest.Tests.ps1` asserts
an exact exported-function count, so no new public function was possible. The
helper lives in `internal\` (that test globs `public\` only, L191-193) and entry
scripts reach it via `& $module { ... }` — the same idiom
`tests\Unit.Logging.Tests.ps1` L271-272 already uses. **Look for an existing
in-repo idiom before inventing one; there usually is one.**

### Verification, including a failure of my own method

Unit suite **1,573 / 0**. But getting there was instructive: intermediate runs
gave 1571/2 and then 1531/42, and my first instinct was to suspect my own change.
An A/B with the helper renamed away reproduced the failures **with my file absent
too**, and `LastWriteTime` showed Beast and Cyclops had saved 11 module files
between 18:00 and 18:07. **On a shared branch, a red suite is not evidence until
you have A/B'd it and checked mtimes** — and a single-process Pester A/B is
worthless because mocks and the imported module leak between runs. Every
comparison has to be a fresh `pwsh -NoProfile` process. Final clean A/B: 1573/0
with the helper, 1573/0 without.

**A passing unit suite was never going to be proof here** — the bug was precisely
that a code path never executed. So I ran both entry scripts for real against an
unreachable DC with `-Logging`, and confirmed the log files contained module-level
records emitted with no `-LogPath` argument anywhere (`Starting prerequisites
validation`, `Checking required modules`, ...). Those lines were unreachable
before this change. Also confirmed the inverse: both scripts run without
`-Logging` from a clean temp directory produced **0 files**, so opt-in survives.
**Prove the new path runs, and prove the old default still doesn't.**

### Course correction (same day): `internal\` is banned — the helper moved into the psm1

I placed `Initialize-TierModelLogging.ps1` under `modules\TierModel\internal\`
because I was told that folder was acceptable. It is **not**: the repo owner has a
standing rule that `internal\` must not be used, and has had to repeat it. The
folder is now **deleted**, and I removed the dot-source loop in `TierModel.psm1`
that scanned it, replacing it with a comment recording the rule so it cannot
silently reappear.

**Where it went, and how I chose:** `public\` looked like the obvious home but is
wrong here, and I checked rather than assumed.
`tests\Unit.ModuleManifest.Tests.ps1` L188-216 builds the expected function list
from `Get-ChildItem public\ -Filter '*.ps1'` **plus exactly three hard-coded
inline names** (`Get-TierModel`, `Get-TierModelPlan`, `Test-TierModelConfig`) and
asserts it equals `FunctionsToExport` exactly. So any new file in `public\` forces
a `FunctionsToExport` entry, which raises the exported count, which requires
editing Wolverine's test. Dead end — correctly.

Defining the function **inline in `TierModel.psm1`** satisfies everything at once:
the manifest test's inline scan is three literal regexes so a fourth function is
invisible to it; `FunctionsToExport` is an explicit list, not a wildcard, so the
function is defined but never exported; and it sits directly beside the
`$script:LoggingEnabled` / `$script:DefaultLogPath` declarations it exists to set,
which is where a reader would look for it. Verified: exported count **83 = 83**
(80 public files + 3 inline), `Get-Command` finds nothing outside the module,
`& $module { Get-Command ... }` resolves, `Test-Path ...\internal` is False.

**Lesson:** the best fix here was *no new file at all*. I reached for a new file
because the brief offered one, not because the problem needed one — the logic
belonged next to the variables it initialises the whole time. **When a brief
suggests a structure, treat it as a suggestion and re-derive it from the
codebase's own constraints.** The constraint that decided it (a test deriving its
expectation from folder contents) was readable in five minutes and would have
pointed at the psm1 immediately.

**Second lesson:** an instruction repeated by an owner is a convention that
tooling should enforce. Deleting the folder without also deleting the loader that
scans for it would have left the rule depending on everyone's memory. I removed
both.

### Additional evidence from Joel's lab that raises Finding B's severity

Verified on the live DC 2026-09-03: `Deploy-TierModel.ps1` L387-395 hard-stops
below PowerShell 7, `Audit-TierModel.ps1` L212 does the same, and the manifest
sets `PowerShellVersion = '7.0'`. Under pwsh 7 there, `GroupPolicy` loads with
`ModuleType = Script`, `New-GPO` is a `Function` (a proxy), and PowerShell emits
the `WinPSCompatSession` deserialisation warning.

**So the WinPSCompat shim is the only path any supported user takes — it is the
default, not an edge case.** That kills the "but it doesn't happen on 5.1" caveat
I had been carrying: 5.1 is not a supported host, so that caveat protects nobody.
It also means the dead logging denied diagnostics to *every* operator on *every*
run, in exactly the configuration where the shim makes errors hardest to read and
easiest to swallow. The two defects compound.

Consequence for the remaining work, now recorded in the design doc: **`-ErrorAction
Stop` alone will not stop a proxy that calls `$PSCmdlet.WriteError()`.** W1 must
pair it with explicit `$null`/result verification. And W3 was a *prerequisite* for
W2, not a peer — the richer catch blocks W2 adds would have had nowhere to write.

**Meta-lesson worth keeping:** I had already been told the shim was the mechanism
and still treated it as one configuration among several. A single `Get-Module`
plus a look at the two version gates settled that it was universal. **When a
mechanism is confirmed, immediately ask how many users are actually exposed to
it** — severity, not just correctness, drives what gets fixed first.

### Follow-up: I tested the `public\` placement instead of arguing about it

Joel followed up with precise mechanics: `FunctionsToExport` is an explicit
83-name array with no wildcard, and the psm1 dot-sources `public\` and `internal\`
with the identical `. $_.FullName`, so a file in `public\` is only *available*,
not *exported*. **That reasoning about PowerShell is completely correct.** Placing
the file there genuinely does not change the runtime exported count.

**But `tests\Unit.ModuleManifest.Tests.ps1` does not assert on the runtime
exported list — it asserts on the contents of the `public\` folder.** L188-216
builds its expectation from `Get-ChildItem public\ -Filter '*.ps1'` BaseNames plus
three hard-coded inline names, then requires that set to equal `FunctionsToExport`
exactly. A file in `public\` that is deliberately absent from `FunctionsToExport`
fails *by construction*.

I did not reply with that reading. I made the change and ran the test:

```
Invoke-Pester tests\Unit.ModuleManifest.Tests.ps1   ->   Passed 60, Failed 3
  Expected 84 ... but got 83.
  These functions exist in public/ or .psm1 but are not in FunctionsToExport:
    Initialize-TierModelLogging
  @{InputObject=Initialize-TierModelLogging; SideIndicator==>}
```

Then reverted the file out of `public\` and put the function back inline in the
psm1, with a comment in its help block recording this measurement so nobody
repeats the experiment. Per the brief I did not invent a dodge (an `.old`-style
filename would slip past the folder scan — that is exactly the kind of workaround
I was told not to build) and I did not touch Wolverine's test.

**Lesson — the important one:** the owner and I were both right about different
things, and the disagreement was only resolvable by running it. He was reasoning
about *PowerShell's* export semantics; I was reasoning about *the test's*
assertion. Both readings were internally sound. **When an instruction and my
reading conflict, the cheapest resolution is usually to perform the instruction
and measure the result** — it took about four minutes, produced three verbatim
failure messages, and replaced a "you're wrong / no you are" exchange with
evidence. Do the experiment before writing the objection.

**Second lesson:** I flagged this as a blocker in my previous report but framed it
as a conclusion from reading the test. Framing it that way invited a
counter-reading. Had I run it the first time and pasted the three failures, the
whole round trip would have been unnecessary. **Assert with output, not with
citations**, especially when contradicting someone who has just verified something
themselves.

**Left as an open item for the owner:** the real defect is that the manifest test
asserts on folder contents rather than on `(Get-Module TierModel).ExportedCommands`.
If the project wants unexported helpers to live in `public\` — a reasonable
convention, and the owner's stated preference — that test needs a one-Context
change in Wolverine's file to compare against the exported surface and to treat
`public\` files absent from `FunctionsToExport` as intentionally private. Recorded
in the decision record; not actioned, because it is not mine to action.

**Also completed this round:** deleted `modules\TierModel\internal\` and removed
the now-dead L18-36 loader block from the psm1 rather than leaving it for someone
else. The psm1's own comments showed a prior migration had already emptied that
folder deliberately; my earlier file repopulated it and undid that cleanup.
Removal was surgical — `Set-StrictMode`, `$ErrorActionPreference = 'Stop'`, the
correlation ID, `$script:ModuleRoot`, `$script:ConfigPath`, the logging variables,
the domain cache variables and the whole `public\` loader all intact, confirmed by
an import with **0 warnings and 0 errors**. **Deleting a folder without deleting
the code that scans for it leaves the rule depending on memory** — remove both, or
the folder comes back.
