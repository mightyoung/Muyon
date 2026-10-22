# Actual Bot Service/native acceptance on disposable API26

**PASS: 3/3 actual device tests, 109.46 seconds.** Each fixed method completed with instrumentation status0; final output `OK (3 tests)` and `INSTRUMENTATION_CODE: -1`. Independent live read-only review verified the installed packages and identity evidence. Production verification remains **false**; no feature release or merge is authorized by this report alone.

Code/build source: `f2f9928a0a35afeb2d5956d3bc2d69406adcc503`, descendant of the reviewed c363 fixture checkpoint and fixed parent composition `ee742351fe7cf02133c5d68fd21eaabd73579d8d`. Only the androidTest identity collector changed after c363. No production source, owner, gate, MainActivity/Compose, Reader policy, PR102/main/develop or other worker branch changed in this batch. The earlier REPORT.md remains an honest earlier checkpoint with zero executed device tests; this report supplies the new execution, without rewriting its old results.

## Actual device and three results

Official stable emulator37.2.12, official `system-images;android-26;default;x86_64` revision1, software acceleration (`-accel off`), 1080x1920/420dpi. Actual guest replies: `sys.boot_completed=1`, API26, x86_64, Android8.0.0, `ro.kernel.qemu=1`. Fingerprint: `Android/sdk_phone_x86_64/generic_x86_64:8.0.0/OSR1.180418.004/4931640:userdebug/test-keys`. This newly created disposable device had no Muyon package before installation, no user account or real Muyon database. No inference or real model/search/fee request ran.

| Actual method | Result | Precise coverage |
| --- | --- | --- |
| realServiceSaveCasCancelAndProcessLossRestore | status0 | Genuine synthetic project; Service resolve/edit/save; stale editor CAS and stale scope rejection; duplicate save refusal; cancel/resume; kill only the checked fixture PID **after known commit response**; reconnect, original historical receipt query, explicit restore. |
| committedNativeReplyDiscardedIsRecoveredOnlyAsOriginalHistory | status0 | Actual native prepare/commit and duplicate-save receipt; intentionally no delivery to a Host editor; cold Service discovers original pointer, explicitly queries committed history, does not acknowledge new editor, explicitly restores. This is **not actual Binder packet loss or kill-in-flight**. |
| realNativePreparedOriginalIsDiscoveredAndExplicitlyFencedByService | status0 | Actual native durable prepare and duplicate prepare; stale generation/revision rejection; cold Service discovery without save dispatch; explicit original query fences not-committed; late original save refused. Sequential, **not concurrent CAS proof**. |

The normal case traverses actual Messenger → inherited ProductService → ProductChatRuntime/HostLocalDraftSession → actual generated five-method binding → native BusinessStore. Two cases use actual native only for fixture preparation/post-stop assertions against the same synthetic root, never FakePort or a second store. Root/workspace remain `bot-native-acceptance-fixture` / `bot-native-acceptance` in the non-exported debug-only `:bot_native_acceptance` Service. No test opens the normal product root or old financial unknowns/¥0.002620 reserve. Create/start remain false and fee fields unavailable.

Raw results: `device-evidence/device-instrumentation.log`, `device-test-summary.json`, `device-test-driver.log`. Host driver exit0 reflects explicit JUnit checks, **not an inferred legacy shell exit status**. The legacy exit-status field is null. Exactly this one class was dispatched once; no full suite or Reader tests ran. 78 below denotes Gradle tasks, not device tests.

## Source, installed APK and loaded native identity

Native build-id:

`f2f9928a0a35afeb2d5956d3bc2d69406adcc503:185aa9e83d689ae0101865e29fde9deeaf4f689ac42e337dc452fe523e8cfc9a`

The native input manifest includes androidTest; after adding identity collection, native libraries were genuinely rebuilt for f2 rather than reusing c363's seal. Independent recomputation of **276** source files matched the input hash. Full manifest/check: `final-source-input-manifest.sha256`, `final-source-seal-check.json`.

Both `pm install -t` calls returned `Success`. Before each install the staged file SHA256 matched host output; afterward `pm path` plus device `sha256sum` independently matched the **actual installed** base APK:

- App: `8901f7c67f548d056d0a897845a2e2cfe6a28f2f2a661be7bd92695ad7b50d28`.
- Test: `7285891c4b2160de15af85d505fac3d3cafada62876201ecccd2c659fd4d4726`.

All four real Service connections asserted native health build-id equals sealed BuildConfig, synthetic=false and the correct fixture workspace, and logged streaming hashes of their installed APK and all four packaged native entries. The host independently matched all four records to the rebuilt native manifest and APK hashes; reviewer repeated live device package/hash/log reads. `device-identity-verified.json`, `device-identity-logcat.log`, `device-install-journal.jsonl`, `independent-live-device.json`, `independent-live-identity.log` retain evidence. Health equality alone was not treated as a source-seal proof.

Real native libraries built for arm64-v8a and x86_64; generated Kotlin binding cmp passed byte-for-byte. Host bindgen was built from the same unchanged Rust source on final f2, generated again and compared (`host-binding-final-source-build.log`, `binding-final-generate.log`, `binding-final-cmp.log`). Initial host link failed for missing `-lsqlite3`; the retained real system libsqlite3.so.0 was linked only through a task-local development-name symlink/process-local LIBRARY_PATH, not a stub or modified system library. Original failure remains.

## Official resources and complete product build

Reused actual task-local Gradle8.13/AGP8.11.1/Kotlin2.2.20/JDK17/SDK36/BuildTools35.0.0. Restored official Rust1.93.1 and both Android targets, NDK28.2.13676358/CMake3.22.1, stable emulator and image from exact official sources. All SDK packages reference the already accepted `android-sdk-license`; tools/image metadata embed the identical January16,2019 text (SHA2561f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16); current official page April28,2026 was already disclosed/accepted. Preview packages and their different license were not used. No new agreement, account credential, payment, elevated permission, HOME reassignment or system/security change.

Used unchanged formal CI model flow:

```sh
python3 -B apps/muyon_android/checks/ci_model_inputs.py /workspace/host-bot-native-tools/model-source /workspace/host-bot-native-tools/model-assets --fetch
python3 -B apps/muyon_android/checks/ci_model_inputs.py /workspace/host-bot-native-tools/model-source /workspace/host-bot-native-tools/model-assets
```

Both exit0; six real fixed public inputs size/hash verified, full pinned notices retained. `asset-source-notices-final.json` records exact sources, sizes, hashes and all nine external notice files. Formal package gate also checks packaged notices (including existing main provenance). No login/gated source or extra acceptance arose; models were only downloaded/hashed/packaged, never invoked. Existing notices retain conversion-provenance limits.

Actual final **clean offline** product command passed exit0, 2m47s, **78/78 tasks executed**:

```sh
JAVA_HOME=/workspace/host-projection-tools/android-build/jdk-17.0.17+10 \
JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts \
ANDROID_HOME=/workspace/host-projection-tools/android-build/sdk \
ANDROID_USER_HOME=/workspace/host-projection-tools/android-build/android-user-home \
GRADLE_USER_HOME=/workspace/host-projection-tools/android-build/gradle-user-home \
MUYON_UI_GRADLE=/workspace/host-projection-tools/android-build/gradle-8.13/bin/gradle \
bash apps/muyon_android/gradlew -p apps/muyon_android --offline --no-daemon --console=plain \
-PmuyonProductNativeInputs=/workspace/host-bot-native-tools/native-final/jni \
-PmuyonModelAssets=/workspace/host-bot-native-tools/model-assets \
-PmuyonSource="$(cat /workspace/host-bot-native-tools/native-final/build-id.txt)" \
:app:clean :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug
```

`product-final-offline.log`, `package-final.json`, `model-package-final.json` all PASS. Actual SDK/NDK ELF/package/model checks were retained, not skipped or patched. `toolchain-components-final.json` supplies source/checksum/license references. Native build uses the repository's `build-native.sh`/`build-ml-native.sh`, fixed llama b11763 archive and real two-ABI outputs, with task-owned CARGO_HOME/RUSTUP_HOME/targets. Initial c363 builds are labeled intermediate, not substituted for final f2 results. One first package-check invocation lacked ANDROID_HOME and raised KeyError before validation; its corrected invocation used the real SDK and passed without source/gate changes.

## Platform transport and exact execution command

Official host adb remains unavailable on this filesystem: it aborts creating `/home/agent/.android`; the emulator console also cannot create its default home token. We did **not** change HOME, grant filesystem access, create/authenticate keys, disable auth, or modify network/security settings. Optional metrics were disabled through the ordinary emulator flag on the final instance. The official emulator/guest themselves ran normally.

An independently reviewed **standard raw ADB transport** connected only to our emulator's loopback5581. First probe during boot timed out and exited/closed; after new readiness evidence, a read-only handshake returned CNXN (no AUTH). Subsequent shell reads confirmed boot/API/ABI and absent preexisting app. AUTH/unknown frames hard-stop, all stream IDs/checksums are checked, no credential/AUTH implementation or automatic mutation replay exists. This is platform installation/test transport, not a replacement Product/native ABI or business gateway, and it is **not called official adb recovery**.

Review initially found a staging-path whitelist defect before any upload: prefix/suffix allowed `..` subpaths. It was fixed to strict fullmatch `/data/local/tmp/muyon-bot-[a-z0-9-]+\.apk`; four invalid path checks rejected before transport creation, and two exact staging files were used. Framing was also tightened before execution. Reviewed scripts are archived in `device-tools/` with SHA256SUMS; `device-install.py` journals one dispatch, actual replies and installed identity. Legacy shell has no exit-status channel, so CLSE was never interpreted as success; full pm/JUnit/hash results were checked.

The **single actual instrumentation command** on the device was:

```sh
am instrument -w -r -e class com.mightyoung.muyon.product.agentipc.BotNativeServiceAcceptanceTest com.mightyoung.muyon.product.test/androidx.test.runner.AndroidJUnitRunner
```

The code archives exactly how it was delivered and how raw output/identity were independently checked. No mutation was automatically replayed after a transport timeout/unknown; deliberate same-attempt duplicate assertions remain part of the specified tests. The timeout was only the initial read-only boot handshake; the test invocation reached a definite terminal result. The dedicated emulator was stopped only after independent live review and terminal tests; no fixture Service PID remained. Host emulator wait reported exit138 after the requested SIGTERM shutdown, recorded as shutdown, not a test exit code. APKs/models/native binaries remain in the task directory and are not committed or redistributed in Git.

## Independent conclusion and limits

Non-author static review of fixture/identity/transport and independent live read-only verification found no remaining Important. Reviewer personally rehashed source seal, actual installed APKs, native ZIP entries and runtime records; did not reinstall or rerun tests. `independent-device-review.log` and live files record this. Raw setup failures, earlier no-device checks and the transport path finding were not backfilled as passes.

This closes the requested three-case **debug fixture Service/native** evidence gap. It does not prove physical arm64 execution, other APIs, UI visual acceptance/screenshots, full release-root behavior, concurrent CAS, actual Binder lost-packet/save-in-flight recovery or Reader policy. Normal production verified=false is unchanged; only parent/B may decide subsequent release gating/integration. No branch merge/deploy, new Flutter, paid call or old financial-state operation occurred.
