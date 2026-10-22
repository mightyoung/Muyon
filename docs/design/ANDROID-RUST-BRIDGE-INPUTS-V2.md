# Current Android minimum API packaging contract (V2)

The user approved Android 8.0 / API 26 on 2026-10-18. This supersedes the
minimum-API portion of the earlier API 24 design and plans for new builds.
The shipping Flutter app and the independent Compose lab now explicitly set
minSdk 26. compileSdk/targetSdk declarations, permissions and credentials are unchanged.

`ANDROID-RUST-BRIDGE-INPUTS-V2.schema.json` is the current strict packaging
schema: format_version=2, min_api=26. Protocol=1, namespace, field shape and
all source/library/binding/JNA hash requirements remain unchanged. The shared
verifier pins this schema's hash. V1/schema/API 24 evidence is retained unchanged
as history, and is rejected as input to new V2 builds. No old API 24 or API 26
binary or CI run supplies evidence for a new source SHA.

Fresh Rust producers link with the API 26 NDK clang wrapper, require the API 26
ELF note and resolve strong imports against exact API 26 stubs. Dependency ELF
notes may declare an older compatible API up to 26. Package aggregation requires
exact source SHA, V2 inputs and APK minSdk 26; the lab target remains 36.

`.github/workflows/android-min26.yml` builds the complete shipping Flutter APK,
compiles/lints the separate lab without optional native inputs, and freshly
cross-links both native ABIs. It does not run the blocked I04 action or any
Service/process/reopen regression. APK assembly and ELF checks do not establish
installed-device, Android 8 runtime, real store migration, UI/Service wiring,
OCR integration or 16 KiB runtime acceptance. The shipping app currently uses
its existing Dart services; the receipt observer remains default-disabled.

Dated API 24 plans and original evidence remain accurate historical records.
Use this document and V2 for current build requirements. Old guarded callback
handling may remain; raising the floor does not require deleting safe fallbacks.
