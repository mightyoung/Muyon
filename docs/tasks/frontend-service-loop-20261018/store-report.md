# Android supplier source bridge

Implemented in the assigned store paths. The Service Rust worker owns the controller/module declarations and census; the integrator owns the Android-only bundled SQLite Cargo dependency and locks.

## Actual path

`run_lab_supplier_read(run_dir, text, key, revision, RunControl)` validates the fixed host-owned synthetic selection, installs an embedded actual-domain-schema12 SQLite copy with `create_new`, validates its exact bounded bytes, then uses `SupplierReader` → `NativeSession::service_in_process` → registered `inquiry.supplier_name` Catalog dispatch → existing read-only SQLite handler → ORIGINAL ToolRegistry durable receipt in `run_dir/native.db`. No `read-*` child directory is created. This uses the existing private `:agent` Service isolation boundary when Android invokes it. The store bridge does not install arbitrary external plugins.

`SupplierReadResult` includes the actual Agent task/attempt IDs, accepted projection and unchanged receipt reference. The receipt reference remains `{owner, invocation_id, binding_id, identity}`. `validate_lab_supplier_projection(run_dir,key,revision,projection)` reopens and validates the host-owned source and exact current projection without another tool dispatch or replacement receipt. Missing/tampered source and mismatched projection deny replay.

The Android fixture is `app/src/main/assets/synthetic-supplier-schema12.siq`, embedded into Rust; size 20480 bytes, SHA256 `844109f40c8b47afe82bf4b3fdf2366bdd84345e0f983178d94c48b2346ac364`. Its only selected object is inquiry/supplier key `11111111-1111-4111-8111-111111111111`, revision `7`, name `合成供应商甲`. It has the actual meta/supplier domain12 DDL and dense supplier JSON. It is synthetic, not a user DB or a production authority bridge. Other objects/revisions fail `production_supplier_scope_unavailable`; no path, SQL or authority is accepted from the UI. The private fixed synthetic authority disables model use. Production ScopeResolver/current policy bridging remains unavailable and fails closed.

Linux retains the existing libsqlite3.so.0 ABI. Android retains the same read-only wrapper but links public bundled SQLite via Android-only libsqlite3-sys 0.35.0, avoiding Android private platform sqlite symbols. The wrapper still exposes no SQLite create/write operation; only the host fixture installer writes the separate synthetic copy.

## Validation

PASS: scoped `cargo test --test supplier_lab_source --test supplier_store -- --nocapture`, 17 tests (5 new bridge, 12 existing C supplier). Full output: `evidence/store-targeted-test.log`. Includes original durable receipt identity, task/attempt binding, same run file layout, exact fixture preservation, unrelated-object/revision rejection, cancel-before-read, tamper replay failure, historical receipt unchanged and symlink refusal. Existing C tests cover schema/payload budgets, source mutation, unknown/revoked authority and business byte preservation.

Tests were authored before the new source implementation. Initial test execution was blocked by another worker's intermediate controller syntax/module changes, rather than observing the intended feature failure. Consequently strict TDD red evidence is NOT established. Later scoped tests pass. Existing core host_session.rs emits the two pre-existing suspicious C read/write signature warnings.

NOT_RUN here: Android cross-build/device execution, JNI/Binder/UI path, production DB/ScopeResolver, real model/API. `rustfmt` initially unavailable; no component was installed by this worker. Independent fixed-SHA review belongs to integrator after commit.

## Test-scope incident (not a successful full-suite claim)

This worker mistakenly ran `/workspace/toolchains/cargo/bin/cargo test -- --nocapture` in `experiments/redesign/rust-agent-host-lab/core`, with CARGO_HOME=/workspace/toolchains/cargo, RUSTUP_HOME=/workspace/toolchains/rustup, CARGO_TARGET_DIR=/workspace/build-targets/store. This violated the requested HTTP/reopen test exclusion. It is completed, exited 101, and is not running or being retried. Complete retained output: `evidence/store-cargo-test.log`.

The command executed 7 lib unit tests, including http_recovery_tests (fresh `/tmp/muyon-http-recovery-5266-*` loopback states; the log records sent=312/received=174), and 8 contract_transport tests. It then ran host_http; all 6 failed immediately on missing plugin-child environment, so Cargo stopped. Failed names: loopback_answer_uses_gateway_review_and_shared_durable_budget; loopback_budget_and_initial_authority_refuse_before_socket_bytes; loopback_mismatched_session_refuses_before_ledger_or_connection; loopback_receive_budget_stops_partial_response_without_retry; loopback_truncation_cancellation_and_revocation_never_resend; loopback_unknown_inflight_crash_blocks_same_state_retry. The loopback recovery unit operations did execute; this report does not relabel them as NOT_RUN. No legacy state was supplied, but the prohibited suite was reached. Parent was immediately notified after inspecting the complete log and instructed no further broad/HTTP/reopen tests. Only the two explicitly assigned supplier targets were subsequently run.

## CI umask fixture correction

CI run 39104528559 exposed a test-only portability bug: `Run::new` used `std::fs::create_dir`, so runner umask022 produced a 0755 run directory. Production correctly rejected it with `private_directory_required`; the initial environment's umask077 hid the fixture defect. Reproduced RED under explicit `umask 022`: 3 passed, 2 failed (`synthetic_schema12_read_uses_same_run_original_durable_receipt`, `replay_revalidates_source_and_exact_projection_without_creating_new_receipt`), exit101. Log: `evidence/store-umask022-red.log`.

Changed only the new test helper to use `muyon_core_agent_lab::store::create_dir`, which explicitly creates a private0700 directory. Production checks/runtime are unchanged. GREEN under explicit `umask 022`: `cargo test --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test supplier_lab_source -- --nocapture`, 5 passed, exit0. Log: `evidence/store-umask022-green.log`. No broad suite or HTTP/reopen target was run for this correction.
