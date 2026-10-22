# MIG17 / U12 implementation contract

Fixed implementation base: f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac.
UI reference: 98baa979223d96094f11a56c3ac6d48f9b84c0eb (read only).
Design read from fixed remote commit 400e206135690c284c8402521e3135cfb7bfaee8,
`docs/design/2026-10-22/originals/Muyon-三产品借鉴与UI统一改进总纲-v1.0.md`, U12 and shared invariants.
No AGENTS.md or .agents/skills exists in these snapshots or workspace ancestors.

Owned: `crates/muyon-core/src/artifacts/**`, this task's docs and evidence.
No changes to lib.rs, documents/**, MainActivity, ChatScreen, ProductService,
ProductChatRuntime. Core owner integration: add `pub mod artifacts;` to lib.rs.
All remaining hooks already exist on the fixed core commit.

1. Write synthetic real-SQLite/blob unit tests first; attempt RED before implementation.
2. Artifact catalog on the existing BusinessStore connection, immutable revisions,
   source DocumentMetadata snapshots, actor/message/attempt provenance.
3. Explicit initial archive of an existing canonical document revision; revisions
   publish via document_publish_in_transaction with artifact+document CAS in one
   transaction. No second document body, blob or authority store.
4. Current grants required on every output/source access, including history;
   historical refs stay old even if current grants bind newer source revisions.
5. Reject generated revision after any human revision. Human changes preserve
   snapshots unless explicitly replaced by fresh authorized source capture.
6. Bounded paginated revision reads; historical recovery returns frozen metadata,
   never copies old bytes into the current head or authorizes an engine.
7. Independent review, final checks, push isolated branch and verify full remote SHA.

Public API planned on BusinessStore:
- initialize_artifacts_trusted()
- archive_artifact_trusted(id, access, sources, origin)
- revise_artifact_trusted(id, expected, access, finished, title, sources, origin)
- read_artifact_revision(id, revision, current_output, current_sources)
- artifact_history(id, before, limit, current_output, current_sources)

Origin is host-authenticated human actor or generated agent/run plus optional
message+attempt. It is never derived from model-authored JSON. The host must
explicitly invoke archive/revise after user save action. None is a dispatcher.
Ordinary form/reaction submission wiring is outside this artifact backend.

Review decisions superseding the initial proposal: source replacement is not
provided; all revision saves retain initial source snapshots. Newer source/output
grants do not authorize old revision content. Until core historical authorization
is implemented, changed historical refs fail closed (CORE-HOOKS.md).
