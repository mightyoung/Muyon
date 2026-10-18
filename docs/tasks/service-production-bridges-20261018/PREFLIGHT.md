# Approved binding preflight

Read-only review at ff792336d3c52ee8874ccfa2b80b19beb71f72e5 found no verified approved live profile/endpoint/model/credentialRef/budget binding in workspace evidence. This does not assert the user has no device configuration. No secret values were inspected, no secret read/create was invoked, and no external model was called.

- Dart source owner: apps/muyon/lib/app/bootstrap.dart:376-423; platform/grants/host_scope_authority.dart:46-180; platform/storage_manager.dart:13-23. ScopeResolver resolves current references and source identity, not durable read consent by itself.
- Read policy: platform/business_tools.dart and tool_registry.dart recheck current registry/scope/policy; assistant/model/write/outbound/module grants do not authorize an independent durable read.
- Profile metadata repository: services/models/profile_repository.dart:9-36 reads workspace settings modelProfiles dynamically. Defaults in assistant/agent_budget.dart:13-21 are not approved paid provider budgets.
- Model authorization: platform/grants/host_model_authorization.dart:58-186,346-424; services/models/model_gateway.dart:661-734 recheck precise payload/destination and current policy around credential/ledger/send boundaries.
- Package boundary: Flutter com.mightyoung.muyon and Compose com.mightyoung.muyon.androidlab are independent app sandboxes. Flutter secret_store channel is not a Service bridge. Flutter MainActivity.kt:18-36 may create Keystore key on read; it must not be used as availability probe.
- Compose has no INTERNET permission. Existing Rust offline-fixture/loopback endpoint is not an approved live transport and is not reused by this implementation.

Minimum remaining binding: existing approved profile id; complete endpoint URI and endpoint identity; provider/model; location; chat purpose; declared/tested capabilities; credentialRef existence through its actual owner (handle only); source owner namespace and readonly source binding; authorization owner and current revisions; approved call/token/spend maxima and durable quota proof. No raw key is requested.

Code integration and live model acceptance are separate statuses. Controlled test owners and synthetic schema12 fixtures prove bridge behavior only. External provider acceptance, production user-store access and actual budget/ledger owners remain NOT_RUN/unbound until the above evidence exists. I04 original denial and PR86/dependency merge hold are unchanged; PR87 remains separate.
