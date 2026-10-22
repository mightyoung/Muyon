# Sustained reading: trusted reauthorization contract v1 (NOT implemented)

Task source: parent long-reading request after actual fifth Service wiring. This is
NEW authority coordination, not another short-TTL security fix. Scope is readonly
public-document experience; no annotation/write/model/external execution permission.
Current30s grants and presentation15s idle/30s absolute cannot support normal long
PDF reading by renewing a lease within the same grant. No continuous-reading claim.

## Verified production facts and exact blockers

Inspected current769feb7f15c32d514ce9ef1d87187345afb76ab1 source:
- MainActivity.kt creates/binds ProductClient in onCreate and closes in onDestroy.
  It has no reader visibility/focus onStart/onStop/onPause registration, selected
  exact DocumentRef reading-session owner, or policy-issued principal reference.
  Public document route is DocumentCapabilitiesScreen, not an active reader.
- ProductService.clients binds actual same-UID Binder to a generated session and
  death/release cleanup. A live connection does NOT prove visible reading. Runtime
  ProductScopeRegistry is a chat scope, not a document-principal policy/visibility
  grant. Existing readerOwners tracks research attachments, not shared DocumentAccess.
- documents/storage.rs issue_document_grant_trusted checks actual current document,
  owner epoch, next generation and expiry <=native now+30,000ms. It explicitly
  requires authentic current policy/user authorization. It does NOT itself maintain
  a live reading consent, selected Activity, principal assignment or sticky revocation
  intent across new generations. Its update can activate a new generation: calling
  it after an unlocked policy bool risks reviving a concurrently revoked session.
- Reader466 FFI accepts already-issued grant refs, offers no issuer/reauthorizer,
  and its EOF closes source pin. Core display-retention API/real binding is pending.
  Thus neither existing Android visibility nor native policy/issuance port can
  implement the trusted chain today. No fake allow/principal/lifecycle is added.

Action blocked (PENDING CONTRACT, not denied): product reauthorization coordinator
and continuous reader wiring. Missing owners/targets: shell/Activity supplies genuine
visible exact selection; policy/core owner supplies atomic readonly reauthorization
and revocation fence; FFI owner+B supply actual typed bridge; this Host owns coordinator,
Service scope/late-call fencing and reader adapter AFTER those fixed inputs.

## Authority semantics / impact requiring independent review

| Change | Effective impact / explicit limit |
| --- | --- |
| Repeated newly issued readonly grants | Extends effective reading across30s only while a current visible user reading session and CURRENT policy authorize it; original grant/old generation expiry is never lengthened. |
| Live reading consent/session | New local policy fact bound to exact document/source/scope and real Activity surface; not account ACL, a JSON allow bit, execution grant or persisted short-lived token. |
| New generation + presentation replacement | Old generation becomes unusable. Every issuance and exact result must be auditable; old historical expiry/permission facts retained in audit. No silent re-open/latest revision. |
| Stop/revoke/unknown handling | Stops view/output/new grants immediately at Host lifecycle fence, explicitly closes/revokes owned native resources, and holds on uncertain cleanup. Cannot erase arbitrary previously copied bytes at OS level. |

Document permission semantics change even though the per-grant TTL stays capped.
This design requires separate non-author review BEFORE product wiring. Pure state
or simulated policy tests cannot authorize the real policy port or open verified gate.

## Required trusted inputs (not deserialized client authority)

1. A private reader-surface adapter attached to the REAL Activity/LifecycleOwner and
   actual selected reader route. It registers a unique live surface instance with
   existing Binder owner, service epoch and actual Runtime scope. Visible default:
   resumed foreground selected surface with window visibility/focus; unsupported
   multiwindow/PiP/overlays fail closed until real device policy is defined. Compose
   recomposition, bindService, saved UI state or an incoming boolean is not evidence.
2. Explicit genuine user selection opens a NEW reading intent for one canonical
   DocumentRef + actual immutable source identity/digest, actual workspace/project,
   Service session/scope generation, surface/lifecycle epoch and monotonic selection
   sequence. page/render sequence is separate: changing PDF page keeps SAME document
   intent but prevents an old page response from replacing a newer page.
3. Current policy owner supplies a real opaque principal/policy-session reference
   and explicit readonly consent for that exact source. It must derive from existing
   local user policy, not a fabricated account, same-UID assumption or caller JSON.
   Only required ReadText/Render operations are eligible, each individually allowed;
   no Annotate/export/sync/structured-edit or unrelated document permissions added.
4. Native policy session has a sticky revocation/lifecycle/selection fence and an
   expected policy revision. Core atomic issuance verifies it, expected prior grant
   generation and exact current immutable source. The Host cannot substitute an
   allow flag for this atomic native predicate.

Freshness is a required port field, not an assumption about the last visible event:
for EACH original reauthorization attempt the real Activity adapter must sample its
current lifecycle/window/selection on its owning thread and return a one-use opaque
sample bound to that attempt, surface/lifecycle epoch and accepted selection version.
Host/native broker assigns and enforces a monotonic admission deadline; proposed
upper bound2s from the actual sample, subject to policy-owner/device review before
implementation. An expired/missing/reused/version-mismatched sample DENIES issuance;
no cached visible=true fallback. Stop callbacks advance the local fence immediately
and Service/native fences on receipt; bounded propagation is not an instantaneous
physical-visibility attestation. The concrete release must define the clock bridge
and reject at native transaction tail if freshness expires during work. An activity
heartbeat or validity check never issues authority or reuses a sample for a new grant.

No model tool, ordinary Messenger JSON or text/card payload can invoke or construct
these capabilities. Concrete Android adapter must be reviewed at its construction
and lifecycle callbacks, not merely given a class named Trusted. Scope/principal
mapping and real consent UI remain missing implementation inputs.

## Minimal coordinator/policy protocol (names proposed, no invented ABI)

All operations run in one per-owner serialized admission domain; actual FFI names/
records must be released by the policy/core owner, then generated by B.

- beginReading(actualSurface, trustedSelection): register exact immutable binding,
  readonly consent and initial policy version; returns opaque live session handle.
  No stale session restoration or implicit grant issuance from saved UI state.
- observeCurrent(handle): checks current grant/display lease/source only. NEVER
  issues/rotates a grant, extends grant/absolute lease expiry, renews consent or
  performs hidden reauthorization. Native checks must honor this semantic contract.
- requestReauthorization(handle, originalAttempt, expectedSelectionSeq,
  expectedPolicyVersion, expectedPreviousGrantGeneration): dedicated EXPLICIT
  issuance operation, separate from observeCurrent. It may be scheduled by this
  trusted active-reading coordinator near a real native deadline, so normal users
  need not reopen every30s; a timer itself confers no authority. At most1 in flight.
  Fresh visibility/selection/scope/policy must pass immediately before admission.
- acceptSelection(ownerSlot, trustedSurfaceEvent, nextSelectionSeq): atomically
  advances native/Host owner admission fence, invalidates prior intent and records
  new exact binding. It is a trusted surface callback path, never caller JSON.
  Native presentation admission must reference this accepted slot/version.
- openPresentationForReading(handle, expectedSelectionSeq, expectedLifecycleEpoch,
  expectedGrantGeneration): validates exact CURRENT slot before invoking destructive
  core open, under the same native/Host serialized admission. Reject stale requests
  with ZERO core open/issue/close-current calls. Do not fall back to the unguarded raw
  open endpoint. Exact record/API requires FFI owner's release; it does not exist in466.
- Native issue transaction: verifies active policy session, nonrevoked prior chain,
  expected generation/CAS, current exact source/head, readonly consent subset and
  live owner epoch; atomically records original attempt/outcome + NEW generation/
  expiry <=native now+30s. Preserve old-generation facts in audit; never update its
  old expiry. Extract an owner-controlled transaction hook if needed; do not nest
  current issue_document_grant_trusted's transaction or issue after an unlocked bool.
- lookupReauthorization(originalAttempt): exact original outcome only, no new grant.
  An uncertain dispatch cannot be retried with a new attempt or inferred from latest
  generation. A historical committed grant may already be expired/revoked; receipt
  is not current display permission. Unknown/cleanup failure stops and holds session.
- stopReading(handle, reason): first advance terminal lifecycle/selection fence,
  suppress output and any new admission, then close only exact owned presentation/
  handles and revoke only this reading chain's current generation. Record cleanup
  success/failure. No automatic reauthorization/resume after terminal stop.

Background, logout/policy-session change, document/project/workspace switch, Binder
release/death, grant revocation, source revision change or poisoning stop the chain.
A foreground return/new selection may start a NEW explicitly confirmed reading
intent under current policy; it never revives the old stopped/revoked/poisoned chain.
Grant expiry alone is not revocation, but a new grant STILL needs the fresh atomic
policy decision; an expired/failed presentation is not proof of renewed authority.
No widened presentation TTL, blind old-grant reuse or silent head substitution.

A valid new grant then permits a separately gated SAME-source presentation handoff.
Until a real current new display lease is confirmed, don't publish/continue under
an invalid old generation. Keep intended page/zoom locally; policy success should
avoid manual reopen, not claim uninterrupted rendering without device evidence.

## Pre-call selection fence: destructive open must not affect a newer selection

Core open_presentation closes an old selection BEFORE validating new access. Host
and FFI therefore must reject stale work BEFORE that call, not merely discard its
late result. Required trace:

- Admit B selectionSeq2 in the serialized owner registry; advance fence before its
  native open. A delayed open/reauthorization for selectionSeq1 is now rejected
  WITHOUT calling core open, issuing grant, or closing B.
- Recheck binding/cancellation and enter native operation under that SAME admission
  serialization; no check-then-queue gap in which B can become active before A calls
  destructive open. Native boundary must also fence owner/sequence where async IPC
  could reorder calls. A caller-supplied high sequence isn't trusted selection.
- Output is additionally fenced by actual Activity lifecycle/selection AND per-page
  frame sequence. Discard/close only A's exact returned handle, never “close current”
  after B has opened. Old callbacks never clear a new frame, state or grant.
- On the physical Activity callback, local fence suppresses output immediately;
  Service/native stop occurs when serialized lifecycle message is received. Do not
  claim zero-latency distributed revocation or erase already-read bytes. Lost sender
  /Binder death and missing fresh visibility stop future issuance, not renew it.

## Audit and acceptance contract

Bounded local audit records: real session/surface/policy version, exact ref/source/
scope, selection/frame epochs, original attempt, old+new grant IDs/generations,
requested readonly operations, native issued/deadline, decision/reason and cleanup
outcome. Identifiers in audit are non-replayable historical metadata: never restore
principal, visibility, a live lifecycle capability or current grant authority from
the log after restart. No content, credentials or model text. Audit commit and grant issuance
must be one native transaction, not a success log after an uncertain issue. If an
old record is unknown, do not mark saved/revoked/issued or replay automatically.

Capacity/retention must be part of the fixed policy-port release, not an evicting
map: max1 issuance in flight per reader intent, no more active reader slots than
the actual native cap8, and an explicit finite durable audit bound chosen by the
policy owner. Missing bound/retention semantics block implementation. Admission and
audit capacity are checked in the same issue transaction; capacity rejects a new
grant and lets only already-valid authority run to its original deadline. Pending/
unknown originals and stopped/revoked/poisoned fences are NEVER silently evicted,
reset or inferred resolved by time/absence. Confirmed terminal outcomes are stable
for exact lookup; any compaction requires a separately specified auditable retention
rule that preserves non-replay/terminal fences. No automatic pruning in this proposal.

Required independently executable acceptance vectors AFTER real ports exist:
- >30s reading across multiple genuinely NEW grants with one exact source/page
  intent; actual30s grant cap remains, no repeated user reopen, no implicit check issue.
- check-only repeated over deadline produces expiry and ZERO reauthorization calls.
- real background/foreground, focus loss, switch/logout, scope/principal changes,
  revoked grant/changed generation/old revision/poison all stop; no automatic revive.
- A(seq1) arrives after B(seq2): ZERO native open/issue/close-current calls for A;
  delayed A response/cleanup cannot publish or clear B. Both deterministic orders
  and bounded race probes required at real Host/FFI/native boundary. Include
  A(seq1)->B(seq2)->A(seq3): equal DocumentRef alone must not accept oldseq1.
- policy revoke races issue: only atomic valid new grant or denied/unknown; never
  reactivates revoked intent. Lost receipt queries exact attempt, no duplicate issue.
- page navigation preserves exact document; old page callback cannot replace new page.
- issuer/audit/close failure, lifecycle message loss, owner death, native expiry,
  clock/deadline handling and capacity bounds fail closed without a fake allow.

Android >30s/foreground/page/principal/grant/old-response tests are currently
NOT_RUN; no actual lifecycle/policy/native coordinator is implemented by this
contract. Existing short-TTL tests and pure simulations are NOT continuous-reading
proof. Production verified remains false; no writing/external action is enabled.

## Independent design review result and delivery scope

Non-author review of source facts, impact and race contract: no Important. All three
inventory source SHA256 values independently match. Final freshness/retention addendum
also statically reviewed:2s is only a proposed review bound, never an implemented
claim. Raw evidence/reader-reauthorization-independent.log and
reader-reauthorization-contract-final-independent.log retained. git diff --check0.
No fake behavior tests were run, production source unchanged. This delivers the
requested concrete contract/blockers fallback because actual policy/lifecycle ports
are absent; it does NOT deliver an enabled or simulated-as-real coordinator.
