# C01 product agent owner: local implementation and live gate

Status: new-product owner, transport composition and settings/confirmation UI implemented locally; **C01 live acceptance remains incomplete**. No model/search request was issued, no real credential was read, and no historical reservation was changed. Compiled production pricing-proof ports remain unbound, so entering a credential/budget cannot enable a paid request.

## Product implementation

- `crates/muyon-core/src/agent/owner.rs` owns a separate product SQLite ledger. Explicit initialization never replaces an existing database. A workspace/version check and process owner lock protect it. Settings create fresh configuration and credential-generation identities; they never read an old canary profile, batch, key, grant or ledger.
- Visible settings confirmation supplies a cumulative cap in micro-CNY and a cumulative request-count cap. Reconfiguration keeps all charged amounts and reserved/unknown holds. Native plans bind the exact configuration, owner epoch, payload digest, purpose, conversation and request identity. Preparing never sends or reserves. Confirming reserves under one SQLite transaction. Dispatch commits `unknown` before returning bytes for its sole attempt; the original request cannot dispatch twice.
- Cancellation before dispatch releases only an unconsumed reservation and retains the request tombstone. Cancellation after dispatch leaves unknown and its hold. Reopening retains all accounting; lookup is read-only, old-epoch configurations cannot dispatch, and credentials must be reinstalled. Valid completed ordinary answers retain bounded conversation history. An unresolved prior ordinary-chat request blocks a new turn in that conversation.
- Full response/schema/answer/usage validation precedes settlement. Invalid/truncated/over-bound answers retain unknown and the full hold. Known usage settles to a conservative cost bound, not a provider invoice. Configuration change or cancellation suppresses answer disclosure while allowing proven usage accounting. Search decoding directly reuses the existing DeepSeek provider contract; a validated empty result releases spend while preserving request identity. No tool call is treated as a text answer.
- `ProductChatRuntime.kt` is the private Service coordinator. It binds reviewed plans to the live client session, separates native control from network workers, never holds a Kotlin credential lock across native calls, and exposes no raw claim/settle operation to UI/model code. Session release cancels active/prepared requests. Close wipes the memory credential and stops accepting work; `awaitDrain` must succeed before native teardown. A drain timeout is not completion evidence.
- `ProductHttpsTransport.kt` extracts the existing Android HTTPS worker, retaining TLS hostname verification/SNI, exact endpoint, repaired header/framing handling, bounded body, deadlines, write watchdog and a single POST. Chat/search use only their fixed provider paths. There is no redirect, alternate provider, retry, proxy or credential fallback. The temporary credential port uses only a Service-memory CharArray plus opaque generation; credential material never crosses a Rust argument or enters a saved-state/JSON/log API.
- `ChatScreen.kt` supports new configuration review, request preview, explicit per-request confirmation, original-result lookup/cancel, accounting display, external source display and local business reads. It commits original request identity before confirmation and never automatically resends after a timeout/restart. Credentials are masked, not saved, and cleared from the UI after handoff. The current missing-proof plan explicitly disables confirmation.

## Reuse and pricing authority

The reused Android transport and memory-credential source files are:

- `experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/OrdinaryChatHttpsTransport.kt`
- `experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/OrdinaryChatTemporaryCredential.kt`

Existing provider admission/readiness, finite text review, SSE parser and SearchProvider contracts remain repository dependencies rather than replacement implementations. `agent/mod.rs` also connects strict read-only supplier/paper tools to the real BusinessStore; source replies bind current workspace/project/epoch and explicitly declare `outbound_authorized:false`. Local data is not automatically model-disclosure authority. Imported raw JSON and attachment paths are excluded from paper summaries.

The pinned 2/8 micro-CNY token formula originates in the old `OrdinaryChatLiveInstallation.kt` response validation; the 5000 micro-CNY search value originates in `web-search-lab/core/src/deepseek.rs::price(CNY)`. These are provenance for the existing contract/test arithmetic, **not new authorization or verified current hosted prices**. `PRICE_REVISION` identifies that formula only. Ordinary chat requires a compiled trusted `HostedCostVerifier`; search requires a compiled trusted `SearchPriceVerifier` for the actual endpoint/payload/revision. Neither is deserializable from UI input or installed by the production FFI. Default prepare methods therefore return a blocked local plan with zero reservation. `FixtureProof` and `FixturePrice` exist only in Rust tests.

The existing `OrdinaryChatReferenceTokenBound` explicitly does not prove hosted billing parity; the historical fixed canary permission cannot authorize generic product text. A real verified current pricing/cost-bound port must be installed independently before enabling a live request. Historical CNY1 caps or unknown reservations are never expanded, cleared or reused here.

## Fresh verification

From the candidate worktree:

```text
cargo test --manifest-path crates/Cargo.toml -p muyon-core --test agent_tools --test agent_owner --test agent_product --offline --locked
owner: 11 passed; local read/parser: 6 passed; tools: 6 passed; 0 failed; 0 ignored; exit 0

cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --test agent_tools --test agent_owner --test agent_product --offline --locked --no-deps -- -D warnings
exit 0

python3 docs/tasks/muyon-android-refactor/C01/run-offline-check.py
transport compile: exit 0
memory-stream protocol/send-gate checks: 20 passed; 0 failed; no network
runtime + transport compile against SDK36, JVM target17: exit 0

rustfmt --edition 2021 --check crates/muyon-core/src/agent/mod.rs crates/muyon-core/src/agent/owner.rs crates/muyon-core/tests/agent_product.rs crates/muyon-core/tests/agent_owner.rs
git diff --check
exit 0
```

The Rust owner tests use fresh actual SQLite files and include two actual child-process SIGKILL windows after reservation and after dispatch claim, retaining the original hold and refusing replay after reopen. Their provider/cost authorities and response bodies are explicit local fixtures. Other cases cover cumulative budgets, revocation, credential generations, cancellation, strict usage, conversation history, empty/nonempty search settlement, read scope isolation and soft-deleted records.

The Kotlin harness uses only ByteArrayInputStream/ByteArrayOutputStream, CountDownLatch barriers and a deadline close callback. It creates no socket, contacts no server and loads no real credential. The original 11 header/protocol checks remain, plus both write/revocation orders for cancellation/configuration/session release/close and late registration rejection. Kotlin compiler emits JDK25 deprecation warnings about its own Unsafe use; compilation exits zero. Android Gradle/lint, full Service/Compose compilation and API26 tests remain the parent integrator's serialized verification responsibility.

## Independent-review repairs

`ProductSendGate` serializes actual write/flush with configuration invalidation, cancellation, session release and close. The network's native permission check is outside the gate and is only a prior check; the gate rechecks its local ticket/generation/session at actual write. No native DB/FFI call occurs under this monitor. Its advisory reads are volatile and nonblocking so the watchdog can close a blocked socket while the write holds the gate. If revocation linearizes first, no later write occurs. If write linearizes first, revocation waits for that write and the prior durable unknown reservation remains.

The previous check-then-write shape is deterministically RED using `run-offline-check.py --legacy-send-check`: a latch pauses after permission checking, cancellation completes, and the zero-later-writes assertion fails (exit 1). The repaired gate passes both orders for all four revocations. `sendgate-red.log` and `sendgate-green.log` retain the results.

The attempt-count regression was first RED against real SQLite: claimed request → cancellation → valid empty search settlement caused used_calls to become zero. A persistent `attempted` marker now commits with the dispatch claim. Cancellation/empty/late terminal results never remove an attempted call from cumulative counting, including after reopen; a never-claimed cancellation may still release its held slot. `attempt-count-red.log` retains the failure; the repaired regression passes within the 11 owner tests.

The new-product ledger schema is now version 3 with the same filename; older versions are rejected explicitly, never wiped or silently treated as compatible. The parent integrator confirmed this candidate had not configured/created that agent ledger on the device. Existing business data and historical canary ledgers remain untouched. Same-version restart tests prove holds and attempted counts survive.

Transport failures persist only an allowlisted stage and optional numeric HTTP status. Unknown, reservation and no-replay behavior stay unchanged. The test stores HTTP_STATUS/403, reopens, verifies the original hold/count, and rejects raw text or invalid status. These are memory/SQLite fixtures, not network retries. UI operation errors use only an allowlisted generated native code field; raw Throwable messages are never retained.

## Remaining acceptance boundaries

- No live provider/search execution, accepted live answer/usage or externally obtained source evidence was produced in this lane. CH01–CH04 and the complete C01 card cannot close on these local tests.
- The local function-call → actual BusinessStore read → exact visible disclosure → independent follow-up path and suggestion → pure P04 preview → visible original business confirmation → verified original receipt → result disclosure path are implemented and fixture-tested. See [TOOLS-LOOP.md](TOOLS-LOOP.md). Actual live model access and API26 tool-dialog behavior remain unverified; local/fixture tests cannot close those acceptance gates.
- Model write suggestions only prepare a P04 plan; no model confirmation/grant tool exists. Completing a tool context does not authorize automatic retransmission of its history. The user can explicitly start a fresh conversation; historical tool-context reapproval is outside the implemented route.
- The historically platform-denied I04 experiment was not retried, decomposed, renamed or routed through this owner. Its independent HOLD remains unchanged.
