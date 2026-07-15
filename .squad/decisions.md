# Squad Decisions

## Active Decisions

*Active decisions from the current retention window. Older entries are archived in decisions-archive.md.*

### 2026-07-15T07:37:12Z: Windows LAPS Decryptor — Full-Deployment Lab Validation PASS
**Author:** Wolverine (Logan)  
**Status:** ✅ VERIFIED — Lab-proven, no bugs, idempotent  
**Significance:** Canonical milestone; decryptor code on disk, ready for Joel's manual UAT

**Test Summary:**
- Deployed `-FullDeployment -IncludeWinLaps -ConfirmApply` against clean WinLapsSchema baseline
- All 6 non-DC GPO `ADPasswordEncryptionPrincipal` entries verified independently via `Get-GPRegistryValue`
- Applied: 681 total (baseline 643, delta +38 including WinLaps acls + decryptor); decryptor contributed +6 actions
- Idempotency: Re-run Applied 0, Converged True — all 6 decryptor actions correctly detected as converged
- Errors: 0; Bugs: 0

**Verified GPO Mappings (7/7 pass):**
- Tier 0 PAWs → TIERLAB\Tier0Admins ✅
- Tier 0 Servers → TIERLAB\Tier0ServerOperators ✅
- Tier 1 PAWs → TIERLAB\Tier1Admins ✅
- Tier 1 Servers → TIERLAB\Tier1ServerOperators ✅
- Tier 2 PAWs → TIERLAB\Tier2Admins ✅
- Tier 2 EUD → TIERLAB\Tier2DeviceOperators ✅
- Tier 0 DCs → (NOT SET, DSRM=Domain Admins) ✅

**Key Confirmations:**
- `ADPasswordEncryptionEnabled=1` preserved on all 6 non-DC GPOs (no clobber)
- Zero property/method errors
- Design validated: decryptor decouples from main LAPS ACL flow; config-driven; integrates cleanly into Phase 10

**Next Phase:** Joel's manual UAT (end-to-end `Get-LapsADPassword -AsPlainText` validation, prerequisites edge-cases)

### 2026-07-15T14:59:20+08:00: Windows LAPS Decryptor Integration Complete
**Author:** Beast (Dr. Hank McCoy)
**Branch:** feature/windows-laps
**Status:** IMPLEMENTED — decryptor GPO configuration wired into deploy code; awaiting Joel lab validation

**Summary:** Integrated proven Set-GPRegistryValue ADPasswordEncryptionPrincipal recipe into deployment as config-driven, idempotent ConfigureLapsDecryptor step within -IncludeWinLaps flow.

**Changes:**
- config/tiermodel-winlaps.json: Added decryptorGroup + decryptorGpoName fields; EUD simplified to Tier 2 Device Operators only; schemaVersion 1.1.0
- Get-TierModelWinLapsAcl(.Fd).ps1: Added GPO existence gate; decryptorGroup resolution; ConfigureLapsDecryptor plan actions
- New-TierModelWinLapsAcl.ps1: Execute ConfigureLapsDecryptor via Set-GPRegistryValue ADPasswordEncryptionPrincipal; ShouldProcess/-WhatIf safe
- Deploy-TierModel.ps1: Display ConfigureLapsDecryptor plan actions

**Design Decisions (Joel-Approved):**
1. decryptorGroup stores plain display name (e.g., "Tier 0 Admins"); runtime resolution to NETBIOS\sAMAccountName via Get-ADGroup
2. decryptorGpoName explicit (e.g., "*- Tier 0 PAWs Windows LAPS - Computer"); avoids OU→GPO inference
3. EUD simplified: Tier 2 Device Operators only (dropped Help-desk for consistency)
4. DC entry: no decryptorGroup/decryptorGpoName; DSRM always uses Domain Admins

**Validation:** Parse OK, module import v1.2.0 OK, Pester 101/101 pass. Lab NOT touched (Joel UAT pending).

### 2026-07-15T14:59:20+08:00: USER DECISION: Cross-Tier LAPS Decrypt — Per-Tier Isolation
**Requested by:** Joel Platek
**Context:** Windows LAPS decryptor GPO integration; question of Tier 0 Admins access to Tier 1/2 PAW passwords
**Decision:** KEEP per-tier isolation — Tier 0 Admins CANNOT decrypt Tier 1/2 PAW passwords
**Rationale:** 
- CNG-DPAPI decryption requires exact encryption principal (no inheritance via GenericAll)
- Per-tier PAW decryptors (T1 PAWs→Tier1Admins, T2 PAWs→Tier2Admins) enforce separation
- config/tiermodel-groups.json has no group nesting (no members/memberOf fields)
- Tier 0 Admins retain GenericAll (READ-only) on lower PAW OUs, but cannot decrypt passwords
- This is the strongest security posture; alternative (nest T0 into T1/T2) was rejected
**Status:** CONFIRMED — implementation reflects this choice

### 2026-07-15T14:59:20+08:00: USER DECISION: LAPS ACL Delegation at Tier Model Root OU
**Requested by:** Joel Platek
**Context:** Where to place LAPS delegation entires (Tier Model Administration root OU vs per-tier)
**Decision:** KEEP LAPS ACL delegation at Tier Model root OU (OU=Tier Model Administration)
**Rationale:** Standardized location matching existing ACL delegation patterns; allows inheritance to child OUs; single authoritative source for delegation config
**Status:** CONFIRMED — Tier0Admins entry in config now targets root OU; read/reset delegations organized by OU within config

### 2026-07-15T14:59:20+08:00: USER DECISION: decryptorGroup Display Name Convention
**Requested by:** Joel Platek
**Context:** Placeholder format for decryptorGroup field (plain name vs literal DOMAIN\)
**Decision:** KEEP decryptorGroup as plain display names (e.g., "Tier 0 Admins"), NOT literal DOMAIN\ format
**Rationale:** Consistent with existing readGroup/resetGroup convention; no modification to Resolve-TierModelPlaceholder needed; runtime resolution happens at execution time via Get-ADGroup -Filter
**Status:** ACTIVE — placeholder convention unchanged; may revisit if Joel requests literal DOMAIN\ format later

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

## Archived Inbox (merged from .squad/decisions/inbox/)

### Beast Decision: Precompute Optional MSA/gMSA/dMSA ACL Plans During Full-Deployment
**Date:** 2026-06-03T21:34:33.354+08:00
**Requested by:** Joel Platek
**What:** Precompute optional MSA/gMSA/dMSA ACL plans during `Deploy-TierModel.ps1` full-deployment orchestration, before the aggregate Deployment Plan summary is printed, and reuse those same plan objects during optional feature execution.
**Why:** The optional include phases were previously analyzed after the summary, so planning output missed their yellow ACL lines and aggregate counts. Reusing the precomputed Fd plans keeps planning and apply paths aligned and avoids a second, divergent planning pass.
**Impact:** `-FullDeployment -IncludeMsa/-IncludeGmsa/-IncludeDmsa` now shows phases 7-9 in planning mode, adds their `CreateAcl` counts into the summary totals, and executes the same stored plans after the standard phases complete successfully.

### Beast: Phase 16 Pester Test Patterns — MSA/gMSA/dMSA
**Author:** Beast (Dr. Hank McCoy)
**Date:** 2025-07-18
**Relates to:** T028–T036, Unit.MsaAclOperations.Tests.ps1, Unit.GmsaAclOperations.Tests.ps1, Unit.DmsaAclOperations.Tests.ps1

#### Conventions established by Phase 16 tests:
1. **Never use `Mock` inside `It` blocks for error-path tests** — Pester 5.7.1 treats such mocks as Context-scoped (bleed to subsequent tests). Use dedicated config objects instead.
2. **`Should -Invoke` "at least N" syntax** — `-AtLeastTimes` is NOT valid. Use `-Times N` (omit `-Exactly`) for "at least N" semantics.
3. **Hashtable vs PSCustomObject in cmdlet outputs** — Module cmdlets return `Summary` and `Validation` as `@{...}` hashtables. Test using `.Keys | Should -Contain`, not `.PSObject.Properties.Name`.
4. **InheritedObjectType in ACE mock rules** — Expected `InheritedObjectType` is always `[Guid]::Empty` for GenericAll/Descendents ACE entry.
5. **BeforeAll conditional mocks handle both positive and negative paths** — Describe-level BeforeAll mocks for `Get-ADOrganizationalUnit` and `Get-ADGroup` return or throw based on Identity value.

### Beast: Standalone Lab Validation — Use Direct Guest Deploy and Clear Blocking Checkpoint KDS Key
**Date:** 2026-05-30T15:30:00+08:00
**By:** Beast (via Copilot)
**What:** For manual Hyper-V validation of standalone `-IncludeMsa -IncludeGmsa -IncludeDmsa`, do not use `Start-LabAndDeploy.ps1` because it always appends `-FullDeployment`. After `Reset-Lab.ps1`, stage files to `C:\TierModel` manually over PS Direct, run `Deploy-TierModel.ps1` directly on the guest for `-OuOnly`, then `-GroupOnly`, then the standalone `-Include*` switches. Also remove the newer non-effective checkpoint KDS root key `d33d6533-a88c-8938-eac2-3c42a8b1838d` after each reset until the checkpoint is refreshed, because prereq validation currently sorts by the latest `EffectiveTime` and otherwise blocks gMSA/dMSA deployment.
**Why:** This was the only reliable way to complete the requested lab coverage from `DC-Promoted-Clean` and it produced passing results for both the full-deployment and standalone sequencing scenarios.

### Copilot Directive: 002-gmsa-support Testing Scope
**Date:** 2026-05-30T10:15:07
**By:** Joel Platek (via Copilot)
**Testing Constraints:**
1. DO NOT test pre-requisites (KDS, Server 2025, AD domain/forest requirements for dMSA) — Joel tests manually
2. DO NOT test actual creation of MSA/gMSA/dMSA objects — Joel tests manually
3. DO test: -Include* fails without OUs and Groups present
4. DO test: -Include* cannot be combined with -*Only parameters
5. DO test: All 3 -Include* parameters can run together with -FullDeployment
6. Track total successful changes/audits counts to verify they increase with MSA additions
7. Stop before Pester test tasks — let Joel complete manual testing first
8. Do NOT modify other cmdlets beyond what is required
9. If any issue arises, STOP and ask Joel
10. Update tasks.md as each task is completed
11. Recommended approach: Deploy tier model first, capture counts, roll back checkpoint, then make code changes and test

### Storm Decision: Phase 16 MSA/gMSA/dMSA Documentation Approach
**Date:** 2025-07-18
**Stakeholders:** Storm (DevRel & Documentation), Joel Platek (Project Lead)
**Scope:** Documentation updates for 12 new Managed Service Account ACL delegation cmdlets
**Approach:** All documentation files updated with consistent "Optional Feature" messaging across 7 files (test-tag-matrix.md, detailed-deployment-guide.md, deployment-methodology.md, drift-detection-details.md, cmdlet-architecture.md, test-coverage.md, README.md)
**Key Decisions:**
- All MSA/gMSA/dMSA features clearly marked as "Optional" requiring explicit -Include* switches
- Coordinated updates to 7 docs in single pass for consistency
- Test coverage marked "Pending" to signal team that measurements will shift once tests execute
- Standardized naming: MsaAcl, GmsaAcl, DmsaAcl tags; Get-TierModel*Acl cmdlet naming
**Status:** ACTIVE — All 7 docs updated, 12 cmdlets marked pending re-measure

## Windows LAPS Implementation — Phase 10 (T001–T012)

### 2026-07-14T10:30:00+08:00: Beast Windows LAPS Implementation T001–T012 Complete
**Author:** Beast (Dr. Hank McCoy)
**Branch:** feature/windows-laps
**Status:** Delivered T001–T012, ready for Joel's manual UAT at 🛑 STOP gate

**Architecture Summary:**
- **Config:** `config/tiermodel-winlaps.json` with 7 delegation entries (DC OU, Tier 0/1 Member Servers, Tier 0/1/2 PAW, Tier 2 EUD)
- **Cmdlets:** 4 new public functions (Get-TierModelWinLapsAcl, New-TierModelWinLapsAcl, Test-TierModelWinLapsAcl, Get-TierModelWinLapsAclFd); TierModel.psd1 v1.2.0
- **Deployment:** -IncludeWinLaps switch on Deploy-TierModel.ps1; Phase 10 in full-deployment orchestration
- **Actions:** 21 total when fresh (7 OUs × 3 actions: Self+Read+Reset); LAPS module direct calls (Set-LapsAD*Permission)
- **Idempotency:** Via Find-LapsADExtendedRights and Get-Acl "AD:$ouDn" for SELF detection
- **Group mapping (Joel-approved):** DC→Domain Admins(isDomainControllerOu:true); T0/T1 Members→T0/T1ServerOperators; T0/T1/T2 PAW→T0/T1/T2Admins; EUD→[Tier2DeviceOperators, Tier2HelpdeskOperators] dual-principal array

**Key Decisions:**
- Windows-LAPS-only (ms-LAPS-* attributes, never ms-Mcs-AdmPwd)
- -DomainController threaded on all 3 Set-LapsAD* calls
- -AllowedPrincipals format = "NetBIOS\sAMAccountName" (resolved at plan time via Get-ADGroup)
- ResourceType='LapsPermission' (distinct from 'ACL' used by gMSA/MSA/dMSA)
- Tier 0 Admins entry OU moved to ROOT "OU=Tier Model Administration" so Tier0Admins own LAPS across ALL PAW tiers
- No per-feature schema; central tiermodel.schema.json aligned instead (T002 dropped)
- Five-gate prerequisite: schema HARD STOP, LAPS module + cmdlets, DFL ≥2016, OUs + DC bypass, groups resolve

**Bugs Fixed During Lab Validation (all 5 FIXED):**
1. $schemaDN StrictMode crash in Test-TierModelPrerequisites.ps1 (WinLaps-only path) → added -or $IncludeWinLaps
2. Plan display identityreference crash → branched on ResourceType='LapsPermission' in Write-IncludeAclPlanActions
3. Get-ADGroup -Identity fails for display names with spaces → changed to -Filter "Name -eq"
4. $winLapsFdPlan pre-generated before groups exist → re-generate at execute time for -FullDeployment
5. SELF detection false positive (counts any SELF ACEs) → filter by LAPS GUID + use Get-Acl instead of nTSecurityDescriptor
5b. SELF ACEs show IsInherited=True via nTSecurityDescriptor in PS7 → use Get-Acl "AD:$ouDn"

**Local Validation:** ✅ Module imports (v1.2.0), 4 cmdlets resolve, Deploy-TierModel.ps1 parses, 101 Pester tests pass, PSScriptAnalyzer clean
**Lab Validation (Wolverine):** 6 live runs; final Run 6 GREEN: 673 applied (baseline 643, delta +30 correcting for design change to root OU SELF), idempotency Converged:True, all 7 OUs + EUD dual-principal verified

### 2026-07-14T11:05:00+08:00: Cyclops Code Review — Windows LAPS Deployment APPROVED
**Reviewer:** Cyclops (Architect)
**Verdict:** ✅ APPROVED (one blocking fix required)

**Scorecard (10/10 pass, 1 blocking):**
1. Windows-LAPS-only ✅ — all code uses msLAPS-*, Set-LapsAD*Permission, Find-LapsADExtendedRights; legacy AdmPwd only in docs disclaimers
2. Five-gate prerequisite ✅ — schema HARD STOP + stable message, LAPS module + cmdlets, DFL ≥2016, OUs with DC bypass, groups resolve
3. LAPS mechanics vs reference ✅ — Set-LapsAD*Permission calls all include -DomainController; -AllowedPrincipals = NetBIOS\sAMAccountName; EUD dual-principal works
4. Totals model (7×3=21) ✅ — exact 7 entries, each 3 actions, Phase 10 integrates into aggregate
5. Idempotency ✅ — Find-LapsADExtendedRights + Get-Acl for detection; known gap: tool can't distinguish read vs reset holders (acceptable; config enforces readGroup==resetGroup)
6. -WhatIf / ShouldProcess ✅ — CmdletBinding(SupportsShouldProcess), all writes gated by PSCmdlet.ShouldProcess
7. Config shape + schema ✅ — tiermodel-winlaps.json correct; tiermodel.schema.json oneOf [string, array] for readGroup/resetGroup
8. Integration/ordering ✅ — -IncludeWinLaps guard, Phase 10 after Phase 9, precompute-then-summary pattern matches MSA/gMSA/dMSA
9. **BLOCKING:** optional/Enable-TierModelAuditing.ps1 DELETED (unauthorized) — must restore or explicitly authorize
10. Constitution compliance ✅ — comment-based help on all 4 new public functions, Write-TierModelLog used throughout

**Non-Blocking Suggestions:**
- Cache Get-TierModelConfig result (called twice in prereqs)
- Document known limitation of Find-LapsADExtendedRights re: Read vs Reset distinction
- Consider Set-StrictMode standardization pass (future, not new debt)

**Summary:** Implementation well-structured, follows gMSA pattern, correctly translates reference script into idempotent config-driven phased deployment. Single blocking file restoration trivial.

### 2026-07-14 (Wolverine): Windows LAPS Baseline & Live Deployment Testing
**Tester:** Wolverine (Logan)
**Lab:** TierLab-DC01 (Hyper-V), WinLapsSchema checkpoint
**Sessions:** 6 runs (Bugs 1-5b found and fixed), final Run 6 ✅ GREEN for Joel's UAT gate

**Run 6 Summary (Final — All Bugs Fixed):**
- Applied: 673 (baseline 643, delta +30) ✅ totals increase
- SELF applied: 7/7 OUs ✅ (including new Tier Model Administration root per Joel design)
- R/R applied: 10 actions ✅ (DC + T0Members + T1Members + EUD; T1PAW/T2PAW skipped pre-existing)
- Idempotency (2nd run): Applied 0, Converged True ✅ (Bug 5b fix confirmed)
- EUD dual-principal: Tier2DeviceOperators + Tier2HelpdeskOperators ✅
- All 7 config OUs delegated ✅
- Plan display clean ✅ (0 errors)
- Legacy LAPS refs: NONE ✅

**Bug 5b Root Cause (Confirmed Fixed):**
- **Symptom:** SELF ACEs show IsInherited=True via Get-ADOrganizationalUnit -Properties nTSecurityDescriptor in PS7 → detection filter misses them → SELF re-applied every run
- **Fix Applied:** Both planners (Get-TierModelWinLapsAcl & Get-TierModelWinLapsAclFd) now use Get-Acl "AD:$ouDn" for SELF detection instead of nTSecurityDescriptor
- **Result:** SELF idempotency now works correctly (Applied 0, Converged True on 2nd run)

**Design Behavior Note (Joel):**
- Tier Model Administration root OU: Tier0Admins already present via GenericAll from base deploy OU ACL phase → WinLaps planner correctly detected and skipped Read/Reset, added SELF only
- T1PAW/T2PAW: Tier0Admins present via inherited GenericAll from root OU → effective LAPS access confirmed via Get-Acl (Find-LapsADExtendedRights reports direct holders only)
- Functional access verdict: Tier0Admins CAN read/reset LAPS passwords on ALL computers in TierModel admin hierarchy via GenericAll inheritance

**Validation Commands (next manual UAT phase):**
- Get-LapsADPassword -Identity \<T1PAW-computer\> -AsPlainText as Tier0Admins member (confirm end-to-end)
- Find-LapsADExtendedRights vs Get-Acl comparison on inherited scenarios

**Prerequisites Testing (Joel manual UAT scope):**
- Schema-missing hard-stop
- DFL < 2016 rejection
- LAPS module missing
- DC/DSRM scope rejection

**Lab Restore Commands:**
Provided in baseline report; VM clean at WinLapsSchema checkpoint, ready for Run 7+ if needed after UAT fixes.
