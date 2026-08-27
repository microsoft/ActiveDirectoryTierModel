# beast — History (Archived Summary)

## 2026-08-27 — Auth Silos Feature Complete

**Status:** ✅ IMPLEMENTATION COMPLETE — Deploy + Audit cmdlet sets, 8 public functions, config, lab-ready

### Auth Silos Deployment (2026-08-27)

**8 Public Cmdlets:**
- Get-TierModelAuthPolicy / Get-TierModelAuthPolicyFd — Load and plan auth policies
- Get-TierModelAuthSilo / Get-TierModelAuthSiloFd — Load and plan auth silos
- New-TierModelAuthPolicy — Idempotent create/update (Enforce=$false, PFAD=$true)
- New-TierModelAuthSilo — Idempotent create/update (1:1 policy per silo; all 3 classes same policy)
- Set-TierModelAuthSiloMembership — Idempotent membership (recursive expansion, exemptions, pre-checks)
- Test-TierModelAuthSiloPrerequisite — Dependency gate (group existence)

**Public Helper:**
- Build-TierModelAuthSddl — Constructs Member_of_any (OR-logic) SDDL; never AND-logic

**Key Invariants:**
- SDDL OR-logic: Member_of_any prevents lockout; AND-logic is documented failure mode
- Policies before silos (execution order enforced in Deploy-TierModel)
- Grant then Set for membership (both idempotent via pre-checks)
- RID-500 exemption resolved at runtime for renamed administrator accounts

**Deploy-TierModel Integration:**
- Param: -IncludeAuthSilos (after -IncludeWinLaps)
- Standalone: 3-step execution (policies → silos → membership)
- FullDeployment: Phase 12 planning; policies → silos → membership after audit
- Module v1.3.3, FunctionsToExport updated

**Config:** config/tiermodel-authsilos.json — 4 policies + 4 silos (1:1 mapping), group names resolved at runtime

### Auth Silos Audit (2026-08-27)

**2 Public Audit Cmdlets:**
- Test-TierModelAuthPolicy — Verify policy compliance (existence, Description, TGT lifetime, SDDL via Compare-TierModelAuthSddl, PFAD)
- Test-TierModelAuthSilo — Verify silo compliance (existence, policy links, PFAD, membership validation)

**Return Shape:** TotalChecked / Compliant / Missing / NonCompliant / Errors / Drift / Findings array (consistent with Test-TierModelWinLapsAcl)

**Hard Rule:** Enforce is intentionally NOT checked — audit mode is default; enforcement is a separate lifecycle step

**Audit-TierModel Integration:**
- -IncludeAuthSilos param after -IncludeWinLaps
- Standalone block + FullDeployment results (EntityType: 'Auth Policies' / 'Auth Silos')
- Membership comparison: config-expected vs silo's msDS-AuthNPolicySiloMembers (recursive expansion minus exempts + RID-500)

### SDDL Alias Fix (2026-08-26)

**Bug:** Domain Controllers group (RID 516) stored as SID, read back as SID(DD) alias → false drift on every re-run (Tier 0 only)

**Fix:** New public cmdlet Compare-TierModelAuthSddl
- Extracts domain SID from desired SDDL
- Expands DA/DU/DG/DC/DD aliases to full SIDs in both SDDLs
- Set-based comparison (order-insensitive, case-insensitive)
- Returns { Equal: bool, Reason: string }

**Applied to:** Get-TierModelAuthPolicyFd drift detection

### Silo Policy Dependency Fix (2026-08-25)

**Bug:** First deploy errored on silo planning (policies not yet in AD) → deployment blocked

**Fix:**
1. Get-TierModelAuthSiloFd now validates policy reference against **config**, not AD
2. Deploy-TierModel.ps1 restructured: policies created first (AD), then silos planned+created
3. Error handling: policy not in config = real error; policy pending creation = proceeds

**Invariant:** Policies must exist in AD before silos are created (non-negotiable)

### Config Finalization (2026-08-27)

**Naming Convention:** All 8 objects use *-  prefix (mirrors GPO convention)
- Tier 0/1/2 Admins: policies + silos
- Tier 2 EUD: policy + silo

**TGT Lifetimes:** Tier 0 (120m), Tier 1 (240m), Tier 2 Admin (360m), Tier 2 EUD (null/domain default)

**Group Scope:** Admins + Operators + ServiceAccounts per tier; Tier 2 EUD = LocalDeviceOperators only

**Open Items:** VPN account group inclusion (pending confirmation)

---

## 2026-08-24 — Format-TierModelDuration Implementation

**Status:** ✅ COMPLETE — Public function, 9 Write-Host sites updated, 12/12 smoke tests pass

**Function:** Format-TierModelDuration.ps1
- 4-tier format: <1ms / Xms / Xs / Xm Ys
- Floor-based arithmetic (no banker's rounding: 90000→1m 30s, not 2m 30s)
- Accepts both [int] and [double] DurationMs

**Integration:** Updated 9 Write-Host console sites in Deploy-TierModel.ps1; left 2 log sites raw

**Module v1.3.0, added to FunctionsToExport**

**Regression Guards:** 90000/119999/120000 boundary values locked

---

## 2026-08-14 — -EnableAuditing Implementation

**Status:** ✅ DELIVERED — 4 audit cmdlets, config/schema, deploy integration, lab-validated

**Cmdlets:** Get-TierModelAuditRule, New-TierModelAuditRule, Test-TierModelAuditRule, Get-TierModelAuditRuleFd

**Config:** tiermodel-audit.json — 9-right SACL list, domain DN templating

**SACL Pattern (Validated):**
- Get-Acl -Path "AD:<dn>" -Audit (requires SeSecurityPrivilege)
- UNION converge: remove managed ACEs, add canonical 9-right ACE, Set-Acl
- Idempotency: already-converged = zero writes
- No-clobber: non-Success AuditFlags left untouched

---

## 2026-08-11 — BUG-006 Canonical ACL Pre-flight Gate

**Status:** ✅ COMPLETE — Test-TierModelCanonicalAcl, 18 tests, lab-validated

**Technique:** System.DirectoryServices.Protocols + CommonSecurityDescriptor parsing
- Check .DiscretionaryAcl.IsCanonical (CommonAcl only)
- Two parameter sets: ByServer (live AD), ByBytes (Pester-friendly)

**Integration:** Pre-flight gate in Test-TierModelPrerequisites (WinLaps block); both Deploy/Audit hard-stop on non-canonical state

---

## Essential Technical Patterns

**SDDL Semantics:** Member_of_any (OR) prevents lockout; Member_of_each (AND) = documented failure

**Idempotency:** Always check-before-act; .Count wrapping for empty sets (@() prevents StrictMode errors)

**Type Handling:** Mixed int/double require explicit casting

**SACL Converge:** Remove managed → add canonical → write same object; zero writes when converged

**Exemptions:** RID-500 resolved at runtime; configured accounts in HashSet (case-insensitive skip)

**CLR Conflicts:** Process-lifetime persistence; spawn clean child process to resolve

**Hashtable vs PSObject:** .ContainsKey() for hashtables; .Properties.Name for objects

**Two-Step Binding:** Grant-ADAuthenticationPolicySiloAccess + Set-ADAccountAuthenticationPolicySilo (both idempotent)

---

**Latest Decision:** Beast-AuthSilos-Deploy (2026-08-27) — 8-object model, SDDL design, key implementation decisions documented

**Next:** Lab validation of 8 open items; config review (Joel); module code deployment to test environment
