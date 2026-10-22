# Independent review: actual product708570 minimum runtime smoke

No blocking or Important finding in this bounded smoke evidence/report. Product
source remains `708570d59ea51024ee69bb62c97f63380d490f78`; current evidence-only HEAD
`1e15af457fccead7eb1e89b6d1096a9f39ac319f` has no additional apps/crates/workflow
source diff. This is the actual product APK runtime, not the earlier component
harness. It explicitly excludes subsequent PR102/Office/Bot composition and must
not be transferred to a new candidate. Reviewer only reads existing evidence and
writes this file; no device operation, build, model run, network or Library action.

## Exact installation and startup evidence

Product APK426369208 bytes, SHA256
`f1cc240fd981a1ea08841f3964c6422e5b240268984447022406428723ddeb0b`.
Archived normal Android shell device-apk-sha256.txt reports this exact hash for
the installed product base.apk, connecting the installed bytes to the previously
statically verified product artifact. No production APK rebuild or replacement
with a synthetic harness is implied by the instrumentation-only probe.

Preflight records boot1, package absent and Accounts0 in the task-owned guest.
Install progress represents one session1358214155 followed by Success, not a
blind repeated installation after an uncertain result. Cold activity launch
Status:ok4404ms, initial screenshot/hierarchy shows explicit new-workspace action.
After that visible local initialization, main is empty, not seeded business data.
Menu-open hierarchy contains the main/pinned heading; explicit-close and Back-close
hierarchies remove it. Launcher foreground after Activity Back is recorded, then
relaunch Status:ok2180ms. Slow-operation/lifecycle warnings remain in the log;
no FATAL EXCEPTION/Fatal signal found in the captured activity-runtime-log. This
is not an exhaustive crash/performance or all-lifecycle test.

## Probe and authority boundary

Reviewed actual archived RuntimeHealthSmokeProbe.kt and prior startup source path.
The probe binds the real ProductClient and calls only health and agent_availability,
asserts the exact build identity, synthetic=false and configured=false, then closes
client in finally. External test-source init only adds instrumentation code; the
shipping product APK source/bytes remain unchanged. No configure/prepare/confirm/
send/search/credential installation/inference is called by the probe.

probe-instrumentation.log contains exactly the specified one test, status0,
OK(1 test),1.636s, normal terminal code-1. runtime-health.log records real service
PID3070 and build identity:
`708570d59ea51024ee69bb62c97f63380d490f78:95d79703ba3b05f9af3020118286fb5559f17c7042d183cee394074dc25ae811`.
Native health synthetic=false, workspace local-workspace; availability configured
false, chat/search configured=false and transport_bound=false, local_reads=true.
These are actual logged Service/native health observations, not inference output.

MainActivity bind/health and explicit initialize paths were statically checked;
Service creates the memory-only empty credential vault, native open performs local
store ownership/recovery/GC, initialize creates the new local store, chat entry
reads local availability/scope. Fresh-package/no-account prerequisites matter:
this review does not authorize clearing/replacing existing user data. No original
unknown request, fee reconciliation or existing user workspace was retried.
Current bounded actions provide no observed provider binding/request; this is
not a whole-device packet-capture proof of no networking by any process.

## Four actual product PNGs and metadata

Independently checked all four PNG SHA256 and byte counts against screenshots.json,
PNG signature/dimensions1080x1920, Pillow verify plus full pixel load. Visually
inspected all four: cold-uninitialized, main-empty, menu-open, menu-back-closed.
Each depicts actual product UI and no ANR/permission overlay; XML surface labels
correspond to the named states. Menu shows only the real main Agent and no invented
recent conversations. Main shows empty text composer with disabled send; it does
not demonstrate model output, bubbles/history or disabled Office/Bot capabilities.
No image generation, cropping, retouching or reviewer byte modification performed.

Recorded environment is API26/x86_64/1080x1920/420dpi/font1.0, system night mode yes.
Metadata/filenames identify fixed708570 and PRODUCT-RUNTIME-NOT-PR102. The synthetic
fixture label used for prior component previews is not transferred: these are
actual fresh empty product-local states. No PR102 runtime acceptance is claimed.

## Reporting and held delivery

PRODUCT-RUNTIME-SMOKE-708570.md accurately narrows the result to install, cold
startup, explicit local-empty workspace initialization, menu/Back/re-entry and
real health/unconfigured-provider probe. REPORT's new opening explicitly marks
prior NOT_RUN text as the preceding packaging milestone. No claim of inference,
authoritative ReaderHost/FFI/document/receipt integration, all UI completeness,
PR102 or forthcoming B candidate is made. The minimum smoke advances the earlier
product-runtime-NOT_RUN milestone only for these exact708570 actions.

Licence-only ZIP metadata independently matches actual31422-byte file, SHA256
`2b0cdeadda55e3ebcd04de464f4fb7e8719702959de828e57de827d0cf812c2a`;
inspected16 ZIP entries and found no APK. It is only prepared. Parent superseded
the old conditional upload instruction; reports/metadata explicitly mark old APK,
PNG and licence Library preparation/upload/finalization as not started and HELD.
Reviewer did not access Library and asserts no remote delivery. Previously prepared
large ZIP is likewise not a completed upload. Wait for B's exact released new SHA;
rebuild, reverify and smoke that composition without inheriting these results.

## Sealed evidence hashes

- `PRODUCT-RUNTIME-SMOKE-708570.md`: `3132bf67c3b8797200bf5e5e7504728ea37faaa0f8f241f2f381aa61e969967a`
- `REPORT.md`: `b8667eb324a44d4b1a780220ff67240c1504ab6b3feff35bc962f4b52f27e86b`
- `evidence/product-runtime-708570/screenshots.json`: `9c508c0fef63a16eecaef9f9fdd3c0247db353be5f0918e85a168f14b1fa472a`
- `evidence/product-runtime-708570/device-apk-sha256.txt`: `53844b6cb3c3c8fe74933b3cab21f121bbe8db5bbaf77300d5a2f8139f1ccf82`
- `evidence/product-runtime-708570/probe-instrumentation.log`: `10c58d89ee7c732ddef6395c8e34a5b3214d261ac9af93f254d93b5c39511a2e`
- `evidence/product-runtime-708570/runtime-health.log`: `fcf14dabb52deeb2b7abfb15402690381e7baec776754dd961a6154814138ae6`
- `evidence/product-runtime-708570/RuntimeHealthSmokeProbe.kt`: `63de1c8f0357272909b516f1337c2f106df7511462ee9777aabcdf09d5367e56`
- `evidence/product-runtime-708570/licence-attachment.json`: `b512dc8792a036acab8080d439e06b307070d77a1061622a86512539714b95ab`


Artifact isolation supplementary check: source-only androidTest output is restored
to original fa0c08ed932d8a28f439601a224e45c0a4854ad73ec3983d6ef396287ba01d1d;
external probe APK is independently retained as69088e81773a6f40fb77711200e938dc9cd0ba9a8a19b26ab0aa1f3791d7bcf4.
Reviewer rehashed both distinct outputs and confirmed the isolation record. No
source or shipping product byte change is implied. The probe APK must not replace
the source-only test artifact in later delivery or reproducibility claims.

- `evidence/product-runtime-708570/artifact-isolation.json`: `9a59cea575320788ed3fab5fd2329802da2fddb5927fe49d38bd38250d80196e`
