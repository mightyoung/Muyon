# Independent repair graph review

Immutable reviewed source: `c76687fd`. No test, build, generation, network or credential operation was executed by this reviewer.

## Ruling

Permitted against this source:

```sh
cargo test --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test ordinary_chat_controller -- --test-threads=1
```

The target now has six tests. New cases use the same fresh temporary roots and controller path: synthetic output-secret rejection, generation change after commit, quota exhaustion, bounded modification of the newly created ordinary-send-v1.db evidence, revoked authority and a no-host fresh controller. They do not use historical state, Agent::open, HTTP/socket, subprocesses or suite discovery. Modifying the new ordinary evidence file and then polling is not the denied old task.db → HTTP → original-state reopen sequence. The new missing-owner constructor only inventories its newly created empty root, and ordinary dispatch denies without falling through into supplier work.

Same build-only bridge and local UniFFI generation commands from CONTRACT.md are permitted, with MUYON_BRIDGE_BUILD_ID set to the full actual c76687fd source SHA. Repository manifests/build.rs/workflow selectors are unchanged from the previously reviewed graph. The plugin-contract public Json import fixes the earlier E0603 path without broadening execution. Preserve the failed build log as FAIL evidence. Genuine generated Kotlin must still be reproduced and committed; no compilation or runtime success is inferred from this review.

## Context-freeze repair

The prior blocking send-context substitution defect is resolved in source:

- ServiceProviderBridge.prepare_chat first creates the held reservation, then invokes the same host's bind_chat_context with its exact binding/request/payload/handle/context. A bind failure drops the prepared object through the existing held-reservation release path. Default hosts deny this new operation.
- CallbackProvider forwards opaque identity/generation and exact context bytes to the same callback owner. No new authority or credential-value API was introduced.
- DurableServiceHostOwner.bindChatContext runs under the existing monitor → authority guard → SQLite transaction. It checks the current owner/binding/capability and exact held request/binding/scope/payload. It requires task/attempt and request-correlated input_ref, then inserts a unique immutable chat_contexts row keyed by the held reservation token. Duplicate insertion cannot overwrite the pin.
- Ordinary commit requires a pinned row and matching current capability in the same transaction, alongside the existing held-reservation/current binding/scope/proof checks.
- Send joins that pinned row and checks exact context and capability byte equality, in addition to current capability/scope/binding/payload, before inserting/committing its unique chat_attempts row. Fake handoff remains after durable attempt commit while the authority guard is held. A changed conversation/task/attempt/input_ref after prepare cannot become the first accepted send context.

The new schema is intentionally strict and remains a fresh ordinary-chat schema. No migration/reopen of a prior installed ordinary schema is approved in this test scope. The initial pin accepts trusted Rust-created context; runtime current authority is checked again before send. This matches the chosen same-owner contract without needing a supplier source.

## Evidence limits and remaining validation

The six Rust cases use a test-local Owner; they prove controller behavior and a synthetic owner contract, not execution of Kotlin's SQLite transaction code. The real Kotlin durable owner repair has been source reviewed, but an exact per-field mutation/rebind/duplicate-send negative test against that owner has not been observed. Do not report such a test PASS from this review or from the Rust fixture's matching implementation.

Provider receipt validation is now stricter about closed context/authority/profile/body/usage fields, policy-owner relationships, exact input bytes, completion/total bounds and restored input_ref. New evidence-tampering tests stay in the permitted fresh-root graph. Their outcomes remain NOT_RUN by the reviewer.

The previous workflow graph allowance and restrictions remain: only ordinary chat lab push and PR94-stacked Draft; no develop/main Draft that launches ci.yml aggregate, no other suite/CI dispatch, no I04 or old 403 download, no key/.env access, real model, fee, deployment, merge, force push, deletion, PR90/Dart8 modification or HOLD removal. No real DeepSeek verification is claimed. Reviewer writer stopped after this file.

## Inventory follow-up at 61e25a59

Read-only reviewed delta c76687fd → immutable 61e25a59. The same six-case named integration target with `-- --test-threads=1`, bridge build-only and local binding generation are permitted with the actual source SHA updated. No I04/HTTP/Agent::open/historical-root route was introduced.

ServiceRoot inventory adds only ordinary-agent-v1.db and ordinary-send-v1.db to its known-file list, permitting the existing active controller to admit another request after a successful ordinary run. Existing directory ownership/mode, file type/symlink/uid/0600, entry and byte limits remain; recognized interrupted atomic temporary files still poison the root. The changed quota test now asserts first and second completion before exhaustion, so the earlier census failure cannot masquerade as a successful quota rejection. The other Kotlin delta stores nullable provider in a local variable for the existing capability predicate; it does not change the graph or authority.

Previously observed c76687fd 5 PASS / 1 FAIL and diagnostic failure remain failures, per parent's report and retained logs. This review did not rerun them or claim the fix passes. Generated binding remains incomplete until genuine reproduction. No old records may be reopened to validate this repair. Reviewer writer stopped again.
