# Implementation Plan: Scope Publish Guard — **STUB**

**Spec**: `specs/007-scope-publish-guard/spec.md`
**Created**: 2026-09-05
**Status**: **STUB — deliberately not written.**

---

## Why this file is a stub

The scope publish guard is **deferred to v2.2.0** and **nobody has scoped the work**. Writing a detailed
implementation plan now would invent sequencing, contracts and effort estimates that no one has agreed to,
and would make the feature look more decided than it is.

What exists today is a design argument, not a plan: `specs/007-scope-publish-guard/spec.md`.

## What must happen before this file is written

1. **OQ-002 answered** — does the cross-check `throw`, or log loudly plus a console banner? The two answers
   produce materially different implementations and materially different risk profiles (spec §5).
2. **OQ-003 answered** — is branch 5 (`-OuAclOnly`) brought into the normaliser, or does it keep a
   `-PreNormalised` escape hatch? This decides whether the guard has a hole in it by design.
3. **The drifted fixture has run against a real DC**, so the guard can be built against known-real producer
   shapes rather than assumed ones. This is deferral argument 4 in the spec and it is the load-bearing one.
4. **The canonical-ACL phase has been observed succeeding against a healthy DC.** Until then, the guard
   cannot be given a `throw` behaviour safely — see the hazard in spec §5.

Only after all four does an ~11-call-site edit plan, the helper contract, and a test plan mean anything.
