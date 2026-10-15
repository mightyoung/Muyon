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
