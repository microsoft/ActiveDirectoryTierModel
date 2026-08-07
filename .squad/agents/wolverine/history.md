# wolverine — History

## Learnings

**2026-07-28 — BUG-008 & BUG-004 Lab Validation (this session):**

### Lab Config Facts
- Checkpoints actually on TierLab-DC01 (as of 2026-07-28): `DC-Promoted-Clean`, `WinLapsSchema`. No `WinLapsSchema-Ready` — that was created during BUG-002/005 session and is gone.
- `lab-config.json` lives in `.research/copilot-cli-hyperv-ad-lab/` (parent of `scripts/`), NOT inside `scripts/`. Pass `-ConfigPath` explicitly to helper scripts.
- WinLaps audit (Test-TierModelWinLapsAcl) is slow — each of the 7 delegations calls `Find-LapsADExtendedRights` which takes ~1 min per OU. Full audit: 8–10 min. Always use `-File` mode (not `-Command {}`); the former streams output; the latter buffers until completion.
- The `run-winlaps-audit.ps1` wrapper `Set-Location C:\TierModel; & .\Audit-TierModel.ps1 -PreferredDc DC01 -IncludeWinLaps` works reliably when executed via `& $pwsh -File`.

### Exact Function Signatures (re-confirmed on guest)
- `Test-TierModelWinLapsAcl -Config <object> -DomainController <string> [-Silent] [-SuppressSummary]`
- `Get-TierModelConfig` (no params) — loads from module-relative config
- `Audit-TierModel.ps1 -PreferredDc DC01 -IncludeWinLaps` (standalone WinLaps audit mode, no scope param needed)

### Pre-existing WinLapsSchema Checkpoint State (important: known false-positive pattern)
- After deploying TierModel on WinLapsSchema checkpoint, `Test-TierModelWinLapsAcl` reports `UnexpectedAcl` for:
  - `TIERLAB\Tier0Admins` on `OU=Tier 0 Member Servers` — root cause: `Tier0Admins` has a **GenericAll** ACE (non-inherited) on that OU from OU delegation. `Find-LapsADExtendedRights` expands GenericAll → effective LAPS rights holder. Config only expects Tier0ServerOperators there.
  - `TIERLAB\Tier1Admins` on `OU=Tier 1 Member Servers` — same root cause (GenericAll OU delegation ACE).
- These are NOT inherited from domain root or parent OUs — they are direct GenericAll ACEs set as part of the Tier Model's OU de
[truncated summary]
