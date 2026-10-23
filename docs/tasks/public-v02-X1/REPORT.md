# X1 local Connector contract candidate — 2026-10-23

Plan/spec fixed source: `64900d4a6a46a9ef2919bcf922fb059413b1ce82`.
Develop re-fetched `fd26dcdabcdac996bc2881e8141cac2b519966fc`.
Parent-released Contracts candidate `4d49a580cb518d9b0b80c9df3df1ff564194a639` ordinarily composed; not merged develop. C1 `6e7f774b1559a0a9693eeb195ba13c9ded561993`, C2 `b626c18a5dff184519e59bb866e5ed37362ac84e`, C3 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`. Read source/fixtures/reports before coding; C1 types reused without copies, no Money/Quantity/phase enum changes.

Rust/Cargo 1.93.1, host x86_64-unknown-linux-gnu. Explicit task-local PATH/CARGO_HOME/CARGO_TARGET_DIR/RUSTFLAGS documented in ../public-v02-connectors/TOOLCHAIN.md. Official rustfmt component additionally installed under the same approved setup: https://static.rust-lang.org/dist/2026-02-12/rustfmt-1.93.1-x86_64-unknown-linux-gnu.tar.xz, component SHA256 `2ad6fa7ad2b5e42e1ca39299039ea0110b8cb2a45847553e4cbab82181a351e0`. No SDK, new product dependency, real model or account.

## Scope and interfaces

Local descriptors/catalogs/connection snapshots/bindings, exact adapter lookup, existing catalog getter, fixed built-in public config validation. Auth/catalog/network/availability stay independent. Endpoint JSON/Debug projection strips userinfo/query/fragment; public config rejects extra/sensitive fields or secret-bearing endpoint parts. Tool/resource/prompt remain distinct; duplicate kind/name catalogs are rejected at validated getter/use boundaries. Eight synthetic fixture vectors cover all fixture cases. No refresh/transport/store/global network handle exists.

Rulings (full ledger in LEDGER.md): actual module source is compiled by #[path] in tests pending Contracts registration; only exact trusted endpoint/optional-label schema is supported, requiring future adapter schema review; Connector-local grant keys are kind-qualified tool:name/resource:name/prompt:name, with legacy bare keys denied. These choices preserve owner boundaries and avoid generic schema execution.

## TDD and immutable source

Behavior RED source `c8fbca09f60832ec4ef4fbe92d07e2a74bb4833e`: successful compilation followed by **0 passed / 7 failed**, exit101. GREEN source `7bb235c95a7431d7e419d13108b26c8557ab4c38`; combined fixed source `86534f4126835b46af3c7ec818de184491128be9` was rerun clean and unchanged: **13 passed / 0 failed**, split X1 7 and X2 6. No compilation failure was counted as behavioral RED. RED commits retain test+unavailable stub for reproduction.

Exact scoped commands (repository root):

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors
cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings
```

Initial whole-core regression: exit0, **585 passed / 0 failed / 0 ignored**, 34 result groups, including existing code and C1/C2/C3. X2 not yet part of that run.

Combined workspace/all-targets regression: **632 passed / 0 failed / 0 ignored**, 38 result groups, exit0. The command began before the feature commit and finished after it, with the same product source bytes; the clean immutable HEAD86534f41 scoped rerun separately confirms 13/13. Execution counts include overlapping existing targets and do not imply 632 distinct product scenarios. Strict core all-target Clippy and changed-file rustfmt --check both exit0. Workspace stderr includes the existing negative-boundary `ZipWriter::drop ... FileTooLarge` diagnostic while all tests succeed; no failing test is omitted.

```sh
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
```

Independent read-only reviewer `/root/review_connectors_x12` examined fixed HEAD86534f4126835b46af3c7ec818de184491128be9 against the plan and rulings, then reran X1 7/7 and X2 6/6 offline/locked in a separate target directory. No P0-P2 finding within the agreed pure-validator/host-provenance scope. Review did not accept live protocols, production host integration or library registration.

Nonblocking evidence limitation/deferred coverage: timeout fixture does not actually perform disconnect or failed remote revoke. Its unchanged server_token_revoked flag and fake dispatch count establish only fixture behavior, not lifecycle support. Those production transitions remain unimplemented and NOT_RUN; they require the X3 host/protocol design gate and later authorized tests.

## Evidence (outside git)

Raw logs and command JSON stay in `/workspace/connectors-v02-tools/evidence/`. The command JSON includes explicit environment/argv/UTC/exit; fixed runs additionally record source before/after and clean status. Only summaries/hashes enter git.

| Label | Exit | stdout SHA256 | stderr SHA256 |
| --- | --- | --- | --- |
| x1-red-final | 101 | 7cfb7c53395a9d1e600fdbbe2a84e1cb5bb83fdcd3a174fc16f973e6af63578a | b21b40180e13d0e7f091fdb0c9325aef776c8c0281a8c5ac21546e5ee53e28ab |
| x1-formatted-green | 0 | 0ffdf8910f52ee30049f69b95c201ac7fabb7319eb8bf798a3b6e39191d089ef | a5613c49d767e2e5c9d99671fe1efaa4457a36d44d72d18e86b718b9d3932c1d |
| x1-regression | 0 | 740819b36e5229665bf75547cdecbc1b6aaab41e259a695fad9bb7c4522545c7 | 976050719d03230884258d065ceeebc08d24c7c46a929c351091085a3811d88c |
| x12-fixed-green | 0 | d145f73d0f57c10a5c77dbba0e38b47ecccafd362fee93532db172d725a97c73 | 274d939970d66080a5f246c59b6818fd37d8ea5cb607c2d76faf580a2446ce75 |
| x12-fixed-fmt | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| x12-clippy | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | 9fe0881c5fc723f89088f2efbc6741f9ca4f35d9911c761f7933abec28113ca3 |
| x12-workspace | 0 | 1fc498d54dff4e4ec2135ebfd8645e48f79c66ff1cc79b7796fc901ad80f574f | bd27c80f374a721afc4ad4f9bf7d4eabb7ffcee2d0921a5b5a633c7891e03e41 |

## Registration and unverified scope

Contracts must register `pub mod connectors;` and `pub mod connections;` in services/mod.rs. No local edit to services/mod.rs, core lib.rs or FFI lib.rs; their tree bytes match the consumed Contracts candidate. Tests compile the actual module files using shared-contract aliases, not copied shared types. Library export is **pending Contracts owner**, not a production-ready API claim.

No new concrete Connector Operation, production dispatch, credential owner/store, OAuth/remote revoke, SDK/MCP transport, localhost server, Android or live external effects. Those are NOT_RUN/unavailable. X3 license/Android/credential gate and X4 provider-specific official capability evidence/Domain design review remain open; no GitHub/GitLab/Gitee equivalence or support claim. Existing Reader FD and historical real-request unknown/charge holds remain unchanged.

Normal rollback removes these new modules/registration if later registered; no data/schema migration, receipt deletion or new execution ledger exists. B alone merges develop.

Synthetic fixture SHA256: `bc8930b884475f8bf4d6c02413ac3c4d3a3e13618ababd69f32596cb160dff59`.

Phase remains the existing C1 String field. connector_preflight is only this module's descriptive call-site label, not a new common phase enum, dispatch-stage proof or frozen phase taxonomy.

Released dependency fixture checksums were independently recomputed and match the C3 REPORT: types.json `af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5`, commands.json `9f7618861e7fbc33c82e53d06c2acefb06e9fe3e40129eb172085cb48d104adc`, drafts.json `e1012c72cccea844a65a66e3b4a7ce3ae3a5257bba476f98ee9b4983cefd1460`.
