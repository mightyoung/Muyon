# DOC-01 / DOC-03 public contracts

Base: `3ecb544ad0a47ccc38fe830777f35588b92e8afc`; branch:
`task/document-core-contracts-20261022`. No UI, DB or agent-flow changes.

## Public interface (published before implementation)

- `DocumentRef::new(Scope, document_id, Revision, DocumentFormat)` validates
  immutable identity; accessors only. This is metadata, never authority or MIME proof.
- `ReadRequest { document, authority: AuthorityBinding, operation, anchor }` contains
  no path or URL. `DocumentHost::resolve_current(&ReadRequest)` must atomically
  resolve a host-owned handle and current scope/revision/grant/lease, or reject.
  The host supplies `CurrentDocument` with existing `FileSource`, current identity,
  binding, active/revoked state and granted operations. No decoded grant is trusted.
- `validate_read(&dyn DocumentHost, &ReadRequest, &CapabilityMatrix)` returns only
  `Result<(), ReadInvalidation>`; no reusable permit, bytes or authorized cache.
  The future host must check again at delivery, including every cache/OCR/index/
  thumbnail/export access. Local read never authorizes outbound disclosure.
- DOC-02: `DocumentSafety::check(&DocumentRef, &FileSource) -> SafetyStatus`;
  `Unknown`, `Rejected`, `Accepted` are reports, not implemented parsing. The
  future resolver must bind safety reports to exact source bytes before engine use.
- DOC-06: `RevisionPrecondition { document: DocumentRef, authority:
  AuthorityBinding }` names the base for future CAS. It performs no transaction,
  publication, idempotency, cancellation or write and mints no authority.
- `CapabilityMatrix` indexes `(DocumentFormat, DocumentOperation)`; default
  `Unknown`, explicit `Unsupported` and gated states. No installed engine exists.
- `DocumentAnchor { document, location }` binds the entire identity/revision.
  PDF anchors retain zero-based page, explicitly unknown coordinate system,
  rotation and crop; invalid/nonfinite rectangles fail; unknown geometry remains
  unknown. DOCX part/paragraph, PPTX slide/shape and XLSX sheet/range stay format
  specific. Anchor validation never claims underlying target resolution.

## Host boundary

The trait implementation belongs to a trusted service, never model arguments.
This batch deliberately provides no production resolver or engine. Existing blob
readers alone do not establish document/project revocation semantics. A future
adapter must check active grants and project membership at byte delivery and
exclude stale cache/handle replay. `Scope` currently has workspace/project only;
group membership remains a host check, not a fabricated scope field.

## Task index and execution plan

Research originals: [Office v2.0](research-office-v2.0.md),
[static evidence v1.0](research-static-evidence-v1.0.md). Library IDs respectively
`libfile_c94323014d388191ba1853e9aef8f532` and
`libfile_f74abbd878e081918ff0e1886325a7fd`; complete text read (194/185 lines,
`has_more=false`), copied without proprietary binary/code payloads.

1. Publish this interface/research checkpoint before implementation.
2. Add behavior tests first for cross-scope, stale revision/epoch/generation,
   revoked-cache replay, permission intersection, unsupported/missing capabilities,
   invalid/unknown PDF geometry and cross-format anchors.
3. Attempt `cargo test --offline -p muyon-core --test documents` from `crates/`.
   Missing toolchain is NOT_RUN, never a verified red/green TDD cycle.
4. Implement `documents/{identity,anchor,capability,mod}.rs`, exporting only the
   new module in `lib.rs`; no SDK/dependency/filesystem/network integration.
5. Attempt offline full workspace test and formatting, independently review the
   branch, fix findings, publish raw logs/environment/report and push own branch.

DOC-01/03 contracts only; DOC-02 parsing, DOC-04 annotation, DOC-05 licensing,
DOC-06 execution, DOC-07 real format experiments, DOC-08 durable CAS, DOC-09 UI,
DOC-10 advanced engines remain unimplemented. No real model/search calls; old
two unknown requests and ¥0.002620 reservation untouched. Leader B alone merges
develop; no main/develop modification, deployment or paid work.
