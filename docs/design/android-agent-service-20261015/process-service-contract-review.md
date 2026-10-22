# Independent review — whole Rust Agent in Android Service (B)

2026-10-15. Original non-author reviewer. **Read-only: zero product/source changes, zero new tests/builds/device/model/credential operations; no commit, push or merge.** Official Android/AOSP documentation was consulted today. Existing code and earlier CI establish reuse, not execution of this proposed Service.

## Fixed target and verdict

Final contract: ANDROID-AGENT-SERVICE-SLICE.md, SHA256 **5be6a11739f3d48153c18631ebbe9473bff7e2aa9adb7f44cc5a3ca5f8c58e18**. Four process-options reports support the assessment; the consolidated contract supersedes their alternative callbacks, counters and interfaces. Exact hashes are in process-service-contract-review-inputs.json.

Source **0ab2c4f667681b9aacb017f8cd2eea6f576cf78e** was independently fetched and verified: parents a01dcc83348c705fb8c6e3905aa9df8999058b1a +6e3b5eacc25e4d81f9bde658b643e9f8c3af31ef; tree **bca71d8794edab6c63989f6cdfebbca32d059c03**, identical to locally read6e. Root source worktree remains clean. Manifest/Application were additionally read directly from0ab Git objects: no Service exists; diagnostic construction is lazy, not an existing Agent startup.

**SPEC PASS / QUALITY C0. Critical0, Important0 open, Minor0 open.** Two Important protocol gaps in initial aff0fc2 were corrected in c22631fa and rechecked. 8b3 clarified snapshot equality. Final5be6 records the subsequent explicit design-to-development authorization and selected inner backend, plus concrete asynchronous bootstrap/join ordering, all rechecked below. This is contract feasibility/consistency, not implemented behavior or runtime acceptance.

**B is required; A as first slice or transition is rejected.** No A approval, implementation or milestone is a prerequisite. Linux/JVM engine validation supports B directly. The user subsequently authorized development after design completion. Under that authorization root explicitly selects persistent trusted Catalog inside the :agent Rust worker, retaining Linux child as a separate regression path. This is a disclosed design decision, not an assertion that the user separately uttered an inner-backend choice. No generic approval gate remains; root can align the implementation plan/ABI and activate the original owners after this nonblocking review.

## Independently checked platform facts

- `android:process=":agent"` selects an app-private process; isolatedProcess is a separate setting. Ordinary B separates memory/process failure from UI, but adds no UID permission boundary. Android's UID sandbox covers native code. Same-UID storage reuse is therefore a reasonable design inference, not a measured Android result. C has no own permissions and cannot be assumed to open the unchanged UID/0700 root. [Service manifest](https://developer.android.com/guide/topics/manifest/service-element), [AOSP Application Sandbox](https://source.android.com/docs/security/app-sandbox).
- Remote AIDL calls may arrive concurrently on Binder pool threads; oneway is asynchronous transport, not durable admission. Service lifecycle callbacks do not supply a safe execution worker. Short IPC/control plus one Rust-owned worker follows these constraints. [AIDL](https://developer.android.com/develop/background-work/services/aidl), [Processes and threads](https://developer.android.com/guide/components/processes-and-threads).
- A pure bound Service normally loses its lifetime after the last client unbinds. Separate placement does not guarantee background completion or survival. The visible/bound scope and explicit drain policy make no such claim. [Bound services](https://developer.android.com/develop/background-work/services/bound-services).
- Binder's documented1MB buffer is shared across in-flight process transactions. TransactionTooLargeException cannot establish whether request or reply delivery failed. Small4KiB/8KiB application limits are useful but not delivery guarantees. DeadObjectException can also represent lower-level Binder failures, not only confirmed process death. [TransactionTooLargeException](https://developer.android.com/reference/android/os/TransactionTooLargeException), [DeadObjectException](https://developer.android.com/reference/android/os/DeadObjectException).
- Disconnection may reconnect; dead binding requires unbind/rebind. onBindingDied starts at API26 and onNullBinding at API28. The contract correctly includes API24 connection/death/timeout handling and treats reconnection separately from replay. [ServiceConnection](https://developer.android.com/reference/android/content/ServiceConnection).
- Process death does not promise lifecycle cleanup. Android10's writable-home exec restriction has specific target/version conditions; it is not a general ban on Android multiprocess applications. [Process lifecycle](https://developer.android.com/guide/components/activities/process-lifecycle), [Android10 execute restriction](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission).

These platform facts do not prove this app's actual PID/UID, remote Binder execution, SELinux behavior, JNA loading, file locks/fsync or death recovery.

## Existing source and genuinely new work

The existing runtime entry delegates to one private Agent drive (`core-agent-lab/core/src/agent.rs:209–249`). Native host already owns registered dispatch, current authority/purpose, physical handler, original raw receipt, projection/history and final model-byte admission. The old child executes Catalog metadata/tickets, **not business handlers** (`rust-agent-host-lab/core/src/lib.rs:337–445`, `read_registry.rs:73–119`, `model_gateway.rs:31–76`). No second Agent loop or Kotlin policy implementation is necessary.

NativeSession still owns concrete PluginProcess and Rc/RefCell-local state. Its current local cancel/failure behavior is not a Service protocol. NativeStore has strict original evidence but no durable Binder request→run index or full live-session recovery. Application singleton/slots are process-local; metadata FFI proves no Agent runtime. Service/Rust control, durable admission, queries, RootLease, epochs and recovery are therefore real new adapter work.

For the explicitly selected inner backend, use one persistent Catalog through bounded request/reply serialize/parse admission, fatal versus recoverable errors, wire-close versus transport-close, generation/ticket semantics and no fallback. Keep Linux child as a named regression path. That backend provides no inner child isolation/kill/reap. A separate Android contract Service is outside this selected slice and would need another IPC/death/lifetime contract; current POSIX child packaging/execution is unproved. The selected design does not restore A.

## Durable admission and recovery

Two-stage acknowledgment is coherent: short submit reserves the only volatile slot; only the worker can publish DurablyAdmitted after original request/run/variant/source/admission-epoch and pending evidence are durable. Neither Queued nor durable admission proves authorization, task creation or read completion. Task/attempt remain paired optional actual identities.

Same immutable request returns Existing; changed binding conflicts. Startup reconciliation precedes Ready. `current` recovers outstanding identity after UI memory loss. Current/lookup/result never creates attempts, grants or reads. Controls and submit bind current epoch/lease; historical lookup cannot control a replacement incarnation. No lifecycle callback, missing reply or reconnect submits work again.

The new lifecycle index is not another raw receipt owner. Implementation must freeze ordered writes and recovery validation across index/pending/task/native.db, including each crash boundary. Missing/corrupt metadata cannot prove NotStarted. Running/uncommitted/uncertain evidence stays Unknown/OutcomeUnknown; recorded raw success survives cancellation. Historical facts do not restore live authority or resume Agent. This preserves begin-before-handler and raw-before-projection.

## Thread, storage and control assessment

Service owns the root and actual execution slot; UI owns proxy/presentation only. Multiprocess Application initialization must not create Agent in UI or use diagnostic lazy initialization as an Agent bootstrap. Same UID does not justify concurrent writers.

Initialization, execution, filesystem access and join stay off Binder/main threads. Queries copy bounded immutable state; a separate bounded client control channel plus Rust control signal avoids queuing cancellation behind blocked submit/status. Control touches neither busy Rc nor root lock. Signal must actually reach provider polling, pre-handler, raw-preservation and final-send boundaries; declaring an AtomicBool is insufficient.

RootLease spans the live runtime and all workers; conflicting ownership refuses.8dirs/8MiB and2MiB transaction reservation include new index/summary/temp remnants. Actual file-layout/scan/high-water proof and pre-read/prewrite guards remain implementation requirements. No automatic reset, cleanup or replay; Android syscall assumptions remain unverified.

Graceful Closed requires actual worker/drop/join and resource settlement; it does not assert PID disappearance. Service death and transport loss remain observation facts, not cancellation or zero-read proof. Visibility loss stops admission and requests cancellation/close; panel detach does not. Rotation keeps identity but explicitly may trigger cancellation if the last visible lease goes false. Visibility return cannot clear cancellation or resume. Normal terminal permits only a new explicit user action; closed runtime cannot reopen.

## Findings and closure history

**B-I1 — Important, CLOSED.** Initial aff0fc2 required last-visible-lease cancellation while retaining binding for drain, but defined no visibility/release IPC. Liveness death cannot tell the server a still-alive UI moved to background; repeated connect could exhaust two leases. c22631fa adds epoch/lease/generation-bound set_visibility/release_client, same-token idempotent connect, initially invisible admission, stale/conflicting update refusal and release-not-slot-release. Rotation interruption policy is explicit rather than promised away.

**B-I2 — Important, CLOSED.** Initial epoch/run identity checks did not order delayed same-run submit/status/control replies. Old Running could replace Terminal without an identity change. c22631fa adds server snapshot revision, local connection/lease/display generations, older-revision rejection, terminal non-regression, distinct historical presentation and checked nonwrapping bounds. ObservationUnknown is distinct from Rust terminal.

**B-O1 — Minor clarification, CLOSED.** Final8b3 specifies equal-revision equality for the same observation key and authoritative snapshot; unrelated cancel ACK/status RPC envelopes are not compared as equal values. This is the only change from c22631fa and resolves the implementation ambiguity.

## Evidence gates and recommendation

The three layers remain correctly separate:

1. Actual compiled Rust/matching generated Linux JVM: new control/admission interface, existing drive/physical source/original receipt/exact second payload, four mappings/canary, strict transport, duplicate/conflict, unknown/join/quota and guard inverses. Nonshipping probes must not replace shipping driver/policy. Compiled semantic refusal is RED; load/setup/timeout is INVALID.
2. Android compile/package: fresh API24 two-ABI host dependency, AIDL/Service/manifest, binding/ELF/import/JNA/exact APK bytes, lint/zipalign and no-native build. This establishes build/provenance, not process execution.
3. Authorized Android runtime: actual distinct UI/Service PIDs, expected UID relation and remote Binder proxy; same native chain; phase-barrier service death and reply-loss siblings with original evidence and zero re-dispatch. UI death, last-visible/unbind, service death, low-level Binder error and graceful close must be separate. Host SIGKILL or fake RemoteException cannot stand in for this gate.

Negative targets include before/after durable admission; receipt-begin before read; read before raw finish; raw before terminal; terminal before reply; stale visibility/control generations; same-epoch reply ordering; same-token reconnect without lease leakage; current recovery after lost UI identity; root lock/incomplete evidence; bounded RPC traffic. Use deterministic barriers and independent source-frozen oracles. Keep old native/child/metadata/UI regressions, without counting them as B proof.

**Recommend publication and implementation-plan/ABI alignment, followed directly by original-owner TDD activation for required B.** The latest user authorization already permits development after design completion; no A prerequisite, unresolved inner-backend choice or generic approval flow remains. Root remains sole integrator. Device execution and new external permissions/resources are not inferred from this contract review.

All new B runtime/test/build results remain **NOT_RUN**. Android Binder scheduling, PID/UID isolation behavior, ART/JNI, filesystem/lock/fsync/process-death/lifecycle and4KB/16KB execution are unverified. Real model/credentials/business data, broad sandbox claims, public M03, foreground/background daemon scope and arbitrary plugins remain outside this slice.


## Final authorization and ABI ordering recheck — 5be6a117

The latest contract explicitly selects trusted persistent Catalog within the whole Agent's independent :agent process and preserves Linux child. Earlier report alternatives/pending-choice wording are historical and superseded. This selection does not change the already reviewed no-UI-Agent ownership, no arbitrary plugin isolation claim, same drive/authority/receipt rules or evidence limits. User authorization is recorded precisely as design completion followed by development; root's selected implementation detail is not presented as another user statement.

The concrete bootstrap/join clauses are consistent with the reviewed lifecycle:

- Before Rust controller construction completes, Binder exposes only TransportInitializing with no invented Rust epoch, lease, Ready or admission. A platform-owned service/connection generation invalidates delayed initialization when close/client death/service destruction occurs; late controller results are closed and drained off-thread, never published Ready.
- One native runtime gate and cross-process RootLease exclude a replacement worker during old initialization/cleanup. This must be covered by constructor-delay/close/new-bind negative tests rather than assumed from per-process Kotlin singleton behavior.
- At most one Service-owned background waiter calls internal Rust await_settled/join_worker. This is not an AIDL method; Binder/main/admission locks never join. Rust alone reconciles and publishes normal Terminal and Closed after actual worker/drop/join. Kotlin schedules the wait but does not decide business outcome.

No new technical finding arises from this final delta. **SPEC PASS / QUALITY C0, Critical0/Important0/Minor0 open.** All new implementation, tests/builds and Android execution remain NOT_RUN at this review; no product code was changed.
