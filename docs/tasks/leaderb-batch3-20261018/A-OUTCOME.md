# A Android verification outcome

Product remains exact clean `2fbdc13efd84cabf04623775f87e762cd0d08c11`; 340 tracked product inputs unchanged. Verification files were extracted from `a0c14e13b700a57b92fabab19dd546a636da2741` outside the product tree. No source edits, commits, push, external write or integration.

All six runners exited 0: Linux full (Rust9/JVM5/load-negative1/panic1), arm64-v8a API24, x86_64 API24, shipping package, ShippingService four variants plus same-run durable oracle and seven controls, and ordinary Android build after clean. Exact tool pins were retained.

Two ABI producers checked actual Rust and JNA ELF, API24 strong imports against exact NDK stubs, RELRO/NOW/nonexecuting stack and 16KiB segments. Package checked six native entries with exact hashes and uncompressed 16KiB ZIP offsets, app/test zipalign, minSdk24/targetSdk36/two ABIs, 163 JVM state checks, AIDL compilation and lint (0 errors, 6 warnings). Shipping Gradle executed81 tasks. Ordinary build passed after app/state clean, executed71 tasks without supplied bridge inputs; its APK contains four JNA/graphics native entries and no Rust bridge.

Raw logs, command sidecars, manifests, two shipping APKs, two ordinary APKs, libraries, generated bindings, synthetic durable records, lint reports and generated AIDL are retained. Each command sidecar has verified original-log hash and natural process cleanup. No owned build worker remains.

ART/Binder/UID/permissions/Android fsync/kill/rebind/device/emulator are NOT_RUN. JVM oracle does not observe actual first payload/exact handler count. Fresh compiled Service inverses and separate private Rust13 were not rerun here; historical evidence is not relabelled. New Linux shipping hash differs from historical pin and was explicitly recorded, without altering old inverse pins. These results apply to product2f only, not a combined candidate or acceptance of integration.
