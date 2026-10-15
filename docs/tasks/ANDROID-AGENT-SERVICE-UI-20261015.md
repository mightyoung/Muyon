# Android Agent Service UI: Phase 1 checkpoint

Baseline: `de83e44758ba036b94779cc00d439224b1d06973`. Owner branch: `task/android-agent-service-ui-20261015`. This slice adds pure Kotlin presentation/lifecycle policy only; the Agent is neither constructed nor executed in the UI process.

## Executed TDD

- Refusing implementation `ccbe0412ad00918563514e029a5da0eab53ed1d8`: Kotlin compilation succeeded, original 67 checks passed, 35 of the new 37 named checks failed; process exit 1.
- First implementation: original 67 + new 37 passed.
- Interleaving checkpoint `9431b059`: compilation succeeded, 3 of 41 new checks failed: known terminal erased by empty current, Closed phase reopened by a later revision, and retirement at initializer-wait return lacked close settlement. Process exit 1. The additional visible-activity forwarding check passed.
- Final source: original groups 16 + 22 + 29 and new 41 all passed, total 108 named JVM cases, exit 0. This proves only the pure client policy and synthetic lifecycle/control seams.

Command (existing compiler, target 17; output external to Git):

```sh
MUYON_UI_KOTLINC=/tmp/muyon-native-ui-tools-20261015/kotlinc/bin/kotlinc \
MUYON_UI_OUTPUT=/tmp/rd-android-agent-service-ui-20261015/verified-green \
bash experiments/redesign/android-compose-lab/run-state-checks.sh
```

## Behavior and ownership

`AgentServiceContract.kt` contains closed private presentation projections, no generated/native objects, authority payload, raw data, model history, business answer or counters. `AgentServiceClientState.kt` validates protocol/build/epoch/revision, request/durable identity and receipt shape; preserves settled evidence; isolates historical lookup from active state; ignores stale connection/lease/display tickets. Submission is explicit, visible-lease acknowledged and reconciled first; loss/rebind/detach never submits. Activity identities aggregate last-visible transitions; a new lease forwards current visibility explicitly. Native Closing/Closed and an issued last-visible stop cannot be reopened by local UI state.

`AgentServiceRuntimeSupport.kt` is a platform-neutral lifecycle seam, not a fake Rust implementation. It waits for actual initializer settlement before installation, retires/drains a late controller, and hands off retirement without holding its admission lock around native work or listeners. The app install callback must also check its own current Service generation before publishing a controller. Actual adapter retirement must call Service-only `retire_service()`; it must not create a fake lease or rely on Cleaner. The platform adapter must dispatch native initialization/settlement and prompt controls on their appropriate independent background lanes; these pure helpers do not assert Android thread placement.

`AgentRpcLanes` admits one observation and one independent control without a waiting queue. A blocked observation cannot prevent a control from starting; errors/rejected execution release only the relevant local slot. A returned control acknowledgement is never a fabricated native terminal.

## Next dependent phase and evidence limits

The actual Object Android bindings must come from the native owner's pinned UniFFI generation. No handwritten binding, production stub, fake Ready or fallback Agent is added here. Service/AIDL/manifest/proxy/Settings integration and new generated Object minSdk 24 compatibility are not implemented or compiled by this Phase 1 checkpoint. Existing metadata diagnostic and general chat execution port remain unchanged.

Android Binder, separate PID/UID, process death/rebind, ART/JNA loading, private filesystem lock/fsync, actual Service bootstrap and Rust Agent execution are **NOT_RUN** here. No Gradle, Android installation, emulator, device, model or permission changes were used. Parent imports/pushes and obtains independent review and remote compilation.

Raw logs and generated test jars remain under `/tmp/rd-android-agent-service-ui-20261015`, outside Git. Old clones/branches/logs/alternates are preserved.

| Log | SHA-256 |
| --- | --- |
| `phase1-red.log` | `af806729d44189743bbbb8dac92d0f2269a362da7459e85e3ecd9e0092a7ac80` |
| `phase1-green.log` | `9b10c5eceacb404a9e2bc6ae03a73e86558cd82527ebd87869eeb321893eed79` |
| `phase1-interleaving-red.log` | `415c67b3f2039910b57d0cc3a5812c615111a63b17e1aaa8a01633a98f35072b` |
| `phase1-verified-green.log` | `29e68e8222ef7a10c49a6bc5445a69b19757292ca20539e5ca3f1b1d4cec2a41` |

## Query binding and independent review corrections

The preceding 108-case checkpoint is preserved. Follow-up self-review found that historical queries lacked an exact original intent and incorrectly compared revisions across different query keys. Actual checkpoint `09b5c6b5` compiled and failed 2/43 new cases. `captureLookup(expectedIntent)` now validates and binds the original request/variant/source; historical publication requires that binding and compares equal revisions only within that key.

Independent review then identified (1) a late STATUS ticket for A overwriting an explicitly selected and already observed B and (2) initialization observing old Ready while `retire()` had marked the object retired but had not actually completed the native stop signal. The deterministic review checkpoint `70d10901` compiled and failed both cases (2/45). The lifecycle case blocks at the fake retire entry **before** mutating stop state, releases the initializer waiter, and waits for that job to finish before permitting the real signal; it uses latches rather than sleeps. STATUS now rechecks its captured expected intent against current selection. Retirement now publishes signal completion only after `retire()` returns: an initializer encountering a signal in progress relinquishes settlement ownership, and the signal's completion schedules the actual close waiter if needed. Native work and listeners remain outside the coordination lock.

Final review-fix source executes old 16 + 22 + 29 and new 45 named JVM cases: **112 PASS**, exit 0. This remains synthetic policy/lifecycle evidence, not Android Binder or Rust Agent runtime evidence. Final external log: `/tmp/rd-android-agent-service-ui-20261015/phase1-review-green.log`.

| Follow-up log | SHA-256 |
| --- | --- |
| `phase1-lookup-red.log` | `cfeba2d2062e8f7cce2afcea344d162c7f5edd11ebca561e20d3890089605977` |
| `phase1-lookup-green.log` | `c06727b8c29e9618fcabf1931bfd40a6b362e1d0873268fc7f3bb50e6cd2a739` |
| `phase1-review-red.log` | `d18b036978e7fe925445d90b6781541ca96f37a2181081d06814871257a01d8d` |
| `phase1-review-green.log` | `f6e10472ec1785e73d6fe6c92c4ea9cef9c8ea69e09e6732e6ab95df6fae295a` |

## Independent review round 2: historical selection

Review found a remaining historical selection race in `7e53b03f`: capture A, capture B, accept B, then late A could replace B because the accepted-key comparison alone did not bind the **currently selected query**. The original 112-case evidence above remains preserved; it did not cover this reverse delivery.

Compiling RED checkpoint `e9625170c0a29a8af10f736d44bf697966b8ba23` adds two named cases: late A at the same revision 3 and at lower revision 2 after B at revision 3. Both fail on the prior implementation (2/47), process exit 1. Each case also requires the active Running request to stay untouched, accepts the current B ticket's identical response, and accepts a newly captured explicit A query at the same server revision.

`captureLookup` now establishes the current historical selection at successful capture using the returned ticket's unique object identity as an opaque query generation. Historical delivery must carry that exact current ticket; data-class value equality does not make an older selection current. This state is separate from active-run selection, connection/lease/display generations and accepted historical evidence. No DTO/FFI, native coordination or listener-lock behavior changes.

Final exact-source check: old groups 16 + 22 + 29 and new 47, **114 PASS**, exit 0. Command is the same existing compiler invocation above with `MUYON_UI_OUTPUT=/tmp/rd-android-agent-service-ui-20261015/query-selection-green`. Android Binder/native runtime remains **NOT_RUN**; independent review of this correction is still required.

| Round 2 log | SHA-256 |
| --- | --- |
| `phase1-query-selection-red.log` | `3d81379da1cb2c6c06e4a9a96bed2a73c5fb9299bb8fd3220bad0b7783222ea0` |
| `phase1-query-selection-green.log` | `908835c32be651ff07a084423f900b74e6d05d8310f36b74e724db5fadf83d9f` |

## Phase 2a: closed IPC metadata codec

Refusing codec checkpoint `4a83f0e9` compiles; existing 114 named checks pass and 6/9 newly defined codec cases fail (exit 1). The first five failures explicitly refuse valid closed replies; truncated-input coverage also fails because no valid encoded sibling exists yet. No claim that these six failures represent six separate native boundaries.

Implemented a versioned binary metadata-only reply schema: local transport status without native identity, actual connected metadata/lease/phase, six sealed run snapshot shapes, queued versus Existing start, closed control/rejection/unknown/busy outcomes. The codec carries no raw data, answer/history, authority payload, counters, dynamic method/map or native object. It validates actual identity/receipt relationships; unsupported versions/tags, truncation/trailing bytes, invalid fields and oversized bytes cannot become a successful result. Payload cap 7680 bytes leaves room for a separately enforced actual Android 8KiB Parcel envelope; this is not a claim that bytes.length proves the Parcel cap.

Exact-source JVM checks: old 114 + new 9 = **123 PASS**, exit 0. Android Parcel/Binder runtime remains NOT_RUN. Actual AIDL onTransact envelope checks, liveness registry and generated Object adapter are subsequent work. No permission/dependency/runtime change.

| Phase 2a log | SHA-256 |
| --- | --- |
| `phase2-codec-red.log` | `a4d6c53e762d43eeda12d1c1db5d22b6623544211371212a7e954d9a7e53fd39` |
| `phase2-codec-green.log` | `e7b5cd1ad15d3ed9558c70b5cc3ad6a77b405664ce6c76460be53e0b367d071e` |

## Phase 2b: bounded liveness registry

Codec review Minor corrected tests only in `f1b3d21f`: magic mutation remains, VERSION byte index 4 is now independently mutated; unknown reply tag and noncanonical boolean flag also have valid encoded siblings. The codec implementation is unchanged. All 9 codec cases pass in the subsequent full JVM run.

Refusing registry checkpoint `68f099254b19a3fda9165eed5496b1debd1fa858` compiles and fails all 9 new cases. Initial registry implementation passed those cases. An additional real setup-failure case then failed at `e8be2bf1`: a throwing death-link setup must not create an unobserved native lease. Final implementation returns local Unavailable after failed link, retains no token and never invokes native connect for it.

The pure registry retains at most 2 tokens including released-live tombstones, links a live token once, preserves the private key on repeated connect, remembers death during linking/connect, and reissues only the original key's stop after a late native connect if death raced it. Dead entries can be removed; duplicate late callbacks remain bound to the dead entry and cannot remove a replacement. Native and link/gone callbacks run outside the registry lock. Private keys use a process-prefix and checked monotonically increasing sequence; the eventual Service adapter must share this key source for its process lifetime and must never accept private keys from UI parameters. `markReleased` is called only after native acknowledgement; it does not implement Rust cancellation or business authorization.

Final JVM result: previous 123 + new 10 = **133 PASS**, exit 0. These are synthetic liveness/control seams, not real Binder death, Android process, Rust authority or runtime evidence. No actual platform callback/Rust Object is substituted.

| Registry log | SHA-256 |
| --- | --- |
| `phase2-registry-red-fixed-tests.log` | `ea348b9f815d8512fa36efe1f983382543ca031395787269401442d515693c98` |
| `phase2-registry-green.log` | `8950b8ae78a500ba99a98669b06a81d73e2d6d8eb97e4e9c32dbbe4c2bcabd6a` |
| `phase2-registry-link-red.log` | `00ffeaadfcbe9e97d1ce4b935c44b50db86130ed645967cd582e7e8db66be81f` |
| `phase2-registry-verified-green.log` | `e2fa86022c9694d3ea50328df1129fc42a0c1ec68383e0fd015675b8fdddedc1` |

## Phase 2c: explicit AIDL and actual Parcel envelope source

Added private explicit AIDL methods connect/start/status/current/lookup/setVisibility/release/cancel/close. No callbacks, oneway stream, dynamic dispatch, private platform key, root/path input or Service-only native lifecycle function appears in AIDL. Requests use closed primitive fields and will be validated by the actual Service adapter before native calls. The single reply Parcelable carries only the closed metadata codec above.

`BoundedAgentBinder` checks the actual complete incoming `Parcel.dataSize()` against 4096 before generated request decoding, rejects cross-UID and oneway calls, then checks the complete outgoing temporary Parcel against 8192 after generated exception/object/byte-array framing. `AgentReplyParcel` also checks the actual source/destination Parcel and bounded payload. Encoding/validation failure becomes local transport Unavailable, never business NoAdmission, terminal success or proof of no side effect.

AGP AIDL generation is enabled without new dependencies or permissions. Three device-only instrumentation cases cover interface-token/array overhead, valid local reply with exception/presence framing, and complete reply oversize rejection. These tests are source only: **Android/AIDL compilation, Parcel tests and Binder runtime NOT_RUN locally**; remote normal Gradle compilation is required. They are not counted in the 133 pure JVM result. Service class/manifest entry, UI proxy and actual generated Object adapter are not yet added by this checkpoint; no fake implementation or Agent construction exists.

## Registry independent review: release versus repeated connect

The previous 133-case checkpoint did not cover an acknowledged native release racing a repeated live-token connect. Deterministic RED `fe2dc2091e436865c79b41876b5fc21ae8a57390` blocks inside the repeated native connect, marks the original lease released, then lets connect return. The case fails on the prior implementation (1/11 registry failures, compilation succeeded, exit 1).

Post-native publication now checks both dead and released state under the registry lock. A late Connected result cannot revive a released-live tombstone. The tombstone retains capacity; this correction adds no native gone/release invocation. The test includes a valid same-live repeat sibling, checks retained count 1 and gone count 0 after the race, and verifies future connect cannot invoke native for the released token.

Full exact-source JVM check: old 123 + registry 11 = **134 PASS**, exit 0. Service integration depending on the registry remains paused until independent scoped re-review. Android/Binder/native runtime remains NOT_RUN.

| Release-race log | SHA-256 |
| --- | --- |
| `phase2-registry-release-red.log` | `d996d0daaff50e0f3ed2a7651598bdd4cf957a4452f87f8e5cda298f218e84e9` |
| `phase2-registry-release-green.log` | `e506eba686920281a764d74896f6fa4d89cf6c3aed655b195c31f18e626be502` |

## Actual Android Object binding handoff

Copied the unmodified actual Android-profile generated source from the independently verified ordinary-log handoff for remote run `38765354239`, source `c6287d403c7c3d465f7decdadd91930a0a4ad17c`. Local source candidate: `/tmp/rd-android-rust-bridge-20261015/service-android-binding-c628/muyon_android_contract_bridge.kt`; manifest in the same directory. Bytes 141263; SHA-256 `6fec4795a50cab1b629cb19c45562fb435a805f542bc2312da100995aa5636db`. This matches the earlier actual fresh Android generation at `fa064` and is not a JVM-profile substitute or handwritten binding.

Pinned evidence manifest: Android config `543bab24b017d782b38aff958254db5bd185c3688eada2e6a96a5753dc98ab11`, bindgen `083a46313d5d5608a62a1883d1f3689aa6e8f98165afaef69cf25dbbff8bb73a`, actual default library `59b4061d346974ea50fcd13ce83be6df164ff0effeb68a3a88057be02ca63dc8`. That run establishes fresh generation/load and the expected refusing native semantic RED, not GREEN Agent execution.

Original generated header/body retained byte-for-byte; existing UniFFI MPL notice/license remain. The Object source includes generated API34 SystemCleaner guards with JNA Cleaner fallback. This is source observation only: fresh Android compile/lint with minSdk 24 and actual ART cleanup behavior remain required, NOT_RUN locally. No hand modification or API floor increase is applied.

## Bounded death-link disposal seam

Compiling RED `5888f07a1fef3c6abe0d10366ac68ddd4a62cabd` adds four deterministic cases and fails 4/15 liveness cases. Final registry links retain their own unlink closure inside the same at-most-two entry inventory, with no separate recipient map. `dispose` seals registration, detaches live/released tokens once outside the lock and does not claim native cancellation. A link still being installed is detached only after its setup returns. Late native connect after disposal is rejected and its original private key is stopped; no replacement key is affected. Explicit Service retire/await remains responsible for Rust cleanup.

Final JVM result: prior 123 + liveness 15 = **138 PASS**, exit 0; real Binder, Service and Android runtime NOT_RUN. This is a small independent registry delta for scoped review before Service integration uses it. Original logs/source commits remain preserved. Future small compiler runs reuse the current `disposal-green` output directory per parent resource instruction; no new toolchain/SDK/large target or cache cleanup.

| Disposal log | SHA-256 |
| --- | --- |
| `phase2-disposal-red.log` | `f43ce7c2e5ec4c9bc56db482658072ec56fafdf0e9937334e621d62b3f9b6d24` |
| `phase2-disposal-green.log` | `ee299c5e447b3e8ca0ac089a7bd635b68f62664d2cf724ac8a614eb5ed13e47b` |

## Pending remote-only state checkpoints after local resource pause

The last already-running local compilation completed before the no-new-build resource instruction: `phase2-start-refusal-red.log`, compilation succeeded, process exit 1, 2/12 IPC cases failed. Registry cases are sequenced after IPC and were not executed in that failing run. Refusing start-reply source is preserved in the preceding test commit. The implementation now distinguishes actual native Busy/Rejected from uncertain transport/unrelated ACK/stale selection and forces current reconciliation; its GREEN is **NOT_RUN** locally and awaits remote validation.

Independent disposal review found that the first throwing unlink interrupts the second detach attempt after entries have been cleared. Added source-only deterministic test `dispose attempts second unlink when first unlink fails`: two actual registered pure-token entries, first unlink prints `DISPOSAL_UNLINK_FAILURE_REACHED` and throws, test catches the injected exception then positively requires the second detach attempt. It also requires exactly once on repeat disposal, no native gone calls and empty retained inventory; the prior valid disposal sibling remains. **This new test has NOT_RUN**: no RED is claimed until the parent runs the approved remote Kotlin command on this fixed checkpoint. The disposing implementation is deliberately still unfixed here.

Remote command (existing runner Kotlin/JDK; no Android runtime): `bash experiments/redesign/android-compose-lab/run-state-checks.sh`. The dedicated workflow already supplies its pinned compiler environment. No local compile/Gradle/SDK/install/cleanup after the pause. Subsequent Service teardown must call explicit native retire/await through a finally path even if platform unlink cleanup fails.

## Disposal failure remote RED and source-only correction

Parent/non-author confirmed remote run `38767513905` at `ef373451` (tree-exact to `e4837d54`): Kotlin compilation exit 0, IPC 12/12 including the new start-refusal cases passed, prior 15 liveness cases passed, and the sole new failure reached `DISPOSAL_UNLINK_FAILURE_REACHED` then the positive assertion `DISPOSAL_RED: second recipient must still be attempted`. It was a 1/16 semantic failure with exit 1, not timeout/setup failure.

The correction attempts every at-most-two unlink outside the registry lock, remembers the first failure and rethrows it only after the remaining detach attempts. No native gone/release/Closed is invented, and repeated disposal still does not duplicate attempts. The Service must run explicit retirement in finally regardless of that platform failure. This correction is **source-only GREEN candidate; local/remote GREEN NOT_RUN at this checkpoint**. No further local compilation was started after the parent's low-space instruction.

## Service settlement pump: source-only refusing checkpoint

Added four deterministic pure policy cases before implementing the Service settlement pump: coalesced requests/no waiting queue, a request arriving from actual waiter's return, rejection/failure recovery, and a latch-blocked waiter that coalesces further requests without overlapping another waiter. This helper schedules only native settlement, never business admission or control. Its implementation deliberately refuses (`request=false`) at this checkpoint.

The four new cases are **NOT_RUN locally** under the low-space instruction; no RED/PASS is claimed. Parent may execute the same pinned remote `run-state-checks.sh` command. Existing disposal-failure correction is separate in `6e459c69`; the new refusing pump is not its GREEN evidence. Actual Service integration will use this helper instead of duplicating untested waiter handoff state.

## Settlement pump remote RED and source-only implementation

Parent independently confirmed remote run `38768672327` at `197b9d26` (tree-exact `543b9522`): Kotlin compilation exit 0, exactly the four newly named settlement pump cases failed, 4/51 B-service cases, process exit 1. IPC/registry groups sequenced later did not execute; this run is not disposal GREEN evidence.

Implemented a single owned settlement slot with a coalesced pending bit, no waiting request queue. Requests arriving during actual settlement cause another settlement pass; the release/reacquire handoff prevents the old waiter's finally from clearing a replacement's slot. Rejected executor admission returns false and a future explicit request can acquire the slot. Settlement errors reach the failure callback; neither the pump nor its boolean admission result creates native terminal/Closed metadata. Native calls and failure listeners are outside any admission monitor.

This is a **source-only GREEN candidate, GREEN NOT_RUN locally** under resource instructions. Parent runs the pinned remote Kotlin checks and non-author review before final integration; raw refusing checkpoint remains preserved.

## Pump independent review: exceptional admission handoff, source-only tests

The initial four pump cases did not cover a second request while the executor was still deciding whether to accept dispatch, nor a second request during a throwing failure listener. Added two deterministic source-only barriers: executor entry blocks before rejecting A while concurrent B requests settlement (`PUMP_REJECT_RED`), and failure-listener entry blocks before throwing while B requests settlement (`PUMP_LISTENER_RED`). Both positively require that any acknowledged request has actual drain responsibility, with a subsequent valid explicit-request sibling. They do not call native.await on a requester/Binder thread and do not create terminal metadata.

These two new tests are **NOT_RUN locally**; implementation is still unfixed at this checkpoint. Parent uses the existing approved remote pure Kotlin command to establish semantic RED. The initial pump candidate/old four-case evidence is preserved, and no new test count is reported PASS from source inspection.


## Actual Service, generated adapter and Settings proxy: source checkpoint

The ordinary no-native-input Android run `38766467473` at parent `0aafe3ea` already compiled the genuine Object binding and AIDL and assembled app/debugAndroidTest APKs successfully. It did not run lint, package a Rust library, execute instrumentation or prove Android API24 Object cleanup. The following Service/proxy integration is a new **source-only, NOT_COMPILED/NOT_RUN checkpoint** under the parent's no-local-build resource instruction; the prior successful run does not verify these new files.

Added an explicit non-exported, non-isolated ordinary bound `:agent` Service, with no new permissions/foreground service. Only the Service background bootstrap constructs the actual generated `AgentServiceController`; its private root comes from the Service Context and is canonicalized, with Rust retaining actual owner/mode/symlink/lock/quota/index validation. UI `Application` lazily owns only the Binder proxy. Process-local Application instances are not treated as cross-process singletons. Metadata diagnostics remain independent and are not Agent execution evidence.

The actual generated-record adapter mechanically preserves native epoch/revision, sealed run states, original admitted identities and receipt outcomes. No Kotlin store, Agent loop, business terminal, authority decision, raw response/history/projection or counter has been introduced. Original generated source remains 141263 bytes / SHA-256 `6fec4795a50cab1b629cb19c45562fb435a805f542bc2312da100995aa5636db`.

Service liveness uses the reviewed at-most-two inventory and private process keys. Explicit Rust retire/settlement remains in teardown finally paths even if platform unlink cleanup fails. Generation-stale construction retires and waits on that captured original object, never a replacement. Runtime close and generated no-argument Object-handle close are separate: only actual Rust Closed plus disposal request permits releasing the generated handle. Actual settlement is delegated to the coalesced pump; its exceptional-handoff review correction is a separate pending checkpoint, so this integration is not presented as final-ready.

UI observations and user controls use independent capacity-one admissions. Lifecycle visibility/final release has its own bounded lane, so it cannot wait behind a blocked status RPC. The Application aggregates Activity visibility; last-invisible emits explicit stop/release and unbinds, with local result uncertainty retained. A new run ID is generated only by an explicit visible user action after reconciliation. Connect/reconnect/current/lookup never resubmit or replay a run. Deliveries retain the original LOCAL observation ticket, including historical query identity; IPC data never reconstructs the ticket. Lost/oversized reply remains uncertain, never proof that execution did not happen. Request preflight and receiving Stub/Parcelable enforce complete Parcel caps including token/exception/object/array framing.

Settings exposes a separate offline synthetic run panel with explicit connect/current/lookup/start/cancel/close controls and original native metadata. ACK/requested is described as a request, not cancellation/terminal completion. General chat/model/business operations remain disconnected. Panel dismissal only invalidates display; last-Activity visibility, liveness and Service lifecycle perform actual control.

Added five generated-record projection fixtures without constructing a native controller. They are **source-only, NOT_RUN**, not five claimed passes. The existing codec fixture now contains `t-4231-1792012800000000000` / `a-4231-1792012800000000000`, preserving the Core identifier format instead of falsely requiring 32hex task/attempt IDs; these are synthetic examples, not an actual native oracle.

Required parent remote validation: existing pinned `run-state-checks.sh` after pending pump fix; normal `:app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:compileDebugUnitTestKotlin :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug` with the existing minSdk24/config; actual generated-record fixture execution against a fresh JVM-profile binding if added to the checker-owned JVM gate. Kotlin compilation and lint failures remain owned follow-up fixes. Device/PID/Binder-death/storage/ART/native execution remain NOT_RUN and are not replaced by compilation or pure policy checks. No local build, SDK/tool install, cache deletion, push or merge was performed.


## Pump exceptional handoff: actual remote RED and source-only correction

Parent and independent reviewer confirmed remote `38770145118` at parent `8095` (the fixed refusing tests `7658ce29`): compilation succeeded, 118 checks passed before group termination, exactly `PUMP_REJECT_RED` and `PUMP_LISTENER_RED` failed, with all original four pump cases passing. No setup/timeout failure is counted as semantic RED.

The correction uses a per-dispatch acceptance marker. A concurrent request arriving while initial executor admission is still undecided conservatively returns false; it cannot be acknowledged and abandoned if dispatch rejects. Executor/native/listener code runs outside the small admission monitor, and stale inline-executor completion cannot clear another dispatch's slot. The normal return/reacquire ownership handoff is preserved. A throwing failure listener is isolated so an already acknowledged pending pass retains its actual waiter; no new queue, autonomous retry loop, Binder-thread native wait or synthesized Closed is introduced. The two refusing test oracles are unchanged.

This correction is **source-only GREEN candidate: GREEN NOT_RUN locally**, awaiting parent remote checks and scoped independent review. No local build/installation/cleanup was performed after the resource pause. The separately committed actual Service source is also pending its own ordinary compile/lint/review, not verified by this policy correction.


## Control target correlation: source-only refusing test

Self-review of actual UI wiring found that an explicit new selected request B may coexist with the previous snapshot A until reconciliation. The original cancel path extracted A's run ID while using B's request/variant. Rust would reject this mismatch, but the UI must preserve correlation rather than send the wrong run ID. Extracted the unchanged metadata-selection expression into `agentControlRunId` and added a deterministic refusing fixture: previous A run + selected B must produce no run ID; same-A and same-B siblings must retain the genuine ID, no selection and Queued must remain absent. No Rust cancellation/outcome policy is moved into Kotlin.

This fixture is **NOT_COMPILED/NOT_RUN**, with its refusing implementation intentionally retained for the parent fresh-JVM generated-record gate. It is not a claimed semantic RED. The generated adapter fixture entry point is `com.mightyoung.muyon.androidlab.agentipc.AgentNativeProjectionChecksKt`; compile state sources, actual fresh JVM-profile generated binding, `AgentNativeProjection.kt` and this fixture using the existing pinned Kotlin/JNA tool environment. No Android/controller construction is needed for this record-only group. Existing ordinary Service compile/lint and pump gates remain separate.


## Service storage-parent alignment correction

Native-owner cross-check of the actual 5c7 Service candidate found that it appended/created `native-agent-service-v1` before passing private_root, while actual Rust `ServiceRoot::open` also appends that namespace. Per root's narrow decision and the reviewed slice section 6, Service now passes only `filesDir.canonicalFile.absolutePath`. Rust alone owns the namespace and its layout. UI/Service does not chmod the platform parent, create a second envelope or relax native strict owner/mode/symlink checks.

This is a source-only path correction, not a device storage success. Actual Android filesDir mode is unverified; if strict native 0700 parent checks fail, the result must remain fail-closed InvalidRoot, not a guessed permission workaround. Android runtime remains NOT_RUN. Cancel-correlation refusing test `f58897d7` is unchanged and still awaits actual remote RED; pump correction and ordinary app/lint are separate gates.
