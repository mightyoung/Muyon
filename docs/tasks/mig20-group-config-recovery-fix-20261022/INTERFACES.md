# Recovery fix integration delta

Based on96d90fd0b264552ec93a997b59da56099d345937. Existing `GroupUiScope::current`, `group_ui_read` and `group_ui_prepare_configuration` public signatures and v1 request schemas are unchanged. No core/lib, FFI, AgentOwner, RunLedger or host owner file is modified. Existing export patches and exact canonical/gateway hooks remain in ../mig20-group-config-bridge-20261022/INTERFACES.md.

## Complete intended group row

`group_effect` now serializes the intended Registration and captures workspace/project/revision/record BEFORE the group INSERT or UPDATE can fire SQL triggers. The effect transaction passes these intended bytes to the final check. After exact grant consumption, the final reader compares the real complete group row against this intended row, in addition to the existing intended run-row witness, authority/scope/expiry, receipt, event and grant checks. No write follows those checks before commit. A mode/leader revert preserving the new revision is Storage/PendingOriginal with effect rollback. Register is covered by the same pre-insert capture. The former post-effect database snapshot is removed; it could already be corrupted.

## Durable original intent identity: explicit extension schema2

`initialize_group_runtime` explicitly creates or atomically migrates the owned extension namespace from1 to2. Original six table DDLs and the BusinessStore core schema remain unchanged. One seventh owned table is added:

```sql
CREATE TABLE group_runtime_intent_bindings(
  intent_id TEXT PRIMARY KEY REFERENCES group_runtime_local_intents(intent_id),
  command TEXT NOT NULL
)
```

`command` is the exact actual GroupCommand supplied after trusted local confirmation and grant checks; it contains local scope/actor/revision/operation/authority, not credentials or provider payload bytes. It is inserted in the SAME initial transaction as the original pending local journal. The transaction's final reads require the exact workspace/project/group/digest/status=pending/receipt=NULL row AND the exact command row before committing. Suppression/tampering/SQL failures roll back both and return an error, without asserting a durable pending original. Later effect/receipt/grant-consumption tails verify the exact command row too. Corruption discovered after durable pending still uses PendingOriginal and rolls back only effect changes.

Schema migration never reconstructs a historical command or invents an account/principal/group. Version1 journal and receipt rows are preserved exactly; the new table is initially empty. The migration uses the owned BusinessStore connection/transaction and verifies final version/table DDL before commit. Partial/missing/wrong v2 table is rejected, not silently recreated. Call explicit initialization/migration at host setup before group operations. Reads never migrate or register anything.

## Read recovery without successful group registration

The v1 wire request is still:

```json
{"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"original-register-intent"}}
```

The host still supplies actual native workspace/project/owner epoch/authenticated principal through GroupUiScope; JSON cannot supply them. Query first selects the exact actual workspace/project/group/intent journal row. A store-private read-only `group_original_command` joins its durable original command and verifies the canonical command digest against the ACTUAL persisted journal binding, full scope, intent ID and original Human identity. Register additionally verifies original owner equals original Human. This verifies actual recorded facts; it does not trust a caller's in-memory command or snapshot.

The original submitter may query its exact historical intent without the group existing and without revalidating an expired old grant or old owner epoch as new authority. Another current human needs current group owner/admin membership. A missing command from legacy v1 is not original-actor proof: current group owner/admin may read using actual group management scope; without a group/proof the result is Unknown, not NotFound or a fabricated permission. Corrupt existing binding yields BindingMismatch; storage errors stay errors. No exact journal row yields NotFound. A stale native GroupUiScope still fails; reconstruct it from the current host after restart.

Response `local_intent.identity_source` is additive: exact_original_command for the actual original submitter, or current_group_management for current owner/admin. Missing receipt remains status=pending_original with recovery_action=query_original_local_intent. Query executes no effect, grant issuance/consumption, receipt write, registration, external request or automatic replay. A real pending Register before restart remains queryable after restart/owner-epoch change while no group exists.

The old source test for a trigger changing pending status has a stronger outcome under the new initial transaction proof: Storage plus no journal/binding rows, rather than claiming durable PendingOriginal after allowing a damaged pending row to commit. The existing original tests/logs are retained as historical evidence, and the updated test asserts the stronger rollback boundary explicitly.

## Owner boundaries

This change adds local metadata only. It does not authenticate accounts itself, create execution permissions, change host_only/fixed/per_task selection defaults, alter Unknown request retry rules, or provide canonical external request certification. The earlier exact AgentOwner canonical projection, durable trusted host context, richer private admission facts and sole gateway/FFI hooks remain pending their owners. The pinned document-core direct-source documents-import seam is unchanged; combined tests use the already delivered temporary-runner shim, not a protected-file edit.
