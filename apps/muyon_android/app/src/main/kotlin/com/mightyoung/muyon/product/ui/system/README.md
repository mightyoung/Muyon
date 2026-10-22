# UI foundation contract — 2026-10-22

Branch `task/ui-foundation-20261022`, base `f4781e16ddf4e542b983fbd77f266a0071148255` verified against origin. No AGENTS.md exists in this candidate tree or workspace ancestors. Existing checkout was clean; main/develop untouched. Latest candidate progress and web-search handoff read; overall acceptance HOLD remains.

Design authority: `task/design-intake-20261022` at `399e3094740c8fcf1783797f0d0ae1f076dfd123`, `docs/design/2026-10-22/ui-v1.0/Muyon-统一UI规范与覆盖-v1.0.md`, and actual image `08-基础组件状态-v1.0.png` inspected. Library source `libfile_a0b55e1cdb208191b7156e193d173c05`, image `libfile_f7ab1e3e06b48191be6766f0c733c298`. The generated image is design reference only. No brand assets copied or regenerated.

## Public API (package com.mightyoung.muyon.product.ui.system)

All controls are controlled components: no network, persistence, receipt inference or automatic retry. Strings are caller supplied for localization. Nullable callbacks mean unavailable capability and render disabled. No default fake business data.

- `FoundationTheme(dark: Boolean = isSystemInDarkTheme(), reduceMotion: Boolean = true, content)` — opt-in local theme only; no existing theme/main/build edits.
- `FoundationTokens.light/dark: FoundationPalette` — background/panel/text/secondary/border/link/action/onAction/error; minimumTargetDp=48. Neutral soft light/dark; blue reserved for explicit links.
- `ActionState { Ready, Disabled, Loading, Error, Unknown }`; `ButtonKind { Primary, Secondary, Quiet }`.
- `FoundationButton(label, onClick: (() -> Unit)?, modifier, state=Ready, kind=Primary, stateLabel: String?=null)` — loading/unknown block actions; error allows explicit retry only when host supplies callback. Loading/unknown/error require localized stateLabel.
- `FoundationTextField(value, onValueChange: ((String)->Unit)?, label, modifier, state=Ready, supportingText: String?=null)` — editable local draft only, unknown/loading read only; errors persistent. Non-ready states require supportingText.
- `FoundationSelection(label, selected, onSelectedChange: ((Boolean)->Unit)?, modifier, enabled=true)` — one accessible checkbox row, selected conveyed by check and semantics.
- `FoundationTag(label, modifier)` — noninteractive text label, not an action.
- `FoundationMenuItem(id, label, selected=false, enabled=true)`; `FoundationMenu(expanded, items, onSelect: ((String)->Unit)?, onDismiss, modifier)` — controlled popup, selection callback only, no implied host action; stable unique IDs.
- `FoundationDialog(title, onDismiss, confirmLabel, onConfirm: (() -> Unit)?, dismissLabel, modifier, confirmState=Ready, confirmStateLabel: String?=null, content)` — modal scrollable content/actions, nullable confirmation disabled.
- `FeedbackKind { Info, Loading, Partial, Error, Unknown }`; `FoundationFeedback(kind, title, detail, modifier)` — persistent explicit status, unknown distinct from error, no percentage inference.
- `FoundationEmptyState(title, detail, modifier, actionLabel: String?=null, onAction: (() -> Unit)?=null)` — optional real host action; not fabricated capability.

Material controls provide keyboard/focus/press behavior and expanded text sizing, minimum 48dp interactive height (no fixed max height). No decorative animation; loading indicator is static by default for reduced motion. Caller must retain existing content alongside feedback; foundation does not own data. Menu/dialog use platform popup/modal dismissal and block background interaction; screen owner retains drafts/back stack and handles keyboard ordering.

## Verification plan and limits

Test first: color contrast tests (normal text >=4.5, meaningful boundaries >=3), Android Compose semantic/behavior tests for disabled/loading/unknown, local selection, persistent error, modal dismissal, 200% text. Standalone preview/test surface uses generic component labels only. Actual Android rendering/screenshot verification required before visual acceptance. At contract publication SDK/adb/kotlinc/Gradle not found in PATH; no build or visual pass claimed. No models/search/paid requests; historical unknown calls and ¥0.002620 reservation untouched.

Contract commit intentionally precedes implementation for parallel consumers. Full completion and independent review evidence will be appended here.
