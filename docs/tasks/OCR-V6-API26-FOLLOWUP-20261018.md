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
