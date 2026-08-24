# beast — History

## Learnings: Format-Duration Design Investigation (issue #34) (2026-08-24)

**Branch:** N/A — Design proposal only (no code written)
**Status:** ✅ PROPOSAL DELIVERED — awaiting Joel go/no-go before implementation

### Key facts established

**All 9 Write-Host (console) duration call sites in Deploy-TierModel.ps1:**
- L2165: `$totalDuration` — consolidated full-deployment results summary
- L2176: hardcoded `"Duration: 0ms"` — no-actions-needed branch (must also change)
- L2227: `$ouResult.DurationMs` — OuOnly (ConfirmApply-gated)
- L2278: `$groupResult.DurationMs` — GroupOnly (ConfirmApply-gated)
- L2338: `$userResult.DurationMs` — UserOnly (ConfirmApply-gated)
- L2395: `$ouAclResult.DurationMs` — OuAclsOnly (ConfirmApply-gated)
- L2479: `$gpoResult.DurationMs` — GposOnly (ConfirmApply-gated)
- L2570: `$admxResult.DurationMs` — AdmxOnly (always shown when ConfirmApply)
- L2767: `$standaloneTotalDuration` — standalone MSA/gMSA/dMSA/WinLaps/Audit results

**Two Write-TierModelLog (machine log) duration sites — KEEP RAW:**
- L559 (OU deployment), L701 (Group deployment)

**DurationMs type is mixed:**
- `New-TierModelOu.ps1`: casts to `[int]` → integer
- `Copy-TierModelAdmx.ps1`: raw `TotalMilliseconds` → double (e.g., 2254.1343)
- Function must accept `[double]` to handle both

**CI coverage scope (ci.yml L120):**
- `modules/TierModel/*.psm1` AND `modules/TierModel/public/*.ps1`
- Private/internal NOT counted; `Format-TierModelDuration` MUST be public

**No internal/ .ps1 files exist** — no private function mechanism is active

**Existing integration tests that assert on "Xms" format (Integration.Deploy.Tests.ps1):**
- L1901: `$output | Should -Match 'Duration: 150ms'` — DurationMs=150 (sub-1000ms → stays '150ms') ✓
- L2744: `$output | Should -Match 'Duration: 100ms'` — DurationMs=100 (sub-1000ms → stays '100ms') ✓
- Both assertions remain compatible after the change (sub-1000ms stays as Xms)

### Proposed design (pending Joel approval)
- Function name: `Format-TierModelDuration` (follows `Verb-TierModelNoun` convention)
- 4-tier format: `<1ms` / `Xms` / `Xs` / `Xm Ys`
- `[double]$Milliseconds` parameter — handles both int and double DurationMs values
- Open question for Joel: `<1ms` vs `1ms` ceiling; `Xs` middle tier vs just `Xm Ys` for ≥1s

### Lab acceptance validation added (2026-08-24, Joel request)
Three manual DC01 scenarios mapped to branches/call-sites/expected output:
- Scenario 1: `-OuOnly -ConfirmApply` (all OUs) → seconds branch → L2227 → `Duration: Xs`
- Scenario 2: delete 1 OU, re-run → ms branch → L2227 → `Duration: Xms` (THE never-zero acceptance test)
- Scenario 3: `-FullDeployment -ConfirmApply` → m/s branch → L2165 → `Duration: Xm Ys`
- Optional 2b: fully-converged FullDeployment → `<1ms` floor → L2176 → `Duration: <1ms` (tests hardcoded-zero fix)
Pester covers all branches offline/deterministically; lab proves the end-to-end module call chain on live AD.

### IMPLEMENTATION COMPLETE (2026-08-24) — production code only, no tests
- `modules/TierModel/public/Format-TierModelDuration.ps1` — CREATED (4 tiers, all floor-based, parse clean)
- `modules/TierModel/TierModel.psd1` — `'Format-TierModelDuration'` added to FunctionsToExport after `'Copy-TierModelAdmx'`
- `Deploy-TierModel.ps1` — 9 Write-Host sites updated; L559/L701 log lines left raw
- `CHANGELOG.md` — Unreleased entry added (issue #34)
- 12/12 smoke-test cases passed including the two banker's-rounding regression cases (90000ms→1m 30s, 119999ms→1m 59s)
- ModuleVersion stays 1.3.1 (not bumped per Joel instruction)
- Tests: NOT written — Wolverine phase after lab validation

---

## Learnings: Granular Per-Right Audit Output (2026-08-14)

**Branch:** `feature/domain-auditing`
**Status:** ✅ DELIVERED — per-right output, 3 drift scenarios proven, lab restored COMPLIANT

### What changed in Test-TierModelAuditRule.ps1
- After computing `$presentInt` and `$missingInt`, iterate every `$right` in `$ruleConfig.rights`
- Per-right: compute `$rightBit = [int][ActiveDirectoryRights]$right`; `$rightPresent = ($rightBit -band $presentInt) -ne 0`
- Emit `"        ✅ Right '$right' - present"` or `"        ❌ Right '$right' - missing"` (8-space indent, matching GPO URA style)
- Add a `{Type='AuditRight', Property=$right, Status=Pass/Fail}` finding per right, always (even under -Silent)
- Per-right loop runs BEFORE the rule-level status line (all 9, then the overall COMPLIANT/DRIFT line)
- -Silent: no host output at all (unchanged), but findings still populated
- Drift rollup: TotalChecked=1, Drift=0/1, completely unchanged — only output changed

### Model: Test-TierModelGPOContent.ps1 URA validation
- 8-space indent `❌ URA '$name'` / `✅ URA '$name'` per item → adopted directly
- GPO suppresses green per-item for cleanliness (dozens of URAs) — Joel explicitly wants all 9 rights shown always (small list), so we emit both green and red

### Lab scenarios (2026-08-14)
| Scenario | SACL state | Per-right output | Status |
|---|---|---|---|
| A - ABSENT | 0 managed ACEs | all 9 ❌ red | DRIFT ABSENT |
| B - PARTIAL | 7-of-9 (no WriteDacl/WriteOwner) | 7 ✅, 2 ❌ | DRIFT PARTIAL |
| C - EXTRA out-of-scope | canonical + Everyone/Failure/All | all 9 ✅ | COMPLIANT |
| RESTORE | canonical only (New-TierModelAuditRule) | all 9 ✅ | COMPLIANT |

### Gotchas
- `Invoke-Command -VMName` runs in PS 5.1 by default on the guest; the TierModel module requires PS 7 — always use the `$pwsh` path via `-Command` for any module import
- `New-TierModelAuditRule` requires both `-Plan` (from `Get-TierModelAuditRule`) and `-Config`; cannot call with Config alone
- Here-string `@'...'@` (single-quote) over `-Command` argument loses double-quote expansion for variable interpolation inside embedded strings like `"AD:$dn"` — use `'AD:' + $dn` or backtick-escape `$` in the host-side double-quoted here-string

---

## Learnings: Audit-TierModel.ps1 Standalone Header Fix (2026-08-14)

**Branch:** `feature/domain-auditing`
**Status:** ✅ DELIVERED — label logic restructured, lab-validated, PSScriptAnalyzer clean

### What changed
- `$featureLabel` array replaced by two separate constructs: `$aclLabel` (MSA/gMSA/dMSA/WinLaps) and `$hasAclIncludes` flag
- Three-branch conditional builds `$topHeader` / `$resultsHeader` instead of interpolating a single `$standaloneLabelStr` into fixed suffix strings
- `$standaloneLabelStr` removed entirely (was flagged as assigned-but-never-used by PSScriptAnalyzer after the refactor)

### Header rendering matrix (lab-validated)
| Switches | Top header | Results header |
|---|---|---|
| `-EnableAuditing` only | `=== Standalone Domain Audit Rule Audit ===` | `=== Domain Audit Rule Results ===` |
| `-IncludeMsa -EnableAuditing` | `=== Standalone MSA ACL & Decryptor / Domain Audit Rule Audit ===` | `=== MSA ACL & Decryptor / Domain Audit Rule Results ===` |
| `-IncludeMsa` only (unchanged path) | `=== Standalone MSA ACL & Decryptor Audit ===` | `=== MSA ACL & Decryptor Audit Results ===` |

### Gotcha
- After removing `$standaloneLabelStr` from both Write-Host calls, the variable assignment itself had to be dropped — PSScriptAnalyzer fires on assigned-but-never-used variables

---

## Learnings: Audit-TierModel.ps1 -EnableAuditing Wiring (2026-08-14)

**Branch:** `feature/domain-auditing`
**Status:** ✅ DELIVERED — all 6 integration points wired, lab-validated, PSScriptAnalyzer clean

### Integration Points
1. **Comment-based help** — `.PARAMETER EnableAuditing` + 2 `.EXAMPLE` blocks added at top of `Audit-TierModel.ps1`
2. **Param block** — `[switch]$EnableAuditing` after `[switch]$IncludeWinLaps`
3. **Scope validation** — `$EnableAuditing` added to `$includeParameters` array; both error messages updated to name it
4. **FullDeployment optional-features block** — `if ($EnableAuditing)` block after WinLAPS block; calls `Test-TierModelAuditRule -SuppressSummary`; result wrapped as `EntityType = 'Domain Audit Rule'` with `TotalAcls = TotalChecked`
5. **Consolidated report EntityType handling** — `'Domain Audit Rule'` added at three sites: two `$_ -in '...'` case lists, one `$entityType` label switch
6. **Standalone block** — `$featureLabel += 'Audit'`; `if ($EnableAuditing)` test block with drift/error accumulation

### Key Decisions
- **`Test-TierModelPrerequisites` does NOT accept `-EnableAuditing`** — prereq splat in standalone block skips the EnableAuditing key; SeSecurityPrivilege check lives in the cmdlet itself
- **`EntityType = 'Domain Audit Rule'`** with `TotalAcls` (= `TotalChecked`) maps into same consolidated-report rendering as WinLaps Decryptor
- **Standalone featureLabel** becomes `'Audit'` → produces slightly redundant "=== Audit ACL & Decryptor Audit ===" header — cosmetic, matches the WinLAPS pattern exactly

### Lab Validation Results (2026-08-14) — read-only, no checkpoint restore
- **T1** `.\Audit-TierModel.ps1 -EnableAuditing` → COMPLIANT, Total Checked: 1, Drift: 0 ✅
- **T2** `.\Audit-TierModel.ps1 -FullDeployment -EnableAuditing` → Full Audit Results includes `Domain Audit Rule: Checked: 1, Drift: 0, Errors: 0` ✅
- **T3** `.\Audit-TierModel.ps1 -FullDeployment` (no `-EnableAuditing`) → Full Audit Results Total Checked: 366 (no Domain Audit Rule row) ✅
- **T4** `.\Audit-TierModel.ps1 -EnableAuditing -OuOnly` → `Write-Error: -IncludeMsa, -IncludeGmsa, -IncludeDmsa, -IncludeWinLaps, and -EnableAuditing can only be used standalone or combined with -FullDeployment...` ✅

### PSScriptAnalyzer
- Zero errors/warnings on `Audit-TierModel.ps1` after all edits

### Files Staged to Lab
- `Audit-TierModel.ps1` → `C:\TierModel\Audit-TierModel.ps1` on DC01
- `Deploy-TierModel.ps1` (yellow ■ + split warning fixes) → `C:\TierModel\Deploy-TierModel.ps1` on DC01

### Deferred to Joel UAT
- Interactive double-Y confirm flow (`-EnableAuditing -ConfirmApply`) — cannot test non-interactively
- Standalone `$featureLabel` header wording ("Audit Audit Results") — cosmetic; matches WinLAPS pattern; defer decision to Joel

## Learnings: -EnableAuditing Production Build (2026-08-14)

**Branch:** `feature/domain-auditing`
**Status:** ✅ DELIVERED — all 4 cmdlets, config/schema, deploy integration, lab smoke-tested

### Files Created
- `config/tiermodel-audit.json` — optional segment; `{{DOMAIN_DN}}` templating; 9-right list
- `modules/TierModel/public/Get-TierModelAuditRule.ps1` — plan/drift (returns TotalActions, ConfigureActions, ExistingCount)
- `modules/TierModel/public/New-TierModelAuditRule.ps1` — apply (UNION converge; returns Applied/Executed/Failed/Skipped/Errors/DurationMs/Converged)
- `modules/TierModel/public/Test-TierModelAuditRule.ps1` — drift detection (returns Compliant/Missing/Drift/Findings)
- `modules/TierModel/public/Get-TierModelAuditRuleFd.ps1` — FullDeployment planner (delegates to Get-TierModelAuditRule; re-stamps CorrelationId)

### Files Modified
- `config/tiermodel.schema.json` — added `domainAuditRule` object schema
- `modules/TierModel/public/Get-TierModelConfig.ps1` — added `tiermodel-audit.json` to `$optionalFiles`; merged `domainAuditRule` property into config object
- `modules/TierModel/TierModel.psd1` — bumped 1.2.3→1.3.0; added 4 new FunctionsToExport; ReleaseNotes updated
- `Deploy-TierModel.ps1` — see deploy hook regions below

### Deploy Hook Line Regions (post-edit, approximate)
| What | Region |
|------|--------|
| `[switch]$EnableAuditing` param | ~line 100 (after `[switch]$IncludeWinLaps`) |
| `$includeParameters` array update | ~line 115 |
| Scope validation error messages | ~line 119-127 |
| Audit 2nd confirmation gate | ~line 248 (new block before existing `if ($ConfirmApply)`) |
| FullDeployment Phase 11 planning | ~line 1756 (after WinLAPS phase block) |
| FullDeployment Phase 11 execution | ~line 1992 (after WinLAPS execution block) |
| `$auditExecResult` in `$allResults` | ~line 2015 |
| Standalone audit block | ~line 2652 (after WinLAPS standalone block) |
| `Add-IncludeAclPhaseToDeploymentPlan` | ~line 1148 — extended to handle `ConfigureActions` → `ConfigureCount` via `[hashtable].ContainsKey()` |

### Config Load Path
`Get-TierModelConfig` loads `tiermodel-audit.json` as optional segment (same pattern as WinLAPS). Key: `$config.domainAuditRule`. Cmdlets check `$Config.PSObject.Properties.Name -contains 'domainAuditRule'` for presence.

### Cmdlet Object Shapes
- **Get-TierModelAuditRule / Fd:** `{ Actions, Summary{ TotalActions, ConfigureActions, ExistingCount }, Errors, DurationMs, Converged, CorrelationId }`
- **New-TierModelAuditRule:** `{ Applied, Executed, Failed, Skipped, Errors, DurationMs, Converged, CorrelationId }`
- **Test-TierModelAuditRule:** `{ TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings, DurationMs, CorrelationId }`
- **Findings shape:** `{ Type, ResourceType, Identifier, Property, ExpectedValue, ActualValue, Details }`

### Gotchas

**`Add-IncludeAclPhaseToDeploymentPlan` uses `PSObject.Properties.Name` to detect hashtable keys — doesn't work for `@{...}` Summaries.** The existing WinLAPS code works around this by using `CreateAcl` fallback action counting. Our audit plan uses `ConfigureAuditRule` (not `CreateAcl`), so I had to:
1. Add `ContainsKey()` checks as alternatives to `PSObject.Properties.Name` checks
2. Add `ConfigureAuditRule` to the fallback `Where-Object` filter

This affects ALL future feature work that adds non-`CreateAcl` action types to `Add-IncludeAclPhaseToDeploymentPlan`.

**Summary hashtable keys are hashtable keys, NOT PSObject note properties.** Use `$hash.ContainsKey('key')` or `$hash['key']` to check/access them; never rely on `PSObject.Properties.Name`.

**UNION contains WriteProperty even on fresh clean DC.** The clean domain root has default `Everyone/Success/All/WriteProperty` ACEs in managed scope. The UNION target therefore includes WriteProperty + our 9 rights = effectively 9 distinct rights (WriteProperty is in our 9). Final ACE: 9 rights, idempotent.

**Emoji rendering:** `🟨` renders as `??` in non-UTF-8 consoles (Hyper-V Direct). Cosmetic only; not a bug.

**Pester intercepts `(expected` in Write-Host strings** on the lab DC (Pester is autoloaded). Smoke test verification strings must avoid the word `expected` when running via PowerShell Direct `-Command`.

### Lab Smoke Results (2026-08-14)
- **Plan mode:** Action count: 1, Configure count: 1, PARTIAL status shown ✅
- **B1 Fresh apply:** Applied: 1, Errors: 0, Converged: True, UNION rights displayed ✅
- **B2 Idempotency:** Plan actions: 0, IDEMPOTENCY PASS ✅
- **B3 Union+no-clobber:** Partial seed + Failure ACE seeded, PARTIAL detected, Applied:1, final rights = all 9 ✅
- **Double-Y confirm flow:** Deferred to Joel's interactive UAT (requires Read-Host, cannot test over PowerShell Direct)

---

## Learnings: SACL Audit Spike — domain-root auditing read/write/merge (2026-08-14)

**Spike script:** `.research/copilot-cli-hyperv-ad-lab/scripts/audit-spike/Invoke-AuditSpikeRepro.ps1`
**Target:** domain root (`AD:DC=tierlab,DC=internal`) SACL — feed for `-EnableAuditing` parameter
**Lab:** TierLab-DC01 / DC-Promoted-Clean baseline / tested under clean-reset conditions

### SACL Read API
- **Winner:** `Get-Acl -Path "AD:<dn>" -Audit` — works correctly once `Import-Module ActiveDirectory` (provides the `AD:` PSDrive) is loaded.
- `DirectoryEntry.Options.SecurityMasks` is NOT available on this OS/PS version; that property path fails.
- **Write API:** `Set-Acl -Path "AD:<dn>" -AclObject <obj>` — must use the SAME object returned by the same `Get-Acl` call; cross-object ACE removal silently no-ops.
- **Privilege:** `SeSecurityPrivilege` is required to read/write the SACL. Lab admin has it; production must verify.
- `GetAuditRules()` returns `AuthorizationRuleCollection` — NOT a PS array. NEVER wrap with `@()` (wraps the entire collection as one element). Enumerate via `foreach` or pipeline.

### AddAuditRule behaviour (empirical result)
- **AddAuditRule MERGES** — when an ACE with matching SID / AuditFlags / InheritanceType already exists, adding a new rule with different rights merges the rights (bitwise-OR) into that existing ACE rather than creating a duplicate.
- HOWEVER: the baseline domain root has TWO default `Everyone/Success/All/WriteProperty` ACEs. If there are multiple existing managed ACEs (e.g. seeded partial + 2 defaults), AddAuditRule only merges into one of them; the others remain as-is. The count stays the same (no new ACE) but the state is still multi-ACE.

### Validated converge recipe
```
$acl = Get-Acl -Path "AD:<dn>" -Audit
# Read managed ACEs FROM SAME acl object
foreach ($a in <managedAces-from-this-acl>) { $acl.RemoveAuditRuleSpecific($a) }
$acl.AddAuditRule(<canonical 9-right rule>)
Set-Acl -Path "AD:<dn>" -AclObject $acl
```
Managed = Everyone / Success / Inheritance=All / non-inherited. PurgeAuditRules(SID) intentionally avoided.

### Idempotency: PASS
- When the canonical ACE already exists (1 ACE, all 9 rights), converge detects "already up to date" and makes zero writes.

### No-clobber: PASS
- `Everyone/Failure/All` ACE seeded before converge; survived converge untouched. Converge is scoped to `AuditFlags=Success` only.

### Baseline default SACLs on clean domain root (5 rules)
1. S-1-1-0 / Success / None — WriteProperty, WriteDacl, WriteOwner
2. S-1-5-32-544 (Administrators) / Success / None — ExtendedRight
3. Domain-SID-513 (Domain Users) / Success / None — ExtendedRight
4. S-1-1-0 / Success / All — WriteProperty  *(duplicate)*
5. S-1-1-0 / Success / All — WriteProperty  *(duplicate — two identical default ACEs)*

**Note:** The two identical default `Everyone/Success/All/WriteProperty` ACEs are included in "managed" scope by the converge logic and will be REPLACED by the single canonical ACE. This is intentional and correct; it also cleans up a pre-existing duplication in the default SACL.

---

## Current: Windows LAPS Implementation Complete (2026-07-16)

**Status:** ✅ SHIPPED — All T001–T021 tasks complete, committed to feature/windows-laps branch, ready for Joel's UAT + release.

**Implementation Summary:**
- T001–T013: Implementation + audit cmdlet (5 new public functions, config, decryptor integration)
- T014–T020: Test suite (113 new Pester tests, 90.92% coverage, 1401/1401 green)
- T021: Documentation (8 files, README metrics updated to v1.2.0)

**Latest Fixes (2026-07-16):**
1. **SELF ACE Detection (Bug A):** Replaced `Find-LapsADExtendedRights` SELF check with `Get-Acl "AD:$ouDn"` filtering for non-inherited LAPS ACEs. SELF now correctly detected on all 7 OUs post-deploy.
2. **Mixed Findings Shapes (Bug B):** Consolidated audit reporting now guards `.Type` / `.Status` property access with `PSObject.Properties.Name` checks to work with both WinLaps ACL and Decryptor findings shapes.

**Essential Patterns for Future Work:**
- SELF ACE detection: Use `Get-Acl "AD:$ouDn"` + non-inherited filter + LAPS GUID filter (never `Find-LapsADExtendedRights` for SELF)
- Pre-compute LAPS schema GUIDs once before loop, not inside it
- Mixed audit findings: Guard property access with `$_.PSObject.Properties.Name -contains 'Type'`
- Decryptor audit pattern: Get-GPO → Get-GPRegistryValue ADPasswordEncryptionPrincipal → compare -ieq expected value
- Opt-in enforcement: WinLaps audit gated by `if ($IncludeWinLaps)` inside optional feature block

**Next Phase:** Joel's manual UAT, then PR merge, v1.2.0 release.

## Learnings: BUG-006 Canonical-ACL Pre-flight Gate (2026-08-11)

**Function:** `Test-TierModelCanonicalAcl`
**File:** `modules/TierModel/public/Test-TierModelCanonicalAcl.ps1`
**Exported in:** `modules/TierModel/TierModel.psd1` (alphabetical, before Test-TierModelPrerequisites)
**Wired into:** `modules/TierModel/public/Test-TierModelPrerequisites.ps1` (after WinLaps block, before ArrayLists conversion)

**Detection technique:**
- Use `System.DirectoryServices.Protocols` (S.DS.P) for DACL-only read from AD — NOT `Get-Acl` or `DirectoryEntry.Options` (unreliable for this use case).
- Parse bytes via `CommonSecurityDescriptor($true, $true, $sdBytes, 0)` — `isContainer=$true, isDS=$true` is mandatory for AD objects; `isDS=$false` mis-parses object-type ACEs and gives wrong results.
- `RawSecurityDescriptor`/`RawAcl` have NO `IsCanonical` property — must use `CommonSecurityDescriptor.DiscretionaryAcl.IsCanonical` (CommonAcl exposes it).
- Cast enum operands to `[int]` before `-band` (PS 5.1 throws otherwise; defensive for PS 7+ too).
- Two parameter sets: `ByServer` (live AD) and `ByBytes` (Pester-friendly, no AD required).

**Insertion point in Test-TierModelPrerequisites:**
- Between the `$result.EnvironmentSnapshot.LapsModulePresent = $lapsModulePresent` / `}` block close and the `# Convert ArrayLists` comment.
- Guarded with `if (Get-Module ActiveDirectory ...)` mirroring existing AD-language check pattern.
- On exception: sets `RootAclCheckError` snapshot field only — does NOT hard-fail (DC reachability already gated).

**Audit also hard-stops:** Both `Deploy-TierModel.ps1` and `Audit-TierModel.ps1` call `Test-TierModelPrerequisites` and fail-fast on `.Valid=$false`. Placing the gate in the shared prerequisites means Audit also hard-stops on a non-canonical root domain DACL. This is intentional and accepted.

**STATUS (2026-08-11 end-of-session):** Gate + doc lab-validated. Beast implementation complete. Pending owner code review. No commit (per owner request).

---

**Earlier history archived to history-archive.md (2026-07-28).**

**Essential Patterns (for future work):**
1. **StrictMode scoping:** Shared variables resolve BEFORE conditionals, not inside branches.
2. **ResourceType in display:** Branch on `$_.ResourceType -eq 'LapsPermission'` to render lapsOperation/allowedPrincipals.
3. **ACE IsInherited (PS7):** Use `Get-Acl "AD:<dn>"`, not nTSecurityDescriptor; filt
[truncated summary]

- 2026-08-11T20:14:44+08:00 | Moved non-blocking Pester side-by-side advisory from `\.Remediation` to `\.EnvironmentSnapshot.PesterAdvisory` in `Test-TierModelPrerequisites.ps1`; updated coupled test in `Unit.Prerequisites.Tests.ps1`; 1 Pester test passed, 0 failed.

- 2026-08-11T21:23:45+08:00 | FINALIZATION COMPLETE: Canonical-ACL gate + tests + docs reviewed APPROVE, nits fixed (Write-Warning in catch block, doc disclaimer removed). All 1,457 tests passing (91.13% coverage). PENDING owner code review + PR tomorrow. No commit (per owner request).
