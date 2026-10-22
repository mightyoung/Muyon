# Save journal and project catalog continuation

Base artifact source: 4eec6d164e84d87c74b6bc92f45ecb1e3138f680.
Owned new modules: artifacts/project_access.rs, save_journal.rs, catalog.rs,
workflow_tests.rs; artifacts/mod.rs only for owned refactoring and exports.
No lib.rs/documents/host/Android owner edits.

New explicit same-BusinessStore schema namespace (no second SQLite connection):
- artifact_workflow_meta_v1: version/workspace, explicit initialization only.
- artifact_save_intents_v1: exact semantic request+digest, actor, pending,
  committed/rejected state and original bounded receipt; never chat state.
- artifact_project_grants_v1: narrow host-issued project catalog/save/own-receipt
  permissions using existing Scope, AuthorityBinding and project revisions.
  No document body, grant or document truth is duplicated.

Save protocol: authenticate independent Save project permission plus exact output
write/source read authority; persist pending before effect; commit document,
artifact and original receipt in one transaction. Same intent never reruns a
pending or committed effect. Changed parameters/actor/scope conflict. Storage
errors return Unknown+QueryOriginal, never an automatic retry action. Lookup
cannot schedule effects or change pending rows, even if no matching row exists.
A failure before pending persistence can leave no row and no effect; lookup still
returns Unknown/NotFound and callers must not auto-submit a replacement.

Catalog: independent Discover permission on exact workspace/project/actor and
project revision, current persisted epoch/generation/expiry/revocation. Grant on
a document never grants Discover. Return only inventory (ID/revision/title),
no source snapshots or body. Read document content via separate document grants.
LookupOwnSaves is actor-bound; Discover does not reveal other actors' journals.
Trusted issuing must be called only after actual host project-membership policy
and authenticated identity. No model-defined permission list is accepted by a
public dispatcher. Scope deletion/project revision change invalidate access.

Historical content: consume only the actual core-owned historical hook once a
fixed implementation commit is provided. No publication-tail authorization reuse.
Current exact-source snapshot/sticky-human checks stay intact.

Test first: journal duplicate/parameter conflict, persisted pending across restart,
no retry on SQL fault, receipt survives later edits, receipt revocation/other actor,
catalog pagination, wrong project/doc-only grant/expired/revoked denial. Keep Rust
NOT_RUN if no installed toolchain; independent SQL results remain separate.
