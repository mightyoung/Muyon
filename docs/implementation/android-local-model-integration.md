# Android local research models

Implementation plan, 2026-10-21. Existing Muse UI and business schema 2 remain in use.

1. Bundle the existing, hash-verified GGUF and PP-OCRv5 models through an external build asset directory. Verify bytes again before atomic installation into app-private storage. No model downloads or provider calls at runtime.
2. Pin llama.cpp b11763 and ONNX Runtime Android 1.23.0. Build API26 CPU inference for arm64-v8a and x86_64 with 16KiB native alignment. Use the 768-dimensional projected embedding output and official retrieval task prefixes.
3. Port existing Paddle preprocessing, contour geometry, perspective crop and CTC decoding. Preserve line quadrilaterals and confidence. Process committed private PDF attachments, not discarded previews or original SAF paths.
4. Publish page chunks and normalized vectors atomically into a separate rebuildable SQLite index. Bind results to current project, paper revision, attachment digest and model identity. Revalidate before publication and every search; exclude stale and cross-project results.
5. Offer local indexing and semantic search in the research page. Run CPU work off the UI thread; cancellation prevents publication. Local results do not authorize disclosure to a remote agent.

Verification requires real API26 loading, Chinese/English/amount/rotated OCR, finite 768-dimensional inference, committed PDF -> index -> reopen -> correct paper/page search, and missing/corrupt model, invalid vector, stale source, cancellation and project isolation checks. Report cold/warm time and memory, APK hashes and ABI/alignment separately from runtime evidence. [Completed scoped verification](android-local-models-20261021/README.md) records45/45 device methods and the model-inclusive APK. Full product acceptance and the previously denied I04 experiment are outside this work.

## Build inputs

`python3 apps/muyon_android/prepare-model-assets.py ORIGINAL_REPO /private/tmp/muyon-model-assets --fetch-notices` verifies the existing local weights, decodes the full YAML dictionary with PyYAML, and prepares model/license assets outside Git. Notice downloads are explicit build-time operations, verified by frozen hashes. Subsequent runs work offline with these artifacts. The supplied GGUF records architecture and license metadata but not its converter/source revision; that provenance limit is recorded in the APK notice.

Set `ANDROID_HOME`, `MUYON_NATIVE_OUTPUT`, `MUYON_ML_OUTPUT` and `MUYON_LLAMA_ARCHIVE` (verified archive), then run `apps/muyon_android/build-native.sh`. It builds Rust and forces the pinned ML JNI rebuild before copying either ABI. Set `MUYON_ML_FETCH=1` only to fetch the fixed archive if absent. Gradle receives `muyonProductNativeInputs`, `muyonModelAssets` and the exact generated `muyonSource` build ID. Assets and native bytes are checked before packaging; do not commit model weights.

Model sessions serialize use and release off the UI thread. A cancellation waits for the current native inference to return, then prevents further pages/chunks and transaction publication. A cancellation arriving after commit reports the completed result. Derived results remain local UI data, without a new agent tool or automatic remote RAG disclosure. PDF pages currently use OCR, including PDFs with a text layer; text-layer extraction and multimodal embedding are not implemented.

The index stores text, vector, page and source/model identity; line confidence and quadrilaterals are available from OCR but are not persisted as a layout database. It supports up to200 pages,3200 chunks and192 code points per model chunk. Final native tokenizer bounds still apply and fail explicitly. Search uses exact cosine over the bounded private index, revalidating each distinct source from the business service. The unshipped initial derived schema was revised before any device index database existed; the authoritative business schema remains2.
