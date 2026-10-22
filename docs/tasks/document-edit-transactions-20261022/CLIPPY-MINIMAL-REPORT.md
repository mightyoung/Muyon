# Minimal gateway Clippy fix for the old B combination

Source commit0e325011d6eb66962669aac284cdccf5fa0685e9 on
`task/document-edit-clippy-20261022`, directly based90b7a35a49f4acb09ff73a2b088df4c1d1a037a6.
Remote source SHA verified. Cherry-pick the SOURCE commit alone; no schema2/new
candidate dependency. Exactly2lines in gateway.rs: parity via is_multiple_of(2),
remove identity .into() on [u8;32]. No lint allow/suppression or behavior changes.
Read exact B f26b189ebabdd9ab1323d93c1e65dd778a962c67 CLIPPY-OWNER-HANDOFF.md.

Actual exacta27 combination verification:
`bash docs/tasks/document-edit-transactions-20261022/verify-durable-combination.sh -p muyon-core --test document_edit_gateway --test document_edit_engine_protocol --test document_edit_transactions`
with existing toolchain1.90/cache/SQLite linker alias env in DURABLE-REPORT.md.
Result53passed/0failed (19+6+28); raw clippy-minimal-evidence/tests.log. Independent
read-only review confirmed only these2equivalent lines and no feature/source mixing;
reviewer did not rerun tests. Strict workspace Clippy itself is B's integration gate,
not claimed passed by these behavior tests. No main/develop modification/merge,
force push, engine/provider request or credential change. Branch/worktree retained.
