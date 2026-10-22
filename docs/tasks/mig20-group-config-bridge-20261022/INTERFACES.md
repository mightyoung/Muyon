# Native integration contract — MIG20 v1

Base: grant-tail fix `68f0fb697699d3a8589fc2cc4f274edaf2b2a67d`. This slice edits only group_runtime/store.rs and adds group_runtime/bridge.rs, dedicated tests and task artifacts. It supplies working local persistence and reads, with no FFI/host/core-owner edits and no executable Agent permit.

## Export integration

Sole core/lib.rs owner applies `CORE-EXPORT.patch` after combining the fixed group sources with document-core `10d3aa83e2a93581107ad2e9f44331b5ea99d866`. The patch is generated against that exact lib.rs and dry-run checked on a disposable copy. If group_governance/group_runtime/group_runtime_store were already exported, use `CORE-EXPORT-INCREMENTAL.patch` instead. Never apply both. No actual owner-checkout lib.rs was edited here. The patch is applied only in a disposable composition snapshot for validation. No new dependencies or lockfile changes.

```rust
use muyon_core::group_runtime_bridge::GroupUiScope;
// The actual host owns these native values, never the JSON caller.
GroupUiScope::current(&BusinessStore, selected_project: &str,
                      authenticated_actor_id: &str) -> Result<GroupUiScope, ContractError>;
BusinessStore::group_ui_read(&self, &GroupUiScope, raw: &str,
    owner: Option<&AgentOwner>,
    workflow: Option<(&mut RunLedger, &str /* actual host session */)>)
    -> Result<serde_json::Value, ContractError>;
BusinessStore::group_ui_prepare_configuration(&self, &GroupUiScope, raw: &str,
    authority: AuthorityBinding, conversation: Option<&str>)
    -> Result<GroupCommand, ContractError>;
```

Both methods recheck the native workspace/project/owner epoch. `GroupUiScope` is opaque, but its constructor's actor argument is a trusted host assertion, not account authentication. The inspected ProductCore State has store/agent/workflow, but no multi-user account/principal or registered group-context owner. The host must supply a real authenticated principal with project access; do not fabricate accounts, pre-register a group, or accept identity from model JSON. Existing local group owner/admin determines whether a prepared mutation can receive a trusted grant. Coordinator/member role grants no management rights.

`BusinessStore::initialize_group_runtime` is explicit schema setup. Reads/preparation do not initialize tables, create projects, register groups or issue grants. A brand-new group must be registered by a visible user action under an actual project.

## FFI owner: wire requests and routing

Exact requests are in `read-request.schema.json` (8192 UTF-8 bytes) and `prepare-configuration.schema.json` (65536 bytes). Duplicate keys, extra fields and schema versions other than1 fail. Runtime also checks canonical u64 bounds and cross-field rules; JSON Schema is the structural contract. There are no wire scope, actor, authority, session, SQL, file-path, snapshot or workflow-action fields.

Suggested FFI methods, to be implemented by its sole owner under the existing State mutex:

- `group_read(raw: String) -> Result<String, ProductError>`: derive native selected project and real authenticated principal, build GroupUiScope, pass actual state.store/agent/workflow and host session, serialize the Value. Workflow method internally sends only the read-only snapshot action. It does not enable other RunLedger actions.
- `group_prepare_configuration(raw: String) -> Result<String, ProductError>`: derive same native context; generate an authority reference and (register only) a host conversation ID; call preparation and retain the returned GroupCommand in host-owned prepared state. Return a review preview and opaque token. No grant at this step. Exact authority generation and confirmation token storage belong to host, not wire input.
- After visible confirmation, consume that prepared token once, call existing `issue_group_local_grant_trusted` then `execute_group_local`, and return its real local receipt. A dropped/uncertain result is queried by original local intent; do not prepare a replacement or claim Agent success. Return `LocalStatus::PendingOriginal` as pending. This task supplies the real implementations of those store operations, not a placeholder handler.

Read examples:

```json
{"schema_version":1,"request":{"operation":"catalog"}}
{"schema_version":1,"request":{"operation":"groups","limit":20,"after_group_id":null}}
{"schema_version":1,"request":{"operation":"group","group_id":"group"}}
{"schema_version":1,"request":{"operation":"runs","group_id":"group","limit":20}}
{"schema_version":1,"request":{"operation":"run","group_id":"group","run_id":"run"}}
{"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"original-intent"}}
{"schema_version":1,"request":{"operation":"workflow","group_id":"group","run_id":"run"}}
```

Preparation examples (project selected natively is `project`):

```json
{"schema_version":1,"change":{"operation":"register","intent_id":"create-group","group_id":"group","expected_revision":"0","members":{"a":{"scopes":["project"],"permissions":["read"]}}}}
{"schema_version":1,"change":{"operation":"configure","intent_id":"configure-group","group_id":"group","expected_revision":"2","mode":"fixed","fixed_leader":"a","members":{"a":{"scopes":["project"],"permissions":["read"]}}}}
```

Register missing/null mode yields host_only, native actor becomes actual local owner, initial admins are empty. Configure requires an explicit mode. Fixed requires its coordinator in members; host_only/per_task forbid a fixed coordinator.1..32 members, each scope must equal exactly the native project; nonempty permission IDs are local capabilities, never host permission elevation. Owner/admin transfer is not this configuration operation. Existing runs retain captured member/mode grants; configuration applies to future runs only and is not global member revocation. Each command uses the exact group CAS revision, existing local authorization and the fixed transaction-tail checks. Legacy captures are checked against the intended complete run-row set after receipt/events/grant-consumption writes; trigger interference rolls back and remains PendingOriginal.

## Response v1 fields

All successful reads contain `schema_version:1`, matching snake_case `operation`, and `execution_authority:false`. All UI revisions, coordinator epochs, deadlines, handoff/round limits, sequence numbers and money use decimal strings; counts/limits use bounded JSON integers. These responses are display facts, not permissions.

| Operation | Payload and interpretation |
|---|---|
| catalog | default_mode=host_only; modes host_only/fixed/per_task with initial_default/explicit; coordination_is_management=false; configuration_changes_apply_to=future_runs_only |
| groups / group | groups array + next_after_group_id, or group. Persisted group_id/revision/owner_user_id/admin_user_ids/default_mode/fixed_coordinator_id/members; management_role owner/admin/none reflects native principal only; configuration_scope=future_runs_only |
| runs / run | runs array + next_after_run_id, or run. Captured coordination_mode/coordinator_id/coordinator_epoch/members, limits, stopped/deadline_reached, nodes, persisted_summary, live_state, original_owner_status, owner_budget_status/owner_budget, canonical_payload_binding, execution_authority=false |
| local_intent | local_intent.intent_id/status/receipt/recovery_action. Missing receipt is pending_original; identity/status contradictions fail. It looks up only the original scoped local intent, never retries |
| workflow | availability + actual root/children, lifetime_child_count excluding root, active_child_count, original_request_ids, complete_lifetime_children, source, events_are_display_only, display_event_count, canonical_payload_binding, host_dispatch_permission=false, execution_authority=false |

Run live_state is stopped/deadline_reached/owner_not_bound/reconciling/pending_host_admission/configured/originals_resolved/local_proposals_inactive. These have display meaning only; stopped is a local coordination stop and does not cancel/complete an external original. A pending Unknown remains reconciling even after its deadline. `persisted_summary` is historical local evidence; live original observations are separate. Owner absent/unconfigured/query-failed does not manufacture ready, resolved or zero-charge state.

Each bound node or remote workflow child has `original`: actual owner lookup_status, original_request_id/current_request_id, actual status/attempted/cancel_requested/recovery_action and persisted request chain. `actual_usage_known` and `original_chain_resolved` are separate. tool_pending/tool_consumed can have known charged cost while chain resolution remains false. Current request cost uses actual_cost_scope=current_request and is not a root/chain total. Unknown/null/unavailable costs stay null; held reservations remain held. Per-chain entries preserve actual charged amounts only when settled. owner_budget has scope=workspace_owner and cap/held/charged/used_calls/max_calls; it is never presented as a root budget. Owner-budget unavailable/not_bound returns null with explicit status.

Workflow uses the real RunScope derived from current store/project, host session and group root conversation. RunLedger snapshot includes ALL historical runs; events are pruned to256, result previews may be truncated and snapshot total exceeds524288 bytes fails. Root IDs/scope/child parents/depth/counts are checked; child originals must match the actual child's unique conversation, not root conversation. The root is excluded from children counts (max8 lifetime,2 active). Snapshot root/child can_control is stripped. `complete_lifetime_children:true` certifies row identity/count coverage only, not complete attempts, payload history, result body or execution proof. If ledger is not supplied, availability=not_bound and complete_lifetime_children=false. Read results exceeding1MiB fail.

Contract errors remain errors (InvalidVersion/Payload/Identity/ScopeMismatch/NotFound/Storage*/TextLimit/RawLimit); storage/owner failures are not turned into Agent success. Preparation has no authoritative execution output. LocalStatus::Committed means SQLite coordination mutation committed only.

## Exact remaining owner hooks for canonical binding and the sole gateway

These are necessary integration changes in protected owner files; none was attempted or silently substituted. Current fixed document-core owner interface was inspected at `10d3aa83e2a93581107ad2e9f44331b5ea99d866` and recorded in evidence. These correct the earlier store slice's overly broad RunLedger limitation: full child rows ARE available now through actual snapshot and are implemented above.

1. **AgentOwner owner — read-only immutable binding.** Add `request_binding(&self, request_id: &str) -> Result<OriginalRequestBinding>` based on the actual request row: request_id, workspace, conversation_id, purpose, configuration_id, owner_epoch and canonical payload_digest. Existing private request SQL columns are id/conversation/purpose/config/epoch/payload/digest/reserved/charged/status/...; no project/group/node/member columns exist. AgentPlan already exposes its actual preparation digest, but there is no public persisted re-read hook after restart or at gateway claim; a saved caller plan is insufficient. Price revision and endpoint must come from the matching actual configuration owner/history, not guessed request columns. Do not return credentials or raw payload to UI.
2. **Host context owner — durable exact mapping.** Register real workspace/project/group/run/root/node/member plus epoch, plan/config/approval/policy/grant revision and actual request ID/digest before admission, verifying current group CAS/native project/account scope. No current mapping/table or authenticated-principal API was found in ProductCore State. The trusted owner must define that table/lifetime and admission transaction; this task cannot assert it exists or fabricate it. Store BindOriginal remains conservative actual-root-conversation identity association; the new workflow bridge can read child-conversation originals but does not upgrade that association into canonical execution authorization.
3. **RunLedger owner — richer admission facts.** Existing execute(snapshot) already supplies complete lifetime child identity/state. For atomic admission expose native scoped projection including private epoch/host-session, arguments/canonical dispatch binding, all attempt identities/counters/lease and actual root budget source. Preserve failed/cancelled/Unknown lifetime capacity and holds; events are never accounting. Existing authorize_request is retained.
4. **Sole gateway owner — recheck under claim boundary.** Current actual FFI `agent_claim` holds State mutex, calls authorize_agent_request (owner.ensure_request_resolved + ledger.authorize_request), then owner.claim_dispatch; `agent_allowed` calls authorization again plus dispatch_allowed. Add the real group-context canonical/lease/grant/recipient/epoch/budget/limits check here for every mapped original and followup, and recheck at actual claim/allowed path. Read-only UI snapshots and coordinator selection cannot authorize it. claim_dispatch itself owns a separate AgentOwner SQLite transaction that commits unknown before returning request bytes. BusinessStore, RunLedger and AgentOwner are separate connections; a mutex alone is not a cross-database commit. Owners must define one authoritative admission/consumption protocol and failure recovery, preserve Unknown/no automatic replay, and account for context changes between checks. No fake atomic guarantee or new outbound path is delivered here.

Local UI/configuration works now. Canonical dispatch certification remains unavailable until these precise hooks are integrated by their owners. No actual Agent/model/search/tool-provider execution was requested or performed; offline owner prepare/confirm/claim/settle tests only generate/inspect synthetic bytes and events.


Combination validation: raw `cargo test` against pinned document-core10d has a pre-existing direct-source harness import failure (blobs calls documents extensions, but business_worker does not import documents). The delivered `TEST-HARNESS-COMBINATION.patch` supplies imports for our two group harnesses only. `verify-combination.py` tests those copied harnesses with the actual combined exported production library through a standalone locked runner, so it does not compile or edit the unrelated business_worker. Its documents imports must be added by the responsible owner in the full integration. Raw failures and final161 passing executions are retained; full combined-package/FFI acceptance is not claimed.
