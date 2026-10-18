# LeaderB verification and hold decisions

## Immutable sources and independent reviews

A: `4b609602f76996ec69e9f51da8bc4261d6a2d94a`, [Draft PR91](https://github.com/mightyoung/Muyon/pull/91), base frozen PR89 `fc8ffd7e061736fdf9f4897d7c1c7914d429400a`. Six authored/generated/test/workflow paths plus task evidence changed. Trusted Service Kotlin→generated UniFFI→Rust review/reserve/admission forwarding added; no host controller, Dart business code, UI layout, lifecycle, permission or transport change. Source remains frozen after publication; final CI evidence is only on this leader documentation branch.

Fresh independent design review initially REVISE, then approved three corrections (Kotlin generated-interface compatibility, stored full-budget reservation validation, hold/snapshot/expiry semantics). Compiler later proved UniFFI exported Rust methods cannot have default bodies; reviewer inspected actual macro and corrected earlier assumption, approved explicit required Rust methods plus Kotlin source-owner deny defaults. Fresh immutable implementation reviewer found no substantiated blocker for bounded Draft. Reviews/ preserves original revisions and corrected approvals separately. No reviewer claimed real owner installation or merge acceptance.

B executable extraction: `0229fa75f7c0e4ff88d22ef845aa982a83f230a6`, exactly13 original added files from PR87 `38b59db43f2487700ff15971ee008f0024673a13`, parent fixed develop `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`. No130 historical ancestors imported; apps/packages/pubspec trees equal develop. Final [Draft PR90](https://github.com/mightyoung/Muyon/pull/90) head `060e46f1359915e267f849f3807ec1999b29dd8d` includes six fresh evidence files (19 additions total), based fixed-develop alias at exact0ab2c4f. Original PR87/base unchanged. Fresh independent read-only review checked all13 blobs/hash/size manifests, graph, direct APIs/dependencies, raw test evidence and workflow predicates. Root-only last commit removes one trailing blank EOF in a new audit transcript; original13/executable source unchanged. See reviews/memory-and-ci-independent.md.

## PR89 acceptance audit

Requeried GitHub exact original finalfc8 head. Generic [39109951834](https://github.com/mightyoung/Muyon/actions/runs/39109951834) remains completed/CANCELLED, not replaced or relabeled. Original specialized [39109951880](https://github.com/mightyoung/Muyon/actions/runs/39109951880), [39110008555](https://github.com/mightyoung/Muyon/actions/runs/39110008555), [39109953658](https://github.com/mightyoung/Muyon/actions/runs/39109953658) remain completed/SUCCESS. Original cancelled39109952120, skipped39109955916 and earlier failure39109364242 were also reread; raw prior handoff and earlier unfiltered-suite incident retained unchanged. Snapshot evidence/pr89-ci-readback.json.

Generic ci.yml runs scripts/ci.sh (Flutter pub get,8 analyzes, mocked gate/doctor regressions,8 Flutter targets, coverage) plus4 local Laya Python suites. Independent static traversal reached967 local files from471 Dart test entries, no unresolved local imports, no invocation into experimental Rust I04 host/core or new experiment Dart fixtures. Existing HTTP/recovery names are distinct from denied original I04. This is static graph evidence, not a broad runtime certificate. No generic rerun was necessary for this bounded slice; no complete broad suite was run. User authorization for necessary nonI04 checks was not missing; cancellation remains cancellation.

## Actual bounded coverage

- A local scoped integration `--test service_host_bridge`: initial old2 PASS/new6 FAIL behavioral RED after compile skeleton; implementation8PASS, final mapping coverage9PASS. Final clean-source CI must establish immutable artifact provenance because local worker builds used originalfc8 base build id while dirty. No unfiltered Rust suite.
- Host scoped48 are supplier_scope_bridge7, service_provider15, service_host_controller5, supplier_store12, supplier_lab_source5, supplier_business_controller1 and exact supplier_business::terminal_regressions3. Named integration targets plus exact unit filter only, never HTTP/reopen module.
- Genuine generated Kotlin final SHA256 `9e1ab588ba5aa3cc0eb70cc7d7fba36ff34f84281547707959d5d431bf3a626d`; immutable reviewer independently cmp'd /workspace/muyon-worker-a-generated-final output. Unsuffixed directory retains superseded output, never accepted. CI regenerates/cmp from final source.
- Kotlin metadata instrumentation3 assert default refusal, exception refusal and unchanged full objects/bytes/request/budget/reservation/profile-ref forwarding. They invoke the real handwritten callback adapter only, without constructing a native controller or using a source/credential/network. Combined API26 runner retains originalUI/Binder/native synthetic-read/original-receipt/lookup-restart2 tests and requires exact5. This does not test an installed production Kotlin owner crossing new native admission callbacks.
- Frontend scoped job separately runs existing18 Python contract-oracle tests, exact old21 Rust store/terminal cases and genuine binding reproduction. ABI producers build x86_64 and arm64-v8a at API26; actual selected emulator runtime is x86_64 only. ARM64/physical runtime remains NOT_RUN.
- B Python command is exact direct unittest discovery selecting test_failure_lab.py only, source0229fa75;21PASS/0failures/errors/skips, exit0. Stdlib/local synthetic Store only; inspected child workers exit71/72 with temporary SQLite files, no HTTP or product adapter. Original run_suite.py not invoked because it overwrites historical evidence. No repeat tests solely for review.
- B8 actual Dart fixtures remain UNCOMPILED/NOT_RUN. SDKs absent and this round forbids running their loopback/new-ledger/reopen scenarios. Final2 assertions remain STATIC_EXPECTED_FAIL only: generic request succeeds before blank-chat/embed-count response validation. No observed runtime failure claimed, no skip edit or production Dart fix. Historical old24 tests distinct/NOT_RUN this round. Full logging matrix/actual production adapter semantics remain unverified.

## Failures and limits preserved

Worker A retains initial missing-build-id environment compile101, missing-new-API compile101, UniFFI exported-default-body compile101, actual behavioral RED old2PASS/new6FAIL, and first bindgen missing-cargo-PATH failure. Adding Rust documentation later changed UniFFI metadata/checksums: final cmp caught stale generated output before commit, genuine rebuild/regeneration corrected it. No hand checksum editing, failure suppression or false behavioral proof from compiler errors.

Full final git diff --check on A returns2 ONLY for preserved raw Cargo stdout blank EOF lines in FINAL-RUST.log/GREEN-2.log/GREEN.log. Root separately checked authored/generated/test/workflow/docs paths excluding raw logs: exit0. Worker precommit blanket whitespace statement saw logs untracked; this record corrects the final scope. Raw logs remain byte-for-byte intact. B's new audit transcript trailing blank was corrected after ownership release; root check exit0. These formatting checks are not behavioral gates.

## Production blockers and integration disposition

New seam accepts only trusted bootstrap owner callbacks. Existing Kotlin owners deny/null and exceptions deny/null. Rust preserves complete current binding/payload/budget and existing gate checks. No actual durable reviewer/quota/outbound ledger, production source/profile owner, secure credential capability or transport is installed. Existence sentinel remains Rust-only correlation metadata, proves neither actual handle identity nor rotation and cannot read/send a secret. ConfiguredChat remains configured_transport_unavailable, no synthetic fallback.

A future durable owner must capture full actual CallBudget at reserve, prove conservative total input+output token/spend/one-call bounds, atomically recheck current binding/credential existence/exact reservation identity and consume once, handle replay/concurrency and expiry. Full binding comparison after reserve means changed exposed counters/revision fails closed and may leave a hold needing owner cleanup. No automatic resend. Real owner installation, payload/budget metering, actual handle use, transport/cancellation/usage/recovery, billing/live model and ARM64 device runtime remain unbound/NOT_RUN.

PR91 depends on held PR89/88/86 chain; HOLD persists even if these new scoped gates pass. PR90 lacks actual Dart compilation/runtime and original acceptance gates; fixed base is safe Draft isolation, not a merge exemption. Neither candidate qualifies for develop merge. No main/develop integration, force push, branch deletion or deployment.

Original denied action: legacy script task.db→HTTP→original-state reopen (I04), platform DENIED_BEFORE_EXECUTION for possible cybersecurity risk in prior session; still DENIED/NOT_RUN, not retried/rewritten/split/alternate executor/full-suite-triggered. PR86/dependent combinations remain HOLD. No credential read/configuration, real/paid model call, new license acceptance, privilege expansion or Mac sync write workaround. UI frozen; Rust core/Kotlin API26; no Dart business implementation. All writers released.

## Final exact-source CI terminal readback

All rows below identify source `4b609602f76996ec69e9f51da8bc4261d6a2d94a`, run_attempt1. Root dispatched each named workflow once only after the automatic PR predicate run had completed; no reruns or cancellations this slice. No source/evidence push occurred on product branch during CI.

| Run | Terminal | Actual scope |
| --- | --- | --- |
| [39126115051](https://github.com/mightyoung/Muyon/actions/runs/39126115051) | SKIPPED | Automatic PR Compose branch predicate; no pass substitution. |
| [39126154622](https://github.com/mightyoung/Muyon/actions/runs/39126154622) | SUCCESS |2 jobs: named host48, Android adapter Rust9, genuine Kotlin generation/cmp, clean source. |
| [39126156490](https://github.com/mightyoung/Muyon/actions/runs/39126156490) | SUCCESS | JVM checks, AIDL/Kotlin/generated bindings, app/test APK compilation, unit-test Kotlin compilation and lint. This job alone does not prove runtime. |
| [39126158381](https://github.com/mightyoung/Muyon/actions/runs/39126158381) | SUCCESS |4 jobs: scoped regressions/generation, API26 x86_64+arm64-v8a ABI builds, exact-source combined package and actual x86_64 API26 instrumentation5/5. |

Actual instrumentation.log in final API26 run names both original FrontendServiceLoopTest cases and all3 ServiceHostBindingsTest cases, then `OK (5 tests)` (12:16:54 UTC). Build marker explicitly identifies source4b609602. Android_runtime=NOT_RUN in build-stage package-result is intentionally an earlier stage declaration; later successful instrumentation establishes selected emulator runtime, not production owner/native admission callback installation or ARM64 device acceptance.

[Package/device artifact12136486991](https://github.com/mightyoung/Muyon/actions/runs/39126158381/artifacts/12136486991), ZIP metadata size22,662,145 bytes, contains combined APK/test APK and device evidence. Root did not download/replace a user artifact or install on a user device. This ZIP size is not APK size and no APK hash is inferred. Source/producer matching is enforced by package script and same-run source/build-id manifests; exact artifact metadata retained in evidence/artifacts-39126158381.json.

Raw full logs and SHA256:

- scoped39126154622:134,649 bytes, `074e8117e59c36cdbd98294a3897e864b0c3c129500c449f7b1ba2a7766023a0`.
- Compose39126156490:90,398 bytes, `3262b21fb5bce3ead893a6a56180bcf42332714cf80c5402ad22d3dfe1c4caa7`.
- API26 loop39126158381:228,122 bytes, `8c58f54c0c75671c3362943dbbfdf483285984e29f6df65da94905877ca19905`.

Final jobs/status/source evidence/pr91-ci-terminal.json and per-run JSON accompany raw logs. Original PR89 generic remains CANCELLED; PR90 has no workflow runs and generic CI_NOT_RUN. Scoped successes do not resolve dependency HOLD or remaining real-owner/Dart/production gates. Both candidates remain Draft; no develop/main merge.

PR91 body was updated with final review/CI facts only; source head remained frozen and Draft. `gh pr edit` failed on deprecated GraphQL projectCards access. Root read the current body first (unchanged), then PATCHed the same metadata via GitHub REST and read confirmed body/head/Draft. This is a metadata-tool error, not CI failure or platform action denial; no duplicate source write/run or denied I04 retry. No unresolved action outcome remains.
