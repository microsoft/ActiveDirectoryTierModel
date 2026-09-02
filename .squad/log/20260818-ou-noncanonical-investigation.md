# Session Log: OU Non-Canonical DACL Investigation

**Date:** 2026-08-18T11:32:55+08:00  
**Coordinators:** Scribe (documentation), Beast (root cause), Research (sources), RubberDuck (corrections), Coordinator (owner liaison)  
**Status:** ✅ INVESTIGATION COMPLETE — Design discussion PENDING with owner

---

## Mechanism Confirmed

The non-canonical DACL corruption is a **documented .NET/AD platform behavior**, not a code-unique defect:

1. **Source:** `SetAccessRuleProtection($true,$true)` + `Set-Acl "AD:\"` on OUs with inherited Deny ACEs
2. **Effect:** Inherited Deny ACEs promoted to explicit while preserving positional order → end up after existing explicit Allows (violates canonical order: Deny must precede Allow)
3. **Trigger:** Any OU inheriting ≥1 Deny ACE, when disabling inheritance
4. **Throw:** `New-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $true` fails because `AddAccessRule()` refuses non-canonical parent DACL
5. **Recurrence:** Occurs after EVERY `SetAccessRuleProtection+Set-Acl` step on OUs with inherited Deny — not once-off

---

## Lab Evidence

**TierLab-DC01 (Phase 1 & 2):**
- Phase 1 (clean domain, no inherited Deny): Set-Acl succeeded + DC canonicalized → IsCanonical = True
- Phase 2 (inherited Deny present): Set-Acl wrote non-canonical → IsCanonical = False, Deny ACE at position 10 (after 9 Allow ACEs)
- Remediation (raw SD bytes + sort): IsCanonical restored to True, multiset preserved

---

## Key Decisions Captured

✅ **Beast Root-Cause Analysis** — Mechanism identified: `SetAccessRuleProtection` path, inherited Deny promotion, DC-side behavior  
✅ **Research Verdict** — Confirmed as known platform behavior (MS Learn, dotnet/runtime, managedpriv.com sources)  
✅ **RubberDuck Corrections** — Refined mechanism details, flagged DC-pinning bug, emphasized verify-after-write pattern  
✅ **Coordinator Directive** — Owner instructs: ASSUME corruption will occur → design for VERIFY+REMEDIATE per-step approach  

---

## NO Code Changes This Session

All investigation findings documented in `.squad/decisions/inbox/` (now merged into `decisions.md`).  
No product code modified. Design discussion required before implementation.

---

## Health Report

| Metric | Before | After |
|--------|--------|-------|
| decisions.md size | 1,727 bytes | ~48,000 bytes |
| Inbox files | 11 | 0 |
| Decisions captured | ~2 | 11 items + context |

All inbox files merged and deleted. Archive not required (below threshold).

---
