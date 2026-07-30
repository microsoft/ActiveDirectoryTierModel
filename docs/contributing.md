# Contributing

> This page mirrors [`CONTRIBUTING.md`](https://github.com/microsoft/ActiveDirectoryTierModel/blob/main/CONTRIBUTING.md)
> in the repository root, which GitHub surfaces automatically when you open an issue or
> pull request. That file is the authoritative version.

Thank you for your interest in improving this project. This is a **security-sensitive
reference implementation** of Microsoft's tiered administration model, so we follow a
deliberate, **issue-first** process to keep the model coherent, secure, and maintainable.
Please read this before opening a pull request.

## The change process, in short

1. **Open an issue first.** Every change — feature, bug fix, refactor, config, or docs —
   starts with a GitHub Issue that describes the problem or proposal.
2. **Discuss and get agreement.** A maintainer will review the issue and agree on the
   scope and approach. **Wait for a clear go-ahead** (the issue is accepted) **before you
   write code.**
3. **Then open a focused pull request** that links the agreed issue and implements only
   what was agreed.

!!! warning "Pull requests without a linked, pre-agreed issue will be closed."
    This is not personal — please see *Why we work this way* below.

## Why we work this way

- **Security first.** This project deploys and audits privileged-access tiering
  (Tier 0 / 1 / 2) boundaries in Active Directory. An unreviewed change can silently
  weaken a tier boundary, broaden the attack surface, or relax a validation that exists
  on purpose. Every change needs a design- and threat-aware review **before** code, not
  after.
- **The model is intentionally opinionated.** It implements a specific, tested topology
  and set of conventions. Alternative approaches — new parameters, alternate OU layouts,
  relaxed prerequisites, different naming — may well be reasonable, but they change the
  security posture and must be discussed and justified in an issue first so we can weigh
  them as a project.
- **We respect your time.** Agreeing on scope up front avoids you investing hours in a PR
  we can't accept because it conflicts with the design, duplicates in-flight work, or
  bundles too much. A five-minute issue saves everyone a large, hard-to-review PR.

## Opening a good issue

Please include:

- **What** you want to change and **why** (the problem or use case).
- **Scope** — the smallest change that solves it.
- **Security / tiering impact** — does it touch OUs, ACLs / delegations, GPOs,
  prerequisites, or add a parameter or topology option?
- **Environment details** if it's a bug (OS, PowerShell version, AD functional level, and
  the domain controller's install language).

If you're reporting something that's already fixed, we'll close the issue with a pointer to
the fix or release — please check the latest release and the project changelog first.

## Pull request requirements

Once an issue is agreed, your PR must:

1. **Link the agreed issue** (e.g. `Closes #123`) and stay within the agreed scope.
2. **Be focused — one concern per PR.** Don't bundle unrelated changes (e.g. a bug fix
   *plus* a new parameter *plus* reformatting). Split them into separate issues and PRs.
3. **Contain no unsolicited scope changes.** New public parameters, alternate deployment
   topologies, relaxed or bypassed prerequisite/validation logic, and mass config
   reformatting will be rejected unless they were the agreed subject of the issue. In
   particular, changes that turn a deliberate **fail-fast / hard-stop into a "warn and
   continue"** weaken safety and require explicit design sign-off.
4. **Include tests.** New code and bug fixes need Pester tests; keep coverage at or above
   the **80%** CI gate.
5. **Keep the diff clean.** No incidental whitespace or reformatting churn in files
   unrelated to your change.
6. **Update documentation** for any changed behavior.
7. **Pass CI** — lint, tests, coverage, and security checks are enforced. The release
   artifact is only produced when these pass.

## What tends to get rejected

- PRs with **no prior issue and no agreement**.
- **Bundled** PRs mixing unrelated features, fixes, and reformatting.
- **New parameters or alternate topologies** that were never discussed — they change the
  model's contract and its security surface.
- Changes that **relax security-relevant validation** (for example, converting a fail-fast
  prerequisite gate into a silent skip).
- Large **reformat-only** diffs across config / JSON that obscure the real change.

## Working agreement

- Be respectful and assume good intent — from contributors and maintainers alike.
- Maintainers may decline changes that don't fit the project's security model or roadmap,
  even when they are well implemented. We will always explain why.
- This project follows the
  [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

Thank you for helping keep the Tier Model secure and coherent. 🙏
