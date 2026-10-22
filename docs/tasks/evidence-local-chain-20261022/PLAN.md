# MIG16 local evidence implementation

Base: f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac (document core).
UI reference: 98baa979223d96094f11a56c3ac6d48f9b84c0eb.
Design read from 400e206135690c284c8402521e3135cfb7bfaee8, originals/三产品总纲 and Perplexity specification.
No AGENTS.md or .agents/skills in these checked repository snapshots.

Ownership: only src/evidence/, tests/evidence_local.rs and this report directory.
Do not edit lib.rs or documents/ (core owner), Android shell or host service.

1. Test first: synthetic UTF-8 text, byte digest, scope/revision/revocation,
   wrong anchor, body/citation/candidate separation, unsupported PDF and failed text.
2. Implement pure local processor with core DocumentRef, BlobRef, AuthorityBinding,
   DocumentHost and validate_read. Bounded UTF-8 extraction and literal matching;
   no database, file paths, network, embedding, new document store or second index.
3. Source IDs hash complete source identity, including scope/revision/blob;
   anchors bind UTF-8 byte offsets to immutable source. Text has no fabricated PDF page.
4. Receipts are actual ephemeral processing outcomes, not durable save receipts.
   Existing persisted import/task/intent stores remain owned by their current owners.
5. Independent review, preserve failed/NOT_RUN, push dedicated branch and verify SHA.

Integration request to core owner: add `pub mod evidence;` to lib.rs. Until then,
standalone integration test includes the actual module with #[path]. No owner file patch.
For text, DocumentFormat::Unknown plus explicit InputKind::Utf8Text is used because
shared DocumentFormat has no text variant; owner should add a Text format before
production routing. Hosts must deliberately authorize this mode. Never classify
unknown files automatically as UTF-8. PDF/OCR processing remains Unsupported here.

Android ResearchIndex (existing) uses normalized 768-dimensional embeddings and
checks source currentness per search. Dart DocumentParser uses pdfrx for PDF, plain
UTF-8 for text and digest recheck. Neither runtime is available to this Rust module.
We expose extraction and bounded literal lookup, with index=not_run; no claim of
semantic retrieval, PDF extraction or OCR. Existing hits may be adapted by owners later.
