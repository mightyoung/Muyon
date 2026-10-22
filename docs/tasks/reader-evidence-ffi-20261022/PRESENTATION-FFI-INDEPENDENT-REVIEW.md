# Independent presentation FFI review

Read-only reviewer /root/independent_provider_review,2026-10-22. Source reviewed
in this isolated task branch; no reviewer edits or compilation. Core actual
verification remains its separate immutable report, not FFI evidence.

Original findings retained:
1. Important: core advance may increment N->N+1 then fail final check, emitting
   terminal N+1 before Host received it. Merely forwarding N+1 would miss Host's N
   renderer if it matched exact generation and the failed response was delayed.
2. Medium: StoreEvidence cleanup blocks all bridge operations but its independent
   adapter produces no DocumentReaderHost event. Its failure could leave drain
   clear_all=false although the current presentation is globally unusable.

Fixes: terminal/stored-ticket generation mismatch sets clear_all; every reader or
evidence global Cleanup block sets clear_all. Actual native ID is translated while
its mapping exists, then removed. Two projection tests use a genuine synthetic
store/ticket and inject those event/error values. They do not claim actual fault
execution inside core. Ordinary stale callback rejects locally before native
call, emits no terminal/clear_all and cannot close a current newer frame.

Parent-requested additional late-open fence: native one-current opaque selection
token, bound to exact scope,15s, consumed before any core replacement. Late/replay
opens reject without replacing current. Host must register only at actual
synchronous authenticated selection, never at late callback. Same/cross-scope
and completed-replay test sources are included.

Final review: both findings repaired. No outstanding Important or apparent
compiler/borrow issue on static review.21 API tests plus2 simulated projection
tests confirmed. Owned diff whitespace check PASS. Rust compilation/tests/fmt/
clippy, actual binding generation and Host/PFD/Android execution NOT_RUN here.
