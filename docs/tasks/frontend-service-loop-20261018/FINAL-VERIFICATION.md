# Frontend/private-Service loop — final evidence

Product source is frozen at `2f8f4da674e871708880dcc792a1c9dafb3a17f3` (CI and instrumentation only differ from73a582d3) on `lab/android-compose-frontend-loop-20261018`. [Draft PR88](https://github.com/mightyoung/Muyon/pull/88) targets frozen B06 documentation branch `docs/leaderb-next-20261018`, not main/develop. This evidence-only branch records results without changing the tested source or triggering new product builds. Earlier preparation HANDOFF/INTEGRATION pending statements are superseded here.

## Delivered source path and limits

Existing Muse chat input → existing Application/session → same private Android Service/AIDL/lease lanes → generated UniFFI → same Rust AgentServiceController/worker → registered trusted supplier read → readonly SQLite schema12 → durable ORIGINAL ToolRegistry receipt → ordered cursor events → conversation result and receipt UI. Request identity is persisted before submit; Service death clears current disclosure, keeps historical receipt, disables resend, and reconciles the original request. Cancellation and uncertain terminal errors fail closed.

The SQLite asset is explicitly synthetic; all nonfixture authority selections fail closed. The input really reaches Rust Agent state, but the trusted read is deterministic. Events arrive as an ordered result batch after the short read, not model-token streaming. No live model, production user-store authority bridge, or production provider budget has been configured. Those are remaining gates, not completed work. PIP/OCR candidates and PR87 are deferred.

## Fixed-source verification

Latest exact-source full workflow SUCCESS at07:28 UTC: two actual API26 x86_64 CI emulator tests PASS, UI PID4599, Service PID4672→4699, unchanged ORIGINAL receipt identity01fb3a3c7b7745a22cf8a810378e3d74 and invocation_id equality asserted. Only original-request lookup followed death; no second Send. Physical device NOT_RUN.

Latest artifact12129012677: appAPK SHA256 67bca372b01973b46926406efcbfd4fb6aaf95c42a94643690444f58c7efce41; testAPK2e076a5bd8cf5288bcae0c23dcacaa6b8cab38e6ad5b39d1f0a52c3f858a5db0; ZIP746894f4d30b78da8eb1c1151c25b966e96f7afb01e0b85b5abca60860f9e8dd. Downloaded and independently checked both APK hashes against package-result.json: PASS. That raw package-result Android_runtime=NOT_RUN describes pre-device packaging stage; device-result.txt, instrumentation.log and final outcome record establish subsequent PASS without rewriting the original manifest. Logcat dump captured the real PID/receipt continuity. Log-buffer clear was separately UNAVAILABLE and did not replace the successful instrumentation gate; its status file is retained.

Final full selector semantic audit includes old-failure→final-assertion mapping, finds all partial checks anchored to exact tags/subtree, and confirms no weakening of exact projection/receipt/recovery invariants: final-evidence/muyon-selector-semantic-audit.md.

Latest [Compose39107350771](https://github.com/mightyoung/Muyon/actions/runs/39107350771) at2f8f4da6 SUCCESS; duplicate push39107347173 auto-CANCELLED. JVM state checks, app/test APK compilation and lint passed.

Latest2f native SHA256 arm64 f0380259af27d3ae4d646258ced33033eef8da51cde30f23d4c777ec84e99141; x86_64 04801a9582a1d66a0e7f247acc70301394d2a4e19331041d26c5ec0532b5a2e0. Latest21 scoped Rust tests (18 integration plus3 regressions) and18 design oracle cases passed; exact generated binding comparison passed. These latest binaries are distinct from source73 because source identity is embedded.

Latest full pipeline [39107347147](https://github.com/mightyoung/Muyon/actions/runs/39107347147) at2f8f4da6. Independent final scoped review found no gate weakening; test keyboard handling and intended substring matches corrected. Previous full pipeline: [39107156686](https://github.com/mightyoung/Muyon/actions/runs/39107156686), source44df2265. Independent immutable APK harness [39107132638](https://github.com/mightyoung/Muyon/actions/runs/39107132638) at210b1ddac609c5546394c66c082d2a2ebb921e92 verifies the original73a APKs and then runs the unchanged actual two tests; it cannot substitute for44df exact-source results. Source73→44 changes only CI AVD paths and bounded waits.

- [Loop39106124839](https://github.com/mightyoung/Muyon/actions/runs/39106124839): source73a582d3; scoped Rust integration18/18 plus exact regression filter3/3 PASS; design oracle18/18 PASS; generated Kotlin byte comparison PASS; arm64-v8a and x86_64 API26 native producers PASS.
- [Compose39106128442](https://github.com/mightyoung/Muyon/actions/runs/39106128442): SUCCESS, JVM state checks, AIDL/Kotlin/app/test APK build and lint. Duplicate39106124840 auto-cancelled.
- Independent fixed-source reviews addressed four blocking findings at93beaf18; follow-up2a763bdf and scoped73a selector/workflow review found no new blocker. See retained review reports. Source review does not substitute for runtime proof.
- Native SHA256: arm64 `0ad29fe47d955c9710294611e23a6030474efb8ff28a62aff9197c82f72cb93f`; x86_64 `733af9505c30b6ace3962943f08d6d32adf72f0441971355138a9f4ca942f0a8`. These are the latest73 source producers, not earlier989 binaries.
- Runtime ARM64 device/physical device and production model/store use remain NOT_RUN.

## Failures and cancellations retained

- Immutable73 harness39107132638 FAILURE:2 tests executed; Save label visibility failed while keyboard remained, and happy read failed at partial disclaimer assertion (default substring=false despite correct full text). Prior ordered exact supplier/completed/ORIGINAL receipt assertions had passed, but Service recovery had not executed; no full acceptance claimed. Fixed only test setup/matchers at2f8f4da6, visibility assertion retained.
- Source44 full39107156686 cancellation requested by root after this known instrumentation failure, to avoid repeating invalid assertions and release latest pipeline queue. Scoped/native bothABIs had passed; final CANCELLED confirmed; raw package log retained. Compose39107160928 succeeded. B06 original run untouched.

- Source73 run39106124839 was cancelled by root after nine minutes stuck at unbounded adb wait-for-device. Last pre-cancel raw line07:08:22.531977Z; cancellation07:17:03.613573Z. Emulator log proves Unknown AVD name/default directory mismatch. Instrumentation NOT_RUN in this run. Original combined package retained as artifact12129275262, zipSHA256 e319ded58e9f57266123e7889d01c54db6955963ab46bfd9dd35f1b4624f7e3e; appAPK b40dc3fdb6e61a8bebcac6a69ee4e96ed1ac29faa2fbe48753465e1e3266e1b5; testAPK afc453f7688958ac7c27ee03f6181f740393069769e185208f5f9abf3640c89c. CI fix44df explicitly shares AVD directory and bounds both device wait and instrumentation; boot_completed must equal1. Product files unchanged. Independent review at44df found no new blocker.

- 39104528559: scoped helper permission failures under runner umask022; private test directory creation fixed, production checks unchanged. Native producers succeeded, package skipped.
- 39104985154: scoped tests succeeded; bindgen invoked at wrong cwd. Corrected crate cwd and byte comparison.
- 39105160635/source989: combined package and APK verification succeeded; runtime aborted because adb absent from PATH. Runtime NOT_RUN in this run.
- 39105665986/immutable989 harness: installed API26 APKs; optional logcat clear failed before instrumentation. Runtime NOT_RUN there.
- 39105898766/immutable989 harness: actual two instrumentation tests FAILED on ambiguous prompt/empty-edit selectors. Corrected selectors at54caeac5; mandatory business/receipt/recovery assertions unchanged. This failure is not treated as a passed read.
- 39105714711/sourcefa176: root requested cancellation of its superseded own integration run to release the queue after the selector failure was known; final CANCELLED. Compose39105717693 succeeded.
- Original inherited A generic39102166368 at3f3a2368648db5e9767f11adcae4548ac5da2527 is COMPLETED/CANCELLED. Root never cancelled or retried it. Actor/cause are not inferred. Dedicated A green39102166352 is not a replacement.

Store worker once mistakenly ran an unfiltered cargo test command. It executed fresh synthetic temporary HTTP recovery/transport tests then failed six host_http cases for missing MUYON_PLUGIN_CHILD (exit101). Full raw `evidence/store-cargo-test.log` and prior INTEGRATION incident record are retained. This exceeded the scoped test plan, was not retried, and did not use I04 original old-state inputs. All subsequent tests used explicit target/filter allowlists. I04 original denied action and dependent-merge hold remain intact.

## Read-only follow-ups and unchanged refs

PR87 fixed38b59db43f2487700ff15971ee008f0024673a13 was read only:21 synthetic Python PASS; eight real Dart gateway fixtures UNCOMPILED/NOT_RUN; Hy24Rust not rerun. Static ledger semantic/error-body suggestions need adapter-specific validation before a future provider gate; this deterministic Rust supplier read does not call those Dart adapters. No PR87 integration or HTTP fixture run.

Final readback: main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`; develop `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`; PR86 OPEN/unmerged at3f1be180bb009a91e659c113ba5b1916e5360332. No merge, force push, branch deletion, deployment, new credentials, paid service, or license acceptance.

Raw exact-source logs and latest independent source reviews are in `final-evidence/`; earlier logs/reviews are in `integration-logs/` and `evidence/`. Artifacts retain the original run/source association. Continue only from the fixed product SHA; evidence branch is documentation-only.
