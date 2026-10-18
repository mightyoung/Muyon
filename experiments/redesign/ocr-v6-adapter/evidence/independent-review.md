# Independent review — OCR v6 isolated slice

Reviewed on 2026-10-18 by a separate read-only reviewer. Fixed implementation:
`8684e1ca0f002c0944ec6b24a33e969085ee3b9b`, product base
`3f1be180bb009a91e659c113ba5b1916e5360332`. First command was
`git rev-parse HEAD && git show --stat --oneline 8684e1ca`; HEAD matched.
Only this report was added by the reviewer; implementation, tests and original
evidence logs were not edited. No merge, push, deployment or host changes.

Verdict: the independent Rust contract/Kotlin adapter source slice is deliverable
for LeaderB review. **Production integration/release remains blocked.** No blocking
defect was found in the tested Rust task/source/geometry acceptance path. The
following concrete native failure risks must be resolved before formal App
integration; passing JVM tests do not resolve them.

## Findings

1. **P2 — inherited OpenCV exception paths do not deterministically release native
   allocations.** `vendor/paddleocr/com/paddle/ocr/postprocess/QuadTextCrop.kt:63-76`
   creates perspective transform `m`, then allocates `dst` and calls
   `warpPerspective` before either release is protected by `finally`. If allocation
   or warp throws, `m` and any created `dst` have no deterministic release.
   Lines 79-81 similarly allocate `rotated` before a throwing rotation and release
   `dst` only after success. `vendor/paddleocr/com/paddle/ocr/preprocess/DetPreprocessor.kt:68-93`
   allocates `resized`, `floatMat` and split channels, but exceptions from
   `convertTo`, `split`, arithmetic, FloatArray allocation or `get` skip subsequent
   releases. Session cleanup in `OcrExecutor.kt:62` cannot free these inaccessible
   temporary Mats. This is a source-confirmed ownership gap, not merely a missing
   benchmark; repeated failures can retain native memory until eventual wrapper
   collection/finalization. Add exception-safe ownership in a tracked upstream
   adaptation (update source pins/notice accordingly), then exercise injected
   native failure and repeated-job memory behavior. The README already avoids
   claiming native error/OOM cleanup; this finding makes that gate concrete.

2. **P2 — native loader failures can escape the controlled error envelope.**
   `kotlin/src/main/kotlin/com/mightyoung/muyon/ocr/OcrExecutor.kt:53-67` catches
   `Exception`, which excludes `LinkageError`/`UnsatisfiedLinkError` and
   `ExceptionInInitializerError`. The real factory calls ORT during
   `OfficialRuntime.kt:28`; `ORTSessionManager.kt:39` initializes ORT, and
   `OCREngine.kt:46-48` releases then rethrows `Throwable`. Thus an ORT native
   linkage/initialization error can propagate outside `OcrFailure`, despite the
   adapter's controlled-error intent. OpenCV's own load wrapper handles its
   `UnsatisfiedLinkError`, but that does not cover ORT. Map the specific expected
   linkage failures to a stable unavailable/inference error at the platform
   boundary, preserving cancellation and avoiding indiscriminate swallowing of
   fatal VM errors; add a JVM factory-throws-LinkageError regression test and
   actual Android missing/incompatible-native-library coverage. This is not a
   claim that an observed device failed: no Android execution was available.

## Verified strengths and boundaries

- `core/src/lib.rs:95-132` validates source/raster identity, input budgets,
  transform and expiry before the authority port. Lines 144-199 make attempted
  completion terminal, recheck authority/deadline/identity, validate confidence
  and convex finite bounded geometry, project into source coordinates and call
  the atomic store port. The concrete production authority/store implementations
  are intentionally absent; test doubles are not evidence of durable authority.
- Kotlin hashes the exact image and locked assets before factory creation
  (`OcrExecutor.kt:25-52`), checks cancellation/expiry around inference, and closes
  the returned runtime in non-cancellable cleanup. `SerializedRuntime.kt:10-15`
  serializes use/release and rejects use after close. API24/25 tests prove no
  factory invocation in this JVM path; they do not prove ART class/native loading.
- `OfficialRuntime.kt:24-41` calls the vendored real PaddleOCR det/rec pipeline,
  checks normalized PNG dimensions and maps quadrilaterals/confidence. It is an
  actual SDK construction adapter, not a fake OCR output implementation. It has
  only signature-compilation evidence, not Android inference evidence.
- Lock tests verified 26 vendored source hashes and both exact dictionary YAMLs;
  real CPU tests reverified cached model/config/card bytes against model locks.
  This review did not independently redownload all upstream source files or
  establish general model quality. Source immutability and provenance are pinned;
  desktop Python postprocessing is explicitly different from Android.
- `git diff 3f1be180 8684e1ca --name-only` stays within the isolated module and task
  note. No old Dart OCR, embedding, host or Android minSdk file changed. README
  accurately marks full migration/device/PDF/store/index/v5 regression as NOT_RUN.

## Reproduction performed

All commands ran from `/workspace/muyon-ocr-v6`; outputs were read directly and
original logs were left intact.

```sh
CARGO_HOME=/workspace/toolchain/cargo RUSTUP_HOME=/workspace/toolchain/rustup /workspace/toolchain/cargo/bin/cargo test --locked --manifest-path experiments/redesign/ocr-v6-adapter/core/Cargo.toml
JAVA_HOME=/workspace/toolchain/jdk17 /workspace/toolchain/gradle-8.13/bin/gradle --no-daemon -g /workspace/toolchain/gradle-home -p experiments/redesign/ocr-v6-adapter test
PYTHONPATH=/workspace/toolchain/python OCR_ASSETS=/workspace/ocr-assets python -m unittest discover -s experiments/redesign/ocr-v6-adapter/checks -p 'test_*.py'
```

Results: Rust **9 passed**, Kotlin **14 passed** / BUILD SUCCESSFUL, Python
**3 passed** / OK. Python includes real desktop CPU tiny/small det+rec on five
synthetic images twice per model, geometry checks and lock checks. Android native
adapter inference, device memory/performance/thermal remain **NOT_RUN**.

Also called `native_audit.audit(Path('/workspace/ocr-deps'))` and compared its
JSON-roundtripped output to `evidence/native-audit.json`: exact equality,
**16 libraries**, shipping gate **BLOCKED**. An initial direct Python equality
comparison failed because in-memory artifact tuples differ from JSON arrays;
normalizing both to JSON resolved that representation-only mismatch.

## Remaining integration gates

Resolve both findings above; replace/rebuild and pin OpenCV/libc++ for 16KiB ELF
alignment; validate SDK min26/source adaptation without raising product min24 or
using overrideLibrary; actual APK/ZIP/ABI/API24/26/16KiB loading and inference;
private Service authorization and cancellation/clock transport; W1 file/PDF
raster provenance; atomic durable Rust extraction store and separate index task;
representative language/quality comparison including frozen v5 regression.
These gates are required before claiming formal App migration complete. The
existing tiny default, small comparison and unchanged embedding decision stand.
