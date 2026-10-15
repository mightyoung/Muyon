# Next real Agent slice — checker feasibility, read-only

Status: proposal only; no source/API/fixture/workflow implementation or new test execution. No model, credentials, device, installation or permission expansion. Original checker/native/UI writers and clean checkpoints remain preserved. Parent must approve the contract before source work. This report describes verification feasibility, not completed new Agent integration.

## Fixed evidence and source identity

Baseline merge `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e` has remote Git tree `bca71d8794edab6c63989f6cdfebbca32d059c03`, independently read from ordinary GitHub commit JSON. This exactly equals validated parent `6e3b5eacc25e4d81f9bde658b643e9f8c3af31ef`'s local Git tree. Read-only local6e source therefore represents postmerge0ab byte-for-byte. Selected source SHA256 map: `next-agent-checker-source-identity.json` beside this report.

Existing real evidence:

| Existing gate | Actual evidence | What it establishes |
|---|---|---|
| Metadata FFI | Dedicated38737340099@6e SUCCESS; task2-final-38737340099.log/observation.json | Rust9, generated Linux/JVM real native7, Android API24 twoABI link/ELF, binding bytecmp,67state,lint,APK/testAPK/sixnativehash/zipalign. It executes metadata Catalog inspection, not Agent/business read. |
| Native Linux Agent | Explicit38737375497@6e SUCCESS; final-legacy-rust-38737375497.log | Core94/plugin21/host25, process44/harness13/old17mutants plus three compiled native guard inverses. Includes actual child Catalog, physical synthetic store, registered handler, real common driver, model encoder/SSE decoder and two actual endpoint payloads. |
| Postmerge automatic CI |38740489239@0ab currently in progress | Separate general Flutter analyze/test gate; terminal/counts still pending, not inferred from tree equality or earlier success. |

No new builds/tests were run for this feasibility task; evidence above is preserved existing ordinary logs, source and metadata. General CI is not the Rust/JVM/Android-specific gate.

## Reusable execution chain and exact seam

`core-agent-lab/core/src/agent.rs` routes run/run_with_provider/run_with_ports/run_with_runtime_ports to the one `Agent::drive`; `agent_ports.rs` supplies the generic ports. Reuse this driver, not a second Kotlin or wrapper loop.

`rust-agent-host-lab/core/src/lib.rs` supplies `NativeSession`, `Enrollment`, `RuntimePorts`, live `AuthoritySource`, `PurposeReview`, and the host-owned installed handler map. The actual chain is enrollment validation -> Catalog register/discover -> canonical arguments and selected typed refs -> prepare ticket -> fresh authority -> invoke/dispatch identity -> durable original receipt begin -> final current scope/authority/cancel check -> physical handler -> durable raw finish/facts -> accept_result with original receipt -> reviewed projection/history -> final model admission and outbound journal. Catalog never executes the handler or owns the receipt.

`model_gateway.rs::ModelGateway` is real encoding/decoding, with an offline fixture endpoint; it is not a network model implementation. Existing tests record the exact two payloads and feed SSE tool-call then answer bytes. `read_registry.rs::PhysicalReadHandler` reads a real private synthetic file, binds key/type/reference and exposes only configured projection fields. `NativeStore` preserves bounded64KiB snapshots, original receipts/facts and ledger with strict restore; filesystem helper uses Unix owner/mode/lock/atomic writes.

The transport is currently hard-coded: `NativeSession.process: PluginProcess`, and create requires an absolute child binary. `PluginProcess` uses Command/Unix fd/fcntl(nonblocking2048), bounded pipes/deadline and close/reap. An in-process transport owning the same actual `Catalog` is a plausible small change, but it is a proposed contract change, not an existing alternate. Its request/close semantics must preserve the same register/discover/prepare/invoke/accept_result checks. Preserve child/Linux path as a separately named comparison. Do not label in-process execution as child-process isolation or claim Android child launch readiness.

`SharedSession = Rc<RefCell<NativeSession>>` must remain within one owner thread. Construct/use/drop inside one Rust-owned worker (or within the approved synchronous Rust call on its worker); pass bounded immutable inputs/results across FFI. Do not expose/move this Rc session as a cross-thread UniFFI handle. Exact lifetime/cancellation semantics are still a contract decision.

## Minimum genuine runtime proof through the new public bridge

A future positive must call the actual newly generated FFI entry point, then same Agent/RuntimePorts/ModelGateway/registered-handler chain on one fixed synthetic selected record. Registration/discovery alone or a direct `CallProvider` event does not prove the actual model-byte path. Assert:

- Source/build/protocol match and actual default library is mapped; typed call enters the actual driver, registration is zero execution, catalog/current descriptor and one trusted binding are genuine.
- Exactly two recorded encoded endpoint payloads, one admitted physical read, one original durable receipt; exact call/task/attempt/turn/binding identity and native receipt owner remain bound. Read known fixture contents with an independent private canary into the native raw receipt; no direct fake counters substitute for this evidence.
- Model turn2 has the actual safe projection plus original receipt/call pair and no private raw canary; final answer and persisted task state come from the actual driver. No bypass to a Kotlin success string, fabricated receipt, missing-source fallback or fake Agent.
- Inspect durable native evidence through a bounded test-only oracle/private store if needed, not by adding raw receipt/counter exports to shipping metadata API. Fixture inputs/expected projection/negative targets must be frozen from source before implementation, not generated from DUT output.

Current defaults are not a two-turn/one-read bound: Agent defaults16steps/16calls, and RuntimePorts advertises discovered tools on every turn. If the next slice promises two model turns and one read, the contract must explicitly enforce these limits and second-turn tool/admission behavior. Bounded input/output/context/response/store and cancel behavior also need explicit values. `ProviderControl.charge/checkpoint` rejects host usage; do not call existing offline endpoint an already-supported network budget/credentials transport.

## Negative cases and real inverse evidence

Reuse source-defined native negatives: disabled/current authority, missing selected refs and wrong type/key/version, pre-handler revocation, malformed projection preserving raw receipt, actual-value policy denial, post-receipt/historical projection revocation, final-model-policy revision, duplicate/unadvertised calls, ledger failure, cancellation before invoke and during handler, strict forged-store restore and size/depth failure. Freeze exact handler/receipt/facts/payload counts at the relevant boundary: a read denial may still permit a first model send, and denial after durable begin is different from early denial. Do not use generic failure/timeout as success.

Actual existing native3 KILLED in final-legacy-rust-38737375497.log:

1. `native_prehandler_fresh_authority`: exact revoke-after-preinvoke snapshot oracle; bypass makes physical handler1 instead of0.
2. `native_selected_record_scope`: exact early scope/facts oracle. Durable begin independently prevents physical read; inverse proves early denial and facts/health integrity (`external_read`1 vs0), not a physical-data leak. Initial survivor and corrected oracle history remain preserved.
3. `native_final_model_admission`: revocation at the third actual second-turn payload policy review; inverse makes endpoint sends2 instead of1, with handler1/original receipt1 reach guards.

These prove the existing Linux path, not a future facade/in-process path automatically. At least a narrow new-path baseline and targeted inverse must invoke the actual new facade/transport through the compiled matching library. Prefer the final pre-handler and final-send boundaries; if scope is selected, retain the truthful facts oracle rather than demanding a leak blocked by another guard. Baseline same oracle GREEN first; isolated source mutation, real compile, exact single target assertion/reach/value, no timeout/load/setup/classifier failure counted KILLED. Record source/library/binding/patch hashes, bounded owned cleanup and preserve old baseline. Old17 generic mutants are regressions, not proof of new FFI/thread guards. Any worker admission/correlation guard added needs its own meaningful negative, and an inverse if it is a new essential guard.

## Android compile versus host/JVM runtime and future CI split

Existing Android bridge depends on plugin and transitively core; that builds Rust dependency code but its exported call only registers/inspects metadata. Native-host composition is not a dependency. Existing Android .so checks therefore do not establish Agent invocation, host store lifecycle or in-process transport execution on Android.

After a reviewed fixed contract, minimal required checks can be:

1. Preserve current metadata and old native gates. Add source-frozen Rust integration cases for the same actual Agent chain with the proposed in-process transport, and retain existing physical child path separately. New counts/targets must come from author's fixed test-first source, not this proposal.
2. Fresh default Linux library + fresh generated JVM bindings + actual JVM call through the new facade. Positive/negative/control/lifetime cases above run without network, model or credentials. Rust/JVM compile/load errors are INVALID, not reachable semantic RED. Real compiling refusal stub plus a fixed reach marker/positive assertion supplies first RED before GREEN implementation.
3. Fresh same-source API24 arm64+x86_64 shipping library including the approved new path, generated Android binding bytecmp, actual imports/ELF, same-source manifest, normal Compose state/lint/app+testAPK and exact dependency byte/zipalign gate. No old metadata-only binary may satisfy this gate. Retain default/probe/tool artifacts separately.

This can prove real Rust Agent execution on Linux/JVM plus Android compile/link/package compatibility. With the current no-device constraint it cannot prove ART/JNI execution, Android app-private filesystem/lock/persistence, lifecycle, concurrency or 4/16KiB runtime behavior. Those stay NOT_RUN. If the acceptance goal requires actual Android Agent execution, a later approved device/instrumentation stage is necessary; changing the wording to a compile claim is not equivalent proof.

## Contract decisions before source work

Freeze the typed new Agent request/result/capability and how it differs from current metadata `BridgeInfo` (model/business_read/execute=false) and `RustUiPort.NOT_CONNECTED`; do not silently reinterpret diagnostic Ready as task success. Define synthetic data ownership/bootstrap, trusted authority/reviewer source, no client-invented grants/profiles/paths, transport trust/isolation semantics, worker lifetime/single flight, request/task/attempt correlation, true native cancellation versus UI presentation timeout, exact bounds and persisted-result exposure. Keep raw/private material out of outbound/context/logs.

No exact DTO/API/test count, new directory or new workflow namespace is frozen by this report. Checker retains original workflow/checks ownership only; native/UI original owners retain implementation. All next-slice runtime/Android/inverse outcomes are PENDING until the contract is reviewed and author source/tests exist.
