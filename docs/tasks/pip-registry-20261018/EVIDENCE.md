# Evidence record

Environment: selected Linux x86_64 workspace, 2026-10-18 UTC. Source baseline
F2 `3f1be180bb009a91e659c113ba5b1916e5360332`; no product source modifications.
Audit additions are under `docs/tasks/pip-registry-20261018/` only.

Local toolchain: Rust1.90.0 / cargo1.90.0, installed with the official rustup
installer into `/workspace/pip-toolchain` outside Git. Minimal profile initially
had no rustfmt. Component installation resolved that setup error. No global PATH,
system permission, credentials or repository build configuration changed.

Run from repository root. Prefix Rust commands with:

```sh
export CARGO_HOME=/workspace/pip-toolchain/cargo
export RUSTUP_HOME=/workspace/pip-toolchain/rustup
export PATH=/workspace/pip-toolchain/cargo/bin:$PATH
```

| Command | Exit | Actual result / retained log |
|---|---|---|
| `cargo test --locked --offline --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml` | 0 | Original full crate: mapping5/read8/registration9 =22 passed,0 failed/skipped. `evidence/plugin-baseline.log` |
| `cargo test --offline --manifest-path docs/tasks/pip-registry-20261018/probe/Cargo.toml` before correcting error-code expectation | 101 | 3 passed/1 failed; exact existing code vs test expectation mismatch. `evidence/initial-probe.log` records a repeat of the same initial failure; no production fix or feature RED |
| `cargo fmt --manifest-path docs/tasks/pip-registry-20261018/probe/Cargo.toml --check` before rustfmt component install | 1 | Missing rustfmt setup error. `evidence/probe-fmt-initial.log` |
| `cargo test --locked --offline --manifest-path docs/tasks/pip-registry-20261018/probe/Cargo.toml` after correction and formatting | 0 | 4 passed,0 failed/skipped. `evidence/probe-green.log` |
| `rustfmt --edition 2021 --config skip_children=true --check docs/tasks/pip-registry-20261018/probe/tests/publication.rs` | 0 | New consumer test formatting only; shared existing support source untouched. `evidence/probe-fmt.log` |
| `git diff --check` before staging | 0 | Initial additions were untracked, so this was not an authored-file whitespace proof |
| `git diff --cached --check` | 2 | Preserved raw Cargo logs have final blank lines (`plugin-baseline.log:61`, `probe-green.log:12`); logs are not rewritten |
| Staged diff check excluding raw `evidence/*.log` | 0 | Authored documentation/test/manifest whitespace check |

The original crate target directory was generated locally then moved outside
the Git worktree to `/workspace/pip-plugin-baseline-target`. Probe target remains
ignored by its scoped `.gitignore`. Cargo.lock is retained for the evidence
consumer; it uses only the two existing local crates, without new third-party
dependencies. Build caches are not evidence files.

Fixed source/path readbacks:

- Library plan read succeeded; no refused Library action or workaround.
- B05 handoff and next ownership record were read at fixed complete SHAs listed
  in README. Existing A/B CI states are historical handoff facts, not rerun here.
- Store candidate vs F2 Catalog path diff returned0; no inference that the whole
  store candidate or later B06 combined product passes.
- Source `git diff` contains no core/shared path; owner clearance remains pending.

NOT_RUN: Dart suites, host lifecycle suite, supplier store candidate tests,
SQLite migration/recovery, Android build/emulator/device/ART/Binder, real data,
online model, I04 legacy provider→HTTP→reopen or equivalents. These are not
skipped tests inside a claimed green production suite. No production change was
made, so this consumer supplement and original Catalog suite are the relevant
executed scope. Production utility and all-plugin-platform completion remain
unaccepted.

Independent review and exact audit commit retest are recorded separately in
`REVIEW.md` when available. No claim of independent review is made by the author
of this evidence file alone.
