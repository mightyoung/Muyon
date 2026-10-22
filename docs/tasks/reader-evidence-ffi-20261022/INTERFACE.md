# Controlled document/evidence FFI — raw/evidence protocol

Fixed deps: provider7bb89a713c0ce5678a8c4cae7fc5e24612d88362;
reader presentation report3ff95947337c85f15ef1f9edcf5d47ad49e14999/sourceee184fc1dd90faf2c3cdd48d735f47274de6d418, purefmtdfa63451c0d65417b425f5bf1e92a3b43e0b6052;
evidence78cdff32dee68b664c4fe71b4bbd6b81251af5e7. Ordinary dependency merges on
isolated task/reader-evidence-ffi-20261022. Owned changes ONLY FFI/lib.rs, new
FFI document_bridge.rs/tests and task docs. No core/lib.rs, documents, Service,
Runtime, shell or generated binding edits. Existing five draft signatures retained.

## Real authority input; unresolved production join is not invented

Private trusted Service must resolve its actual client/session/generation/selected
project and an ALREADY ISSUED persistent DocumentAccess grant reference. It must
not forward model/UI JSON as authority. No native issuer endpoint, grant scan,
latest-grant lookup, caller account/workspace/owner epoch, arbitrary URI/path or
permission boolean exists. These typed grant IDs/generations are references only:
core checks exact persisted source, operation, project/head, active state, generation,
current owner epoch and expiry. Owner epoch/workspace derive from the actual opened
store. An arbitrary or stale grant reference fails; nothing issues new permission.

Host9d2 has no demonstrated production document principal->grant/DocumentRef join.
Therefore real Host navigation remains unavailable until its policy owner supplies
that join. Synthetic tests use actually issued grants and actual temporary source
bytes, not a mock true authority. This adapter does not fabricate historical ownership.

## Native typed records and methods

All new records derive UniFFI Record; enums derive UniFFI Enum. Fields:

- DocumentReaderScope: service_session:String, generation:String, project:Option<String>.
  Actual live host scope lease; never persisted owner identity. Host validates current
  values before EVERY call. Native session binds all three exactly.
- DocumentAccessRequest: scope:DocumentReaderScope, document_ref_json:String,
  grant_id:String, grant_generation:String. Strict exact core DocumentRef JSON<=8192.
  No grant JSON/permission list; generation is canonical unsigned decimal string.
- DocumentReadUseRequest: scope:DocumentReaderScope, read_session_id:String.
- DocumentReadChunkResult: offset:String, bytes:Vec<u8>/ByteArray, eof:Boolean,
  session_active:Boolean. Successful EOF means session_active=false under current core.
- DocumentReadOperation enum: ReadText|Render, finite actual persisted operation.
- DocumentEvidenceKind enum: Utf8Text|Pdf|Ocr (unsupported remains unsupported).
- DocumentEvidenceUseRequest: scope:DocumentReaderScope, processing_id:String.
- DocumentEvidenceAnswerRequest: context:DocumentEvidenceUseRequest, query_id:String,
  body:String, cited_indices:Vec<u32>. Explicit selection only, never body-markup parsing.

Private ProductCore methods, all fallible with sanitized ProductError:

```
document_metadata(request: DocumentAccessRequest) -> String
document_annotations(request: DocumentAccessRequest) -> String
document_read_open(request: DocumentAccessRequest, purpose: DocumentReadOperation) -> String
document_read_check(request: DocumentReadUseRequest) -> String
document_read_chunk(request: DocumentReadUseRequest, max_bytes: u32) -> DocumentReadChunkResult
document_read_close(request: DocumentReadUseRequest) -> ()
document_read_release_owner(service_session: String) -> ()
document_read_shutdown() -> ()
document_evidence_process(request: DocumentAccessRequest, kind: DocumentEvidenceKind) -> String
document_evidence_query(context: DocumentEvidenceUseRequest, query: String, limit: u32) -> String
document_evidence_quote(context: DocumentEvidenceUseRequest, query_id: String, evidence_id: String) -> String
document_evidence_answer(request: DocumentEvidenceAnswerRequest) -> String
document_evidence_close(context: DocumentEvidenceUseRequest) -> ()
```

No project-wide list endpoint is fabricated: core explicitly has no authorized
project document enumeration API. metadata is exact known-reference Inspect;
annotations is actual core ReadText listing, canonical JSON unchanged, read-only.
Its final delivery gate requires a source<=2,000,000 bytes; larger sources fail
DOCUMENT_LIMIT rather than returning empty annotations.

metadata JSON schema1/status=inspected/document=actual DocumentMetadata,
annotation_editing=false, safety_status=not_assessed. Annotation JSON schema1/
status=listed/annotations=actual records/annotation_editing=false. Oversize output
fails, never silently returns an empty list or truncates annotations.

open JSON schema1/status=opened/read_session_id=opaque bridge ID/document=actual
metadata/purpose=read_text|render/byte_length=decimal string/sha256=actual digest,
expires_at_ms=null/expiry_status=enforced_by_core_not_exposed,
annotation_editing=false/safety_status=not_assessed/display_lease=false.
Null expiry explicitly means NOT exposed, not infinite/no expiry. Native does not
invent a deadline; core enforces actual grant and monotonic session limits.
Native cap8 sessions,<=16MiB source (an admission bound, NOT a completion promise),
chunks1..65536. Source identity is exact; no latest/historical substitution.

check returns schema1/status=current with exact reference only after real core
check, or schema1/status=invalidated (closed/expired/not-current). Cleanup errors
return failure, preserve cleanup retry and block success; no cached true. Scope or
owner mismatch fails without closing another live owner's session. release_owner
closes matching service owner only and also clears its evidence entries.
shutdown is trusted Service lifecycle only, never an ordinary client route: it
permanently stops all document/evidence outputs and explicitly closes core leases.
Cleanup failures withhold success and require owner restart/real reconciliation.
At full admission capacity only, at most8 real core checks remove stale bridge IDs.
Explicit check hashes the whole source; chunk never calls it redundantly.

## Evidence is real local processing, not saved/indexed/claimed support

process calls the existing concrete StoreEvidence adapter on the same BusinessStore.
Returns schema1/status=processed/processing_id/actual stored-processing projection.
Maximum4 ephemeral processing entries,15s idle/30s absolute; no authority cache.
Each query/quote/answer calls StoreEvidence again, revalidating actual bytes/grant/
exact source. Before publishing an encoded owned projection, a separate public
with_document_source gate compares the exact processing metadata and rechecks
committed cleanup authority. Its callback has no nested transaction or delivery.
The <=2M gate rereads/hashes a bounded source; it is not used on raw chunks. The
15s idle/30s absolute processing lifetime is checked again after that work, before
touch/reinsertion, so slow work cannot renew an already expired entry.
Query returns a fresh explicit query_id + canonical hits (limit1..32,
query<=4096); quote/answer require that exact query_id, not latest substitution.
Only cached native EvidenceRefs are accepted; no caller-authored reference JSON.
Answer takes explicit indices into that query, returns core's AnswerEvidence,
body<=65536, no automatic [1] citation or saved/index flag. Canonical Text byte
anchors/quote digest retained; no inferred PDF page. Pdf/Ocr remain Unsupported.
JSON output<=262144 bytes; unsupported/error never becomes available or saved.

## Raw mode limits

Additive presentation ticket/open-selection fencing and retained EOF are defined
in PRESENTATION-FFI-INTERFACE.md. They fulfill the original core follow-up below;
this raw API deliberately retains its original transport EOF-close behavior.

The original ff3 cleanup vulnerabilities and independent RED are preserved in the
merged core report. This source uses the corrected tail+snapshot dependency above;
parent independent execution/acceptance remains separate. Snapshot64MiB is the
aggregate payload budget, not total RSS. Raw chunks rely on core's fresh grant,
revision, pin and source-stamp checks plus authenticated private immutable snapshot.
They never repeat is_current's whole-file hash. Do not widen15/30s timeouts,
delete integrity checks, or promise16/30MiB always completes.

Core read_chunk closes/releases its real pin at successful EOF. Native therefore
removes the mapping and emits eof=true/session_active=false. Later check is
invalidated. A copied cache/PFD CANNOT inherit current=true from that old ID, and
there is NO silent reopen. Host must not deliver/activate a display under this
closed lease. Needed core additive contract: explicit display-retaining read mode
(or read_chunk_keep_session) that keeps the SAME immutable source/pin/grant/generation
validated through EOF, with real is_current/explicit close and bounded expiry; no
latest revision fallback. Core owner alone decides/implements it. Until then this
is a bounded raw read/processing bridge, not a PFD display lease.

Android owner must still implement actual seekable READ_ONLY PFD creation from
bounded/digest-verified bytes, correct display lease/final check, actual Messenger
transport, owner/scope lifecycle disposal and idle invalidation publication.
No fake FD/URI provider is returned here. Annotation mutation needs its separate
original intent/receipt/reconciliation gateway; native exposes NO annotation save.
Core lib.rs evidence export stays B-owned; existing evidence module must be exported
on the integration branch. Real generation/Host/Android are separate acceptance.
