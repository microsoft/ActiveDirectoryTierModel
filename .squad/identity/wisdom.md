---
last_updated: 2026-07-31T04:20:00.000Z
---

# Team Wisdom

Reusable patterns and heuristics learned through work. NOT transcripts — each entry is a distilled, actionable insight.

## Patterns

<!-- Append entries below. Format: **Pattern:** description. **Context:** when it applies. -->

**Pattern:** The Hyper-V AD test lab is fully defined under `.research/copilot-cli-hyperv-ad-lab/`. Read `lab-config.json` for the single source of truth: VM `TierLab-DC01` (English) / `TierLab-German-DC01` (German), domain `tierlab.internal` (`TIERLAB`), the `Administrator` credential, guest deploy path `C:\TierModel`, and the `DC-Promoted-Clean` baseline checkpoint (ADR-0011). The lab scripts default `-ConfigPath` to their own folder but `lab-config.json` lives one level up, so pass `-ConfigPath ..\lab-config.json`. Run end-to-end tests with `scripts/Start-LabAndDeploy.ps1` (starts VM, waits for AD, copies host repo → guest, deploys), `scripts/Invoke-LabAudit.ps1`, and `scripts/Reset-Lab.ps1` (restore baseline). **Context:** Any time DC/lab testing, credentials, or VM details are needed — consult these files first; never ask the user for lab details that already live here.

**Pattern:** Two clean checkpoints exist for `TierLab-DC01`. `DC-Promoted-Clean` is a bare clean DC with **no** Windows LAPS schema. `WinLapsSchema` is the clean DC **with the LAPS schema already extended** — revert to `WinLapsSchema` for any full test that includes `-IncludeWinLaps`, because on `main` the LAPS schema is a prerequisite **hard-stop** (the Tier Model does NOT auto-extend it), so deploying `-IncludeWinLaps` against `DC-Promoted-Clean` fails prerequisites with "The current Domain does not contain the Windows LAPS schema extensions." **Context:** Choosing the baseline checkpoint before a lab deploy/audit — use `WinLapsSchema` for full/WinLAPS-inclusive runs, `DC-Promoted-Clean` only for core (non-WinLAPS) runs.
