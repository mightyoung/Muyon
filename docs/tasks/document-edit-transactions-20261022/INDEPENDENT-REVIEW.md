# Independent non-author review

Reviewer: separately dispatched `independent_review`, read-only; no authoring,
commits or pushes by reviewer. Final assessment: no outstanding blocking or
should-fix findings in the offline contract scope. This is not approval to merge
or evidence of actual Office editing, durable CAS or production authority wiring.

Round 1 independently ran 17 original tests and 3 reproductions. Found three P2:
1. Candidate/validation could be accidentally associated with another intent/patch.
2. Cancel before a late durable commit/unknown result made the outcome unobservable.
3. New grant generation/epoch blocked original-intent read recovery and local cancel.
Author wrote behavioral regressions first: `07-review-regression-red.log` has
18 passed / 4 failed. Fixes bind candidates to the full transaction, keep cancelled
phase for late recovery, and separate read recovery/local cancellation from reuse
of an old effect confirmation. Additional apply-unknown and revoked-unknown tests
preceded their implementations (`08`, `10`); all historical failures retained.

Round 2 independently ran 23 tests and 7 extra probes, passed. This precedes the
final shared-core adaptation and is preserved as historical evidence only.

Round 3 reviewed direct reuse of the exact core dependency:
`ab9c381cc935be0cd52db5a8a455ce985bdba1db`, not a second document identity or
authority implementation. Personally ran offline locked Cargo combination:
**27/27 transaction tests + 18/18 documents tests passed**, plus **6/6 independent
probes** covering complete workspace/project/document/revision/format binding,
unknown/gated capability matrices, Inspect-only recovery with a new grant,
revoked local cancel/unknown, and cancelled apply recovery that cannot resume writes.
Combination source/test hashes were independently matched to the working branch:

- module SHA256 `fcdcdd2ac85f31737d96eb1743a3333d4c9376da5de5939caa333bf394610284`
- test SHA256 `3f47dd2b0d9888f0f4dfc932a7fb804d706c66b02b4ec7047db766ddbe0f9a3e`

Code checkpoint: `9b242a4ae0143b872e7c885be29585da87a165f8`.
Reviewer's raw tests, independently written probes, outputs and hashes are in
`evidence/independent-round{1,2,3}/`. PLAN's later addendum documents the final
shared-core dependency; final production/test code matches the reviewed hashes.

Boundary: HostFacts, capability matrix and receipts must come from a trusted
host. The module has no engine, durable atomic gateway, actual original-intent
lookup, byte delivery, file write or existing business authorization integration.
Default Unknown capability denies. A read preflight is never publication authority.
