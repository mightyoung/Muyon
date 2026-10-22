# Immutable APK harness scoped review

Fixed harness `210b1ddac609c5546394c66c082d2a2ebb921e92`, isolated branch `verify/frontend-service-device-20261018`; reviewed diff `296d0fa3→210b1dda` and its directly relevant workflow provenance/gate context. Read-only; no test, process, HTTP or model operation executed.

**No gate weakening or source mixing found.**

- Harness checks out exact product source `73a582d3c948d70450a45da4205435a715eeb6b4` and downloads the named original combined package artifact from fixed producer run `39106124839`. Before installing either APK, it requires checked-out HEAD, configured source SHA and producer package-result source SHA to match, requires build PASS/min API26, and verifies both app/test APK SHA256 values against that original producer record. No APK rebuild or test-source replacement is introduced. Harness SHA and product SHA are separately recorded.
- The only new execution control is `timeout 240` around mandatory instrumentation. With `set -euo pipefail`, expiry fails the pipeline; it cannot produce a false PASS. Existing exact `OK (2 tests)` requirement and failure/crash rejection remain mandatory.
- Explicit shared ANDROID_AVD_HOME applies to both AVD creation and emulator launch; device connection remains bounded by timeout300, boot completion is explicitly required and actual device SDK must equal26. Existing original APK install and UI/Binder/read/process-recovery instrumentation class are unchanged.
- Only auxiliary logcat failures remain separately marked UNAVAILABLE. They do not replace instrumentation. Evidence upload remains always-on. Permissions are read-only and trigger remains the isolated verification branch; no main/develop writes, merge or deployment step is present.

Original producer package/native/scoped PASS and canceled pre-instrumentation AVD run are provenance context only. This review does not relabel its tests as passed: exact product APK API26 device/recovery acceptance remains pending the new harness run.

## Same correction in complete-source pipeline

Also reviewed immutable product/pipeline source `44df2265808eee7fba17eb1aae6dc26c3554c3a4` in `/workspace/Muyon-frontend-loop`, exact diff from73a582d3. The only changed file is `.github/workflows/frontend-service-loop.yml`; APK product and instrumentation source are unchanged. Shared explicit ANDROID_AVD_HOME fixes create/start directory agreement. timeout300 bounds device discovery; the new mandatory boot_completed=1 check strengthens boot acceptance. timeout240 on instrumentation fails closed under pipefail while retaining existing two-test success/failure checks. No source-mixing or gate-weakening issue found. New whole-pipeline and immutable73 harness39107132638 execution outcomes remain pending; no runtime actions were run by this review.
