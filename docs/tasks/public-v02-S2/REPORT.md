# S2 partial pure validation and original-query candidate

2026-10-23 UTC. Partial S2 only, not a runnable Skill service. Same approved plan, base and exact C1/C2/C3 dependency history as [S1](../public-v02-S1/IMPLEMENTATION.md).

## Scope and TDD

Own `services/skill_runtime.rs` and `tests/public_skill_runtime.rs`. Public types come from real C1 and original contracts/documents; HostCommandPort/OriginalLookup come from C2. No copied JobSnapshot, Operation variant or RunLedger. Input schemas mirror only the two original bounded list operations; document_refs are refused because neither accepts document/body context.

`inspect_requirements` reports unique required, present required and missing capabilities. `validate_inputs` explicitly checks known schema/digest, exact limit/offset fields and integer bounds. `decide_step` first checks exact scope/account/generation, binding revision and SkillRef, then enabled state and candidate metadata; requested actions must all belong to host ∩ plugin ∩ descriptor.required ∩ connection. Empty connection capability set is not an exemption. Any disallowed action rejects the entire request; no partial filtering followed by success.

Ruling: because D2 JobSnapshot and original workflow ownership handoff are absent, get_run_snapshot/request_run and production cancellation/dispatch are not implemented. Added only a narrow `lookup_original_run` adapter to C2 lookup_original, preserving supplied original identity and mapping unproven host errors to C2 Unknown/AfterLookup. The trusted caller must authorize current original scope first. Cost: no production run snapshot or execution API is delivered.

The approved decide_step signature has eight explicit arguments; a local Clippy too_many_arguments allowance documents exactly this interface. It does not relax checks globally. The runtime test path-includes skills.rs with test-only dead_code allowance because catalog functions are exercised by the separate S1 integration target. Neither allowance suppresses production authorization or unsafe-code warnings.

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skill_runtime
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills --test public_skill_runtime --test agent_workflow --test agent_tools
```

- RED source `06cf7218a86984bec320c12e27c59b8ee633afa7`: compile-ready unavailable stubs; actual exit101, 0 passed/4 failed (empty requirement view, denied valid decision, unavailable original lookup).
- GREEN source `ea4e3d785658cee6c9aa4eec118ffffbc13bb9b2`: 4 passed/0 failed; focused four-target regression 32 passed/0 failed (4 S1, 4 S2, 17 original workflow, 7 original tools).

Tests exercise malicious extra permission fields and requested write rejection, all four-set restrictions, cross-plugin empty grant, account/project/workspace/generation changes, expected binding revision/digest changes, disable and per-step revoke, precise built-in arguments, wrong/unknown schema digest. FakeOwner lookup returns C2-decoded Unknown three times for simulated timeout/UI-close/restart labels; lookup count3, prepare/confirm counts0, unchanged original identity. Labels do not constitute real timeout or process-restart evidence. Existing workflow tests remain original-owner synthetic regressions; they do not prove new Skills wiring.

## Pending work and boundaries

Module registration is Contracts-owned and remains unmodified here. Original workflow handoff is absent; no workflow/UI/FFI edits. JobSnapshot/get_run_snapshot, original cancellation integration, durable prepared invalidation across real binding changes, connection grant-generation invalidation and new requestRun Operation binding are NOT_IMPLEMENTED/NOT_RUN. Pure checks assume the trusted host supplies fresh sets; callers cannot use these DTOs as authority tokens. Dispatch must recheck atomically at use under the original owner.

No real model/provider, Connector, paid call, credentials, Skill script/parser, new dependencies, second ledger or new storage. Unknown results remain original identity; no generic retry or resubmission. S3 parser gate remains separate and NOT_STARTED. Exact fixture/hash/log evidence for shared tests and final author/independent checks will be appended before delivery.

## Captured evidence hashes

Raw logs/metadata are outside git in `/tmp/muyon-skills-v02-evidence/<name>.*`.

| Name | Exit | stdout SHA256 | stderr SHA256 |
| --- | --- | --- | --- |
| s2-red | 101 | `947a18b4dd95d0b55f35213d700100d21beec19f463fe4f3e058312a19df6fa9` | `5d4f09c9c37256cebed31207107cf49be829660c1c3211dbb09a7658eac90286` |
| s2-green | 0 | `dbf0971a21a5f36327d8f47517ff542ae3a1effdc373c3dba214f908e5242ff6` | `5b6070bc639536f98c706f1705b89903237341125b1db9b14c388d3ecdcfa25e` |
| s2-regression | 0 | `2adee5f7b0a346104d3e14a847594a44d73ff50612cfebd292d225418ef80380` | `13054298453a664a309f7079be699810a00d1e577ac6c34ff4b8e7cc7137c726` |

## Final fixed-source checks and independent review

Source `ea4e3d785658cee6c9aa4eec118ffffbc13bb9b2` (later commits change reports only). Full `cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1`: exit0, 627 passed/0 failed/0 ignored, 38 test-binary result groups, 2026-10-23 05:36:57–05:38:45 UTC. Counts include existing cross-target coverage, not 627 distinct new scenarios. Expected fault-test stderr includes FileTooLarge; process exits0. Core all-target strict Clippy `cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings`: exit0. Rust 1.93.1 and locked cached dependencies as in the toolchain restoration report; Cargo.lock unchanged.

Independent reviewer `/root/review_skills_implementation` reviewed exactly `7f9ebf3fe1bc972597e1a97a73851afcd264a8ce..ea4e3d785658cee6c9aa4eec118ffffbc13bb9b2`, fixed plan/spec, all five owned code/test/fixture files and raw RED evidence. Independently reran public_skills/public_skill_runtime/agent_workflow/agent_tools offline locked: exit0, 32 passed/0 failed. Source hashes match fixture references; diff whitespace check passed. Reviewer reused local target cache, did not rerun full workspace, and did not edit sources/install/fetch. Verdict: approve bounded S1/partial S2 candidate handoff, not production integration or develop merge. No Critical/Important finding.

Deferred Minor: original-query fake owner always returns decoded Unknown. Direct tests of host error remapping, mismatched NotSubmitted identity, malformed ExecutionResult and wrong receipt identity are absent; reviewer found conservative code branches, but those guarantees remain statically reviewed rather than independently exercised. Add table-driven cases before production wiring. No claim these paths were tested.

Review rulings on all declined areas:

- S3 paths/symlinks/undeclared-resource handling remains a separate unimplemented parser/host resource gate; no arbitrary resources are loaded here. Cost: no package parsing or execution acceptance.
- Original-owner draining, cancellation and atomic dispatch revalidation remain the original owner's future wiring work; pure decisions/lookup do not establish it. Cost: no production lifecycle/recovery acceptance.
- Real current-account authorization must precede host port use; decoded scope snapshots are not credentials. Cost: no account-level production authority claim.
- D2 JobSnapshot, get_run_snapshot and exact request_run Operation/binding/input contract await their real owner handoff. Cost: no run API or snapshot implementation, no substitute execution ledger.
- Catalog persistence transition enforcement stays with the original command owner, separate from pure CAS candidates. Cost: no durable register/bind/enable/unbind management implementation.

This candidate was not merged to main/develop, force-pushed, deployed or used for external effects. No rejected or uncertain operations. Disable rollback removes only future entry points; preserve original ledger, history and unresolved IntentId for owner lookup. B remains sole integrator.

| Final run | stdout SHA256 | stderr SHA256 |
| --- | --- | --- |
| skills-clippy | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `9fe22c0af2f8ce426e8d91b95275d58f1e77c1157a6f5244f08c3899281fdf06` |
| skills-workspace | `9aa28fd1e1bdbe3dfd6e1d9e45a18361ad8a17fc1f760ea1aeb7a99166f8d165` | `095a61795efd6f2466aa5f7ed271decf14d118b1370b0ed90c96cfd6dc9b3299` |

Additional final checks on unchanged source: entire workspace/all-target strict Clippy (`cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings`) exit0; rustfmt --edition 2021 --check on four owned source/test files exit0; shared registration, workflow and Cargo.lock match the fixed Contracts dependency byte-for-byte.

| Additional run | stdout SHA256 | stderr SHA256 |
| --- | --- | --- |
| skills-fmt | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| skills-workspace-clippy | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `dfb22db2d8c8f2ae6afd481c98b3253a83b65b970f8447223e5afd6927812180` |
