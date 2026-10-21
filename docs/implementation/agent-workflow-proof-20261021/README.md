# Agent workflow integration verification · 2026-10-21

This record covers the Rust workflow backend, Android Service integration and Compose task/skill/activity presentation. It supplements the [implementation contract](../agent-workflow-and-conversation-20261021.md) and [offline OCR/embedding verification](../android-local-models-20261021/README.md).

## Delivered behavior

- Root/child tasks persist in a private SQLite ledger, with scoped authority, ordered activity, bounded concurrency/depth, restart recovery and cascading cancellation. Current limits are depth1, two active and eight total children per root.
- Two bundled skills load metadata before instructions and use the existing scoped business-read tools. Disabling a skill prevents creation and execution. The same underlying business services remain authoritative.
- AI children prepare distinct conversations through the existing request owner, budget and actual-field confirmation path. Tool catalogs are restricted to the selected skill. Followup chains retain original identity; unresolved requests cannot be bypassed through a new root or ordinary chat.
- Task/skill management stays under the conversation menu. The normal execution strip is collapsed. Expanded local results show record names and source; raw JSON is a second disclosure. Task selection uses a compact dropdown.
- Replies support selectable text, headings, lists, quotations, inline emphasis/code, fenced code with exact copy, horizontally scrollable tables and validated HTTP(S) links. Only observed execution facts are presented.

## Verification

The accepted APK pair, source/build identities, SHA256 values and all required device methods are recorded in `suite-manifest.json`; `suite-gate.json` checks that every source test method passed exactly once with no skips, omissions or duplicate selectors. Logs are content-gated: adb exit zero alone is insufficient.

Final source: `79dca05ba6ff84dbc8a60d0838951aec6720227a`. APK: `/private/tmp/muyon-workflows-79dca05b.apk`, SHA256 `4007f227f0cb17c3bba0b7ef5c7115ed7901efd24883390354d5c07198a23720`. `candidate.json` records the complete pair and screenshots; `installed-identity.json` independently checks device-installed bytes. Device acceptance: **54/54 PASS**. Android lint: **0 errors,33 warnings,6 hints**; this is not a warning-free lint claim. The archived runner is the host-specific invocation used for this candidate.

Rust verification passed143 tests across16 suites, including13 workflow tests and real owner/tool-chain fixtures. Strict Clippy passed with warnings denied. Four Python gate regression tests passed. The Android candidate was built with `assembleDebug assembleDebugAndroidTest lintDebug`; the final build and package reports are retained beside this record.

Device verification uses API26 arm64 emulator `emulator-5556`, 320×640, font scale1.0, a4KiB kernel and retained private app data. Forty-nine non-picker methods and five ordered real system-picker methods cover the new workflow/rich-text behavior and previous business, lifecycle, OCR, embedding, PDF/ZIP/directory import and private-attachment recovery behavior. The selected original fixture PDF is removed before independently reopening its private copy. Test fixtures are generated local records, not production data.

The screenshot pair in `screens/` comes from the real Activity→Binder→Rust test. It shows expanded completed local-task results and the collapsed conversation. Package checks compare generated bridge bytes and product-library hashes, all bundled model hashes/notices, both ABIs and16KiB ELF/APK alignment for all12 native libraries. Static alignment does not prove execution on a16KiB kernel.

## Failed candidates and review

The initial device run exposed a real UI adapter bug: successful `error:null` envelopes were rejected. It was corrected without weakening assertions. A second run exposed a fixture pagination mismatch with the existing Service page limit; the fixture now paginates by10. Original rejected logs and candidate hashes remain in `diagnostics/`; neither run is included as accepted evidence.

The Rust/Service review closed followup-chain tracking, unresolved-child bypass, missing-price-proof status and duplicate observation event issues. A separate final UI review approved the compact task/result change. An initially reported newline-escaping issue was withdrawn after checking source bytes; it was a review interpretation error, not an additional code change.

## Explicit boundaries

This is a local source/build/device result, with no push, merge, release signing or distribution acceptance. The original `develop` checkout's two macOS xcconfig edits and user model files were preserved.

Remote AI requests remain blocked when production pricing proof is missing. No provider credentials or paid calls were used. Model-selected automatic delegation, live parallel AI inference and parent synthesis are not accepted by this test record. The current provider still uses `stream:false` and `thinking:disabled`; this work does not claim provider reasoning-summary integration or expose private reasoning. Public ChatGPT/Codex/Claude references informed the design; their private backend code was not available. No new SDK dependency was introduced.

I04 remains closed; the overall36-scenario product acceptance remains PARTIAL/HOLD. Physical-device, x86 runtime,16KiB-kernel and live-provider acceptance remain separate.
