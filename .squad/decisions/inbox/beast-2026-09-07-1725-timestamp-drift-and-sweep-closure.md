# Decision record - Beast - 2026-09-07 17:25

## 1. Session timestamp drift - recorded, not rewritten

**Joel's ruling: leave the stamps, add a note.** Times issued during the 2026-09-07 session drifted
ahead of the system clock by up to roughly 75 minutes. The values ran 17:05, 17:15, 17:35, 17:45,
17:55, 18:05, 18:15, 18:30, 18:40 against a real elapsed span of about 17:00 to 17:20.

**Cause:** the values were incremented by feel rather than read from the system clock, and were then
written into files as fact. **The fault was the coordinator's own, stated explicitly. It is NOT
attributed to any agent** - Beast and Storm wrote what they were given, which was correct behaviour.

**Known affected:** `.research\known-bugs.md` stamps from today's later jobs;
`specs\006-verbose-debug-logging\tasks.md` (T024 records a measurement "as of 2026-09-07T18:30" taken
nearer 17:15); `specs\006-verbose-debug-logging\spec.md`; agent `history.md` files.

**Scope of the damage:** dates are correct everywhere, **only times are affected**, and nothing
functional depends on them.

**Action taken:** a short, factual limitation note placed in `.research\known-bugs.md` immediately
under the "Last updated" line - the point at which a reader first meets a timestamp and might rely on
one. It states the drift, that the values were supplied rather than measured, that only times are
affected, and that **file modification times on disk are authoritative where precise ordering
matters.** Written as a limitation of the record, not an apology. **No existing timestamp was
changed.**

Note that this record's own stamp (17:25) reads *earlier* than the register's "Last updated 17:45".
That inconsistency is left in place deliberately - it is the artefact the note exists to explain.

### Rule candidate flagged, NOT self-approved

The coordinator observed this is the **third instance today** of a document asserting something that
did not happen that way, and the **second about time specifically** (the first being a 1 September
file read as minutes old because times were printed without dates). His formulation:

> **A timestamp is a measurement and must be read, never composed.**

**I have not added this to `.squad\skills\verification-discipline\SKILL.md`.** Rules 22 and 23 were
each added on an explicit ruling to add them; this was phrased conditionally ("if a rule comes out of
it"). **Flagging it as the rule-24 candidate for the coordinator to rule in or out.** It is a strong
candidate - three instances in one day, and it generalises past time to any value an agent could
either measure or invent.

## 2. Literal false-clean summary sweep - CLOSED, no seventh instance

**Recommendation accepted: no scope expansion.** Nothing from this family enters v2.1.0. Recorded in
the live register as a closed line of inquiry with an explicit do-not-re-open heading, since the
value of a null result is entirely in it not being re-derived.

**Population stated beside every count:** 81 files (80 under `modules\TierModel\public\` plus
`TierModel.psm1`). **`modules\TierModel\internal\` does not exist** - the brief assumed it did.
Verified that no entry in the register asserted otherwise, so no correction was needed there.

33 error-returns zeroing a count across 27 files at HEAD; 32 across 26 in present state, one fewer
because Cyclops's own BUG-056 fix removed it. **False-clean: 0.**

**Why the zero is trustworthy - the part worth keeping:** a mutation battery of 12 audit
error-returns, each stripped of every error signal, caught **12 of 12, 0 missed.** A sweep that finds
nothing is worth nothing until it is shown able to find something.

**Cyclops caught his own instrument twice** - a pass-3 filter under-reporting by half (3 sites to 6
once fixed), and a mutation generator whose greedy regex swallowed the summary block, reporting 11/12
until rebuilt on AST extents. **Suspect the instrument, including the instrument that tests the
instrument.**

**The coordinator's own narrow regex was right by luck**, and he asked for that recorded.
`DriftFindings\s*=\s*@\(\)` returned 0 across 80 files but would have missed **all 33 sites** had they
been false-clean. That is working rule 19's shape - an exact literal where a class was meant -
arriving as a false negative.

**Precedent produced for BUG-052:** `Test-TierModelAuthSiloPrerequisite.ps1:83` already returns
`Passed=$false` with a real failure message for an empty scope, so **Joel's Option 1 is not a fourth
opinion - it is the rule this code already follows** (working rule 23).

**Residual risk is already open:** every producer error path flags an error; whether the user sees it
depends on the renderer surfacing the flag. That is BUG-055, Rogue's.

## Open count unchanged

**5 open in scope for v2.1.0. Next free ID 058.** Neither job registered or closed a bug.