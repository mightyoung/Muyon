# Private frontend/service loop: review proposal v1

Status: proposed, not an implemented Android ABI. Base inventory is fixed at
`10773ba4d7849ee745c2859063ac8a45194687a3`; UI inspected separately at
`d3572ea5e74996f468952f16b095775f59ea37b3`. Existing summary protocol remains unchanged.
The executable Python oracle in `experiments/redesign/frontend-service-loop-lab/`
tests this proposal only. It invokes no Binder, native Agent, business store or model.

## First supported operation

Read the selected supplier's identity, name and revision through the existing Rust
Agent and trusted registered Catalog read. Preserve the current Compose layout,
four-menu/Muse/puppy assets and local Save behavior. Send is a distinct action.
No write tools, generic SQL, file access or arbitrary plugin execution are added.
Chat text is untrusted content, never authority or an instruction to bypass scope.

## Separate private interface

Add typed `submitRead`, `readEvents`, `lookupRead` and `cancelRead` operations to
the same private Service/controller ownership domain. Exact generated Kotlin/Rust
signatures and parcel schema must be frozen together by the sole integrator.
Do not reuse summary reason/build/receipt fields to carry answer text.
Keep the existing liveness Binder as a death token, not a UI callback.
Use bounded cursor polling on the existing background RPC lane for the first stream;
never block the UI thread on an Agent run. No second controller or driver.

Submission proposal:

| Field | Limit / meaning |
| --- | --- |
| protocol | Integer 1 for the new private contract; independently versioned from old summaries |
| epoch, lease | Existing Service-issued client identity; validate against the current Service |
| request_id | Stable client-generated ID, persisted before the first submit |
| text | Nonblank UTF-8, at most 4096 bytes; opaque prompt content |
| selected | Exactly module_id, type, key, revision, schema_version |
| module_id, type | `inquiry`, `supplier` for this initial slice |
| schema_version | Integer 1 (object reference schema); distinct from SQLite database schema12 |
| key, revision | Nonempty identifiers, at most 128 UTF-8 bytes each |

No arbitrary maps/extensions at the production boundary. Reject unknown parcel tags
and JSON fields; UI cannot provide paths, SQL, grants, authority snapshots,
credentials, endpoint configuration or `approved=true`. A typed selection is an
untrusted requested object, not proof of permission. Host-owned scope/policy must
resolve it and recheck at physical read and result disclosure. Missing proof fails
closed with a visible reason. Do not infer read rights from model/write/outbound
grants or `module_grants`.

Epoch/lease and request/run format must ultimately reuse existing identity validators.
The oracle's bounded IDs are illustrative and do not replace those validators.
For a durable admitted request, identical ID+payload returns its original run;
changed text, selection or revision under that ID is `REQUEST_CONFLICT`.
Persist the semantic payload binding before executing a read. Transport lease is
not part of that payload binding. Limit one active read per existing lifecycle policy.

## Event envelope and bounds

Every event binds `(admitted_service_epoch, request_id, run_id, cursor)` and the
selected object. Connection epoch/lease authorizes the readEvents call; the admitted
epoch stays unchanged across service reconnection. A new connection does not rewrite
historical run identity. A mismatched request/run/object/revision cannot update UI.

Proposed limits for production review: 32 events per reply, 64 KiB encoded reply,
1024 UTF-8 bytes per answer delta, 32 KiB cumulative answer, 512 bytes supplier name,
256 bytes opaque receipt ID. Service enforces limits before IPC allocation; client
also bounds decoding and accumulation. No unlimited in-memory event log. Persist
bounded resumable events or return explicit `REPLAY_UNAVAILABLE` plus a validated
lookup snapshot; never silently skip missing events or restart a run.

| Event | Payload / UI behavior |
| --- | --- |
| answer_delta | Ordered, reviewed/redacted display text; no raw source facts |
| supplier_projection | Selected identity, name, read revision; current business display |
| receipt | ORIGINAL durable opaque ID and recorded outcome, copied without regeneration |
| terminal | completed, cancelled, failed, budget_exhausted, outcome_unknown plus closed reason |

Cursor begins at 1 and advances contiguously. Exact duplicate is idempotent;
same cursor/different payload is conflict. A gap requires reconciliation, never
append out of order. After terminal, reject all new events; exact replay is allowed.
Receipt/projection precede a successful terminal. Completed requires recorded-success
receipt and matching projection; a delta alone cannot mean success. Multiple
different receipt identities for one run are a protocol conflict, not an overwrite.

Historical receipt and current projection have distinct storage/display roles.
Authority revocation, object revision change or missing current authority clears or
hides the current business projection and displayed answer. Reconnection alone does
not restore disclosure rights; fresh host authorization is required. It cannot relabel a recorded receipt as a new
current read. Receipt metadata is displayed only where lookup permission allows it;
this does not authorize re-disclosing revoked business values or answer content.
Persisted streams require fresh disclosure checks on replay, not only at execution.

## Recovery and cancellation

Persist request ID, payload binding and admitted run identity before treating Send as
accepted. Binder death sets visible reconciliation/UNKNOWN state. Reconnect obtains
a new lease, then invokes lookupRead using the existing request/run; no implicit
submit, fallback fixture, regenerated request ID or automatic retry. A definitely
not-admitted response may enable an explicit user retry. Missing lookup evidence
stays UNKNOWN, never becomes success, failure or not-started by assumption.

`cancelRead` means cancellation requested. Retain run/receipt identity and wait for
the existing controller's settled terminal. Completion may win the race; show its
original receipt. Releasing a screen observer is not cancellation or native teardown.
Late results from a retired connection/display generation must not alter another chat.

## Evidence ladder

1. Oracle tests: synthetic contract behavior only (this deliverable).
2. Kotlin/Rust codec and controller tests: new DTO parity, admission and persistence.
3. API26 device/emulator: real input → Binder private :agent → native Agent → trusted
   registered tool/subprocess boundary → ordered projection/receipt display, using an
   explicitly synthetic schema12 SQLite copy. Label synthetic business data and provider.
4. Production source: supported schema/namespace plus the existing authoritative
   ScopeResolver/current-policy bridge; no guessed grants or permissive callback.
5. Live model: Service-owned approved profile/endpoint, purpose/model authorization,
   safe credential resolver/final-send gate and verified budget binding. None is
   established here; no credential values requested or inspected, no model/network call.

I04's denied legacy-state → HTTP → original-state reopen action remains blocked.
This contract does not authorize retrying, splitting or rerouting it. Dependent merges
remain on hold. No candidate or unrelated passing CI certifies this new composition.
