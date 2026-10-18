# Service production bridge verification

Product source: `fc8ffd7e061736fdf9f4897d7c1c7914d429400a` ([Draft PR89](https://github.com/mightyoung/Muyon/pull/89)), stacked on frozen `ff792336d3c52ee8874ccfa2b80b19beb71f72e5`. A git diff confirmed ff792336 and accepted2f8f4da6 have identical experiments/.github/apps/packages product trees. No main/develop merge, force push, deletion or deployment occurred. Independent immutable review found no remaining substantiated blocker; see reviews/.

## Exact final source

| Evidence | Final result |
| --- | --- |
| [Scoped CI39109951880](https://github.com/mightyoung/Muyon/actions/runs/39109951880) | SUCCESS. Host Rust48/48, Android owner bridge2/2, genuine Kotlin regeneration+cmp and clean source. |
| [Compose CI39110008555](https://github.com/mightyoung/Muyon/actions/runs/39110008555) | SUCCESS. JVM state/source-kind checks, AIDL/Kotlin/generated bindings, app and test APK build, lint. |
| [API26 loop CI39109953658](https://github.com/mightyoung/Muyon/actions/runs/39109953658) | SUCCESS, all four jobs. Both API26 ABI builds and real x86_64 instrumentation2/2 PASS, including private Service process death/lookup-only original receipt recovery. |

Rust48 means supplier_scope_bridge7, service_provider15, service_host_controller5, supplier_store12, supplier_lab_source5, supplier_business_controller1, exact terminal_regressions3. This is a scoped suite, not the complete Rust suite. No unrelated legacy HTTP/reopen unit module ran. The loop workflow also reruns the old21 scoped Rust regressions, Python oracle18 and real binding reproduction. Both ABI producers are API26 builds; only actual x86_64 instrumentation can establish runtime acceptance. Native ARM64 build does not establish ARM64/physical-device runtime.

Accepted combined APK is23,581,948 bytes, SHA256 `6dfdc49cad9beed6b93275b66b42c72e8b0c28898eea79656c0d215c6b989198`, artifact[12129383864](https://github.com/mightyoung/Muyon/actions/runs/39109953658/artifacts/12129383864). Package/bridge manifests independently identify the exact fc8ffd7e source and API26. package-result.json was written at build stage with Android_runtime=NOT_RUN and is retained unchanged; later instrumentation.log/device-result.txt and the successful package-device job establish actual API26 runtime. No user-device install/uninstall or Library replacement occurred.

Accepted geometry trace recorded label/list zero bounds and visible-window bottom391 before/after scroll, then nonzero label Rect(175,191,296,207) and window bottom640 after the bounded display wait. Actual visibility and all business assertions passed. This supports waiting for settled geometry in this run; it does not retroactively prove a specific IME cause for the prior failure. Markers also show private agent PID4593→4617 with unchanged original receipt identity. See evidence/accepted-runtime-markers.log.

The five host-controller tests cover registered read and revoked redisclosure/restart, logical owner changes, same-byte atomic DB inode replacement, managed-root replacement with preserved DB inode, missing profile, and valid profile+HANDLE readiness ending at configured_transport_unavailable without scope read, payload preparation or outbound admission. Fixture source, metadata and opaque handles are synthetic. Owner adapter tests cover typed current mapping, fresh callbacks, handle existence/revocation and unavailable payload review.

Generated Kotlin SHA256: `0422df1001841d8a487e1f47a78c306febc7fa52973d86f942d2d2dae78e76a7`. Exact CI artifact provenance is in evidence/generated-binding.json; no manual generated edits. Runtime bridge code remains identical to reviewed f5b058eb; fc8ffd7e only adds bounded instrumentation visibility synchronization and geometry diagnostics. No production layout or save logic changed.

## Failures, cancellations and limits retained

| CI | Source | Outcome and meaning |
| --- | --- | --- |
| 39108516976 | 9ec0b630 | FAILURE, initial new modules absent; compile RED only, not behavioral proof. |
| 39108598253 | 40143d61 | FAILURE, fail-closed constructor skeleton caused0/2 controller behavior RED; cargo stopped at that target. |
| 39108632445 | 8819425c | FAILURE, separately exercised skeleton behavior RED: scope2PASS/5FAIL, provider3PASS/5FAIL, controller0PASS/2FAIL. |
| 39108756938 | 1248118b | FAILURE, Android callback skeleton actual fresh-call count0vs2; old skeleton tests still RED. |
| 39108756603 | 1248118b | FAILURE, source-kind helper stub failed ChatReadChecks line22 in actual JVM check. |
| 39108818671 | 71016974 | FAILURE. scope7PASS; provider11PASS/4FAIL exposed payload budget/type defects; controller InvalidRoot exposed fixture0755vsrequired0700 before business assertions. No production directory check was weakened. |
| 39109033480 | 967ec1ae | FAILURE. provider15PASS, scope7PASS and old21PASS; controller2PASS/2FAIL precisely reproduced physical DB/root replacement. Android1PASS/1FAIL because non-JSON fixture stopped before desired review rejection; only fixture corrected. |
| 39109181290 | 2f51e704 | FAILURE overall despite all48+2 behavior tests passing: coordinator invoked bindgen from repository root and cargo metadata could not find Cargo.toml. Corrected working directory only. |
| 39109250035 | 9b9b3543 | SUCCESS. All48+2 and genuine generation passed after cwd fix. |
| 39109362168 | f5b058eb | SUCCESS, prior candidate scoped48+2 and genuine binding cmp. |
| 39109496219 | f5b058eb | SUCCESS, prior candidate JVM state checks, app/test APK compile and lint. |
| 39109364242 | f5b058eb | FAILURE, actual instrumentation1PASS/1FAIL: private Service read/original receipt/process death and recovery passed; local-save label existed but assertIsDisplayed failed. Baseline save/layout/IME/auto-scroll and test were unchanged; specific IME resize cause unproven. fc8 adds10s wait for actual visibility, retains original assertion, logs geometry, and does not change production UI. Raw failed APK/log artifact12130285785 is retained; ZIP SHA256 a9db42159548b80bb3940cf55b758d21cfbbd71e0703a21263e7a14470ef4093. |
| 39109952120 | fc8ffd7e | CANCELLED by the same Compose PR-synchronize concurrency race; no test ran. |
| 39109955916 | fc8ffd7e | SKIPPED by PR branch predicate. After it completed, independent dispatch39110008555 was created. |
| 39109362655 | f5b058eb | CANCELLED by Compose workflow concurrency when PR89 caused a same-branch event; no passing substitution claim. Raw logs retained. |
| 39109426108 | f5b058eb | SKIPPED by PR branch predicate; it nevertheless participated in Compose concurrency. A cancellation request after it completed had no effect. New independent dispatch39109496219 retains the original cancelled run. |

Root cancelled only its own automatic broad Flutter ci runs to keep work on the selected native suite:39108516868,39108598285,39108632437,39108756870,39108818748,39109033471,39109181288,39109250019,39109362165,39109951834. All terminal statuses and exact heads are in evidence/ci-runs.json. Their cancellation is not a successful broad Dart test. The final automatic run39109951834 reached the broad analyze step: muyon_module_api, muyon_ui and prototype_module analyses passed before cancellation; no complete Dart-fixture acceptance is established. Others were cancelled in Flutter setup. Coverage-upload missing-file errors after setup cancellation are retained in the raw logs, not hidden. No unfiltered Rust suite was executed in this slice. No new Dart feature was added. Direct gh artifact download returnedHTTP403; the authorized connected GitHub artifact download succeeded, with source/hash checked before using generated output. This was an artifact delivery issue, not a model/test call.

All earlier failed/cancelled runs and the previous worker's accidental unfiltered Rust-suite/missing MUYON_PLUGIN_CHILD incident remain in ../frontend-service-loop-20261018/FINAL-VERIFICATION.md and its raw logs, unchanged. Nothing here converts those events into success or retries the denied I04 input/action.

## Actual usability and remaining gates

Shipping default remains explicit SyntheticLab. The new trusted Application/Service owner installation path is callable code, not an installed production owner. API26 default entry evidence remains deterministic synthetic schema12 supplier reading, ordered result batches, ORIGINAL receipt and lookup-only Service restart recovery. New current-policy/source/profile/HANDLE tests use controlled synthetic owners. Actual Kotlin installed-owner callback invocation against production state, production user DB, actual secret handle usage, durable quota/review/outbound ledger and real model are NOT_RUN/unbound.

The Android provider adapter checks current non-secret metadata and existence-only sentinel; its payload review, reserve and admission methods deliberately return unavailable. Generic Rust admission ports require an actual trusted durable owner but this slice does not install it. Even valid configured metadata reaches configured_transport_unavailable and cannot dispatch a synthetic substitute. No INTERNET permission, real transport, paid call, credential read/create/configuration, license acceptance or scope expansion was added. No model-token streaming or arbitrary chat acceptance is claimed.

I04 legacy script→HTTP→original-state reopen remains denied and was not retried, rewritten, split or run in another environment. No new HTTP route depends on it. PR86/dependent merge hold remains. PR87 remains separate at38b59db43f2487700ff15971ee008f0024673a13; old24,21 synthetic Python PASS and8 actual Dart fixtures UNCOMPILED/NOT_RUN remain distinct. REMORY experiment gate and RSI exclusion remain unchanged. All code writers stopped; only root produced this evidence after product freeze.
