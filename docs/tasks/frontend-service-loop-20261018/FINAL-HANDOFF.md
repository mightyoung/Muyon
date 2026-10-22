# Private Service frontend loop

Source: `2f8f4da674e871708880dcc792a1c9dafb3a17f3`, branch `lab/android-compose-frontend-loop-20261018`. [Draft PR88](https://github.com/mightyoung/Muyon/pull/88) targets frozen B06 branch, not main/develop. This documentation branch has the same product tree plus evidence.

**PASS — CI API26 x86_64 emulator, two actual instrumentation tests, including private Service process death and lookup-only recovery.**

Implemented existing Muse Send → actual private Service/AIDL → same Rust controller/Agent → registered trusted readonly SQLite tool → ordered result batch and ORIGINAL durable receipt → conversation UI. Persisted request identity, bounded callbacks, cancellation/UNKNOWN handling and lookup-only recovery are included. Existing visual design is retained.

This is a deterministic supplier read on a synthetic schema12 SQLite copy. It is not arbitrary model chat or model-token streaming. Production store authority and approved live provider/budget integration remain unavailable and fail closed. Physical/arm64 runtime, live model and production user data are NOT_RUN; PIP/OCR and PR87 are deferred.

- [Exact-source loop CI39107347147](https://github.com/mightyoung/Muyon/actions/runs/39107347147): PASS, all four jobs SUCCESS. Scoped Rust21/21, design oracle18/18, generated binding reproduction and both API26 ABI producers PASS.
- [Compose CI39107350771](https://github.com/mightyoung/Muyon/actions/runs/39107350771): PASS; JVM state checks, AIDL/Kotlin/app/test APK build and lint.
- Fixed-SHA independent review: four initial blockers fixed at93beaf18; final scoped review2f8f4da6 found no new blocker or test weakening. Reviews and logs in `final-evidence/` and `integration-logs/`.
- [Combined APK and raw device artifact](https://github.com/mightyoung/Muyon/actions/runs/39107347147/artifacts/12129012677); app SHA256 `67bca372b01973b46926406efcbfd4fb6aaf95c42a94643690444f58c7efce41`.

Earlier failed/cancelled runs remain failed/cancelled. Source73 original APK test failed on substring/visibility assertions before recovery; source2f corrects test matchers/keyboard handling without removing business assertions. An AVD directory mismatch made source73 device startup hang; root cancelled only its own run, retained logs, and fixed explicit AVD paths and bounded waits. Root also cancelled superseded own44/fa runs. Original inherited A39102166368 is CANCELLED, not cancelled or retried by root, and no other green substitutes for it.

An initial store worker accidentally ran an unfiltered cargo suite, including fresh synthetic HTTP tests, then failed missing MUYON_PLUGIN_CHILD. It was not retried; raw incident log and full failure ledger are in [FINAL-VERIFICATION.md](FINAL-VERIFICATION.md). I04 original denied input/action was not retried; dependent merge hold remains. No main/develop merge, force push, branch deletion, deployment or credential/license configuration occurred.

Full source/CI/hash/failure ledger: [FINAL-VERIFICATION.md](FINAL-VERIFICATION.md). Continue from the fixed product SHA; no writers remain active. Next separate gate is authorized production-store scope/provider integration, not another UI redesign.

Delivery-only follow-up: exact accepted APK saved to Library as `libfile_cca1bb43d0cc8191b6113d9c0d9e9c70`; [native download, package/signature and installation-data details](DELIVERY.md). All implementation writers stopped; [fresh-session dependencies and exact missing production/model bindings](NEXT-SESSION.md). No new feature, model, HTTP or installation operation was executed.
