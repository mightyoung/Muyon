# Additive presentation bridge — interface first

Core report3ff95947337c85f15ef1f9edcf5d47ad49e14999/sourceee184fc1dd90faf2c3cdd48d735f47274de6d418.
Owned files remain FFI/lib.rs, document_bridge.rs/tests, task docs. Core/lib.rs,
documents, generated bindings, Service/Runtime/Android remain their owners.

Old five draft APIs and 13 raw/evidence methods retain signatures. Raw mode EOF
still removes mapping/session_active=false. Presentation is an explicit separate
mode requiring actual Render on exact existing DocumentAccess. No grants issued.

New UniFFI records:
- DocumentPresentationOpenRequest { access:DocumentAccessRequest, selection_id:String }.
  Token comes only from the native begin-selection registry, not a caller's counter.
- DocumentPresentationUseRequest { scope:DocumentReaderScope,
  presentation_id:String, frame_generation:String }. Canonical unsigned decimal
  generation copied from the ORIGINAL request/callback; never upgraded to latest.
- DocumentPresentationChunkResult { offset:String, bytes:Vec<u8>, eof:bool,
  session_active:bool, frame_generation:String }. Presentation EOF keeps same
  native ticket/pin/snapshot/mapping, session_active=true. This is not render success.

Additive native methods:
```
document_presentation_begin_selection(scope:DocumentReaderScope) -> String
document_presentation_open(request:DocumentPresentationOpenRequest) -> String
document_presentation_chunk(request:DocumentPresentationUseRequest,max_bytes:u32)
  -> DocumentPresentationChunkResult
document_presentation_check(request:DocumentPresentationUseRequest) -> String
document_presentation_advance_frame(request:DocumentPresentationUseRequest) -> String
document_presentation_close(request:DocumentPresentationUseRequest) -> ()
document_presentation_take_invalidations() -> String
```

Open/check/advance schema1: status=current, mode=presentation, presentation_id,
frame_generation, document=exact DocumentRef, metadata=actual DocumentMetadata on
open (null otherwise), phase=loading|ready, valid_for_ms and check_after_ms numeric
bounded actual core deadlines, annotation_editing=false,safety_status=not_assessed.
Raw native ticket/grant/pin ID is never serialized across FFI. Core ticket stays
in native registry; incoming scope, ID and generation must match it exactly.
Loading cannot display. Ready means bytes transferred, not PDF parsed/rendered.
A pre-EOF advance fails; successful explicit advance replaces stored ticket with
actual native next generation. Older check/chunk/advance/close callbacks fail,
including old raw APIs trying to use a presentation ID.

After every native document operation, collect actual core terminal events even
on failure. Host must drain take_invalidations AFTER success AND errors. It is a
trusted Service administrative call, not a client/Messenger/model route: returns
schema1/clear_all/invalidated[{scope,presentation_id,frame_generation,cleanup_pending}]
so Service can route only to matching active client scope. No historical listing,
document metadata, grant or cross-client API. Queue<=8; overflow/unknown mapping/
core poison asks clear_all. Service clears all private renderer outputs on it.
Owner release and shutdown use stored real ticket for cleanup, never a stale async
callback. Closed/replaced mappings are removed when native terminal events arrive.

Native cap<=16MiB/source; core aggregate64MiB is payload, not RSS. Cheap core
check_presentation validates grant/head/pin/stamp using authenticated snapshot;
no full-file is_current per chunk/check. Raw full-capacity sync dispatches each
entry to its proper mode. Only one presentation active per core host; selecting
another closes old source even when same document. No implicit regrant/reopen.

Host: derive authenticated current scope and previously issued exact access first;
anchor valid_for_ms/check_after_ms to REQUEST START monotonic time. Check before
render and before showing async results with that original frame generation;
refuse expired/inflight stale responses. DOCUMENT_PRESENTATION_STALE and scope/
mode errors from an OLD callback discard only that callback/its old resources;
never clear the current newer frame. A current-ticket denial, corresponding
terminal event or clear_all invalidates the current display. Poll no later than
check_after_ms<=1000; clear current PFD/bitmap/cache on its denial, timeout,
terminal event, scope/generation change,
background or close. Checking never renews original15s idle/30s absolute/grant.
No native timer/push into Kotlin is fabricated. Android owner still supplies real
seekable READ_ONLY PFD/cache bounded by declared length, actual renderer facts,
transport/principal mapping and lifecycle tests. No annotation save or product
reader acceptance is implied. B alone generates actual bindings.

## Open fence before core replacement

Core open_presentation closes old selection BEFORE it validates new access. Host
must serialize its actual live scope/user-selection event, call begin_selection
synchronously at that event (before async document lookup), and hold its returned
native opaque selection_id with the ORIGINAL scope. Native retains only one
pending token for<=15s, replaces it only on explicit begin, and consumes it ONCE
before invoking core. Late A open is rejected before core if B was registered,
including same-scope A/B and cross-scope cases; duplicate completed open cannot
reopen/close a newer selection. No caller-supplied integer/generation proves current.
Host must not call begin upon a delayed callback or replay old selection events:
its authenticated current activity/pane check is required before native begin.
Begin itself neither creates authority nor closes an existing core presentation.
Host hides old UI on explicit selection change and disposes its old resources.

If core terminates at a generation not yet delivered to Host (failed frame
advance), notification generation mismatch sets clear_all. Any global cleanup
block, including the separate evidence adapter, also sets clear_all. Ordinary
old-generation callbacks rejected locally generate no terminal event/clear_all.

The administrative invalidation queue is ephemeral/cooperative, not durable push.
If its transport fails or a drain response is lost, trusted Service must treat
that uncertainty as clear_all and dispose actual renderer/cache/PFD state. It may
not treat a successful Rust byte return as proof that Android disposal occurred.
