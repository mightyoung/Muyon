# MCP SDK fixed-candidate gate — HOLD

Read-only assessment, 2026-10-23 UTC. No SDK/package/transport was installed,
executed or wired. Cargo/Gradle/lockfiles are unchanged. This is a partial X3
engineering assessment, not a selection approval or a protocol/Android result.

## Fixed source evidence

Official GitHub GETs resolved both plan candidates; mutable default branches were
not used. Source blob IDs below identify what was read, not published-package
checksums or signed provenance.

| Candidate | Immutable source | Source facts |
| --- | --- | --- |
| Rust rmcp 3.7.0 | Tag object `cdf95e06d7cc2a13f9ff97e3e5d6cf1226630ae9`, commit `5d6a11f2ae022f513aec0f6e0f10f89a57891a7f` | [Workspace manifest](https://github.com/modelcontextprotocol/rust-sdk/blob/5d6a11f2ae022f513aec0f6e0f10f89a57891a7f/Cargo.toml) declares edition2024, rust-version1.88 and Apache-2.0 metadata. [Package manifest](https://github.com/modelcontextprotocol/rust-sdk/blob/5d6a11f2ae022f513aec0f6e0f10f89a57891a7f/crates/rmcp/Cargo.toml) inherits those values. |
| Kotlin SDK 0.15.0 | Commit `76b8e7d63aac39fe41e03684e3b91a6c3724a8da` | [Version catalog](https://github.com/modelcontextprotocol/kotlin-sdk/blob/76b8e7d63aac39fe41e03684e3b91a6c3724a8da/gradle/libs.versions.toml) declares Kotlin2.4.0, Ktor3.5.1 and coroutines1.11.0. [Build convention](https://github.com/modelcontextprotocol/kotlin-sdk/blob/76b8e7d63aac39fe41e03684e3b91a6c3724a8da/buildSrc/src/main/kotlin/mcp.multiplatform.gradle.kts) specifies JVM11 bytecode, language/API2.1 and JDK21 build toolchain. |

The Rust annotated tag was reported unsigned by GitHub. Its source commit is
pinned here; no stronger distribution-integrity conclusion is claimed.

## License/package evidence

The previously missing fixed Rust source license is now readable:
[rmcp/LICENSE](https://github.com/modelcontextprotocol/rust-sdk/blob/5d6a11f2ae022f513aec0f6e0f10f89a57891a7f/crates/rmcp/LICENSE),
blob `30cff7403da04711c46979a06f6bf8eb10ee088a`.
[Kotlin LICENSE](https://github.com/modelcontextprotocol/kotlin-sdk/blob/76b8e7d63aac39fe41e03684e3b91a6c3724a8da/LICENSE),
blob `185054bef9dfb083b7ab2db43908ffa173a0f48e`, is also readable.
Both describe an MIT-to-Apache transition retaining MIT for contributions lacking
relicensing consent, and separate documentation licensing. A manifest's single
license field therefore does not replace the complete source notice inventory.

No NOTICE-named file was found in either complete recursive fixed-source tree.
This does not establish what a published crate/JAR/AAR and its transitive packages
contain. Published artifact bytes/checksums, packaged licenses/notices and exact
dependency closure are **NOT_FETCHED / NOT_REVIEWED**. Source-license retrieval
closes only that narrow evidence gap; redistribution approval remains open.

## Minimum future candidate and Android limits

Recommendation: **keep installation blocked**. If the dependency/host gates are
later approved, evaluate Rust first with an in-memory transport boundary, using
the fixed rmcp3.7.0 candidate, default-features=false and client only. This is a
smallest-feature research proposal, not a minimal dependency closure or an
approved Cargo edit. Source always exposes a sink/stream transport module;
[Transport](https://github.com/modelcontextprotocol/rust-sdk/blob/5d6a11f2ae022f513aec0f6e0f10f89a57891a7f/crates/rmcp/src/transport.rs)
provides send/receive/close. Do not enable server, macros, stdio, subprocess,
HTTP/reqwest or auth features for that initial in-memory evaluation.

The manifest still brings Tokio/futures and other new dependencies even with
those features disabled; current Muyon locks do not approve that closure. Its
declared Rust1.88 floor is below Muyon's fixed1.93.1, but neither transitive MSRV,
actual compile behavior nor Android ABI/API compatibility has been tested.
No TLS/HTTP engine, trust-store or automatic-retry policy is selected.

Kotlin0.15.0 would add another dependency stack and needs separate metadata,
engine and Android API review. Its JVM11 target alone is not an Android guarantee.
The fixed source build convention/client module do not establish an Android
minSdk guarantee. Muyon currently uses Kotlin2.2.20, minSdk26 and JVM17; differing
SDK build-tool versions need artifact compatibility checks, not a conclusion
that either compatibility or incompatibility has already been proved. The
[client module](https://github.com/modelcontextprotocol/kotlin-sdk/blob/76b8e7d63aac39fe41e03684e3b91a6c3724a8da/kotlin-sdk-client/build.gradle.kts)
depends on core and Ktor client-core; its Apache5 engine declaration is in tests,
so it is not a production Android engine selection.

Prefer one Rust-owned Connector authority path with Kotlin platform/credential
adaptation if later approved, rather than two independent execution owners.
That is a recommendation; no architecture/SDK decision is frozen by this report.

## Proposed boundary, not a command API

Existing local `validate_admission`, `validate_lifecycle_change` and `recovery_for`
continue to enforce preflight/unknown semantics. An SDK adapter would own a live
session and only protocol correlation IDs. IntentId/Receipt/C2 remain the single
execution truth; protocol request IDs never replace them.

For later review only, the adapter boundary should separate:

```text
request_catalog_refresh(trusted_original_command, expected_binding)
    -> complete | partial | failed catalog observation
send_once(trusted_original_command, expected_binding, RemoteRequest)
    -> protocol observation + RemoteEffect, never a business Receipt
close_local(session)
    -> local close observation, never a token-revoked or rollback assertion
```

These are semantic proposal signatures, not implemented or frozen Rust APIs.
The trusted-original-command proof and concrete Operation/identity issuer are
unresolved; a decoded approved flag or model-created secretRef cannot supply it.
No public configure/connect/revoke/refresh API may be enabled from these names.

The host must own secret resolution, disclosure/budget limits, consent/scopes,
expiry and revoke evidence. Host-side session creation may not accept raw secrets
or privileged endpoints from UI/Skill. Endpoint or external identity changes and
directory/authorization changes invalidate old prepared bindings. Every explicit
directory refresh is an authorized external operation, not a getter side effect.

Catalog handling must negotiate an explicit protocol range, page all three kinds
within approved bounds, bind schema digests/revisions, preserve partial/failed
observations and reject stale publication. Limits/digest normalization and exact
protocol compatibility range are still gate decisions. Tool descriptions, prompt
text and readOnly metadata cannot enlarge host/plugin grants.

After any possible send, timeout/error/cancel/close retains original Unknown
unless the original owner proves an outcome. No SDK-level retry or reconnect may
silently repeat a business action; local close is separate from remote revoke.

## Required future evidence; not executed commands

After explicit dependency/engine/credential design approval, add a separately
reviewed adapter/test slice with deterministic in-memory initialize negotiation,
three-kind pagination/catalog replacement, malformed schema, stale scope/binding,
send-before-timeout, failed revoke, stream close and duplicate response cases.
The existing original-lookup tests remain the recovery oracle. Exact test files,
adapter signatures and selected dependency lock must be frozen before coding.

Future validation must include offline/locked Rust host regression and both
Android targets (`aarch64-linux-android`, `x86_64-linux-android`), the actual FFI
crate check and Android minSdk26 build/lint. A future command template is:

```sh
cargo check --manifest-path crates/Cargo.toml -p muyon-android-ffi --target aarch64-linux-android --offline --locked
cargo check --manifest-path crates/Cargo.toml -p muyon-android-ffi --target x86_64-linux-android --offline --locked
```

These templates are **NOT_RUN** and do not provision targets/NDK/dependencies.
The exact authorized Android build/lint commands depend on the later reviewed
adapter and existing platform owner. Real OAuth, credentials, accounts, remote
effects and SDK install remain outside this assessment's authorization.

Gate state: **RED / HOLD**. Pinned source and license text read; package closure,
notices, Android, host credential owner, concrete Operation/identity provenance,
consent/revoke semantics, protocol bounds and exact adapter tests are unresolved.
No gate GREEN or SDK compatibility claim is made. X4 provider research remains a
separate design task; MCP does not make GitHub/GitLab/Gitee capabilities uniform.
