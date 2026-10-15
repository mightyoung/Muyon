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
