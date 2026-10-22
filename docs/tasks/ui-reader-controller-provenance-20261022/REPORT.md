# Host Reader operation provenance checkpoint

Independent branch `task/ui-reader-controller-provenance-20261022`, based on original Host checkpoint `97b4d737b01186c73f0c7fa8314aada66d27b868`. This is a dependency-bearing Reader patch, not directly a PR101-only branch. No merge, deployment or Compose/Activity/Rust/FFI edits. Old worktree and Claude branch preserved.

## Changes

The existing controller now accepts `Checked` only from check, and `Replaced` only from renewal after that operation's fresh original challenge observation. A check cannot upgrade its ticket; a renewal cannot pretend a check extended its deadline. The first challenge consumes the operation slot even when malformed; a second challenge cannot replace it. The result callback snapshots sampling provenance on arrival with an AtomicBoolean: later owner-thread observation validation cannot retroactively authorize an already arrived response. Wrong results close the original frame and dispose exact supplied resources; late original unknown retention and stale-A/new-B isolation remain intact.

No native authority or new allow path was added. Existing backend-null and production verified gates remain unchanged. Tests use fault-injected backend/clock/observation fixtures, not actual native, physical Activity visibility, file descriptors or device reading.

## Test-first evidence

- `evidence/provenance-red.log`: four failing product regressions before first fix (check upgrade, unsampled renewal replacement, renewal check, replacement challenge).
- `evidence/invalid-first-challenge-red.log`: independent finding reproduced before fixing malformed-first challenge substitution.
- `evidence/arrival-order-red.log`: deterministic queued-observation/early-result regression before arrival-time capture fix.
- `evidence/final-green.log`: fresh actual Kotlin/JVM runner exit 0, all five groups pass, including >30s synthetic-clock continuation, deadlines/watchdog, cleanup/unknown, A/B isolation, new provenance cases. This is not elapsed device time or native policy execution.
- Command: `KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/run-admission.sh`.
- Android command: `bash apps/muyon_android/gradlew --offline :app:compileDebugKotlin`, exit 2, NOT_RUN: existing Gradle 8.13 executable unavailable (`evidence/android-compile.log`). Trusted PATH/cache checked; no SDK/tool installation, stubs or permission changes.
- `git diff --check`: exit 0.

## Independent review

Non-author review completed with no remaining Important finding. The review's original malformed-first-challenge proof failed before fix and now reports `accepted_replacement_after_invalid_original=0; actual_sampler_calls=0`; both logs are preserved. The reviewer independently ran the entire actual Kotlin runner (exit 0), reviewed result-arrival sampling, old-frame cleanup and unknown retention, and ran diff checks. Evidence: `evidence/independent-final.log`, `independent-invalid-first-red.log`, `independent-invalid-first-green.log`, `independent-source.sha256`. Reviewed Controller SHA256 `372ad24ac669564c6e2ec578508c04e0f2930099a21eb93bc4250975bc897fde`. No subsequent production/test edits.

## Exact native dependencies, still pending

Read-only remote verification confirmed Core `be90295872885b499cc88e983d9146542e0033e2` (`task/document-reader-policy-20261022`) and FFI `1c64ab50021c6183f281ee32f751f2a2876a4e45` (`task/reader-evidence-ffi-20261022`). Core `crates/muyon-core/src/documents/reading_policy/mod.rs` implements source A observe, B begin, C prepare and D renew, plus selection/frame hooks; E original reconcile, F retained-owner stop, G genuine-ticket handoff and approved initial-read admission remain missing. Core source is not verified here: cargo/rustc unavailable. FFI `docs/tasks/reader-evidence-ffi-20261022/CORE-READER-POLICY-ATOMIC-REQUEST.md` fixes required atomic Core facade; no seven-endpoint generated policy ABI exists. Do not copy pre-policy presentation bindings or call a successful mock replacement.

The next owner deliverable is concrete original-attempt reconcile/fence, retained-owner administrative stop, genuine presentation handoff and first-read admission under the existing State/domain and exact selection epoch, followed by actual generation/verification. Host then consumes those exact generated types; no second gateway/owner. Genuine Activity sampler and directory/IPC/PFD remain integration dependencies. Existing user-approved explicit-selection rule is already authorized, not a new permission request: registered source-known local document/current project, no explicit revocation, readonly only. Missing code does not imply permission denial.

Bot prepare is delivered separately on PR101-based `task/ui-host-runtime-resume-20261022` at `ea1d1af2d7d0d3b52bad698405f5b71d7f36e0c5`; its report preserves actual ABI/static and synthetic-consumer limits. Neither branch claims backend save acceptance or Reader >30s device acceptance. No production gate may open from these offline tests alone.
