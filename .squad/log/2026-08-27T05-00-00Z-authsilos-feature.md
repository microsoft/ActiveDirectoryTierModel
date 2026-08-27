# Session Log: Auth-Silos Feature Delivery

**Date:** 2026-08-27T05:00:00Z  
**Branch:** `feature/auth-silos`  
**Agents:** Beast, Wolverine, Storm (docs), Coordinator (integration), Scribe  

## Delivery Summary

The `-IncludeAuthSilos` feature implements complete authentication policy and silo lifecycle management for the Active Directory Tier Model, enabling enforcement-ready audit-mode deployment of tier-based Kerberos hardening across Tier 0 Admin, Tier 1 Admin, Tier 2 Admin, and Tier 2 EUD.

### Feature Scope

- **4 Authentication Policies** + **4 Authentication Silos** (1:1 mapping)
- **TGT Lifetimes**: Tier 0 (120m), Tier 1 (240m), Tier 2 Admin (360m), Tier 2 EUD (domain default)
- **Audit mode default**: All objects created with Enforce=$false, ProtectedFromAccidentalDeletion=$true
- **SDDL invariant**: Member_of_any (OR logic) — AND logic is documented lockout failure mode
- **Idempotent membership**: Group expansion with recursive resolution, exemption handling, pre-checks on grant/set

### Agents and Deliverables

| Agent | Deliverable | Status |
|---|---|---|
| Beast | 8 public cmdlets + 2 audit cmdlets + 1 public helper; Deploy/Audit integration; tiermodel-authsilos.json config | ✅ Lab-ready |
| Wolverine | 88 Pester tests (44 deploy + 44 audit); stale version fixes | ✅ All passing |
| Storm | auth-silos-operations-guide.md with Appendix B (v2.0.0 breaking change); 15-scenario UAT table | ✅ Draft |
| Coordinator | StrictMode .Count guard; membership idempotency fix; Build-TierModelAuthSddl public placement; version bump | ✅ Complete |
| Scribe | Decision consolidation; orchestration logs; session record | ✅ Complete |

### Key Design Decisions

1. **Plan-based cmdlet pattern**: Get-*Fd returns actions; New-* executes (mirrors WinLaps)
2. **Config-first, SDDL-resolved-at-runtime**: Group names in JSON, SIDs resolved during deploy
3. **RID-500 runtime exemption**: Handles renamed administrator accounts
4. **All functions under public/**: No internal/ helper placement (confirmed directive)
5. **Code-first, tests-after**: Lab validation before Pester authoring (workflow directive)

### Lab Validation Gate

8 open items documented in Beast's decision:
- Enforce parameter hashtable splatting behavior
- SDDL round-trip format preservation
- TGT lifetime property naming
- Silo policy property names (DN vs friendly)
- Empty group handling
- Grant idempotency error behavior

### Breaking Changes (v2.0.0)

- New groups: Tier2EUDDevices, Tier2PAWDevices, Tier2EUDDomainJoin
- New service account: svc-t2euddomainjoin
- Modified GPOs: Tier 0 DCs Authentication Silo Computer; all Account Restriction templates
- Upgrade path required for v1.x.x deployments

## Next Steps

1. Lab validation of 8 open items (Joel)
2. Config review and confirmation (Joel)
3. Deploy code to lab (team)
4. Audit code deployment and validation (team)
5. Pester execution against lab environment
6. Enforcement pre-checklist and rollout planning
