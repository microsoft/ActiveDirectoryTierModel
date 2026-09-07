# Compliance reporting: three outcomes kept distinct, and two headline verdicts aligned

Rogue, 2026-09-07. Covers the standalone-headline error guard and the empty-scope ruling
(Option 1). Nothing committed or staged.

## The rule

A compliance percentage is only meaningful when objects were checked and the audit that checked
them completed. Three outcomes are now reported differently everywhere:

| Outcome | Rendering | In the denominator? |
|---|---|---|
| Audit raised errors | `N/A (could not be determined)`, red | no |
| Nothing configured | `Not checked - nothing configured`, grey | no |
| Objects checked | the percentage, coloured by band | yes |

A scope that IS configured but whose objects are absent from the directory keeps a real check
count and real drift, so it takes the percentage branch and reports as drift. Executed and
confirmed: `TotalChecked=3, Drift=3` renders `0%` in red, not grey. "Nothing to check" and
"everything is missing" remain different results.

Denominator exclusion needed no arithmetic change. An unconfigured scope already contributes
zero to both numerator and denominator, so it was never in the ratio - it was only ever
*rendered* as though it had passed.

## Why one shared renderer

Seven sites rendered compliance. Five computed it locally with a guard; two (GPO, ADMX) read a
`CompliancePercentage` the producer sets to a literal `100` when nothing was checked, printing a
green 100% over `Total Checked: 0`. The defect was the inconsistency, so the repair is a single
renderer rather than a second local guard.

The renderer accepts a percentage from callers whose producer already publishes one, so GPO and
ADMX keep their existing figures unchanged whenever checks actually ran. Only the unchecked and
errored states are newly handled.

**A consequence worth naming:** GPO and ADMX now also report `N/A` when their section raised
errors, which they previously did not. That follows from matching the five - the five have always
consulted the error count. Passing a literal zero to avoid it would have re-created the exact
defect class being repaired.

## One site deliberately left inline

`Invoke-CanonicalAclAudit` renders its compliance line inline rather than through the renderer.
Its unit tests extract that single function by brace-matching and execute it on its own, so it
cannot depend on a sibling helper; routing it broke 23 tests. It was also already correct, and
the "nothing configured" state is unreachable there because the domain root is always checked.
The uniformity would have been cosmetic and the cost was real, so the dependency was removed
rather than pushed onto the test harness.

## Headline verdicts

Both paths now use the same ladder: errors outrank nothing-checked, which outranks the drift
verdict. The standalone path previously branched on drift alone and could print a green
`COMPLIANT` directly above `Total Errors: 2`. The consolidated path already had the error guard
and gains the not-checked branch. Neither can render green without a completed run over real
objects.
