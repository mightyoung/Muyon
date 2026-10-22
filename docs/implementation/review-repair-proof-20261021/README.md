# Dot review repair verification · 2026-10-21

Review baseline: `30c033cd8542f566d40e9248bcc498e7efce7fc6`. This record addresses the nine Important findings supplied by the user. It is not whole-branch approval, a merge decision or release acceptance.

## Fixed batches

| Batch | Fixed source commit | Behavior and regression |
| --- | --- | --- |
| 1 · business recovery | `2952ec33` | Durable review lifecycle distinguishes unsubmitted previews from accepted/legacy unknown. Lookup atomically seals an unclaimed preview; late confirmation is refused. Supplier, research and chat recovery only release their local marker for this trusted result. Existing unknown requests are never cleared/replayed. New sidecar initialization survives empty-file and uncommitted-DDL interruption without resetting accepted records. |
| 2 · chat and OCR | `faba4d73` | Mounted conversation/project generations reject late previews; current Service memory configuration is queried on return. OCR corners preserve long-text direction and vertical normalization. Positive/negative inclination,24 corner permutations and four-color corner identity are checked. Exact outgoing payload/endpoint disclosure UI is included. |
| 3 · outbound authority | `bb8b8a56` | Rechecks unresolved requests at confirmation, claim and final write permission; all task roots and normal chat share the fence. Skill revocation covers existing plans and host-created followup chains, including other sessions in the same conversation/project, while preserving other conversations. The write gate/native plan is revoked before durable skill mutation. Plan preview includes the exact persisted body, automatic history, tools and endpoint. |
| 4 · CI/resources | `9c1fb4a9` | Actual product CI definition, Linux/macOS NDK tool selection, fixed model-input validation and resource provenance. Extracted Claude fonts removed; platform sans/serif used. Five extracted WorkBuddy vector paths replaced with original basic geometry. CI execution/configuration status is recorded separately below and in the repair ledger. |

The later merge of remote `94431082` preserves the separately authored Claude report; that merge changes only a document. It does not change the APK's source identity.

## Final local candidate

- Source: `9c1fb4a9e8aa0b85f1c896938278085ee8cdc0ad`.
- Build: `9c1fb4a9e8aa0b85f1c896938278085ee8cdc0ad:707dff5340d754c9f5e4d0c71f856a16957eb4d08d1ae63da4accbe4bdff6079`.
- APK: `/private/tmp/muyon-workflows-9c1fb4a9.apk`; SHA256 `7a2958a06da0093c20e15c49c757645d72cd72edf101a62fdaae64e691f91bdd`.
- Test APK and device-installed digests are independently recorded in `candidate.json`; both match the candidate files.
- Rust: **157 executions across16 test suites PASS**; strict all-targets Clippy PASS. These are executions, not a claim of157 independent acceptance scenarios.
- Python checker regressions: **7/7 PASS**.
- Android assemble app/test + lint: PASS; lint **0 errors,33 warnings,6 hints**.
- Two-ABI product/model package gates: PASS, including generated bridge byte comparison, model bytes/notices and12 native libraries' ELF/APK16KiB alignment. No public FFI signature changed in this repair.
- Device: API26 arm64,320×640, font scale1.0,4KiB kernel, original private app data retained. **63/63 methods PASS**:58 non-picker plus5 ordered real system-picker methods. `suite-gate.json` proves complete source inventory, no skips/duplicates/omissions and one APK pair.

The added device methods exercise real Service/Rust unsubmitted-review recovery for both research and suppliers, configuration restoration on tab return, conversation callback generation, full outgoing-history disclosure, OCR direction and actual serialized Runtime cross-session skill revocation. Existing OCR/embedding, import, attachment-reopen, business and lifecycle methods remain included. Fixture credentials and proof objects do not permit real provider traffic.

## Negative evidence and independent review

- `recovery-RED.log`: restart between local confirmation intent and core acceptance returned permanent unknown on the reviewed source; `recovery-GREEN.log` includes the corrected lifecycle regressions.
- `review-init-RED.log` / `review-init-GREEN.log`: empty sidecar and initialization-transaction interruption initially failed, then passed; committed accepted state and invalid schemas are preserved/refused respectively.
- `authority-RED.log`: two actual regression assertions fail on a fixed baseline snapshot—preprepared plan wrongly confirms after another unknown, and automatic history is missing from preview. `authority-GREEN.log` proves the fix; the complete Rust log includes the additional cross-root and skill-revocation tests.
- `ocr-RED-device.log`: old OCR geometry fails the new compatible detector-axis assertion on the real API26 emulator. The diagnostic APK deliberately retained old native identity and is not delivery evidence. Final source is restored and all three geometry methods pass in the sealed63-method candidate. This is a geometric/pixel regression, not a claim of new real-world OCR benchmark accuracy.
- Independent safety review found and closed the sidecar initialization window, cross-session final-write revocation race and cross-conversation over-cancellation. Its final approval is limited to those static repair slices; final build/device evidence is separately recorded here.

## Open gates

The new Android CI needs a reviewed model source at `MUYON_MODEL_INPUT_URL`. Existing local GGUF identity alone does not establish the upstream model/conversion license chain. No guessed URL, substitute weights, skip or fake green is used. See [CI/resource remediation](../../reviews/2026-10-21-product-ci-and-resource-remediation.md). The repository Actions run, including workflow validation fix `6fa48732`, is tracked in the [repair ledger](../../tasks/muyon-android-refactor/REVIEW-REPAIR-20261021.md); local tests are not represented as remote CI success.

The concurrently pushed [Claude report](../../reviews/2026-10-21-claude-android-refactor-report.md) contains further findings beyond the user's nine-item Dot repair request (including completed/cancelled workflow ordering, complete-response settlement after cancellation, production attachment maintenance, agent instruction behavior and broader evidence/usability items). Those are not silently declared closed by this scoped record. The integration Draft must retain them for separate disposition/review.

Overall36-scenario acceptance remains **PARTIAL/HOLD**. No merge into develop, live provider/model/search call, credential extraction, I04 retry, unknown replay or public distribution was performed. Physical device, x86 runtime,16KiB kernel and paid-provider acceptance remain separate. Earlier APKs and Git history still contain the previously extracted resources; replacing current assets does not license old artifacts for public redistribution.
