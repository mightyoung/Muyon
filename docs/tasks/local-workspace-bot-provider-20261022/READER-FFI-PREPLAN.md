# Reader / StoreEvidence inspection checkpoint — deferred behind draft recovery

Read shell74a39791774f85514a03b0a578ecff788e048130 READER-WIRING-REQUEST.md;
coreaec085fafef8aa02f86f2fc60626f168b10f4caa history/Text source;
evidence78cdff32dee68b664c4fe71b4bbd6b81251af5e7 HANDOFF/store.rs.
No Service/Runtime/documents/core lib.rs edits or dependency merges made here.

Real hooks: read_document validates persisted Inspect grant; document reader blob
open/chunk/close exists. StoreEvidence::process/find_literal/open/answer is concrete,
rechecks ReadText/head/project/generation/epoch/grant and real bytes under owner
transaction; processing projection is serializable, index remains NotRun. Text only;
PDF/OCR unsupported. No parser saved/import success or fabricated citation.

Important boundary: BusinessStore.database(), document_access_in_transaction and
historical policy hooks are crate-private, so the FFI crate cannot directly invoke
those atomic checks. Inspect read_document + later read_blob_chunk is insufficient
atomic ReadText/render authorization and must not be presented as completed reader
bridge. Need a minimal core-owner public controlled read-session wrapper or explicit
source-owned adapter export; do not widen DB visibility. No list/read-session hook
may auto-issue grants from caller JSON. Existing Research attachment lacks exact
DocumentAccess/epoch/idle invalidation. Host PFD and idle invalidation remain host work.

Proposed public facade directions: authorized metadata resolution/list selection;
open exact source read session; bounded chunk reads with use-time and delivery-tail
authority/version checks; is_current; close. Service derives real access from its
policy and passes only typed references; no arbitrary path/model authority. Evidence
process/query/citation projection via existing StoreEvidence, bounded live session IDs.
Precise signatures must be frozen with core+host before implementation. Annotation
write unavailable without original intent/reconciliation journal; never fake save.
Parent priority now durable Bot save preparation; this reader checkpoint is NOT_RUN,
not a delivered PFD, engine, document authority or working product entrypoint.
