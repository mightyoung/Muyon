# UI host continuation — source delivery, Android acceptance open

Branch task/ui-host-projection-20261022; preceding implementation baseline
98e5b6529cfbd9313c5fea73db168eebcfd4cfbc. Protocol was written and pushed first at
473c13f13403f309b269caf258b1b7410af09b06, before implementation. The following
implementation commit on this branch is required to call the new endpoints.
UI-HOST-PROTOCOL.md is the authoritative schema1 contract. chat_snapshot schema1
is unchanged and remains compatible with the sole shell owner's strict consumer.

Read latest remote shell NEXT-BATCH.md and READ-ONLY-SNAPSHOT-BATCH.md, actual
CardModels.kt, BotSetupDraft.kt, configuration README/editor and AgentCatalog.
No newer runtime source was taken from shell or overwritten. Only production
files modified: ProductChatRuntime.kt and ProductService.kt. No ChatScreen,
MainActivity, ui components, canonical Bot reducer, Rust/FFI/documents or database
write workflow changed. Dedicated projection tests/runner and evidence are included.

## Real interfaces now implemented

Existing ProductClient.call handles both new names through the existing private
Service lease. Outer status=ok/data wraps each inner result; inspect inner status
and current mounted scope before rendering. No endpoint is registered as a model
function, and no rendered/model command selects backend behavior.

### chat_card_candidates / schema1

Payload original request_id + displayed conversation_id + nullable project_id +
actual integer scope_generation (from chat_scope). Same original provenance checks
as chat_snapshot run before the one local original lookup. Response read_only /
projection_type=card_candidates embeds the original chat_snapshot schema1 and a
finite request_observation candidate. It exposes the original native request and
native child conversation, plus the original configuration_id only if actually
provided by the native AgentPlan at preparation. Native observation excludes answer,
commands and payload bytes. Unknown charge0/positive remain actual null; only the
reviewed completed+attempted Boolean true proof may expose actual cost.

Only explicit query_original is a supported local read. can_execute/can_cancel are
false and binding is null. Newer prepare/configuration never substitutes a latest
request or fills a missing old configuration identity. This finite-kind read-only
candidate is not a fully bound ReceiptCardModel/OriginalCardRequest: missing card
identities, digest, business intent and CAS still prevent actionable typed adoption.

### chat_setup_draft / schema1

Payload displayed conversation_id + nullable project_id + actual integer
scope_generation + operation object. Workspace/session derive exclusively from
Service, with existing UID/epoch/client checks. The serialized runtime owns one
actual BotSetupDraft per live scope, reusing that existing reducer without copying
its state machine or accepting passive creation observations.

Finite operations: open/read, edit_name/edit_purpose/edit_role, next/back,
suggest_role/accept_role, cancel/resume. open is idempotent for that scoped draft;
read addresses exact local_draft_id. All mutations require exact local_draft_id and
the expected_local_revision from the displayed response, with value or suggestion
request ID where required. Stale/repeated mutations reject before applying; no
latest-revision substitution or automatic retry. Operation keys, revision integer,
String values and allowed state transitions are checked. Suggestion is solely the
existing deterministic local template; accept requires its actual original token
and cannot overwrite user-locked role. Edits/cancel invalidate old tokens.

local_draft_id is the actual ephemeral reducer UUID, local_revision is an actual
host memory CAS counter for accepted LOCAL operations, and reducer_revision is the
canonical reducer counter. These are explicitly not original business intent,
component revision, saved version or created Agent identity. next/back availability
matches the actual step/required fields; cancelled drafts advertise only open/read/
resume, with the same enablement list checked by the handler.

This API calls no ProductChatPort, transport, credential, AgentCatalog, create,
provider, document registry or persistence API. Local snapshots are detached.
Scope invalidation and session release discard local drafts. Capacity32 affects
only opening a new local draft, preserves existing drafts and adds no business
request gate. Persistence, backend create/start/query are not implemented:
saved/can_save/can_create/can_start=false; creation_status=not_requested; actual/
reserved/agent/intent/binding remain null. capability_metadata_status and
material_metadata_status are unavailable; empty offers are not a claim about the
underlying permissions, capabilities or documents. No alternate document/material
truth store, source ID/version or anchor is invented. Any future material offers
must use the shared authorized Rust documents producer.

Shell must choose one local draft source of truth; do not keep both the old
UI-only reducer and this IPC reducer independently editable. Existing editor may
remain until shell owns its actual adaptation. No screen integration is claimed
by this host branch, and no backend save/create confirmation may be enabled.

## Actual verification and retained outputs

Kotlin2.2.20/JDK21 with actual org.json20250517. New runner compiles actual
ProductChatRuntime/ProductSendGate/ProductHttpsTransport/BotSetupDraft sources;
local/private ports are fixtures and transports throw if reached. No real Service,
credential, original unknown, network/model/search or paid operation was exercised.

1. Test-first RED before new APIs existed: compilation exit1, unresolved setupDraft
   and cardCandidates. evidence/continuation-red.log retained unchanged.
2. Current runtime/projection + host setup runner exit0, two PASS lines:
   evidence/continuation-green.log. Covers original identity after newer request/
   configuration, cross-scope/generation, unknown actual0, missing configuration,
   disabled business operations; actual local UUID/CAS/repeats, stale ID/revision,
   numeric/null/invalid text, exact operation keys, state-based next/back/suggestion,
   suggestion token invalidation/manual lock, cancel/resume, field detachment,
   release/remount and capacity32 preserving existing drafts. Setup portCalls=0.
3. Existing canonical Bot checks exit0, 11 checks:
   evidence/continuation-bot.log; configuration editor checks exit0, 5/5:
   evidence/continuation-configuration.log. Neither dependency source was edited.
4. Existing settlement/revocation JVM tests compile with canonical Bot dependency
   and run exit0, OK (3 tests). evidence/continuation-regression-compile.log and
   evidence/continuation-regression.log. No Android instrumentation claim.
5. Independent non-author static review plus current actual runner rerun exit0:
   evidence/continuation-independent.log. Reviewer flagged initial local operation
   availability; fixed by shared projection/handler guard and step/empty-field tests.
   Strict String input handling recommendation also implemented and verified. No
   remaining new blocker in this host scope. REVIEW.md records the review.
6. Actual Android full-suite attempt exit2, before compilation:
   NOT_RUN: set MUYON_UI_GRADLE to the existing Gradle8.13 executable.
   evidence/continuation-android.log. This selected workspace has no usable existing
   Gradle executable. Prior remote shell evidence describes its own Gradle/AGP
   failure; no result is borrowed. SDK failure is not retried/relocated/bypassed.
   Service Android compilation, lint, instrumentation, device and accessibility
   validation all remain open.
7. Authored source/test/docs whitespace checks pass. Original JUnit terminal blank
   line remains in the new raw regression log; full-archive whitespace checking
   will report this raw-output warning, as with previous evidence. Logs untrimmed.

Commands from repository root:

```sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc JSON_JAR=/workspace/host-projection-tools/json.jar bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/configuration/run-offline-checks.sh
java -cp /workspace/host-projection-tools/continuation-regression.jar:/workspace/host-projection-tools/json.jar:/workspace/host-projection-tools/junit.jar:/workspace/host-projection-tools/hamcrest.jar org.junit.runner.JUnitCore com.mightyoung.muyon.product.chat.ProductSkillRevocationTest com.mightyoung.muyon.product.chat.CompleteResponseSettlementTest
```

Regression compile: same actual sources/JUnit arguments as initial report, with
canonical agents/setup/BotSetupDraft.kt additionally passed to Kotlin compiler and
output continuation-regression.jar. New runner already includes that source.
No Android stubs or platform replacement supplied. Existing cards45/contracts20
results from the previous batch are retained as historical validation, not relabelled
as rerun in this batch (their source is unchanged).

Android command from apps/muyon_android:

```sh
./gradlew --offline --no-daemon --console=plain :app:testDebugUnitTest :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest :app:lintDebug
```

## Remaining real gaps

Full typed CardBinding/message/component/attempt/original-intent/CAS host producer;
authorized task/source/attachment/material/report versions and anchors from shared
Rust documents truth; trusted persistent draft/create/configuration/Agent execution
backend; actual shell integration; Android build/device acceptance. No placeholder
identity, digest, revision, saved/created result or business data closes these gaps.
Parent coordinates exact backend contracts. Native confirmation/cost gates remain.

Historical two unknown and ¥0.002620 held untouched. No main/develop changes,
merge, force push, deletion, deployment, paid CI dispatch, credentials or permission
expansion. Leader B remains sole develop integrator. This delivery extends the
host read/local-draft API only; it is not all UI development or actionable-card
completion.
