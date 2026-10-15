# Muyon Android Compose lab

Independent UI slice at `31b9b6fc1f7f8b27952533ca141e901676ba90e8`, owned solely by the original UI writer. New code lives only in this directory. No Dart, Rust/core/plugin, shared UI package or old Android host change. P04/P08 supplier experiments remain untouched; this slice supplies the missing standalone four-destination shell rather than a second supplier page. Electron is the separate desktop direction, not implemented here.

## What exists

- Kotlin immutable shell memory: assistant / tasks / data / settings, assistant default, 900 logical-pixel bar/rail boundary, exact raw UTF-16 draft, scroll coordinates, last input focus marker. This is in-process local UI memory, not durable storage or request state.
- A Compose Android app source with hoisted scroll objects, keyed content, conditional focus restoration after the input is mounted, live disconnected status and a plain temporary input. The neutral Material scaffold is **not** a reconstructed WorkBuddy screen or measured visual design.
- `RustUiPort` intentionally has only `NOT_CONNECTED`. No successful task/receipt, authority, submit/cancel, HTTP/JNI transport, credential, real model or native library capability. No INTERNET permission. The default app shows the actual disconnected condition; synthetic task states occur only in display checks.
- Safety copy distinguishes queued/waiting/running/succeeded/failed/cancelled/paused/interrupted; interruption retains unknown-outcome advice even for platform tasks; cancellation in flight cannot imply final cancellation. These strings do not grant actions or prove host results. Production Rust DTOs/authority remain owned elsewhere.
- A source instrumentation check for draft/focus and 899→900 navigation. It has not run and is not device evidence.

No APK assets, font files, proprietary illustration or recovered competitor source is copied. Muyon remains the lab name. Real WorkBuddy screenshots, runtime Widget tree, pixel comparison, Android execution/TalkBack/IME/rotation and process-death persistence remain absent. Workspace/back-stack business navigation is not implemented in this first skeleton.

## Actual local verification

Existing PATH had Java21 runtime only; no kotlinc, javac, Gradle or Android SDK. An official JetBrains Kotlin2.2.20 compiler zip was downloaded only to `/tmp/muyon-native-ui-tools-20261015`, SHA-256 `81f0264c9073b5cbbdb3ff8418cf2c5dac076879fc156fa1a6462f5a5acc4420`, matching its official checksum. No system path/config or Android toolchain was installed.

Run the complete standalone state suite using an existing compiler:

```sh
MUYON_UI_KOTLINC=/tmp/muyon-native-ui-tools-20261015/kotlinc/bin/kotlinc bash run-state-checks.sh
```

`MUYON_UI_KOTLINC`, `MUYON_UI_JAVA` and `MUYON_UI_OUTPUT` allow other already-installed tools/private `/tmp` outputs. The script never installs dependencies. It compiles real Kotlin/JVM bytecode at target17 and executes the complete suite. JVM state checks do not compile or execute Compose or Rust.

## Normal CI compilation path (not automatically enabled)

Requirements: JDK17, Gradle8.13, existing approved Android SDK platform36/build-tools35.0.0; dependency resolution via Google Maven/Maven Central/Gradle plugin portal. The project pins AGP8.11.1, Kotlin+Compose compiler2.2.20, Compose BOM2025.09.01 and activity-compose1.11.0. No wrapper binary or SDK download/license acceptance script is added.

From this directory, with the SDK already available:

```sh
MUYON_UI_GRADLE=gradle bash run-ci-checks.sh
```

This runs `:state:check :app:assembleDebug :app:assembleDebugAndroidTest`; it compiles the app and test APK, without installation or Android execution. The script returns exit2 with `NOT_RUN` if required tools are absent. An existing CI runner may supply JDK/Gradle/SDK through its normal approved setup, then invoke the command. No root workflow or other owner's build is changed. Device tests require separate explicit authorization; this script never runs `connectedAndroidTest`.

The state suite uses a standard-library `main` harness, not JUnit. Its Gradle `checkState` JavaExec runs the same compiled checks as `run-state-checks.sh`; `check` depends on it. The empty conventional JUnit `test` task is explicitly disabled rather than suggesting it executed these checks.

Version references: [Kotlin command-line compiler](https://kotlinlang.org/docs/command-line.html), [Compose compiler setup](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler), [AGP8.11 compatibility](https://developer.android.com/build/releases/agp-8-11-0-release-notes). Dependencies are experiment pins, not a recommendation to upgrade the product.

## Remaining gates

Compose/Gradle compilation: **NOT_RUN** locally until a real SDK/Gradle environment runs the command. Source test compilation, physical focus/scroll/keyboard/accessibility, native Rust adapter, host provenance, workspace restoration and real WorkBuddy page pixels remain unverified. No TDD/runtime claim is made for the source-only Compose adapter. The pure state suite has separately observed semantic RED→GREEN evidence.
