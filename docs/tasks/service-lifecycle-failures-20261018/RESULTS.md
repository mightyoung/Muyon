# Actual Service failure and inflight teardown results

Draft [PR94](https://github.com/mightyoung/Muyon/pull/94), stacked on PR93. Validated executable CI source: **c1f57af047671ec3c3f2b2d73d20ac6ece4bcc32**. Implementation source **ad69f9831192f011be8d02396eb938f266061be5** differs from that CI source only by review/progress documentation. Final archival changes are documentation only; no merge is authorized or performed.

[CI39141540456](https://github.com/mightyoung/Muyon/actions/runs/39141540456), attempt1, is terminal **SUCCESS**: 11/11 jobs successful, including genuine binding reproduction, API26 arm64-v8a/x86_64 native producers, and all eight package/lint/API26 emulator jobs. Evidence is preserved permitted GitHub run/job/step metadata in [evidence/39141540456](evidence/39141540456), with an explicit [bounded result](evidence/39141540456/bounded-device-result.json). The exact reviewed workflow invokes one named instrumentation method per fixed package, requires `OK (1 test)` and rejects failure/crash markers. This is narrow synthetic metadata lifecycle acceptance, not a broad regression or production-use result.

| Fixed actual Service case | Terminal evidence | Assertions required by successful frozen test |
| --- | --- | --- |
| failSetup | PASS | Pre-native failure closes durable owner once before releasing slot; replacement acquires. |
| failSetupOwner | PASS | Setup plus injected owner-release failure retains owner/slot; replacement unavailable. |
| failUnknown | PASS | Genuine constructor returns, pre-publication failure retains returned controller/owner/slot; replacement denied. |
| failOwner | PASS | Genuine native cleanup completes; injected owner-release failure prevents slot release/replacement. |
| failNative | PASS | Injected failure immediately before native.close leaves sealed/incomplete handle and retained owner/slot. |
| failInflight | PASS | Real Binder client and genuine native callback held during actual destruction; stale/replacement Binder unavailable, no duplicate owner or premature cleanup; after drain, one durable consumed admission and exact callback-return -> native-close -> owner-close -> slot-release; sealed probe rejected. |
| failReady | PASS | onReady failure denies Service, proactively retires/cleans native and owner; replacement acquires. |
| failConstructDestroy | PASS | Genuine constructor/pre-publication barrier versus actual destruction; replacement denied while held; no Ready or ledger admission; native/owner/slot cleanup once, executor terminates, same private PID successfully creates/connects replacement and cleans twice total. |

All cases assert API26 and same-UID private `:agent` process distinct from instrumentation. Their compiled Application/manifest fixes authority and fault schedule; no Binder/Intent/env/file selects approval. Actual chain remains Application -> private AgentRuntimeService -> owned GeneratedAgentController -> genuine generated UniFFI -> Rust admission -> same durable SQLite owner. New dedicated packages/schema only. Both packaged APKs are checked for absence of INTERNET. No transport/model operation is added or called.

## Repairs and independent verification

Native retirement formerly ran synchronously against the probe-held Rust mutex, blocking platform destruction. The Service now revokes publication immediately and dispatches native work to its backend. Bootstrap retirement is marked synchronously without foreign work, and construction/waiting/handoff workers own retirement and settlement. Late queued shutdown rejection is handled; backend shutdown no longer treats an unpublished reserved slot as cleaned. onReady exceptions proactively dispose. Lease close tracks attempted/completed state and cannot convert a failed close to success via a no-op retry. Native handle drain/sealing and native -> owner -> slot cleanup order remain mandatory.

[Initial execution audit and follow-up](INDEPENDENT-REVIEW.md) and [fresh final whole-branch review](FINAL-REVIEW.md) cover concurrency, scope and transitive build/test graph. The first review missed the construction/destruction queued waiter race; LeaderB identified it, independent review confirmed it, the original implementer fixed it and added the eighth actual regression, and both reviewers rechecked the final source. Local Python AST syntax checking passed; local Rust/Kotlin compilation was NOT_RUN because those tools are absent. No aggregate suite was run.

## Preserved failure and evidence access boundary

[CI39140979633](https://github.com/mightyoung/Muyon/actions/runs/39140979633), attempt1, source **489178b0c5c80979156ad4ee0b2eba8955465191**, remains terminal FAILURE. Binding and both ABI producers passed; all seven APK jobs failed Gradle DSL receiver resolution at build.gradle.kts:51. Every device test was SKIPPED/**NOT_RUN**. Qualification with buildTypes.getByName fixed the evidenced compiler issue in the later source. [First run metadata/diagnostics](evidence/39140979633) remain unchanged; the run was not cancelled or rerun.

A single direct log GET for **CI39141540456 / job117717160270 (failInflight)** was **DENIED**: GitHub's redirected job-log storage returned **HTTP403**. That read stopped. No retry, run-log archive, artifact download, alternate route or environment switch followed. [Exact redacted blocker](evidence/39141540456/LOG-READ-BLOCKED.json) is preserved. Current-run raw fixture JSON/logs could not be archived; opaque PID/receipt values are therefore not quoted or invented. Terminal build/device claims above derive from permitted API metadata plus the reviewed source/workflow assertions, not from an independently inspected raw stdout dump. Remaining blocker is raw log/JSON access; product changes and terminal CI acceptance are completed.

The earlier forbidden archive service-durable-owner-evidence-39127896088-1 was never accessed/retried. A gh pr edit CLI query encountered a deprecated Projects(classic) GraphQL field (not an authorization rejection); readback confirmed unchanged body, then the same authorized body update succeeded through official REST. No other permission escalation was attempted.

## Limits, HOLD and real-use prerequisites

Faults are explicitly bounded: Unknown throws after genuine constructor success; Native throws before native.close; Owner/SetupOwner throw before underlying durable close. Actual foreign constructor/destructor exceptions and underlying SQLite close failure remain **NOT_RUN**. Physical device, real provider/model network, production credential identity/rotation/revocation, in-flight crash recovery and interrupted scheduling-marker faults remain unproven. No production authority is installed; ordinary UI remains SyntheticLab. Real use still needs approved source/profile/reviewer/payload authority, conservative total-token/spend proof, actual credential handle identity/revocation/retention policy, and separately authorized provider/physical-device acceptance.

PR86 and dependent I04 combination **HOLD remain**. PR90/Dart8/UI are untouched and unrun. The denied old script task.db -> HTTP -> original-state reopen and hidden suites were not executed/retried/split/rewritten/rerouted. No credential read/configuration, payment, real model request, deployment, force push, branch deletion or main/develop merge occurred. All implementer/reviewer writers stopped; both CI watchers exited at their respective terminal states.

## Rulings recorded

- Used the clean dedicated lab branch in the supplied checkout instead of a second checkout after checking remote occupancy. If that occupancy judgment were wrong, re-isolation would be needed; no source writer overlapped.
- Isolated process-lifetime retention using fixed compiled APK packages (initially seven, necessarily eight after the constructor/destruction finding), without reset/retry mechanisms. Incorrect isolation would require redoing acceptance; tests explicitly check fresh packages, private process identity and no duplicate owner.
