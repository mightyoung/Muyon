# Independent native slice review

Immutable source: `02d0da9a` (commit `feat: route ordinary text through existing Rust Agent with frozen offline admission`). Uncommitted bridge changes are excluded. Read-only review; no test, build, generation, network or credential operation performed.

## Execution ruling

Approved to run only this target against the reviewed source, using fresh temporary roots as coded:

```sh
cargo test --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test ordinary_chat_controller -- --test-threads=1
```

The prior manifest/path-dependency graph remains unchanged. The only test edit adds explicit generation to the fake capability. Ordinary submission reaches the existing controller/start/worker, then the early ordinary-intent branch in supplier_business::execute. That branch creates State::runtime and invokes the same Agent::run_with_runtime_ports with ChatPorts. All persistence through those ports uses ordinary-agent-v1.db. Tool advertisement is empty; dispatch denies. No Agent::open, HTTP/socket, subprocess, recovery script, old task.db load or write is reached by this fresh-root target. Compiling other library modules does not execute their tests. Serial test execution fixes the process-wide Service occupancy conflict identified previously.

No I04 graph blocker was found. The allowance is for these new-root offline tests only, not another target, aggregate suite, historical-state reopen, Android/CI, or a later changed implementation graph.

## Findings before end-to-end completion claims

1. **Durable owner guarantees remain to be established by the bridge implementation.** Native exchange_chat simply delegates to the host, and the reviewed test Owner.exchange_chat checks revoked/opaque identity but does not atomically validate profile/policy/input context, claim an admission once, or durably record an attempted handoff. Its state is an in-memory Mutex. This is sufficient for controller routing tests, not evidence of the contract's same durable owner enforcement. Review the concrete bridge owner for exact admission/context equality, handle identity AND generation, current provider/authority, atomic attempted marker, duplicate rejection and consumed quota before treating the closed loop as meeting the frozen admission contract. The test sends once because controller state prevents reentry; it does not prove owner-level one-shot consumption.

2. **Frozen response evidence is incomplete at this layer.** ordinary-send-v1.db stores context, body, admission and answer, but not reported input/output usage or the provider profile/revisions/handle generation. ChatProvider validates usage and discards it, and does not implement Provider::reported_usage, so Agent state records None/None. A later durable owner ledger can bind profile/handle evidence by admission ID, but must also persist validated response usage and correlation; ensure that record is durable before completed answer/events are published. Do not describe the present file alone as all required frozen send evidence.

3. **Synthetic token-bound rationale needs tightening.** input_bound = text UTF-8 bytes + 512 ignores configurable model length and escaping/framing; it is not generally a bound for the exact serialized payload. Production is correctly denied here, so this cannot create real expense in this slice. For a testable synthetic proof, derive the bound from full frozen body bytes (with explicit declared synthetic counting semantics) or reject profiles outside a documented bound. Keep wire completion cap distinct from the total reservation, as the code now does. Runtime usage checks happen after attempted handoff and do not establish a pre-send upper bound by themselves.

4. **Coverage is narrower than the contract.** Three tests cover success/duplicate, disclosure revocation, credential input, prepare-to-commit generation change and lost reply. They do not test output credential rejection, grant/profile/mode/payload drift, budget exhaustion, generation change specifically after commit, final persistence failure, absent configuration, or independent owner attempted-send claim. These are not reasons to execute a broader suite; extend only this new-root target or add another separately reviewed named offline target. Its first test is controller coverage despite the name `compose_contract...`; Compose Send/same-conversation rendering still requires Android instrumentation evidence.

## Positive source checks

- Actual Agent task/attempt and exact single user message are checked before wire construction. The ordinary payload has no invented supplier fields; mixed/changed request payload conflicts are handled by existing controller checks.
- USER-TEXT-v1 direct input and MODEL-TEXT-v1 output both run the local bounded scanner. Unsupported controls/normalization and credential signals deny. Input authority preserves personal/commercial and inherited restriction facts; production authority is explicitly rejected.
- Generationless existence handles cannot prepare ordinary chat. Final admission still compares current binding and handle; post-admission errors settle outcome_unknown without refund/retry.
- The serial controller test observes ordinary-agent-v1.db and absence of task.db/native.db. Ordinary reply evidence preserves synthetic=true. Successful disclosure revalidates current input authority and correlates the local answer record.

I04 old task.db → HTTP → original-state reopen remains prohibited, including rewrites, split execution or suite indirection. Old 403 downloads, real model/key operations, HOLD removal, PR90/Dart8 changes and merges remain excluded. No runtime success or real DeepSeek success is asserted. Reviewer writer stopped after this file.
