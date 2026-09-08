# Audit's PowerShell-version gate can now log — plus a material new finding (encoding)

- **Author:** Rogue (Core Developer)
- **Date:** 2026-09-05
- **Status:** Implemented (reorder) + **new defect reported, not actioned** (encoding)
- **Scope:** `Audit-TierModel.ps1` only
- **Branch state:** uncommitted; HEAD `04ab664`

## Part 1 — the reorder (done)

Joel overruled my earlier deferral, reasoning that Deploy already resolves its log path
before its version gate and has shipped that way, so aligning Audit adds no new risk. I
accept that and have implemented it.

**What moved:** only the version gate itself — a single 11-line `if` block. No
initialisation was reordered, which is the safer direction than moving the ~90-line logging
block upward as originally framed.

**New ordering in Audit:**

| Line | Item |
|------|------|
| L524 | `$script:LogFilePath = $null` |
| L566 | `$script:LogFilePath = Join-Path $script:LogDirectory $logFileName` |
| **L579** | **PowerShell version gate** |
| later | diagnostics/transcript block, then `Import-Module` |

The gate stays **before** the diagnostics/transcript block and before `Import-Module`, so
strictly less work runs on an unsupported PowerShell than in Deploy today.

### Control experiment

Two control copies at repo root, **both asserted to parse (0 errors) before being trusted**,
with the gate threshold forced to `-lt 999` so it fires on PowerShell 7.

- **PRE-FIX** (gate in its original position, ahead of log-path resolution) — verified by
  line numbers that the earlier gate is the one that fires:
  ```
  CONSOLE: full failure message + remediation printed
  PRE-FIX log files produced: 0
  ```
- **POST-FIX** (current file):
  ```
  CONSOLE: identical output
  log files: 1 ; entries: 1
    [Error] FAIL-FAST (terminal): Deploying and Auditing of the Tier Model requires PowerShell 7.x or later. Current version: PowerShell 7.6.5
  ```

Console-correlated, `Error` level, `FAIL-FAST (terminal)` prefix. Both control copies deleted
afterwards.

## Part 2 — **NEW FINDING: neither script can reach its version gate on PowerShell 5.1**

Joel invited me to stop and report a concrete hazard. I did not find one that blocks the
reorder, but I found something more important while looking, and I am reporting rather than
acting.

**Both scripts fail to *parse* under Windows PowerShell 5.1, so the version gate never
executes there at all — in Deploy either.**

Measured with the real 5.1 engine (`powershell.exe`, 5.1.26100.9278):

```
PS 5.1 parse errors in Audit:  2
PS 5.1 parse errors in Deploy: 16
```

Running them under 5.1 gives the operator a raw `ParserError` / `MissingEndCurlyBrace`, not
the friendly "requires PowerShell 7.x or later" message, and no log.

**Cause — and it is *not* PowerShell 7-only syntax.** Both files are **UTF-8 without a BOM**
(first bytes `3C 23 0D`), and contain non-ASCII characters — 76 in Audit, 180 in Deploy:

```
️ — § ⏭ ⚠ ⛔ ✅ ❌
```

Windows PowerShell 5.1 decodes a BOM-less file as ANSI/Windows-1252, so an em-dash inside a
**comment** becomes `â€”` and derails the parser. The reported error lines are cascades that
land on innocent comment lines:

- `DEPLOY L696: The '<' operator is reserved for future use.` — a `#` comment containing `<file>`
- `DEPLOY L703: Variable reference is not valid.` — a `#` comment containing an em-dash
- `AUDIT L1124/L1268: Missing closing '}'` — cascade

### What this means

- The reorder is still **correct and worth having**, but its practical effect is narrower
  than assumed: it fixes the gate's logging on **PowerShell 6.x**, where Audit parses. On
  5.1 nothing in either script runs.
- Deploy's version gate — cited as the proof that this pattern works — is **also**
  unreachable on 5.1 for the same reason.
- Since PowerShell 5.1 is explicitly unsupported, one could argue a parse error is an
  acceptable outcome. I disagree that it is a *good* one: the release exists to make
  failures legible, and this is the least legible failure in the product.

### Recommendation — Joel's call, I have not acted

Adding a UTF-8 BOM to both scripts would make them parse on 5.1 and let the gate deliver its
message and its log record. I did **not** do it, because changing file encoding:

- touches the whole file rather than a few lines, which conflicts with hand review;
- may interact with other tooling, signing, or CI expectations;
- is outside the spirit of the surgical edits authorised so far.

The alternative — replacing all non-ASCII glyphs with ASCII — would be a large, cosmetic,
and behaviourally visible change to console output. I do not recommend it.

**Please add this to `docs/known-bugs.md`; I have not edited that file.**
