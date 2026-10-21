# Android offline OCR and embedding · 2026-10-21

Integrated and locally verified on API26 arm64 emulator. Source:
`4a1534a6f10c5d645587740ad4507de26b8a13c2`.
Build ID:
`4a1534a6f10c5d645587740ad4507de26b8a13c2:2cb18838c2bbf47f1100ccc0fc0a00c368db02bae5c8c4f1cb363344a48f6d73`.

[Installable model-inclusive APK](/private/tmp/muyon-models-4a1534a6.apk)
(434,441,025 bytes; local debug signing).
SHA256: `ab79701c729b5419d8ff97309cf4cfd67f79ca4ebfd7d7e7ac5db9cba5103cc0`.
Test APK SHA256: `86511bec120e94bdffa57740846c9453c44caf9e694eecccfc0db21e8c8b98e4`.
Named APK copies are independent of future Gradle output overwrites.

## Product behavior

- Existing local GGUF, two PP-OCRv5 ONNX files and the correctly decoded dictionary are embedded in the APK. Build-time and private-install hashes are fixed. No runtime download, substitute model or remote embedding fallback.
- Research paper details expose local attachment OCR/indexing. Project semantic search returns matching text with paper, attachment digest and page provenance. Results are local; no agent tool or automatic outbound RAG disclosure is added.
- Indexing reads the committed private attachment through the existing controlled reader, so the selected original URI can be deleted. Drafts/discarded previews are not indexed. Every publication and search validates the current paper revision and attachment digest.
- A separate rebuildable SQLite database stores page chunks and finite, normalized768-dimensional vectors. Multiple attachments coexist. Failed/cancelled replacement rolls back to the previous complete index; explicitly removed papers are excluded without hiding unrelated service/storage failures.
- Inference runs off the UI thread. Cancellation waits for the current native call to finish, then stops further work and publication. Muse conversation controls and Claude typography remain in place.

The initial derived schema correction was made before any device index database existed (`run-as ... ls databases` returned absent). No business database was deleted or migrated.

## Fresh verification

**45/45 required device methods PASS**, zero omitted, duplicate, failed or skipped methods:26 existing methods plus19 new model/index/integration methods. All accepted runs use the same final APK/test APK pair. [Suite](SUITE.json), [hash-bound manifest](SUITE-MANIFEST.json), [40 non-picker methods](NONPICKER.log), [five ordered picker logs](PICKER-GENERATE.log).

The new checks execute actual models, except the explicitly isolated SQLite failure/constraint tests:

- GGUF load,768 finite unit-normalized values, deterministic repeat, query/document prefix distinction, English/Chinese semantic ranking, real-token overflow refusal and recovery, close/reopen.
- Real Chinese/English images,12-degree rotation and Android-rendered scanned PDF recognize `材料`, `123.45` and `678.90`; real blank page, cancellation and session reuse. BGR planes, padding, CTC blank/repetition, shape/NaN refusal, rotated geometry and reading-order threshold chains are checked separately.
- Real business RPC prepare/confirm, PDF upload/confirm, original file deletion, private PDF OCR→embedding→atomic index, SQLite close/reopen and Chinese query `材料的金额是多少` retrieve the correct paper/page and amounts.
- A deliberately stale missing-paper candidate uses a real query vector and real `NotFound` RPC; other valid results remain available. Cross-project/model filtering, multiple attachment digests, invalid vector/text refusal, SQLite failure and cancellation after the first actual chunk write preserve prior data.
- Corrupted installed dictionary is repaired from the fixed bundled bytes. Cancelled installation leaves no partial model published.
- Existing supplier/research/receipt/recovery/lifecycle/UI tests and real PDF/ZIP/directory system pickers pass. The picked original PDF is removed before the separate private-attachment reopen test.

`assembleDebug`, `assembleDebugAndroidTest`, `lintDebug` PASS. Lint reports0 errors,33 warnings and6 hints, not a warning-free claim. [Build](BUILD.log).
Python evidence tests4/4 PASS. [Log](PYTHON.log).
Rust and ML JNI build both API26 ABIs. [Native build](NATIVE-BUILD.log).
All12 packaged native libraries pass ELF and APK16KiB alignment; all6 prepared model/config/dictionary asset hashes pass. [Model package gate](MODEL-PACKAGE.json), [product bridge/native gate](PACKAGE.json).

## Observed resource cost and remaining limits

[Device](DEVICE.json): API26 arm64 emulator,320×640/160dpi,font1.0,4KiB kernel pages. Final process measurements: model load448ms, first short-text inference149ms, warm154ms, reopen452ms. English cosine relevant/unrelated0.8525/0.5345; Chinese0.7889/0.5170. [Scoped timings](EMBEDDING-TIMINGS.log).

Main app RSS maximum sampled during the40-method run:645,608KiB (about630MiB),147 samples. [Memory record](MEMORY.json). This is a sampled emulator result, not an instantaneous guaranteed peak, cold OS-page-cache benchmark or low-memory physical-device acceptance.

Physical devices, x86_64 runtime,16KiB-kernel execution, long-paper stress/quality, arbitrary document orientation and table reconstruction remain unverified. PDFs currently use OCR even when a text layer exists. Index data preserves text/page/source/vector; OCR line quadrilaterals and confidence are returned by the OCR API but not persisted as a document-layout database. No multimodal encoder is included. Limits and model provenance are in the [integration/build contract](../android-local-model-integration.md).

Independent review found and closed four issues: attachment overwrite, removed-paper search failure, stale JNI build identity and non-transitive OCR reading-order sorting. Full product36-scenario acceptance remains PARTIAL/HOLD; this scoped result does not reopen I04 or prove real provider/tool-loop, production pricing, release signing or distribution acceptance.
