# DM02 repository evidence consumer candidate

Baseline: `d2c56a626736fa85a95cbf8f52d5dba85fc04be3` (`origin/develop`).
Branch: `codex/dm02-repository-evidence-20261023`.
Isolated checkout: `/private/tmp/muyon-dm02-20261023`.

## Scope and prior plan

Read `docs/superpowers/plans/2026-10-23-business-plugins.md` B3/B4 and
`docs/superpowers/plans/2026-10-23-connectors.md` X4. Those plans keep the full
development domain and real repository synchronization behind review gates.
The user's later task 6 authorizes only synthetic GitHub/GitLab/Gitee fixtures
and pure consumption rules; this candidate implements that bounded slice.
No DM02 implementation branch or matching commit was found in fetched refs.

## Files and behavior

- `crates/muyon-core/src/domains/development/repository_evidence.rs`: pure in-memory
  snapshot consumer, scoped by provider, canonical instance identity, repository
  identity and PR/MR object identity. Complete SHA identities remain exact.
- `crates/muyon-core/tests/development_repository_evidence.rs`: 13 integration
  tests loading this candidate module through `#[path]`; no shared module
  registry or public contract is edited.
- `docs/contracts/development/fixtures/repository-evidence.json`: synthetic,
  already-normalized provider fixtures; these are not samples of real provider
  wire payloads or claims about current external API capabilities.

The host supplies monotonic repository access generations separately from
repository facts. Revocation clears every object in the repository; regrant
requires a new generation and fresh snapshots. A provider event cannot grant
access. This is a testable boundary, not an implemented host authorization chain.

The connector must reconcile raw provider events into **complete replacement
snapshots** with a monotonic revision per object and authorization generation.
Webhook delivery order or provider timestamps do not satisfy that contract.
Lower revisions cannot overwrite current facts; identical revisions are
idempotent after check-order normalization; conflicting equal revisions fail.
Actual adapter reconciliation and its durable cursor are not implemented here.

Current-head CI evaluates only exact head checks. Success means only that all
supplied checks for that head succeeded; it does not prove required-check
coverage, branch protection, mergeability, trusted provenance, human acceptance
or local requirement completion. Missing/unknown CI capability cannot pass,
including the Gitee fixture with intentionally missing CI capability. A real
Gitee connection's capability must later be established independently.

Synthetic test-merge checks retain tested SHA and head/base inputs and are shown
separately only while both inputs match the current snapshot. They never imply
head CI success or actual merge. Actual merged state carries its own merge SHA;
closed remains closed. Unknown/skipped/cancelled conclusions never pass.

No local Issue/Project mutation API, model call, persistence, OAuth, webhook,
provider request, host command, deployment or automatic completion exists in
this slice. Snapshot shape validation does not authenticate a source or grant
authorization. Product linkage remains unregistered for the integration owner.

## Actual verification

Rust and Cargo: existing `1.93.1` from
`/Users/muyi/.rustup/toolchains/stable-aarch64-apple-darwin/bin`.
Target: `/private/tmp/muyon-dm02-target` (isolated from other candidates).
Commands use that bin directory first in PATH; Clippy also uses
`RUSTUP_TOOLCHAIN=stable` to select the existing installation without a rustup
network sync. No toolchain, SDK, dependency or system setting was installed.

- Structural RED: targeted test failed because the new domain module did not
  yet exist. No behavioral RED is claimed for that compile failure.
- `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked
  --test development_repository_evidence`: **13 passed, 0 failed, 0 ignored**.
  Tests cover three normalized provider fixtures; provider/instance/repository/
  object isolation; exact SHA and serialization; head/base changes; synthetic
  versus actual merge; closed; all CI conclusions and mixed conclusions;
  missing/unknown capability; duplicates, reordered check lists and out-of-order
  snapshots; conflicting revisions; revocation/regrant; malformed snapshots.
- `cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --offline --locked
  --test development_repository_evidence -- -D warnings`: **passed**.
- `cargo build --manifest-path crates/Cargo.toml -p muyon-core --offline --locked`:
  **passed**. The new candidate module is compiled by its targeted integration
  test; library registration is intentionally deferred to the single owner.
- `rustfmt --edition 2021 --check` on the two new Rust files: **passed**.
- `git diff --check`: **passed** before candidate submission.

The first default rustup invocation was blocked by sandbox writes under
`~/.rustup/tmp`; direct installed binaries resolved that without disabling any
restriction. The first Clippy attempt also tried rustup synchronization;
explicit existing toolchain selection resolved it.

## Review and remaining gates

Independent review is requested from the sole integration owner; this report
does not label the author's own inspection independent review. Final CI must
run for the final submitted SHA and any integration combination. No CI result
is claimed yet. No develop/main update, force push or deployment was performed.

Before production use: independent review; shared-module registration by its
owner; adapter-specific identity/provenance/capability validation; trustworthy
snapshot reconciliation and revision ownership; actual host authorization;
durable storage/recovery and data retention decisions; real fixture/API
conformance and device/product acceptance. All three platforms remain unsynced.
