# RD-P08B desktop and mobile browser projection

Owned branch: `task/rd-p08-desktop-20261014`, base `25bfb3180111b156b8ba567fd14c7cca101d3e13`. Only new `operable-supplier-flow/desktop/**` and this task document. No host/Android/product/core/schema/CI edits; no push, merge, dependencies, devices, models or deployment.

## Delivery

| Requirement | Evidence |
| --- | --- |
| Existing v1.3.2 D01.1 fidelity | Page handbook D01.1/F13 and Android addendum read; existing F13 PNG inspected. Search, center stable-ID list, right current/raw editor/preview/receipt; mobile list → detail → full editor. |
| Host truth only | app.mjs sends select/edit/draft/preview/save/cancel/lookup and GET state; no normalization/CAS/binding/receipt-verification implementation. Exact csrf/session contract coordinated with host writer. |
| Raw identity and recovery | Serialized exact UTF16 draft; CR/CRLF display offsets preserve originals through actual native insertion/deletion and clipboard events; late replies preserve newer input/focus. SessionStorage contains only host session reference. Explicit recovery is read-only and blocked over an existing editor. |
| Honest results | Current row, draft, preview, historical receipt separate; saving request progress; saved requires host receipt shape/identity. Version vs binding conflict distinct. Unknown permits lookup only and cannot silently create a new intent. |
| Accessibility/responsiveness | Semantic labels, keyboard Enter/Ctrl+A route, stable focus, unchanged status announcement suppression, mobile 390×844, desktop 1400×1000 and 200% root text reflow. Buttons remain below input in normal flow. |
| Capability limits | Visible synthetic experiment and M03 blocked_contract; P07 preview not formal grant; no fake authorization modes. |

## Verification

Fresh final source command `node --test experiments/redesign/device-deferred/operable-supplier-flow/desktop/tests/browser.test.mjs`: **25 tests, 25 pass, 0 fail**. Actual Chromium DOM/events with explicitly mocked host projections; no P07/SQLite business effect claim. Runtime/console exception and foreign HTTP request checks run after every case. `node --check desktop/app.mjs` and `git diff --check` pass (run with repository-relative full path).

The first run had an about:blank sessionStorage harness error; it was corrected without production code. The subsequent page-absent RED run had 12 failures; this proves missing page coverage, not 12 independent loaded-DOM behavior regressions. Subsequent loaded-DOM RED→GREEN showed retained draft/recovery guards, desktop 200% overflow (scroll width 1744 at viewport 1400), CR/CRLF loss, in-flight raw freeze, pre-dispatch lookup guard, binding-conflict text, saving progress and redundant live-status mutations. All first failures/logs retained outside Git.

Two final inverse mutations were executed against loaded DOM: opening cancel for unknown caused `false !== true`; trimming raw caused exact UTF16 action mismatch. Each exited 1. Original app.mjs restored byte-for-byte in finally, followed by the fresh 25/25 full suite above.

Browser plugin unavailable; Playwright module unavailable (`ERR_MODULE_NOT_FOUND`). Existing Chromium CDP used, no install. Keyboard test drives actual Enter/Ctrl+A/Input.insertText. Clipboard test uses Chromium clipboard.writeText plus actual Ctrl+V/paste event with CRLF; external OS/app clipboard behavior is not claimed.

Raw evidence: `/tmp/rd-p08-workflow-20261014/desktop-*.log`. Screenshots: `/tmp/rd-p08-workflow-20261014/desktop-evidence-final/{mock-desktop,mock-desktop-200,mock-mobile-200}.png`. They show mocked host data, not actual database results. The screenshot series was visually inspected against existing F13: handbook three-column body wins over old PNG placement; preview/receipt stack inside right detail; unimplemented modes replaced by honest experiment capability text.

## Remaining gates

Post-combination actual loopback host/P07/SQLite flow, physical effect counts, restart lookup and two-window CAS conflict are reserved for fresh non-author integration QA. No duplicate actual-DB flow run by this writer. Real Android/Compose/Electron, screen-reader/TalkBack, OS clipboard variants, production M03/grants and migration remain NOT_RUN/blocked_contract. This owned slice awaits non-author review/integration; it does not assert full product acceptance.
