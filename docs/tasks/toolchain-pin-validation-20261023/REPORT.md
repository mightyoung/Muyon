# Root Rust toolchain validation

Original candidate: `8a3064b207ee5a02374b5cbcb179e419580a56bf`, based on `fd26dcdabcdac996bc2881e8141cac2b519966fc`. Original signed commit and dated review remain unchanged. This isolated integration adds a one-line product path selector, its narrowly bounded prerequisite-witness adaptation/tests, this report and a separate factual addendum; no Rust/UI/contract implementation changes.

## Actual local execution

The selected integrator environment initially had no cargo/rustup installation. Within the previously approved fixed-version scope, official rustup-init was downloaded from static.rust-lang.org, verified against its official SHA256 (`5be191e8c70a5007074254cb74d78dbfdd25cd5a61c27de7b8e5410122ec24f4`), and used only under `/workspace/muyon-toolchain-validation-tools`. No system profile/PATH, credential, SDK, security or privilege change. Rust1.93.1/minimal plus clippy/rustfmt were installed; only `cargo fetch --locked` provisioned project dependencies. All following build/test commands were `--offline --locked`.

The isolated worktree was materialized and verified against the complete original Git tree `5e5a5db1ca94b31de45a64224b1a05eb91ab86c9`; the original signed commit bytes reproduce8a3064b exactly. Existing worktrees and uncommitted probes were untouched. Root toolchain, Cargo.lock and all Rust inputs remain byte-identical to8a3064b; only CI/docs change during integration. Logs record argv/cwd/UTC/exits/environment overrides and hashes, outside the repository at `/workspace/Muyon-plan-review-queue-20261023/actual`.

- `rustup show active-toolchain` at root, `crates/` and `crates/muyon-core/`: each explicitly reports the root rust-toolchain override selecting1.93.1. Outside the repository it reports the default instead.
- Installed components include cargo/rustc/rust-std/clippy/rustfmt. Actual `rustc --version --verbose`, cargo, `cargo fmt --version` and `cargo clippy --version` all exit0 at the official1.93.1 toolchain. This checks formatter availability, not an assertion that every inherited Rust source file passes whole-tree formatting.
- Root `cargo fetch --locked --manifest-path crates/Cargo.toml`: exit0; then root `cargo build --offline --locked --workspace --all-targets --manifest-path crates/Cargo.toml`: exit0.
- Root `cargo test --offline --locked --workspace --all-targets --manifest-path crates/Cargo.toml -- --test-threads=1`: **603 passed /0 failed /0 ignored,33 summaries**. Executions overlap across binaries and are not603 independent scenarios.
- From `crates/`, `cargo clippy --offline --locked --workspace --all-targets --manifest-path Cargo.toml -- -D warnings` and `cargo check --offline --locked --workspace --all-targets --manifest-path Cargo.toml`: both exit0.
- Local link search uses a task-owned symlink to the existing system libsqlite3.so.0; no new system library installation. `CARGO_HOME`, `RUSTUP_HOME`, target directory and native-link flag are recorded task-local overrides.

## Independent review and CI gap

Independent fixed-source review found C0/I1/M1. Important: the root file did not match product_paths, so a root-only change would omit Rust/native/Android required gates. The isolated fix adds `rust-toolchain.toml` to the existing shared paths list. An external selector probe records before=false/after=true; removing the single added line restores every original workflow byte. All job bodies, dependencies, conditions, thresholds, model/package/license checks and permissions are unchanged. Exact combined hosted CI remains required; local603 cannot substitute for it.

Deferred Minor: legacy lab workflows that use only `rustup default1.99.0` then ordinary cargo are overridden by the new root file; frontend-service-loop's original1.99.0 guard can refuse. Historical SHA without the root file is unaffected; explicit `+version`, RUSTUP_TOOLCHAIN, direct toolchain binaries and more-local toolchain files have their own selection. No old version assertion is removed, no environment workaround or old lab/I04/Reader execution is performed. Production workflow installs1.93.1 already. This slice does not claim all historical lab gates passed.

Final immutable integration review and actual hosted product/legacy checks are pending at report publication. Do not infer merge or C1 delivery from this report. PR108 remains Draft/VISUAL HOLD. Full Rust PDF, Electron/napi, Money/Quantity/phase choices and UI redesign are separate owner decisions. No real model/search/fees/credential operations, branch deletion, main modification or deployment.

## Preserved hosted RED and exact witness correction

First integration head56dda3f78cb78abdf7c71885d7ca77530dcee8c7 failed push39906583450 and PR legacy39906639791: `FrozenSchema.test_historical_reference_manifest_matches_fixed_git_objects` required the current product workflow to equal SOURCE_PIN byte-for-byte and correctly rejected the new path line. Laya failure propagated to the original ci gate; no failure was ignored. Local unchanged-test reproduction also failed1/1 with the same byte mismatch. Original raw logs remain outside the repository.

Keep SOURCE_PIN/GATE_BASE, all23 historical witnesses, manifest hash/blob/size checks, coverage baseline and all original assertions. The current-product comparison now permits exactly the one reviewed root-toolchain path extension when the root file exists; it still requires every other workflow byte to equal the fixed historical source. Absence/duplication of the root path, missing Rust path, broader permission, weaker Clippy, changed aggregate and changed model gate are seven rejected mutation cases. Two added tests also require root inputs actually select the product gate. The original15 plus new2 prerequisite tests pass17/17; independent Laya four suites pass8+4+8+9=29. No baseline is moved, test removed, threshold lowered or original product job altered.

This is local witness GREEN, not a claim that the failed hosted run turned green. The repaired immutable head requires fresh full PR CI; the initial red/superseded runs remain separate. Rust source/root pin/Cargo.lock are unchanged, so local603 is not rerun or added to a new unique-scenario total for a Python witness change.
