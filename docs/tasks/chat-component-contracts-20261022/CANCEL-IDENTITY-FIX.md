# Follow-up — bind cancellation to original pending identity and CAS revision

Parent review: Important, must fix before UI integration. Previous branch head `c7c0d4729d034eb3d644e8945a56ca7dba467ff4` exposed `requestCancel(scope)` and checked only scope. This finding supersedes the earlier scoped no-blocker review for that interface. It does not mean any remote cancellation was executed.

## Reproduction before implementation

Added a test using the original API: submit A, capture callback context, observe A committed, redo into a fresh attempt, edit and submit B, then invoke A's late same-scope cancellation. Actual output before fixing:

```text
late-cancel probe: original=intent-1 current=intent-B before=PENDING after=CANCEL_REQUESTED
Exception in thread "main" java.lang.IllegalStateException: Late cancellation for A mutated pending B
```

The test exited 1 with the 16 previous groups passing first. Complete original stdout/stderr: [evidence/cancel-original-red.log](evidence/cancel-original-red.log). This is a synthetic offline regression, not an observation of a real request or a remote cancel. The user explicitly requested raw test output in this follow-up; only these synthetic output files are committed as an exception to the repository's usual raw-log rule.

## Revised UI-facing API

```kotlin
fun requestCancel(
    scope: ComponentScope,
    pendingIdentity: SubmissionIdentity,
    expectedRevision: Long
): PendingSubmission
```

The scope-only overload is removed. Callers must capture all three arguments from the same rendered snapshot. Example:

```kotlin
val shown = ledger.snapshot()
val shownPending = shown.pending ?: return
// Capture shown + shownPending in this specific UI action, not a later attempt.
val requested = ledger.requestCancel(
    shown.scope, shownPending.identity, shown.stateRevision
)
```

`pendingIdentity` equality includes workspace/conversation/project/agent/generation, component/message IDs, component and original submission state revisions, attempt/action/intent IDs and params digest. `expectedRevision` is separately the current snapshot CAS revision, not `identity.stateRevision` (the original submission's revision). Both checks run under the existing synchronized transition and before any mutation. A mismatched identity, stale revision, wrong scope or absent pending operation throws `IllegalArgumentException` and leaves the entire snapshot unchanged. The caller may refresh presentation after rejection; it must not replace the captured identity with a newer attempt and automatically retry the stale action.

On an exact current snapshot, a normal or unknown pending operation records local `CANCEL_REQUESTED` and advances revision once. Repeating against the same pending identity with the *current* revision returns the existing pending value without another revision change. A duplicate carrying the old pre-cancel CAS revision is rejected. Terminal operations cannot be cancelled. The return value records local cancellation intent only: it is not a remote-dispatch instruction, authorization, terminal receipt, success or rollback. Unknown still uses the original lookup; draft/committed/history and held/nullable-actual costs are retained.

## Fixed regression coverage and commands

```sh
KOTLINC=/tmp/muyon-contract-toolchain/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/components/run-offline.sh
git diff --check
bash apps/muyon_android/gradlew --offline :app:testDebugUnitTest
```

- Standalone suite exit 0, 20 groups PASS, compiler `-Werror`, JVM target 17. Complete stdout/stderr: [evidence/cancel-fixed-green.log](evidence/cancel-fixed-green.log).
- New late-A test rejects both A's captured revision and A's identity paired with B's current revision; verifies B's entire snapshot unchanged.
- Normal/repeated cancellation: one local phase/revision transition; same identity/current CAS repeat idempotent; stale repeat and post-terminal cancellation rejected without mutation.
- Negative cancellation: each altered identity field, negative/old/future CAS revision, all scope dimensions and generation rejected without mutation.
- Unknown: stale pre-observation CAS rejected; exact unknown identity/current CAS allowed only as local cancel intent; original lookup, held cost, nullable actual cost, history and committed values preserved; resubmission remains lookup-only.
- Diff whitespace check PASS. Gradle exit 2, missing Gradle 8.13, NOT_RUN; no Android compile, persistence or UI integration acceptance follows.

Independent final-source review and exact implementation SHA are recorded in CANCEL-INDEPENDENT-REVIEW.md after the reviewer returns. The reviewed source and final pushed head are reported separately, since evidence-only commits do not change implementation.

## Scope and holds

Only the allocated component implementation, corresponding independent test, and this task's reports/evidence are changed. ChatScreen.kt/MainActivity.kt/build files and other tasks remain untouched. No real request, remote cancellation, lookup of stopped state, model/search, credential, permission, deployment, paid action or I04 retry occurred. The old two unknown requests, CNY0.002620 held reservation and unknown actual charges remain unchanged. No main/develop modification or merge; Leader B retains sole develop integration authority.
