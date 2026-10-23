# X2 local Connector contract candidate — 2026-10-23

Plan/spec fixed source: `64900d4a6a46a9ef2919bcf922fb059413b1ce82`.
Develop re-fetched `fd26dcdabcdac996bc2881e8141cac2b519966fc`.
Parent-released Contracts candidate `4d49a580cb518d9b0b80c9df3df1ff564194a639` ordinarily composed; not merged develop. C1 `6e7f774b1559a0a9693eeb195ba13c9ded561993`, C2 `b626c18a5dff184519e59bb866e5ed37362ac84e`, C3 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`. Read source/fixtures/reports before coding; C1 types reused without copies, no Money/Quantity/phase enum changes.

Rust/Cargo 1.93.1, host x86_64-unknown-linux-gnu. Explicit task-local PATH/CARGO_HOME/CARGO_TARGET_DIR/RUSTFLAGS documented in ../public-v02-connectors/TOOLCHAIN.md. Official rustfmt component additionally installed under the same approved setup: https://static.rust-lang.org/dist/2026-02-12/rustfmt-1.93.1-x86_64-unknown-linux-gnu.tar.xz, component SHA256 `2ad6fa7ad2b5e42e1ca39299039ea0110b8cb2a45847553e4cbab82181a351e0`. No SDK, new product dependency, real model or account.

## Scope and interfaces

Pure validate_call checks expected/current connection/external identity/endpoint/config/auth/catalog/plugin-binding revisions; current scope equality; exact catalog freshness, schema and capability kind; host/plugin allowed-set intersection. Resource/prompt access uses the same host gate. New directory entries or remote readOnly/prompt text never grant authority. Unknown recovery delegates C2 unphased_host_error with the original IntentId; other effects return only original lookup identity, never a Receipt.

Rulings (full ledger in LEDGER.md): current snapshots and per-plugin allowed sets are host-derived in one pre-dispatch critical section; original C2 scope/authority must also be revalidated. This pure function cannot attest input provenance and cannot replace budget/disclosure/consent gates. recovery_for Ok(identity) selects original lookup only, does not authorize replay or attest business success.

In-memory timeout fixture performs one synthetic dispatch then queries the same original through actual C2 decode_original twice; Unknown has no fabricated Receipt. Removing host grants blocks new validator admissions without deleting old outcomes. Fake host assertions do not prove live disconnect/revoke/cancel behavior; no real token or server exists.

## TDD and immutable source

Behavior RED source `2f8842c08ae0d774fc54a1a198b6ac5c3a0eb09a`: successful compilation followed by **0 passed / 6 failed**, exit101. GREEN source `86534f4126835b46af3c7ec818de184491128be9`; combined fixed source `86534f4126835b46af3c7ec818de184491128be9` was rerun clean and unchanged: **13 passed / 0 failed**, split X1 7 and X2 6. No compilation failure was counted as behavioral RED. RED commits retain test+unavailable stub for reproduction.

Exact scoped commands (repository root):

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connections
cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings
```

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
| x2-behavior-red | 101 | 55599916aaa9aec391bdf049e1f2bc55f2d2c6b45f46059ef0c6cdcf2acf9af3 | fcae1e8c93536e977a8cb68e669b745df05e4330c68355205847c638f318f5d1 |
| x2-green | 0 | 581c005881a48d945679626f2e8017ec2e4ef63160f69e59d9fcc9d1a0465146 | c53ecb04966d6c6a15a58cd841d06c70cdd19d03187087a7f524a0996c8286ff |
| x12-fixed-green | 0 | d145f73d0f57c10a5c77dbba0e38b47ecccafd362fee93532db172d725a97c73 | 274d939970d66080a5f246c59b6818fd37d8ea5cb607c2d76faf580a2446ce75 |
| x12-fixed-fmt | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| x12-clippy | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | 9fe0881c5fc723f89088f2efbc6741f9ca4f35d9911c761f7933abec28113ca3 |
| x12-workspace | 0 | 1fc498d54dff4e4ec2135ebfd8645e48f79c66ff1cc79b7796fc901ad80f574f | bd27c80f374a721afc4ad4f9bf7d4eabb7ffcee2d0921a5b5a633c7891e03e41 |

## Registration and unverified scope

Contracts must register `pub mod connectors;` and `pub mod connections;` in services/mod.rs. No local edit to services/mod.rs, core lib.rs or FFI lib.rs; their tree bytes match the consumed Contracts candidate. Tests compile the actual module files using shared-contract aliases, not copied shared types. Library export is **pending Contracts owner**, not a production-ready API claim.

No new concrete Connector Operation, production dispatch, credential owner/store, OAuth/remote revoke, SDK/MCP transport, localhost server, Android or live external effects. Those are NOT_RUN/unavailable. X3 license/Android/credential gate and X4 provider-specific official capability evidence/Domain design review remain open; no GitHub/GitLab/Gitee equivalence or support claim. Existing Reader FD and historical real-request unknown/charge holds remain unchanged.

Normal rollback removes these new modules/registration if later registered; no data/schema migration, receipt deletion or new execution ledger exists. B alone merges develop.

Phase remains the existing C1 String field. connector_preflight is only this module's descriptive call-site label, not a new common phase enum, dispatch-stage proof or frozen phase taxonomy.

Released dependency fixture checksums were independently recomputed and match the C3 REPORT: types.json `af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5`, commands.json `9f7618861e7fbc33c82e53d06c2acefb06e9fe3e40129eb172085cb48d104adc`, drafts.json `e1012c72cccea844a65a66e3b4a7ce3ae3a5257bba476f98ee9b4983cefd1460`.
