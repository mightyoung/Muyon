# UI-3a recovery validation

Branch: `task/ui-3a-semantic-preview-recovery`.
Base: `4f2f749958a14ad9d94e607dc79ada62df753f28`.
The original author's 29-file uncommitted implementation was copied and SHA-256 checked; see `ui-3a-recovery-source-snapshot.json`. Original worktree files matched the frozen snapshot again after validation. Unrelated macOS Podfile and both Flutter xcconfig changes are excluded.

## Reproduced failures

Before production changes, both new preview regression tests failed because validation returned true for `SourceList.tap -> detail` and `Field.change -> back` (expected false; test command exit 1). The existing alternative-fixture test also failed when asserting quantity should be verified, before correcting the delivery conflict fixture (exit 1).

## Change

`UiComponentSchema.eventActions` declares immutable sets of allowed action refs per event. Missing mappings allow no actions. The implemented catalog permits Field/change/edit, SourceList/tap/source and ObjectChip/tap/detail or back/back. Validator and dispatcher reject incompatible pairs. Detail actions require a value binding; the renderer also handles a missing detail value without forced null dereference. The alternative fixture exposes delivery as the conflict fact and keeps quantity verified; its source text supports both facts. Invalid plans retain original answer text with no interactive controls.

## Fresh verification

SDK: Flutter 3.47.5 stable / framework `6a19cca564`, Dart 3.13.4.

Commands run through the isolated SDK's `dart flutter_tools.snapshot --no-version-check --suppress-analytics`:

| Working directory | Command | Result |
| --- | --- | --- |
| apps/muyon_ui_preview | test --no-pub --concurrency=1 --reporter=expanded --timeout=20s | 7 tests passed; exit 0 |
| packages/muyon_module_api | test --no-pub --concurrency=1 --reporter=expanded --timeout=30s | 37 tests passed; exit 0 |
| packages/muyon_ui | test --no-pub --concurrency=1 --reporter=expanded --timeout=30s | 225 tests passed; exit 0 |
| workspace | dart analyze packages/muyon_module_api packages/muyon_ui apps/muyon_ui_preview | No issues found; exit 0 |
| apps/muyon_ui_preview | build web --no-pub --release | Build succeeded; exit 0 |
| workspace | git diff --check | Passed |

Total: 269 relevant package tests. The full unrelated monorepo suite and browser acceptance were not run. Build output has the existing Intel-Mac support notice and Wasm dry-run suggestion; neither is a failure.

## Diagnostic environment differences

The recovery source files were tested directly, without replacing Flutter test imports. SDK cache/config and build artifacts are isolated outside the original worktree. Package-config paths point to this worktree; no original build locks are copied or removed. During each test/build command only, the recovery workspace pubspec temporarily sets `hooks.user_defines.sqlite3.source=system` to avoid a native-library download; the runner restores the exact original pubspec in finally. The child process uses localhost `NO_PROXY` and `no_proxy`. Widget tests used approved sandbox escalation for localhost sockets. These environment accommodations are not committed application configuration changes.

No original processes were killed, no original author files were overwritten, and no develop merge or deployment was performed. Raw logs and build artifacts remain outside Git.

Web main.dart.js SHA-256: `4cd40b095b35e8e5e7aad96ab9d5ffa3d3a1663a2e3bb95b9e456cf57c50326c`.
