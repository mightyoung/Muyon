# Real Evidence resolver and invalidation handoff

Continuation of fixed 65fb35c6195a03b48dc476a0917527aa310d02c5; inherited
Evidence 78cdff32dee68b664c4fe71b4bbd6b81251af5e7 and core aec085fa.
Only artifacts/** and this task's docs/scripts were authored here. The Evidence
merge introduces only its owner's fixed files. No owner lib.rs/documents/FFI/UI
or Runtime changes; module exports in test copies only.

## Actual source API

`artifacts::local_sources::ResolvedLocalEvidence<'store>` has private fields,
no Deserialize and no public constructor. It borrows the exact BusinessStore and
freezes resolving actor. Its only projection, `target() -> LocalTarget`, uses real
EvidenceRef.evidence_id and **source document revision**. There is no fabricated
independent Evidence row revision, message ID or display-index mapping.

```rust
BusinessStore::resolve_local_evidence_trusted<'store>(
    &'store self,
    project: &ArtifactProjectAccess,
    purpose: ArtifactProjectOperation, // ONLY LocalDraft or LocalFeedback
    access: &DocumentAccess,
    processing: &StoredProcessing,
    reference: &EvidenceRef,
) -> Result<ResolvedLocalEvidence<'store>, ContractError>;

BusinessStore::issue_local_evidence_binding_trusted(
    &self,
    access: &LocalAccess,
    kind: &LocalKind,
    expires_at_ms: u64,
    proof: &ResolvedLocalEvidence<'_>,
) -> Result<(), ContractError>;
```

Host uses its existing serialized BusinessStore guard: obtain actual
StoreEvidence::process(Utf8Text), find_literal, then resolve the exact hit. Resolver
calls actual StoreEvidence::open, verifies original bytes/controlled reader and
quote/source IDs, discards the ephemeral quote, rechecks exact canonical metadata
and ReadText grant, and rechecks independent project purpose before returning.
Cleanup ambiguity becomes Unknown; never claim source verification on error.
No real model/search request occurs.

Issuer requires same store/actor, exact project scope, exact evidence ID/source
revision and fresh persisted ReadText. `LocalDraft`, `LocalSubmit`, `LocalFeedback`,
`ReadOwnLocal` remain separate persisted purposes; Save/Discover imply none.
Core DocumentAccess grants have no actor column: the trusted host must still
resolve the source grant from the authenticated actor's actual source-policy
decision. This module freezes actor and prevents cross-actor proof reuse; it does
not invent an actor ACL absent from core.

One explicit new table: **artifact_local_evidence_sources_v1**, same BusinessStore
connection/transaction, project+actor+local object primary key. Stores original
DocumentMetadata, source authority and exact EvidenceRef JSON (IDs, offsets,
source/blob digests), active bit and exact source document ID; **no source bytes or
quote/body copy**. Six prior local tables/schema/journal unchanged. Explicit
initialize_local_interactions_trusted adds/checks the new table atomically; read
paths never create it. A 65fb-only DB needs this explicit initialization.

Each binding resolution, read, prepare, confirmation and mutation checks the
original source's current canonical document head, exact metadata/blob reference,
ReadText generation/epoch/expiry/active state in its existing local transaction.
StoredReference decoder also verifies content-addressed source/evidence IDs and
metadata/reference consistency against fixed78cdff's ID contract. Unknown or
unsupported references fail closed. Receipt final UPDATE is followed by this
live source check plus existing exact local kind/binding/project-purpose checks
before COMMIT. There are no writes after those tail checks.

A <=30s component lease remains an additional bound, **never source verification**.
New head, grant withdrawal, expiry or generation change immediately denies frozen
preview lookup/confirmation and current value reads without waiting for TTL or a
callback. No automatic source-latest rebinding or retry occurs. Source snapshots
and manual values remain on disk. Original pending is QueryOriginal, never replay.
Receipt-only own lookup stays actor/project filtered and exposes no form/body.

Generic `issue_local_binding_trusted` now only renews an already resolved original
Evidence binding. Initial unverified Evidence and **all Message targets are
Unsupported/denied**. Actual PDF/OCR processing remains unsupported by fixed
Evidence; Text is not a PDF relabel or a promise that arbitrary bytes are UTF8.
No FFI/UI action should be enabled for these unsupported types.

Explicit fresh real proof may renew only source **authority** (including after
revocation/restart). Original metadata/reference/evidence identity must remain
identical, local binding_generation must advance and existing kind/spec/object
identity remain fixed. Old preview authority then fails. Stored human draft,
CAS revision, sticky mask and per-field provenance survive unchanged. Changed
source revision requires a new explicit object/attempt, never overwrite/rebind.

## Source mutation notification hook — owner integration required

```rust
BusinessStore::invalidate_local_evidence_sources_in_transaction(
    &self,
    tx: &Transaction<'_>,
    changed: &DocumentRef,
) -> Result<Vec<LocalSourceInvalidation>, ContractError>;
// LocalSourceInvalidation { project_id, actor_id, object_id }
```

Core owner must call AFTER changing a source head or its persisted grant, inside
that exact BusinessStore transaction, propagate any error and roll back. On
success, commit the source mutation, then notify the returned object identities
through Runtime's existing UI event channel. Do not publish events before commit.
Do not add a new store, polling lease, model message or external notification.

Hook checks same connection/workspace and scans only the exact project+document
identity using 256-row keyset batches in one transaction. It verifies actual
original source access for every matching binding; unavailable sources atomically
mark their source and local binding inactive. It neither modifies/deletes form
values, original review snapshots, receipts nor pending intents. Event identities
are trusted-owner output, not a project-discovery/user bridge endpoint. The hook
returns all affected objects; there is no 256-object refusal that can block
legitimate revocation. Rollback removes both invalidation and source mutation.

**This hook is implemented and tested, but NOT wired to core mutation entrypoints
or UI events**, because those files belong to their designated owners. Every
public local read/write independently enforces source revocation already; automatic
push-to-UI notification remains integration work. Owner grant changes must pass
the affected exact document to this hook, not just grant ID without resolving its
canonical document identity. No document-owner hook was edited in this branch.

## Message source gap — precise owner request, no fake implementation

Read actual AgentOwner requests schema and lookup/request_conversation. Its
canonical rows persist request id, conversation, payload/digest, answer and status;
**they contain no stable Message identity/revision**. ProductChatRuntime's maps and
ChatScreen's conversation UUID do not provide that missing persistent mapping.
Do not interpret request ID, body text, row position or display component ID as a
stable Message. Existing request/unknown/reservation records remain untouched.

Runtime/AgentOwner owner needs a read-only authenticated source interface with:

- stable persisted message_id, request_id, side (user/assistant), conversation_id,
  exact project/workspace/actor scope, source_revision and source_digest;
- owner epoch and independent policy generation/revision, access state, terminal
  request status; answer revisions must refer to canonical persisted answer, not
  UI text or model-provided message IDs;
- `resolve_message_snapshot(actor, scope, message_id, expected_revision)` returning
  a non-deserializable owner proof and optional readonly canonical content handle;
- `with_message_source_guard(proof, operation)` / tail revalidation under the same
  owner serialization boundary as message changes and policy withdrawal. Parent
  must define cross-ledger lock ordering/atomicity before enabling Message local
  commits; a fresh 30s snapshot alone cannot close the race;
- post-commit source-change/revocation events carrying exact message identity and
  revision/policy generation so frozen local previews are invalidated.

The host must bind LocalTarget to the owner-confirmed message ID+revision, retain
request+side mapping in its canonical owner, and not create canonical body rows in
artifacts. No Message resolver, empty trait, fabricated receipt or clickable
placeholder has been supplied here. FFI/UI wait for real owner support.

## Verification and retained failures

Official Rust1.93.1 + Clippy installed only /tmp using pinned official hashes from
fixed Evidence provenance; all dependencies from repository Cargo.lock, no version
changes. Existing SQLite runtime linked using temporary symlink. See
`evidence/source-toolchain.txt`. Original NOT_RUN/127 is retained; no SQL run is
counted as Rust evidence.

- `source-workspace-final.log`: actual module-export-only disposable copy, **41/41
  artifacts tests**, comprising original17 + original15 adapted to real Evidence
  fixtures +9 source tests. Full workspace **279 passed, 0 failed**, EXIT0.
- `source-independent-cargo.log`: independent reviewer runs actual9 source cases
  in its own target directory, 9/9 passed. Final review/hash in
  SOURCE-INDEPENDENT-REVIEW.md.
- `source-live-guard-red.log`: real negative-control copy with only live bound-source
  check removed: head-change preview test fails; receipt-tail revocation falsely
  commits and test fails. Both cargo EXIT101, expected. Production source unchanged.
- `source-batch-red.log` TextLimit -> `source-batch-green.log` passed; regression
  has258 actual resolved bindings. `source-renewal-red.log` BindingMismatch ->
  source-renewal-green.log all40 passed. `source-identity-red.log` wrong real source
  accepted -> source-identity-green.log all41 passed.
- `source-second-run.log` retains one test setup failure: reused grant ID with a
  different actor correctly denied; fixture changed to a distinct grant ID.
- `source-first-compile.log`: first actual build failed native -lsqlite3 linkage,
  plus full-workspace existing formatting differences; log retained. Temporary
  existing-runtime symlink fixed linker; owner/system files unchanged.
- `source-live-guard-harness-failed.log`: disposable negative-control initially
  lacked git metadata; corrected explicit source label, not counted as regression RED.
- `source-clippy-first.log` found own2 needless borrows and prior local6 same-line
  if formatting lints; fixed equivalently. `source-clippy-owner-fixes.log` still
  **FAILS strict -Dwarnings only on unmodified owner hooks**:
  blobs.rs646 clone_blob_reference_in_transaction and documents/storage.rs449
  document_clone_in_transaction are unused in this limited combination. No allow,
  owner edits or strict-clippy-success claim. Parent B may exercise them through
  its full fixed owner modules. Full-workspace fmt is also not declared passing.

No deployment, real source/user files, network provider calls, credential changes,
external messages or actual business submissions. Local form submit and feedback
remain local durable records only. FFI/UI/Message/core-notification integration and
full production acceptance remain explicitly incomplete.
