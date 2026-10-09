# UI-4a preview build and later controlled-URL smoke

The Flutter entry is `apps/muyon_ui_preview`. Public fixtures reuse the validated runtime. Select **UI-4a fixture** to edit/sort, open sources/detail and return, apply a complete patch, cancel/confirm a simulated memory operation, or request a simulated explanation. Nothing calls a model, host database or network service.

The confirmation fixture starts with fact quantity 10 and host-provided draft 12. Editing makes its old operation reference stale; a new confirmation needs a fresh host context. A simulated receipt does not rewrite the snapshot; new facts require the trusted service to publish a new snapshot. Batch mapping supports one existing operation; it does not invent per-record authorization.

Build: `cd apps/muyon_ui_preview && flutter build web --release`. The `ui-preview` workflow uploads only the static package and a hash manifest. It does not deploy or create a public URL.

Cloud deployment/browser acceptance is paused. Once authorized hosting is available and the supplied environment has Playwright, use:

```sh
node scripts/ui_preview/smoke.mjs --base-url "$PREVIEW_URL" --output /tmp/muyon-ui-preview-evidence
```

Use the actual controlled URL and static package SHA. The script checks mobile/desktop operations and saves screenshots plus a result manifest; do not treat compilation or Widget tests as browser evidence. Large text, light/dark themes and native capabilities still need their recorded browser/device matrix; the script currently covers only default browser styling and the two viewport sizes. Do not install a browser/SDK or deploy as a side effect of this script. No raw logs or screenshots enter Git.

Existing host `inquiry_write_tools_test.dart` separately tests real SQLite quantity 10→12 and authorization failure paths in CI. That is existing business evidence, not a claim that the browser runtime invokes SQLite or that REG-4a/UI-4b integration is complete.

Later real GPT replay/export still needs a host recorder for full question/answer and task/turn context, serializer/parser with schema/catalog versions, event/payload and patch acceptance history, immutable snapshot/source digests, actual port receipts and user revisions, redaction/consent and reviewed training-candidate records. This slice exposes stable surface/node IDs, revisioned events, patch IDs and correlated pending/receipt references. It adds no GPT API, paid call, credentials or training pipeline. Existing exam packages remain question/regression material, not runtime gold data.
