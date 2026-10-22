# UI foundation contract — 2026-10-22

Branch `task/ui-foundation-20261022`, base `f4781e16ddf4e542b983fbd77f266a0071148255` verified against origin. No AGENTS.md exists in this candidate tree or workspace ancestors. Existing checkout was clean; main/develop untouched. Latest candidate progress and web-search handoff read; overall acceptance HOLD remains.

Design authority: `task/design-intake-20261022` at `399e3094740c8fcf1783797f0d0ae1f076dfd123`, `docs/design/2026-10-22/ui-v1.0/Muyon-统一UI规范与覆盖-v1.0.md`, and actual image `08-基础组件状态-v1.0.png` inspected. Library source `libfile_a0b55e1cdb208191b7156e193d173c05`, image `libfile_f7ab1e3e06b48191be6766f0c733c298`. The generated image is design reference only. No brand assets copied or regenerated.

## Public API (package com.mightyoung.muyon.product.ui.system)

All controls are controlled components: no network, persistence, receipt inference or automatic retry. Strings are caller supplied for localization. Nullable callbacks mean unavailable capability and render disabled. No default fake business data.

- `FoundationTheme(dark: Boolean = isSystemInDarkTheme(), reduceMotion: Boolean = true, content)` — opt-in local theme only; no existing theme/main/build edits.
- `FoundationTokens.light/dark: FoundationPalette` — background/panel/text/secondary/border/link/action/onAction/error; minimumTarget=48.dp. Neutral soft light/dark; blue reserved for explicit links.
- `ActionState { Ready, Disabled, Loading, Error, Unknown }`; `ButtonKind { Primary, Secondary, Quiet }`.
- `FoundationButton(label, onClick: (() -> Unit)?, modifier, state=Ready, kind=Primary, stateLabel: String?=null)` — loading/unknown block actions; error allows explicit retry only when host supplies callback. Loading/unknown/error require localized stateLabel.
- `FoundationTextField(value, onValueChange: ((String)->Unit)?, label, modifier, state=Ready, supportingText: String?=null)` — editable local draft only, unknown/loading read only; errors persistent. Non-ready states require supportingText.
- `FoundationSelection(label, selected, onSelectedChange: ((Boolean)->Unit)?, modifier, enabled=true)` — one accessible checkbox row, selected conveyed by check and semantics.
- `FoundationTag(label, modifier)` — noninteractive text label, not an action.
- `FoundationMenuItem(id, label, selected=false, enabled=true)`; `FoundationMenu(expanded, items, onSelect: ((String)->Unit)?, onDismiss, modifier)` — controlled popup, selection callback only, no implied host action; stable unique IDs.
- `FoundationDialog(title, onDismiss, confirmLabel, onConfirm: (() -> Unit)?, dismissLabel, modifier, confirmState=Ready, confirmStateLabel: String?=null, content)` — modal scrollable content/actions, nullable confirmation disabled.
- `FeedbackKind { Info, Loading, Partial, Error, Unknown }`; `FoundationFeedback(kind, title, detail, modifier)` — persistent explicit status, unknown distinct from error, no percentage inference.
- `FoundationEmptyState(title, detail, modifier, actionLabel: String?=null, onAction: (() -> Unit)?=null)` — optional real host action; not fabricated capability.

Material controls provide keyboard/focus/press behavior and expanded text sizing, minimum 48dp interactive height (no fixed max height). The reduced-motion flag removes menu open/close transitions and loading animation; native control focus/press/selection feedback follows platform animation settings. Caller must retain existing content alongside feedback; foundation does not own data. Menu/dialog use platform popup/modal dismissal and block background interaction; screen owner retains drafts/back stack and handles keyboard ordering.

## Verification plan and limits

Test first: color contrast tests (normal text >=4.5, meaningful boundaries >=3), Android Compose semantic/behavior tests for disabled/loading/unknown, local selection, persistent error, modal dismissal, 200% text. Standalone preview/test surface uses generic component labels only. Actual Android rendering/screenshot verification required before visual acceptance. At contract publication SDK/adb/kotlinc/Gradle not found in PATH; no build or visual pass claimed. No models/search/paid requests; historical unknown calls and ¥0.002620 reservation untouched.

Contract commit intentionally precedes implementation for parallel consumers. Full completion and independent review evidence will be appended here.

## Implementation handoff — current batch

Implemented all interfaces listed above in `FoundationTokens.kt` and `FoundationComponents.kt`; not wired into any screen. Wrap each consuming screen in `FoundationTheme`, or coordinate a single root wrapper with the shell owner. Do not treat importing this package as completed product UI adoption. Nullable callbacks deliberately disable unavailable capabilities. `ActionState.Unknown` blocks repeat actions: supply a separate host-owned original-receipt query action when supported. Confirmation is purely UI and never itself an approval receipt.

Latest design archive fixed at `400e206135690c284c8402521e3135cfb7bfaee8` (fetched and checked). Reference 08 SHA256 `9cdf958b537a33fc2b1b00067eefb1003beec3bfd77da0481efb0a69e7969acc`; unified specification SHA256 `1b6fdff69cacb64f88a9de5fa5f5125f5f0f4342d98681672a9653d52d36f74c`. No archive commits merged into this feature branch. No asset integration needed in foundation: brand-originals must remain unchanged and the shell owner handles production placement.

### Validation evidence

- Palette test written before implementation: initial missing-file error corrected to an explicit `assertTrue(SOURCE.exists())`; observed expected RED `Foundation palette has not been implemented` (exit 1), then GREEN after token implementation (exit 0). This evaluates actual source palette literals mathematically; it does not sample rendered pixels.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/checks -v`: PASS, one test covering both palettes and text/boundary pairs. Raw latest output: `evidence/contrast.log`.
- `git diff --check`: PASS. All changed files confined to this directory and corresponding `androidTest/.../ui/system` directory.
- Build, Kotlin compilation, project JVM suite and lint attempted via repository wrapper: exit 2, missing Gradle 8.13 executable. `evidence/android-build.log` retains command and result. SDK/adb/kotlinc also unavailable in PATH. No external tooling installation, credential configuration or permission expansion attempted.
- Compose behavior and rendering test targets were written before implementation, but their RED/GREEN behavior could NOT be executed. This is an explicit test-first execution gap, not a passing TDD cycle. Device run attempt exit 2: `evidence/android-render.log`. Review regression tests also remain NOT_RUN.
- `FoundationComponentsTest` covers unavailable/disabled/loading/unknown actions, disabled selection semantics callback, local checked state, dark default text color, persistent error/unknown at 200% font, retained draft, menu host selection/dismiss, and disabled dialog confirm/cancel.
- `FoundationRenderingTest` defines four actual Compose rendering cases: light/dark × 100%/200%, saving top/bottom screenshots under device app external-files `foundation-rendering/`. It has NOT run; no screenshot files were generated and no actual rendered visual acceptance is claimed. A device reviewer must inspect screenshots for clipping, text, focus, popup occlusion and contrast, plus keyboard/TalkBack and background hit interception. Capturing an image alone is not visual acceptance.

### Independent review

Initial immutable implementation `44ac99a82a19510c1913d52dac66c2cd78174d5b` independently reviewed with static HOLD: disabled selection callback lacked an internal enabled guard; dark theme failed to set default LocalContentColor; reduced-motion menu retained Material transitions. Follow-up `d532552dcb2c0103c652e6a5fb8e8746aa098e15` corrects all three, with regression test targets for callback/default-color issues. Final independent disposition is recorded in `REVIEW.md` when available.

### Remaining gates / owner handoff

This is a minimal foundation source batch, not completion of all requested UI development. Before integration acceptance: compile production/test Kotlin and lint; execute the named behavior/rendering tests on Android; inspect actual screenshots, 48dp targets, small screens, 200% font, keyboard/TalkBack, focus/pressed/disabled states, no modal click-through and draft/back behavior. Native checkbox/button/dialog press/selection transitions use OS animator settings; local reduceMotion specifically suppresses foundation menu and loading animation. Existing main/develop, theme/main/build and brand assets unchanged. Unique Leader B retains develop integration authority. Historical two unknown calls / ¥0.002620 reservation remain unchanged, without any retry or real model/search call.

## Material fallback supplement — 2026-10-22

Required by shell `HOST-ADAPTER-PATCH-PLAN.md` item 6, read at immutable `8937b3d62943351f918b4ae980f987e804427911`. Runtime/test increment is one commit: `a810f204c27658a43f3ed13cca7ea0e59ce450b8`, parent `2aa95ba7ab74ea11f9a89a42d2568650363e6c17`. Shell can take this commit alone after the prior foundation; no shell history was merged.

Explicitly mapped previously inherited ordinary Material roles: primary/secondary/tertiary containers and their foregrounds, tertiary foreground/background, inverse surface/foreground/primary, all ordinary surface elevation roles including `surfaceContainerLow`, and error containers. Foundation surfaces/containers use neutral background/panel; inverse roles use neutral text/panel; `surfaceTint` remains transparent. Scrim is the dark neutral light-palette text token in either mode. Semantic error roles retain the error color; explicit links remain blue. No palette literals or public component signatures changed.

Before production edit, static regression failed with 18 missing mappings (expected RED, exit 1). After edit, `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/checks -v` passes 2 tests (exit 0). New regression checks explicit enumerated role coverage, neutral mapping, both palettes' text/container pairs >=4.5:1 and surface boundaries >=3:1. See `evidence/material-roles-regression.log`. `git diff --check` passes. Independent static review approved immutable increment; see `REVIEW.md` supplement.

Android build/instrumentation/rendering remain NOT_RUN; this supplement did not configure tools, access SDK paths or retry any denied operation. Tests inspect source mappings, not compiled Compose values or actual pixels; API compatibility and runtime visual acceptance remain open. This enumerates ordinary Material roles for the pinned theme usage, not unverified future/fixed-accent API coverage. No shell/business/theme-entry/build files changed. Main/develop and all live-call/billing restrictions remain unchanged.
