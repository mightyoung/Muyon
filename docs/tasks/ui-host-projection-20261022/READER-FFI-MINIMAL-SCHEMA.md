# Read-only document FFI request v1 — coordination contract, not a released API

Supersedes the loose endpoint sketch in READER-HOST-BRIDGE-REQUEST.md for the
sole FFI owner. No Rust/lib.rs change is made here. Please release exact accepted
signatures/schema/SHA before Kotlin calls them. Annotation mutation excluded.

Read actual StoreEvidence HANDOFF at78cdff32dee68b664c4fe71b4bbd6b81251af5e7:
its real ReadText transaction + controlled reader + digest + tail-authority check
is the applicable byte pattern. Inspect is insufficient. Its Text processing is
not proof of a PDF renderer or Office engine, and its cached projection is not a
new byte-delivery grant. Keep one shared core truth and actual byte lease.

## Minimal private ProductCore methods requested

```
document_list(project: Option<String>, limit: u32) -> Result<String, ProductError>
document_read_open(service_session: String, project: Option<String>,
                   document_ref_json: String, purpose: String) -> Result<String, ProductError>
document_read_check(service_session: String, read_session_id: String) -> Result<String, ProductError>
document_read_chunk(service_session: String, read_session_id: String,
                    max_bytes: u32) -> Result<Vec<u8>, ProductError>
document_read_close(service_session: String, read_session_id: String) -> Result<(), ProductError>
```

Service session is the actual private Binder client registry entry, checked by
Service before native dispatch. Selected project comes from current host scope;
DocumentRef must match it. No model/URI/path/actor/grant JSON input. Purpose is a
finite host-selected `read_text` or `render`, requiring that exact persisted
operation, never inferred from a format enum or replaced by Inspect.

All JSON uses existing ProductCore encode envelope; shapes below are **data**.
Reject unknown schema/keys/types and oversized input, never default active=true.
DocumentRef is EXACT core serde JSON (nested scope with workspace_id/project_id,
document_id, revision, format). Revision uses existing canonical unsigned decimal
string up to18446744073709551615, never JSON number/Double/Kotlin Long. Preserve
canonical annotation JSON unchanged; Reader SharedDocumentJson does conversion.

list data:
```
{schema:1, status:"listed", documents:[DocumentMetadata...], truncated:Boolean}
```
limit1..32; only live current project/workspace/registered heads visible under
actual trusted host policy. Actual empty store returns empty array. No guessed
paper/title/digest identity, cache import, synthetic revision or automatic grant.
DocumentMetadata is existing core serialization, not a second handwritten model.

open data:
```
{schema:1, status:"opened", read_session_id:String,
 document:DocumentMetadata, annotations:[Annotation...],
 byte_length:String, sha256:String, expires_at_ms:String,
 purpose:"read_text"|"render", annotation_editing:false}
```
IDs opaque native-generated, bounded128; byte_length decimal String0..16777216
(16MiB maximum); sha256 lowercase64hex of actual blob. expires_at_ms canonical
unsigned decimal string from real authority, no invented deadline (if authority
has no expiry, explicit null instead; native owner must document that choice).
Do not expose grant key or reusable permission token. Native read-session table
privately binds actual DocumentAccess, immutable metadata/blob, exact service
session, selected operation, real grant generation/epoch/expiry and controlled
reader. Source format/actual-byte mismatch or inadmissible bytes is an error.
Host engine support remains separately gated; format membership alone is not it.

check data:
```
{schema:1, status:"current", read_session_id:String,
 document:DocumentRef, expires_at_ms:String|null}
```
Any revoke/expiry/head/project/source/grant-generation mismatch gives a stable
sanitized invalidation error and closes that session. No `current` result may
reuse a cached bool. Native owner must document the error allowlist.

chunk returns typed bytes (UniFFI ByteArray), sequential cursor,1..65536 maximum.
Empty means actual EOF. Check live DocumentAccess/current immutable source before
read and under final guarded transaction again before bytes leave; the preliminary
open check is insufficient. A thrown read closes session and discards bytes.
Whole stream exact byte count + sha256 checked again by Android before PFD delivery;
extra/missing bytes fail. Reuse controlled source safety, no raw file path escape.
Close is exact-owner only, repeat close may succeed without revealing other leases.
Service release/scope change also closes all exact-owner native sessions.

## Authority policy that native owner must explicitly settle

Which existing persisted host binding grants this private user's requested
read_text/render operation? Do not accept authority bool/unchecked grant ID from
Kotlin JSON, issue blanket new permissions, or use latest matching grant. If no
existing production host principal maps to a current persisted DocumentAccess,
report the precise missing issuer/join; new ordinary local registry development
is authorized, but it must represent real explicit local selection and persisted
operation, not infer old authority. This is the dependency to coordinate with
canonical document owner, not a reason to implement a duplicate document store.

## Kotlin/Android consumption and remaining owner boundaries

Exclusive new files remain product/documents/host/{DocumentHostLease,
DocumentDescriptorBroker,ProductDocumentHost}.kt and
product/agentipc/ProductDocumentClient.kt plus dedicated tests. Runtime/Service
remain this thread's sole production ownership. Shell/reader source not edited.

Private typed Messenger Bundle carries READ_ONLY seekable PFD, not JSON/base64
file bytes to UI. Opaque content URI is host-owned metadata only. New artifact
is built from authorized native bytes, bounded/digest-verified, fresh final check,
read-only open and unlink; no cache attachment granted retroactively. Late or
foreign ref/epoch/session PFD replies close immediately. Native checks are needed
at open, pre/post parse, before delivery and on bounded idle polling/expiry;
publish accessActive=false and close/drop output when invalidated. Do not claim
arbitrary already-delivered bytes can be erased remotely.

Reader owner must release explicit read-only editing gate before factory connects;
real annotations remain displayed, save controls disabled. Original annotation
intent/receipt journal + immutable old anchor CAS is a separate canonical owner
transaction task, never a fake Saved callback to save_annotation_trusted.
Android/FD/renderer acceptance remains NOT_RUN until actual toolchain availability.
