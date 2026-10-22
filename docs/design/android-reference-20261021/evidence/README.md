# Retained intermediate evidence

Only `../muse-final/` describes the final accepted candidate. This folder preserves
intermediate failures and screenshots; passing intermediate tests do not establish
final source identity or visual correctness.

- `0c23421b-UI-FAIL.log`: closed drawer duplicated visible navigation semantics.
- `62c51424-UI-PRE-IME-FIX.log` and `pre-ime-fix-62c51424/`: assertions passed
  before the keyboard had fully expanded; screenshots exposed hidden input.
- `1643de61-FONT2-PRE-ADAPT.log` / font and edge folders: intermediate large-text
  and inset observations, before the Muse correction.
- `093e8708-WIDE-*.log`: requested window size did not meet840dp because API26
  clamps the small device framebuffer. `rejected-stale-wide-capture/` contains
  copied previous frames and is explicitly excluded from accepted screenshots.
- `f2da3cef-ORIGIN-ASSERT-FAIL.log`: original identity was correct; a new test used
  exact-text matching where a substring assertion was intended. The preceding
  exact full-origin assertion was retained.
- `pre-muse-f2da3cef/`: provisional captures, including a dialog dismissal frame.
- `fead50a2-BUILD-FAIL.log`: missing TextButton import, fixed before delivery.
- `4b286ee2-*.log` / `pre-foreground-4b286ee2/`: behavior tests passed, but wide
  screenshot inspection exposed black inherited text in the dark sidebar. The
  final theme root supplies its explicit foreground color.

No failed run is included in the final PASS manifest, and raw logs are preserved.
