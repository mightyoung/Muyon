# DM01 — conversation draft domain candidate

Baseline: `d2c56a626736fa85a95cbf8f52d5dba85fc04be3` (`origin/develop` after the integration owner's fresh fetch). Branch: `codex/dm01-domain-drafts-20261023`.

## Scope and prior work

Read `docs/superpowers/plans/2026-10-23-business-plugins.md` B3/B4 and the public-service plan review. No existing DM01 code candidate was found in fetched history. B3 remains a proposed complete lifecycle; the user's later DM01 instruction specifically authorizes this smaller pure domain slice. This does not approve the full proposed lifecycle, new Issue Operations or persistence schema. Existing public contracts, `ProjectCreate`, `CommandEnvelope`, `ExecutionResult` and `Receipt` remain the owners of their respective meanings.

Files: `crates/muyon-core/src/development_drafts.rs`, `crates/muyon-core/tests/development_drafts.rs`, this report. Public module registration is reserved for the integration owner (`pub mod development_drafts;` in `lib.rs`); the isolated integration test includes the source by path before registration. No public contract, registration, table, Bot draft store or dependency was changed.

## Implemented behavior

- Structured suggestions can progressively add a project name and multiple Requirement/Bug/Question draft items from one preserved message. This is not a natural-language parser or model integration.
- Stable item IDs retain kind and exact original-message binding, message revision and UTF-8 byte range. Cross-conversation inputs, invalid boundaries, duplicate item IDs and silent source rebinding fail. These are shape/binding checks, not trusted provenance resolution or authorization.
- Candidate project IDs remain ambiguous until explicit selection. Existing selections must come from the displayed candidates. New project creation is a separate explicit choice; project-scoped drafts cannot move to another project.
- Revision-gated preview exposes before/after text and manual-edit conflicts. Suggestions cannot overwrite manual edits; explicit manual changes can resolve them. Invalid patches are atomic. Edits invalidate unexecuted preparation; a dispatched draft freezes its content to preserve the original binding.
- `DraftEnvelope` round-trip restoration validates schema, owner and expected full `ScopeRef`; `SaveAck` uses the existing exact-content/revision/intent validator. Unknown fields, duplicate JSON keys and mismatched restored commands fail.
- Only the existing `ProjectCreate` is accepted, with exact project ID/name/scope and original validated command. Requirement/Bug/Question items remain draft content even when a project is created. No Requirement or Bug Operation is introduced.
- `begin_project_dispatch` marks and returns the original command. A future real adapter must durably save the resulting envelope **before** sending that command. `observe_project_result` validates results and committed original receipts. Once dispatched, repeat clicks, pending, unknown, malformed results and marker-only restart use `recover_project` to query the original command. Terminal results are cached and cannot silently regress. No command is recreated on lookup.

## Verification

Toolchain: existing local Rust/Cargo 1.93.1. `PATH=/Users/muyi/.rustup/toolchains/stable-aarch64-apple-darwin/bin:/opt/homebrew/bin:/usr/bin:/bin`; `RUSTUP_TOOLCHAIN=stable` selects that installed 1.93.1 toolchain for Clippy without a rustup download. No dependencies were installed.

- `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test development_drafts`: **17 passed**, 0 failed, 0 ignored.
- `cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test development_drafts -- -D warnings`: passed; includes typechecking of the source included by the integration test.
- Direct `rustfmt --edition 2021` applied to both new Rust files; format check and `git diff --check` required before candidate commit.
- `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_service_drafts --test business --test development_drafts`: **35 passed** (4 public draft + 14 original business + 17 DM01), 0 failed, 0 ignored. The business tests include actual local SQLite subprocess/restart checks for the existing business owner; they do not prove new DM01 durable storage or Android execution.
- `rustfmt --check --edition 2021 crates/muyon-core/src/development_drafts.rs crates/muyon-core/tests/development_drafts.rs`: passed.

Initial verification exposed a fake-host command fixture with an invalid hard-coded plan digest; the fixture now derives `expected_plan_digest()` using the existing contract. The final domain tests pass with real contract validation intact.

## Remaining gates

Independent review belongs to the integration owner; this author does not claim an independent review. Module registration and tests on the final integrated commit, exact-commit CI, PR organization and any merge belong exclusively to the integration owner.

There is no durable draft service, model connection, UI integration, chat end-to-end flow, trusted document/Reader/FD resolution or production host adapter in this candidate. The fake host does not prove production execution or crash-safe persistence. Durable save of the dispatch marker and admission through the original authorized host remain mandatory before attaching a real executor. A marker saved before execution can leave an original intent absent; recovery deliberately queries and does not automatically resend. Broader project lifecycle and Requirement/Bug Operations remain undesigned and out of scope.
