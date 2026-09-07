### 2026-09-05T20:22+08:00: User directive — no bug-history comments in code

**By:** Joel Platek (via Copilot)

**What:** Inline `BUG-nnn` references and bug-history comment blocks must NOT remain in the
code once the bug is fixed. Comments should explain **what the code does** — never that
something was, or used to be, a bug. Git, GitHub, branches and pull requests already track
that history; duplicating it in source is noise.

Joel's words: *"I dont like you putting all these comments about BUG-029 numbers inline
comments in our code once its been fixed we should remove it. I saw this a lot during my code
review. Github and git and committing keeps track of these changes along with branch and pull
request. I dont want all these huge comment blocks in the code the only comment should be what
this code is doing not that it is or was a bug."*

**Why:** Raised during his manual code review of the `feature/enable-verbose-debug` branch.

**Status:** PARKED at Joel's request — *"park this until tomorrow and I will remind the team in
the morning."* No cleanup work has been started. Do not begin until he raises it.

**Scope of the cleanup when it starts (not yet sized, do not assume this list is complete):**
- Multi-line `# BUG-nnn:` explanatory blocks across `modules/TierModel/public/*.ps1`
- The same pattern in `Audit-TierModel.ps1` and `Deploy-TierModel.ps1`
- Known examples seen today: `Test-TierModelOuAcl.ps1` ~L120-127 (7-line BUG-042 block),
  `Audit-TierModel.ps1` ~L1095-1105 (BUG-042), `~L2000` and `~L2014` (BUG-028),
  `~L2406` (BUG-030), `Get-TierModelGpo.ps1:99`, `Get-TierModelGpoFd.ps1:286`,
  `Test-TierModelGPOAudit.ps1:149`

**Open questions to resolve with Joel before executing:**
1. **Memory scope** — does this apply only to this repository, or to all of his repositories?
   Not stored as a memory yet precisely because both are plausible. Ask him.
2. Where does the *reasoning* go instead? Several of these blocks carry non-obvious rationale
   (e.g. why four raw-path `Identifier` sites were deliberately left alone; why the
   GPO/WinLapsDecryptor breakdown legitimately does not sum). Losing that reasoning entirely
   would invite re-filing the same closed items. Candidate homes: the CHANGELOG entry, the
   spec under `specs/`, or a short non-BUG comment stating the constraint without the history.
3. Does this extend to `BUG-nnn` references inside **test** files, which are often the only
   record of why a specific assertion exists?

**Interaction with existing work:** BUG-019 + BUG-024..044 (22 items) are still pending
migration into `CHANGELOG.md` under `[2.1.0]`. That migration is the natural place for the
history being stripped out of the code — sequence the two together rather than separately.
