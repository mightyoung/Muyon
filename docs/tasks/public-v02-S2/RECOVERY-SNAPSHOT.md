# Partial S2: original cancellation recovery and existing JobSnapshot projection

2026-10-23 UTC. This advances the approved plan's pure contract/fake-host portion only. It does not complete S2, supply a running Skill, or enable production dispatch.

## Fixed inputs, baseline and file ownership

- Approved Skill plan/spec/index read from `64900d4a6a46a9ef2919bcf922fb059413b1ce82`; no newer Skill plan exists in fetched develop. Also read the merged plan review/addendum, current Contracts interfaces, previous exact S2 checklist, Documents D1/D2 fixed reports and Contracts Skills registration report.
- Fetched reviewed develop `e943856e4b6e2de26a9c2c8e2fa0912713b590e5` (C1–C3 now actually merged), consumed on the isolated Skills branch through local merge `c44ab41a70f49bbc0f80e9e3d91ed5fde312adab`. Root Rust pin is 1.93.1, matching the installed authorized toolchain. No AGENTS.md in that tree; earlier workspace ancestor checks remain recorded.
- Documents owner declared its JobSnapshot delivery at branch head `6e79be12fb537655454e8f28265439da02550530`. Read its pipeline source/fixture and reports. That pipeline is byte-identical to the owner's fixed source `4bb47be7b3b34ff66da3b2e9bf740e924f56bd1e`. Consumed as an explicit typed candidate dependency through local merge `d3f65ee7b5f1f44f5f18aa3e188490576e7fed41`; it is not a develop baseline or a claim Documents is accepted by B. Original candidate history/files are preserved, not copied into alternate types.
- Documents pipeline.rs SHA256 `34bd53d3d3dcf1d02f046d404b2210f50eee024e1ec0cf098edf6c1536042e8f`; pipeline fixture `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2`.
- Own implementation changes only `crates/muyon-core/src/services/skill_runtime.rs` and `tests/public_skill_runtime.rs`. Shared registry, core lib.rs, FFI lib.rs, original contract.rs/workflow.rs and Cargo.lock match the fetched reviewed develop. All three Documents modules and fixture match its fixed dependency. No new dependency, migration, ledger or real external operation.

## Independent slices and actual RED/GREEN

| Slice | RED source / result | GREEN source / result |
| --- | --- | --- |
| Original cancellation/recovery | `574ac1d5528d99ae7519d7a1b9f940c6d09885ae`: compile-ready unavailable cancel adapter; runtime9 passed/5 failed, exit101. Failures show missing host cancel call and unavailable original facts. | `97a199c3d956eaecc7b8009daa4e61fa5b73cb88`: runtime14 passed/0 failed, exit0. This slice does not require Documents types. |
| Actual JobSnapshot projection | `669263f504ea09bf02419c3b0987b53007835648`: placeholder incorrectly projects UnknownOutcome as Accepted; runtime14 passed/2 failed, exit101 with exact state/equality assertions. This is an observed stub behavior, not an old production bug claim. | `4ce50debd39c6dc4ca39dae7f76fd113b5856047`: runtime16 passed/0 failed, exit0. Uses exact real Documents type and copies original facts. |

Commands, from repository root with `/workspace/skills-rust-tools/env.sh`:

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skill_runtime
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills --test public_skill_runtime --test public_pipeline --test agent_workflow --test agent_tools
```

Focused regression at final source4ce50: **50 passed/0 failed** (catalog5, runtime16, pipeline5, original workflow17, original tools7).

`cancel_original_run` invokes existing C2 HostCommandPort.cancel_original exactly once using the supplied original IntentId; lookup and cancel share shape/receipt-identity validation. It returns original ExecutionResult without inventing cancelled/stopped status. Pending/Unknown stay pending/unknown, terminal committed/rejected/cancelled facts stay intact. Host errors or malformed/foreign replies become C2 UnknownOutcome/Unknown/AfterLookup with requested original identity. No automatic lookup, prepare, confirm, replay or new intent follows an error.

Five new cancellation tests cover lookup→cancel→lookup of the same original; original pending/unknown/committed/cancelled/rejected projection; error remapping; malformed and foreign results; and lookup failure after unresolved cancellation. Synthetic owner records real trait invocations and panics on prepare/confirm. Native ProjectCreate appears only in a synthetic original-receipt fixture to verify C2 projection/binding semantics; it is never prepared or used as a Skill Operation.

`SkillRunSnapshot` wraps the real Documents JobSnapshot plus exact SkillRef/binding revision; it is Serialize/Clone, not authority. `get_run_snapshot` only clones supplied original facts. Two new tests preserve >JS-safe binding revision, job/intent identity, scope/generation, stage, attempt, unknown phase and coverage; mutating the copied projection does not alter the original. Explicit cancellation/recovery still targets original IntentId, not JobId. No source factory creates a new job or increments attempt.

These tests use an explicitly synthetic reference for an already existing document processing step. PipelineStage::Parse represents that document step only, never an entire supplier/paper Skill. The fixture is not installed as another executable Skill. Host authorization and snapshot provenance must precede projection; cloning caller-provided metadata supplies neither.

## Fixed-source verification and independent review

Final source `4ce50debd39c6dc4ca39dae7f76fd113b5856047`; later commits are reports only. Full workspace/all-target offline locked run: **652 passed/0 failed/0 ignored**, 40 test-binary result groups, UTC06:44:15–06:45:30. Counts include pre-existing cross-target overlap and the declared Documents candidate, not 652 new independent scenarios. Expected FileTooLarge fault stderr remains; process exit0. Strict whole-workspace Clippy and owned-file rustfmt exit0. No lockfile or toolchain update.

```sh
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/skill_runtime.rs crates/muyon-core/tests/public_skill_runtime.rs
```

Fresh independent reviewer `/root/review_s2_recovery_projection` read the fixed plan, own two-file diff, source dependencies, tests and recorded RED runs. Independently reran the five focused targets above offline locked: exit0, 50 passed. Verified exact dependency merge parent identities, pipeline bytes and fixture hashes; no Critical/Important/Minor findings. Verdict PASS for pure partial S2 only. Reviewer did not rerun full workspace, re-execute historical RED commits or approve forthcoming report/production wiring. No review action was blocked.

## Contracts / B handoff and exact remaining scope

Contracts remains the sole registrar. Ensure the exact Documents-owned `pipeline` module is exported together with `skills` / `skill_runtime` before compiling this revision as public library API. Owner registration must adapt test-local pipeline/skills/runtime imports to the same actual library symbols and verify nominal type identity; this branch deliberately does not edit shared registration or take over the separate registration candidate. The prior Skills registration report (`1e1c0ee22580971b188300dfdaf783847aa3ccfb` head) covers old source047ab786 only, not these new dependency edges. Public library registration verification of this revision is NOT_RUN here.

| S2 item | Current status / next dependency |
| --- | --- |
| Existing document-step SkillRunSnapshot/get_run_snapshot | Implemented pure clone against pinned D2 type; no production source/provider of authorized snapshots or whole-Skill job factory. |
| Original lookup and cancel adapters | Implemented/tested with fake host; no real HostCommandPort implementation, current account/scope authorization, process restore, transport, actual stop or rollback evidence. |
| request_run and exact original Operation | NOT_IMPLEMENTED. Original Operation still lacks Skill variant. Original core/contract owner plus Contracts must fix full binding representation and confirm-time checks; Skills will consume that type, not encode Skill JSON in ProjectCreate/ResearchImport. |
| Real workflow/RunLedger wiring | NOT_IMPLEMENTED; original owner handoff absent. Existing workflow tests are regressions, not new adapter wiring. |
| Durable prepared invalidation / per-step dispatch | NOT_IMPLEMENTED. Pure stale scope/revision/digest and capability-set rejection exists; no persistent registry transition, real prepared handle invalidation or atomic use-time dispatch recheck. |
| Disable/cancel/drain lifecycle | Only pure decisions and C2 result preservation tested; no real original owner draining, actual stop, late-result delivery or process/device recovery. |
| X2 connection identity/generation/catalog | NOT_CONNECTED; only trusted host-computed capability intersections, no current endpoint/account/grant-generation/catalog evidence. |
| Registry mutation and public registration | Owner registration/combined test work pending; no persistent register/bind/enable/unbind command or new authority. |
| Input/output breadth | Only approved two list-input shapes checked; document_refs refused. Output schema is declarative, no general schema interpreter. |

No Android/device/real model/paid effects/account access/production host dispatch or Skill scripts. S3 parser/license/resource gate remains NOT_STARTED; no parser or dependency installation. Reader block, unknown external effects and original ledger remain untouched. This slice supplies no new Operation, no dispatch and no authorization grant; it is not full S2 acceptance.

## Decisions left to the original owners (no guessed implementation)

1. **Whole-Skill job stage:** recommended option A is for Documents/Contracts task-type owners to define a general task stage that represents Skill work while preserving the existing document-stage meaning and version compatibility. Option B keeps JobSnapshot document-specific and defers whole-Skill status to a separately reviewed read-only projection of the existing RunLedger. Neither option creates another execution ledger. This revision chooses neither; it copies existing document-step facts only.
2. **requestRun Operation:** planned option A is an explicit original Operation variant reviewed/owned by the core contract owner and Contracts, binding exact SkillRef, binding ID/revision, schema/input digest, scope and original expected revision. Then Skills can write the prepare adapter and fake-host exact-binding tests. Option B leaves requestRun unavailable and delivers only existing-intent query/cancel/projection. No generic JSON carrier is an acceptable third option. Current behavior remains B until the owner fixes A's exact contract; no new source-owned substitute is invented.

Implementation rulings: consume the exact declared D2 candidate as a typed dependency without editing it; project only existing document jobs (cost: no whole-Skill state); cancellation returns original C2 facts and never treats request as stop proof (cost: actual lifecycle still pending); keep registration/tests migration with Contracts (cost: no claim this revision is already public-library/production wired). B alone decides dependency acceptance and develop integration. No main/develop write, force push, branch deletion, deployment, denied operation or uncertain external write.

## Raw evidence summaries

Raw argv/explicit environment/UTC/exit and byte-exact logs remain outside git in `/tmp/muyon-skills-v02-evidence/<name>.*`. No raw logs are committed.

| Run | Exit | stdout SHA256 | stderr SHA256 |
| --- | --- | --- | --- |
| cancel-recovery-red | 101 | `7f6db6004d2c9a90c3fde9d56d231e0b52a8f071be269bddac8c64566d31e065` | `ba08aade3a53ebbf66a59f5a5933272cd9fdb2033c74aaa1cd9974cbf1682aea` |
| cancel-recovery-green | 0 | `1cf7f0113c60d35a06333e2379252ac4f1dee8b7f6f5ca64f7feb9e454a046af` | `14e41eaf64b1d8f1a3510031eebb5f96402b4170be5f1c405f1e2bfa2257d3ca` |
| job-projection-red | 101 | `7c5bc0165edcb9677b47d50edfc312c4bf6c42705fe6eea05b5364e3a1af9b21` | `c07819b78c567a3ab022b73cfbe5aa1e2ff0f15688cdb43eec70b4bc74ebb4f7` |
| job-projection-green | 0 | `9dce81490957cf377be94b1a1f929582689687636470724fc4c99df30073c8e8` | `9004ce8fc5f578f67a683dbd2d24b23aa7d135573b918e51d3a78e7cbb1240b9` |
| recovery-snapshot-focused | 0 | `631ae91c3b991977900a66f46523fc81f51d6dd2017043f1985d8b1529ee889b` | `106dd028c8ba2d9762fdf5d38867a14e837ed8d6d6eba2d9123f736d6254e2a3` |
| recovery-snapshot-workspace | 0 | `720edec765b5571442cfbc67d079e4aee752736d00376fd9e2abb9dbcaac1eda` | `f3103d66fb40277bcb343b3bf7ba1e94c8d81928591fccab7af8005f812a9ad0` |
| recovery-snapshot-clippy | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `7c40d6a85084f8eb3fc872ea2966b2d9eb967ff33a160a378ad3d7795a840b88` |
| recovery-snapshot-fmt | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
