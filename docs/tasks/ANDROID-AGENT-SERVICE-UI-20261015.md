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
