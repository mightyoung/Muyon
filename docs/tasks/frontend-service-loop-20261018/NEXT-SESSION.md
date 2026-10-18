# Fresh-session continuation boundary

Start from product `2f8f4da674e871708880dcc792a1c9dafb3a17f3`, Draft PR88, and this directory's FINAL-HANDOFF/FINAL-VERIFICATION/DELIVERY. Do not reconstruct intent from the old long thread. The finished slice is the actual private Service/Rust/registered read/receipt/recovery path on a synthetic SQLite copy, not arbitrary real-model chat.

## Writers and ownership

All implementation writers are stopped: android_ipc, android_store, frontend_binding, rust_business. Both fixed_sha_review and integration_review are complete/read-only. Root's only follow-up was delivery metadata/docs; it stops after this record. Product branch remains clean and frozen. No code writer, pending implementation task or ongoing acceptance run remains in this slice. The future session must establish its own isolated branch/path ownership before edits; do not resume idle workers against this frozen branch.

## Dependencies to resolve before live execution

| Gate | Existing integration point | Still missing |
| --- | --- | --- |
| Production source/scope ownership | `apps/muyon/lib/platform/scope_resolver.dart`, `business_tools.dart`, `tool_registry.dart`; Rust `core/src/supplier_store.rs::CurrentSupplierAuthority` | Supported schema12 user-store source namespace/identity and safe readonly handle from its actual host owner; trusted current ScopeResolver/policy adapter carrying allowed/available/scope, binding/source/rule revisions and selected object references. UI must not supply paths, SQL, grants, authority snapshots or approved=true. Never infer a durable read grant from assistant_grants/model/write/outbound/module_grants. Revocation must be checked before read, disclosure and outbound admission. |
| Service-owned model profile | Dart `services/models/model_gateway.dart`; Rust host `model_gateway.rs` and Agent Provider | Real configured-profile resolver in private Service, host-owned endpoint identity and approved purpose/model authorization. Current Rust gateway accepts offline-fixture only; synthetic supplier authority explicitly has model_allowed=false. Do not simply flip that flag or repurpose loopback/script adapters. |
| Credential/final-send bridge | Existing platform secret store/Keystore and Dart host model/outbound policies | Compose Service-accessible safe credential-handle lookup, payload/purpose review, exact-current-policy check immediately before transmission, durable outbound ledger and cancellation/usage handling. Existing Flutter channel is not this bridge. No secret values were inspected; no new credential may be configured under this slice. |
| Approved execution configuration | Existing approved configured profile/budget, if available in a new session | No verified binding was available here. Resolve actual profile id, endpoint URI+endpointIdentity, provider/modelId, location, purpose=chat, declared/tested capabilities, credentialRef availability (handle only), authorization/grant owner and current revision, approved call/token/spend budget and quota proof. Reuse only already-approved values; if absent, report the exact missing binding/approval at this gate rather than inventing defaults or asking for raw keys prematurely. |
| Android transport/policy | Current manifest and private Binder/Rust path | Current APK deliberately has no INTERNET permission. A real outbound path needs a separately reviewed network/policy change with the approved provider gate; retain private Service, same controller, API26 and child-process isolation. |
| True streaming/recovery | Existing bounded cursor batch contract | Provider token/event stream, bounded backpressure, cancellation, durable partial-result/error semantics and no-replay recovery must be specified and tested against actual authorized provider behavior; current post-read batch is not token streaming. |

Recommended next order: read-only approved-profile/source-owner preflight → define trusted production authority/provider bridges and explicit path ownership → scoped tests first → implement within existing controller → immutable independent review → fixed-SHA platform tests → only then a bounded approved real-provider canary. Physical/ARM64 runtime remains a separate evidence gap. Do not merge/deploy or add paid services/credentials without applicable authorization.

PR87 fixed38b59db43f2487700ff15971ee008f0024673a13 remains separate:21 synthetic Python PASS, eight actual Dart fixtures UNCOMPILED/NOT_RUN. Its static ledger semantic/error-body findings require validation before any provider reuse; no zero-leak or production canary claim is established.

I04 original legacy script→HTTP→original-state reopen is still denied; no retry, rewrite, split or alternate executor. Dependent merge holds remain. Preserve the store worker's accidental broad-test incident and every earlier failure/cancellation in FINAL-VERIFICATION and raw logs. No such test was run during this delivery-only follow-up.

## Subsequent independent slice

The next code slice is frozen at fc8ffd7e061736fdf9f4897d7c1c7914d429400a / Draft PR89. See [its handoff](../service-production-bridges-20261018/FINAL-HANDOFF.md), [verification](../service-production-bridges-20261018/FINAL-VERIFICATION.md), and [next-session boundary](../service-production-bridges-20261018/NEXT-SESSION.md). Prior evidence and failure records above remain historical and unchanged.
