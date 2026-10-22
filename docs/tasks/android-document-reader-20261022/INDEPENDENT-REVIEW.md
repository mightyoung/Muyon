# Independent review — 2026-10-22

Reviewer: independently dispatched nonauthor `reader_review`, read-only inspection of
new reader main/test/androidTest code and PLAN.md. No file changes, installs, real model/
search/network calls, or user files. Core contract compared at fixed f4a8e8d commit.

Initial findings (both High, preserved rather than erased):

1. Foreign-scope annotations were displayed with only an edit lock. Fix: `belongsTo`
   filters workspace, project, document ID and format before rendering; same-document
   older revision remains explicit stale preview. Pure and platform regression tests added.
2. Save locks lived in AnnotationEditor, unmounted during page Loading. Unknown could be
   retried after flipping; pending saves were canceled. Fix: editor draft/submission map
   and CoroutineScope now belong to ReaderContent, survive loading; cancellation is
   UNKNOWN and rapid duplicate tap has synchronous submission-state guard. Platform test
   holds a pending host save, navigates, returns Unknown, flips back, asserts one save call,
   disabled action and unchanged edited draft. Full screen close/process death still needs
   durable host receipt reconciliation as documented in HANDOFF.md.

Re-review response:

> Static re-review clears both prior findings. Scope/document/format filtering hides
> foreign annotations. Hoisted editor state and save scope preserve drafts and Unknown
> locks across page navigation. Synchronous submission guard prevents rapid duplicate
> taps. JSON revisions require decimal strings. Added platform regression test covers
> pending save, navigation, Unknown outcome, preserved draft and foreign-scope hiding.
> No additional definite Kotlin compilation or native API defect identified.

This is STATIC clearance only. Reviewer confirmed compilation/tests remain NOT_RUN;
Android SAX feature/property support and Compose lifecycle assertions need execution.
No successful test/build/renderer screenshot/device acceptance is asserted.
