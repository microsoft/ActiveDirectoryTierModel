# Decision note - lab topology source of truth, pre-flight guards, and text-artifact encoding

**From:** Cyclops (Test/Validation)
**Date:** 2026-09-05
**Trigger:** Joel's live lab run of the frozen validation harness - all 41 rows failed.
**Scope of change:** `.research\lab-validation\` only. Nothing committed.

---

## 1. Lab topology values come from `lab-config.json`, never from hardcoded defaults

`Invoke-LabValidationMatrix.ps1` defaulted `-PreferredDc` to `TierLab-DC01`. That is the
**Hyper-V VM name**. The DC's OS hostname is `DC01` (`DC01.tierlab.internal`), and the VM name
does not resolve in DNS. Every row failed at Deploy's prerequisite gate.

`.research\copilot-cli-hyperv-ad-lab\scripts\lab-config.json` already distinguishes them:

```json
"vm": { "hyperv_name": "TierLab-DC01", "hostname": "DC01" }
```

**Decision.** Any tooling that needs lab topology reads it from `lab-config.json`. Hardcoding
duplicates a value the config owns and is precisely what allowed the drift. The harness now
resolves `vm.hostname`, reports which source it used, and **rejects** the `hyperv_name` value
with a message naming the correct one.

**Caveat for everyone:** `lab-config.json` is **git-ignored**, so it is absent whenever a script
is copied to the DC on its own. Tools must tolerate its absence, fall back, and say loudly that
the value is a guess. Silent fallback is how this defect would recur.

**Related, unfixed, not mine:** `Restage-Lab.ps1`'s default `-ConfigPath` resolves to the
*parent* of `scripts\`. Both `lab-config.json` copies exist, so the wrong one is picked up
**silently**. Always pass `-ConfigPath <scripts>\lab-config.json` explicitly.

## 2. Environmental preconditions get a row-zero guard that aborts the run

The harness ran 41 child processes to discover one environmental fact 41 times. Every verdict
was correct; the output was still useless, and it cost ~10 minutes of lab time.

**Decision.** A precondition that would invalidate every row is checked **before** row one and
aborts the run. In this harness that is a DNS resolve plus a raw TCP 389 probe (~2 s),
deliberately not `Get-ADDomain` so it works before and independently of the ActiveDirectory
module. Escape hatch: `-SkipDcPreflight`. Proven by the **absence of any row output**, not by
exit code.

I suggest this as a general expectation for lab tooling, not just mine.

## 3. Human-readable text artifacts are written with a UTF-8 BOM

The em-dash in Deploy's re-run hint rendered as `â€”` in `capture.tsv`. Root cause, measured on
the bytes: the file contained `E2 80 94` - **correct UTF-8** - but had **no BOM**, so
ANSI-defaulting readers mis-decoded it. The bug was in the read, not the write.

**Decision.** Harness artifacts intended for humans (`capture.tsv`, `harness.log`,
`matrix-detail.txt`, `matrix-results.csv`) are written UTF-8 **with BOM**.
`matrix-results.json` stays BOM-less, since a BOM trips strict JSON parsers.

**`Deploy-TierModel.ps1` was not changed and is not at fault.** Its em-dash is correct on disk
and survives the pipeline intact. No product text needs replacing.

## 4. Standing lesson: verify the input, not only the output

Three of the four defects found in this harness were cases where the harness measured correctly
but was fed something wrong. Checks have been reliable; preconditions have not. Pre-flight
validation of inputs is now part of the harness design rather than an afterthought.

## 5. Evidence

`proof\Prove-DcPreflight.ps1` - 14/14 assertions. Full suite: 7/7 + 12/12 + 14/14.
No lab VM contact; the only network activity is a DNS lookup of an RFC 2606 `.invalid` name.
