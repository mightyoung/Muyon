# Bot / Agent continuation — independent static review

Snapshot: `7aa852ab8134545c6312cd71de5c12cd49f66b5b`, 2026-10-23 UTC.
Review is read-only. No cargo tests/Clippy were rerun by this reviewer, avoiding contention with the parent runner. Parent-dispatched tests are not counted as independent PASS.

## Existing Bot definition fixes are present

`bot_definitions.rs` retains the reviewed durable pending/effect split and final `verify_current`, original-intent uniqueness, owner epoch binding, current business/project scope, source registry exact schema/meta validation, TEXT and byte-length validation, source revision/lifecycle/scope/archive digest comparison, and exact definition/receipt comparison. `a1544d77eb3817c28201ef75c877511a6c6bb579` already applies the one-line equivalent flag expression. No repeat implementation or old Clippy-failure claim is warranted.

Creation remains a trusted local definition operation with `runnable=false` and `provider_not_configured`. The absence of Bot create FFI/UI wiring is a documented design/delivery boundary, not grounds to invent a new public API or provider configuration.

## Important candidate: lazy workflow loading skips a persisted cross-child guard

Static path is present in the current source; runtime regression is still required.

1. `crates/muyon-android-ffi/src/lib.rs:145`: `ProductCore::open` always sets `workflow: None`, including when the durable workflow database exists.
2. `:340`: the existing unscoped `agent_prepare` calls Owner preparation directly. `:366–374` scoped preparation opens the ledger, but using the old entry does not.
3. `:567–614`: confirm/claim/allowed use `authorize_agent_request`; `:992–996` calls `RunLedger::authorize_request` only if the optional ledger is already loaded.
4. `agent/workflow.rs:957–969`: the skipped ledger gate is precisely where a parent conversation is matched to unresolved child chains. `AgentOwner::ensure_request_resolved` only checks the request's own conversation; generated child conversations differ from their parent.
5. The existing private Service adapter still supplies both old and scoped preparation ports. No change to Service/UI is proposed here.
6. The existing `another_root_and_ordinary_chat_cannot_bypass_an_unknown_child` regression (`FFI :1188–1301`) checks scoped preparation in the same core instance, then deletes the fixture. It does not test reopening before the old entry/confirmation path.

Minimal proposed proof: reuse that existing synthetic owner fixture and valid local cost-proof stub; persist the unknown child and original held cost, drop/reopen to a new epoch, avoid workflow/scoped preparation calls, then exercise existing unscoped prepare plus the existing confirmation/claim guards. Assert that the parent remains blocked by `conversation_original_outcome_required`, all original child reservations remain unchanged, and no transport is invoked. Current production missing-price-proof refusal must not be mistaken for this specific cross-child guard.

If reproduced, fix only the existing internal ledger-recovery/authorization initialization boundary under its owner; no new public endpoint, database, grant, credential, provider configuration or real external request is necessary. This report does not authorize modifying another owner's FFI/Service path.

## Other reviewed boundaries

- Workflow child depth 1, simultaneous active count 2 and cumulative count 8 are present in `CreateChild`; unknown children count as active.
- `RunScope` is host-built; action enum rejects unknown fields. Skills map to the two compiled read tools. Local execution uses existing `ReadScope` and `read_business`.
- Startup projects queued/running/waiting activities to unknown; old session/epoch mutations are refused. Remote observation chains originate from Owner durable followup edges.
- Cancel and disable route back to original owner request IDs; they do not imply a refund, rollback or successful model execution.
- No new confirmed Bot-definition defect was identified in this static pass. The lazy-loading candidate above requires the stated local regression before a runtime-failure claim.

No Reader/Laya changes, source edits, commits, pushes, live requests, credentials, old unknown retries or hold changes occurred.
