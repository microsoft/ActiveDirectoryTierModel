# Decision — v2.1.0 lab validation run (Cyclops, 2026-09-05)

## Checkpoint ordering — decided and executed

**The brief's premise was false.** `AuthSilo-Lab` exists on `TierLab-Client`,
`TierLab-PAW` and `Tierlab-Server` — but **not on `TierLab-DC01`**. The DC had only
`DC-Promoted-Clean` and `WinLapsSchema`. Joel's standing instruction to leave the
lab on `AuthSilo-Lab` was not executable on the DC as written.

Decision: **build the AuthSilo-Lab state rather than restore it**, in two invocations:

1. **RUN 1** — restage to `WinLapsSchema`, then run all 50 non-drift rows including
   `-IncludeFailurePaths` and `-IncludeApplyPaths`. The apply rows deploy the full
   Tier Model plus every `-Include*`/`-Enable*`, which *is* the AuthSilo-Lab state.
2. **RUN 2/3** — drift rows against that end-state, because the `-IncludeAuthSilos`
   and `-IncludeWinLaps` rows need the policy, silo and decryptor GPO to EXIST
   before drift can make them look missing.

Two invocations are required because the harness sorts Drift rows BEFORE Apply rows
within a single run, which is the wrong order for exactly these rows.

At the end I **created an `AuthSilo-Lab` checkpoint on `TierLab-DC01`** and left the
lab there, so the standing instruction becomes executable in future.

## WI-18 / D9 — the `-Verbose` gap. RECOMMEND: DOES NOT CLOSE. It is real work.

Measured, not reasoned. Four rounds; three were thrown away as void.

Instrument proven in both directions before any product claim was made:
* preference-only `Write-Verbose` direct = 1 record, inside an advanced function = 1
  (the capture CAN see preference-driven output);
* explicit `-Verbose` on an AD write = 1 record (the capture CAN see ShouldProcess
  messages);
* no preference and no `-Verbose` = 0 (the capture does NOT manufacture records).

Results:

| Arm | Mechanism | Records naming the DN |
|---|---|---|
| AD1 | explicit `-Verbose`, write SUCCEEDS | **1** |
| AD2 | preference only, write SUCCEEDS | **0** |
| AD3 | explicit `-Verbose`, write FAILS *after* resolution | **1** |
| AD4 | preference only, write FAILS *after* resolution | **0** |
| AD5 | explicit `-Verbose`, write FAILS *at* resolution (no such DN) | **0** |
| L3 | preference only, hand-written `$PSCmdlet.ShouldProcess` | **0** |
| L4 | preference only, `New-Item` | **0** |

Captured record text:

    VERBOSE: Performing the operation "Set" on target "OU=CyclopsR4Ok,DC=tierlab,DC=internal".
    VERBOSE: Performing the operation "Remove" on target "OU=CyclopsR4Protected,DC=tierlab,DC=internal".

**Answer to Q1: NO.** `$VerbosePreference = 'Continue'` alone produces ZERO
ShouldProcess records from AD write cmdlets. This is not specific to the AD module —
a hand-written `ShouldProcess` and `New-Item` behave identically. The preference
variable governs `Write-Verbose`; it does not turn on ShouldProcess descriptions.

**Answer to Q2: NO under the preference, YES under explicit `-Verbose` — but only
for one failure shape.** AD3 shows explicit `-Verbose` DOES name the DN when the
object resolved and the write was refused. AD5 shows it does NOT when the object
does not exist, because the failure precedes ShouldProcess.

**This partially contradicts the brief.** The brief states earlier POC work
established that explicit `-Verbose` yields a DN-naming record "even when the
operation fails". That holds only for post-resolution failures. For "not found" —
the commonest audit/drift case — there is no record with or without `-Verbose`.

**Answer to Q3: confirmed, nothing to gain.** `GroupPolicy` is `ModuleType = Script`,
`New-GPO` is a `Function` (proxy), and a `WinPSCompatSession` PSSession is present.
`New-GPO -Verbose` measured **0** records, as did preference-only. All three
predictions in the brief were correct.

**Recommendation.** WI-18/D9 does **not** close as unnecessary. There is a real,
measured diagnostic gap: the product's 216 AD/GPO call sites emit no target-naming
verbose record at all. But the value is narrower than assumed — it buys the DN only
on post-resolution write failures, and nothing on GroupPolicy. Scope the work to AD
**write** call sites and expect no benefit on the GroupPolicy side. No product code
was changed.

## Fixture defect (mine, `.research\lab-validation\`, not a product bug)

`New-LabDriftFixture.ps1` drifts the auth policy and silo by **rename**. AD refuses:
`A system flag has been set on the object and does not allow the object to be moved
or renamed.` Deletion is also refused until `ProtectedFromAccidentalDeletion` is
cleared. The offline proof used stubs and could not have caught this.

Two changes needed:
1. Replace the rename mechanism for `AuthPolicyRename` / `AuthSiloRename` with
   clear-protection-then-delete, snapshotting enough state to redeploy on revert.
   Verified in-lab that this works and that `Deploy -IncludeAuthSilos -ConfirmApply`
   correctly recreates both objects.
2. The fixture's exit 2 is all-or-nothing. 6 of 8 components staged and every
   precondition was met, yet all seven rows were marked unstaged. Exit code must
   distinguish "a component failed" from "the profile's preconditions are unmet".

## Rule to keep

An offline proof over stubs cannot validate a **mutation mechanism**. It validates
assertions. Any fixture component that writes to AD needs one cheap in-lab staging
smoke test before the matrix depends on it — 54/54 green offline told me nothing
about whether the directory would accept the write.
