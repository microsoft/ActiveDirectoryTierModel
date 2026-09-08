### 2026-09-05T08:40:00+08:00: POC in .research before modifying working scripts

**By:** Joel Platek (via Copilot)

**What:** When a design question cannot be decided from existing evidence, create a small
standalone test script and try the different scenarios FIRST — before writing a lot of code
against the real working scripts. Verbatim: *"If something cant be decided then create a small
test script and try different scenarios before writing a bunch of code and modifying our real
working scripts."*

**Why:** Deploy-TierModel.ps1 and Audit-TierModel.ps1 are production Tier 0 tooling. Speculative
edits to them to "see what happens" are expensive to unwind and risk regressions in code that is
already lab-validated. A throwaway POC in `.research\` is cheap, isolated, and produces evidence
that can be cited in the design record.

**Scope:** Standing methodology rule, not specific to the verbose/debug work.

**Existing precedent:** `.research\verbose-vs-debug-poc\` and `.research\debug-switch-poc\` were
produced exactly this way and their captured results are cited throughout
`.research\verbose-vs-debug-design.md`. Extend that scaffolding rather than starting new POCs
from scratch.

---

### 2026-09-05T08:40:00+08:00: Console output during diagnostics is intentionally messy

**By:** Joel Platek (via Copilot)

**What:** The terminal/console output when `-EnableVerbose` and/or `-EnableDebug` are active WILL
be messy, and that is an accepted, deliberate trade-off. Do not build console-cleanliness
machinery to hide it. Joel: *"I understand that -EnableDebug is going to mess up the screen and
output... Either way dont care these are for when there are issues."*

**Why:** These switches exist for the situation where something is already broken and the
operator needs everything. Suppressing or reformatting output to look tidy risks hiding the very
detail the switches were added to expose.

**Consequence:** The v1 "unified sink" / console-cleanliness design in
`.research\verbose-vs-debug-design.md` is formally withdrawn and must not be revived.

---

### 2026-09-05T08:40:00+08:00: Sequencing — BUG-019 before any verbose/debug work

**By:** Joel Platek (via Copilot)

**What:** BUG-019 (37 AD/GroupPolicy read call sites with no explicit `-ErrorAction`) is fixed
FIRST, before implementation of `-EnableVerbose` / `-EnableDebug` begins.

**Why:** This matches design-doc decision D1. Diagnostic switches cannot surface an exception the
code never sees — a failed read that returns `$null` is indistinguishable from "object does not
exist" regardless of how much logging is switched on. Fixing the error handling first is the
difference between fixing the defect and decorating it.

**Also:** BUG-019 touches `modules\`, and `-Verbose` forwarding to AD/GPO call sites (D9) touches
the same files. Sequencing BUG-019 first also prevents two agents colliding in `modules\`.
