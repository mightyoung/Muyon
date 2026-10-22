# P03 / S01 / S02 product core

Implemented in `crates/muyon-core/src/business.rs`. The product store uses the reviewed SQLite C seam, a distinct explicitly initialized namespace, and a process-lifetime nonblocking exclusive flock. `open_existing` never creates a database, upgrades a schema or creates the blob directory. Current store version is **2**, independent of protocol/business version 1; no legacy migration is implemented. Opening validates all 19 required table definitions, including columns and constraints, against the same initial DDL used by initialize. A version label alone does not establish a valid schema. Old v1, failed/partial or altered schemas are refused without creating tables or replaying intents. The API26 development-candidate incident and preserved old unknown intent are documented in [SCHEMA-V2-INCIDENT.md](SCHEMA-V2-INCIDENT.md).

## Host API and authority boundary

```
BusinessStore::initialize(path: &Path, workspace: &str) -> Result<(), ContractError>
BusinessStore::open_existing(path: &Path, workspace: &str, owner_epoch: &str)
    -> Result<BusinessStore, ContractError>
store.issue_grant_trusted(&CommandEnvelope, Option<&str> /* admission_id */)
store.revoke_grant_trusted(grant_id: &str, generation: &Revision)
store.cancel_trusted(intent_id: &str) -> Result<ExecutionResult, ContractError>
store.execute(&CommandEnvelope) -> Result<ExecutionResult, ContractError>
store.lookup(intent_id: &str) -> Result<ExecutionResult, ContractError>
store.supplier(id: &str) -> Result<SupplierRecord, ContractError>
store.suppliers(limit: u32, offset: u32) -> Result<Vec<SupplierRecord>, ContractError>
store.project(id: &str) -> Result<ProjectRecord, ContractError>
store.projects(limit: u32, offset: u32) -> Result<Vec<ProjectRecord>, ContractError>
```

`*_trusted` entry points belong exclusively to the real authenticated host confirmation/policy path. No model-supplied envelope can issue, renew or revoke a grant. Wire authority is not capability proof. Grant issuance starts at generation 1, subsequent issuance requires the next stored generation, and the trusted host assigns a 30-second expiry using actual system clock. Epoch, full command binding, generation, active state and expiry are checked before pending persistence and inside the business transaction; expiry is checked again after the actual SQL effect. Grant consumption, revocation, cancellation and commit use the same database's BEGIN IMMEDIATE write queue. The admission ID is only a correlation, not a claim of atomicity with a second billing/outbound database.

Pending is committed first. Business row, domain history, generic business history, original receipt, committed intent state and grant consumption then share one transaction. Before COMMIT the executor checks persisted receipt, effect, history and consumed-grant bindings, including grant generation/epoch/admission. Same full intent returns its original result without a second effect; altered intent binding conflicts. Existing pending/unknown never reruns. Lookup is read-only; missing is unknown+not_found, not proof of no execution. Receipt recovery revalidates the stored original command and exact identity. Cancellation cannot undo an already committed effect.

The public dispatcher currently implements supplier create/update/soft-delete/restore and project create. Paper/import/blob commands return unsupported until the respective trusted implementations are connected. The crate-private `execute_with(&CommandEnvelope, FnOnce(&Db, &Transaction<'_>, &CommandEnvelope) -> Result<Value, ContractError>)` shares durable admission, authority, transaction and original receipt for future domain modules; its closure receives proof of the active transaction for controlled blob publication, and must not use another connection or issue transaction control. Successful closures return the real resulting projection. The wrapper independently writes generic business history.

## Supplier behavior

All eight fields pass the P01 normalizer. Same names have distinct stable IDs. Complete updates require the exact current revision and SQL CAS. New same-normalized-name intent still advances revision. Soft deletion keeps payload, ID, history and old references; ordinary lists filter deleted rows while by-ID and old references project the tombstone. New references to a deleted supplier fail. Restore increments revision and adds its own receipt. Pagination caps each page at 200. Every reader binds to the workspace selected by `open_existing`.

SQLite failures map to fixed Storage/StorageBusy/StorageConstraint/StorageCorrupt/StorageIo errors; SQL/errmsg/path details do not enter public errors. A failure with an unproven transaction outcome remains unknown and never becomes a retry.

## P05 schema handoff

The sole schema writer added blob_uploads, blobs, blob_pins and blob_references in the initial unpublished schema transaction. `database()`, `workspace_id()`, `owner_epoch()` and `root_dir()` are crate-private. The root is the **complete database path plus `.blobs`**, avoiding shared parent-directory namespaces. Only explicit blob begin should create it; open_existing does not. This schema/helper handoff does not claim any file-copy, GC, reader-pin or attachment-recovery behavior has passed.

Paper/import plans now bind the exact attachment/snapshot upload IDs in addition to hashes. Attachment ID map keys must be declared attachment digests. Runtime still must consume the named project's actual pinned upload or prove an existing same-project readable reference; absent ID is not permission.

Evidence and boundaries: [VERIFICATION.md](VERIFICATION.md).
