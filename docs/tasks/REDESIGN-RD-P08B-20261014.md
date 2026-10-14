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

## Initial 818cf60 verification

Initial source command `node --test experiments/redesign/device-deferred/operable-supplier-flow/desktop/tests/browser.test.mjs`: **25 tests, 25 pass, 0 fail**. Actual Chromium DOM/events with explicitly mocked host projections; no P07/SQLite business effect claim. Runtime/console exception and foreign HTTP request checks run after every case. `node --check desktop/app.mjs` and `git diff --check` pass (run with repository-relative full path).

The first run had an about:blank sessionStorage harness error; it was corrected without production code. The subsequent page-absent RED run had 12 failures; this proves missing page coverage, not 12 independent loaded-DOM behavior regressions. Subsequent loaded-DOM RED→GREEN showed retained draft/recovery guards, desktop 200% overflow (scroll width 1744 at viewport 1400), CR/CRLF loss, in-flight raw freeze, pre-dispatch lookup guard, binding-conflict text, saving progress and redundant live-status mutations. All first failures/logs retained outside Git.

Two final inverse mutations were executed against loaded DOM: opening cancel for unknown caused `false !== true`; trimming raw caused exact UTF16 action mismatch. Each exited 1. Original app.mjs restored byte-for-byte in finally, followed by the fresh 25/25 full suite above.

Browser plugin unavailable; Playwright module unavailable (`ERR_MODULE_NOT_FOUND`). Existing Chromium CDP used, no install. Keyboard test drives actual Enter/Ctrl+A/Input.insertText. Clipboard test uses Chromium clipboard.writeText plus actual Ctrl+V/paste event with CRLF; external OS/app clipboard behavior is not claimed.

Raw evidence: `/tmp/rd-p08-workflow-20261014/desktop-*.log`. Screenshots: `/tmp/rd-p08-workflow-20261014/desktop-evidence-final/{mock-desktop,mock-desktop-200,mock-mobile-200}.png`. They show mocked host data, not actual database results. The screenshot series was visually inspected against existing F13: handbook three-column body wins over old PNG placement; preview/receipt stack inside right detail; unimplemented modes replaced by honest experiment capability text.

## Remaining gates

Post-combination actual loopback host/P07/SQLite flow, physical effect counts, restart lookup and two-window CAS conflict are reserved for fresh non-author integration QA. No duplicate actual-DB flow run by this writer. Real Android/Compose/Electron, screen-reader/TalkBack, OS clipboard variants, production M03/grants and migration remain NOT_RUN/blocked_contract. This owned slice awaits non-author review/integration; it does not assert full product acceptance.


## Fix round 1 — independent D1/D2 findings

Independent immutable review of `818cf60` passed the original 25 tests but found two additional native Chromium failures: a previously opened discard confirmation could send cancel after unknown, and native Undo reconstructed original CRLF as LF. The original review/probe/failure logs remain unchanged.

Cancellation now uses one current projection/local-uncertainty eligibility check for the main button, confirmation button, click handler and queued dispatch. Confirmation carries the original intent identity and becomes hidden/disabled when the current phase no longer permits cancellation. Exact host pre-dispatch `unavailable/preview_unavailable` remains cancellable; saving/unknown are blocked.

Raw history stores bounded exact editor-buffer snapshots (256 states). Native Undo/Redo uses retained exact provenance rather than synthesizing LF-only text from the textarea display. When the original history cannot be matched, the prior raw is restored, a local limitation is visible and no draft is sent. This is presentation history only; no name rules, business binding, durable replay or host authority were added.

Three added owned regressions preserve the independent assertion expectations and cover stale confirmation, native Undo and native Redo with a lone surrogate. First loaded-DOM RED was 0/3 pass, with actual cancel request and CRLF→LF failures. Fresh full suite after both targeted inverse mutations and exact-byte restoration: **28 tests, 28 pass, 0 fail**. Syntax and diff checks pass. app.mjs SHA256: `8295f703f150588a17ee166682b1fc3bde3ede8dffd61a2b9238612cda5c0676`.

Independent probe source SHA256 remains `8040ae2249caa24ade9d46b44637f025916e0ef06cf87f5a28032213c773859f`. Parent authorized an external copy changing only the hard-coded desktop asset target constant to an environment parameter. Assertions/fixtures remain unchanged; the parameterized copy whole-file hash differs (`ef9e13108936a87350a855a04d1965756fb5dfc1e5768d868533b70a1e747dda`). Target-only unified diff and both source files are preserved. The copy against fixed assets passes **2/2 independent probes**; this writer rerun is not the pending non-author scoped re-review.

Evidence outside Git: `/tmp/rd-p08-workflow-20261014/desktop-fixround1-{red,green-regressions,full-green,independent-green,final-green}.log`, `desktop-fixround1-mutation-{discard-phase,undo-provenance}.log`, and `desktop-fixround1-independent-target-only.diff`. The original review remains `/workspace/reports/rd-p08-flow-20261014/desktop-review-818cf60.md`. Actual combined P07/SQLite QA remains the parent's separate gate.
