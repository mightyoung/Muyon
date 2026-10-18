# OCR API26 follow-up independent review

Review date: 2026-10-18. Baseline: `67e3f4f4561c306d8ff2ebd58c5c2728eedb2aed`.
Initial immutable candidate: `ed2cd18c7918468e47b2035d8ec315ca136544b3`.
Final source candidate: `9a2ac7864d7bccf7fc2622dd561b22a58ca3498a`.
Reviewer made no code/config changes and did not run concurrent Gradle. Only this report and `review-*` evidence are reviewer deliverables.

## Finding

P2 — clean probe build fails with a missing custom debug keystore. Initial candidate `android-packaging/probe/build.gradle.kts:6` sets `storeFile` to `build/ocr-probe-debug.keystore`, without a generation task. The documented assemble command fails in `:probe:validateSigningDebug` when that file is absent; root's fixed-build attempt demonstrated the failure after 44 tasks. Fixed in `9a2ac7864d7bccf7fc2622dd561b22a58ca3498a` by deleting only the custom signing override, restoring AGP standard debug signing. I independently reviewed this one-line config diff; the two other added files preserve the failing log and its exact source SHA. Final fixed package validation passes as detailed below; the P2 finding is resolved.

## Independent completed checks

- `cargo test --locked --manifest-path core/Cargo.toml`: 9 integration tests pass on both the initial and final source candidates, no ignored tests; `review-rust.log`.
- `PYTHONPATH=/workspace/ocr-python OCR_ASSETS=/workspace/ocr-assets python3 -m unittest discover -s checks -p 'test_*.py'`: 3 pass on both initial and final source candidates; `review-python.log`.
- `python3 checks/asset_cache.py /workspace/ocr-assets`: all four frozen det/rec model/config bundles match; `review-assets.log`.
- `review-source.log` records final SHA, 71 allowed changed paths, frozen source/model/config paths and source/verification hashes.
- Initial diff has 69 paths (final candidate adds only two signing-RED evidence files), all beneath the OCR module or the independent task document. No changes to models.lock.json, dictionary fixtures, Rust core, main Kotlin adapter/contract, application or embedding paths. Both verification metadata files include the exact official OpenCV4.12.0 and ORT1.21.1 AAR digests. Three original vendor files exactly match the upstream hashes in the baseline; adaptation hashes are checked by the independent Python tests.

## Source and evidence assessment

QuadTextCrop finally blocks release rectInput and every crop temporary, transferring only a successfully returned Mat. ImageUtils releases unsuccessful resize destinations. DetPreprocessor releases RGB conversion, resized/float images and channels through finally; the large resized/float/RGB intermediates are released before FloatArray extraction. Borrowed src remains caller-owned. Numeric operations, arguments and normalization constants are unchanged. No blocking ownership defect found in the reviewed source.

The Mat tests instrument real desktop JNI Mat constructors/releases via ByteBuddy; they assert explicit release and empty(), then clean leaks after RED assertions. Native/channel exception tests are real; cancellation is injected before selected calls, rather than claimed as native cancellation polling. Archived mat-red.xml records five failing ownership assertions on original source; mat-lifetime-red.log records the extraction-time regression failure. I inspected these historical RED artifacts and confirmed baseline vendor bytes, but did not independently rerun RED or claim independently observed Kotlin/Android execution. Parent ran final Kotlin and Android Gradle builds with --rerun-tasks. I read the successful build logs and independently summed final JUnit XML: 22 tests, 0 failures/errors/skips. These are inspected parent-run Gradle results, not a second reviewer Gradle execution.

Packaging audit checks pinned AAR digests, exact four-ABI/16-native-file inventory and byte preservation in APK, LOAD alignment/congruence, RELRO writable overlap, strong versioned dynamic imports against API26 NDK stubs, APK native compression/ZIP offsets, manifest minSdk26, and frozen tiny det/rec/YAML assets. Adapter AAR is a standard AAR with Gradle transitive dependencies, not a fat bundle. The 16KiB ELF claim is explicitly for 64-bit ABIs; published 32-bit libraries remain 4KiB. Official OpenCV is org.opencv:opencv:4.12.0 and ORT remains 1.21.1, locked in root/Android dependencies and SHA verification metadata. Final fixed artifact audit and independent negative controls pass below.

Desktop OpenCV4.5.3/4.12 Python parity uses the same ORT1.21.1 host and frozen models, and its ten synthetic cases / 44 measured stages passed exactly in archived evidence. I inspected the comparison/sensitivity harness and limitations. This is not QuickBird Android versus official Android JNI parity: Python geometry, binding and normalization differ from Kotlin, and NumPy metadata is overridden for the 4.12 worker. No Android inference conclusion is inferred from these desktop results.

The final fixed-source desktop rerun initially failed at import because parent PYTHONPATH pointed at CPython3.12/NumPy2 packages while workers are Python3.9. Parent preserved fixed-parity-environment-red.log and reran the unchanged source with env -u PYTHONPATH. This is environment setup failure, not a measured numerical mismatch. The parent-owned rerun completed successfully: fixed-parity.log reports desktopDiagnosticPassed=true for 10 cases. I inspected that log and confirmed parity-desktop.json has no diff from the final source candidate archive. This remains desktop diagnostic evidence only.

API26 ART/JNI execution, Android det/rec parity, 16KiB device loading, peak memory/performance/thermal behavior, host libc++ integration, production service/grants/store wiring and full old Dart v5 regression remain NOT_RUN. Static build/package PASS cannot close these gates.

## Final fixed candidate and artifact checks

Final source: `9a2ac7864d7bccf7fc2622dd561b22a58ca3498a`, matching followup-tested-sha.txt. Root Kotlin build completed successfully in 42s; Android completed successfully in 58s with all 62 tasks executed. The prior custom-keystore failure remains in fixed-android-signing-red.log with its original ed2cd18c source identity.

I independently ran native_packaging_audit.py with --apk, --adapter-aar, --ndk and --require-static-pass. It exited 0; review-package-audit.log is exactly equal to the parsed parent fixed-package-audit.json. All six static gates pass, including actual adapter AAR minSdk26/assets, APK minSdk26, 16 native entries from four ABIs, unchanged AAR native bytes, three frozen model/config assets, strong API26 imports and 64-bit ELF/ZIP alignment.

- APK SHA256: `5eec6ea2576f7597ec64e03be7d39c6f7d09fec3d4f88b31549b026b064baa5a`.
- Adapter AAR SHA256: `37c4f1db5d6b7109a559c63ee5dc1d972502040058ce008e10b7e9ad9262b68d`.

I independently ran native_packaging_negative.py on this exact APK. It exited 0: 4KiB synthetic LOAD rejected, 16KiB LOAD accepted; missing libopencv_java4.so, corrupt tiny det model, unaligned ZIP and missing API26 stub providers were all rejected (review-negative.log). The control ELF is synthetically generated and readelf-parsed; package mutations use the actual locked APK. No modified APK is represented as a signed runtime test.

Outcome: no remaining source/static-package blocker found within this review scope. The clean-build signing P2 is fixed and verified by the final successful build. Device/host integration and numerical parity gates remain NOT_RUN as above; this review does not grant shipping approval.
