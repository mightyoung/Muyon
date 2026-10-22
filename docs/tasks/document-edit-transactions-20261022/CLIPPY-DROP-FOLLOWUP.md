# Minimal restart-test drop_non_drop correction for B

SOURCE:2e2cfcdec28c5ecdf4ebc45523fc0885d4b0a9da on
`task/document-edit-clippy-20261022`. B should cherry-pick this SOURCE commit after
its already-applied0e325011d6eb66962669aac284cdccf5fa0685e9 gateway production fix.
Only one test file changes: exactly five `drop(g);` deletions. No candidate/schema2,
production code, fake Drop, lexical behavior, assertion or lint-allow addition.
Main candidate branch remains721077297ba77471ede80b653274cec4a8224655 untouched.

Read B96852341f6347dba303c883f8f175d8da52e3761 GATEWAY-CLIPPY-FOLLOWUP.md and
verified all five sites in the accepted90b7 test source. DocumentEditGateway only
borrows BusinessStore; no Drop implementation owns any resource. The last gateway
use ends its borrow under NLL. Every actual `drop(s)` and `drop(db)` is retained at
the original position, then the fresh owner/store opens. Whole test source equality
to base after exactly those5line deletions is asserted in drop-non-drop-source-proof.log.

Actual command with exacta27 core and original old gateway source:
`bash docs/tasks/document-edit-transactions-20261022/verify-durable-combination.sh -p muyon-core --test document_edit_gateway --test document_edit_engine_protocol --test document_edit_transactions`
Use existing1.90/cache/SQLite alias env from DURABLE-REPORT.md.53passed/0failed
(19+6+28), owned gateway-test rustfmt0. Raw drop-non-drop-tests.log and
-rustfmt.log under clippy-minimal-evidence/. Independent reviewer verified exact
5line diff/all lifetime order, then personally reran gateway19/19; raw logs/diff
under clippy-minimal-evidence/independent-drop-non-drop/.

Full command was actually attempted:
`cargo clippy --offline --locked --manifest-path <exacta27 temporary archive>/crates/Cargo.toml --workspace --all-targets -- -D warnings`
It exited101: `error: no such command: clippy`. This environment has standalone
rustc/cargo1.90.0 without cargo-clippy. Therefore analysis DID NOT RUN; no strict
Clippy PASS or absence of later-target diagnostics is claimed. Raw
clippy-minimal-evidence/drop-non-drop-strict-clippy.log. B's1.93.1 environment must
perform the full strict scan; no global allow or toolchain/credential change here.

Original B50diagnostics clearing/full435 behavior results are separate immutable
B evidence, not counted as our tests or a strict-pass claim. Source-only patch can
be reviewed/reverted independently. No main/develop changes, merge, deletion,
force push, engine/model/search/user-file action, payment or historical unknown retry.
