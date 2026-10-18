# Active integration — supersedes preparation-only ownership status

Parent explicitly transferred the existing host/AIDL/agentipc/shared Gradle/UI paths after B06 stopped all writers at final handoff `6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa`.

Independent integration branch: `lab/android-compose-frontend-loop-20261018`. No main/develop/PR86 merge.
Candidates were fetched at full SHA, then bounded dependency commits were cherry-picked rather than importing unrelated memory work from B ancestry:
- A `3f3a2368648db5e9767f11adcae4548ac5da2527`: default-off observer prerequisite, min26, V2 native packaging and release regeneration fix.
- B `190477fe0e5008d473508e45d2d835ddd5e0c09c`: only nested Flutter test isolation commit.
- C `fdc9aea120925229aa592c3551efab9b3f67a825`: supplier readonly implementation and dedicated CI commits.
- UI `d3572ea5e74996f468952f16b095775f59ea37b3`: all five Muse candidate commits.
- B06 final record commits retained. PIP `853687cb0ce7d7e0133808f05a07258175c6b486` fetched but not integrated; no new untrusted plugin route added. OCR deferred.

## Actual source connection

Muse `ChatPage` Send → `MuyonLabShell` → `Application.chats` → `AgentChatReadSession` (identity persisted before submit) → existing `AgentServiceClient` connection/lease/background lane → bounded private `IAgentRuntime.submitSupplierRead` → existing `:agent` Service/GeneratedAgentController → genuine generated UniFFI → same `AgentServiceController` root/worker/control → `supplier_business` durable payload ledger → `run_lab_supplier_read` → actual readonly schema12 SQLite → registered Catalog/NativeSession/Rust Agent dispatch → `native.db` ORIGINAL receipt → bounded cursor events → native/Binder → conversation-specific answer, supplier projection and original receipt.

This is deterministic local supplier reading on an explicitly synthetic real-schema copy. Text reaches Rust Agent State; no model chooses tools or generates a response. The answer is a typed local business-result rendering. The four ordered result events are returned as a cursor batch after this small read settles, not a model token stream. Production user-store/scope bridge remains unavailable and fails closed for any nonfixture selection. No live model provider/credential/budget binding has been added.

## Source and local tests

- Frontend `8063eced`, device acceptance source `dedd3295` + `f8207487`.
- Store `4f61d9af`: Linux targeted supplier checks 17/17 PASS.
- Same-controller/Rust `dddc3805`: targeted service/runtime/business checks 7/7 PASS.
- Android IPC/generated binding `018eb4f0` + `e74138c3`: required Kotlin state gate PASS, including new chat bounds/recovery and frontend policy checks.
- Root independently ran `cargo test --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test supplier_store --test supplier_lab_source --test supplier_business_controller -- --nocapture`: 18/18 PASS; raw `integration-logs/rust-scoped.log`.
- Contract oracle 18/18 PASS. Python/YAML syntax and `git diff --check` PASS.
- Rust1.99.0 installed from official rustup per existing CI; Kotlin2.2.20 official release archive matches existing repository SHA256 `81f0264c9073b5cbbdb3ff8418cf2c5dac076879fc156fa1a6462f5a5acc4420`. No Android license accepted locally.
- Android uses pinned `libsqlite3-sys=0.35.0` bundled C build (public SQLite) rather than hidden platform SQLite ABI; prior registry dependencies kept at existing lock versions.
- Immutable source review requested at `e74138c37b3e5786291dba3f066e84ae72df2c99`, diff from combined candidate base `1d1437e6`.

## CI/device gate

New targeted workflow `.github/workflows/frontend-service-loop.yml` runs only explicitly scoped supplier targets and the oracle, reproduces generated binding, builds both native API26 ABIs through the existing V2 producers, verifies same-source manifests/actual APK contents, and executes only `FrontendServiceLoopTest` on API26. It uses runner's existing SDK license state and contains no license acceptance command. It does not dispatch the held manual release-artifact workflow or any HTTP/legacy test suite.

At this record, CI/device results are PENDING, not PASS. Device test covers actual UI input, receipt/name/terminal display and a separate live :agent PID; also validates disabled invalid input and independent Save behavior.

## Test-scope incident (do not retry)

Store worker erroneously ran `/workspace/toolchains/cargo/bin/cargo test -- --nocapture` from host/core once. This executed seven host library unit tests including five `http_recovery_tests` in fresh `/tmp/muyon-http-recovery-*` directories, plus eight contract transport tests; then six `host_http` tests failed at missing `MUYON_PLUGIN_CHILD`, exit101. Full raw log is `evidence/store-cargo-test.log`. It was stopped/finished before discovery and was not retried. This was an unintended test-scope error; no I04 original old-state input was used. All further verification uses an explicit target allowlist. I04 original denied operation and dependent merge holds remain unchanged. This event is not omitted from the failure ledger or counted as integration acceptance.

## Latest read-only inherited CI/ref observation

A original generic run39102166368 remained `in_progress` at the latest check; same original SHA3f3a2368, not cancelled or retried. Dedicated39102166352 is green but cannot substitute its outcome. Remote main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`, develop `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`, PR86 OPEN/unmerged at source3f1be180 on latest readback. These refs were not modified.

## First platform CI and review correction

- Source `4836aeee94afe871443b852d08b637fe0c7e23f0`: [Compose build39104528534](https://github.com/mightyoung/Muyon/actions/runs/39104528534) SUCCESS (actual AIDL/Kotlin/app/test APK compilation, lint, JVM checks; runtime NOT_RUN).
- [Loop39104528559](https://github.com/mightyoung/Muyon/actions/runs/39104528559) FAILURE: native arm64-v8a and x86_64 producers SUCCESS; scoped supplier tests had 2 FAIL because new test helpers inherited runner umask022. Package/device correctly SKIPPED. Test helper corrected at `0d15d5cb` using explicit private creation; same umask022 RED→GREEN 5/5. Production mode checks unchanged.
- Independent immutable review at `e74138c3` found four blockers (final-ledger UNKNOWN polling, pending-submit cancellation, historical receipt availability, bootstrap callback completion). New immutable review at `93beaf18ff553db0e5d54feabb54c949cfc1a4e3` marked all four ADDRESSED with no new serious defect. Raw reports retained.
- `ccbc3a72`, `d14b9426`, `a9c13341`, `93beaf18`: cancel/no-dispatch token, exactly-once bounded submit/query completion, historical receipt display, UNKNOWN terminal/history, before-dispatch task identity persistence and payload-only receipt recovery.
- Additional wire correction `2a763bdf`: legitimate unknown+terminal replies preserve their native reason; no poll/resubmit.
- Root separately ran the exact `--lib supplier_business::terminal_regressions` filter: 3/3 PASS, seven unrelated unit tests filtered out. No broad or HTTP suite run by root. CI explicitly uses the same module filter and asserts the three-test count.
- Actual implementation wire is documented in [WIRE.md](WIRE.md); preparatory oracle remains a design model, not Android JSON codec conformance proof.
- Source whitespace checks PASS for `.rs/.kt/.py/.yml/.toml`. Raw logs are preserved byte-for-byte, including trailing blank lines; full patch whitespace checks may report those evidence-only lines.

Next exact-SHA CI result is still pending until its own jobs complete. Earlier native/compile successes are not substituted for the corrected composition.
