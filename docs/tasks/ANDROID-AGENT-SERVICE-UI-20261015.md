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
