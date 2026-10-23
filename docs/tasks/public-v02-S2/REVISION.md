# Skills candidate follow-up — checked listing and original-query fault coverage

2026-10-23 UTC. Parent requested the previous Minor be covered and malformed catalogs be distinguishable from real empty catalogs. This is a pure lower-level candidate revision; it is not a completed catalog service or production runtime.

## Fixed source and interface change for Contracts

Refreshed develop still `fd26dcdabcdac996bc2881e8141cac2b519966fc`; consumed fixed Contracts dependency remains `4d49a580cb518d9b0b80c9df3df1ff564194a639` (candidate, not merged develop). Previous Skills candidate `5fa37fb6a72757102b6de4f983df67a662df18bc`; new test commit `e47bffdd0cfe558e52214ef73f8110fb8a6c407d`; fixed source `047ab7869ec280020588710c2564f883786f0b7f`.

Contracts registration review must use the revised Skills-owned signature:

```rust
fn list_skills(snapshot: &SkillRegistrySnapshot)
    -> Result<Vec<SkillRef>, ServiceError>;
```

`list_skills` now calls validate_catalog internally: real empty metadata returns Ok([]); duplicate/invalid metadata or unsupported schema returns Err with its actual reason. No caller must remember an independent validation step and no lossy Vec-only public listing remains. This intentionally supersedes the earlier planned Vec return and the earlier empty-on-error ruling, pursuant to the parent's boundary request. Cost: source-level change for any consumer of that previous candidate; repository search found only the owned integration tests, and those now handle Result. No common DTO, serialized fixture or other owner's file changes. Public consumers cannot discard the Result accidentally without Rust's unused-result warning; callers can still deliberately ignore an error as with any Result API.

Module registration remains requested from Contracts only (`pub mod skills;`, `pub mod skill_runtime;`), never edited here. Registration must not expose these helpers as an authorized service or dispatch endpoint. Both modules are still unregistered in this branch; tests compile the real module files using test-local paths and actual common types.

## Direct regression coverage and observed RED/GREEN

Using `/workspace/skills-rust-tools/env.sh` and raw evidence root `/tmp/muyon-skills-v02-evidence/`:

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills --test public_skill_runtime
```

At e47bffdd: runtime 9 passed, catalog4 passed/1 failed. `malformed_catalog_is_distinct_from_a_valid_empty_catalog` actually failed because both lists were []; exit101. At fixed source047ab786: runtime9/catalog5 all passed, exit0; additionally asserts Ok(empty), duplicate InvalidArgument and unknown-schema CapabilityUnavailable directly. No compile failure is counted as RED.

The four previously untested original-query failure branches now have separate direct tests:

| Scenario | Required observation |
| --- | --- |
| Host Err claims NotStarted/Never and a foreign identity | Returned UnknownOutcome/Unknown/AfterLookup with requested original IntentId, not foreign metadata |
| NotSubmitted carries another identity | Error with the original requested identity; never a new editable request |
| Committed ExecutionResult has no receipt | Shape is explicitly invalid and maps to original unknown |
| Otherwise shape-valid execution carries another receipt intent | Shape validation first succeeds; separate identity guard then maps to original unknown |

Every test asserts one lookup of the requested identity and unchanged fake reply; prepare/confirm/cancel panic if called. An additional positive control preserves matching NotSubmitted identity. The fake uses actual C2 OriginalLookup and original ExecutionResult/Receipt, not parallel definitions.

These query tests passed the existing defensive runtime code immediately; no new query production fix or original bug reproduction is claimed. To verify sensitivity, four separate temporary mutations removed/altered the corresponding guard. Each targeted command below compiled, ran one test and failed its behavior assertion (exit101). Original runtime source was restored byte-for-byte in a finally block; its SHA256 remains `13154b0a0ac2edbc929ad1f681e3fd5202ba5fdfe45a402103457e37360005ef`. These mutations were uncommitted source states, not immutable git commits and not production patches.

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skill_runtime <test_name> -- --exact
```

Test names: `query_host_error_retains_requested_original_and_unknown_effect`, `query_foreign_not_submitted_identity_remains_unknown`, `query_malformed_execution_remains_unknown`, `query_valid_execution_with_foreign_receipt_identity_remains_unknown`. Per-mutation source byte hashes and restoration fact are in query-mutation-manifest.json outside git. After restoration, public_skills/public_skill_runtime/agent_workflow/agent_tools passed38/0 (5+9+17+7). This is synthetic helper/host testing, not real timeouts, restart, cancellation or side effects.

## Exact remaining S2 implementation and verification boundaries

| Remaining item | Missing prerequisite / actual boundary |
| --- | --- |
| SkillRunSnapshot / get_run_snapshot | D2 JobSnapshot not delivered; no substitute Job or snapshot DTO created. |
| request_run | Exact original Operation variant must bind SkillRef, binding revision and input digest under original owner/Contracts review; no variant or requestRun adapter implemented. |
| Production HostCommandPort, scope/account authorization and FFI | C2 provides a trait/projections only. The lookup helper requires a trusted host to authorize current original scope; fake-owner tests do not enforce real account permissions. |
| Original workflow/RunLedger wiring | Original workflow owner has not handed over wiring; no workflow edits or new execution ledger. |
| Durable prepared invalidation and per-step dispatch | Pure functions reject stale scope/revision/digest and revoked current sets. No persistent binding transition, real prepared-handle invalidation or atomic dispatch-time recheck is wired. |
| Cancellation, disable lifecycle and owner draining | Only disabled pure decisions and original lookup are tested. No new production cancel adapter, dispatched-task draining, late-result publication, restart or original cancellation integration. |
| Connector identity/auth generation/catalog changes | connection_allowed is only a host-resolved capability set. X2 identity/endpoint/grant-generation/catalog binding is not connected. |
| Production registry and module registration | Contracts-owned module declarations pending; S1 only reads candidate metadata and checks CAS. No persistent register/bind/enable/unbind command implemented. |
| Input/output validation breadth | Only two compiled list-input schemas validated; document_refs refused. Output schema is a declaration, not a full output validator or general JSON Schema engine. |

S3 parser/license/resource gate remains NOT_STARTED; no package loading, path/symlink validation, Skill script execution, real models/Connectors, paid effects or new dependencies. Existing Reader block unchanged. Money/Quantity/phase enum choices untouched. No production dispatch expansion, merge/deploy/force-push or rejected/uncertain operation.

## Final verification and independent review

At fixed source `047ab7869ec280020588710c2564f883786f0b7f` (later commits only reports), full workspace command below exited0: **633 passed/0 failed/0 ignored**, 38 test-binary result groups including zero-test binaries; 2026-10-23 05:46:15–05:47:44 UTC. Counts include existing overlap across targets, not 633 new cases. Expected FileTooLarge fault-test stderr is preserved; process exits0. Whole-workspace strict Clippy and rustfmt on all four owned files exited0. Cargo.lock, Skills fixture, runtime implementation, original workflow and shared registrations are byte-identical to the previous candidate.

```sh
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/skills.rs crates/muyon-core/src/services/skill_runtime.rs crates/muyon-core/tests/public_skills.rs crates/muyon-core/tests/public_skill_runtime.rs
```

Independent reviewer `/root/review_skills_implementation` reviewed the revised source/tests at047ab786, all call sites and the observed fault/mutation logs. Verdict: previous Minor resolved, no new findings; approved bounded pure candidate handoff only. Independently reran public_skills/public_skill_runtime/agent_workflow/agent_tools offline locked: exit0, **38 passed** (5+9+17+7). Confirmed Ok(empty) vs Err(malformed), genuine directory RED, immediate GREEN of the defensive query regression, all four mutation failures, restored runtime byte hash, and the source-owned candidate signature change. Did not modify/fetch/install or rerun the full workspace. Production registration/dispatch, real original owner lifecycle, D2/new Operation/workflow/X2 and S3 resource gates remain pending and unjudged; their exact remaining scope is the table above, not acceptance by omission.

Ruling: the prior empty-on-invalid Vec boundary is withdrawn. Result-returning checked listing is the only list API; source consumers must handle the type change. All remaining earlier scope rulings stand: pure metadata/CAS only, compiled schemas only, String phase is diagnostic only, original authorization/dispatch/cancel/persistence await their actual owners. No new deferred findings remain from this revision.

## Evidence summaries (no raw logs committed)

Raw metadata/argv/environment/UTC and byte-exact logs remain in `/tmp/muyon-skills-v02-evidence/`.

| Run | Exit | stdout SHA256 | stderr SHA256 |
| --- | --- | --- | --- |
| revision-boundary-red | 101 | `97976635b3f8cc877c855950bf8993b1c139d06240c4184fc8c4ecc5b14bedbc` | `a5d49d54a0b5a85627bb3ed458f0ed4a14e77994bafd8a1e2ad7acee6bec0be6` |
| revision-boundary-green | 0 | `d307d0455ba2fb6379311ecc1e7776491eef1431e9e0a4af035b50262b5d7324` | `dde65e56c4d2e03252f8154d7eb9f248d2cda137408fec85be0e6987d23a54d5` |
| query-mutant-host-error | 101 | `7f289e8e475a4f13af1bb65c8c00c5ca13b800426cca852f2a13b3fab4c72f18` | `13d31f69d52585c1bd3af32f21da04130c4cf33468f745f560878ee40092a2d5` |
| query-mutant-foreign-not-submitted | 101 | `56bcc42adbf2436b1d0da249ccaa025c1eb00d58b8b154a3964b27fe3d1abe7b` | `52bab3e4984ea4102fa794d0ccd6cde6d2da913caded424dfd8d05e07ef22824` |
| query-mutant-execution-shape | 101 | `c7e5a50c99215de97c6c1e6198a03ff18d56d2818cb6e8fd61b7d1c71e415f2c` | `59374d26f75f40ff18e3a4acb5b098238e62cd7cabcb0dde290efa7bd23623e7` |
| query-mutant-foreign-receipt | 101 | `ce120c2f3af6b41b0159ca3a1b35a13bfcc4af862ca3aca953b3602783a13889` | `8a1998cb29b8ac0ab9a65b5f6ae233a124c80368660c16adc0606fa13e4e621e` |
| revision-restored-focused | 0 | `b19cb3a75334a514527bcac6eee2d4c858aa3089a064edf6acb9e3e87a3e7635` | `ae731f71b08074aed31861c0faccef5cbcb36a50e9f4b5639bcf6db85c276eb2` |
| revision-workspace | 0 | `a675af5d1568542182245eda6c664990cff29214ab6f9b37a8dec9f16be26b21` | `b742f7baba39b87088f1d1c16e3100c95327ace51853f56679facd63aab60fa3` |
| revision-clippy | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e7894fb0b9b8294a8e507ead342dfc21bea5c74cbc8eacf0efdf5f3a65cfa5dd` |
| revision-fmt | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

Mutation source-byte manifest SHA256: `9315f0b8e2b1cde57cf936bba8b35931dbe9b20c914a80df28f65cce2c6b18f2`. All mutations were temporary and restored; they are not alternate product candidates.
