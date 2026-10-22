> Latest held schema2/edited preparation slice: [SCHEMA2-REPORT.md](SCHEMA2-REPORT.md).
> Previous results below remain historical; no engine publication is enabled.

> Latest durable COPY batch: see [DURABLE-REPORT.md](DURABLE-REPORT.md).
> Earlier contract-only results and limitations below are historical.

# DOC-06/08 delivery — offline contract only

## Current revision fix (supersedes original counts below)

Parent's Important finding of decreasing commit revisions is fixed in
`84d438e3f2587c3398c33fac7e984cd5143289a0`. Both Commit and RecoverCommit now require
shared checked `previous_revision.next()`, including cancelled late recovery;
same/backward/skipped revisions and u64 overflow reject without changing the prior
state/candidate or enabling Export/rollback. A rollback always publishes a new
increasing revision. Scope: one validator, tests and docs/evidence; no added effects.

Behavioral RED `31` preceded the fix. Final combination: **28 transaction +18 exact
core tests passed** (`32`). Full `cargo test --offline --locked --manifest-path
/workspace/document-edit-combination/crates/Cargo.toml -p muyon-core`, same tools/env
as below: **193 passed,0 failed,0 compiler warnings** (`33`). Seven compiled behavior
mutations caught (`34`). Fourth non-author review independently reran28+18 and three
probes, including546 numeric/route combinations and15 edge cases; no remaining
blocking findings. See REVISION-FOLLOWUP.md and evidence/independent-round4/.
Original evidence/results below remain historical; the same toolchain/Flutter and
production gateway/engine blockers remain open.

## Original batch report

Status: source-delivered, independently reviewed; production integration pending.
Branch: `task/document-edit-transactions-20261022`.
Original source commit: `9b242a4ae0143b872e7c885be29585da87a165f8`.
Fixed UI base: `3ecb544ad0a47ccc38fe830777f35588b92e8afc`.
Verified original candidate: `f4781e16ddf4e542b983fbd77f266a0071148255`.
Core dependency read/combined exactly: `ab9c381cc935be0cd52db5a8a455ce985bdba1db`;
its early public interface: `85daa64449c494eb005589ca71b164a48c470951`.
UI moved to `b6fcc030410d1718d00fbad15627423d4f809e2f` while working; inspected
its diff (UI/brand/foundation only), did not merge/rebase or write any UI files.

## Delivered

Only new `src/document_edit/`, corresponding integration test and task docs/logs.
No `lib.rs`, `documents/`, business permission/DB/UI file changes. Shared
DocumentRef / Revision / AuthorityBinding / capability types are consumed directly.
Typed lifecycle observations cover inspect/read/propose/preview/apply-copy/validate/
commit/export, cancellation, distinct apply/commit unknown recovery, and explicit
new rollback transactions. Exact binding includes full immutable document identity,
source Revision/scope/format, patch digest, original intent and rollback target.
Preview is not confirmation; immutable copy candidates and validation facts bind
that exact transaction. CAS conflicts refuse and retain already-known candidates.
Duplicates cannot repeat an effect transition on the same transaction instance.
Default/missing/gated capabilities and missing operation permission deny.

There are no actual edits, previews, file writes, network/model requests or CAS
implementation. Commit accepts host-observed facts; it does not publish. The future
host must implement durable original-intent claims/query, atomic permissions+CAS,
immutable output durability, crash recovery and actual validators. Recreating an
in-memory Transaction is not durable duplicate protection. Core read preflight and
RevisionPrecondition do not replace that gateway. No fake production host adapter,
JSON authority decoder, SDK, downloaded vendor code or runtime engine was added.

## Verification and evidence

All final execution below is offline after downloading the existing locked Cargo
dependencies. Downloads used public official Rust/crate distribution endpoints;
no document files or credentials were uploaded. Toolchain installed only under
`/workspace/document-edit-tools`, with archive SHA256 verified against official
checksums. Compiler: rustc1.90.0; environment/checksums in `25-environment.log`.
The installed SQLite runtime lacked `libsqlite3.so`; a workspace-only linker alias
to the existing system `libsqlite3.so.0` was used. System and DB code were unchanged.
No permission/approval denial occurred or was bypassed.

Commands (run from `/workspace/Muyon`; environment variables are tools, not secrets):

```sh
export CARGO_HOME=/workspace/document-edit-tools/cargo-home
export RUSTC=/workspace/document-edit-tools/toolchain/bin/rustc
export RUSTDOC=/workspace/document-edit-tools/toolchain/bin/rustdoc
export RUSTFLAGS='-L native=/workspace/document-edit-tools/native'
CARGO=/workspace/document-edit-tools/toolchain/bin/cargo \
  bash docs/tasks/document-edit-transactions-20261022/verify-combination.sh
```

The script archives the exact core dependency and copies ONLY our module and test
into a temporary tree; no ownership violation or lib.rs edit. It invokes:

```sh
cargo test --offline --locked --manifest-path <combination>/crates/Cargo.toml \
  -p muyon-core --test document_edit_transactions --test documents
```

Final targeted: **27 transaction + 18 exact core tests passed**, exit0 (`22`,
independent round3 and `27` reproduce logs). Tests include old confirmation,
double-click, cross-scope, revocation/generation, unvalidated/failed validation,
CAS/source conflict, all validation dimensions/formula unknown, original-intent
recovery, cancel-before-late-receipt, and default capability/permission rejection.

Full core command, same environment and exact combined tree:
`cargo test --offline --locked --manifest-path <combination>/crates/Cargo.toml -p muyon-core`.
Final **192 passed, 0 failed** across unit/integration/doc suites, exit0 (`23`).
It does not test this unexported module through a production library API.

Six behavioral negative-control mutations caught, each compiled then failed the
expected real assertions; `check-mutations.py` and `24-mutation-checks.log`.
Final rustfmt check exit0 (`26`); source/document whitespace check exit0.
Whole-delivery whitespace check exits2 because raw compiler/test logs retain
trailing whitespace/blank lines (`30`); raw evidence is deliberately not rewritten. Independent review is
in `INDEPENDENT-REVIEW.md`, with raw non-author probes and logs retained.

TDD history is deliberately not flattened into an all-green story. Initial tests
were written before the module and failed compilation because it was absent (`01`);
that is API-missing RED, not a behavioral failure. Next compile exposed missing std
(`02`), then17 tests passed (`03`, with formula-variant dead-code warning). The
review regressions actually failed behavior before fixes (`07`, `10`, `21`);
API additions failed compilation before implementation (`08`, `14`, `17`). Earlier
Cargo misses (`04` rustc not on PATH, `05` uncached serde_json) and SQLite linker
failures (`13`, `15`) remain with their original outputs. Final API depends on shared
core, so original standalone rustc path logs are historical only.

## Remaining blockers / NOT_RUN

- Full Rust workspace command `cargo test --offline --locked --manifest-path
  <combination>/crates/Cargo.toml --workspace` FAILED before tests: locked
  cargo-platform0.3.3 requires Rust1.91; compiler is1.90 (`19`). No lockfile downgrade.
- Full product gate `bash scripts/verify.sh` FAILED before tests because Flutter
  is absent (`06`); Android/runtime/device behavior NOT_RUN in this batch.
- Bare fixed UI-base branch does not contain documents exports. Consume the exact
  core dependency first; use the supplied temporary combination verification now.
  The document-core owner alone controls lib.rs exports; no self-integration done.
- Production document host/atomic intent-CAS gateway, actual format engines and
  license/fidelity/CPU/resource/security assessment are not implemented or accepted.
  Word/PPT/Excel/PDF real round-trip, format rendering/formula truth, real permission
  revocation at byte delivery, persistence/crash recovery and Agent wiring NOT_RUN.

No main/develop modification, force push, branch deletion, deployment, paid service,
credential setup, permission expansion or real model/search request. Historical two
unknown requests and ¥0.002620 reservation remain unchanged, with no retries/refund.
Leader B remains the sole develop merger; this branch is not merged automatically.

## Late remote observations

Before delivery, core formatting follow-up reached
`d2ac6a87a8bf13d8a22ebd41676683be8d849a22`. Canonical rustfmt output of all four
documents source files plus its test was byte-identical to pinned ab9c381 (`28`).
This report's executed combination and192-test count remain pinned to ab9c381;
it does not claim a test run or repository-wide formatting pass for d2ac6a87.
Final remote observation of UI was `98baa979223d96094f11a56c3ac6d48f9b84c0eb`;
this task still uses the explicitly fixed3ecb544a base and writes no UI paths.
