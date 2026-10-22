# Independent WebSearch composition

This bounded Rust slice implements the new DeepSeek **independent Search JSON API** through a provider-neutral registered `web_search.search` tool. It is not the Responses/Anthropic model server-side search feature. Fetch is deferred.

Status: socket-free integration fixture; **not installed in Android ordinary Send**. A production durable SearchHost/TLS adapter and settings persistence/UI are not implemented. There are no real credentials, network clients or account defaults in this crate. `SearchConfig::default()` is disabled; an enabled configuration without an installed local transport is explicitly unavailable. Saving or checking configuration does not call the API.

## Composition

A trusted host supplies `SearchHost` and a `SearchProvider` to `runtime::install(existing_native_session, owner, provider)`. Install uses existing Enrollment/Catalog data and tool registration. The returned `SearchRuntime::run` drives the existing core Agent; use this entry so final error/unknown normalization is applied. It delegates dispatch, scope and receipt validation to existing RuntimePorts. The query takes `query` and `count`; it cannot select credentials, endpoint, model, destination, location, original conversation or grants. A second synthetic provider exercises the same entry without provider-specific business branches.

Configuration stores only credential reference/generation. SearchHost resolves the existing opaque CredentialHandle; only the trusted owner may attach a Bearer header. The DeepSeek adapter pins `https://api.deepseek.com/v1/tools/search` and emits query/count/need_content=false. It does not use model settings or chat budgets. Direct successful nonempty search is budgeted at USD750 micros or CNY5000 micros per request; currencies are never converted. Empty results succeed at zero cost. Unknown retains its bound and identity until authoritative reconciliation; there is no retry, fallback or redirect following here.

The proposed SearchHost port must be implemented by the **same real durable owner ledger**, with final atomic config/policy/handle/payload/quota checks and one-shot attempt insertion before TLS handoff. It must reject running/unknown/consumed identities after restart. Trait comments are requirements, not evidence that the Android owner already implements them. Local readiness confirms installed adapter/config/handle only, not remote service health. Server account-wide rate limits cannot be guaranteed by this local component.

All result text, URLs and icons are tainted; no URL/icon fetch occurs. Results have no instruction authority, enter the Agent as Role::Tool, and retain provider/request/rank/URL provenance. Connection ObjectRef is an authorized capability scope; webpage URLs are provenance, not invented local references or upstream citation IDs. Existing native schema lacks float/null: exact score spelling is retained as string and actual nullable metadata is omitted. No date is fabricated. Before any result persistence, the whole normalized projection is reviewed by the owner; the saved raw receipt equals that reviewed projection. Query/result/derived answer review and current config are rechecked; mode policy uses the existing core authorize function. FullAllow does not add a prompt merely for taint/new destination, and cannot override credential/scope/revocation restrictions.

Muyon imposes 32KiB maximum wire response, 16KiB maximum normalized projection and 4KiB individual returned strings. These are local resource limits, not DeepSeek contract values. Oversized/invalid/incomplete replies fail explicitly without truncation or empty-list fallback. Error bodies never enter diagnostics or receipts. Official response/request facts: [Search reference](https://api-docs.deepseek.com/api/search/), [guide](https://api-docs.deepseek.com/guides/search/), [October17 release](https://api-docs.deepseek.com/updates/).

## Exact offline verification

Use pinned Rust1.99.0 and a disposable target directory:

```sh
export CARGO_TARGET_DIR=/tmp/muyon-web-search-target
cargo build --locked --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml --bin muyon-plugin-contract-lab
export MUYON_PLUGIN_CONTRACT_BIN="$CARGO_TARGET_DIR/debug/muyon-plugin-contract-lab"
cargo test --locked --manifest-path experiments/redesign/web-search-lab/core/Cargo.toml --test contract --test agent_search -- --test-threads=1
```

Only those two new integration targets execute. Existing dependency crates are build-only; no inherited unit/aggregate/HTTP/I04 target, old Agent::open/task reopen, denied log/artifact retrieval, real model/Search/Fetch, paid request or account modification. The fixture writes a new-root search ledger and proves rejection of the same identity by a separately instantiated fixture owner; this is not production Service restart acceptance.
