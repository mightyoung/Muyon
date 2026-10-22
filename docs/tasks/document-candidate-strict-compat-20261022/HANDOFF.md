# Candidate strict-gate compatibility patch for B

Base: `b13af1124ed1b078609a3b36fcf4f56e5ec27567`.
Fixed source: `7557cc9fcecfac92cbec1371ce47112c413729ee`.
Branch: `task/document-candidate-strict-compat-20261022`.
This worktree starts from B's fixed combination, with no Reader/tail/snapshot import.

Read overall-combination-next-20261022/HANDOFF.md and original final-strict and
workspace-compile-fixed logs. B's original576 workspace executions passed, but
strict Clippy failed on the candidate's unused publication seam and another
owner's bot_definitions boolean; worker/group contexts also warned on unused
CandidateState/CandidateStatus re-exports. Original logs remain unchanged in the
base. Those old576 results do not verify this patch or close the strict gate.

## Core patch: preserve the genuine hard rejection

Exactly seven lines add a local `cfg_attr(not(test), expect(dead_code, reason=…))`
to the reserved crate-private publication hook. There is no production consumer
until reviewed validator/gateway integration. Deleting the hook, compiling it
only in tests, widening it to public or inventing a consumer would misrepresent
that boundary. The local expectation records this intentional temporary gap.
It is not a global/module allow. Once a real production caller is integrated,
the unfulfilled expectation should require removing this marker; test builds do
not set it because real tests already exercise the hook.

Authorization, transaction ownership, source/candidate binding and final
UnsupportedOperation are byte-identical. No code path, permission, validator,
test or production request is enabled/removed. source-equivalence.json records
the unchanged function-and-rest-of-file hash. Existing test sources are untouched.

The Rust team documents expect and lint reasons as stable since Rust1.81:
[Rust1.81 release](https://blog.rust-lang.org/2024/09/05/Rust-1.81.0/).
This API is supported by B's recorded Rust1.93 strict-gate environment. No project
MSRV or successful compilation of this source is inferred from that fact.

## B-owned harness export suggestion — UNAPPLIED

UNAPPLIED-HARNESS-EXPORTS.patch changes exactly `mod documents` to
`pub mod documents` at:

- crates/muyon-core/src/bin/business_worker.rs
- crates/muyon-core/tests/group_runtime_store.rs

Both harnesses directly compile the real documents source, but their private
parent module makes its public re-exports unreachable. A public module chain
preserves library-style export reachability without deleting CandidateStatus,
which is part of the pending interface, or CandidateState, which the real core
bridge imports. It adds no dummy references or lint suppression. This only changes
Rust visibility in binary/test harness composition; it does not alter production
lib.rs, internal pub(crate) methods, CLI dispatch or FFI/host permissions.

Shared composition remains B-owned. The patch was generated against B's exact
source and `git apply --check` exited0; neither harness source was modified here.
B should apply/review it in its own combination and rerun all target checks,
including absence of unfulfilled expectations. If B uses another export repair,
keep the complete real modules and public API, not permissive authorization stubs.

## Evidence and remaining blockers

verification.log records targeted candidate tests, complete workspace tests,
strict workspace/all-target Clippy and owned-file rustfmt: all NOT_RUN127 because
cargo/rustfmt are absent. Source diff-check exited0; unapplied patch check exited0.
No extra mirrored test was added for a diagnostic-only annotation; all genuine
candidate behavior tests remain unchanged for actual rerun.

Separate read-only reviewer checked exact7557cc9f against B base: seven attribute
lines only; function/checks/hard refusal/tests/harness unchanged, no Reader delta.
Static review passed, with no new blocker. Reviewer ran no Rust and made no edits.

Actual targeted/full/format/strict verification is pending in B's existing Rust
environment. bot_definitions.rs:207 nonminimal_bool remains its owner's blocker;
this patch does not fix it or prove downstream targets clean. New Reader source,
its real cleanup REDs and pending performance tests remain separate evidence.
No main/develop merge, deployment, engine/model/search request, paid action,
credential/permission change, user file or old unknown retry occurred.
