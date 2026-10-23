# Rust Bot / Agent continuation, 2026-10-23 UTC

## Baseline and ownership

Started from fetched `origin/develop` **7aa852ab8134545c6312cd71de5c12cd49f66b5b** in isolated branch `task/bot-core-continuation-20261023`. `main` was cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003. No AGENTS.md was found in the workspace. Existing task handoffs and latest Office/Rust boundary reports were read; older strict-Clippy failures were treated as historical and retested.

The earlier Bot definition fixes and one-line Clippy expression are already in develop (integration 9b6051eff8c27c27b4098d8948b15a220bf1c819 and a1544d77eb3817c28201ef75c877511a6c6bb579). Bot definition source/tests match the previous c65 author tree, so they are not resubmitted. Current definition checks retain source/schema/type/scope/epoch/CAS, exact original intent/receipt/definition validation and conservative pending recovery. Local definitions remain non-runnable with provider_not_configured.

Only existing workflow authorization, existing host startup recovery and their synthetic tests changed. No new public interfaces, tables, registries, execution ledgers or provider configuration. No UI/Runtime/Service/Reader/Laya changes. Main/develop were not modified; sole integrator B decides integration.

## Confirmed fixes and test-first history

1. **Owner workspace binding:** RunLedger::authorize_request accepted a prepared request owned by another workspace when the ledger had no tasks. The new regression uses separate synthetic owner databases with colliding conversation names, tests positive same-workspace authorization, rejection, unchanged budgets and prepared states. RED: workspace-binding-red (exit 101, unwrap_err received Ok). Fix reuses existing AgentOwner::workspace with workflow_scope_mismatch; GREEN: workspace-binding-green (1/1).
2. **Durable guard after restart:** ProductCore::open discarded the existing workflow ledger until a scoped/workflow call lazily opened it. Public confirm/claim/allowed therefore skipped cross-child unknown checks after reopening through the old unscoped path. The extended existing unknown-child fixture drops the host, reopens a new epoch without a scoped/workflow call, synthetically reinstalls the existing test configuration, and uses the existing hosted-cost-proof fixture for a normal parent plan. RED restart-gate-proven-red actually returned reserved from confirmation despite an unresolved child. GREEN restart-gate-green refuses confirm and claim with conversation_original_outcome_required; original request remains unknown, new plan prepared, held amount unchanged. Fix reopens the same durable RunLedger during host open if its existing path is present; absent ledgers are not initialized by open. Existing ledger corruption is refused, not ignored/replaced (invalid-ledger RED/GREEN).

The ordinary unscoped production prepare still lacks the hosted cost proof and cannot confirm by itself: restart-gate-confirm-diagnostic records hosted_cost_proof_unavailable. This is not evidence of a currently runnable production provider. The definitive reservation regression uses only the existing synthetic proof. No dispatch, transport or external request was performed.

Commits (ordered, all belong to this batch):

- f3259d14286577c6afa3427c591fa052a1e5fba5: workspace binding RED test.
- 16318a296e2f1efbdbc952d2e3e29cec680fb5e0: workspace binding fix.
- 519086571bdc764c2fa925591b61bff1014e00d9: restart/corrupt-ledger RED tests.
- **8e018ad6e67d73ad58ff6ee80d3cfa898da697ce**: startup ledger recovery fix and test formatting; final production-source SHA.

## Environment and evidence

Rust 1.93.1 is installed only in /workspace/bot-core-tools. CARGO_HOME/RUSTUP_HOME/target directory and native SQLite library link are recorded in per-run JSON. The first offline baseline failed with an empty dependency cache (initial-offline-bot, exit 101). Public locked dependency fetch then succeeded; every author test/Clippy verification thereafter uses --offline --locked. No application credentials were configured. record.py/capture.py preserve original bytes, UTC intervals, argv and exit status. evidence/metadata.json preserves baseline command information. SHA256SUMS covers captured artifacts, excluding itself.

Author baseline: bot definitions 33, bot drafts 26, owner 11, product 6, workflow 16, tools 7, child tools 3: **102 passed**, plus strict workspace Clippy exit 0. These are baseline results, not final regression totals.

Failed setup/diagnostic logs are retained separately: restart-gate-red is credential-reinstall setup failure; restart-gate-confirm-red/diagnostic hit the independent fee-proof guard; restart-gate-proven-red is the actual bypass reproduction. They are not counted as passing tests or omitted. Old historical author/non-author logs are not presented as new execution evidence.

Final author verification at production source 8e018ad6e67d73ad58ff6ee80d3cfa898da697ce, 04:22:38–04:24:07 UTC:

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml --workspace --all-targets -- --test-threads=1
cargo clippy --offline --locked --manifest-path crates/Cargo.toml --workspace --all-targets -- -D warnings
rustfmt --check --edition 2021 crates/muyon-core/src/agent/workflow.rs crates/muyon-core/tests/agent_workflow.rs crates/muyon-android-ffi/src/lib.rs
```

Actual cargo path and environment are in workspace-regression.json/strict-final.json/changed-fmt.json. All exit 0. Workspace regression: **603 passed, 0 failed, 0 ignored**, 33 test binaries (including 0-test binaries). No test dispatch is counted as execution. Expected fault-test stderr includes ZipWriter FileTooLarge, and the full process still exits 0. Full stdout/stderr retained (workspace-regression.*.log); SHA256 stdout 23c2ebfbc2803baa0405b1ce459712e89aa8f827878a14d69643838ac6aedd92, stderr 7a3a7b940d7db87450c21fc71cf71eda37d8768d8bf60557e5267536dd3766a3.

Independent fixed-source review: **PASS**, no remaining required change. Reviewer independently executed workspace binding, restart unknown-child, and corrupt-existing-ledger focused regressions, each 1 passed / 0 failed (3 total), with separate target-independent. Those commands used --offline (not --locked); Cargo.lock and source hashes were unchanged. See evidence/independent/FIX-REVIEW.md and focused-fix-metadata.json for exact argv/environment/UTC/exits/source and log hashes. Independent reviewer did not rerun full workspace/Clippy; those remain author results. Baseline STATIC-REVIEW is historical candidate discovery, not the post-fix conclusion.

## Limits

Synthetic Rust/SQLite tests only. No actual Android service/device, UniFFI binding generation or UI wiring was validated; no claim that the product or a provider is runnable. No external model/search requests, account creation, payments, grants, deployment or credential changes. The two historical unknown requests and ¥0.002620 hold were not retried/read/changed. No operations on the separately blocked Reader Core or Laya work were performed; workspace test runner may exercise existing synthetic tests. Broader Skill/Connector/UI specifications and any new execution design remain outside this batch. Existing missing hosted cost proof remains a delivery boundary, not bypassed by this fix.
