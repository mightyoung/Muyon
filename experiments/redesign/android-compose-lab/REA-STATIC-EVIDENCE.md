# REA static evidence and frontend boundary · 2026-10-15

REA **6.5.0 was installed and actually run** against the previously verified WorkBuddy APK. Both built-in Flutter operations completed with exit 0. This recovered build identity and bounded AOT string observations; it did not recover a WorkBuddy page, Widget tree, typed application classes, navigation graph or runtime state transition. The Compose lab remains an original Muyon implementation, with no imported competitor code or assets.

## Fixed inputs and installation

| Item | Actual observation |
|---|---|
| Input | `com.tencent.workbuddy.app`, 2.6.1 / versionCode852; package/version from the earlier binary-manifest parse, not newly claimed as an REA result |
| APK identity, recomputed during this run | 293687392 bytes; SHA-256 `5ce904337ba2821fb1cdb7965075445746d198bc82d40b12d6842d24f1da34e3` |
| Official package | `rea-agents@6.5.0`, registry `https://registry.npmjs.org`, repository `morluto/rea` |
| Runtime | Node24.19.0, npm11.9.0; CLI `--version` actually printed `6.5.0` |
| Isolated installation | `/tmp/muyon-rea-tools-20261015`, local prefix and cache, `/dev/null` userconfig; exact dependency and package-lock |
| Install constraints | `--ignore-scripts --omit=optional --save-exact --no-audit --no-fund`; 146 packages installed, optional Frida absent; no global install or setup |
| Registry/package-lock integrity | `sha512-C6BG7LyrAdR74mSjertM6PrxJkcNZ2bfQNOJornPo9erDEp2tyPRVYPnV5Yodr+1RqewCQla68WulXlVnveD+A==` |
| package-lock SHA-256 | `3361cfa577728a046961dbed5159c30dde84ef2af18962b67cf5c7dff606fce0` |

The registry metadata, including all dependencies and lifecycle scripts, was reviewed before installation and retained locally. Lifecycle scripts were not executed. CLI children received an allowlisted environment containing only PATH, TMPDIR, REA_LOG_LEVEL, NO_COLOR and XDG cache/config paths. No credential environment was inherited or printed, and no agent registration, commercial provider or model was configured.

Official docs were read at commit `e18fccc548ba51a51d960b38cdd8996062c2917c`: [Flutter analysis](https://github.com/morluto/rea/blob/e18fccc548ba51a51d960b38cdd8996062c2917c/docs/flutter-analysis.md), [Android analysis](https://github.com/morluto/rea/blob/e18fccc548ba51a51d960b38cdd8996062c2917c/docs/android-analysis.md), [installation](https://github.com/morluto/rea/blob/e18fccc548ba51a51d960b38cdd8996062c2917c/docs/installation.md). The [official README](https://github.com/morluto/rea) identifies the npm package as an official channel. Repository-main documentation is distinguished from the installed release; the actual installed CLI help and output establish the operations available here.

## Actual CLI execution

All commands used the local Node executable and `node_modules/rea-agents/scripts/rea.mjs`, from the isolated tool directory. Full argv, timestamps, exit codes, stdout/stderr hashes and outputs remain in `/tmp/muyon-rea-tools-20261015/commands.json` and `outputs/`; none of the raw AOT output is committed.

```sh
node node_modules/rea-agents/scripts/rea.mjs --version
node node_modules/rea-agents/scripts/rea.mjs --help
node node_modules/rea-agents/scripts/rea.mjs identify-flutter-build --help
node node_modules/rea-agents/scripts/rea.mjs inspect-dart-aot --help
node node_modules/rea-agents/scripts/rea.mjs identify-flutter-build /tmp/rd-workbuddy-android-ui-20261015/apk-static-review/workbuddy-drive-base2.apk --json
node node_modules/rea-agents/scripts/rea.mjs inspect-dart-aot /tmp/rd-workbuddy-android-ui-20261015/apk-static-review/workbuddy-drive-base2.apk --abi arm64-v8a --json
```

All six commands exited **0**, with **0 stderr bytes**. No target APK was installed, executed or connected to a service. REA's temporary read-only snapshots were cleaned after each operation; no `rea-*` snapshot directories remained under its isolated TMPDIR.

| REA observation | Actual value and limit |
|---|---|
| Build evidence | `ev_34289e8b193f16f19e6b72d0cbd4a76288dabc3b8251aabf35bcb5e5a085f500`; observed shipped artifact; identity coverage complete |
| ABI | `arm64-v8a` only |
| libapp | 37815216 bytes; SHA-256 `5be6a8e5e2f2e77372393a396dce0329cf6c707e1b914acf694b116fc93086ba` |
| Snapshot hash | `78da37fed6bf1489361a312568249f3f`, two agreeing header sources; no hash-to-SDK lookup was performed |
| libflutter | 11317824 bytes; SHA-256 `0d3ca63fa946d4264b2fc5281d92ed4d4016dd2cf174214e76bfc7c507a0a59e` |
| Engine GNU build-id | `2ba998ff250d3d969fba77ae3d275dc5a99cbdb7`; labeled Dart version absent (`null`) |
| AOT evidence | `ev_da74d852f64aba4942c091c38da5b7f91e8eff8d41adaa8276228068876c4bfd`; structural coverage complete, string-pool and overall coverage **partial** |
| String projection | 5 observed package URIs (Flutter/ffi/stack_trace), 7 Dart URIs; 2000 returned identifier-shaped tokens of at least4000; 66939 printable runs |

No observed package URI identifies a WorkBuddy application page. Absence from this bounded projection does not prove a class or page is absent. Identifier-shaped byte runs are not recovered typed classes, functions or references. Complete structural snapshot checks do not mean complete Dart deserialization or frontend recovery.

## Frontend implementation decisions

| Surface | Traceable evidence | Current original Compose treatment / remaining input |
|---|---|---|
| App identity | Muyon-owned source and brand material | Keep Muyon naming; do not import WorkBuddy assets or credentials |
| Four destinations and 900dp boundary | Approved Muyon migration baseline | Existing `Destination`, `navigationLayout` and bar/rail shell; these are not newly asserted WorkBuddy facts |
| Draft, last input focus, per-page scroll memory | Approved Muyon behavior and immutable state checks | Existing `ShellState` and hoisted Compose objects; device behavior remains unexecuted |
| Task/permission presentation | Approved Muyon interrupted/cancelling/platform-owner distinctions | Preserve safety copy and disconnected Rust port; do not fabricate tasks, grants or results |
| Input icons, sheets, page routes | Prior static resource/name evidence, not page call sites | Candidate component inventory only; no new placement, enabled action or state transition inferred |
| Complete page layout, theme mapping, typography, interaction timing | No screenshot, Widget tree or application call graph recovered | Per the later09:05 user authorization, continue a reasonable original adjustable layout from operating logic; only full-page fidelity claims require further evidence |

The previously viewed10 PNG remain resource pixels, not runtime page screenshots. A minimum reference for a future pixel-comparison claim remains a complete task/list or assistant page with top/bottom chrome, version, device dimensions/density, font scale and theme; applicable empty/populated/menu states must be identified. This input does not block the later-authorized original frontend implementation. An APK resource or rebuilt collage does not substitute for that input. Existing original frontend work can continue against the approved Muyon behavior contract without inventing WorkBuddy pixel claims.

## Additional provider boundary

Actual Java method decompilation has **not run**. The official Android guide requires a separately supplied headless JADX provider. Its exact official release asset is [jadx-headless-mcp0.7.1](https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar), 42619858 bytes, SHA-256 `6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75`. Those facts were checked against release metadata without downloading the JAR. Existing Java21 includes `jdk.compiler`; procps-compatible `ps` is available, but provider readiness and actual execution remain unverified. Downloading/executing this additional provider awaits the separately required scope decision. JADX would inspect the Java/DEX shell; it must not be reported as Flutter Widget-tree recovery.

## Existing independent CI baseline

Before this evidence-only change, [normal GitHub CI run38707183090](https://github.com/mightyoung/Muyon/actions/runs/38707183090) succeeded at `451b3a2cb9423c02294ed00266fa1f6cc5c61a60`: actual16/16 JVM state checks, `compileDebugKotlin`, `compileDebugAndroidTestKotlin`, `assembleDebug` and `assembleDebugAndroidTest`. Device installation/runtime/rendering remain **NOT_RUN**, Rust **NOT_CONNECTED**, full-page pixel fidelity **UNVERIFIED**. The earlier `VERIFICATION.md` records the initial local-tool baseline; it does not erase this later remote compilation evidence.

This initial evidence-only record was subsequently followed by the authorized original local-UI implementation described in LOCAL-UI-IMPLEMENTATION.md. Raw decompilation output and third-party assets remain outside Git. No additional local SDK/Gradle build was attempted.
