# Isolated Host/Bot native acceptance checkpoint

Branch `task/host-bot-native-acceptance-20261022`, fixed base `ee742351fe7cf02133c5d68fd21eaabd73579d8d` (PR102 input supplied by parent). Old branches/worktrees preserved. No PR102/main/develop/Claude branch edit, merge or deployment. No Reader policy work; that dependency remains paused as instructed.

## Implementation

Reuse the actual ProductService, ProductChatRuntime, HostLocalDraftSession, canonical reducer/codec, five generated methods and BusinessStore. Main Service now has protected build-subclass seams for workspace, storage root and draft verification; default remains `local-workspace`, `filesDir/muyon-product-v2` and false. There is NO wire/Intent/configuration flag to enable them on ProductService. Native open and initialized reporting use the same selected root.

Only `src/debug` declares BotNativeAcceptanceService, non-exported, in `:bot_native_acceptance`; it overrides the build seams with a fixed separate `bot-native-acceptance-fixture` app-private root, synthetic workspace `bot-native-acceptance`, and enabled draft port for this test Service only. Release contains neither its class nor manifest entry. MainActivity and the normal ProductService are not redirected. This is test injection, not evidence that the production port is verified or released.

The androidTest class sends the real Messenger protocol with actual session/epoch and request IDs. It never uses FakePort, synthetic native responses, a second store implementation or a second execution gateway. Direct ProductCore use in two cases is only offline fixture preparation before Service startup, and post-stop assertion against the same synthetic root; ownership is closed before another owner opens it.

## Device-only cases (NOT_RUN)

1. Create a genuine synthetic project via existing local prepare/confirm. Real Service resolve/edit/save, stale editor CAS rejection and duplicate save refusal; cancel/resume; stale scope rejection. Kill only the checked `package:bot_native_acceptance` PID (never instrumentation/normal Service), release AUTO_CREATE binding, reconnect with fresh native owner and scope. Discover original committed pointer, explicitly query historical receipt (not current-editor acknowledgment), explicitly restore canonical edits. Kill occurs AFTER known committed response; this is not save-in-flight process-loss coverage.
2. Real native prepare with canonical MYBD archive, duplicate prepare, stale generation and stored revision rejection. Close owner and start real Service. Open discovers original pointer and holds unknown; no dispatch on open. Explicit query fences prepared attempt as not committed. Stop fixture, reopen native and assert late original save cannot commit.
3. Real native prepare/save, duplicate save; discard delivery to Host, not the actual committed state. Reject foreign conversation lookup. Cold Service open retains original unknown pointer, explicit query returns committed history without marking new editor saved; explicit restore obtains original data. This is a discarded-delivery fixture, not actual Binder packet-loss/kill-in-flight fault injection.

No test runs agent creation/execution, model/search, credentials, fees or real user files/DB. Assertions keep create/start false and costs unavailable. Historical unknown requests and the ¥0.002620 reserve are not inspected or changed.

## Actual validation

The previous ABI checker now validates the protected production gate's false default and actual generated prepare mapping; added mutation test rejects changing the default true. It does not claim native execution. `python3 apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/check-prepare-binding.py`: 4/4 exit0 (`evidence/abi-contract.log`).

Actual debug and androidTest compilation initially passed; debug/androidTest/release also passed at an intermediate checkpoint. An overlapping connected-test command and final compile competed for Kotlin incremental cache; both outcomes and daemon fallback are preserved, not hidden. The overlap was a scheduling mistake. Both were confirmed exited before the final serial clean build. Final serial clean build PASS exit0: all43 tasks executed, including actual debug, release and androidTest Kotlin compilation, BUILD SUCCESSFUL in1m (`evidence/final-clean-compile.log`). Actual merged manifests and compiled output also confirm debug-only fixture isolation (`evidence/debug-release-isolation.log`). These are compilation/isolation evidence, not device/native execution.

Common command environment (all existing tools on THIS machine, no remote cache assumption):

```sh
export JAVA_HOME=/workspace/host-projection-tools/android-build/jdk-17.0.17+10
export JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts
export ANDROID_HOME=/workspace/host-projection-tools/android-build/sdk
export ANDROID_USER_HOME=/workspace/host-projection-tools/android-build/android-user-home
export GRADLE_USER_HOME=/workspace/host-projection-tools/android-build/gradle-user-home
export MUYON_UI_GRADLE=/workspace/host-projection-tools/android-build/gradle-8.13/bin/gradle
```

Final source compilation, from repository root:

```sh
bash apps/muyon_android/gradlew -p apps/muyon_android --no-daemon --console=plain :app:clean :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:compileReleaseKotlin
```

Real device command attempted from `apps/muyon_android`:

```sh
bash ./gradlew --no-daemon --console=plain :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.mightyoung.muyon.product.agentipc.BotNativeServiceAcceptanceTest
```

Result exit1 at `:app:verifyModelAssets`: `Prepare fixed offline assets and set muyonModelAssets`; **0 device tests executed**. Log `evidence/device-attempt-blocked.log`. No task exclusion, fake files, native input hash/source replacement or changed validation gate used.

## Exact pending environment / acceptance work

This task's caches have actual SDK36/BuildTools35/Gradle8.13/JDK17, but no fixed model asset directory, Rust/cargo, NDK28.2.13676358, CMake3.22.1, product native libraries, installed emulator/system image or visible `/dev/kvm`/USB device nodes. `environment-inventory.log` records local checks. Existing adb attempted device enumeration but aborted trying to create `/home/agent/.android` on a read-only filesystem even with ANDROID_USER_HOME; no HOME reassignment, new ADB keys/credentials, elevated permissions or system change was attempted. Device availability is not established, rather than falsely reporting an empty adb list. These are pending environment/tool inputs, not an auto-review rejection.

Next authorized native provisioning uses existing `apps/muyon_android/checks/ci_model_inputs.py` fixed-source fetch + independent offline hash check, existing `build-native.sh`/`build-ml-native.sh` (including pinned llama b11763), exact source/build-input identity and native manifests. No second pipeline/store is introduced. Existing base CI39838561014 was read-only verified success with head ee742351; workflow uploads logs/lint only, not model APK/native inputs. It does not execute this new device suite and supplies no reusable device evidence. Any newly encountered distinct agreement still must be reported; no new agreement accepted this batch.

After genuine inputs are ready, provision a real supported device/emulator under existing authorization and execute these three tests (source/input identity retained). Actual native save-in-flight/Binder lost callback races, concurrent native CAS, and final release-gate decision require further actual execution, not these static/source fixtures. Parent/B must independently review evidence before any production enablement; this branch does not open production verified.

## Review / evidence

Independent non-author final static review found no Important, including all three cases; `evidence/independent-review.log`. Source hashes in `SOURCE-SHA256SUMS` bind reviewed code. Reviewer did not claim device execution. Raw logs retain original Gradle trailing spaces, so evidence-only whitespace warnings are retained; source and Markdown diff checks pass.

Actual release ProductService bytecode was inspected with official JDK javap; protected localDraftPortVerifiedForBuild returns iconst_0/ireturn (`evidence/release-service-bytecode.log`). This proves the compiled default, not invocation/native acceptance.

Final evidence/report review independently rechecked all four source hashes, all43 executed clean-build tasks, exact device command stopping before test start, and actual debug/release merged manifests/classes; no Important or reporting correction (`evidence/independent-results-review.log`). Reviewer did not rerun compilation or device tests.
