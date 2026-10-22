# Approved initial readonly admission — native contract addendum

The parent supplied trusted session evidence of the user's approval2026-10-22
09:23:33UTC: actual explicit selection of a registered, source-known local document
in the current project may authorize THIS readonly view without another prompt.
This fixes section6 of NATIVE-READER-POLICY-V1.md; no further user approval is needed
for this specified policy or its normal implementation. All production adapters
remain unavailable pending actual core/FFI/binding/Host integration and acceptance.
This document is proposed exact implementation guidance, not a generated API.

## Authorized trigger and scope

Only a NEW genuine user selection admitted by the existing real Activity surface,
current registered Binder/session/Service epoch/Runtime scope and exact canonical
native catalog record may create the initial reading intent. The native selected
source/ref/digest/current policy version must still match at commit. No broad scan,
account ACL, new filesystem access, credentials, editing, annotation write, external
send or background reading. Internal local authorization/outcome bookkeeping does
not mean editing document contents. Unknown source, explicit revoke or unavailable
current policy fails closed. Do not infer permission from mere registration/existence,
model/card JSON, old callback, cached title/URI/bytes, timer or an old receipt.

Host's periodic ReaderContinuationController only has check/renew conceptual ports;
it must NEVER call initial authorization to repair an expired/denied root. Normal
renewal still needs existing root/new original challenge and same visible intent.
A genuinely new/reselected reading intent may use initial admission as approved.
It does not revive the old root, old permission or old consumed native token.

## Required native initial admission (additive endpoint proposal)

reader_policy_authorize_selection({scope:DocumentReaderScope,
document:exactDocumentRef, sourceDigest, nativeSelectionId,
surfaceBinding:{surfaceId,lifecycleEpoch,selectionSequence},
originalAttemptId, expectedReadPolicyVersion}) -> InitialReadOutcome

Private trusted Service-only path. Actual Activity event is joined to actual owner
before call; none of these correlation fields is an editable JSON allow/principal.
Use native actual store/project/source, not caller workspace/epoch/policy permission.
The Host must record/accept actual selection synchronously before delayed lookup;
native validates same current opaque selection token and its real selection epoch.
Bind initial intent to native exact known source, ref, readonly minimum Render (and
Inspect only as needed), observed current read-policy version and original attempt.
No caller operation/expiry/allow bit. Recheck current persisted explicit-deny fence.

Atomically register NEW reading intent, native-generated owned initial grant and
immutable outcome; <=30s initial grant. IDs/generation/receipt are newly stored facts,
never replacements for an unknown prior operation or fabricated original identities.
Native selection token has separate one-use AUTHORIZE and OPEN phases: claiming it
for this original authorization must not require replaying begin_selection to open.
Presentation open may use the original token once only for its exact authorized
intent/access/ref. Altered payload/new attempt on same authorized event rejects;
identical duplicate returns original historical outcome without fresh expiry or new
grant. A new genuine selection is needed for a new initial intent. Stale selection
must fail BEFORE any destructive open of another currently selected document.

Output schema1/status=authorized, readingIntentId, exact original bindings,
readPolicyVersion, actual DocumentAccessRequest, exact source identity/digest,
expiresAtMs/native issuedAtMs, ownedInitialGrant=true and outcomeId. These are REAL
native fields, not Host guesses. Source identity comes from real native registration/
metadata; any proposed wire sourceId must correspond to that actual store fact.
On pending/unknown retain originalAttemptId, never authorize again automatically.
Explicit original reconcile must support kind=initial_authorize and recover exact
historical outcome even if reply lost before readingIntentId was returned. Historical
receipt alone neither reopens bytes nor proves the selection/permission still live.

After actual initial presentation open, existing policy B attaches its real native
ticket to this exact initial readingIntentId/selection epoch. B must verify actual
owned-initial-grant record rather than trusting wire ownedInitialGrant=true. Existing
valid EXTERNAL parent-grant path remains separate and cannot infer exclusive grant
ownership. D's owned child-chain renewal/G ticket handoff rules still apply.

Before a root exists, stop/selection-replacement/reconcile must still fence the
readingIntentId OR exact original initial-authorize attempt under its retained owner.
Stop must not require a rootId that caller never received or that is not created yet.
Reconcile may fence unperformed authorization/open; do not replay it. New selection B
fences ALL old A pending authorization/open/continuation tokens before destructive
calls. Unknown original intent and cleanup are retained, never marked not_committed
merely because a current lookup failed. API names/records must be fixed by FFI owner
before Kotlin calls are implemented; no guessed generated methods are introduced.

## Lifecycle stop is NOT persistent document revocation

Lifecycle/window/route/scope/selection stop terminally closes original reading
intent/root and its OWNED initial/child grants; it does not permanently deny that
document. Source-known new genuine selection may create a NEW authorized intent.
For external shared parent grant, stop closes only own tickets/children, preserving
unrelated parent access. Native record must distinguish genuine initial-owned vs
external parent; caller cannot assert that ownership. Background return alone never
counts as a new user selection or permits auto-authorize.

Explicit user/policy revocation of DOCUMENT READ is different: persistent native
read-policy deny/version fence, independent of grant IDs/root lifecycle/Service epoch.
At minimum key it by actual stable local workspace/project/document identity across
its revisions; apply actual source-registration alias fences if such aliases represent
the same revoked source in the existing store. Derive alias identity from native
registration, never checksum alone or UI claims. Do not invent a global disk-file ban
from a per-document product policy. Native owner must fix the canonical revocation
resource boundary explicitly; no fresh grant ID or epoch erases the existing deny.
Do NOT retrospectively classify every inactive/expired legacy grant as permanent
user document revocation: inactive child grants can be ordinary lifecycle cleanup.
Unknown legacy reason is not a permission proof or new deny fact; fail availability
where reason is necessary, and record NEW actual explicit policy actions distinctly.

Required same-transaction explicit policy revoke path (new endpoint or existing
trusted revoke hook owned by core): set persistent read-policy deny + next version;
fence all matching initial intents/roots/prepared attempts/current grants, collect
exact ticket invalidations. No automatic un-revoke endpoint/fallback is authorized.
Fresh authorize observes CURRENT deny/version, so changing grantId/rootId/session/
document revision cannot bypass revoke. Initial admission vs revoke ordering: revoke
first denies authorize; authorize first is fenced by revoke before future use/open.
All exact-current-grant revocation hooks from v1 still fence derived roots. A grant-
level revocation remains scoped to that fact; don't silently relabel it as a permanent
document ban or expand an old-generation callback into revoke-current.

## Mandatory additional tests and current integration boundary

Synthetic native tests: true fresh selection authorized once; duplicate/altered
attempt; old selection after B; model/timer/background no issuer path; source unknown/
changed/current-project invalid; stop owned intent then NEW real reselection succeeds;
background return alone denied; persistent document deny blocks NEW grant ID/root/
Service epoch/revision; authorize-vs-revoke both transaction orders; initial grant
owned vs shared external parent stop behavior; before-root lost reply/pending stop;
unknown initial reconcile/fence; capacity and schema corruption failclosed.

Host pure controller tests are NOT these native tests. Existing production backend
is still null, Activity challenge sampler/catalog/actual typed IPC/owned-resource
ledger/first authorization adapter are not connected. Actual initial read, PFD,
policy/native path, Android and >30s uninterrupted device behavior remain NOT_RUN.
No default verified gate changes from receiving policy approval or from fake tests.
