# Explicit bounded presentation lifecycle

Base Reader source: `2e71384e808ecbe5bb010d05e87094e33e9cd3fd` (report8d7323aa).
Read FFI `466424b13400c3f88b0cfec815ce3450c41b3cff` request: existing transport
removes mapping at EOF and marks session_active=false. Core retention alone is
not Android/PFD support. This owner changes only documents modules/tests/docs;
FFI/lib/Android and engine integration remain their original owners.

## Additive DocumentReaderHost API

- `open_presentation(&DocumentAccess) -> DocumentPresentationInfo`: requires
  actual Render permission; single active presentation selection per host.
  Explicitly closes prior presentation selections before opening the exact new
  reference. Never substitutes latest, silently issues/renews grants or adopts
  another scope/generation. Legacy transport sessions retain their old behavior.
- `read_presentation_chunk(&PresentationTicket, max_bytes)`: authenticated,
  bounded sequential source delivery; EOF retains the same pin, snapshot, exact
  authority and session. No reopen or duplicated native snapshot at EOF.
- `check_presentation(&PresentationTicket) -> PresentationStatus`: cheap current
  grant/head/pin/stamp validation with precise remaining lifetime projection;
  does not touch idle time or extend absolute/grant expiry. Phase Ready means
  full raw bytes delivered, not parser/renderer success. Host may display only
  Ready after this check and before its returned deadline.
- `advance_presentation_frame(&PresentationTicket) -> PresentationStatus`:
  explicit user page/view change, requires Ready, increments a native callback
  generation and updates idle activity while keeping original absolute and grant
  deadlines. All prior callback tickets become stale; same snapshot/pin reused.
- `close_presentation(&PresentationTicket)`: idempotent after removal; a stale
  generation cannot close a newer frame. Exact ticket/root source are immutable.
- `take_presentation_invalidations()`: bounded terminal notifications for Host
  cache/PFD cleanup. Overflow or cleanup poisoning requests clear-all. Cleanup
  failure retains native resources/budget solely for explicit cleanup retry.

PresentationTicket is cloned/serialized only, not constructible from model JSON.
It freezes session ID, exact DocumentRef, original AuthorityBinding and frame
generation. FFI stores the real native ticket and compares every incoming callback
ID/generation against it. It must not fetch the newest ticket on behalf of a stale
callback. Page indices remain actual renderer facts, not invented core coordinates.

The existing 8-session / 64-MiB snapshot / 30-MiB source limits remain. Presentation
uses the original15s idle /30s absolute deadlines and actual earlier grant expiry.
Refresh/check never renews them. Explicit fresh host authorization plus a new
selection is required after expiry; no automatic source reopen is authorized.

## Host execution contract

Status includes valid_for_ms and check_after_ms<=1000, bounded by original idle,
absolute and persisted grant deadlines. Host checks before rendering and again
before an async result is shown, schedules the next check/expiry timer, and clears
old images/PFD/private cache on any denial, terminal event, scope change or close.
Anchor the returned lifetime to the Host request-start monotonic timestamp, not
response receipt, so queue/FFI latency cannot extend it. Ignore stale response
generations; never replace a stale callback's ticket with the current one.
Core cannot retract bytes/PFDs already handed to Android; this is a cooperative
trusted-host lease, not an OS revocation sandbox or an instantaneous push service.

Legacy read_chunk, is_current and close reject presentation sessions. Explicit
ticket methods enforce generation; internal expiry/selection maintenance uses a
private cleanup method. close_all remains trusted administrative logout/owner
cleanup, never an arbitrary async page callback endpoint.

FFI must add explicit mode: existing document_bridge.rs EOF mapping deletion and
session_active=!eof apply only to legacy transport. Display EOF keeps native
mapping/ticket active until lifecycle invalidation/close. Host cache payload must
be bounded by exact declared source length (<=30MiB); at most one active selection
is allowed here. PFD/cache bytes are not a new native grant and must not be opened
through arbitrary model paths. No product-ready claim until FFI/Host actually
consumes these methods and passes lifecycle tests.
