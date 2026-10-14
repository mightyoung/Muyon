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

## Fix round 2 — actual-combination mobile recovery panel

Fresh combined actual-browser QA on frozen `8f71b3a` found that two durable sessions leave a recovery button, making the ID-specific `.search-panel:has(#recoverable-sessions button){display:block}` rule override mobile detail/editor hiding. The original actual screenshot and reproduction JSON are preserved outside Git; this writer did not rerun actual P07/SQLite effects.

The CSS-only source fix removes that redundant selector. The mobile base rule still shows directory/recovery on the list, the existing detail/editor rules now hide it, and desktop rules remain unchanged. At CSS-only commit `c5fe347`, app.mjs SHA256 remained `8295f703f150588a17ee166682b1fc3bde3ede8dffd61a2b9238612cda5c0676` byte-for-byte; the subsequent null-render guard below intentionally changes that hash while leaving unknown/receipt/raw/history/action logic untouched.

One added mocked-host Chromium regression includes two session metadata entries and a rendered recovery button. At 390×844/200% text, it asserts directory hidden in detail and full editor, shown in list, no horizontal overflow or input/action overlap; at desktop it asserts directory and recovery remain visible. Initial loaded-DOM RED is `block !== none`. Fresh full suite: **29/29 pass**, including all prior 28 cases. A CSS-only inverse restoring the pre-fix stylesheet exits 1; fixed bytes restored in finally, followed by the fresh full 29/29 GREEN. Diff checks pass.

Logs: `/tmp/rd-p08-workflow-20261014/desktop-fixround2-{red,green,css-inverse,final-green}.log`. Preserved actual evidence: `/workspace/reports/rd-p08-flow-20261014/actual-qa/06-mobile-200-actual.png` SHA256 `62b9c0c95a09d9320c944752704342690b183b0c146b4a65a00b1bc01af207f2`; `mobile-panel-repro.json` SHA256 `ae7e50d1a06549b95b453b5ff84816916b817e6dfad76cc531ab0156dc8c84b9`. Fixed styles.css SHA256 `e644bc3672bcb31b74257d11ccb8ffc0486aeea25a18a5b5004596818635bdda`. Parent same-reviewer actual-combination scoped re-review remains the next gate.


## Same-wave supplemental fix — healthy no-selection render

Independent actual-combination fresh-state probe on frozen `8f71b3a` found a valid HTTP200/available projection with `selected:null, editor:null` producing false transport uncertainty. Optional supplier accesses compared `undefined===undefined`, selecting the branch that dereferenced null editor.current. One rendering line now requires an actual editor and selection before reading editor.current; no domain or transport semantics change.

A new valid fresh-session fixture asserts empty transport warning, available populated list, explicit selection prompt, disabled edit, hidden editor, idle status and zero actions. Initial RED reproduces the exact false uncertainty text. Fresh full suite after a detected null-guard inverse (exit1), finally byte-restoration and syntax check: **30/30 PASS**. Fixed app.mjs SHA256 is now `78f99148577b2ed4e227120b207a42cf58110e954bcf1ba69a19da2ec06b828a`, intentionally differing from the CSS-only commit's JS hash. CSS `c5fe347` fix remains unchanged at `e644bc3672bcb31b74257d11ccb8ffc0486aeea25a18a5b5004596818635bdda`.

First actual evidence untouched: `fresh-state-probe.log` SHA256 `3bdc865f4d85831f7fb19b79a1bdb96982939e234a413e444b45e9b8cb09ddd7`, `fresh-state-repro.json` SHA256 `d02cd950b052e78f5d1bde91ad85156805cdcdffb731dddbbe3d977e96238381` under `/workspace/reports/rd-p08-flow-20261014/actual-qa/`. Owned mocked logs under `/tmp/rd-p08-workflow-20261014/desktop-fixround3-null-{red,green,inverse,final-green}.log`. Parent will combine this supplemental source commit with `c5fe347` for one whole-wave scoped actual re-review; this writer did not duplicate actual database QA.
