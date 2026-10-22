# Required atomic core facade — seven-endpoint reader policy checkpoint

Fixed governing Host input660f03da29d26d6cdcf28c594c959cc6c43098e4:
docs/tasks/ui-host-projection-20261022/NATIVE-READER-POLICY-V1.md.
Supersedes875e7c's SIX endpoints, selection-token-before-begin and shared-parent
mutation assumptions. Latest protocol read including all changes, not inferred.
Current FFI source5488ec69d59ae2ed368ca2fd53d5989c51cf2719. Core remote inspected
read-only at4c9072af48d7a6eceb9abb70594b03ab4bc412be, not merged; it has presentation
plus purefmt but no continuation facade. No live user grants/files were inspected.

This is the concrete CORE OWNER implementation request. It is NOT a generated ABI,
implemented policy or new user-authorization request. No six/seven mock exports,
empty trait or successful stub was added. FFI cannot implement the required atomic
root/grant transaction by using today's public facade. Core owner currently owns
storage/source_notifications; those files remain untouched by this checkpoint.

## Verified blocking gap

storage.rs345 private document_grant_deadline filters generation/active=1, then
expiry. Public read_document needs Inspect, not policy's initial Render; public
Reader open/check reads/hashes source or rejects expiration. None can classify
actual naturally-expired/revoked/replaced rows without changing semantics.

storage.rs589 generic issue_document_grant_trusted owns its own transaction and
upserts active=1. FFI checking then issuing would revive revoked grants across a
TOCTOU gap. storage.rs624 exact revoke owns its own transaction, with no descendant
root fence. Fixed4c9072af has no root/outcome/journal or policy API. Publicizing
private tx helpers, a second store, copied SQL policy or cached allow is forbidden.

## Concrete public core request

Please implement a concrete documents::reading_policy facade, borrowing the
EXISTING DocumentReaderHost (and its store) per call. It owns native challenges/
continuation state only, not a second BusinessStore or an Android visibility check.
Using ReaderHost lets begin/handoff verify the real live ticket/selection and do
real cleanup rather than trust a deserialized ticket or a caller boolean.

Suggested exact method shape (names can be fixed by core owner before source):

```rust
pub struct ReadingPolicyHost { /* actual native owner and challenge state */ }
impl ReadingPolicyHost {
    pub fn open(reader: &mut DocumentReaderHost) -> PolicyResult<Self>;
    pub fn observe(&mut self, reader: &mut DocumentReaderHost,
        request: &PolicyObserveRequest) -> PolicyResult<PolicyObservation>;
    pub fn begin(&mut self, reader: &mut DocumentReaderHost,
        request: &PolicyBeginRequest, initial: &PresentationTicket,
        native_selection_epoch: &Revision) -> PolicyResult<OriginalPolicyOutcome>;
    pub fn prepare(&mut self, reader: &mut DocumentReaderHost,
        request: &PolicyPrepareRequest) -> PolicyResult<PreparedPolicyOutcome>;
    pub fn renew(&mut self, reader: &mut DocumentReaderHost,
        request: &PolicyRenewRequest) -> PolicyResult<OriginalPolicyOutcome>;
    pub fn reconcile(&mut self, reader: &mut DocumentReaderHost,
        request: &PolicyReconcileRequest) -> PolicyResult<OriginalPolicyOutcome>;
    pub fn stop(&mut self, reader: &mut DocumentReaderHost,
        request: &PolicyStopRequest) -> PolicyResult<OriginalPolicyOutcome>;
    pub fn continue_presentation(&mut self, reader: &mut DocumentReaderHost,
        request: &PolicyContinueRequest) -> PolicyResult<PolicyContinuation>;
    pub fn selection_changed(&mut self, reader: &mut DocumentReaderHost,
        scope: &PolicyScope, native_epoch: &Revision) -> PolicyResult<()>;
    pub fn frame_advanced(&mut self, reader: &mut DocumentReaderHost,
        previous: &PresentationTicket, next: &PresentationTicket) -> PolicyResult<()>;
}
```

The extra three methods open/selection_changed/frame_advanced are NATIVE integration
hooks, not additional wire endpoints. All seven requests and outcome fields mirror
latest Host section4 A..G EXACTLY. No wire workspace/owner epoch, allow boolean,
expiry or caller permissions. Scope=service_session/generation/project; actual
workspace/epoch derive from existing store. Canonical counters are Revision, IDs
and original SurfaceBinding remain bounded exact correlations. Surface/lifecycle
ID Kotlin types are not defined by the prose; freeze with Host before generation.

Critical request bindings:
- Observe exact supplied DocumentAccess/scope; no source bytes/issuer. Read active,
  exact original generation and bounded schema/types BEFORE expiry classification.
- Begin from ACTUAL initial presentation_id/frame_generation AFTER original open.
  FFI passes its stored real ticket plus internally retained native selection epoch;
  core verifies real current Render ticket, exact access/source/digest/project,
  CURRENTLY VALID parent grant and native correlation in root transaction. Begin
  no longer accepts/replays nativeSelectionId. Root duplicate uses scoped original
  attempt fingerprint and identical original receipt, not latest state.
- Prepare binds expected grant ID AND generation, root CAS, actual SurfaceBinding,
  expected presentation ID/frame and original attempt before issuing challenge.
  Root retains genuine predecessor binding even when its natural lease expires.
- Renew validates original prepared bindings and <=2000ms native monotonic challenge
  window ONCE. Verify parent active/original generation/epoch/ref/permissions with
  only natural expiry allowed. FIRST renewal creates a NEW root-owned child grant
  ID/generation1; later renews only that child chain. Parent row never narrowed,
  reissued or revoked just for this reader. Owned child and root CAS/receipt/handoff
  reservation commit in SAME transaction. Actual receipt includes new one-use
  <=2000ms continuation token bound to original renew/root/predecessor/selection.
- Continue binds resulting root revision/original renew/token/predecessor ID/frame,
  native owner/current genuine selection epoch, exact source and valid new child.
  Validate BEFORE any destructive ReaderHost open/close. Return real
  DocumentPresentationInfo (contains nonconstructible native ticket) PLUS exact
  durable original handoff outcome. Never reconstruct ticket from wire JSON.
- Reconcile kinds begin|renew|handoff|stop; original scope/attempt only. Prepared
  renew/handoff can be fenced before not-performed. Absent original that may still
  arrive late requires a rejecting scoped tombstone or unknown, not fake absence.
- Stop same original root under authentic recorded owner, including raced own CAS;
  revoke ONLY its owned child chain, fence challenge/handoff and close only its
  recorded initial/predecessor/current native tickets. Parent/unrelated uses stay
  untouched. No expiry/visible-surface prerequisite; terminal capacity reserved.

PolicyContinuation should contain typed original outcome + optional genuine
DocumentPresentationInfo only on THIS actual successful native handoff, never an
apparently-live ticket from historical reconciliation. FFI allocates new opaque
presentation ID BEFORE G and includes it as native correlation in PolicyContinue
request/outcome, enabling exact mapping/outcome after dispatch without guessing.
Native core ticket/source/grant structs stay internal; bounded Serialize receipt
projections expose only Host's declared fields. Errors preserve original attempt;
SQL/clock/type/unknown commit cannot become expiry or not_committed.

## Required core transaction and lifecycle hooks

1. SAME store transaction for durable root/CAS, original prepared attempts, child
   issuance, capacity reservation, immutable grant outcome and reserved handoff
   outcome. Suggested16 roots/256 attempts, byte/type limits before materialization.
   Never evict live/unknown/revocation fences. Reserve terminal stop slot at begin.
2. Extend EXISTING revoke transaction paths to fence descendants by parent binding
   AND current child binding. Add root/chain addressed revoke for superseded OWN
   child generations. Do not turn unrelated stale grant callbacks into revoke-latest.
3. External parent/child generation replacement must irreversibly terminal-fence
   affected roots/prepared/handoff in that write transaction (or durable mutation
   tombstone); later active=1/time rollback cannot resurrect them. Own renewal is
   the sole allowed current-child/root CAS update. No parent ownership inference.
4. Coordinate source_notifications owner: head/digest/project deletion terminally
   fences roots and descendants. Natural lease expiration closes output but does
   not terminally kill a valid continuing root. Explicit stop/selection/scope/epoch/
   surface loss does. Expose bounded root terminal notifications or equivalent
   real current-root check to let FFI/Host route exact cleanup without cached truth.
5. open() runs ONCE after existing owner lock acquisition. Establish fresh native
   owner-session; kill old roots/challenges/continuation even if epoch accidentally
   reused, retain original historical outcomes and rejecting fences. No restart
   grant/visibility reconstruction or automatic retries.
6. selection_changed() is invoked synchronously on REAL current Host selection
   admission BEFORE a new token is returned or async lookup starts. It fences old
   root/prepared/continuation, so late A after B cannot reach destructive native open.
   This hook must complete/fail closed before FFI publishes B's selection token.
7. frame_advanced() records actual old->new core ticket binding BEFORE FFI publishes
   its frame response; prepared original-frame challenges cannot adopt latest.
   Keep frame-correlation generation separate from policy root CAS if that avoids
   altering Host's root revision semantics. On failure after native advance, hold/
   terminally clean exact owned identities, emit clear_all/terminal as appropriate;
   never pretend SQLite rolled back an in-memory ticket generation.
8. G cannot be SQLite-atomic with in-memory snapshot/PFD work. Reserve handoff with
   D; serialize actual G under owner; persist completed/fenced original outcome.
   Reconcile distinguishes grant_issued_handoff_pending, handoff_completed historical,
   handoff_failed_fenced and unknown. Failure after child commit is NOT grant
   not_committed. Preserve old/new owned native handles for exact cleanup, never
   close-current by guess. Reconcile must fence any unperformed G before reporting
   nonperformance; duplicate/expired token cannot create a second ticket/deadline.

## FFI-owned implementation immediately after fixed facade source

I retain sole FFI ownership. Add reader_policy_bridge.rs and concrete typed UniFFI
records/wrappers delegating the actual facade under existing State mutex. Keep all
5draft/13raw APIs and7presentation signatures/behavior. Persist native initial
selection epoch in ReadLease at open; current selection epoch remains after token
consumption. Begin matches that internal epoch and actual ticket, not wire claims.
New selection and frame paths call the core hooks before publication. Core G
returns a genuine ticket: replace exact predecessor mapping, retain new root
association, translate old invalidation as predecessor cleanup rather than killing
same continuing root. clear_all/unknown remains conservative hold. No suppressing
notifications or default allow to keep UI alive.

B generates actual new bindings; db40 is old raw-only and01e1 is pre-policy. Host
owns fresh Looper observation, actual principal/scope/selection serialization,
shared D->G->drain->admission batch and real PFD disposal. Native never measures
physical Android visibility or claims OSFD revocation. On2026-10-22T09:23:33Z
user explicitly approved genuine selection -> this reading intent's first readonly
authorization, subject to exact local registered source/current project and no
explicit document-read revocation. INITIAL-READ-ADMISSION-REQUEST.md fixes the
additional admission request; implementation is still pending, not a generated
endpoint or universal document disclosure. Until real core admission exists,
missing authorization still fails honestly.

## Checkpoint status

Core facade above is PENDING core owner, not denied, not run/uncertain execution.
No continuation endpoints exported until they can call concrete atomic code.
This checkpoint changes task docs only; existing source and its23 test sources
remain5488. Local cargo absent; NO new Rust run or new feature acceptance claimed.
Previous294 core and old FFI passes do not verify continuation. Required synthetic
matrix is latest Host section5, including shared parent preservation, both revoke/
renew orders, natural expiry only, original receipts/CAS, challenge/token lifetime,
G failure/unknown/reconcile, A/B stale handoff, quota/type/source/epoch/restart and
stop at full capacity. No real model/engine/search/user file or credentials work.
