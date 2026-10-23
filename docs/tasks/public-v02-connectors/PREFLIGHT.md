# Connectors X1/X2 — dependency hold and independent preparation

Later update: parent released fixed Contracts candidate 4d49a580cb518d9b0b80c9df3df1ff564194a639. X1/X2 local implementation and actual verification now appear in [X1 REPORT](../public-v02-X1/REPORT.md) and [X2 REPORT](../public-v02-X2/REPORT.md). Historical dependency-hold text below describes its original stage, not current source availability. Contracts registration/production host gates remain pending.

Follow-up: the user subsequently authorized official Rust toolchain and locked
cache setup. See [TOOLCHAIN.md](TOOLCHAIN.md) for the later actual results. The
missing-toolchain observations below describe the original preflight only;
the C1/C2 interface release hold still applies.

2026-10-23 UTC. This is preparation only: X1/X2 implementation, behavioral
RED/GREEN, regression and product acceptance are **NOT_RUN**.

## Fixed inputs and ownership

- Approved plan/spec source: `64900d4a6a46a9ef2919bcf922fb059413b1ce82`,
  `docs/superpowers/plans/2026-10-23-connectors.md`, the complete
  `2026-10-23-public-services-index.md`, and
  `docs/superpowers/specs/2026-10-23-public-services-ui-design.md`.
- Latest develop fetched in this session: `fd26dcdabcdac996bc2881e8141cac2b519966fc`.
  Initial checkout `work` at `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` was
  not used as the product baseline. Remote fetch configuration maps only main;
  `git fetch origin develop` returned develop through FETCH_HEAD. The plan
  commit was subsequently fetched separately; its FETCH_HEAD is not develop.
- Isolated branch: `task/public-v02-connectors-20261023`, workspace
  `/workspace/Muyon-connectors-v02`, based on the explicit develop SHA above.
- No AGENTS.md found in the develop tree, fixed plan tree, or the selected
  workspace. Read `docs/tasks/HANDOVER-LEADER.md`, `REVIEW.md` and the existing
  `ui-shell-20261022/HANDOFF.md`. Historical permissions are not new authorization.
- Contracts task `01a16706-39b2-7083-9bdd-ba0e9c4750ed` owns C1/C2/C3.
  Parent-released, immutable C1/C2 interface and fixture SHAs have **not arrived**.
  A branch name, plan signature or unreviewed candidate is not a release.
- Only B (`01a14fbb-c8ec-7215-9b01-9c8cebf140d7`) may merge develop.
  No main/develop update, deployment or branch deletion is part of this slice.

## Source findings at the explicit develop SHA

| Evidence | Consequence for this line |
| --- | --- |
| `crates/muyon-core/src/contract.rs:54` defines private-string Revision; parse validates canonical u64 decimal and next checks overflow. | Reuse it; do not introduce a Connector revision type. |
| `contract.rs:100` Scope and `:106` AuthorityBinding are existing types. | Consume C1 ScopeRef; account selection must not become authority. |
| `crates/muyon-core/src/lib.rs` has no services registration; no services/ directory exists. | Do not register modules locally or guess C1 exports. |
| `crates/muyon-android-ffi/src/lib.rs:765`, `:798`, `:806`, `:821` contain prepare/confirm/lookup/cancel. `:1090` lookup_json includes not_submitted. | C2 remains the receipt/lookup adapter; no Connector receipt or execution ledger. |
| `crates/muyon-core/src/agent/owner.rs:299` describes host-selected capability subsets. | This is existing authority behavior, not a connection lifecycle or consent implementation. |
| `crates/Cargo.toml` and core Cargo.toml already provide serde/serde_json and sha2. | No MCP SDK, URL/schema interpreter or other new dependency. |
| `apps/muyon_android/app/build.gradle.kts:16`, `:32`, `:40` specify minSdk26/JVM17. | X3 Android suitability remains unproven by JVM compilation. |

## Dependency handoff required before coding

1. Parent releases full C1 source SHA, fixture SHA256 and independent review
   disposition. Inspect exact constructors, visibility, strict decoding and error
   mapping for Digest, UnixMs, ScopeRef, IntentId and ServiceError, and the reused
   Revision; do not copy their proposed definitions into this module.
2. For X2, also release C2 source/fixture SHA and review disposition. Confirm
   original lookup/NotSubmitted semantics and error-effect projection. No concrete
   Connector Operation is supplied by this plan, so production dispatch stays
   unavailable even after the pure validator is implemented.
3. Re-read latest develop and compare released dependencies before composing the
   approved source. Preserve review provenance and do not take an unrelated
   candidate as baseline.
4. Contracts registers only `pub mod connectors;` and, when X2 is ready,
   `pub mod connections;` in its services/mod.rs. Contracts retains exclusive
   ownership of core lib.rs and FFI lib.rs. This line supplies module files and
   registration requests, never edits those three shared files.

X1-owned future files: `crates/muyon-core/src/services/connectors.rs`,
`crates/muyon-core/tests/public_connectors.rs`, and
`docs/contracts/public-services-v02/fixtures/connectors.json`.
X2-owned future files: `services/connections.rs` and `tests/public_connections.rs`
under the same core crate. No product file or fixture is created by this preflight.

## Prepared behavior matrix — not implemented tests

| Planned test | Behavior RED target / observation required |
| --- | --- |
| auth_and_catalog_states_are_independent | Authorized + Failed remains two separate states; missing catalog returns CapabilityUnavailable; getter never refreshes. |
| no_secret_in_public_projection | Synthetic sentinel in sensitive config fields, URL userinfo/query/fragment never reaches JSON, Debug or safe_message; config is rejected rather than masked and accepted; reads have zero transport calls. Test nested sensitive fields and invalid endpoints as well as nominal input. |
| capability_kinds_are_separate | Same name in Tool/Resource/Prompt stays distinct; duplicate kind/name rejects. Calling one kind cannot match another kind's catalog entry. |
| binding_changes_invalidate_calls | Change identity, endpoint digest, configuration revision, authorization generation, catalog revision, plugin binding revision one at a time; reject each stale expected binding. Also mismatch connection, stale catalog, schema digest and scope. |
| same_connection_does_not_share_plugin_permissions | Synthetic research/read, inquiry/quote and development/repo bindings on one connection retain distinct allowed sets; host/plugin intersection is required; catalog additions grant nothing. |
| remote_read_and_prompt_require_host_gate | Tool self-description or malicious prompt cannot enlarge either allowed set; Resource/Prompt requests require the same host policy gate and exact kind/schema match. |
| timeout_and_disconnect_preserve_original | An in-memory fake dispatch records one send before timeout; Unknown recovers the original IntentId without another send/prepare; local disconnect does not claim token revocation, cancellation does not claim rollback, disabling blocks new actions while old outcomes remain queryable. |

Before implementing each behavior, use a compiling unavailable stub when needed;
observe the specific assertion fail. A missing symbol, missing Cargo or missing
test target is not behavioral RED. The future test harness must exercise the
production validator, not just assertions about a fake's own behavior.

Review decisions to settle against released contracts before claiming GREEN:
X1 trusted built-in schema vocabulary/validation limits and endpoint projection
construction; duplicate-catalog rejection entry point; X2 kind-qualified permission
names when capability names overlap; trusted binding owner/scope source and exact
NotDispatched/Confirmed/Unknown recovery semantics. Keep these reviewable and
fail closed; do not add an arbitrary schema interpreter or infer permission from
catalog text. These are implementation review points, not released interfaces.

## Commands and actual results

Commands below were issued from `/workspace/Muyon-connectors-v02` unless stated.

| Command / action | Actual outcome |
| --- | --- |
| `git fetch origin develop` (initial checkout) | exit 0; develop `fd26dcdabcdac996bc2881e8141cac2b519966fc`. |
| `git fetch origin 64900d4a6a46a9ef2919bcf922fb059413b1ce82` (initial checkout) | exit 0; fixed plan available for git show. |
| `git worktree add /workspace/Muyon-connectors-v02 -b task/public-v02-connectors-20261023 fd26dcdabcdac996bc2881e8141cac2b519966fc` | exit 0; separate worktree and branch. |
| `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors` | exit 127, `/bin/bash: line 1: cargo: command not found`; toolchain BLOCKED before compilation. Not RED, not a product failure. |
| X1 GREEN / fixture digest / regression | NOT_RUN / not created / NOT_RUN. |
| X2 RED/GREEN / fake dispatch / regression | NOT_RUN; C1/C2 release pending, cargo unavailable. |
| Rust workspace baseline | NOT_RUN: same unavailable toolchain. |
| Android build, mock protocol, real consent/revoke, real remote effects | NOT_RUN. |

The first two future scoped commands are specified by the plan. The third is
the additional core-crate regression command required before completion:

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connections
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked
```

No installation, cache download or privilege expansion was attempted to resolve
the unavailable toolchain. A toolchain with offline dependencies must be supplied
through an authorized environment before these tests can run.

The exact scoped command was captured again with `/bin/bash -c`, exit 127.
Raw output stays outside git in `/workspace/scratch/public-v02-connectors/`:
stdout `toolchain.stdout.log` SHA256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`;
stderr `toolchain.stderr.log` SHA256
`a326558a932a2a67436a997ada30bbb04a637812287a7435cac205a7a51c6e71`.

## X3/X4 and remaining blockers

X3 remains an engineering gate, with no SDK selection/install or services/mcp.rs.
Pinned LICENSE/NOTICE, dependency closure, MSRV/Android API/ABI and host credential
owner/consent/revoke semantics are not established in this slice.
X4 remains a design gate awaiting the parent's separate official GitHub/GitLab/
Gitee capability evidence and Domain review; no capability is marked supported,
no provider interchangeability is assumed, and no synchronization service,
application, credential or Webhook is created.

Pending action: implement X1 against released C1, then X2 against released C2.
Targets: the new module/test/fixture files listed above. Reasons: parent release
has not arrived and cargo is unavailable. Outcome: **pending dependencies**, not
denied and not an uncertain write. Independent preparation is complete; no
implementation, successful tests or remote-effect acceptance is claimed.

Independent read-only reviewer `/root/review_connector_preflight` checked this
preparation document against the fixed plan and source baseline. No blocking or
important findings; two minor documentation findings were corrected: Scope and
AuthorityBinding definition line references, and distinguishing the planned
scoped test commands from the additional crate regression command. This review
is of preparation only, not X1/X2 implementation or product acceptance.
