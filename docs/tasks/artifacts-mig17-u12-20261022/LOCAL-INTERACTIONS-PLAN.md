# U06 / U09 bounded local interaction storage

Fixed base de3ec5b56de80f30c5a98c0b22bae64ece6167ae, core aec085fa.
Read U06/U09/U08/U13 from design400e2061 and actual Kotlin ComponentLedger,
CardModels/ActionCards. Kotlin owns the reducer/view, not durable host storage.
No existing generic Rust form/feedback persistence was found. No bot draft or
canonical message/evidence/document body is replaced.

Owned new artifacts/local_interactions.rs + dedicated test module and docs.
Reuse BusinessStore, existing Scope/AuthorityBinding/project checks, CAS and the
artifact journal's bounded rows, pending/commit writes and uncertainty dispatcher.
Local-domain table names are internal constants, never payload-defined SQL.

Six explicitly initialized same-connection tables: artifact_local_meta_v1,
artifact_local_bindings_v1, artifact_local_forms_v1, artifact_local_feedback_v1,
artifact_local_reviews_v1, artifact_local_intents_v1. Existing namespaces unchanged.

Binding issuance is a trusted HOST seam: resolve the real current original
message/evidence and actor/project policy first. Persist only exact IDs/revisions,
component/attempt identity, fixed field allowlist/options, short <=30s binding
lease tied to the parent project grant. This is not a second canonical source.
Reissue may refresh the same binding only; changed target/revision/spec needs a
new explicit object/attempt, never silently retarget existing edits. Host must
revoke on source/policy changes. No source resolver/FFI is invented here.

Separate project purposes: LocalDraft, LocalSubmit, LocalFeedback, ReadOwnLocal.
Existing Save/Discover never imply them. Code-enumerated fields Text/Choice/
Selections; host options are bounded opaque IDs, not action/method/URL names.
Human per-field sticky mask; suggestions cannot change human-edited fields.

Every mutation has an original intent and CAS. Pending locks its local object;
Unknown never replays or creates replacement intent. Form prepare stores exact
values+revision digest for explicit local confirmation; edit invalidates preview.
Confirm changes only that local component record and locks it; redo requires a
new explicit attempt/object. Feedback references exact original message/evidence
revision; Helpful/NotHelpful/None has no approval/execution meaning.

Last receipt write must be followed by exact binding/purpose/project tail checks.
Receipt lookup is actor/project SQL filtered and returns operation metadata only,
not private draft values or source bytes. Current values require ReadOwnLocal and
fresh exact target binding. No external send, real business object edit, arbitrary
schema executor, model request or source byte read is provided.
