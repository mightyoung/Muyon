# Owner handoff / MIG16

## Delivered API

`process_local(host, request, InputKind::Utf8Text, bytes)` verifies current
DocumentHost authority, exact DocumentRef and BlobRef length/SHA-256, extracts
bounded UTF-8 and returns LocalEvidence. Invalid UTF-8/blank/NUL produces a
failed processing receipt. PDF/OCR produces unsupported with no content.
Oversized bytes and access/binding errors return explicit errors, never success.

`receipt()` exposes historical metadata only (no text or approval). `find_literal`
performs bounded direct literal matching without building another index. `open`
returns the exact UTF-8 byte-range excerpt after checking current permission and
source both before and after computation. `answer` validates every reference,
separates selected citations from remaining candidates and leaves support
unassessed. It accepts caller-authored body text; it does not generate/verify claims.

Wire structures are serde Serialize: SourceVersion, ProcessingReceipt, EvidenceRef,
Citation, AnswerEvidence. Schemas are explicitly v1. Processing identity hashes
canonical tuple (processor, source_id, input_kind); source_id includes complete
core scope/document/revision/format/blob, evidence_id includes exact byte range
and quote digest. Changing v1 identity encoding requires a new processor/schema.
No body markup is parsed as an action or approval.

## Core owner action requested (not performed)

1. Add `pub mod evidence;` in crates/muyon-core/src/lib.rs.
2. Add shared Text format under documents owner review. Until then explicit
   Utf8Text accepts DocumentFormat::Unknown only. Do NOT automatically treat
   unknown documents as supported text or enable a general capability matrix.
3. Provide a trusted DocumentHost adapter over existing BusinessStore document
   grant/current-revision/lease state. Existing read_document enforces Inspect;
   it alone is insufficient for derived ReadText access. Do not treat metadata
   presence or a model-provided permission list as permission to read text.

No lib.rs or documents/ file was edited. The integration test uses #[path] to
compile the real module with aliases to the existing public core contracts.

## Host / Android owner integration requested (not performed)

Reuse controlled blob readers for bytes, DocumentHost for current scope/membership,
revision, grant generation/epoch and lease; serialize each synchronous use against
revocation under the owner transaction/lock. This module is a pure processor,
not an authority or substitute transaction. For future async/IPC, bytes and results
must be delivered in the same trusted owner boundary; two pure checks cannot
create atomicity around an arbitrary external host implementation.

Store processing receipts under existing import/task/intent ownership. Connect
selection and actual committed save receipts separately. `index=not_run` stays
until ResearchIndex owner reports real publish/contains/current-source evidence.
It must not be turned green just because extraction or literal matching succeeds.
Existing Unknown operations require lookup of their original intent; this module
has no retry, cancellation, refund, fee, reservation or durable commit API.

For PDF pages, reuse the existing document-core DocumentAnchor/PdfAnchor once the
trusted runtime supplies real extraction + resolved geometry and source bytes.
This task does not manufacture PDF pages, geometry, OCR or parsed PDF content.
UTF-8 EvidenceRef.page_index_zero_based is always null and non-null is rejected.

Android shell owner remains sole MainActivity/ChatScreen owner; host owner remains
sole ProductService/ProductChatRuntime owner. No UI or service integration files
were modified and no production readiness/HOLD release is implied.

## Run offline tests

```
PATH=/tmp/evidence-rust/toolchain/bin:$PATH \
CARGO_HOME=/tmp/evidence-cargo LIBRARY_PATH=/tmp/evidence-link \
cargo test --locked --offline --manifest-path crates/Cargo.toml \
  -p muyon-core --test evidence_local
```

`/tmp` paths are disposable session tooling, not portable dependencies. Rust
1.93.1 is the version already specified by muyon-product CI. Official component
hashes were verified before isolated installation. LIBRARY_PATH points at a
local symlink to already-installed system libsqlite3.so.0; no sqlite install,
repository dependency version change or security permission expansion occurred.
