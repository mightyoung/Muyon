# OCR v6 migration slice — 2026-10-18

User decision: PP-OCRv6; default implementation assumption tiny, small comparison
candidate. This task does not change embedding. Immutable product base F2
`3f1be180bb009a91e659c113ba5b1916e5360332`; sole integration owner remains LeaderB.
Branch `feat/ocr-v6-adapter`; no develop/main merge or deployment authorization.

Owned implementation: [ocr-v6-adapter](../../experiments/redesign/ocr-v6-adapter/README.md).
All changes stay there and this task note. App host, Service and old Dart OCR are
untouched. Old [v5 decision](../implementation/paddleocr-platform-decision.md) is
historical regression evidence, superseded for the new Rust/Kotlin OCR selection;
no silent v5 fallback is implemented.

Read contracts: redesign v1.3 W1/W6/W7 and product F2 Android/Rust Service handoff
`3de330189ed4d94247e215c03bfad7c6de87931b:docs/tasks/LEADERB-HANDOFF-20261018-BATCH4.md`.
I04 remains unrelated and was not retried. No new Android SDK license accepted.

| Workstream | This independent delivery | Required next owner seam |
|---|---|---|
| W1 document/PDF | Rust DocumentRef snapshot, physical page, digests, normalized raster geometry and homography validation | Actual file grant/current revision, PDF rasterizer+version, PNG byte digest and transform provenance |
| W6 OCR | Rust task validation and commit port; Kotlin det/rec runtime adapter using pinned upstream preprocessing; controlled errors and lifetime tests | Private Service worker call, actual extraction store transaction, cross-language task cancellation/clock mapping |
| W6 retrieval | Extraction explicitly separate from indexing; model/algorithm lineage retained | Rust index job with current source/policy projection; no embedding change |
| W7 capability | API24/25 unsupported before native factory, missing/corrupt model errors, CPU-only fixed identity | Model installation settings, immutable verified packaging, storage/resource budget and actual platform capability registration |

Stop gate: isolated source/test slice is deliverable; **production OCR migration
is not complete**. Official SDK minSdk26 cannot be directly included in min24 App.
Native Maven OpenCV4.5.3 has4KiB LOAD alignment on arm64/x86_64; this blocks a16KiB
release. Source/dependency minSDK evidence, .so hashes and exact required follow-up
are in the module README/native audit. Do not raise minSdk or use overrideLibrary.

Desktop real ONNX tiny/small det+rec ran twice on five synthetic images each.
Both recognize these samples; tiny removes Chinese-line spaces, small preserves
them. Frozen dictionaries have6906/18710 classes. No general accuracy/language or
Android inference/performance/memory/thermal claim follows. Old Dart v5 source
and all fixed assets remain unchanged; original v5 tests were not executed here.

Handoff includes source/model locks, licenses, shared Rust/Kotlin JSON fixtures,
raw RED/GREEN logs, desktop tensor/geometry results and ABI/ELF audit. Review and
sealed commit identities are appended after independent review; LeaderB decides
integration only after the remaining gates, without treating mock/desktop results
as an App or device pass.

Independent review of `8684e1ca` reran Rust9/Kotlin14/Python3 successfully.
It identified inherited OpenCV temporary-Mat exception cleanup gaps (QuadTextCrop
and DetPreprocessor), which remain an explicit App integration blocker. A second
finding, native LinkageError escaping the controlled envelope, was reproduced by
a new failing test and mapped to INFERENCE_FAILED; its follow-up verification is
recorded with the sealed candidate in module evidence.
