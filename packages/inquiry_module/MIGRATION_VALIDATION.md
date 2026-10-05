# Supplier module migration validation

Frozen source: `software-cost-calculator` commit
`b35eccbe9ddf458a6538fa107baa9b456972a4f8` (origin/main, 2026-10-04).

All 85 supplier UI Dart files excluding standalone `main.dart` are retained.
Only `app/app_state.dart` and `app/shell.dart` differ from the frozen UI:
host-owned database/task store/data directory/secret injection, shutdown drain,
and an embedded shell with no window controls. The new public entry point is
`InquiryRuntime.attach` / `InquiryHome`; it shares the host Navigator and window.

The original source test suite, screenshots and referenced graph/icon fixtures
are retained. Test package imports and fixture locations were adapted; generated
review images now go to a test temporary directory instead of source directories.
Run UI tests from `apps/muyon` so they load the host's original asset keys:

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
  flutter test --no-pub ../../packages/inquiry_module/test
```

## Verified host boundary

Local run on 2026-10-04: migrated UI suite 309 passed, 1 skipped and the single
known source golden failure documented below. Targeted host attachment, export,
restore and migrated fixture suite: 18 passed. After the final LAN/shutdown guard,
host attachment and background/LAN tests: 4 passed. Static analysis of both
`supplier_core` and `inquiry_module`: no issues.

Attachment regressions verify same-connection execution, host-only connection
closure, injected secrets without plaintext file storage, no automatic LAN start,
and shutdown rejecting new writes while draining an already-running operation.
The core host regression verifies export -> strict standalone preview/import ->
restore -> reopen, retaining the live host schema, migration state and version.
Only exported copies drop `host_schema_state` and `schema_migrations` and reset
SQLite user_version; the supplier import schema allowlist remains unchanged.

## Existing source golden difference

On the current Flutter SDK, `screenshot_test.dart` / `desktop settings` differs
from its frozen golden by 158 pixels (0.02%), at a dropdown arrow. This was
reproduced with the *unmodified* frozen supplier UI and its original test, using
the same resolved dependencies via an alternate package map. Both original and
migrated renders are byte-identical:

- Rendered PNG SHA-256:
  `3f51c7a531a4fc403840bfb0aa007f04f8cb93b462ad409b4c673590de638090`
- Isolated diff PNG SHA-256:
  `eb6f0b93fb2fd1ab1eb90d889becfd6f0800636bdd48e55d9189e4bb97a254ed`

The frozen golden is preserved. This is an existing source/current-SDK visual
baseline failure, not a passing screenshot acceptance claim. No physical-device,
release or real-model acceptance follows from the local tests.

## Golden baseline update (2026-10-05)

A decided to update this one golden instead of keeping the known failure in
`scripts/verify.sh`, because a permanent allow-list entry would also hide real
regressions of this screenshot later.

Re-ran the failing test on Flutter 3.47.5 (stable, framework revision
`6a19cca564`, 2026-09-17) from `apps/muyon`. The only difference is still the
dropdown arrow next to “改前逐次确认”: bounding box (431,649)–(480,668) in the
1280×800 render, 158 pixels = 0.0154% (below the ~0.05% review threshold). No
other pixels differ; the arrow glyph is unchanged, only its horizontal position.

- Previous golden SHA-256:
  `24c143a01b5c250a03b9936cbf59f28c82a37b35909f03f77379eeeb3a3cf50c`
- New golden SHA-256:
  `3f51c7a531a4fc403840bfb0aa007f04f8cb93b462ad409b4c673590de638090`
  (byte-identical to the rendered PNG recorded in the section above)
- Update command:
  `cd apps/muyon && flutter test --update-goldens --plain-name 'desktop settings' ../../packages/inquiry_module/test/screenshot_test.dart`
- Only `packages/inquiry_module/test/screens/desktop_settings.png` changed;
  `scripts/verify.sh` no longer lists this test in `KNOWN_FAILURES`.

The earlier record is kept as history. This is a local SDK rendering baseline
update, not physical-device, release or real-model acceptance.
