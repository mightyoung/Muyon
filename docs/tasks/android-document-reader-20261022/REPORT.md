# MIG32 / DOC04 / DOC09 source delivery

2026-10-22 UTC. Independent branch `task/android-document-reader-20261022`, based on
UI composition `98baa979223d96094f11a56c3ac6d48f9b84c0eb`.
Shared core read at `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac`; design master read from
archive `400e206135690c284c8402521e3135cfb7bfaee8`.

Delivered actual Compose/native components in new `product/ui/documents`:

- Native PdfRenderer page rendering with bounded bitmap, page flipping, numeric page
  location, 100–300% zoom/scroll, per-render FD closure and host delivery checks.
- Concrete bounded DOCX/PPTX/XLSX ZIP/SAX text previews, cell refs/shared strings/formula
  cached-value labels, explicit unsupported layout/graphics/calculation/embedded payloads.
- Shared core JSON identity/revision/author/body/anchor projections, same scoped document
  filtering and stale revision preview. Sidecar edit uses expected annotation revision,
  unchanged raw anchor and trusted host callback, with honest Saved/Rejected/Unknown UI.
- Drafts, pending saves and Unknown locks survive PDF page reload. No embedded annotation,
  text selection, new fake selection geometry, file writes, competing store or fake success.
- Pure logic and real synthetic PDF/platform lifecycle regression test source; exact shell/
  host callback contract in HANDOFF.md. Shell/host/core owner integration remains their work.

Validation: all four execution attempts in evidence/06-final-checks.json are NOT_RUN
(exit2), because existing Kotlin compiler/Gradle/SDK/device are unavailable. Tests were
written before corresponding production changes, but no successful red/green is claimed.
Android compilation, native rendering execution, SAX Android support, device UI/accessibility
acceptance and integration against core persistence must be run in the authorized verifier.
`git diff --cached --check` passed before delivery. This is source delivery, not APK acceptance.

Independent reviewer found two High defects (cross-scope preview, lost Unknown lock on
navigation). Both were corrected and statically re-reviewed; initial findings, regression
sources, limits and NOT_RUN are preserved in INDEPENDENT-REVIEW.md and evidence.

Required remaining integration: host owner must provide actual permission/safety-bound FD
resolution and durable sidecar intent/receipt reconciliation; shell owner wires the callable
component. No edits to MainActivity/ChatScreen/ProductService/ProductChatRuntime, Rust
lib.rs/documents, Gradle dependencies, main/develop, credentials, paid configuration or
security permissions. No third-party HOLD engine, real model/search request, original two
unknown requests/reservation or real user files touched. No installs, force pushes, deletes
or deployment. Synthetic fixtures are created only by retained platform tests, not executed here.
