# Minimal needless_update test correction for B

Cherry-pick SOURCE5959173995b92f55587cf9e201d51a7b2a04cf0e from
`task/document-edit-clippy-20261022`. Exactly ONE deletion in
crates/muyon-core/tests/document_edit_transactions.rs: `..binding()` in
rollback_is_a_new_bound_transaction_not_a_cancel_side_effect. All four Binding
fields are explicitly specified; helper only creates fixed test data. Values and
all positive/negative rollback assertions remain byte-identical. No production,
authority, new candidate/bridge code, lint allow or branch merge is included.

Exact B53a7d2726bfa8f59dccba4ad957d933a9b9eb2e5 was fetched and archived without
checkout changes. Its entire original test file equals this branch before the
one-line removal. Only the corrected test file was placed into the archive; no
lib.rs/module or dependency changes were necessary. Exact source equality/hashes:
clippy-minimal-evidence/needless-update-source-proof.log.

Actual target command (existing rustc/cargo1.90.0, cache/SQLite alias environment):
`cargo test --offline --locked --manifest-path /tmp/muyon-needless-update-B.qv7t_087/crates/Cargo.toml -p muyon-core --test document_edit_transactions`
exit0,28passed/0failed, including rollback test and all contract regressions. Raw
stdout+stderr retained in clippy-minimal-evidence/needless-update-exact-B-test.log.
`rustfmt --check --edition 2021 crates/muyon-core/tests/document_edit_transactions.rs`
exit0 (needless-update-rustfmt.log). Independent read-only reviewer confirmed exact
one-line diff, all four fields/unchanged assertions, pure helper/no unrelated changes;
reviewer did not claim an independent test rerun. Raw diff/hashes under
clippy-minimal-evidence/independent-needless-update/.

Strict full Clippy remains B's1.93.1 gate. This environment has no cargo-clippy
(previous actual no-such-command output retained in drop-non-drop-strict-clippy.log);
no new full strict PASS is claimed. No install/credential/permission change.
Main candidate branch remains721077297ba77471ede80b653274cec4a8224655 clean and
untouched. main/develop unchanged; no merge/force/delete/deploy/engine/provider/search,
user-file operation, payment or historical unknown retry.
