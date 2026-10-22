# Actual Android compile, source tests and first current-source component images

Product source:043bed97e218bc25202a803aff3c0de1a5da031f. Evidence-only parent
HEAD before this batch:1f2f1d615af010e8f7f234cd63e52a286c01c382. No production
source changed here; PR101 fixed214b4031deb38ca7dfd35ee86396089eb48157d5,
main/develop untouched by this worker. Leader B remains sole develop merger.

## Verifiable results

- Full product :app:compileDebugKotlin: actual BUILD SUCCESSFUL, exit0, with real
  Android36/JDK17/AGP8.11.1/Kotlin2.2.20. Recovered Maven inputs were used via a
  task-local file repository; no dependency version, production repository or
  verification gate was reduced. Raw recovered-product-main-compile.log.
- Joint :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin: exit1 after
  entering actual test source compilation. Exact three errors are the reader
  owner's DocumentReaderPlatformTest.kt:33:27,86:27,158:27 PdfDocument().use.
  Raw recovered-product-androidtest-failure.log. This is a source failure, not
  a continuing AGP-resolution failure. No owner file was edited by UI shell.
- Isolated screenshot/semantics harness: actual assembleDebug and
  assembleDebugAndroidTest BUILD SUCCESSFUL exit0, preview-assemble-success.log.
  Twelve files including the six-method ConversationShellTest are copied exactly
  from the product source. Source hashes in preview-source-manifest.json; reviewer
  independently compared source git43, working source and copies. Harness is
  **not the full product APK**, has a distinct package, no ProductClient/Service/
  native library/model or invented CardBinding, and no INTERNET permission.
- Actual device instrumentation of those six source tests: OK(6 tests), each
  distinct method STATUS_CODE0, terminal INSTRUMENTATION_CODE-1. This validates
  header/body bounds, mascot count, menu interactions/draft retention and new
  semantics properties in the component harness. It does not validate real
  TalkBack speech, ActivityReaderSurface/IPC/lifecycle or the full application.
  Raw preview-six-source-tests.log. No claim that connectedDebugAndroidTest passed.
- 8 actual framebuffer PNGs, each SHA256/IHDR1080x1920/Pillow full decode verified
  independently and all visually inspected. No AI-generated image, cropping or
  pixel edit. 8/8 uploaded to Library, per-item finalize and scope rename succeeded.
  Confirmed IDs in preview-screens-043bed/CAPTURES.json and README.md, not merely
  paths visible only in this environment. Library filenames explicitly say
  COMPONENT-PREVIEW-NOT-PRODUCT-APK and synthetic.

## Tool restoration and scope

Google SDK agreement was explicitly accepted by the user for this disclosed task
scope. Repository packages reference android-sdk-license with2019-01-16 text;
current official download page displays2026-04-28 text. Both are the disclosed
Google Android SDK agreement family, not a new third-party service contract.
Only stable packages selected: base Android36 r2, build-tools35.0.0,
platform-tools37.0.1, emulator37.2.12 and AOSP API26 default x86_64 revision1.
Official Android CLI installed them successfully; no blanket yes or preview license
acceptance. ANDROID_USER_HOME points to the writable task directory; HOME and
security permissions remain unchanged. This fixes the prior CLI internal-bin error.

System java21 was a JRE without javac. Existing CI uses Temurin17; restored complete
Temurin17.0.21+9 from official Adoptium release metadata, verified archive SHA256
8b9b611d917e3dfd8419d3566b5949226f69b052fed7e109c1368add1dfe8711.
Actual java/javac17.0.21 ran. Its bundled existing OpenJDK GPLv2+Classpath notices
were retained, no Oracle/commercial agreement or separate interactive terms accepted.
Gradle8.13 distribution reused, exact existing pin20f1b117...e78 verified.

JVM direct repository network remains unreachable. Existing permitted curl route
fetched official Google Maven and Maven Central bytes to a task-local file repository.
738 original artifacts, source URL/effective URL/SHA256 in recovered-maven-sources.jsonl;
reviewer rehashed all. No proxy/VPN/system-network setting, credentials, permission,
third-party mirror or local reverse proxy. Task-local init points Gradle at those
files; it changes neither dependency versions nor repository production source.

## Runtime and capture method

Official emulator37.2.12, task-owned AOSP API26 x86_64, no KVM. It actually booted
with documented software TCG and software GPU options; emulator boot log records
170537ms. Raw getprop/wm/settings: boot_completed1,API26,x86_64,1080x1920,420dpi,
font_scale1.0 in preview-device-runtime.txt. Guest-only font and night-mode settings
were normal UI test configuration, not host security changes. No new account/data.

Official adb binary is installed but cannot write its default HOME/.android on
this host, and ignores the attempted SDK preference variables. No HOME override
or permission expansion. A small bounded local ADB protocol client talks only to
this owned emulator127.0.0.1:5559. It accepts the guest's normal CNXN; AUTH is a
hard stop. No auth disable, key retrieval/injection, proxy or console-token bypass.
This is a normal guest transport, not an Android stub. Reviewer checked it. It is
not a general production ADB client: stream-ID/checksum validation and write-output
bounds are incomplete. No unknown remote device is supported.

Initial raw capture had a System UI ANR and is retained only under
rejected-captures. It is excluded from all8 delivery images. A normal visible Wait
button action dismissed the dialog; pre-capture UIAutomator hierarchy checks then
rejected any remaining ANR. PNG pixels are raw exec:screencap -p bytes. Guest
PackageManager installed the exact own-built APK/test APK, both reported Success.
APK SHA256 5e4032741b374cf622e83333b3a49019380514d0385fe85e5e5039ebeeee319d;
testAPK SHA256 a0f605b32a5fc30922a5622798440f566a1c463a35299360dbaaac81a9a162b3.

Capture limits: menu Dialog covers the wrapper scope banner; dark banner contrast
is poor. Every shared image must include its Library filename or equivalent caption:
“043bed component preview, synthetic data, not full product APK”. Do not publish
these as exact MainActivity/ChatScreen page screenshots or full APK/device acceptance.
Chat images render actual header/composer plus explicitly labelled preview body,
not production transcript/bubbles. Cards image shows the actual null/unavailable
ReadOnlySnapshotPanel. No seven typed-card fake bindings or real business data.
Group is an unknown/disabled config variant, not an executing leader. Bot uses
actual pure local draft reducer only; no save/create/run is asserted.

The task-owned emulator was stopped only after all captures/tests and final device
read completed. Cleanup requested SIGTERM; execution session terminated exit138
(Shell reported SIGUSR1). No zero-exit cleanup success or continuing live VM is
claimed; capture/test results precede cleanup. See preview-emulator-cleanup.txt.

## Exact commands and reproducibility

With JDK17, ANDROID_HOME/ANDROID_USER_HOME and GRADLE_USER_HOME task paths, product:

```bash
/workspace/ui-shell-tools/gradle-8.13/bin/gradle --offline --no-daemon --console=plain \
 --init-script /workspace/ui-shell-tools/maven-offline-restore/local.init.gradle \
 :app:compileDebugKotlin
```

Joint command adds :app:compileDebugAndroidTestKotlin and fails as above. Preview
uses the same command in the isolated preview directory with :app:assembleDebug
:app:assembleDebugAndroidTest. Device command:

```text
am instrument -w -r -e class com.mightyoung.muyon.product.ui.shell.ConversationShellTest
 com.mightyoung.muyon.uicomponentpreview.test/androidx.test.runner.AndroidJUnitRunner
```

preview-harness contains the isolated manifest/Activity/build scripts, original
source hash manifest, normal protocol client and capture script; production source
copies are materialized from the fixed product commit, not duplicated into feature
source. Tool-specific absolute paths are reproducibility examples, not screenshot
delivery links. Library IDs are the actual cross-environment deliverables.

## Reader integration handoff and remaining blockers

Required Android JSON compatibility dependency: **af57d05ce779508615775e44dac0af12df7cf2e6**.
It is an ancestor of current candidate and RequestCandidates.kt is byte-identical
(no diff); SHA256 c30ca08815352a901bb45ddbc428241ebea89279b8f68bf221bf98e8afe4d7c2.
Minimal production file is product/ui/shell/RequestCandidates.kt; matching tests
RequestCandidateChecks.kt. Exact commit includes these plus evidence, no new
foundation/Host/binding dependency. Older Reader dde1856 lineage needs this exact
fix, not reimplementation or a merge of all90df/043bed lifecycle work. Parent/B
coordinates only on independent combination branches; PR101 stays fixed.

Reader owner must fix its three PdfDocument().use sites with real Android API
resource lifetime (for example explicit try/finally close) and rerun the full test
compile. Shell did not edit product/ui/documents or its tests. Actual full product
APK still needs its existing native/model build inputs and full owner integration;
no gate was bypassed to make this component preview. Reader authority/PFD, real
Host capabilities, group execution and seven-card business interactions remain
unaccepted. No model/search request, old unknown retry/fee adjustment, deployment,
payment, branch deletion, force push or develop merge occurred.
