# OCR v6 isolated migration slice

Current follow-up: [API26 ownership and packaging handoff](../../../docs/tasks/OCR-V6-API26-FOLLOWUP-20261018.md).

Owner: OCR adapter writer. Base: product F2 `3f1be180bb009a91e659c113ba5b1916e5360332`.
Owned paths: **this directory only**, plus `docs/tasks/OCR-V6-ADAPTER-20261018.md`.
LeaderB `01a14d88-2a5f-76ac-886c-5feb4a2c40f5` owns all host/Service integration. This slice is not connected to the production App.
User approved Android 8.0+ (API26) for this follow-up. Only this isolated OCR module may declare minSdk26; shared App/Gradle/CI changes belong to LeaderB. No embedding changes, Dart edits, merge, deployment or user documents.

## Selection and immutable inputs

User selected v6. The execution baseline is **PP-OCRv6 tiny**, CPU, two threads;
small is an accuracy comparison candidate. v5 remains the unchanged historical
regression baseline in `apps/muyon/lib/services/ocr/` and the old platform-decision
record. There is no automatic v5 fallback. Unlimited-OCR/VLM is out of scope.

`models.lock.json` pins official Hub revisions, byte counts, SHA-256, full config
and model-card provenance. Tiny det+rec weights: **6,243,229 B**; small:
**31,039,890 B**. These exclude runtimes, dictionary configs and packaging overhead.
Models/cards declare Apache-2.0; source/third-party licenses are in `licenses/`.
No weights are committed. Recognition YAML fixtures are exact public upstream
configs, with 6,905/18,709 dictionary entries including space, plus CTC blank.
Official model cards describe Chinese/English; this is not universal language support.

`upstream.lock.json` fixes PaddleOCR `dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf`.
The SDK source count is recorded by the original lock (26 Kotlin files), copied
under `vendor/paddleocr/`. `upstream.lock.json` preserves original source hashes;
`upstream-adaptations.lock.json` records the narrowly changed ownership paths and
their resulting hashes. Original Apache-2.0 headers remain intact. `OfficialRuntime.kt` reuses its det normalization, DB
postprocessing, perspective crops, rec normalization and CTC decoder. The exact
parameter identity is `ppocr-android-dab3fe35-defaults-v1`: BGR detection;
min-side 64/max-side 4000; thresholds .3/.6, unclip 1.5, candidates 3000,
no dilation; RGB recognition, height48/max-width3200; batch1, rec threshold0.
These are **SDK defaults**, different from frozen det YAML .2/.4(tiny)/.45(small),
unclip1.4. They must be compared before a product quality decision; no claim of
PaddleX/YAML parity is made. Engine thread count2 does not imply NPU.

## Authority and transport

1. W1 provides a Rust-owned DocumentRef snapshot: scope, stable ID, revision,
   source SHA-256 and opaque blob ref. Display names stay in W1/UI, not task authority.
   W1 rasterizer supplies zero-based physical page, orientation-normalized PNG,
   raster digest/dimensions, original EXIF orientation, source dimensions/units,
   and nonsingular raster-to-source homography. PDF renderer/parser version must
   be stored by W1 with this snapshot; current crate does not implement rasterization.
2. Rust `Task::begin` bounds pixels/duration, fixes model/algorithm and calls
   `SourceAuthority::allows_ocr`. This is a required integration port, not an
   allow-all implementation. Service owns task IDs, lifetime and cancellation.
3. The private Service passes `Request` JSON to `OcrWire.decodeRequest`, obtains
   the actual raster through its controlled handle and runs the Kotlin executor
   on a worker. The UI must never call the runtime directly or supply an arbitrary
   filesystem path. No Activity, UI command, network/download or index writer is
   provided by this module. Host IPC/UID/permission enforcement is NOT implemented here.
4. `expiresAtMs` is an absolute **monotonic boot-time millisecond** deadline shared
   with Android elapsedRealtime, not a wall-clock timestamp. A host with another
   clock must convert remaining budget once at dispatch and preserve the Rust
   deadline for acceptance. Max duration120s; encoded input32MiB; pixels16m;
   sides4096; lines3000; text1MiB/page and64KiB/line. Models and dictionary are
   hashed before each session pair is created; the factory uses the same immutable
   app-private APK assets. Downloaded/mutable cache support is not exposed.
5. Kotlin returns raster-coordinate quadrilaterals, recognition confidence, nullable
   detection confidence (upstream does not expose it), model and parameter versions,
   raster digest and job ID. It has no source/grant/store authority. Rust rechecks
   current source/grant, identity, finite convex in-bounds quads and confidence,
   maps to source coordinates, then invokes `ResultStore::commit_if_current`.
   The store MUST atomically recheck source revision/digest/grant and persist the
   extraction under scope; rejection is terminal, never a success stub.
6. Cancellation and completion are serialized by Rust `&mut Task`. Result arrival
   after cancel/timeout/revocation cannot commit. Kotlin cancellation is cooperative:
   it checks before/after native work; synchronous ORT is not force-preempted.
   Service must retain the worker until native return and cleanup. A timeout means
   discard result, not proof that CPU/memory use stopped at the deadline.
7. Rust persistence is **extraction only**. Index writes are a later Rust application
   task which checks the current source again and stores model/algorithm/anchor
   versions. Delete/revoke/digest change invalidates extraction/index use. OCR text
   remains unreviewed derived content, not a business fact or outbound grant.

Controlled adapter errors distinguish unsupported platform, invalid request/result,
missing/corrupt models, inference failure, timeout and cancellation. Exception text
is not copied into results/logs. Empty valid page is distinct from unavailable.
Resources: one det/rec session pair per job, release in a non-cancellable finally;
source sessions/tensors/mats retain upstream ownership. QuadTextCrop,
DetPreprocessor and resizeToMultipleOf32 now use exception-safe ownership and
success-only crop transfer. Normal detection releases intermediate large Mats at
their last use before allocating/copying the final tensor. Tests observe real
OpenCV JNI Mats, inject cancellation and trigger real native/channel errors;
original failing logs are retained. These desktop tests do not prove Android OOM
cleanup or peak memory. LinkageError/initialization failures remain controlled
INFERENCE_FAILED; fatal VM errors are not indiscriminately swallowed.

## Android API26 packaging candidate

The user explicitly approved Android8.0+ after the original handoff. The isolated
`android-packaging/adapter` now declares minSdk26, matching the upstream SDK;
`probe` is an installable build/audit target without Activity, Service, permissions
or fake OCR success. Shared App/CI minimum API changes remain LeaderB-owned.
Executor API24/25 rejection tests stay as defensive no-native-load controls.

Current runtime dependency is official Maven Central **org.opencv:opencv:4.12.0**,
with ORT1.21.1 unchanged. Exact AAR digests, official source tag/POM, four ABI
inventories, LOAD/RELRO checks and versioned strong imports against NDK API26
stubs are recorded in `evidence/native-candidate-audit.json`. Original
`native-audit.json` preserves the rejected QuickBird4.5.3 4KiB evidence.
`checks/native_packaging_audit.py` audits real APK native entry sets, locked AAR
byte identity, uncompressed ZIP16KiB offsets and the three runtime model assets.
AARs do not bundle transitive native dependencies; consume the Gradle project or
publish matching Maven metadata. Do not ship the bare adapter AAR alone.

Root JVM tests compile against the actual Android AAR signatures but execute
OpenPnP4.9.0-0 desktop JNI for Mat ownership; that test dependency is excluded from
the Android project. Official Android JNI loading and det/rec parity remain
NOT_RUN. `checks/native-parity-desktop/` independently runs actual desktop
OpenCV4.5.3 and4.12 det+rec: ten synthetic cases matched exactly at every measured
stage. Its README records NumPy metadata override and Python/Kotlin differences.
This is supporting version-sensitivity evidence, not Android runtime parity.
The host must still reassess libc++ collision with its Rust/native dependency set.

## Verification and reproduction

JDK17 + Gradle8.13 (local external toolchain), Kotlin2.1.0, coroutines1.9.0;
Rust1.99.1. No Android SDK license was newly accepted.

```sh
cargo test --locked --manifest-path core/Cargo.toml
gradle --no-daemon test
python checks/asset_cache.py /external/ocr-assets
python checks/native_audit.py /external/aar-directory
OCR_ASSETS=/external/ocr-assets PYTHONPATH=/external/python-deps \
  python -m unittest discover -s checks -p 'test_*.py'
```

The current actual Android build/audit commands are:

```sh
gradle -p android-packaging --no-daemon :adapter:assembleDebug :probe:assembleDebug \
  -PocrAssets=/external/ocr-assets
python checks/native_packaging_audit.py /external/current-aars \
  --apk android-packaging/probe/build/outputs/apk/debug/probe-debug.apk \
  --ndk /external/android-sdk/ndk/28.2.13676358 --require-static-pass
/external/android-sdk/build-tools/36.0.0/zipalign -c -P 16 4 \
  android-packaging/probe/build/outputs/apk/debug/probe-debug.apk
```

Use the exact pinned `ort.aar` and official `opencv.aar` for the current audit.
`android-packaging` has its own Gradle locks and SHA256 verification metadata.
Its Gradle plugin is8.11.1, compile/target SDK36; it uses Gradle8.13/JDK17.
No model download occurs in the App: verified external models are staged at build.

The following original audit command remains for reproducing the rejected input:

For the audit, `aar-directory` contains `ort.aar` and `opencv.aar` from the Maven
coordinates in `checks/native_audit.py`. These external tools/assets are not stored
in git. Gradle extracts compile-only classes from Android AARs. New Mat ownership tests
load desktop JNI explicitly; they do not execute the Android .so files.
Pinned Python versions are in `checks/requirements.txt`.

Raw failing/passing logs in `evidence/` preserve TDD checkpoints. Setup logs are
separate: initial Gradle was interrupted for proxy configuration, then JRE-only and
JDK trust-store errors were corrected. Those are not product regression failures.
SDK dictionary parser is compared against PyYAML's exact codepoint digest of both
locked fixtures. Shared JSON fixtures test Rust/Kotlin geometry representation.

Desktop ORT1.21.1 CPU ran real tiny/small det+rec twice per generated English,
Chinese, colored, rotated and blank image. `cpu-results.json` contains actual
outputs, tensor/input digests and diagnostic elapsed times. All five cases were
repeat-deterministic in this environment. Tiny removed spaces on the Chinese line;
small preserved them. This is a tiny synthetic smoke set, not business accuracy.
`checks/` reuses fixed upstream Python DB/crop helpers; its pyclipper geometry and
OpenCV5 differ from Android PolygonUnclip/OpenCV4.5.3. Thus these runs establish
model execution and sample behavior, **not Android pipeline numerical parity**.
Generated text/image pixels are synthetic; fonts are not redistributed.

Historical original verification below predates the API26 packaging follow-up;
current build/audit identities are in the follow-up handoff.

NOT_RUN: ART/Binder/private Service authorization, native runtime
adapter inference, real device performance/memory/thermal, API26 native loading,
16KiB device loading, PDF rasterization/layout/tables/formulas, W1 file authority,
actual durable extraction/index stores, production wiring, full old Flutter suite,
and actual old Dart v5 regression execution. These gates remain for LeaderB/W1/W7.
