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

### Bounded Mac search update (2026-10-10)

The user authorized checking this Mac and suspected that old files were removed. Read-only search found retained evidence; it does **not** establish permanent deletion.

| Checked scope | Result |
|---|---|
| Two original Folio projects, Muyon task/implementation records, selected frozen Git documents | Earlier doctor/version logs retained; no exact Oct 1/2 generator tester hash found |
| 12 standard SDK/cache prefixes, depth ≤8, 1500-directory cap | Only current `/Users/muyi/development/flutter` tester found; recorded `/private/tmp/supplier-inquiry-toolchain` absent; common FVM/Homebrew/Flutter cache prefixes absent |
| Task-related direct `/tmp` logs, 2 MiB/file cap | Later diagnostics retained; no Oct 1–5-mtime candidate in this direct-file subset; mtime is not provenance proof |
| Three already-registered Oct 5 release worktrees and their adjacent verification logs | Original settings actual + expected + diffs retained, as are SDK version and native-ABI metadata |
| Time Machine/volume metadata only | No local snapshot names; `listbackups` exit 1: no machine directory found; no destinations configured; `/Volumes` contains only the system-volume link. No external contents mounted or restored |

No home-wide search, private documents, chat/session history, browser history, credential stores, Trash, or restricted directories were inspected. Frozen Git Markdown was limited to relevant UI/verification documents ≤128 KiB; project text scans were depth ≤5 and ≤2 MiB/file. Historical build inspection was limited to selected native/font artifacts at depth ≤6.

**Important recovered facts:** all three Oct 5 worktrees retain `desktop_settings_testImage.png` SHA `3f51c7a531a4fc403840bfb0aa007f04f8cb93b462ad409b4c673590de638090`, identical to the settings golden later committed by `c7adebf`. Their verification logs report the earlier 158-pixel dropdown difference; they do not contain today's 5830-pixel text difference. Oct 5 package configs record Flutter 3.47.5 / Dart 3.13.4 at the same absolute SDK path. Native assets are explicitly `macos_arm64`, so the older Intel doctor log must not be used to infer the architecture of these Oct 5 runs.

Retained Oct 5 Noto source/unit-test assets and MaterialIcons hashes match today's fonts exactly. Historical system-font copies and an exact Oct 5 tester binary hash were not found. The retained source font and icon bytes therefore exclude a change of those specific assets, while not excluding system fallback/OS behavior.

The task-relevant entries in readable `/Library/Receipts/InstallHistory.plist` record macOS 26.5.2 and an upgrade to **macOS 27.0.1 on 2026-10-06 at 06:45:16 UTC**. This puts the Oct 5 matching render before the OS upgrade and the later reproduced text drift after it. OS-dependent font rasterization now has strong temporal evidence; the exact CoreText/Skia mechanism and old system-font hashes remain unverified. A simple smoothing override already failed the controlled A/B. No low-risk harness corrective patch follows from this evidence.

Within the checked scope there is no directly runnable pre-upgrade OS environment or alternate old tester. Current retained screenshots can support visual comparison, but running the prior OS would require another existing machine/backup environment or separately authorized recovery; none was restored or installed here.

### Controlled baseline reconstruction proposal — not executed

1. Freeze a proposed supported Mac27 environment and current reviewed source: record OS build, actual tester architecture/hash, SDK/engine revision, locale, DPR, text scale, all font hashes and renderer flags. Preserve old expected PNGs and existing Oct 5/Oct 8 evidence separately. Use the existing three-scene visual review material first; inspect text position, line widths, weight, clipping, controls, icons and scroll positions at native scale with overlays.
2. Require a named visual reviewer to approve each concrete old/current/diff comparison and the explicit policy of moving the baseline to Mac27. Any layout or business-state difference must be explained or fixed. This is a new visual acceptance decision, not an extension of the old C2 exception, and root-cause uncertainty must remain recorded.
3. Only after explicit approval, prepare an independent baseline-candidate branch. Estimate total added build/evidence space first and stop if it may exceed 1 GiB or current free space is insufficient. Use the existing SDK/cache, one Mac test process, no broad regeneration. Initially change only the three approved candidate PNGs, preserving exact bytes and a review manifest; do not change tests, skips, comparators or tolerances.
4. Verify the same three cases against unchanged old baseline and proposed current baseline under the **same** pinned environment. First run the old-source control and current source for every subsequently proposed scene. Compare complete dimensions, diff-pixel counts and expected/actual/diff hashes; disclose added/removed/changed failures. Expand to the affected screenshot suite only if resource limits permit and only with explicit per-image visual acceptance. Stop at unexplained differences rather than regenerating them away.
5. After the full affected suite is independently reviewed, run the Mac gate and existing non-golden regressions on the final exact source. Linux skips remain non-visual evidence. A draft PR must list approved images, reviewer decisions, environment/commands, old/current failure sets and limitations; independent review and the user's existing merge policy govern publication. This proposal does not authorize overwriting golden files now or modifying F5b.

The standalone local review artifact `/tmp/quality-macos-golden-20261010/golden-visual-review-20261010.html` embeds the existing three expected/actual/diff images with an opacity slider. It is review material, not regenerated golden data. New raw search indexes, hashes, extracted task-relevant log lines and backup-query status remain outside Git under `evidence/search`. The search/review bundle (1,188,843 bytes) was saved to Library as `quality-macos-golden-search-review-20261010.tar.gz`, Library ID `libfile_b04f1d299f0081918871779edaa7a1a9`, file ID `file_00000000a69c81fd9e2b84f5a062f908`. No new Flutter tests or baseline-generation commands were run during this read-only search.

To fully separate SDK/CPU/OS font-rasterizer changes from test harness behavior, an exact generator tester/engine fingerprint and historical system-font hashes are still useful. The search now recovered Oct 5 SDK version, arm64 ABI, bundled font hashes, matching images and an OS-upgrade timeline, so these are no longer all unspecified. The exact generator tester SHA and historical system-font hashes remain missing.

The user's reply authorized the bounded search above. No further broad search, recovery, installation, or baseline approval is assumed. The current red gate remains red; the controlled reconstruction proposal is ready for visual review if the original environment cannot be accessed elsewhere.

## Evidence and resource use

Native probe source/binary, exact commands, telemetry-only diff, raw logs, historical doctor log, four-image comparisons and environment JSON remain outside Git under `/tmp/quality-macos-golden-20261010/evidence`. The 4,082,023-byte follow-up bundle was saved through the regular Library upload route as `quality-macos-golden-ab-evidence-20261010.tar.gz`, Library ID `libfile_43d1233313cc81919d249d2a20f6cb51`, file ID `file_00000000aa3482309ec05e57ded1f771`. Sources/cache/evidence used approximately 697 MiB total after bundling; around 13 GiB disk remained during the follow-up. Offline pub resolution exited 0. Only this task's own generated macOS config/Podfile changes were reverted in its isolated worktree after resolution. No large downloads, storage expansion, user-file cleanup, shared F5b changes, merge or release was performed.
