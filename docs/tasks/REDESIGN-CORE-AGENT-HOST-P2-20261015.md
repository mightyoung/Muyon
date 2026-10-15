# Product Rust Agent host seam — Dart checkpoint

Status: **API/stub checkpoint; runtime validation NOT_RUN locally**.

The existing `PersonalAgent` and `MuyonHost.open` now accept nullable
`coreAgentProcess`. `CoreAgentProcessConfig` defaults to disabled and requires
explicit executable/state paths. Enabled relative paths fail with the fixed
`core_config_invalid` error. Disabled paths are unused.

A valid enabled request enters the real facade's existing task factory,
persists its normal task and user message, then terminates that task as failed
with `core_backend_unavailable`. It does not invoke the legacy model loop. This
deliberately incomplete behavior is the immutable semantic RED checkpoint for
the independently owned host integration tests.

`MuyonHost.open(modelClientFactory: ...)` passes its optional testing transport
factory directly into the existing shared `OpenAiModelGateway`. The gateway's
authorization, outbound ledger and production default transport remain in place.
No model/profile/credential configuration enters the process API.

Local `dart`, `flutter` and `cargo` executables are absent. No runtime or analyzer
pass is claimed; root will run the existing GitHub runner against this compiling
API candidate and preserve its first semantic test failure before full behavior
implementation. No tests, business handlers, registry, grant policy, old runtime
defaults, or Rust sources changed at this checkpoint.

## Full adapter implementation checkpoint

The compiling stub is preserved at `3a37c8fccd7c0cde0c944ece41c600c006380e2e`.
Root verified actual semantic RED in CI38686248722 at exact combined
313bcc8b9f432774c7bd47da9f979c77adaebc96: successful Rust offline build,
Flutter dependency setup and compilation, then the positive product task assertion
expected succeeded / actual failed. Raw evidence is external at
`/tmp/rd-core-agent-host-evidence-20261015/dart-red-first-full.log`.

The enabled facade now persists its backend ownership and services the common
Rust Agent's callbacks through a private, bounded child session. The child gets
only sanitized prompt, actual registered descriptor, correlated callback replies
and five-field typed reference projection. Process environment is explicit;
strict UTF8/JSON framing rejects duplicates, unknown fields, malformed types,
wrong correlation and oversized aggregate traffic. One session, two model turns
and one actual readonly invocation are bounded separately from legacy execution.

`AgentModelTurn.preparePermission` accepts an optional exact `ModelRequest` and
shares the existing HostModelAuthorization payload review helper. Core callbacks
map registered/native function names through the existing frozen name helpers,
construct the exact request and digest, obey category gate and effective review,
and enter the original gateway under its one-use permission and beforeSend
scope/profile/memory/policy checks. GateConfirm alone does not imply manual review.
The legacy caller retains its original request construction and compatibility
payload behavior. No fallback, automatic capability changes or approval creation
is introduced.

Readonly authority follows the existing registered read path: actual prepare,
current category/scope/identity checks, invoke and receiptFor. Root corrected an
earlier proposed extra readonly reviewer gate; no effectIntent, grant, approval
or new read-content requirement is invented. Inquiry invocation and actual object
source facts are marked through the same authorizationFacts rules as the existing
AgentDispatch. Original result and receipt stay host-local, and their invocation
link is stored before admission. Successful projection uses actual returned
version metadata and excludes record, name, summary and nativeProjectId.

Existing gateway.mask handles credential echoes before any provider answer,
call identity, prompt or projected metadata can enter IPC; frozen profile fields
are also excluded. Tools with a sensitive identity are refused rather than
rewritten. This can read the synthetic SecretStore for masking independently of
the two actual model sends; gateway ledger rows remain the send evidence.

Cancel/close abort model requests and send process controls. Once admitted, a
read drains to its original receipt instead of cancelling its tool token; no
subsequent callback starts. Child exit/reap precedes facade completion. Stored
backend ownership fences resume, pause, confirmation, compaction and optional UI
continuations across restart. Legacy startTool and disabled backend remain intact.

Root extended Task2 ownership to
`apps/muyon/test/core_agent_process_owner_test.dart`: unsafe optional metadata
is rejected, and real in-memory registry reads are held behind Completers so
cancel/close occurs after admission and before original return. These are narrow
owner unit boundaries, not substitutes for the independent compiled Rust/product
roundtrip. Test/analyzer runtime evidence will be updated after execution.

The preinstalled SDK became available during implementation. Formatting and a
focused analyzer run succeeded using cached packages, temporary analyzer state
and `DASH__SUPPRESS_ANALYTICS=true`; HOME was not changed for these checks. No
package install/download, model service, credential configuration or real data
was used. Full combined runtime, independent checker, inverse controls, non-author
review and exact terminal CI remain root integration gates; this checkpoint does
not claim product GREEN, device acceptance or M03 completion.

## Non-author review round 1 and first combined runtime

Fixed-source review of b3f012e requested three Important corrections and one
Minor call-ID correction. The first actual combo CI38687677301 at root5e9b81a
had45 passing /5 failing product tests; its unchanged raw first-failure log stays
at `/tmp/rd-core-agent-host-evidence-20261015/first-combo-live.log`. Corrections
below are source fixes awaiting exact combined runtime verification, not a claim
that a source inspection turned those failures GREEN.

| Review / evidence | Owned source correction | Covering evidence |
| --- | --- | --- |
| T2-I1: admitted unknown, accepted result, early close settlement | fdf2067/e77165b: adapter owns core close finalization; accepted projection distinguishes known result; d1f3019: shared production failure selector includes framing/aggregate host_budget before matching result | Real registry Completer tests preserve original read on cancel/close; oversized_header/aggregate barriers exercise actual parser and shared failure selector before/after accepted projection. Independent cancel-second-model/close tests cover product paths; full repository lifecycle review/CI remains a gate. |
| T2-I2: clean EOF | 3000d51: clean EOF maps interrupted/host_eof; truncation remains failed/host_protocol before admission | Existing independent clean_eof oracle retained. |
| T2-I3: queued cancellation lost before active session | 3000d51: synchronous queued revocation plus persisted cancelled state; run refuses terminal/revoked task before launch | Actual PersonalAgent start/cancel test pauses appendMessage after task publication and checks cancelled/no process-state directory/no tool receipt. |
| T2-O1: C1 call-ID controls | a390683: reject C0/C1 and unpaired UTF16, retain valid Unicode scalars | Owner call-ID unit checks C1, Chinese/emoji, valid U+FFFD, malformed surrogate and byte limit. |
| Cross-runtime JSON history ordering | 5579708: compare embedded arguments/projection as strict parsed structures; retain exact role/call/tool pairing; authorize the actual received Rust messages | Rust owner confirmed BTreeMap key reserialization. Independent positive keeps its original paired actual-result assertions. |

The read-category pre-start test had an independently identified overstrong
expectation: AgentTaskFactory already filters unavailable categories, so zero
model sends/ledger/launch is the actual path. No policy checks were relaxed to
force preparation. CoreAgentModel's ModelPolicyGuard remains unchanged from the
initial full implementation, including its checks after a response.

Local owner-unit execution was attempted with the preinstalled Flutter snapshot,
`--no-pub`, analytics suppressed and unchanged HOME. It loaded zero tests because
the clone lacks `.dart_tool/package_graph.json`; this is setup failure/NOT_RUN,
not a test pass or semantic RED. Raw log:
`/tmp/rd-core-agent-host-reports-20261015/evidence/task-2/owner-units-first.log`.
No packages or SDK updates were installed to bypass it. Root's full regression
and dedicated actual-Rust host workflow remain required to execute these tests.
