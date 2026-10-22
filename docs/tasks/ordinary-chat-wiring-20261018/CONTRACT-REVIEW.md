# Independent contract review

Reviewed immutable source: `458ce2547e0e35980061fe5f7f5b0393c9988e34`, including `CONTRACT.md`, existing Service controller/provider/runtime, and fixed v1.3.2 payload classification patch. This is a design review, not implementation approval or execution evidence. No test, build, network request, branch operation, credential operation, or prior evidence download was performed.

## Decision

The selected slice is viable: separate ordinary-chat intent, existing private Service/controller/worker, the same `Agent::run_with_runtime_ports`, no tools, one durable provider owner, exact frozen bytes and synthetic one-shot transport. It can establish the requested Compose Send → Service → same Rust Agent → provider answer → same conversation offline loop. Default unconfigured production behavior and a compile-time synthetic installer are appropriate. It does not establish real DeepSeek operation or production credential readiness.

Implementation may proceed after incorporating the following design corrections. Test/build execution is not approved by this review: the contract names categories rather than an exact transitive execution graph. Review the concrete targets, build scripts, CI entry points and instrumentation selectors before running them.

## Blocking corrections

1. **Classify the returned answer before persistence and disclosure.** The transport paragraph only bounds plain answer/usage; that does not cover model-generated free text. Fixed v1.3.2 payload patch sections 2–3 explicitly require a registered rule for new model text and say classified sources do not prove credential checking of generated text. Define a versioned deterministic bounded-output rule, mark provenance `model_generated`, apply complete local credential/suspected-secret checking, and bind the exact returned bytes and current disclosure purpose. Unsupported/incomplete/suspect output must not enter answer events, ordinary ledger plaintext or diagnostics. A generic error and minimal evidence are sufficient. This requires no UI expansion or user confirmation.

2. **Bind inherited restrictions and submission provenance explicitly.** USER-TEXT-v1 requires absence of inherited bans/lost rights, not merely absence of a credential pattern. The proposed authority fields do not name that evidence. Add an owner-produced submission/input fact binding conversation, request, actual text digest/version, input event/reference, workspace/task/attempt, purpose, rule coverage/completeness, and any tracked source/use restrictions (or explicit absence for this fresh direct-input-only path). Fail closed if a known restricted source is present. UI supplies text/identity only; it cannot assert personal classification or unrestricted provenance. Classification and grant checks must use the same owner snapshot frozen for prepare/commit/send. No fabricated supplier source permission is necessary.

3. **Separate completion cap from total token/spend reservation.** Existing `CallBudget.max_tokens` is documented as a conservative total input/output bound, while the new wire `max_tokens` is an output cap. State both explicitly and verify `input_upper_bound + output_cap <= reserved_total_tokens`, checked arithmetic, one choice/call, and synthetic cost bound with named synthetic currency/price proof. Actual usage must fit the reservation; missing/malformed/excess usage cannot become successful terminal output. Unknown currency/model/real price proof continues to deny production. No real price or user ceiling may be invented.

4. **Supply the exact execution graph before executing.** Name the new integration target, its dependency/build-script graph, binding-generation command, offline APK variant, instrumentation class/method, and CI workflow/job invocations. Show that no aggregate test selector, existing recovery test, HTTP module execution or old database reopen path is reached. Mere absence of HTTP from the new test function is insufficient. New temporary roots and dedicated new schema must be mechanically selected.

## Required implementation checks

- Parent's follow-up clarification is acceptable: retaining the existing BusinessRead/controller container is not a second authority if the intent is an explicit variant and ordinary admission never constructs supplier key/revision, source binding, ToolRegistry receipt or supplier projection. Use a typed variant/closed envelope; reject unknown/mixed fields and intent confusion.
- Follow-up persistence choice (`ordinary-agent-v1`, no `Agent::open`, no old `task.db`) is compatible with the prohibited-path boundary. State encoding/checkpoint persistence may reuse the Agent API through no-tool AgentPorts without executing existing recovery scripts. Fresh session identity and preference namespace must prevent restoring old supplier records into the new intent.
- Opaque identity plus generation must be minted/checked by the existing durable owner. The existence sentinel cannot mint or satisfy it. Reserve, commit and send validate identical owner identity/profile/authority/input evidence; a generation change or revocation at any boundary denies. Callback transport must receive the committed capability only through that owner. No key value API is needed for this slice.
- Budget consumption, attempted marker and send claiming must be durable before handing bytes to the fake. A crash or write failure after possible handoff is outcome_unknown and remains consumed. Duplicate request/admission must not cause another exchange. Failed final persistence must never report completed or retry.
- Recheck current conversation/workspace/input-policy authority on both events and reconnect/snapshot disclosure. Cancellation before handoff prevents exchange; cancellation after handoff cannot refund or fabricate a provider result.
- Preserve an explicit synthetic marker in admission/answer evidence and UI contract. Existing `host_marker` treats any host as `synthetic=false`; the synthetic chat owner must not inherit that misleading behavior. Provider receipt correlates response/admission only and cannot imply paid/provider authenticity.
- Exact frozen body must be derived from the Agent request's actual user message/task/attempt, with equality checks against admitted input, rather than constructing an unrelated canned message beside the Agent loop. No automatic history/tool context inclusion.
- Auto and the other settled modes are host facts. FullAllow receives no new taint, destination, or reviewer confirmation gates. Model/outbound grants remain checked. Output filtering and missing-configuration denial are deterministic enforcement, not user approval flows.

## Useful scope reductions

Do not add HTTPS transport now. One typed fake exchange and one bounded answer path suffice. A single typed intent variant and one no-tool AgentPorts implementation can reuse the existing controller/Agent loop. Keep real configuration/credential setup unavailable and document required model ID, endpoint/profile proof, currency, accepted monetary ceiling, token pricing proof and authorized credential provider as remaining production prerequisites.

## Prohibited actions and evidence limits

I04 old script `task.db → HTTP → original state reopen` was denied: do not execute, rewrite, split, reroute, change environment, or indirectly execute it through a suite. Do not retry `job117717160270` or `service-durable-owner-evidence-39127896088-1` 403 downloads. No real provider traffic, key/.env reading, persistent credentials, fee, deployment, merge, force push, branch deletion, PR90/Dart8 change or HOLD removal is authorized. Seven physical device checks and real foreign constructor/destructor exceptions remain NOT_RUN. No runtime success is asserted here.

Reviewer writer stopped after this file.

## Clarification follow-up

Read-only reviewed follow-up contract at immutable `94906d2b` (full SHA available from repository). Its `Review clarifications` resolves blocking corrections 1 and 2 by requiring exact-input owner facts, inherited restrictions, preserved personal/commercial decisions and independent MODEL-TEXT-v1 before answer persistence/disclosure. It also names the initial `ordinary_chat_controller` target and defers Android/CI execution until concrete source review. The design is sufficient to begin implementation and write that new target, provided correction 3's total-token versus completion-cap distinction is implemented explicitly. No execution approval is implied: inspect the new target and transitive build graph at a fixed SHA first. Existing `host_marker` synthetic=false behavior remains an explicit implementation review item. No renewed user approval gate is introduced.

Reviewer writer stopped after this follow-up.
