# MIG32 / DOC04 / DOC09 interface checkpoint

Base UI: 98baa979223d96094f11a56c3ac6d48f9b84c0eb.
Read-only shared core: f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac.
Design archive: 400e206135690c284c8402521e3135cfb7bfaee8, 2026-10-22 original master plan.
No AGENTS.md or .agents/skills exists in this checkout or either inspected tree.

Ownership: only new product/ui/documents main/test/androidTest directories and this task's docs.
Do not modify shell MainActivity/ChatScreen, host ProductService/ProductChatRuntime,
core lib.rs/documents, build configuration or dependency locks.

1. Test first: pure reader state boundaries, exact decimal revisions, stale/scope annotation
   filtering, edit CAS envelope; bounded real OOXML text extraction; synthetic PDF instrumentation.
2. Implement shared-core projection codecs (exact field names, no authority inferred from metadata).
   Reader snapshot comes from host; local UI state holds page/zoom/draft only.
3. Native PdfRenderer opens host-controlled content URI descriptor per page; close each renderer,
   bound bitmap allocation, perform IO off main, fence returned work by snapshot identity/epoch.
   Host must authorize at open AND before delivery. No retained authority/cache.
4. Local DOCX/PPTX/XLSX ZIP/XML text/cached-value preview; bounded reads, no network/entities,
   no layout fidelity, formulas, macros or embedded content execution.
5. Annotation sidecar previews retain revision-bound raw anchors and author provenance.
   Edit existing body only through host CAS callback; no invented selection coordinates,
   native embedded annotation or PDF text selection. Unknown save outcome blocks retry.
6. Document exact shell wiring contract; independent reviewer; preserve all failures/NOT_RUN;
   push independent branch and verify full remote SHA.

Host API: DocumentReaderScreen(snapshot, host, onClose). Snapshot includes DocumentRef projection,
controlled content URI, host epoch, annotation records. Host callbacks openCurrent, isCurrent and
saveSidecar must bind exact scope/document/revision/epoch to the shared core authority checks.
Save returns Saved / Rejected / Unknown. Only Saved is confirmed; host supplies refreshed snapshot.
No production resolver exists in this patch. Component is callable, not wired into shell.

Toolchain inspected: Java available; kotlinc/Gradle/Android SDK not found. Tests retained and
commands attempted, NOT_RUN is allowed by the explicit task instruction; no red/green claimed.
