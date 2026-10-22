# Local model tool loop

This implementation executes no provider request and installs no pricing proof. Production chat/search/follow-up remain blocked without compiled trusted cost/price authority. Local fixtures validate the orchestration; they do not constitute live model or external search acceptance.

## Reused contracts

`agent/tools.rs` composes the existing `ToolDefinition`, logical/wire name mapping, `identifier`, strict JSON decoder, and `wire_provider::encode_registered_request` structural assistant-call/tool-result pairing. The existing host distinguishes native read from model disclosure; the product preserves that distinction with an independent visible review. Business reads use the actual product `BusinessStore` and core payload/schema rules. No generic plugin executor, automatic grant or third-party dependency was added.

The catalog permits supplier/paper list/detail and supplier/paper write suggestions. Tool arguments cannot contain workspace, project, session, generation, authority or grant. List bounds are 1–50 with offset ≤10000; identifiers and supplier/paper payloads are validated by the product rules. Supplier suggestions permit only create/update/delete/restore, and paper suggestions permit only PaperCreate; imports, blob mutation, project creation, confirmation and arbitrary tools are rejected.

A complete single-choice, single-function-call response with exact type/name/arguments and complete bounded usage becomes `tool_pending`, with its original call cost settled. It is not accepted text and does not execute a tool. Mixed content, duplicate arguments, unknown tools, oversized pages, malformed schemas and unsupported write operations remain unknown without business effects.

## Bound source and disclosure

1. After pure ordinary-chat prepare and before confirmation, `bind_tool_scope_trusted` binds the request to the Service's live session, current generation, workspace/project and owner epoch. The context type is not model-deserializable. Binding a blocked zero-reservation plan is allowed; it does not authorize sending.
2. A read tool queries current actual business values. `review_tool_read` returns the exact serialized fields/bytes, digest, purpose and bound scope. These values are local UI data. No earlier `outbound_authorized:false` response is automatically forwarded.
3. Only a separate visible approval action may call `approve_tool_read_trusted`. It rereads and compares actual values, rejects a different digest/scope/generation, and records approval separately from the budget ledger.
4. A distinct user action prepares the follow-up. The code rechecks the approved values and builds structurally paired assistant-call/tool-result messages with the existing encoder. A new request identity and its own cost proof/reservation are required. The production `None` proof yields another blocked plan; there is no automatic confirm or send.

Restart, cancellation, changed generation/project/session, uncommitted/unknown originals and consumed steps cannot approve or resume the old flow. A step produces at most one follow-up plan.

## Write suggestion and actual confirmation

The suggestion callback can only construct a pure P04 plan. Its trusted host return contains a public `plan_id`/summary and private original intent/binding digest; only the public view is returned to the model workflow. The Service additionally provides the original complete business preview to the local UI. No grant or business execution occurs during suggestion preparation.

The UI renders the complete operation parameters, expected revision and scope. A separate visible P04 confirmation invokes the existing business confirmation path. Before doing so, it persists the original business identity. An unknown confirmation is query-only; it is never automatically repeated.

The tool workflow then reads the original committed receipt from `BusinessStore`, checking its exact intent binding and scope. It cannot accept a model/UI-supplied success receipt. Only after this check does it produce a result disclosure review. Another explicit approval is required before preparing a follow-up that contains only committed status and plan summary, without grant, authority, full receipt or intent identity.

`ProductChatRuntime` freezes the original project/session/generation per request, caches the exact host business preview, and rejects a different plan identity. Its private port and the parent's `agent_tool_step` dispatcher provide only named stages. The UI uses `chat_tool` with explicit stage actions; claim/settlement/raw receipt injection are not UI methods.

## Conversation recovery

Cancelling a settled `tool_pending` request now produces the `cancelled` terminal state, retaining its known charge and attempted-call marker. New ordinary messages in that conversation can proceed; the old disclosure cannot resume.

After a successful tool follow-up, ordinary automatic history reuse deliberately refuses the old `role=tool` bytes. The UI provides **开始新会话**, which persists a fresh conversation identity and does not carry previous business disclosures. Original requests remain independently queryable. Historical tool-context reapproval is not implemented; starting a new conversation is the explicit supported recovery path.

## Verification and limits

```text
cargo test --manifest-path crates/Cargo.toml -p muyon-core --test agent_tools --test agent_owner --test agent_product --offline --locked
7 tools + 11 owner + 6 local read/parser = 24 passed; 0 failed; 0 ignored

cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --test agent_tools --test agent_owner --test agent_product --offline --locked --no-deps -- -D warnings
exit 0

python3 docs/tasks/muyon-android-refactor/C01/run-offline-check.py
23 offline protocol/send-gate/scope checks passed; transport/runtime compile exit 0
```

The seven tool-loop tests cover real SQLite supplier reads, exact-byte disclosure, generation/source-change rejection, independent follow-up identity/budget, production missing-proof blocking, pure write preparation, independent P04 commit, original-receipt verification, result-disclosure approval, strict malformed-call rejection, cancellation/restart, pre-confirmation suggestion revocation and the explicit fresh-conversation recovery path. The separate local-read tests cover actual newly added PDF paper reads. No real model function-call, paid search, or API26 tool-dialog behavior was executed in this lane. Parent-owned full Service/Compose build, UI wiring and device acceptance remain separate evidence. Current-project and pending-plan revocation are detailed in [SCOPE-REPAIR.md](SCOPE-REPAIR.md).

The product agent ledger schema is now version 3, with the same new-product ledger filename and explicit rejection of older schemas. The parent confirmed this candidate had not initialized the agent ledger on the device; the existing business database and its imported papers were preserved. Historical canary ledgers and I04 HOLD were untouched.
