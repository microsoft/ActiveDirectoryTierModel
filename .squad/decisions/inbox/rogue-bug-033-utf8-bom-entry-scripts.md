# BUG-033 — UTF-8 BOM on the two entry scripts

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05
- **Status:** Implemented, awaiting review
- **Scope:** `Deploy-TierModel.ps1`, `Audit-TierModel.ps1` — BOM prepended, nothing else re-encoded
- **Branch state:** uncommitted; HEAD `04ab664`

## Problem

Both entry scripts were **UTF-8 without a BOM** and contain non-ASCII characters (76 in Audit,
180 in Deploy — em-dashes, `§`, and the `✅ ❌ ⚠ ⛔ ⏭` status glyphs). Windows PowerShell 5.1
decodes a BOM-less file as ANSI/Windows-1252, mangling those bytes and derailing the parser
**on characters inside comments**.

Consequence: on PowerShell 5.1 neither script parsed, so **not one line executed** — including
the PowerShell-version fail-fast gate whose entire job is to tell a 5.1 operator to use
PowerShell 7. The operator instead got `Missing closing '}'` pointing at *valid code*, blaming
braces for an em-dash. No console guidance, no log, no remediation.

## Change

Prepended the 3-byte UTF-8 BOM (`EF BB BF`) to both files. **Nothing else was altered** — no
re-encoding, no line-ending changes, and deliberately no "cleanup" of the em-dashes or glyphs.
The characters were never the defect; the missing BOM was.

## Verification

**1. Content preserved byte-for-byte.** SHA-256 of each file with the 3 leading bytes stripped,
compared against the pre-change hash:

| File | Pre-change SHA-256 | Stripped hash matches |
|---|---|---|
| `Audit-TierModel.ps1` | `8CAEBECD…2A1F1225` | **True** |
| `Deploy-TierModel.ps1` | `4F9AFBA0…275D79EB` | **True** |

Byte counts grew by exactly 3 (129583→129586, 203256→203259).

**2. PowerShell 7 parse (regression check):** Audit **0**, Deploy **0**.

**3. Real PowerShell 5.1 parse (5.1.26100.9278):** Audit **0**, Deploy **0** — was 2 and 16.

**4. End-to-end on the real 5.1 engine.** Both scripts now reach the gate, print the correct
guidance, and — because of the version-gate reorder done in the previous task — **persist it**:

```
[Error] FAIL-FAST (terminal): Deploying and Auditing of the Tier Model requires PowerShell 7.x or later. Current version: PowerShell 5.1.26100.9278
  FailFast=True Terminal=True Script=Audit-TierModel.ps1
  Remediation: Run the Tier Model from a PowerShell 7 (pwsh) console. ...
```

Deploy produces the equivalent record. Confirmed for both.

**5. Suites (by path):** Unit **1573/1573/0**; Integration **318 total, 315 passed, 3 failed** —
the same three BUG-031 tests, no new failures.

**6. BOM survived subsequent edits.** I re-verified the BOM and the 5.1 parse **after** making
the normaliser changes below, because an editor that rewrites a file can silently drop it. Both
still `BOM=True`, both still parse `0` on 5.1. **This is the regression to re-check after any
future edit to these two files.**

## Measurement artifact worth recording

My first 5.1 end-to-end run reported `log files: 0` and looked like a product bug. It was my
own harness: `... | Select-Object -First 10` **stops the pipeline**, which killed the child
`powershell.exe` before it flushed the log. Re-running without `-First` produced the record.
**Never pipe a child-process run through `Select-Object -First N` when the thing being measured
is a side effect that happens near the end of the process.**

## Note

Two independent CI blind spots let this survive (both found by Joel, both in files I must not
edit): PSScriptAnalyzer's `PSUseBOMForUnicodeEncodedFile` is in the exclusion list at
`.github/workflows/ci.yml` L52, **and** CI only scans `-Path "modules/TierModel"`, so the two
entry scripts are never analysed at all. 83 other tracked files also lack a BOM, but they load
after the gate and are out of scope here.
