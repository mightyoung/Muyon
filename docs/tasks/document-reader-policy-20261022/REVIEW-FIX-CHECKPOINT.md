# Independent review follow-up (A/B/C only)

Review source: 9466cb330f8505c5e18f6ed930bf7e1c3b552128. Four static Important findings, not executed RED probes in this environment. Regression source precedes production fix at 22b7c1c1. The six added wired tests exercise old ticket adoption, late A versus current B, explicit close and close-all after natural cleanup, lost-pin failure followed by expiry, and unrelated-document generation observation.

Session captures the native policy owner/scope-key/selection epoch when opened. A genuine selection change closes every preceding presentation, including unrooted tickets, before publishing the new binding. Begin checks the captured binding before insertion and again after all writes. Exact duplicate outcomes remain historical and cannot create a new root.

Explicit close of an exactly retained closed ticket fences its durable root. Close-all also visits retained closed tickets. Non-natural validation failure now fences immediately. Natural lease/grant expiry is classified at cleanup time by real active exact grant, current metadata/source, backing stamp and reader pin; a future expiry cannot reclassify an earlier failure. Observe checks exact document and owner epoch before exposing generation replacement.

Commands: cargo test -p muyon-core reading_policy_kernel_tests --offline (before and after): exit 127, cargo unavailable, NOT_RUN. Logs in evidence/review-regressions-{before,after}.log. python3 evidence/schema-smoke.py: exit 0, actual SQL DDL and triggers only; not Rust or authorization behavior validation. Rustfmt NOT_RUN. No executed RED/GREEN is claimed. Full D/E/F/G and approved explicit-selection initial admission remain pending and absent, not stubbed. This checkpoint is HOLD pending independent compilation/review.
