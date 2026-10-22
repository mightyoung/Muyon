# Independent review — MU-01 / MU-04 / PX-09 offline contract

Historical review at the source below. Parent review later found an Important stale-cancellation identity gap; this initial scoped conclusion did not cover it. The gap and follow-up evidence are tracked in [CANCEL-IDENTITY-FIX.md](CANCEL-IDENTITY-FIX.md); do not use this older review to waive that repair.

Reviewed source: `37015799dcda3ef918ae9c6e161bfebff30103c8`.
Base: `f4781e16ddf4e542b983fbd77f266a0071148255`.
Reviewer: independent non-author agent `independent_contract_review`; this report transcribes its returned result. Reviewer did not edit, commit, push or access real requests.

Conclusion: the minimal offline contract is deliverable with no remaining blocker found in this scope. This is not production integration acceptance or permission to merge. Leader B remains the sole develop integrator.

## Independently executed checks

```sh
KOTLINC=/tmp/muyon-contract-toolchain/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/components/run-offline.sh
git diff --check f4781e16ddf4e542b983fbd77f266a0071148255..37015799dcda3ef918ae9c6e161bfebff30103c8
bash apps/muyon_android/gradlew --offline :app:testDebugUnitTest
```

- Contract suite exit 0: 16 groups PASS.
- Diff check exit 0. Four new files only: scoped implementation, test main, runner, own report; tree clean at reviewed source.
- Gradle exit 2: missing Gradle 8.13, NOT_RUN. Full Android build/unit suite, lint and devices are not accepted by this review.
- Reviewer also ran an independent temporary probe, exit 0, seven checks PASS for fixed duplicate-decision, nested-scope restore, changed values with old digest, forged committed, malformed Unicode and terminal duplicate paths. The persistent reproduction coverage is in the checked-in 16-group suite; raw temporary probe/logs are not committed.

Reviewed implementation SHA-256:
`bd01d99688e5e2107101736ce38c7a2bc74516d76e0005943db7758b5742415e`.

## Findings and closure

Initial review independently reproduced: same ambiguous PendingSubmission on first and duplicate click, cross-conversation pending identity surviving restore, and changed pending/last values committing against the old digest. Later review identified malformed UTF-16 digest aliasing and forged committed/reused-intent restore inconsistencies. Each received a negative regression; failing schema/restore/Unicode runs are preserved as factual RED evidence in REPORT.md.

Fixed source now distinguishes NewPending, ExistingPending, LookupOriginal and HistoricalReceipt (implementation lines 159–179); validates nested scope/revision/digest/values/history/intent relationships on restore (239–280); rejects lone UTF-16 surrogates before hashing (300–309). Independent rerun confirms these original examples no longer succeed.

Draft edits and compose proposals grant no business/disclosure authority. Unknown selects original lookup, never NewPending; cancel requested is nonterminal. Held cost and nullable actual cost remain distinct. Original exact matching trusted receipt is needed for committed state; immutable terminal history is not current business state.

## Remaining acceptance boundaries

The in-memory reducer and snapshot contract do not establish durable persistence or process-exit recovery. JSON transport, source permission resolution, host receipt mapping, UI/ChatScreen wiring and save-before-dispatch integration require a separately allocated host-owner patch, outlined in REPORT.md. No real model/search or stopped-request operation ran; the old two unknown requests and CNY0.002620 reservation remain unchanged. Missing Android environment and production integration block broader acceptance, not this standalone contract result.
