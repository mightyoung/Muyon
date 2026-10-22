# Independent fixed-source integration review

Reviewed `e74138c37b3e5786291dba3f066e84ae72df2c99` against `1d1437e6` in `/workspace/Muyon-frontend-loop`. Read-only review; no test execution, model call, HTTP, legacy-state/reopen operation or secondary agent. Existing worker reports/logs were read as reported evidence, not independently rerun. Untracked integration logs were not source inputs. Device/platform CI outcome remains pending.

## Blocking findings

### R1 — P1: final ledger write failure becomes endless nonterminal polling

`experiments/redesign/rust-agent-host-lab/core/src/supplier_business.rs:404-407` changes the summary to `OutcomeUnknown` and clears all events when final ledger persistence fails. `.../core/src/service_controller.rs:624-629` recognizes only `AgentRunSnapshot::Unresolved` as unknown; a settled `Terminal { summary: OutcomeUnknown }` falls through to the empty BusinessRead at 641-648. `supplier_business::reply` reports `status=events`, no events, `terminal=false` for that empty ledger. `AgentChatReadSession.kt:66` then polls every 250ms forever and shows “读取中”, concealing the actual storage/UNKNOWN settlement. Fail closed from the authoritative settled summary even when no ledger terminal could be saved. A targeted injected-final-save-failure regression should assert finite terminal/UNKNOWN presentation and no re-execution.

### R2 — P2: Cancel before bootstrap finishes does not stop the pending first dispatch

`.../agentipc/AgentServiceClient.kt:54-56` retains the original submit as `pendingChat`. `chatCancel` at 64-67 calls back null if bootstrap has not installed a lease; it leaves `pendingChat` intact. `AgentChatReadSession.kt:54-56` sets unknown and tries lookup, but the original submit still owns `inFlight` (59-60), so lookup is discarded. Successful bootstrap subsequently executes the original submit, despite the user cancelling while the UI explicitly enables Cancel for submitting. Cancel must remove an undispatched pending submit by request identity, or latch cancellation so a definitely dispatched run receives the same-ID cancel. No fabricated cancelled outcome is appropriate after uncertain dispatch. Parent has already routed this finding to the Android worker.

### R3 — P2: original durable receipt is unavailable to the chat after receipt-bearing interruption or disclosure loss

`.../core/src/supplier_business.rs:356-381` recovers a valid original receipt into `summary.receipt`, then clears all business events and emits only outcome_unknown terminal. The private chat API consumes BusinessRead, not summary receipt; this original receipt never reaches its UI. In addition, `.../state/.../ChatReadContract.kt:20` clears the receipt itself on every disclosure loss (including a successful read merely backgrounded), although historical metadata is distinct from current answer/projection. The stored `originalReceiptIdentity` is not rendered. This conflicts with `PLAN.md:30-31` and the retained oracle's `binder_lost` semantics: retain authorized historical receipt independently of current projection, and preserve actual original receipt after cancel/complete races. Return a separately validated original historical receipt on UNKNOWN/revocation where authorized, without republishing current values. Do not manufacture a replacement receipt or label a missing durable record as not-started.

### R4 — P2: unsuccessful handshake can strand pending chat indefinitely

`.../agentipc/AgentServiceClient.kt:145-146` only publishes diagnostic text for Busy/Rejected handshake replies. Unlike the adjacent Local branches, it does not clear/complete `pendingChatFailure`. The chat callback therefore never removes `inFlight`; its conversation remains submitting, with subsequent reconciliation silently rejected at `AgentChatReadSession.kt:60`. Every bounded handshake exit needs exactly one completion of its pending request, retaining UNKNOWN/no-resend policy. Review `observe` queue refusal and `connect` early-return branches for the same outstanding-callback invariant.

## Confirmed source properties and limits

- Actual implementation path is Compose Send -> Application-owned ChatReadPort -> bounded private AIDL -> private `:agent` Service -> retained GeneratedAgentController -> genuine UniFFI bridge -> existing AgentServiceController -> registered trusted `inquiry.supplier_name` -> read-only SQLite -> ORIGINAL NativeStore/ToolRegistry receipt -> bounded ordered terminal event batch. This is real platform wiring in source, with an explicitly synthetic business database and deterministic local Agent/tool dispatch, not a live model.
- UI visuals/assets are retained and local Save remains separate. Fixed host synthetic key/revision, source-byte identity, no UI path/SQL/grant/model/credential input, and production selection denial are explicit.
- Binder request/reply bounds, same-UID/private Service boundary, UTF-8 payload limits and JSON closed shapes are present. Snapshot restoration retains request/run/admitted epoch/original receipt identity; reconnect performs lookup, not submit. Completed requires projection plus original receipt. JSON reply matching prevents replacing an already known run/admitted epoch with a new connection identity.
- `supplier_read_events` explicitly drops the controller mutex at line 630 before durable receipt/source verification in `reply`. No new global-lock-held SQLite/receipt IO was found there. It performs disk IO on a Binder worker, but the single UI observer queue is independent of the control lane.
- The final ledger save failure clears completed business events, so I did not find a direct completed-events/UNKNOWN-summary false-success contradiction in that branch. Its actual bug is R1's empty nonterminal stream. Transient validation can fail closed while task identity is still being published; an UNKNOWN response must remain reconcilable.
- JNI/API26 cross-build explicitly selects cc/ar per Android target for bundled SQLite. CI reproduces Kotlin bindings, requires same-source ABI manifests, verifies native APK entries and runs real UI/Binder/native instrumentation on API26. Actual workflow success/device evidence is still required before claiming platform acceptance. Existing tests mostly cover pure policy and Rust source/receipt semantics; they do not cover R1/R2/R4 transport/error schedules.
- The 18 Python oracle tests describe a different preparatory DTO (including receipt-before-projection) than the implemented wire protocol. Their pass is useful design evidence only, not a conformance proof for Android `JSONObject` decoding or the concrete Rust event shape.
- Production ScopeResolver/model provider/approved endpoint binding remains absent and fail closed. Real model API is NOT_RUN. Existing synthetic source and endpoint-free read do not establish production business integration or model use.
- Known prior worker broad-suite incident remains as recorded; this reviewer did not repeat it. Main/develop merge and I04 hold remain untouched.

## Assessment

Happy-path source wiring meets the bounded synthetic-platform slice; it does not yet satisfy the recovery/cancellation/original-receipt acceptance target due to R1-R4. No new tests were run by this review. Re-review the fixes at a new immutable SHA and capture actual combined API26 CI/device results before declaring this slice complete.
