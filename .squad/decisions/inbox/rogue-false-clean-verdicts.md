# Decision: "Could not verify" must never render as "compliant"

- **Date:** 2026-09-05
- **Agent:** Rogue (Core Dev, PowerShell/AD)
- **Requested by:** Joel Platek (rubber-duck review of the full `feature/enable-verbose-debug` diff)
- **Status:** Implemented, uncommitted, awaiting review
- **Related:** BUG-019, BUG-024, BUG-025

## Context

A review of the full diff produced six findings. Two were blocking. Both blocking findings, plus
one non-blocking one, are the **same defect class**: a read that failed was reported to the operator
as a clean result. The test suite was green before and after every one of these fixes.

## Decisions

### 1. A not-found heuristic is only legal where the call can actually produce not-found

BUG-019 introduced `try/catch` around read sites, discriminating "does not exist" from "read
failed" via `$isNotFound`. That discriminator was applied uniformly across sites — including three
`Get-GPO -All` enumerations and one `-Filter` search, **which have no not-found case at all**.

`Get-GPO` throws `[System.ArgumentException]` for an unreachable or invalid `-Server`. The
heuristic classified that as not-found and suppressed both the log entry and the console warning,
so a genuine enumeration failure produced `$null` and deployment planning would plan a create for
a GPO that already exists — with no log entry and no warning. That is the original customer symptom
class, reintroduced by its own fix.

**Rule adopted:** the discriminator is chosen by the *parameter set*, not the cmdlet.

| Call shape | Not-found is... | Catch may discriminate? |
|---|---|---|
| `Get-GPO -Name` | an exception | **yes** — heuristic is correct |
| `Get-GPO -All` | an empty collection | **no** — every exception is a real failure |
| `Get-ADObject -Filter` | an empty collection | **no** — branch is dead code |

Heuristic removed at `Get-TierModelGpo.ps1` (2 sites), `Get-TierModelGpoFd.ps1`,
`Resolve-TierModelPrincipalSid.ps1`. Retained at `New-TierModelGPOLink.ps1` and
`Update-TierModelGPOConfig.ps1`, which are `-Name` lookups.

### 2. Unverified is a third state and must feed the verdict

`Test-TierModelOu.ps1` recorded a read failure as a `Type='Error'` finding but incremented neither
counter feeding `$driftCount`. An unreadable Tier 0 OU therefore produced `DriftCount = 0`, a
"compliant" console verdict, and a `0` copied into `Audit-TierModel.ps1`'s summary.

Introduced `$unverifiedCount`, surfaced as its own summary line and its own `UnverifiedCount`
summary property, and added into `$driftCount` at **both** computation sites.

It is deliberately **not** folded into `$mismatchCount`: a mismatch is a known state, an unverified
OU is an unknown one, and collapsing them would tell the operator we checked something we did not.

The **outer** per-OU catch had the identical gap and was fixed too, though it was outside the
stated brief — a half-fixed false-clean is still a false-clean.

### 3. A warning is not a verdict

Both callers of `Invoke-CanonicalAclAudit` caught its hard-stop, printed a yellow warning, and
continued **without incrementing `$auditSummary.ErrorCount`**. The entire canonical-ACL phase could
vanish from the audit while the summary still reported success. Callers now increment `ErrorCount`
and state explicitly that compliance is **unknown, not compliant**.

## Rationale

A false "not protected" makes an operator look. A false "compliant" removes their reason to. When
a check cannot complete, the only safe rendering is one that demands attention.

## Consequences

- **Audit verdict numbers change** when a read fails: previously `0`, now non-zero. This is the
  intended correction. Confirmed by grep that **no test asserted the old behaviour** before making
  the change.
- Deployment planning can no longer silently plan a create off a failed enumeration.
- Runtime-proven: read failure now yields `Total=1 Unverified=1 Drift=1` (was `Drift=0`); the
  healthy path is unchanged at `Total=1 Unverified=0 Drift=0`.
- Unit 1573/0 and Integration 318/0 — unchanged, **and that is the finding**: the suite was green
  across all of this in both directions. No test covers these paths.

## Open

`Test-TierModelOu.ps1`'s **outermost** catch still returns `TotalChecked = 0` / `DriftCount = 0`
when the whole audit fails, which is the same false-clean class at whole-function scope. Outside
the stated brief; raised for a decision rather than fixed unilaterally.
