# Independent source repair review

Immutable reviewed source: `c76687fd`, repair delta from `802844fc`. Inspection only: no tests, builds, binding generation, network, emulator, credentials, historical database reopen or implementation writes. The only reviewer write is this report.

## Ruling

The two original source findings are repaired for the explicitly authorized fresh-session, fresh-schema offline path. No additional concrete source blocker was found for that bounded acceptance path. This does not establish Android buildability or executed end-to-end success; generated bindings, the immutable execution graph and actual test outcomes retain their separate review/evidence requirements.

### Credential-bearing input journal

`AgentChatReadSession.submit()` now calls `ordinaryTextSupported()` before creating/persisting the request record or invoking Binder. Rejection produces an empty-text snapshot with a generic reason. `update()` independently omits unsupported text from the persisted record. Consequently the previously identified credential-hit input cannot reach the initial identity-journal write through a fresh ordinary submission. Native input checks remain present and authoritative; the local check does not grant model/outbound permission.

The initializer still restores existing v2 records using generic text bounds rather than the supported ordinary-text check. Therefore this repair must not be described as scrubbing or safely migrating an existing journal written by the earlier source. That limitation does not block this round's explicitly fresh-root/new-schema acceptance; no old journal was inspected, reopened or migrated during this review.

### Frozen evidence recovery and disclosure

`ordinary_chat::receipt()` now requires closed top-level/context/authority/provider/wire/message/usage schemas, mandatory supported rule/input/counting versions, provider identities and HTTPS endpoint, authority/provider owner and policy/grant agreement, positive credential generation and call limits. It checks the exact one-user-message body, n=1, no streaming, output cap <=1024, full serialized body plus output within the frozen total, reported output within the wire cap, and checked reported total usage within the frozen call bound. Missing endpoint and excessive output usage therefore reach rejection predicates before completed answer disclosure.

`restore()` additionally verifies `input_ref == run_id:request_id` and actual durable task/attempt/conversation. It neither opens a core task nor sends/retries transport. The call budget now travels with ProviderAdmission and is persisted with the provider evidence, closing the previously absent total-bound evidence.

The new negative cases in the same explicit integration target deliberately replace output usage with 999999 or remove endpoint and require DISCLOSURE_UNAVAILABLE without answer text. These cases inspect new temporary roots and query the existing controller; source inspection found no old task.db reopen, HTTP, script/subprocess or aggregate runner in them. They exercise disclosure validation, not process-restart recovery, and must not be reported as executed here.

### Context and capability ownership

`prepare_chat()` now calls the owner context-binding callback while the reservation remains held. Kotlin persists context and capability identity/generation in unique `chat_contexts`, after exact held reservation/request/binding/scope/payload checks. Commit requires that pinned capability to equal the current owner capability. Exchange joins the pin to the admitted reservation, compares exact context/capability bytes plus current binding/scope/payload, then records a unique attempt before invoking the fake response. Rebinding fails rather than replacing the first row. The callback defaults deny; it introduces no second driver, authority or secret-value operation.

## Retained evidence limits

The expanded source includes output-signal rejection, post-commit handle rotation, quota exhaustion and absent/revoked owner cases. Their presence does not prove runtime success. The native fixture is in memory and is not a substitute for the concrete Android SQLite owner's execution evidence. Source review does not prove all mode/grant/profile/payload drift cases, persistence-failure behavior, process restart, physical devices or foreign constructor/destructor exceptions.

Production transport still denies non-synthetic authority. Real model ID, currency, fee ceiling and real price/usage proof remain outside this offline acceptance. No real DeepSeek completion is claimed. I04 and implicit suites remain prohibited; no prior 403 was retried, PR90/Dart8/HOLDs were unchanged. Reviewer writer stopped after this file.
