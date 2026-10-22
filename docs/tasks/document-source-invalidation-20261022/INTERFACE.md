# Exact source invalidation integration patch

Patch baseline: B `b4940ddc1600acced5e268053450b48395df93f6`; no Reader source.
Required source dependency: artifacts resolver
`0e85c6e98c4e32efc8008092e480626f342a701d` and its fixed Evidence78cdff module.
B must import those exact owner files and own the existing library/harness exports.
This branch will carry a reviewable unapplied core patch; it does not submit broken
crate::artifacts references against the old resolver or modify the author's files.

Core patch calls the real
`BusinessStore::invalidate_local_evidence_sources_in_transaction(tx, changed)`
AFTER head publication/COPY and grant issue/update/revoke writes, in the same
existing SQLite transaction. Grant replacement decodes the original bounded
DocumentRef before overwriting and checks both old/new document identities.
Errors propagate and original mutation plus source/binding invalidation roll back.

Optional feature policy: no source-feature table and no core notification marker
means the new resolver is not initialized; normal docs operations remain usable,
including legacy six-table local-interaction databases. A present wrong-kind or
malformed source table is not absence; the real owner hook validates its schema.
If the core marker already exists but source table disappears, fail closed.

One notification table on the SAME BusinessStore database stores only affected
project/actor/object IDs plus per-object monotonically increasing generation and
pending bit. No source body, permission truth, quote, form value or extra store.
Coalescing avoids one row per repeated event; acknowledged rows retain generation
to prevent stale-ack ABA. A source invalidation and pending notification commit
together. Nothing is sent to Runtime from inside a transaction.

Trusted Host reads pending notification pages only after source mutation commit,
publishes to Runtime's existing local UI channel, then acknowledges exact returned
generation tokens. Failed/unknown publish does not acknowledge; repeat notification
is safe. No model/user discovery endpoint or external send is added. Notification
does not replace live validation on any local read/write.

Public seams: `pending_document_source_notifications_trusted(after, limit)`
returns at most256 typed metadata tokens; `ack_document_source_notifications_trusted`
acknowledges at most256 exact tokens. Old mutation API result shapes stay compatible.
The new table is lazily initialized by a source-feature writer transaction only;
read/ack paths never initialize absent schemas. Existing marker schema is exact.
No 256-object refusal may block a real revocation; all hook results are queued,
with bounded query pages. Storage cardinality follows distinct affected objects,
not a claimed total disk quota.

Runtime/FFI must consume this post-commit API; that adapter is not this owner.
Worker/group same-source harnesses also need actual Artifacts+Evidence modules
before this core patch can compile, supplied as a separate UNAPPLIED B-owned
composition patch. No fake/no-op hook or conditional feature hides a missing
dependency, and no lib.rs export is authored here.
