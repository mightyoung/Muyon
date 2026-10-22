# Research: API26 emulator availability and verification path

## Request Type

Current best-practice research plus read-only local SDK and workflow verification. Retrieved 2026-10-20, approximately 14:22 UTC. This lane did not install images, accept licenses, start/stop emulators, modify product files, or trigger GitHub workflows.

## Direct Answer

**API26 ARM64 images exist in the current official stable SDK repository. Apple Silicon is not, by itself, a demonstrated blocker.** Local `sdkmanager --list` with ordinary sandbox networking failed to fetch manifests; the authorized read-only elevated retry fetched the repository successfully. Therefore the initial installed-only result must not be treated as proof that API26 ARM64 packages do not exist.

Local host: Darwin arm64; SDK `/Users/muyi/Library/Android/sdk`; Emulator **37.1.11.0**, build **15917651**; `emulator -accel-check` returned **0**, `Hypervisor.Framework OS X Version 27.0`. Only API36 Google Play ARM64 revision 6 was installed at the time of inspection. API26 installation and successful boot were **NOT_RUN in this lane**. The parent is evaluating installation separately.

| Official stable package | Revision | Compressed archive bytes | Approximate MiB | Minimum Emulator |
| --- | --- | ---: | ---: | --- |
| `system-images;android-26;google_apis;arm64-v8a` | 3 | 733331565 | 699.4 | 31.1.1 |
| `system-images;android-26;default;arm64-v8a` | 2 | 330014927 | 314.7 | 31.1.1 |
| `system-images;android-26;google_apis;x86_64` | 16 | 980740438 | 935.3 | 26.1.3 |

The current installed Emulator exceeds the published minimum version. That is a compatibility prerequisite, **not a boot/test result**. Archive sizes are compressed download sizes, not installed disk requirements.

## Official Docs Evidence

- [SDK Manager](https://developer.android.com/tools/sdkmanager) documents `sdkmanager --list` and stable channel selection. The current tool emits a deprecation notice in favor of Android CLI; the SDK Manager executable remains installed and its read-only query worked.
- [Google APIs system image repository](https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-5.xml) establishes the API26 Google APIs package IDs, revisions, ABI, minimum Emulator and archive sizes above. The SDK Manager cache metadata records HTTP **200**, fetched **2026-10-20 14:22:28 GMT**, repository Last-Modified **2026-10-17 07:10:37 GMT**.
- [Default Android system image repository](https://dl.google.com/android/repository/sys-img/android/sys-img2-5.xml) establishes the API26 default ARM64 package. Cache metadata records HTTP **200**, fetched **2026-10-20 14:22:27 GMT**.
- [Emulator hardware acceleration](https://developer.android.com/studio/run/emulator-acceleration) documents ARM64-host ARM64-image requirements, macOS Hypervisor.Framework, Linux KVM, `-accel-check`, and the deprecation of `swiftshader_indirect` since Emulator 36.4.9. Current documented software render modes include `software` and `swiftshader`.
- [AVD Manager](https://developer.android.com/tools/avdmanager) documents package-selected AVD creation and explicit AVD paths. It also flags AVD Manager deprecation; this report uses the already installed tool for compatibility with current repository scripts.
- [GitHub Linux hardware acceleration](https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/) establishes Android hardware acceleration on standard 2-vCPU GitHub-hosted Linux runners; larger paid runners are not a categorical prerequisite.

## Version Note

API26 is Android 8.0. All package facts above are from stable (`channel-0`) repository entries retrieved during this session, not recollections from early Apple Silicon support. No claim of successful API26 boot or instrumentation is made. The official release notes list local Emulator 37.1.11 as a stable release; see [Emulator release notes](https://developer.android.com/studio/releases/emulator).

## License and Network Boundary

The Google APIs ARM64 package references license ID `android-sdk-license`. The local license file exists. A Python SHA1 comparison of cached XML license text, both raw and trimmed, did **not** match any existing accepted hash; XML binding/normalization details make this a warning rather than a definitive SDK Manager acceptance verdict. Do not infer acceptance solely from file existence. Install with closed stdin and treat a new-license prompt as a stop condition; never pipe `yes`, edit the accepted-hash file, or run automatic license acceptance.

Official archive: `https://dl.google.com/android/repository/sys-img/google_apis/arm64-v8a-26_r03.zip`; published SHA1 `7a9764f1856119c4ceb311f6c76ff975a4c1e65d`. This lane did not download the archive. Ordinary restricted-network lookup printed `Failed to download any source lists` / manifest IO warnings despite returning exit 0. The elevated read-only retry returned available packages successfully. Repository XML fetched through the generic web tool failed, and context-mode HTML conversion lacked `@mixmark-io/domino`; the working evidence source is the successful SDK Manager response plus its just-refreshed official XML cache.

## Supporting Examples

Read-only query that succeeded (the current JDK is required because shell Java defaults may differ):

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  /Users/muyi/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --list
```

Candidate local installation/AVD sequence, supplied for the parent and **not executed here**. Run only on the authorized install branch, preserve existing licenses, use a separate AVD directory and port, and leave the API36 emulator on port 5554 running:

```sh
export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
export ANDROID_SDK_ROOT='/Users/muyi/Library/Android/sdk'
export ANDROID_AVD_HOME='/private/tmp/muyon-api26-avds'
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
  --install 'system-images;android-26;google_apis;arm64-v8a' </dev/null
# Stop if the package is not installed or a new license is required.
mkdir -p "$ANDROID_AVD_HOME"
printf 'no\n' | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager" \
  create avd -n muyon-refactor-api26 \
  -k 'system-images;android-26;google_apis;arm64-v8a'
"$ANDROID_SDK_ROOT/emulator/emulator" -avd muyon-refactor-api26 \
  -port 5556 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader
```

The emulator command occupies the foreground; a supervising process should capture its log and boot deadline. Target later ADB commands with `-s emulator-5556`, require `sys.boot_completed=1` and `ro.build.version.sdk=26`, record ABI, then install actual app/test APKs and collect instrumentation results. Do not use generic unqualified ADB commands when API36 and API26 coexist.

## Existing Linux CI Path — Local Evidence

Local repository evidence, not a claim that a workflow was executed:

- `.github/workflows/frontend-service-loop.yml` defines `ubuntu-24.04`, Java 17, separately built ARM64/x86_64 Rust producers, actual APK packaging, `/dev/kvm` access, Google APIs API26 x86_64 AVD, boot completion and SDK=26 assertions, and actual `FrontendServiceLoopTest` / `ServiceHostBindingsTest` instrumentation. It checks `OK (5 tests)` and rejects failure/crash markers. Its result explicitly says **model API NOT_RUN**.
- That workflow pushes only on `lab/android-compose-frontend-loop-20261018` and also declares `workflow_dispatch`. It does not automatically validate an unrelated refactor branch. Re-running an old workflow would only validate its old checkout, not current local changes.
- `.github/workflows/web-search-send.yml` packages the search fixture and calls `experiments/redesign/android-rust-bridge-lab/checks/search_send_device.sh`. The script records source SHA and device phases, requires API26, installs real APKs, and runs `SearchSendServiceLoopTest` with `OK (2 tests)` plus failure/crash rejection. Its fixture and selected-class scope do not establish real provider-network acceptance or complete new business CRUD coverage.

To make Linux CI a current acceptance gate, the implementation owner must wire the accepted current branch/PR SHA, build and hash current APK/native artifacts, ensure the selected instrumentation covers the newly implemented flows, assert SDK26/x86_64 and boot completion, reject missing/skipped tests and failure markers, then archive source SHA, artifacts, instrumentation, crash logs and phase status. Existing fresh-native and packaging producers are reusable prerequisites. That is product/CI ownership outside this evidence lane. No push, dispatch, rerun, account operation or automation was performed.

## Caveats / Ambiguity Flags

- Package availability plus ABI and minimum-version compatibility does not prove the image boots on this exact host. Installing and booting the official ARM64 candidate is the next factual check, subject to existing-license and disk constraints.
- Local API36 observations cannot satisfy the agreed API26 acceptance target. Linux API26 instrumentation can satisfy API26 emulator compatibility only for tests actually executed against current artifacts.
- Neither offline fixture instrumentation nor a build-only native ABI check establishes successful real model/provider execution.
- No upstream code or third-party examples were needed for the conclusion. A legacy Apple Silicon/API29 minimum assertion would contradict the current package catalog and must not be used.

## Reusable Takeaway

Use the official API26 ARM64 candidate locally if normal installation succeeds without new license acceptance; otherwise keep API26 marked NOT_RUN and use the existing Linux x86_64/KVM path after it is wired to the actual refactor SHA and complete acceptance tests. The environment blocker is currently **uninstalled/unverified API26**, not proven Apple Silicon incompatibility.
