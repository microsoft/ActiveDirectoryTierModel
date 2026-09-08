# Decision: apply-path rows in the lab validation matrix

**Author:** Cyclops
**Date:** 2026-09-05T11:57:35+08:00
**Scope:** `.research\lab-validation\` only
**Status:** Implemented, not committed (Joel reviews manually)

---

## 1. Withdrawn claim

The lab-validation README previously stated that `-ConfirmApply` **"cannot be automated"**
because both of Deploy's confirmation gates use `Read-Host`.

**That statement was false and has been withdrawn.** The repository already contained a working
pattern — `.research\copilot-cli-hyperv-ad-lab\scripts\Invoke-AutoConfirmDeploy.ps1`, which
defines a `function global:Read-Host` returning `'Y'`. It was missed because it lives in a
different `.research\` subfolder.

**Team-relevant lesson:** a false "cannot" in a README actively stops other people from looking.
Before declaring something impossible, search the whole `.research\` tree.

## 2. Decision

An **opt-in, mutating** apply-path phase is added to `Invoke-LabValidationMatrix.ps1` behind a
new `-IncludeApplyPaths` switch. Five rows, all with `-EnableVerbose -EnableDebug`:

1. `-OuOnly -ConfirmApply`
2. `-GroupOnly -ConfirmApply`
3. `-FullDeployment -ConfirmApply`
4. `-FullDeployment -ConfirmApply` + every `-Include*`/`-Enable*` (two gates)
5. `Audit -FullDeployment` — the post-apply **compliant** path, always last

**The default invocation is unchanged and remains non-mutating**, and that is now *asserted*
by a matrix-level `Run was non-mutating` check rather than merely stated.

## 3. Why it matters to the team

These rows are the **only** coverage anywhere for:

- the ~33 `-ErrorAction Stop` catch blocks added for BUG-019 — `tests\helpers\ADStubs.ps1`
  L88-L104 accept `-ErrorAction` and **never throw**, so the green Pester suite exercises none
  of them;
- the real OU / group / ACL write paths;
- **Audit's COMPLIANT branch** — every plan-only audit run only ever sees the
  everything-missing domain.

## 4. Technical decision that other agents must not "simplify"

The `global:Read-Host` override lives **inside the generated child runner**, not in the harness.

The harness launches every row in a separate `pwsh` process (`Start-Process -File`). A `global:`
function in the parent **cannot cross a process boundary**. `Invoke-AutoConfirmDeploy.ps1` puts
the override in the parent, which is correct *for that helper* because it runs Deploy in its own
process. Moving it to the parent here would be silently useless and would hang every apply row.

Do not relocate it. Do not "tidy" it into the harness body.

## 5. Ordering is a correctness requirement

Apply rows are stateful. Ordering is explicit (`ApplyOrder`) and enforced by
`Assert-ApplyOrdering`, which refuses to start a run where apply rows are not contiguous-and-last,
where `-GroupOnly` precedes `-OuOnly`, or where the post-apply Audit is not the final row.
It survives `-RowId` filtering — proven by feeding the ids in reverse.

## 6. Correction to an earlier documented assumption (affects anyone reading the harness)

The harness documented that "a timeout is the signature of an unexpected `Read-Host`".
**Measured and false.** Under `-NonInteractive`, `Read-Host` throws
`"PowerShell is in NonInteractive mode. Read and Prompt functionality is not available."`
and the child can still **exit 0**. A new per-row check, `No unanswered Read-Host prompt`,
asserts that string is absent on **every** row.

Related: exit code alone cannot distinguish an applied run from a **declined** one — Deploy's
gates `exit 0` on any answer other than `'Y'`. Content assertions are mandatory.

## 7. Lab operating requirement

Apply rows require the DC to start from the **`WinLapsSchema`** checkpoint, and the domain
**must be rolled back afterwards**:

```powershell
.\Restage-Lab.ps1 -CheckpointName WinLapsSchema `
                  -ConfigPath <path-to>\copilot-cli-hyperv-ad-lab\scripts\lab-config.json
```

`-ConfigPath` **must** be passed explicitly. `Restage-Lab.ps1`'s default resolves to the *parent*
of `scripts\`, and a `lab-config.json` exists in both locations — so the wrong one is picked up
silently rather than erroring.

## 8. Evidence

| Script (`.research\lab-validation\proof\`) | Result |
|---|---|
| `Prove-ReadHostOverride.ps1` | 7/7 — override reaches both gates through the real child-process model, incl. a nested-function gate; negative control fails without it; no leak into plan-only runners |
| `Test-ApplyPathRows.ps1` | 12/12 — real harness vs stub Deploy/Audit: default stays non-mutating, 5 apply rows added and all pass, both gates of the `-EnableAuditing` row answered, `Mode = EXECUTION` logged, Audit compliant branch reached, ordering enforced from reversed input, declined deployment FAILED |

Neither script contacts Active Directory, Hyper-V, or the lab VM.

## 9. Explicitly still unproven

The override is proven against a **stub** that mirrors Deploy's gates, not against the real
`Deploy-TierModel.ps1` on the lab. The override *mechanism* is proven; what a lab run would add
is confirmation that the real script reaches its gates by no path a stub fails to model.
