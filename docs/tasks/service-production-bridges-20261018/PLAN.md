# Service production bridges implementation plan

**Goal:** Connect trusted scope and configured provider metadata/credential handles to the existing private Rust Service controller without claiming live model acceptance.
**Spec:** ../frontend-service-loop-20261018/NEXT-SESSION.md and current user delegation.
**Architecture:** Host-only typed owners supply current authority. The UI retains text and selected object references only. Configured provider preparation is separate from any transport and defaults unavailable.

## Constraints
API26, private Service, Rust Agent, trusted builtins and existing subprocess boundary; unchanged visual UI. No external model, secret retrieval/configuration, INTERNET permission, paid service, license acceptance, main/develop merge, force push, branch deletion or deployment. I04 denied original script→HTTP→original-state reopen and dependent PR86 merge hold remain untouched. PR87 remains separate at 38b59db43f2487700ff15971ee008f0024673a13. No broad Rust suite that could execute the denied path.

## Ownership and steps
- Scope worker: core/src/supplier_scope_bridge.rs, core/tests/supplier_scope_bridge.rs, core/src/supplier_store.rs. Typed source identity/namespace and current scope stamps; tests first, scoped RED then implementation and GREEN.
- Provider worker: core/src/service_provider.rs, core/tests/service_provider.rs. Profile/endpoint/model/purpose/capability/budget and safe credential handle binding; exact-current admission tests first. No network adapter reuse.
- Service integration worker: core/src/service_host.rs, core/tests/service_host_controller.rs, core/src/service_controller.rs, core/src/supplier_business.rs. Host-only injection into same controller/worker; no UI authority input, no silent synthetic fallback, no replay on recovery. Tests first.
- Root alone: lib.rs exports, CI, Android bridge if feasible, docs, commits/push/Draft PR and final coordination. Independent read-only fixed SHA review after writers stop.

## Review focus
Revocation between read and disclosure; source/owner/revision drift on recovery; credential handle creation or secret leakage; endpoint/profile/payload drift before admission; budget/ledger failures, cancellation and ambiguity. Each belongs to scoped tests and immutable review.

## Preflight
Workspace starts from ff792336d3c52ee8874ccfa2b80b19beb71f72e5 (same product as 2f8f4da674e871708880dcc792a1c9dafb3a17f3). No verified approved live binding is present. Dart owners are in another Android package, not inherited by Compose. Live acceptance NOT_RUN. Existing failure/cancellation/broad-test incident ledger is retained unmodified.
