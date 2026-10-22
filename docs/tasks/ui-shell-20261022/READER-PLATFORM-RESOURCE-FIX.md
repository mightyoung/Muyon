# Reader platform test resource compatibility fix — 2026-10-22

Source fix: `acfa9d47808ee860369e080820524ca03c900f59`, parent
`c5dd872863a0e454f5d74889e1cd6c3932c2fed5`, branch
`task/ui-shell-20261022`. Only the explicitly delegated
`DocumentReaderPlatformTest.kt` changed in that source commit. No production
Reader/Host, feature gate, build gate, PR101, main or develop change.
Remote develop was read-only checked as `c130008bbc40d78e85d10058030da9da4aca38f0`.

## Cause and minimal fix

Real SDK36 `javap` shows `android.graphics.pdf.PdfDocument` declares `close()` but
implements neither Closeable nor AutoCloseable. Kotlin's `use` does not apply.
The preserved prior real full Android-test compilation RED is
`evidence/recovered-product-androidtest-failure.log`, with failures at lines33/86/158.
The API inspection is `evidence/reader-platform-fix/pdfdocument-sdk36-javap.log`.

Each of the three PDF fixture builders now creates the document and closes it in
`finally`. OutputStream.use, page counts/colors, assertions, outer file deletion
and pending coroutine cancellation are retained. Test file SHA256:
`0ff86ea1bf4b6280a18b98f4ef0752ff4c316832545a4f45e9df2106a3d311f2`.

## Actual build verification

From repository root, with real restored official toolchain and unchanged pinned
Maven originals in a task-local offline repository:

```sh
JAVA_HOME=/workspace/ui-shell-tools/jdk-17.0.21+9 \
ANDROID_HOME=/workspace/ui-shell-tools/sdk \
ANDROID_USER_HOME=/workspace/ui-shell-tools/android-user \
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
  --offline --no-daemon --console=plain \
  --init-script /workspace/ui-shell-tools/maven-offline-restore/local.init.gradle \
  -p apps/muyon_android :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin
```

PASS exit0, BUILD SUCCESSFUL in32s,27 tasks (1 executed/26 up-to-date).
`compileDebugAndroidTestKotlin` actually executed; no test exclusions or fake SDK.
Raw log: `evidence/reader-platform-fix/full-androidtest-compile-green.log`.

The separate real component harness `:app:assembleDebug :app:assembleDebugAndroidTest`
also passed exit0 in32s (62 tasks), with the five real Reader production sources
and fixed original platform-test file copied byte-for-byte. Exact source hashes:
`evidence/reader-platform-fix/source-manifest.json`; base harness and environment
recipe: `preview-harness/`. Raw build:
`evidence/reader-platform-fix/component-apks-build.log`.

Full product APK assembly was also actually attempted with the same toolchain,
`:app:assembleDebug :app:assembleDebugAndroidTest`. FAILED exit1 in13s at
`:app:verifyModelAssets`: `Prepare fixed offline assets and set muyonModelAssets`.
Raw log: `evidence/reader-platform-fix/product-package-blocked.log`.
No gate was skipped. Matching native input/build-id prerequisites also remain
required by the unchanged product build. Therefore no full product APK or
end-to-end authorized ReaderHost/FFI device acceptance is claimed.

## Independent review

Independent agent review of source diff, original assertions, SDK javap and
`git diff --check` found no blocking/Important issue. The three finally blocks
close documents on success and write failure, and preserve existing stream and
outer fixture cleanup. Separate runtime evidence follows; static review alone
is not a device pass.

## Actual device verification

PASS **4/4**, AndroidJUnitRunner `OK (4 tests)`,54.029s,
`INSTRUMENTATION_CODE: -1`. Normal package-manager installation confirmed Success
for both APKs before testing. Emulator37.2.12, official API26 default x86_64 image,
TCG software acceleration,1080x1920,420dpi,font_scale1.0. No KVM, security or
network setting change. Exact APK hashes are `evidence/reader-platform-fix/apk-hashes.json`.

Actual guest command:

```sh
am instrument -w -r -e class \
  com.mightyoung.muyon.product.ui.documents.DocumentReaderPlatformTest \
  com.mightyoung.muyon.uicomponentpreview.test/androidx.test.runner.AndroidJUnitRunner
```

Methods all status0:

- `nativePdfRendersActualPagesAndRejectsBadPage`: actual Android PdfDocument/
  PdfRenderer, generated red/blue PDF pages and out-of-range rejection.
- `sharedCoreJsonPreservesAnchorAndExactRevision`: exact JSON revision/anchor contract.
- `pendingSaveAndUnknownLockSurvivePageNavigationAndOtherScopesAreHidden`:
  actual composed Reader, synthetic PDF and synthetic host callbacks.
- `pageReadFailureCanNavigateAndExplicitlyRetryWithoutResendingUnknownSave`:
  actual composed Reader with synthetic transient descriptor error/currentness/save response.

This is **Reader component/device regression**, beyond the earlier visual component
screenshots, but it is still **not** a real product ReaderHost authorization/FFI/
persistent sidecar end-to-end test. Fixture callbacks intentionally belong only to
this original instrumentation test, never production. ReaderHost null and all
existing unavailable permissions/capability gates are preserved. No model/search
request, document import, actual business save or receipt was performed.

Raw install/environment/test output: `evidence/reader-platform-fix/device-install-and-tests.log`;
raw instrumentation output: `evidence/reader-platform-fix/device-instrumentation.log`.
Exact task-owned normal guest transport invocation is archived in
`evidence/reader-platform-fix/run-reader-device-tests.py` (uses the existing
CNXN-only owned-emulator utility from `preview-harness/`).
`materialize-reader.py` reproduces the pinned six source additions to that
previous isolated harness and refuses differing existing outputs.

Remaining blockers: full product package requires authentic fixed model assets
and matching native libraries/build identity; this task did not manufacture them
or skip their checks. Full product connected tests/real ReaderHost chain therefore
remain NOT_RUN, not denied by a permission review. Existing snapshot/capability
restrictions remain unchanged. This batch does not alter PR101 or integrate this
historical shell branch into develop; B may consume the minimal source commit.

Final independent review (`review_shell`) also checked original/archived log byte
identity, APK hashes, four distinct test names/status0 and runtime terminal result;
no blocking/Important finding. No reviewer edits or device reruns. Production
source has zero diff since the source fix commit. Task-owned software emulator
was stopped normally after confirmed test completion.
