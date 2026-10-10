# F5b slice 2a: controlled component interfaces

Status: proposed integration; native Codex implementation, awaiting real Claude review.

Choice adds optional optionIds/selectedIds/onChangedIds. ID mode retains stable identity for duplicate labels and reorder, reads labels in its accessible text, disables custom entry, and never invokes the legacy label callback. Legacy label mode is preserved. Tabs selectedIndex and Disclosure expanded are optional controlled values: requests invoke callbacks without changing local display until the host supplies new state. Controlled components without callbacks are read only; existing uncontrolled behavior remains.

Verification: five behavior tests genuinely fail against interface-only commit 4011eb7 (missing stable keys, visible custom field, ignored controlled selection/expansion, enabled read-only callback); all five pass after implementation. Full muyon_ui suite passes 480 tests including old catalog and layout cases. First attempts from repository root failed because the UI test harness could not load MaterialIcons assets; these are environment failures, excluded from RED evidence. Genuine RED was rerun from the UI package directory and recorded in controls-real-red.log outside Git.

This slice does not switch the production catalog, add a runtime/router, implement F5c publish/workspace, or claim all 33 component adapters are complete. Raw logs remain /tmp/aiui-f5b-logs.
