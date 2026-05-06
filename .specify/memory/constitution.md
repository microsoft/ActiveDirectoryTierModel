# Tier Model v2 Constitution

## Core Principles

### I. Code Quality Is Foundational
All code must be:
- Readable (clear naming, cohesive functions, minimal side effects)
- Consistent (shared style guide; automated formatting/linting where feasible)
- Reviewed (every change requires peer review focusing on clarity, risk, and test coverage)
- Traceable (each feature/change tied to a work item or documented rationale)
Quality debt is tracked explicitly; "temporary" code is prohibited in mainline branches.

### II. Test-First With Pester (NON-NEGOTIABLE)
Before implementing PowerShell logic, author Pester tests that express intended behavior (happy path, failure modes, idempotency, drift detection). The sequence: Define tests → Validate they fail → Implement → Achieve green → Refactor safely. Minimum requirements:
- Unit tests for pure functions (no external calls)
- Contract tests for scripts/modules exporting public functions
- Idempotency tests: re-run deployment/apply functions against an unchanged environment and assert no destructive changes
- Drift audit tests: re-run against modified environment and surface discrepancies in a structured report (JSON)
`Invoke-Pester` must pass in CI; failures block merges.

### III. Idempotent Deployments
Deployment scripts must produce the same resulting state regardless of repeated execution. Rules:
- Only create/update when drift detected; never assume prior state—always query & compare
- Changes are additive or convergent; destructive operations require explicit, separate approval path
- All state transitions logged (who/what/when) and testable
Acceptance: A second immediate run yields 0 changes and marks run as "Converged".

### IV. Zero-Unintended-Impact Production Runs
Every production execution must be safe to run with no pending changes ("no-op" capability). Pre-flight mode (`-WhatIf` / dry-run) required, emitting:
1. Summary (counts: adds, updates, deletes)
2. Detailed plan (resource identifier, action, rationale)
3. Risk level classification
If plan indicates destructive changes, operation halts unless explicitly allowed via signed-off parameter or approval artifact. Actual apply must match previously generated plan signature (hash) or abort.

### V. Drift Detection & Auditable Reconciliation
Re-running deployment logic against production acts as an audit:
- Detect divergence between declared configuration and actual state
- Produce machine-readable drift report (JSON) plus human summary
- Classify drift: benign (e.g., tags), required remediation, manual-exempt
- Pester drift tests validate classification logic and reporting schema
Remediation steps must be explicitly tracked; auto-correction only for low-risk benign drift.

### VI. Structured Observability & Logging
All scripts/modules emit structured logs (timestamp, correlation id, action, target, result, duration). Minimum levels: Debug, Info, Warn, Error. Logs integrate with centralized aggregation via Write-TierModelLog helper function with JSON output support. Sensitive data is never logged (enforce allowlist of fields with automatic redaction for passwords, secrets, and PII). Each deployment run creates a unique correlation id used in test assertions and drift reports.

**Logging Standards (Added Phase 9)**:
- Use Write-TierModelLog for all structured logging with -Level and -Data parameters
- Include correlation IDs for traceability across distributed operations  
- Redact sensitive fields automatically (passwords, secrets, SIDs with partial masking)
- Support JSON output format for machine parsing and CI artifact creation
- Log major action execution points with timing data (DurationMs) for performance analysis

### VII. Simplicity & Explicitness
Prefer simple, declarative configuration over implicit magic. Hidden side effects, dynamic global state or reliance on execution order are prohibited. Complex operations must be decomposed into clearly testable units.

### VIII. Modular Decomposition Over Monoliths
No new functionality is delivered as a single sprawling script. Requirements:
- Break large scripts (>300 lines) into cohesive modules/functions with single responsibility
- Shared utilities centralized in versioned modules; duplication tracked as technical debt
- Each module independently testable (unit + contract)
- Public surface kept minimal; internal helpers remain private (non-exported)
- Clear dependency graph: modules may depend downward (core/util) but avoid cyclic or implicit dependency
- Refactoring path: legacy monolithic scripts are incrementally carved into modules with regression Pester tests ensuring behavior parity
Success Criteria: Adding a feature rarely increases any file beyond 20% growth; new capability primarily appears as a new module/function + tests.

### IX. Dependency & Configuration Version Governance
All modules, external PowerShell dependencies, test frameworks, and configuration inputs (e.g., JSON source files driving deployments) are strictly version-controlled to guarantee reproducibility.
Requirements:
- Pin versions: Pester, external modules (e.g., Az, PSDesiredStateConfiguration, custom company modules) must be declared with explicit versions (no floating/latest) in a manifest (`dependencies.json` or `RequiredModules` in module manifest).
- Compatibility matrix: Maintain a `TESTED_VERSIONS.md` enumerating validated combinations (Module Name → Version, Pester Version, PowerShell Edition). CI asserts current environment matches a supported row.
- Controlled upgrades: Version bumps require a dedicated PR with: upgrade rationale, changelog review, added/updated tests for new behaviors, and rollback plan.
- Input JSON Schemas: Each input source JSON file has an associated semantic version and JSON Schema file; changes to schema require minor/major version increment and migration notes.
- Provenance & Integrity: Hash (SHA256) of critical input JSON is logged at run start and included in drift and deployment reports; mismatch from recorded hash triggers warning.
- Backward compatibility tests: For schema or module updates, Pester tests load previous minor version inputs to validate non-breaking behavior (unless documented otherwise).
Success Criteria: Any environment can recreate a prior successful run given commit + dependency manifest + input JSON bundle hashes.

## Implementation Standards
PowerShell & Pester specifics:
- Module layout: `Modules/<Name>/<Name>.psm1` + accompanying tests under `Tests/<Name>.Tests.ps1`
- Exported functions require comment-based help and examples
- Use `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`
- Functions return rich objects; CLI/console formatting handled separately
- Use `Should -BeExactly`, `Should -Throw`, and custom matchers for idempotency/drift semantics
CI Requirements:
- Lint pass (PSScriptAnalyzer with security rules enabled)
- Pester pass (all tests including logging and redaction verification)
- Drift simulation test scenario with artifact publishing
- Security analysis with fail-on-critical-issues enforcement
- Scheduled drift detection runs with report artifact generation
Failure in any gate blocks merge.

**CI/CD Pipeline Standards (Added Phase 9)**:
- GitHub Actions and Azure DevOps pipeline templates with multi-stage workflows
- Automated drift detection on schedule with artifact publishing to CI system
- Security scanning integration with critical issue blocking (fail-fast on high/critical findings)
- Code coverage reporting and test result publishing as pipeline artifacts
- Logging output capture and validation in CI environment with structured JSON format

## Workflow & Quality Gates
Pull Request Checklist:
1. Tests: Added/updated (unit + idempotency + drift as applicable)
2. Dry-run output attached for deployment-related changes
3. Risk assessment included for any non-additive changes
4. Reviewer confirms: code clarity, no sensitive logging, adherence to idempotency pattern
Automated Gates:
- `Invoke-Pester` full suite
- Static analysis (script analyzer)
- Optional security scan (placeholder for future tool)
Versioning:
- Semantic: MAJOR.MINOR.PATCH (MAJOR requires migration plan & governance approval)

## Governance
This constitution overrides informal practices. Amendments require:
1. Proposal document (problem, change, migration impact)
2. Review & approval by designated maintainers
3. Version bump & dated amendment entry
Enforcement: All PR reviews must reference this constitution. Deviations must include explicit waiver with expiry date.

**Version**: 1.3.0 | **Ratified**: 2025-10-28 | **Last Amended**: 2025-11-10

## Amendment History
- **v1.3.0** (2025-11-10): Added Phase 9 governance rules for structured logging standards, CI/CD pipeline requirements, and security analysis integration. Enhanced logging section with Write-TierModelLog specifications and data redaction requirements. Added CI/CD pipeline standards for GitHub Actions/Azure DevOps with artifact publishing and automated drift detection.
- **v1.2.0** (2025-10-28): Initial ratification of core principles and implementation standards.

