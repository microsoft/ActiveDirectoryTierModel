# Beast — History Archive

Archived on 2026-07-15T06-59-20Z. Summary of earlier session learnings archived for reference.

## Earlier Sessions

- Phase 16 Pester patterns (2025-07-18): Mock scope bleeding, shadow variables, Resolve-TierModelPlaceholder double-invocation
- MSA/gMSA/dMSA prep work (2026-05-29 through 2026-06-03): Precomputed optional plans, lab validation with KDS workaround
- Windows LAPS Wave-1 technical foundation (2026-07-13): Schema validation, LAPS cmdlets research, deployment patterns established
- Windows LAPS implementation T001–T012 (2026-07-14): Full cmdlet suite wired, 5 bugs found and fixed (StrictMode, display, group lookup, FD plan stale, SELF detection), lab runs 1–6 progression

## Key Learnings (Condensed)

- StrictMode trap: conditional variable initialization causes VariableIsUndefined in shared code paths — always resolve shared vars before any conditional branch
- LAPS ActionType ResourceType='LapsPermission' distinct from 'ACL' (gMSA/MSA/dMSA) — requires dedicated display branching
- SELF ACE detection: filter by IsInherited=False AND LAPS schema GUIDs; use Get-Acl "AD:" not nTSecurityDescriptor for reliable IsInherited flag in PS7
- FD plans must be regenerated at execution time if they contain late-resolved principals
- Group lookup by display name requires -Filter "Name -eq", not -Identity

## Windows LAPS Decryptor Integration (2026-07-15)

- ADPasswordEncryptionPrincipal GPO setting integrates proven Set-GPRegistryValue recipe
- Config shape: decryptorGroup (plain name), decryptorGpoName (explicit GPO name)
- Validation: 101 Pester tests pass, module imports v1.2.0 OK, parse clean
- 3 user decisions captured (per-tier isolation, root OU placement, placeholder convention)
- Lab NOT touched — ready for Joel's UAT

Status: READY FOR LAB VALIDATION — see decisions.md for details
