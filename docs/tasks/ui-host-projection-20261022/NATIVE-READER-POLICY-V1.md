# Native reader policy v1 — implementation request, not a generated ABI

Checkpoint based on Host66394026000d3acdc4942df1df31400a8603adaa and exact
B662aeec6d6462cabfcc317e855ae23797dd88d51/native binding01e1. FFI owner may
implement these records/methods; names below are PROPOSED fixed semantic names,
not claims that generated methods already exist. Host owns Runtime/Service;
FFI/core owners implement their own files. Ordinary missing code is NOT a request
for new user authorization. This contract enables continued reading of an exact
already-authorized document; it does not permit executing, writing or sending.

## 1. Confirmed identity and authorization facts

Actual principal construction is in ProductService.withReaderPrincipal:
same-UID registered Binder -> fresh Service-issued session UUID -> original Runtime
ScopeRegistry selected project/generation -> actual ProductCore.health workspace,
Service owner epoch, synthetic=false. Every use rechecks membership/stopped and the
revocable Runtime snapshot. release is irreversible, even before queued cleanup;
4096 tombstone saturation fails reader admission closed. Native must additionally
validate actual store workspace/epoch and project exists/not deleted. This is
local_workspace identity, NOT an account or proof of document permission.

The real Activity adapter is Shellc0c2dc994df099c36c83813adf8410dac999d943,
READER-ACTIVITY-SURFACE.md: actual lifecycle/window/focus/current route/project,
exact typed selection gesture and separate page/frame identity. It currently has
host=null/catalog unavailable. No production Binder/surface join is claimed here.
Its observationId/timestamps/sequence are correlation evidence, NOT grant authority.

Existing native facts (crates/muyon-core/src/documents/storage.rs):
- document_grants: grant_id PK, generation unsigned decimal, owner_epoch,
  document_json exact DocumentRef, permissions, expires_at_ms, active IN(0,1).
- document_grant_deadline lines345+: exact ID/generation/current epoch/active=1,
  exact document and readonly operation checks, expiry enforced. current_document
  resolves actual registered revision/head/source and current live project.
- issue_document_grant_trusted lines589+: authentic current policy precondition,
  generation must be previous.next(), expiry <= now+30000; writes active=1. This
  generic hook MUST NOT be used as a continuation policy check or after an unlocked
  cached allow. It can otherwise revive active=0. Extract a transaction-owned hook.
- revoke_document_grant_trusted lines624+: exact generation/epoch -> active=0.
  Continuation roots MUST be fenced in this SAME revocation transaction, including
  all revocation entry points. Adding only a new stop endpoint is insufficient.
- Existing presentation access derives native workspace/epoch, not caller values;
  validates existing exact access, but has NO issuer/root/principal-surface join.

These are verified schema/code facts, NOT a claim that any current user document
or valid grant was inspected. No live user file/grant listing was performed.
Project selection, document metadata, checksum, research cache, URI, native selection
token or Binder identity alone NEVER authorize document contents.

## 2. Precise continuation policy / TTL vs revocation

A NEW editing-independent reading root may start ONLY from a currently valid exact
persisted grant containing Render (and other readonly operations only if already
present) plus a genuine current visible selection admitted by the private Host.
Store the root/new fact atomically, not an invented historical policy assignment.
Persist root = original source/ref/digest + initial parent/current presentation grant binding + actual
workspace/epoch/session/scope generation + genuine surface instance/lifecycle epoch/
selection sequence + readonly subset + root revision + terminal fence + outcomes.
No accountId; no serialized credentials/allow/current/visibility boolean.

A root authorizes continuity ONLY for this one exact visible reading session. It
never survives background/window loss, route exit, scope/project/Binder/epoch change,
selection replacement, explicit stop/revoke, project deletion or source/revision
change. Foreground return/restart/new selection cannot revive an old root; re-open
requires a new valid initial authorization. Page/frame change within the same exact
visible reading intent may retain the root, but must use actual native frame API.

Never mutate/narrow/revoke an arbitrary pre-existing parent grant just to continue
one reader: existing rows do not prove exclusive ownership. B records parent access
and initial presentation; D's FIRST renewal creates a NEW native-issued readonly
child grant chain owned by this root (generation1). Later D renews only that child
chain with next generation. Parent binding remains unchanged. Every renewal also
checks the ORIGINAL parent is still active=1 with its original generation/epoch/
source/permissions; its natural expiry alone is allowed after root began, but explicit
parent revoke or external parent generation replacement terminates all derived roots.
Native revocation hooks must fence roots by BOTH parent binding and current child
binding. Root stop revokes owned child grants and closes its original presentation,
not unrelated parent uses. No fake child IDs or inferred exclusive owner.

Natural TTL: parent and current owned child (if issued) still have active=1, EXACT expected generation,
epoch/ref/readonly permissions, but expires_at_ms <= now. A CURRENT nonterminal root
plus NEW original-attempt-bound trusted visible observation may atomically issue
first child generation1 or later child.next() <=30s and advance root CAS. Root is the recorded continuing policy;
the expired grant by itself is never enough. Checks do NOT perform renewal.

Explicit revoke: active=0 OR a root terminal/revocation fence => permanent denial
for that root, even if native time later changes or another method sets active=1.
Parent generation replaced, or child generation replaced outside THIS root's
committed renewal => stop root, no adoption of newest grant. Our own renewal updates root.current generation in SAME tx. Revoke
and renew serialize: revoke first prevents issue; renew first is subsequently revoked
at the new current generation/root fence. A revoke addressed to the root/original
reading chain MUST NOT miss because its initial grant generation was superseded by
that same root's renewal. Preserve compatibility and fence on existing exact grant
revokes; add explicit root/chain revocation for this case. Do not silently change
an unrelated old-generation callback into revoke-current.

Unknown/read/SQL/clock failure is NOT natural expiry or not_committed. Reject and
hold original attempt. Never re-dispatch automatically. Do not alter old two model
unknown requests or their fee reservations; this is a separate document-only domain.

## 3. Common record semantics / trusted boundary

Reuse generated DocumentReaderScope(serviceSession,generation,project). Native
workspace/epoch come from its actual owner. unsigned counters/generations/revisions
are canonical decimal STRINGS (u64), including rootRevision and selectionSequence.
No Kotlin Long conversion of document revision. Overflow refuses, never wraps.
DocumentRef is exact existing canonical structure; sourceDigest is lower64hex.

ReadingSurfaceBinding {surfaceId, lifecycleEpoch, selectionSequence} is an ORIGINAL
correlation tuple issued/captured by the actual Activity adapter. Host joins it to
actual Binder owner/scope; no restored old visibility or caller-selected principal.
Root operations are trusted Service-only typed calls, never generic Messenger/model
JSON or tools. Core/FFI validates correlations, ownership, CAS and native freshness;
it DOES NOT claim to measure Android physical visibility. Host must sample actual
surface on its owning Looper immediately for the native-issued original challenge,
reject unknown overlay semantics, and hold its authoritative event ordering through
native admission. FFI must not implement a default boolean allow policy.

Host must preserve its shared Service domain lock for business call -> admin drain ->
current scope/selection validation -> raw result admission. Main-thread Activity must
serialize the original selection/stop event BEFORE a queued Host invocation; Host
pre-call guard rejects stale original requests. Activity observation may not be copied
from an unrelated request or sampled on a worker. Stop/revoke fences are terminal;
late open/renew can't supersede them. Async rendering rechecks actual fresh Activity
and original native frame before publish. Native root receipt is NOT display/PFD proof.

All mutations use SAME BusinessStore transaction for root, grant, revision, prepared
attempt and immutable outcome. Use native clock; challenge window <=2000ms from native
prepare monotonic start, single-use. Proposed freshness value is a protocol parameter,
not currently an accepted physical visibility guarantee. Host clock values are audit
correlation only, never trusted native expiry math. Root and challenges die on native
owner restart; retain durable original outcomes without resurrecting permission.

## 4. Seven concrete native endpoints (inputs -> exact outputs)

A. reader_policy_observe(access:DocumentAccessRequest) -> PolicyObservation
Read-only transaction, NO issuer/idle renewal/source bytes. Requires trusted actual
scope; exact reference/grant; returns schema1, exact document+sourceDigest, grantId,
grantGeneration, active, expiresAtMs, nowMs, readonlyOperations, availability:
valid | naturally_expired | revoked | replaced | unavailable. To classify expiry,
read exact active row before expiry filter; do not convert missing/SQL/type/corrupt
into expiry. Missing exact generation with another current gen is replaced only if
that fact is actually observed; never return replacement access. Return no unrelated
metadata or grant enumeration. Observation is historical evidence, not a permit.

B. reader_policy_begin({access, sourceDigest, presentationId, frameGeneration,
surfaceBinding, originalAttemptId}) -> BeginOutcome
Host already verified genuine selection/visible event and exact existing grant.
First perform ORIGINAL presentation_open using actual valid existing access and
its true one-use native selection token. Then begin root from that ACTUAL current
presentationId/frameGeneration, exact initial access/source, scope and trusted
surface selection. Native validates the stored real ticket and its original native
selection epoch, CURRENTLY VALID existing Render grant, source/digest/project. It
must record the true selection epoch in its presentation mapping at initial open;
root cannot be attached to an arbitrary old/current-looking wire ID or raw reader.
If the grant expires before begin, reject; do not retroactively create root.
Atomically NEW opaque rootId, rootRevision="1", readonly intersection, original
correlation, genuine current presentation binding and immutable outcome. The consumed
selection token is NOT replayed and begin_selection is NOT called from this callback.
begin itself does not open bytes or issue a grant. Actual root creation and initial
binding require the SAME native owner serialization as open and selection changes.
Output status=begun, rootId/rootRevision, exact original binding, currentGrant,
rootState=active, outcomeId/native-generated receipt identity. Duplicate exact
originalAttemptId returns SAME original outcome; altered payload rejects, not latest.
Unknown begin recovery uses scoped originalAttemptId even if caller never got rootId.

C. reader_policy_prepare({scope, rootId, expectedRootRevision,
expectedGrantId, expectedGrantGeneration, originalAttemptId, surfaceBinding,
expectedPresentationId, expectedFrameGeneration}) -> PreparedOutcome
Atomically register original next renewal intent, binding fingerprint, expected CAS
and capacity BEFORE issue. Check current root/scope/source/policy/revocation; actual
grant may be naturally expired, never revoked/replaced. Return actual opaque one-use
challengeId, rootId, originalAttemptId, native-relative validForMs<=2000, exact binding.
No grant issuance, root revision update or implicit presentation advance. Duplicate
original returns original status/challenge, never a refreshed deadline or new attempt.
Host now requests NEW actual owning-thread observation for THIS challenge.

D. reader_policy_renew({scope,rootId,expectedRootRevision,originalAttemptId,
challengeId,surfaceBinding,observationId}) -> RenewOutcome
Private Host call only after validating fresh actual observation bound to the original
challenge/request. No caller allow/permissions/expiry/workspace/account inputs.
Within SAME tx: consume exact prepared challenge once and check native window,
original payload/CAS, current source/project/root/policy and expected current grant
including active flag. Also validate the original presentation binding captured at
prepare, even if its natural lease has just expired: only this exact root's known
predecessor may be continued, never an unrelated currently open frame. On FIRST renewal generate an actual new root-owned child grant ID/generation1,
without updating the parent's row; subsequent renewal issues child.next() on that
same root-owned chain. Check parent active/original generation in SAME transaction,
allowing only its natural expiry under this established root. Readonly subset
only, expiry<=native now+30000; update root revision/current grant and durable receipt.
Output status=issued, original bindings, resultingRootRevision, actual resulting
DocumentAccessRequest grant reference, exact sourceDigest, expiresAtMs, issuedAtMs,
outcomeId, and a NEW native one-use continuationToken with validForMs<=2000,
bound to this root, original renew attempt, expected original selection epoch,
predecessor presentation/frame, new grant and resultingRootRevision. It is NOT a
presentation selection token or display permission. First child issuance does not overwrite the parent grant; later child-generation
issuance makes the old child presentation access stale. In BOTH cases handoff must
invalidate the predecessor ticket/output; Host MUST NOT publish/reuse that old frame.
Before returning from the SAME Host serialized business batch, invoke G using this
actual token and then drain/reroute native invalidations. D alone does not provide
continuous reading. No fake revision, token, ID or expiry placeholders. On expired challenge:
not_committed terminal original outcome, no auto fresh prepare. Error/uncertain commit:
unknown(originalAttemptId); Host must reconcile same original, never retry issue.
Duplicate committed attempt returns historical exact receipt, never extends deadline;
receipt alone cannot mark current display live or reopen old scope.

E. reader_policy_reconcile({scope,originalAttemptId,kind:begin|renew|handoff|stop})
 -> OriginalOutcome
Explicit reconciliation of original mutation, NOT automatic background read/replay.
May atomically FENCE an original prepared-but-unissued renewal to not_committed so a
late renew can no longer issue. Document this mutation clearly in generated comments.
Return exact original status: committed/begun/issued/stopped OR fenced_not_committed
OR unknown; original fingerprint/root/CAS/result binding, historical=true. Never
resolve by latest grant or current selection; failed read is unknown, not missing.
Do not fence an in-progress native commit outside its transaction/owner ordering.
Keep historical outcome separate from current root/grant state and display admission.

F. reader_policy_stop({scope,rootId,expectedRootRevision,originalAttemptId,
reason:background|window_lost|route_exit|scope_changed|selection_replaced|user_close|revoked})
 -> StopOutcome
Trusted actual lifecycle/current original owner only. Terminally fence SAME original
root/chain, prepared attempts and its current OWNED child grant (if any) in one tx;
close its known predecessor/current presentation through real native owner cleanup,
including an initial parent-backed ticket. Do not revoke unrelated parent uses; exact old root
request never closes unrelated new root/frame. Stop must not require still-unexpired
grant/visible surface; cleanup is administration for actual recorded owner. Revision
race from own issued renewal cannot make genuine owner stop ineffectual: re-read and
fence THAT same root transactionally, recording observed resulting revision; never
switch root identity. Return stopped original root/revision/current affected grant,
outcomeId and cleanup status (not proof Android OS/PFD disposal). Unknown retains
original stop; no new reading until exact reconciliation/cleanup. Existing revoked
fence remains terminal, repeated exact stop idempotent with same outcome.

G. reader_policy_continue_presentation({scope,rootId,resultingRootRevision,
originalRenewAttemptId,continuationToken,predecessorPresentationId,
predecessorFrameGeneration}) -> PresentationContinuationOutcome
This is a NEW restricted native continuation endpoint/core hook, NOT existing
presentation_open with a replayed selection_id and NOT a new user selection.
Under the sole native owner, before ANY operation that could close another frame:
validate token original/root/epoch/scope/current genuine selection epoch, exact
predecessor binding, new persisted grant and nonterminal root/revocation fence.
Consume once. A newly accepted real selection B must fence old A roots/challenges/
continuation tokens immediately; late A MUST refuse BEFORE destructive core open.
The existing presentation_begin_selection therefore needs an explicit policy-root
selection-fence hook; its current pending token registry alone is not enough.

On success create a GENUINE new native presentation ticket from the resulting valid
access and bind it to the same original root/reading intent, returning the real
presentation_id/frame_generation/document/sourceDigest/phase/valid_for_ms/
check_after_ms plus original root/renew outcome correlation. Values are native facts;
never increment Host frame counters to fake a ticket. Native may securely transfer
its existing authenticated exact-source snapshot/pin under a new validated access
if core implements that transaction/ownership invariant, otherwise explicitly open
a new bounded source snapshot. No bare cached Android bytes become an active lease.
Old access/ticket/frame is invalidated, with exact predecessor notification; new
frame starts its OWN genuine deadline. Host destroys old PFD/cache/bitmap before
publishing new frame, checks original source+actual current session and drains in
SAME shared batch. This is native lease handoff, not proof Android disposal occurred.

A naturally expired old ticket may be replaced ONLY through the root's recorded
predecessor binding and freshly issued grant/token. Natural expiry closes output,
not automatically the independent continuation root. Explicit revocation/scope/
source/selection change terminates root AND continuation, never a regrant fallback.
Root keeps last genuine presentation binding under native owner; explicit frame
advance must update it before publication. A prepared challenge binds exact original
frame; intervening advance rejects that prepared handoff, not upgrade-to-latest.
Known predecessor invalidation from successful handoff clears only predecessor
resources; it must not terminate this same still-current root/new frame. This
requires actual Host controller routing; the current generic registry's
CURRENT_TERMINAL stop is NOT a complete continuation implementation. Unknown or
clear_all remains conservative hold; don't suppress notifications to keep UI alive.

SQL grant/root receipt commit and in-memory ticket/PFD transfer are NOT one SQLite
atomic transaction. Reserve a durable handoff outcome with D, serialize native G,
then record completed/fenced outcome against exact attempt. Reconcile distinguishes
grant_issued_handoff_pending, handoff_completed (HISTORICAL, not live permission),
and handoff_failed_fenced/unknown. No caller retries G blindly after lost result;
explicit original reconciliation fences any unperformed handoff before reporting
not-performed and returns exact committed fact when known. A crash closes tickets/
root epoch; historical committed grant receipt cannot reconstruct a live frame.
Failure AFTER grant issue is NOT not_committed grant and must invalidate output,
fence/hold this original root/handoff, preserve audit and require explicit original
reconciliation. A duplicate or expired continuation token never creates a second
new ticket, refreshes deadlines, reopens or closes current B. Capacity/error paths
must retain old/new owned identities for actual owner cleanup, not close-current.

This endpoint needs a genuine core ticket-transfer/reopen hook from core owner plus
FFI mapping; FFI cannot fabricate native tickets from JSON. Coordinate those exact
owners before implementing, and leave production gate closed until jointly tested.

## 5. Retention, concurrency and mandatory tests

Reserve receipt/pending capacity BEFORE any grant issuance. Suggested initial bounded
native owner limits: 16 roots, 256 original attempts total; limit values can be reduced
by owner but never evict live/unknown/root revocation fences to admit new work. Stop
updates reserved terminal space in-place and cannot be refused merely because the
new-admission quota is full. Persistent total bytes bounded with schema/type/UTF8/length
checks before materialization. Compaction may preserve a rejecting tombstone instead
of full terminal payload; it cannot make an old original ID valid/new again. Owner
epoch changes close roots and prohibit reusing their grants, even after process death.
Threat boundary is app-private same-UID local workspace; no invented account ACL or
claim of preventing malicious OS rollback of all app data.

Required native offline tests using synthetic store facts:
valid root; expired-before-begin deny; natural expiry after real begin renew; active=0
never revived; unrelated generation replacement deny; matching root CAS; source/head/
project deletion; scope/Binder/epoch/selection changes; root stop then late prepare/
renew/open; revoke-before-renew AND renew-before-root-revoke; duplicate/altered attempt;
challenge expiry/consumption/overflow; shared parent grant unaffected by child issue/stop, parent revoke fences descendants,
first child creation and later generation renewal, grant renewal invalidates old child access;
renew->genuine next presentation handoff (no replay selection token), expired old
lease continuation with live root, frame advance between prepare/handoff, duplicate/
expired handoff token, failed/lost handoff after issued grant, begin B then late A
handoff zero destructive calls, old invalidation cannot clear new frame/root;
failure before/after commit+original reconcile;
reconcile fences late issue; old receipt never current; restart roots dead/outcomes
historical; quota/SQL/type/corruption failclosed; stop still works at full capacity.
Host tests additionally A/B/ABA stale pre-call and shared call/drain/publish batch.
Real Android >30s, lifecycle/page/PFD/revoke/invalidation tests remain NOT_RUN; no gate
flip from these native/unit tests alone.

## 6. Initial-access rule — NOW APPROVED; see addendum

The user approved the precise local explicit-selection policy via trusted parent
session evidence2026-10-22 09:23:33UTC. Read FIRST-READ-APPROVED.md: additive native
initial admission, before-root stop/reconcile, one-use genuine selection event and
persistent document-read deny/version vs lifecycle cleanup. Missing code is not a
new authorization blocker. Seven continuation endpoints above remain proposed APIs;
initial admission is an additional native contract, not hidden observe/renew behavior.
No production gate was enabled and no synthetic native result is substituted.


## Independent review correction retained

Initial875e7c350d9587c64aaa52f7677164be524e0ba0 had six semantic endpoints.
Reviewer found Important: grant generation renewal leaves original presentation access
stale and its native selection token is consumed. G and its core/FFI mapping are a
REQUIRED new interface, not existing behavior. B now attaches root to an actual initial
open ticket; D issues bounded one-use continuation handoff and G creates a genuine new
ticket. Existing six endpoints alone must NOT be presented as continuous reading.
Native, controller/PFD and Android implementation/acceptance are still pending.
