# Muyon Android product target

New application identity `com.mightyoung.muyon.product`; private business store and attachments must never open the old Flutter database. No synthetic owner or provider is installed by this target.

The app connects a private Rust Service to supplier CRUD and the research workbench (PDF/manual metadata, directory/ZIP snapshots and private attachments). The assistant can read local records; model chat and external search remain unavailable until trusted product transport/budget owners are installed. Task evidence and remaining acceptance gates are tracked in `docs/tasks/muyon-android-refactor/PROGRESS.md`.

Use the existing pinned Android dependencies, Android NDK 28.2.13676358 and an installed Gradle executable. This host was tested with Gradle 9.3.1 / Android Studio JBR 25. The shim does not download a wrapper or change global caches. Build both native ABIs before packaging:

```sh
export ANDROID_HOME=/path/to/Android/sdk
export MUYON_NATIVE_OUTPUT=/absolute/task-owned/native-output
sh apps/muyon_android/build-native.sh
MUYON_UI_GRADLE=/path/to/gradle-9.3.1/bin/gradle \
  bash apps/muyon_android/gradlew -p apps/muyon_android \
  -PmuyonProductNativeInputs="$MUYON_NATIVE_OUTPUT/jni" \
  -PmuyonSource="$(cat "$MUYON_NATIVE_OUTPUT/build-id.txt")" \
  :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug
```

Native inputs, when supplied, must be rebuilt from this candidate and verified against source/build/ABI identity. Old lab APK or `.so` artifacts are not current product binaries. API26 instrumentation and real provider results remain separate gates.

Initialize a new workbench explicitly on first launch. Existing stores reopen through health/read operations; initialization never overwrites a database. An uncertain operation retains its original intent for explicit lookup and is not automatically submitted again.
