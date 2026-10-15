# B native ABI alignment — implementation not activated yet

2026-10-15, based on technicalC0 input8b3fd16bd07cb715af84e696061d82d13192ed40dcda889c1a1849eeb96022eb and latest authorized design SHA256a48b95af8c9430cb599f4a397f7d96ae5353159303bfdbca21c9d8c5e32e957e (root reports subsequent technicalC0 contract5be6; no policy change inferred): persistent trusted Catalog INSIDE :agent Rust worker, unchanged Linux child backend retained. User authorizes development once final design/independentC0/plan complete; no A approval or further generic permission gate. This document aligns private interfaces, not a new runtime implementation. No builds/installs/cleanup; current/tmp711MiB available.

## Ownership and runtime boundary

Plain Rust semantic controller/types live in nativehost crate; UniFFI derives/thin conversion live only in bridge crate. Core/Plugin unchanged unless root explicitly grants carve-out. `AgentServiceController` exported as UniFFI Object is Send+Sync by construction (Arc atomics, small Mutex controller data, immutable snapshots, Send root lease); it contains no Rc/RefCell session/handler/provider crossing FFI. No unsafe Send/Sync. Exactly one initialization/execution worker owns and drops the non-Send native composition and executes existing Agent drive. Control does not wait for worker queue, root file lock or busy session. Service Kotlin is platform glue, not Rust business/authority replacement.

Constructor `new(AgentServiceConfig) -> Result<Arc<AgentServiceController>, AgentServiceSetupError>` runs from Service-owned background bootstrap, not Binder/main. Config `{ protocol:u32=1, private_root:String }` is supplied only by Service Context/bootstrap, never exposed in AIDL/UI request. Constructor can create a controller/epoch and launch asynchronous inventory worker; connect may observe Initializing. Existing diagnostic functions remain byte/signature/checksum-identical. Generated files gain new definitions naturally; no manual body changes.

## Exact proposed Rust method spellings

```
connect(&self, req: AgentConnectRequest) -> AgentConnectReply
start_run(&self, req: AgentStartRequest) -> AgentStartReply
status(&self, req: AgentStatusRequest) -> AgentSnapshotReply
current(&self, req: AgentClientRef) -> AgentSnapshotReply
lookup(&self, req: AgentLookupRequest) -> AgentSnapshotReply
set_visibility(&self, req: AgentVisibilityRequest) -> AgentControlReply
release_client(&self, req: AgentReleaseRequest) -> AgentControlReply
cancel(&self, req: AgentCancelRequest) -> AgentControlReply
close(&self, req: AgentClientRef) -> AgentCloseReply
client_gone(&self, platform_client_key: String) -> AgentControlReply
await_settled(&self) -> AgentSnapshotReply
```

`start_run` is contract submit; Kotlin AIDL can call it submit. `lookup` supplies lookup/result semantic read, no execution/result recomputation. `client_gone` and `await_settled` are **Service-only platform/lifecycle FFI**, never AIDL/UI methods. `await_settled` may block/join; one dedicated Service-owned backend waiter calls it after initialization and each start, outside Binder/main. It joins outside controller mutex and then Rust (not Kotlin) validates/publishes immutable terminal/Ready/Closed snapshots. NORMAL Terminal as well as Closed requires actual worker drop/join; worker-finished alone is insufficient. Until settlement, status remains nonterminal/pending. Worker can durably write a candidate terminal before exiting, but only Rust waiter settlement publishes it after successful cleanup/join. A failed join/persistence is classified by durable receipt precedence as Unknown, never manufactured normal completion. At most1Rust initialization/run worker +1Service background join-waiter; no unbounded task queue or second waiter. close only seals admission/signals and returns Closing until settlement releases resources. Root lease remains across normal run settlement, and is released on actual closed settlement. No lock is held while join blocks; control/status remain prompt.

Constructor is called from Service backend bootstrap; before an actual Rust controller/info exists, Kotlin reports local TransportInitializing with **no invented Rust service_epoch/revision**. This is a connection state, not an AgentConnectReply. After constructor returns actual controller/epoch, connect may report Rust Initializing during root inventory. Service calls await_settled on its sole waiter to complete initialization; only then can Rust publish Ready. Failure remains explicit unavailable/RecoveryRequired. No file I/O or join on Binder/lifecycle main.

## Records (private protocol1)

All RPC replies contain `AgentReplyMeta { protocol:u32, build_identity:String, service_epoch:String, server_snapshot_revision:i64 }`. i64 revisions/generations validated0..Long.MAX_VALUE, checked increment only for actual publication, read methods copy without increment. Epoch/run/client lease IDs are Rust-generated32lowerhex. request_id uses existing ASCII safe1..64; no ID is path or authority.

```
AgentServiceConfig { protocol:u32, private_root:String }
AgentConnectRequest { protocol:u32, platform_client_key:String }
AgentClientRef { protocol:u32, expected_service_epoch:String, client_lease:String }
AgentStartRequest { client:AgentClientRef, request_id:String, variant:AgentReadVariant }
AgentRunRef { request_id:String, variant:AgentReadVariant, run_id:Option<String> }
AgentStatusRequest { client:AgentClientRef, run:AgentRunRef }
AgentLookupRequest { client:AgentClientRef, key:AgentLookupKey }
AgentLookupKey = RequestId { request_id:String } | RunId { run_id:String }
AgentVisibilityRequest { client:AgentClientRef, observation_generation:i64, visible:bool }
AgentReleaseRequest { client:AgentClientRef, observation_generation:i64 }
AgentCancelRequest { client:AgentClientRef, run:AgentRunRef }
AgentTaskIdentity { task_id:String, attempt_id:String }
AgentRunIdentity { run_id:String, admitted_service_epoch:String,
                   actual_task:Option<AgentTaskIdentity> }
AgentReceiptSummary { opaque_id:Option<String>, outcome:AgentReceiptOutcome }
AgentRunSummary { request_id:String, variant:AgentReadVariant, source_build_identity:String,
                  identity:AgentRunIdentity, terminal:AgentTerminal,
                  reason:AgentReason, receipt:AgentReceiptSummary }
AgentIntentBinding { request_id:String, variant:AgentReadVariant, source_build_identity:String }
AgentDurableRun { intent:AgentIntentBinding, identity:AgentRunIdentity }
AgentNoAdmissionSettlement { intent:AgentIntentBinding, reason:AgentNoAdmissionReason }
AgentUnresolvedObservation { intent:AgentIntentBinding, identity:Option<AgentRunIdentity>,
                             receipt:AgentReceiptSummary }
AgentRunSnapshot =
    QueuedVolatile { intent:AgentIntentBinding }
  | DurablyAdmitted { run:AgentDurableRun }
  | Running { run:AgentDurableRun }
  | Terminal { summary:AgentRunSummary }
  | SettledNoAdmission { settlement:AgentNoAdmissionSettlement }
  | Unresolved { observation:AgentUnresolvedObservation }
AgentSnapshot { meta:AgentReplyMeta, service_state:AgentServiceState,
                run:Option<AgentRunSnapshot> }
```

`AgentReadVariant=Equipment|Research|Inquiry|SeededEquipment` (seed0x7631). `AgentServiceState=Initializing|Ready|RecoveryRequired|Closing|Closed`. Use the closed AgentRunSnapshot enum above, not a phase enum plus contradictory optional terminal/identity fields. QueuedVolatile has only intent. Durable states require original durable run identity; actual_task is paired optional until State creation. Terminal requires the summary's original durable run identity. SettledNoAdmission contains **no run/task/attempt/receipt identity**, rather than filling missing values with placeholders. Root contract may refer to this lifecycle settlement as NoAdmission/NotStarted, but the record shape itself prevents fabricating a receipt. `AgentNoAdmissionReason=CancelledBeforeAdmission|QuotaExceeded|DirectoryRejected|IndexValidationRejected|StorageRejectedBeforeAdmission`.

SettledNoAdmission can be published only by Rust after the worker positively proves no durable admission/no handler effect and actual cleanup/join. Cancel/quota/mkdir or candidate-index validation may take this path if those facts are known. Failed/partial/ambiguous index publication is NOT IndexValidationRejected: preserve Unknown/Unresolved, reconcile authoritative files, and never return NoAdmission merely because a durable identity is unavailable. Known settled pre-admission cancellation is distinct from both an ordinary admitted Cancelled terminal and a lost volatile Unresolved observation. A pre-durable partial index may yield Unresolved{identity:None,receipt:Unknown{id:None}}; no durable run/task ID is invented.

`AgentTerminal=Completed|Cancelled|Failed|BudgetExhausted|OutcomeUnknown`; `AgentReceiptOutcome=NotStarted|Unknown|RecordedSuccess|RecordedFailure` exactly matches root contract. Unknown permits absent opaque_id. Running/uncommitted or persistence ambiguity dominates terminal OutcomeUnknown when a durable run identity is known; without trustworthy durable identity use Unresolved, never an invalid Terminal. Receipt success stays RecordedSuccess independent of overall cancellation. Terminal Completed additionally requires actual_task=Some(real paired State task/attempt), durable identity, receipt RecordedSuccess with actual opaque identity, reasonNone, and exact request/variant/source/admitted-epoch correlation against original admission. Other terminals may lack actual_task if State was never created, but still require genuine durable run identity. Repeated snapshots preserve exact same correlation; no synthetic replacement identity on lookup/reconnect.

`AgentReason=None|Cancelled|AuthorityDenied|PurposeDenied|ContractRejected|StorageFailure|ProviderFailure|DeadlineExceeded|BudgetExceeded|Interrupted|InternalFailure`.
`AgentServiceError=UnsupportedProtocol|InvalidRoot|InvalidRequestId|InvalidIdentity|InvalidGeneration|EpochMismatch|ClientUnavailable|ClientNotVisible|RequestConflict|Busy|Closed|TargetUnavailable|RecoveryRequired|BudgetExceeded|InternalFailure` (safe units only; no error/path/frame/exception string). Method rejections live in each reply outcome, not unstructured Kotlin exceptions.

Concrete reply records each have meta plus a typed outcome (UniFFI enums with associated records):
- `AgentConnectReply { meta, outcome: Connected{client_lease,service_state}|Busy|Rejected{error} }`.
- `AgentStartReply { meta, outcome: QueuedVolatile{snapshot:AgentRunSnapshot}|Existing{snapshot:AgentRunSnapshot}|Busy|Rejected{error} }`.
- `AgentSnapshotReply { meta, outcome: Snapshot{service_state:AgentServiceState,run:Option<AgentRunSnapshot>}|Unresolved|Rejected{error} }`. Payload has no second meta; outer meta is the sole authoritative revision for that reply. `AgentSnapshot` above is the in-memory aggregate, not a nested duplicate reply field.
- `AgentControlReply { meta, outcome: Applied|Requested|AlreadyTerminal|NotRunning|NotActive|Rejected{error} }` (method validates permitted cases).
- `AgentCloseReply { meta, outcome: Closing|Closed|Rejected{error} }`.

No shipping counters/raw/history/answer/projection/sourcefacts/authority JSON. request/control bounded4KiB, snapshot/result8KiB actual encoded Parcel checked by platform adapter plus field caps checked Rust. No generic dynamic map/policy/callable payload.

### Setup and read-only reconnection rules

Planned GREEN setup mapping (not implemented by refusing checkpoint9a7): constructor malformed/noncanonical/unacceptable root shape, owner/mode/symlink mismatch maps to InvalidRoot without OS path text. Constructor entropy/thread/setup unexpected failure maps InternalFailure; filesystem I/O/restore failure maps RecoveryRequired at setup (no fabricated Ready); a nonblocking root-lock conflict detected by background constructor/bootstrap returns public AgentServiceSetupError::Busy (mapped from internal host AgentServiceError::Busy; no controller reply/meta is invented). If root/restore failure is discovered after controller publication by initialization worker, publish service_state=RecoveryRequired; do not invent a Busy service-state variant or auto-retry. Existing independent controls remain available where a controller exists, and no second worker is started. Runtime persisted data/index corruption maps RecoveryRequired rather than InvalidRoot or a new empty store. Inventory/storage failures after volatile start use SettledNoAdmission only with affirmative no-admission proof; ambiguous writes use Unresolved/Unknown. These are safe closed mappings; precise runtime publication may be connect service_state Initializing/RecoveryRequired with last setup error, never a successful run.

connect in Closing/Closed may issue/reuse at most2 bounded **read-only reconciliation leases** for a live registered key, returning actual service_state and epoch/revision. Such a lease permits status/current/lookup, not start_run or visibility=true reopening. An ordinary lease also becomes read-only when runtime closes. set_visibility(false), release/client_gone and idempotent close remain safe stop operations, but cannot reopen a closed runtime. A replacement Service instance gets a new epoch and must initialize/reconcile old evidence before Ready; no connect or lookup resumes execution. This gives a precise UI-death/rebind reconciliation path without manufacturing a new runnable controller.

## Platform liveness translation and race rules

Kotlin Service owns a bounded registry mapping real UI-process liveness Binder identity to `platform_client_key` (private32hex correlation token), links death before connect, and does not accept that key as client-supplied AIDL data. Same live Binder repeated connect maps same key; Rust returns same lease in same epoch without using another of max2client slots. Kotlin translates Binder death to `client_gone(key)`; Rust invalidates matching lease and signals owner's active run. It must not create a new client/epoch or reinterpret liveness as authorization. Death during registration must be remembered so an already dead key cannot gain a live lease. Neither callback nor visibility/release can borrow Rc/session. Rust still owns all grants/purpose/receipt decisions.

Rust validates current epoch/lease before mutation; observations monotonically checked per client (same generation/same value idempotent; old/conflict rejects). client_gone/release invalidate old lease. Keep at most2bounded client slots; recycled slots must get a fresh Rust lease ID, never reuse old lease IDs, and private Binder registry must not resurrect a released/dead key. Stale release/gone cannot touch a replacement slot. A released but still-live Binder retains a bounded tombstone and repeated connect does not mint a replacement key/lease; dead Binder registry entry may be removed, but its private key is never reused and any late gone callback remains correlated to that retired key. Registry including tombstones has a strict2entry cap, not unbounded churn. Cleaner/ArcDrop is never the explicit control/cleanup guarantee; fresh Android API24 generated-object Cleaner compatibility remains a build/runtime gate. Final visible lease=false seals new admission/signals cancellation/closing; later visible=true cannot clear an issued stop or restart. status/current/lookup remain bounded reconciliation copies only. Old epochs cannot control new runs; lookup under current lease can identify prior admitted epochs.

Same request_id+exact immutable variant/protocol/source returns Existing without executing; changed binding returns RequestConflict. Queued !=durable acceptance. Worker under exclusive RootLease performs bounded inventory/quota reservation/run mkdir/durable index before publishing DurablyAdmitted. task/attempt created by actual State, then paired/persisted. current returns unique outstanding/reconciliation or latest terminal and original binding, not a guessed new request. No query scans disk on Binder path or resumes Agent. Close/release/clientgone do not release the occupied execution slot until actual drop/join/root lease cleanup. Missing ID or transport reply is observation uncertainty, not NotStarted.

## Minimal source split / checkpoints

1. Nativehost `contract_transport.rs` private trait, persistent bounded Catalog adapter, existing PluginProcess wrapper unchanged; inject into NativeSession internal constructor. Keep Linux child tests/backend and child_pid evidence applicable only there. Plain request/reply bound/parse/fatal/close parity. New worker/control/limits hooks remain host-owned.
2. Nativehost `service_types.rs`, `service_controller.rs`, `service_store.rs` (bounded index/root quota), `service_worker.rs` (trusted built-in composition/one drive). Plain Rust DTOs; no UniFFI dependency into host/Core/Plugin. Reuse existing physical handlers/sourcefacts/purpose/receipt/model final-byte barriers, add optional cooperative control/one-read/turn2subset guards without changing legacy backend semantics.
3. Bridge `agent_service.rs` thin UniFFI records/Object/delegation. Add host path dependency and refresh owned lockfile only; no gratuitous new runtime crates. `lib.rs` only module/reexport; old diagnostic functions and parameter spellings untouched. Existing Android/JVM config/package/cdylib names retained. No fixed expected test count before tests are defined.

Test-first small commits: freeze DTO/method inventory+compiling refusing controller/tests first; provide exact source SHA and named primary Rust/JVM targets/markers to checker before run. Proposed primary targets `service_controller_executes_registered_read` (Rust) and checker-owned real generated JVM equivalent: reach accepted actual runtime seam before positive terminal/receipt assertion fails; no compile/load/setup/timeout RED. Need a bridge-reachable guard distinct from older native-host stub, e.g. `AGENT_SERVICE_STUB_REACHED`, positive assertion `AGENT_SERVICE_RED: admitted run must complete the registered physical read`. Primary guard must prove original request/run reaches service native path; later stage actual same-drive reachable guard is required before claiming native dispatch RED. Parent/checker freeze guards/counts from test sources, not output. Preserve refusing fixed checkpoint while GREEN lands separately after actual Rust+JVM semanticRED.

Then minimal GREEN increments: transport parity; async controller/index/liveness/controls; actual bounded worker/registered two-turn chain; FFI/runtime validation. Tests include paired actual identity, root peak2MiB including index, quota8runs8MiB, partial index→Unknown, dedup/current/lookup no handler, cancel provider/prepostread, old epochs/generation, release/gone/lastvisible, join/Closed, one read/turn2empty, all4variants, originalreceipt/finalpayload inverse. Original regressions and new checker negatives/mutations are independently owned; no local large mutants/Android build.

Generation ownership: native writer builds only small shared release target or uses remote if711MiB budget insufficient; generate fresh Android+JVM bindings into private/tmp and provide exact source/lib/default-vs-probe/config/lock/generator/generated hashes. UI alone copies actual Android generated source and owns Service/AIDL/adapter/state. Checker independently generates JVM binding, runs actual FFI RED/GREEN/probes, remote API24twoABI/package gates and verifies committed Android bytes. Added API necessarily expands generated file; old diagnostic names/field/signature/checksum must remain identical (whole generated file cannot remain byte-identical after new exports). Never overwrite preserved initial/source-matched libraries with another feature build. No new toolchain/target/NDK/SDK/license install or cache cleanup in this alignment task.

## Authorized late-bootstrap retirement closure

Root authorizes exact additional Service-only FFI method `retire_service(&self) -> AgentCloseReply`, not AIDL, no argument/lease. The actual controller object scopes the operation to that instance/epoch; it always permanently seals admission and signals stop, including Initializing/zero-client bootstrap. Captured retired platform generation invokes it only on the late returned original controller, never a replacement. Idempotent and never creates a client/lease; actual Closed still requires await_settled/drop/join/root lease release. It closes the late-constructor/no-connected-lease hole without fabricating epoch/lease or taking a third client slot. Native first checkpoint includes a zero-client initialization-retirement positive target; UI separately tests late bootstrap generation.

The plain host internal config is `AgentHostServiceConfig {protocol,private_root,build_identity}` with a validated trusted40hex source identity, no host build environment requirement. Bridge public `AgentServiceConfig {protocol,private_root}` injects only existing compile-bound MUYON_BRIDGE_BUILD_ID. No UI/AIDL caller can choose source identity. Authoritative PUBLIC constructor error is `AgentServiceSetupError = UnsupportedProtocol | InvalidRoot | Busy | RecoveryRequired | InternalFailure` (all unit variants), as fixed9a7 bridge/src/agent_service.rs:53–58,73–89. Internal host constructor still returns `AgentServiceError`; bridge maps its UnsupportedProtocol/InvalidRoot/Busy/RecoveryRequired one-to-one and every other internal setup failure (including invalid trusted build identity) to public InternalFailure. This is an explicit bounded setup conversion, not a change to the separate public business/control AgentServiceError reply enum. Business/control methods keep safe typed reply outcomes, never throw this setup exception. Fixed9a7 currently validates protocol/build identity/entropy and otherwise refuses runtime execution; desired root/storage/lock mappings above remain GREEN requirements after both RED gates. This preserves old host workflow environment and keeps existing diagnostic ABI untouched.
