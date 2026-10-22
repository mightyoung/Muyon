# Verification record · 2026-10-15

Base: `31b9b6fc1f7f8b27952533ca141e901676ba90e8`. All added paths are under this directory. Existing P04/P08 pages, Flutter, Rust/core and plugin code are unchanged.

| Layer | Actual result |
|---|---|
| Pure Kotlin source compilation | PASS, official kotlinc2.2.20, target17, existing Java21 runtime |
| Complete state suite | **16/16 PASS**, real compiled bytecode execution |
| Initial semantic RED | 11/13 failed at width boundary, retained memory, validation and safety copy; compiler completed, failures were assertions |
| Safety combination RED | Added platform+interrupted case failed because platform text hid the unknown warning; fixed and included in final GREEN |
| Selection inverse | Isolated `/tmp` copy replaced `select` with no-op; exact selection assertion failed1/16; repository source remained unchanged; final original suite GREEN |
| Manifest/script/scope | XML parses, no uses-permission; shell syntax passes; no Dart/APK/font/SVG/native library added |
| Gradle/Compose app compilation | **NOT_RUN**, `run-ci-checks.sh` exits2: Gradle8.13 not installed; no existing Android SDK available |
| Compose instrumentation source | Present, **NOT_COMPILED / NOT_RUN**; Gradle CI command can compile it without executing it |
| Android install/runtime, IME/TalkBack/rotation | **NOT_RUN** |
| Rust/native host integration | **NOT_CONNECTED**, no adapter/effect/credential/model capability |
| WorkBuddy complete page / pixel fidelity | **UNVERIFIED**, no complete screenshot/Widget tree supplied |

Reproducible state command from the repository root:

```sh
MUYON_UI_KOTLINC=/tmp/muyon-native-ui-tools-20261015/kotlinc/bin/kotlinc bash experiments/redesign/android-compose-lab/run-state-checks.sh
```

Compiler zip SHA-256 (matched official checksum): `81f0264c9073b5cbbdb3ff8418cf2c5dac076879fc156fa1a6462f5a5acc4420`. Its installation and logs stay only under `/tmp/muyon-native-ui-tools-20261015`; no compiler binary is committed.

Selected immutable source hashes:

- `ShellState.kt`: `5879f12dc487f8433203c22dba3120e031ab1aa4752950c495d9aaa383aba1eb`.
- `StateChecks.kt`: `92961ed52ce8e815193859da460327f4ac72aca34d43c26dfda9f02970f082e3`.
- `MuyonLabShell.kt`: `1d38a8a495e91942ef8a512e57728fbebb28b518ba1549b913fd2e92eff22f84`.
- `ShellComposeTest.kt`: `ee53da1fd299059530094240d55e7fd64a5562760054459af47fe56957f94a65`.

Retained local log hashes:

- `state-red.log`: `7f086a9686b64bba68ef7b68084314a28f37af247c492aa8d7505d6df9f7c854`.
- `unknown-platform-red.log`: `41d9228121d2d1d67ebb70c2fada9e2ceb4f804bf98a14fe2099ee892ff2e482`.
- `selection-inverse-red.log`: `10327273040a03f8c0c7d42f956ccdcb688b3bbeb1229251c67fd34a5f554834`.
- `state-final-16.log`: `cd119535e8839bb6effa5c75156b13ca0a8ed04dffe764e4561dbc8f1e0e3053`.

The green state suite proves local presentation transitions and safety copy, not real focus/scroll rendering, Rust truth, a working Android app or production migration completion. Those gates remain explicit rather than inferred from the JVM result.
