# Fixed-source remediation re-review

Reviewed immutable `93beaf18ff553db0e5d54feabb54c949cfc1a4e3` against `e74138c37b3e5786291dba3f066e84ae72df2c99`, in `/workspace/Muyon-frontend-loop`. Only source and retained reports/logs were read. No tests, network/provider/model calls, HTTP/reopen operations or extra agents were run. This review does not independently certify report PASS counts or pending new-SHA Android instrumentation.

| Original finding | Status | Source assessment |
| --- | --- | --- |
| R1 final save failure polls forever | ADDRESSED | `service_controller.rs` captures the actual settled snapshot, drops the mutex, then routes Terminal/Unresolved through `snapshot_reply`. UNKNOWN snapshots generate a bounded original-receipt-plus-UNKNOWN terminal or an explicit unknown terminal reply. `execute` replaces failed final ledger output with historical-only/UNKNOWN state instead of retaining a completed projection or empty pending stream. |
| R2 cancellation before bootstrap still dispatches | ADDRESSED | Request-specific main-thread `PendingChatAction` makes deferred dispatch and unsent cancellation mutually exclusive. Cancel clears the retained closure and calls the original failure completion before presenting definitive not-sent cancellation, freeing the UI in-flight slot. Late bootstrap/timeout cannot dispatch the cancelled token. Already handed-off RPC work remains uncertain and uses native cancellation/lookup. |
| R3 historical original receipt unavailable after loss/interruption | ADDRESSED | UNKNOWN uses exact original native row identity, admitted task/attempt, operation/args/ref binding and receipt outcome. Its stream contains receipt and UNKNOWN terminal only, never current answer/projection. UI separately displays persisted originalReceiptIdentity when current receipt disclosure is absent and explicitly disclaims current disclosure/success. |
| R4 unsuccessful bootstrap never completes pending chat | ADDRESSED | Busy/rejected handshake, connection/state failure, lane refusal, visibility failure and bind timeout all invalidate deferred work and complete once. Five-second timeouts stop indefinite chatRpc presentation waits. Identity-specific closure comparison and ChatReadCompletion suppress stale timeout/late completion. |

## Additional source checks

- Actual Agent task/attempt is attached to the durable Service run before `session.dispatch`, not first inferred after a successful receipt. The existing read path propagates callback failure and checks cancellation before dispatch. A payload-only source ledger on restart now reconciles durable receipt evidence to UNKNOWN without invoking another tool.
- Recorded failure metadata remains distinct from success; completed restoration explicitly requires RecordedSuccess. Historical receipt extraction does not publish the row raw value. A mismatched recorded identity fails closed.
- The store umask fix changes only test directory creation to the existing private-directory helper. It does not relax production mode/owner/symlink checks.
- Review fixes do not introduce HTTP/model/provider paths, production authority, new credentials, dynamic external plugins or an alternate Service controller. They do not alter original receipt bytes during recovery.
- No new serious source defect was found in the remediation diff. The new tests cover pure production helper/token semantics; their labelled categories are not real Android callback scheduling tests. Existing combined compile/lint and earlier native ABI successes reported by parent apply to their original SHAs; the new exact combined SHA still needs its CI/API26 runtime result.

## Nonblocking follow-up

`experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/AgentChatReadSession.kt:102` still requires every `terminal=true` envelope to have a terminal-event-derived status (completed/cancelled/failed/outcome_unknown). Rust `supplier_business::reply` now intentionally emits `status=unknown, terminal=true` with no events for unknown/disclosure-unavailable cases. Android rejects these legitimate envelopes and catches them as generic “连接或协议不可核实”, dropping the precise Rust reason. It still becomes UNKNOWN, stops polling, preserves identity and does not retransmit, so this does not reopen R1. Permit an explicit unknown terminal envelope while preserving no-value/no-resubmit checks, and add an actual decoder regression when practical.

`chatCancel` itself still lacks the chatRpc five-second one-shot timeout. This was not the R4 bootstrap defect and adds no new regression, but a stalled control RPC may leave a cancellation interaction pending. Do not broaden claims from bounded submit/query presentation to all control calls.

## Decision

R1-R4 are source-addressed at the reviewed SHA. Source review supports the synthetic real-platform integration slice proceeding to exact-SHA combined CI/API26 acceptance, with the nonblocking envelope correction above recommended. Real model API, production store/authority and new-SHA device result remain NOT_RUN/pending; none is established by this review. I04/dependent-merge holds remain unchanged.
