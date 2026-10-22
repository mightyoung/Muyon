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
Persist root = original source/ref/digest + original/current grant binding + actual
workspace/epoch/session/scope generation + genuine surface instance/lifecycle epoch/
selection sequence + readonly subset + root revision + terminal fence + outcomes.
No accountId; no serialized credentials/allow/current/visibility boolean.

A root authorizes continuity ONLY for this one exact visible reading session. It
never survives background/window loss, route exit, scope/project/Binder/epoch change,
selection replacement, explicit stop/revoke, project deletion or source/revision
change. Foreground return/restart/new selection cannot revive an old root; re-open
requires a new valid initial authorization. Page/frame change within the same exact
visible reading intent may retain the root, but must use actual native frame API.

Natural TTL: root.current grant still has active=1, EXACT expected generation,
epoch/ref/readonly permissions, but expires_at_ms <= now. A CURRENT nonterminal root
plus NEW original-attempt-bound trusted visible observation may atomically issue
next generation <=30s and advance root CAS. Root is the recorded continuing policy;
the expired grant by itself is never enough. Checks do NOT perform renewal.

Explicit revoke: active=0 OR a root terminal/revocation fence => permanent denial
for that root, even if native time later changes or another method sets active=1.
Generation replaced outside THIS root's committed renewal => stop root, no adoption
of newest grant. Our own renewal updates root.current generation in SAME tx. Revoke
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

## 4. Six concrete native endpoints (inputs -> exact outputs)

A. reader_policy_observe(access:DocumentAccessRequest) -> PolicyObservation
Read-only transaction, NO issuer/idle renewal/source bytes. Requires trusted actual
scope; exact reference/grant; returns schema1, exact document+sourceDigest, grantId,
grantGeneration, active, expiresAtMs, nowMs, readonlyOperations, availability:
valid | naturally_expired | revoked | replaced | unavailable. To classify expiry,
read exact active row before expiry filter; do not convert missing/SQL/type/corrupt
into expiry. Missing exact generation with another current gen is replaced only if
that fact is actually observed; never return replacement access. Return no unrelated
metadata or grant enumeration. Observation is historical evidence, not a permit.

B. reader_policy_begin({access, sourceDigest, nativeSelectionId, surfaceBinding,
originalAttemptId}) -> BeginOutcome
Host already verified genuine selection/visible event and exact existing grant.
Native validates its current pending selection token belongs to same original scope
(do not call begin_selection on a delayed callback), actual source/digest/project and
CURRENTLY VALID existing Render grant; no beginning from naturally_expired grant.
Atomically NEW opaque rootId, rootRevision="1", readonly intersection, original
correlation, immutable outcome. Do not consume/reissue the separate presentation
selection token such that actual open must guess/replay it; pin/check its association
and define exact handoff to presentation_open. begin itself does not open bytes.
Output status=begun, rootId/rootRevision, exact original binding, currentGrant,
rootState=active, outcomeId/native-generated receipt identity. Duplicate exact
originalAttemptId returns SAME original outcome; altered payload rejects, not latest.
Unknown begin recovery uses scoped originalAttemptId even if caller never got rootId.

C. reader_policy_prepare({scope, rootId, expectedRootRevision,
expectedGrantGeneration, originalAttemptId, surfaceBinding}) -> PreparedOutcome
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
including active flag. Issue next generation on same exact chain, readonly subset
only, expiry<=native now+30000; update root revision/current grant and durable receipt.
Output status=issued, original bindings, resultingRootRevision, actual resulting
DocumentAccessRequest grant reference, exact sourceDigest, expiresAtMs, issuedAtMs,
outcomeId. No fake revision, token, ID or expiry placeholders. On expired challenge:
not_committed terminal original outcome, no auto fresh prepare. Error/uncertain commit:
unknown(originalAttemptId); Host must reconcile same original, never retry issue.
Duplicate committed attempt returns historical exact receipt, never extends deadline;
receipt alone cannot mark current display live or reopen old scope.

E. reader_policy_reconcile({scope,originalAttemptId,kind:begin|renew|stop})
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
root/chain, prepared attempts and its current derived grant in one tx; exact old root
request never closes unrelated new root/frame. Stop must not require still-unexpired
grant/visible surface; cleanup is administration for actual recorded owner. Revision
race from own issued renewal cannot make genuine owner stop ineffectual: re-read and
fence THAT same root transactionally, recording observed resulting revision; never
switch root identity. Return stopped original root/revision/current affected grant,
outcomeId and cleanup status (not proof Android OS/PFD disposal). Unknown retains
original stop; no new reading until exact reconciliation/cleanup. Existing revoked
fence remains terminal, repeated exact stop idempotent with same outcome.

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
challenge expiry/consumption/overflow; failure before/after commit+original reconcile;
reconcile fences late issue; old receipt never current; restart roots dead/outcomes
historical; quota/SQL/type/corruption failclosed; stop still works at full capacity.
Host tests additionally A/B/ABA stale pre-call and shared call/drain/publish batch.
Real Android >30s, lifecycle/page/PFD/revoke/invalidation tests remain NOT_RUN; no gate
flip from these native/unit tests alone.

## 6. Only remaining product rule (if no existing grant can be supplied)

Continuation above is fully specified development within already-authorized reading;
no new user permission is requested to implement it. Initial access with NO prior
valid grant is different: existing code contains no production policy assigning one
merely because a document is registered. Do not infer universal file disclosure.

Single decision to pin with product owner: should a genuine explicit selection of an
exact registered document in current LOCAL workspace/project create FIRST readonly
Render access for that reading session? Recommended YES, limited to app-private
registered source, exact revision/digest, current real Activity/Binder scope and a NEW
recorded reading intent; readonly minimum, no file-system scan/URI grants/account ACL/
external source/annotation/write/execution. Implement as a separate explicit initial
policy admission, not observe/expiry recovery or hidden continuation fallback. This
is a product semantics choice to record, not a reason to request permission for normal
adapter/backend development. Until pinned, implement all continuation endpoints and
fail initial_no_authorization honestly rather than fake a grant.
