# Independent fix review — workspace binding and restart guard

Reviewed commit: `8e018ad6e67d73ad58ff6ee80d3cfa898da697ce`.
Base: `7aa852ab8134545c6312cd71de5c12cd49f66b5b`.
Conclusion: PASS for the two existing-interface fixes. No remaining blocking or should-fix finding in this diff. No merge authorization or whole-product acceptance is implied.

## Scope and implementation

Exactly three tracked files changed: `agent/workflow.rs`, its existing `agent_workflow` test suite, and existing Android FFI `lib.rs`. Production changes are the workspace comparison and startup initialization of the existing optional RunLedger. No public signature, new ledger, provider configuration, credentials, UI, Reader or Laya change.

- `agent/workflow.rs:920–924`: owner workspace is compared before reading request identity or traversing request chains; mismatches return `workflow_scope_mismatch` without changing budgets or requests.
- FFI `lib.rs:135–156`: if the existing workflow path exists, startup opens/reconciles it before returning ProductCore. Filesystem/open errors propagate instead of silently continuing with `workflow=None`. The `try_exists()` error path fails closed. If the file is absent, this startup branch leaves the ledger unset and does not create a workflow database; the existing explicit workflow entry remains responsible for first creation.
- Existing `authorize_agent_request` is unchanged and now sees restored durable child chains on confirm/claim/allowed immediately after restart. Existing scope, session, epoch, cancellation, price-proof and budget checks remain in place.
- Invalid existing ledger bytes are not replaced; the new regression checks this explicitly.

## Independent focused execution

New independent runs used Rust 1.93.1, offline Cargo and `/workspace/bot-core-tools/target-independent`; the author target and logs were not overwritten. Full argv, environment overrides, source SHA256 values before/after, UTC times, exit codes and raw stdout/stderr hashes are in `focused-fix-metadata.json`.

1. `cargo test --offline --manifest-path crates/Cargo.toml -p muyon-core --test agent_workflow request_authorization_rejects_an_owner_from_another_workspace_without_side_effects -- --exact --nocapture`: 1 passed, 0 failed, exit 0.
2. `cargo test --offline --manifest-path crates/Cargo.toml -p muyon-android-ffi --lib tests::another_root_and_ordinary_chat_cannot_bypass_an_unknown_child -- --exact --nocapture`: 1 passed, 0 failed, exit 0.
3. `cargo test --offline --manifest-path crates/Cargo.toml -p muyon-android-ffi --lib tests::open_refuses_an_invalid_existing_workflow_ledger_without_replacing_it -- --exact --nocapture`: 1 passed, 0 failed, exit 0.

These are three focused executions, not full-suite or strictClippy reruns. Commands used `--offline` and did not pass `--locked`; the tracked Cargo.lock remained unchanged. The exact fixed HEAD and source hashes stayed unchanged across execution.

## RED and operational limits

Author `restart-gate-proven-red.*` records the genuine regression under the existing synthetic `FixtureProof`: the unfixed confirmation incorrectly returned `reserved`. Initial credential-generation setup failures and ordinary `hosted_cost_proof_unavailable` diagnostic failures are separate preserved attempts and are not evidence of that gate defect.

The final test deliberately first checks that the ordinary production preparation path still returns `hosted_cost_proof_unavailable`. It then uses only the existing local cost-proof fixture to exercise confirmation/claim, both of which must reject with `conversation_original_outcome_required`. Original child status remains `unknown`; original held cost is unchanged; the new plan remains `prepared`. This proves local guard behavior and does not establish that any current production transport can make a real paid request.

No real configuration/credentials/transport/model/search request was used. No historical reservation or user database was changed. No source edits, commits or pushes were performed by this reviewer.
