# Public service migration: actual entry points and remaining work

Source baseline: F2 `3f1be180bb009a91e659c113ba5b1916e5360332`. This is a source-and-caller inventory, not an installed-device acceptance report. No model, network service, OCR inference or production migration was executed for this inventory.

`PublicServices` means shared host capabilities, including local services. The existing Dart implementation is not an empty shell: `apps/muyon/lib/services/public_services.dart::PublicServices.open` constructs `PaddleOcrService`, `KnowledgeService`, `EmbeddingService` and `TransferService`, opens managed storage, initializes transfer and registers public tools. `apps/muyon/lib/app/bootstrap.dart` connects these services to source invalidation, task coordination, accepted research imports, scopes, tools and the Flutter UI.

| Capability | Existing product entry and implementation | New Rust/Kotlin migration |
|---|---|---|
| W1 files/PDF and knowledge import | `screens/platform_shell_knowledge.dart` calls `knowledge_service.dart::importFile/index/search/delete`; managed file copies, digests, parser freshness and local FTS/BM25 exist. | No real document-store/parser/FTS adapter in the private Service. |
| W6 text search and OCR | `PublicServices.open` injects image/PDF parsers. `paddle_ocr_service.dart::recognizePdf/recognize` uses `pdfrx` and `flutter_onnxruntime`; `ocr_models.dart` gates revision/checksum-verified assets. | No model installer, PDF renderer or inference adapter in the new service. This batch neither changes model choice nor minSDK. Android feasibility research remains separate. |
| Embeddings/vector search | `embedding_service.dart::preview/index/searchVector/search` freezes source text and persists profile/endpoint/model/dimension-bound vectors; `public_tools.dart` registers scoped preview/build/search. | Not wired. Depends on real knowledge identities and the profile/gateway/final-send boundary. |
| Transfer, devices, chat, research tasks | `transfer_service.dart` implements durable initialization, export/import, pairing, sends, chat and task envelopes. `devices_page.dart`, `chat_entry_page.dart`, accepted research imports and bootstrap supply callers. | No equivalent transport/device/task composition in the private Service. |
| W7 resources, profiles and safe storage | Profile repository and settings UI exist. `model_gateway.dart` resolves secrets, applies policy and journals sends. Production Android `MainActivity` provides Keystore-backed secrets through a MethodChannel. | Real product storage/schema/authority/profile/secret adapters are absent. Service-owned root protection is only one dependency, not W7 completion. |
| Agent read and original receipt | Experimental Service/generated controller reaches a trusted built-in Rust registry and durable receipt. `current/lookup` return the original run/receipt summary. | Still synthetic offline composition; `service_runtime.rs::run_builtin_admitted` creates synthetic `source.db`, `BuiltinAuthority`, `BuiltinReview`, `BuiltinEndpoint`, profile `offline-fixture`. No production business-record reads. |
| Memory governance B | Candidate `379b1a6d8d5a5830fb3a74924fd5c41cfb234e1c` contains the isolated SQLite governance crate. | No production application/model/tool-send/Android connection. Single scope/direct source, synthetic indexes and caller clock remain explicit limits. |

## Dependency order and acceptance

W1 real file/PDF source identities and safe managed storage must precede W6 parser/OCR/text-index migration. Vector migration additionally needs frozen text/source versions, model/profile/endpoint/dimension identity and the actual authorized final-send path. W7 supplies safe resource/model/credential storage, schema/restore ordering and the single authoritative policy boundary throughout these paths. None is completed by a lab test total.

A's target remains the already-designed minimal real store -> current authority -> trusted read -> original receipt/current business projection -> UI loop. The current private ABI explicitly excludes answer/projection/sourcefacts payloads; its `current` is the current run record, not current business values. A safe complete loop therefore requires identified real store/authority adapters and a permitted business projection contract. A disconnected receipt observer is only an independent dependency fragment.

B can connect only after the authoritative production ledger and actual sinks are mapped, governed reads are checked at the model-context/final-send boundary, and restore/backup/startup ordering is implemented. A synthetic committed consumption row is not a real external-send fence. Do not introduce a second authority to make the lab appear integrated.

Production acceptance requires entry through the actual App/Service, real supported data and authority, meaningful failure/UNKNOWN cases, stable original receipt identity and current-value checks, and platform/runtime evidence. JVM checks are not ART/Binder/device acceptance. Existing Dart capability source is present; no installed current build or live endpoint was verified here.

Latest parent coordination: the user selected PP-OCRv6. Separate task `01a14d70-8afa-71c1-bea9-a871b2e090ce` owns its platform adapter, Rust result contract and tests on an independent unmerged branch; tiny is the current candidate and minSDK24 stays. This host task does not duplicate that implementation or imply the adapter has landed. Existing source above still describes the old OCR implementation at F2.

There is no selected default embedding model in the product. The user configures an OpenAI-compatible endpoint and `modelId`; `test-embedding` is only a test fixture. No embedding replacement decision was supplied.

I04 remains DENIED_BEFORE_EXECUTION/BLOCKED; its action was not retried, decomposed or routed elsewhere. PR86 and develop integration remain held. This inventory does not authorize a minSDK increase, REMORY implementation or RSI layer.
