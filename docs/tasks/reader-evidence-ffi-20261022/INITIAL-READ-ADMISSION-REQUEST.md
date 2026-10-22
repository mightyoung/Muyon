# Approved initial reading intent — required native admission hook

Authorization received in parent delegation's trusted transcript: user answered
“允许” at2026-10-22T09:23:33Z to genuine explicit selection granting THIS readonly
view of a source-known locally registered document in current project, without
another confirmation. Excludes editing, sending, background automatic reading,
unknown sources and restoring explicitly revoked document-read permission.

This updates only initial admission product semantics. Host660f03da29d26d6cdcf28c594c959cc6c43098e4's
seven continuation endpoints, same-store policy state, real scope/Activity proof,
exact source/head/epoch, native selection fence, original intents and device gates
remain required. No account ACL/credential or host filesystem permission is added.
This checkpoint is a concrete core/Host integration request, NOT an implemented
or generated eighth API. Current executable FFI source remains5488ec69.

## Suggested additional concrete admission operation

```rust
// ReadingPolicyHost, same existing reader/store/native owner serialization.
pub fn admit_selection(&mut self, reader: &mut DocumentReaderHost,
    request: &InitialReadAdmissionRequest) -> PolicyResult<InitialReadAdmissionOutcome>;
```

Proposed new private Service wire name `reader_policy_admit_selection`, typed record:
- scope: existing DocumentReaderScope, verified real registered Binder/session and
  revocable current project/generation by Host; store workspace/epoch stay native.
- document_ref_json: exact native registered DocumentRef, source_digest: lower64hex;
  no path/URI, permissions, grant ID, account, sourceKnown or visibility boolean.
- native_selection_id: ORIGINAL native-issued one-use selection token registered
  synchronously at the genuine current Activity selection event, never late callback.
- surface_binding: original real surface/lifecycle/selection correlation, joined by
  actual Host, not a claim native can measure Android visibility.
- original_attempt_id: this one explicit reading intent's stable native/Host-issued
  attempt, never an automatic retry/new ID following unknown or old outcome.

FFI must validate exact pending selection token/current native selection epoch and
scope BEFORE core call. It retains token for the actual initial presentation open,
not consuming/replaying it during admission. Existing presentation_open then uses
real resulting access and consumes that same original selection token. Existing
reader_policy_begin attaches root to the ACTUAL returned presentation/ticket/frame,
following Host660; no root begins from a merely prepared/claimed display.

Core atomically checks exact registered local controlled source, current live
project/head/digest and native epoch, actual source provenance/managed blob binding,
current genuine selection association and explicit document-read denial fence.
Missing/unknown provenance or corrupt/unavailable facts deny, never infer permission
from file existence/URI/checksum alone. The recorded genuine new reading intent is
the approved policy basis; metadata/blob identity by itself is not authorization.

Reserve original outcome/capacity BEFORE issuing a real new initial readonly grant.
Choose minimum native readonly operations needed by this viewer (including Render),
not caller permission arrays; no annotation write, export/send or engine permission.
Actual grant ID/generation/expiry come from SAME core transaction,<=30s, persisted
with source/scope/original selection intent and immutable receipt. Return actual
DocumentAccessRequest + original attempt/outcome ID, exact source/binding/deadline.
Receipt is historical evidence, never current display/PFD proof. Duplicate exact
attempt returns original unchanged receipt; altered payload rejects. Unknown never
causes automatic redispatch or new grant IDs. Scoped original reconcile must cover
this admission mutation too (new kind admission, or an equally explicit native
original-outcome lookup; cannot pretend the seven current kinds already cover it).

This endpoint/type and reconcile-kind addition require Host/B codec agreement;
no old binding is to be advertised as implementing them. Core owner may fix names
while preserving these exact semantics before emitting fixed source.

## Lifecycle cleanup is not permanent document denial

- background/window/route/scope/selection/user-close stops original reading intent,
  root, pending attempts/tokens and native presentation, revoking only the chain it
  actually owns. It must NOT create a permanent file-read denial just because a
  root-owned child grant was cleaned. Arbitrary existing parent grant stays intact.
- Parent grant issued by THIS initial admission has durable selection-intent
  provenance. A stopped/consumed old intent cannot be used with a fresh token to
  claim new authorization while its row still has time left. Fence its original
  intent association (and owned lease uses) without inferring ownership of an
  arbitrary preexisting parent. New explicit selection may create a NEW intent
  after normal lifecycle cleanup if document permission was not explicitly revoked.
- Explicit document-read revocation is a separate persistent terminal denial fact
  keyed to canonical workspace/project/document identity (core fixes revision/source
  scope precisely), NOT just one grant ID. Check it on initial admission AND root/
  child continuation, and fence existing descendants transactionally. New grant
  IDs, aliases of that SAME canonical identity, restarted owner, later active=1 or another selection must not
  bypass it. No implicit un-revoke endpoint is authorized by this approval.
- Existing generic revocation entrypoints must retain their promised semantics.
  Distinguish user-directed explicit read revocation from private owned-child
  lifecycle cleanup in core helpers. Do not use generic active=0 alone as either
  proof of a permanent document ban or justification to invent a new grant.

## Required tests and current status

Synthetic exact real selection/source -> initial grant -> actual open -> begin;
unknown/foreign/unregistered/external source and old/cross-scope token deny; original
attempt duplicates/alterations/unknown reconciliation; parent unchanged; lifecycle
stop then NEW genuine selection can admit again; old intent/ticket never revived;
explicit document revoke then new selection/new grant ID cannot admit; source/head/
project/epoch changes; admission versus revoke both orders; quota/corrupt/commit
failures. Include never-opened initial intent stopped before root creation.

Core admission/persistent denial hook: PENDING core owner, not denied/executed.
FFI records/wrappers: await that concrete API then real delegation under existing
State mutex; no mock issuer fallback. No new Rust test/UniFFI/device success here.
Earlier23 FFI source tests and core294 results do not cover this new admission.
