# Source receipt tail — required core interface, not an implemented API

Fixed reproduction coree3fa0ee71f071bb8cff667d50ee1c0da6827a7c9, based B662aeec6.
Current document_clone_in_transaction returns DocumentMetadata and discards the real
invalidation event batch. Its internal checks finish BEFORE our last receipt write.
Existing verify_document_source_notifications_in_transaction is documents-only and
requires the exact earlier event batch; gateway cannot safely reconstruct missing
expected events by scanning the already-corrupted outbox.

Minimum concrete contract requested (owner chooses actual Rust names/signatures):
1. The real clone operation returns actual published metadata plus an opaque,
   immutable same-store/transaction publication postcondition, minted internally.
   It freezes metadata/head/source identity, real blob reference/publication facts,
   and EXACT owner-returned notification IDs+generations for the full batch.
2. A read-only verifier consumes that frozen postcondition in the SAME caller SQL
   transaction. Reject foreign store/tx, changed head/metadata/blob/reference,
   missing or changed-generation/pending0 queued events, and reactivated source/
   local bindings. Existing legacy/installed namespace rules remain core-owned.
3. No BEGIN/COMMIT, new event generation, repair/re-invalidation, acknowledgement,
   payload/grant decoder, authorization shortcut or caller-constructible evidence.
   Failure propagates to roll back the entire clone/ref/head/source/outbox/receipt.
4. Gateway order: clone+freeze -> last receipt UPDATE -> reconstruct/check view ->
   read-only frozen postcondition verifier -> existing FINAL live grant check ->
   one COMMIT. No subsequent writes. Existing intent/Unknown/budget/permission
   semantics and hard engine/candidate publication denial remain unchanged.

No named Rust method/type is fabricated here. Await fixed owner interface/source,
then call its actual implementation. Re-running invalidate after receipt would
repair the deleted event/accept lost generations and is expressly unacceptable.

Independent additional build dependency: exacte3fa normal Cargo integration cannot
compile worker source_notifications.rs45 because its path-module graph lacks the
real Artifacts/Evidence source hook. Owner must assemble real modules; this worker
does not edit worker/core/lib/FFI, suppress the hook, or provide permissive defaults.
