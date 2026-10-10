# Mac golden historical-debt diagnosis — 2026-10-10

## Outcome and scope

Three historical Inquiry golden failures reproduced on both fixed sources. All twelve expected/actual/isolatedDiff/maskedDiff PNG hashes match between sources and also match the retained 2026-10-08 comparison matrix. This establishes non-regression only for these three cases. The current full-suite failure count remains unknown; the historical 281 passed / 1 skipped / 46 failed is not a current result. Linux platform skips are not visual acceptance.

No golden, comparator, tolerance, skip, assertion, renderer/snapshot core, font asset or production code was changed. Only this summary is committed. Root cause is narrowed to historical text rendering but not conclusively attributed to OS, CoreText, engine or font-version drift; no safe corrective patch is justified yet.

## Fixed sources and history

- Current cached origin/develop: `8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d`. Local develop was older (`4e61cc7604c67faf34966fe9a9b6183c09041ec1`); no fetch was needed for the local fixed comparison, and no claim is made that the remote could not move afterward.
- Pre-C2 baseline: `4573adb73f32526bc3f3bab8125db923e474f890`.
- Historical C2 integration: `ffe6be31a8a4cb516f8bcc5331a3065cbc142dcd`; publication documented at `00dbd6cf722ddd4b5f7e8c65ec378ee4150fada9`.
- Read current HANDOVER-LEADER, VERIFICATION-MEMO, REVIEW, AUTH-1b-model-policy-review and Inquiry MIGRATION_VALIDATION. No tracked AGENTS.md or .skills directory exists on either selected source; the original working tree has no applicable repository AGENTS.md.
- Historical evidence still exists locally at `/tmp/auth-c2-golden-4573-comparison.json`; its three selected entries were compared directly, not inferred from historical totals.

## Environment and safeguards

macOS 27.0.1 (26A434), arm64; existing absolute SDK `/Users/muyi/development/flutter`, Flutter 3.47.5 / Dart 3.13.4, framework `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`, engine `af7e796e161ae0bb1ff0758c71a7105418bd9ded`, engine content hash `ab598368592da0064197e2bc15c7f5b0a2c6bb1f`. Test executable is SDK darwin-x64, software + deterministic Skia rendering; test-font/disable-asset-font flags are framework defaults. Test sets DPR=1 and scene physical sizes explicitly.

The test loads bundled Noto Sans SC, aliases the existing system Arial Unicode into Roboto/fallback families, aliases Andale Mono into the monospace stack, and loads SDK MaterialIcons. Font versions read with existing fontTools: Noto 2.004, Arial Unicode 1.01x, Andale Mono 2.00x. SHA256 fingerprints:

| Input | SHA256 |
|---|---|
| NotoSansSC-VF.ttf | d68bafcb48a2707749396aa12bbbd833cb70401f3a9a689fd2902c7e0d295964 |
| Arial Unicode.ttf | 876af2cd4854644e7f3e7feb2f688997fdb3343c6df6693611209c9dfb47ccec |
| Andale Mono.ttf | ca436a8f07f6699107542ebe19dcc9478f12aa666927699e9fa10115e7d2ee95 |
| MaterialIcons-Regular.otf | d9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453 |
| darwin-x64/flutter_tester | 118ef3bd0c67da11ed6a369c4932ea487d45f4e36aa590e59523e7544f8fa354 |

Disk showed approximately 17 GiB available before and after the run. Two clean git-archive source copies were used under `/tmp/quality-macos-golden-20261010`; diagnostic data plus copies/build caches were 417 MiB before adding the 54 MiB report worktree. Temporary compiler artifacts may add space; no install, download, storage expansion or user-file cleanup occurred. Both original source test and lockfiles were checked byte-for-byte against their fixed Git objects after offline resolution. HTTP(S) proxies were inherited only at 127.0.0.1; NO_PROXY and no_proxy were set to localhost,127.0.0.1,::1.

Flutter's shell launcher initially failed because the sandbox could not write the existing SDK cache stamp, and direct flutter_tools initially could not open its lockfile. A narrow execution exception for the existing SDK lock/local sockets was approved. No ownership/permission/SDK configuration was changed. Existing test processes were inspected, and baseline/current runs were sequential with concurrency=1.

## Exact reproduction

For each tree (`baseline`, then `current`), run the existing cached tool directly to avoid shell-launcher stamp writes:

```sh
cd /tmp/quality-macos-golden-20261010/<tree>
env NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_ROOT=/Users/muyi/development/flutter /Users/muyi/development/flutter/bin/cache/dart-sdk/bin/dart /Users/muyi/development/flutter/bin/cache/flutter_tools.snapshot --no-version-check pub get --offline
cd apps/muyon
env NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 FLUTTER_SUPPRESS_ANALYTICS=true FLUTTER_ROOT=/Users/muyi/development/flutter /Users/muyi/development/flutter/bin/cache/dart-sdk/bin/dart /Users/muyi/development/flutter/bin/cache/flutter_tools.snapshot --no-version-check test --no-pub --concurrency=1 --reporter expanded ../../packages/inquiry_module/test/screenshot_test.dart --name '^(desktop settings|desktop home|phone project list)$'
```

Offline pub get exited 0 in both trees; each golden command exited 1 with 0 passed / 3 failed / 0 skipped (setup/teardown excluded). Each selected image has four identical hashes across both trees and the historical 10/8 matrix:

| Case | Image size | Different pixels vs expected | Actual SHA256 |
|---|---|---:|---|
| desktop home | 1280×800 | 2351 | 754a40cc4353aa9ba918e0ff5bfb6f8d8f54af2a4bea1cbe8a6f4ae7ebdd50ed |
| desktop settings | 1280×800 | 5830 | bf18dc615cd18ae20cb211e40ff25f93541c2470dc2f4d48deba612900234411 |
| phone project list | 390×844 | 1178 | 4d2e4cd1989b38344bc5b463d4cbcba372d5545dce94fc9d35f46d6426f85643 |

## Diagnosis and remaining work

Visual inspection of isolated/masked differences shows changes on text strokes, with no visible control-boundary relocation in the settings scene. Changed pixels are overwhelmingly lighter in actual than expected across all RGB channels: settings 5744/5830, home 2245/2351, phone 1089/1178. Alpha is unchanged. This is consistent with text rasterization/weight drift, rather than broad widget layout movement; it is a hypothesis, not proof of a specific platform bug. Max channel differences are 108, 112 and 97 respectively, so this is not merely a one-level PNG rounding difference.

The current and old screenshot source, golden assets, theme/shell and bundled font assets are unchanged for these cases. Current lock adds cupertino_icons, but identical actual renders exclude a visible effect in the selected scenes. The 10/5 settings golden was recorded on the same nominal Flutter version; its note describes a separate 158-pixel dropdown shift. Today's 5830-pixel text difference must not be conflated with that resolved incident.

Next useful controlled investigation requires the baseline-generation machine's exact OS/font/engine fingerprints or its already-installed toolchain (no new SDK installation), to distinguish CoreText/Skia backend behavior from font registration/version behavior. A minimal standalone text probe can then compare Noto primary versus Arial fallback at explicit normal/600 weights. Merely re-running all 46 cases on the unchanged environment will not resolve that cause. Expand to affected suites only after a specific cause and low-risk corrective patch are established; keep F5b snapshot/renderer changes with its owner.

Raw logs, environment/commands, full four-PNG hash matrix and copied images remain outside Git at `/tmp/quality-macos-golden-20261010/evidence`. The 1,944,141-byte evidence archive was saved through the regular Library upload route as `quality-macos-golden-evidence-20261010.tar.gz`, Library ID `libfile_24488ba34dd081919c8ba5c70ab1b718`, file ID `file_000000003f408230b348eaa2fe34e123`. No full Mac verify.sh, physical-device or release acceptance is claimed.
