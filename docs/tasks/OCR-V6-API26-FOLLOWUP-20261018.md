# OCR v6 API26 follow-up — 2026-10-18

User decisions: PP-OCRv6; Android 8.0+ (API26) approved in the parent conversation.
Tiny remains the default candidate, small the comparison, v5 historical regression
only. Embedding, model bytes, dictionaries and their original source locks stay fixed.

Ownership: branch `feat/ocr-v6-api26-packaging`, isolated from sealed OCR archive
`67e3f4f4561c306d8ff2ebd58c5c2728eedb2aed` (tested runtime source
`d1c8096d22e2281641cccc7f8e5e8cd5490f1a14`). Only
`experiments/redesign/ocr-v6-adapter/` and this independent task record are modified.
The original handoff remains historical. Sole integrator is now LeaderB
`01a14d88-2a5f-76ac-886c-5feb4a2c40f5`; App shared Gradle, CI and minimum API
changes belong to that owner. UI remains independently owned. No main/develop
merge, force push, deployment, permission change, paid resource or I04 retry.

## Frozen-model rerun

Actual Rust contract tests: 9 passed. Actual Python tests: 3 passed. Four frozen
v6 bundles passed byte count/SHA256 verification. Tiny and small executed actual
CPU det+rec twice on each of five synthetic images. All ten pages have the same
text, boxes and input pixels as the old desktop report. Tensor hashes differ in
this fresh execution environment; the largest recognition-confidence absolute
difference is 2.980232238769531e-7. Both the new raw results and exact comparisons
are retained, including failures of bitwise equality. This is a desktop diagnostic,
not Android inference or proof of changed-OpenCV numerical parity.

Evidence lives under the module's `evidence/followup-*`. Tool caches and model
weights live outside the repository; no weight or font binary is redistributed.

## Integration conditions retained

The platform still must provide the private Service worker, real W1 source grant
and revision/digest authority, PNG raster/geometry provenance, boot-monotonic clock
and cancellation mapping, and atomic `ResultStore::commit_if_current` transaction.
OCR extraction and retrieval indexing remain separate; no success stub replaces
these seams. Service must retain work until synchronous native return and cleanup,
even after cancellation or timeout.

ART/native inference, real API26/16KiB device loading, OCR quality on real documents,
performance, peak memory, thermal behavior and full old Dart v5 regression are
NOT_RUN. Cloud development/build evidence cannot close these device gates.

## LeaderB-only shared minimum-API patch

The minimal source edit to the current Compose host is provided for its owner;
it has **not** been applied on this OCR branch:

```diff
--- a/experiments/redesign/android-compose-lab/app/build.gradle.kts
+++ b/experiments/redesign/android-compose-lab/app/build.gradle.kts
@@
-        minSdk = 24
+        minSdk = 26
```

This line alone is not CI migration. Current bridge evidence validators deliberately
pin API24: `android-rust-bridge-lab/checks/android_gate.py`, `package_gate.py`,
`test_verify_inputs.py` and `test_android_evidence.py`; the Android workflow also
labels its native check API24. LeaderB must change the producer/validator contract
and rebuild its own Rust/JNI/App evidence together, while retaining historical
API24 logs. Do not relabel the old API24 runs API26 or weaken negative controls.
The OCR executor already rejects API24/25 before invoking the native factory;
that defensive guard stays tested despite the newly approved installation floor.

## Implemented follow-up

Three upstream ownership adaptations preserve numeric operations: QuadTextCrop
transfers a crop only after success; DetPreprocessor releases all owned channels
and temporaries on exceptions/cancellation while preserving normal early release;
ImageUtils releases the resize destination if native resize fails. Real desktop
JNI tests produced five initial ownership failures, plus a separate regression
showing six live Mats where only the three channels should remain. The full
Kotlin suite now has 22 tests, including seven Mat tests, five injected cancellation
sites and twenty repeated normal calls. Original failure logs and source headers
remain in the evidence archive; the original upstream lock is unchanged.

The Android dependency is official Maven Central `org.opencv:opencv:4.12.0`, with
ORT1.21.1 retained. The independent `android-packaging` Gradle root builds min26
adapter AAR and a no-entry-point APK probe. It verifies frozen tiny assets before
staging; the checker also hashes the actual packaged assets. AAR consumers require
the pinned transitive ORT/OpenCV dependencies; the AAR is not a fat bundle.

A true desktop OpenCV4.5.3→4.12 diagnostic holds ORT1.21.1 fixed across both sides.
All ten sample pages and forty-four tensor/crop stages are bitwise equal, with
exact text/boxes/confidence. Numeric/text/missing-tensor negative controls reject
corruption. Its two Python3.9 workers use NumPy1.26.4; the 4.12 wheel's NumPy>=2
metadata override is explicit, actual imports/runs passed, and this is not a
production Python dependency recommendation. Python/Kotlin and desktop/Android
pipeline differences remain documented; Android det/rec parity is NOT_RUN.

Initial static-package checkpoint passed; the first fixed-source build then
exposed a probe signing configuration error: its custom build-directory keystore
was never generated. `fixed-android-signing-red.log` preserves this real failure
and `fixed-android-signing-red-source.txt` identifies its source. The subsequent
minimal fix restores standard Android debug signing under writable Android user
home. No signing key is committed or used as a production identity.

The final desktop parity orchestration initially inherited the host Python3.12
package path into its Python3.9 workers, producing an import failure. The raw
`fixed-parity-environment-red.log` is retained. Clearing that inherited PYTHONPATH
for the parity command restores the intended isolated workers; no runtime or
comparison source was changed for this environment correction.

## Final verification and delivery

Final tested code candidate: `9a2ac7864d7bccf7fc2622dd561b22a58ca3498a`.
All 83 tracked module inputs other than evidence and README documentation are
hashed in `evidence/followup-source-manifest.json`; its fingerprint is
`79738b567f6a955fa1d18fef4573f7dbfcda82e95021d2e62d4404a844671c4a`.
The final seal adds evidence/documentation only; runtime, tests, build and locks
are identical to the tested candidate.

| Verification on final candidate | Actual result |
|---|---|
| Rust contract | 9 passed, locked dependencies |
| Kotlin JVM/JNI | 22 passed, 0 failures/errors/skips, all six Gradle tasks executed |
| Python frozen assets/reference | 3 passed; tiny/small actual ONNX inference |
| Android adapter AAR + probe APK | 62 tasks executed, BUILD SUCCESSFUL |
| Official runtime binary imports | All 16 libraries, four ABIs, API26 strong versioned imports PASS |
| ELF/RELRO 16KiB | All 8 libraries in arm64-v8a/x86_64 PASS; 32-bit libraries retain 4KiB |
| APK ZIP16KiB + minSDK | All 16 native entries uncompressed/aligned, exact set/bytes, min26 PASS; zipalign PASS |
| Packaged immutable assets | Three tiny assets SHA/size match; adapter AAR min26/assets match |
| Desktop4.5.3→4.12 actual det/rec | 10 cases /44 measured stages bitwise equal; Android equivalence NOT_RUN |
| Independent review | Rust9/Python3 rerun, assets/source/locks reviewed, final Kotlin XML audited, full final package audit and all packaging negative controls passed |

Final local artifacts (debug probe, not production release):

- `android-packaging/adapter/build/outputs/aar/adapter-debug.aar`: 5,860,634 B,
  SHA256 `37c4f1db5d6b7109a559c63ee5dc1d972502040058ce008e10b7e9ad9262b68d`.
- `android-packaging/probe/build/outputs/apk/debug/probe-debug.apk`: 223,075,735 B,
  SHA256 `5eec6ea2576f7597ec64e03be7d39c6f7d09fec3d4f88b31549b026b064baa5a`.
  This includes four ABIs and standard debug signing; it is not a production App
  size budget, release build or deployed application. Binaries are excluded from Git.

Raw fixed-source commands/logs, original failing checkpoints, binary/asset audits,
negative controls and independent review are retained under module `evidence/`.
`followup-verification.json` links identities and evidence hashes. The independent
review found the clean-build signing defect, verified its one-line fix and found
no remaining source/static packaging blocker. It does not approve host integration
or distribution. Main/develop and the old sealed OCR branch remain unmodified by
this delivery. No ongoing writer or builder should be resumed from this seal;
LeaderB takes the branch as a reviewable adapter/packaging slice.
