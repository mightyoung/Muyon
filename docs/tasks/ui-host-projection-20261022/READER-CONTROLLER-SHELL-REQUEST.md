# Existing Activity challenge sampler request / Host controller checkpoint

Consume exact Shellc0c2dc994df099c36c83813adf8410dac999d943; ordinary dependency
mergeacb0fa21 (full merge SHA in controller report). Two conflicts restored EXACT
Shell-owner files, not redesigned: HostPersistenceProjectionChecks.kt and Shell
HANDOFF.md. Upstream raw reader-surface-android.log has original trailing whitespace;
it is preserved as evidence. No handwritten MainActivity/ChatScreen/UI edits.

Host new ReaderContinuationController uses existing public ReaderSurfaceRequest /
ReaderVisibilityObservation; no duplicate physical-state model or UI lifecycle.
Production native backend remains null. Service private factory supplies actual
elapsedRealtime clock + worker Handler and real original scope/source checks.
This is not yet a bound IPC client or installed Activity host.

## Exact request to the original Shell owner

Implement the existing conceptual Host interface in owned Activity/Fence files:

```kotlin
internal fun interface ReaderActivityChallengeSampler {
    fun sample(original: ReaderSurfaceRequest, nativeChallengeId: String,
        receive: (ReaderVisibilityObservation?) -> Unit)
}
```

Use ActivityReaderSurface's ALREADY actual owning-main Handler and existing fence.
Post to actual owner thread; sample lifecycle/window/decor/focus/current route/
project through its existing source. The fence should expose a bounded internal
`sampleForContinuation(original)` returning a NEW existing ReaderVisibilityObservation
only if original current frame/request object, same selection/lifecycle/scope and
active reading intent still match after refreshPhysical. Null on destroy/background/
window/project/route/frame/selection change, unsupported modes or uncertain state.
Do not call dispatch/open/acceptSelection, increment selection sequence, or create a
new user selection just to get an observation. Static same-page refresh needs no new
click. New page has its own current frame request; old challenge returns null.

Native challenge ID is correlation, not permission or a replacement visibility fact.
Host ties that genuine native ID to original request/attempt and consumes once;
Host additionally requires one-use observationId, timestamp >= start of this sample
request and <=2s old on same actual elapsedRealtime clock. Native separately enforces
its own challenge deadline. Activity MUST actually sample now, not reuse the old
selection/open observation even if it is within2s. No boolean allow/visible/principal
from JSON and no credential/account payload. Return via original callback, retaining
original request identity; do not substitute current request on a delayed callback.

The current sampler is an interface seam with NO production default implementation.
Do not install fake Activity in production. Existing host=null/catalog-unavailable
remains until genuine Binder/scope/catalog/policy/resource joins are implemented.
Host controller is backend-null and refuses admit; its private Service factory is
not a final cross-process ABI. Owner must coordinate actual typed transport before
wiring this sampler across the existing separate Service process.

## Native backend requirements while exact generated seven policy methods arrive

ReaderContinuationBackend is a Host CONCEPTUAL port, not a guessed generated API.
The real adapter must be NONBLOCKING on controller Handler. Run synchronous FFI on a
bounded separate native worker under the shared native batch domain; returning to
controller must not prevent its timeout/lifecycle work. Controller deadlines do not
claim safety if its actual Android owner queue is blocked. Real renderer has its
own actual lifecycle/current-frame publication checks, not a Service boolean.

Backend check supplies real original frame + native valid_for/check_after anchored
to REQUEST START. check cannot extend old native deadline. renew performs original
native prepare, requests the NEW Activity sample for that native challenge, then
actual renew+G genuine presentation handoff and invalidation drain in shared batch.
Known old-frame terminal notification clears predecessor, not new root/frame. No
mock allow, frame arithmetic, replayed consumed selection token, copied bytes as
lease, or root grant receipt as PFD proof. Unknown returns exact originalAttemptId;
late unknown remains historical/queryable even after display expiration, never
revives old frame or changes a newer frame's status.

Controller requires exact callbacks: clearExact(frame), publishReplacement(frame),
disposeLateExact(frame), stopOriginalAdministrative(frame). Final publication must
post to actual Activity owner and resample existing fence/current native frame before
showing. Resource callbacks must use actual one-shot owned-resource ledger (Shell
ReaderSurfaceResource), not close-current or new wrapper per duplicate reply. Scope
loss invokes retained-original-owner administration, NOT a live principal/business
permit. Real policy backend/ledger/PFD/native controller integration remain pending.

NativeReaderPresentationPort now has separate administrative closeExact and admin
drain using generated methods, plus releaseDisconnectedClient. The latter is ONLY
actual session/Binder release; retained owner checks original actual client UUID no
longer exists in Service clients. A live client's A->B/page switch cannot invoke it.
Per-reading stop/reconcile must use exact root/frame under the incoming seven-method
policy API; don't substitute broad reader release. Service releaseClient currently
holds Service monitor: schedule administration AFTER exiting it to preserve existing
domain->Service lock order. This note is mandatory for later actual release wiring.
