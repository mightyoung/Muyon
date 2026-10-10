# Mac golden follow-up: controlled font-path diagnosis

2026-10-10; fixed current develop `e192a32ebe659160cb64a1d4bd5df0b93bfdb74f`; isolated branch `task/quality-macos-golden-ab`. This is diagnostic work, not a resolved visual gate. No production/test/golden/renderer source is changed in this branch; only this summary is committed.

## New measured results

The same three selected historical failures on this newer current source remain home 2351 px, phone project list 1178 px, settings 5830 px. All twelve expected/actual/isolatedDiff/maskedDiff hashes match fixed `8debfd2`, pre-C2 `4573adb`, and the retained Oct 8 matrix. Current full-suite counts are still unknown.

A telemetry-only temporary copy of the existing screenshot test recorded actual DPR 1, text scale 1, platform locales `[en_US, zh_CN]`, MaterialApp locale `en_US`, light platform brightness and theme family `Noto Sans SC` for all three scenes. Native CoreText observation resolved Noto Sans SC normal/600 variants, AndaleMono in the phone scene, and MaterialIcons. The observation did not alter output: all twelve image hashes stayed identical. Settings URL/model text must not be assumed to use Andale merely from visual appearance: the single-settings observer saw Noto plus MaterialIcons, not Andale.

The existing SDK tester is **Mach-O arm64**, even though its artifact directory is named `darwin-x64`. The SDK and executable hash remain the previously recorded versions. Directory names are insufficient evidence of binary architecture.

## Controlled A/B, not a proposed fix

Hypothesis: a simple CoreGraphics font-smoothing switch could explain the lighter text strokes. A 49 KiB task-local universal diagnostic library intercepted only the rendering calls of the test process. It never wrote macOS preferences, changed SDK files, altered repository renderer/snapshot files, or changed golden comparisons. Recorded requested/effective switches prove the probe was active. A passive observer control retained the original settings actual SHA `bf18dc615cd18ae20cb211e40ff25f93541c2470dc2f4d48deba612900234411`.

| Single settings run | Exit | Different pixels from unchanged golden |
|---|---:|---:|
| Passive observer | 1 | 5830 |
| Force smoothing off | 1 | 41285 |
| Force smoothing on | 1 | 38729 |

Both overrides worsen the result, ruling out a simple smoothing toggle as a corrective patch. This probe changes CoreGraphics smoothing requests, not a historical global AppleFontSmoothing preference, so it does not prove that all preference/backend effects are impossible. Skia's [Mac CoreText rasterization implementation](https://raw.githubusercontent.com/google/skia/main/src/ports/SkScalerContext_mac_ct.cpp) motivates the isolated call-boundary probe; it is not represented as the exact source revision of this cached engine.

No fix, baseline regeneration, tolerance increase or skip is justified by these results. There was no expansion to a full suite. One early attempt was cancelled after detecting a different owner's suite and produced `No tests ran`; it is excluded from all results. Subsequent runs checked both Flutter command and tester processes before starting, used concurrency 1, and were sequential.

## Generation history now located

The original repository exists at `/Users/muyi/Downloads/dev/software-cost-calculator`; only read-only operations were performed there. Its current checkout is an older snapshot, so source comparisons used the exact frozen Git object `b35eccbe9ddf458a6538fa107baa9b456972a4f8`, not checkout files. The original bundled Noto bytes match today's `d68bafcb48a2707749396aa12bbbd833cb70401f3a9a689fd2902c7e0d295964`.

Generation/update commits are now specific:

- `phone_projects.png`: original `79b117e7b1eb8da0007672b704d7f1f8a24e1fa0`, 2026-10-01, introducing the typography redesign and bundled Noto.
- `desktop_home.png`: original `f96e6cb40fb53548ae8a8d5c22f5355f16b3ecfe`, 2026-10-02, workbench icon changes.
- `desktop_settings.png`: Muyon `c7adebf6c4caa47954c1ee12249037716a6df983`, 2026-10-05; its note identifies Flutter 3.47.5, but not exact OS build, tester architecture/hash or font hashes.

The source repository's `artifacts/development/platform/flutter-doctor.log`, preserved in its `484053b` archive, records **macOS 26.5.2 (25F84), darwin-x64, Flutter 3.47.4, Dart 3.13.3**, framework `9584c6713b324636289d067944a46fd6b49df14b`, engine `06a2e2a110089dff50fe635cffd2a61e1b24fbcd`. That log is older than the Oct 1/2 golden updates and therefore is a historical clue, not proof of their generation environment. The recorded SDK path `/private/tmp/supplier-inquiry-toolchain/flutter` is absent now. No alternate SDK was installed or downloaded.

## Exact remaining dependency and minimum question

To separate SDK/CPU/OS font-rasterizer changes from test harness behavior, obtain the actual golden-generation run's **macOS build, tester architecture and SHA256, SDK engine revision, and font SHA256**, particularly Oct 1/2 source goldens and the Oct 5 settings update. Available sources are the original Mac/SDK cache, backups of that cache, the generating sessions' environment logs, or original-repository author/reviewer records for the three commits above. Current files plus the earlier doctor log cannot supply those missing values. DPR and locale on the current side have now been measured, rather than left unspecified.

Minimum user question: “Can the Mac or SDK cache used for these Oct 1–5 golden-generation runs still be accessed, or are only its logs/backups available?” If available, first read its fingerprints and compare one settings render using that already-installed environment; do not install another SDK. If not available, remaining platform attribution is blocked and the current red gate must remain explicitly red.

## Evidence and resource use

Native probe source/binary, exact commands, telemetry-only diff, raw logs, historical doctor log, four-image comparisons and environment JSON remain outside Git under `/tmp/quality-macos-golden-20261010/evidence`. The 4,082,023-byte follow-up bundle was saved through the regular Library upload route as `quality-macos-golden-ab-evidence-20261010.tar.gz`, Library ID `libfile_43d1233313cc81919d249d2a20f6cb51`, file ID `file_00000000aa3482309ec05e57ded1f771`. Sources/cache/evidence used approximately 697 MiB total after bundling; around 13 GiB disk remained during the follow-up. Offline pub resolution exited 0. Only this task's own generated macOS config/Podfile changes were reverted in its isolated worktree after resolution. No large downloads, storage expansion, user-file cleanup, shared F5b changes, merge or release was performed.
