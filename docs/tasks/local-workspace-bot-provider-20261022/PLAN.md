# Local workspace Bot draft provider

Dependencies pinned: UI 98baa979223d96094f11a56c3ac6d48f9b84c0eb; document core
f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac; host plan/contracts read from
6d61baf709f6d5a1e411ec6f24a19f357dc9a8bc. The local-workspace addendum supersedes
old account-blocked framing. No legacy files or execution ledgers are imported.

Files owned: new crates/muyon-core/src/bot_drafts.rs, its tests;
crates/muyon-android-ffi/src/lib.rs local_draft_* methods only; this task's docs.
Core lib.rs export stays with core owner (exact patch: add `pub mod bot_drafts;`).
No Kotlin, documents, MainActivity, ChatScreen, ProductService or Runtime changes.
The task's `muyon-ffi` path resolves to the actual `muyon-android-ffi` crate.

Interface: four free functions resolve/read/save/lookup_save, taking &BusinessStore
and trusted conversation/project plus explicit binding. FFI publishes
local_draft_resolve/read/save/lookup_save, bounded JSON success or stable typed
ProductError code; decimal revisions are canonical signed-Long-range strings.
Returned owner_kind=local_workspace, schema=1, lifecycle=editing_only.

1. Add behavioral Rust tests first; retain attempted execution evidence.
2. Implement strict dedicated schema on BusinessStore connection; BEGIN IMMEDIATE
   atomically creates registry or commits archive/CAS/original receipt. Enforce
   scope/project/lifecycle on every call, exact original attempt idempotency,
   bounded canonical MYBD envelope and SHA256 corruption detection.
3. Add only private native bridge methods, mutex serialized. No dispatcher tools.
4. Run available meaningful checks, independent review, repair findings, record
   FAILED/NOT_RUN explicitly; push task branch and verify remote full SHA.

Capacity: 128 drafts/workspace; 8 MiB encoded archive hex; 4096 retained receipts.
Unknown save errors require lookup of the SAME attempt, never automatic resave.
A receipt acknowledges only exported_memory_revision; host must compare its live
reducer/scope/editor revision before displaying saved. Read never marks edits saved.
Checksums do not authenticate data or prevent full database rollback.

Environment: repository snapshot contains no AGENTS.md, .agents/skills or dated
2026-10-22 design master document. Do not infer absent instructions. No Rust tools
found on initial PATH; no unknown software will be installed.
