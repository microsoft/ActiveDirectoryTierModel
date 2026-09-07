# SKILL: Deserialization-Safe Identity Checks in PowerShell 7

**Owner:** Cyclops (Architect & Reviewer)
**Established:** 2026-09-03T17:04:41+08:00
**Origin:** BUG-011 — Domain Admin false-fail under the WinPSCompat shim; blank SIDs in GPO `GptTmpl.inf`.

> **NOTE — 2026-09-04:** The shim-based deserialization hazard described below is
> **platform-dependent**. On Windows Server 2025 / PowerShell 7.5.1 (TierLab-DC01), both
> ActiveDirectory and GroupPolicy modules load natively (`CommandType=Cmdlet`); no
> WinPSCompatSession warning was emitted. The hazard may still apply on older RSAT
> management workstations where GroupPolicy is not Core-native. All rules in this skill
> remain valid — they defend against any platform where the shim is active, and Rules 1–5
> are independently sound regardless of shim presence. The skill is **not** being removed
> or weakened; it is being scoped to the platforms where it applies.

## The hazard

On platforms where the shim is active: under PowerShell 7, an RSAT module that is not
Core-native loads through the Windows PowerShell compatibility shim (`WinPSCompatSession`).
Every object crossing that boundary is **deserialized**:

- `.SID` / `.objectSid` / `.DomainSID` come back as `System.String`, not `SecurityIdentifier`.
- A `String` has no `.Value` property, so `$obj.SID.Value` silently yields **`$null`** — no error.
- Comparing a deserialized SID to a live `SecurityIdentifier` (`$_.SID -eq $identity.User`) is
  **always `$false`** — no error.

Both failure modes are silent. The first writes blank principals into security policy. The second
denies a legitimately privileged operator.

## Rules

### 1. Decide privilege from the local token, never from a directory query

```powershell
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$accountDomainSid = $currentUser.User.AccountDomainSid
if ($null -eq $accountDomainSid) { <# well-known/local principal: fail closed, do not throw #> }
$isDomainAdmin = [bool]($currentUser.Groups.Value -contains "$($accountDomainSid.Value)-512")
```

Pure .NET. Zero module calls. Immune to deserialization. Reflects **effective** nested membership,
so no `-Recursive` query is needed. Works for any RID: 512 Domain Admins, 519 Enterprise Admins,
518 Schema Admins, 516 Domain Controllers.

`AccountDomainSid` is the *machine* SID on a workgroup box (not null) — it is null only for
well-known principals such as `S-1-5-18`. Null-check it explicitly; never let it throw.

### 2. Normalise every "SID-ish" value through one validating helper

Accept all shapes, validate, and **throw** rather than return empty:

```powershell
# SecurityIdentifier -> .Value | String -> itself | byte[] -> ctor | PSObject -> .Value else ToString()
# then: reject null/whitespace, match ^S-1-\d+(-\d+)+$, round-trip through
# [SecurityIdentifier]::new($candidate), and return the validated string.
```

A validating normaliser makes the deserialized shape *work* as a bonus, but its real job is that a
blank can never leave the function.

### 3. Never read a SID inside a swallowing catch

This is the trap that hides the whole class of bug:

```powershell
# WRONG - a blank SID is indistinguishable from "lookup failed", so it degrades silently
try { $u = Get-ADUser -Identity $p -ErrorAction Stop; return @{ Sid = $u.SID.Value } } catch { }
```

Split it: the **lookup** may fail silently and fall through to the next strategy; the **SID read
and validation** must sit outside the swallowing catch so a malformed value propagates loudly.

### 4. Fail loudly beats fail silently — always, for security-config data

Anything feeding User Rights Assignment, Restricted Groups, ACLs or SDDL must hard-fail on an
unresolvable principal. A hard stop is recoverable; a policy applied with blank principals is a
silent security-configuration failure that looks like success.

### 5. Never rely on a single upstream guard

A prerequisite/preflight guard is necessary but is a single point of failure — it can be skipped,
bypassed, or its probe can miss the condition. The consuming function must be safe on its own.
Defence in depth is a structural requirement, not a nicety.

### 6. Detecting the shim (platform-dependent)

```powershell
$probe = Get-ADDomain -Server $dc -ErrorAction Stop
if ($probe.DomainSID -is [string]) { <# deserialized: compat shim is active #> }
```

> **NOTE — 2026-09-04:** On Windows Server 2025 / PowerShell 7.5.1 this probe returns a
> live `SecurityIdentifier`, so `$probe.DomainSID -is [string]` evaluates `$false` and the
> shim is not detected — because on that platform it is not active. The probe remains
> correct as a defence against older RSAT platforms; it should **not** be removed.

Pair it with `-SkipEditionCheck` on every `Import-Module` of an RSAT module so PowerShell 7 loads
a Desktop+Core module (RSAT `1.0.1.0`) natively instead of shimming it. On a genuinely
Desktop-only module the import then fails clearly instead of degrading silently.

## Preserving the test contract while replacing a check

When a fragile check sits inside an `if/elseif` chain whose branches each emit distinct
remediation text, do **not** collapse the chain. Lift the new authoritative check out and run it
first; demote the old chain to *environment classification* that only selects remediation wording.
The security verdict becomes robust, the operator diagnostics stay rich, and existing assertions
keep passing.

## Review checklist

- [ ] No `.SID.Value` / `.objectSid.Value` / `.DomainSID.Value` read without a validating normaliser.
- [ ] No `-eq` comparison between a directory-returned SID and a live `SecurityIdentifier`.
- [ ] Privilege verdicts come from the token, not from `Get-AD*Member`.
- [ ] `AccountDomainSid` null case handled explicitly, fails closed, does not throw.
- [ ] SID reads are outside swallowing `catch` blocks.
- [ ] `-SkipEditionCheck` on every RSAT `Import-Module`.
- [ ] Catch blocks surface the real exception message, never a hardcoded substitute cause.
