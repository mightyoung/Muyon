# Rust product host seam — P1

Scope: `core/` and this task note. Contract: `HOST-CONTRACT.md`; base
`3836149416020a0ac58f9e7ca788c20e66688e0e`. No product migration, model, credential,
network, business write or device evidence is claimed.

## Compiling stub checkpoint

The explicit `host-session --root ABS [--idle-ms N] [--total-ms N]` command accepts
a bounded framed start and returns a protocol terminal with status `failed`,
reason `host_not_implemented`, zero turns/invocations and no result. This is an
intentional unavailable backend, with no host loop or callbacks implemented yet.
Existing fixture/SSE entry points, store encodings and inverse sites are retained.

The new `host_roundtrip_pairs_the_original_projected_result_in_turn_two` test was
written before the stub. It uses the actual compiled binary and a synthetic host
protocol peer, expecting the inquiry call, separate core invocation, original
paired projected metadata and result-dependent second-turn answer. The stub
instead produces a valid failure terminal, so the expected RED is the assertion
`HOST_ROUNDTRIP_REQUIRES_REAL_AGENT_CALLBACK`, not a build or transport failure.
This unit is not the independent real-PersonalAgent/registry integration proof.

Local Rust execution is **NOT_RUN** because cargo/rustc are absent. The checkpoint
requires actual compiling semantic RED in GitHub CI before implementation starts.
Deadlines, lifecycle, authorization/tool ports and common-loop implementation
remain intentionally incomplete at this checkpoint. No local PASS is claimed.

## Implementation checkpoint (awaiting CI)

Root verified the immutable stub at CI38684187394, exact combination23824d76:
compilation succeeded and the named roundtrip failed the intended behavioral
assertion (terminal versus model_request), without timeout. Author checkpoint
`aaeca5a1ab37be8cea797521f98349bf866cd421` remains in history.

The implementation now routes legacy `run_with_provider` and the injected host
`run_with_ports` through one `Agent::drive` loop. Host provider, authorization and
tool callback ports are separate from the unchanged scripted/SSE paths. Native
host calls have typed JSON arguments, independent core invocation identity,
exact callback correlation and field-by-field result projection. Host attempts
write only their separate `host.db` journal under root/task/attempt, reject reuse,
and never write fixture effects or reopen an attempt for redispatch.

Framing uses nonblocking private pipes, strict existing JSON parsing, one pending
callback, bounded polling, idle/total deadlines and aggregate byte admission.
Time/byte capacity is reserved for terminal delivery within the original limits.
Cancel/close after invoke drains only the pending matching result; accepted
metadata and its opaque receipt reference survive, with no next model callback.

Added focused protocol tests cover denial/confirmation, forged approval, wrong
callback/numeric type, cancellation/close before and after invoke, missing result,
silent callback timeout, raw-record projection rejection and a second tool call.
These are synthetic protocol peer tests; product facade/registry acceptance is
the independent checker owner's work. Local compilation/runtime remain NOT_RUN.
Static diff validation and all18 original mutation replacement sites were checked;
the original53 tests and17 mutants have not been executed locally.
