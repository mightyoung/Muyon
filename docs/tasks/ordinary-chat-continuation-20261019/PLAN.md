# Ordinary chat continuation implementation plan

**Goal:** Prove two explicit ordinary Sends in the original conversation through the same private Service, Rust Agent and socket-free provider, then prove a budget refusal without another exchange.

**Architecture:** Retain the existing single-message intent and latest-request conversation projection. Increase only the compile-time synthetic fixture ceiling to two calls. Keep failure status and raw reason intact; connect a controlled budget explanation to the existing result area and expose the existing read-only query action for that failure.

**Spec:** User delegation; ../ordinary-chat-wiring-20261018/CONTRACT.md and RECREATION-RESULTS.md. The user has already requested execution, sole writer and independent review; no additional design approval is needed.

## Classification and constraints

- Settled: one checked current user message per call, no implicit history/context; explicit original-request query after unknown; default unconfigured denial; no automatic resend/refund.
- Implemented: backend handles distinct requests in the same conversation. Rust has weak two-success/quota assertions. Android fixture currently allows only one call.
- Missing: device second-success evidence, exact budget-code and failed-state/identity preservation assertions, useful budget guidance/query access.
- No new demonstration route or visual redesign. No history schema or real model/currency configuration.
- Never execute I04 or containing suites, retrieve denied old logs, read .env/keys, configure credentials, merge main/develop, deploy or delete branches. PR86/dependencies HOLD.

## Execution

- [ ] Add pure policy assertions for controlled budget guidance, label and read-only query availability; run a standalone policy probe RED before changing policy.
- [ ] Implement those presentation helpers and wire the existing result/query control. Preserve failed status, raw reason and Send gating.
- [ ] Change compile-time quota to calls=2, tokens=16384, synthetic micros=2; per-call budget remains 8192/1. Strengthen the existing Compose test: recreation unknown/nonblank disabled → explicit original query → second success with distinct request/run/receipt, same conversation/Service PID/epoch, attempts=2 → third failed with exact budget code/no answer/receipt, then explicit query preserving identity/cursor/status and attempts=2. Original Rust and owner paths stay in use.
- [ ] Strengthen only the named Rust integration target with exact event/payload/identity and quota-failure assertions, including duplicate/read-only no-exchange checks.
- [ ] Independent source and transitive execution graph review at immutable source SHA. Only standalone Kotlin policy probe, named ordinary_chat_controller target, build-only binding/ABI/package and two named Android test classes are permitted. No aggregate suite.
- [ ] Push isolated lab branch with dedicated workflow branch selector, create draft stacking PR95; follow its exact-source CI to terminal, retain fresh evidence and short handoff. Recheck remote branch conflict before push.

## Review focus

- Unknown after lease loss never enables Send and never increments durable attempts.
- A fresh request in the same conversation receives fresh request/run/receipt and exact checked text.
- Budget rejection remains failed with exact reason; no answer or receipt from a prior request leaks into it.
- Repeated read-only lookup preserves the failed request identities/cursor and never consumes budget.
- Current-message-only semantics and latest-request projection are reported honestly; no multi-turn model context is claimed.
