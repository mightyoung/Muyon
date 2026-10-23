# Root Rust toolchain validation

Original candidate: `8a3064b207ee5a02374b5cbcb179e419580a56bf`, based on `fd26dcdabcdac996bc2881e8141cac2b519966fc`. Original signed commit and dated review remain unchanged. This isolated integration adds only a one-line product path selector, this report and a separate factual addendum; no Rust/UI/contract implementation changes.

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
