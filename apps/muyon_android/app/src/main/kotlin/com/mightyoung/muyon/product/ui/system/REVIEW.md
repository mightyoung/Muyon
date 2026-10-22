# Independent foundation source review

Reviewer: isolated read-only `foundation_review` agent, supplied only requirements, base/source SHAs and tool limitations; no implementation edits by reviewer.

Base: `f4781e16ddf4e542b983fbd77f266a0071148255`.
Initial implementation: `44ac99a82a19510c1913d52dac66c2cd78174d5b` — HOLD.

1. P1: selection/empty-state default text inherited LocalContentColor instead of dark text palette. Corrected by providing LocalContentColor from FoundationTheme; new dark default-color regression target.
2. P2: disabled selection depended on platform enabled semantics without an internal callback guard. Added guard and disabled semantics activation regression target.
3. P2: reduced-motion menu retained Material transitions. Reduced-motion path now uses a focusable nonanimated Popup; ordinary path retains native DropdownMenu.

Reviewed corrected immutable source: `d532552dcb2c0103c652e6a5fb8e8746aa098e15`.
Final disposition: STATIC APPROVAL; no remaining blocking source findings or apparent Compose API/type issues found. Reviewer independently ran palette contrast and whitespace checks successfully. Reviewer did not run Android compilation, instrumentation, rendering or visual acceptance; all remain NOT_RUN. Device verification must check popup positioning, keyboard focus/dismissal, and large-text dialog/menu layouts. Source approval does not resolve these gates.

Local reduceMotion controls menu/loading animation; standard Material control focus/press/selection feedback follows OS animation settings. Screens still need real integration and actual visual review. This review excludes later documentation/evidence-only changes, including this file.

## Material role supplement

Independent read-only review of `a810f204c27658a43f3ed13cca7ea0e59ce450b8` against `2aa95ba7ab74ea11f9a89a42d2568650363e6c17`: STATIC APPROVAL, no blocking findings. Required secondaryContainer/onSecondaryContainer/surfaceContainerLow use neutral tokens. Container/inverse/surface/error/tint/scrim mappings are consistent and enumerated foreground/background pairs meet contrast thresholds in both palettes. Reviewer independently ran 2 Python tests and diff whitespace checks successfully. Runtime/test diff confined to FoundationTokens.kt and checks/test_contrast.py. No reviewer edits or SDK operations.

Limit: tests validate enumerated source roles, not runtime rendering or exhaustiveness against the installed Material API. Android compilation/instrumentation/rendering/visual acceptance remain NOT_RUN. Later documentation/evidence seal excluded from immutable source review.
