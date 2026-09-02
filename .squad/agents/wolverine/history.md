# wolverine — History

## Session 2026-09-02 — Auth Silos Public Docs + v2 Migration (Storm)

Public-facing auth-silos operations guide revised with v2 migration appendix. No test impact (docs only).

---

## PENDING: Pester Tests for optional/Update-TierModelMembership.ps1

**Status:** BLOCKED (awaiting Joel UAT completion)
**Trigger:** Once Beast confirms UAT complete, write comprehensive Pester test suite covering all 15 tier switches + optional flags.

**Test Coverage Needed:**
- Tier 0/1/2 Operator switches
- ServiceAcct / PawDevices / MemberServers / Staging switches  
- Tier 2 EUD vs Tier 2 Operators conflict resolution
- -All aggregates
- Exclusion attribute handling
- -EnableDebug and -EnableLogging output
- -WhatIf logging logic (v1.7.2): script-relative Logs/Debug folders, WHATIF preview lines, -WhatIf:$false on infra I/O
- PS 7.0+ requirement + 5.1 block

---

## Session 2026-08-27 — Auth Silo Coverage Gap-Fill

**Status:** ✅ COMPLETE — Auth silos test suite rewritten for create-once model

**Deliverables:** 1,783 tests passing (1,771→1,783), coverage raised from 90.16% → 90.9%

**Key Outcomes:**
- New-TierModelAuthSilo: 79.8% → 99.1%  
- Get-TierModelAuthSiloMembershipFd: 64.7% → 87.8%
- Set-TierModelAuthSiloMembership: 61.5% → 87.8%

**Design Changes Validated:**
- Removed memberAccountGroups (computer-only model)
- Removed exemptAccounts (pre-set built-in exclusions)
- Deferred SDDL (null at plan time, resolved at execute time)
- -OnlyForSilos filter validation

**Key Learning:** Outer catch blocks in membership functions are structurally unreachable — all inner operations are exception-safe by design (HashSet, List, comparisons don't throw). Documented as structural barrier.

---

## Archived Sessions  

Detailed coverage reports from 2026-08-15 and earlier archived to history-archive.md. Current focus: Update-TierModelMembership.ps1 Pester tests awaiting Beast UAT completion.
