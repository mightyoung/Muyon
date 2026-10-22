# Host read projection — bounded request observation slice

Branch: `task/ui-host-projection-20261022`.
Pinned parent: `8937b3d62943351f918b4ae980f987e804427911`.
Verified candidate: `codex/muyon-android-refactor` =
`f4781e16ddf4e542b983fbd77f266a0071148255`.
Verified design archive: `400e206135690c284c8402521e3135cfb7bfaee8`;
original specification, source manifest and actual PNG blobs exist there.
No UI resource/image implementation is authored here.
At final remote read the concurrently owned shell branch had advanced to
`3ecb544ad0a47ccc38fe830777f35588b92e8afc`; this patch retains its instructed pinned
parent and does not rewrite or merge the other owner's branch.

Read repository task index, leader handover/status, shell handover and
HOST-ADAPTER-PATCH-PLAN.md. No AGENTS.md found in this checkout or its workspace
parent. Original checkout was clean, on `work`; no user changes overwritten.

## Implemented and exact file boundary

Only production changes:

- `apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/ProductChatRuntime.kt`
- `apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agentipc/ProductService.kt`

No Rust/FFI increment is necessary for the available request observations. Existing
`crates/muyon-core/src/agent/owner.rs::Observation/lookup` and
`crates/muyon-android-ffi/src/lib.rs::agent_lookup` were inspected, not modified.
No database write flow, ChatScreen, MainActivity, ui/ component, reducer contract,
transport, gateway, or credential configuration implementation changed.
New tests live under `app/src/test/kotlin/.../product/chat/projection/`.

Trusted successful prepare/search/workflow-prepare/followup results supply original
request identity and native request conversation. The runtime captures the actual
session, displayed conversation, selected project and scope generation separately.
`readSnapshot` compares every supplied scope field before its sole native local
`lookup(originalRequest)` call. The Service supplies workspace/session from its own
owner and Binder lease; payload cannot choose them. Service UID/epoch/client checks
remain in force. Generation must be a nonnegative JSON integer.

The observation is a detached, point-in-time wire value with no authority. It
excludes model answers, commands and raw failures. It retains whitelisted native
request status (including tool_consumed), exact reserved micro-CNY strings or null,
and actual charged micro-CNY only when a dispatched completed native request
proves settlement (otherwise null),
actual attempted/cancelled facts or null, and original native request identity.
Prepared/reserved/pending/tool-pending never imply running. Completed request
observations do not imply current business state. Unknown cancellation flags do
not imply terminal cancellation. No reservation, refund, automatic query/retry,
confirm, followup or cancel action is introduced by the reader.

The 256-entry display provenance cache evicts only display availability. It does
not block business preparation. Scope invalidation/release removes corresponding
origins. Missing original conversation facts leave projection unavailable without
turning successful prepare into failure. Process restart/cache eviction cannot
reconstruct provenance: return unavailable, retain existing original lookup UI.

## Shell consumption contract (sole shell owner to integrate)

Use existing `ProductClient.call("chat_snapshot", payload, callback)`.
Payload fields: original `request_id`, displayed `conversation_id`, nullable
`project_id`, and integer `scope_generation` captured from the actual `chat_scope`
reply. There are no caller-provided workspace/agent/binding fields.

Normal Service envelope: `status=ok`, `data` is this version-1 snapshot. Service
correlation `request_id` is separate from `data.original_request.request_id`.
Inspect inner `data.status` before rendering:

- `read_only`: `scope` contains workspace_id/conversation_id/project_id/generation
  and null agent_id; `original_request` contains native request_id and
  request_conversation_id (workflow child/followup may differ from displayed
  conversation_id), with null intent_id.
- `observation`: status, execution_status, reserved_micro_cny, charged_micro_cny,
  attempted, cancelled, cancellation_status, and null current_business_state.
  Costs are micro-CNY strings; null stays unknown, never zero. charged_micro_cny
  is actual settled cost, not the requests.charged ledger default: only native
  completed plus attempted=true exposes it; all other cases return null.
- `binding=null`, `capabilities=[]`; `unavailable` enumerates absent agent,
  message/component/attempt identity, component/state revision, host digest,
  original intent, task/source snapshots.
- `unavailable`/snapshot_scope_unavailable or snapshot_identity_mismatch: do not
  render previous-scope facts or substitute identity. Generic native failures
  retain the existing unavailable response. Do not fetch another ID and retry.

Before applying a callback, compare its conversation/project/generation with the
still-mounted view using the existing callback-scope guard. Retain the captured
scope generation from chat_scope; current shell only checks its presence and will
need to store it. Never derive one from UI count, time or component reducer.

This API cannot construct existing CardBinding/OriginalCardRequest or
ComponentSnapshot honestly. Shell can display these real observations read-only
and explicit unavailable state, but must not instantiate an actionable typed card
with fallback IDs, revisions or digests. This is not live typed-card adoption.

## Actual validation and original output

All new execution uses local fake private ports and real production runtime JVM
code. Fixtures never reach ProductService/native storage/provider. Transport in
new tests throws if reached. No old real unknown request was queried or retried.

1. Test-first RED: projection runner before implementation failed compilation on
   unresolved readSnapshot. Original `evidence/red.log` retained.
2. New runtime projection tests: exit 0; scope/session/conversation/project/
   generation rejection before lookup, unknown/null costs, cancellation intent,
   empty and malformed observations, original ID mismatch, pending vs running,
   history vs current business state, detached output, missing original facts,
   search/workflow/followup provenance, release/remount, and 257 prepares across
   cache capacity. `evidence/green.log`.
3. Existing card runner: exit 0, 45 assertions. `evidence/cards.log`.
4. Existing component contracts: exit 0, 20 groups. `evidence/components.log`.
5. Existing ProductSkillRevocationTest and CompleteResponseSettlementTest compiled
   against actual runtime/transport/SendGate and JUnit, run as JVM tests: exit 0,
   `OK (3 tests)`. `evidence/regression-compile.log`, `evidence/regression.log`.
   This does not claim execution through Android instrumentation.
6. Independent non-author static review and actual runner rerun passed after
   closing cache-gate regression and missing tool_consumed status.
   `REVIEW.md`, `evidence/independent.log`.
7. Authored source/test/document scoped `git diff --cached --check -- apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/ProductChatRuntime.kt apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agentipc/ProductService.kt apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection docs/tasks/ui-host-projection-20261022/REPORT.md docs/tasks/ui-host-projection-20261022/REVIEW.md docs/tasks/ui-host-projection-20261022/HANDOFF.md` passed. Whole staged archive check exits2 on the original JUnit output's terminal blank line (`evidence/regression.log:6: new blank line at EOF`). Raw output is intentionally retained unchanged. No baseline tests changed to obtain green.
8. Actual Android command below exited 2 before compilation: existing Gradle8.13
   executable absent. Exact NOT_RUN output retained in `evidence/android.log`.
   No Android test, Service compilation, lint, APK or device test completed.
   Prior shell SDK install denial remains stopped; no retry, relocation,
   permission expansion or substituted Android build.

Commands from repository root (KOTLINC and JSON_JAR name real downloaded JVM tools):

```sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc JSON_JAR=/workspace/host-projection-tools/json.jar bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/components/run-offline.sh
java -cp /workspace/host-projection-tools/regression.jar:/workspace/host-projection-tools/json.jar:/workspace/host-projection-tools/junit.jar:/workspace/host-projection-tools/hamcrest.jar org.junit.runner.JUnitCore com.mightyoung.muyon.product.chat.ProductSkillRevocationTest com.mightyoung.muyon.product.chat.CompleteResponseSettlementTest
```

Regression jar was compiled with Kotlin2.2.20 `-Werror -jvm-target 17`, actual
ProductChatRuntime.kt/ProductSendGate.kt/ProductHttpsTransport.kt and those two
unmodified existing androidTest source files; classpath actual org.json and JUnit,
`-include-runtime`. No Android stub supplied.

Android command from `apps/muyon_android`:

```sh
./gradlew --offline --no-daemon --console=plain :app:testDebugUnitTest :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest :app:lintDebug
```

Tools downloaded only to task-writable /workspace/host-projection-tools:
Kotlin2.2.20 compiler ZIP SHA256
`81f0264c9073b5cbbdb3ff8418cf2c5dac076879fc156fa1a6462f5a5acc4420`;
org.json20250517 jar `3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796`;
JUnit4.13.2 `8e495b634469d64fb8acfa3495a065cbacc8a0fff55ce1e31007be4c16dc57d3`;
Hamcrest1.3 `66fdef91e9739348df7a096aa384a5685f4e875584cce89386a7a47251c4d8e9`.
These are JVM dependency downloads, not provider/model/search requests or SDK installs.

## Remaining blockers / next trusted contracts (not implemented)

- Complete immutable host card binding must originate from real message/component/
  attempt/action/intent identities, actual agent ownership, revisions and digest.
  Current AgentPlan/Observation do not provide these. No placeholder can close it.
- Task and source snapshots need their own authorized read contracts, actual stage/
  version/anchor/membership and original/current revision facts. No synthetic task,
  source, report, attachment progress or saved result supplied here.
- Future writes require separately approved core contracts: durable original intent
  binding, exact displayed-snapshot CAS, original cancellation-intent lookup and
  terminal reconciliation. Preserve existing component reducer identity semantics
  at 52576777716ea215ef1428b4dc0bcd65fde17f00 and corrected card wording at
  0a8c9fede203ecb5f3a65fb3bd01bd104e429838. Reader grants no such write authority.
- Sole shell owner integrates read-only interface and unavailable presentation;
  full typed cards remain unbound. Actual Android toolchain/Service build/device
  accessibility and callback-scope integration tests remain open.

Historical two unknown requests / ¥0.002620 held untouched. No live model/search,
SDK installation, paid CI dispatch, credential setup, permission expansion,
deployment, force push, deletion or main/develop modification. Leader B remains
sole develop integrator. Completion here is only this bounded request-read slice,
not all UI development or full host-card adapter completion.

## Parent review correction — actual charge proof

Parent review found Important at ac55ef65a65baf9499fe2e4b3a63a0baaf827887:
native requests.charged defaults to zero, and unknown lookup serializes that ledger
value as "0". The original reader incorrectly passed it off as known actual cost.
Prior unknown-with-null test did not cover that actual native shape.

Added the true shape (unknown, attempted=true, charged_micro_cny="0",
reserved_micro_cny="2620") before the fix: runner exited1 at
"native unknown ledger zero is not actual cost proof". Original output remains
in evidence/charge-proof-red.log; original baseline logs are untouched.

Pure projection fix: expose actual charged_micro_cny only for native completed
and strict Boolean attempted=true. owner.rs:534 sets attempted when dispatch is
claimed; settle_response:568–635 is the sole completed transition and validates
response/usage before recording cost. For all other statuses (including unknown,
prepared/reserved/pending/tool_pending/tool_consumed/failed/cancelled), actual cost
is null, even if a raw ledger charge is present. Cancelled mixes pre-send and
settled cases; tool statuses lack a separately exposed terminal settlement proof.
Those costs may be known internally but this public projection conservatively
leaves them unavailable. No ledger-recorded-charge field added or ledger mutated.

Regression includes unknown default0 and positive ledger value, non-completed
status default0, completed with missing/false/non-Boolean attempt fact, proven
completed zero and positive charge, and unchanged reservation2620. Projection
runner exit0 (evidence/charge-proof-green.log). Existing settlement/revocation
JVM regressions are rerun on the new runtime, with separate original compile/run
outputs. Actual Android acceptance remains blocked by the previously recorded
absent Gradle executable; no SDK retry or old unknown lookup was performed.

Use the same projection runner command above. Non-author review of this delta and
actual rerun are recorded in REVIEW.md and evidence/charge-proof-independent.log.

Fee-fix regression JVM compile exit0 and run exit0, OK (3 tests):
evidence/charge-proof-regression-compile.log and evidence/charge-proof-regression.log.
Same exact compiler/source/classpath command from the initial validation was used,
with output jar /workspace/host-projection-tools/charge-regression.jar. Run command:

```sh
java -cp /workspace/host-projection-tools/charge-regression.jar:/workspace/host-projection-tools/json.jar:/workspace/host-projection-tools/junit.jar:/workspace/host-projection-tools/hamcrest.jar org.junit.runner.JUnitCore com.mightyoung.muyon.product.chat.ProductSkillRevocationTest com.mightyoung.muyon.product.chat.CompleteResponseSettlementTest
```

Fee-fix authored source/test/docs diff-check passes; newly preserved original JUnit
charge-proof-regression.log also retains its terminal blank line, so full-archive
whitespace checking reports that raw-output warning in addition to the initial log.
No log was trimmed to hide original output.
