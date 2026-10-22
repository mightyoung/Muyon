# Implemented private supplier wire v1

This records the actual implementation. CONTRACT.md and the Python oracle retain
the earlier proposal and are not codec conformance certification for this wire.
Old summary protocol fields and its payload exclusions remain unchanged.

## Calls

The existing private `IAgentRuntime` adds flattened typed `submitSupplierRead(epoch,
lease, requestId, text, supplierKey, revision)` and
`supplierReadEvents(epoch, lease, requestId, afterCursor)` returning bounded JSON
Strings. Genuine UniFFI exports equivalent methods on the existing controller.
Cancel uses the existing Inquiry run reference and controller lifecycle.

The Service validates same UID, complete encoded Parcel size and individual field
bounds before invoking native code. New business transactions allow 16KiB request
and 131200 encoded reply bytes (String UTF-16 framing); the old summary transaction
4/8KiB bounds are unchanged. UI and native code independently validate semantic bounds.
No input accepts a filesystem path, SQL, grant, authority snapshot or provider config.

Request ID uses existing safe-ASCII/64-byte validation. Text is nonblank UTF-8 at
most 4096 bytes; selected supplier key/revision are at most 128 bytes. The sole
host-owned supported selection is the explicitly synthetic supplier
`11111111-1111-4111-8111-111111111111`, revision `7`, module `inquiry`, type `supplier`,
object schema1 in a real schema12 SQLite copy. All other business sources/scopes are
unavailable; the UI selection is never a grant.

## Result

Exact envelope keys:

```text
protocol: 1
status: accepted | existing | events | rejected | unknown
reason: bounded safe status/rejection text
request_id: original request ID
run_id: original durable run ID, or null before known admission
admitted_service_epoch: original admitted epoch, or null
events: ordered array, at most 4 events for this read
next_cursor: last delivered cursor
terminal: boolean
synthetic: true
```

An event has exactly `cursor`, `kind`, `payload`. Successful execution returns:

1. `answer_delta`: `{text}`; deterministic local rendering of the selected name.
2. `supplier_projection`: `{supplier:{module_id,type,key,revision,schema_version},name}`.
3. `receipt`: ORIGINAL `{owner,invocation_id,binding_id,identity}` stored by ToolRegistry.
4. `terminal`: `{state:"completed",reason:"none"}`.

This is an ordered cursor batch after a short read settles, not a model token stream.
No model response or automatic natural-language tool selection is implemented.
UI publishes a decoded batch atomically. Completion requires both matching projection
and original receipt; the native side revalidates the durable receipt/task/object
binding and fixed source before replay/disclosure. Names are bounded to 512 UTF-8 bytes.

On a receipt-bearing interruption, independently validated historical receipt metadata
may precede an `outcome_unknown` terminal with no answer/projection. A settled UNKNOWN
without valid events is explicitly terminal and stops polling. Missing evidence
cannot become definite not-started, completed or failed by assumption.

## Recovery and cancel

UI persists request/text/selection binding before its first submission. Restored,
corrupt or lost-transport state keeps UNKNOWN and performs lookup only. Current
connection epoch/lease is distinct from the original run's admitted epoch. Disclosure
loss clears answer/current projection and resets the replay cursor to zero, while
retaining the original historical receipt identity. Reconnection alone cannot restore
disclosure; native receipt/source validation must succeed again.

Before dispatch, cancellation revokes only the matching deferred request, so bootstrap
cannot later send it. After dispatch, cancellation uses the existing control lane and
waits for native settlement; an absent/invalid ACK produces UNKNOWN. Pending bootstrap
and RPC completion are bounded, at most once, and never auto-resubmit.
