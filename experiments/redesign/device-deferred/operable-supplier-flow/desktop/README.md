# RD-P08 browser projection

Desktop D01.1 has directory search, a stable-ID supplier list, and current/detail/raw editor panels. Mobile uses list → detail → full editor. The v1.3.2 page handbook body and F13 are the reference; the Android addendum keeps the body authoritative over the older PNG.

This is a private synthetic experiment. M03 remains `blocked_contract`. P07 preview is validation, not a grant. The renderer implements no name normalization, CAS, business mutation, dispatch binding, receipt verification, or commit replay. It uses host projections and narrow actions only.

## Run and verify

Start the combined host as documented in `../host/PROJECTION.md`. It serves `index.html`, `app.mjs`, and `styles.css`; no build, npm package, or dependency installation is needed. First GET receives `session` and `csrf`. Only the session reference lives in per-tab sessionStorage; no success/receipt authority is stored in the browser. Later requests send `X-RD-P08-Session`; POST also sends `X-RD-P08-CSRF`.

```sh
node --test experiments/redesign/device-deferred/operable-supplier-flow/desktop/tests/browser.test.mjs
```

Run from repository root. Tests require existing Node (WebSocket support) and `/usr/bin/chromium`. They run actual Chromium rendering, events, keyboard and clipboard interactions against a **MOCK host**. They do not run P07 or inspect SQLite. Optional `RD_P08_SCREENSHOT_DIR` points to an already-created directory outside Git for screenshots. Browser plugin unavailable and project Playwright unavailable (`ERR_MODULE_NOT_FOUND`); existing Chromium CDP is the explicitly permitted no-install fallback.

## UI boundaries

- Selection sends the stable supplier ID and leaves any original editor visible with its own ID. Edit is explicit and requires no existing editor. Saved or confirmed conflict editors must be explicitly ended before a fresh edit.
- Draft actions preserve JS UTF16 units, including whitespace, NUL and lone surrogates. HTML textarea displays CR/CRLF as LF; a presentation offset map retains the exact original buffer through insertion/deletion and uses original beforeinput/clipboard data when available. This mapping has no supplier-name semantics. Browser-provided text is the input boundary; unknown transformations in other browsers/OS clipboard providers are not covered.
- Draft requests serialize before preview/save. Late acknowledgements retain newer input and keyboard focus. A retained unacknowledged draft is sent again only through an explicit later preview, after a successful read refresh. Preview/save double clicks deduplicate the pending action. Save freezes the editor and shows request progress, never saved success from a click.
- Version conflict shows the original expected revision/raw and actual current row. Bound conflict is labelled separately. Unknown permits original lookup and navigation, blocks cancel/new edit/draft/save, and cannot be replaced by another recovery session.
- `unavailable / preview_unavailable` is host-declared pre-dispatch: edit/preview/cancel stay available, lookup is disabled. `unknown / lookup_unavailable` keeps original lookup only. Transport failures retain the original projection/raw, require refresh/manual lookup, and never retry writes automatically. A successful explicitly selected session read clears the prior transport uncertainty.
- Current saved value, raw draft, Rust preview, and original historical receipt render separately with textContent/value. Saved requires a structurally complete host receipt, including matching editor identity; this is defensive presentation checking, not independent receipt authority.
- Native Undo/Redo retains up to 256 exact raw snapshots per editor intent and restores a known original buffer matching the browser history display. If native history extends beyond retained exact snapshots, the page restores the prior raw buffer, shows a local limitation and sends no draft; history is not persisted across reload.
- Cancel first shows the unsaved buffer warning; confirm sends cancel only. Confirmation is bound to the original editor and rechecks the current host phase before dispatch; stale confirmations close when saving/unknown or local uncertainty blocks cancellation. Restoring a lost-tab reference explicitly selects an existing host session and reads it, never creates an intent. Existing editors block restoration of a different session.
- Native labels, focus outlines, status text, a skip link, normal document-flow buttons and rem-based wrapping support keyboard and 200% text. An unchanged live status is not repeatedly announced. Runtime screen-reader/TalkBack/Android/Electron evidence remains NOT_RUN.

Actual host/P07/SQLite browser flow verification is the separate post-combination, non-author integration gate.
