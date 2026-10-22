# DOC06/08 real host gateway — ownership and implementation batch

Preserved reviewed base:601f562f98163429103b344aecb3d8639c890a82.
Core persistence interface read:7c4a0664969da312208f1c0625920aae21c58948,
`docs/tasks/document-core-contracts-20261022/PERSISTENCE-INTERFACES.md`.

## Agreed direction / cross-owner hooks requested

Use the SAME BusinessStore connection, owner lock, BEGIN IMMEDIATE and rollback-on-
drop. No second DB, mirror document revision, or direct document_* table writes.
Core owner alone owns documents/, document grants/metadata/revision history,
annotations and lib.rs. This worker owns only document_edit/{gateway.rs,...},
tests/document_edit_gateway.rs and this task's docs/evidence. Existing business,
SQLite seam, blob code, UI/FFI are read-only dependencies.

Required core hooks (same owner and transaction, no nested transaction/COMMIT):
`document_authorize_in_transaction(tx, &DocumentAccess, DocumentOperation)
 -> DocumentMetadata` and
`document_publish_in_transaction(tx, &DocumentRef, title, format, &FinishedBlob)
 -> DocumentMetadata`.
The latter is already proposed by core owner; the former has been requested through
parent coordination. Actual compile/integration must use the published source;
there will be no fabricated production implementation to make tests pass.

## Real implementation scope

Gateway uses existing persisted document grants; it NEVER issues another user
permission or treats a decoded grant, read preflight, HostFacts or Validation boolean
as publication authority. Every source/candidate/receipt delivery checks current
scope/project membership and live document operation grant at use. Confirmation
persists the exact original binding and authority generation/epoch; preparation
and preview do not confirm. New session/grant cannot silently reuse old confirmation.

Tables owned exclusively by gateway: edit_journal_meta / edit_journal_intents.
Store exact canonical plan/binding, real source blob, confirmation reference,
state, cancellation flag, candidate bytes/hash, upload identity and original receipt.
Candidate bytes live as bounded hex TEXT because the existing SQLite seam binds
text only. Their actual SHA256 is checked on each delivery. No arbitrary paths,
URLs, fake blob refs or shared-store files are accepted from a model.

This batch exposes an explicitly COPY-ONLY operation: real immutable source bytes
are copied into durable candidate storage and verified byte-identical to their
source digest. This narrow validation is not Office parsing, layout or editing.
Engine patch/edit requests remain explicitly Unsupported; no third-party engine
or synthetic boolean can mark them validated. Copy-only receipt labels the action.
Real byte-copy infrastructure can therefore execute independently of engine HOLD.

Before copy and publication, persist one durable original-intent claim. Crash or
storage uncertainty after claiming becomes query-only Unknown, never automatic
replay. Core metadata CAS, receipt insert and committed intent state share one
SQL transaction; checked next revision applies. Finished blobs use the existing
fsync/pin/publication path. Same-intent duplicate calls return the original result
or Unknown and never start another upload/publication. Different binding conflicts.
Cancellation stops future work but cannot erase a receipt or rollback committed data.
Lookup accepts a current authorized DocumentAccess plus exact original binding;
a new read grant may query old receipts without authorizing another effect.

Tests first, original synthetic local sources only: reopen after prepare/candidate/
commit; two staged intents competing for one source version; same intent duplicates;
crash/pending original query without replay; revocation/generation/epoch; cancellation
before/after commit; source change; candidate tamper; engine Unsupported. Exact
raw test logs/environment/source SHAs and non-author review are required.

Temporary combination verification may add a verification-only module export in
the archive; the task branch's lib.rs remains untouched and only core owner will
publish the final library export. Full execution vs NOT_RUN will be separate.
