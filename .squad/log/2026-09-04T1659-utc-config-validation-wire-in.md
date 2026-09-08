# Session Log: Config Validation Wire-In (BUG-020..023)

**Date:** 2026-09-04  
**Branch:** fix/gpo-silent-skip-and-false-success  
**Outcome:** 4 bugs fixed, 1,573 unit tests pass, 318 integration tests pass. Lab validation: TierLab-DC01 deployment succeeded.

## Summary

- **BUG-020:** `Test-TierModelConfig -Scope` vocabulary mismatch — retired scope names caused an unmatched scope to fall through and return `Valid=True`, silently skipping validation. Fixed in `TierModel.psm1`: renamed branches, `GposOnly` added to both GPO gates, `ValidateSet` added so a mismatch now fails at parameter binding → shipped
- **BUG-021:** Two diagnostic messages asserted the compatibility shim as a proven cause; one advised running under PowerShell 5.1 which both scripts hard-block. Affected `Resolve-TierModelPrincipalSid.ps1` AND `Test-TierModelPrerequisites.ps1` → shipped
- **BUG-022:** `Test-TierModelConfig` had zero production callers, so all schema hardening was unreachable in a real run. Fixed by wiring validation into Deploy (three mutually exclusive branches, no silent path) and Audit — which also fixed Audit's genuine false success where a thrown validation left `$configValidation` null and printed a green "Configuration validation passed." → shipped
- **BUG-023:** All schema validation was gated on `ParameterSetName -eq 'FromPath'`; Deploy and Audit call `-Config`, so required-property checks and `_validateArrayItems`' six call sites never ran. Fixed so `FromConfig` loads the schema; a missing or unparseable schema now fails closed (`Valid=false`) → Rogue fixed, Wolverine tested

## Key Decisions

- Silent GPO failure root cause: CLOSED and UNKNOWN (motivation for observability, not root-cause attribution)
- Parameter naming: -EnableVerbose / -EnableDebug (leaves built-in -Debug free)
- Deploy blocks on config validation failure; Audit warns and continues
- BUG-019 deferred to verbose/debug feature branch

## Handoff

Rogue/Wolverine/Cyclops completed all assigned work with verification. Beast's BUG-022 edit was reported complete but never reached disk; Cyclops wrote the corrected entry from scratch.

Orchestration logs written to .squad/orchestration-log/.