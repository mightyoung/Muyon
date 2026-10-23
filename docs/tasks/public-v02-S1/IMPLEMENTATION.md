# S1 pure catalog candidate — 2026-10-23

## Fixed dependencies and scope

Approved plan/spec source `64900d4a6a46a9ef2919bcf922fb059413b1ce82`. Refreshed develop remains `fd26dcdabcdac996bc2881e8141cac2b519966fc`. Parent explicitly delivered C1 `6e7f774b1559a0a9693eeb195ba13c9ded561993`, C2 `b626c18a5dff184519e59bb866e5ed37362ac84e`, C3 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`, evidence head `4d49a580cb518d9b0b80c9df3df1ff564194a639`. Full sources, three fixtures and C1/C2/C3 reports were read. This candidate dependency is not merged develop. Local merge `7f9ebf3fe1bc972597e1a97a73851afcd264a8ce` consumes its exact history in the isolated Skills branch; no cherry-picked or rewritten common types. C1 fixture hashes match its reports.

S1 own files: `crates/muyon-core/src/services/skills.rs`, `crates/muyon-core/tests/public_skills.rs`, `docs/contracts/public-services-v02/fixtures/skills.json`. Digest/ScopeRef/ServiceError are C1 types and Revision is original contract::Revision. Own source commit `6253b0f2951cf7200cfade66b67db6f9d91a2add`.

Pure immutable snapshots declare the two compiled built-ins, exact resource SHA256, plugin ownership, schema declarations, capability requirements and resources. No directory scanning, body/context projection, database access, invocation port or runnable command. Getters return borrowed metadata; candidate CAS checks expected/current/next revision, stable binding identity/scope/Bot and exact new SkillRef shape. It does not persist, grant permission or resolve authority. Replacement reference must separately resolve in the reviewed catalog before a future original-owner command persists it. No register/bind/enable/unbind production command is opened.

## TDD and actual validation

All commands load `/workspace/skills-rust-tools/env.sh`; raw bytes and command metadata are outside git at `/tmp/muyon-skills-v02-evidence/`.

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills --test agent_workflow
```

- `fbe34a94283713a95858cc6e9bbfc3f36269c5ae`: test/stub source. First test attempt failed compilation because locked sha2 0.11 digest bytes do not implement LowerHex. This is NOT behavior RED; test helper fixed without changing assertions.
- `355612929f93010ee7a26dbf8bb43f97d6ed0d5d`: compile-ready unavailable stubs, actual behavior RED, exit101, 0 passed/4 failed (missing built-in catalog and catalog validation).
- `874a4f13d79174920a564d0292865fa9f9e650e8`: compiled descriptions present; remaining lookup/list/CAS stubs produce actual behavior RED, exit101, 0 passed/4 failed, including wrong CAS error and unavailable exact version lookup.
- `6253b0f2951cf7200cfade66b67db6f9d91a2add`: S1 implementation plus exact fixture/built-in comparison. GREEN: 4 passed/0 failed. Regression with original agent_workflow: 21 passed/0 failed total.

Cases cover coexistence of exact versions, wrong digest and duplicate immutable versions, wrong expected revision, identity/scope/Bot transplantation and skipped revision rejection, candidate disable without modifying original, missing bindings/descriptors, strict fixture roundtrip and unknown permission fields. The no-side-effect claim is based on APIs having no owner/invocation context and the reviewed implementation using compiled bytes/pure values; no unrelated fake counter is presented as evidence of invocation=0. Runtime dispatch after disable belongs to S2; S1's metadata success is not execution permission.

Skills fixture SHA256: `7acc6c66f41ab2b35709fdf93fc0b6677a3eeee35ad4f74d3b7f23b6ac367e63`.

## Explicit implementation rulings and costs

- Contracts retains exclusive shared module registration. Tests use `#[path]` to compile the owned real modules, with aliases to actual C1 imports. Cost: until Contracts registers modules, no public production library entry point is exposed.
- The planned `list_skills -> Vec` cannot report malformed catalogs. Added `validate_catalog` provides errors; invalid lists return empty and getters reject. Cost: callers must validate first to distinguish invalid from empty.
- P1 schemas are explicit list arguments mirroring original workflow bounds (`limit` integer1..50, `offset` integer0..10000); output declares object/records array, with no general schema interpreter. Both built-ins share this shape. Unknown schemas are capability_unavailable. These declarations do not prove runtime output conformance or grant additional fields/capabilities.
- Phase remains the existing C1 String diagnostic label `skill_validation`, not a new phase enum or trusted dispatch-stage proof. Money/Quantity and other pending exact choices are untouched.

## Integration handoff and limits

Registration request to Contracts owner: add `pub mod skills;` and, for the S2 pure candidate, `pub mod skill_runtime;` to services/mod.rs in its own reviewed serial commit. Skills did not edit services/mod.rs, core lib.rs or FFI lib.rs. Existing workflow.rs and UI Shell are unchanged. The dependency merge contains only Contracts-authored registration; it is not a Skills edit.

S2 partial scope and recovery limits: [../public-v02-S2/REPORT.md](../public-v02-S2/REPORT.md). Full workspace/strict checks and independent review will be recorded below before delivery. No fixture is real business content; tests are synthetic Rust/SQLite only. Production registration/dispatch, Android, device, real models/Connector effects, parser/scripts, unknown external effects, account-level host binding and full schema engine are NOT_RUN. S3 not started; engineering/evaluation gate remains.

## Captured evidence hashes

Raw logs/argv/exit/environment/UTC are outside git in `/tmp/muyon-skills-v02-evidence/<name>.*`.

| Name | Exit | stdout SHA256 | stderr SHA256 |
| --- | --- | --- | --- |
| s1-red | 101 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `3227205cabd0083b0412d26cc09aa7b2c996eb85d732843e04ef2be4252cb840` |
| s1-behavior-red | 101 | `29ac982522a2d8a4c8c790ff1d5215752707e3c7f0418857a9e21cd37b56fc7d` | `5b600444297471fe2c2b3e667b5e577ff4f590fa0937180bab76c07e76c002d5` |
| s1-lookup-cas-red | 101 | `634ecaa917cee3066f8fea98931e9605d596dd41258ff20f987e149d0c4b248a` | `b1f64ba2f2b957357345ef03574893fbca1133b74d7f0c5ff046c12ad2edd168` |
| s1-green | 0 | `f4063a8da4059fec79762c5f011add1efa03fff4d6834d868825c9850f18a906` | `9931cfb0cd6b27d219deb16e4e487b9cd101d53d7410e1ea3feda3a9e3d44788` |
| s1-regression | 0 | `835c49adaec091e7c662be5c839b5d435eb1449a148e0d3d8c1bff7740498968` | `a381e109e363fe189d8f4ca90fd8484d0ae52bfe671f30669ffd68cdaabcce79` |

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
