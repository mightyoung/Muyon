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
