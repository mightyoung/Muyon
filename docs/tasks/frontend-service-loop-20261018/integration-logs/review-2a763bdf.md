# Scoped UNKNOWN envelope re-review

Fixed source: `2a763bdf907d0068d4cd5ad2e8492aeb8fbfe9ac`, diff from `93beaf18ff553db0e5d54feabb54c949cfc1a4e3` only. Read-only source/report review; no tests or HTTP/model operations run.

**ADDRESSED.** `AgentChatReadSession.decode` now calls the pure `finishEnvelope` helper after the existing closed JSON/type/identity/cursor validation. The helper accepts `status=unknown, terminal=true` only when eventCount is zero, preserves the precise Rust reason (including DISCLOSURE_UNAVAILABLE), and clears answer/current projection/current receipt while retaining historical originalReceiptIdentity. UNKNOWN does not enter the automatic polling statuses. Nonterminal `events` cannot claim terminal, and UNKNOWN with events is rejected.

The added checks exercise the accepted empty UNKNOWN envelope, precise reason/history retention, rejected UNKNOWN-with-event, and rejected events-as-terminal cases. Reported RED/GREEN logs are retained; this reviewer did not rerun them. No new break was found within these changed files. This closes the nonblocking wire issue from the preceding review without altering its R1–R4 decisions.

New exact-source combined CI/API26 runtime evidence remains pending and is not established by this source review.
