<!--
  Thanks for contributing! Before opening this PR, please confirm you followed the
  issue-first process in CONTRIBUTING.md:
  https://github.com/microsoft/ActiveDirectoryTierModel/blob/main/CONTRIBUTING.md

  Pull requests WITHOUT a linked, pre-agreed issue will be closed. This is a
  security-sensitive tiering tool — changes must be discussed before code is written.
-->

## Linked issue

<!-- Every PR must reference an issue that was discussed and AGREED before you wrote code. -->

Closes #

## What this PR does

<!-- One concern per PR. Describe the single change and how it matches the agreed issue. -->

## Security / tiering impact

<!-- Does this touch OUs, ACLs / delegations, GPOs, prerequisites, or add a parameter or
     topology option? Describe the impact on the tier boundaries and security posture. -->

## Checklist

- [ ] This change was **discussed and agreed in the linked issue before I wrote code**
- [ ] The PR addresses **one concern** (no bundled or unrelated changes)
- [ ] I did **not** add new public parameters, alternate topologies, or relax
      prerequisite / validation logic unless it was the agreed subject of the issue
- [ ] Tests added or updated; `.\tests\Invoke-AllTests.ps1` passes and coverage stays **≥ 80%**
- [ ] No unrelated reformatting or whitespace churn
- [ ] Documentation updated for any changed behavior
