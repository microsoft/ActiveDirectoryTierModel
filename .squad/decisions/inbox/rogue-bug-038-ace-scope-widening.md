# BUG-038 — Silent ACE scope widening on `inheritedObjectType` resolution failure

**Author:** Rogue (Core Developer)
**Date:** 2026-09-05
**Severity:** Security — silent privilege escalation, invisible to the audit
**Files:** `New-TierModelOuAcl.ps1`, `Get-TierModelOuAcl.ps1`, `Get-TierModelOuAclFd.ps1`, `Test-TierModelOuAcl.ps1`
**Status:** Implemented, verified, uncommitted

## I agree with the reviewer's reading. Both claims verified, not reasoned.

### Claim 1 — `[Guid]::Empty` on `inheritedObjectType` means "all classes"

Verified against .NET directly rather than from memory:

```
A: inheritedObjectType = bf967aba-… → ObjectFlags = InheritedObjectAceTypePresent
B: inheritedObjectType = Guid.Empty → ObjectFlags = None
```

`ObjectFlags = None` means the `InheritedObjectAceTypePresent` bit is **not set**, so the ACE
carries no class restriction at all and applies to every child object class. The framework
itself reports the widening; it is not an inference.

### Claim 2 — the audit self-blinds

Confirmed in code. The audit derives its **expectation** through the same fallback it uses to
read reality:

```powershell
$inheritedObjectTypeMatches = if ($inheritedObjectTypeGuid -ne [Guid]::Empty) {
    $ace.InheritedObjectType -eq $inheritedObjectTypeGuid
} else {
    $ace.InheritedObjectType -eq [Guid]::Empty -or $null -eq $ace.InheritedObjectType
}
```

A failed resolution sets the expectation to `Guid.Empty`, and the `else` branch then matches
**precisely the over-scoped ACEs** a failed resolution produces on the write path. Expectation
and reality are widened by the same bug, so they agree, and the audit certifies an escalated
delegation as compliant.

### One consequence beyond the reviewer's reading

In `Get-TierModelOuAcl` the same match drives `$existingAcl`, and a match sets
`$needsApplication = $false`. So the planner did not merely risk emitting a broad ACE — on
finding an over-scoped ACE it concluded *"ACL delegation already exists with exact match"* and
**planned no remediation**. The tool actively declined to repair the escalation it had caused.

### One claim I checked and could NOT support

I looked for a second, non-exception widening path — a resolver returning empty without
throwing, which no catch-block fix would reach. It does not exist:
`Resolve-DomainSpecificGuid` throws on every failure path (L99, L135, L148), and
`Resolve-TierModelGuid`'s only non-throwing empty return (L68) is the **deliberate**
`AllObjectClasses` / empty-value case. The reviewer's catch-block framing is complete.

## The fix, and why the codebase already answered the "fail outright?" question

The MSA/gMSA/dMSA write paths **already** treat this as fatal, with an explicit message:

> `Resolved inheritedObjectType GUID for '…' is Guid.Empty. Aborting ACL application to prevent an over-scoped ACE.`

backed by tests named *"Fails safely when inheritedObjectType resolves to Guid.Empty"*. The OU
family was the inconsistent one. So this is not a new policy — it is applying the existing one.

| Site | Path | Before | After |
|---|---|---|---|
| `New-TierModelOuAcl` L146 | write | `Write-Warning`, then writes a WIDE ACE | **throws**, MSA wording, before any write |
| `Get-TierModelOuAcl` L220 | plan | silent | logs `Warning`; match **fails closed** |
| `Get-TierModelOuAclFd` L196 | plan | silent | logs `Warning`; match **fails closed** |
| `Test-TierModelOuAcl` L239 | audit | silent | logs `Warning`; match **fails closed** |

`Guid.Empty` is ambiguous — it is both *"no restriction, by design"* and *"resolution failed"*.
The three read paths now carry `$inheritedObjectTypeUnresolved` so the two can never be
conflated. Logging matches the sibling `objectType` precedent at `Get-TierModelOuAcl` L112,
which already logged; only `inheritedObjectType` was silent.

## Over-fixing guard — 5 of 6 behaviours unchanged

| Case | BEFORE | AFTER | Correct |
|---|---|---|---|
| resolution FAILS, ACE WIDE (the escalation) | **compliant** | drift | drift |
| resolution FAILS, ACE narrow | drift | drift | drift |
| resolves OK, ACE matches | compliant | compliant | compliant |
| resolves OK, ACE WIDE | drift | drift | drift |
| no restriction configured, ACE wide | compliant | compliant | compliant |
| no restriction configured, ACE narrow | drift | drift | drift |

**BEFORE: 1 wrong verdict. AFTER: 0. Exactly 1 of 6 cases changed** — the escalation. The
legitimate `Guid.Empty`-by-design behaviour is untouched, which is the guarantee that matters:
15 delegations in `tiermodel-acls.json` declare `inheritedObjectType`.

## Verification

Parse 0 on all four files. Unit **1572/1**, Integration **318/0** — the single failure is
BUG-037's test, not this fix (see that record).
