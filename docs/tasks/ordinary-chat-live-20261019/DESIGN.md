# Ordinary chat live canary — design before implementation

Base: 3abc1cae405de4c941d540f1043cdf31463b3f95; executable source d1df23200df0ffaccac6edddd3b2115aaa6cfb42. Preserve the existing Compose → Service → Rust Agent → same durable owner path, original history revalidation, credential generations and receipt checks. Search is outside scope. No real request before independent review, offline checks and local credential handover.

## Gates and ownership

New chat-only files may implement immutable production configuration, exact payload pricing and a durable batch ledger. Shared DurableServiceHostOwner.kt must be coordinated with the WebSearch owner before editing. Any ABI extension additionally requires ServiceHostBindings.kt/service_host_bridge.rs coordination and regenerated bindings. Until coordinated, these files remain unchanged; dedicated components cannot be described as product integration.

Trusted configuration fixes endpoint https://api.deepseek.com/chat/completions and user-selected deepseek-flash. Require verified CNY account currency and current official peak/cache-miss pricing. A byte or character count is never a token proof. Exact full-history wire must have independently validated tokenizer/template evidence; missing proof denies sending. max_tokens=128, thinking disabled, n=1, non-streaming, no tools or attachments.

## Budget state machine

Batch identity is fixed for this acceptance run, independently of provider epoch and credential generation. Ceiling is 1,000,000 integer micro-CNY and two attempts. Reserve worst input plus hard output cap before handoff, with checked integer arithmetic and no cache/discount credit. Persist request identity, exact payload digest, pricing/proof identities, reservation and state atomically. Never refund a handed-off attempt. A pending attempt recovered after process death is unknown and permanently stops this batch. Timeout, cancellation after handoff, malformed/missing/out-of-bound usage, late result and any unknown result retain reservation and stop the batch. No retry, fallback, top-up or epoch reset. Historical usage is evidence; reservation stays conservative.

## HTTPS and credentials

Use a chat-only HTTPS implementation with fixed endpoint, certificate/hostname verification, bounded response, timeouts, redirects disabled and no retries. Authority and credential generation must remain valid at final handoff; network I/O cannot block the UI thread or be placed outside a proven authority handoff boundary. Temporary key entry must occur locally inside the Service process, use masked input with no restoration/clipboard/logging/persistence, expose only opaque handle/generation, and disappear on process death. Do not add a network-capable fixture to the no-network build.

## Validation and stop condition

Offline exact targets cover full-history cost, insufficient balance, third attempt, changed epoch/restart, pre/post-handoff cancellation, late success, crash/unknown, duplicate identity and missing token/currency proof. Preserve all existing synthetic evidence checks; live token evidence requires a distinct version rather than relaxing byte-equality guards. I04 and containing suites are forbidden. After review and checks, the user safely enters credentials; only then two sequential actual ordinary Send actions, second dependent on first, with sanitized wire/answer/usage/cost evidence. If a proof, shared-file authority, device path or secure handover is missing, report incomplete and zero calls; never substitute a standalone runner.

## Independent review disposition

The independent critic rejected this as a complete live integration plan. It approved only the bounded independent configuration/pricing/batch-ledger/token-proof components and their offline checks. No permission to send follows from that component review. Shared owner/ABI edits and the network adapter are not implemented under this draft.

Required design repairs before integration:

* Live evidence needs a separate `ordinary-send-live-v1` format in `ordinary_chat.rs`, with explicit live usage rules in receipt/restore/history. The current five-field body and synthetic checks must remain exact for legacy evidence. `OrdinaryChatContext.kt` needs an explicit live six-field body including `thinking`, rather than widening the existing closed set.
* Existing `ServiceAdmissionAuthority.State` holds immutable snapshots behind one guard. A real send needs a guarded one-shot handoff that durably records the fixed batch reservation and attempt before any possible outflow, then revalidates capability, exact history and payload. The fake callback cannot simply be replaced with blocking HTTPS. Reading the response must not hold the owner monitor or authority guard. Post-handoff cancellation must reach the batch stop latch; an ABI/callback acknowledgement extension may be needed and must be coordinated first. The current API does not establish this acknowledgement.
* A dedicated live build must declare INTERNET and a non-exported credential-entry Activity in `:agent`; its Application/store/authority must be the same objects used by AgentRuntimeService. This affects app Gradle, live manifest and a dedicated Application. A masked UI-process field cannot configure Service-process memory. Save-state, clipboard, debug logging and persistent key configuration are forbidden. No such entry currently exists or is offered for key entry.
* The token proof must bind exact payload bytes, model, current tokenizer/template provenance and a conservative input bound; it must not be supplied by chat/UI. A default-denying proof-verifier seam is preparation, not a verified tokenizer implementation. Whole-context worst-case reservation exceeds this run's 1 CNY ceiling and cannot substitute for the missing proof.

The new isolated budget component uses one stable directory and fixed batch identity, independent of epochs. Its state file is protected by an exclusive process file lock. Provisioning is separate from reopen, and existing or corrupt state must not be overwritten. It persists a pending reservation before returning a handoff permit, uses conservative no-refund accounting, and reopens pending as unknown/stopped. Success with validated usage records evidence without reducing the reserved maximum. Unknown or cancellation permanently stops the batch, including a late success after stop. File and directory durability and actual multi-process exclusion require offline verification.

Exact regression target (no I04): `RUSTFLAGS='-l sqlite3' CARGO_TARGET_DIR=/tmp/muyon-chat-live-canary-target cargo test --offline --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test ordinary_chat_controller -- --test-threads=1`. The sqlite link flag is a macOS host prerequisite, not a runtime source change. The new Kotlin component has a dedicated JVM-only runner; it is not an Android/Service/HTTPS acceptance test.
