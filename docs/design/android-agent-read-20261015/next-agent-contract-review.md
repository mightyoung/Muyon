# Next registered-read Agent slice — independent contract review

2026-10-15. Original non-author host/UI reviewer. **Read-only source and contract assessment: 0 product/code changes, 0 new tests/builds, 0 devices/models/credentials, no commit/push/merge.** Existing runtime evidence is historical and is not execution of the proposed new surface.

## Fixed inputs and verdict

Reviewed root proposal `NEXT-AGENT-SLICE-PROPOSAL.md`, SHA256 **464263df676947c2100c10f51721f5f7f9695841ed7223c9ef72bc2f8be99e80**, plus the four feasibility reports. The root proposal is authoritative where the earlier alternatives differ, especially UI projections/counters, lifetime and storage reservation. Exact read versions are recorded in `next-agent-contract-review-inputs.json`.

Normal `git fetch origin develop` independently established baseline **0ab2c4f667681b9aacb017f8cd2eea6f576cf78e**, parents a01dcc83348c705fb8c6e3905aa9df8999058b1a +6e3b5eacc25e4d81f9bde658b643e9f8c3af31ef, tree **bca71d8794edab6c63989f6cdfebbca32d059c03**. The locally read immutable6e files have that identical tree. No WIP source was reviewed.

**SPEC PASS / QUALITY C0 for the fixed bounded proposal. Critical0, Important0 open, Minor0 blocking.** The selected route is technically feasible from existing seams and is ready for the parent's concrete slice decision and root's implementation spec/plan. This verdict is not implementation approval, a runtime PASS, Android acceptance, public M03 freeze or a new authorization to merge. No unresolved architecture contradiction requires restarting the chosen direction.

## Why this is substantive Agent integration

The positive path must enter the existing `Agent::run_with_runtime_ports` and its single private `drive`, then actual `RuntimePorts`, `NativeSession`, host enrollment/authority, physical handler, durable original receipt, Catalog result admission, purpose review, actual request encoder and offline endpoint. Two actual encoded requests and the real accepted read projection in the second payload provide the decisive evidence. Registration/inspect, fabricated counters, directly calling a handler or manufacturing a terminal cannot satisfy this contract.

Terminal-only shipping FFI does not diminish that proof. Public output need not contain business values for the internal Agent to genuinely execute. The independent test-only physical source/receipt/payload oracle must prove the entire chain and its values, including changed-source positive siblings and private canary absence. Shipping must use the same composition and default behavior as the tested route; probes cannot supply a replacement driver, permissive policy or alternate successful implementation.

This remains explicitly **offline synthetic-data Agent execution**, with Android cross-link/package compatibility as a separate outcome. It is neither a natural-language/live-model integration nor product database access. Settings labels and the unchanged general NOT_CONNECTED state correctly describe that scope.

## Source-backed seams and invariants

Paths below are under `experiments/redesign/`; line numbers refer to fixed0ab/identical6e.

| Source | Independent finding and required preservation |
|---|---|
| core-agent-lab/core/src/agent.rs:209–215,229–249 | Runtime entry delegates to the same drive. Actual ModelRequest, provider control, advertised tools and HostTool dispatch are already generic. No second Agent loop is needed. |
| rust-agent-host-lab/core/src/lib.rs:100–148 | Concrete PluginProcess and Rc/RefCell session are the small transport/lifetime seam. Add an explicit in-process constructor/adapter; preserve the child path rather than auto-fallback. |
| plugin-contract-lab/core/src/lib.rs:13–46 and src/main.rs:11–25 | One persistent Catalog owns generations/tickets. Bounded Json validation alone is not child envelope/fatal parity. Serialized roundtrips and terminal latch are necessary; explicit transport close differs from wire command close/inspect behavior. |
| rust-agent-host-lab/core/src/lib.rs:298–480 | Registered identity/scope/arguments → prepare/invoke → original durable begin → final fresh authority/ref/control → physical read → original raw finish → current admission/purpose → history. Preserve order, source facts and one receipt owner. |
| rust-agent-host-lab/core/src/read_registry.rs:73–119 | Real private-file read and selected-record binding are already implemented. Metadata must not select paths; new8KiB cap belongs to the bounded new path, not silent broad changes. |
| rust-agent-host-lab/core/src/model_gateway.rs:31–90 | Actual registered bytes, journal-before-send, repeated current-authority/purpose admission and SSE decoder are reusable. OfflineEndpoint/profile offline-fixture are real protocol processing, not a network/credential implementation. |
| rust-agent-host-lab/core/src/lib.rs:248–279,525–538 | Model purpose/answer masking is not UI-display authorization. Existing failure collapse is not authoritative cancellation or receipt outcome. Omission of shipping business projection avoids inventing a UI policy. |
| core-agent-lab/core/src/agent.rs:288–293 and host lib.rs:281–296,507–511 | Current control polls the cancel file or local boolean, not a proposed ArcAtomic automatically. New signal must actually reach provider/endpoint and pre/post-handler/send checkpoints without borrowing busy Rc. |
| rust-agent-host-lab/core/src/store.rs:171–240,261–299 | Native snapshot64KiB and poisoned candidate failures are real. Open validates evidence; it does not restore live session/grants. Running/uncertain durable outcome must survive cancellation and no-resend. |
| core-agent-lab/core/src/store.rs:5–40 | UID/mode/symlink/lock/atomic/fsync rules are existing Unix assumptions. Android runtime filesystem support is still unproved; canonical app root alone is not evidence of a sandbox or device compatibility. |

The existing all-four physical-read test in host `tests/native_read.rs:642–785` is a sound source oracle, not an already executed test of the new facade. The renamed mapping prevents business-name coupling; independent new-path assertions must still exercise actual source values and final payloads.

## Closed contract findings

These were material gaps in the preliminary reports and were sent directly to root/native/UI owners. They are closed in this fixed proposal; no product fix is claimed.

1. **Receipt uncertainty versus cancellation/failure.** Existing RuntimePorts collapses failure reasons, and NativeStore finish can leave running evidence. The proposal derives typed outcomes from task/receipt facts, gives Unknown/OutcomeUnknown precedence, separates RecordedSuccess from the run's Cancelled terminal, and refuses to infer zero execution from missing FFI result. Deterministic post-begin/post-read/persistence-failure plus cancel/close controls are required.
2. **Correlation and pre-identity failures.** Native preliminary DTO omitted variant while UI checked it, and required actual task/attempt even before they could exist. Fixed DTO echoes typed variant and carries paired optional actual identities. Optional receipt identity no longer implies NotStarted; Unknown may lack identity, while NotStarted needs affirmative evidence. Shipping counters are omitted consistently.
3. **Busy worker lifetime/control.** Existing local cancel is not a quick cross-thread control API. The proposal supplies a small concurrent control facade, worker-local Rc, independent correlated cancellation, sticky close/start linearization, no queue, strong run ownership and join outside locks. Closing/Cancelled/Closed are distinct; only actual worker drop/join and resource settlement release runtime occupancy. UI Accepted/NotRunning and presentation timeout cannot release it.
4. **Storage high-water reservation.** Preliminary1MiB was unproved against declared old/candidate/temp ceilings. Fixed2MiB is coherent within root8MiB and independent directory-count8 ceiling, provided actual layout/entry/temp bounds and prewrite limits are proved. Eight dirs is not a promise eight runs fit. Root lock covers scan/reserve/mkdir; incomplete/unknown retained material counts and is not automatically removed/replayed.
5. **Purpose boundary.** Earlier UI projection alternative required new Rust ui_display/current-scope admission. Fixed shipping result omits values/raw/history/answer, so model-purpose admission is not repurposed as UI permission. Existing diagnostic capability remains distinct from Agent execution.

## Minimal implementation and evidence checklist

These are implementation consequences of the selected proposal, not additional product scope or requests for a new approval cycle:

- Keep transport fatal versus recoverable errors and wire-close versus host-close explicit. Test malformed number/depth/size input through actual serialize/parse admission, generation changes, consumed/cross-Catalog tickets and post-terminal requests. Do not claim in-process isolation/kill/reap.
- Freeze method-specific error subsets and state transitions in the implementation spec: second run on a consumed handle, request mismatch, pre-start cancel, close/start race, optional identity combinations and terminal/receipt consistency. No success/default status inferred from absent evidence.
- Hold no admission/result mutex during FFI work, filesystem operations, listener invocation or join. A retained Arc during run means a language handle's cleaner may only drop one reference; do not rely on Rust Drop firing promptly to deliver cancellation. Explicit independent controls and retained occupancy must remain correct even when Drop is delayed until the run ends.
- Preserve exact64KiB model body while enforcing the new outer-file/raw/task caps. Task128KiB and raw8KiB are new restrictions, not existing guarantees. Prove2MiB transaction peak including temporary/bootstrap/marker files, bounded scans and failure leftovers; control never waits for root file lock. A saturated/corrupt/incomplete namespace fails closed and keeps evidence.
- Enforce host read budget1 independently of two model calls. Turn2 advertises no tools; decoder/dispatch must reject known-but-unadvertised or repeated reads. Positive2send/1read expectations must be measured through actual admissions, never assumed on denials.
- Required semantic RED must reach the intended new compiled facade/driver seam; load/config/build failures are INVALID. GREEN and guard inverses use the same actual default path plus clearly separate nonshipping observation/fault probes. Preserve the old child/native/metadata/UI gates, all raw failures and source/binary/generated-binding identities.
- Independent negatives cover before-handler authority, after-begin unknown evidence, accepted raw followed by revoked projection/purpose/final-send denial, cancellation during held provider/handler, pre-start close, late UI lease delivery, cleaner/reopen single-flight and quota races. Barriers establish order; sleeps or wallclock timeout alone do not prove the target behavior.

## Routine choices versus genuinely new scope

The canonical deferred paragraph already selects private ContractTransport, persistent in-process Catalog, unchanged Linux child, one existing Agent drive, trusted host authority/purpose/receipts, non-Send worker ownership, independent cancel, drain and no automatic replay. The proposed one-shot shell, exact closed DTOs, trusted synthetic bootstrap, quotas and original native-owner host+bridge ownership are concrete choices within that direction. Parent may decide this finite contract without reopening a service framework or all prior architecture.

Still outside this proposal: real model/network/credentials/permissions, actual business DB/data, business-value UI projection and its ui_display policy, arbitrary/untrusted plugin execution, public M03, broad Send/Sync conversion, persistent task queues/background services, automatic deletion/retry/resume or Android child execution. Any such extension requires its own explicit scope decision. Android device/emulator execution is separately authorized platform work; no new installation/model permission is presumed here.

## Acceptance boundary and handoff

Recommend **accepting the fixed proposal for the minimal next implementation slice**, subject to the parent's requested concrete decision, then root records the spec/plan and activates the original owners with exact directories/test identities. No further feasibility investigation is needed to begin that bounded implementation once authorized; normal implementation/code-review findings may still require scoped fixes.

New actual Rust facade, Linux/JVM Agent FFI, cancellation/join/quota tests, API24 host-dependency builds and packaging are **NOT_RUN** at this review. Prior stateless metadata9/JVM7/state67 and old native94/21/25/44/13/17+3 are reusable regression evidence, not new-path acceptance. Android ART/JNI execution, filesystem locks/fsync/process death/lifecycle/rendering,4KB/16KB runtime and production business capability remain NOT_RUN even after host/JVM and build gates succeed.
